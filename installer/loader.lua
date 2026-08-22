-- OpenOS RC service: PlasmaOS starts after the normal OpenOS runtime is ready.
local function read(path)
  local handle = io.open(path, "rb")
  if not handle then return nil end
  local data = handle:read("*a")
  handle:close()
  return data and data:gsub("%s+$", "")
end

function start()
  io.write("[PlasmaOS] locating active release...\n")
  local active = assert(read("/system/active"), "PlasmaOS active version pointer is missing")
  local root = "/system/versions/" .. active
  _G.PLASMAOS_VERSION_ROOT, _G.PLASMAOS_BOOT_MODE = root, "normal"
  io.write("[PlasmaOS] loading kernel...\n")
  local chunk, err = loadfile(root .. "/src/boot/init.lua")
  assert(chunk, "PlasmaOS boot load failed: " .. tostring(err))
  io.write("[PlasmaOS] starting kernel...\n")
  return chunk(root)
end
