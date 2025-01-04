# The Windsor Blueprint

<p align="center">
  <img src="docs/img/windsor-logo.png" alt="Windsor CLI Logo" style="width: 20%; height: auto;">
</p>

<p align="center">
  <img src="https://img.shields.io/github/v/release/windsorcli/cli" alt="GitHub release (latest by date)">
  <img src="https://img.shields.io/github/actions/workflow/status/windsorcli/blueprint/ci.yaml" alt="GitHub Workflow Status">
</p>

---

## Purpose

The Windsor Blueprint repository is a repository that serves as both a github template repository for creating new blueprints and a base level test source for testing blueprints.  New repositories can be created using this repository as the template while the github actions that are part of the initial template refer back to the template to run many base level checks.  Because of this relationship, the newly created repository will also include a backwards watch to the blueprint repository to automatically kick off new tests and update when this repository (base class) is changed.

## Blueprint Guidelines

See the [Blueprint Guidelines Document](./docs/guides/blueprint.md) for detailed description of the blueprint

## Quick Start

- **[Setup and Installation](https://windsorcli.github.io/latest/install/install/)**

## Supported Tools

The following tools are supported by the Windsor Blueprint:

- [**Docker**](https://github.com/docker/docker-ce)
- [**Kubernetes**](https://github.com/kubernetes/kubernetes)
- [**AWS**](https://github.com/aws/aws-cli)
- [**Terraform**](https://github.com/hashicorp/terraform)
- [**SOPS**](https://github.com/mozilla/sops)
- [**Localstack**](https://github.com/localstack/localstack)
- [**Colima**](https://github.com/abiosoft/colima)
- [**Talos Linux**](https://github.com/siderolabs/talos)

## Contributing

Contributions are welcome! To get started, fork the repository, create a new branch, make your changes, and submit a pull request. Ensure your code follows our standards and includes tests. Thank you for your contributions!

## License

Windsor CLI is licensed under the Mozilla Public License Version 2.0. See the [LICENSE](LICENSE) file for more details.

## Contact Information

If you have any questions or need further assistance, please feel free to open an issue on our GitHub repository.
