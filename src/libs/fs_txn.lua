local Txn = {}
Txn.__index = Txn

local function hostAdapter()
  return {
    read = function(path)
      local handle, err = io.open(path, "rb")
      if not handle then return nil, err end
      local data = handle:read("*a"); handle:close(); return data
    end,
    write = function(path, data)
      local handle, err = io.open(path, "wb")
      if not handle then return nil, err end
      local ok, writeErr = handle:write(data)
      handle:flush(); handle:close()
      if not ok then return nil, writeErr end
      return true
    end,
    exists = function(path)
      local handle = io.open(path, "rb")
      if handle then handle:close(); return true end
      return false
    end,
    remove = function(path) return os.remove(path) end,
    rename = function(from, to) return os.rename(from, to) end,
  }
end

function Txn.new(adapter, logger)
  return setmetatable({fs = adapter or hostAdapter(), logger = logger}, Txn)
end

function Txn:_log(level, message, fields)
  if self.logger then self.logger:write(level, "fs_txn", message, fields) end
end

function Txn:write(path, data, validator)
  local fresh, backup = path .. ".new", path .. ".bak"
  local ok, err = self.fs.write(fresh, data)
  if not ok then return nil, "write staging: " .. tostring(err) end
  local staged, readErr = self.fs.read(fresh)
  if not staged then self.fs.remove(fresh); return nil, "read staging: " .. tostring(readErr) end
  if validator then
    local valid, validation = pcall(validator, staged)
    if not valid or validation == false then
      self.fs.remove(fresh)
      return nil, "validation failed: " .. tostring(validation)
    end
  end
  local hadOriginal = self.fs.exists(path)
  if hadOriginal then
    self.fs.remove(backup)
    local moved, moveErr = self.fs.rename(path, backup)
    if not moved then self.fs.remove(fresh); return nil, "backup: " .. tostring(moveErr) end
  end
  local activated, activateErr = self.fs.rename(fresh, path)
  if not activated then
    if hadOriginal then self.fs.rename(backup, path) end
    self.fs.remove(fresh)
    return nil, "activate: " .. tostring(activateErr)
  end
  self:_log("info", "atomic write committed", {path = path, backup = hadOriginal})
  return true
end

function Txn:recover(path, validator)
  local fresh, backup = path .. ".new", path .. ".bak"
  if self.fs.exists(path) then
    if self.fs.exists(fresh) then self.fs.remove(fresh) end
    return true, "current"
  end
  if self.fs.exists(fresh) then
    local data = self.fs.read(fresh)
    local valid = true
    if validator then
      local checked, result = pcall(validator, data)
      valid = checked and result ~= false
    end
    if valid and self.fs.rename(fresh, path) then return true, "staged" end
    self.fs.remove(fresh)
  end
  if self.fs.exists(backup) and self.fs.rename(backup, path) then return true, "backup" end
  return nil, "no recoverable copy"
end

return Txn
