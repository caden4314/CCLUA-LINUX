local M={}
local config=dofile("/usr/lib/cclua/config.lua")

function M.new(ctx)
  return {title="Settings",icon="*"}
end

function M.draw(ctx,st,ui,x,y,w,h)
  local m=config.machine()
  ui.fill(x,y,x+w-1,y+h-1,colors.black,colors.white)
  ui.text(x+2,y+1,"About",colors.orange,colors.black)

  local rows={
    {"OS","Ubuntu 22.04.5 LTS Desktop"},
    {"Device",m.hostname or "test-client"},
    {"Address",m.address or "unconfigured"},
    {"Computer ID",tostring(os.getComputerID())},
    {"Kernel",tostring(ctx.kernel.version.version)},
    {"ABI",tostring(ctx.kernel.version.kernel_abi)},
    {"Session","ubuntu / cclua"},
    {"Display","Advanced Computer terminal"},
    {"Processes",tostring(#ctx.kernel.process.all())},
  }
  local yy=y+3
  for _,r in ipairs(rows) do
    if yy>y+h-1 then break end
    ui.text(x+2,yy,r[1],colors.gray,colors.black)
    ui.text(x+15,yy,tostring(r[2]):sub(1,math.max(1,w-17)),colors.white,colors.black)
    yy=yy+1
  end
end

function M.event() return false end
return M
