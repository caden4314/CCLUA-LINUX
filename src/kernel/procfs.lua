local M={}
function M.new(k)
 local p={}
 function p.exists(path)
  if path=="/" or path=="/uptime" or path=="/version" or path=="/meminfo" or path=="/cpuinfo" then return true end
  local pid=path:match("^/(%d+)");return pid and k.process.get(tonumber(pid))~=nil or false
 end
 function p.isDir(path)return path=="/" or path:match("^/%d+$")~=nil end
 function p.list(path)
  if path=="/" then local o={"uptime","version","meminfo","cpuinfo"};for _,x in ipairs(k.process.all())do o[#o+1]=tostring(x.pid)end;return o end
  if path:match("^/%d+$")then return {"status","cmdline","fd"}end
  return {}
 end
 local function content(path)
  if path=="/version" then return k.version.name.." "..k.version.version.."\n" end
  if path=="/uptime" then return string.format("%.2f\n",(os.clock and os.clock() or 0))end
  if path=="/meminfo" then return "MemTotal: CC-Tweaked\nMemFree: dynamic\n" end
  if path=="/cpuinfo" then return "processor\t: 0\nmodel name\t: CC:Tweaked Lua runtime\n" end
  local pid,file=path:match("^/(%d+)/(.+)$")
  local pr=pid and k.process.get(tonumber(pid))
  if pr and file=="status" then return ("Name:\t%s\nPid:\t%d\nPPid:\t%d\nState:\t%s\nUid:\t%d\nGid:\t%d\n"):format(pr.name,pr.pid,pr.ppid,pr.state,pr.uid,pr.gid)
  elseif pr and file=="cmdline" then return table.concat(pr.argv or {},"\0") end
 end
 function p.open(path,mode)
  if mode and mode:find("w")then return nil,"EROFS" end
  local data=content(path);if data==nil then return nil,"ENOENT" end
  local pos=1
  return {readAll=function()local s=data:sub(pos);pos=#data+1;return s end,close=function()end}
 end
 return p
end
return M
