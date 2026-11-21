
# Security Architecture

## Secret Management

Application and database credentials are stored
outside Git as Kubernetes Secrets.

The bootstrap script creates separate credentials
for Sentry and ClickHouse.

The bootstrap procedure is intended for local
development. Production requires an external
secret-management strategy and secure backup
and rotation procedures.

## Network Isolation

A dedicated NetworkPolicy is defined for ClickHouse.

Allowed ingress:
- Sentry application workloads: TCP 8123, 9000
- ClickHouse Operator namespace: TCP 8123, 9000
- ClickHouse peers: TCP 9009

The current Minikube cluster uses Kindnet, which
does not enforce Kubernetes NetworkPolicy.

Therefore, this policy has only been validated
statically. Network isolation must be tested on
a cluster using Calico or another supported CNI.

## Current Limitations

- Full Sentry is not deployed yet.
- NetworkPolicy enforcement is not verified.
- ClickHouse TLS is not configured.
- Secret backup and rotation are not implemented.
- The local Minikube cluster is not production HA.
```

## Шаг 7. Сохраняем всё в Git

Выполни:

```bash
git diff --check
```

Добавь файлы:

```bash
git add \
  infra/clickhouse/clickhouse-installation.yaml \
  infra/networking/clickhouse-ingress.yaml \
  docs/SECURITY.md
```

Проверь:

```bash
git diff --cached --stat
git diff --cached --check
```

Создай коммит:

```bash
git commit -m "feat(security): define ClickHouse network isolation policy"
```

Проверь историю:

```bash
GIT_PAGER=cat git log -5 --oneline
git status -sb
```

---

## Что прислать после выполнения

```bash
kubectl --context=ioka-lab -n sentry \
  get secret \
  sentry-clickhouse-auth \
  sentry-clickhouse-client \
  sentry-system-secret \
  sentry-admin-password

kubectl --context=ioka-lab apply \
  --dry-run=server \
  -f infra/clickhouse/clickhouse-installation.yaml

kubectl --context=ioka-lab apply \
  --dry-run=server \
  -f infra/networking/clickhouse-ingress.yaml

grep -n -m 5 \
  'app.kubernetes.io/instance:' \
  .cache/helm/sentry-rendered.yaml

GIT_PAGER=cat git log -5 --oneline
```

После этих проверок перейдём к следующей важной части — **CI/CD через GitHub Actions** с обязательными стадиями Test → Security Scan → Validate → Deploy.

У нас уже накопилось достаточно IaC-кода, чтобы внедрять не формальный pipeline, а реальные автоматизированные проверки. При этом полноценный deployment Sentry и проверка фактической сетевой изоляции останутся отдельными критериями приёмки, пока не будет подготовлен кластер с достаточными ресурсами и поддержкой NetworkPolicy.
