local Shell = {}
Shell.__index = Shell

local function words(line)
  local out, index = {}, 1
  while index <= #line do
    local nextNonSpace = line:find("%S", index); if not nextNonSpace then break end
    index = nextNonSpace
    if line:sub(index, index) == '"' then
      local finish = line:find('"', index + 1, true)
      if not finish then out[#out + 1] = line:sub(index + 1); break end
      out[#out + 1] = line:sub(index + 1, finish - 1); index = finish + 1
    else
      local finish = line:find("%s", index) or (#line + 1)
      out[#out + 1] = line:sub(index, finish - 1); index = finish + 1
    end
  end
  return out
end

local function tabulate(rows)
  local out = {}
  for _, row in ipairs(rows) do out[#out + 1] = table.concat(row, "  ") end
  return out
end

function Shell.new(services)
  return setmetatable({s = services, aliases = {ll = "ls", tm = "tasks"}}, Shell)
end

function Shell:execute(line, session)
  local args = words(line); local command = table.remove(args, 1)
  if not command or command == "" then return {} end
  command = self.aliases[command] or command
  if command == "help" then return {"Commands: help ls cat mkdir rm cp mv ps kill services logs",
    " sessions displays restart-session components apps open packages automation",
    " update memory energy uptime clear lua reboot shutdown"}
  elseif command == "clear" then return {__clear = true}
  elseif command == "ls" then
    local entries, err = self.s.files:list(args[1] or "/", args[2] == "-a")
    if not entries then return {"error: " .. tostring(err)} end
    local out = {}; for _, entry in ipairs(entries) do out[#out + 1] = (entry.directory and "[D] " or "    ") .. entry.name end; return out
  elseif command == "cat" then
    local data, err = self.s.fs.read(assert(args[1], "path required")); return {data or ("error: " .. tostring(err))}
  elseif command == "mkdir" then local ok, err = self.s.fs.makeDirectory(assert(args[1], "path required")); return {ok and "created" or ("error: " .. tostring(err))}
  elseif command == "rm" then local ok, err = self.s.files:delete(assert(args[1], "path required"), args[2] == "--confirm"); return {ok and "deleted" or ("error: " .. tostring(err))}
  elseif command == "mv" then local ok, err = self.s.files:move(assert(args[1]), assert(args[2])); return {ok and "moved" or ("error: " .. tostring(err))}
  elseif command == "cp" then local job, err = self.s.files:copy(assert(args[1]), assert(args[2])); return {job and ("copy job " .. job.id) or ("error: " .. tostring(err))}
  elseif command == "ps" then
    local rows = {{"PID", "STATE", "APP", "NAME"}}
    for _, process in ipairs(self.s.scheduler:list()) do rows[#rows + 1] = {tostring(process.pid), process.state, process.appId, process.name} end
    return tabulate(rows)
  elseif command == "kill" then local ok, err = self.s.scheduler:kill(tonumber(args[1]), "terminal kill"); return {ok and "terminated" or ("error: " .. tostring(err))}
  elseif command == "services" then
    local rows = {{"SERVICE", "STATE", "RESTARTS"}}
    for _, item in ipairs(self.s.supervisor:list()) do rows[#rows + 1] = {item.id, item.state, tostring(item.restartCount)} end
    return tabulate(rows)
  elseif command == "logs" then
    local out = {}; local logs = self.s.log:list()
    for index = math.max(1, #logs - 15), #logs do local item = logs[index]; out[#out + 1] = string.format("%s %-12s %s", item.level, item.source, item.message) end
    return out
  elseif command == "sessions" then
    local rows = {{"SESSION", "STATE", "ENDPOINT", "FOCUS"}}
    for _, item in ipairs(self.s.sessions:list()) do rows[#rows + 1] = {item.id, item.state, item.endpointId, item.focusedWindow or "-"} end
    return tabulate(rows)
  elseif command == "displays" then
    local rows = {{"ENDPOINT", "KIND", "STATE", "GEN", "SIZE"}}
    for _, item in ipairs(self.s.registry:list()) do rows[#rows + 1] = {item.id, item.kind, item.state,
      tostring(item.generation), item.width .. "x" .. item.height} end
    return tabulate(rows)
  elseif command == "restart-session" then
    local restarted, err = self.s.sessions:restart(args[1] or session.id)
    return {restarted and "session restarted" or ("error: " .. tostring(err))}
  elseif command == "components" then
    local rows = {{"ADDRESS", "TYPE", "METHODS"}}
    for _, item in ipairs(self.s.components:snapshot()) do rows[#rows + 1] = {item.address:sub(1, 8), item.type, tostring(#item.methods)} end
    return tabulate(rows)
  elseif command == "apps" then
    local out = {}; for _, app in ipairs(self.s.apps:list()) do out[#out + 1] = app.id .. " - " .. app.name end; return out
  elseif command == "open" then
    local pid, err = self.s.apps:launch(assert(args[1], "app id required"), session.id,
      {services = self.s, path = args[2]}); return {pid and ("started PID " .. pid) or ("error: " .. tostring(err))}
  elseif command == "packages" then
    local out = {}; for id, item in pairs(self.s.packages.installed) do out[#out + 1] = id .. " " .. item.version end
    if #out == 0 then out[1] = "No optional packages installed" end; table.sort(out); return out
  elseif command == "automation" then
    local out = {}; for _, job in ipairs(self.s.automation:list()) do out[#out + 1] = string.format("%s %s next=%.1f", job.id, job.running and "running" or "idle", job.nextRun) end
    return out
  elseif command == "update" then
    if args[1] == "rollback" then local ok, err = self.s.updates:rollback(); return {ok and "rollback selected" or ("error: " .. tostring(err))} end
    local status = self.s.updates:status(); return {string.format("%s %.0f%% %s", status.state, status.progress * 100, status.error or "")}
  elseif command == "memory" then local m = self.s.memory:sample(); return {string.format("%d/%d free (%.1f%%) %s", m.free, m.total, m.ratio * 100, m.state)}
  elseif command == "energy" then return {string.format("%.1f / %.1f", self.s.computer.energy(), self.s.computer.maxEnergy())}
  elseif command == "uptime" then return {string.format("%.1f seconds", self.s.computer.uptime())}
  elseif command == "lua" then
    local source = table.concat(args, " "); local environment = {math = math, string = string, table = table,
      pairs = pairs, ipairs = ipairs, tostring = tostring, tonumber = tonumber, type = type}
    local chunk, err = load("return " .. source, "=repl", "t", environment)
    if not chunk then chunk, err = load(source, "=repl", "t", environment) end
    if not chunk then return {"error: " .. tostring(err)} end
    local result = {pcall(chunk)}; if not result[1] then return {"error: " .. tostring(result[2])} end
    local out = {}; for index = 2, #result do out[#out + 1] = tostring(result[index]) end; return out
  elseif command == "reboot" or command == "shutdown" then
    if args[1] ~= "--confirm" then return {"Refused: append --confirm"} end
    self.s.computer.shutdown(command == "reboot"); return {command .. " requested"}
  end
  return {"command not found: " .. command}
end

return Shell
