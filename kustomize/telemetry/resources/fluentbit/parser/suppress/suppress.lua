-- Log suppressor
-- Downgrades known noisy logs from upstream vendors to TRACE severity
--
-- These logs come from third-party components we can't fix at the source.
-- We reduce log volume by downgrading these known patterns to TRACE level,
-- which can then be filtered out by the log-level filter.
--
-- Tracked issues:
--   - OpenEBS LocalPV: Uses v1 Endpoints instead of EndpointSlices
--     No upstream fix available as of v4.4.0
--   - kube-prometheus-stack: Uses v1 Endpoints instead of EndpointSlices

-- Service-specific suppressions: { service_pattern = { message_patterns } }
-- Only suppresses if BOTH service name matches AND message matches
local SUPPRESS_RULES = {
  -- OpenEBS LocalPV uses deprecated v1 Endpoints API
  -- No upstream fix available as of v4.4.0
  ["openebs"] = {
    "v1 Endpoints is deprecated",
  },
  -- kube-prometheus-stack uses deprecated APIs
  ["kube-prometheus-stack"] = {
    "v1 Endpoints is deprecated",
    "v1beta2 ImagePolicy is deprecated",
  },
}

function suppress(tag, timestamp, record)
  local sev = record["severity_text"]
  
  -- Get content to match against (check both body and log)
  local body = record["body"]
  local log = record["log"]
  
  local content = ""
  if type(body) == "string" then
    content = body
  elseif type(log) == "string" then
    content = log
  else
    return 0, timestamp, record
  end

  -- Service-specific rules only apply to WARN level
  if sev ~= "WARN" then
    return 0, timestamp, record
  end

  -- Get service name for targeted suppression
  local service = record["service_name"]
  if not service or type(service) ~= "string" then
    return 0, timestamp, record
  end

  -- Check if service matches any suppression rule
  for service_pattern, message_patterns in pairs(SUPPRESS_RULES) do
    if service:find(service_pattern, 1, true) then
      for _, msg_pattern in ipairs(message_patterns) do
        if content:find(msg_pattern, 1, true) then
          record["severity_text"] = "TRACE"
          record["severity_number"] = 1
          return 1, timestamp, record
        end
      end
    end
  end

  return 0, timestamp, record
end
