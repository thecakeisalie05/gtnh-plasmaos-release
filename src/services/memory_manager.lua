local Memory = {}
Memory.__index = Memory

function Memory.new(options)
  options = options or {}
  return setmetatable({free = options.free, total = options.total,
    warningRatio = options.warningRatio or 0.20, criticalRatio = options.criticalRatio or 0.10,
    state = "normal", trimmers = {}, onState = options.onState}, Memory)
end

function Memory:registerTrimmer(name, callback, priority)
  self.trimmers[#self.trimmers + 1] = {name = name, callback = callback, priority = priority or 0}
  table.sort(self.trimmers, function(a, b) return a.priority > b.priority end)
end

function Memory:sample()
  local free, total = self.free(), self.total()
  local ratio = total > 0 and free / total or 0
  local state = ratio <= self.criticalRatio and "critical" or ratio <= self.warningRatio and "warning" or "normal"
  if state ~= self.state then
    self.state = state
    if state ~= "normal" then for _, trimmer in ipairs(self.trimmers) do pcall(trimmer.callback, state) end end
    if self.onState then pcall(self.onState, state, free, total) end
  end
  return {free = free, total = total, ratio = ratio, state = state}
end

function Memory:canLaunch(essential)
  return self.state ~= "critical" or essential
end

return Memory
