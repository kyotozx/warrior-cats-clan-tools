-- Native-map pointer projection and fail-closed travel validation.
-- Static formula: GuiPopupWorldMap world-to-map helper RVA 0x1911550.
local dir=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local nativeValid=dofile(dir..'runtime_valid.lua').valid
local M={}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<=1000000 end
local function vec(v)local p={X=v.X,Y=v.Y,Z=v.Z};assert(finite(p.X)and finite(p.Y)and finite(p.Z),'Invalid world position.');return p end
local function coordinates(c)
 local out={};for _,key in ipairs({'MapWidth','MapHeight','WorldMinX','WorldMaxX','WorldMinY','WorldMaxY'})do out[key]=c[key];assert(finite(out[key]),'Map bounds are unavailable.')end
 assert(out.MapWidth>0 and out.MapHeight>0 and out.WorldMaxX>out.WorldMinX and out.WorldMaxY>out.WorldMinY,'Map bounds are invalid.');return out
end
function M.world_to_map(c,p)
 c=coordinates(c);assert(finite(p.X)and finite(p.Y),'Invalid map position.')
 return{X=(p.Y-c.WorldMinY)*c.MapWidth/(c.WorldMaxY-c.WorldMinY),Y=(p.X-c.WorldMaxX)*c.MapHeight/(c.WorldMinX-c.WorldMaxX)}
end
function M.map_to_world(c,p)
 c=coordinates(c);assert(finite(p.X)and finite(p.Y)and p.X>=0 and p.Y>=0 and p.X<=c.MapWidth and p.Y<=c.MapHeight,'Choose a point inside the world map.')
 return{X=c.WorldMaxX+p.Y*(c.WorldMinX-c.WorldMaxX)/c.MapHeight,Y=c.WorldMinY+p.X*(c.WorldMaxY-c.WorldMinY)/c.MapWidth}
end
-- FGeometry is opaque to UE4SS on this build. Resolve the native canvas slots
-- instead: pointer and ContentMap share a parent, so their common anchor cancels.
function M.canvas_rect(a,parent)
 local function axis(lo,hi,offset,extent,align,size)
  local length=hi==lo and extent or (hi-lo)*size-offset-extent
  assert(finite(length)and length>0,'Native map canvas has no usable size.')
  return lo*size+offset-align*length,length
 end
 local x,w=axis(a.min.X,a.max.X,a.left,a.right,a.align.X,parent.X)
 local y,h=axis(a.min.Y,a.max.Y,a.top,a.bottom,a.align.Y,parent.Y)
 return{X=x,Y=y},{X=w,Y=h}
end
function M.canvas_inverse(point,origin,size,t)
 assert(finite(t.scale.X)and finite(t.scale.Y)and t.scale.X>0 and t.scale.Y>0,'Native map zoom is unavailable.')
 local function axis(k)local pivot=size[k]*t.pivot[k];return(point[k]-origin[k]-t.translation[k]-pivot)/t.scale[k]+pivot end
 return{X=axis('X'),Y=axis('Y')}
end
local function canvas(w)
 local a=w.Slot.LayoutData;local t=w.RenderTransform
 assert(t.Angle==0 and t.Shear.X==0 and t.Shear.Y==0,'Rotated map layouts are unsupported.')
 return{min={X=a.Anchors.Minimum.X,Y=a.Anchors.Minimum.Y},max={X=a.Anchors.Maximum.X,Y=a.Anchors.Maximum.Y},
  left=a.Offsets.Left,top=a.Offsets.Top,right=a.Offsets.Right,bottom=a.Offsets.Bottom,align={X=a.Alignment.X,Y=a.Alignment.Y}},
  {scale={X=t.Scale.X,Y=t.Scale.Y},translation={X=t.Translation.X,Y=t.Translation.Y},pivot={X=w.RenderTransformPivot.X,Y=w.RenderTransformPivot.Y}}
