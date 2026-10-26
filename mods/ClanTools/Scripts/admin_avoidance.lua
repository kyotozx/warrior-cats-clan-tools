-- Temporarily suppress ordinary roaming enemy detection/encounter queries.
-- Never destroys or replaces actors. Run only on the game thread.
local dir=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local nativeValid=dofile(dir..'runtime_valid.lua').valid
local M={}
local className='BlueprintGeneratedClass /Game/Gameplay/Blueprints/Characters/ExplorationCharacters/BP_Exploration_Character_Base.BP_Exploration_Character_Base_C'
local worldName='World /Game/Art/Maps/Gameplay/L_WorldMap_01_P.L_WorldMap_01_P'
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function position(v)
 local p={X=v.X,Y=v.Y,Z=v.Z};for _,k in ipairs({'X','Y','Z'})do assert(finite(p[k])and math.abs(p[k])<=1000000,'Invalid enemy position.')end;return p
end
local function separated(a,b,r)return(a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2>r*r end
function M.new(ctx)
 assert(ctx and ctx.snapshot,'Enemy avoidance requires the active game context.')
 local api={};local enabled,closed=false,false;local records={};local session,lastError
 local adapter=ctx.avoidanceAdapter or{}
 local valid=ctx.valid or nativeValid
 local function id(o)return o:GetAddress()end
 local function context(s)
  s=s or ctx.snapshot()
  if not s or s.offline~=true or s.phase~=4 or s.combat or not valid(s.pawn)or not valid(s.pc)or not valid(s.pc.Pawn)or id(s.pc.Pawn)~=id(s.pawn)then return nil end
  if not adapter.validate_world and s.worldId~=worldName then return nil end
  if adapter.validate_world and not adapter.validate_world(s)then return nil end
  return s
 end
 local function supported(actor,s)
  if not valid(actor)or id(actor)==id(s.pawn)then return false end
  if adapter.supported then return adapter.supported(actor,s)==true end
  local class=actor:GetClass();if not valid(class)or class:GetFullName()~=className then return false end
  local level=actor:GetLevel();return valid(level)and level.bIsVisible==true and valid(level.OwningWorld)and level.OwningWorld:GetFullName()==s.worldId
 end
 local function components(actor)
  if adapter.components then return adapter.components(actor)end
  local detection=actor.BP_Exploration_DetectionComponent
  local encounter=actor.ExplorationEncounterCollision
  assert(valid(detection)and valid(encounter),'Roaming enemy components are unavailable.')
  return{{object=detection,radius=detection:GetScaledSphereRadius()},
   {object=encounter,radius=encounter:GetScaledCapsuleHalfHeight()+encounter:GetScaledCapsuleRadius()}}
 end
 local function collisionMode(component)
  -- GetCollisionEnabled reports effective collision, which becomes zero when
  -- the game disables the whole distant actor. Preserve the component's own
  -- setting so it restores correctly when that actor becomes active again.
  local value=component.BodyInstance.CollisionEnabled
  assert(type(value)=='number'and value%1==0 and value>=0 and value<=5,'Unknown enemy collision mode.')
  return value
 end
 local function read(actor,s)
  local record={actor=actor,actorId=id(actor),world=s.worldId,components={}}
  for _,entry in ipairs(components(actor))do
   local c=entry.object
   assert(valid(c),'Invalid enemy query component.')
   local collision=collisionMode(c)
   assert(type(collision)=='number'and collision%1==0 and collision>=0 and collision<=5,'Unknown enemy collision mode.')
   assert(finite(entry.radius)and entry.radius>=0 and entry.radius<=100000,'Invalid enemy query radius.')
   record.components[#record.components+1]={object=c,objectId=id(c),collision=collision,radius=entry.radius+200}
  end
  assert(#record.components==2,'Expected the two roaming enemy query components.')
  return record
 end
 local function disable(record)
  for _,c in ipairs(record.components)do
   assert(valid(c.object)and id(c.object)==c.objectId,'Enemy query component changed.')
   if collisionMode(c.object)~=0 then c.object:SetCollisionEnabled(0)end
   -- UE's setter early-outs when the actor's effective collision is already
   -- disabled. Its body still needs NoCollision before the actor wakes up.
   if collisionMode(c.object)~=0 and record.actor:GetActorEnableCollision()==false and c.object:GetCollisionEnabled()==0 then
    c.object.BodyInstance.CollisionEnabled=0
   end
   assert(collisionMode(c.object)==0,'Enemy query collision did not disable.')
  end
 end
 local function safeRestore(record,s)
  if not valid(record.actor)or id(record.actor)~=record.actorId then return true end
  -- Restore only in positively identified exploration; turning queries back
  -- on during a battle/possession transition can synchronously start combat.
  if not s or s.worldId~=record.world then return false end
  local player=position(s.pawn:K2_GetActorLocation())
  for _,c in ipairs(record.components)do
   if valid(c.object)and id(c.object)==c.objectId and c.collision~=0 then
    local center=position(c.object:K2_GetComponentLocation())
    if not separated(player,center,c.radius)then return false end
   end
  end
  return true
 end
 local function restore(s)
  local survivors={};local failure
  for _,r in ipairs(records)do
   local ok,complete=pcall(function()
    if not safeRestore(r,s)then return false end
    if not valid(r.actor)or id(r.actor)~=r.actorId then return true end
    for _,c in ipairs(r.components)do if valid(c.object)and id(c.object)==c.objectId then
     c.object:SetCollisionEnabled(c.collision)
     assert(collisionMode(c.object)==c.collision,'Enemy query collision did not restore.')
    end end
    return true
   end)
   if not ok or not complete then survivors[#survivors+1]=r end
   if not ok then failure=tostring(complete)end
  end
  records=survivors;lastError=failure
  return not failure,failure
 end
 local function apply(s)
  local owned={};local alive={}
  for _,r in ipairs(records)do if valid(r.actor)and id(r.actor)==r.actorId then
   owned[r.actorId]=true;alive[#alive+1]=r
  end end;records=alive
  local list=adapter.actors and adapter.actors(s)or FindAllOf('BP_Exploration_Character_Base_C')or{}
  assert(#list<=512,'Too many roaming enemies to safely inspect.')
  for _,actor in ipairs(list)do if supported(actor,s)and not owned[id(actor)]then
   local record=read(actor,s)
   -- Retain restoration before the first mutation, including partial failure.
   records[#records+1]=record;owned[record.actorId]=true
  end end
  for _,r in ipairs(records)do disable(r)end
 end
 function api.set_enabled(value)
  if closed then return false,'Enemy avoidance is shut down.'end
  if type(value)~='boolean'then return false,'Enabled must be true or false.'end
  if not value then
   enabled=false;local ok,why=restore(context())
   return ok,why or(#records>0 and'Restoring when clear. Move away from nearby enemies.'or'Enemy detection restored.')
  end
  if ctx.avoidanceVerified~=true then return false,'Enemy avoidance has not been verified for this game build.'end
  local s=context();if not s then return false,'Enemy avoidance requires possessed offline exploration.'end
  if #records>0 and not enabled then return false,'Wait for enemy detection to restore before enabling it again.'end
  local nextSession=table.concat({s.worldId,s.profile or'',tostring(s.slot),tostring(id(s.pawn))},'|')
  if session and session~=nextSession and #records>0 then return false,'Waiting for the previous exploration session to restore.'end
  session=nextSession;enabled=true
  local ok,why=pcall(apply,s)
  if not ok then enabled=false;restore(s);lastError=tostring(why);return false,lastError end
  lastError=nil;return true,'Roaming enemy detection and proximity encounters disabled.'
 end
 function api.tick()
  if closed then return false,'Enemy avoidance is shut down.'end
  if not enabled and #records==0 then session=nil;return true end
  local s=context()
  local token=s and table.concat({s.worldId,s.profile or'',tostring(s.slot),tostring(id(s.pawn))},'|')
  if enabled and token~=session then enabled=false end
  if not enabled then
   local ok,why=restore(s);if #records==0 then session=nil end;return ok,why
  end
  local ok,why=pcall(apply,s)
  if not ok then enabled=false;restore(s);lastError=tostring(why);return false,lastError end
  lastError=nil;return true
 end
 function api.reset()return api.set_enabled(false)end
 function api.status()
  return{enabled=enabled,restoring=not enabled and #records>0,count=#records,error=lastError,
   available=not closed and ctx.avoidanceVerified==true and context()~=nil,
   message=lastError or(not enabled and #records>0 and'Restoring when clear' or enabled and'Ordinary roaming enemies only; scripted story battles are unchanged.'or'Enemy detection is normal.')}
 end
 function api.shutdown()
  enabled=false;local ok,why=restore(context())
  if not ok or #records>0 then return false,why or'Move away from nearby enemies and finish the active transition before disabling enemy avoidance.'end
  closed=true;return true
 end
 return api
end
return M
