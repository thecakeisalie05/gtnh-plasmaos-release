local Ring = require("libs.ring")

local Manager = {}
Manager.__index = Manager

function Manager.new(componentBroker, telemetry, options)
  options = options or {}
  return setmetatable({components = componentBroker, telemetry = telemetry,
    adapters = {}, claims = {}, clock = options.clock or os.clock,
    history = Ring.new(options.historyLimit or 64), logger = options.logger,
    capabilities = options.capabilities, audit = options.audit}, Manager)
end

function Manager:register(adapter)
  assert(adapter.id and type(adapter.detect) == "function", "invalid adapter")
  adapter.pollInterval = math.max(1, adapter.pollInterval or 10)
  self.adapters[adapter.id] = adapter
end

function Manager:discover()
  local snapshot = self.components:snapshot()
  local present = {}
  for _, item in ipairs(snapshot) do
    present[item.address] = true
    if not self.claims[item.address] then
      for id, adapter in pairs(self.adapters) do
        local ok, matched = pcall(adapter.detect, item)
        if ok and matched then
          self.claims[item.address] = {adapter = id, component = item, nextPoll = 0,
            state = "available", failures = 0}
          self.history:push({time = self.clock(), action = "claimed", address = item.address, adapter = id})
          break
        end
      end
      if not self.claims[item.address] then
        self.claims[item.address] = {adapter = "generic", component = item, state = "available", nextPoll = math.huge}
      end
    end
  end
  for address, claim in pairs(self.claims) do
    if not present[address] then claim.state = "unavailable" end
  end
  return self.claims
end

function Manager:poll(now, limit)
  now = now or self.clock(); limit = limit or 1; local count = 0
  for address, claim in pairs(self.claims) do
    if count >= limit then break end
    local adapter = self.adapters[claim.adapter]
    if adapter and claim.state ~= "unavailable" and now >= claim.nextPoll then
      local ok, values = pcall(adapter.poll, address, self.components, claim.component)
      if ok and type(values) == "table" then
        claim.state, claim.failures, claim.lastUpdate = "live", 0, now
        for id, sample in pairs(values) do
          local metricId = claim.adapter .. ":" .. address .. ":" .. id
          if not self.telemetry.metrics[metricId] then self.telemetry:define(metricId,
            {source = address, unit = sample.unit, staleAfter = adapter.pollInterval * 3}) end
          self.telemetry:sample(metricId, sample.value, sample.quality or "live", now)
        end
      else
        claim.failures = claim.failures + 1; claim.state = "error"; claim.lastError = tostring(values)
      end
      claim.nextPoll = now + adapter.pollInterval; count = count + 1
    end
  end
  return count
end

function Manager:action(subject, address, actionId, confirmed)
  local claim = self.claims[address]; local adapter = claim and self.adapters[claim.adapter]
  local action = adapter and adapter.actions and adapter.actions[actionId]
  if not action then return nil, "action unavailable" end
  if action.confirm and not confirmed then return nil, "confirmation required" end
  if self.capabilities then
    local ok, err = self.capabilities:require(subject, "component.control", {address = address, action = actionId})
    if not ok then return nil, err end
  end
  if action.interlock then local ok, reason = action.interlock(address, self.telemetry); if not ok then return nil, reason end end
  local ok, result = pcall(action.execute, address, self.components)
  if self.audit then self.audit(subject, "integration-control", {address = address, action = actionId, ok = ok}) end
  if not ok then return nil, result end
  return result == nil and true or result
end

function Manager:list()
  local out = {}
  for address, claim in pairs(self.claims) do out[#out + 1] = {address = address,
    type = claim.component.type, adapter = claim.adapter, state = claim.state,
    lastUpdate = claim.lastUpdate, lastError = claim.lastError} end
  table.sort(out, function(a, b) return a.address < b.address end); return out
end

return Manager
