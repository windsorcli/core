-- Zerolog log parser (Go logging library)
-- Format: TIMESTAMP LEVEL caller/path.go:line > message key=value key2=value2
-- Examples:
--   2026-01-23T22:21:37.123Z TRC github.com/kyverno/.../validation.go:123 > validation passed action=validate
--   2026-01-23T22:21:37Z INF pkg/engine/validate.go:45 > policy applied policy=require-labels
--   2026-01-23T22:21:37.456789Z ERR pkg/webhooks/server.go:89 > webhook failed error="timeout"
--
-- Common in: Kyverno, and other Go services using zerolog

-- Strip ANSI escape codes (color codes like [32m, [0m, etc.)
local function strip_ansi(str)
  if not str then return str end
  -- Match ESC[ followed by any params and ending with a letter
  return str:gsub('\027%[[%d;]*[A-Za-z]', '')
end

-- OTEL severity mapping for zerolog short codes
local SEVERITY_MAP = {
  TRC = { text = "TRACE", number = 1 },
  DBG = { text = "DEBUG", number = 5 },
  INF = { text = "INFO",  number = 9 },
  WRN = { text = "WARN",  number = 13 },
  ERR = { text = "ERROR", number = 17 },
  FTL = { text = "FATAL", number = 21 },
  PNC = { text = "FATAL", number = 21 }  -- panic
}

function parse_zerolog(tag, timestamp, record)
  local log = record["log"]
  if not log then return 0, timestamp, record end

  -- Skip if already parsed
  if record["severity_text"] and record["severity_text"] ~= "" then
    return 0, timestamp, record
  end

  -- Strip ANSI escape codes before parsing
  log = strip_ansi(log)

  -- Match zerolog format: TIMESTAMP LEVEL caller > message
  -- Pattern: timestamp followed by 3-letter level code (supports fractional seconds)
  local level = log:match('^%d%d%d%d%-%d%d%-%d%dT[%d:.]+Z%s+(%u%u%u)%s+')

  if not level then
    return 0, timestamp, record
  end

  local sev = SEVERITY_MAP[level]
  if not sev then
    return 0, timestamp, record
  end

  record["severity_text"] = sev.text
  record["severity_number"] = sev.number

  -- Extract message: everything after " > " up to first key=value or end
  local msg = log:match('%s>%s+([^=]+)%s+%w+[=:]') or
              log:match('%s>%s+(.+)$')

  if msg then
    -- Trim trailing whitespace
    msg = msg:gsub('%s+$', '')
    record["body"] = msg
  else
    -- Fallback: just the level and everything after caller
    local after_caller = log:match('%s>%s+(.+)$')
    record["body"] = after_caller or log
  end

  return 1, timestamp, record
end
