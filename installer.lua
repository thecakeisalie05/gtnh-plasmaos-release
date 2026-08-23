-- GTNH PlasmaOS transactional installer. Runs under OpenOS before PlasmaOS boots.
local component = require("component")
local computer = require("computer")
local filesystem = require("filesystem")
local shell = require("shell")
local unpack = table.unpack or unpack

local function portableBits()
  if bit32 then return bit32 end
  local nativeFactory = load([[
    local MASK = 0xffffffff
    local function norm(value) return value & MASK end
    local function band(value, ...)
      value = norm(value)
      for index = 1, select("#", ...) do value = value & select(index, ...) end
      return norm(value)
    end
    local function bxor(value, ...)
      value = norm(value)
      for index = 1, select("#", ...) do value = value ~ select(index, ...) end
      return norm(value)
    end
    local function rrotate(value, count)
      count = count % 32; value = norm(value)
      if count == 0 then return value end
      return norm((value >> count) | (value << (32 - count)))
    end
    return {band=band, bxor=bxor, bnot=function(value) return norm(~value) end,
      rshift=function(value, count) return norm(value) >> count end, rrotate=rrotate}
  ]])
  if nativeFactory then
    local ok, native = pcall(nativeFactory)
    if ok then return native end
  end
  local MOD = 4294967296
  local function norm(value) return value % MOD end
  local function binary(a, b, exclusive)
    a, b = norm(a), norm(b); local result, place = 0, 1
    for _ = 1, 32 do
      local aa, bb = a % 2, b % 2
      if exclusive and aa ~= bb or not exclusive and aa == 1 and bb == 1 then result = result + place end
      a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
    end
    return result
  end
  return {
    band=function(a, ...) for i=1,select("#", ...) do a=binary(a,select(i,...),false) end return norm(a) end,
    bxor=function(a, ...) for i=1,select("#", ...) do a=binary(a,select(i,...),true) end return norm(a) end,
    bnot=function(a) return 4294967295-norm(a) end,
    rshift=function(a,n) return math.floor(norm(a)/2^n) end,
    rrotate=function(a,n) n=n%32;a=norm(a);return norm(math.floor(a/2^n)+(a%2^n)*2^(32-n)) end,
  }
end
local bit = portableBits()

local DEFAULT_BASE_URL = "https://raw.githubusercontent.com/thecakeisalie05/gtnh-plasmaos-release/main"
local MANIFEST_NAME = "manifest.txt"
local args = {...}
local download = _G.PLASMAOS_WGET or function(url, path)
  return shell.execute("wget", nil, "-f", url, path)
end

local function option(name)
  for index, value in ipairs(args) do if value == name then return args[index + 1] end end
end
local function flag(name) for _, value in ipairs(args) do if value == name then return true end end end

local function read(path)
  local handle, err = io.open(path, "rb"); if not handle then return nil, err end
  local data = handle:read("*a"); handle:close(); return data
end
local function write(path, data)
  local handle, err = io.open(path, "wb"); if not handle then return nil, err end
  local ok, writeErr = handle:write(data); handle:flush(); handle:close()
  if not ok then return nil, writeErr end; return true
end
local function atomic(path, data)
  local temporary = path .. ".new"; assert(write(temporary, data))
  local backup = path .. ".bak"; filesystem.remove(backup)
  if filesystem.exists(path) then assert(filesystem.rename(path, backup)) end
  local ok, err = filesystem.rename(temporary, path)
  if not ok then if filesystem.exists(backup) then filesystem.rename(backup, path) end; return nil, err end
  return true
end
local function mkdir(path) if not filesystem.exists(path) then return filesystem.makeDirectory(path) end return true end
local function parent(path) return path:match("^(.*)/[^/]+$") end
local function mountProxy(path)
  if type(filesystem.get) ~= "function" then return nil end
  return filesystem.get(path)
end
local function isReadOnly(path)
  if type(filesystem.isReadOnly) == "function" then return filesystem.isReadOnly(path) end
  local proxy = mountProxy(path)
  return proxy and type(proxy.isReadOnly) == "function" and proxy.isReadOnly() or false
