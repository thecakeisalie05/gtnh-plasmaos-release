local Ring = require("libs.ring")

local Automation = {}
Automation.__index = Automation

function Automation.new(scheduler, options)
  options = options or {}
  return setmetatable({scheduler = scheduler, clock = options.clock or os.clock,
    jobs = {}, history = Ring.new(options.historyLimit or 100), notifications = options.notifications}, Automation)
end

function Automation:add(job)
  assert(job.id and type(job.run) == "function", "invalid automation job")
  job.enabled = job.enabled ~= false; job.interval = job.interval or 60
  job.retryLimit = job.retryLimit or 0; job.nextRun = job.nextRun or self.clock() + job.interval
  job.running, job.failures = false, 0; self.jobs[job.id] = job
end

function Automation:_start(job, reason)
  if job.running then return nil, "already running" end
  job.running = true
  local started = self.clock()
  local pid, err = self.scheduler:spawn(function(api)
    local result = job.run(api, reason)
    return result
  end, {name = "automation:" .. job.id, appId = "automation", owner = job.owner or "system",
    onExit = function(_, state, detail)
      job.running, job.lastRun = false, self.clock()
      local ok = state == "exited"
      if ok then job.failures = 0 else job.failures = job.failures + 1 end
      self.history:push({job = job.id, started = started, finished = job.lastRun,
        ok = ok, detail = detail, reason = reason})
      if not ok and self.notifications then self.notifications:push("automation", "error",
        "Automation failed", job.id .. ": " .. tostring(detail)) end
      if not ok and job.failures <= job.retryLimit then
        job.nextRun = self.clock() + math.min(job.retryBackoff or 5, 60)
      else job.nextRun = self.clock() + job.interval end
    end})
  if not pid then job.running = false; return nil, err end
  job.pid = pid; return pid
end

function Automation:manual(id)
  local job = self.jobs[id]; if not job then return nil, "unknown job" end
  return self:_start(job, "manual")
end

function Automation:trigger(eventName, payload)
  for _, job in pairs(self.jobs) do
    if job.enabled and job.event == eventName then self:_start(job, {event = eventName, payload = payload}) end
  end
end

function Automation:tick(now)
  now = now or self.clock()
  for _, job in pairs(self.jobs) do
    if job.enabled and not job.running and not job.event and now >= job.nextRun then self:_start(job, "schedule") end
  end
end

function Automation:list()
  local out = {}; for id, job in pairs(self.jobs) do out[#out + 1] = {id = id,
    enabled = job.enabled, running = job.running, nextRun = job.nextRun, failures = job.failures} end
  table.sort(out, function(a, b) return a.id < b.id end); return out
end

return Automation
