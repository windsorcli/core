// Import the helper library and context
local hlp = std.extVar("helpers");
local context = std.extVar("context");

// Get basic configuration using helper functions
local vmDriver = hlp.getString(context, "vm.driver", "");
local provider = hlp.getString(context, "provider", "");

// Get cluster configuration safely
local cluster = hlp.getObject(context, "cluster", {});
local controlplaneNodes = hlp.getObject(context, "cluster.controlplanes.nodes", {});
local workerNodes = hlp.getObject(context, "cluster.workers.nodes", {});

// Get first controlplane node safely
local nodeList = std.objectValues(controlplaneNodes);
local firstNode = if std.length(nodeList) > 0 then nodeList[0] else null;

// Get endpoint using helpers
local clusterEndpoint = hlp.getString(context, "cluster.endpoint", "");
local nodeEndpoint = if firstNode != null then hlp.getString(firstNode, "endpoint", "") else "";
local endpoint = if clusterEndpoint != "" then clusterEndpoint else nodeEndpoint;
local baseUrl = hlp.baseUrl(endpoint);

// Build certSANs using helpers
local hostname = if firstNode != null then hlp.getString(firstNode, "hostname", "") else "";
local domain = hlp.getString(context, "dns.domain", "");
local domainSAN = if hostname != "" && domain != "" then hostname + "." + domain else "";

local baseCertSANs = ["localhost"];
local urlSAN = if baseUrl != "" then [baseUrl] else [];
local hostSAN = if hostname != "" then [hostname] else [];
local domainSANList = if domainSAN != "" then [domainSAN] else [];
local certSANs = baseCertSANs + urlSAN + hostSAN + domainSANList;

// Build registry mirrors
local registries = hlp.getObject(context, "docker.registries", {});
local registryKeys = std.objectFields(registries);

local buildMirror(key) = 
  local registryInfo = registries[key];
  if std.objectHas(registryInfo, "hostname") && registryInfo.hostname != "" then
    local localOverride = if std.objectHas(registryInfo, "local") then
      local parts = std.split(registryInfo["local"], "//");
      if std.length(parts) > 1 then parts[1] else registryInfo["local"]
    else "";
    local targetRegistry = if localOverride != "" then localOverride else key;
    {
      key: targetRegistry,
      endpoints: ["http://" + registryInfo.hostname + ":5000"]
    }
  else
    null;

local validMirrors = std.filter(function(x) x != null, std.map(buildMirror, registryKeys));
local registryMirrors = std.foldl(
  function(acc, mirror) acc { [mirror.key]: { endpoints: mirror.endpoints } },
  validMirrors,
  {}
);

// Build network config
local needsNetworkConfig = provider == "local" && vmDriver == "docker-desktop";
local networkConfig = if needsNetworkConfig then
  {
    interfaces: [
      {
        ignore: true,
        interface: "eth0"
      }
    ]
  }
else
  {};

// Build base machine config
local baseMachineConfig = {
  certSANs: certSANs,
  kubelet: {
    extraArgs: {
      "rotate-server-certificates": "true"
    }
  }
} + (if needsNetworkConfig then { network: networkConfig } else {});

// Add registries if they exist
local machineConfig = baseMachineConfig + (
  if std.length(std.objectFields(registryMirrors)) > 0 then {
    registries: {
      mirrors: registryMirrors
    }
  } else {}
);

// Build common config patches
local commonConfig = {
  cluster: {
    apiServer: {
      certSANs: certSANs
    },
    extraManifests: [
      "https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/v0.8.7/deploy/standalone-install.yaml"
    ]
  },
  machine: machineConfig
};

// Helper for volume mounts
local createMount(volume) = 
  local parts = std.split(volume, ":");
  {
    destination: parts[1],
    type: "bind",
    source: parts[1],
    options: ["rbind", "rw"]
  };

// Worker config patches using helpers
local workerVolumes = hlp.getArray(context, "cluster.workers.volumes", []);
local workerMounts = if std.length(workerVolumes) > 0 then std.map(createMount, workerVolumes) else [];
local workerConfig = if std.length(workerMounts) > 0 then
  {
    machine: {
      kubelet: {
        extraMounts: workerMounts
      }
    }
  }
else
  {};

// Controlplane config patches using helpers
local controlplaneVolumes = hlp.getArray(context, "cluster.controlplanes.volumes", []);
local controlplaneMounts = if std.length(controlplaneVolumes) > 0 then std.map(createMount, controlplaneVolumes) else [];
local controlplaneConfig = if std.length(controlplaneMounts) > 0 then
  {
    machine: {
      kubelet: {
        extraMounts: controlplaneMounts
      }
    }
  }
else
  {};

// Build node lists
local controlplaneList = std.map(
  function(v) { endpoint: v.endpoint, node: v.node },
  std.objectValues(controlplaneNodes)
);

local workerList = std.map(
  function(v) { endpoint: v.endpoint, node: v.node },
  std.objectValues(workerNodes)
);

// Final output
{
  cluster_endpoint: if endpoint != "" then "https://" + baseUrl + ":6443" else "",
  cluster_name: "talos",
  controlplanes: controlplaneList,
  workers: workerList,
  common_config_patches: std.manifestYamlDoc(commonConfig)
} + (if std.length(std.objectFields(workerConfig)) > 0 then {
  worker_config_patches: std.manifestYamlDoc(workerConfig)
} else {}) + (if std.length(std.objectFields(controlplaneConfig)) > 0 then {
  controlplane_config_patches: std.manifestYamlDoc(controlplaneConfig)
} else {}) 
