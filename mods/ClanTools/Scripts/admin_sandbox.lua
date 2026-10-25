-- Offline progression and temporary resource helpers. Permanent XP changes use
-- a one-shot preview, backup, session revalidation and native game setters.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local valid=dofile(folder..'runtime_valid.lua').valid
local M={}
local function addr(o)assert(valid(o),'Object is no longer available.');return o:GetAddress()end
local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
function M.nativeAdapter(ctx,options)
 options=options or{};local bin=options.bin or ctx.root..'bin/'
 local run=assert(package.loadlib(bin..(options.library or'admin-sandbox.dll'),'ClanSandbox_run'));local nonce=0
 local function invoke(command,component,owner,manager,expected,level,amount,tagIndex)
  assert(same(component:GetOwner(),owner),'Resource owner changed.')
  nonce=nonce+1
  local f=assert(io.open(bin..'admin-sandbox-request.txt','wb'))
  assert(f:write(string.format('%d %s %x %x %x %x %.9g %d %.9g %d\n',nonce,command,addr(component),addr(owner),addr(component:GetClass()),manager and addr(manager)or 0,expected or 0,level or 0,amount or 0,tagIndex or 0)));f:close();run()
  f=assert(io.open(bin..'admin-sandbox-status.txt','rb'));local text=f:read('*a');f:close()
  local r={};for k,v in text:gmatch('([%w_]+)=([^\r\n]+)')do r[k]=v end
  assert(tonumber(r.nonce)==nonce,'Stale sandbox response.')
  assert(r.status==(command:find('PROBE',1,true)and'READY'or'APPLIED'),r.status or'Missing sandbox response.')
  for _,k in ipairs({'current','maximum','after','level','max_level','after_level','stat0','stat1','stat2','stat3','stat4','stat5'})do r[k]=assert(tonumber(r[k]),'Malformed sandbox response.')end
  r.moves={};for index,number in text:gmatch('move=(%d+) (%d+)')do if number=='0'then r.moves[tonumber(index)]=true end end
  return r
 end
 local function level(s)
  local pc=assert(s.pc,'Player controller unavailable.');addr(pc)
  local state=pc.PlayerState;addr(state);local component=state.LevelComponent;addr(component)
  local class=StaticFindObject('/Script/SwtAdventure.SwtAdventureLevelComponent');assert(same(component:GetClass(),class),'Unsupported level component.')
  return component,state,FindFirstOf('WrcSaveManager')
 end
 local adapter={}
 function adapter.probeXP(s)local c,o,m=level(s);return invoke('XP_PROBE',c,o,m)end
 function adapter.addXP(s,amount,preview)local c,o,m=level(s);return invoke('XP_ADD',c,o,m,preview.current,preview.level,amount)end
 function adapter.setStat(s,index,value,preview)local c,o,m=level(s);return invoke('STAT_SET',c,o,m,preview.before,preview.level,value,index)end
 local function health(s)
  local pawn=s.pawn;addr(pawn);local class=StaticFindObject('/Script/SwtQuest.SwtQuestHealthComponent');addr(class)
  local c=pawn:GetComponentByClass(class);addr(c);assert(same(c:GetClass(),class),'Unsupported health component.');return c,pawn
 end
 function adapter.probeHealth(s)local c,o=health(s);return invoke('HEALTH_PROBE',c,o)end
 function adapter.setHealthMaximum(s,value,expected)local c,o=health(s);return invoke('HEALTH_MAX',c,o,nil,expected,0,value)end
 function adapter.moves(s)local c,o,m=level(s);return invoke('MOVES_PROBE',c,o,m).moves end
 function adapter.unlock(s,tag)
  local name=FName(tag);assert(name:ToString()==tag,'Move tag is unavailable.');local c,o,m=level(s)
  return invoke('MOVE_UNLOCK',c,o,m,0,0,0,name:GetComparisonIndex())
 end
 function adapter.tagIndex(tag)local n=FName(tag);assert(n:ToString()==tag,'Move tag is unavailable.');return n:GetComparisonIndex()end
 function adapter.fillStamina(s)
  local actors={}
  if s.combat then
   local director=s.gameState.Director;addr(director)
   director.PlayerParty:ForEach(function(_,v)local c=v:get();if valid(c)then local actor=c:GetOwner();if valid(actor)then actors[#actors+1]=actor end end end)
   -- The director empties its party before the exploration flag switches back.
   -- There is nothing to refill during those transition frames.
   assert(#actors<=3,'Unexpected player combat party size.')
  else actors={s.pawn}end
  for _,actor in ipairs(actors)do
   addr(actor)
   local class=StaticFindObject(s.combat and'/Script/SwtAdventure.SwtCombatStaminaComponent'or'/Script/SwtQuest.SwtQuestStaminaComponent')
   addr(class);local c=actor:GetComponentByClass(class);addr(c)
   assert(same(c:GetClass(),class),'Unsupported stamina component.')
   local r=invoke('STAMINA_PROBE',c,actor)
   if r.current<r.maximum-.01 then invoke('STAMINA_FILL',c,actor,nil,r.current)end
  end
  return true
 end
 return adapter
end
function M.new(ctx,options)
 options=options or{};local adapter=options.adapter or M.nativeAdapter(ctx,options)
 local verified=options.verified or{};local closed,infinite=false,false;local toggleSession,preview,sequence,lastTick=nil,nil,0,-math.huge
 local api={error=nil};local moveCatalog=options.moves;local damage;local statTools
 local function damageTools()
  if not damage then damage=dofile(folder..'admin_sandbox_damage.lua').new(ctx,{verified=verified.damage==true})end
  return damage
 end
 local function catalog()
  if not moveCatalog then moveCatalog=ctx.json.decode(assert(ctx.read(ctx.root..'data/admin-moves.json'),'Move catalog unavailable.'))end
  return moveCatalog
 end
 local function snapshot(exploration)
  local s=assert(ctx.snapshot(),'Load an offline campaign first.')
  assert(s.offline==true and s.phase==4 and(not exploration or not s.combat),'Use this feature during offline exploration.')
  assert(s.profile and s.slot~=nil and s.chapter~=nil and s.worldId,'Campaign identity is unavailable.')
  return s
 end
 local function identity(s)return table.concat({s.profile,tostring(s.slot),tostring(s.chapter),s.worldId},'|')end
 statTools=dofile(folder..'admin_sandbox_stats.lua').new(ctx,{adapter=adapter,snapshot=function()assert(not closed,'Sandbox is closed.');return snapshot(true)end,identity=identity,verified=function()return verified.stats==true end})
 function api.preview_stat(key,value)return statTools.preview(key,value)end
 function api.apply_stat(token)return statTools.apply(token)end
 function api.preview_xp(amount)
  local ok,result=pcall(function()
   assert(not closed and verified.xp==true,'XP editing has not been verified for this game build.')
   assert(type(amount)=='number'and amount%1==0 and amount>=1 and amount<=100000,'Choose 1–100000 XP.')
   local s=snapshot(true);local current=adapter.probeXP(s)
   assert(current.level<current.max_level,'Your cat is already at maximum level.')
   sequence=sequence+1;preview={token=tostring(sequence),session=identity(s),amount=amount,current=current.current,level=current.level,max_level=current.max_level}
   return{token=preview.token,amount=amount,current=current.current,level=current.level,max_level=current.max_level,maximum=current.maximum}
  end)
  if not ok then preview=nil;return false,tostring(result)end
  return true,result
 end
 function api.apply_xp(token)
  local p=preview;preview=nil -- Never retry an uncertain persistent operation.
  local ok,result=pcall(function()
   assert(not closed and verified.xp==true and p and p.token==token,'XP preview expired. Preview the change again.')
   local s=snapshot(true);assert(identity(s)==p.session,'Campaign changed since the preview.')
   local fresh=adapter.probeXP(s);assert(fresh.level==p.level and math.abs(fresh.current-p.current)<.01,'XP changed since the preview.')
   assert(ctx.backupSave,'Save backup unavailable.');ctx.backupSave(s)
   s=snapshot(true);assert(identity(s)==p.session,'Campaign changed during backup.')
   local r=adapter.addXP(s,p.amount,p)
   return{message='XP granted through the game progression system.',requested=p.amount,before_level=p.level,level=r.after_level,current=r.after,maximum=r.maximum}
  end)
  if not ok then return false,tostring(result)end;return true,result
 end
 function api.stats()
  local ok,r=pcall(function()assert(not closed and(verified.xp==true or verified.stats==true),'Player stats are unavailable.');local s=snapshot(true);return statTools.decorate(s,adapter.probeXP(s))end)
  return ok,r
 end
 local function eligibleMove(s,tag)
  for _,m in ipairs(catalog())do if m.tag==tag and(m.clan=='None'or m.clan==(ctx.clans or{})[s.clan])then return m end end
  error('Choose a player move available to your current clan.')
 end
 function api.moves()
  local ok,result=pcall(function()
   assert(not closed and verified.moves==true,'Move unlocking has not been verified for this game build.')
   local s=snapshot(true);local unlocked=adapter.moves(s);local out={}
   for _,m in ipairs(catalog())do if m.clan=='None'or m.clan==(ctx.clans or{})[s.clan]then
    local e={};for k,v in pairs(m)do e[k]=v end;e.unlocked=unlocked[adapter.tagIndex(m.tag)]==true;out[#out+1]=e
   end end
   return out
  end)
  return ok,result
 end
 function api.unlock_move(tag)
  local ok,result=pcall(function()
   assert(not closed and verified.moves==true,'Move unlocking has not been verified for this game build.')
   local s=snapshot(true);local id=identity(s);local move=eligibleMove(s,tag)
   assert(not adapter.moves(s)[adapter.tagIndex(tag)],'This move is already unlocked.')
   assert(ctx.backupSave,'Save backup unavailable.');ctx.backupSave(s)
   s=snapshot(true);assert(identity(s)==id,'Campaign changed during backup.');eligibleMove(s,tag)
   adapter.unlock(s,tag);return'Move unlocked: '..tostring(move.name or tag)..'. Equip it in the original move menu.'
  end)
  return ok,tostring(result)
 end
 function api.set_damage_multiplier(value)return damageTools().set_multiplier(value)end
 function api.set_one_hit(value)return damageTools().set_one_hit(value)end
 function api.set_infinite_stamina(value)
  if type(value)~='boolean'then return false,'Infinite stamina must be on or off.'end
  if not value then infinite=false;toggleSession=nil;api.error=nil;return true,'Infinite stamina disabled.'end
  local ok,why=pcall(function()
   assert(not closed and verified.stamina==true,'Stamina refill has not been verified for this game build.')
   local s=snapshot(false);assert(adapter.fillStamina(s)~=false,'Stamina refill failed.');toggleSession=identity(s);infinite=true;lastTick=-math.huge;api.error=nil
  end)
  return ok,ok and'Infinite stamina enabled for exploration and your combat party.'or tostring(why)
 end
 function api.tick(now)
  if damage then damage.tick()end
  if closed or not infinite then return true end
  local ok,s=pcall(snapshot,false)
  if not ok or identity(s)~=toggleSession then infinite=false;toggleSession=nil;return true end
  now=now or os.clock();if now-lastTick<.2 then return true end;lastTick=now
  local good,why=pcall(function()assert(adapter.fillStamina(s)~=false,'Stamina refill failed.')end)
  if not good then infinite=false;toggleSession=nil;api.error=tostring(why);return false,api.error end
  return true
 end
 function api.state()
  local d=damage and damage.state()or{multiplier=1,one_hit=false}
  return{infinite_stamina=infinite,error=api.error or d.error,xp_supported=verified.xp==true,stats_supported=verified.stats==true,stamina_supported=verified.stamina==true,moves_supported=verified.moves==true,damage_supported=verified.damage==true,damage_multiplier=d.multiplier,one_hit=d.one_hit}
 end
 function api.shutdown()infinite=false;toggleSession=nil;preview=nil;closed=true;if damage then return damage.shutdown()end;return true end
 return api
end
return M
