-- gRPC-Go log parser
-- Parses grpc-go logging format embedded in klog or other log formats
-- Format: [LEVEL] [component] [Channel #N SubChannel #M]grpc: message
-- OR:     error [core] [Channel #N]grpc: message
-- Example: [core] [Channel #2512 SubChannel #2513]grpc: addrConn.createTransport failed...

local SEVERITY_MAP = {
  error = { text = "ERROR", number = 17 },
  warn  = { text = "WARN",  number = 13 },
  warning = { text = "WARN", number = 13 },
  info  = { text = "INFO",  number = 9 },
  debug = { text = "DEBUG", number = 5 }
}

function parse_grpc(tag, timestamp, record)
  local log = record["log"]
  local body = record["body"] or log
  if not body then return 0, timestamp, record end

  -- Check if this looks like a grpc log (contains "grpc:" or starts with [core], [transport], etc.)
  if not body:match("grpc:") and not body:match("%[core%]") and not body:match("%[transport%]") then
    return 0, timestamp, record
  end

  -- Try to extract severity from "error [core]" or "error[core]" pattern at start
  -- Also handle body starting with severity (no prior extraction)
  local level, rest = body:match("^%s*(%l+)%s*(%[.+)$")
  if level and SEVERITY_MAP[level] then
    local sev = SEVERITY_MAP[level]
    if not record["severity_text"] or record["severity_text"] == "" or record["severity_text"] == "INFO" then
      record["severity_text"] = sev.text
      record["severity_number"] = sev.number
    end
    body = rest
  end

  -- Extract the actual message after "grpc:" (clean up grpc prefixes)
  local grpc_msg = body:match("grpc:%s*(.+)$")
  if grpc_msg then
    record["body"] = grpc_msg
  else
    -- Fallback: strip leading brackets and component markers
    local cleaned = body:gsub("^%[[^%]]*%]%s*", "") -- Remove first [...]
    cleaned = cleaned:gsub("^%[[^%]]*%]%s*", "")    -- Remove second [...] if present
    if cleaned ~= body then
      record["body"] = cleaned
    end
  end

  return 1, timestamp, record
end
