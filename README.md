# IOKA Sentry Platform — Senior DevOps Assignment

Kubernetes-based infrastructure for a self-hosted Sentry lab, with parameterized Helm settings, Kubernetes Secrets, an Altinity-managed ClickHouse, independently managed PostgreSQL and Redis, and a GitHub Actions CI/CD pipeline.

**Verification status (2026-11-22):** CI Test, Security Scan and Validate passed; Sentry Helm lint/render and Kubernetes dry-run (`scripts/deploy-sentry.sh --plan`) passed; PostgreSQL and Redis were started and tested with persistent volumes; Altinity Operator was running. **The complete Sentry application and Deploy job have not been executed or end-to-end tested.** The available MacBook Air M3 has 8 GiB physical RAM and approximately 17 GiB free disk space, which is insufficient for this deployment. No paid infrastructure was used.

## Architecture

```text
                    Browser / SDK
                         |
                       Nginx
                         |
           +-------------+-------------+
           |                           |
       Sentry Web                     Relay -> Kafka -> Snuba -> ClickHouse
        |       |                                           (Altinity + PVC)
   PostgreSQL  Redis
       (PVC)     (PVC)
```

The Sentry chart also deploys additional services and jobs (including task broker and memcached, depending on the chart release). For the exact workload inventory, render the pinned chart instead of assuming the diagram is exhaustive.

## Files

- `helm/values/sentry-lab.yaml` — Sentry chart overrides, external database endpoints and Secret references.
- `infra/clickhouse/` — ClickHouseInstallation and Altinity Operator values.
- `infra/datastores/` — persistent PostgreSQL and Redis StatefulSets and Services.
- `infra/networking/` — ClickHouse NetworkPolicy.
- `scripts/bootstrap-*.sh` — idempotent Secret bootstrap routines for the lab.
- `scripts/ci-validate.sh` — pinned-chart download, lint, rendering and schema checks.
- `scripts/preflight-deploy.sh` — resource, storage, Secret and dependency gate.
- `scripts/deploy-sentry.sh` — `--plan` (dry-run) and `--apply` (actual deployment).
- `.github/workflows/ci-cd.yaml` — Test, Security Scan, Validate and gated Deploy.
- `TROUBLESHOOTING.md` — the four theoretical incident-response scenarios.
- `COVERAGE.md` — requirements versus demonstrated evidence and limitations.

## Prerequisites

An accessible Kubernetes cluster, Helm 4.3.0, `kubectl`, `jq`, Bash, OpenSSL, `shasum` (or Perl providing it), Git, `kubeconform` 0.8.0 and network access to the chart repositories are required. The example target uses context `ioka-staging`, namespace `sentry` and StorageClass `standard`. The infrastructure manifests **currently hard-code namespace `sentry` and StorageClass `standard`**; do not use a different namespace or storage class without modifying and validating the corresponding YAML files.

For the complete Sentry deployment, the repository uses a conservative lab preflight threshold of **6000 millicores and 24576 MiB of allocatable memory** across Ready nodes. This is a lab admission gate, not a proof of sufficient schedulable capacity or a guarantee for production. Verify actual available disk and resources for all Pods, including Kafka and ClickHouse, before deploying. The host used for this assignment did not meet this threshold.

The local Minikube baseline has a `standard` hostpath StorageClass **without volume expansion**, a single node, and Kindnet; the NetworkPolicy is not enforced by that CNI. This configuration is for a lab, not HA production.

## Clean-cluster setup (documented, NOT end-to-end verified)

The commands below are an intended sequence for a suitable existing cluster. **Do not run them against the 8 GiB Mac lab.** Replace `ioka-staging` only with an actual configured context; do not assume the existence of a cluster, runner, or secrets.

