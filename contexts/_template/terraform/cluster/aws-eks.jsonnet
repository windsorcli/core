local context = std.extVar("context");
local hlp = std.extVar("helpers");

// Extract worker count safely
local workerCount = hlp.getInt(context, "cluster.workers.count", null);

// Only output node_groups if worker count is populated
if workerCount != null then {
  node_groups: {
    default: {
      instance_types: ["t3.xlarge"],
      min_size: workerCount,
      max_size: workerCount + 2,
      desired_size: workerCount,
    }
  }
} else {} 
