-- Pastebin-friendly bootstrap. Publication tooling fills these constants.
local INSTALLER_URL = "https://raw.githubusercontent.com/thecakeisalie05/gtnh-plasmaos-release/main/installer.lua"
local FALLBACK_URL = ""
local INSTALLER_SIZE = tonumber("11993")
local INSTALLER_SHA256 = "37b06adc5b04dfa772ae5a23e7c3f6cf558254c7a7bd51a2bf1e83a2a2e7050f"
local component = require("component")
local shell = require("shell")
local filesystem = require("filesystem")
local unpack = table.unpack or unpack
local args = {...}
local target = "/tmp/plasmaos-installer.lua"
local download = _G.PLASMAOS_WGET or function(url, path)
  return shell.execute("wget", nil, "-f", url, path)
end

local function fetch(url)
  filesystem.remove(target)
  return url ~= "" and url:sub(1,1) ~= "@" and download(url, target)
end
assert(component.isAvailable("internet"), "Internet Card required (or use the offline release archive)")
local fetchedFrom = fetch(INSTALLER_URL) and INSTALLER_URL or fetch(FALLBACK_URL) and FALLBACK_URL
assert(fetchedFrom, "unable to download PlasmaOS installer")
local handle = assert(io.open(target, "rb")); local data = handle:read("*a"); handle:close()
assert(#data == INSTALLER_SIZE, "installer size mismatch")
if component.isAvailable("data") then
  local raw = component.data.sha256(data)
  local hex = #raw == 64 and raw:match("^%x+$") and raw:lower()
    or raw:gsub(".", function(char) return string.format("%02x", char:byte()) end)
  assert(hex == INSTALLER_SHA256, "installer checksum mismatch")
else io.stderr:write("Warning: no Data Card; full installer will verify every release file.\n") end
local chunk, err = load(data, "=plasmaos-installer", "t", _G); assert(chunk, err)
local sourceSpecified = false
for _, value in ipairs(args) do
  if value == "--base-url" or value == "--offline" then sourceSpecified = true; break end
end
local releaseBase = fetchedFrom:match("^(.*)/installer%.lua$")
if not sourceSpecified and releaseBase then
  args[#args + 1] = "--base-url"; args[#args + 1] = releaseBase
end
local ok, runtimeError = xpcall(function() return chunk(unpack(args)) end, debug.traceback)
assert(ok, runtimeError)
