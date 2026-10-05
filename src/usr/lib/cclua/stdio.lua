local M={}

local function stream(ctx,fd,name)
  local p=ctx and ctx.process or {}
  if p.fd and p.fd[fd] then return p.fd[fd] end
  return p[name]
end

function M.stdin(ctx)
  return stream(ctx,0,"stdin")
end

function M.stdout(ctx)
  return stream(ctx,1,"stdout")
end

function M.stderr(ctx)
  return stream(ctx,2,"stderr")
end
function M.read_all(ctx)
  local s=M.stdin(ctx)
  if not s then return nil,"ENOSTDIN" end
  if s.readAll then return s:readAll() end
  return nil,"ENOTSUP"
end

function M.read_line(ctx)
  local s=M.stdin(ctx)
  if not s then return nil end
  if s.readLine then return s:readLine() end
  if s.readAll then
    s._cclua_buffer=s._cclua_buffer or s:readAll() or ""
    if s._cclua_buffer=="" then return nil end
    local p=s._cclua_buffer:find("\n",1,true)
    if not p then
      local v=s._cclua_buffer
      s._cclua_buffer=""
      return v
    end
    local v=s._cclua_buffer:sub(1,p-1)
    s._cclua_buffer=s._cclua_buffer:sub(p+1)
    return v
  end
end

function M.write(ctx,text)
  local s=M.stdout(ctx)
  if s and s.write then return s:write(tostring(text or "")) end
  write(tostring(text or ""))
  return true
end

function M.error(ctx,text)
  local s=M.stderr(ctx)
  if s and s.write then return s:write(tostring(text or "")) end
  local old=term.getTextColor and term.getTextColor() or colors.white
  if term.setTextColor then term.setTextColor(colors.red) end
  write(tostring(text or ""))
  if term.setTextColor then term.setTextColor(old) end
  return true
end

function M.println(ctx,text)
  return M.write(ctx,tostring(text or "").."\n")
end

function M.errorln(ctx,text)
  return M.error(ctx,tostring(text or "").."\n")
end

return M
