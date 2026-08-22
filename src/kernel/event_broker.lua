local Queue = require("libs.queue")

local Broker = {}
Broker.__index = Broker

local function mergeInput(previous, incoming)
  if previous and incoming and previous.name == incoming.name
    and (incoming.name == "drag" or incoming.name == "scroll")
    and previous.args[1] == incoming.args[1]
    and previous.args[5] == incoming.args[5] then
    return incoming
  end
end

function Broker.new(options)
  options = options or {}
  return setmetatable({
    queue = Queue.new(options.capacity or 128, mergeInput),
    subscribers = {},
    nextId = 1,
    logger = options.logger,
    scheduler = options.scheduler,
    dispatchErrors = 0,
  }, Broker)
end

function Broker:subscribe(filter, callback, owner)
  local id = self.nextId; self.nextId = id + 1
  self.subscribers[id] = {filter = filter, callback = callback, owner = owner}
  return id
end

function Broker:unsubscribe(id)
  self.subscribers[id] = nil
end

function Broker:publish(name, ...)
  return self.queue:push({name = name, args = {...}})
end

local function matches(filter, event)
  if filter == nil then return true end
  if type(filter) == "string" then return filter == event.name end
  if type(filter) == "table" then return filter[event.name] == true end
  if type(filter) == "function" then return filter(event) end
  return false
end

function Broker:drain(limit)
  local count = 0
  while count < (limit or 32) do
    local event = self.queue:pop()
    if not event then break end
    if self.scheduler then self.scheduler:deliver(event) end
    for id, subscriber in pairs(self.subscribers) do
      local selected, selection = pcall(matches, subscriber.filter, event)
      if selected and selection then
        local ok, err = pcall(subscriber.callback, event)
        if not ok then
          self.dispatchErrors = self.dispatchErrors + 1
          if self.logger then self.logger:write("error", "event_broker", "subscriber failed",
            {id = id, owner = subscriber.owner, error = tostring(err)}) end
        end
      end
    end
    count = count + 1
  end
  return count
end

function Broker:metrics()
  return {depth = self.queue:size(), capacity = self.queue.capacity,
    dropped = self.queue.dropped, coalesced = self.queue.coalesced,
    dispatchErrors = self.dispatchErrors}
end

return Broker
