-- Stable stage-1 loader. Installed as /init.lua; versioned code stays immutable.
local filesystem = require("filesystem")
local computer = require("computer")

local function read(path)
  local handle = io.open(path, "rb"); if not handle then return nil end
  local data = handle:read("*a"); handle:close(); return data and data:gsub("%s+$", "")
end

local function atomic(path, value)
  local temporary = path .. ".new"
  local handle = assert(io.open(temporary, "wb")); assert(handle:write(value)); handle:close()
  filesystem.remove(path); assert(filesystem.rename(temporary, path))
end

local active = read("/system/active")
local previous = read("/system/last-good")
local attempts = tonumber(read("/system/boot-attempts") or "0") or 0
if not active then error("PlasmaOS active version pointer is missing") end
local mode = "normal"
local signal, _, _, code = computer.pullSignal(0.35)
if signal == "key_down" and (code == 42 or code == 54) then
  io.write("GTNH PlasmaOS boot menu\n1 Normal\n2 Safe mode\n3 Recovery shell\n4 Previous version\n> ")
  local choice = io.read()
  if choice == "2" then mode = "safe" elseif choice == "3" then mode = "recovery"
  elseif choice == "4" and previous then active = previous end
end
if attempts >= 3 and previous and previous ~= active then active, mode = previous, "safe" end
atomic("/system/boot-attempts", tostring(attempts + 1))
local root = "/system/versions/" .. active
local entry = root .. "/src/boot/init.lua"
package.path = root .. "/src/?.lua;" .. root .. "/src/?/init.lua;" .. package.path
local chunk, loadError = loadfile(entry)
if not chunk then error("PlasmaOS boot load failed: " .. tostring(loadError)) end
_G.PLASMAOS_VERSION_ROOT, _G.PLASMAOS_BOOT_MODE = root, mode
local ok, runtimeError = xpcall(function() return chunk(root) end, debug.traceback)
if not ok then
  io.stderr:write("PlasmaOS boot failed:\n" .. tostring(runtimeError) .. "\n")
  _G.PLASMAOS_BOOT_MODE, _G.PLASMAOS_BOOT_REASON = "recovery", runtimeError
  local safeChunk = loadfile(root .. "/src/boot/safe_mode.lua")
  if safeChunk then
    local safe = safeChunk()
    safe.run(require("compat.openos").load(), runtimeError)
  end
end
