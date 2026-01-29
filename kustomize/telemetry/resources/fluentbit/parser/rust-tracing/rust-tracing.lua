-- Rust tracing log parser
-- Format: TIMESTAMP  LEVEL module::path: message key=value key2=value2
-- Examples:
--   2026-01-23T21:40:14.382Z  INFO quickwit_janitor::actors::garbage_collector: Janitor deleted...
--   2026-01-23T21:15:28.810Z  WARN quickwit_search::root: search failed...
--
-- Common in: Quickwit, other Rust services using tracing crate

-- OTEL severity number mapping
local SEVERITY_MAP = {
  TRACE = { text = "TRACE", number = 1 },
  DEBUG = { text = "DEBUG", number = 5 },
  INFO  = { text = "INFO",  number = 9 },
  WARN  = { text = "WARN",  number = 13 },
  ERROR = { text = "ERROR", number = 17 }
}

-- Strip ANSI escape codes from string
local function strip_ansi(s)
  -- Pattern matches: ESC [ ... m (SGR sequences)
  return s:gsub('\027%[[%d;]*m', '')
end

function parse_rust_tracing(tag, timestamp, record)
  local log = record["log"]
  if not log then return 0, timestamp, record end

  -- Skip if already parsed
  if record["severity_text"] and record["severity_text"] ~= "" then
    return 0, timestamp, record
  end

  -- Strip ANSI color codes if present
  log = strip_ansi(log)

  -- Match Rust tracing format: TIMESTAMP  LEVEL module::path: message
  -- The level is typically uppercase, surrounded by whitespace
  local level = log:match('%s+(TRACE)%s+') or
                log:match('%s+(DEBUG)%s+') or
                log:match('%s+(INFO)%s+') or
                log:match('%s+(WARN)%s+') or
                log:match('%s+(ERROR)%s+')

  if not level then
    return 0, timestamp, record
  end

  local sev = SEVERITY_MAP[level]
  if not sev then
    return 0, timestamp, record
  end

  record["severity_text"] = sev.text
  record["severity_number"] = sev.number

  -- Extract message: everything after "module::path: "
  -- Module paths contain only alphanumerics, underscores, and :: separators
  -- Using [%w_:]+ stops at first ": " (single colon-space) after module path
  -- This preserves ": " sequences within the actual message
  local msg = log:match(level .. '%s+[%w_:]+:%s(.+)$')

  if msg then
    record["body"] = msg
  else
    -- Use stripped log as body
    record["body"] = log
  end

  return 1, timestamp, record
end
