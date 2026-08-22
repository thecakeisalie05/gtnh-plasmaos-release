local Ring = require("libs.ring")

local Apps = {}
Apps.__index = Apps

function Apps.new(scheduler, sessions, options)
  options = options or {}
  return setmetatable({scheduler = scheduler, sessions = sessions, registry = {},
    crashes = Ring.new(options.crashLimit or 32), logger = options.logger,
    notifications = options.notifications, repaint = options.repaint,
    memory = options.memory, services = options.services}, Apps)
end

function Apps:register(manifest, factory)
  assert(manifest.id and manifest.name and type(factory) == "function", "invalid app")
  self.registry[manifest.id] = {manifest = manifest, factory = factory}
end

function Apps:launch(appId, sessionId, options)
  options = options or {}
  local app = self.registry[appId]; if not app then return nil, "application not found" end
  local session = self.sessions:get(sessionId); if not session then return nil, "session not found" end
  if self.memory and not self.memory:canLaunch(app.manifest.essential) then return nil, "memory critically low" end
  local pid
  pid = self.scheduler:spawn(function(api)
    local appPid = api.pid()
    local context = {api = api, session = session, options = options, services = options.services or self.services or {}}
    local model = app.factory(context)
    local view = model.render and model:render() or {app.manifest.name}
    local window = session.windowManager:create({ownerPid = appPid, appId = appId,
      title = app.manifest.name, w = app.manifest.width, h = app.manifest.height,
      minW = app.manifest.minWidth, minH = app.manifest.minHeight,
      render = function() return view end,
      onEvent = function(_, event) return self.scheduler:send(appPid, event) end,
      onClose = function() self.scheduler:send(appPid, {name = "app_close"}) end})
    while true do
      local event = api.receive(model.refreshInterval)
      if event and event.name == "app_close" then return end
      if model.onEvent and event then model:onEvent(event) end
      if model.tick and not event then model:tick() end
      if model.render then view = model:render() end
      if self.repaint then self.repaint(session.endpointId,
        {x = window.x, y = window.y, w = window.w, h = window.h}) end
    end
  end, {name = app.manifest.name, appId = appId, owner = session.user, sessionId = sessionId,
    onExit = function(process, state, detail)
      session.windowManager:closeByOwner(process.pid, state)
      if state == "crashed" then
        local report = {time = os.clock(), pid = process.pid, appId = appId,
          name = app.manifest.name, error = tostring(detail), sessionId = sessionId}
        self.crashes:push(report)
        if self.logger then self.logger:write("error", "apps", "application crashed", report) end
        if self.notifications then self.notifications:push(appId, "error", app.manifest.name .. " crashed",
          tostring(detail), {persistent = true}) end
      end
    end})
  return pid
end

function Apps:list()
  local out = {}; for id, app in pairs(self.registry) do out[#out + 1] = {id = id,
    name = app.manifest.name, category = app.manifest.category, essential = app.manifest.essential} end
  table.sort(out, function(a, b) return a.name < b.name end); return out
end

function Apps:crashReports() return self.crashes:values() end

return Apps
