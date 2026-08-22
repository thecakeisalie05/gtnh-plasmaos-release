local SafeMode = {}

function SafeMode.run(environment, reason)
  io.write("\nGTNH PlasmaOS safe mode\n")
  if reason then io.write("Reason: " .. tostring(reason) .. "\n") end
  io.write("Network and graphical services are disabled. Type 'help'.\n")
  while true do
    io.write("safe> ")
    local line = io.read()
    if not line then return end
    local command, argument = line:match("^(%S+)%s*(.-)%s*$")
    if command == "help" then io.write("help, ls [path], cat <path>, logs, versions, use <version>, reboot, shutdown\n")
    elseif command == "ls" then
      local list, err = environment.fs.list(argument ~= "" and argument or "/")
      if list then for _, name in ipairs(list) do io.write(name .. "\n") end else io.write("error: " .. tostring(err) .. "\n") end
    elseif command == "cat" then io.write((environment.fs.read(argument) or "unable to read") .. "\n")
    elseif command == "logs" then io.write((environment.fs.read("/var/log/plasmaos/startup.log") or "no startup log") .. "\n")
    elseif command == "versions" then
      local list = environment.fs.list("/system/versions") or {}; for _, version in ipairs(list) do io.write(version .. "\n") end
    elseif command == "use" and argument ~= "" then
      if environment.fs.exists("/system/versions/" .. argument .. "/src/boot/init.lua") then
        environment.fs.write("/system/active.new", argument); environment.fs.rename("/system/active.new", "/system/active"); io.write("selected " .. argument .. "\n")
      else io.write("version not found\n") end
    elseif command == "reboot" then environment.computer.shutdown(true); return
    elseif command == "shutdown" or command == "exit" then environment.computer.shutdown(false); return
    else io.write("unknown command\n") end
  end
end

return SafeMode
