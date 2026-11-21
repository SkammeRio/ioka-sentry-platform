
#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077

KCTX="${KCTX:-ioka-lab}"
NAMESPACE="${NAMESPACE:-sentry}"

echo "Checking Kubernetes access..."

kubectl --context="$KCTX" \
  get namespace "$NAMESPACE" >/dev/null

create_secret() {
  local name="$1"
  local key="$2"
  local password

  if kubectl --context="$KCTX" \
    -n "$NAMESPACE" \
    get secret "$name" >/dev/null 2>&1; then

    echo "EXISTS: $name"
    return 0
  fi

  password="$(openssl rand -hex 32)"

  printf '%s' "$password" |
    kubectl --context="$KCTX" \
      -n "$NAMESPACE" \
      create secret generic "$name" \
      --from-file="${key}=/dev/stdin" \
      --dry-run=client \
      -o yaml |
    kubectl --context="$KCTX" \
      -n "$NAMESPACE" \
      apply -f - >/dev/null

  unset password

  echo "CREATED: $name"
}

create_secret \
  sentry-postgresql-admin \
  password

create_secret \
  sentry-postgresql-auth \
  password

create_secret \
  sentry-redis-auth \
  redis-password

echo "External database secrets bootstrap completed."

