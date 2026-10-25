-- Transactional den layout sidecar. Original hotspot actors and saves are never edited.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local json=dofile(folder..'json.lua')
local crafting=dofile(folder..'crafting.lua')
local M={}
local function copy(v)if type(v)~='table'then return v end;local r={};for k,x in pairs(v)do r[k]=copy(x)end;return r end
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function offset()return{x=0,y=0,z=0,yaw=0}end
local function validOffset(v)
 return type(v)=='table'and finite(v.x)and finite(v.y)and finite(v.z)and finite(v.yaw)
  and math.abs(v.x)<=250 and math.abs(v.y)<=250 and math.abs(v.z)<=150 and math.abs(v.yaw)<=360
end
function M.validateLayout(v)
 if type(v)~='table'or type(v.asset)~='string'or #v.asset>1024 or(v.kind~='static'and v.kind~='skeletal')or not validOffset(v.offset)or type(v.copies)~='table'or #v.copies>16 then return false end
 for k,o in pairs(v.copies)do if type(k)~='number'or k%1~=0 or k<1 or k>#v.copies or not validOffset(o)then return false end end
 return true
end
function M.new(ctx)
 local valid=assert(ctx.valid);local api={};local records={};local session,scope,preview,lastError;local stopped=false
 local history={};local database={version=1,layouts={}};local broken=false
 local root=ctx.root or folder..'../';if not root:match('[/\\]$')then root=root..'/'end
 local path=root..'den-layouts.json'
 local function id(o)return{object=o,address=o:GetAddress(),name=o:GetFullName()}end
 local function alive(r)return r and valid(r.object)and r.object:GetAddress()==r.address and r.object:GetFullName()==r.name end
 local function assetOf(component,kind)return kind=='static'and component.StaticMesh or component:GetSkeletalMeshAsset()end
 local function sourceAlive(r)
  if not alive(r.component)or not alive(r.actor)then return false end
  local mesh=assetOf(r.component.object,r.kind);return valid(mesh)and mesh:GetFullName()==r.asset
 end
 local function empty(r)return{asset=r.asset,kind=r.kind,offset=offset(),copies={}}end
 local function saved(r)local t=database.layouts[scope];local v=t and t[r.tag];if v and v.asset==r.asset and v.kind==r.kind then return copy(v)end;return empty(r)end
 local function store(nextDatabase)
  assert(not broken,'Invalid den layout file; preserve it before saving new layouts.')
  assert(ctx.write and ctx.read,'Den layout storage is unavailable.')
  local raw=json.encode(nextDatabase);local prior=ctx.read(path)
  if prior then ctx.write(path..'.previous.txt',prior)end
  local ok,why=pcall(function()ctx.write(path,raw);assert(ctx.read(path)==raw,'Den layout readback failed.')end)
  if not ok then if prior then pcall(ctx.write,path,prior)end;error(why)end
  database=nextDatabase
 end
 if ctx.read then
  local raw=ctx.read(path)
  if raw then
   local ok,value=pcall(json.decode,raw)
   if ok and type(value)=='table'and value.version==1 and type(value.layouts)=='table'then
    local count=0
    for key,entries in pairs(value.layouts)do
     if type(key)~='string'or type(entries)~='table'then ok=false;break end
     for tag,layout in pairs(entries)do count=count+1;if type(tag)~='string'or not M.validateLayout(layout)or count>2048 then ok=false;break end end
     if not ok then break end
    end
   else ok=false end
   if ok then database=value else broken=true;lastError='Invalid saved den layouts; automatic restoration is disabled.'end
  end
 end
 local function destroyClone(r,c)
  if alive(c)then c.object:K2_DestroyComponent(r.actor.object)end
 end
 local function clearCopies(r)
  for i=#r.clones,1,-1 do destroyClone(r,r.clones[i]);table.remove(r.clones,i)end
 end
 local function setTransform(r,component,o)
  component:SetMobility(2)
  component:K2_SetRelativeLocationAndRotation({X=r.location.X+o.x,Y=r.location.Y+o.y,Z=r.location.Z+o.z},
   {Pitch=r.rotation.Pitch,Yaw=r.rotation.Yaw+o.yaw,Roll=r.rotation.Roll},false,{},true)
  component:SetRelativeScale3D(copy(r.scale))
 end
 local function sameApplied(r)
  if not r.applied or not alive(r.component)then return false end
  local c=r.component.object;local p,q=c.RelativeLocation,c.RelativeRotation;local a=r.applied
  return p.X==a.x and p.Y==a.y and p.Z==a.z and q.Pitch==r.rotation.Pitch and q.Yaw==a.yaw and q.Roll==r.rotation.Roll
 end
 local function createClone(r)
  local source=r.component.object;local actor=r.actor.object
  if ctx.denClone then return ctx.denClone(actor,source,r.kind)end
  local class=StaticFindObject('/Script/Engine.'..(r.kind=='static'and'StaticMeshComponent'or'SkeletalMeshComponent'))
  assert(valid(class),'Decoration mesh class is unavailable.')
  local clone=actor:AddComponentByClass(class,true,source:GetRelativeTransform(),false)
  assert(valid(clone),'Could not create a decoration copy.')
  local owned=id(clone);r.clones[#r.clones+1]=owned -- Own cleanup before any subsequent engine call.
  clone:SetMobility(2);clone:SetCollisionEnabled(0);clone:SetGenerateOverlapEvents(false)
  local parent=source:GetAttachParent();assert(valid(parent),'Decoration has no valid attachment parent.')
  assert(clone:K2_AttachToComponent(parent,FName('None'),0,0,0,false)~=false,'Could not attach the decoration copy.')
  if r.kind=='static'then assert(clone:SetStaticMesh(assetOf(source,r.kind))~=false,'Could not copy the decoration mesh.')else
   clone:SetSkeletalMeshAsset(assetOf(source,r.kind));clone:SetLeaderPoseComponent(source,true,false)
  end
  local n=source:GetNumMaterials();assert(type(n)=='number'and n>=0 and n<=64,'Unexpected decoration material count.')
  for i=0,n-1 do local material=source:GetMaterial(i);if valid(material)then clone:SetMaterial(i,material)end end
  clone:SetVisibility(true,false);return clone,owned
 end
 local function render(r,layout)
  assert(sourceAlive(r),'The selected decoration was replaced or unloaded.')
  local total=#layout.copies;for _,other in pairs(records)do if other~=r then total=total+#other.clones end end
  assert(total<=64,'The den copy limit has been reached.')
  for _,c in ipairs(r.clones)do if not alive(c)then clearCopies(r);break end end
  setTransform(r,r.component.object,layout.offset)
  r.applied={x=r.location.X+layout.offset.x,y=r.location.Y+layout.offset.y,z=r.location.Z+layout.offset.z,yaw=r.rotation.Yaw+layout.offset.yaw}
  if layout.offset.x==0 and layout.offset.y==0 and layout.offset.z==0 and layout.offset.yaw==0 then r.component.object:SetMobility(r.mobility)end
  for i=#r.clones,#layout.copies+1,-1 do destroyClone(r,r.clones[i]);table.remove(r.clones,i)end
  for i,o in ipairs(layout.copies)do
   local c=r.clones[i]
   if not alive(c)then
    local object,owned=createClone(r);c=owned or id(object)
    if not owned then r.clones[i]=c end
   end
   setTransform(r,c.object,o)
  end
 end
 local function restore(r)
  clearCopies(r)
  if sourceAlive(r)or sameApplied(r)then setTransform(r,r.component.object,offset());r.component.object:SetMobility(r.mobility)end
 end
 function api.reset()
  local failed
  for tag,r in pairs(records)do local ok,why=pcall(restore,r);if ok then records[tag]=nil else failed=tostring(why)end end
  preview=nil
  if failed then lastError=failed;return false,failed end
  session=nil;scope=nil;history={};return true
 end
 local function snapshot()return ctx.snapshot and ctx.snapshot()end
 local function discover(s)
  if not s or not s.offline or s.combat or ctx.appearanceActive then return nil end
  if ctx.denDiscover then return ctx.denDiscover(s)end;return crafting.discover(s)
 end
 local function scopeKey(s)return table.concat({tostring(s.profile),tostring(s.slot),tostring(s.chapter),tostring(s.clan)},':')end
 local function scan(s)
  local c=discover(s)
  if not c then assert(api.reset());return false end
  local nextScope=scopeKey(s)
  if session~=c.session or scope~=nextScope then assert(api.reset());session=c.session;scope=nextScope end
  local seen={}
  for _,actor in ipairs(c.actors or{})do
   if valid(actor)then
    local tag=actor.UniqueHotspotTag.TagName:ToString()
    local component,kind=actor.DecorationComponent,'static'
    if not valid(component)or not valid(component.StaticMesh)or not component:IsVisible()then component=actor.DecorationSkeletalComponent;kind='skeletal'end
    if tag~=''and tag~='None'and valid(component)and component:IsVisible()then
     local asset=assetOf(component,kind)
     if valid(asset)then
      assert(not seen[tag],'Duplicate den hotspot tags are ambiguous.');seen[tag]=true
      local r=records[tag]
      if r and(not sourceAlive(r)or r.component.address~=component:GetAddress())then restore(r);records[tag]=nil;r=nil;if preview and preview.tag==tag then preview=nil end end
      if not r then
       local p,q,z=component.RelativeLocation,component.RelativeRotation,component.RelativeScale3D
       local fullName=asset:GetFullName()
       r={tag=tag,actor=id(actor),component=id(component),kind=kind,asset=fullName,name=fullName:match('([^%.: /]+)$')or fullName,
        location={X=p.X,Y=p.Y,Z=p.Z},rotation={Pitch=q.Pitch,Yaw=q.Yaw,Roll=q.Roll},scale={X=z.X,Y=z.Y,Z=z.Z},mobility=component.Mobility,clones={}}
       records[tag]=r
       local layout=saved(r)
       if not broken and(layout.offset.x~=0 or layout.offset.y~=0 or layout.offset.z~=0 or layout.offset.yaw~=0 or #layout.copies>0)then render(r,layout)end
      end
     end
    end
   end
  end
  for tag,r in pairs(records)do if not seen[tag]then restore(r);records[tag]=nil;if preview and preview.tag==tag then preview=nil end end end
  return true
 end
 function api.tick(s)
  if stopped then return false,'Den tools are stopped.'end
  local ok,why=pcall(scan,s or snapshot());if not ok then lastError=tostring(why);api.reset();return false,lastError end
  return true
 end
 local function run(fn)
  if stopped then return false,'Den tools are stopped.'end
  local ok,result=pcall(function()assert(scan(snapshot()),'Enter your clan den while offline.');return fn()end)
  if not ok then lastError=tostring(result);return false,lastError end;lastError=nil;return true,result
 end
 function api.begin(tag)
  return run(function()
   assert(not preview,'Apply or cancel the current preview first.')
   local r=assert(records[tag],'Select a completed den decoration.')
   preview={tag=tag,layout=saved(r),before=saved(r),selected=0};return'Selected '..r.name
  end)
 end
 function api.selectCopy(index)
  return run(function()assert(preview,'Select a decoration first.');assert(type(index)=='number'and index%1==0 and index>=0 and index<=#preview.layout.copies,'Choose the original or an existing copy.');preview.selected=index end)
 end
 local function edit(fn)
  return run(function()
   assert(preview,'Select a decoration first.');local r=assert(records[preview.tag]);local old=copy(preview.layout);local selected=preview.selected
   local ok,why=pcall(function()fn(preview.layout);assert(M.validateLayout(preview.layout),'Keep movement within 250 cm horizontally and 150 cm vertically.');render(r,preview.layout)end)
   if not ok then preview.layout=old;preview.selected=selected;pcall(render,r,old);error(why)end
  end)
 end
 function api.move(x,y,z)
  return edit(function(l)assert(finite(x)and finite(y)and finite(z),'Invalid movement.');local o=preview.selected==0 and l.offset or l.copies[preview.selected];o.x=o.x+x;o.y=o.y+y;o.z=o.z+z end)
 end
 function api.rotate(degrees)
  return edit(function(l)assert(finite(degrees),'Invalid rotation.');local o=preview.selected==0 and l.offset or l.copies[preview.selected];o.yaw=(o.yaw+degrees+180)%360-180 end)
 end
 function api.duplicate()
  return edit(function(l)
   local total=0;for _,r in pairs(records)do total=total+#r.clones end
   assert(#l.copies<16 and total<64,'The den copy limit has been reached.')
   local o=copy(preview.selected==0 and l.offset or l.copies[preview.selected]);o.x=math.min(250,o.x+30)
   l.copies[#l.copies+1]=o;preview.selected=#l.copies
  end)
 end
 function api.removeCopy()
  return edit(function(l)assert(preview.selected>0,'Only copies made by Clan Tools can be removed.');table.remove(l.copies,preview.selected);preview.selected=0 end)
 end
 function api.restoreLayout()
  return edit(function(l)l.offset=offset();l.copies={};preview.selected=0 end)
 end
 function api.cancel()
  return run(function()assert(preview,'No decoration preview is open.');render(assert(records[preview.tag]),preview.before);preview=nil end)
 end
 function api.apply()
  return run(function()
   assert(preview,'No decoration preview is open.');assert(sourceAlive(assert(records[preview.tag])),'The decoration changed.')
   local nextDatabase=copy(database);nextDatabase.layouts[scope]=nextDatabase.layouts[scope]or{};nextDatabase.layouts[scope][preview.tag]=copy(preview.layout)
   store(nextDatabase);history[#history+1]={tag=preview.tag,before=copy(preview.before)};if #history>20 then table.remove(history,1)end;preview=nil
  end)
 end
 function api.undo()
  return run(function()
   assert(not preview,'Apply or cancel the current preview first.');local h=assert(history[#history],'There is no applied layout to undo.');local r=assert(records[h.tag],'That decoration is no longer available.');assert(r.asset==h.before.asset,'That decoration was replaced.')
   local old=saved(r);render(r,h.before);local nextDatabase=copy(database);nextDatabase.layouts[scope][h.tag]=copy(h.before)
   local ok,why=pcall(store,nextDatabase);if not ok then render(r,old);error(why)end;table.remove(history)
  end)
 end
 function api.status()
  local rows={};for tag,r in pairs(records)do rows[#rows+1]={tag=tag,name=r.name,kind=r.kind,copies=#r.clones}end;table.sort(rows,function(a,b)return a.tag<b.tag end)
  return{active=session~=nil,rows=rows,preview=copy(preview),canUndo=#history>0,error=lastError,scope='Layout changes are stored by Clan Tools. Copies have no collision.'}
 end
 function api.shutdown()local ok,why=api.reset();if ok then stopped=true end;return ok,why end
 return api
end
return M
