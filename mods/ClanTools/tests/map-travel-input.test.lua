local M=dofile('mods/ClanTools/Scripts/map_travel_input.lua');local n=0
local function test(name,fn)fn();n=n+1;print('PASS '..name)end
local function fixture()
 local keys={};local pawn={GetAddress=function()return 1 end};local pc={Pawn=pawn,GetAddress=function()return 2 end,IsInputKeyDown=function(_,k)return keys[k.KeyName]==true end}
 local s={offline=true,phase=4,pawn=pawn,pc=pc,worldId='world',profile='p',slot=0};local popup={GetAddress=function()return 3 end}
 local visible=true;local position={X=1,Y=2};local calls={preview=0,travel=0,reset=0,show=0,hide=0};local verified=true;local clock=10;local failRender=false;local message
 local rows={{key='Gamepad_LeftThumbstick',command=13}}
 local ctx={snapshot=function()return s end,valid=function(o)return o~=nil end,make_name=function(x)return x end,mapTime=function()return clock end,
 mapTravelFindPopup=function()return visible and popup or nil end,keybinds={bindings=function()return rows end},
 mapTravelPresenter={show=function(_,_,line)calls.show=calls.show+1;message=line;return not failRender,'No visible UI'end,hide=function()calls.hide=calls.hide+1 end},
 mapTravel={status=function()return{verified=verified}end,inspect=function()return true,{world=position}end,
 preview=function()calls.preview=calls.preview+1;return true,{token=7,label='Destination preview'}end,
 travel=function(token)assert(token==7);calls.travel=calls.travel+1;return true,'Travel complete'end,reset=function()calls.reset=calls.reset+1 end}}
 local a=M.new(ctx)
 local f={a=a,s=s,ctx=ctx,keys=keys,calls=calls,rows=rows,position=position}
 function f.press(key)keys[key]=true;assert(a.tick())end
 function f.release(key)keys[key]=false;assert(a.tick())end
 function f.visible(v)visible=v end;function f.verify(v)verified=v end;function f.clock(v)clock=v end;function f.failRender(v)failRender=v end;function f.message()return message end
 return f
end
test('map stays open, held entry is ignored, release and second press confirms once',function()
 local f=fixture();f.press('F9');assert(f.calls.preview==0);f.release('F9');f.press('F9');assert(f.calls.preview==1 and f.calls.travel==0)
 assert(f.a.tick());assert(f.calls.travel==0);f.release('F9');f.press('F9');assert(f.calls.travel==1 and not f.a.state().pending);assert(f.a.tick());assert(f.calls.travel==1)
end)
test('controller L3 supports preview and confirmation without native input mutation',function()
 local f=fixture();f.a.tick();f.press('Gamepad_LeftThumbstick');f.release('Gamepad_LeftThumbstick');f.press('Gamepad_LeftThumbstick');assert(f.calls.preview==1 and f.calls.travel==1)
end)
test('moving pointer cancels and no stale target travels',function()
 local f=fixture();f.a.tick();f.press('F9');f.release('F9');f.position.X=50;assert(f.a.tick());assert(not f.a.state().pending)
 f.press('F9');assert(f.calls.preview==2 and f.calls.travel==0)
end)
test('expiry and campaign changes cancel preview',function()
 local f=fixture();f.a.tick();f.press('F9');f.release('F9');f.clock(41);f.a.tick();assert(not f.a.state().pending)
 f.press('F9');f.release('F9');f.s.slot=1;f.press('F9');assert(not f.a.state().pending and f.calls.travel==0)
end)
test('unverified builds never call terrain preview or teleport',function()
 local f=fixture();f.verify(false);f.a.tick();f.press('F9');assert(f.calls.preview==0 and f.calls.travel==0);assert(f.message():match('verification'))
end)
test('custom bindings disable only conflicting shortcut',function()
 local f=fixture();f.rows[#f.rows+1]={key='F9',command=74};f.a.tick();f.press('F9');assert(f.calls.preview==0);f.press('Gamepad_LeftThumbstick');assert(f.calls.preview==1)
end)
test('hidden map, combat, foreign pawn and Clan Tools cannot trigger',function()
 for _,mutate in ipairs({function(f)f.visible(false)end,function(f)f.s.combat=true end,function(f)f.s.pc.Pawn=nil end,function(f)f.ctx.ui={opened=true}end,function(f)f.ctx.textPrompt={active=function()return true end}end})do
  local f=fixture();f.a.tick();f.press('F9');mutate(f);f.release('F9');f.press('F9');assert(not f.a.state().active and f.calls.travel==0)
 end
end)
test('failed visible hint disables actions and shutdown removes only owned hint',function()
 local f=fixture();f.a.tick();f.failRender(true);f.keys.F9=true;assert(not f.a.tick());assert(f.calls.preview==0 and not f.a.state().active);assert(f.a.shutdown());assert(not f.a.tick())
end)
print(n..' map input tests passed (model; native UI/geometry acceptance pending).')
