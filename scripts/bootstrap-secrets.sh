
#!/usr/bin/env bash
set -euo pipefail
set +x
umask 077

KCTX="${KCTX:-ioka-lab}"
NAMESPACE="${NAMESPACE:-sentry}"

NAMES=(
  sentry-clickhouse-auth
  sentry-clickhouse-client
  sentry-system-secret
  sentry-admin-password
)

kubectl --context="$KCTX" get namespace "$NAMESPACE" \
  >/dev/null

existing=0

for name in "${NAMES[@]}"; do
  if kubectl --context="$KCTX" \
    -n "$NAMESPACE" get secret "$name" \
    >/dev/null 2>&1; then
    existing=$((existing + 1))
  fi
done

if (( existing == ${#NAMES[@]} )); then
  echo "All bootstrap secrets already exist."
  exit 0
fi

if (( existing != 0 )); then
  echo "ERROR: Partial secret set detected." >&2
  echo "Reconcile existing secrets manually." >&2
  exit 1
fi

create_secret() {
  local name="$1"
  local key="$2"
  local value="$3"

  printf '%s' "$value" |
    kubectl --context="$KCTX" \
      -n "$NAMESPACE" create secret generic "$name" \
      --from-file="${key}=/dev/stdin" \
      --dry-run=client -o yaml |
    kubectl --context="$KCTX" \
      -n "$NAMESPACE" create -f - >/dev/null
}

CH_PASSWORD="$(openssl rand -hex 32)"
CH_HASH="$(printf '%s' "$CH_PASSWORD" |
  shasum -a 256 | awk '{print $1}')"

SYSTEM_KEY="$(openssl rand -hex 32)"
ADMIN_PASSWORD="$(openssl rand -hex 24)"

trap 'unset CH_PASSWORD CH_HASH SYSTEM_KEY ADMIN_PASSWORD' EXIT

create_secret \
  sentry-clickhouse-auth \
  password_sha256_hex "$CH_HASH"

create_secret \
  sentry-clickhouse-client \
  clickhouse-password "$CH_PASSWORD"

create_secret \
  sentry-system-secret \
  system.secret-key "$SYSTEM_KEY"

create_secret \
  sentry-admin-password \
  admin-password "$ADMIN_PASSWORD"

echo "Bootstrap secrets created:"
printf '  %s\n' "${NAMES[@]}"

