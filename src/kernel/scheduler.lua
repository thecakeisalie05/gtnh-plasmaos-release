local Queue = require("libs.queue")
local Ring = require("libs.ring")
local unpack = table.unpack or unpack

local Scheduler = {}
Scheduler.__index = Scheduler

local function copyMetadata(source)
  local out = {}
  for key, value in pairs(source or {}) do out[key] = value end
  return out
end

function Scheduler.new(options)
  options = options or {}
  local self = setmetatable({
    clock = options.clock or os.clock,
    logger = options.logger,
    ready = Queue.new(options.maxProcesses or 128),
    processes = {},
    exited = Ring.new(options.historyLimit or 64),
    nextPid = 1,
    heartbeat = 0,
    cycle = 0,
    maxSteps = options.maxSteps or 32,
    stallThreshold = options.stallThreshold or 0.25,
    current = nil,
  }, Scheduler)
  self.api = {
    yield = function() return coroutine.yield({op = "yield"}) end,
    sleep = function(seconds) return coroutine.yield({op = "sleep", seconds = math.max(0, seconds or 0)}) end,
    wait = function(filter, timeout) return coroutine.yield({op = "wait", filter = filter, timeout = timeout}) end,
    receive = function(timeout) return coroutine.yield({op = "receive", timeout = timeout}) end,
    cancelled = function()
      local process = self.processes[self.current]
      return not process or process.cancelled
    end,
    pid = function() return self.current end,
  }
  return self
end

function Scheduler:_log(level, message, fields)
  if self.logger then self.logger:write(level, "scheduler", message, fields) end
end

function Scheduler:spawn(fn, metadata, ...)
  assert(type(fn) == "function", "task entry must be a function")
  local pid = self.nextPid
  self.nextPid = pid + 1
  local args = {...}
  local process = copyMetadata(metadata)
  process.pid = pid
  process.parentPid = process.parentPid or self.current or 0
  process.name = process.name or ("task-" .. pid)
  process.appId = process.appId or "system"
  process.owner = process.owner or "system"
  process.state = "ready"
  process.startTime = self.clock()
  process.cpuTime = 0
  process.work = 0
  process.resumes = 0
  process.openResources = process.openResources or {}
  process.windowIds = process.windowIds or {}
  process.cleanup = process.cleanup or {}
  process.mailbox = Queue.new(process.mailboxLimit or 32)
  process.coroutine = coroutine.create(function() return fn(self.api, unpack(args)) end)
  self.processes[pid] = process
  local queued, err = self.ready:push(pid)
  if not queued then self.processes[pid] = nil; return nil, err end
  self:_log("debug", "process spawned", {pid = pid, name = process.name})
  return pid
end

function Scheduler:_finalize(process, state, detail)
  process.state = state
  process.endTime = self.clock()
  if state == "crashed" then process.lastError = tostring(detail) end
  for i = #process.cleanup, 1, -1 do pcall(process.cleanup[i], state, detail) end
  self.processes[process.pid] = nil
  local snapshot = {}
  for key, value in pairs(process) do
    if key ~= "coroutine" and key ~= "cleanup" and key ~= "mailbox" and key ~= "onExit" then
      snapshot[key] = value
    end
  end
  self.exited:push(snapshot)
  if process.onExit then pcall(process.onExit, process, state, detail) end
  self:_log(state == "crashed" and "error" or "debug", "process " .. state,
    {pid = process.pid, name = process.name, detail = detail})
end

function Scheduler:_ready(process, ...)
  process.state = "ready"
  process.resumeArgs = {...}
  local ok = self.ready:push(process.pid)
  if not ok then self:_finalize(process, "crashed", "ready queue overflow") end
end

function Scheduler:_wake(now)
  for _, process in pairs(self.processes) do
    if process.state == "sleeping" and now >= process.wakeDeadline then
      self:_ready(process)
    elseif (process.state == "waiting" or process.state == "receiving")
      and process.wakeDeadline and now >= process.wakeDeadline then
      self:_ready(process, nil, "timeout")
    end
  end
end

function Scheduler:deliver(event)
  local delivered = 0
  for _, process in pairs(self.processes) do
    if process.state == "waiting" then
      local matches = process.waitFilter == nil
      if type(process.waitFilter) == "string" then matches = event.name == process.waitFilter end
      if type(process.waitFilter) == "function" then
        local ok, result = pcall(process.waitFilter, event)
        matches = ok and result or false
      end
      if matches then self:_ready(process, event); delivered = delivered + 1 end
    end
  end
  return delivered
end

function Scheduler:send(pid, message)
  local process = self.processes[pid]
  if not process then return nil, "no such process" end
  if process.state == "receiving" then self:_ready(process, message); return true end
  return process.mailbox:push(message)
end

function Scheduler:addCleanup(pid, callback)
  local process = self.processes[pid]
  if not process then return nil, "no such process" end
  process.cleanup[#process.cleanup + 1] = callback
  return true
end

function Scheduler:kill(pid, reason)
  local process = self.processes[pid]
  if not process then return nil, "no such process" end
  process.cancelled = true
  self:_finalize(process, "stopped", reason or "terminated")
  return true
end

function Scheduler:tick(now, stepLimit)
  now = now or self.clock()
  self.heartbeat = now
  self.cycle = self.cycle + 1
  self:_wake(now)
  local steps = 0
  while steps < (stepLimit or self.maxSteps) do
    local pid = self.ready:pop()
    if not pid then break end
    local process = self.processes[pid]
    if process and process.state == "ready" then
      process.state = "running"
      self.current = pid
      local before = self.clock()
      local args = process.resumeArgs or {}
      process.resumeArgs = nil
      local resumed = {coroutine.resume(process.coroutine, unpack(args))}
      local elapsed = math.max(0, self.clock() - before)
      self.current = nil
      process.cpuTime = process.cpuTime + elapsed
      process.work = process.work + 1
      process.resumes = process.resumes + 1
      process.lastRun = now
      if elapsed > self.stallThreshold then
        process.stallCount = (process.stallCount or 0) + 1
        self:_log("warning", "long cooperative slice", {pid = pid, elapsed = elapsed})
      end
      if not resumed[1] then
        self:_finalize(process, "crashed", resumed[2])
      elseif coroutine.status(process.coroutine) == "dead" then
        self:_finalize(process, "exited", resumed[2])
      else
        local request = resumed[2]
        if type(request) ~= "table" then request = {op = "yield"} end
        if request.op == "sleep" then
          process.state = "sleeping"; process.wakeDeadline = now + request.seconds
        elseif request.op == "wait" then
          process.state = "waiting"; process.waitFilter = request.filter
          process.wakeDeadline = request.timeout and (now + request.timeout) or nil
        elseif request.op == "receive" then
          local message = process.mailbox:pop()
          if message ~= nil then self:_ready(process, message)
          else
            process.state = "receiving"
            process.wakeDeadline = request.timeout and (now + request.timeout) or nil
          end
        else self:_ready(process) end
      end
      steps = steps + 1
    end
  end
  return steps
end

function Scheduler:nextDeadline(now)
  if not self.ready:isEmpty() then return 0 end
  now = now or self.clock()
  local delay
  for _, process in pairs(self.processes) do
    if process.wakeDeadline then
      local candidate = math.max(0, process.wakeDeadline - now)
      if not delay or candidate < delay then delay = candidate end
    end
  end
  return delay
end

function Scheduler:list()
  local out = {}
  for _, process in pairs(self.processes) do out[#out + 1] = process end
  table.sort(out, function(a, b) return a.pid < b.pid end)
  return out
end

function Scheduler:history()
  return self.exited:values()
end

return Scheduler