end
local function pointerPoint(p)
 local pointer,map=p.mcGuiPointer,p.ContentMap
 assert(pointer:GetParent():GetAddress()==map:GetParent():GetAddress(),'Native map pointer parent changed.')
 local a,t=canvas(pointer);local b,u=canvas(map)
 assert(a.min.X==a.max.X and a.min.Y==a.max.Y and b.min.X==b.max.X and b.min.Y==b.max.Y
  and a.min.X==b.min.X and a.min.Y==b.min.Y,'Native map anchors changed.')
 local origin,size=M.canvas_rect(a,{X=0,Y=0})
 local point={X=origin.X+size.X*t.pivot.X+(size.X*(.5-t.pivot.X))*t.scale.X+t.translation.X,
  Y=origin.Y+size.Y*t.pivot.Y+(size.Y*(.5-t.pivot.Y))*t.scale.Y+t.translation.Y}
 origin,size=M.canvas_rect(b,{X=0,Y=0});point=M.canvas_inverse(point,origin,size,u)
 local parent=map
 for _,w in ipairs({p.ContentScaler,p.CanvasLayers,p.CanvasGenericIcons})do
  assert(w:GetParent():GetAddress()==parent:GetAddress(),'Native map canvas hierarchy changed.')
  a,t=canvas(w);origin,size=M.canvas_rect(a,size);point=M.canvas_inverse(point,origin,size,t);parent=w
 end
 return point
