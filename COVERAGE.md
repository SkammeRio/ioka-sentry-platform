# Requirements and Evidence Matrix

Assessment date: 2026-11-22. All statuses below are limited to verifiable logs and files; **static validation is not equivalent to a working Sentry deployment**.

| Original assignment requirement | Status | Evidence / limitation |
|---|---|---|
| Local Sentry platform (Kubernetes option) | **PARTIAL** | Chart, values, manifests and deployment script are in Git; full Sentry workload and UI were not deployed on the resource-constrained laptop. |
| Reproducible Kubernetes setup | **PARTIAL** | README documents namespace, Secrets, operator, external DBs, Helm and verification; no full clean-cluster replay has been completed. |
| Parameterized IaC | **PARTIAL** | Helm chart settings and scripts allow overrides; some manifests still hard-code `sentry` and StorageClass `standard`. |
| No plaintext secrets in Git | **CHECKED** | Cluster Secrets generated using bootstrap scripts; Trivy repository secret scan succeeded. Secret rotation/backup remain out of scope. |
| Testing stage | **PASS (CI)** | Successful GitHub Actions run 44990820451; Bash syntax/whitespace checking. |
| Vulnerability scanning stage | **PARTIAL (CI PASS)** | Trivy IaC and secret scanning pass. Image vulnerability scanning is documented but **not enforced for the complete image set**. |
| Validation stage | **PASS (static)** | Pinned-chart Helm lint/render and Kubeconform succeeded; server-side dry-run of ClickHouseInstallation and NetworkPolicy succeeded. |
| Deploy stage | **IMPLEMENTED, NOT EXECUTED** | Manual main-only job needs a separate self-hosted runner and adequately sized `ioka-staging` cluster. `deploy-sentry.sh --plan` passed locally; `--apply` was not run. |
| PostgreSQL / Redis persistence | **PASS (lab)** | Both StatefulSets Ready 1/1, PVCs Bound, functional authentication/PING and restart persistence tests were observed in the user's terminal outputs. |
| ClickHouse | **PARTIAL** | Altinity Operator Ready and ClickHouseInstallation accepted by server-side dry-run; ClickHouse server not confirmed running. |
| NetworkPolicy | **STATIC ONLY** | Manifest validated; lab's Kindnet does not enforce NetworkPolicy. |
| Troubleshooting 4.1 ClickHouse corruption | **DOCUMENTED** | `TROUBLESHOOTING.md`, theoretical recovery procedure. |
| Troubleshooting 4.2 OOMKilled | **DOCUMENTED** | `TROUBLESHOOTING.md`, theoretical recovery procedure. |
| Troubleshooting 4.3 DiskPressure | **DOCUMENTED** | `TROUBLESHOOTING.md`, theoretical recovery procedure. |
| Troubleshooting 4.4 Session Replays | **DOCUMENTED** | `TROUBLESHOOTING.md`, theoretical recovery procedure. |
| Browser/UI and event-ingestion smoke test | **NOT VERIFIED** | No successful full Sentry deployment on available hardware. |

## Submission caveat

The unavailable portion is the operational end-to-end deployment of the whole Sentry stack. The host is a MacBook Air M3 with 8 GiB RAM and approximately 17 GiB free disk; the local Minikube's allocatable RAM was approximately 4 GiB. The preflight gate correctly refused full deployment, rather than masking OOM conditions or lowering security/resource thresholds. No paid host was provisioned. Reviewers can reproduce the remaining steps on a suitably sized Kubernetes cluster following README, but this is **an unverified deployment path** until actually run.
