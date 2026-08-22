-- OpenOS boot hook. Run after OpenOS has initialized its standard libraries.
local filesystem = require("filesystem")
local event = require("event")

local function read(path)
  local handle = io.open(path, "rb")
  if not handle then return nil end
  local data = handle:read("*a")
  handle:close()
  return data and data:gsub("%s+$", "")
end

local function startPlasmaOS()
  local active = assert(read("/system/active"), "PlasmaOS active version pointer is missing")
  local root = "/system/versions/" .. active
  assert(filesystem.exists(root .. "/src/boot/init.lua"), "PlasmaOS boot entry missing")
  _G.PLASMAOS_VERSION_ROOT, _G.PLASMAOS_BOOT_MODE = root, "normal"
  local chunk, err = loadfile(root .. "/src/boot/init.lua")
  assert(chunk, "PlasmaOS boot load failed: " .. tostring(err))
  return chunk(root)
end

local listener
listener = function()
  event.ignore("init", listener)
  startPlasmaOS()
end
event.listen("init", listener)
