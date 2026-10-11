#!/usr/bin/env bash
# Diagnoses the local prerequisites of `make up`. It never installs anything:
# it reports every problem at once, with the command to fix each one.
set -uo pipefail

failures=0
warnings=0

ok()      { printf '  \033[32m%-8s\033[0m %-15s %s\n' "OK" "$1" "$2"; }
warn()    { printf '  \033[33m%-8s\033[0m %-15s %s\n' "WARN" "$1" "$2"; warnings=$((warnings + 1)); }
fail()    { printf '  \033[31m%-8s\033[0m %-15s %s\n' "$1" "$2" "$3"; failures=$((failures + 1)); }
hint()    { printf '  %-8s %-15s \033[2m%s\033[0m\n' "" "" "$1"; }

# version_ge <found> <minimum>
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

# check_tool <name> <minimum or -> <version command> <install hints...>
check_tool() {
  local name=$1 minimum=$2 version_cmd=$3
  shift 3
  if ! command -v "$name" >/dev/null 2>&1; then
    fail "MISSING" "$name" "$([ "$minimum" != - ] && echo ">= $minimum")"
    for h in "$@"; do hint "$h"; done
    return
  fi
  local version
  version=$(eval "$version_cmd" 2>/dev/null | head -1)
  if [ "$minimum" != - ] && [ -n "$version" ] && ! version_ge "$version" "$minimum"; then
    fail "OLD" "$name" "$version (needs >= $minimum)"
    for h in "$@"; do hint "$h"; done
    return
  fi
  ok "$name" "${version:-found}"
}

echo "Tools"
check_tool docker - "docker version --format '{{.Client.Version}}'" \
  "Linux: https://docs.docker.com/engine/install/ (Docker Engine)" \
  "macOS / Windows (WSL2): Docker Desktop, with WSL integration enabled for this distro"
check_tool kind 0.24.0 "kind version | sed -E 's/^kind v([0-9.]+).*/\1/'" \
  "make tools   (pinned, checksum-verified, into .bin/, no sudo)" \
  "or https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
check_tool terraform 1.5.0 "terraform version -json | sed -n 's/.*\"terraform_version\": *\"\([0-9.]*\)\".*/\1/p'" \
  "make tools   (pinned, checksum-verified, into .bin/, no sudo)" \
  "or https://developer.hashicorp.com/terraform/install"
check_tool kubectl - "kubectl version --client -o json | sed -n 's/.*\"gitVersion\": *\"v\([0-9.]*\)\".*/\1/p'" \
  "make tools   (pinned, checksum-verified, into .bin/, no sudo)" \
  "or https://kubernetes.io/docs/tasks/tools/"
check_tool helm 3.0.0 "helm version --short | sed -E 's/^v([0-9.]+).*/\1/'" \
  "make tools   (pinned, checksum-verified, into .bin/, no sudo)" \
  "or https://helm.sh/docs/intro/install/"
check_tool curl - "curl --version | awk '{print \$2}'" \
  "Debian/Ubuntu: sudo apt-get install -y curl   |   macOS: brew install curl"
check_tool python3 3.8.0 "python3 --version | awk '{print \$2}'" \
  "Debian/Ubuntu: sudo apt-get install -y python3   |   macOS: brew install python"

echo "Environment"
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  ok "docker daemon" "reachable"
  if docker compose version >/dev/null 2>&1; then
    ok "docker compose" "$(docker compose version --short 2>/dev/null)"
  else
    fail "MISSING" "docker compose" "plugin not found"
    hint "https://docs.docker.com/compose/install/linux/"
  fi
  mem_bytes=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
  mem_gib=$(( ${mem_bytes:-0} / 1024 / 1024 / 1024 ))
  if [ "$mem_gib" -ge 8 ]; then
    ok "memory" "${mem_gib} GiB available to Docker"
  else
    warn "memory" "${mem_gib} GiB available to Docker (the full stack uses ~6.5 GiB; 8 GiB recommended)"
    hint "Docker Desktop: Settings > Resources > Memory   |   WSL2: memory= in %UserProfile%\\.wslconfig"
  fi
else
  fail "FAIL" "docker daemon" "not reachable (is Docker running? can this user run docker?)"
  hint "Linux: sudo systemctl start docker && sudo usermod -aG docker \$USER (then log in again)"
  hint "Docker Desktop: start it; on WSL2 enable Settings > Resources > WSL integration"
fi

# Ports already held by this project (kind node or state backend) are fine:
# preflight must also pass on an environment that is already running.
project_port_owner() {
  command -v docker >/dev/null 2>&1 || return 1
  # Ports look like "127.0.0.1:80->30080/tcp" or ranges "127.0.0.1:7070-7071->7070-7071/tcp".
  docker ps --format '{{.Names}}|{{.Ports}}' 2>/dev/null | awk -F'|' -v port="$1" '
    $1 ~ /-control-plane$/ || $1 ~ /^tfstate-/ {
      n = split($2, maps, ", ")
      for (i = 1; i <= n; i++) {
        host = maps[i]; sub(/->.*/, "", host); sub(/.*:/, "", host)
        split(host, r, "-"); lo = r[1]; hi = (r[2] == "" ? r[1] : r[2])
        if (port + 0 >= lo + 0 && port + 0 <= hi + 0) { print $1; exit }
      }
    }'
}
for port in 80 7070 7071; do
  if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
    owner=$(project_port_owner "$port")
    if [ -n "$owner" ]; then
      ok "port $port" "in use by this project ($owner)"
    else
      fail "BUSY" "port $port" "already in use by another process"
      hint "free it, or change the port (ingress_host_port in terraform.tfvars / bootstrap/docker-compose.yml)"
    fi
  else
    ok "port $port" "free"
  fi
done

if [ "$(uname)" = Linux ]; then
  instances=$(sysctl -n fs.inotify.max_user_instances 2>/dev/null || echo 0)
  watches=$(sysctl -n fs.inotify.max_user_watches 2>/dev/null || echo 0)
  if [ "$instances" -ge 512 ] && [ "$watches" -ge 524288 ]; then
    ok "inotify" "instances=$instances watches=$watches"
  else
    fail "LOW" "inotify" "instances=$instances watches=$watches (kind workers fail to join)"
    hint "sudo sysctl -w fs.inotify.max_user_watches=524288 fs.inotify.max_user_instances=512"
  fi
fi

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures problem(s) found. Fix them and run 'make preflight' again."
  exit 1
fi
if [ "$warnings" -gt 0 ]; then
  echo "All prerequisites met ($warnings warning(s))."
else
  echo "All prerequisites met."
fi
