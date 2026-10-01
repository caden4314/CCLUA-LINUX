local M={}

function M.new(ctx)
  local self={ctx=ctx,devices={},generation=0,listeners={}}

  local function describe(name)
    if not peripheral or not peripheral.isPresent(name) then return nil end
    local types={peripheral.getType(name)}
    local methods=peripheral.getMethods(name) or {}
    table.sort(types);table.sort(methods)
    return {
      name=name,types=types,methods=methods,
      primaryType=types[1] or "unknown",
      attached=true,
    }
  end

  function self:scan()
    local nextDevices={}
    if peripheral and peripheral.getNames then
      for _,name in ipairs(peripheral.getNames()) do
        local d=describe(name)
        if d then nextDevices[name]=d end
      end
    end
    self.devices=nextDevices
    self.generation=self.generation+1
    return self.devices
  end

  function self:get(name) return self.devices[name] end
  function self:wrap(name)
    if not self.devices[name] then return nil end
    return peripheral.wrap(name)
  end

  function self:find(typeName)
    local out={}
    for _,dev in pairs(self.devices) do
      for _,t in ipairs(dev.types) do
        if t==typeName then out[#out+1]=dev;break end
      end
    end
    table.sort(out,function(a,b)return a.name<b.name end)
    return out
  end
  function self:wirelessModems()
    local out={}
    for _,dev in ipairs(self:find("modem")) do
      local m=peripheral.wrap(dev.name)
      local ok,w=pcall(m.isWireless)
      if ok and w then out[#out+1]={device=dev,handle=m} end
    end
    return out
  end

  function self:onChange(fn)
    self.listeners[#self.listeners+1]=fn
  end

  function self:event(event,name)
    if event~="peripheral" and event~="peripheral_detach" then return end
    local before=self.devices[name]
    self:scan()
    local after=self.devices[name]
    for _,fn in ipairs(self.listeners) do
      pcall(fn,event,name,before,after)
    end
  end

  function self:summary()
    local counts={}
    for _,d in pairs(self.devices) do
      for _,t in ipairs(d.types) do counts[t]=(counts[t] or 0)+1 end
    end
    return {generation=self.generation,count=(function()
      local n=0;for _ in pairs(self.devices) do n=n+1 end;return n
    end)(),types=counts}
  end

  self:scan()
  return self
end

return M
