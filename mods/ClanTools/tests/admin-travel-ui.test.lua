local M=dofile('mods/ClanTools/Scripts/admin_travel_ui.lua')
local n=0;local function test(name,fn)fn();n=n+1;print('PASS '..name)end
local function fixture()
 local buttons,calls={},{};local cap={available=true,hasReturn=true,actions={teleport_destination={enabled=true}}};local failure,prompt
 local rows={{id='clan_spawn:1',label='ThunderClan spawn point'},{id='clan_spawn:4',label='WindClan spawn point'}}
 local admin={capabilities=function()return cap end,destinations=function()if failure then return false,failure end;return true,rows end,action=function(id,args)calls[#calls+1]={id=id,args=args};return true,'Travel complete'end}
 local api;local function render()buttons={};api.page()end
 local function bounds(x,y,w,h)assert(x>=430 and y>=135 and x+w<=1780 and y+h<=980)end
 api=M.new({admin=admin},{text=function(_,x,y,w,size)bounds(x,y,w,size*2.1)end,panel=bounds,button=function(label,x,y,w,h,fn,selected,enabled)bounds(x,y,w,h);buttons[label]={fn=fn,enabled=enabled}end,refresh=render,notify=function()end,prompt=function(opts)prompt=opts;return true end})
 return{api=api,render=render,cap=cap,calls=calls,get=function(s)return buttons[s]end,fail=function(s)failure=s end,prompt=function()return prompt end}
end
test('bounded canvas and exact named id action',function()local f=fixture();f.render();assert(#f.calls==0);f.get('WindClan spawn point').fn();assert(f.calls[1].id=='teleport_destination'and f.calls[1].args.id=='clan_spawn:4');f.get('Return to previous position').fn();assert(f.calls[2].id=='return_position')end)
test('noclip and verification gate buttons',function()local f=fixture();f.cap.noclip=true;f.render();assert(not f.get('WindClan spawn point').enabled and not f.get('Return to previous position').enabled);f.cap.noclip=false;f.cap.actions.teleport_destination.enabled=false;f.render();assert(not f.get('WindClan spawn point').enabled)end)
test('failed refresh removes stale destinations and back clears cache',function()local f=fixture();f.render();f.fail('Campaign changed');f.get('Refresh locations').fn();assert(not f.get('WindClan spawn point'));assert(not f.api.back());f.fail(nil);f.render();assert(f.get('WindClan spawn point'))end)
test('waypoints are paged four at a time and travel uses exact name',function()
 local f=fixture();f.cap.waypoints={};for i=1,9 do f.cap.waypoints[i]={name='Place '..i}end;f.render();f.get('My waypoints').fn()
 assert(f.get('Place 4')and not f.get('Place 5')and not f.get('Previous').enabled);f.get('Next').fn();assert(f.get('Place 5')and f.get('Place 8')and not f.get('Place 4'))
 f.get('Place 5').fn();assert(f.calls[1].id=='teleport_waypoint'and f.calls[1].args.name=='Place 5');f.get('Next').fn();assert(f.get('Place 9')and not f.get('Next').enabled)
 f.cap.noclip=true;f.render();assert(not f.get('Place 9').enabled)
end)
test('delete confirmation and back never delete silently',function()
 local f=fixture();f.cap.waypoints={{name='Lookout'}};f.render();f.get('My waypoints').fn();f.get('Delete').fn();assert(#f.calls==0)
 assert(f.api.back());assert(#f.calls==0);f.get('Delete').fn();f.get('Keep waypoint').fn();assert(#f.calls==0)
 f.get('Delete').fn();f.get('Delete waypoint').fn();assert(f.calls[1].id=='delete_waypoint'and f.calls[1].args.name=='Lookout')
end)
test('native prompt rejects duplicates invalid names and race-time duplicates',function()
 local f=fixture();f.cap.waypoints={{name='Lookout'}};f.render();f.get('My waypoints').fn();f.get('Save current location').fn();local p=f.prompt();assert(p and p.maxLength==32)
 assert(not p.validate('Lookout'));assert(not p.validate('../oops'));assert(not p.validate('   '));assert(p.validate('Riverbank'))
 f.cap.waypoints[#f.cap.waypoints+1]={name='Riverbank'};assert(not p.accept('Riverbank'));assert(#f.calls==0)
 assert(p.accept('Camp trail'));assert(f.calls[1].id=='save_waypoint'and f.calls[1].args.name=='Camp trail')
end)
test('map guide does not cover original map or invoke teleport and back returns home',function()
 local f=fixture();f.render();f.get('World map travel').fn();assert(#f.calls==0 and not f.get('WindClan spawn point'));assert(f.api.back());assert(f.get('WindClan spawn point'));f.api.reset();f.render()
end)
print(n..' travel UI tests passed (mock renderer).')
