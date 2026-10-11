#!/usr/bin/env bash
# Opt-in installer (make tools): downloads pinned versions of kind, kubectl,
# helm and terraform into the project-local .bin/ directory, verifying each
# download against the SHA-256 checksum published by the project itself.
# No sudo and no system changes. Docker is not installed (system-level).
set -euo pipefail

# Versions the project is tested with. Newer releases also work
# (Terraform >= 1.5, kind >= 0.24, Helm 3+); 1.5.7 is the last MPL release.
KIND_VERSION=v0.31.0
KUBECTL_VERSION=v1.33.4
HELM_VERSION=v3.22.0
TERRAFORM_VERSION=1.5.7

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/.bin"

os=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$(uname -m)" in
  x86_64 | amd64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
case "$os" in
  linux | darwin) ;;
  *) echo "unsupported OS: $os (use WSL2 on Windows)" >&2; exit 1 ;;
esac

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# verify <file> <expected sha256>
verify() {
  local actual
  actual=$(sha256 "$1")
  if [ -z "$2" ] || [ "$actual" != "$2" ]; then
    echo "  checksum MISMATCH for $(basename "$1")" >&2
    echo "    expected: ${2:-<not found in checksum file>}" >&2
    echo "    actual:   $actual" >&2
    exit 1
  fi
  echo "  sha256 ok  $actual"
}

fetch() { curl -fsSL --retry 3 -o "$2" "$1"; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$BIN"

echo "==> kind $KIND_VERSION ($os/$arch)"
url="https://github.com/kubernetes-sigs/kind/releases/download/$KIND_VERSION/kind-$os-$arch"
fetch "$url" "$tmp/kind"
verify "$tmp/kind" "$(curl -fsSL "$url.sha256sum" | awk '{print $1}')"
install -m 0755 "$tmp/kind" "$BIN/kind"

echo "==> kubectl $KUBECTL_VERSION ($os/$arch)"
url="https://dl.k8s.io/release/$KUBECTL_VERSION/bin/$os/$arch/kubectl"
fetch "$url" "$tmp/kubectl"
verify "$tmp/kubectl" "$(curl -fsSL "$url.sha256" | awk '{print $1}')"
install -m 0755 "$tmp/kubectl" "$BIN/kubectl"

echo "==> helm $HELM_VERSION ($os/$arch)"
file="helm-$HELM_VERSION-$os-$arch.tar.gz"
fetch "https://get.helm.sh/$file" "$tmp/$file"
verify "$tmp/$file" "$(curl -fsSL "https://get.helm.sh/$file.sha256sum" | awk '{print $1}')"
tar -xzf "$tmp/$file" -C "$tmp"
install -m 0755 "$tmp/$os-$arch/helm" "$BIN/helm"

echo "==> terraform $TERRAFORM_VERSION ($os/$arch)"
file="terraform_${TERRAFORM_VERSION}_${os}_${arch}.zip"
base="https://releases.hashicorp.com/terraform/$TERRAFORM_VERSION"
fetch "$base/$file" "$tmp/$file"
verify "$tmp/$file" "$(curl -fsSL "$base/terraform_${TERRAFORM_VERSION}_SHA256SUMS" | awk -v f="$file" '$2 == f {print $1}')"
python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extract("terraform", sys.argv[2])' "$tmp/$file" "$tmp"
install -m 0755 "$tmp/terraform" "$BIN/terraform"

echo
echo "Installed into $BIN (the Makefile puts it first in PATH)."
echo "Docker is not installed by this script; see 'make preflight' for instructions."
