local M={}

function M.new(ctx)
  local self={ctx=ctx,page="System"}

  function self.draw(win)
    local s=win.surface
    s:clear(colors.black,colors.white)
    s:fill(1,1,s.width,2," ",colors.white,colors.gray)
    s:write(2,1,"Settings",colors.white,colors.gray)
    s:write(2,2,"System",colors.cyan,colors.gray)

    s:write(2,4,ctx.config.name.." "..ctx.config.version,colors.cyan,colors.black)
    s:write(2,5,ctx.config.codename.." / "..ctx.config.build,colors.lightGray,colors.black)
    s:write(2,7,"Kernel",colors.lightGray,colors.black)
    s:write(14,7,ctx.config.kernel:sub(1,math.max(1,s.width-14)),colors.white,colors.black)
    s:write(2,8,"Architecture",colors.lightGray,colors.black)
    s:write(14,8,ctx.config.architecture,colors.white,colors.black)
    s:write(2,10,"User",colors.lightGray,colors.black)
    s:write(14,10,ctx.config.user.displayName.." ("..ctx.config.user.name..")",colors.white,colors.black)
    s:write(2,12,"System image",colors.lightGray,colors.black)
    s:write(14,12,tostring(ctx.iso.meta.version or "?"),colors.white,colors.black)
    s:write(2,13,"Image files",colors.lightGray,colors.black)
    s:write(14,13,tostring(ctx.iso.meta.files or "?"),colors.white,colors.black)

    if s.height>=16 then
      s:write(2,15,"Display backend",colors.lightGray,colors.black)
      s:write(18,15,ctx.display.kind,colors.white,colors.black)
    end
  end

  function self.event() end
  return self
end

return M
