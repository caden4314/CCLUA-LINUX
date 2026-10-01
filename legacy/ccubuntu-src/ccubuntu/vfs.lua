local M={}
local ROOT="/ccubuntu/root"
local cwd="/home/caden"

function M.norm(path)
 path=tostring(path or "")
 if path=="" then return cwd end
 if path=="~" then path="/home/caden"
 elseif path:sub(1,2)=="~/" then path="/home/caden"..path:sub(2) end
 if path:sub(1,1)~="/" then path=cwd.."/"..path end
 local parts={}
 for p in path:gmatch("[^/]+") do
  if p==".." then table.remove(parts)
  elseif p~="." and p~="" then parts[#parts+1]=p end
 end
 return "/"..table.concat(parts,"/")
end

function M.host(path)
 local p=M.norm(path)
 return p=="/" and ROOT or ROOT..p
end
function M.getcwd() return cwd end
function M.chdir(path)
 local p=M.norm(path)
 if not fs.exists(M.host(p)) or not fs.isDir(M.host(p)) then return nil,"No such file or directory" end
 cwd=p; return true
end
function M.exists(path) return fs.exists(M.host(path)) end
function M.isdir(path) return fs.isDir(M.host(path)) end
function M.list(path) return fs.list(M.host(path)) end

function M.mkdir(path,parents)
 local p=M.host(path)
 if fs.exists(p) then return true end
 if parents then fs.makeDir(p); return true end
 local par=fs.getDir(p)
 if par~="" and not fs.exists(par) then return nil,"No such file or directory" end
 fs.makeDir(p); return true
end
function M.read(path)
 local h=fs.open(M.host(path),"r"); if not h then return nil,"No such file or directory" end
 local s=h.readAll(); h.close(); return s
end
function M.write(path,data,append)
 local p=M.host(path); local d=fs.getDir(p)
 if d~="" and not fs.exists(d) then return nil,"No such file or directory" end
 local h=fs.open(p,append and "a" or "w"); if not h then return nil,"Permission denied" end
 h.write(data or ""); h.close(); return true
end
function M.remove(path,recursive)
 local p=M.host(path)
 if not fs.exists(p) then return nil,"No such file or directory" end
 if fs.isDir(p) and #fs.list(p)>0 and not recursive then return nil,"Directory not empty" end
 fs.delete(p); return true
end
function M.copy(a,b) fs.copy(M.host(a),M.host(b)); return true end
function M.move(a,b) fs.move(M.host(a),M.host(b)); return true end
function M.size(path) return fs.getSize(M.host(path)) end
function M.capacity() return fs.getCapacity(ROOT) or 0 end
function M.free() return fs.getFreeSpace(ROOT) or 0 end
return M
