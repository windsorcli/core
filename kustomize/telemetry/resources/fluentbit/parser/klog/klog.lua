-- klog parser for Kubernetes components
-- Format: <severity><MMDD> <HH:MM:SS.microseconds> <pid> <file>:<line>] <message>
-- Examples:
--   I0123 19:30:55.954002       1 shared_informer.go:356] "Caches are synced"
--   W0123 19:40:33.804067       1 logging.go:55] [core] grpc: message...
--   E0123 19:30:31.251850       1 reflector.go:158] "Unhandled Error" err="..."

-- OTEL severity number mapping (https://opentelemetry.io/docs/specs/otel/logs/data-model/#severity-fields)
local SEVERITY_MAP = {
  I = { text = "INFO",  number = 9 },
  W = { text = "WARN",  number = 13 },
  E = { text = "ERROR", number = 17 },
  D = { text = "DEBUG", number = 5 },
  F = { text = "FATAL", number = 21 }
}

function parse_klog(tag, timestamp, record)
  local log = record["log"]
  if not log then return 0, timestamp, record end

  -- Skip if already parsed (severity already set)
  if record["severity_text"] and record["severity_text"] ~= "" then
    return 0, timestamp, record
  end

  -- Match klog format: <sev><MMDD> <time> <pid> <file>:<line>] <msg>
  -- Pattern: single char + 4 digits + space + time
  local sev_char = log:sub(1, 1)
  local mmdd = log:sub(2, 5)

  -- Validate this is klog format
  if not SEVERITY_MAP[sev_char] or not mmdd:match("^%d%d%d%d$") then
    return 0, timestamp, record
  end

  -- Extract components
  local time_str, pid, file, line, msg = log:match(
    "^.%d%d%d%d%s+(%d%d:%d%d:%d%d%.%d+)%s+(%d+)%s+([^:]+):(%d+)%]%s*(.*)$"
  )

  if not msg then
    -- Fallback: just extract severity and treat rest as message
    msg = log:sub(22) -- Skip "X0123 HH:MM:SS.xxxxxx "
    if msg:match("^%s*%d+%s+") then
      msg = msg:match("^%s*%d+%s+(.*)$") or msg
    end
  end

  -- Set OTEL fields
  local sev = SEVERITY_MAP[sev_char]
  record["severity_text"] = sev.text
  record["severity_number"] = sev.number
  record["body"] = msg or log

  -- No body.* extraction - schema doesn't support dynamic fields

  return 1, timestamp, record
end