end
function M.new(ctx)
 assert(ctx and ctx.snapshot and ctx.admin,'Map travel requires the active admin context.')
 local api={};local pending,sequence,lastError=nil,0,nil;local valid=ctx.valid or nativeValid
 local function snapshot()
  local s=ctx.snapshot();assert(s and s.offline==true and s.phase==4 and not s.combat and valid(s.pawn)and valid(s.pc)and valid(s.pc.Pawn)and s.pc.Pawn:GetAddress()==s.pawn:GetAddress(),'Map travel requires possessed offline exploration.')
  assert(ctx.mapAdapter or s.worldId=='World /Game/Art/Maps/Gameplay/L_WorldMap_01_P.L_WorldMap_01_P','Unsupported map world.')
  return s
 end
 local function session(s)return table.concat({s.worldId,s.profile or'',tostring(s.slot),tostring(s.pawn:GetAddress())},'|')end
 local function inspect(s)
  if ctx.mapAdapter and ctx.mapAdapter.inspect then return ctx.mapAdapter.inspect(s)end
  local popup
  for _,p in ipairs(FindAllOf('GuiPopupWorldMap')or{})do if valid(p)and p:IsInViewport()and p:IsVisible()then assert(not popup,'Multiple active maps are ambiguous.');popup=p end end
  assert(popup,'Open the native world map and move its pointer to a destination.')
  assert(valid(popup.mcGuiPointer)and valid(popup.CanvasGenericIcons)and valid(popup.mcGuiPlayerIcon),'Native map widgets are unavailable.')
  local point=pointerPoint(popup)
  local c=coordinates(popup.MapCoordinates)
  -- Verify this projection against the game's own currently displayed player
  -- marker before interpreting the pointer. Pan, scale and DPI are in geometry.
  local expected=M.world_to_map(c,s.pawn:K2_GetActorLocation())
  local actual=popup.mcGuiPlayerIcon.RenderTransform.Translation
  assert(finite(actual.X)and finite(actual.Y)and math.abs(expected.X-actual.X)<=5 and math.abs(expected.Y-actual.Y)<=5,'Native player marker does not match map coordinates; travel is blocked.')
  local world=M.map_to_world(c,point)
  return{point={X=point.X,Y=point.Y},world=world,map={width=c.MapWidth,height=c.MapHeight},markerError={X=expected.X-actual.X,Y=expected.Y-actual.Y}}
 end
 local function ground(s,point)
  if ctx.mapAdapter and ctx.mapAdapter.ground then return vec(ctx.mapAdapter.ground(s,point))end
  local system=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
  local nav=StaticFindObject('/Script/NavigationSystem.Default__NavigationSystemV1')
  assert(valid(system)and valid(nav),'Terrain query APIs are unavailable.')
  local capsule=s.pawn.CapsuleComponent;assert(valid(capsule),'Player collision capsule is unavailable.')
  local radius,height=capsule:GetScaledCapsuleRadius(),capsule:GetScaledCapsuleHalfHeight()
  assert(finite(radius)and finite(height)and radius>0 and height>=radius and height<=500,'Player collision dimensions are unsupported.')
  local profile=capsule:GetCollisionProfileName();local hit={};local color={R=0,G=0,B=0,A=0}
  local blocking=system:LineTraceSingleByProfile(s.pawn,{X=point.X,Y=point.Y,Z=100000},{X=point.X,Y=point.Y,Z=-100000},profile,false,{s.pawn},0,hit,true,color,color,0)
  -- UE4SS marshals FHitResult packed booleans as the whole byte, so a blocking
  -- hit also appears "start penetrating". Positive time/distance and zero depth
  -- independently prove that this line entered the surface after its origin.
  assert(blocking==true and hit.bBlockingHit==true and finite(hit.Time)and hit.Time>0 and hit.Time<1
   and finite(hit.Distance)and hit.Distance>0 and hit.PenetrationDepth==0,'No loaded solid ground beneath this map point.')
  local floor=vec(hit.ImpactPoint);assert(finite(hit.ImpactNormal.Z)and hit.ImpactNormal.Z>=0.72,'The selected ground is too steep.')
  local navData
  for _,candidate in ipairs(FindAllOf('RecastNavMeshPlayer')or{})do if valid(candidate)then
   local world=candidate:GetWorld();if valid(world)and world:GetFullName()==s.worldId then assert(not navData,'Player navigation is ambiguous.');navData=candidate end
  end end
  assert(navData,'Player navigation is not loaded at this destination.')
  local projected={};local projectedOK=nav:K2_ProjectPointToNavigation(s.pawn,floor,projected,navData,nil,{X=radius,Y=radius,Z=64})
  assert(projectedOK==true,'No walkable player navigation near the selected surface.')
  projected=vec(projected)
  assert((projected.X-floor.X)^2+(projected.Y-floor.Y)^2<=radius^2 and math.abs(projected.Z-floor.Z)<=64,'The destination is too far from the walkable surface.')
  local target={X=projected.X,Y=projected.Y,Z=projected.Z+height+5};local obstruction={}
  local blocked=system:CapsuleTraceSingleByProfile(s.pawn,{X=target.X,Y=target.Y,Z=target.Z+2},target,radius,height,profile,false,{s.pawn},0,obstruction,true,color,color,0)
  assert(blocked==false,'The player capsule does not fit at this destination.')
  return vec(target)
 end
 local function call(fn,...)
  local ok,a,b=pcall(fn,...);if not ok then lastError=tostring(a);return false,lastError end
  lastError=nil;return a,b
 end
 function api.inspect()return call(function()return true,inspect(snapshot())end)end
 function api.preview()
  return call(function()
   local s=snapshot();local map=inspect(s);local target=ground(s,map.world)
   local caps=ctx.admin.capabilities();assert(caps.available and not caps.noclip,'Turn noclip off before map travel.')
   sequence=sequence+1;pending={token=sequence,session=session(s),point={X=map.world.X,Y=map.world.Y},target=target,time=(ctx.mapTime or os.time)()}
   return true,{token=sequence,position=vec(target),label=string.format('Travel to %.0f, %.0f',target.X,target.Y)}
  end)
 end
 function api.travel(token)
  return call(function()
   assert(ctx.mapTravelVerified==true,'Map travel has not been verified for this game build.')
   assert(pending and pending.token==token,'Preview this destination again before travelling.')
   local s=snapshot();assert(pending.session==session(s),'Campaign changed; preview the destination again.')
   local age=(ctx.mapTime or os.time)()-pending.time;assert(age>=0 and age<=30,'Destination preview expired; choose the point again.')
   local target=ground(s,pending.point)
   assert((target.X-pending.target.X)^2+(target.Y-pending.target.Y)^2+(target.Z-pending.target.Z)^2<=25,'Destination terrain changed; preview it again.')
   local ok,why=ctx.admin.action('teleport',{position=target});assert(ok,why)
   pending=nil;return true,why
  end)
 end
 function api.reset()pending=nil;return true end
 function api.status()return{verified=ctx.mapTravelVerified==true,pending=pending~=nil,error=lastError}end
 return api
end
return M
