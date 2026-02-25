# AGENTS.md

## Cursor Cloud specific instructions

### Overview

Windsor Core is an infrastructure-as-code repository containing reusable Terraform modules and Kustomize configurations for the [Windsor CLI](https://github.com/windsorcli/cli). There is no running application server — the "product" is the IaC modules themselves, validated via `terraform test` (mock providers, no cloud credentials needed) and `windsor test` (blueprint composition tests).

### Key tools

All CLI tools are version-pinned in `aqua.yaml`. Run `aqua i` (with `AQUA_DISABLE_COSIGN=true AQUA_DISABLE_SLSA=true` flags if SLSA verification fails) to install them.

### Windsor CLI from main branch

The released Windsor CLI (`v0.8.1`) does **not** include the `test` subcommand. Blueprint tests (`windsor test`) require a build from the `main` branch of `github.com/windsorcli/cli`. Build with:

```bash
cd /tmp && git clone --depth 1 https://github.com/windsorcli/cli.git windsor-cli
cd windsor-cli && go build -o /tmp/windsor-main ./cmd/windsor
sudo install -m 0755 /tmp/windsor-main /usr/local/bin/windsor
```

Before running `windsor test`, initialize the project: `windsor init local --reset` (required once per workspace to mark it as trusted).

### Development commands

All standard commands are documented in the repo `README.md` and `Taskfile.yaml`:

- `task fmt` — format Terraform code
- `task test` — run all tests (terraform + blueprint)
- `task test:terraform` — run Terraform unit tests only
- `task test:blueprint` — run Windsor blueprint tests only
- `task scan` — security scan (requires Python venv with checkov)
- `task docs` — generate Terraform docs (requires Docker)
- `yamllint .` — lint all YAML files

### Shell integration

The Windsor CLI uses a shell hook for dynamic environment variable injection. This is configured in `~/.bashrc`:

```bash
eval "$(windsor hook bash)"
```

The update script installs this automatically. It sets variables like `WINDSOR_PROJECT_ROOT`, `DOCKER_HOST`, `KUBECONFIG`, etc. when you `cd` into the project.

### Environment variable

Set `WINDSOR_PROJECT_ROOT=/workspace` when running Windsor or Task commands (the shell hook handles this automatically).

### Docker

Docker Engine is installed in the cloud VM for integration tests and `task docs`. The daemon starts via `sudo dockerd` (no systemd). Socket permissions are opened with `sudo chmod 666 /var/run/docker.sock` after daemon start.

### Gotchas

- `aqua i` may fail with SLSA verification errors. Use `AQUA_DISABLE_COSIGN=true AQUA_DISABLE_SLSA=true aqua i` as a workaround.
- Terraform tests run in parallel via `find | while read ... &`. Each module directory gets `terraform init` + `terraform test` independently.
- Integration tests (CI `integration` job) require Docker, Docker Compose, and significant disk space. These are not part of the standard dev loop.
- `task scan` requires a Python virtualenv at `.venv/` with `checkov` installed. This is optional for typical development.
- Docker daemon must be started manually in the cloud VM: `sudo dockerd &>/tmp/dockerd.log &` then `sudo chmod 666 /var/run/docker.sock`.
