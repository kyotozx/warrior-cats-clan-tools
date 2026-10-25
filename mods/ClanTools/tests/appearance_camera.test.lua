local module=dofile('mods/ClanTools/Scripts/appearance_camera.lua')
local function fixture(fail)
 local f={created={},attached={},hidden=false}
 local sourceLens={FieldOfView=60,AspectRatio=16/9}
 local inventory={CameraComponent=sourceLens,GetTransform=function()return{}end,K2_GetActorLocation=function()return{X=-100,Y=0,Z=20}end}
 local helper={targetParams={ForEach=function(_,fn)fn(1,{get=function()return{TargetName={ToString=function()return'InventoryCam'end},CameraTarget=inventory}end})end}}
 local reference={bHidden=false,SetActorHiddenInGame=function(_,v)f.hidden=v end}
 local gameplay={}
 function gameplay:BeginDeferredActorSpawnFromClass()
  if fail and #f.created==fail-1 then return nil end
  local camera={id=#f.created+1}
  local lens={Filmback={SensorWidth=36},FocusSettings={FocusMethod=1},SetConstraintAspectRatio=function()end,SetAspectRatio=function()end,
   SetCurrentFocalLength=function(_,v)camera.focal=v end,SetCurrentAperture=function()end,SetFocusSettings=function(_,v)assert(v.FocusMethod==0)end,
   K2_SetWorldRotation=function()camera.aimed=true end}
  function camera:SetActorEnableCollision(v)assert(not v)end
  function camera:GetCineCameraComponent()return lens end
  function camera:GetAddress()return self.id end
  function camera:K2_GetActorLocation()return{X=-100,Y=0,Z=20}end
  function camera:K2_DestroyActor()self.destroyed=true end
  f.created[#f.created+1]=camera;return camera
 end
 function gameplay:FinishSpawningActor()end
 function StaticFindObject(path)
  if path:find('GameplayStatics',1,true)then return gameplay end
  if path:find('KismetMathLibrary',1,true)then return{FindLookAtRotation=function()return{}end,GetRightVector=function()return{X=0,Y=1,Z=0}end}end
  return{}
 end
 function FindAllOf()return{}end
 function FName(v)return v end
 f.height=30
 local mesh={GetNumBones=function()return 1 end,GetBoneName=function()return{ToString=function()return'head'end}end,GetSocketLocation=function()return{X=0,Y=0,Z=f.height}end}
 f.h={actor={CustomizableMeshComponent={SkelMeshComp=mesh},K2_GetActorLocation=function()return{X=0,Y=0,Z=0}end},context={pawn={}}}
 f.api=module.new({valid=function(o)return o~=nil and not o.destroyed end})
 f.helper=helper;f.reference=reference
 return f
end
do
 local f=fixture();f.api:prepare(f.h,f.helper,f.reference)
 local before=f.created[2].focal;f.height=9
 f.api:tick(f.h);f.api:tick(f.h);assert(f.created[2].focal==before)
 f.api:tick(f.h);assert(f.created[2].focal>before*2,'Settled kitten size must replace spawn framing')
 assert(f.h.cameraFrame.height==9)
 for i=4,9 do f.api:tick(f.h)end
 local settled=f.created[2].focal;f.height=10;f.api:tick(f.h);assert(f.created[2].focal==settled,'Do not follow idle head bob forever')
 f.api:release(f.h);assert(f.h.cameraFrame==nil)
 print('PASS post-init kitten head measurement reframes owned lenses and stops after settling')
end
do
 local f=fixture();assert(f.api:prepare(f.h,f.helper,f.reference));assert(#f.created==5 and f.hidden)
 f.api:attach(f.h,{cameraTarget=function(index,address)assert(index==address);f.attached[index]=true;return true end})
 assert(#f.attached==5 and f.created[1].Tags[1]=='SelectBody'and f.created[5].Tags[1]=='SelectMouth')
 assert(f.created[1].aimed and f.created[2].aimed and f.created[2].focal>f.created[1].focal)
 f.api:restore(f.h);assert(not f.hidden)
 for _,c in ipairs(f.created)do assert(not c.destroyed,'Camera destroyed before END')end
 f.api:release(f.h);for _,c in ipairs(f.created)do assert(c.destroyed)end
 print('PASS owned cameras use native stage framing, register five targets, and defer destruction')
end
do
 local f=fixture(3);assert(not pcall(f.api.prepare,f.api,f.h,f.helper,f.reference));assert(#f.created==2 and not f.hidden)
 f.api:release(f.h);for _,c in ipairs(f.created)do assert(c.destroyed)end
 print('PASS partial camera spawn retains ownership for cleanup without hiding original preview')
end
