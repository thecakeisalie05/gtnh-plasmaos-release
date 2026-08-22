local Queue = {}
Queue.__index = Queue

function Queue.new(capacity, merge)
  assert(type(capacity) == "number" and capacity > 0, "capacity must be positive")
  return setmetatable({
    capacity = capacity,
    merge = merge,
    data = {},
    head = 1,
    tail = 1,
    count = 0,
    dropped = 0,
    coalesced = 0,
    highWater = 0,
  }, Queue)
end

function Queue:size()
  return self.count
end

function Queue:isEmpty()
  return self.count == 0
end

function Queue:push(value)
  if self.count > 0 and self.merge then
    local last = ((self.tail - 2) % self.capacity) + 1
    local merged = self.merge(self.data[last], value)
    if merged ~= nil then
      self.data[last] = merged
      self.coalesced = self.coalesced + 1
      return true, "coalesced"
    end
  end
  if self.count == self.capacity then
    self.dropped = self.dropped + 1
    return false, "full"
  end
  self.data[self.tail] = value
  self.tail = (self.tail % self.capacity) + 1
  self.count = self.count + 1
  if self.count > self.highWater then self.highWater = self.count end
  return true
end

function Queue:pop()
  if self.count == 0 then return nil end
  local value = self.data[self.head]
  self.data[self.head] = nil
  self.head = (self.head % self.capacity) + 1
  self.count = self.count - 1
  return value
end

function Queue:peek()
  if self.count == 0 then return nil end
  return self.data[self.head]
end

function Queue:clear()
  self.data = {}
  self.head, self.tail, self.count = 1, 1, 0
end

function Queue:values()
  local out = {}
  local index = self.head
  for i = 1, self.count do
    out[i] = self.data[index]
    index = (index % self.capacity) + 1
  end
  return out
end

return Queue
