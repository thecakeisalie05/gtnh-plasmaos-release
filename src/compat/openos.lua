local OpenOS = {}

function OpenOS.load()
  -- The stage-one PlasmaOS loader runs before OpenOS creates require().
  -- Prefer its firmware bridges, then retain normal OpenOS compatibility.
  local component = _G.component or require("component")
  local computer = _G.computer or require("computer")
  local filesystem = _G.PLASMAOS_BOOT_FILESYSTEM or require("filesystem")
  local shellOk, shell = pcall(require, "shell")

  local components = {
    list = function(filter) return component.list(filter) end,
    proxy = function(address) return component.proxy(address) end,
    invoke = function(address, method, ...) return component.invoke(address, method, ...) end,
    methods = function(address) return component.methods(address) end,
    type = function(address) return component.type(address) end,
  }

  local fs = {}
  local function mountProxy(path)
    if type(filesystem.get) ~= "function" then return nil end
    return filesystem.get(path)
  end
  function fs.read(path)
    local handle, err = io.open(path, "rb"); if not handle then return nil, err end
    local data = handle:read("*a"); handle:close(); return data
  end
  function fs.write(path, data)
    local handle, err = io.open(path, "wb"); if not handle then return nil, err end
    local ok, writeErr = handle:write(data); handle:flush(); handle:close()
    if not ok then return nil, writeErr end; return true
  end
  function fs.open(path, mode) return io.open(path, mode) end
  function fs.exists(path) return filesystem.exists(path) end
  function fs.isDirectory(path) return filesystem.isDirectory(path) end
  function fs.isReadOnly(path)
    if type(filesystem.isReadOnly) == "function" then return filesystem.isReadOnly(path) end
    local proxy = mountProxy(path)
    return proxy and type(proxy.isReadOnly) == "function" and proxy.isReadOnly() or false
  end
  function fs.concat(a, b) return filesystem.concat(a, b) end
  function fs.makeDirectory(path) return filesystem.makeDirectory(path) end
  function fs.makeParent(path)
    local parent = filesystem.path(path)
    return parent == nil or parent == "" or filesystem.exists(parent) or filesystem.makeDirectory(parent)
  end
  function fs.list(path)
    local ok, iterator = pcall(filesystem.list, path); if not ok then return nil, iterator end
    local out = {}; for name in iterator do out[#out + 1] = name:gsub("/$", "") end
    table.sort(out); return out
  end
  function fs.remove(path) return filesystem.remove(path) end
  function fs.rename(from, to) return filesystem.rename(from, to) end
  function fs.removeTree(path)
    if not filesystem.exists(path) then return true end
    if filesystem.isDirectory(path) then
      for name in filesystem.list(path) do
        local ok, err = fs.removeTree(filesystem.concat(path, name)); if not ok then return nil, err end
      end
    end
    return filesystem.remove(path)
  end
  function fs.space(path)
    if type(filesystem.spaceTotal) == "function" and type(filesystem.spaceUsed) == "function" then
      return filesystem.spaceTotal(path) - filesystem.spaceUsed(path), filesystem.spaceTotal(path)
    end
    local proxy = mountProxy(path)
    if proxy and type(proxy.spaceTotal) == "function" and type(proxy.spaceUsed) == "function" then
      local total = proxy.spaceTotal()
      return total - proxy.spaceUsed(), total
    end
    return math.huge, math.huge
  end

  return {component = components, computer = computer, fs = fs,
    shell = shellOk and shell or nil, uptime = computer.uptime,
    pullSignal = computer.pullSignal, shutdown = computer.shutdown}
end

return OpenOS
