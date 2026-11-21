
#!/usr/bin/env bash
set -Eeuo pipefail

KCTX="${KCTX:-ioka-lab}"
NS="${NAMESPACE:-sentry}"
MIN_CPU_M="${MIN_CPU_M:-6000}"
MIN_MEMORY_MIB="${MIN_MEMORY_MIB:-24576}"
STORAGE_CLASS="${STORAGE_CLASS:-standard}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

ok() {
  echo "OK: $*"
}

echo "==> Sentry deployment preflight"
echo "Context: $KCTX"
echo "Namespace: $NS"

for tool in kubectl jq helm; do
  command -v "$tool" >/dev/null ||
    fail "Required tool not installed: $tool"
done

kubectl config get-contexts -o name |
  grep -Fxq "$KCTX" ||
  fail "Kubernetes context not found: $KCTX"

kubectl --context="$KCTX" \
  get namespace "$NS" >/dev/null ||
  fail "Namespace not found: $NS"

ok "Kubernetes connection"

echo "==> Checking node conditions"

nodes_json="$(
  kubectl --context="$KCTX" get nodes -o json
)"

ready_nodes="$(
  jq '
    [.items[] |
      select(any(.status.conditions[]?;
        .type == "Ready" and .status == "True"))] |
    length
  ' <<< "$nodes_json"
)"

(( ready_nodes > 0 )) ||
  fail "No Ready nodes"

pressure="$(
  jq -r '
    .items[].status.conditions[]? |
    select(
      (.type == "MemoryPressure" or
       .type == "DiskPressure") and
      .status != "False"
    ) |
    "\(.type)=\(.status)"
  ' <<< "$nodes_json"
)"

[[ -z "$pressure" ]] ||
  fail "Node resource pressure detected: $pressure"

ok "$ready_nodes Ready node(s), no reported resource pressure"

echo "==> Checking allocatable resources"

cpu_m="$(
  jq '
    [.items[] |
      select(any(.status.conditions[]?;
        .type == "Ready" and .status == "True")) |
      .status.allocatable.cpu |
      if endswith("m")
      then (.[0:-1] | tonumber)
      else (tonumber * 1000)
      end
    ] | add // 0
  ' <<< "$nodes_json"
)"

memory_mib="$(
  jq '
    [.items[] |
      select(any(.status.conditions[]?;
        .type == "Ready" and .status == "True")) |
      .status.allocatable.memory |
      if endswith("Ki")
      then (.[0:-2] | tonumber) / 1024
      elif endswith("Mi")
      then (.[0:-2] | tonumber)
      elif endswith("Gi")
      then (.[0:-2] | tonumber) * 1024
      else error("Unsupported memory quantity")
      end
    ] | add // 0 | floor
  ' <<< "$nodes_json"
)"

echo "CPU allocatable: ${cpu_m}m"
echo "Memory allocatable: ${memory_mib} MiB"

(( cpu_m >= MIN_CPU_M )) ||
  fail "Insufficient CPU: need at least ${MIN_CPU_M}m"

(( memory_mib >= MIN_MEMORY_MIB )) ||
  fail "Insufficient RAM: need at least ${MIN_MEMORY_MIB} MiB"

ok "Cluster resource minimums"

echo "==> Checking storage"

kubectl --context="$KCTX" \
  get storageclass "$STORAGE_CLASS" >/dev/null ||
  fail "StorageClass missing: $STORAGE_CLASS"

ok "StorageClass exists"

echo "==> Checking required Secrets"

secrets=(
  sentry-admin-password
  sentry-system-secret
  sentry-clickhouse-auth
  sentry-clickhouse-client
  sentry-postgresql-admin
  sentry-postgresql-auth
  sentry-redis-auth
)

for name in "${secrets[@]}"; do
  kubectl --context="$KCTX" \
    -n "$NS" get secret "$name" >/dev/null ||
    fail "Missing Secret: $name"
done

ok "Required Secrets exist"

echo "==> Checking ClickHouse Operator"

kubectl --context="$KCTX" \
  get crd clickhouseinstallations.clickhouse.altinity.com \
  >/dev/null ||
  fail "ClickHouseInstallation CRD missing"

operator_ready="$(
  kubectl --context="$KCTX" \
    -n clickhouse-operator get deployments -o json |
  jq '
    [.items[] |
      select((.status.readyReplicas // 0) > 0)] |
    length
  '
)"

(( operator_ready > 0 )) ||
  fail "No Ready ClickHouse operator Deployment"

ok "ClickHouse Operator available"

echo "==> Checking external databases"

for name in ioka-postgresql ioka-redis; do
  replicas="$(
    kubectl --context="$KCTX" -n "$NS" \
      get statefulset "$name" \
      -o jsonpath='{.status.readyReplicas}'
  )" || fail "StatefulSet missing: $name"

  [[ "$replicas" == "1" ]] ||
    fail "$name not ready"

  ok "$name Ready"
done

echo "==> Checking Helm chart artifacts"

[[ -f .cache/helm/sentry-36.1.0.tgz ]] ||
  fail "Pinned Sentry Helm chart not downloaded"

[[ -f helm/values/sentry-lab.yaml ]] ||
  fail "Sentry values file missing"

ok "Helm chart artifacts found"

echo
echo "PASS: Sentry deployment preflight completed"
echo "Note: storage free space, pod scheduling,"
echo "image pulls and application connectivity still"
echo "require separate runtime verification."

