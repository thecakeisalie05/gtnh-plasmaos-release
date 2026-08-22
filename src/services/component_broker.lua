local Queue = require("libs.queue")
local Ring = require("libs.ring")
local unpack = table.unpack or unpack

local Broker = {}
Broker.__index = Broker

function Broker.new(componentApi, options)
  options = options or {}
  return setmetatable({api = componentApi, capabilities = options.capabilities,
    logger = options.logger, pending = Queue.new(options.queueLimit or 32),
    history = Ring.new(options.historyLimit or 64), methodCache = {},
    maxCallsPerStep = options.maxCallsPerStep or 2}, Broker)
end

function Broker:list(filter)
  return self.api.list(filter)
end

function Broker:proxy(address)
  local ok, value = pcall(self.api.proxy, address)
  if not ok then return nil, value end
  return value
end

function Broker:invoke(address, method, ...)
  local result = {pcall(self.api.invoke, address, method, ...)}
  if not result[1] then return nil, result[2] end
  table.remove(result, 1)
  return true, unpack(result)
end

function Broker:methods(address)
  if self.methodCache[address] then return self.methodCache[address] end
  local ok, methods = pcall(self.api.methods, address)
  if not ok then return nil, methods end
  self.methodCache[address] = methods
  return methods
end

function Broker:invalidate(address)
  self.methodCache[address] = nil
end

function Broker:request(subject, address, method, args, mode, callback)
  mode = mode or "read"
  if self.capabilities then
    local ok, err = self.capabilities:require(subject, "component." .. mode,
      {address = address, method = method})
    if not ok then return nil, err end
  end
  return self.pending:push({subject = subject, address = address, method = method,
    args = args or {}, mode = mode, callback = callback})
end

function Broker:step(limit)
  local count = 0
  while count < (limit or self.maxCallsPerStep) do
    local request = self.pending:pop(); if not request then break end
    local result = {self:invoke(request.address, request.method, unpack(request.args))}
    local ok = result[1]
    self.history:push({subject = request.subject, address = request.address,
      method = request.method, mode = request.mode, ok = not not ok})
    if request.mode == "control" and self.logger then
      self.logger:write(ok and "info" or "error", "audit", "component control action",
        {subject = request.subject, address = request.address, method = request.method, ok = not not ok})
    end
    if request.callback then pcall(request.callback, unpack(result)) end
    count = count + 1
  end
  return count
end

function Broker:snapshot()
  local out = {}
  for address, kind in self:list() do
    local methods = self:methods(address)
    local names = {}
    if type(methods) == "table" then for name in pairs(methods) do names[#names + 1] = name end end
    table.sort(names)
    out[#out + 1] = {address = address, type = kind, methods = names}
  end
  table.sort(out, function(a, b) return a.address < b.address end)
  return out
end

return Broker
