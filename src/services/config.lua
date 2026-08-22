local Json = require("libs.json")
local Txn = require("libs.fs_txn")

local Config = {}
Config.__index = Config

function Config.new(options)
  options = options or {}
  return setmetatable({root = options.root or "/etc/plasmaos", schemas = {}, cache = {},
    transaction = options.transaction or Txn.new(options.fs, options.logger),
    logger = options.logger}, Config)
end

function Config:register(name, schema)
  assert(type(schema.version) == "number" and schema.defaults, "invalid schema")
  self.schemas[name] = schema
end

function Config:path(name) return self.root .. "/" .. name .. ".json" end

function Config:_validate(schema, value)
  assert(type(value) == "table", "config must be an object")
  assert(type(value.schemaVersion) == "number", "missing schemaVersion")
  if schema.validate then assert(schema.validate(value), "schema rejected config") end
  return true
end

function Config:load(name)
  if self.cache[name] then return self.cache[name] end
  local schema = assert(self.schemas[name], "unknown config schema")
  local data = self.transaction.fs.read(self:path(name))
  local value
  if data then
    local ok, decoded = pcall(Json.decode, data)
    if ok then value = decoded
    else
      self.transaction.fs.rename(self:path(name), self:path(name) .. ".corrupt")
      if self.logger then self.logger:write("warning", "config", "corrupt config isolated",
        {name = name, error = tostring(decoded)}) end
    end
  end
  if not value then
    value = {}; for key, item in pairs(schema.defaults) do value[key] = item end
    value.schemaVersion = schema.version
  end
  while value.schemaVersion < schema.version do
    local previousVersion = value.schemaVersion
    local migration = schema.migrations and schema.migrations[previousVersion]
    assert(migration, "no migration from schema " .. previousVersion)
    local nextValue = migration(value)
    assert(type(nextValue) == "table" and nextValue.schemaVersion == previousVersion + 1,
      "migration did not advance exactly one version")
    value = nextValue
  end
  self:_validate(schema, value)
  self.cache[name] = value
  return value
end

function Config:save(name, value)
  local schema = assert(self.schemas[name], "unknown config schema")
  self:_validate(schema, value)
  local encoded = Json.encode(value)
  local ok, err = self.transaction:write(self:path(name), encoded, function(text)
    local decoded = Json.decode(text); return self:_validate(schema, decoded)
  end)
  if ok then self.cache[name] = value end
  return ok, err
end

function Config:update(name, mutator)
  local current = self:load(name)
  local copy = {}; for key, value in pairs(current) do copy[key] = value end
  local result = mutator(copy) or copy
  return self:save(name, result)
end

return Config
