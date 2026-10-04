local perfs=dofile("/usr/lib/cclua/peripherals.lua")

local function usage()
  print("Usage:")
  print("  cclua-peripheralctl list")
  print("  cclua-peripheralctl printer [name] status|test")
  print("  cclua-peripheralctl speaker [name] status|note|sound|stop")
end

return {main=function(ctx,args)
  local kind=tostring(args[1] or "list"):lower()

  if kind=="list" then
    local found=0
    for _,ptype in ipairs({"printer","speaker","monitor","modem","drive","redstone_relay"}) do
      for _,d in ipairs(perfs.list(ptype)) do
        print(("%-10s %s"):format(ptype,d.name))
        found=found+1
      end
    end
    if found==0 then print("(no supported peripherals)") end
    return 0
  end

  if kind=="printer" then
    local name,action
    if args[3] then name=args[2];action=args[3]
    else name=nil;action=args[2] or "status" end
    action=tostring(action):lower()

    if action=="status" then
      local s,err=perfs.printer_status(name)
      if not s then print(err);return 1 end
      print(("Printer %s: ink=%s paper=%s ready=%s"):format(
        s.name,tostring(s.ink),tostring(s.paper),tostring(s.ready)))
      return 0
    elseif action=="test" then
      local r,err=perfs.print_text(name,"CCLUA Test",
        "CCLUA Ubuntu 22.04.5\nPrinter subsystem test\nStatus: OK",
        {single_page=true})
      if not r then print(err);return 1 end
      print(("Printed %d page(s) on %s"):format(r.pages,r.name))
      return 0
    end
    usage();return 1
  end

  if kind=="speaker" then
    local name,action
    if args[3] then name=args[2];action=args[3]
    else name=nil;action=args[2] or "status" end
    action=tostring(action):lower()

    if action=="status" then
      local s,err=perfs.speaker_status(name)
      if not s then print(err);return 1 end
      print(("Speaker %s: ready, %d Hz audio"):format(s.name,s.sample_rate))
      return 0
    elseif action=="note" then
      local r,err=perfs.play_note(name,"pling",1,12)
      if not r then print(err);return 1 end
      print("Note played on "..r.name);return 0
    elseif action=="sound" then
      local r,err=perfs.play_sound(name,"minecraft:block.note_block.pling",1,1)
      if not r then print(err);return 1 end
      print("Sound played on "..r.name);return 0
    elseif action=="stop" then
      local r,err=perfs.stop_audio(name)
      if not r then print(err);return 1 end
      print("Audio stopped on "..r.name);return 0
    end
    usage();return 1
  end

  usage()
  return 1
end}
