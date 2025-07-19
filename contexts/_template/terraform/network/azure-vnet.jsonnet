local context = std.extVar("context");
local hlp = std.extVar("helpers");

{
  vnet_cidr: hlp.getString(context, "network.cidr_block", "10.0.0.0/16"),
} 
