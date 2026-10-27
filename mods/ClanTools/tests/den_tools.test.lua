local M=dofile('mods/ClanTools/Scripts/den_tools.lua')
local counter=0
local function object(t)
 counter=counter+1;t=t or{};t.id=counter
 function t:GetAddress()return self.id end;function t:GetFullName()return'Object '..self.id end;function t:GetName()return'Den decoration '..self.id end
 return t
end
local function mesh(asset)
 local m=object({StaticMesh=asset,RelativeLocation={X=10,Y=20,Z=30},RelativeRotation={Pitch=1,Yaw=2,Roll=3},RelativeScale3D={X=1,Y=2,Z=3},Mobility=0})
 function m:IsVisible()return true end
 function m:SetMobility(v)self.Mobility=v end
 function m:K2_SetRelativeLocationAndRotation(p,r)self.RelativeLocation=p;self.RelativeRotation=r end
 function m:SetRelativeScale3D(v)self.RelativeScale3D=v end
 function m:K2_DestroyComponent()self.destroyed=true;self.dead=true end
 return m
end
local function fixture()
 local f={files={},s={profile='A',slot=0,chapter=0,clan=1,offline=true},copies={}}
 f.source=mesh(object());f.actor=object({DecorationComponent=f.source,UniqueHotspotTag={TagName={ToString=function()return'Den.Test'end}}})
 f.ctx={characterKey=function(s)return s.profile..'_'..s.slot..'_'..(s.generation or'generation1')end,root='memory/',valid=function(o)return type(o)=='table'and not o.dead end,snapshot=function()return f.s end,
  denDiscover=function()if f.outside then return end;return{session='session',actors={f.actor}}end,
  denClone=function(_,source)local c=mesh(source.StaticMesh);f.copies[#f.copies+1]=c;return c end,
  read=function(p)return f.files[p]end,write=function(p,v)if f.failWrite and p=='memory/den-layouts.json'then error('disk full')end;f.files[p]=v end}
 f.api=M.new(f.ctx);assert(f.api.tick());return f
end
do
 local f=fixture();assert(f.api.begin('Den.Test'));assert(f.api.move(40,0,0));assert(f.api.apply())
 local previous=f.files['memory/den-layouts.json'];f.s.generation='new';assert(f.api.tick())
 assert(f.source.RelativeLocation.X==10,'Recreated character cannot automatically inherit another den layout')
 assert(f.files['memory/den-layouts.json']==previous,'Previous character layout remains untouched')
 f.s.generation=nil;assert(f.api.tick());assert(f.source.RelativeLocation.X==50)
 f.ctx.characterKey=function()return nil,'Missing generation'end;assert(not f.api.tick())
 assert(f.source.RelativeLocation.X==10 and f.files['memory/den-layouts.json']==previous)
 print('PASS reused slot never restores another character den layout; unavailable identity restores native placement')
end
do
 local f=fixture();assert(f.api.begin('Den.Test'));assert(f.api.move(40,0,0));assert(f.api.apply());assert(f.api.reset())
 local json=dofile('mods/ClanTools/Scripts/json.lua');local data=json.decode(f.files['memory/den-layouts.json'])
 local scoped='v2:A_0_generation1:0:1';data.layouts['A:0:0:1']=data.layouts[scoped];data.layouts[scoped]=nil
 f.files['memory/den-layouts.json']=json.encode(data);local previous=f.files['memory/den-layouts.json']
 f.api=M.new(f.ctx);assert(f.api.tick());assert(f.source.RelativeLocation.X==10 and f.files['memory/den-layouts.json']==previous)
 print('PASS ambiguous legacy den layout is preserved without automatic restoration')
end
do
 local f=fixture();assert(#f.api.status().rows==1);assert(f.api.begin('Den.Test'))
 assert(f.api.move(25,-5,10));assert(f.api.rotate(90));assert(f.source.RelativeLocation.X==35 and f.source.RelativeRotation.Yaw==92)
 assert(f.api.duplicate());assert(f.api.status().preview.selected==1);assert(#f.copies==1)
 assert(f.api.move(5,0,0));assert(f.copies[1].RelativeLocation.X==70)
 assert(f.api.cancel());assert(f.source.RelativeLocation.X==10 and f.copies[1].destroyed)
 assert(not f.source.destroyed and not f.actor.destroyed);assert(f.api.begin('Den.Test'));assert(not f.api.removeCopy())
 assert(not f.api.move(500,0,0));assert(f.source.RelativeLocation.X==10)
 print('PASS den preview move/rotate/duplicate/cancel; original actors cannot be removed; bounds enforced')
end
do
 local f=fixture();assert(f.api.begin('Den.Test'));assert(f.api.move(20,0,0));assert(f.api.duplicate());assert(f.api.apply())
 assert(f.files['memory/den-layouts.json']);assert(f.api.status().canUndo);assert(f.api.undo());assert(f.source.RelativeLocation.X==10 and f.copies[1].destroyed)
 assert(f.api.begin('Den.Test'));assert(f.api.move(40,0,0));assert(f.api.apply());assert(f.api.reset());assert(f.source.RelativeLocation.X==10 and f.source.Mobility==0)
 f.api=M.new(f.ctx);assert(f.api.tick());assert(f.source.RelativeLocation.X==50,'Restored sidecar offset once against native base')
 assert(f.api.tick());assert(f.source.RelativeLocation.X==50,'No accumulated movement on repeated tick')
 f.outside=true;assert(f.api.tick());assert(f.source.RelativeLocation.X==10 and f.source.Mobility==0)
 print('PASS apply/undo/persistent restart offsets; no repeated drift; cleanup restores native transform/mobility')
end
do
 local f=fixture();assert(f.api.begin('Den.Test'));assert(f.api.move(10,0,0));f.failWrite=true
 assert(not f.api.apply());assert(f.api.status().preview);assert(f.api.cancel());assert(f.source.RelativeLocation.X==10)
 f.failWrite=false;assert(f.api.begin('Den.Test'));assert(f.api.duplicate());assert(f.api.apply());f.s.offline=false
 assert(f.api.tick());assert(not f.api.status().active and f.copies[1].destroyed);assert(not f.api.begin('Den.Test'))
 f.s.offline=true;assert(f.api.tick());local old=f.source;old.dead=true;f.source=mesh(object());f.actor.DecorationComponent=f.source
 assert(f.api.tick());assert(f.source.RelativeLocation.X==10 and #f.api.status().rows==1,'Asset replacements do not inherit old layout')
 f.s.profile='B';assert(f.api.tick());assert(f.source.RelativeLocation.X==10)
 print('PASS save failure retains cancel; offline/world/profile boundaries; replacement mesh ignores stale sidecar')
end
do
 local f=fixture();assert(f.api.reset());f.files['memory/den-layouts.json']='corrupt';f.api=M.new(f.ctx);assert(f.api.tick())
 assert(f.api.status().error);assert(f.api.begin('Den.Test'));assert(f.api.move(10,0,0));assert(not f.api.apply());assert(f.files['memory/den-layouts.json']=='corrupt');assert(f.api.cancel())
 assert(not M.validateLayout({asset='x',kind='static',offset={x=0/0,y=0,z=0,yaw=0},copies={}}))
 print('PASS corrupt layout preserved and malformed/NaN offsets rejected')
end
do
 for _,kind in ipairs({'static','skeletal'})do
  local f=fixture();assert(f.api.reset());f.ctx.denClone=nil
  local source=f.source;local asset=source.StaticMesh;local parent=object();local material=object()
  function source:GetRelativeTransform()return{}end;function source:GetAttachParent()return parent end
  function source:GetNumMaterials()return 1 end;function source:GetMaterial()return material end
  if kind=='skeletal'then source.StaticMesh=nil;function source:GetSkeletalMeshAsset()return asset end;f.actor.DecorationSkeletalComponent=source;f.actor.DecorationComponent=nil end
  StaticFindObject=function(path)return object({path=path})end;FName=function(v)return v end
  function f.actor:AddComponentByClass(class,manual,transform,deferred)
   assert(manual and deferred==false);local c=mesh(nil);self.created=c;self.class=class.path
   function c:SetCollisionEnabled(v)self.collision=v end;function c:SetGenerateOverlapEvents(v)self.overlap=v end
   function c:K2_AttachToComponent(p)self.parent=p;return true end
   function c:SetStaticMesh(v)self.StaticMesh=v end;function c:SetSkeletalMeshAsset(v)self.skeletal=v end
   function c:SetLeaderPoseComponent(v)self.leader=v end;function c:SetMaterial(i,v)self.material=v end
   function c:SetVisibility(v)self.visible=v end;return c
  end
  f.api=M.new(f.ctx);assert(f.api.tick());assert(f.api.begin('Den.Test'));assert(f.api.duplicate())
  local c=f.actor.created;assert(c.parent==parent and c.material==material and c.collision==0 and c.overlap==false and c.visible)
  assert(kind=='static'and c.StaticMesh==asset or kind=='skeletal'and c.skeletal==asset and c.leader==source)
  assert(f.api.cancel());assert(c.destroyed and not source.destroyed)
 end
 print('PASS reflected static/skeletal clone adapter: owned attachment/materials, no collision, leader pose, cleanup')
end
do
 local f=fixture();assert(f.api.begin('Den.Test'));assert(f.api.move(40,0,0));assert(f.api.apply())
 f.source.StaticMesh=object();assert(f.api.tick());assert(f.source.RelativeLocation.X==10,'Mesh replacement in same component clears only our previous transform')
 print('PASS source mesh replacement on same component restores our prior transform before capturing new base')
end
