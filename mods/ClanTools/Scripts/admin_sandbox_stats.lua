-- Persistent stat transactions use the original game's serializer. A token is
-- consumed before mutation; uncertain results must never be silently retried.
local M={}
local keys={prowess=0,strength=1,resilience=2,instinct=3,agility=4,stamina=5}
function M.new(ctx,o)
 local a=o.adapter;local pending,seq=nil,0;local baseline,baselineSession={},nil
 local api={}
 function api.decorate(s,r)
  local id=o.identity(s);if baselineSession~=id then baseline={};baselineSession=id end
  for i=0,5 do local k='stat'..i;if type(r[k])=='number'then baseline[k]=baseline[k]or r[k];r['original_'..k]=baseline[k]end end
  return r
 end
 function api.preview(key,value)
  pending=nil
  local ok,r=pcall(function()
   assert(o.verified(),'Stat editing has not been verified for this game build.')
   local index=keys[key];assert(index~=nil,'Choose a player stat.')
   assert(type(value)=='number'and value%1==0 and value>=1 and value<=10000,'Choose a value from 1 to 10000.')
   local s=o.snapshot();local r=api.decorate(s,a.probeXP(s));local before=r['stat'..index]
   assert(type(before)=='number'and before>=1 and before<=100000,'Player stat unavailable.')
   assert(before~=value,'This stat already has that value.')
   local hp;if index==0 then hp=a.probeHealth(s);assert(math.abs(hp.maximum-before)<.01,'Health maximum differs from Prowess. Wait for temporary effects to end.')end
   seq=seq+1;pending={token='stat-'..seq,key=key,index=index,before=before,after=value,original=baseline['stat'..index],level=r.level,session=o.identity(s),health=hp}
   local result={};for k,v in pairs(pending)do if k~='session'and k~='health'then result[k]=v end end;return result
  end)
  return ok,ok and r or tostring(r)
 end
 function api.apply(token)
  local p=pending;pending=nil
  local ok,r=pcall(function()
   assert(o.verified()and p and token==p.token,'Stat preview expired. Preview the change again.')
   local function fresh()
    local s=o.snapshot();assert(o.identity(s)==p.session,'Campaign changed since the preview.')
    local r=a.probeXP(s);assert(r.level==p.level and math.abs(r['stat'..p.index]-p.before)<.01,'Player stats changed since the preview.')
    if p.health then local hp=a.probeHealth(s);assert(math.abs(hp.maximum-p.health.maximum)<.01,'Health maximum changed since the preview.')end
    return s
   end
   local s=fresh();assert(ctx.backupSave,'Save backup unavailable.');ctx.backupSave(s);s=fresh()
   a.setStat(s,p.index,p.after,p)
   if p.health then
    local success,why=pcall(a.setHealthMaximum,s,p.after,p.health.maximum)
    if not success then
     -- Roll back only in the same campaign; never write a newly loaded slot.
     local restored=pcall(function()
      local now=o.snapshot();assert(o.identity(now)==p.session,'Campaign changed.')
      a.setStat(now,p.index,p.before,{before=p.after,level=p.level})
      local hp=a.probeHealth(now);if hp.maximum~=p.before then a.setHealthMaximum(now,p.before,hp.maximum)end
     end)
     error('Health update failed: '..tostring(why)..(restored and' Original stat restored.'or' Restore the automatic backup before continuing.'))
    end
   end
   return{message='Player stat saved. Native level-ups may recalculate stats.',key=p.key,before=p.before,after=p.after,original=p.original}
  end)
  return ok,ok and r or tostring(r)
 end
 return api
end
return M
