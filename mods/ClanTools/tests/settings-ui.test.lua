local dir=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local M=dofile(dir..'../Scripts/settings_ui.lua')
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function fixture()
 local objects,messages,calls={},{},{};local page='keys';local api
 local rows={};for i=1,15 do rows[i]={id=tostring(i),command=64+i,kind=0,scale_bits=1065353216,device='keyboard',original=string.char(64+i),key=string.char(64+i),label='Action '..i,editable=true,custom=false}end
 rows[2].key='Z';rows[15].device='gamepad';rows[15].key='Gamepad_FaceButton_Bottom';rows[15].original=rows[15].key
 local key={bindings=function(device)local list={};for _,r in ipairs(rows)do if r.device==device then list[#list+1]=r end end;return list end,
 available_keys=function(r)if r.device=='gamepad'then return{'Gamepad_FaceButton_Bottom','Gamepad_FaceButton_Right'}end;local keys={};for i=65,90 do keys[#keys+1]=string.char(i)end;return keys end,
 rebind=function(id,k,options)calls.bind={id,k,options};if calls.fail then return false,'Native validation failed'end;rows[tonumber(id)].key=k;rows[tonumber(id)].custom=true;return true end,
 reset_binding=function(id)calls.reset=id;return true end,reset_all=function()calls.reset_all=true;return true end}
 local function record(kind,label,x,y,w,h,fn,selected,enabled)
  assert(x>=430 and y>=135 and x+w<=1780 and y+h<=980,kind..' bounds '..tostring(label)..' '..y..'+'..h)
  local o={kind=kind,label=label,x=x,y=y,w=w,h=h,fn=fn,enabled=enabled,SetText=function(self,v)self.label=v end};objects[#objects+1]=o;return o
 end
 local function render()objects={};api.keybindPage() end
 api=M.new({keybinds=key,valid=function()return true end},{text=function(s,x,y,w,size)return record('text',s,x,y,w,size*2.1)end,button=function(s,x,y,w,h,fn,sel,en)return record('button',s,x,y,w,h,fn,sel,en)end,panel=function(x,y,w,h)return record('panel','',x,y,w,h)end,notify=function(s)messages[#messages+1]=s end,refresh=render})
 return {api=api,calls=calls,messages=messages,rows=rows,render=function(which)page=which or page;render()end,
 click=function(label,n)n=n or 1;for _,o in ipairs(objects)do if o.kind=='button'and o.label==label then n=n-1;if n==0 then assert(o.enabled~=false,'Disabled control '..label);o.fn();return end end end;error('Missing button '..label)end,
 has=function(label)for _,o in ipairs(objects)do if o.label==label then return o end end end}
end
test('paginated keyboard and controller binding pages fit native canvas',function()
 local f=fixture();f.render('keys');assert(f.has('Page 1 / 2'));f.click('Next');assert(f.has('Page 2 / 2'));f.click('Controller');assert(f.has('A / Cross'));f.click('Change');assert(f.has('B / Circle'));assert(f.api.back());assert(not f.api.back())
end)
test('conflicting binding requires explicit confirmation and redraws once committed',function()
 local f=fixture();f.render('keys');f.click('Change');f.click('Next keys');f.click('Z');assert(f.calls.bind==nil);assert(f.has('This key is already in use'));f.click('Use this key anyway');assert(f.calls.bind[2]=='Z'and f.calls.bind[3].allow_conflict);assert(f.has('Game controls'));assert(not f.api.back())
end)
test('failed rebind retains selection and surfaces actual backend error',function()
 local f=fixture();f.calls.fail=true;f.render('keys');f.click('Change');f.click('Next keys');f.click('Z');f.click('Use this key anyway');assert(f.messages[#f.messages]=='Native validation failed');assert(f.api.back());assert(f.api.back())
end)
test('reset all confirmation can cancel and back never applies a change',function()
 local f=fixture();f.render('keys');f.click('Restore all controls');assert(f.api.back());assert(f.calls.reset_all==nil);f.click('Restore all controls');f.click('Restore all controls');assert(f.calls.reset_all);assert(f.has('Game controls'));assert(not f.api.back())
end)
print(passed..' settings UI tests passed.')
