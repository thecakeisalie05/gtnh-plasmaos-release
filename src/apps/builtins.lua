local Builtins = {}

local function charFrom(event, unicode)
  if not event.char or event.char <= 0 then return nil end
  if unicode and unicode.char then return unicode.char(event.char) end
  if event.char < 256 then return string.char(event.char) end
end

local function explorer(context)
  local s, path = context.services, context.options.path or "/home/player"
  local model = {path = path, hidden = false, selected = 1, entries = {}, status = ""}
  function model:refresh()
    local entries, err = s.files:list(self.path, self.hidden)
    self.entries, self.status = entries or {}, err and tostring(err) or ""
    self.selected = math.max(1, math.min(self.selected, math.max(1, #self.entries)))
  end
  function model:render()
    local out = {"Path: " .. self.path, "[Enter] Open  [Backspace] Up  [H] Hidden  [R] Refresh"}
    for index, entry in ipairs(self.entries) do out[#out + 1] = (index == self.selected and "> " or "  ")
      .. (entry.directory and "[D] " or "    ") .. entry.name end
    if self.status ~= "" then out[#out + 1] = "Error: " .. self.status end
    return out
  end
  function model:onEvent(event)
    if event.name == "key_down" then
      if event.code == 200 then self.selected = math.max(1, self.selected - 1)
      elseif event.code == 208 then self.selected = math.min(#self.entries, self.selected + 1)
      elseif event.code == 28 then
        local item = self.entries[self.selected]
        if item and item.directory then self.path = item.path; self.selected = 1; self:refresh()
        elseif item then s.apps:launch("editor", context.session.id, {services = s, path = item.path}) end
      elseif event.code == 14 then self.path = self.path:match("^(.*)/[^/]+/?$") or "/"; if self.path == "" then self.path = "/" end; self:refresh()
      else local char = charFrom(event, s.unicode); if char and char:lower() == "h" then self.hidden = not self.hidden; self:refresh()
        elseif char and char:lower() == "r" then self:refresh() end end
    elseif event.name == "touch" and event.localY >= 3 then
      self.selected = math.max(1, math.min(#self.entries, event.localY - 2))
    end
  end
  model:refresh(); return model
end

local function terminal(context)
  local s = context.services
  local model = {input = "", output = {"GTNH PlasmaOS Terminal", "Type 'help' for commands."},
    history = {}, historyIndex = 1, refreshInterval = nil}
  function model:render()
    local out = {}; local room = 13
    for index = math.max(1, #self.output - room + 1), #self.output do out[#out + 1] = self.output[index] end
    out[#out + 1] = "> " .. self.input .. "_"; return out
  end
  function model:onEvent(event)
    if event.name == "clipboard" then self.input = self.input .. (event.text or "")
    elseif event.name == "key_down" then
      if event.code == 14 then self.input = self.input:sub(1, -2)
      elseif event.code == 28 then
        local line = self.input; self.output[#self.output + 1] = "> " .. line
        if line ~= "" then self.history[#self.history + 1] = line; self.historyIndex = #self.history + 1 end
        local ok, result = pcall(s.shell.execute, s.shell, line, context.session)
        if not ok then result = {"error: " .. tostring(result)} end
        if result.__clear then self.output = {} else for _, value in ipairs(result) do
          for text in tostring(value):gmatch("[^\n]+") do self.output[#self.output + 1] = text end end end
        while #self.output > 100 do table.remove(self.output, 1) end; self.input = ""
      elseif event.code == 200 and #self.history > 0 then self.historyIndex = math.max(1, self.historyIndex - 1); self.input = self.history[self.historyIndex]
      elseif event.code == 208 and #self.history > 0 then self.historyIndex = math.min(#self.history + 1, self.historyIndex + 1); self.input = self.history[self.historyIndex] or ""
      else local char = charFrom(event, s.unicode); if char and char:byte() >= 32 then self.input = self.input .. char end end
    end
  end
  return model
end

local function taskManager(context)
  local s = context.services
  local model = {tab = 1, selected = 1, refreshInterval = 1}
  local names = {"Processes", "Performance", "Services", "Hardware", "Sessions", "Logs"}
  function model:render()
    local out = {table.concat(names, " | "), "View: " .. names[self.tab] .. "  [1-6] switch  [K] kill/restart"}
    if self.tab == 1 then
      for index, process in ipairs(s.scheduler:list()) do out[#out + 1] = (index == self.selected and ">" or " ")
        .. string.format(" %3d %-10s %-10s %s", process.pid, process.state, process.appId:sub(1, 10), process.name) end
    elseif self.tab == 2 then
      local memory = s.memory:sample(); out[#out + 1] = string.format("Memory %d/%d free - %s", memory.free, memory.total, memory.state)
      out[#out + 1] = string.format("Scheduler cycle %d ready=%d", s.scheduler.cycle, s.scheduler.ready:size())
      for _, endpoint in ipairs(s.registry:list()) do local m = s.compositor:metrics(endpoint.id); out[#out + 1] = endpoint.id .. " renderQ=" .. m.queueDepth .. " dirty=" .. m.dirtyRegions end
    elseif self.tab == 3 then for _, service in ipairs(s.supervisor:list()) do out[#out + 1] = string.format("%-18s %-9s restarts=%d", service.id, service.state, service.restartCount) end
    elseif self.tab == 4 then for _, item in ipairs(s.components:snapshot()) do out[#out + 1] = item.address:sub(1, 8) .. " " .. item.type .. " methods=" .. #item.methods end
    elseif self.tab == 5 then for _, item in ipairs(s.sessions:list()) do local endpoint = s.registry:get(item.endpointId); out[#out + 1] = item.id .. " " .. item.state .. " " .. item.endpointId .. " gen=" .. (endpoint and endpoint.generation or 0) .. " inputQ=" .. item.inputQueueDepth end
    else local logs = s.log:list(); for index = math.max(1, #logs - 12), #logs do local item = logs[index]; out[#out + 1] = item.level .. " " .. item.source .. " " .. item.message end end
    return out
  end
  function model:onEvent(event)
    if event.name ~= "key_down" then return end
    local char = charFrom(event, s.unicode)
    local number = char and tonumber(char)
    if number and number >= 1 and number <= 6 then self.tab = number; self.selected = 1
    elseif event.code == 200 then self.selected = math.max(1, self.selected - 1)
    elseif event.code == 208 then self.selected = self.selected + 1
    elseif char and char:lower() == "k" then
      if self.tab == 1 then local item = s.scheduler:list()[self.selected]; if item and item.pid ~= context.api.pid() then s.scheduler:kill(item.pid, "Task Manager") end
      elseif self.tab == 5 then local item = s.sessions:list()[self.selected]; if item then s.sessions:restart(item.id) end end
    end
  end
  function model:tick() end
  return model
end

local function settings(context)
  local s = context.services
  local categories = {"Appearance/theme", "Panel and desktop", "Display/resolution", "Remote performance",
    "Keyboard/input", "Users/security", "Startup/services", "Network", "Packages/updates",
    "Notifications", "Date/time", "GTNH integrations", "Accessibility", "Developer", "Backup/recovery"}
  local model = {selected = 1}
  function model:render()
    local out = {"Settings - arrows select, Enter changes", "Current theme: " .. context.session.theme}
    for index, name in ipairs(categories) do out[#out + 1] = (index == self.selected and "> " or "  ") .. name end
    return out
  end
  function model:onEvent(event)
    if event.name ~= "key_down" then return end
    if event.code == 200 then self.selected = math.max(1, self.selected - 1)
    elseif event.code == 208 then self.selected = math.min(#categories, self.selected + 1)
    elseif event.code == 28 and self.selected == 1 then
      local order = {"dark", "light", "highContrast", "lowColor"}; local nextIndex = 1
      for index, name in ipairs(order) do if name == context.session.theme then nextIndex = index % #order + 1 end end
      context.session.theme = order[nextIndex]
      local config = s.config:load("desktop"); config.theme = context.session.theme; s.config:save("desktop", config)
      s.desktop:request(context.session)
    elseif event.code == 28 and self.selected == 4 then
      local endpoint = s.registry:get(context.session.endpointId); endpoint.lowBandwidth = not endpoint.lowBandwidth; endpoint.targetFps = endpoint.lowBandwidth and 4 or 10
    end
  end
  return model
end

local function editor(context)
  local s, path = context.services, context.options.path or "/home/player/untitled.lua"
  local data = s.fs.read(path) or ""
  local model = {path = path, lines = {}, row = 1, column = 1, undo = {}, redo = {}, status = "Ctrl+S Save  Ctrl+F Find  Ctrl+Z Undo"}
  for line in (data .. "\n"):gmatch("(.-)\n") do model.lines[#model.lines + 1] = line end
  if #model.lines == 0 then model.lines[1] = "" end
  function model:snapshot()
    local value = table.concat(self.lines, "\n"); self.undo[#self.undo + 1] = value
    if #self.undo > 64 then table.remove(self.undo, 1) end; self.redo = {}
  end
  function model:render()
    local out = {self.path .. "  " .. self.status}
    local start = math.max(1, self.row - 6)
    for index = start, math.min(#self.lines, start + 12) do out[#out + 1] = string.format("%4d %s%s", index, self.lines[index], index == self.row and " <" or "") end
    return out
  end
  function model:save()
    local text = table.concat(self.lines, "\n")
    local ok, err = s.transaction:write(self.path, text, function() return true end)
    self.status = ok and "Saved" or ("Save failed: " .. tostring(err))
  end
  function model:onEvent(event)
    if event.name ~= "key_down" then return end
    local modifiers = s.desktop.modifiers[context.session.id] or {}
    local char = charFrom(event, s.unicode)
    if modifiers.ctrl and char and char:lower() == "s" then self:save(); return end
    if modifiers.ctrl and char and char:lower() == "z" and #self.undo > 0 then
      self.redo[#self.redo + 1] = table.concat(self.lines, "\n"); local value = table.remove(self.undo); self.lines = {}
      for line in (value .. "\n"):gmatch("(.-)\n") do self.lines[#self.lines + 1] = line end; return
    end
    if event.code == 200 then self.row = math.max(1, self.row - 1); self.column = math.min(self.column, #self.lines[self.row] + 1)
    elseif event.code == 208 then self.row = math.min(#self.lines, self.row + 1); self.column = math.min(self.column, #self.lines[self.row] + 1)
    elseif event.code == 203 then self.column = math.max(1, self.column - 1)
    elseif event.code == 205 then self.column = math.min(#self.lines[self.row] + 1, self.column + 1)
    elseif event.code == 14 then self:snapshot(); local line = self.lines[self.row]
      if self.column > 1 then self.lines[self.row] = line:sub(1, self.column - 2) .. line:sub(self.column); self.column = self.column - 1 end
    elseif event.code == 28 then self:snapshot(); local line = self.lines[self.row]; local tail = line:sub(self.column)
      self.lines[self.row] = line:sub(1, self.column - 1); table.insert(self.lines, self.row + 1, tail); self.row, self.column = self.row + 1, 1
    elseif char and char:byte() >= 32 then self:snapshot(); local line = self.lines[self.row]
      self.lines[self.row] = line:sub(1, self.column - 1) .. char .. line:sub(self.column); self.column = self.column + #char end
  end
  return model
end

local function listApp(title, provider, help)
  return function(context)
    local model = {refreshInterval = 2}
    function model:render()
      local out = {title, help or "Refreshes automatically"}; local ok, rows = pcall(provider, context.services, context)
      if not ok then out[#out + 1] = "Unavailable: " .. tostring(rows)
      elseif #rows == 0 then out[#out + 1] = "Unavailable (no compatible component detected)"
      else for _, row in ipairs(rows) do out[#out + 1] = type(row) == "table" and table.concat(row, "  ") or tostring(row) end end
      return out
    end
    function model:tick() end
    return model
  end
end

function Builtins.register(apps)
  apps:register({id="files",name="File Explorer",category="System",essential=true,width=64,height=18,minWidth=28,minHeight=8}, explorer)
  apps:register({id="terminal",name="Terminal",category="System",essential=true,width=68,height=18,minWidth=28,minHeight=8}, terminal)
  apps:register({id="tasks",name="System Monitor",category="System",essential=true,width=72,height=20,minWidth=34,minHeight=10}, taskManager)
  apps:register({id="settings",name="System Settings",category="System",width=56,height=20,minWidth=30,minHeight=10}, settings)
  apps:register({id="editor",name="Plasma Editor",category="Development",width=70,height=20,minWidth=32,minHeight=10}, editor)
  apps:register({id="components",name="Component Explorer",category="Development",width=70,height=18,minWidth=32,minHeight=8},
    listApp("Component Explorer", function(s) local out = {}; for _, item in ipairs(s.components:snapshot()) do out[#out+1] = {item.address:sub(1,8),item.type,"methods="..#item.methods} end; return out end,
      "Runtime-discovered methods; control invocation is disabled by default."))
  apps:register({id="machines",name="Machine Dashboard",category="GTNH",width=68,height=18,minWidth=30,minHeight=8},
    listApp("Machine Dashboard", function(s) local out = {}; for _, item in ipairs(s.integrations:list()) do out[#out+1] = {item.address:sub(1,8),item.adapter,item.state} end; return out end))
  local centers = {energy="Energy Center", inventory="Inventory / Fluid Center", redstone="Redstone Control Center",
    base="Base Control", ae="AE / ME Center", gregtech="GregTech Machine Center", reactor="Reactor / Plant Center",
    network="Network / Rack Manager", robots="Robot / Drone Console", navigation="World / Navigation"}
  for id, name in pairs(centers) do apps:register({id=id,name=name,category="GTNH",width=64,height=17,minWidth=30,minHeight=8},
    listApp(name, function(s) local out = {}; for _, item in ipairs(s.integrations:list()) do
      if item.adapter:lower():find(id,1,true) or item.type:lower():find(id,1,true) then out[#out+1] = {item.address:sub(1,8),item.type,item.state} end end; return out end,
      "Adapter-driven; absent or stale hardware is shown explicitly.")) end
  apps:register({id="packages",name="Application Center",category="System",width=58,height=17,minWidth=30,minHeight=8},
    listApp("Application Center", function(s) local out = {}; for id,item in pairs(s.packages.installed) do out[#out+1] = {id,item.version} end; return out end,
      "Checksummed staged installs; shell command: packages"))
  apps:register({id="automation",name="Automation Scheduler",category="GTNH",width=60,height=17,minWidth=30,minHeight=8},
    listApp("Automation Scheduler", function(s) local out = {}; for _,job in ipairs(s.automation:list()) do out[#out+1] = {job.id,job.running and "running" or "idle","failures="..job.failures} end; return out end))
  apps:register({id="notifications",name="Notification Center",category="System",width=60,height=17,minWidth=30,minHeight=8},
    listApp("Notification Center",function(s)local out={};for _,item in ipairs(s.notifications:list())do out[#out+1]={item.severity,item.source,item.title,item.acknowledged and "ack" or "new"}end;return out end))
end

return Builtins
