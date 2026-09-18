# Q1 — Migrating from ingress-nginx to Gateway API without downtime

I would begin with an inventory of every Ingress, its hostname, TLS secret,
annotations, upstream Service, path matching, and external dependencies such
as DNS, WAF rules, authentication, rate limiting, and IP allow-lists. I would
also identify the highest-risk routes and define success criteria: request
success rate, latency, TLS errors, and a tested rollback time.

Next I would install and operate a Gateway API implementation alongside
ingress-nginx, without changing existing traffic. I would create the
`GatewayClass`, a shared `Gateway`, listener/certificate configuration, and
observability first. I would translate a small, low-risk Ingress to an
`HTTPRoute` in a staging environment, compare route behaviour and load-test
it. Translation should be reviewed rather than blindly automated because
Ingress annotations do not have universal Gateway API equivalents.

For production, I would migrate hostname by hostname in small batches. Both
controllers would stay live while I validate the new endpoint with synthetic
checks and real traffic. Depending on the load-balancer and DNS capabilities,
I would use weighted traffic splitting, or lower DNS TTLs followed by a
controlled DNS cutover. I would monitor the defined SLOs during each change
and retain the old Ingress and DNS target as the immediate rollback path.

I expect problems around nginx-specific annotations (rewrites, snippets,
auth, rate limits), TLS and certificate ownership, source-IP behaviour,
unsupported protocols, DNS caching, and hidden consumers of the old
load-balancer address. Once all routes have been stable through a defined
observation window, I would remove the old Ingress resources and finally
decommission ingress-nginx.
