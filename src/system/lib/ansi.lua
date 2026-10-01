local M={}
local HEX={
 [colors.white]="0",[colors.orange]="1",[colors.magenta]="2",[colors.lightBlue]="3",
 [colors.yellow]="4",[colors.lime]="5",[colors.pink]="6",[colors.gray]="7",
 [colors.lightGray]="8",[colors.cyan]="9",[colors.purple]="a",[colors.blue]="b",
 [colors.brown]="c",[colors.green]="d",[colors.red]="e",[colors.black]="f",
}
local NORMAL={
 [30]=colors.black,[31]=colors.red,[32]=colors.green,[33]=colors.brown,
 [34]=colors.blue,[35]=colors.purple,[36]=colors.cyan,[37]=colors.lightGray,
}
local BRIGHT={
 [90]=colors.gray,[91]=colors.red,[92]=colors.lime,[93]=colors.yellow,
 [94]=colors.lightBlue,[95]=colors.magenta,[96]=colors.cyan,[97]=colors.white,
}
local BG={
 [40]=colors.black,[41]=colors.red,[42]=colors.green,[43]=colors.brown,
 [44]=colors.blue,[45]=colors.purple,[46]=colors.cyan,[47]=colors.lightGray,
 [100]=colors.gray,[101]=colors.red,[102]=colors.lime,[103]=colors.yellow,
 [104]=colors.lightBlue,[105]=colors.magenta,[106]=colors.cyan,[107]=colors.white,
}

function M.parse(input,defaultFg,defaultBg)
  input=tostring(input or "")
  local fg=defaultFg or colors.white
  local bg=defaultBg or colors.black
  local bold=false
  local lines={{text="",fg="",bg=""}}
  local function put(ch)
    if ch=="\n" then lines[#lines+1]={text="",fg="",bg=""};return end
    local line=lines[#lines]
    line.text=line.text..ch
    line.fg=line.fg..(HEX[fg] or "0")
    line.bg=line.bg..(HEX[bg] or "f")
  end
  local i=1
  while i<=#input do
    if input:sub(i,i)=="\27" and input:sub(i+1,i+1)=="[" then
      local j=input:find("m",i+2,true)
      if j then
        local params=input:sub(i+2,j-1)
        if params=="" then params="0" end
        for n in params:gmatch("[^;]+") do
          local code=tonumber(n) or 0
          if code==0 then
            fg=defaultFg or colors.white;bg=defaultBg or colors.black;bold=false
          elseif code==1 then bold=true
          elseif code==22 then bold=false
          elseif code==39 then fg=defaultFg or colors.white
          elseif code==49 then bg=defaultBg or colors.black
          elseif NORMAL[code] then
            fg=NORMAL[code]
            if bold then
              local map={
                [colors.black]=colors.gray,[colors.red]=colors.red,[colors.green]=colors.lime,
                [colors.brown]=colors.yellow,[colors.blue]=colors.lightBlue,[colors.purple]=colors.magenta,
                [colors.cyan]=colors.cyan,[colors.lightGray]=colors.white,
              }
              fg=map[fg] or fg
            end
          elseif BRIGHT[code] then fg=BRIGHT[code]
          elseif BG[code] then bg=BG[code] end
        end
        i=j+1
      else
        put(input:sub(i,i));i=i+1
      end
    else
      put(input:sub(i,i));i=i+1
    end
  end
  return lines
end

function M.strip(input)
  return tostring(input or ""):gsub("\27%[[0-9;]*m","")
end

function M.blitColour(colour) return HEX[colour] or "0" end
return M
