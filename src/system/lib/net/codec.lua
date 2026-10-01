local M={}

local function isArray(t)
  local n=0
  for k in pairs(t) do
    if type(k)~="number" or k<1 or k%1~=0 then return false end
    if k>n then n=k end
  end
  for i=1,n do if t[i]==nil then return false end end
  return true,n
end

local function encode(v)
  local tv=type(v)
  if tv=="nil" then return "n"
  elseif tv=="boolean" then return v and "b1" or "b0"
  elseif tv=="number" then return "d"..string.format("%.17g",v)..";"
  elseif tv=="string" then return "s"..#v..":"..v
  elseif tv=="table" then
    local arr,n=isArray(v)
    local out={}
    if arr then
      out[#out+1]="a"..n.."{"
      for i=1,n do out[#out+1]=encode(v[i]) end
    else
      local keys={}
      for k in pairs(v) do keys[#keys+1]=k end
      table.sort(keys,function(a,b)return tostring(a)<tostring(b) end)
      out[#out+1]="m"..#keys.."{"
      for _,k in ipairs(keys) do out[#out+1]=encode(k);out[#out+1]=encode(v[k]) end
    end
    out[#out+1]="}"
    return table.concat(out)
  end
  error("unsupported canonical type: "..tv,2)
end

M.canonical=encode
return M
