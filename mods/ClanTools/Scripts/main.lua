local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local ctx=dofile(folder..'context.lua')
ctx.appearanceDllName='clanappearance-skins-v8.dll'
ctx.skins=dofile(folder..'skins.lua').new(ctx)
local ready,stopped,closing=false,false,false
local tick=0;local errors={};local ui,items,party,admin,crafting,portraits,input,appearance,settings,keybinds,progression,followers,flightInput;local portraitSession,lastSnapshot
local healAdapter,adminVerified,progressionAdapter
local cleanupDone={};local shutdownMessage
local pendingToggle,pendingPointer=false,false
local pendingSettings
local creatorSkins
local loopHandle
ctx.defer=function(fn)ExecuteInGameThreadAfterFrames(1,fn)end
local function report(key,message)
 message=tostring(message);if errors[key]~=message then errors[key]=message;ctx.log(key..': '..message)end
end
local function safe(key,fn,...)
 local ok,a,b=pcall(fn,...);if not ok then report(key,a);return false,a end
 errors[key]=nil;return true,a,b
end
local function portraitReady()
 if not closing and ui and ui.opened then safe('Portrait refresh',ui.render)end
end
local function loadPortraits()
 if portraits then return portraits end
 local f=io.open(folder..'portraits.lua','rb');if not f then return nil end;f:close()
 local ok,p=pcall(function()return dofile(folder..'portraits.lua').new(ctx)end)
 if not ok then report('Portraits',p);return nil end
 portraits=p;ctx.portraits=p;return p
end
ctx.portrait=function(cat)
 if closing then return nil end
 local p=loadPortraits();if p then return p:get(cat,portraitReady)end
