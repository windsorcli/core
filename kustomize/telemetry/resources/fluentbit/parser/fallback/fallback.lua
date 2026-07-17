-- Fallback parser for logs not matched by specific format parsers
-- Handles: klog format (outside kube-system), bracketed format, default severity
-- Does NOT pattern-match: JSON, logfmt, rust-tracing (handled by dedicated parsers).
-- Still applies the UNKNOWN default to those formats if their own parser
-- couldn't extract a severity (e.g. JSON logs with no level/severity field).

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

-- klog severity mapping (I=Info, W=Warning, E=Error, F=Fatal)
local KLOG_SEVERITY = {
  I = { text = "INFO",  number = 9 },
  W = { text = "WARN",  number = 13 },
  E = { text = "ERROR", number = 17 },
  F = { text = "FATAL", number = 21 }
}

function parse_fallback(tag, timestamp, record)
  local log = record["log"]
  if not log then return 0, timestamp, record end

  -- Skip if already parsed (severity already set by another parser)
  if record["severity_text"] and record["severity_text"] ~= "" then
    return 0, timestamp, record
  end

  -- JSON logs got a real shot from json-structured already; it just
  -- couldn't find a level field. Don't run the plain-text heuristics below
  -- against JSON (they can false-match inside a JSON string), but still
  -- fall through to the UNKNOWN default at the bottom.
  local is_json = log:match("^%s*{") ~= nil

  if not is_json then
    -- Try klog format: I0123, W0123, E0123, F0123 at start of line
    -- Format: [IWEF]MMDD HH:MM:SS.NNNNNN  PID file:line] message
    local klog_level = log:match('^([IWEF])%d%d%d%d%s')
    if klog_level then
      local sev = KLOG_SEVERITY[klog_level]
      if sev then
        record["severity_text"] = sev.text
        record["severity_number"] = sev.number
        -- Extract message after "] "
        local msg = log:match('%]%s*(.+)$')
        record["body"] = msg or log
        return 1, timestamp, record
      end
    end
  end

  -- Set body to full log if not already set
  if not record["body"] then
    record["body"] = log
  end

  if not is_json then
    -- Try bracketed format: [ info], [error], [ warn] (Fluent Bit format)
    local bracketed = log:match('%[%s*([a-zA-Z]+)%]')
    if bracketed then
      local level = bracketed:upper()
      level = LEVEL_ALIASES[bracketed:lower()] or level
      local sev = SEVERITY_MAP[level]
      if sev then
        record["severity_text"] = sev.text
        record["severity_number"] = sev.number
        return 1, timestamp, record
      end
    end
  end

  -- No severity detected - mark unclassified rather than guessing
  record["severity_text"] = "UNKNOWN"
  record["severity_number"] = 0
  return 1, timestamp, record
end
