
# TROUBLESHOOTING — Sentry on Kubernetes

## Environment

- Platform: Kubernetes / Minikube
- Namespace: `sentry`
- Sentry: Helm chart 36.1.0
- ClickHouse: Altinity ClickHouse Operator 0.26.3
- PostgreSQL and Redis: external StatefulSets
- Deployment: parameterized manifests and Helm values

These are theoretical incident-response runbooks.
They must be validated against a running Sentry deployment
before being treated as operationally verified procedures.

## General Incident Procedure

1. Determine severity, affected components and start time.
2. Stop infrastructure changes and record the last deployment.
3. Capture logs, Kubernetes events, resource utilization and
   relevant configuration versions.
4. Preserve persistent data before making destructive changes.
5. Restore service using the least destructive method.
6. Verify functionality and document the incident.

Initial checks:

```bash
kubectl get nodes -o wide
kubectl -n sentry get pods -o wide
kubectl -n sentry get deploy,sts,pvc
kubectl -n sentry get events \
  --sort-by=.metadata.creationTimestamp
kubectl describe nodes
```

Use the configured kubecontext for the affected cluster.
For the local lab, add `--context=ioka-lab`.

Do not publish credentials, DSNs, tokens, session recordings
or database contents in troubleshooting evidence.

---

## 4.1 ClickHouse CrashLoopBackOff

### Symptoms

After an unexpected shutdown, a ClickHouse Pod repeatedly
restarts. Logs report checksum failures, corrupted parts,
unexpected EOF or other storage-related errors.

Event ingestion, Snuba queries and Sentry event searches
may be affected.

### Diagnosis

Identify the installation and its Pods:

```bash
kubectl -n sentry get chi
kubectl -n sentry get pods -o wide
kubectl -n sentry get pvc
```

Identify the affected ClickHouse Pod and replace
`<clickhouse-pod>` below with its actual name.

```bash
kubectl -n sentry describe pod <clickhouse-pod>

kubectl -n sentry logs <clickhouse-pod> \
  --previous --tail=300

kubectl -n sentry logs <clickhouse-pod> \
  --tail=300
```

Inspect the operator:

```bash
kubectl -n clickhouse-operator get pods

kubectl -n clickhouse-operator logs \
  deployment/clickhouse-operator --tail=200
```

If the deployment name differs, discover the actual operator
workload using `kubectl get deploy -n clickhouse-operator`.

Check disk pressure and volume status:

```bash
kubectl describe nodes

kubectl -n sentry get pvc -o wide

kubectl get pv
```

Distinguish actual corruption from:

- Invalid configuration or incomplete configuration rollout
- Memory exhaustion
- Storage permission errors
- Full filesystem or inode exhaustion
- Persistent volume or underlying disk failures

### Recovery

1. Suspend deployment changes and prevent further ingestion
   into the affected system where operationally possible.
2. Collect logs and identify the damaged table, part or volume.
3. Preserve an application-consistent backup or a cold snapshot
   of the affected persistent volume.
4. Inspect the damage in a separate recovery environment.
5. Prefer restoration from a verified backup or healthy replica.
6. For replicated installations, follow the documented
   replica resynchronization procedure.
7. For a single-node installation, do not assume that a healthy
   replica exists.

Never blindly delete ClickHouse parts, remove PVCs or
reinitialize the database to resolve CrashLoopBackOff.

If the database starts successfully, inspect affected tables
with version-compatible ClickHouse diagnostic queries.

### Verification

Confirm that:

- The ClickHouse Pod remains Ready without repeated restarts.
- The database responds to queries.
- Snuba can query ClickHouse.
- Newly ingested test events become searchable in Sentry.
- Historical data is accessible within the expected RPO.
- Any lost or unrecoverable event range is documented.

### Prevention

Use verified backups, restore drills, disk monitoring,
storage-health monitoring and controlled upgrades.

For production, assess replication, quorum and
failure-domain isolation.

