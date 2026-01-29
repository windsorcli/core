-- Logfmt log parser
-- Format: key=value key2="value with spaces" key3=value3
-- Examples:
--   ts=2026-01-23T21:04:56.097Z level=info caller=/go/pkg/mod/... msg="Warning: v1 Endpoints..."
--   level=error time=2026-01-23T21:00:00Z msg="connection failed" err="timeout"
--
-- Common in: Go services (client-go, controller-runtime, etc.)

-- OTEL severity number mapping
local SEVERITY_MAP = {
  TRACE = { text = "TRACE", number = 1 },
  DEBUG = { text = "DEBUG", number = 5 },
  INFO  = { text = "INFO",  number = 9 },
  WARN  = { text = "WARN",  number = 13 },
  ERROR = { text = "ERROR", number = 17 },
  FATAL = { text = "FATAL", number = 21 }
}

local LEVEL_ALIASES = {
  warning = "WARN",
  warn = "WARN",
  critical = "FATAL",
  panic = "FATAL"
}

function parse_logfmt(tag, timestamp, record)
  local log = record["log"]
  if not log then return 0, timestamp, record end

  -- Skip if already parsed
  if record["severity_text"] and record["severity_text"] ~= "" then
    return 0, timestamp, record
  end

  -- Skip JSON logs
  if log:match("^%s*{") then
    return 0, timestamp, record
  end

  -- Match logfmt: level= or level:
  local level = log:match('level[=:]%s*"?([a-zA-Z]+)"?')
  if not level then
    return 0, timestamp, record
  end

  -- Normalize level
  local normalized = level:upper()
  normalized = LEVEL_ALIASES[level:lower()] or normalized

  local sev = SEVERITY_MAP[normalized]
  if not sev then
    return 0, timestamp, record
  end

  record["severity_text"] = sev.text
  record["severity_number"] = sev.number

  -- Extract msg= value for body (handles quoted and unquoted)
  local msg = log:match('msg="([^"]+)"') or
              log:match("msg='([^']+)'") or
              log:match('msg=([^%s]+)')

  if msg then
    record["body"] = msg
  else
    record["body"] = log
  end

  return 1, timestamp, record
end
