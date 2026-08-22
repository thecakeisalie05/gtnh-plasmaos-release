local WindowManager = {}
WindowManager.__index = WindowManager

local function clamp(value, low, high) return math.max(low, math.min(high, value)) end

function WindowManager.new(session, options)
  options = options or {}
  return setmetatable({session = session, windows = {}, order = {}, nextId = 1,
    width = options.width or 80, height = options.height or 24, logger = options.logger,
    drag = nil, damage = options.damage}, WindowManager)
end

function WindowManager:setGeometry(width, height)
  self.width, self.height = width, math.max(4, height)
  for _, window in pairs(self.windows) do
    window.x = clamp(window.x, 1, math.max(1, width - window.w + 1))
    window.y = clamp(window.y, 1, math.max(1, self.height - window.h + 1))
  end
end

function WindowManager:_dirty(window)
  if self.damage then self.damage(window and {x = window.x, y = window.y, w = window.w + 1, h = window.h + 1}
    or {x = 1, y = 1, w = self.width, h = self.height}) end
end

function WindowManager:create(spec)
  spec = spec or {}
  local id = spec.id or ("window:" .. self.nextId); self.nextId = self.nextId + 1
  local window = {
    id = id, ownerPid = spec.ownerPid, appId = spec.appId or "app", title = spec.title or "Application",
    x = clamp(spec.x or (2 + #self.order * 2), 1, self.width),
    y = clamp(spec.y or (2 + #self.order), 1, self.height),
    w = math.min(spec.w or math.min(60, self.width - 2), self.width),
    h = math.min(spec.h or math.min(18, self.height - 2), self.height),
    minW = spec.minW or 18, minH = spec.minH or 6, state = "normal",
    render = spec.render, onEvent = spec.onEvent, onClose = spec.onClose,
    data = spec.data or {}, previous = nil,
  }
  window.x = clamp(window.x, 1, math.max(1, self.width - window.w + 1))
  window.y = clamp(window.y, 1, math.max(1, self.height - window.h + 1))
  self.windows[id] = window; self.order[#self.order + 1] = id
  self:focus(id); self:_dirty(window)
  return window
end

function WindowManager:focus(id)
  local window = self.windows[id]
  if not window or window.state == "minimized" then return nil end
  for index = #self.order, 1, -1 do
    if self.order[index] == id then table.remove(self.order, index); break end
  end
  self.order[#self.order + 1] = id
  self.session.focusedWindow = id; self:_dirty(window)
  return window
end

function WindowManager:close(id, reason)
  local window = self.windows[id]
  if not window then return nil, "unknown window" end
  self:_dirty(window)
  if window.onClose then pcall(window.onClose, reason or "closed") end
  self.windows[id] = nil
  for index = #self.order, 1, -1 do if self.order[index] == id then table.remove(self.order, index) end end
  self.session.focusedWindow = self.order[#self.order]
  self:_dirty()
  return true
end

function WindowManager:closeByOwner(pid, reason)
  local ids = {}
  for id, window in pairs(self.windows) do if window.ownerPid == pid then ids[#ids + 1] = id end end
  for _, id in ipairs(ids) do self:close(id, reason) end
end

function WindowManager:closeAll(reason)
  local ids = {}; for id in pairs(self.windows) do ids[#ids + 1] = id end
  for _, id in ipairs(ids) do self:close(id, reason) end
end

function WindowManager:minimize(id)
  local window = self.windows[id]; if not window then return nil end
  window.state = "minimized"; self:_dirty(window)
  if self.session.focusedWindow == id then self.session.focusedWindow = nil end
  return true
end

function WindowManager:maximize(id)
  local window = self.windows[id]; if not window then return nil end
  if window.state ~= "maximized" then
    window.previous = {x = window.x, y = window.y, w = window.w, h = window.h}
    window.x, window.y, window.w, window.h = 1, 1, self.width, self.height
    window.state = "maximized"; self:_dirty()
  end
  return true
end

function WindowManager:restore(id)
  local window = self.windows[id]; if not window then return nil end
  if window.state == "minimized" then window.state = "normal"; self:focus(id)
  elseif window.state == "maximized" and window.previous then
    window.x, window.y, window.w, window.h = window.previous.x, window.previous.y,
      window.previous.w, window.previous.h
    window.previous, window.state = nil, "normal"; self:_dirty()
  end
  return true
end

function WindowManager:move(id, x, y)
  local window = self.windows[id]; if not window or window.state ~= "normal" then return nil end
  self:_dirty(window)
  window.x = clamp(x, 1, math.max(1, self.width - window.w + 1))
  window.y = clamp(y, 1, math.max(1, self.height - window.h + 1))
  self:_dirty(window); return true
end

function WindowManager:resize(id, width, height)
  local window = self.windows[id]; if not window or window.state ~= "normal" then return nil end
  self:_dirty(window)
  window.w = clamp(width, window.minW, self.width - window.x + 1)
  window.h = clamp(height, window.minH, self.height - window.y + 1)
  self:_dirty(window); return true
end

function WindowManager:cycle()
  if #self.order < 2 then return end
  local id = table.remove(self.order, #self.order)
  table.insert(self.order, 1, id)
  self.session.focusedWindow = self.order[#self.order]; self:_dirty()
end

function WindowManager:hit(x, y)
  for index = #self.order, 1, -1 do
    local window = self.windows[self.order[index]]
    if window and window.state ~= "minimized" and x >= window.x and x < window.x + window.w
      and y >= window.y and y < window.y + window.h then
      local localX, localY = x - window.x + 1, y - window.y + 1
      local area = localY == 1 and "title" or "content"
      if localY == 1 and localX >= window.w - 2 then area = "close"
      elseif localY == 1 and localX >= window.w - 5 then area = "maximize"
      elseif localY == 1 and localX >= window.w - 8 then area = "minimize"
      elseif localX == window.w and localY == window.h then area = "resize" end
      return window, area, localX, localY
    end
  end
end

function WindowManager:handle(event)
  if event.name == "key_down" or event.name == "key_up" or event.name == "clipboard" then
    local focused = self.windows[self.session.focusedWindow]
    if focused and focused.onEvent then return focused.onEvent(focused, event) end
    return
  end
  if event.name == "touch" then
    local window, area, localX, localY = self:hit(event.x, event.y)
    if not window then return end
    self:focus(window.id)
    if area == "close" then return self:close(window.id)
    elseif area == "maximize" then
      return window.state == "maximized" and self:restore(window.id) or self:maximize(window.id)
    elseif area == "minimize" then return self:minimize(window.id)
    elseif area == "title" and window.state == "normal" then
      self.drag = {kind = "move", id = window.id, dx = event.x - window.x, dy = event.y - window.y}
    elseif area == "resize" and window.state == "normal" then
      self.drag = {kind = "resize", id = window.id, startX = event.x, startY = event.y,
        w = window.w, h = window.h}
    elseif window.onEvent then
      event.localX, event.localY = localX - 1, localY - 1
      return window.onEvent(window, event)
    end
  elseif event.name == "drag" and self.drag then
    if self.drag.kind == "move" then self:move(self.drag.id, event.x - self.drag.dx, event.y - self.drag.dy)
    else self:resize(self.drag.id, self.drag.w + event.x - self.drag.startX,
      self.drag.h + event.y - self.drag.startY) end
  elseif event.name == "drop" then self.drag = nil
  elseif event.name == "scroll" then
    local window, _, localX, localY = self:hit(event.x, event.y)
    if window and window.onEvent then event.localX, event.localY = localX - 1, localY - 1; return window.onEvent(window, event) end
  end
end

function WindowManager:list()
  local out = {}
  for _, id in ipairs(self.order) do if self.windows[id] then out[#out + 1] = self.windows[id] end end
  return out
end

return WindowManager
