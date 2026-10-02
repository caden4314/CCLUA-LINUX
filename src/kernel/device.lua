local M={devices={}}

local function describe(name)
  local types={peripheral.getType(name)}
  local methods={}
  if peripheral.getMethods then
    local ok,res=pcall(peripheral.getMethods,name)
    if ok and type(res)=="table" then
      methods=res
      table.sort(methods)
    end
  end
  return {
    name=name,
    types=types,
    methods=methods,
    present=true
  }
end

function M.scan(kernel)
  local previous=M.devices
  local current={}
  if peripheral then
    for _,name in ipairs(peripheral.getNames()) do
      current[name]=describe(name)
    end
  end

  if kernel and kernel.log then
    for name,dev in pairs(current) do
      if not previous[name] then
        kernel.log.write("info","device","peripheral attached: "..name,{types=dev.types})
      end
    end
    for name,dev in pairs(previous) do
      if not current[name] then
        kernel.log.write("warning","device","peripheral detached: "..name,{types=dev.types})
      end
    end
  end

  M.devices=current
  return current
end

function M.get(name) return M.devices[name] end

function M.snapshot(path)
  path=path or "/var/lib/cclua/peripherals.json"
  local payload={schema=1,computer_id=os.getComputerID and os.getComputerID() or nil,devices={}}
  for _,dev in pairs(M.devices) do
    payload.devices[#payload.devices+1]=dev
  end
  table.sort(payload.devices,function(a,b)return a.name<b.name end)

  if fs and textutils and textutils.serializeJSON then
    pcall(function()
      if not fs.exists("var") then fs.makeDir("var") end
      if not fs.exists("var/lib") then fs.makeDir("var/lib") end
      if not fs.exists("var/lib/cclua") then fs.makeDir("var/lib/cclua") end
      local h=fs.open(path:gsub("^/",""),"w")
      if h then h.write(textutils.serializeJSON(payload));h.close() end
    end)
  end
  return payload
end

return M
