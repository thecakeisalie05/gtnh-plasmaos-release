local Sha256 = require("libs.sha256")

local Users = {}
Users.__index = Users

function Users.new(options)
  options = options or {}
  return setmetatable({users = {}, tokens = {}, clock = options.clock or os.clock,
    entropy = options.entropy or function() return tostring(os.clock()) .. tostring(math.random()) end,
    audit = options.audit}, Users)
end

local function derive(secret, salt)
  local value = salt .. ":" .. secret
  for _ = 1, 256 do value = Sha256.digest(value .. salt) end
  return value
end

function Users:create(name, secret, admin)
  assert(type(name) == "string" and name:match("^[%w_.-]+$"), "invalid user name")
  if self.users[name] then return nil, "user exists" end
  local salt = Sha256.digest(self.entropy() .. name):sub(1, 24)
  self.users[name] = {name = name, salt = salt, verifier = secret and derive(secret, salt) or nil,
    admin = not not admin, capabilities = {}}
  if self.audit then self.audit(name, "user-created", {admin = not not admin}) end
  return true
end

function Users:authenticate(name, secret)
  local user = self.users[name]
  if not user then return false end
  if not user.verifier then return true end
  return derive(secret or "", user.salt) == user.verifier
end

function Users:issueToken(name, secret, ttl)
  if not self:authenticate(name, secret) then return nil, "authentication failed" end
  local token = Sha256.digest(self.entropy() .. name .. tostring(self.clock()))
  self.tokens[token] = {user = name, expiry = self.clock() + math.min(ttl or 300, 3600)}
  return token
end

function Users:verifyToken(token, requireAdmin)
  local record = self.tokens[token]
  if not record or record.expiry < self.clock() then self.tokens[token] = nil; return false end
  local user = self.users[record.user]
  return user and (not requireAdmin or user.admin), record.user
end

return Users
