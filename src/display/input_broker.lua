local Queue = require("libs.queue")

local Input = {}
Input.__index = Input

local screenEvents = {touch = true, drag = true, drop = true, scroll = true, walk = true, screen_resize = true}
local keyboardEvents = {key_down = true, key_up = true, clipboard = true}

local function merge(previous, incoming)
  if previous and incoming and previous.name == incoming.name
    and (incoming.name == "drag" or incoming.name == "scroll")
    and previous.address == incoming.address and previous.player == incoming.player then return incoming end
end

function Input.new(registry, sessions, options)
  options = options or {}
  return setmetatable({registry = registry, sessions = sessions, queues = {},
    capacity = options.capacity or 48, logger = options.logger,
    dispatch = options.dispatch, globalShortcut = options.globalShortcut,
    rawReceived = 0, normalizedDispatched = 0, routeFailures = 0}, Input)
end

function Input:_queue(sessionId)
  if not self.queues[sessionId] then self.queues[sessionId] = Queue.new(self.capacity, merge) end
  return self.queues[sessionId]
end

function Input:route(event)
  if not screenEvents[event.name] and not keyboardEvents[event.name] then return false end
  self.rawReceived = self.rawReceived + 1
  local address = event.args[1]
  local endpoint = self.registry:byInput(address)
  if not endpoint or not endpoint.connected then self.routeFailures = self.routeFailures + 1; return nil, "unmapped input" end
  local session = self.sessions:getByEndpoint(endpoint.id)
  if not session or session.state ~= "active" then self.routeFailures = self.routeFailures + 1; return nil, "inactive session" end
  local normalized = {name = event.name, address = address, sessionId = session.id,
    endpointId = endpoint.id, generation = endpoint.generation, time = event.time}
  if screenEvents[event.name] then
    normalized.x, normalized.y, normalized.button = event.args[2], event.args[3], event.args[4]
    normalized.player = event.args[5]
  else
    normalized.char, normalized.code, normalized.player = event.args[2], event.args[3], event.args[4]
    if event.name == "clipboard" then normalized.text, normalized.player = event.args[2], event.args[3] end
  end
  endpoint.lastInput = event.time or os.clock()
  local ok, err = self:_queue(session.id):push(normalized)
  session.inputQueueDepth = self:_queue(session.id):size()
  return ok, err
end

function Input:drain(sessionId, limit)
  local session = self.sessions:get(sessionId)
  local queue = self:_queue(sessionId)
  local count = 0
  while count < (limit or 16) do
    local event = queue:pop(); if not event then break end
    local endpoint = self.registry:get(event.endpointId)
    if endpoint and endpoint.connected and endpoint.generation == event.generation then
      local intercepted = false
      if self.globalShortcut then
        local ok, result = pcall(self.globalShortcut, session, event)
        intercepted = ok and result or false
      end
      if session.locked and not intercepted then intercepted = true end
      if not intercepted and self.dispatch then
        local ok, err = pcall(self.dispatch, session, event)
        if not ok and self.logger then self.logger:write("error", "input", "application dispatch failed",
          {session = sessionId, error = tostring(err)}) end
      end
      self.normalizedDispatched = self.normalizedDispatched + 1
    end
    count = count + 1
  end
  if session then session.inputQueueDepth = queue:size() end
  return count
end

function Input:clear(sessionId) self:_queue(sessionId):clear() end

function Input:metrics(sessionId)
  local queue = self:_queue(sessionId)
  return {depth = queue:size(), capacity = queue.capacity, dropped = queue.dropped,
    coalesced = queue.coalesced, rawReceived = self.rawReceived,
    normalizedDispatched = self.normalizedDispatched, routeFailures = self.routeFailures}
end

return Input
