local M={}
function M.new(cols,rows)
 local p={cols=cols or 51,rows=rows or 19,input={},output={},closed=false,foreground_pgid=nil}
 function p:write(x)if self.closed then return nil,"EIO" end self.output[#self.output+1]=tostring(x);return true end
 function p:read_output()local s=table.concat(self.output);self.output={};return s end
 function p:push_input(x)self.input[#self.input+1]=tostring(x)end
 function p:read_input()if #self.input==0 then return nil end return table.remove(self.input,1)end
 function p:close()self.closed=true end
 return p
end
return M
