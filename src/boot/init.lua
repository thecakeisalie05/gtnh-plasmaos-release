local root = (...) or _G.PLASMAOS_VERSION_ROOT or "/system/versions/0.1.0"
io.write("[PlasmaOS] loading modules...\n")
local unpack = table.unpack or unpack
local packageTable = package or {path = "", loaded = {}}
packageTable.path = root .. "/src/?.lua;" .. root .. "/src/?/init.lua;"
  .. (packageTable.path ~= "" and (";" .. packageTable.path) or "")
package = packageTable

local function moduleSearch(name)
  local relative = name:gsub("%.", "/")
  for template in package.path:gmatch("[^;]+") do
    local candidate = template:gsub("%?", relative)
    local chunk = loadfile(candidate)
    if chunk then return chunk, candidate end
  end
end

local require = _G.require or function(name)
  if package.loaded[name] ~= nil then return package.loaded[name] end
  local loader, resolved = moduleSearch(name)
  assert(loader, "module not found: " .. tostring(name))
  local value = loader(resolved)
  if value == nil then value = true end
  package.loaded[name] = value
  return value
end
_G.require = require

local OpenOS = require("compat.openos")
local environment = OpenOS.load()
if _G.PLASMAOS_BOOT_MODE == "safe" or _G.PLASMAOS_BOOT_MODE == "recovery" then
  return require("boot.safe_mode").run(environment, _G.PLASMAOS_BOOT_REASON)
end

local Log = require("kernel.log")
local Scheduler = require("kernel.scheduler")
local EventBroker = require("kernel.event_broker")
local IPC = require("kernel.ipc")
local Capabilities = require("kernel.capabilities")
local Supervisor = require("kernel.supervisor")
local ComponentBroker = require("services.component_broker")
local Config = require("services.config")
local Notifications = require("services.notifications")
local LogSink = require("services.log_sink")
local Telemetry = require("services.telemetry")
local Alarms = require("services.alarms")
local Automation = require("services.automation")
local Network = require("services.network")
local ModemTransport = require("services.modem_transport")
local Users = require("services.users")
local FileJobs = require("services.file_jobs")
local FileService = require("services.file_service")
local Packages = require("services.package_manager")
local UpdateService = require("services.update_service")
local Memory = require("services.memory_manager")
local Apps = require("services.app_manager")
local FirstRun = require("services.first_run")
local Registry = require("display.endpoint_registry")
local Sessions = require("display.session_broker")
local Compositor = require("display.compositor")
local Input = require("display.input_broker")
local Desktop = require("ui.desktop")
local IntegrationManager = require("integrations.manager")
local Shell = require("shell.commands")
local Builtins = require("apps.builtins")
local Txn = require("libs.fs_txn")

io.write("[PlasmaOS] initializing services...\n")

environment.fs.makeDirectory("/etc/plasmaos")
environment.fs.makeDirectory("/var/lib/plasmaos")
environment.fs.makeDirectory("/var/log/plasmaos")
environment.fs.makeDirectory("/home/player")
local log = Log.new({clock = environment.computer.uptime, capacity = 256})
local logSink = LogSink.new(environment.fs, {path = "/var/log/plasmaos/system.log", maxBytes = 32768, rotations = 3})
log.sink = function(entry) logSink:enqueue(entry) end
local transaction = Txn.new(environment.fs, log)
local config = Config.new({root = "/etc/plasmaos", fs = environment.fs, transaction = transaction, logger = log})
config:register("desktop", {version = 1, defaults = {theme = "highContrast", remoteFps = 6, localFps = 12}})
config:register("first_run", {version = 1, defaults = {step = 1, completed = false}})
local scheduler = Scheduler.new({clock = environment.computer.uptime, logger = log, maxProcesses = 96})
local events = EventBroker.new({logger = log, scheduler = scheduler, capacity = 128})
local ipc = IPC.new({clock = environment.computer.uptime})
local capabilities = Capabilities.new(function(subject, capability, allowed, context)
  log:write(allowed and "info" or "warning", "audit", "capability check",
    {subject = subject, capability = capability, allowed = allowed, context = context})
end)
capabilities:grant("system", "*")
local components = ComponentBroker.new(environment.component, {logger = log, capabilities = capabilities})
local registry = Registry.new(components, {logger = log, clock = environment.computer.uptime})
registry:discover()
io.write("[PlasmaOS] displays discovered.\n")
local sessions = Sessions.new(registry, {logger = log, clock = environment.computer.uptime})
sessions:sync()
local compositor = Compositor.new(registry, components, {logger = log, clock = environment.computer.uptime})
local notifications = Notifications.new({clock = environment.computer.uptime})
local telemetry = Telemetry.new({clock = environment.computer.uptime, historyLimit = 120})
local alarms = Alarms.new(telemetry, notifications, {clock = environment.computer.uptime})
local automation = Automation.new(scheduler, {clock = environment.computer.uptime, notifications = notifications})
local users = Users.new({clock = environment.computer.uptime,
  audit = function(subject, action, detail) log:write("info", "audit", action, {subject = subject, detail = detail}) end})
