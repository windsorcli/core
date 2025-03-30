# core
Core configurations used as the basis for most blueprints

![CI Workflow](https://github.com/your-repo/core/actions/workflows/ci.yaml/badge.svg)

# Blueprint.yaml

## Quickwit

```
- name: observability-base
  path: observability/base
- name: quickwit
  path: observability/quickwit
  dependsOn:
  - observability-base
  - pki-base
  components:
  - local-file
  ```

  ## Metrics Server
  ```
  - name: metrics-server-resources
  path: telemetry/resources
  components:
  - metrics-server
  ```

  ## FluentBit
  ```
  - name: fluentbit
  path: telemetry/base
  components:
  - fluentbit
- name: fluentbit-resources
  path: telemetry/resources
  components:
  - fluentbit
- name: metrics-server-resources
  path: telemetry/resources
  components:
  - metrics-server
  ```
  