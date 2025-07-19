local context = std.extVar("context");
local hlp = std.extVar("helpers");

// Extract worker count safely
local workerCount = hlp.getInt(context, "cluster.workers.count", null);

// Only output autoscaled_node_pool if worker count is populated
if workerCount != null then {
  autoscaled_node_pool: {
    min_count: workerCount,
    max_count: workerCount + 2,
  }
} else {}
