# Decisões de design e trade-offs

Cada decisão segue o formato: **contexto → decisão → trade-off**.

## 1. kind como cluster local

**Contexto.** O desafio exige um cluster local com 1 control plane e 2 workers, provisionado por Terraform.

**Decisão.** kind, via provider `tehcyx/kind`.

- O cluster é um recurso Terraform de verdade (`kind_cluster`), com plan/apply/destroy, e devolve endpoint e certificados usados pelos providers `helm` e `kubernetes` no mesmo `apply`.
- Roda Kubernetes upstream (kubeadm): etcd, scheduler, controller-manager e kube-proxy existem como em produção e são monitorados pelo Prometheus.
- Multi-nó declarativo; é a ferramenta usada no CI do próprio Kubernetes.
- O CNI padrão (kindnet) implementa NetworkPolicy e o local-path-provisioner já entrega PersistentVolumes dinâmicos.

**Alternativas.** minikube (provider Terraform pouco mantido, multi-nó menos estável), k3s (exige VMs; distribuição modificada, sem etcd por padrão) e k3d (bom, mas provider menos difundido e não é upstream).

**Trade-offs.** Não há LoadBalancer nativo (uso NodePort + `extraPortMappings`); imagens locais precisam de `kind load`; os nós compartilham o kernel do host, o que exige aumentar os limites de `inotify` (o `make preflight` detecta).

## 2. Remote state em S3 local (Versity S3 Gateway)

**Contexto.** Remote state em uma solução S3-compatível local.

**Decisão.** Versity S3 Gateway em Docker Compose (`bootstrap/`), fora do cluster, com versionamento habilitado no bucket.

- O state precisa sobreviver ao cluster; por isso o backend não roda dentro do kind.
- Versity é Apache-2.0, um único binário que expõe um diretório como S3. As imagens públicas do MinIO deixaram de ser distribuídas, e o SeaweedFS 4.x exige configuração de IAM/STS desproporcional para este uso.
- O backend é declarado vazio (`backend "s3" {}`) e configurado por ambiente em `environments/<env>/backend.hcl` (partial configuration).

**Trade-offs.** Sem state locking (single user local). Em ambiente compartilhado: S3 com `use_lockfile` (Terraform ≥ 1.10) ou DynamoDB. As credenciais do backend são locais, vinculadas a `127.0.0.1`, e podem ser sobrescritas por `TFSTATE_ACCESS_KEY`/`TFSTATE_SECRET_KEY`.

## 3. Organização do Terraform

Um root module enxuto que compõe quatro módulos com interfaces explícitas:

```
cluster ──► observability ──► service_mesh ──► sample_app
```

- **Dependências reais, não ordem manual.** O mesh precisa dos CRDs do Prometheus Operator (PodMonitor) e do endpoint do Tempo; a app precisa da injeção de sidecar e dos CRDs do Istio.
- **Recursos baseados em CRD ficam em charts Helm locais** (`modules/*/chart`). `kubernetes_manifest` exige que o CRD exista no momento do *plan*, o que quebraria o "um comando só" em um cluster que ainda não existe.
- **Versões fixadas** de providers e charts em `terraform.tfvars`, para builds reproduzíveis.
- **Ambientes** em `environments/<env>/` (tfvars + backend). `make up ENV=<env>` seleciona o ambiente.

## 4. Stack de observabilidade

| Sinal    | Coleta                                   | Backend    |
|----------|------------------------------------------|------------|
| Métricas | ServiceMonitor/PodMonitor (Prom Operator)| Prometheus |
| Logs     | Grafana Alloy (DaemonSet)                | Loki       |
| Traces   | OTLP direto da app + Envoy (Istio)       | Tempo      |

- **kube-prometheus-stack** entrega Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics e regras padrão da comunidade.
- **Alloy** em vez de Promtail (em fim de vida). Lê logs pela API do Kubernetes, só dos pods do próprio nó, sem montar `hostPath`.
- **Loki e Tempo em modo single binary com filesystem + PVC.** O modo distribuído com object storage é o caminho para produção, mas multiplicaria os pods sem agregar valor localmente.
- **Correlação entre os três sinais:**
  - métrica → trace: *exemplars* no histograma de latência;
  - log → trace: `trace_id` no log JSON + derived field no datasource Loki;
  - trace → log/métrica: `tracesToLogsV2` e `tracesToMetrics` no datasource Tempo;
  - service graph: o metrics-generator do Tempo envia métricas de spans ao Prometheus via remote write.

