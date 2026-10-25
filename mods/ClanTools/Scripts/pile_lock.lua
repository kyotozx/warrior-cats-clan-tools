-- A temporary lock retains a chosen food value through the native resource API.
-- Every activation backs up the current save; a transition or failure disables it.
local M={}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
function M.new(ctx,adapter)
 local api={};local lock,reason,closed
 local function snapshot()
  local s=ctx.snapshot()
  assert(not closed and s and s.offline==true and s.phase==4 and not s.combat,'Food lock requires offline exploration.')
  assert(type(s.profile)=='string'and type(s.slot)=='number'and s.gameState,'Active save unavailable.')
  return s,table.concat({s.profile,s.slot,s.worldId or'',s.gameState:GetAddress()},'|')
 end
 local function probe(s)
  local r=adapter.pileProbe(s)
  assert(r and finite(r.current)and finite(r.maximum)and r.maximum>0 and r.maximum<=1000000 and r.current>=0 and r.current<=r.maximum,'Invalid food values.')
  return r
 end
 function api.set(enabled,value)
  if not enabled then lock=nil;reason=nil;return true,'Food lock disabled.'end
  local ok,result=pcall(function()
   assert(ctx.pileLockVerified==true,'Food lock is awaiting in-game verification.')
   local s,scope=snapshot();local r=probe(s);value=value or r.current
   assert(finite(value)and value>=0 and value<=r.maximum,'Choose a food value within the pile capacity.')
   assert(ctx.backupSave(s),'Save backup failed.')
   local again,key=snapshot();assert(key==scope,'Active save changed.')
   r=probe(again)
   if math.abs(r.current-value)>.01 then local out=adapter.pileSet(again,r,value);assert(out and math.abs(out.after-value)<.01,'Food value was not confirmed.')end
   lock={scope=scope,value=value,maximum=r.maximum};reason=nil
   return 'Fresh-kill pile locked at '..string.format('%.1f',value)..'.'
  end)
  if not ok then lock=nil;reason=tostring(result)end
  return ok,result
 end
 function api.tick()
  if not lock then return end
  local ok,why=pcall(function()
   assert(ctx.pileLockVerified==true,'Food lock verification changed.')
   local s,scope=snapshot();assert(scope==lock.scope,'Food lock stopped after a session change.')
   local r=probe(s);assert(r.maximum==lock.maximum,'Food lock stopped because pile capacity changed.')
   if math.abs(r.current-lock.value)>.01 then
    local out=adapter.pileSet(s,r,lock.value)
    assert(out and finite(out.after)and math.abs(out.after-lock.value)<.01,'Food lock readback failed.')
   end
  end)
  if not ok then lock=nil;reason=tostring(why)end
 end
 function api.state()return{enabled=lock~=nil,value=lock and lock.value,available=not closed and ctx.pileLockVerified==true,error=reason}end
 function api.reset()lock=nil;reason=nil;return true end
 function api.shutdown()api.reset();closed=true;return true end
 return api
end
return M
