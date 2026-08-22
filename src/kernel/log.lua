local Ring = require("libs.ring")

local Log = {}
Log.__index = Log

function Log.new(options)
  options = options or {}
  return setmetatable({
    clock = options.clock or os.clock,
    entries = Ring.new(options.capacity or 256),
    sink = options.sink,
    sequence = 0,
  }, Log)
end

function Log:write(level, source, message, fields)
  self.sequence = self.sequence + 1
  local entry = {seq = self.sequence, time = self.clock(), level = level,
    source = source, message = tostring(message), fields = fields or {}}
  self.entries:push(entry)
  if self.sink then pcall(self.sink, entry) end
  return entry
end

function Log:list(filter)
  local out = {}
  for _, entry in ipairs(self.entries:values()) do
    if not filter or filter(entry) then out[#out + 1] = entry end
  end
  return out
end

return Log
