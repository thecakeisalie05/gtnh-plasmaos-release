local Ring = require("libs.ring")

local Telemetry = {}
Telemetry.__index = Telemetry

function Telemetry.new(options)
  options = options or {}
  return setmetatable({metrics = {}, clock = options.clock or os.clock,
    historyLimit = options.historyLimit or 120, staleAfter = options.staleAfter or 10}, Telemetry)
end

function Telemetry:define(id, spec)
  local metric = self.metrics[id] or {id = id, history = Ring.new(spec.historyLimit or self.historyLimit)}
  metric.source, metric.unit = spec.source, spec.unit
  metric.staleAfter = spec.staleAfter or self.staleAfter
  metric.quality = "unavailable"; self.metrics[id] = metric
  return metric
end

function Telemetry:sample(id, value, quality, timestamp, errorMessage)
  local metric = self.metrics[id] or self:define(id, {})
  local sample = {time = timestamp or self.clock(), value = value,
    quality = quality or "live", error = errorMessage}
  metric.last = sample; metric.quality = sample.quality; metric.history:push(sample)
  return sample
end

function Telemetry:get(id, now)
  local metric = self.metrics[id]; if not metric then return nil end
  now = now or self.clock()
  if metric.last and metric.quality == "live" and now - metric.last.time > metric.staleAfter then
    metric.quality = "stale"
  end
  return {id = id, source = metric.source, unit = metric.unit,
    value = metric.last and metric.last.value, timestamp = metric.last and metric.last.time,
    quality = metric.quality, error = metric.last and metric.last.error}
end

function Telemetry:history(id) return self.metrics[id] and self.metrics[id].history:values() or {} end

function Telemetry:trim(limit)
  limit = limit or math.max(8, math.floor(self.historyLimit / 2))
  for _, metric in pairs(self.metrics) do
    local values = metric.history:values(); metric.history = Ring.new(limit)
    for index = math.max(1, #values - limit + 1), #values do metric.history:push(values[index]) end
  end
end

return Telemetry
