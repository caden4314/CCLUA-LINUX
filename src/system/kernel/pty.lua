local M={}

function M.new(opts)
  opts=opts or {}
  local self={
    cols=tonumber(opts.cols) or 51,
    rows=tonumber(opts.rows) or 19,
    maxBuffer=tonumber(opts.maxBuffer) or 32768,
    output="",input={},closed=false,
    written=0,read=0,
  }

  local function trim()
    if #self.output>self.maxBuffer then
      self.output=self.output:sub(#self.output-self.maxBuffer+1)
    end
  end

  function self:write(data)
    if self.closed then return nil,"pty closed" end
    data=tostring(data or "")
    self.output=self.output..data
    self.written=self.written+#data
    trim()
    return #data
  end
  function self:pushInput(data)
    if self.closed then return nil,"pty closed" end
    data=tostring(data or "")
    self.input[#self.input+1]=data
    return true
  end

  function self:readInput()
    if #self.input==0 then return nil end
    local data=table.remove(self.input,1)
    self.read=self.read+#data
    return data
  end

  function self:peek()
    return self.output
  end

  function self:drain(maxBytes)
    if #self.output==0 then return "" end
    local n=tonumber(maxBytes) or #self.output
    n=math.max(0,math.min(n,#self.output))
    local data=self.output:sub(1,n)
    self.output=self.output:sub(n+1)
    return data
  end
  function self:resize(cols,rows)
    cols,rows=tonumber(cols),tonumber(rows)
    if not cols or not rows or cols<1 or rows<1 then return nil,"invalid size" end
    self.cols,self.rows=math.floor(cols),math.floor(rows)
    return true
  end

  function self:close()
    self.closed=true
    self.input={}
    return true
  end

  function self:status()
    return {
      cols=self.cols,rows=self.rows,closed=self.closed,
      buffered=#self.output,pendingInput=#self.input,
      written=self.written,read=self.read,
    }
  end

  return self
end

return M
