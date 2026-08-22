local Theme = require("ui.theme")

local Desktop = {}
Desktop.__index = Desktop

local function intersection(a, b)
  local x, y = math.max(a.x, b.x), math.max(a.y, b.y)
  local right = math.min(a.x + a.w - 1, b.x + b.w - 1)
  local bottom = math.min(a.y + a.h - 1, b.y + b.h - 1)
  if right < x or bottom < y then return nil end
  return {x = x, y = y, w = right - x + 1, h = bottom - y + 1}
end

local function append(commands, command) commands[#commands + 1] = command end

local function clippedText(commands, dirty, x, y, text, foreground, background)
  if y < dirty.y or y >= dirty.y + dirty.h then return end
  local left, right = math.max(x, dirty.x), math.min(x + #text - 1, dirty.x + dirty.w - 1)
  if right < left then return end
  append(commands, {op = "set", x = left, y = y,
    text = text:sub(left - x + 1, right - x + 1), foreground = foreground, background = background})
end

function Desktop.new(options)
  options = options or {}
  return setmetatable({compositor = options.compositor, registry = options.registry,
    sessions = options.sessions, apps = options.apps, notifications = options.notifications,
    clock = options.clock or os.time, debug = {}, modifiers = {}, launcher = {},
    lastMinute = nil, uptime = options.uptime or os.clock}, Desktop)
end

function Desktop:_builder(session)
  return function(endpoint, regions) return self:build(endpoint, session, regions) end
end

function Desktop:attach(session)
  local endpoint = self.registry:get(session.endpointId); if not endpoint then return nil end
  session.windowManager:setGeometry(endpoint.width, endpoint.height - 1)
  session.windowManager.damage = function(rect)
    self.compositor:request(endpoint.id, rect, self:_builder(session))
  end
  return self.compositor:request(endpoint.id, nil, self:_builder(session))
end

function Desktop:request(session, rect)
  return self.compositor:request(session.endpointId, rect, self:_builder(session))
end

function Desktop:_window(commands, dirty, window, focused, colors)
  local rect = {x = window.x, y = window.y, w = window.w, h = window.h}
  local body = intersection(dirty, rect); if not body then return end
  append(commands, {op = "fill", x = body.x, y = body.y, w = body.w, h = body.h,
    char = " ", background = colors.raised, foreground = colors.foreground})
  local titleRect = intersection(dirty, {x = window.x, y = window.y, w = window.w, h = 1})
  if titleRect then append(commands, {op = "fill", x = titleRect.x, y = titleRect.y,
    w = titleRect.w, h = 1, char = " ", background = focused and colors.titleActive or colors.titleInactive}) end
  local title = " " .. window.title
  clippedText(commands, dirty, window.x, window.y, title, colors.foreground,
    focused and colors.titleActive or colors.titleInactive)
  clippedText(commands, dirty, window.x + window.w - 5, window.y, "_ [] X", colors.foreground,
    focused and colors.titleActive or colors.titleInactive)
  local lines = window.render and window.render(window) or {}
  for index = 1, math.min(#lines, window.h - 2) do
    local value = type(lines[index]) == "table" and lines[index].text or tostring(lines[index])
    local fg = type(lines[index]) == "table" and lines[index].foreground or colors.foreground
    clippedText(commands, dirty, window.x + 1, window.y + index, value:sub(1, math.max(0, window.w - 2)),
      fg, colors.raised)
  end
end

function Desktop:_panel(commands, dirty, endpoint, session, colors)
  local y = endpoint.height
  local panel = intersection(dirty, {x = 1, y = y, w = endpoint.width, h = 1}); if not panel then return end
  append(commands, {op = "fill", x = panel.x, y = y, w = panel.w, h = 1,
    char = " ", background = colors.panel, foreground = colors.foreground})
  local tasks = {}
  for _, window in ipairs(session.windowManager:list()) do
    tasks[#tasks + 1] = (window.id == session.focusedWindow and "[" or " ") .. window.title:sub(1, 9)
      .. (window.id == session.focusedWindow and "]" or " ")
  end
  local left = "[P] " .. table.concat(tasks, " ")
  clippedText(commands, dirty, 1, y, left, colors.foreground, colors.panel)
  local health = self.registry:get(session.endpointId)
  local clock = os.date and os.date("%H:%M") or tostring(math.floor(os.clock()))
  local right = (health and health.lowBandwidth and " REMOTE " or " LOCAL ") .. clock
  clippedText(commands, dirty, math.max(1, endpoint.width - #right + 1), y, right,
    health and health.state == "active" and colors.success or colors.warning, colors.panel)
end

function Desktop:_overlay(commands, dirty, endpoint, session, colors)
  if not self.debug[session.id] then return end
  local metrics = self.compositor:metrics(endpoint.id)
  local lines = {"DEBUG " .. session.id, "screen " .. endpoint.screenAddress:sub(1, 8),
    "gen " .. endpoint.generation .. " " .. endpoint.width .. "x" .. endpoint.height,
    "renderQ " .. metrics.queueDepth .. " dirty " .. metrics.dirtyRegions,
    "inputQ " .. (session.inputQueueDepth or 0), "state " .. endpoint.state}
  local width = 24
  for index, line in ipairs(lines) do
    local y = index
    local rect = intersection(dirty, {x = endpoint.width - width + 1, y = y, w = width, h = 1})
    if rect then append(commands, {op = "fill", x = rect.x, y = y, w = rect.w, h = 1,
      char = " ", background = colors.panel}); clippedText(commands, dirty,
        endpoint.width - width + 2, y, line:sub(1, width - 2), colors.warning, colors.panel) end
  end
end

function Desktop:_toast(commands, dirty, endpoint, session, colors)
  local toast = session.toast
  if not toast or toast.expires <= self.uptime() then return end
  local width = math.min(34, endpoint.width - 2)
  local x, y = endpoint.width - width, math.max(2, endpoint.height - 5)
  local rect = intersection(dirty, {x=x,y=y,w=width,h=3}); if not rect then return end
  append(commands,{op="fill",x=rect.x,y=rect.y,w=rect.w,h=rect.h,char=" ",background=colors.panel})
  clippedText(commands,dirty,x+1,y,"["..toast.item.severity.."] "..toast.item.title,colors.accent,colors.panel)
  clippedText(commands,dirty,x+1,y+1,tostring(toast.item.message):sub(1,width-2),colors.foreground,colors.panel)
end

function Desktop:build(endpoint, session, regions)
  local colors = Theme.get(session.theme)
  local commands = {}
  if #regions == 0 then regions = {{x = 1, y = 1, w = endpoint.width, h = endpoint.height}} end
  for _, dirty in ipairs(regions) do
    append(commands, {op = "fill", x = dirty.x, y = dirty.y, w = dirty.w, h = dirty.h,
      char = " ", background = colors.desktop, foreground = colors.foreground})
    clippedText(commands, dirty, 3, 2, "GTNH PlasmaOS", colors.secondary, colors.desktop)
    if session.locked then
      clippedText(commands,dirty,math.max(2,math.floor(endpoint.width/2)-8),math.floor(endpoint.height/2),"SESSION LOCKED",colors.warning,colors.desktop)
      clippedText(commands,dirty,math.max(2,math.floor(endpoint.width/2)-11),math.floor(endpoint.height/2)+2,"Press Enter to unlock",colors.foreground,colors.desktop)
    else
      for _, window in ipairs(session.windowManager:list()) do
        if window.state ~= "minimized" then self:_window(commands, dirty, window,
          window.id == session.focusedWindow, colors) end
      end
    end
    self:_panel(commands, dirty, endpoint, session, colors)
    self:_toast(commands,dirty,endpoint,session,colors)
    self:_overlay(commands, dirty, endpoint, session, colors)
  end
  return commands
end

function Desktop:toggleLauncher(session)
  local existing = self.launcher[session.id]
  if existing and session.windowManager.windows[existing] then
    session.windowManager:close(existing); self.launcher[session.id] = nil; return
  end
  local appList = self.apps:list()
  local lines = {"Applications"}
  for index, app in ipairs(appList) do lines[#lines + 1] = string.format("%2d  %s", index, app.name) end
  lines[#lines + 1] = ""; lines[#lines + 1] = "F2 Terminal  F3 Files  F4 Tasks"
  local window
  window = session.windowManager:create({title = "Application Launcher", x = 2,
    y = math.max(2, session.windowManager.height - math.min(16, #lines + 2) + 1),
    w = math.min(42, session.windowManager.width - 2), h = math.min(16, #lines + 2),
    render = function() return lines end,
    onEvent = function(_, event)
      if event.name == "touch" then
        local index = event.localY - 1
        if appList[index] then self.apps:launch(appList[index].id, session.id); session.windowManager:close(window.id); self.launcher[session.id] = nil end
      end
    end})
  self.launcher[session.id] = window.id
end

function Desktop:globalShortcut(session, event)
  local modifiers = self.modifiers[session.id] or {}; self.modifiers[session.id] = modifiers
  if event.name == "key_down" then
    if session.locked then
      if event.code == 28 then session.locked=false;self:request(session) end
      return true
    end
    if event.code == 56 then modifiers.alt = true; return true end
    if event.code == 29 then modifiers.ctrl = true; return true end
    if modifiers.alt and event.code == 15 then session.windowManager:cycle(); return true end
    if modifiers.ctrl and (event.char == 108 or event.char == 76) then session.locked=true;self:request(session);return true end
    if event.code == 59 then self:toggleLauncher(session); return true end
    if event.code == 60 then self.apps:launch("terminal", session.id); return true end
    if event.code == 61 then self.apps:launch("files", session.id); return true end
    if event.code == 62 then self.apps:launch("tasks", session.id); return true end
    if event.code == 88 then self.debug[session.id] = not self.debug[session.id]; self:request(session); return true end
  elseif event.name == "key_up" then
    if event.code == 56 then modifiers.alt = nil; return true end
    if event.code == 29 then modifiers.ctrl = nil; return true end
  end
  return false
end

function Desktop:handle(session, event)
  local endpoint = self.registry:get(session.endpointId)
  if event.name == "touch" and endpoint and event.y == endpoint.height and event.x <= 3 then
    self:toggleLauncher(session); return
  end
  return session.windowManager:handle(event)
end

function Desktop:tick()
  local minute = math.floor((os.time and os.time() or os.clock()) / 60)
  if minute ~= self.lastMinute then
    self.lastMinute = minute
    for _, session in ipairs(self.sessions:list()) do
      local endpoint = self.registry:get(session.endpointId)
      if endpoint and session.state == "active" then self:request(session,
        {x = math.max(1, endpoint.width - 20), y = endpoint.height, w = 20, h = 1}) end
    end
  end
  for _,session in ipairs(self.sessions:list())do
    if session.toast and session.toast.expires<=self.uptime()then
      local endpoint=self.registry:get(session.endpointId);session.toast=nil
      if endpoint then self:request(session,{x=math.max(1,endpoint.width-36),y=math.max(1,endpoint.height-6),w=36,h=5})end
    end
  end
end

return Desktop
