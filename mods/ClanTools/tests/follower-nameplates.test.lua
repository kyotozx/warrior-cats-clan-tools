local M=dofile('mods/ClanTools/Scripts/follower_nameplates.lua')
local n=0
local function test(name,fn)fn();n=n+1;print('PASS '..name)end
local function object(t)t=t or{};t.alive=true;function t:IsValid()return self.alive end;return t end
local function fixture()
 local position={X=0,Y=0,Z=0};local pawn=object{K2_GetActorLocation=function()return position end}
 local actor=object{GetAddress=function()return 7 end,K2_GetActorLocation=function()return{X=0,Y=0,Z=0}end}
 local function text()return object{SetText=function(self,v)self.text=v end,SetVisibility=function(self,v)self.visibility=v end}end
 local widget=object{mcGuiTextName=text(),mcGuiTextRole=text(),mcGuiTextExtraInfo=text(),SetVisibility=function(self,v)self.visibility=v end,RemoveFromParent=function()end}
 local component=object{GetOwner=function()return actor end,SetWidget=function(self,w)self.widget=w end,
  SetVisibility=function(self,v)self.visible=v end,SetHiddenInGame=function()end,
  SetCollisionEnabled=function(_,v)assert(v==0)end,SetGenerateOverlapEvents=function(_,v)assert(v==false)end,
  SetWidgetSpace=function(_,v)assert(v==1)end,SetDrawSize=function()end,SetPivot=function()end,SetDrawAtDesiredSize=function()end,
  K2_DestroyComponent=function(self,o)assert(o==actor);self.alive=false end}
 function actor:AddComponentByClass()return component end
 local paused=false
 StaticFindObject=function(path)
  if path=='/Script/UMG.Default__WidgetBlueprintLibrary'then return{Create=function()return widget end}end
  if path=='/Script/Engine.Default__GameplayStatics'then return{IsGamePaused=function()return paused end}end
  return object()
 end
 FText=function(v)return v end
 local s={offline=true,phase=4,pc=object(),pawn=pawn}
 local plate=M.new(actor,{name='Hareblaze',rank='MedicineCat'},s)
 return plate,s,position,actor,component,widget,function(v)paused=v end
end
test('native name and rank only, no interaction status',function()
 local p,s,x,a,c,w=fixture();assert(w.mcGuiTextName.text=='Hareblaze'and w.mcGuiTextRole.text=='MEDICINE CAT');assert(w.mcGuiTextExtraInfo.visibility==2);assert(not c.visible)
 p.update(s);assert(c.visible and w.visibility==4)
end)
test('nearby hysteresis prevents boundary flicker',function()
 local p,s,x,a,c=fixture();x.X=480;p.update(s);assert(not c.visible)
 x.X=400;p.update(s);assert(c.visible);x.X=500;p.update(s);assert(c.visible);x.X=560;p.update(s);assert(not c.visible)
end)
test('menus combat and unsafe phases hide immediately',function()
 local p,s,x,a,c,w,pause=fixture();p.update(s);pause(true);p.update(s);assert(not c.visible)
 pause(false);p.update(s);assert(c.visible);s.combat=true;p.update(s);assert(not c.visible)
 s.combat=false;s.phase=5;p.update(s);assert(not c.visible)
end)
test('renaming and changing rank refresh text without actor identity writes',function()
 local p,s,x,a,c,w=fixture();p.update(s,{name='Free Name',rank='Deputy'});assert(w.mcGuiTextName.text=='Free Name'and w.mcGuiTextRole.text=='DEPUTY');assert(a.NarrativeRole==nil and a.ActorIdentifier==nil)
end)
test('destroy is idempotent and touches owned component only',function()
 local p,s,x,a,c=fixture();assert(p.destroy());assert(not c.alive and a.alive);assert(p.destroy());assert(p.update(s)==false)
end)
test('reassigned component is not destroyed',function()
 local p,s,x,a,c=fixture();c.GetOwner=function()return object{GetAddress=function()return 99 end}end
 assert(p.destroy());assert(c.alive and a.alive)
end)
test('destroyed actors hide and can retire label safely',function()
 local p,s,x,a,c,w=fixture();p.update(s);a.alive=false;assert(p.update(s)==false);assert(w.visibility==2);assert(p.destroy())
end)
print(n..' follower nameplate model tests passed; native rendering requires in-game validation.')
