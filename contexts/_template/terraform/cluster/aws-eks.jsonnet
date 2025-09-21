local context = std.extVar("context");
local hlp = std.extVar("helpers");

// Extract worker configuration safely
local workerCount = hlp.getInt(context, "cluster.workers.count", null);
local workerInstanceType = hlp.getString(context, "cluster.workers.instance_type", "t3.xlarge");

// Only output node_groups if worker count is populated
if workerCount != null then {
  node_groups: {
    default: {
      instance_types: [workerInstanceType],
      min_size: workerCount,
      max_size: workerCount + 2,
      desired_size: workerCount,
    }
  }
} else {} 
