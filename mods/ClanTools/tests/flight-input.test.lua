local M=dofile('mods/ClanTools/Scripts/flight_input.lua')
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function fixture()
 local held,analog,calls,logs={},{},{},{};local pause=false
 local pc={GetAddress=function()return 2 end,IsInputKeyDown=function(_,key)return held[key.KeyName]==true end,GetInputAnalogKeyState=function(_,key)return analog[key.KeyName]or 0 end,IsMoveInputIgnored=function()return false end}
 local s={offline=true,phase=4,pc=pc,pawn={GetAddress=function()return 1 end},worldId='world',profile='p',slot=0}
 pc.Pawn=s.pawn
 local cap={available=true,flight=true,actions={vertical_input={enabled=true}}};local ui={opened=false}
 local ctx={snapshot=function()return s end,valid=function(o)return o~=nil end,make_name=function(n)return n end,ui=ui,is_paused=function()return pause end,log=function(v)logs[#logs+1]=v end,
 admin={capabilities=function()return cap end,flightInput=function(axis,horizontal)if calls.fail then return false,'Native failure'end;calls[#calls+1]={axis,horizontal};return true end}}
 local api=M.new(ctx)
 return api,s,held,analog,calls,cap,ui,logs,function(v)pause=v end,ctx
end
local function last(c,axis,horizontal)local r=c[#c];assert(r and r[1]==axis and r[2]==horizontal)end
test('conflict-free keyboard ascent descent and immediate neutral stop',function()
 local a,s,h,an,c=fixture();a.tick();h.V=true;a.tick();last(c,1,false);h.B=true;a.tick();last(c,0,false);h.V=false;a.tick();last(c,-1,false);h.B=false;a.tick();last(c,0,false)
 h.SpaceBar=true;h.LeftControl=true;an.Gamepad_LeftTriggerAxis=1;an.Gamepad_RightTriggerAxis=1;a.tick();last(c,0,false)
end)
test('controller shoulders/thumbstick leave right camera stick alone',function()
 local a,s,h,an,c=fixture();a.tick();h.Gamepad_RightShoulder=true;an.Gamepad_RightX=.9;a.tick();last(c,1,false)
 h.Gamepad_LeftThumbstick=true;a.tick();last(c,0,false);h.Gamepad_RightShoulder=false;a.tick();last(c,-1,false)
end)
test('native horizontal movement and deadzone prevent false braking',function()
 local a,s,h,an,c=fixture();a.tick();h.W=true;a.tick();last(c,0,true);h.S=true;a.tick();last(c,0,false)
 h.W=false;h.S=false;an.Gamepad_LeftX=.1;a.tick();last(c,0,false);an.Gamepad_LeftX=.5;a.tick();last(c,0,true)
end)
test('held menu confirmation must release before entering flight',function()
 local a,s,h,an,c,cap,ui=fixture();ui.opened=true;h.V=true;a.tick();ui.opened=false;a.tick();a.tick();last(c,0,false);h.V=false;a.tick();h.V=true;a.tick();last(c,1,false)
end)
test('active flight brakes once on menu entry and resumes without held ascent',function()
 local a,s,h,an,c,cap,ui=fixture();a.tick();h.V=true;a.tick();ui.opened=true;a.tick();last(c,0,false);local n=#c;a.tick();assert(#c==n);ui.opened=false;a.tick();a.tick();last(c,0,false)
end)
test('unknown online combat and unverified states never submit input',function()
 local a,s,h,an,c,cap,ui,log,pause=fixture();h.V=true
 pause(true);a.tick();pause(false);s.offline=nil;a.tick();s.offline=false;a.tick();s.offline=true;s.combat=true;a.tick();s.combat=false;cap.actions.vertical_input.enabled=false;a.tick();assert(#c==0)
end)
test('same failure logs once across repeated attempts and activation resets',function()
 local a,s,h,an,c,cap,ui,logs=fixture();a.tick();c.fail=true;h.V=true;assert(not a.tick());a.tick();h.V=false;assert(not a.tick());assert(#logs==1)
end)
test('custom movement bindings used and vertical conflict disabled per control',function()
 local a,s,h,an,c,cap,ui,logs,pause,ctx=fixture()
 ctx.keybinds={bindings=function()return{{command=60,key='T',scale_bits=1065353216},{command=61,key='G',scale_bits=1065353216},{command=71,key='V',label='Crouch'},{command=95,key='Gamepad_RightShoulder',label='AnimTool Next'}}end}
 a.tick();h.T=true;h.V=true;a.tick();last(c,0,true);assert(a.state().conflicts.V=='Crouch');assert(not a.state().conflicts.Gamepad_RightShoulder)
 h.Gamepad_RightShoulder=true;a.tick();last(c,1,true);assert(#logs==1)
end)
test('binding lookup failure is fail-closed and cannot brake unknown input',function()
 local a,s,h,an,c,cap,ui,logs,pause,ctx=fixture();ctx.keybinds={bindings=function()return false,'failure'end};assert(not a.tick());assert(#c==0)
end)
test('temporary unpossession never injects movement into the old exploration pawn',function()
 local a,s,h,an,c=fixture();a.tick();s.pc.Pawn=nil;h.V=true;a.tick();assert(#c==0)
 s.pc.Pawn={GetAddress=function()return 99 end};a.tick();assert(#c==0)
end)
test('own timer is saved cancelled explicitly and shutdown prevents restart',function()
 local a=fixture();local registrations,cancelled=0,0;local callback
 LoopInGameThreadWithDelay=function(delay,fn)assert(delay==16);registrations=registrations+1;callback=fn;return 73 end
 CancelDelayedAction=function(h)assert(h==73);cancelled=cancelled+1 end
 assert(a.start());assert(a.start());assert(registrations==1);callback();assert(a.stop());assert(cancelled==1);assert(a.start());assert(a.shutdown());assert(cancelled==2);assert(not a.start());callback()
 LoopInGameThreadWithDelay=nil;CancelDelayedAction=nil
end)
print(passed..' flight input tests passed (mock controls).')
