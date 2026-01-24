-- Upstream deprecation warning suppressor
-- Downgrades known upstream warnings to TRACE severity
--
-- These warnings come from third-party components using deprecated Kubernetes APIs.
-- We can't fix the upstream code, but we can reduce log noise by downgrading
-- these known-harmless warnings to TRACE level.
--
-- Tracked issues:
--   - OpenEBS LocalPV: Uses v1 Endpoints instead of EndpointSlices
--     No upstream fix available as of v4.4.0
--     https://github.com/openebs/dynamic-localpv-provisioner

-- Service-specific suppressions: { service_pattern = { message_patterns } }
-- Only suppresses if BOTH service name matches AND message matches
local SUPPRESS_RULES = {
  -- OpenEBS LocalPV uses deprecated v1 Endpoints API
  -- No upstream fix available as of v4.4.0
  ["openebs"] = {
    "v1 Endpoints is deprecated",
  },
}

function suppress_upstream_warnings(tag, timestamp, record)
  -- Only process WARN level logs
  local sev = record["severity_text"]
  if sev ~= "WARN" then
    return 0, timestamp, record
  end

  -- Get service name for targeted suppression
  local service = record["service_name"]
  if not service or type(service) ~= "string" then
    return 0, timestamp, record
  end

  -- Get content to match against (check both body and log)
  local body = record["body"]
  local log = record["log"]
  
  -- body might be a string or nil at this stage
  local content = ""
  if type(body) == "string" then
    content = body
  elseif type(log) == "string" then
    content = log
  else
    return 0, timestamp, record
  end

  -- Check if service matches any suppression rule
  for service_pattern, message_patterns in pairs(SUPPRESS_RULES) do
    if service:find(service_pattern, 1, true) then
      -- Service matches, now check message patterns
      for _, msg_pattern in ipairs(message_patterns) do
        if content:find(msg_pattern, 1, true) then
          -- Downgrade to TRACE (preserves log but hides from warning views)
          record["severity_text"] = "TRACE"
          record["severity_number"] = 1
          return 1, timestamp, record
        end
      end
    end
  end

  return 0, timestamp, record
end
