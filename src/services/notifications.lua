local Ring = require("libs.ring")

local Notifications = {}
Notifications.__index = Notifications

function Notifications.new(options)
  options = options or {}
  return setmetatable({items = Ring.new(options.limit or 100), nextId = 1,
    clock = options.clock or os.clock, doNotDisturb = false, listeners = {}}, Notifications)
end

function Notifications:push(source, severity, title, message, options)
  options = options or {}
  local item = {id = self.nextId, time = self.clock(), source = source,
    severity = severity or "info", title = title, message = message,
    persistent = options.persistent or severity == "critical", acknowledged = false}
  self.nextId = self.nextId + 1; self.items:push(item)
  for _, listener in pairs(self.listeners) do pcall(listener, item, self.doNotDisturb) end
  return item
end

function Notifications:acknowledge(id, user)
  for _, item in ipairs(self.items:values()) do
    if item.id == id then item.acknowledged = true; item.acknowledgedBy = user; item.acknowledgedAt = self.clock(); return true end
  end
  return nil, "notification not found"
end

function Notifications:onPush(callback) self.listeners[#self.listeners + 1] = callback end
function Notifications:list() return self.items:values() end

return Notifications
