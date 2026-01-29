-- nginx-ingress access log parser
-- Handles both HTTP and Stream (TCP/UDP) log formats
--
-- HTTP Format: $remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent
--              "$http_referer" "$http_user_agent" $request_length $request_time
--              [$proxy_upstream_name] [$proxy_alternative_upstream_name]
--              $upstream_addr $upstream_response_length $upstream_response_time $upstream_status $req_id
--
-- Stream Format: [$remote_addr] [$time_local] $protocol $status $bytes_sent $bytes_received $session_time
--
-- HTTP Example:
-- 10.244.0.1 - - [23/Jan/2026:21:47:21 +0000] "POST /api/ds/query HTTP/2.0" 200 6129 "https://..." "Mozilla/5.0" 500 0.094 [system-observability-grafana-80] [] 10.244.0.98:3000 6142 0.094 200 abc123
--
-- Stream Example:
-- [10.244.0.1] [23/Jan/2026:22:39:25 +0000] UDP 200 58 30 0.004
--
-- Extracts OTEL semantic conventions

-- Severity based on HTTP status code
local function status_to_severity(status)
  local code = tonumber(status)
  if not code then return "INFO", 9 end

  if code >= 500 then
    return "ERROR", 17
  elseif code >= 400 then
    return "WARN", 13
  else
    return "INFO", 9
  end
end

function parse_nginx_access(tag, timestamp, record)
  local log = record["log"]
  if not log then return 0, timestamp, record end

  -- Skip if already parsed
  if record["severity_text"] and record["severity_text"] ~= "" then
    return 0, timestamp, record
  end

  -- Try Stream format first: [IP] [timestamp] PROTO STATUS bytes_sent bytes_recv duration
  local stream_ip, stream_proto, stream_status, bytes_sent, bytes_recv, session_time =
    log:match('^%[([%d%.]+)%]%s+%[[^%]]+%]%s+([A-Z]+)%s+(%d+)%s+(%d+)%s+(%d+)%s+([%d%.]+)')

  if stream_proto then
    local sev_text, sev_num = status_to_severity(stream_status)
    record["severity_text"] = sev_text
    record["severity_number"] = sev_num

    -- OTEL network semantic attributes
    record["attr_network_protocol_name"] = stream_proto:lower()
    record["attr_network_peer_address"] = stream_ip
    record["attr_http_response_status_code"] = tonumber(stream_status)
    record["attr_http_request_duration"] = tonumber(session_time)

    -- Build concise body: PROTO STATUS bytes duration
    record["body"] = string.format("%s %s %s/%sB %.3fs",
      stream_proto, stream_status, bytes_sent, bytes_recv, tonumber(session_time))

    return 1, timestamp, record
  end

  -- Match nginx combined log format with ingress extensions
  -- Pattern: IP - - [timestamp] "METHOD PATH PROTO" STATUS BYTES ...
  local client_ip, method, path, proto, status, bytes, request_time =
    log:match('^([%d%.]+)%s+%-%s+%-%s+%[[^%]]+%]%s+"([A-Z]+)%s+([^%s]+)%s+([^"]+)"%s+(%d+)%s+(%d+)%s+"[^"]*"%s+"[^"]*"%s+%d+%s+([%d%.]+)')

  if not method then
    -- Try simpler pattern without all extensions
    client_ip, method, path, proto, status, bytes =
      log:match('^([%d%.]+)%s+%-%s+%-%s+%[[^%]]+%]%s+"([A-Z]+)%s+([^%s]+)%s+([^"]+)"%s+(%d+)%s+(%d+)')
  end

  if not method then
    return 0, timestamp, record
  end

  -- Set severity based on status code
  local sev_text, sev_num = status_to_severity(status)
  record["severity_text"] = sev_text
  record["severity_number"] = sev_num

  -- Extract upstream info if present
  local upstream_name = log:match('%[([^%]]+)%]%s+%[')
  local upstream_status = log:match('%s+(%d+)%s+[a-f0-9]+$')

  -- Strip query params from path for cleaner display
  local clean_path = path:match('^([^?]+)') or path

  -- OTEL HTTP semantic attributes (prefixed for Fluentd to merge)
  record["attr_http_request_method"] = method
  record["attr_http_response_status_code"] = tonumber(status)
  record["attr_url_path"] = clean_path
  record["attr_client_address"] = client_ip
  if request_time then
    record["attr_http_request_duration"] = tonumber(request_time)
  end
  if upstream_name and upstream_name ~= "" then
    record["attr_server_address"] = upstream_name
  end

  -- Build concise body: METHOD PATH STATUS TIME
  local body_parts = { method, clean_path, status }
  if request_time then
    table.insert(body_parts, string.format("%.3fs", tonumber(request_time)))
  end
  if upstream_name and upstream_name ~= "" then
    table.insert(body_parts, "→ " .. upstream_name)
  end
  if upstream_status and upstream_status ~= status then
    table.insert(body_parts, "(" .. upstream_status .. ")")
  end
  record["body"] = table.concat(body_parts, " ")

  return 1, timestamp, record
end
