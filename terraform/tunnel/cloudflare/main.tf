# =============================================================================
# Provider Configuration
# =============================================================================

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.29.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
  }
}

provider "cloudflare" {}

# =============================================================================
# Zone Lookup
# =============================================================================

# The zone that holds public_domain. It is public_domain itself unless zone_name names a parent zone.
data "cloudflare_zone" "this" {
  filter = {
    name = coalesce(var.zone_name, var.public_domain)
    account = {
      id = var.account_id
    }
  }
}

# =============================================================================
# Tunnel
# =============================================================================

# The tunnel secret is the credential inside the tunnel token. A new secret_version generates a new one.
resource "random_id" "tunnel_secret" {
  byte_length = 32

  keepers = {
    secret_version = var.secret_version
  }

  lifecycle {
    create_before_destroy = true
  }
}

# The tunnel is a remotely managed Cloudflare Tunnel. Its name carries secret_version so a replacement does not collide with the tunnel it replaces.
resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  account_id    = var.account_id
  name          = "${var.name}-${var.secret_version}"
  config_src    = "cloudflare"
  tunnel_secret = random_id.tunnel_secret.b64_std

  lifecycle {
    create_before_destroy = true
  }
}

# The remote configuration routes every hostname under public_domain to the origin service.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id

  config = {
    ingress = [
      {
        hostname = "*.${var.public_domain}"
        service  = var.origin_service
        origin_request = {
          match_sn_ito_host = true
          ca_pool           = var.origin_ca_pool
        }
      },
      {
        service = "http_status:404"
      }
    ]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# The token is what cloudflared runs with. It cannot change routes or read other tunnels.
data "cloudflare_zero_trust_tunnel_cloudflared_token" "this" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

# =============================================================================
# DNS
# =============================================================================

# The wildcard record points every hostname under public_domain at the tunnel.
resource "cloudflare_dns_record" "wildcard" {
  zone_id = data.cloudflare_zone.this.id
  name    = "*.${var.public_domain}"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1

  lifecycle {
    create_before_destroy = true
  }
}
