return {main=function(ctx,args)
  local path="var/log/cclua/kernel.log"
  if not fs.exists(path) then
    print("dmesg: no persistent kernel log yet")
    return 0
  end

  local h=fs.open(path,"r")
  if not h then
    print("dmesg: cannot open /var/log/cclua/kernel.log")
    return 1
  end

  local lines={}
  while true do
    local line=h.readLine()
    if not line then break end
    lines[#lines+1]=line
  end
  h.close()

  local count=tonumber(args[1]) or #lines
  local first=math.max(1,#lines-count+1)
  for i=first,#lines do print(lines[i]) end
  return 0
end}
