---
title: "ADR-0022: Chart-owned listeners on a gateway through ListenerSet"
description: Let a chart attach its own listeners to the external or internal gateway with a Gateway API ListenerSet, let a gateway give up its web-https listener, and let a gateway exist without its domain.
---

# ADR-0022: Chart-owned listeners on a gateway through ListenerSet

## Status

Proposed (2026-11-03). Extends [ADR-0019](0019-explicit-endpoints-dhcp-and-tls-sources.md),
which gave each gateway its own `service_type`, `ip`, and TLS source.

## Context

Each Gateway owns all of its listeners. `kustomize/gateway/resources/gateway.yaml`
defines `web-http` on port 80 and `web-https` on port 443, and both accept only
`HTTPRoute`. The internal gateway also gets `dns-udp` and `dns-tcp` on 53 and
`flux-webhook` on 9292, all added by core patches.

A downstream application chart needs listeners on a gateway address for its own
ports, 443 and 3010, and terminates TLS in its pods. Core cannot express that:

- No chart can add a listener to a core Gateway.
- `web-https` holds 443 with `tls.mode: Terminate`. A TLS passthrough listener
  on 443 conflicts with it on protocol, and the Gateway's own listener wins.
- The external gateway exists only when `dns.public_domain` is set, and the
  internal gateway only when `dns.private_domain` is set. An application that
  brings its own hostnames and certificates still has to give core a domain.

Gateway API answers the first point with `ListenerSet`: a namespaced resource
whose listeners attach to a parent Gateway that opts in through
`spec.allowedListeners`.

### Evidence from the pinned versions

Core pins Gateway API 1.6.2, the Envoy Gateway CRDs 1.9.2 (chart 1.9.3), and
Cilium 1.20.3.

**Gateway API 1.6.2.** `ListenerSet`, `TCPRoute`, `TLSRoute`, and `UDPRoute` are
in the standard channel at `v1`. The release's `standard-install.yaml` defines
`listenersets.gateway.networking.k8s.io` and `tcproutes.gateway.networking.k8s.io`
with `name: v1`, and its Gateway CRD has `spec.allowedListeners.namespaces.from`
with the values `All`, `Selector`, `Same`, and `None`, default `None`. Core's
vendored `gateway-api-experimental-1.6.2` bundle is a superset, so nothing new
needs vendoring.

**Envoy Gateway 1.9.2.** The controller watches `gateway.networking.k8s.io/v1`
`ListenerSet` whenever its CRD exists, with no feature flag
(`internal/provider/kubernetes/controller.go`). The 1.7.0 release notes list
HTTPRoute, GRPCRoute, TLSRoute, TCPRoute, and UDPRoute as route types on a
ListenerSet listener. The 1.8.0 notes move the informer to the standard `v1`
kind. The 1.9.0 notes fix listener precedence: listeners on the Gateway win over
ListenerSet listeners on a hostname or protocol conflict. The repository's e2e
suite has `listenerset-tcp.yaml` and `listenerset-tls-passthrough.yaml` test
data.

