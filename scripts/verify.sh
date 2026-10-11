#!/usr/bin/env bash
# End-to-end checks of the running platform: cluster, app, metrics, logs,
# traces, mesh security, network policies and RBAC.
set -uo pipefail

cd "$(dirname "$0")/../terraform"

url() { terraform output -json urls | python3 -c "import json,sys; print(json.load(sys.stdin)['$1'])"; }

CTX=$(terraform output -raw kubeconfig_context)
APP=$(url application)
GRAFANA=$(url grafana)
PROMETHEUS=$(url prometheus)
ALERTMANAGER=$(url alertmanager)
ARGOCD=$(url argocd)
GRAFANA_AUTH="admin:$(terraform output -raw grafana_admin_password)"
K="kubectl --context $CTX"

failures=0
check() {
  local description=$1
  shift
  if "$@" >/dev/null 2>&1; then
    printf '  \033[32mPASS\033[0m %s\n' "$description"
  else
    printf '  \033[31mFAIL\033[0m %s\n' "$description"
    failures=$((failures + 1))
  fi
}

# Returns success when the PromQL query has a value greater than zero.
prom_positive() {
  curl -sf "$PROMETHEUS/api/v1/query" --data-urlencode "query=$1" |
    python3 -c "import json,sys; r=json.load(sys.stdin)['data']['result']; sys.exit(0 if r and float(r[0]['value'][1]) > 0 else 1)"
}

echo "Cluster"
check "3 nodes Ready (1 control plane + 2 workers)" \
  bash -c "[ \$($K get nodes --no-headers | grep -c ' Ready') -eq 3 ]"
check "No pod in Pending/Failed state" \
  bash -c "! $K get pods -A --no-headers | grep -Ev 'Running|Completed'"
check "PersistentVolumeClaims bound" \
  bash -c "[ \$($K get pvc -A --no-headers | grep -vc Bound) -eq 0 ]"

echo "Application"
check "Ingress gateway -> frontend -> orders -> inventory" \
  bash -c "curl -sf --retry 5 --retry-all-errors $APP/ | grep -q inventory"
check "HPAs are reading CPU metrics" \
  bash -c "! $K -n sample-app get hpa --no-headers | grep -q unknown"

echo "Ingress"
check "Grafana published at $GRAFANA" bash -c "curl -sf $GRAFANA/api/health | grep -q ok"
check "Prometheus published at $PROMETHEUS" curl -sf "$PROMETHEUS/-/ready"
check "Alertmanager published at $ALERTMANAGER" curl -sf "$ALERTMANAGER/-/ready"
check "Argo CD published at $ARGOCD" curl -sf "$ARGOCD/healthz"

echo "GitOps"
check "Argo CD application Synced and Healthy" bash -c \
  "[ \"\$($K -n argocd get applications.argoproj.io sample-app -o jsonpath='{.status.sync.status}/{.status.health.status}')\" = Synced/Healthy ]"
check "Workloads run the image published by the CD pipeline" bash -c \
  "$K -n sample-app get deploy -o jsonpath='{..image}' | grep -q ghcr.io/"

echo "Metrics"
check "Application metrics scraped" prom_positive 'sum(rate(http_server_requests_total{namespace="sample-app"}[5m]))'
check "Envoy (Istio) metrics scraped" prom_positive 'sum(rate(istio_requests_total[5m]))'
check "Control plane metrics scraped (etcd, scheduler, controller-manager)" \
  prom_positive 'count(up{job=~"kube-etcd|kube-scheduler|kube-controller-manager"} == 1) == 3'
check "SLO recording rules evaluated" prom_positive 'count(app:sli_errors:ratio_rate5m)'
check "Tempo service graph metrics remote-written" prom_positive 'sum(traces_service_graph_request_total)'

echo "Logs"
check "Application logs in Loki" bash -c \
  "curl -sf -u $GRAFANA_AUTH -G '$GRAFANA/api/datasources/proxy/uid/loki/loki/api/v1/query_range' \
    --data-urlencode 'query={namespace=\"sample-app\", container=\"app\"}' --data-urlencode limit=1 |
    python3 -c \"import json,sys; sys.exit(0 if json.load(sys.stdin)['data']['result'] else 1)\""

check "Control plane logs in Loki (kube-system)" bash -c \
  "curl -sf -u $GRAFANA_AUTH -G '$GRAFANA/api/datasources/proxy/uid/loki/loki/api/v1/query' \
    --data-urlencode 'query=sum(count_over_time({namespace=\"kube-system\", node=~\".*control-plane\"}[15m]))' |
    python3 -c \"import json,sys; r=json.load(sys.stdin)['data']['result']; sys.exit(0 if r and float(r[0]['value'][1]) > 0 else 1)\""
check "Log agent runs without root and without capabilities" bash -c \
  "for p in \$($K -n monitoring get pods -l app.kubernetes.io/name=alloy -o name); do
     [ \"\$($K -n monitoring exec \$p -c alloy -- id -u)\" != 0 ] &&
     $K -n monitoring exec \$p -c alloy -- grep -q 'CapEff:.0000000000000000' /proc/1/status || exit 1
   done"

echo "Traces"
check "Traces for frontend in Tempo" bash -c \
  "curl -sf -u $GRAFANA_AUTH -G '$GRAFANA/api/datasources/proxy/uid/tempo/api/search' \
    --data-urlencode 'q={resource.service.name=\"frontend\"}' --data-urlencode limit=1 |
    python3 -c \"import json,sys; sys.exit(0 if json.load(sys.stdin).get('traces') else 1)\""

check "TraceQL metrics (Grafana Traces Drilldown)" bash -c \
  "curl -sf -u $GRAFANA_AUTH -G '$GRAFANA/api/datasources/proxy/uid/tempo/api/metrics/query_range' \
    --data-urlencode 'q={nestedSetParent<0} | rate() by(resource.service.name)' \
    --data-urlencode start=\$(( \$(date +%s) - 300 )) --data-urlencode end=\$(date +%s) --data-urlencode step=60s |
    python3 -c \"import json,sys; sys.exit(0 if json.load(sys.stdin).get('series') else 1)\""

echo "Alerting"
check "Watchdog alert reaching Alertmanager" bash -c \
  "curl -sf '$ALERTMANAGER/api/v2/alerts?filter=alertname%3D%22Watchdog%22' | grep -q Watchdog"

echo "Security"
check "Service-to-service traffic uses mutual TLS" \
  prom_positive 'sum(rate(istio_requests_total{reporter="destination", connection_security_policy="mutual_tls"}[5m]))'
check "NetworkPolicy blocks inventory -> frontend" bash -c \
  "! $K -n sample-app exec deploy/inventory-v1 -c app -- python -c \
    \"import httpx; httpx.get('http://frontend:8080/', timeout=3).raise_for_status()\""
check "Mesh-wide PeerAuthentication is STRICT" bash -c \
  "[ \"\$($K -n istio-system get peerauthentication default -o jsonpath='{.spec.mtls.mode}')\" = STRICT ]"
check "RBAC: developers can scale deployments" \
  $K auth can-i patch deployments.apps --subresource=scale -n sample-app --as=jane --as-group=sample-app-developers
check "RBAC: developers cannot read secrets" bash -c \
  "! $K auth can-i get secrets -n sample-app --as=jane --as-group=sample-app-developers"

echo
if [ "$failures" -eq 0 ]; then
  echo "All checks passed."
else
  echo "$failures check(s) failed."
  exit 1
fi
