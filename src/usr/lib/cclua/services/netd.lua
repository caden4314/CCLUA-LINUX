return function(ctx)
 local opened={}
 if peripheral and rednet then
  for _,name in ipairs(peripheral.getNames()) do
   if peripheral.hasType(name,"modem") then
    local ok=pcall(rednet.open,name)
    if ok then opened[#opened+1]=name end
   end
  end
 end
 ctx.unit.details={modems=opened}
 while true do
  coroutine.yield("wait_event")
 end
end
