local context = std.extVar("context");
local hlp = std.extVar("helpers");

// Extracts local volume path from cluster.workers.volumes[0]
local volumes = hlp.getArray(context, "cluster.workers.volumes", []);
local raw_volume = if std.length(volumes) > 0 then volumes[0] else "";
local local_volume_path =
  if std.type(raw_volume) == "string" then
    (
      local split = std.split(raw_volume, ":");
      if std.length(split) > 1 then split[1] else split[0]
    )
  else
    "";

hlp.removeEmptyKeys({
  common: {
    external_domain: hlp.getString(context, "dns.domain", "test"),
  },
  csi: {
    local_volume_path: local_volume_path,
  },
  ingress: {
    loadbalancer_ip: hlp.getString(context, "network.loadbalancer_ips.start", ""),
  },
})
