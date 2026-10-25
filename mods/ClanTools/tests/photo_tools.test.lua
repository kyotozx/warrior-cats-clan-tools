local M=dofile('mods/ClanTools/Scripts/photo_tools.lua')
local counter=0
local function object(t)
 counter=counter+1;t=t or{};t.id=counter
 function t:GetAddress()return self.id end;function t:GetFullName()return'Object '..self.id end
 return t
end
local function fixture()
 local f={files={},s={profile='A',slot=0,worldId='World',offline=true}}
 local lens=object({FieldOfView=70,RelativeRotation={Pitch=2,Yaw=3,Roll=1}})
 function lens:SetFieldOfView(v)self.FieldOfView=v end
 function lens:K2_SetRelativeRotation(v)self.RelativeRotation=v end
 local popup=object({opacity=.8});function popup:GetRenderOpacity()return self.opacity end;function popup:SetRenderOpacity(v)self.opacity=v end
 f.p={lens=lens,popup=popup,camera=object()}
 local movement=object({tick=true,stops=0});function movement:IsComponentTickEnabled()return self.tick end;function movement:SetComponentTickEnabled(v)self.tick=v end
 function movement:StopMovementImmediately()self.stops=self.stops+1 end
 local mesh=object({GlobalAnimRateScale=.75})
 f.cat=object({CustomTimeDilation=.5,CharacterMovement=movement,Mesh=mesh})
 f.name=object({opacity=.6});function f.name:GetRenderOpacity()return self.opacity end;function f.name:SetRenderOpacity(v)self.opacity=v end
 f.ctx={root='memory/',valid=function(o)return type(o)=='table'and not o.dead end,snapshot=function()return f.s end,
  read=function(p)return f.files[p]end,write=function(p,v)f.files[p]=v end,
  photoDiscover=function()return f.p end,photoCharacters=function()return{f.cat}end,photoNameWidgets=function()return{f.name}end}
 f.api=M.new(f.ctx);return f
end
do
 local f=fixture();assert(f.api.configure('fov',95));assert(f.api.configure('roll',12))
 assert(f.api.configure('hideUI',true));assert(f.api.configure('hideNames',true));assert(f.api.configure('freezeCharacters',true));assert(f.api.tick())
 assert(f.p.lens.FieldOfView==95 and f.p.lens.RelativeRotation.Roll==13)
 assert(f.p.popup.opacity==0 and f.name.opacity==0 and f.ctx.photoHideNames and f.ctx.photoHideUI)
 assert(f.cat.CustomTimeDilation==0 and f.cat.CharacterMovement.tick==false and f.cat.Mesh.GlobalAnimRateScale==0)
 f.p.lens.RelativeRotation.Pitch=20;f.p.lens.RelativeRotation.Yaw=40;assert(f.api.tick())
 assert(f.p.lens.RelativeRotation.Pitch==20 and f.p.lens.RelativeRotation.Yaw==40,'Preserve native camera look')
 local p=f.p;f.p=nil;assert(f.api.tick())
 assert(p.lens.FieldOfView==70 and p.lens.RelativeRotation.Roll==1 and p.popup.opacity==.8)
 assert(f.cat.CustomTimeDilation==.5 and f.cat.CharacterMovement.tick and f.cat.Mesh.GlobalAnimRateScale==.75)
 assert(f.name.opacity==.6 and not f.ctx.photoHideNames and not f.ctx.photoHideUI)
 print('PASS photo lens/roll preserve native look; UI/names/freeze restore exact prior states on exit')
end
do
 local f=fixture();assert(f.api.tick());f.p.lens.FieldOfView=82;f.p.lens.RelativeRotation.Roll=4;assert(f.api.tick())
 assert(f.p.lens.FieldOfView==82 and f.p.lens.RelativeRotation.Roll==4,'Defaults leave native lens controls alone')
 assert(not f.api.configure('fov',200));assert(not f.api.configure('roll',0/0));assert(not f.api.configure('hideUI',1))
 f.s.offline=false;assert(f.api.tick());assert(not f.api.status().active)
 f.s.offline=true;f.s.combat=true;assert(f.api.tick());assert(not f.api.status().active)
 print('PASS native photo controls pass through default settings; invalid values/multiplayer/combat refused')
end
do
 local f=fixture();assert(f.api.configure('freezeCharacters',true));assert(f.api.tick());f.cat.dead=true
 f.p.lens.dead=true;assert(f.api.shutdown());assert(not f.ctx.photoHideNames)
 print('PASS destroyed actors/cameras release without stale-object writes')
end
do
 local f=fixture();assert(f.api.configure('fov',95));local lens=f.p.lens;local fail=true
 function lens:SetFieldOfView(value)self.FieldOfView=value;if fail then fail=false;error('partial native setter failure')end end
 assert(not f.api.tick());assert(lens.FieldOfView==70 and not f.api.status().active,'Mutation cleanup owns state before invoking native setter')
 local prior=f.files['memory/photo-settings.json'];local rawWrite=f.ctx.write;local failWrite=true
 f.ctx.write=function(path,value)rawWrite(path,value);if path=='memory/photo-settings.json'and failWrite then failWrite=false;error('partial write failure')end end
 assert(not f.api.configure('fov',100));assert(f.files['memory/photo-settings.json']==prior and f.api.status().settings.fov==95)
 print('PASS partial native setter and preference write failures restore prior states')
end
