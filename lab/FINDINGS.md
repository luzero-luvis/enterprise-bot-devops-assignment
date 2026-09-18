# Findings — Part 4 debug lab

The terminal session is recorded in `part4-session.log`. The final supported
verification passed 9/11 checks; the reporter limitation at the end is an
immutable-image blocker, documented separately rather than hidden.

## Defect 1 — explicit numeric runtime UID

**Symptom:**

```text
Error: container has runAsNonRoot and image has non-numeric user (nonroot),
cannot verify user is non-root
```

This appeared for backend, gateway, worker, metrics, and reporter.

**Cause:** The image declares the symbolic user `nonroot`, while the Pod only
specified `runAsNonRoot: true`. Kubelet cannot verify that symbolic image user.

**Fix:** Set `runAsUser: 65532` alongside `runAsNonRoot: true` on every
workload. UID 65532 is the image's non-root user, preserving the least-privilege
intent.

**How I found it:** `kubectl -n debug-lab get pods` showed
`CreateContainerConfigError`; `kubectl -n debug-lab get events --sort-by=.lastTimestamp`
reported the exact Kubelet message above.

## Defect 2 — invalid Job restart policy

**Symptom:**

```text
Error: server-side apply failed for object debug-lab/migrate batch/v1, Kind=Job:
Job.batch "migrate" is invalid: spec.template.spec.restartPolicy: Required value:
valid values: "OnFailure", "Never"
```

**Cause:** The Job Pod template omitted `restartPolicy`.

**Fix:** Set `restartPolicy: Never`; migration is a one-shot workload and the
Job controller owns retries through `backoffLimit`.

**How I found it:** Re-running `./scenario.sh up` exposed the Helm/Kubernetes
validation error before any migration Pod could be created.

## Defect 3 — service connectivity configuration

**Symptom:** Backend logged:

```text
eb-debug-app 2.0.0 starting: mode=api ... listening on :8081
(image default is 8081; set PORT to override)
```

Gateway then logged:

```text
readiness failed: backend not reachable: GET http://backend:8080/healthz:
dial tcp ...:8080: connect: connection refused
```

**Cause:** The chart targeted a different container port than the image's
default, and the gateway's backend URL did not consistently address the
same-namespace backend Service.

**Fix:** Use `common.port: 8081` for every container and Service targetPort;
retain Service port 8080 for consumers. Set `BACKEND_URL` to
`http://backend:8080`.

**How I found it:** Compared the backend startup log with the rendered Service
targetPort, then confirmed the gateway's readiness failure in its logs.

## Defect 4 — LimitRange-incompatible metrics resources

**Symptom:** The cluster applies a per-container CPU ceiling; the original
metrics CPU setting exceeded it and prevented a compliant Pod from being
admitted.

**Cause:** Metrics requested/limited more CPU than the `debug-lab` LimitRange
allows.

**Fix:** Set metrics requests to `100m` CPU/`64Mi` and limits to `500m`
CPU/`128Mi`, which satisfy the namespace guardrail while leaving headroom.

**How I found it:** Inspected `cluster-state/limits.yaml`, then compared its
maximum CPU with the rendered metrics resources and Pod admission events.

## Defect 5 — worker writes to a read-only root filesystem

**Symptom:**

```text
FATAL: worker could not initialise its cache: mkdir /var/cache/app:
read-only file system — the process needs a writable directory at /var/cache/app
```

**Cause:** The worker correctly uses a read-only root filesystem but its cache
path was not backed by a writable volume.

**Fix:** Mount an `emptyDir` at `/var/cache/app` and set Pod `fsGroup: 65532`.
This keeps the root filesystem read-only while granting the application a
minimal writable cache location.

**How I found it:** `kubectl -n debug-lab logs deployment/worker --previous`
showed the fatal cache initialization error.

## Defect 6 — reporter RoleBinding targeted the wrong identity

**Symptom:** Before the fix:

```text
$ kubectl auth can-i list pods -n debug-lab \
  --as=system:serviceaccount:debug-lab:reporter
no
```

**Cause:** The RoleBinding subject was not the `reporter` ServiceAccount used
by the reporter Deployment.

**Fix:** Bind Role `reporter-read` to ServiceAccount `reporter` in the release
namespace.

**How I found it:** Used `kubectl auth can-i` with the exact ServiceAccount
identity from the reporter Pod spec. After the fix it returned `yes` and the
final verifier passed the authorization check.

## Unresolved supplied-image blocker — reporter truncates its own API response

**Symptom:** The final run shows:

```text
PASS  ServiceAccount debug-lab/reporter can list pods
FAIL  deployment reporter: 0/1 ready
FAIL  reporter /report does not return a pod count
```

Reporter logs repeatedly show:

```text
pod list failed: parse pod list: unexpected end of JSON input
GET /healthz -> 503
```

**Evidence and conclusion:** An authenticated request made using the reporter
ServiceAccount token, mounted CA certificate, and the standard Kubernetes URL
returned HTTP 200 in 0.014 seconds with a 122,918-byte body. Static inspection
of the supplied immutable binary shows it constructs an `io.LimitedReader`
with `N = 0x400` before JSON decoding the hard-coded
`/api/v1/namespaces/<namespace>/pods?limit=100` response. The response is
therefore truncated at 1,024 bytes before decoding.

I did not change the image repository or tag, modify `cluster-state`, or add a
response-rewriting proxy. A correct remediation requires a corrected image
(remove/increase the fixed response limit, or use Kubernetes pagination).
