local json = {}

local escapes = {['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
  ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}

local function encodeString(value)
  return '"' .. value:gsub('[%z\1-\31\\"]', function(char)
    return escapes[char] or string.format('\\u%04x', char:byte())
  end) .. '"'
end

local function isArray(value)
  local max, count = 0, 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
    if key > max then max = key end
    count = count + 1
  end
  return max == count, max
end

local function encode(value, seen)
  local kind = type(value)
  if kind == "nil" then return "null" end
  if kind == "boolean" then return value and "true" or "false" end
  if kind == "number" then
    assert(value == value and value ~= math.huge and value ~= -math.huge, "non-finite number")
    return tostring(value)
  end
  if kind == "string" then return encodeString(value) end
  assert(kind == "table", "unsupported JSON type: " .. kind)
  assert(not seen[value], "cyclic table")
  seen[value] = true
  local array, length = isArray(value)
  local parts = {}
  if array then
    for i = 1, length do parts[i] = encode(value[i], seen) end
    seen[value] = nil
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for key in pairs(value) do
    assert(type(key) == "string", "JSON object keys must be strings")
    keys[#keys + 1] = key
  end
  table.sort(keys)
  for i, key in ipairs(keys) do
    parts[i] = encodeString(key) .. ":" .. encode(value[key], seen)
  end
  seen[value] = nil
  return "{" .. table.concat(parts, ",") .. "}"
end

function json.encode(value)
  return encode(value, {})
end

local function utf8(code)
  if code < 0x80 then return string.char(code) end
  if code < 0x800 then
    return string.char(0xC0 + math.floor(code / 64), 0x80 + code % 64)
  end
  return string.char(0xE0 + math.floor(code / 4096),
    0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
end

function json.decode(text)
  assert(type(text) == "string", "JSON input must be a string")
  local position, length = 1, #text
  local function skip()
    local _, finish = text:find("^[ \t\r\n]*", position)
    position = (finish or position - 1) + 1
  end
  local parseValue
  local function parseString()
    assert(text:sub(position, position) == '"', "expected string")
    position = position + 1
    local out = {}
    while position <= length do
      local char = text:sub(position, position)
      if char == '"' then position = position + 1; return table.concat(out) end
      if char == "\\" then
        local code = text:sub(position + 1, position + 1)
        local mapped = ({['"']='"', ['\\']='\\', ['/']='/', b='\b', f='\f', n='\n', r='\r', t='\t'})[code]
        if mapped then out[#out + 1] = mapped; position = position + 2
        elseif code == "u" then
          local hex = text:sub(position + 2, position + 5)
          assert(hex:match("^%x%x%x%x$"), "invalid unicode escape")
          out[#out + 1] = utf8(tonumber(hex, 16)); position = position + 6
        else error("invalid escape") end
      else
        assert(char:byte() >= 32, "control character in string")
        out[#out + 1] = char; position = position + 1
      end
    end
    error("unterminated string")
  end
  local function parseArray()
    position = position + 1; skip()
    local out = {}
    if text:sub(position, position) == "]" then position = position + 1; return out end
    while true do
      out[#out + 1] = parseValue(); skip()
      local char = text:sub(position, position); position = position + 1
      if char == "]" then return out end
      assert(char == ",", "expected comma")
      skip()
    end
  end
  local function parseObject()
    position = position + 1; skip()
    local out = {}
    if text:sub(position, position) == "}" then position = position + 1; return out end
    while true do
      local key = parseString(); skip()
      assert(text:sub(position, position) == ":", "expected colon")
      position = position + 1; skip(); out[key] = parseValue(); skip()
      local char = text:sub(position, position); position = position + 1
      if char == "}" then return out end
      assert(char == ",", "expected comma")
      skip()
    end
  end
  function parseValue()
    skip()
    local char = text:sub(position, position)
    if char == '"' then return parseString() end
    if char == "[" then return parseArray() end
    if char == "{" then return parseObject() end
    local token = text:match("^-?%d+%.?%d*[eE]?[+-]?%d*", position)
    if token and #token > 0 then position = position + #token; return assert(tonumber(token)) end
    if text:sub(position, position + 3) == "true" then position = position + 4; return true end
    if text:sub(position, position + 4) == "false" then position = position + 5; return false end
    if text:sub(position, position + 3) == "null" then position = position + 4; return nil end
    error("invalid JSON at byte " .. position)
  end
  local value = parseValue(); skip()
  assert(position > length, "trailing JSON content")
  return value
end

return json