---

## 4.2 OOMKilled During an Event Spike

### Symptoms

Sentry workers or database containers terminate during
a sudden increase in incoming events.

Possible symptoms include:

- `OOMKilled`
- Exit code 137
- Increased container restarts
- HTTP 502/503 responses
- Growing Kafka consumer lag
- Delayed event visibility

### Diagnosis

```bash
kubectl -n sentry get pods -o wide

kubectl -n sentry get events \
  --sort-by=.metadata.creationTimestamp

kubectl describe nodes
```

Find containers recently terminated due to OOM:

```bash
kubectl -n sentry get pods -o json | jq -r '
  .items[] as $pod |
  $pod.status.containerStatuses[]? |
  select(.lastState.terminated.reason == "OOMKilled") |
  "\($pod.metadata.name) \(.name) OOMKilled"
'
```

Inspect the affected Pod:

```bash
kubectl -n sentry describe pod <pod-name>

kubectl -n sentry logs <pod-name> \
  --previous --tail=200
```

If Metrics Server is available:

```bash
kubectl top nodes
kubectl top pods -n sentry --containers
```

Compare observed memory usage against requests and limits.
Inspect incoming event rate, Kafka backlog, consumer lag
and application error rates.

### Mitigation

1. Identify the component that exceeded its memory limit.
2. Determine whether the spike is legitimate traffic,
   abusive traffic or repeated duplicate events.
3. Reduce unnecessary event volume with sampling or
   controlled rate limits where supported.
4. Restore healthy consumption before increasing traffic.
5. Increase memory requests or limits only after checking
   node capacity.
6. Scale eligible stateless consumers if capacity,
   partitioning and application behavior allow it.
7. Avoid indiscriminately increasing database replicas.

Do not clear Kafka topics, reset consumer offsets or
delete pending events as an immediate OOM fix.

### Verification

Confirm that:

- Affected Pods remain Ready.
- OOM restart counts stop increasing.
- Memory usage stabilizes.
- Kafka consumer lag decreases.
- New events appear in Sentry.
- The resulting backlog and any data loss are documented.

### Prevention

Configure resource requests and limits, memory dashboards,
capacity alerts, queue-lag alerts, ingestion controls and
load-testing scenarios.

---

## 4.3 DiskPressure / Read-Only / Evicted

### Symptoms

A Kubernetes node reaches approximately 99% disk usage.

Possible effects:

- Node condition `DiskPressure=True`
- Evicted Pods
- Database write failures
- Filesystem becoming read-only
- Increased ClickHouse or PostgreSQL errors

### Diagnosis

```bash
kubectl get nodes

kubectl describe nodes

kubectl -n sentry get pods -o wide

kubectl -n sentry get events \
  --sort-by=.metadata.creationTimestamp

kubectl -n sentry get pvc -o wide
kubectl get pv
```

Inspect the relevant node filesystem and inodes.

For the local Minikube lab:

```bash
minikube ssh -p ioka-lab -- df -h
minikube ssh -p ioka-lab -- df -i
```

On a remote Kubernetes cluster, use authorized node
diagnostic tooling instead of assuming Minikube access.

Distinguish between:

- Node ephemeral-storage exhaustion
- Container image or log accumulation
- Persistent volume exhaustion
- Inode exhaustion
- Underlying filesystem errors or read-only remount

### Recovery

1. Restrict new writes if data integrity is at risk.
2. Identify the full filesystem and affected components.
3. Preserve required logs and diagnostic evidence.
4. Check retention policies and identify reclaimable data.
5. Expand available storage using supported infrastructure
   procedures when necessary.
6. For PVC expansion, first verify StorageClass support,
   available capacity and the application's expansion rules.
7. If the filesystem has become read-only due to I/O failure,
   investigate underlying storage health before resuming writes.
8. Restore database operations and restart affected workloads
   only after storage conditions are corrected.

Do not run:

```bash
kubectl delete pvc --all -n sentry
```

