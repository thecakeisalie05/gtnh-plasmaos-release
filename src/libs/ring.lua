local Ring = {}
Ring.__index = Ring

function Ring.new(capacity)
  assert(type(capacity) == "number" and capacity > 0, "capacity must be positive")
  return setmetatable({capacity = capacity, data = {}, next = 1, count = 0}, Ring)
end

function Ring:push(value)
  self.data[self.next] = value
  self.next = (self.next % self.capacity) + 1
  if self.count < self.capacity then self.count = self.count + 1 end
end

function Ring:values()
  local out = {}
  local start = self.count == self.capacity and self.next or 1
  for i = 1, self.count do
    local index = ((start + i - 2) % self.capacity) + 1
    out[i] = self.data[index]
  end
  return out
end

function Ring:clear()
  self.data, self.next, self.count = {}, 1, 0
end

return Ring
