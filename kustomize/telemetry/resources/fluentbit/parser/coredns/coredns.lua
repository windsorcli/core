-- CoreDNS log parser
-- Formats:
--   [INFO] plugin/kubernetes: message
--   [WARNING] plugin/health: Local health request failed
--   [INFO] 10.244.0.56:49016 - 44622 "A IN example.com. udp 44 false 1232" NXDOMAIN qr,rd,ra 33 0.321674073s

-- OTEL severity number mapping
local SEVERITY_MAP = {
  INFO    = { text = "INFO",  number = 9 },
  WARNING = { text = "WARN",  number = 13 },
  ERROR   = { text = "ERROR", number = 17 },
  DEBUG   = { text = "DEBUG", number = 5 },
  FATAL   = { text = "FATAL", number = 21 }
}

function parse_coredns(tag, timestamp, record)
  local log = record["log"]
  if not log then return 0, timestamp, record end

  -- Skip if already parsed (severity already set)
  if record["severity_text"] and record["severity_text"] ~= "" then
    return 0, timestamp, record
  end

  -- Match CoreDNS format: [LEVEL] message
  local level, msg = log:match("^%[([A-Z]+)%]%s*(.*)$")

  if not level then
    return 0, timestamp, record
  end

  -- Validate this is a known CoreDNS severity
  local sev = SEVERITY_MAP[level]
  if not sev then
    return 0, timestamp, record
  end

  record["severity_text"] = sev.text
  record["severity_number"] = sev.number

  -- Parse plugin name if present
  local plugin, plugin_msg = msg:match("^plugin/([^:]+):%s*(.*)$")
  if plugin then
    -- No body.* extraction - schema doesn't support dynamic fields
    record["body"] = plugin_msg
  else
    -- Check for DNS query log format
    -- 10.244.0.56:49016 - 44622 "A IN example.com. udp 44 false 1232" NXDOMAIN qr,rd,ra 33 0.321s
    local client_ip, client_port, query_id, query, rcode, duration = msg:match(
      "^([%d%.]+):(%d+)%s+%-%s+(%d+)%s+\"([^\"]+)\"%s+(%S+)%s+%S+%s+%S+%s+([%d%.]+%a*)$"
    )

    if client_ip then
      record["body"] = query
      -- No body.* extraction - schema doesn't support dynamic fields

      -- Parse query details: "A IN example.com. udp 44 false 1232"
      local qtype, qclass, qname = query:match("^(%S+)%s+(%S+)%s+(%S+)")
      if qtype then
        -- No body.* extraction - schema doesn't support dynamic fields
      end
    else
      record["body"] = msg
    end
  end

  return 1, timestamp, record
end
