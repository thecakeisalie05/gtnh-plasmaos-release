-- Stage-1 loader. This is /init.lua, where OpenComputers has not created
-- require/package yet; keep it intentionally dependency-free.
local filesystem = component.proxy(computer.getBootAddress())

local function read(path)
  local handle = filesystem.open(path, "rb")
  if not handle then return nil end
  local chunks = {}
  while true do
    local chunk = filesystem.read(handle, 2048)
    if not chunk then break end
    chunks[#chunks + 1] = chunk
  end
  filesystem.close(handle)
  return table.concat(chunks):gsub("%s+$", "")
end

local function loadfile(path)
  local source = read(path)
  if not source then return nil, "file not found: " .. path end
  return load(source, "=" .. path, "t", _G)
end

local active = assert(read("/system/active"), "PlasmaOS active version pointer is missing")
local root = "/system/versions/" .. active
local packageTable = package or {path = "", loaded = {}}
packageTable.path = root .. "/src/?.lua;" .. root .. "/src/?/init.lua;" .. (packageTable.path or "")
_G.package = packageTable

local function require(name)
  if packageTable.loaded[name] ~= nil then return packageTable.loaded[name] end
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
