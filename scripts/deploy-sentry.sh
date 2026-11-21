
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

if [[ $# -ne 1 ]]; then
  fail "Usage: $0 --plan | --apply"
fi

MODE="$1"

case "$MODE" in
  --plan|--apply) ;;
  *) fail "Unknown mode: $MODE" ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

KCTX="${KCTX:-ioka-lab}"
NAMESPACE="${NAMESPACE:-sentry}"
RELEASE="${RELEASE:-ioka-sentry}"
CHI_NAME="${CHI_NAME:-sentry-clickhouse}"

CHART="".cache/helm/sentry-36.1.0.tgz""
VALUES="helm/values/sentry-lab.yaml"
CHI_MANIFEST="infra/clickhouse/clickhouse-installation.yaml"
NETWORK_POLICY="infra/networking/clickhouse-ingress.yaml"

for tool in kubectl helm grep; do
  command -v "$tool" >/dev/null ||
    fail "Missing required tool: $tool"
done

for file in \
  "$CHART" \
  "$VALUES" \
  "$CHI_MANIFEST" \
  "$NETWORK_POLICY"; do
  [[ -f "$file" ]] || fail "Missing file: $file"
done

echo "==> Deployment configuration"
echo "Mode: $MODE"
echo "Context: $KCTX"
echo "Namespace: $NAMESPACE"
echo "Helm release: $RELEASE"
echo "ClickHouseInstallation: $CHI_NAME"

echo "==> Checking Kubernetes access"

kubectl --context="$KCTX" \
  get namespace "$NAMESPACE" >/dev/null

echo "==> Linting Sentry chart"

helm lint "$CHART" \
  -f "$VALUES" >/dev/null

echo "==> Rendering Helm manifests"

RENDERED="$(mktemp)"
trap 'rm -f "$RENDERED"' EXIT

helm template "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" \
  -f "$VALUES" > "$RENDERED"

if grep -Eq \
  'image:.*bitnamilegacy/(postgresql|redis)' \
  "$RENDERED"; then
  fail "Deprecated PostgreSQL/Redis images found"
fi

echo "==> Validating ClickHouse against API"

kubectl --context="$KCTX" \
  apply --dry-run=server \
  -f "$CHI_MANIFEST"

echo "==> Validating NetworkPolicy against API"

kubectl --context="$KCTX" \
  apply --dry-run=server \
  -f "$NETWORK_POLICY"

if [[ "$MODE" == "--plan" ]]; then
  echo
  echo "PASS: Deployment plan validated"
  echo "No Kubernetes resources were changed."
  exit 0
fi

echo "==> Checking deployment authorization"

EXPECTED_APPROVAL="${RELEASE}/${KCTX}"

[[ "${DEPLOY_APPROVED:-}" == "$EXPECTED_APPROVAL" ]] ||
  fail "Set DEPLOY_APPROVED=$EXPECTED_APPROVAL to execute"

echo "==> Running cluster preflight"

KCTX="$KCTX" NAMESPACE="$NAMESPACE" \
  ./scripts/preflight-deploy.sh

echo "==> Applying ClickHouseInstallation"

kubectl --context="$KCTX" \
  apply -f "$CHI_MANIFEST"

echo "==> Waiting for ClickHouse reconciliation"

kubectl --context="$KCTX" \
  -n "$NAMESPACE" wait \
  --for=jsonpath='{.status.status}'=Completed \
  "chi/$CHI_NAME" \
  --timeout=20m

echo "==> Checking ClickHouse Pods"

kubectl --context="$KCTX" \
  -n "$NAMESPACE" get pods \
  -l "clickhouse.altinity.com/chi=$CHI_NAME"

echo "==> Applying ClickHouse NetworkPolicy"

kubectl --context="$KCTX" \
  apply -f "$NETWORK_POLICY"

echo "==> Installing Sentry"

helm upgrade --install "$RELEASE" "$CHART" \
  --kube-context "$KCTX" \
  --namespace "$NAMESPACE" \
  --values "$VALUES" \
  --atomic \
  --wait \
  --wait-for-jobs \
  --timeout 40m

echo "==> Checking Helm release"

helm --kube-context "$KCTX" \
  --namespace "$NAMESPACE" \
  status "$RELEASE"

echo "==> Workload summary"

kubectl --context="$KCTX" \
  -n "$NAMESPACE" get deployments,statefulsets

echo
echo "PASS: Helm deployment completed"
echo "Functional Sentry smoke tests are still required."

