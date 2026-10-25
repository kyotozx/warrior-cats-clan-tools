-- Private instances of the game's customization cameras. Existing level camera
-- actors/components are read only; the native bridge lends its helper a private
-- target array and restores the original array/queue/weakrefs on DETACH_SCREEN.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local framing=dofile(folder..'appearance_framing.lua')
local M={}
function M.new(ctx)
 local valid=ctx.valid
 local gameplay=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local mathlib=StaticFindObject('/Script/Engine.Default__KismetMathLibrary')
 local class=StaticFindObject('/Script/SwtEngine.SwtCustomizationCineCamera')
 local names={'SelectBody','SelectEye','SelectEyeTinny','SelectEyeMedium','SelectMouth'}
 local api={}
 function api:prepare(h,helper,reference)
  assert(valid(class),'Native customization camera class is unavailable')
  h.cameras=h.cameras or{}
  for _,existing in ipairs(FindAllOf('SwtCustomizationCineCamera')or{})do
   if valid(existing)then for _,tag in ipairs(names)do
    assert(not existing:ActorHasTag(FName(tag)),'A game customization camera is already active')
   end end
  end
  local inventory
  helper.targetParams:ForEach(function(_,entry)
   local value=entry:get()
   if value.TargetName:ToString()=='InventoryCam'and valid(value.CameraTarget)then inventory=value.CameraTarget end
  end)
  assert(valid(inventory),'The game inventory camera is unavailable')
  local transform=inventory:GetTransform()
  local cameraPosition=inventory:K2_GetActorLocation()
  local mesh=h.actor.CustomizableMeshComponent.SkelMeshComp
  assert(valid(mesh),'The appearance preview mesh is unavailable')
  local head
  for i=0,math.min(mesh:GetNumBones()-1,2047)do
   local bone=mesh:GetBoneName(i);local name=bone:ToString():lower()
   if name:find('head',1,true)and not name:find('end',1,true)then head=mesh:GetSocketLocation(bone);break end
  end
  local sourceComponent=inventory.CameraComponent
  assert(valid(sourceComponent),'The game inventory lens is unavailable')
  local fov=sourceComponent.FieldOfView
  assert(type(fov)=='number'and fov>5 and fov<170,'The game inventory lens is invalid')
  local foot=h.actor:K2_GetActorLocation()
  local height=head and head.Z-foot.Z
  h.cameraFrame={mesh=mesh,aspect=sourceComponent.AspectRatio,position=cameraPosition,ticks=0}
  for i=0,math.min(mesh:GetNumBones()-1,2047)do
   local bone=mesh:GetBoneName(i);local name=bone:ToString():lower()
   if name:find('head',1,true)and not name:find('end',1,true)then h.cameraFrame.bone=bone;break end
  end
  for index,tag in ipairs(names)do
   local c=gameplay:BeginDeferredActorSpawnFromClass(h.context.pawn,class,transform,1,h.context.pawn,0)
   assert(valid(c),'Could not create a private customization camera')
   h.cameras[#h.cameras+1]=c
   c.Tags={FName(tag)};c:SetActorEnableCollision(false)
   c.bUpdatePivotWithTrackActor=false;c.bLimitYaw=false
   gameplay:FinishSpawningActor(c,transform,0)
   assert(valid(c),'Private camera failed to initialize')
   local lens=c:GetCineCameraComponent();assert(valid(lens),'Private camera lens unavailable')
   lens:SetConstraintAspectRatio(false)
   lens:SetAspectRatio(sourceComponent.AspectRatio)
   local sensor=lens.Filmback.SensorWidth
   assert(type(sensor)=='number'and sensor>0,'Private camera filmback unavailable')
   local focal=sensor/(2*math.tan(math.rad(fov)*.5))
   local zoom=({1,1.7,1.3,1.5,1.7})[index]
   lens:SetCurrentFocalLength(focal*zoom);lens:SetCurrentAperture(8)
   -- Game camera constructors enable manual focus at95; disable DOF in this
   -- owned lens so kittens/adults remain legible at the shared inventory stage.
   local focus=lens.FocusSettings;focus.FocusMethod=0;lens:SetFocusSettings(focus)
   if head and height and height>1 then
    local point={X=index==1 and foot.X or head.X,Y=index==1 and foot.Y or head.Y,Z=index==1 and(foot.Z+height*.56)or head.Z}
    local plan=framing.plan(cameraPosition,point,height*(index==1 and 1.3 or .65),sourceComponent.AspectRatio,sensor,index==1 and .43 or .48)
    if plan then
     lens:SetCurrentFocalLength(plan.focal)
     local rotation=mathlib:FindLookAtRotation(cameraPosition,point)
     local right=mathlib:GetRightVector(rotation)
     local aim={X=point.X-right.X*plan.rightOffset,Y=point.Y-right.Y*plan.rightOffset,Z=point.Z-right.Z*plan.rightOffset}
     lens:K2_SetWorldRotation(mathlib:FindLookAtRotation(cameraPosition,aim),false,{},true)
    end
   elseif index>1 and head then
    lens:K2_SetWorldRotation(mathlib:FindLookAtRotation(cameraPosition,head),false,{},true)
   end
  end
  h.reference=reference;h.referenceHidden=reference.bHidden
  assert(type(h.referenceHidden)=='boolean','Cannot preserve the inventory preview visibility')
  reference:SetActorHiddenInGame(true)
  return true
 end
 -- Native screen INIT applies the saved body scale after the actor is spawned.
 -- Re-measure its posed head after INIT/animation instead of keeping spawn-size
 -- framing. Only the five private lenses created above are ever adjusted.
 function api:reframe(h)
  local f=h.cameraFrame
  if not f or not f.bone or not valid(h.actor)or not valid(f.mesh)then return false end
  local head=f.mesh:GetSocketLocation(f.bone);local foot=h.actor:K2_GetActorLocation()
  local height=head.Z-foot.Z;if height<=1 then return false end
  for index,c in ipairs(h.cameras or{})do
   if valid(c)then
    local lens=c:GetCineCameraComponent()
    if valid(lens)then
     local position=c:K2_GetActorLocation()
     local point={X=index==1 and foot.X or head.X,Y=index==1 and foot.Y or head.Y,Z=index==1 and(foot.Z+height*.56)or head.Z}
     local plan=framing.plan(position,point,height*(index==1 and 1.3 or .65),f.aspect,lens.Filmback.SensorWidth,index==1 and .43 or .48)
     if plan then
      lens:SetCurrentFocalLength(plan.focal)
      local right=mathlib:GetRightVector(mathlib:FindLookAtRotation(position,point))
      local aim={X=point.X-right.X*plan.rightOffset,Y=point.Y-right.Y*plan.rightOffset,Z=point.Z-right.Z*plan.rightOffset}
      lens:K2_SetWorldRotation(mathlib:FindLookAtRotation(position,aim),false,{},true)
     end
    end
   end
  end
  f.height=height;return true
 end
 function api:tick(h)
  local f=h.cameraFrame;if not f then return end
  f.ticks=f.ticks+1
  -- Two settled passes allow native saved customization and its first posed
  -- skeleton update to finish. Stop thereafter to avoid chasing idle animation.
  if f.ticks==3 or f.ticks==8 then self:reframe(h)end
 end
 function api:attach(h,callbacks)
  assert(#h.cameras==5,'Private camera setup is incomplete')
  for i,c in ipairs(h.cameras)do
   local ok,err=callbacks.cameraTarget(i,c:GetAddress());assert(ok,err)
  end
 end
 function api:restore(h)
  if h.reference and valid(h.reference)and type(h.referenceHidden)=='boolean'then
   h.reference:SetActorHiddenInGame(h.referenceHidden);h.reference=nil
  end
 end
 function api:release(h)
  self:restore(h)
  h.cameraFrame=nil
  for i=#(h.cameras or{}),1,-1 do
   local c=h.cameras[i];if valid(c)then c:K2_DestroyActor()end;h.cameras[i]=nil
  end
 end
 return api
end
return M
