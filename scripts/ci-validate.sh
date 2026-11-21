
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SENTRY_VERSION="36.1.0"
OPERATOR_VERSION="0.26.3"
K8S_VERSION="1.37.0"

CACHE_DIR=".cache/helm"

mkdir -p "$CACHE_DIR"

echo "==> Checking required tools"

for tool in helm kubeconform git bash; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: $tool is not installed" >&2
    exit 1
  fi
done

echo "==> Checking Bash scripts"

for script in scripts/*.sh; do
  bash -n "$script"
done

echo "==> Preparing Helm repositories"

helm repo add sentry \
  https://sentry-kubernetes.github.io/charts \
  --force-update

helm repo add altinity \
  https://helm.altinity.com \
  --force-update

helm repo update sentry altinity

echo "==> Downloading pinned Helm charts"

helm pull sentry/sentry \
  --version "$SENTRY_VERSION" \
  --destination "$CACHE_DIR"

helm pull altinity/altinity-clickhouse-operator \
  --version "$OPERATOR_VERSION" \
  --destination "$CACHE_DIR"

SENTRY_CHART="$CACHE_DIR/sentry-${SENTRY_VERSION}.tgz"
OPERATOR_CHART="$CACHE_DIR/altinity-clickhouse-operator-${OPERATOR_VERSION}.tgz"

echo "==> Helm lint: Sentry"

helm lint "$SENTRY_CHART" \
  -f helm/values/sentry-lab.yaml \
  --strict

echo "==> Helm lint: Altinity Operator"

helm lint "$OPERATOR_CHART" \
  -f infra/clickhouse/operator-values.yaml \
  --strict

echo "==> Rendering Helm templates"

helm template ioka-sentry "$SENTRY_CHART" \
  --namespace sentry \
  --values helm/values/sentry-lab.yaml \
  > "$CACHE_DIR/sentry-rendered.yaml"

helm template clickhouse-operator "$OPERATOR_CHART" \
  --namespace clickhouse-operator \
  --values infra/clickhouse/operator-values.yaml \
  > "$CACHE_DIR/operator-rendered.yaml"

echo "==> Validating standard Kubernetes resources"

kubeconform \
  -strict \
  -summary \
  -kubernetes-version "$K8S_VERSION" \
  "$CACHE_DIR/sentry-rendered.yaml" \
  "$CACHE_DIR/operator-rendered.yaml" \
  infra/networking/clickhouse-ingress.yaml \
  infra/storage/pvc-smoke.yaml

echo "==> Validation completed successfully"

