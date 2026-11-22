# Container Image Security Audit (Partial Historical Assessment)

## Scope and method

Scan date: 2026-11-21. Tool: Trivy 0.76.2; platform: `linux/arm64`; severities HIGH and CRITICAL. Four images from the **historical** Helm-rendered inventory were scanned. This inventory predates the removal of the chart-managed PostgreSQL and Redis workloads, so findings must not be interpreted as a current full-deployment SBOM or a scan of all current images.

| Historical image/component | Critical | High | Fix available |
|---|---:|---:|---:|
| BusyBox 1.38.0 | 0 | 0 | 0 |
| Sentry Relay 26.11.0 | 0 | 0 | 0 |
| Bitnami Legacy PostgreSQL | 13 | 215 | 83 |
| Bitnami Legacy Redis | 13 | 212 | 95 |
| **Total (findings, not unique CVEs)** | **26** | **440** | **178** |

The Bitnami Legacy images are unsupported. In the subsequently revised lab configuration, chart-managed `postgresql.enabled` and `redis.enabled` are disabled and separate `postgres:16.16-bookworm` and `redis:7.4.12-bookworm` StatefulSets have been introduced. Runtime startup/persistence of those replacement services was observed. **No complete post-remediation vulnerability scan covering every rendered image was evidenced in this archive.** A historical inventory also contained the mutable `bitnami/kubectl:latest` tag; re-render and inspect the current image list rather than assume it remains present.

## Security control coverage

The GitHub Actions `Security Scan` stage runs Trivy misconfiguration checks and repository secret scanning. Its successful execution **does not** show that full container image vulnerability scanning passed. Image vulnerabilities, provenance, immutable digests, and supply-chain policy remain open review items.

Before production deployment:

1. Regenerate the current image inventory from pinned, rendered charts plus external datastore manifests.
2. Scan **all** deployable images for the target architecture with a refreshed database.
3. Review CRITICAL/HIGH findings, remediation options and narrowly approved exceptions.
4. Pin or verify immutable digests for deployed images as appropriate.
5. Retest application connectivity, PVC persistence and migrations after image updates.

This document is a bounded audit record, not certification of vulnerability-free infrastructure.
