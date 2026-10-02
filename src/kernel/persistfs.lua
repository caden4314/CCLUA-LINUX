local M={}
function M.new(root)
 root=root or ""
 local p={}
 local function host(path)
  path=tostring(path or "/"):gsub("^/","")
  if root=="" or root=="/" then return path=="" and "/" or path end
  return fs.combine(root,path)
 end
 function p.exists(path)return fs.exists(host(path))end
 function p.isDir(path)return fs.isDir(host(path))end
 function p.list(path)return fs.list(host(path))end
 function p.open(path,mode)return fs.open(host(path),mode or "r")end
 function p.delete(path)fs.delete(host(path));return true end
 function p.mkdir(path)fs.makeDir(host(path));return true end
 function p.move(a,b)fs.move(host(a),host(b));return true end
 function p.copy(a,b)fs.copy(host(a),host(b));return true end
 function p.stat(path)
  local h=host(path)
  if not fs.exists(h) then return nil,"ENOENT" end
  return {path=path,isDir=fs.isDir(h),size=(fs.isDir(h) and 0 or fs.getSize(h)),readOnly=fs.isReadOnly(h)}
 end
 return p
end
return M