users:create("player", nil, true)
local network = Network.new({node = "plasmaos", clock = environment.computer.uptime, logger = log})
local modem = ModemTransport.new(components, network, {logger = log})
network.transport = function(envelope) return modem:send(envelope) end
modem:discover()
local fileJobs = FileJobs.new(environment.fs, {logger = log})
local files = FileService.new(environment.fs, fileJobs, {audit = function(subject, action, detail)
  log:write("info", "audit", action, {subject = subject, detail = detail}) end})
local packages = Packages.new(environment.fs, {transaction = transaction, logger = log})
packages:load()
local updates = UpdateService.new(scheduler, environment.fs, packages)
local memory = Memory.new({free = environment.computer.freeMemory, total = environment.computer.totalMemory,
  onState = function(state) notifications:push("memory", state == "critical" and "critical" or "warning",
    "Memory pressure", "System entered " .. state .. " memory mode", {persistent = state == "critical"}) end})
memory:registerTrimmer("telemetry", function() telemetry:trim(32) end, 10)
local integrations = IntegrationManager.new(components, telemetry, {clock = environment.computer.uptime,
  logger = log, capabilities = capabilities, audit = function(subject, action, detail)
    log:write("info", "audit", action, {subject = subject, detail = detail}) end})
integrations:discover()
local supervisor = Supervisor.new(scheduler, {logger = log, clock = environment.computer.uptime})
local apps = Apps.new(scheduler, sessions, {logger = log, notifications = notifications, memory = memory})
local desktop = Desktop.new({compositor = compositor, registry = registry, sessions = sessions,
  apps = apps, notifications = notifications, uptime = environment.computer.uptime})
local firstRun = FirstRun.new(config)
local services = {log=log,scheduler=scheduler,events=events,ipc=ipc,capabilities=capabilities,
  supervisor=supervisor,components=components,registry=registry,sessions=sessions,compositor=compositor,
  notifications=notifications,telemetry=telemetry,alarms=alarms,automation=automation,network=network,
  users=users,fileJobs=fileJobs,files=files,fs=environment.fs,packages=packages,memory=memory,
  integrations=integrations,config=config,transaction=transaction,apps=apps,desktop=desktop,
  computer=environment.computer,unicode=(pcall(require,"unicode") and require("unicode") or nil),firstRun=firstRun,
  logSink=logSink,updates=updates,modem=modem}
services.shell = Shell.new(services)
apps.services = services
apps.repaint = function(endpointId, rect)
  local session = sessions:getByEndpoint(endpointId); if session then desktop:request(session, rect) end