```bash
export KCTX=ioka-staging
kubectl --context="$KCTX" get nodes -o wide
kubectl --context="$KCTX" get storageclass standard
kubectl --context="$KCTX" create namespace sentry --dry-run=client -o yaml | \
  kubectl --context="$KCTX" apply -f -

# Generate secrets directly in Kubernetes, not in Git:
KCTX="$KCTX" NAMESPACE=sentry bash scripts/bootstrap-secrets.sh
KCTX="$KCTX" NAMESPACE=sentry bash scripts/bootstrap-external-db-secrets.sh

# Pin/download and statically validate the deployment charts:
bash scripts/ci-validate.sh

# Install the ClickHouse operator and CRDs:
helm --kube-context "$KCTX" upgrade --install clickhouse-operator \
  .cache/helm/altinity-clickhouse-operator-0.26.3.tgz \
  --namespace clickhouse-operator --create-namespace \
  -f infra/clickhouse/operator-values.yaml --wait --timeout 10m

# Start external PostgreSQL and Redis:
kubectl --context="$KCTX" apply -f infra/datastores/postgresql.yaml
kubectl --context="$KCTX" apply -f infra/datastores/redis.yaml
kubectl --context="$KCTX" -n sentry rollout status sts/ioka-postgresql --timeout=300s
kubectl --context="$KCTX" -n sentry rollout status sts/ioka-redis --timeout=300s

# Non-mutating plan, then resource and dependency gate:
KCTX="$KCTX" ./scripts/deploy-sentry.sh --plan
KCTX="$KCTX" ./scripts/preflight-deploy.sh

# Only after review and explicit approval on a suitably sized cluster:
KCTX="$KCTX" DEPLOY_APPROVED="ioka-sentry/$KCTX" \
  ./scripts/deploy-sentry.sh --apply
```

`deploy-sentry.sh --apply` applies the ClickHouseInstallation, waits for Operator reconciliation, applies the NetworkPolicy, and installs/updates the Sentry Helm release. The script does **not** create the cluster, operator, namespaces, external database StatefulSets, or secrets. A successful Helm status is not proof of functional event ingestion. Helm rollback does not roll back manually applied database resources or persistent data.

## Acceptance and runtime smoke tests

On a sufficiently resourced cluster, verify and record:

```bash
kubectl --context="$KCTX" -n sentry get pods,deploy,sts,pvc,svc -o wide
kubectl --context="$KCTX" -n sentry get chi
helm --kube-context "$KCTX" -n sentry status ioka-sentry
kubectl --context="$KCTX" -n sentry get events --sort-by=.metadata.creationTimestamp
```

Discover the actual Nginx Service name with `get svc`, then forward it to localhost (substitute the real service):

```bash
kubectl --context="$KCTX" -n sentry port-forward svc/<nginx-service-name> 9000:80
```

Verify the Sentry login page in the browser, create a test project, send an event through its SDK DSN, and **confirm that the same event is searchable in the UI**. Capture sanitized screenshots and logs. The tests cannot be marked PASS until performed; Session Replay playback requires an additional SDK/browser and recording-storage test.

## CI/CD

GitHub Actions executes Test (Bash/whitespace), Security Scan (Trivy configuration and secret scanning) and Validate (Helm lint, render, Kubeconform). The Deploy job is enabled only for `workflow_dispatch` on `main` and requires a dedicated `self-hosted`, `linux`, `ioka-deploy` runner and access to the `ioka-staging` Kubernetes context. **No such runner or successful real Deploy is evidenced in this submission.** The workflow's `environment: ioka-staging` entry is not, on its own, proof that manual approval protections are configured. Restrict runner access and enable appropriate GitHub environment/branch protections before use.

Evidence includes historical CI outputs under `docs/evidence`; the latest reported successful CI run is ID `44990820451` (user-observed GitHub Actions result, 2026-11-22). The checked-in `ci-success.json` records an earlier successful run and should not be read as the latest run.

## Security / limitations

Kubernetes Secrets are bootstrapped directly in the cluster; no plaintext credentials should be committed. Sentry-to-ClickHouse TLS and NetworkPolicy enforcement are not verified. The image vulnerability assessment is incomplete (see `docs/SECURITY_AUDIT.md`), and the successful GitHub Security Scan gates **IaC/secret checks, not every container image**. Single-node PostgreSQL, Redis and ClickHouse are not highly available. See `docs/SECURITY.md`, `COVERAGE.md`, and `TROUBLESHOOTING.md`.
