local Queue = require("libs.queue")
local Ring = require("libs.ring")

local Network = {}
Network.__index = Network

function Network.new(options)
  options = options or {}
  return setmetatable({node = options.node or "plasma-node", clock = options.clock or os.clock,
    outgoing = Queue.new(options.queueLimit or 32), pending = {}, handlers = {},
    seen = {}, seenOrder = Ring.new(options.dedupeLimit or 128), nextId = 1,
    transport = options.transport, authenticate = options.authenticate,
    logger = options.logger, protocolVersion = 1, rateLimit = options.rateLimit or 8,
    sentThisWindow = 0, windowStarted = 0}, Network)
end

function Network:register(service, handler, privileged)
  self.handlers[service] = {handler = handler, privileged = privileged}
end

function Network:envelope(targetNode, targetService, kind, payload, timeout)
  local id = self.node .. ":" .. self.nextId; self.nextId = self.nextId + 1
  local now = self.clock()
  return {protocolVersion = self.protocolVersion, messageType = kind, requestId = id,
    sourceNode = self.node, sourceService = "client", targetNode = targetNode,
    targetService = targetService, timestamp = now, expiry = now + (timeout or 5), payload = payload}
end

function Network:request(targetNode, targetService, payload, options)
  options = options or {}
  local envelope = self:envelope(targetNode, targetService, "request", payload, options.timeout)
  envelope.optionalAuth = options.auth
  local ok, err = self.outgoing:push(envelope)
  if not ok then return nil, err end
  self.pending[envelope.requestId] = {envelope = envelope, callback = options.callback,
    retries = options.retries or 1, nextAttempt = self.clock()}
  return envelope.requestId
end

function Network:_remember(id)
  if self.seen[id] then return false end
  local values = self.seenOrder:values()
  if #values == self.seenOrder.capacity then self.seen[values[1]] = nil end
  self.seen[id] = true; self.seenOrder:push(id); return true
end

function Network:receive(envelope)
  if type(envelope) ~= "table" or envelope.protocolVersion ~= self.protocolVersion then return nil, "bad envelope" end
  if envelope.expiry and envelope.expiry < self.clock() then return nil, "expired" end
  if envelope.messageType == "response" then
    local pending = self.pending[envelope.requestId]
    if pending then self.pending[envelope.requestId] = nil; if pending.callback then pcall(pending.callback, true, envelope.payload) end end
    return true
  end
  if not self:_remember(envelope.requestId) then return true, "duplicate" end
  local service = self.handlers[envelope.targetService]
  if not service then return nil, "service unavailable" end
  if service.privileged and (not self.authenticate or not self.authenticate(envelope)) then
    if self.logger then self.logger:write("warning", "audit", "unauthorized remote action",
      {source = envelope.sourceNode, service = envelope.targetService}) end
    return nil, "unauthorized"
  end
  local ok, response = pcall(service.handler, envelope.payload, envelope)
  if not ok then return nil, response end
  self.outgoing:push({protocolVersion = self.protocolVersion, messageType = "response",
    requestId = envelope.requestId, sourceNode = self.node, sourceService = envelope.targetService,
    targetNode = envelope.sourceNode, targetService = envelope.sourceService,
    timestamp = self.clock(), expiry = self.clock() + 5, payload = response})
  return true
end

function Network:step(now)
  now = now or self.clock()
  if now - self.windowStarted >= 1 then self.windowStarted, self.sentThisWindow = now, 0 end
  local sent = 0
  while self.sentThisWindow < self.rateLimit do
    local envelope = self.outgoing:pop(); if not envelope then break end
    if self.transport then
      local invoked, delivered = pcall(self.transport, envelope)
      if invoked and delivered then sent = sent + 1 end
    end
    self.sentThisWindow = self.sentThisWindow + 1
  end
  for id, pending in pairs(self.pending) do
    if now > pending.envelope.expiry then
      if pending.retries > 0 then
        pending.retries = pending.retries - 1
        pending.envelope.expiry = now + 5; self.outgoing:push(pending.envelope)
      else
        self.pending[id] = nil
        if pending.callback then pcall(pending.callback, false, "timeout") end
      end
    end
  end
  return sent
end

return Network
