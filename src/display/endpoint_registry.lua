local Ring = require("libs.ring")

local Registry = {}
Registry.__index = Registry

local function shallowCopy(list)
  local out = {}
  for i, value in ipairs(list or {}) do out[i] = value end
  return out
end

function Registry.new(componentAccess, options)
  options = options or {}
  return setmetatable({
    components = componentAccess,
    endpoints = {},
    screenIndex = {},
    keyboardIndex = {},
    logger = options.logger,
    clock = options.clock or os.clock,
    kindResolver = options.kindResolver,
    targetFps = options.targetFps or {localDisplay = 12, terminal = 6, unknown = 5},
    history = Ring.new(options.historyLimit or 64),
    listeners = {},
  }, Registry)
end

function Registry:_emit(action, endpoint)
  self.history:push({time = self.clock(), action = action, endpointId = endpoint.id,
    screen = endpoint.screenAddress, generation = endpoint.generation})
  for _, callback in pairs(self.listeners) do pcall(callback, action, endpoint) end
end

function Registry:onChange(callback)
  self.listeners[#self.listeners + 1] = callback
  return #self.listeners
end

function Registry:_index(endpoint)
  self.screenIndex[endpoint.screenAddress] = endpoint.id
  for _, keyboard in ipairs(endpoint.keyboards) do self.keyboardIndex[keyboard] = endpoint.id end
end

function Registry:_unindex(endpoint)
  self.screenIndex[endpoint.screenAddress] = nil
  for keyboard, id in pairs(self.keyboardIndex) do
    if id == endpoint.id then self.keyboardIndex[keyboard] = nil end
  end
end

function Registry:add(spec)
  assert(spec and spec.screenAddress, "screen address required")
  local id = spec.id or ("display:" .. spec.screenAddress)
  local existing = self.endpoints[id]
  if existing then
    self:_unindex(existing)
    existing.screenAddress = spec.screenAddress
    existing.gpuAddress = spec.gpuAddress or existing.gpuAddress
    existing.keyboards = shallowCopy(spec.keyboards)
    existing.kind = spec.kind or existing.kind
    existing.connected = true
    existing.generation = existing.generation + 1
    existing.state = "recovering"
    existing.lastError = nil
    self:_index(existing); self:_emit("reconnected", existing)
    return existing
  end
  local kind = spec.kind or (self.kindResolver and self.kindResolver(spec.screenAddress)) or "unknown"
  local endpoint = {
    id = id,
    screenAddress = spec.screenAddress,
    gpuAddress = spec.gpuAddress,
    keyboards = shallowCopy(spec.keyboards),
    kind = kind,
    connected = true,
    generation = 1,
    width = spec.width or 80,
    height = spec.height or 25,
    maxWidth = spec.maxWidth or spec.width or 80,
    maxHeight = spec.maxHeight or spec.height or 25,
    depth = spec.depth or 1,
    targetFps = spec.targetFps or (kind == "terminal" and self.targetFps.terminal
      or kind == "local" and self.targetFps.localDisplay or self.targetFps.unknown),
    lowBandwidth = spec.lowBandwidth ~= nil and spec.lowBandwidth or kind ~= "local",
    state = "active",
    failures = 0,
    lastRender = 0,
    lastInput = 0,
    lastRenderRequest = 0,
  }
  self.endpoints[id] = endpoint; self:_index(endpoint); self:_emit("added", endpoint)
  return endpoint
end

function Registry:disconnect(id, reason)
  local endpoint = self.endpoints[id]
  if not endpoint then return nil, "unknown endpoint" end
  self:_unindex(endpoint)
  endpoint.connected = false
  endpoint.state = "disconnected"
  endpoint.generation = endpoint.generation + 1
  endpoint.lastError = reason
  endpoint.pending = nil
  endpoint.renderJob = nil
  self:_emit("disconnected", endpoint)
  return true
end

function Registry:recover(id, reason)
  local endpoint = self.endpoints[id]
  if not endpoint then return nil, "unknown endpoint" end
  endpoint.failures = endpoint.failures + 1
  endpoint.generation = endpoint.generation + 1
  endpoint.state = endpoint.connected and "recovering" or "disconnected"
  endpoint.lastError = tostring(reason)
  endpoint.pending, endpoint.renderJob = nil, nil
  self:_emit("recovering", endpoint)
  return endpoint
end

function Registry:updateKeyboards(id, keyboards)
  local endpoint = self.endpoints[id]
  if not endpoint then return nil, "unknown endpoint" end
  self:_unindex(endpoint); endpoint.keyboards = shallowCopy(keyboards)
  endpoint.generation = endpoint.generation + 1; self:_index(endpoint)
  self:_emit("keyboards", endpoint)
  return endpoint
end

function Registry:byInput(address)
  local id = self.screenIndex[address] or self.keyboardIndex[address]
  return id and self.endpoints[id] or nil
end

function Registry:get(id) return self.endpoints[id] end

function Registry:list()
  local out = {}
  for _, endpoint in pairs(self.endpoints) do out[#out + 1] = endpoint end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

function Registry:discover(kindHints)
  local screens, gpus = {}, {}
  for address, componentType in self.components:list() do
    if componentType == "screen" then screens[#screens + 1] = address end
    if componentType == "gpu" then gpus[#gpus + 1] = address end
  end
  table.sort(screens); table.sort(gpus)
  for index, address in ipairs(screens) do
    if not self.screenIndex[address] then
      local keyboards = {}
      local ok, value = self.components:invoke(address, "getKeyboards")
      if ok and type(value) == "table" then keyboards = value end
      local gpuAddress = gpus[((index - 1) % math.max(1, #gpus)) + 1]
      -- A local tiered display should use the GPU's largest supported text
      -- mode.  The old 80x25 fallback made every desktop unnecessarily small.
      local width, height = 80, 25
      if gpuAddress then
        local maxOk, maxWidth, maxHeight = self.components:invoke(gpuAddress, "maxResolution")
        if maxOk and type(maxWidth) == "number" and type(maxHeight) == "number" then
          width, height = maxWidth, maxHeight
        end
      end
      self:add({screenAddress = address, gpuAddress = gpuAddress, keyboards = keyboards,
        width = width, height = height,
        kind = (kindHints and kindHints[address]) or (#keyboards > 0 and "local" or "unknown")})
    end
  end
  local present = {}; for _, address in ipairs(screens) do present[address] = true end
  for _, endpoint in pairs(self.endpoints) do
    if endpoint.connected and not present[endpoint.screenAddress] then self:disconnect(endpoint.id, "screen removed") end
  end
  return self:list()
end

return Registry