**Cilium 1.20.3.** The changelog adds ListenerSet support (cilium/cilium#46303)
and TCPRoute and UDPRoute support (cilium/cilium#46184), and moves both routes to
`v1` (cilium/cilium#46970). `Documentation/network/servicemesh/gateway-api/listenerset.rst`
says that Cilium supports the standard API with no separate flag, and that
TCPRoute and UDPRoute can target ListenerSet listeners. The operator detects the
ListenerSet CRD when it starts. Core already applies the Gateway API CRDs from
the `crds` layer ahead of `cni`, so the CRD is present at operator start. The
translator merges every listener of a Gateway, ListenerSet listeners included,
into the ports of that Gateway's one LoadBalancer Service
(`operator/pkg/model/translation/gateway-api/translator.go`). TCPRoute is not
supported in Cilium's host network mode, which core does not use.

Both drivers support a ListenerSet and a TCPRoute on one gateway address. That
finding comes from source, release notes, and upstream tests. Core has not yet
run TCP passthrough on two ports at one address on a live cluster; see
[Open questions](#open-questions).

**Envoy NodePort gateways.** The `envoy/nodeport` component replaces the Envoy
Service's port list with a JSON merge patch that names only 80 and 443. A
ListenerSet port such as 3010 never reaches that Service.

## Decision

### 1. `listener_namespaces` per gateway

`gateway.external.listener_namespaces` and `gateway.internal.listener_namespaces`
list the namespaces whose ListenerSets MAY attach to that Gateway. The default
is an empty list, which admits none, as today.

```yaml
gateway:
  external:
    ip: 10.30.0.20
    https: false
    listener_namespaces:
      - app
```

Core renders the list as a `Selector` on the `kubernetes.io/metadata.name`
label, which Kubernetes sets on every namespace:

```yaml
spec:
  allowedListeners:
    namespaces:
      from: Selector
      selector:
        matchExpressions:
          - key: kubernetes.io/metadata.name
            operator: In
            values: [app]
```

The schema names the namespaces instead of exposing the API's `from` values.
`Same` would admit only `system-gateway`, where no chart deploys. `All` would
let any namespace claim a port on the gateway address, including 443 on the
external gateway. A list admits exactly the charts the site approves, and a new
chart in another namespace needs a `values.yaml` change before it can attach.

A chart's ListenerSet names the gateway as its parent:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: ListenerSet
metadata:
  name: app
  namespace: app
spec:
  parentRef:
    kind: Gateway
    name: external
    namespace: system-gateway
  listeners:
    - name: app-tls
      protocol: TLS
      port: 443
      tls:
        mode: Passthrough
    - name: app-3010
      protocol: TCP
      port: 3010
```

`listener_namespaces` MUST NOT be set on a NodePort gateway, because the Envoy
NodePort Service drops every port but 80 and 443. A `requires` rule rejects it
on both drivers.

### 2. `https: false` removes `web-https`

`gateway.<name>.https` defaults to `true`. When it is `false`, the Gateway has no
`web-https` listener, so a ListenerSet can take 443 with any protocol. `web-http`
stays on 80, with its redirect to HTTPS. Without `web-https`, the gateway gets no
certificate and no catch-all 404 route, since both bind to that listener.

`gateway.<name>.tls.cert` and `gateway.<name>.tls.issuer` MUST NOT be set on a
gateway with `https: false`. A `requires` rule rejects them.

`https: false` MUST be paired with a non-empty `listener_namespaces`.
Without a ListenerSet on 443, the `web-http` redirect would point at a port with
no listener. A `requires` rule rejects the pairing.

### 3. A gateway exists without its domain when it admits listeners

A gateway exists when its domain is set, as today, or when its
`listener_namespaces` is not empty. A gateway without a domain publishes no DNS
records: it gets no catch-all 404 hostname annotation and no CoreDNS listeners.

The issue asked for a gateway that exists whenever it has an `ip`. Workstation
contexts set `gateway.external.ip` by default, so that rule would start an
external Envoy proxy on every workstation. `listener_namespaces` is the setting
that states the intent.

A gateway without a domain has no names for cert-manager to issue a certificate
for. It MUST either set `https: false` or supply `gateway.<name>.tls.cert`. A
`requires` rule rejects other combinations. The address rules from ADR-0019
still apply. On metal, vsphere, hyperv, incus, and proxmox, a LoadBalancer
gateway needs `gateway.<name>.ip`.

Hetzner has no internal gateway, so `gateway.internal.listener_namespaces` is
rejected there.

### 4. Driver support

Both drivers support ListenerSet at the pinned versions, so no `requires` rule
rejects the setting by driver.

## Consequences

- Charts attach listeners to a core Gateway without patching core.
- A chart that takes 443 on a gateway with `https: false` owns every hostname on
  443 there. Core HTTPRoutes on that gateway, such as Keycloak's, attach only to
  `web-http`, whose redirect sends clients to the chart's listener.
- `values.yaml` gains two fields per gateway. Existing contexts render the same
  Gateway as before.
- Facets that need a gateway with a hostname keep testing the domain. The
  gateway facet tests the new `gateway_effective.external_enabled` and
  `gateway_effective.internal_enabled` values for whether a Gateway exists.

## Alternatives considered

### Terminate at the gateway and re-encrypt with BackendTLSPolicy

The gateway terminates TLS on `web-https` with a supplied certificate
(`gateway.<name>.tls.cert`), an HTTPRoute sends traffic to the application, and
a `BackendTLSPolicy` makes the gateway open a second TLS connection to the pods.
Core already uses that pattern for Keycloak. It needs no new listener on 443 and
keeps core's catch-all 404.

It does not meet this application's needs. TLS ends at the gateway, so the pods
never see the client's TLS session, and the application cannot serve a protocol
other than HTTP on 443. Port 3010 still needs a listener of its own. Charts that
serve HTTP and accept TLS from the gateway SHOULD keep using this pattern.

### Core-owned listener patches per chart

Core could add a component per application port. Every new application would
need a core change.

## Open questions

- TCP passthrough on two ports at one address, with TLS that terminates in the
  pods, has not been run on a live cluster with either driver. The ADR stays
  Proposed until it has.

## References

- [Gateway API ListenerSet guide](https://gateway-api.sigs.k8s.io/guides/user-guides/listener-set/)
- [Gateway API v1.6.2 standard install](https://github.com/kubernetes-sigs/gateway-api/releases/tag/v1.6.2)
- [Envoy Gateway v1.9.2](https://github.com/envoyproxy/gateway/tree/v1.9.2)
- [Cilium v1.20.3 ListenerSet docs](https://github.com/cilium/cilium/blob/v1.20.3/Documentation/network/servicemesh/gateway-api/listenerset.rst)
- [windsorcli/core#3314](https://github.com/windsorcli/core/issues/3314)
