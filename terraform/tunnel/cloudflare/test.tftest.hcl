mock_provider "cloudflare" {
  override_data {
    target = data.cloudflare_zone.this
    values = {
      id = "zone-123"
    }
  }
}
mock_provider "random" {}

variables {
  account_id     = "acct123"
  public_domain  = "apps.example.com"
  origin_service = "https://envoy-external.system-gateway.svc.cluster.local:443"
}

run "routes_the_wildcard_to_the_origin" {
  command = plan

  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress[0].hostname == "*.apps.example.com"
    error_message = "The first ingress rule should match the wildcard under public_domain."
  }

  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress[0].service == "https://envoy-external.system-gateway.svc.cluster.local:443"
    error_message = "The wildcard rule should forward to origin_service."
  }

  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress[1].service == "http_status:404"
    error_message = "The catch-all rule should return 404."
  }
}

run "verifies_the_origin_certificate" {
  command = plan

  variables {
    origin_ca_pool = "/etc/tunnel/ca/ca.crt"
  }

  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress[0].origin_request.match_sn_ito_host == true
    error_message = "SNI should match each request host."
  }

  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress[0].origin_request.ca_pool == "/etc/tunnel/ca/ca.crt"
    error_message = "origin_ca_pool should reach the origin request settings."
  }

  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress[0].origin_request.no_tls_verify == null
    error_message = "The module must not set no_tls_verify."
  }
}

run "writes_a_proxied_wildcard_record" {
  command = plan

  assert {
    condition     = cloudflare_dns_record.wildcard.zone_id == "zone-123"
    error_message = "The record should go in the zone the lookup returns."
  }

  assert {
    condition     = cloudflare_dns_record.wildcard.name == "*.apps.example.com" && cloudflare_dns_record.wildcard.type == "CNAME" && cloudflare_dns_record.wildcard.proxied == true
    error_message = "The record should be a proxied wildcard CNAME."
  }
}

run "looks_up_the_parent_zone" {
  command = plan

  variables {
    zone_name = "example.com"
  }

  assert {
    condition     = data.cloudflare_zone.this.filter.name == "example.com" && data.cloudflare_zone.this.filter.account.id == "acct123"
    error_message = "The zone lookup should use zone_name inside the account."
  }
}

run "tunnel_name_carries_the_secret_version" {
  command = plan

  variables {
    name           = "ctx"
    secret_version = 2
  }

  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared.this.name == "ctx-2" && cloudflare_zero_trust_tunnel_cloudflared.this.config_src == "cloudflare"
    error_message = "The tunnel should be remotely managed and named with the secret version."
  }

  assert {
    condition     = random_id.tunnel_secret.keepers.secret_version == "2"
    error_message = "secret_version should feed the secret keepers."
  }
}

run "rejects_an_http_origin" {
  command = plan

  variables {
    origin_service = "http://envoy-external.system-gateway.svc:80"
  }

  expect_failures = [var.origin_service]
}

run "rejects_an_empty_account" {
  command = plan

  variables {
    account_id = " "
  }

  expect_failures = [var.account_id]
}

run "rejects_a_wildcard_domain" {
  command = plan

  variables {
    public_domain = "*.example.com"
  }

  expect_failures = [var.public_domain]
}
