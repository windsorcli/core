---
title: pki
description: Private certificate authority for in-cluster TLS and Talos apiserver OIDC trust.
stack_name: PKI
stack_backing: Root CA · OIDC trust
---

Root CA generation (or BYO passthrough) backing the private-CA add-on and
Talos apiserver OIDC trust. See [`pki/ca`](ca) for the module itself.

<!-- BEGIN_TERRAFORM_MODULES -->

## Modules

- [ca](ca/) — Root CA generation (or BYO passthrough) for the private-CA add-on and Talos apiserver OIDC trust.
<!-- END_TERRAFORM_MODULES -->
