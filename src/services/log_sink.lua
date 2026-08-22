local Queue = require("libs.queue")
local Json = require("libs.json")

local Sink = {}
Sink.__index = Sink

function Sink.new(fs, options)
  options = options or {}
  local path = options.path or "/var/log/plasmaos/system.log"
  local existing = fs.read(path)
  return setmetatable({fs = fs, path = path, maxBytes = options.maxBytes or 32768,
    rotations = options.rotations or 3, queue = Queue.new(options.queueLimit or 64),
    size = existing and #existing or 0, writeErrors = 0,
    maxEntryBytes = math.min(options.maxEntryBytes or 4096, options.maxBytes or 32768)}, Sink)
end

function Sink:enqueue(entry)
  local safe = {seq=entry.seq,time=entry.time,level=entry.level,source=entry.source,
    message=tostring(entry.message),fields=entry.fields}
  local ok, encoded = pcall(Json.encode, safe)
  if not ok or #encoded + 1 > self.maxEntryBytes then
    safe.fields = {truncated = true}
    safe.message = ""
    local overhead = #Json.encode(safe) + 1
    local available = math.max(0, self.maxEntryBytes - overhead)
    safe.message = tostring(entry.message):sub(1, available)
    encoded = Json.encode(safe)
  end
  return self.queue:push(encoded .. "\n")
end

function Sink:_rotate()
  self.fs.remove(self.path .. "." .. self.rotations)
  for index = self.rotations - 1, 1, -1 do
    if self.fs.exists(self.path .. "." .. index) then
      self.fs.rename(self.path .. "." .. index, self.path .. "." .. (index + 1))
    end
  end
  if self.fs.exists(self.path) then self.fs.rename(self.path, self.path .. ".1") end
  self.size = 0
end

function Sink:step(limit)
  local count = 0
  while count < (limit or 8) do
    local line = self.queue:pop(); if not line then break end
    if self.size + #line > self.maxBytes then self:_rotate() end
    local handle, err = self.fs.open(self.path, "ab")
    if not handle then self.writeErrors = self.writeErrors + 1; return nil, err end
    local ok, writeErr = handle:write(line); handle:close()
    if not ok then self.writeErrors = self.writeErrors + 1; return nil, writeErr end
    self.size = self.size + #line; count = count + 1
  end
  return count
end

return Sink