## 5. Aplicação de exemplo

Uma imagem, três serviços (`frontend → orders → inventory`), papel definido por variáveis de ambiente. Simplifica o build sem perder o que importa: chamadas encadeadas reais, propagação de contexto W3C, latência e falhas configuráveis.

- Instrumentação explícita (OpenTelemetry SDK + prometheus_client) em vez de auto-instrumentação, para ficar claro de onde vem cada sinal.
- A tag da imagem é o hash do código: mudou o código, muda a tag e o Deployment faz rolling update.
- `inventory` falha 2% das requisições de propósito, o que alimenta SLOs, retries e circuit breaker com dados reais.
- Um `loadgen` gera tráfego constante, para que os dashboards nunca fiquem vazios.

## 6. Service mesh: Istio (sidecar)

- **Istio em vez de Linkerd**: VirtualService/DestinationRule cobrem canary, retries e circuit breaking de forma declarativa, e o Telemetry API envia traces direto ao Tempo via OpenTelemetry.
- **Modo sidecar em vez de ambient**: o ambient exige waypoints para L7 (retries, canary), mais peças para explicar.
- **mTLS STRICT mesh-wide** via `PeerAuthentication` no namespace raiz.
- **Prometheus fica fora do mesh**: a porta de métricas da app (9464) é excluída da interceptação do sidecar (`excludeInboundPorts`) e a porta de stats do Envoy (15090) não passa por mTLS. O tráfego de negócio continua 100% mTLS e o scrape continua simples. A alternativa (metrics merging do Istio) acopla o scrape ao sidecar.
- **Retries em uma única camada** (orders → inventory). Retry em todas as camadas multiplica a carga em cascata (3 × 3 × 3) durante incidentes.

## 7. Segurança

- **NetworkPolicy default-deny** no namespace da app, com allow explícito por chamador: gateway/loadgen → frontend → orders → inventory, e monitoring → portas de métricas.
- **RBAC de menor privilégio**: o grupo `sample-app-developers` lê workloads e logs e pode escalar Deployments, mas não lê Secrets nem altera políticas.
- **Secrets**: a senha do Grafana é gerada pelo Terraform (`random_password`) e entregue via Secret do Kubernetes (`existingSecret`), sem valor fixo no código. Em produção: External Secrets + Vault/Secrets Manager, ou Sealed Secrets para GitOps.
- **Pods endurecidos**: non-root, `readOnlyRootFilesystem`, `drop: ALL`, seccomp `RuntimeDefault`, sem token de ServiceAccount montado.

## 8. Alta disponibilidade e resiliência

- **Requests/limits** em todos os workloads, inclusive charts de terceiros e sidecars.
- **HPA** em todos os Deployments da app, usando `ContainerResource` (só o container `app`), para que a CPU do sidecar não distorça a decisão.
- **PDB** para os serviços da app, istiod (2 réplicas) e ingress gateway (2+ réplicas).
- **topologySpreadConstraints** entre os workers, que têm labels de zona (`zone-0`, `zone-1`) para simular multi-AZ.
- **Backends de observabilidade com 1 réplica**: PDB não faz sentido com uma réplica e o modo HA exigiria object storage. Trade-off consciente para ambiente local.

## 9. SLOs e alertas

- **SLIs** a partir das métricas da aplicação: disponibilidade (não-5xx) e latência (< 500 ms).
- **SLOs**: 99,5% de disponibilidade e 99% das requisições abaixo de 500 ms, janela de 30 dias.
- **Alertas multi-window, multi-burn-rate** (SRE Workbook): 14,4x em 1h/5m (crítico) e 6x em 6h/30m (warning). Pegam incidentes rápidos sem alertar por ruído.
- **Alertmanager** envia para um webhook local (`alert-sink`) que registra cada notificação no Loki. Trocar por Slack/PagerDuty é só mudar o receiver.
- `make chaos` eleva a taxa de erro do inventory para 50% via Terraform (sem drift) e dispara os alertas; `make chaos-off` restaura.

## 10. Custo

O dashboard "Cluster Health & Cost" estima custo mensal a partir dos **requests** dos pods em execução (o que se paga numa cloud), por namespace, com preço por vCPU-hora e GiB-hora configurável. Também mostra o **custo ocioso** (requested − used) e a eficiência de CPU/memória, que são os alvos de right-sizing. Para custo real em cloud: OpenCost/Kubecost com preços da API do provedor.
