local Damage = require("display.damage")
local unpack = table.unpack or unpack

local Compositor = {}
Compositor.__index = Compositor

function Compositor.new(registry, componentAccess, options)
  options = options or {}
  return setmetatable({registry = registry, components = componentAccess,
    logger = options.logger, clock = options.clock or os.clock,
    maxRegions = options.maxRegions or 12, operationsPerStep = options.operationsPerStep or 32,
    leases = {}, renderedFrames = 0, staleFrames = 0, componentErrors = 0}, Compositor)
end

function Compositor:_log(level, message, fields)
  if self.logger then self.logger:write(level, "compositor", message, fields) end
end

function Compositor:request(endpointId, rect, builder)
  local endpoint = self.registry:get(endpointId)
  if not endpoint or not endpoint.connected then return nil, "endpoint unavailable" end
  if not endpoint.damage then endpoint.damage = Damage.new(endpoint.width, endpoint.height, self.maxRegions) end
  if rect then endpoint.damage:add(rect) else endpoint.damage:add({x = 1, y = 1, w = endpoint.width, h = endpoint.height}) end
  endpoint.pending = {generation = endpoint.generation, builder = builder or (endpoint.pending and endpoint.pending.builder)}
  endpoint.lastRenderRequest = self.clock()
  return true
end

local function call(components, address, method, ...)
  -- Invoke by component address instead of through a proxy.  In particular,
  -- this avoids proxy method binding differences between OpenOS versions and
  -- Ocelot while retaining the broker's error normalization.
  return components:invoke(address, method, ...)
end

function Compositor:_prepare(endpoint, now)
  if endpoint.renderJob or not endpoint.pending then return true end
  if endpoint.pending.generation ~= endpoint.generation then
    endpoint.pending = nil; if endpoint.damage then endpoint.damage:take() end
    self.staleFrames = self.staleFrames + 1; return true
  end
  local interval = 1 / math.max(1, endpoint.targetFps)
  if now - endpoint.lastRender < interval then return true end
  local regions = endpoint.damage and endpoint.damage:take() or {}
  local ok, commands = pcall(endpoint.pending.builder, endpoint, regions)
  if not ok then endpoint.pending = nil; self:_log("error", "frame builder failed",
    {endpoint = endpoint.id, error = tostring(commands)}); return nil, commands end
  endpoint.renderJob = {generation = endpoint.generation, commands = commands or {}, index = 1,
    builder = endpoint.pending.builder, started = now, bound = false}
  endpoint.pending = nil
  return true
end

function Compositor:_bind(endpoint, job)
  if not endpoint.gpuAddress then return nil, "no GPU assigned" end
  local lease = self.leases[endpoint.gpuAddress]
  if not lease or lease.endpointId ~= endpoint.id or lease.generation ~= endpoint.generation then
    local ok, bindErr = call(self.components, endpoint.gpuAddress, "bind", endpoint.screenAddress, false)
    if not ok then return nil, bindErr end
    self.leases[endpoint.gpuAddress] = {endpointId = endpoint.id, generation = endpoint.generation}
  end
  local okMax, maxWidth, maxHeight = call(self.components, endpoint.gpuAddress, "maxResolution")
  if okMax and (endpoint.width > maxWidth or endpoint.height > maxHeight) then
    endpoint.width, endpoint.height = math.min(endpoint.width, maxWidth), math.min(endpoint.height, maxHeight)
  end
  local okRes, width, height = call(self.components, endpoint.gpuAddress, "getResolution")
  if okRes and (width ~= endpoint.width or height ~= endpoint.height) then
    local set, setErr = call(self.components, endpoint.gpuAddress, "setResolution", endpoint.width, endpoint.height)
    if not set then return nil, setErr end
  end
  job.gpuAddress, job.bound = endpoint.gpuAddress, true
  return true
end

function Compositor:_execute(job, command)
  local components, gpu = self.components, job.gpuAddress
  if command.background then local ok, err = call(components, gpu, "setBackground", command.background); if not ok then return nil, err end end
  if command.foreground then local ok, err = call(components, gpu, "setForeground", command.foreground); if not ok then return nil, err end end
  if command.op == "fill" then return call(components, gpu, "fill", command.x, command.y, command.w, command.h, command.char or " ") end
  if command.op == "set" then return call(components, gpu, "set", command.x, command.y, command.text or "") end
  if command.op == "copy" then return call(components, gpu, "copy", command.x, command.y, command.w, command.h, command.tx, command.ty) end
  return nil, "unknown draw operation"
end

function Compositor:_failure(endpoint, job, err)
  self.componentErrors = self.componentErrors + 1
  self.leases[endpoint.gpuAddress] = nil
  local builder = job and job.builder
  self.registry:recover(endpoint.id, err)
  if endpoint.connected and endpoint.failures <= 3 and builder then
    endpoint.state = "recovering"
    self:request(endpoint.id, nil, builder)
  elseif endpoint.failures > 3 then endpoint.state = "failed" end
  self:_log("error", "endpoint render failed", {endpoint = endpoint.id, error = tostring(err)})
end

function Compositor:step(now, budget)
  now = now or self.clock(); budget = budget or self.operationsPerStep
  local used = 0
  for _, endpoint in ipairs(self.registry:list()) do
    if used >= budget then break end
    if endpoint.connected then
      local prepared, prepareErr = self:_prepare(endpoint, now)
      if not prepared then self:_failure(endpoint, endpoint.renderJob, prepareErr) end
      local job = endpoint.renderJob
      if job and job.generation ~= endpoint.generation then
        endpoint.renderJob = nil; self.staleFrames = self.staleFrames + 1
      elseif job then
        local lease = self.leases[endpoint.gpuAddress]
        if not job.bound or not lease or lease.endpointId ~= endpoint.id or lease.generation ~= endpoint.generation then
          local bound, bindErr = self:_bind(endpoint, job)
          if not bound then self:_failure(endpoint, job, bindErr); job = nil end
        end
        while job and used < budget and job.index <= #job.commands do
          local ok, err = self:_execute(job, job.commands[job.index])
          if not ok then self:_failure(endpoint, job, err); job = nil; break end
          job.index = job.index + 1; used = used + 1
        end
        if job and job.index > #job.commands then
          endpoint.renderJob = nil; endpoint.lastRender = now; endpoint.state = "active"
          endpoint.failures = 0; self.renderedFrames = self.renderedFrames + 1
        end
      end
    end
  end
  return used
end

function Compositor:watchdog(now, schedulerHeartbeat)
  now = now or self.clock(); local faults = {}
  for _, endpoint in ipairs(self.registry:list()) do
    local frame = 1 / math.max(1, endpoint.targetFps)
    local pendingAge = endpoint.pending and (now - endpoint.lastRenderRequest) or 0
    if endpoint.connected and endpoint.pending and pendingAge > frame * 8
      and now - schedulerHeartbeat < frame * 4 then
      faults[#faults + 1] = {endpoint = endpoint.id, domain = "display", age = pendingAge}
    end
  end
  return faults
end

function Compositor:metrics(endpointId)
  local endpoint = self.registry:get(endpointId)
  return {renderedFrames = self.renderedFrames, staleFrames = self.staleFrames,
    componentErrors = self.componentErrors, queueDepth = endpoint and ((endpoint.pending and 1 or 0)
      + (endpoint.renderJob and 1 or 0)) or 0,
    dirtyRegions = endpoint and endpoint.damage and endpoint.damage:count() or 0,
    lastRender = endpoint and endpoint.lastRender or 0, lastError = endpoint and endpoint.lastError}
end

return Compositor
