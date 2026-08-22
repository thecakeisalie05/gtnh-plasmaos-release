local WindowManager = require("ui.window_manager")

local Sessions = {}
Sessions.__index = Sessions

function Sessions.new(registry, options)
  options = options or {}
  local self = setmetatable({registry = registry, sessions = {}, endpointIndex = {},
    nextId = 1, logger = options.logger, clock = options.clock or os.clock,
    windowManagerFactory = options.windowManagerFactory}, Sessions)
  registry:onChange(function(action, endpoint) self:_endpointChanged(action, endpoint) end)
  return self
end

function Sessions:_new(endpoint)
  local id = "session:" .. self.nextId; self.nextId = self.nextId + 1
  local factory = self.windowManagerFactory or function(session)
    return WindowManager.new(session, {logger = self.logger})
  end
  local session = {
    id = id, user = "player", endpointId = endpoint.id, screenAddress = endpoint.screenAddress,
    keyboards = endpoint.keyboards, focusedWindow = nil, clipboard = "", notifications = {},
    cursor = {x = 1, y = 1}, activeWorkspace = 1, theme = "dark", layoutScale = 1,
    locked = false, state = endpoint.connected and "active" or "disconnected",
    generation = endpoint.generation, createdAt = self.clock(), inputQueueDepth = 0,
  }
  session.windowManager = factory(session)
  self.sessions[id] = session; self.endpointIndex[endpoint.id] = id
  return session
end

function Sessions:_endpointChanged(action, endpoint)
  local session = self:getByEndpoint(endpoint.id)
  if not session and endpoint.connected then session = self:_new(endpoint) end
  if not session then return end
  session.generation = endpoint.generation
  session.screenAddress = endpoint.screenAddress
  session.keyboards = endpoint.keyboards
  if action == "disconnected" then session.state = "disconnected"
  elseif endpoint.connected then session.state = "active" end
end

function Sessions:sync()
  for _, endpoint in ipairs(self.registry:list()) do
    if not self:getByEndpoint(endpoint.id) and endpoint.connected then self:_new(endpoint) end
  end
end

function Sessions:get(id) return self.sessions[id] end

function Sessions:getByEndpoint(endpointId)
  local id = self.endpointIndex[endpointId]
  return id and self.sessions[id] or nil
end

function Sessions:restart(id)
  local session = self.sessions[id]
  if not session then return nil, "unknown session" end
  local endpoint = self.registry:get(session.endpointId)
  if not endpoint then return nil, "endpoint unavailable" end
  local oldManager = session.windowManager
  session.windowManager = (self.windowManagerFactory or function(item)
    return WindowManager.new(item, {logger = self.logger})
  end)(session)
  session.focusedWindow, session.clipboard, session.notifications = nil, "", {}
  endpoint.generation = endpoint.generation + 1
  session.generation, session.state = endpoint.generation, endpoint.connected and "active" or "disconnected"
  if oldManager and oldManager.closeAll then oldManager:closeAll("session restart") end
  return session
end

function Sessions:list()
  local out = {}
  for _, session in pairs(self.sessions) do out[#out + 1] = session end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

return Sessions
