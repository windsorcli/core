-- Envoy access log parser (JSON format, no level/severity field of its own)
-- Matches: Envoy Gateway / Envoy proxy access logs
--
-- Example:
-- {":authority":"grafana.test:8443","bytes_received":494,"bytes_sent":7347,
--  "downstream_remote_address":"10.244.0.1:51997","duration":74,"method":"POST",
--  "response_code":200,"response_flags":"-","route_name":"httproute/...",
--  "upstream_host":"10.244.0.45:3000","x-envoy-origin-path":"/api/ds/query",...}
--
-- No cjson: cjson.safe (and plain cjson) aren't present in this fluent-bit
-- build's LuaJIT ("module 'cjson.safe' not found" at runtime, confirmed on
-- the live cluster), so json-structured.lua's cjson_ok check is always
-- false here too, degrading it to the same kind of regex extraction below.
-- Envoy's access log JSON is flat (no nesting), so per-field pattern
-- matching on the raw string is reliable without a real parser.
--
-- Extracts OTEL semantic conventions; severity derived from HTTP status code
-- the same way nginx-access does.

local function escape_pattern(s)
  return (s:gsub("[%-%.%+%[%]%(%)%$%^%%%?%*]", "%%%1"))
end

-- Returns the string value of a JSON field, or nil if absent/null/non-string.
local function extract_string_field(json, field)
  return json:match('"' .. escape_pattern(field) .. '"%s*:%s*"([^"]*)"')
end

-- Returns the numeric value of a JSON field, or nil if absent/null/non-number.
local function extract_number_field(json, field)
  local s = json:match('"' .. escape_pattern(field) .. '"%s*:%s*(%-?%d+%.?%d*)')
  return s and tonumber(s)
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

  local status = extract_number_field(log, "response_code")
  local response_flags = extract_string_field(log, "response_flags")
  local downstream_addr = extract_string_field(log, "downstream_remote_address")
  local upstream_cluster = extract_string_field(log, "upstream_cluster")

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

  local method = extract_string_field(log, "method")
  local path = extract_string_field(log, "x-envoy-origin-path")
  local upstream_host = extract_string_field(log, "upstream_host")
  local duration = extract_number_field(log, "duration")
  local route_name = extract_string_field(log, "route_name")
  local protocol = extract_string_field(log, "protocol")

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
