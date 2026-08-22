-- Generic adapters are configured from observed method snapshots. No GTNH method
-- name is guessed here; each probe names a method verified by the user in-game.
local Generic = {}
local unpack = table.unpack or unpack

function Generic.fromConfig(config)
  assert(config.id and config.componentType and type(config.probes) == "table", "invalid adapter config")
  return {
    id = config.id,
    pollInterval = config.pollInterval or 10,
    detect = function(component) return component.type == config.componentType end,
    poll = function(address, broker, component)
      local available = {}; for _, name in ipairs(component.methods or {}) do available[name] = true end
      local values = {}
      for metric, probe in pairs(config.probes) do
        if available[probe.method] then
          local result = {broker:invoke(address, probe.method, unpack(probe.args or {}))}
          if result[1] then values[metric] = {value = result[2], unit = probe.unit, quality = "live"}
          else values[metric] = {value = nil, unit = probe.unit, quality = "error"} end
        else values[metric] = {value = nil, unit = probe.unit, quality = "unavailable"} end
      end
      return values
    end,
    actions = config.actions,
  }
end

return Generic
