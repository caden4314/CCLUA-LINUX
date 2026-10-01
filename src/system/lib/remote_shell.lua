local M={}

local function words(line)
  local out={}
  for w in tostring(line or ""):gmatch("%S+") do out[#out+1]=w end
  return out
end

function M.new(ctx,user)
  local self={
    ctx=ctx,
    user=user or ctx.config.user.name,
    cwd=ctx.config.user.home,
    closed=false,
  }

  local function absolute(path)
    path=path or self.cwd
    if path=="~" then return ctx.config.user.home end
    if path:sub(1,2)=="~/" then return ctx.config.user.home..path:sub(2) end
    if path:sub(1,1)=="/" then return ctx.vfs.normalize(path) end
    return ctx.vfs.normalize(self.cwd.."/"..path)
  end

  local function ok(text) return tostring(text or "").."\n",0 end
  local function err(text,code) return "\27[91m"..tostring(text).."\27[0m\n",code or 1 end

  function self:prompt()
    local shown=self.cwd==ctx.config.user.home and "~" or self.cwd
    return "\27[92m"..self.user.."@cclua\27[0m:\27[94m"..shown.."\27[0m$ "
  end

  function self:exec(line)
    local a=words(line)
    if #a==0 then return "",0 end
    local c=a[1]

    if c=="exit" or c=="logout" then
      self.closed=true
      return "logout\n",0
    elseif c=="whoami" then return ok(self.user)
    elseif c=="pwd" then return ok(self.cwd)
    elseif c=="uname" then
      if a[2]=="-a" then
        return ok("CCLUA-LINUX "..ctx.config.kernel.." "..ctx.config.architecture.." Lua/Cobalt")
      end
      return ok("CCLUA-LINUX")
    elseif c=="version" then
      return ok(ctx.config.name.." "..ctx.config.version.." ("..ctx.config.codename..")")
    elseif c=="echo" then return ok(table.concat(a," ",2))
    elseif c=="cd" then
      local target=absolute(a[2] or "~")
      if not ctx.vfs.exists(target) or not ctx.vfs.isDir(target) then
        return err("cd: no such directory: "..target)
      end
      self.cwd=target;return "",0
    elseif c=="ls" then
      local target=absolute(a[2] or self.cwd)
      local list,e=ctx.vfs.list(target)
      if not list then return err("ls: "..tostring(e)) end
      table.sort(list);return ok(table.concat(list,"  "))
    elseif c=="cat" then
      if not a[2] then return err("cat: missing operand") end
      local data,e=ctx.vfs.read(absolute(a[2]))
      if not data then return err("cat: "..tostring(e)) end
      return data..(data:sub(-1)=="\n" and "" or "\n"),0
    elseif c=="services" then
      local snap=ctx.services:snapshot()
      local names={};for name in pairs(snap) do names[#names+1]=name end;table.sort(names)
      local out={}
      for _,name in ipairs(names) do
        local s=snap[name]
        local col=s.state=="running" and "\27[92m" or s.state=="failed" and "\27[91m" or "\27[93m"
        out[#out+1]=col..string.format("%-16s %-10s",name,s.state).."\27[0m"
      end
      return table.concat(out,"\n").."\n",0
    end

    local pkg=ctx.packages and ctx.packages:findCommand(c)
    if pkg then
      local chunks={}
      local success,result=ctx.packages:runCommand(c,a,{
        write=function(s) chunks[#chunks+1]=tostring(s) end,
        cwd=function() return self.cwd end,
      })
      if not success then return err(c..": "..tostring(result)) end
      return table.concat(chunks),0
    end

    if c=="help" then
      return ok("whoami pwd uname version echo cd ls cat services help exit")
    end
    return err(c..": command not found",127)
  end

  return self
end

return M
