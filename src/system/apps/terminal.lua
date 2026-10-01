local M = {}
local ANSI = ISO.require("system/lib/ansi.lua")

local function splitWords(line)
  local out = {}
  for word in tostring(line):gmatch("%S+") do out[#out+1] = word end
  return out
end

function M.new(ctx)
  local self = {
    ctx = ctx,
    lines = {},
    input = "",
    history = {},
    historyPos = 0,
    cwd = ctx.config.user.home,
  }

  local function push(text, colour)
    text = tostring(text or "")
    if text == "" then self.lines[#self.lines+1] = {text="", colour=colour}; return end
    for line in (text .. "\n"):gmatch("(.-)\n") do
      self.lines[#self.lines+1] = {text=line, colour=colour or colors.lightGray}
    end
  end

  local function pushAnsi(text)
    for _,line in ipairs(ANSI.parse(text,colors.lightGray,colors.black)) do
      self.lines[#self.lines+1]={text=line.text,fg=line.fg,bg=line.bg}
    end
  end

  local function prompt()
    local home = ctx.config.user.home
    local shown = self.cwd == home and "~" or self.cwd
    return ctx.config.user.name .. "@cclua:" .. shown .. "$ "
  end

  local function absolute(path)
    path = path or self.cwd
    if path == "~" then return ctx.config.user.home end
    if path:sub(1,2) == "~/" then return ctx.config.user.home .. path:sub(2) end
    if path:sub(1,1) == "/" then return ctx.vfs.normalize(path) end
    return ctx.vfs.normalize(self.cwd .. "/" .. path)
  end
  local commands = {}

  commands.help = function()
    push("CCLUA-LINUX shell commands:", colors.cyan)
    push("help clear uname whoami pwd cd ls cat echo mkdir touch rm apps version neofetch")
    push("services netstat net-role peripherals pkg ansi")
    push("Installed .luapkg commands are resolved automatically.", colors.lightGray)
  end

  commands.clear = function()
    self.lines = {}
  end

  commands.uname = function(args)
    if args[2] == "-a" then
      push("CCLUA-LINUX " .. ctx.config.kernel .. " " .. ctx.config.architecture .. " Lua/Cobalt")
    else
      push("CCLUA-LINUX")
    end
  end

  commands.whoami = function() push(ctx.config.user.name) end
  commands.pwd = function() push(self.cwd) end

  commands.cd = function(args)
    local target = absolute(args[2] or "~")
    if not ctx.vfs.exists(target) or not ctx.vfs.isDir(target) then
      push("cd: no such directory: " .. target, colors.red)
      return
    end
    self.cwd = target
  end

  commands.ls = function(args)
    local target = absolute(args[2] or self.cwd)
    local list, err = ctx.vfs.list(target)
    if not list then push("ls: " .. tostring(err), colors.red); return end
    table.sort(list)
    push(table.concat(list, "  "), colors.white)
  end
  commands.cat = function(args)
    if not args[2] then push("cat: missing operand", colors.red); return end
    local data, err = ctx.vfs.read(absolute(args[2]))
    if not data then push("cat: " .. tostring(err), colors.red) else push(data, colors.white) end
  end

  commands.echo = function(args)
    push(table.concat(args, " ", 2), colors.white)
  end

  commands.mkdir = function(args)
    if not args[2] then push("mkdir: missing operand", colors.red); return end
    local ok, err = ctx.vfs.mkdir(absolute(args[2]))
    if not ok then push("mkdir: " .. tostring(err), colors.red) end
  end

  commands.touch = function(args)
    if not args[2] then push("touch: missing operand", colors.red); return end
    local path = absolute(args[2])
    if not ctx.vfs.exists(path) then
      local ok, err = ctx.vfs.write(path, "", false)
      if not ok then push("touch: " .. tostring(err), colors.red) end
    end
  end

  commands.rm = function(args)
    if not args[2] then push("rm: missing operand", colors.red); return end
    local ok, err = ctx.vfs.delete(absolute(args[2]))
    if not ok then push("rm: " .. tostring(err), colors.red) end
  end

  commands.apps = function()
    local names = {}
    for name in pairs(ctx.apps or {}) do names[#names+1] = name end
    table.sort(names)
    push("Installed applications: " .. table.concat(names, ", "), colors.cyan)
  end

  commands.version = function()
    push(ctx.config.name .. " " .. ctx.config.version .. " (" .. ctx.config.codename .. ")")
    push(ctx.config.kernel .. " / ABI " .. tostring(ctx.iso.meta.abi or "unknown"), colors.lightGray)
  end
  commands.neofetch = function()
    push("   CCLUA-LINUX", colors.cyan)
    push("   ==========", colors.cyan)
    push("OS: " .. ctx.config.name .. " " .. ctx.config.version)
    push("Kernel: " .. ctx.config.kernel)
    push("Arch: " .. ctx.config.architecture)
    push("Host: Computer #" .. tostring(os.getComputerID()))
    push("Shell: cclsh 0.2")
    push("Display: " .. tostring(ctx.compositor.width) .. "x" .. tostring(ctx.compositor.height) .. " cells")
    push("ISO: " .. tostring(ctx.iso.meta.version or "?") .. " / " .. tostring(ctx.iso.meta.files or "?") .. " files")
  end

  commands.services=function()
    local snap=ctx.services and ctx.services:snapshot() or {}
    local names={};for name in pairs(snap) do names[#names+1]=name end;table.sort(names)
    for _,name in ipairs(names) do
      local s=snap[name]
      local c=s.state=="running" and colors.lime or s.state=="failed" and colors.red or colors.yellow
      push(string.format("%-16s %-10s restarts=%d",name,s.state,s.restarts or 0),c)
    end
  end

  commands.netstat=function()
    local n=ctx.services and ctx.services:get("netd")
    if n then
      local s=n.status and n.status() or {state="offline"}
      push("CCLUA NET client: "..tostring(s.state),s.state=="online" and colors.lime or colors.yellow)
      push(" address: "..tostring(s.address or "-").."  server: "..tostring(s.server or "-"))
      push(" modem: "..tostring(s.modem or "-").."  pending: "..tostring(s.pending or 0))
      return
    end
    local server=ctx.services and ctx.services:get("ccluanet-server")
    if server then
      local s=server.status()
      push("CCLUA NET central server",colors.lime)
      push(" id: "..tostring(s.serverId).." clients: "..tostring(s.clients).." packets: "..tostring(s.packets))
      push(" modem: "..tostring(s.modem or "-").." dropped: "..tostring(s.dropped))
      return
    end
    push("CCLUA NET: unavailable",colors.red)
  end

  commands["net-role"]=function(args)
    local role=args[2]
    if role~="client" and role~="server" then
      push("Current role: "..tostring(ctx.networkRole or "client"),colors.cyan)
      push("Usage: net-role client|server  (reboots)",colors.lightGray)
      return
    end
    local path="/.cclua/data/system/ccluanet.role"
    local dir=fs.getDir(path);if not fs.exists(dir) then fs.makeDir(dir) end
    local h=assert(fs.open(path,"w"));h.write(role);h.close()
    push("Network role set to "..role..". Rebooting...",colors.yellow)
    os.startTimer(0.5)
    os.queueEvent("cclua_role_reboot")
  end

  commands.peripherals=function()
    local s=ctx.peripherals:summary()
    push("Peripheral bus generation "..tostring(s.generation)..": "..tostring(s.count).." device(s)",colors.cyan)
    local names={};for n in pairs(s.types or {}) do names[#names+1]=n end;table.sort(names)
    for _,n in ipairs(names) do push(" "..n..": "..tostring(s.types[n])) end
  end

  commands.pkg=function(args)
    local op=args[2] or "list"
    if op=="list" then
      local list=ctx.packages:list()
      if #list==0 then push("No user packages installed.",colors.lightGray) end
      for _,p in ipairs(list) do push(p.name.." "..p.version.." ["..tostring(p.source).."]",colors.cyan) end
    elseif op=="remove" and args[3] then
      local ok,err=ctx.packages:remove(args[3]);if not ok then push("pkg: "..tostring(err),colors.red) else push("Removed "..args[3],colors.lime) end
    elseif op=="remote" then
      local svc=ctx.services:get("pkgd")
      if not svc then push("pkg: repository service unavailable",colors.red);return end
      local ok,err=svc:refresh()
      if not ok then push("pkg: "..tostring(err),colors.red) else push("Refreshing CCLUA NET package index...",colors.cyan) end
    elseif op=="install" and args[3] then
      local path=absolute(args[3])
      if ctx.vfs.exists(path) then
        local raw,err=ctx.vfs.read(path)
        if not raw then push("pkg: "..tostring(err),colors.red);return end
        local rec,e=ctx.packages:installRaw(raw,"local")
        if not rec then push("pkg: "..tostring(e),colors.red) else push("Installed "..rec.name.." "..rec.version,colors.lime) end
      else
        local svc=ctx.services:get("pkgd")
        if not svc then push("pkg: repository service unavailable",colors.red);return end
        local ok,err=svc:install(args[3])
        if not ok then push("pkg: "..tostring(err),colors.red) else push("Downloading "..args[3].." from CCLUA NET...",colors.cyan) end
      end
    else
      push("Usage: pkg list | pkg remote | pkg install <name|file.luapkg> | pkg remove <name>",colors.yellow)
    end
  end

  commands.ansi=function()
    pushAnsi("\27[96mcyan \27[92mgreen \27[93myellow \27[91mred \27[0mnormal")
  end

  local function execute(line)
    if self.remoteSession then
      local shown=self.remotePrompt or "[ssh]$ "
      push(shown..line,colors.white)
      if line=="~." then
        local svc=ctx.services:get("sshclientd")
        if svc then svc:close(self.remoteSession) end
        self.remoteSession=nil;self.remotePrompt=nil
        return
      end
      local svc=ctx.services:get("sshclientd")
      if not svc then
        push("ssh: client service unavailable",colors.red)
        self.remoteSession=nil;return
      end
      local ok,err=svc:exec(self.remoteSession,line)
      if not ok then push("ssh: "..tostring(err),colors.red) end
      return
    end

    push(prompt() .. line, colors.white)
    local args = splitWords(line)
    if #args == 0 then return end
    self.history[#self.history+1] = line
    self.historyPos = #self.history + 1
    local fn = commands[args[1]]
    if fn then
      local ok, err = pcall(fn, args)
      if not ok then push("shell: " .. tostring(err), colors.red) end
    elseif ctx.packages and ctx.packages:findCommand(args[1]) then
      local ok,result=ctx.packages:runCommand(args[1],args,{
        write=function(s) pushAnsi(tostring(s)) end,
        cwd=function() return self.cwd end,
      })
      if not ok then
        push(args[1]..": "..tostring(result),colors.red)
      elseif type(result)=="table" and result.remoteSession then
        self.remoteSession=result.remoteSession
      end
    else
      push(args[1] .. ": command not found", colors.red)
    end
  end

  function self.draw(win)
    local s = win.surface
    s:clear(colors.black, colors.white)
    local visible = math.max(1, s.height - 2)
    local first = math.max(1, #self.lines - visible + 1)
    local y = 1
    for i = first, #self.lines do
      local line = self.lines[i]
      local text=line.text:sub(1,s.width)
      if line.fg and line.bg then
        s:blit(1,y,text,line.fg:sub(1,#text),line.bg:sub(1,#text))
      else
        s:write(1,y,text,line.colour or colors.lightGray,colors.black)
      end
      y = y + 1
      if y > visible then break end
    end
    local p = self.remoteSession and (self.remotePrompt or "[ssh]$ ") or prompt()
    s:write(1, s.height, (p .. self.input):sub(1, s.width), colors.white, colors.black)
    local cursor = math.min(s.width, #p + #self.input + 1)
    if cursor >= 1 then s:write(cursor, s.height, "_", colors.cyan, colors.black) end
  end
  function self.event(event, a, b, c, d)
    if event=="cclua_pkg_event" then
      if a=="list" and type(b)=="table" then
        push("CCLUA NET packages: "..(#b>0 and table.concat(b,", ") or "(none)"),colors.cyan)
      elseif a=="installed" then
        push("Installed "..tostring(b).." "..tostring(c),colors.lime)
      elseif a=="error" then
        push("pkg: "..tostring(b),colors.red)
      end
    elseif event=="cclua_ssh_output" then
      local session,text,state,remotePrompt=a,b,c,d
      if session==self.remoteSession then
        if text and text~="" then pushAnsi(text) end
        if remotePrompt then self.remotePrompt=ANSI.strip(remotePrompt) end
        if state=="closed" then
          self.remoteSession=nil;self.remotePrompt=nil
        end
      end
    elseif event == "char" then
      self.input = self.input .. tostring(a)
    elseif event == "paste" then
      self.input = self.input .. tostring(a or "")
    elseif event == "key" then
      if a == keys.enter then
        local line = self.input
        self.input = ""
        execute(line)
      elseif a == keys.backspace then
        self.input = self.input:sub(1, -2)
      elseif a == keys.up then
        if #self.history > 0 then
          self.historyPos = math.max(1, self.historyPos - 1)
          self.input = self.history[self.historyPos] or ""
        end
      elseif a == keys.down then
        if #self.history > 0 then
          self.historyPos = math.min(#self.history + 1, self.historyPos + 1)
          self.input = self.history[self.historyPos] or ""
        end
      end
    end
    local win = ctx.compositor:getWindow(ctx.compositor.focused)
    if win and win.app == self then self.draw(win) end
  end

  push("CCLUA-LINUX terminal ready. Type 'help' for commands.", colors.cyan)
  return self
end

return M