Do not indiscriminately prune volumes, delete ClickHouse data
parts or erase Kafka data directories.

### Verification

Confirm that:

- Node `DiskPressure` is False.
- Disk and inode headroom is restored.
- Persistent volumes remain attached and healthy.
- Databases accept new writes.
- Evicted workloads are replaced with healthy Pods.
- New Sentry events are successfully stored and queried.

### Prevention

Implement storage and inode alerts, log rotation,
retention policies, capacity forecasting, tested backups
and verified storage-expansion procedures.

---

## 4.4 Session Replays — "Replays not available"

### Symptoms

A user opens a Sentry Session Replay, but the recording
cannot be retrieved or displayed.

This may originate from missing client recordings,
ingestion failures, missing metadata, recording-storage
problems or an incompatible client configuration.

### Diagnosis

#### 1. Verify the client SDK

Confirm that the SDK version supports Session Replay.

For the JavaScript SDK, verify the Replay integration and
sampling configuration:

```javascript
Sentry.replayIntegration()
```

Review application configuration for:

```javascript
replaysSessionSampleRate
replaysOnErrorSampleRate
```

In browser developer tools, inspect Replay-related
network requests and their HTTP responses.

A successful event submission does not necessarily
mean that a Replay recording was submitted.

#### 2. Verify Relay and ingress

Discover the relevant Kubernetes workloads:

```bash
kubectl -n sentry get pods | grep -Ei \
  'relay|nginx|sentry'
```

Inspect actual Relay and ingress Pod logs:

```bash
kubectl -n sentry logs <relay-pod> --tail=200

kubectl -n sentry logs <ingress-pod> --tail=200
```

Look for rejected requests, authentication failures,
rate limits, size limits and upstream errors.

#### 3. Verify processing and Kafka

```bash
kubectl -n sentry get pods | grep -Ei \
  'kafka|snuba|worker|task'
```

Inspect the corresponding workload logs and consumer lag
using the tooling supported by the deployed chart version.

Look for ingestion errors, processing failures and
unprocessed recording messages.

#### 4. Verify metadata and recording storage

Confirm that the deployed Sentry release has the expected
Replay processing components enabled.

Check:

- Metadata availability in the query path
- Recording segment availability in the configured storage
- Storage permissions and capacity
- Retention policy
- Application logs for missing recording segments
- Browser Network tab responses from Replay API requests

Do not assume that all recording data is stored directly
in ClickHouse. The actual storage backend depends on
the Sentry version and configuration.

### Recovery

1. Correct SDK configuration or unsupported SDK versions.
2. Resolve ingress or Relay rejection errors.
3. Restore unhealthy processing components.
4. Restore access to recording storage.
5. Correct retention or configuration inconsistencies.
6. Use documented, version-compatible reprocessing
   procedures only when the original data still exists.

Missing recordings cannot always be reconstructed.

### Verification

Generate a new controlled test session.

Verify that:

- The SDK sends Replay data.
- Relay accepts the recording.
- Processing completes successfully.
- Recording metadata is available.
- Recording segments can be retrieved.
- The Replay opens and plays in the Sentry UI.

Do not mark the issue resolved solely because an API
returns HTTP 200 or 202.

### Prevention

Monitor Replay ingestion failures, storage access errors,
processing backlog, retention, SDK compatibility and
end-to-end synthetic Replay tests.

---

## Post-Incident Checklist

Record for every incident:

- Incident ID and timestamps in UTC
- Affected components and impact
- Evidence and confirmed root cause
- Immediate mitigation
- Recovery and data-integrity verification
- Actual RTO and RPO, if measurable
- Preventive changes and assigned owner
- Follow-up validation results

## References

- https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/
- https://kubernetes.io/docs/tasks/debug/debug-cluster/
- https://kb.altinity.com/altinity-kb-kubernetes/
- https://docs.sentry.io/platforms/javascript/session-replay/