end
local function spaceFree(path)
  if type(filesystem.spaceTotal) == "function" and type(filesystem.spaceUsed) == "function" then
    return filesystem.spaceTotal(path) - filesystem.spaceUsed(path)
  end
  local proxy = mountProxy(path)
  if proxy and type(proxy.spaceTotal) == "function" and type(proxy.spaceUsed) == "function" then
    return proxy.spaceTotal() - proxy.spaceUsed()
  end
  return math.huge
end
local function removeTree(path)
  if not filesystem.exists(path) then return true end
  if filesystem.isDirectory(path) then for name in filesystem.list(path) do
    local ok, err = removeTree(filesystem.concat(path, name)); if not ok then return nil, err end end end
  return filesystem.remove(path)
end

local band, bxor, bnot, rshift, rrotate = bit.band, bit.bxor, bit.bnot, bit.rshift, bit.rrotate
local MOD = 4294967296
local K = {0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2}
local function add(...) local sum=0; for i=1,select("#",...) do sum=(sum+select(i,...))%MOD end; return sum end
local function word(s,o) return s:byte(o)*0x1000000+s:byte(o+1)*0x10000+s:byte(o+2)*0x100+s:byte(o+3) end
local function sha256(message)
  local bits=#message*8; message=message..string.char(128)..string.rep("\0",(56-(#message+1)%64)%64)
  local hi,lo=math.floor(bits/MOD),bits%MOD
  message=message..string.char(band(rshift(hi,24),255),band(rshift(hi,16),255),band(rshift(hi,8),255),band(hi,255),band(rshift(lo,24),255),band(rshift(lo,16),255),band(rshift(lo,8),255),band(lo,255))
  local h={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
  for offset=1,#message,64 do local w={}; for i=0,15 do w[i]=word(message,offset+i*4) end
    for i=16,63 do local s0=bxor(rrotate(w[i-15],7),rrotate(w[i-15],18),rshift(w[i-15],3)); local s1=bxor(rrotate(w[i-2],17),rrotate(w[i-2],19),rshift(w[i-2],10)); w[i]=add(w[i-16],s0,w[i-7],s1) end
    local a,b,c,d,e,f,g,z=unpack(h)
    for i=0,63 do local s1=bxor(rrotate(e,6),rrotate(e,11),rrotate(e,25)); local ch=bxor(band(e,f),band(bnot(e),g)); local t1=add(z,s1,ch,K[i+1],w[i]); local s0=bxor(rrotate(a,2),rrotate(a,13),rrotate(a,22)); local maj=bxor(band(a,b),band(a,c),band(b,c)); local t2=add(s0,maj); z,g,f,e,d,c,b,a=g,f,e,add(d,t1),c,b,a,add(t1,t2) end
    h={add(h[1],a),add(h[2],b),add(h[3],c),add(h[4],d),add(h[5],e),add(h[6],f),add(h[7],g),add(h[8],z)} end
  local out=""; for i=1,8 do out=out..string.format("%08x",h[i]) end; return out
end

local function parseManifest(text)
  local manifest = {files = {}}
  local first = true
  for line in text:gmatch("[^\r\n]+") do
    if first then assert(line == "PLOS-MANIFEST\t1", "unsupported manifest"); first = false
    else
      local fields = {}; for field in (line .. "\t"):gmatch("(.-)\t") do fields[#fields + 1] = field end
      if fields[1] == "version" then manifest.version = fields[2]
      elseif fields[1] == "channel" then manifest.channel = fields[2]
      elseif fields[1] == "file" then
        assert(fields[2] and not fields[2]:find("%.%.",1,true) and fields[2]:sub(1,1) ~= "/", "unsafe manifest path")
        manifest.files[#manifest.files + 1] = {path=fields[2],size=tonumber(fields[3]),sha256=fields[4],profile=fields[5]}
      end
    end
  end
  assert(manifest.version and #manifest.files > 0, "incomplete manifest")
  return manifest
end

local baseUrl = option("--base-url") or DEFAULT_BASE_URL
local offline = option("--offline")
local profile = option("--profile") or (not component.isAvailable("gpu") and "server"
  or computer.totalMemory() < 524288 and "compact" or "full")
assert(profile=="full"or profile=="compact"or profile=="server","profile must be full, compact, or server")
assert(DEFAULT_BASE_URL:sub(1, 1) ~= "@" or offline or option("--base-url"),
  "installer is unpublished; pass --base-url or --offline")
assert(not isReadOnly("/"), "target filesystem is read-only")
assert(computer.totalMemory() >= 196608, "at least 192 KiB RAM is required for installation")
mkdir("/var/tmp"); mkdir("/system"); mkdir("/system/versions")
local manifestTemp = "/var/tmp/plasma-manifest.txt"
if offline then
  local source = filesystem.concat(offline, MANIFEST_NAME); assert(filesystem.exists(source), "offline manifest not found")
  assert(write(manifestTemp, assert(read(source))))
else
  assert(component.isAvailable("internet"), "Internet Card unavailable; use --offline <path>")
  assert(download(baseUrl .. "/" .. MANIFEST_NAME, manifestTemp), "manifest download failed")
end
local manifest = parseManifest(assert(read(manifestTemp)))
local selected={};local required=0
for _,file in ipairs(manifest.files)do if file.profile=="all"or file.profile==profile then selected[#selected+1]=file;required=required+file.size end end
local free = spaceFree("/")
assert(free >= required * 1.15 + 16384, "insufficient disk space")
local suffix = flag("--repair") and ("-repair-" .. math.floor(computer.uptime())) or ""
local versionName = manifest.version .. suffix
local staging = "/system/versions/.staging-" .. versionName
local final = "/system/versions/" .. versionName
if filesystem.exists(final) and not flag("--repair") then error("version already installed; use --repair") end
removeTree(staging); assert(mkdir(staging))
io.write("Install profile: "..profile.."\n")
for index, file in ipairs(selected) do
  local target = filesystem.concat(staging, file.path); assert(mkdir(parent(target)))
  io.write(string.format("[%d/%d] %s\n", index, #selected, file.path))
  local downloaded = false
  for attempt = 1, 3 do
    filesystem.remove(target)
    if offline then downloaded = write(target, assert(read(filesystem.concat(offline, file.path))))
    else downloaded = download(baseUrl .. "/" .. file.path, target) end
    local data = downloaded and read(target)
    if data and #data == file.size and sha256(data) == file.sha256 then downloaded = true; break end
    downloaded = false
  end
  if not downloaded then removeTree(staging); error("download/checksum failed: " .. file.path) end
end
assert(filesystem.exists(staging .. "/src/boot/init.lua"), "staged boot entry missing")
assert(write(staging .. "/.complete", manifest.version .. "\n"))
assert(filesystem.rename(staging, final), "unable to activate staged directory")
local oldActive = read("/system/active")
if oldActive then assert(atomic("/system/last-good", oldActive)) end
assert(atomic("/system/active", versionName))
assert(atomic("/system/boot-attempts", "0"))
local loader = assert(read(final .. "/installer/loader.lua"), "stage-1 loader absent")
mkdir("/etc"); mkdir("/etc/rc.d")
assert(atomic("/etc/rc.d/plasmaos.lua", loader))
filesystem.remove("/boot/99-plasmaos.lua")
local rcConfig = read("/etc/rc.cfg") or ""
if not rcConfig:find('"plasmaos"', 1, true) then
  local updated, count = rcConfig:gsub("(enabled%s*=%s*)(%b{})", function(prefix, list)
    return prefix .. list:sub(1, -2) .. (list == "{}" and "" or ", ") .. '"plasmaos"}'
  end, 1)
  if count == 0 then updated = rcConfig .. "\nenabled = {\"plasmaos\"}\n" end
  assert(atomic("/etc/rc.cfg", updated))
end
mkdir("/etc/plasmaos"); mkdir("/home")
assert(atomic("/etc/plasmaos/install-profile",profile))
io.write("PlasmaOS " .. manifest.version .. " installed transactionally. Rebooting.\n")
computer.shutdown(true)
