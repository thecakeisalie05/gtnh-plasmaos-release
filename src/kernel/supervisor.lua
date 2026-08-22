local Supervisor = {}
Supervisor.__index = Supervisor

function Supervisor.new(scheduler, options)
  options = options or {}
  return setmetatable({
    scheduler = scheduler,
    logger = options.logger,
    clock = options.clock or os.clock,
    services = {},
  }, Supervisor)
end

function Supervisor:register(manifest, entry)
  assert(manifest and manifest.id and type(entry) == "function", "invalid service")
  assert(not self.services[manifest.id], "duplicate service")
  self.services[manifest.id] = {manifest = manifest, entry = entry, state = "stopped",
    restartTimes = {}, restartCount = 0}
end

function Supervisor:_log(level, message, fields)
  if self.logger then self.logger:write(level, "supervisor", message, fields) end
end

function Supervisor:_prune(service, now)
  local window = service.manifest.restartWindow or 60
  local kept = {}
  for _, timestamp in ipairs(service.restartTimes) do
    if now - timestamp <= window then kept[#kept + 1] = timestamp end
  end
  service.restartTimes = kept
end

function Supervisor:start(id)
  local service = self.services[id]
  if not service then return nil, "unknown service" end
  if service.state == "running" then return true end
  for _, dependency in ipairs(service.manifest.dependencies or {}) do
    local item = self.services[dependency]
    if not item or item.state ~= "running" then return nil, "dependency unavailable: " .. dependency end
  end
  service.state = "starting"
  local pid, err = self.scheduler:spawn(service.entry, {
    name = service.manifest.id,
    appId = "service:" .. service.manifest.id,
    owner = "system",
    onExit = function(process, state, detail) self:_exited(service, process, state, detail) end,
  })
  if not pid then service.state = "failed"; service.lastError = err; return nil, err end
  service.pid, service.state, service.startedAt = pid, "running", self.clock()
  self:_log("info", "service started", {service = id, pid = pid})
  return true
end

function Supervisor:_exited(service, process, state, detail)
  if service.stopping then service.state = "stopped"; service.stopping = nil; return end
  service.pid = nil
  service.lastError = state == "crashed" and tostring(detail) or nil
  local mode = service.manifest.restart or "never"
  local shouldRestart = mode == "always" or (mode == "on-failure" and state == "crashed")
  if not shouldRestart then service.state = state == "crashed" and "failed" or "stopped"; return end
  local now = self.clock(); self:_prune(service, now)
  local maximum = service.manifest.maxRestarts or 3
  if #service.restartTimes >= maximum then
    service.state = "failed"
    self:_log("error", "service restart limit reached", {service = service.manifest.id})
    return
  end
  service.restartTimes[#service.restartTimes + 1] = now
  service.restartCount = service.restartCount + 1
  service.nextStart = now + math.min(service.manifest.maxBackoff or 30,
    (service.manifest.backoff or 1) * 2 ^ (service.restartCount - 1))
  service.state = "backoff"
  self:_log("warning", "service scheduled for restart",
    {service = service.manifest.id, at = service.nextStart, error = detail})
end

function Supervisor:stop(id, reason)
  local service = self.services[id]
  if not service then return nil, "unknown service" end
  if service.pid then
    service.stopping = true
    return self.scheduler:kill(service.pid, reason or "service stopped")
  end
  service.state = "stopped"
  return true
end

function Supervisor:restart(id)
  local ok, err = self:stop(id, "service restart")
  if not ok then return nil, err end
  return self:start(id)
end

function Supervisor:tick(now)
  now = now or self.clock()
  for _, service in pairs(self.services) do
    if service.state == "backoff" and now >= service.nextStart then self:start(service.manifest.id) end
  end
end

function Supervisor:list()
  local out = {}
  for id, service in pairs(self.services) do
    out[#out + 1] = {id = id, state = service.state, pid = service.pid,
      restartCount = service.restartCount, lastError = service.lastError,
      enabled = service.manifest.enabled ~= false}
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

return Supervisor
