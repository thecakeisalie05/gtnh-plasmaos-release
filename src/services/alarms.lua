local Alarms = {}
Alarms.__index = Alarms

function Alarms.new(telemetry, notifications, options)
  options = options or {}
  return setmetatable({telemetry = telemetry, notifications = notifications,
    clock = options.clock or os.clock, rules = {}, audit = options.audit}, Alarms)
end

function Alarms:add(rule)
  assert(rule.id and rule.metric and rule.condition, "invalid alarm rule")
  rule.cooldown = rule.cooldown or 30
  rule.debounce = rule.debounce or 2
  rule.pendingSince, rule.active, rule.lastAlert = nil, false, -math.huge
  self.rules[rule.id] = rule
end

function Alarms:evaluate(now)
  now = now or self.clock()
  local changes = {}
  for _, rule in pairs(self.rules) do
    local metric = self.telemetry:get(rule.metric, now)
    local ok, triggered = pcall(rule.condition, metric)
    triggered = ok and triggered or false
    if triggered then
      rule.pendingSince = rule.pendingSince or now
      if not rule.active and now - rule.pendingSince >= rule.debounce and now - rule.lastAlert >= rule.cooldown then
        rule.active, rule.lastAlert = true, now
        self.notifications:push("alarm:" .. rule.id, rule.severity or "warning",
          rule.title or rule.id, rule.message or (rule.metric .. " threshold triggered"), {persistent = rule.persistent})
        changes[#changes + 1] = {id = rule.id, active = true}
      end
    else
      rule.pendingSince = nil
      if rule.active then
        rule.active = false; changes[#changes + 1] = {id = rule.id, active = false}
        if rule.notifyClear then self.notifications:push("alarm:" .. rule.id, "info", rule.title or rule.id, "Condition cleared") end
      end
    end
  end
  return changes
end

function Alarms:control(ruleId, action, subject, confirmed)
  local rule = self.rules[ruleId]
  if not rule or not rule.actions or not rule.actions[action] then return nil, "unknown action" end
  local spec = rule.actions[action]
  if spec.confirm and not confirmed then return nil, "confirmation required" end
  local allowed, reason = true
  if spec.interlock then allowed, reason = spec.interlock() end
  if not allowed then return nil, reason or "interlock denied action" end
  local ok, result = pcall(spec.execute, subject)
  if self.audit then self.audit(subject, "alarm-control", {rule = ruleId, action = action, ok = ok}) end
  if not ok then return nil, result end
  return result == nil and true or result
end

return Alarms
