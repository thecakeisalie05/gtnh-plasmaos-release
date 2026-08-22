local Queue = require("libs.queue")

local IPC = {}
IPC.__index = IPC

function IPC.new(options)
  options = options or {}
  return setmetatable({
    endpoints = {},
    mailboxLimit = options.mailboxLimit or 32,
    nextRequest = 1,
    clock = options.clock or os.clock,
  }, IPC)
end

function IPC:register(name, handler)
  assert(not self.endpoints[name], "endpoint already registered")
  self.endpoints[name] = {handler = handler, queue = Queue.new(self.mailboxLimit)}
end

function IPC:unregister(name) self.endpoints[name] = nil end

function IPC:send(target, payload, envelope)
  local endpoint = self.endpoints[target]
  if not endpoint then return nil, "endpoint unavailable" end
  envelope = envelope or {}
  envelope.target = target
  envelope.timestamp = envelope.timestamp or self.clock()
  envelope.payload = payload
  return endpoint.queue:push(envelope)
end

function IPC:request(target, payload, timeout)
  local id = tostring(self.nextRequest); self.nextRequest = self.nextRequest + 1
  local ok, err = self:send(target, payload, {requestId = id, expiry = self.clock() + (timeout or 5)})
  if not ok then return nil, err end
  return id
end

function IPC:drain(target, limit)
  local endpoint = self.endpoints[target]
  if not endpoint then return 0 end
  local count = 0
  while count < (limit or 8) do
    local message = endpoint.queue:pop()
    if not message then break end
    if not message.expiry or message.expiry >= self.clock() then pcall(endpoint.handler, message) end
    count = count + 1
  end
  return count
end

return IPC
