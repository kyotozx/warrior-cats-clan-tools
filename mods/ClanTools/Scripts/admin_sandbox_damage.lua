-- Native OnRegisterDamage queues an FSwtAdventureReceiveDamageStruct before
-- resolution (exact-build exec RVA1716CA0). Change only player-to-enemy hits.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local valid=dofile(folder..'runtime_valid.lua').valid
local M={}
function M.scale(damage,multiplier,oneHit)
 assert(type(damage)=='number'and damage%1==0 and damage>=0 and damage<=1000000,'Invalid native damage.')
 assert(type(multiplier)=='number'and multiplier>=1 and multiplier<=100,'Invalid damage multiplier.')
 if damage==0 then return 0 end
 return oneHit and 1000000 or math.min(1000000,math.floor(damage*multiplier+.5))
end
function M.new(ctx,options)
 options=options or{};local multiplier,oneHit,session,closed=1,false,nil,false
 local path='/Script/SwtAdventure.SwtAdventureCombatDirector:OnRegisterDamage'
 local pre,post;local api={error=nil}
 local function identity(s)return table.concat({s.profile,tostring(s.slot),tostring(s.chapter),s.worldId},'|')end
 local function snapshot()
  local s=assert(ctx.snapshot(),'Load an offline campaign first.')
  assert(s.offline==true and s.phase==4 and s.profile and s.slot~=nil and s.chapter~=nil and s.worldId,'Combat cheats require an offline campaign.')
  return s
 end
 local function reset()multiplier=1;oneHit=false;session=nil end
 local function contains(list,actor)
  if not valid(actor)then return false end
  local found=false
  list:ForEach(function(_,v)local component=v:get();if valid(component)then local owner=component:GetOwner();if valid(owner)and owner:GetAddress()==actor:GetAddress()then found=true end end end)
  return found
 end
 local function hit(object,argument)
  if closed or(multiplier==1 and not oneHit)then return end
  local ok,why=pcall(function()
   local s=snapshot();if identity(s)~=session then reset();return end
   if not s.combat or not valid(s.gameState)then return end
   local director=object:get();if not valid(director)or not valid(s.gameState.Director)or director:GetAddress()~=s.gameState.Director:GetAddress()then return end
   local data=argument:get();local target=data.Character
   if not contains(director.PlayerParty,director.CurrentTurnAttackCharacter)or not contains(director.EnemyParty,target)or contains(director.PlayerParty,target)then return end
   if data.bMissed or data.Damage<=0 then return end
   data.Damage=M.scale(data.Damage,multiplier,oneHit)
  end)
  if not ok then reset();api.error=tostring(why);if ctx.log then ctx.log('Combat damage override disabled: '..api.error)end end
 end
 local function prepare()
  assert(not closed and options.verified==true,'Damage overrides have not been verified for this game build.')
  local s=snapshot()
  if not pre then pre,post=(options.register or RegisterHook)(path,hit);assert(pre and post,'Could not register the damage handler.')end
  session=identity(s);api.error=nil
 end
 function api.set_multiplier(value)
  if type(value)~='number'or value%1~=0 or value<1 or value>100 then return false,'Choose a damage multiplier from 1 to 100.'end
  if value==1 then multiplier=1;api.error=nil;if not oneHit then session=nil end;return true,'Player damage multiplier: 1x.'end
  local ok,why=pcall(function()prepare();multiplier=value end)
  return ok,ok and('Player damage multiplier: '..value..'x.')or tostring(why)
 end
 function api.set_one_hit(value)
  if type(value)~='boolean'then return false,'One-hit victory must be on or off.'end
  if not value then oneHit=false;api.error=nil;if multiplier==1 then session=nil end;return true,'One-hit victory disabled.'end
  local ok,why=pcall(function()prepare();oneHit=value end)
  return ok,ok and(value and'One-hit victory enabled for successful player attacks.'or'One-hit victory disabled.')or tostring(why)
 end
 function api.tick()
  if session then local ok,s=pcall(snapshot);if not ok or identity(s)~=session then reset()end end
  return true
 end
 function api.state()return{multiplier=multiplier,one_hit=oneHit,error=api.error}end
 function api.shutdown()
  reset();closed=true
  if pre then local ok,why=pcall(options.unregister or UnregisterHook,path,pre,post);if not ok then return false,tostring(why)end;pre,post=nil,nil end
  return true
 end
 return api
end
return M
