local base=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local Input=dofile(base..'../Scripts/input.lua')
local down,just,axes={},{},{};local calls={};local opened=false;local pause=nil;local samples=0
local pc={}
function pc:GetAddress()return 1234 end
function pc:IsInputKeyDown(k)assert(type(k)=='table'and type(k.KeyName)=='string');samples=samples+1;return down[k.KeyName]==true end
function pc:WasInputKeyJustPressed(k)return just[k.KeyName]==true end
function pc:GetInputAnalogKeyState(k)return axes[k.KeyName]or 0 end
local ctx={make_name=function(n)return n end,valid=function(o)return o==pc end,
 is_open=function()return opened end,pause=function()return pause end,
 open=function(p)assert(p==pause);opened=true;calls[#calls+1]='open'end,
 back=function()calls[#calls+1]='back'end,activate=function()calls[#calls+1]='activate'end,
 tabcycle=function(d)calls[#calls+1]='tab:'..d end,nav=function(d)calls[#calls+1]=d end}
local input=Input.new(ctx);local snapshot={pc=pc,profile='abc',slot=0,worldId='world',offline=true}
local function tick(dt)assert(input.tick(snapshot,dt or 0.1))end
local function press(name)down[name]=true;just[name]=true;tick();just[name]=nil end
local function release(name)down[name]=nil;tick()end
tick();assert(samples==0);pause={};tick();assert(samples>0)
press('Gamepad_FaceButton_Top');assert(opened and calls[1]=='open');release('Gamepad_FaceButton_Top')
print('PASS input ignores gameplay and opens only from visible pause')
press('Gamepad_DPad_Down');assert(calls[#calls]=='down');local n=#calls
tick();tick();tick();assert(#calls==n);tick();assert(#calls==n+1);release('Gamepad_DPad_Down')
print('PASS digital navigation edge, initial delay and controlled repeat')
press('Gamepad_FaceButton_Bottom');n=#calls;tick();tick();assert(#calls==n and calls[n]=='activate');release('Gamepad_FaceButton_Bottom')
press('Gamepad_LeftShoulder');assert(calls[#calls]=='tab:-1');release('Gamepad_LeftShoulder')
press('Gamepad_FaceButton_Right');assert(calls[#calls]=='back');release('Gamepad_FaceButton_Right')
print('PASS confirm/back/tab mapping never repeats while held')
axes.Gamepad_LeftX=0.8;axes.Gamepad_LeftY=0.7;tick();assert(calls[#calls]=='right');n=#calls
axes.Gamepad_LeftX=0.4;axes.Gamepad_LeftY=0;tick();assert(#calls==n)
axes.Gamepad_LeftX=0;tick();axes.Gamepad_LeftY=-0.8;tick();assert(calls[#calls]=='down')
axes={};tick();print('PASS analog dominant-axis movement and hysteresis')
opened=false;pause=nil;press('Gamepad_FaceButton_Bottom');n=#calls;opened=true;tick();tick();assert(#calls==n)
release('Gamepad_FaceButton_Bottom');press('Gamepad_FaceButton_Bottom');assert(#calls==n+1)
release('Gamepad_FaceButton_Bottom');print('PASS held gameplay confirm suppressed when menu appears')
snapshot.worldId='world2';down.Gamepad_FaceButton_Bottom=true;n=#calls;tick();assert(#calls==n);release('Gamepad_FaceButton_Bottom')
local original=pc.IsInputKeyDown;pc.IsInputKeyDown=function()return nil end
local ok,err=input.tick(snapshot);assert(not ok and err:match('booleans'));assert(not input.status().active)
pc.IsInputKeyDown=original;tick();assert(input.status().error==nil)
print('PASS scene transition resets edges; reflection failure is contained and retryable')
press('Enter');assert(calls[#calls]=='activate');release('Enter');press('Escape');assert(calls[#calls]=='back');release('Escape')
print('PASS keyboard menu navigation shares callback path without binding F6')
press('W');assert(calls[#calls]=='up');release('W');press('A');assert(calls[#calls]=='left');release('A')
press('S');assert(calls[#calls]=='down');release('S');press('D');assert(calls[#calls]=='right');release('D')
press('Q');assert(calls[#calls]=='tab:-1');release('Q');press('E');assert(calls[#calls]=='tab:1');release('E')
print('PASS WASD navigation and Q/E tab switching')
opened=false;pause={};local chord=Input.new(setmetatable({open_keys={'Gamepad_LeftShoulder','Gamepad_RightShoulder','Gamepad_FaceButton_Top'}},{__index=ctx}))
assert(chord.tick(snapshot));down.Gamepad_FaceButton_Top=true;assert(chord.tick(snapshot));assert(not opened)
down.Gamepad_LeftShoulder=true;down.Gamepad_RightShoulder=true;assert(chord.tick(snapshot));assert(opened)
assert(chord.shutdown());assert(not chord.status().active)
print('PASS configurable opener chord and shutdown')
