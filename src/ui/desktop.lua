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

local function rowColors(row, colors)
  local foreground = row.foreground or (row.role and colors[row.role]) or colors.foreground
  local background = row.background or (row.backgroundRole and colors[row.backgroundRole]) or colors.surface
  if row.selected then foreground, background = colors.chromeText, colors.selection end
  if row.style == "header" then foreground, background = colors.chromeText, colors.titleActive
  elseif row.style == "toolbar" then foreground, background = colors.foreground, colors.raised
  elseif row.style == "status" then foreground, background = colors.secondary, colors.field
  elseif row.style == "danger" then foreground, background = colors.chromeText, colors.error
  elseif row.style == "success" then foreground, background = colors.chromeText, colors.success end
  return foreground, background
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
  -- The shadow and solid color planes create window depth without relying on
  -- character-art borders.
  local shadow = intersection(dirty, {x = window.x + 1, y = window.y + 1, w = window.w, h = window.h})
  if shadow then append(commands, {op = "fill", x = shadow.x, y = shadow.y, w = shadow.w,
    h = shadow.h, char = " ", background = colors.shadow}) end
  append(commands, {op = "fill", x = body.x, y = body.y, w = body.w, h = body.h,
    char = " ", background = focused and colors.border or colors.titleInactive, foreground = colors.foreground})
  local interior = intersection(dirty, {x = window.x + 1, y = window.y + 1,
    w = math.max(1, window.w - 2), h = math.max(1, window.h - 2)})
  if interior then append(commands, {op = "fill", x = interior.x, y = interior.y,
    w = interior.w, h = interior.h, char = " ", background = colors.surface}) end
  local titleRect = intersection(dirty, {x = window.x, y = window.y, w = window.w, h = 1})
  if titleRect then append(commands, {op = "fill", x = titleRect.x, y = titleRect.y,
    w = titleRect.w, h = 1, char = " ", background = focused and colors.titleActive or colors.titleInactive}) end
  local title = "  " .. window.title
  clippedText(commands, dirty, window.x, window.y, title, colors.chromeText,
    focused and colors.titleActive or colors.titleInactive)
  local controlY = window.y
  local controls = {{x = window.x + window.w - 14, text = " MIN ", bg = colors.titleInactive},
    {x = window.x + window.w - 9, text = " MAX ", bg = colors.selection},
    {x = window.x + window.w - 4, text = "  X  ", bg = colors.error}}
  for _, control in ipairs(controls) do
    local controlRect = intersection(dirty, {x = control.x, y = controlY, w = 5, h = 1})
    if controlRect then append(commands, {op = "fill", x = controlRect.x, y = controlY,
      w = controlRect.w, h = 1, char = " ", background = control.bg}) end
    clippedText(commands, dirty, control.x, controlY, control.text, colors.chromeText, control.bg)
  end
  local lines = window.render and window.render(window) or {}
  for index = 1, math.min(#lines, window.h - 2) do
    local row = type(lines[index]) == "table" and lines[index] or {text = tostring(lines[index])}
    local value = tostring(row.text or "")
    local fg, bg = rowColors(row, colors)
    local rowRect = intersection(dirty, {x = window.x + 1, y = window.y + index,
      w = math.max(1, window.w - 2), h = 1})
    if rowRect then append(commands, {op = "fill", x = rowRect.x, y = rowRect.y,
      w = rowRect.w, h = 1, char = " ", background = bg, foreground = fg}) end
    local pad = row.pad == false and 0 or (row.indent or 1)
    local available = math.max(0, window.w - pad - 2)
    local x = window.x + 1 + pad
    if row.align == "right" then x = math.max(window.x + 1, window.x + window.w - #value - 1) end
    if row.segments then
      local segmentX = window.x + 2
      for segmentIndex, segment in ipairs(row.segments) do
        local text = tostring(segment.text or "")
        local segmentFg = (segment.role and colors[segment.role]) or colors.foreground
        local segmentBg = (segment.backgroundRole and colors[segment.backgroundRole])
          or (segment.primary and colors.titleActive or colors.raised)
        if segment.disabled then segmentFg, segmentBg = colors.secondary, colors.field end
        local segmentRect = intersection(dirty, {x = segmentX, y = window.y + index, w = #text, h = 1})
        if segmentRect then append(commands, {op = "fill", x = segmentRect.x, y = segmentRect.y,
          w = segmentRect.w, h = 1, char = " ", background = segmentBg}) end
        clippedText(commands, dirty, segmentX, window.y + index, text, segmentFg, segmentBg)
        segmentX = segmentX + #text + 1
        if segmentX >= window.x + window.w - 1 then break end
      end
    else
      clippedText(commands, dirty, x, window.y + index, value:sub(1, available), fg, bg)
    end
  end
end

function Desktop:_panel(commands, dirty, endpoint, session, colors)
  local y = endpoint.height
  local panel = intersection(dirty, {x = 1, y = y, w = endpoint.width, h = 1}); if not panel then return end
  append(commands, {op = "fill", x = panel.x, y = y, w = panel.w, h = 1,
    char = " ", background = colors.panel, foreground = colors.foreground})
  local windows = session.windowManager:list()
  local plasmaWidth = math.min(12, endpoint.width)
  local plasmaRect = intersection(dirty, {x = 1, y = y, w = plasmaWidth, h = 1})
  if plasmaRect then append(commands, {op = "fill", x = plasmaRect.x, y = y, w = plasmaRect.w,
    h = 1, char = " ", background = colors.titleActive}) end
  clippedText(commands, dirty, 2, y, "PLASMA", colors.chromeText, colors.titleActive)
  local taskX, taskWidth = plasmaWidth + 2, 14
  for _, window in ipairs(windows) do
    local active = window.id == session.focusedWindow
    local background = active and colors.selection or colors.raised
    local taskRect = intersection(dirty, {x = taskX, y = y, w = taskWidth, h = 1})
    if taskRect then append(commands, {op = "fill", x = taskRect.x, y = y, w = taskRect.w,
      h = 1, char = " ", background = background}) end
    clippedText(commands, dirty, taskX + 1, y, window.title:sub(1, taskWidth - 2),
      active and colors.chromeText or colors.foreground, background)
    taskX = taskX + taskWidth + 1
  end
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
    -- A quiet, color-led desktop canvas.  Labels are deliberately sparse so
    -- windows and live plant information remain the focus.
    clippedText(commands, dirty, 4, 3, "PlasmaOS", colors.accent, colors.desktop)
    clippedText(commands, dirty, 4, 4, "GT New Horizons control desktop", colors.secondary, colors.desktop)
    clippedText(commands, dirty, 4, 7, "F1  Applications", colors.foreground, colors.desktop)
    clippedText(commands, dirty, 4, 8, "F2  Terminal", colors.foreground, colors.desktop)
    clippedText(commands, dirty, 4, 9, "F3  Files", colors.foreground, colors.desktop)
    clippedText(commands, dirty, 4, 10, "F4  System Monitor", colors.foreground, colors.desktop)
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
  local selected, scroll, visible = 1, 1, 18
  local function rows()
    local lines = {{text = "  Applications", style = "header", pad = false},
      {text = "  Choose an application", style = "toolbar", pad = false}}
    local stop = math.min(#appList, scroll + visible - 1)
    for index = scroll, stop do
      local app = appList[index]
      lines[#lines + 1] = {text = string.format("  %-28s %s", app.name, app.category or ""),
        selected = index == selected, pad = false}
    end
    if #appList == 0 then lines[#lines + 1] = {text = "  No applications installed", role = "secondary"} end
    lines[#lines + 1] = {text = "  Enter: open    Esc: close    F2-F4: quick launch", style = "status", pad = false}
    return lines
  end
  local window
  window = session.windowManager:create({title = "Application Launcher", x = 2,
    y = math.max(2, session.windowManager.height - math.min(24, #appList + 5) + 1),
    w = math.min(52, session.windowManager.width - 2), h = math.min(24, #appList + 5),
    render = rows,
    onEvent = function(_, event)
      if event.name == "touch" and event.localY >= 3 and event.localY < visible + 3 then
        selected = math.min(#appList, scroll + event.localY - 3)
        local app = appList[selected]
        if app then self.apps:launch(app.id, session.id); session.windowManager:close(window.id); self.launcher[session.id] = nil end
      elseif event.name == "key_down" then
        if event.code == 200 then selected = math.max(1, selected - 1)
        elseif event.code == 208 then selected = math.min(#appList, selected + 1)
        elseif event.code == 28 and appList[selected] then self.apps:launch(appList[selected].id, session.id); session.windowManager:close(window.id); self.launcher[session.id] = nil
        elseif event.code == 1 then session.windowManager:close(window.id); self.launcher[session.id] = nil end
        if selected < scroll then scroll = selected elseif selected >= scroll + visible then scroll = selected - visible + 1 end
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
  if event.name == "touch" and endpoint and event.y == endpoint.height then
    if event.x <= 12 then self:toggleLauncher(session); return end
    local taskX, taskWidth = math.min(12, endpoint.width) + 2, 14
    for _, window in ipairs(session.windowManager:list()) do
      if event.x >= taskX and event.x < taskX + taskWidth then
        if window.state == "minimized" then session.windowManager:restore(window.id)
        else session.windowManager:focus(window.id) end
        return
      end
      taskX = taskX + taskWidth + 1
    end
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
