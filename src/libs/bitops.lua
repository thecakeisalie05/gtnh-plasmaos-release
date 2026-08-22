local existing = rawget(_G, "bit32")
if existing then return existing end

-- Lua 5.3 has fast native bit operators but no bit32 global. Compile these
-- dynamically so this module still parses on Lua 5.2 machines.
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
    count = count % 32
    value = norm(value)
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

-- Portable fallback for unusual Lua builds without bit32 or native operators.
local MOD = 4294967296
local function norm(value) return value % MOD end
local function binary(a, b, exclusive)
  a, b = norm(a), norm(b)
  local result, place = 0, 1
  for _ = 1, 32 do
    local aa, bb = a % 2, b % 2
    if exclusive and aa ~= bb or not exclusive and aa == 1 and bb == 1 then result = result + place end
    a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
  end
  return result
end
return {
  band = function(a, ...)
    for index = 1, select("#", ...) do a = binary(a, select(index, ...), false) end
    return norm(a)
  end,
  bxor = function(a, ...)
    for index = 1, select("#", ...) do a = binary(a, select(index, ...), true) end
    return norm(a)
  end,
  bnot = function(a) return 4294967295 - norm(a) end,
  rshift = function(a, count) return math.floor(norm(a) / 2 ^ count) end,
  rrotate = function(a, count)
    count = count % 32
    a = norm(a)
    return norm(math.floor(a / 2 ^ count) + (a % 2 ^ count) * 2 ^ (32 - count))
  end,
}