end
local function init()
 if not ctx.catNames then ctx.catNames=dofile(folder..'cat_names.lua').new(ctx)end
 if not ctx.nativeCatNames then ctx.nativeCatNames=dofile(folder..'native_cat_names.lua').new(ctx)end
 if not ctx.textPrompt then ctx.textPrompt=dofile(folder..'text_prompt.lua').new(ctx)end
 -- Preserve created modules if a later dependency fails during initialization.
 if not party then party=dofile(folder..'party.lua').new(ctx);ctx.party=party end
 if not ctx.partyPresets then ctx.partyPresets=dofile(folder..'party_presets.lua').new(ctx,party)end
 if not followers then followers=dofile(folder..'followers_integration.lua').new(ctx,{verified=true,library='follower-appearance-v4.dll'});ctx.followers=followers end
 if not progression then
  local m=dofile(folder..'admin_progression.lua')
  progressionAdapter=m.nativeAdapter(ctx,ctx.root..'bin/','admin-progression-v2.dll')
  progression=m.new(setmetatable({progressionAdapter=progressionAdapter,verified={pile=true,bonds=true,quests=true}},{__index=ctx}));ctx.progression=progression
 end
 if not admin then
  local heal=dofile(folder..'admin_heal.lua').new();healAdapter=heal
  local verified={movement=true,collision=true,teleport=true,god=true,heal=false,spawn_item=true,spawn_enemy=true,spawn_training=true,vertical_input=true,named_destinations=true}
  adminVerified=verified;ctx.adminVerified=verified
  local ok,r=pcall(heal.probe,ctx.snapshot());if ok and type(r)=='table'and r.status=='READY'then verified.heal=true end
  local enemies=dofile(folder..'admin_enemy.lua')
  admin=dofile(folder..'admin.lua').new(setmetatable({verified=verified,progression=progression,adapters={heal=heal.heal,spawn_enemy=enemies.spawn,spawn_training=enemies.spawn_training}},{__index=ctx}));ctx.admin=admin
 end
 -- Runtime acceptance on Steam build 24847281; native bridges also guard the
 -- executable and object identities before invoking game functions.
 ctx.pileLockVerified=true;ctx.avoidanceVerified=true;ctx.mapTravelVerified=true;ctx.inventoryVerified=true
 if not ctx.pileLock then ctx.pileLock=dofile(folder..'pile_lock.lua').new(ctx,progressionAdapter)end
 if not ctx.avoidance then ctx.avoidance=dofile(folder..'admin_avoidance.lua').new(ctx)end
 if not ctx.mapTravel then ctx.mapTravel=dofile(folder..'admin_map_travel.lua').new(ctx)end
 if not ctx.photoTools then ctx.photoTools=dofile(folder..'photo_tools.lua').new(ctx)end
 if not ctx.skyTools then ctx.skyTools=dofile(folder..'sky_tools.lua').new(ctx)end
 if not ctx.denTools then ctx.denTools=dofile(folder..'den_tools.lua').new(ctx)end
 if not ctx.inventoryTools then ctx.inventoryTools=dofile(folder..'admin_inventory.lua').new(ctx)end
 ctx.workshopVerified=true -- Native recipe, placement and reload acceptance completed.
 if not ctx.workshop then ctx.workshop=dofile(folder..'workshop.lua').new(ctx)end
 if not ctx.sandbox then
  ctx.sandboxVerified={xp=true,moves=true,stamina=true,damage=true,stats=true}
  ctx.sandbox=dofile(folder..'admin_sandbox.lua').new(ctx,{verified=ctx.sandboxVerified})
 end
 if not items then
  items=dofile(folder..'item_feedback.lua').new({mod_root=ctx.root,snapshot=ctx.snapshot,log=ctx.log,notify=function(e)if ui then ui.notify(e)end end});ctx.items=items
  items.set_enabled(ctx.settings.feedback)
 end
 if not ui then ui=dofile(folder..'ui.lua').new(ctx);ctx.ui=ui end
 if not ctx.mapTravelInput then ctx.mapTravelInput=dofile(folder..'map_travel_input.lua').new(ctx);assert(ctx.mapTravelInput.start())end
 if not appearance then appearance=dofile(folder..'appearance_integration.lua').new(ctx)end
 if not flightInput then flightInput=dofile(folder..'flight_input.lua').new(ctx);ctx.flightInput=flightInput;assert(flightInput.start())end
 if not settings then settings=dofile(folder..'settings_extensions.lua').new(ctx);ctx.videoSettings=settings;ctx.settings_extensions=settings end
 if not keybinds then keybinds=dofile(folder..'key_rebind.lua').new(ctx);ctx.keybinds=keybinds end
 if not input then
  input=dofile(folder..'input.lua').new({valid=ctx.valid,log=ctx.log,native_commands=true,
   is_open=function()return ui.opened end,
   pause=function()
    for _,p in ipairs(FindAllOf('GuiScreenPause')or{})do if ctx.valid(p)and p:IsInViewport()and p:GetVisibility()~=2 then return p end end
   end,
   open=ui.openEntry,back=ui.back,activate=ui.activate,nav=ui.navigate,tabcycle=ui.cycleTab})
  ctx.input=input
 end
 if not crafting then crafting=dofile(folder..'crafting.lua').new({mod_root=ctx.root,snapshot=ctx.snapshot,log=ctx.log,notify=function(e)if ui then ui.notify(e)end end});ctx.crafting=crafting end
 ready=true;ctx.log('Ready. Open the pause menu and choose Clan Tools.')
