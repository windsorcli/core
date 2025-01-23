#!/usr/bin/env sh

# Set the number of nodes to check for readiness. If not provided, default to the current number of nodes.
NODE_COUNT=${NODE_COUNT:-$(kubectl get nodes --no-headers 2>/dev/null | awk 'NF' | wc -l)}
# Set the timeout period in seconds. Default is 300 seconds (5 minutes).
TIMEOUT=${TIMEOUT:-300}
# Set the interval between readiness checks in seconds. Default is 10 seconds.
INTERVAL=${INTERVAL:-10}

# Record the start time of the script to calculate elapsed time later.
start_time=$(date +%s)
# Initialize the previous ready count to track changes in node readiness.
previous_ready_count=0

# Inform the user about the number of nodes expected to be ready.
echo "Waiting for $NODE_COUNT nodes to be ready"

# Continuously check the readiness of nodes.
while true; do
  # Attempt to get the list of nodes that are in the 'Ready' state.
  if ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 == "Ready" {print $1}'); then
    # Count the number of nodes that are ready.
    ready_count=$(echo "$ready_nodes" | awk 'NF' | wc -l)
  else
    # If the command fails, assume no nodes are ready.
    ready_count=0
  fi

  # If the number of ready nodes has changed, print the current status.
  if [ "$ready_count" -ne "$previous_ready_count" ]; then
    echo "$ready_count / $NODE_COUNT nodes are ready"
    previous_ready_count=$ready_count
  fi

  # If all nodes are ready, exit the script successfully.
  if [ "$ready_count" -eq "$NODE_COUNT" ]; then
    echo "All nodes are ready"
    exit 0
  fi

  # Calculate the elapsed time since the script started.
  current_time=$(date +%s)
  elapsed_time=$((current_time - start_time))

  # If the elapsed time exceeds the timeout, exit the script with an error.
  if [ "$elapsed_time" -ge "$TIMEOUT" ]; then
    echo "Timeout reached: Not all nodes are ready"
    exit 1
  fi

  # Wait for the specified interval before checking again.
  sleep "$INTERVAL"
done
