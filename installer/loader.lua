-- Stage-1 loader. This is /init.lua, where OpenComputers has not created
-- require/package yet; keep it intentionally dependency-free.
local bootFilesystem = component.proxy(computer.getBootAddress())

local function read(path)
  local handle = bootFilesystem.open(path, "rb")
  if not handle then return nil end
  local chunks = {}
  while true do
    local chunk = bootFilesystem.read(handle, 2048)
    if not chunk then break end
    chunks[#chunks + 1] = chunk
  end
  bootFilesystem.close(handle)
  return table.concat(chunks):gsub("%s+$", "")
end

local function loadfile(path)
  local source = read(path)
  if not source then return nil, "file not found: " .. path end
  return load(source, "=" .. path, "t", _G)
end

local active = assert(read("/system/active"), "PlasmaOS active version pointer is missing")
local root = "/system/versions/" .. active

local filesystem = {
  open = function(path, mode) return bootFilesystem.open(path, (mode or "r"):gsub("b", "")) end,
  read = function(handle, count) return bootFilesystem.read(handle, count) end,
  write = function(handle, data) return bootFilesystem.write(handle, data) end,
  close = function(handle) return bootFilesystem.close(handle) end,
  exists = function(path) return bootFilesystem.exists(path) end,
  isDirectory = function(path) return bootFilesystem.isDirectory(path) end,
  list = function(path) return bootFilesystem.list(path) end,
  remove = function(path) return bootFilesystem.remove(path) end,
  rename = function(from, to) return bootFilesystem.rename(from, to) end,
  makeDirectory = function(path) return bootFilesystem.makeDirectory(path) end,
  isReadOnly = function() return bootFilesystem.isReadOnly() end,
  spaceTotal = function() return bootFilesystem.spaceTotal() end,
  spaceUsed = function() return bootFilesystem.spaceUsed() end,
  get = function() return bootFilesystem end,
  concat = function(a, b) return a:gsub("/$", "") .. "/" .. b:gsub("^/", "") end,
  path = function(path) return path:match("^(.*)/[^/]+$") or "" end,
}
local io = {stderr = {write = function(_, text) return computer.beep and computer.beep() end}}
function io.open(path, mode)
  local handle, reason = filesystem.open(path, mode)
  if not handle then return nil, reason end
  local file = {}
  function file:read(format)
    if format == "*a" or format == nil then
      local chunks = {}; while true do local data = filesystem.read(handle, 2048); if not data then break end; chunks[#chunks + 1] = data end
      return table.concat(chunks)
    end
    return filesystem.read(handle, type(format) == "number" and format or 2048)
  end
  function file:write(data) return filesystem.write(handle, data) end
  function file:flush() return true end
  function file:close() return filesystem.close(handle) end
  return file
end
_G.io = io
local packageTable = package or {path = "", loaded = {}}
packageTable.path = root .. "/src/?.lua;" .. root .. "/src/?/init.lua;" .. (packageTable.path or "")
_G.package = packageTable

local function require(name)
  if packageTable.loaded[name] ~= nil then return packageTable.loaded[name] end
  if name == "component" then return component end
  if name == "computer" then return computer end
  if name == "filesystem" then return filesystem end
  local relative = name:gsub("%.", "/")
  local chunk, err = loadfile(root .. "/src/" .. relative .. ".lua")
  if not chunk then chunk, err = loadfile(root .. "/src/" .. relative .. "/init.lua") end
  assert(chunk, "module not found: " .. name .. ": " .. tostring(err))
  local value = chunk()
  if value == nil then value = true end
  packageTable.loaded[name] = value
  return value
end

_G.require = require
_G.PLASMAOS_VERSION_ROOT, _G.PLASMAOS_BOOT_MODE = root, "normal"
local chunk, err = loadfile(root .. "/src/boot/init.lua")
assert(chunk, "PlasmaOS boot load failed: " .. tostring(err))
return chunk(root)
