local Json = require("libs.json")
local Sha256 = require("libs.sha256")
local Txn = require("libs.fs_txn")

local Packages = {}
Packages.__index = Packages

function Packages.new(fs, options)
  options = options or {}
  return setmetatable({fs = fs, root = options.root or "/apps", databasePath = options.databasePath or "/var/lib/plasmaos/packages.json",
    installed = {}, transaction = options.transaction or Txn.new(fs, options.logger),
    audit = options.audit, versionRoot = options.versionRoot or "/system/versions"}, Packages)
end

function Packages:load()
  local data = self.fs.read(self.databasePath)
  if data then
    local ok, parsed = pcall(Json.decode, data)
    if ok and type(parsed) == "table" then self.installed = parsed end
  end
  return self.installed
end

function Packages:_save()
  return self.transaction:write(self.databasePath, Json.encode(self.installed), function(data)
    return type(Json.decode(data)) == "table"
  end)
end

function Packages:validate(manifest, files)
  assert(type(manifest) == "table" and manifest.id and manifest.version, "invalid package manifest")
  for _, dependency in ipairs(manifest.dependencies or {}) do
    if not self.installed[dependency] then return nil, "missing dependency: " .. dependency end
  end
  for path, expected in pairs(manifest.checksums or {}) do
    local data = files[path]
    if not data then return nil, "missing file: " .. path end
    if Sha256.digest(data) ~= expected then return nil, "checksum mismatch: " .. path end
  end
  return true
end

function Packages:install(manifest, files, subject)
  local ok, err = self:validate(manifest, files); if not ok then return nil, err end
  local staging = self.root .. "/.staging-" .. manifest.id
  self.fs.removeTree(staging); assert(self.fs.makeDirectory(staging))
  for path, data in pairs(files) do
    local target = self.fs.concat(staging, path)
    assert(self.fs.makeParent(target))
    local wrote, writeErr = self.fs.write(target, data)
    if not wrote then self.fs.removeTree(staging); return nil, writeErr end
  end
  local target = self.fs.concat(self.root, manifest.id)
  local backup = target .. ".previous"
  self.fs.removeTree(backup)
  if self.fs.exists(target) then
    local moved, moveErr = self.fs.rename(target, backup)
    if not moved then self.fs.removeTree(staging); return nil, moveErr end
  end
  local activated, activateErr = self.fs.rename(staging, target)
  if not activated then if self.fs.exists(backup) then self.fs.rename(backup, target) end; return nil, activateErr end
  local old = self.installed[manifest.id]
  self.installed[manifest.id] = {version = manifest.version, manifest = manifest}
  local saved, saveErr = self:_save()
  if not saved then
    self.fs.removeTree(target); if self.fs.exists(backup) then self.fs.rename(backup, target) end
    self.installed[manifest.id] = old; return nil, saveErr
  end
  if self.audit then self.audit(subject, "package-install", {id = manifest.id, version = manifest.version}) end
  return true
end

function Packages:remove(id, subject)
  if not self.installed[id] then return nil, "not installed" end
  local target, trash = self.fs.concat(self.root, id), self.fs.concat(self.root, ".removed-" .. id)
  self.fs.removeTree(trash)
  local moved, err = self.fs.rename(target, trash); if not moved then return nil, err end
  local record = self.installed[id]; self.installed[id] = nil
  local saved, saveErr = self:_save()
  if not saved then self.installed[id] = record; self.fs.rename(trash, target); return nil, saveErr end
  self.fs.removeTree(trash)
  if self.audit then self.audit(subject, "package-remove", {id = id}) end
  return true
end

function Packages:activateCore(version, metadataPath)
  local versionPath = self.fs.concat(self.versionRoot, version)
  if not self.fs.exists(self.fs.concat(versionPath, ".complete")) then return nil, "version not complete" end
  local currentData = self.fs.read(metadataPath)
  local current = currentData and Json.decode(currentData) or {bootAttempts = 0}
  local nextMetadata = {active = version, pending = version, lastKnownGood = current.active or current.lastKnownGood,
    bootAttempts = 0, schemaVersion = 1}
  return self.transaction:write(metadataPath, Json.encode(nextMetadata), function(data)
    local value = Json.decode(data); return value.active == version
  end)
end

function Packages:rollback(metadataPath)
  local data = self.fs.read(metadataPath); if not data then return nil, "boot metadata missing" end
  local metadata = Json.decode(data)
  if not metadata.lastKnownGood then return nil, "no last-known-good version" end
  metadata.active, metadata.pending, metadata.bootAttempts = metadata.lastKnownGood, nil, 0
  return self.transaction:write(metadataPath, Json.encode(metadata), function(value)
    return Json.decode(value).active == metadata.active
  end)
end

return Packages
