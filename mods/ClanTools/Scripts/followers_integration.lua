-- Current-party exploration visuals; persist preference, never actor identities.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local M={}
function M.new(ctx,options)
 options=options or{}
 -- Owned spawn, v4 appearance, cleanup and direct movement passed on this build.
 -- Bounded live probe recorded133cm displacement with collision enabled. Native
 -- pathfinding is tried first, with collision-preserving direct movement for
 -- terrain lacking navmesh. Housing remains suspended; root controls the gate.
 if options.verified==nil then options.verified=true end
 options.library=options.library or'follower-appearance-v4.dll'
 assert(ctx.snapshot and ctx.getCats and ctx.party and ctx.party.read,'Follower integration requires the active party context.')
 local api={};local enabled,closed,errorMessage=false,false,nil;local cleanupMessage;local lastSync=-math.huge
 local distance=150
 local selectionKey,worldKey,observedKey=nil,nil,nil
 local suspension,retryAt,environmentChecked,environmentReady,environmentReason=nil,0,-math.huge,true,nil
 local path=(ctx.root or folder..'../')..'state/followers.json'
 local function verified()return type(options.verified)=='function'and options.verified()==true or options.verified==true end
 local driver=options.driver
 local environment=options.environment
 if not environment and not driver then environment=dofile(folder..'follower_environment.lua').new(ctx)end
 if not driver then
  local module=dofile(folder..'followers.lua');local appearance
  local nameplates=dofile(folder..'follower_nameplates.lua')
  local driverContext={snapshot=ctx.snapshot,getCats=ctx.getCats,verified=verified()}
  driverContext.spawn=function(s,cat,index)
   appearance=appearance or module.appearanceAdapter((ctx.root or folder..'../')..'bin/',options.library)
   return module.spawn_probe(s,cat,index,appearance,options.nameplate or function(actor,c,ss)
    return nameplates.new(actor,c,ss,{hidden=function()return ctx.photoHideNames==true end})
   end)
  end
  driver=module.new(driverContext)
  options.updateGate=function()driverContext.verified=verified()end
 end
 local function load()
  if options.load then return options.load()end
  local raw=ctx.read and ctx.read(path);if not raw then return false end
  local v=ctx.json.decode(raw);assert(type(v)=='table'and(v.version==1 or v.version==2)and type(v.enabled)=='boolean','Invalid follower preference.')
  if v.version==2 then assert(type(v.distance)=='number'and v.distance%1==0 and v.distance>=100 and v.distance<=600,'Invalid follower distance.');distance=v.distance end
  return v.enabled
 end
 local function persist(value)
  if options.save then return assert(options.save(value)~=false,'Could not save follower preference.')end
  assert(ctx.write and ctx.json,'Follower preference storage unavailable.')
  ctx.write(path,ctx.json.encode({version=2,enabled=value,distance=distance}));return true
 end
 local ok,value=pcall(load);if ok then enabled=value==true else errorMessage=tostring(value)end
 if driver.set_distance then assert(driver.set_distance(distance))end
 local function report(message)
  if errorMessage~=message then errorMessage=message;if ctx.log then ctx.log('Exploration followers: '..message)end end
 end
 local function reset()
  selectionKey,worldKey,observedKey=nil,nil,nil
  local good,a,b=pcall(driver.reset)
  if not good or a==false then cleanupMessage=tostring(good and b or a);return false,cleanupMessage end
  cleanupMessage=nil
  return true
 end
 local function snapshot()
  local good,s=pcall(ctx.snapshot)
  if not good or not s or s.offline~=true or s.phase~=4 or s.combat then return nil end
  if ctx.valid and not ctx.valid(s.pawn)then return nil end
  if not s.worldId or not s.profile or s.slot==nil then return nil end
  return s
 end
 local function identity(s)
  return table.concat({s.worldId,s.profile,tostring(s.slot),tostring(s.chapter),tostring(s.pawn:GetAddress())},'|')
 end
 local function roles(s)
  local cats,meta=ctx.getCats()
  assert(type(cats)=='table'and meta and meta.valid and meta.profile==s.profile and meta.slot==s.slot,'Clan roster belongs to another session.')
  local eligible={};for _,c in ipairs(cats)do
   if c.living==true and c.clan==s.clan and type(c.role)=='number'and c.role>0 and c.role<255 then eligible[c.role]=c end
  end
  local out,seen={},{}
  for _,entry in ipairs(ctx.party.read())do
   local role=entry.role;local cat=eligible[role]
   if cat and not seen[role]and #out<2 then
    if ctx.validateCat then assert(ctx.validateCat(cat,s)==true,'Clanmate identity changed.')end
    out[#out+1]=role;seen[role]=true
   end
  end
  return out
 end
 function api.set_enabled(value)
  if closed then return false,'Follower integration is shut down.'end
  if type(value)~='boolean'then return false,'Enabled must be true or false.'end
  if value and not verified()then return false,'Exploration followers have not been verified for this game build.'end
  local good,a,b=pcall(function()
   local clean,why=reset();assert(clean,why)
   persist(value);enabled=value;errorMessage=nil;lastSync=-math.huge
   suspension=nil;retryAt=0;environmentChecked=-math.huge
   return true,value and'Exploration followers enabled for your current party.'or'Exploration followers dismissed.'
  end)
  if not good then return false,tostring(a)end;return a,b
 end
 function api.command(value)
  if closed then return false,'Follower integration is shut down.'end
  if not enabled or not snapshot()then return false,'Use follower commands during offline exploration.'end
  if not driver.command then return false,'Follower commands are unavailable.'end
  local ok,a,b=pcall(driver.command,value);if not ok then return false,tostring(a)end;return a,b
 end
 function api.set_distance(value)
  if closed then return false,'Follower integration is shut down.'end
  if type(value)~='number'or value%1~=0 or value<100 or value>600 then return false,'Follow distance must be between 100 and 600 cm.'end
  if not driver.set_distance then return false,'Follow distance is unavailable.'end
  local previous=distance
  local good,why=pcall(function()
   assert(driver.set_distance(value));distance=value;persist(enabled)
  end)
  if not good then distance=previous;pcall(driver.set_distance,previous);return false,tostring(why)end
  return true,'Follow distance set to '..value..' cm.'
 end
 function api.tick(now)
  if closed then return false,'Follower integration is shut down.'end
  if options.updateGate then options.updateGate()end
  if not enabled or not verified()then return reset()end
  local current=now or os.clock()
  local s=snapshot()
  if not s then return reset()end
  if environment and current-environmentChecked>=0.5 then
   environmentChecked=current
   local ok,ready,reason=pcall(environment,s)
   environmentReady=ok and ready==true
   environmentReason=ok and reason or'Follower location check unavailable.'
  end
  if not environmentReady then
   suspension=environmentReason or'Followers are waiting for a navigable location.'
   local clean,why=reset();if clean then errorMessage=nil end
   return clean,why
  end
  if suspension then
   local clean,why=reset();if not clean then return false,why end
   errorMessage=nil
   if current<retryAt then return true end
   suspension=nil
  end
  local good,key=pcall(identity,s);if not good then reset();report(tostring(key));return false,errorMessage end
  if worldKey and worldKey~=key then local clean,why=reset();if not clean then return false,why end end
  -- Require a second observation after transitions before creating actors.
  if observedKey~=key then observedKey=key;return true end
  if errorMessage then local clean,why=reset();return false,clean and errorMessage or why end
  local moved,a,b=pcall(driver.tick,current)
  if not moved or a==false then
   local why=tostring(moved and b or a)
   if why:find('[FOLLOWER_NAVIGATION]',1,true)then suspension='Followers are waiting for a usable path.';retryAt=current+5;reset();return true end
   reset();report(why);return false,errorMessage
  end
  if current-lastSync<1 then return true end;lastSync=current
  local ready,selected=pcall(roles,s)
  if not ready then reset();report(tostring(selected));return false,errorMessage end
  local target=table.concat(selected,',')
  if selectionKey==target and worldKey==key then return true end
  local selectedOK,r,why=pcall(driver.select,selected)
  if not selectedOK or r==false then
   local reason=tostring(selectedOK and why or r)
   if reason:find('[FOLLOWER_NAVIGATION]',1,true)then suspension='Followers are waiting for a usable path.';retryAt=current+5;reset();return true end
   reset();report(reason);return false,errorMessage
  end
  selectionKey,worldKey=target,key;return true
 end
 function api.state()
  local s=driver.state();return{enabled=enabled,supported=verified(),active=s.active or 0,roles=s.roles or{},error=errorMessage or cleanupMessage or s.error,suspended=suspension,mode=s.mode or'follow',distance=distance}
 end
 function api.reset()return reset()end
 function api.shutdown()
  local good,a,b=pcall(driver.shutdown)
  if not good or a==false then report(tostring(good and b or a));return false,errorMessage end
  closed=true;return true
 end
 return api
end
return M
