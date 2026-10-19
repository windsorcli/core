# Split-horizon DNS plan

Let `dns.public_domain` and `dns.private_domain` name the same domain, so a
hostname such as `my-app.example.com` resolves to the `internal` Gateway inside
the network and to the `external` Gateway from the internet. Scope is the
`cloud` private DNS driver on AWS, Azure, and GCP.

Today the two domains MUST differ, and `platform-base` rejects a match at
composition. The gateway split plan lists the same-domain case as not
supported. This plan lifts that rejection for the `cloud` driver.

## Values

```yaml
dns:
  public_domain: example.com
  private_domain: example.com      # same name: public and private zones
  private:
    driver: cloud
```

No new key is needed. Matching domains with `dns.private.driver: cloud` turn on
split-horizon. Matching domains with any other driver stay rejected.

## Gaps

### Record selection by Gateway

Each external-dns instance decides which routes to publish by `domainFilters`
alone. The `gateway-httproute` source carries no Gateway filter, so
`external-dns-public` and `external-dns-private` stay apart only because
their domains differ. With one domain, both instances would publish every
route into both zones.

Each instance MUST select routes by parent Gateway, using external-dns's
`--gateway-name` and `--gateway-namespace` flags (`external` or `internal` in
`system-gateway`).

### Zone pinning

Each instance MUST write only to its own zone when a public and a private
zone share a name.

| Platform | Current state | Change |
|---|---|---|
| AWS | `zoneType` plus `--zone-id-filter` pin each instance to its hosted zone. | None. |
| Azure | The public instance uses the `azure` provider and the private one `azure-private-dns`. | Verify the two zones resolve to distinct resources in Terraform. |
| GCP | Both instances use the `google` provider with the same `txt_owner_id`. | Add `--google-zone-visibility` per instance, and give each instance its own TXT owner ID. |

### Shadowed external routes

Inside the network, the private zone answers for the whole domain. A route
attached only to `external` then has no record for internal clients, because
private zones on all three clouds do not fall through to the public zone by
default.

The private instance MUST publish every route on either Gateway, pointing at
`internal` when the route attaches to it and at `external` otherwise. Pinning
it to the `internal` Gateway alone is not enough; this needs either a second
source on the private instance or a policy that copies external-only records.

### Internal certificate

The `internal` Gateway takes its certificate from the `private` issuer. With a
shared hostname, an internal client without the private CA installed gets a
certificate warning for a name that works from outside.

With matching domains, `internal` SHOULD use the public issuer
(`public-acme`). The DNS-01 challenge for the domain already runs against the
public zone.

### CoreDNS driver

On local and metal clusters every client queries the same CoreDNS, so there
are no inside and outside views to separate. `coredns/public-zone` would also
add the same zone to the CoreDNS server block twice, which CoreDNS refuses to
serve. Matching domains MUST stay rejected for `dns.private.driver: coredns`.

## Slices

Each slice is one PR and leaves every platform composing and passing
`windsor test`.

1. Gateway filters on both external-dns instances on all clouds. This is safe
   with distinct domains and is a prerequisite for the rest.
2. GCP zone visibility and per-instance TXT owner IDs. Verify Azure zone
   separation.
3. External-only route publishing into the private zone.
4. Public issuer for `internal` when the domains match.
5. Narrow the `platform-base` rejection to non-`cloud` drivers. Update the DNS
   and gateway guides.

## Open questions

- Whether the private instance publishes external-only routes at the
  `external` load balancer address or omits them and documents the gap.
