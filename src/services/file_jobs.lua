local Queue = require("libs.queue")

local FileJobs = {}
FileJobs.__index = FileJobs

function FileJobs.new(fs, options)
  options = options or {}
  return setmetatable({fs = fs, pending = Queue.new(options.queueLimit or 16), active = nil,
    nextId = 1, chunkSize = options.chunkSize or 4096, logger = options.logger}, FileJobs)
end

function FileJobs:copy(source, target, callback)
  local job = {id = self.nextId, type = "copy", source = source, target = target,
    callback = callback, state = "queued", filesDone = 0, bytesDone = 0, stack = {{source, target}}, cancelled = false}
  self.nextId = self.nextId + 1
  local ok, err = self.pending:push(job); if not ok then return nil, err end
  return job
end

function FileJobs:cancel(id)
  if self.active and self.active.id == id then self.active.cancelled = true; return true end
  for _, job in ipairs(self.pending:values()) do if job.id == id then job.cancelled = true; return true end end
  return nil, "job not found"
end

function FileJobs:_finish(job, ok, err)
  job.state = ok and "complete" or (job.cancelled and "cancelled" or "failed")
  job.error = err
  if job.reader then pcall(job.reader.close, job.reader) end
  if job.writer then pcall(job.writer.close, job.writer) end
  if not ok and job.currentTarget then self.fs.remove(job.currentTarget .. ".part") end
  if job.callback then pcall(job.callback, job) end
  self.active = nil
end

function FileJobs:_nextEntry(job)
  local pair = table.remove(job.stack)
  if not pair then return false end
  local source, target = pair[1], pair[2]
  if self.fs.isDirectory(source) then
    local ok, err = self.fs.makeDirectory(target)
    if not ok and not self.fs.exists(target) then return nil, err end
    local names, listErr = self.fs.list(source)
    if not names then return nil, listErr end
    for index = #names, 1, -1 do
      local name = names[index]
      job.stack[#job.stack + 1] = {self.fs.concat(source, name), self.fs.concat(target, name)}
    end
  else
    local reader, readErr = self.fs.open(source, "rb"); if not reader then return nil, readErr end
    local writer, writeErr = self.fs.open(target .. ".part", "wb")
    if not writer then reader:close(); return nil, writeErr end
    job.reader, job.writer, job.currentTarget = reader, writer, target
  end
  return true
end

function FileJobs:step()
  local job = self.active
  if not job then job = self.pending:pop(); self.active = job; if job then job.state = "running" end end
  if not job then return false end
  if job.cancelled then self:_finish(job, false, "cancelled"); return true end
  if job.reader then
    local chunk, err = job.reader:read(self.chunkSize)
    if chunk and #chunk > 0 then
      local ok, writeErr = job.writer:write(chunk)
      if not ok then self:_finish(job, false, writeErr); return true end
      job.bytesDone = job.bytesDone + #chunk
    elseif err then self:_finish(job, false, err); return true
    else
      job.reader:close(); job.writer:close(); job.reader, job.writer = nil, nil
      self.fs.remove(job.currentTarget)
      local ok, renameErr = self.fs.rename(job.currentTarget .. ".part", job.currentTarget)
      if not ok then self:_finish(job, false, renameErr); return true end
      job.filesDone = job.filesDone + 1
    end
  else
    local progressed, err = self:_nextEntry(job)
    if progressed == false then self:_finish(job, true)
    elseif not progressed then self:_finish(job, false, err) end
  end
  return true
end

return FileJobs
