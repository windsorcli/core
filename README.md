# core
Core Terraform modules and Kubernetes configurations used by [Windsor CLI](https://github.com/windsorcli/cli) to provision and manage infrastructure across multiple cloud providers.

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
  
## Contributing

This project uses several tools to maintain code quality and consistency:

- [aqua](https://aquaproj.github.io/) for CLI tool management
- [Task](https://taskfile.dev/) for build automation
- [lefthook](https://github.com/evilmartians/lefthook) for git hooks

### Setup

1. Install [aqua](https://aquaproj.github.io/docs/overview/getting-started)

2. Install project dependencies:
```bash
aqua i
```

3. Install git hooks:
```bash
lefthook install
```

### Development Workflow

- `task fmt` - Format Terraform code
- `task test` - Run Terraform tests
- `task docs` - Generate Terraform documentation
- `task scan` - Run security scans

Git hooks will automatically:
- Format code on commit
- Run tests and generate docs before push
