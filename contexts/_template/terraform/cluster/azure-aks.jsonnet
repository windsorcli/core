local context = std.extVar("context");
local hlp = std.extVar("helpers");

// Extract worker configuration safely
local workerCount = hlp.getInt(context, "cluster.workers.count", null);
local workerInstanceType = hlp.getString(context, "cluster.workers.instance_type", "Standard_D4s_v3");

// Only output autoscaled_node_pool if worker count is populated
if workerCount != null then {
  autoscaled_node_pool: {
    vm_size: workerInstanceType,
    min_count: workerCount,
    max_count: workerCount + 2,
  }
} else {}
