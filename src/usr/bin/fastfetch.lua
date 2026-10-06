local api=dofile("/usr/lib/cclua/api/system.lua")

local function value(v)
  if v==nil or v=="" then return "-" end
  return tostring(v)
end

return {main=function(ctx,args)
  local s=api.snapshot(ctx)
  local plain=false
  for _,a in ipairs(args or {}) do if a=="--plain" or a=="--no-color" then plain=true end end

  local accent=colors.orange
  local muted=colors.gray
  local normal=colors.white
  local function set(c) if not plain and term and term.setTextColor then term.setTextColor(c) end end
  local function row(label,v)
    set(accent);write((label..":"):format())
    set(normal);print(" "..value(v))
  end

  set(accent);print("      ____  ____  _    _   _    ")
  print("     / ___|/ ___|| |  | | / \\   ")
  print("    | |   | |    | |  | |/ _ \\  ")
  print("    | |___| |___ | |__| / ___ \\ ")
  print("     \\____|\\____| \\____/_/   \\_\\")
  set(muted);print("       Ubuntu 22.04.5 / CCLUA")
  set(normal);print("")  row("Host",s.host.user.."@"..s.host.hostname.." (ID "..s.host.computer_id..")")
  row("Role",s.host.role)
  row("Kernel",value(s.system.kernel).." ABI "..value(s.system.kernel_abi))
  row("Uptime",s.system.uptime_seconds.."s")
  row("State",s.system.state.." / POST "..s.post.state)
  row("Services",("%d/%d active, %d failed"):format(
    s.system.services.active,s.system.services.total,s.system.services.failed))
  row("Processes",s.system.process_count)
  row("Peripherals",s.system.peripheral_count)
  row("Network",s.network.state.." "..value(s.network.address))
  row("Manager",value(s.network.manager).." RTT "..value(s.network.manager_rtt_ms).."ms")
  row("Update",s.update.state.." "..s.update.percent.."%")
  row("Image",value(s.update.current_commit):sub(1,16))
  local nativeCaps=s.native and s.native.capabilities or {}
  local nativeMode=s.native and s.native.available
    and ("CCPerf "..value(s.native.version).." / API "..value(nativeCaps.api))
    or "stock CC:Tweaked"
  row("Native",nativeMode)
  if s.native and s.native.available then
    row("Timing",(nativeCaps.native_timer and "native" or "stock")..
      " / clock "..(nativeCaps.native_clock and "us" or "ms"))
  end

  if not plain and term and term.setTextColor then term.setTextColor(colors.white) end
  return s.system.error_code>0 and 1 or 0
end}
