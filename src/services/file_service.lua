local Files = {}
Files.__index = Files

function Files.new(fs, jobs, options)
  options = options or {}
  return setmetatable({fs = fs, jobs = jobs, home = options.home or "/home/player",
    trash = options.trash or "/home/player/.Trash", audit = options.audit}, Files)
end

function Files:list(path, hidden)
  local names, err = self.fs.list(path); if not names then return nil, err end
  local out = {}
  for _, name in ipairs(names) do
    if hidden or name:sub(1, 1) ~= "." then
      local full = self.fs.concat(path, name)
      out[#out + 1] = {name = name, path = full, directory = self.fs.isDirectory(full),
        readOnly = self.fs.isReadOnly and self.fs.isReadOnly(full) or false}
    end
  end
  table.sort(out, function(a, b)
    if a.directory ~= b.directory then return a.directory end
    return a.name:lower() < b.name:lower()
  end)
  return out
end

function Files:createFile(path)
  if self.fs.exists(path) then return nil, "already exists" end
  assert(self.fs.makeParent(path)); return self.fs.write(path, "")
end

function Files:createDirectory(path) return self.fs.makeDirectory(path) end

function Files:rename(path, newName)
  local parent = path:match("^(.*)/[^/]+$") or "/"
  return self.fs.rename(path, self.fs.concat(parent, newName))
end

function Files:copy(path, target, callback) return self.jobs:copy(path, target, callback) end
function Files:move(path, target) return self.fs.rename(path, target) end

function Files:trashPath(path)
  assert(self.fs.makeDirectory(self.trash))
  local name = path:match("([^/]+)$") or "item"
  local target, suffix = self.fs.concat(self.trash, name), 0
  while self.fs.exists(target) do suffix = suffix + 1; target = self.fs.concat(self.trash, name .. "." .. suffix) end
  local ok, err = self.fs.rename(path, target)
  if ok and self.audit then self.audit("player", "file-trash", {path = path, target = target}) end
  return ok, err, target
end

function Files:delete(path, confirmed)
  if not confirmed then return nil, "confirmation required" end
  local ok, err = self.fs.removeTree(path)
  if ok and self.audit then self.audit("player", "file-delete", {path = path}) end
  return ok, err
end

function Files:properties(path)
  if not self.fs.exists(path) then return nil, "not found" end
  return {path = path, directory = self.fs.isDirectory(path),
    readOnly = self.fs.isReadOnly and self.fs.isReadOnly(path) or false}
end

function Files:search(root, query, limit, scanLimit)
  limit = limit or 100; scanLimit = scanLimit or limit * 20
  local results, stack, scanned = {}, {root}, 0
  while #stack > 0 and #results < limit and scanned < scanLimit do
    local path = table.remove(stack)
    local entries = self:list(path, true) or {}
    for _, entry in ipairs(entries) do
      scanned = scanned + 1
      if entry.name:lower():find(query:lower(), 1, true) then results[#results + 1] = entry end
      if entry.directory and #stack < limit then stack[#stack + 1] = entry.path end
      if #results >= limit or scanned >= scanLimit then break end
    end
  end
  return results, scanned >= scanLimit and "scan limit reached" or nil
end

return Files
