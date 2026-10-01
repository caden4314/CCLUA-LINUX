local M={}

local PRESETS={
  glassforge={
    name="Glassforge",accent=colors.cyan,accentDim=colors.blue,
    background=colors.black,panel=colors.gray,panelAlt=colors.lightGray,
    text=colors.white,muted=colors.lightGray,danger=colors.red,
    success=colors.lime,selection=colors.blue,
  },
  midnight={
    name="Midnight",accent=colors.lightBlue,accentDim=colors.blue,
    background=colors.black,panel=colors.blue,panelAlt=colors.gray,
    text=colors.white,muted=colors.lightGray,danger=colors.red,
    success=colors.lime,selection=colors.purple,
  },
  ember={
    name="Ember",accent=colors.orange,accentDim=colors.brown,
    background=colors.black,panel=colors.gray,panelAlt=colors.brown,
    text=colors.white,muted=colors.lightGray,danger=colors.red,
    success=colors.lime,selection=colors.brown,
  },
}
local ORDER={"glassforge","midnight","ember"}
local PATH="/AppData/settings/theme"

local function copy(t)
  local out={}
  for k,v in pairs(t or {}) do out[k]=v end
  return out
end

function M.new(vfs,base)
  local self={vfs=vfs,current="glassforge",generation=0}
  local function readSaved()
    if not vfs or not vfs.exists(PATH) then return nil end
    local raw=vfs.read(PATH)
    if type(raw)~="string" then return nil end
    raw=raw:gsub("%s+","")
    return PRESETS[raw] and raw or nil
  end

  function self:palette()
    local p=copy(PRESETS[self.current] or PRESETS.glassforge)
    if type(base)=="table" then
      for k,v in pairs(base) do if p[k]==nil then p[k]=v end end
    end
    p.id=self.current
    return p
  end

  function self:set(name,persist)
    name=tostring(name or ""):lower()
    if not PRESETS[name] then return nil,"unknown theme" end
    if self.current==name then return true end
    self.current=name
    self.generation=self.generation+1
    if persist~=false and vfs then
      vfs.mkdir("/AppData/settings")
      local ok,err=vfs.write(PATH,name,false)
      if not ok then return nil,err end
    end
    os.queueEvent("cclua_theme_changed",name,self.generation)
    return true
  end
  function self:cycle()
    local idx=1
    for i,name in ipairs(ORDER) do if name==self.current then idx=i;break end end
    return self:set(ORDER[(idx % #ORDER)+1],true)
  end

  function self:list()
    local out={}
    for _,id in ipairs(ORDER) do
      local p=PRESETS[id]
      out[#out+1]={id=id,name=p.name,accent=p.accent}
    end
    return out
  end

  function self:status()
    return {id=self.current,name=(PRESETS[self.current] or PRESETS.glassforge).name,generation=self.generation}
  end

  local saved=readSaved()
  if saved then self.current=saved end
  return self
end

M.PRESETS=PRESETS
return M
