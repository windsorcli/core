-- Envoy access log parser (JSON format, no level/severity field of its own)
-- Matches: Envoy Gateway / Envoy proxy access logs
--
-- Example:
-- {":authority":"grafana.test:8443","bytes_received":494,"bytes_sent":7347,
--  "downstream_remote_address":"10.244.0.1:51997","duration":74,"method":"POST",
--  "response_code":200,"response_flags":"-","route_name":"httproute/...",
--  "upstream_host":"10.244.0.45:3000","x-envoy-origin-path":"/api/ds/query",...}
--
-- Envoy fills unused fields with JSON null rather than omitting them (e.g. a
-- TCP/UDP passthrough has method=null). cjson decodes null as the cjson.null
-- sentinel, not Lua nil, so every field read here is type-checked rather than
-- just truth-tested - a bare `if data["method"] then` would treat a null
-- method as present.
--
-- Extracts OTEL semantic conventions; severity derived from HTTP status code
-- the same way nginx-access does.

local cjson_ok, cjson = pcall(require, "cjson.safe")

local function as_string(v)
  if type(v) == "string" then return v end
  return nil
end

local function as_number(v)
  if type(v) == "number" then return v end
  return nil
end

local function status_to_severity(code)
  if not code or code == 0 then
    -- 0 means no HTTP response was ever produced (e.g. connection failure,
    -- TCP/UDP passthrough) - treat as noteworthy, not routine.
    return "WARN", 13
  end
  if code >= 500 then
    return "ERROR", 17
  elseif code >= 400 then
    return "WARN", 13
  else
    return "INFO", 9
  end
end

function parse_envoy_access(tag, timestamp, record)
  local log = record["log"]
  if not log then return 0, timestamp, record end

  -- Skip if already parsed
  if record["severity_text"] and record["severity_text"] ~= "" then
    return 0, timestamp, record
  end

  if not log:match("^%s*{") then
    return 0, timestamp, record
  end

  if not cjson_ok then return 0, timestamp, record end
  local data = cjson.decode(log)
  if not data then return 0, timestamp, record end

  local status = as_number(data["response_code"])
  local response_flags = as_string(data["response_flags"])
  local downstream_addr = as_string(data["downstream_remote_address"])
  local upstream_cluster = as_string(data["upstream_cluster"])

  -- Recognize Envoy's access log shape - these fields together are distinctive
  if status == nil and response_flags == nil then
    return 0, timestamp, record
  end
  if downstream_addr == nil and upstream_cluster == nil then
    return 0, timestamp, record
  end

  local sev_text, sev_num = status_to_severity(status)
  record["severity_text"] = sev_text
  record["severity_number"] = sev_num

  local method = as_string(data["method"])
  local path = as_string(data["x-envoy-origin-path"])
  local upstream_host = as_string(data["upstream_host"])
  local duration = as_number(data["duration"])
  local route_name = as_string(data["route_name"])
  local protocol = as_string(data["protocol"])

  -- OTEL HTTP semantic attributes (prefixed for Fluentd to merge)
  if method then
    record["attr_http_request_method"] = method
  end
  if status then
    record["attr_http_response_status_code"] = status
  end
  if path then
    record["attr_url_path"] = path
  end
  if downstream_addr then
    record["attr_client_address"] = downstream_addr
  end
  if upstream_host then
    record["attr_server_address"] = upstream_host
  end
  if duration then
    record["attr_http_request_duration"] = duration
  end

  -- Build concise body: METHOD PATH STATUS DURATIONms (FLAGS)
  local body_parts = {}
  table.insert(body_parts, method or protocol or "-")
  table.insert(body_parts, path or route_name or "-")
  table.insert(body_parts, status and tostring(status) or "-")
  if duration then
    table.insert(body_parts, tostring(duration) .. "ms")
  end
  if response_flags and response_flags ~= "-" then
    table.insert(body_parts, "(" .. response_flags .. ")")
  end
  record["body"] = table.concat(body_parts, " ")

  return 1, timestamp, record
end
