local FirstRun = {}
FirstRun.__index = FirstRun

local steps = {"hardware", "user", "theme", "display", "network", "components", "dashboard", "updates", "finish"}

function FirstRun.new(config)
  return setmetatable({config = config}, FirstRun)
end

function FirstRun:state()
  return self.config:load("first_run")
end

function FirstRun:current()
  local state = self:state()
  return steps[state.step or 1], state.step or 1, #steps, state.completed
end

function FirstRun:advance(values)
  local state = self:state()
  for key, value in pairs(values or {}) do state[key] = value end
  if (state.step or 1) >= #steps then state.completed = true
  else state.step = (state.step or 1) + 1 end
  local ok, err = self.config:save("first_run", state)
  if not ok then return nil, err end
  return self:current()
end

return FirstRun
