# Demo service and Kubernetes debugging exercise

## Run it

Prerequisites: Docker, `kind`, `kubectl`, and Helm. From the repository root:

```bash
./setup.sh
echo '127.0.0.1 demo.local' | sudo tee -a /etc/hosts
curl http://demo.local/
```

The response is JSON containing the configured app name, version, and pod
hostname. The setup script creates or reuses the `demo` Kind cluster, installs
ingress-nginx, builds and loads `demo-service:local`, and upgrades the `demo`
release in namespace `demo`. It is safe to run again.

If port 80 is already in use on the host, verify through the controller instead:

```bash
kubectl -n ingress-nginx port-forward service/ingress-nginx-controller 8088:80
curl -H 'Host: demo.local' http://127.0.0.1:8088/
```

To run the debugging lab:

```bash
cd lab
./scenario.sh up
./scenario.sh verify
```

## Resources

The demo service requests `50m` CPU and `64Mi` memory, with limits of `250m`
CPU and `128Mi` memory. The request is enough for this small HTTP server to
start and remain schedulable on a local cluster; the limit caps a runaway
process without making normal requests CPU-starved. These values are starting
points, not production measurements.

The debug-lab services use the same small baseline (`50m` CPU/`64Mi` memory
requests and `200m` CPU/`128Mi` limits) because they are lightweight test
processes. Metrics gets `100m` CPU requested and a `500m` CPU limit because the
original values exceeded the namespace LimitRange; these values stay below its
maximum while allowing some burst headroom. This is a compatibility choice,
not a claim that metrics was measured to use more CPU. The migration Job uses
the baseline because it is short-lived. These are conservative local-cluster
values; production sizing should come from measured startup, steady-state, and
peak usage.

## Deliberately skipped and production follow-up

I did not add TLS, image signing/SBOM attestation, NetworkPolicies, a Pod
DisruptionBudget, HPA, external secrets, metrics, or tracing. Skipping them
means traffic is plain HTTP locally, credentials would need a separate
mechanism, and there is no automated scaling or availability protection. CI
does run Helm linting and a Trivy vulnerability gate, but it does not yet sign
images or publish an SBOM. For production I would add those controls, pin image
digests, add structured logs and Prometheus metrics, and size requests and
limits from load-test and production telemetry.

## Part 4 status

The supported chart fixes are applied and the final recorded verification passes
9 of 11 checks. The remaining reporter failure is documented in
[`lab/FINDINGS.md`](lab/FINDINGS.md): the immutable supplied binary wraps the
Kubernetes PodList response in a 1,024-byte reader, while the authenticated API
returns about 123 KB. It consequently parses truncated JSON and remains
unready. I did not replace the image, alter `cluster-state`, or add a proxy that
would hide this defect. The terminal evidence is in `lab/part4-session.log`.

## How I used AI

I used Codex to help scaffold the Python service, Helm chart, setup script, and
documentation, and to suggest diagnostic commands. I ran the commands against
the local Kind cluster myself and corrected assumptions using cluster events,
container logs, rendered manifests, and the verifier. In particular, the
reporter issue was not treated as a Helm fix after inspection showed the hard
1 KiB response limit inside the provided immutable binary.

For that investigation I temporarily exported the supplied image, confirmed
that it contained only a stripped statically linked Go ELF (no source or debug
files), then used Go symbol metadata (`go tool nm`/`readelf`), `strings`, and
`objdump` to inspect `main.(*reporter).listPods`. This produced
source-equivalent pseudocode showing the 1,024-byte reader; it did not recover
the original Go source.

## CI

The optional GitHub Actions workflow at `.github/workflows/ci.yml` lints both
Helm charts, builds the service image, and fails on HIGH or CRITICAL Trivy
findings.
