-- JSON structured log parser
-- Handles common JSON log formats: zap, logrus, zerolog, slog
-- Uses cjson for full JSON parsing, extracts all fields generically
--
-- OTEL mapping:
--   body        = message content (msg, message, error, err)
--   body.*      = all other JSON fields (generic extraction)
--   severity_*  = from level/severity/lvl field
--   attributes  = OTEL semantic attributes (code.filepath, etc.)

-- Try to load cjson (available in Fluent Bit's LuaJIT)
local cjson_ok, cjson = pcall(require, "cjson.safe")

-- OTEL severity number mapping
local SEVERITY_MAP = {
  trace   = { text = "TRACE", number = 1 },
  debug   = { text = "DEBUG", number = 5 },
  info    = { text = "INFO",  number = 9 },
  warn    = { text = "WARN",  number = 13 },
  warning = { text = "WARN",  number = 13 },
  error   = { text = "ERROR", number = 17 },
  fatal   = { text = "FATAL", number = 21 },
  panic   = { text = "FATAL", number = 21 },
  dpanic  = { text = "FATAL", number = 21 },
  critical = { text = "FATAL", number = 21 }
}

-- Fields that map to severity
local LEVEL_FIELDS = { level = true, severity = true, lvl = true, loglevel = true }

-- Fields that map to body (message content)
local MESSAGE_FIELDS = { msg = true, message = true }

-- Fields to skip (metadata, timestamps)
local SKIP_FIELDS = {
  ts = true, time = true, timestamp = true, ["@timestamp"] = true,
  level = true, severity = true, lvl = true, loglevel = true,
  msg = true, message = true
}

-- No separate attribute extraction - all fields go to body.*
-- The Quickwit OTEL schema requires attributes to be a proper object,
-- which is complex to construct in Fluentd. All extracted fields go to body.
local ATTRIBUTE_MAP = {}

-- Fallback regex extraction (when cjson unavailable)
local function extract_json_field(json, field)
  local pattern = '"' .. field .. '"%s*:%s*"([^"]*)"'
  return json:match(pattern)
end

function parse_json_structured(tag, timestamp, record)
  local log = record["log"]
  if not log then return 0, timestamp, record end

  -- Skip if already parsed
  if record["severity_text"] and record["severity_text"] ~= "" then
    return 0, timestamp, record
  end

  -- Check if this looks like JSON
  if not log:match("^%s*{") then
    return 0, timestamp, record
  end

  -- Try cjson parsing
  local data = nil
  if cjson_ok then
    data = cjson.decode(log)
  end

  if data then
    -- Full JSON parsing with cjson
    local level = nil
    local msg = nil

    -- First pass: extract level and message
    for k, v in pairs(data) do
      if type(v) == "string" then
        if LEVEL_FIELDS[k] or LEVEL_FIELDS[k:lower()] then
          level = v
        elseif MESSAGE_FIELDS[k] or MESSAGE_FIELDS[k:lower()] then
          msg = v
        end
      end
    end

    -- Must have a level to parse as structured
    if not level then
      return 0, timestamp, record
    end

    -- Map severity
    local sev = SEVERITY_MAP[level:lower()]
    if sev then
      record["severity_text"] = sev.text
      record["severity_number"] = sev.number
    else
      record["severity_text"] = level:upper()
      record["severity_number"] = 9
    end

    -- Set body
    record["body"] = msg or log

    -- Second pass: extract all other fields
    for k, v in pairs(data) do
      if not SKIP_FIELDS[k] and not SKIP_FIELDS[k:lower()] then
        -- Check if this maps to an OTEL attribute
        local attr_fn = ATTRIBUTE_MAP[k]
        if attr_fn and type(v) == "string" then
          attr_fn(v, record)
        end

        -- Skip body.* extraction for now - schema doesn't support dynamic fields
      end
    end
  else
    -- Fallback: regex extraction for common fields
    local level = extract_json_field(log, "level") or
                  extract_json_field(log, "severity") or
                  extract_json_field(log, "lvl")
    if not level then
      return 0, timestamp, record
    end

    local msg = extract_json_field(log, "msg") or
                extract_json_field(log, "message")

    local sev = SEVERITY_MAP[level:lower()]
    if sev then
      record["severity_text"] = sev.text
      record["severity_number"] = sev.number
    else
      record["severity_text"] = level:upper()
      record["severity_number"] = 9
    end

    record["body"] = msg or log

    -- No body.* extraction - schema doesn't support dynamic fields
  end

  return 1, timestamp, record
end
