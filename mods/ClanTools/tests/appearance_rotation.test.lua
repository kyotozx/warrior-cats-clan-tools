local M=dofile('mods/ClanTools/Scripts/appearance_rotation.lua')
local held,analog={},{};local yaw,now=0,0;local prompt=false;local callback;local cancelled=0
local pc={IsInputKeyDown=function(_,k)return held[k.KeyName]==true end,GetInputAnalogKeyState=function(_,k)return analog[k.KeyName]or 0 end}
local actor={K2_GetActorRotation=function()return{pitch=13,Yaw=yaw,Roll=2}end,K2_SetActorRotation=function(_,r)assert(r.pitch==13 and r.Roll==2);yaw=r.Yaw end}
local h={actor=actor,widget={},pc=pc}
LoopInGameThreadWithDelay=function(ms,fn)assert(ms==16);callback=fn;return 9 end
CancelDelayedAction=function(id)assert(id==9);cancelled=cancelled+1 end
local api=M.new({valid=function(o)return o~=nil end,make_name=function(v)return v end,rotationClock=function()return now end,textPrompt={active=function()return prompt end},keybinds={bindings=function()return{
 {command=66,kind=1,key='T',scale_bits=1065353216},{command=66,kind=1,key='G',scale_bits=3212836864},{command=66,kind=1,key='Gamepad_RightX',scale_bits=1065353216},
 {command=66,kind=1,key='T',scale_bits=1065353216}}
end}})
local function frames(n)for _=1,n do now=now+.016;callback()end end
held.T=true;api.start(h);frames(10);assert(yaw==0,'Held entry input must release')
held.T=false;frames(1);held.T=true;frames(30);assert(yaw>35 and yaw<55,'Remapped input is scaled once')
held.T=false;held.G=true;frames(60);assert(yaw<0)
held.G=false;analog.Gamepad_RightX=.1;frames(35);local neutral=yaw;frames(10);assert(yaw==neutral,'Release settles without drifting')
analog.Gamepad_RightX=.7;frames(20);assert(yaw>neutral)
prompt=true;local before=yaw;frames(10);assert(yaw==before)
prompt=false;frames(10);assert(yaw==before,'Text input must release before rotation resumes')
analog.Gamepad_RightX=0;frames(1);analog.Gamepad_RightX=.7;frames(10);assert(yaw>before)
h.closed=true;before=yaw;frames(10);assert(yaw==before)
api.stop();assert(cancelled==1)
print('PASS owned preview rotation, remapping/dedup, stick deadzone, release damping, prompt and cleanup')