end
local function cleanup()
 local failures={}
 local function finish(name,fn,needsConfirmation)
  if cleanupDone[name]or not fn then return end
  local ok,result,message=pcall(fn)
  if ok and(not needsConfirmation or result==true)then cleanupDone[name]=true
  else failures[#failures+1]=name..': '..tostring(ok and(message or'Cleanup not confirmed')or result)end
 end
 -- Admin may require a cleanup tick after combat before shutdown can succeed.
 if admin and not cleanupDone.admin then safe('Admin cleanup tick',admin.tick)end
 finish('items',items and items.shutdown,true)
 finish('crafting',crafting and crafting.shutdown,true)
 finish('appearance',appearance and appearance.shutdown,true)
 if appearance and not cleanupDone.appearance then return false,'Appearance cleanup is pending.'end
 finish('textPrompt',ctx.textPrompt and ctx.textPrompt.shutdown,true)
 finish('settings',settings and settings.shutdown,true)
 finish('keybinds',keybinds and keybinds.shutdown,true)
 finish('flightInput',flightInput and flightInput.shutdown,true)
 finish('sandbox',ctx.sandbox and ctx.sandbox.shutdown,true)
 finish('pileLock',ctx.pileLock and ctx.pileLock.shutdown,true)
 finish('avoidance',ctx.avoidance and ctx.avoidance.shutdown,true)
 finish('mapTravel',ctx.mapTravel and ctx.mapTravel.reset,false)
 finish('mapTravelInput',ctx.mapTravelInput and ctx.mapTravelInput.shutdown,true)
 finish('photoTools',ctx.photoTools and ctx.photoTools.shutdown,true)
 finish('skyTools',ctx.skyTools and ctx.skyTools.shutdown,true)
 finish('denTools',ctx.denTools and ctx.denTools.shutdown,true)
 finish('nativeCatNames',ctx.nativeCatNames and ctx.nativeCatNames.shutdown,true)
 finish('inventoryTools',ctx.inventoryTools and ctx.inventoryTools.shutdown,true)
 finish('workshop',ctx.workshop and ctx.workshop.shutdown,true)
 finish('followers',followers and followers.shutdown,true)
 finish('admin',admin and admin.shutdown,true)
 finish('portraits',portraits and function()portraits:clear()end,false)
 finish('ui',ui and ui.shutdown,false)
 finish('input',input and input.shutdown,true)
 shutdownMessage=#failures>0 and table.concat(failures,'; ')or nil
 if shutdownMessage then report('Shutdown',shutdownMessage);return false,shutdownMessage end
 stopped=true;ready=false;if loopHandle then CancelDelayedAction(loopHandle);loopHandle=nil end;return true
end
function ctx.shutdown()
 closing=true;ready=false
 if creatorSkins then creatorSkins.shutdown();creatorSkins=nil end
 return cleanup()
end
function ctx.shutdownStatus()return {requested=closing,complete=stopped,error=shutdownMessage}end
local function toggleMenu()
 if ctx.appearanceActive then return end
 if ui.opened then ui.close();return end
 local s=ctx.snapshot();if not s or not ctx.valid(s.pc)then return end
 for _,p in ipairs(FindAllOf('GuiScreenPause')or{})do if ctx.valid(p)and p:IsInViewport()then ui.open(p);return end end
 s.pc:OnListenCommand(89,0)
 ExecuteInGameThreadWithDelay(250,function()
  if not ready or closing or ctx.appearanceActive or not ctx.snapshot()then return end
  safe('Open pause panel',function()for _,p in ipairs(FindAllOf('GuiScreenPause')or{})do if ctx.valid(p)and p:IsInViewport()then ui.open(p);return end end end)
 end)
end
loopHandle=LoopInGameThreadWithDelay(100,function()
 if stopped then return true end
 if closing then cleanup();return stopped end
 tick=tick+1
 if not creatorSkins then local ok,r=pcall(function()return dofile(folder..'creator_skins.lua').new(ctx)end);if ok then creatorSkins=r else report('Creator skins init',r)end end
 if creatorSkins then safe('Creator skins',creatorSkins.tick)end
 local snapshotOK,s=safe('Campaign snapshot',ctx.snapshot);if not snapshotOK then s=nil end
 lastSnapshot=s
 if appearance then safe('Appearance tick',appearance.tick)end
 if settings then safe('Video settings',settings.tick,s)end
 if keybinds then safe('Keybindings',keybinds.tick,s)end
 if followers then safe('Party followers',followers.tick,tick*0.1)end
 if ctx.sandbox then safe('Player sandbox',ctx.sandbox.tick,tick*0.1)end
 if ctx.photoTools then safe('Photo tools',ctx.photoTools.tick,s)end
 if ctx.skyTools then safe('Sky lighting',ctx.skyTools.tick,s)end
 if ctx.denTools and tick%3==0 then safe('Den layout',ctx.denTools.tick,s)end
 if ctx.nativeCatNames and tick%3==0 then safe('Native cat names',ctx.nativeCatNames.tick)end
 if ctx.inventoryTools and tick%3==0 then safe('Inventory tools',ctx.inventoryTools.tick)end
 if ctx.pileLock and tick%3==0 then safe('Food lock',ctx.pileLock.tick)end
 if ctx.avoidance and tick%3==0 then safe('Ignore Enemies',ctx.avoidance.tick)end
 if not s then
  if items then safe('Item reset',items.reset,'no active campaign')end
  if crafting then safe('Crafting reset',crafting.reset)end
  if portraits and portraitSession then safe('Portrait cleanup',function()portraits:clear()end);portraitSession=nil end
  if admin then safe('Admin tick',admin.tick)end
  if ui then safe('UI tick',ui.tick)end
  return
 end
 if not ready then local ok=safe('Initialization',init);if not ok then return end end
 if tick%5==0 and ctx.read then
  local request=ctx.root..'../ClanLoader/open-clantools.txt'
  if ctx.read(request)then os.remove(request);if not ui.opened then pendingToggle=true end end
 end
 if pendingToggle then pendingToggle=false;if not ctx.appearanceActive then safe('Open Clan Tools',toggleMenu)end end
 if pendingPointer then pendingPointer=false;if not ctx.appearanceActive then safe('Pause entry',ui.pointerEntry)end end
 if pendingSettings then local page=pendingSettings;pendingSettings=nil;if not ctx.appearanceActive then safe('Open extended settings',ui.requestSettings,page)end end
 if input and not ui.opened and not ctx.appearanceActive then safe('Menu input',input.tick,s,0.1)end
 local session=tostring(s.profile)..':'..tostring(s.slot)..':'..tostring(s.gs)..':'..tostring(s.worldId)
 if portraitSession and portraitSession~=session and portraits then safe('Portrait cleanup',function()portraits:clear()end)end
 portraitSession=session
 safe('UI tick',ui.tick)
 if portraits then safe('Portrait tick',function()portraits:tick()end)end
 if tick%3==0 then safe('Item feedback',items.tick,s);safe('Admin tick',admin.tick);safe('Crafting tick',crafting.tick,s)end
 if tick%10==0 then
  if adminVerified and not adminVerified.heal then local ok,r=pcall(healAdapter.probe,s);if ok and type(r)=='table'and r.status=='READY'then adminVerified.heal=true end end
  safe('Party tick',party.tick)
  safe('Pause menu attachment',function()for _,p in ipairs(FindAllOf('GuiScreenPause')or{})do if ctx.valid(p)and p:IsInViewport()then ui.attach(p);for _,settingsScreen in ipairs(FindAllOf('GuiPopupCommonSettings')or{})do if ctx.valid(settingsScreen)and settingsScreen:IsInViewport()then ui.attachSettings(settingsScreen,p)end end end end end)
 end
end)
-- Key callbacks only enqueue intent. All engine calls and UI mutations run in
-- the game-thread loop, avoiding nested async Lua execution while rendering.
RegisterKeyBind(Key.F6,function()
 if closing then return end
 if creatorSkins and creatorSkins.request()then return end
 if ready then pendingToggle=true end
end)
RegisterKeyBind(Key.F7,function()if ready and not closing then pendingSettings='keybinds'end end)
RegisterKeyBind(Key.F8,function()if ready and not closing then pendingSettings='video'end end)
-- Native pause menus route their custom pointer separately from UMG controls.
RegisterKeyBind(Key.LEFT_MOUSE_BUTTON,function()if ready and not closing then pendingPointer=true end end)
return ctx
