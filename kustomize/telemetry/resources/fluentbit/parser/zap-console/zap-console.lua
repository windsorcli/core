-- Zap "console" encoder parser (controller-runtime / zap-based Go controllers)
-- Format: <epoch-seconds float>\t<level>\t[<logger>\t]<caller>\t<message>\t[<json context>]
-- The logger-name field only appears when the zap logger was given a name
-- (.Named(...)); root loggers omit it, so the field count varies.
-- Examples:
--   1.784389225979603e+09	info	provider.controller-runtime.cache	rest/warnings.go:107	Warning: deprecated	{"runner": "provider"}
--   1.7843423937898643e+09	info	cmd/certgen.go:133	created secret	{"namespace": "system-gateway", "name": "envoy-oidc-hmac"}
--
-- Common in: envoy-gateway and other controller-runtime-based controllers
-- configured with zap's console encoder (as opposed to the JSON encoder,
-- handled by json-structured).

-- OTEL severity number mapping
local SEVERITY_MAP = {
  DEBUG  = { text = "DEBUG", number = 5 },
  INFO   = { text = "INFO",  number = 9 },
  WARN   = { text = "WARN",  number = 13 },
  ERROR  = { text = "ERROR", number = 17 },
  DPANIC = { text = "FATAL", number = 21 },
  PANIC  = { text = "FATAL", number = 21 },
  FATAL  = { text = "FATAL", number = 21 }
}

function parse_zap_console(tag, timestamp, record)
  local log = record["log"]
  if not log then return 0, timestamp, record end

  -- Skip if already parsed (severity already set by another parser)
  if record["severity_text"] and record["severity_text"] ~= "" then
    return 0, timestamp, record
  end

  local parts = {}
  for part in log:gmatch("[^\t]+") do
    table.insert(parts, part)
  end

  -- Minimum shape: epoch, level, caller, message
  if #parts < 4 then
    return 0, timestamp, record
  end

  -- First field must look like a Unix epoch (integer, decimal, or scientific notation)
  if not parts[1]:match("^%d+%.?%d*[eE]?[%+%-]?%d*$") then
    return 0, timestamp, record
  end

  local sev = SEVERITY_MAP[parts[2]:upper()]
  if not sev then
    return 0, timestamp, record
  end

  record["severity_text"] = sev.text
  record["severity_number"] = sev.number

  -- Message is the last field, unless zap appended a trailing JSON context
  -- blob, in which case the message is the field before it.
  local last = parts[#parts]
  if last:match("^%s*{") and #parts > 4 then
    record["body"] = parts[#parts - 1]
  else
    record["body"] = last
  end

  -- No body.* / logger / caller extraction - schema doesn't support dynamic fields

  return 1, timestamp, record
end
