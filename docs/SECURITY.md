# Security Architecture and Known Limitations

## Credentials

All Sentry application/database credentials are generated into Kubernetes Secrets via `scripts/bootstrap-secrets.sh` and `scripts/bootstrap-external-db-secrets.sh`; passwords are not placed directly into repository manifests. `sentry-clickhouse-auth` contains the ClickHouse password SHA-256 digest and `sentry-clickhouse-client` contains the actual client password. The PostgreSQL init ConfigMap references a password received from a Kubernetes Secret, not a literal password.

`KSV-0109` in `.trivyignore.yaml` is a documented, time-limited exception for that PostgreSQL init script only. It is **not** a blanket exemption from secret scanning. Kubernetes Secrets do not provide automatic rotation, backup, or encryption at rest. These features are not implemented here.

## NetworkPolicy

`infra/networking/clickhouse-ingress.yaml` describes intended ClickHouse ingress on TCP 8123/9000 from Sentry workloads and the Operator namespace, plus TCP 9009 between ClickHouse Pods.

**Enforcement is not verified:** the lab uses Kindnet, which does not enforce Kubernetes NetworkPolicy. This file demonstrates intended policy, not proven isolation. Use a policy-enforcing CNI (e.g., Calico) and connectivity tests before treating it as an active control.

## Container images and CI

The Sentry chart's bundled legacy PostgreSQL and Redis were disabled in `helm/values/sentry-lab.yaml`; separate maintained PostgreSQL/Redis images are defined in `infra/datastores`. The chart version is pinned; not all images are digest-pinned, and the repository's historical image inventory must be regenerated whenever chart overrides change.

The CI `Security Scan` job checks **IaC misconfigurations and repository secrets** with Trivy. It does **not** enforce image-vulnerability scanning for all rendered images; see `SECURITY_AUDIT.md` for the partial historical assessment. Do not equate a green CI result with a complete vulnerability clearance.

## Runtime and production limitations

- Full Sentry and actual `Deploy` job have not been executed in this lab.
- ClickHouse TLS is disabled in the lab values; transport encryption is not verified.
- PostgreSQL, Redis and ClickHouse use single-instance storage and are not HA.
- Disk backup, recovery testing and credential rotation are not implemented.
- Resource admission checks do not guarantee Pod schedulability, capacity, or storage headroom.
- A self-hosted GitHub runner needs careful isolation, minimal Kubernetes RBAC, and protected deployment permissions before real use.
