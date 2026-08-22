local bit = bit32
assert(bit, "SHA-256 requires Lua 5.2 bit32")

local band, bxor, bnot = bit.band, bit.bxor, bit.bnot
local rshift, rrotate = bit.rshift, bit.rrotate
local MOD = 4294967296
local K = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}

local function add(...)
  local sum = 0
  for index = 1, select("#", ...) do sum = (sum + select(index, ...)) % MOD end
  return sum
end

local function word(bytes, offset)
  return bytes:byte(offset) * 0x1000000 + bytes:byte(offset + 1) * 0x10000
    + bytes:byte(offset + 2) * 0x100 + bytes:byte(offset + 3)
end

local HEX = "0123456789abcdef"
local function hexWord(value)
  local out = {}
  for index = 8, 1, -1 do
    local digit = value % 16
    out[index] = HEX:sub(digit + 1, digit + 1)
    value = math.floor(value / 16)
  end
  return table.concat(out)
end

local sha256 = {}

function sha256.digest(message)
  local length = #message
  local bitLength = length * 8
  message = message .. string.char(0x80)
  local padding = (56 - (#message % 64)) % 64
  message = message .. string.rep("\0", padding)
  local high = math.floor(bitLength / MOD)
  local low = bitLength % MOD
  message = message .. string.char(
    band(rshift(high, 24), 0xff), band(rshift(high, 16), 0xff), band(rshift(high, 8), 0xff), band(high, 0xff),
    band(rshift(low, 24), 0xff), band(rshift(low, 16), 0xff), band(rshift(low, 8), 0xff), band(low, 0xff))
  local h = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
  for offset = 1, #message, 64 do
    local w = {}
    for i = 0, 15 do w[i] = word(message, offset + i * 4) end
    for i = 16, 63 do
      local s0 = bxor(rrotate(w[i - 15], 7), rrotate(w[i - 15], 18), rshift(w[i - 15], 3))
      local s1 = bxor(rrotate(w[i - 2], 17), rrotate(w[i - 2], 19), rshift(w[i - 2], 10))
      w[i] = add(w[i - 16], s0, w[i - 7], s1)
    end
    local a,b,c,d,e,f,g,hh = h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8]
    for i = 0, 63 do
      local s1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
      local choose = bxor(band(e, f), band(bnot(e), g))
      local t1 = add(hh, s1, choose, K[i + 1], w[i])
      local s0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
      local majority = bxor(band(a, b), band(a, c), band(b, c))
      local t2 = add(s0, majority)
      hh,g,f,e,d,c,b,a = g,f,e,add(d,t1),c,b,a,add(t1,t2)
    end
    h[1],h[2],h[3],h[4] = add(h[1],a),add(h[2],b),add(h[3],c),add(h[4],d)
    h[5],h[6],h[7],h[8] = add(h[5],e),add(h[6],f),add(h[7],g),add(h[8],hh)
  end
  return hexWord(h[1])..hexWord(h[2])..hexWord(h[3])..hexWord(h[4])
    ..hexWord(h[5])..hexWord(h[6])..hexWord(h[7])..hexWord(h[8])
end

return sha256
