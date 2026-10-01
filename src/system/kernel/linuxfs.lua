local M={}

local STATIC_DIRS={
  ["/bin"]=true,["/boot"]=true,["/dev"]=true,["/etc"]=true,
  ["/mnt"]=true,["/opt"]=true,["/proc"]=true,["/run"]=true,["/srv"]=true,
  ["/usr"]=true,["/usr/bin"]=true,["/usr/lib"]=true,["/usr/share"]=true,
  ["/var"]=true,["/var/log"]=true,["/var/tmp"]=true,
}

function M.new(config)
  local self={config=config,commandProvider=nil,bootClock=os.clock()}

  function self:setCommandProvider(fn)
    self.commandProvider=fn
  end

  local function commands()
    if type(self.commandProvider)~="function" then return {} end
    local ok,value=pcall(self.commandProvider)
    if not ok or type(value)~="table" then return {} end
    table.sort(value)
    return value
  end

  local function osRelease()
    return table.concat({
      'NAME="'..config.name..'"',
      'PRETTY_NAME="'..config.name.." "..config.version..' ('..config.codename..')"',
      'ID=cclua-linux',
      'VERSION_ID="'..config.version..'"',
      'VERSION_CODENAME='..string.lower(config.codename),
      'BUILD_ID='..config.build,
      'ARCH='..config.architecture,
      'HOME_URL="https://github.com/caden4314/CCLUA-LINUX"',
      "",
    },"\n")
  end

  local function generated(path)
    if path=="/etc/os-release" then return osRelease() end
    if path=="/etc/hostname" then
      return ((os.getComputerLabel and os.getComputerLabel()) or config.name):gsub("%s+","-"):lower().."\n"
    end
    if path=="/proc/version" then
      return config.kernel.." "..config.version.." "..config.architecture.."\n"
    end
    if path=="/proc/uptime" then
      return string.format("%.2f %.2f\n",math.max(0,os.clock()-self.bootClock),0)
    end
    if path=="/proc/cpuinfo" then
      return table.concat({
        "processor\t: 0",
        "model name\t: CC:Tweaked Lua Computer",
        "architecture\t: "..config.architecture,
        "runtime\t\t: Lua "..tostring(_VERSION or "unknown"),
        "",
      },"\n")
    end
    local cmd=path:match("^/bin/([^/]+)$") or path:match("^/usr/bin/([^/]+)$")
    if cmd then
      for _,name in ipairs(commands()) do
        if name==cmd then return "#!cclua\n# virtual command endpoint: "..name.."\n" end
      end
    end
    return nil
  end

  function self:exists(path)
    if STATIC_DIRS[path] then return true end
    return generated(path)~=nil
  end

  function self:isDir(path)
    return STATIC_DIRS[path]==true
  end

  function self:list(path)
    if path=="/" then
      return {"bin","boot","dev","etc","mnt","opt","proc","run","srv","usr","var"}
    elseif path=="/etc" then
      return {"hostname","os-release"}
    elseif path=="/proc" then
      return {"cpuinfo","uptime","version"}
    elseif path=="/usr" then
      return {"bin","lib","share"}
    elseif path=="/var" then
      return {"log","tmp"}
    elseif path=="/bin" or path=="/usr/bin" then
      return commands()
    elseif STATIC_DIRS[path] then
      return {}
    end
    return nil,"not a directory"
  end

  function self:read(path)
    local data=generated(path)
    if data==nil then return nil,"not a file" end
    return data
  end

  return self
end

return M
