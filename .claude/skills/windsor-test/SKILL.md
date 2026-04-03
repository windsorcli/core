---
name: windsor-test
description: Run and fix Windsor blueprint (facet) tests and Terraform module tests. Knows .test.yaml format, how windsor test works, and how to diagnose failures.
---

# Windsor Test

## Apply when
- Adding or modifying facets in `contexts/_template/facets/`
- Adding or modifying test cases in `contexts/_template/tests/`
- Modifying Terraform modules under `terraform/`
- A test is failing and needs diagnosis and fixing
- Asked to verify a feature is tested

## Running tests

```bash
task test                                        # all tests (terraform + blueprint)
task test:blueprint                              # windsor test — all .test.yaml files
task test:terraform                              # all terraform modules
task test:terraform -- terraform/cluster/talos  # specific terraform module
```

## Blueprint test file structure

Location: `contexts/_template/tests/<facet-name>.test.yaml`

```yaml
# <facet-name>.yaml facet tests
# One-line description of what this facet covers.

x-defaults:
  network: &default-network
    cidr_block: 10.5.0.0/16
    loadbalancer_driver: kube-vip
    loadbalancer_mode: arp
    loadbalancer_ips:
      start: "10.5.1.10"
      end: "10.5.1.100"

  cluster: &default-cluster
    driver: talos
    controlplanes:
      nodes:
        controlplane-1:
          endpoint: 10.5.0.10:50000
          node: 10.5.0.10
          hostname: controlplane-1
    workers:
      volumes:
        - /var/mnt/local

cases:
  - name: descriptive name of what this case proves
    values:
      provider: metal
      # ... blueprint values
    expect:
      kustomize:
        - name: kustomization-name
          path: some/path
          dependsOn:
            - other-kustomization
          components:
            - component-name
          timeout: 10m
          interval: 5m
    exclude:
      kustomize:
        - name: should-not-appear
```

## Writing good test cases

- **Minimal case first**: test the simplest enabled config, assert only what this facet produces
- **Cover conditions**: one case per meaningful branch (enabled, disabled, each conditional component)
- **Use anchors**: define `&default-network` and `&default-cluster` in `x-defaults` and reference with `*default-network`
- **Name cases clearly**: describe the scenario, not the implementation ("docker desktop uses nodeport" not "test case 3")
- **`expect`**: asserts exact match — every listed field must match, extra fields in output are fine
- **`exclude`**: asserts the named entry is absent from output — use to verify `when:` guards work
- **`terraformOutputs`**: include when the facet uses compute/workstation outputs (docker platform cases often need this)

## Common test patterns

### Testing a conditional component
```yaml
- name: private DNS enables coredns component
  values:
    provider: metal
    addons:
      private_dns:
        enabled: true
  expect:
    kustomize:
      - name: gateway-resources
        components:
          - nginx
          - nginx/coredns   # appears when private_dns enabled
          - nginx/web
```

### Testing a disabled feature
```yaml
- name: excludes gateway when disabled
  values:
    provider: metal
    gateway:
      enabled: false
  exclude:
    kustomize:
      - name: gateway-resources
```

### Testing docker-desktop nodeport selection
```yaml
- name: docker desktop uses nodeport
  values:
    platform: docker
    workstation:
      enabled: true
      runtime: docker-desktop
  terraformOutputs:
    compute:
      controlplanes:
        - endpoint: 10.5.0.10:6443
          node: 10.5.0.10
          hostname: controlplane-1
      workers: []
    workstation:
      registries: {}
  expect:
    kustomize:
      - name: gateway-resources
        components:
          - nginx/nodeport
```

## Diagnosing failures

`windsor test` reports the failing case name and the field mismatch. Common root causes:

| Symptom | Likely cause |
|---------|-------------|
| Component present but not expected | `when:` condition evaluates true unexpectedly |
| Component absent but expected | Expression bug (`??` default wrong, `==` mismatch) |
| Wrong `path` | Facet kustomize entry has wrong path string |
| Entire kustomization missing | `when:` guard blocks it; check effective values |
| Wrong component order | Components are order-sensitive; match facet order in test |

After fixing a facet, always run `task test:blueprint` to confirm. Fix and re-run until clean.