end
notifications:onPush(function(item,dnd)
  if dnd then return end
  for _,session in ipairs(sessions:list())do
    session.notifications[#session.notifications+1]=item
    while #session.notifications>50 do table.remove(session.notifications,1)end
    session.toast={item=item,expires=environment.computer.uptime()+4};desktop:request(session)
  end
end)
Builtins.register(apps)
apps:register({id="first_run",name="Welcome to PlasmaOS",category="System",essential=true,width=58,height=15,minWidth=30,minHeight=10}, function(context)
  local model = {}
  function model:render()
    local step, index, count, complete = context.services.firstRun:current()
    if complete then return {"Setup complete.", "Close this window to use PlasmaOS."} end
    return {"First-run setup (resumable)", string.format("Step %d/%d: %s", index, count, step), "",
      "Hardware and components are discovered at runtime.", "Defaults are safe for remote/low-bandwidth displays.",
      "Press Enter to accept this step and continue."}
  end
  function model:onEvent(event) if event.name == "key_down" and event.code == 28 then context.services.firstRun:advance() end end
  return model
end)

for _, session in ipairs(sessions:list()) do
  local desktopConfig = config:load("desktop"); session.theme = desktopConfig.theme or "dark"
  desktop:attach(session)
  if not firstRun:state().completed then apps:launch("first_run", session.id) end
end

local input = Input.new(registry, sessions, {logger = log,
  globalShortcut = function(session, event) return desktop:globalShortcut(session, event) end,
  dispatch = function(session, event) return desktop:handle(session, event) end})
services.input = input
events:subscribe({touch=true,drag=true,drop=true,scroll=true,walk=true,key_down=true,key_up=true,clipboard=true},
  function(event) event.time = environment.computer.uptime(); input:route(event) end, "input")
events:subscribe({component_added=true,component_removed=true}, function() registry:discover(); sessions:sync()
  for _, session in ipairs(sessions:list()) do if not session.windowManager.damage then desktop:attach(session) end end
  integrations:discover(); modem:discover() end, "hardware")
events:subscribe("modem_message", function(event) modem:receive(event) end, "network")
events:subscribe("screen_resize", function(event)
  local endpoint = registry:byInput(event.args[1]); if endpoint then endpoint.width, endpoint.height = event.args[2], event.args[3]
    endpoint.generation = endpoint.generation + 1; local session = sessions:getByEndpoint(endpoint.id)
    if session then session.windowManager:setGeometry(endpoint.width, endpoint.height - 1); desktop:request(session) end end
end, "display")

supervisor:register({id="display",restart="on-failure",maxRestarts=3,backoff=1}, function(api)
  local ok, err = xpcall(function()
    while true do compositor:step(environment.computer.uptime(), 32)
      for _, session in ipairs(sessions:list()) do input:drain(session.id, 16) end
      desktop:tick(); api.sleep(0.03) end
  end, debug and debug.traceback or tostring)
  if _G.PLASMAOS_SPLASH then _G.PLASMAOS_SPLASH("PlasmaOS display error: " .. tostring(err))
  else io.stderr:write("PlasmaOS display error: " .. tostring(err) .. "\n") end
  error(err)
end)
supervisor:register({id="files",restart="on-failure",maxRestarts=3,backoff=1}, function(api)
  while true do fileJobs:step(); api.sleep(fileJobs.active and 0 or 0.1) end
end)
supervisor:register({id="automation",restart="on-failure",maxRestarts=3,backoff=1}, function(api)
  while true do automation:tick(); alarms:evaluate(); api.sleep(0.5) end
end)
supervisor:register({id="integrations",restart="on-failure",maxRestarts=3,backoff=2}, function(api)
  while true do components:step(); integrations:poll(environment.computer.uptime(), 1); api.sleep(0.2) end
end)
supervisor:register({id="network",restart="on-failure",maxRestarts=3,backoff=2}, function(api)
  while true do network:step(); api.sleep(0.1) end
end)
supervisor:register({id="logging",restart="on-failure",maxRestarts=3,backoff=1}, function(api)
  while true do logSink:step(8); api.sleep(logSink.queue:isEmpty() and 0.2 or 0) end
end)
supervisor:register({id="watchdog",restart="on-failure",maxRestarts=3,backoff=1}, function(api)
  local previousRaw, previousDispatch = 0, 0
  while true do
    local now = environment.computer.uptime()
    for _, fault in ipairs(compositor:watchdog(now, scheduler.heartbeat)) do
      log:write("error", "watchdog", "display stall classified", fault)
      registry:recover(fault.endpoint, "display watchdog timeout")
      local session = sessions:getByEndpoint(fault.endpoint); if session then desktop:request(session) end
    end
    if input.rawReceived > previousRaw and input.normalizedDispatched == previousDispatch then
      log:write("warning", "watchdog", "raw input arrived without dispatch",
        {raw = input.rawReceived, dispatched = input.normalizedDispatched})
    end
    previousRaw, previousDispatch = input.rawReceived, input.normalizedDispatched
    memory:sample(); api.sleep(1)
  end
end)
for _, id in ipairs({"display","files","automation","integrations","network","logging","watchdog"}) do supervisor:start(id) end
io.write("[PlasmaOS] services started.\n")

environment.fs.write("/system/boot-attempts.new", "0")
environment.fs.remove("/system/boot-attempts")
environment.fs.rename("/system/boot-attempts.new", "/system/boot-attempts")
local active = environment.fs.read("/system/active")
if active then environment.fs.write("/system/last-good.new", active); environment.fs.remove("/system/last-good"); environment.fs.rename("/system/last-good.new", "/system/last-good") end
log:write("info", "boot", "desktop services started", {root = root, sessions = #sessions:list()})

while true do
  scheduler:tick(environment.computer.uptime())
  events:drain(32); supervisor:tick(environment.computer.uptime())
  local timeout = scheduler:nextDeadline(environment.computer.uptime()) or 0.25
  timeout = math.max(0, math.min(timeout, 0.25))
  local signal = {environment.computer.pullSignal(timeout)}
  if signal[1] then events:publish(unpack(signal)) end
end
