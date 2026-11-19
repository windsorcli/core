---
title: Tunnel
description: Tunnel credentials and routes that connect the external gateway to the internet.
stack_name: Tunnel
stack_backing: Cloudflare Tunnel
---

# Tunnel

The tunnel category has one driver, `cloudflare`. It provisions the
tunnel, its routes, and the wildcard DNS record, and outputs the token
that the in-cluster connector runs with. The stack only runs when
`tunnel.driver` is `cloudflare`.

<!-- BEGIN_TERRAFORM_MODULES -->

## Modules

- [cloudflare](cloudflare/) — Cloudflare Tunnel, remote configuration, and wildcard DNS record for the external gateway.
<!-- END_TERRAFORM_MODULES -->
