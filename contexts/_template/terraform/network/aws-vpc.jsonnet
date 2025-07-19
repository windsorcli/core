local context = std.extVar("context");
local hlp = std.extVar("helpers");

{
  cidr_block: hlp.getString(context, "network.cidr_block", "10.0.0.0/16"),
  domain_name: hlp.getString(context, "dns.domain", null),
}
