
# Container Image Security Audit

## Scope

Project: IOKA Sentry Platform

Scan date: 2026-11-21
Scanner: Trivy 0.76.2
Target architecture: linux/arm64
Severity filter: HIGH, CRITICAL

This audit covers four container images from the
Sentry infrastructure.

## Findings

| Component | Critical | High | Fix available |
|---|---:|---:|---:|
| BusyBox 1.38.0 | 0 | 0 | 0 |
| Sentry Relay 26.11.0 | 0 | 0 | 0 |
| PostgreSQL (Bitnami Legacy) | 13 | 215 | 83 |
| Redis (Bitnami Legacy) | 13 | 212 | 95 |
| Total | 26 | 440 | 178 |

Counts represent vulnerability findings, not
necessarily unique CVE identifiers.

## Identified Risks

### Unsupported container images

PostgreSQL and Redis use archived Bitnami Legacy
images that no longer receive regular security
updates.

Trivy also reported that the Debian 11.7-based
images are no longer supported by the distribution
according to its vulnerability database.

This reduces confidence in the completeness of
vulnerability detection.

### Mutable image tags

The image inventory includes:

- bitnami/kubectl:latest

This tag is not immutable and must be replaced
with an explicitly approved version or digest.

## Remediation Strategy

1. Replace unsupported PostgreSQL and Redis
   images with maintained alternatives.

2. Prefer independently managed database and
   caching components over replacing Bitnami
   container images inside incompatible charts.

3. Pin container images to approved versions
   and immutable digests.

4. Validate runtime compatibility, persistence,
   authentication and application connectivity.

5. Repeat Trivy scanning after remediation.

6. Enforce vulnerability and unsupported-image
   policies before allowing deployment.

## CI/CD Security Gate

The existing CI pipeline performs IaC and
secret scanning.

Container image vulnerability enforcement
has not yet been implemented.

The current successful CI result therefore
does not represent a successful full image
security assessment.

Deployment approval must remain blocked until
the required image security checks pass or
documented risk exceptions are approved.

## Limitations

Only four of the fifteen inventoried images
have been scanned in this assessment.

Findings are based on the vulnerability
database available on the scan date.

No production deployment or runtime
verification has been performed.

