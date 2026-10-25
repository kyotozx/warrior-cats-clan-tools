-- Engine-independent model shared by name, preset, waypoint and search dialogs.
local M={}
local rows={'QWERTYUIOP','ASDFGHJKL','ZXCVBNM','0123456789'}
function M.new(options)
 options=options or{}
 local self={text=options.value or'',index=1,upper=false,closed=false,error=nil}
 local keys={}
 for _,row in ipairs(rows)do for c in row:gmatch('.')do keys[#keys+1]=c end end
 for _,k in ipairs({'Space',"'",'-','Case','Delete','Clear','Cancel','Done'})do keys[#keys+1]=k end
 self.keys=keys
 local function check(value)
  local length=utf8.len(value)
  return length and length<=(options.maxLength or 40)and not value:find('[%z\1-\31\127<>]')
 end
 function self.insert(value)
  if self.closed then return false end
  if not check(self.text..value)then self.error='Character limit reached or unsupported character.';return false end
  self.text=self.text..value;self.error=nil;return true
 end
 function self.delete()
  if self.closed then return end
  local offset=utf8.offset(self.text,-1);if offset then self.text=self.text:sub(1,offset-1)end;self.error=nil
 end
 function self.cancel()if not self.closed then self.closed=true;if options.cancel then options.cancel()end end end
 function self.confirm()
  if self.closed then return false end
  local value,why=self.text,nil
  if options.validate then
   local checked;checked,why=options.validate(value)
   if checked==false or checked==nil then self.error=why or'Invalid text.';return false end
   if type(checked)=='string'then value=checked end
  end
  local ok,result,reason=pcall(options.accept or function()return true end,value)
  if not ok or result==false then self.error=tostring(ok and reason or result);return false end
  self.closed=true;return true
 end
 function self.activate(index)
  local key=keys[index or self.index];if not key or self.closed then return end
  if key=='Done'then return self.confirm()elseif key=='Cancel'then self.cancel()
  elseif key=='Delete'then self.delete()elseif key=='Clear'then self.text='';self.error=nil
  elseif key=='Case'then self.upper=not self.upper
  elseif key=='Space'then self.insert(' ')
  else self.insert(self.upper and key or key:lower())end
 end
 function self.navigate(direction)
  local delta=({left=-1,right=1,up=-10,down=10})[direction]
  if delta then self.index=((self.index-1+delta)%#keys)+1 end
 end
 function self.key(name,shift)
  name=({Zero='0',One='1',Two='2',Three='3',Four='4',Five='5',Six='6',Seven='7',Eight='8',Nine='9'})[name]or name
  if name=='Escape'then self.cancel();return true end
  if name=='BackSpace'then self.delete();return true end
  if name=='Enter'then self.confirm();return true end
  if name=='SpaceBar'then self.insert(' ');return true end
  if type(name)=='string'and name:match('^[A-Z0-9]$')then self.insert((shift or self.upper)and name or name:lower());return true end
  if name=='Hyphen'or name=='Subtract'then self.insert('-');return true end
  if name=='Apostrophe'then self.insert("'");return true end
  return false
 end
 return self
end
return M
