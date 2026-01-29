function extract_service_name(tag, timestamp, record)
  local k = record["kubernetes"]
  if not k then return 0, timestamp, record end

  -- Extract service name from pod_name by stripping replicaset/pod suffix
  -- e.g., "source-controller-7d9859db54-s24pw" -> "source-controller"
  local pod = k["pod_name"]
  if pod then
    -- Strip replicaset hash and pod suffix (deployment pattern: name-hash-hash)
    local service = pod:match("^(.+)%-[a-z0-9]+%-[a-z0-9]+$")
    -- StatefulSet pattern: name-0, name-1
    if not service then
      service = pod:match("^(.+)%-[0-9]+$")
    end
    -- DaemonSet/Job pattern: name-hash
    if not service then
      service = pod:match("^(.+)%-[a-z0-9]+$")
    end
    record["service_name"] = service or pod
  end

  return 1, timestamp, record
end
