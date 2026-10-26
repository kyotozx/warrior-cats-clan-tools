-- Extensions for the game's own photo camera. Never pause global simulation,
-- change save progression or replace the native photo movement controls.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local json=dofile(folder..'json.lua')
local M={}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function rotation(r)return{Pitch=r.Pitch,Yaw=r.Yaw,Roll=r.Roll}end
function M.validate(p)
 if type(p)~='table'then return nil end
 if p.fov~=nil and(not finite(p.fov)or p.fov<30 or p.fov>110)then return nil end
 if not finite(p.roll)or p.roll< -30 or p.roll>30 then return nil end
 for _,k in ipairs({'hideUI','hideNames','freezeCharacters'})do if type(p[k])~='boolean'then return nil end end
 return{fov=p.fov,roll=p.roll,hideUI=p.hideUI,hideNames=p.hideNames,freezeCharacters=p.freezeCharacters}
end
function M.new(ctx)
 local valid=assert(ctx.valid);local api={};local active;local stopped=false;local lastError
 local settings={roll=0,hideUI=false,hideNames=false,freezeCharacters=false}
 local frozen,names={},{}
 local root=ctx.root or folder..'../';if not root:match('[/\\]$')then root=root..'/'end
 local path=root..'photo-settings.json'
 local function identity(o)return{object=o,address=o:GetAddress(),name=o:GetFullName()}end
 local function alive(r)return r and valid(r.object)and r.object:GetAddress()==r.address and r.object:GetFullName()==r.name end
 local function save(p)
  local raw=json.encode(p)
  if ctx.write then
   local prior=ctx.read and ctx.read(path);if prior then ctx.write(path..'.previous.txt',prior)end
   local ok,why=pcall(function()ctx.write(path,raw);if ctx.read then assert(ctx.read(path)==raw,'Photo preference readback failed.')end end)
   if not ok then if prior then pcall(ctx.write,path,prior)end;error(why)end
  end
 end
 if ctx.read then local raw=ctx.read(path);if raw then local ok,p=pcall(json.decode,raw);if ok and M.validate(p)then settings=M.validate(p)else lastError='Invalid photo settings; defaults are in use.'end end end
 local function discover(s)
  if ctx.photoDiscover then return ctx.photoDiscover(s)end
  local found
  for _,p in ipairs(FindAllOf('GuiPopupPhotoModeWrc')or{})do
   if valid(p)and p:IsInViewport()and valid(p.CameraActor)and valid(p.CameraActor.CameraComponent)then
    if found then return nil end;found={popup=p,camera=p.CameraActor,lens=p.CameraActor.CameraComponent}
   end
  end
  return found
 end
 local function restoreMap(map,fn)
  local failed
  for id,r in pairs(map)do
   local ok,why=pcall(function()if alive(r)then fn(r)end end)
   if ok then map[id]=nil else failed=tostring(why)end
  end
  return not failed,failed
 end
 local function thaw()
  return restoreMap(frozen,function(r)
   r.object.CustomTimeDilation=r.dilation
   if alive(r.movement)then r.movement.object:SetComponentTickEnabled(r.movement.tick)end
   if alive(r.mesh)then r.mesh.object.GlobalAnimRateScale=r.mesh.rate end
  end)
 end
 local function showNames()return restoreMap(names,function(r)r.object:SetRenderOpacity(r.opacity)end)end
 function api.reset()
  ctx.photoHideNames=false;ctx.photoHideUI=false
  local ok,err=thaw();local namesOK,namesError=showNames()
  if not ok or not namesOK then lastError=err or namesError;return false,lastError end
  if active then
   local good,why=pcall(function()
    if alive(active.lens)then
     if active.fovApplied then active.lens.object:SetFieldOfView(active.fov)end
     if active.rollApplied then local r=rotation(active.lens.object.RelativeRotation);r.Roll=active.rotation.Roll;active.lens.object:K2_SetRelativeRotation(r,false,{},true)end
    end
    if alive(active.popup)then active.popup.object:SetRenderOpacity(active.opacity)end
   end)
   if not good then lastError=tostring(why);return false,lastError end
  end
  active=nil;return true
 end
 local function sameWorld(a,s)
  local level=a:GetLevel();local playerLevel=s.pawn:GetLevel()
  return valid(level)and valid(playerLevel)and valid(level.OwningWorld)and valid(playerLevel.OwningWorld)
   and level.OwningWorld:GetAddress()==playerLevel.OwningWorld:GetAddress()
 end
 local function freeze(s)
  local list=ctx.photoCharacters and ctx.photoCharacters(s)or(FindAllOf('SwtAdventureCharacter')or{})
  local count=0
  for _,a in ipairs(list)do
   if valid(a)and(ctx.photoCharacters or sameWorld(a,s))then
    count=count+1;if count>256 then error('Too many characters for photo freeze.')end
    local id=a:GetAddress();local r=frozen[id]
    if not r then
     r=identity(a);r.dilation=a.CustomTimeDilation;assert(finite(r.dilation),'Character timing unavailable.')
     local movement=a.CharacterMovement
     if valid(movement)then r.movement=identity(movement);r.movement.tick=movement:IsComponentTickEnabled()end
     local mesh=a.Mesh
     if valid(mesh)then r.mesh=identity(mesh);r.mesh.rate=mesh.GlobalAnimRateScale;assert(finite(r.mesh.rate),'Animation timing unavailable.')end
     frozen[id]=r
    end
    if alive(r)then
     a.CustomTimeDilation=0
     if alive(r.movement)then r.movement.object:StopMovementImmediately();r.movement.object:SetComponentTickEnabled(false)end
     if alive(r.mesh)then r.mesh.object.GlobalAnimRateScale=0 end
    end
   end
  end
 end
 local function hideNames(s)
  local list=ctx.photoNameWidgets and ctx.photoNameWidgets(s)or(FindAllOf('GuiQuestActorName')or{})
  for i,w in ipairs(list)do
   if i>512 then error('Too many name widgets for photo mode.')end
   if valid(w)then
    local id=w:GetAddress();local r=names[id]
    if not r then r=identity(w);r.opacity=w:GetRenderOpacity();names[id]=r end
    if alive(r)then w:SetRenderOpacity(0)end
   end
  end
 end
 function api.tick(s)
  if stopped then return end
  local ok,why=pcall(function()
   if settings.fov==nil and settings.roll==0 and not settings.hideUI and not settings.hideNames and not settings.freezeCharacters then
    assert(api.reset());return
   end
   s=s or ctx.snapshot()
   if not s or not s.offline or s.combat or ctx.appearanceActive then assert(api.reset());return end
   local p=discover(s)
   if not p then assert(api.reset());return end
   local key=table.concat({s.profile,tostring(s.slot),s.worldId,tostring(p.camera:GetAddress()),tostring(p.popup:GetAddress())},':')
   if not active or active.key~=key then
    assert(api.reset());active={key=key,lens=identity(p.lens),popup=identity(p.popup),fov=p.lens.FieldOfView,
     rotation=rotation(p.lens.RelativeRotation),opacity=p.popup:GetRenderOpacity()}
    assert(finite(active.fov)and finite(active.rotation.Roll),'Native photo camera state unavailable.')
   end
   assert(alive(active.lens)and alive(active.popup),'Native photo camera changed.')
   if settings.fov then active.fovApplied=true;p.lens:SetFieldOfView(settings.fov)
   elseif active.fovApplied then p.lens:SetFieldOfView(active.fov);active.fovApplied=false end
   if settings.roll~=0 or active.rollApplied then
    local r=rotation(p.lens.RelativeRotation);r.Roll=active.rotation.Roll+settings.roll;active.rollApplied=true;p.lens:K2_SetRelativeRotation(r,false,{},true);active.rollApplied=settings.roll~=0
   end
   p.popup:SetRenderOpacity(settings.hideUI and 0 or active.opacity)
   ctx.photoHideNames=settings.hideNames;ctx.photoHideUI=settings.hideUI
   if settings.hideNames then hideNames(s)else assert(showNames())end
   if settings.freezeCharacters then freeze(s)else assert(thaw())end
  end)
  if not ok then lastError=tostring(why);api.reset();return false,lastError end
  lastError=nil;return true
 end
 function api.configure(name,value)
  local p={};for k,v in pairs(settings)do p[k]=v end;p[name]=value
  if name~='fov'and name~='roll'and name~='hideUI'and name~='hideNames'and name~='freezeCharacters'then return nil,'Unknown photo setting.'end
  p=M.validate(p);if not p then return nil,'Invalid photo setting.'end
  local ok,why=pcall(save,p);if not ok then return nil,tostring(why)end;settings=p;return true
 end
 function api.defaults()
  local p={roll=0,hideUI=false,hideNames=false,freezeCharacters=false}
  local ok,why=pcall(save,p);if not ok then return nil,tostring(why)end;settings=p;return api.reset()
 end
 function api.status()
  local p={};for k,v in pairs(settings)do p[k]=v end;local count=0;for _ in pairs(frozen)do count=count+1 end
  return{active=active~=nil,settings=p,frozen=count,error=lastError,scope='Applies only while the original photo mode is open.'}
 end
 function api.shutdown()local ok,why=api.reset();if ok then stopped=true end;return ok,why end
 return api
end
return M
