-- Integration regression: root must revoke native observers when no campaign exists.
local source=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local real_dofile=dofile
local current={offline=true,phase=4,worldId='world1',profile='profile',pawn={}}
local loop;local keys={};local deferred={};local calls={itemReset=0,craftReset=0,adminTick=0,portraitTick=0,portraitClear=0,render=0,itemTick=0,inputTick=0,close=0,pointer=0}
local ctx={root='test/',settings={feedback=true},snapshot=function()return current end,log=function()end,valid=function()return true end}
local ui={opened=true,render=function()calls.render=calls.render+1 end,tick=function()end,notify=function()end,attach=function()end,close=function()calls.close=calls.close+1 end,pointerEntry=function()calls.pointer=calls.pointer+1 end,shutdown=function()return true end}
local items={set_enabled=function()end,tick=function()calls.itemTick=calls.itemTick+1 end,reset=function()calls.itemReset=calls.itemReset+1;return true end,shutdown=function()return true end}
local crafting={tick=function()end,reset=function()calls.craftReset=calls.craftReset+1;return true end,shutdown=function()return true end}
local admin={tick=function()calls.adminTick=calls.adminTick+1 end,shutdown=function()return true end}
local modules={['context.lua']=ctx,['party.lua']={new=function()return {tick=function()end}end},['admin_heal.lua']={new=function()return {probe=function()return{status='READY'}end}end},['admin.lua']={new=function()return admin end},['item_feedback.lua']={new=function()return items end},['ui.lua']={new=function()return ui end},['crafting.lua']={new=function()return crafting end}}
modules['input.lua']={new=function(options)
 assert(options.native_commands==true,'Open menu must use native input events')
 return {tick=function()calls.inputTick=calls.inputTick+1 end,shutdown=function()return true end}
end}
modules['appearance_integration.lua']={new=function()return{tick=function()end,shutdown=function()return true end}end}
modules['settings_extensions.lua']={new=function()error('FPS runtime belongs to Performance')end}
modules['key_rebind.lua']={new=function()return{tick=function()end,shutdown=function()return true end}end}
modules['admin_progression.lua']={nativeAdapter=function()return{}end,new=function()return{}end}
modules['admin_enemy.lua']={spawn=function()end}
modules['followers_integration.lua']={new=function()return{tick=function()end,shutdown=function()return true end}end}
modules['flight_input.lua']={new=function()return{start=function()return true end,shutdown=function()return true end}end}
modules['cat_names.lua']={new=function()return{}end}
modules['party_presets.lua']={new=function()return{}end}
for _,name in ipairs({'skins.lua','creator_skins.lua','sky_tools.lua','text_prompt.lua','pile_lock.lua','admin_avoidance.lua','admin_map_travel.lua','admin_sandbox.lua','photo_tools.lua','den_tools.lua','map_travel_input.lua','native_cat_names.lua','admin_inventory.lua','workshop.lua'})do
 modules[name]={new=function()return{request=function()return false end,start=function()return true end,tick=function()end,reset=function()return true end,shutdown=function()return true end}end}
end
local portraits={}
function portraits:get(cat,callback)assert(self==portraits and cat.role==82);callback();return 'material'end
function portraits:tick()assert(self==portraits);calls.portraitTick=calls.portraitTick+1 end
function portraits:clear()assert(self==portraits);calls.portraitClear=calls.portraitClear+1 end
modules['portraits.lua']={new=function()return portraits end}
function dofile(path)local name=path:match('([^/\\]+)$');return assert(modules[name],'Unexpected module '..tostring(name))end
function LoopInGameThreadWithDelay(_,callback)loop=callback end
function CancelDelayedAction()return true end
function RegisterKeyBind(key,fn)keys[key]=fn end
function ExecuteWithDelay()error('Async Lua scheduling is forbidden')end
function ExecuteInGameThread()error('Key callbacks must enqueue intent only')end
function ExecuteInGameThreadAfterFrames(frames,fn)assert(frames==1 and type(fn)=='function');deferred[#deferred+1]=fn end
function ExecuteInGameThreadWithDelay(ms,fn)assert(ms==250 and type(fn)=='function');deferred[#deferred+1]=fn end
function FindAllOf()return{}end
Key={F6=1,LEFT_MOUSE_BUTTON=2,F7=3,F8=4}
local boot=assert(loadfile(source..'../Scripts/main.lua'))
local result=boot();assert(result==ctx);assert(type(loop)=='function');loop()
assert(keys[Key.F8]==nil and ctx.settings_extensions==nil,'Clan Tools must not own the Performance hotkey or runtime')
keys[Key.F6]();keys[Key.LEFT_MOUSE_BUTTON]()
assert(calls.close==0 and calls.pointer==0,'Key callback touched engine/UI outside game-thread loop')
loop();assert(calls.close==1 and calls.pointer==1,'Game-thread loop did not consume key intents')
assert(calls.inputTick==0,'Open menu should not poll PlayerController keys')
local deferredCalls=0;ctx.defer(function()deferredCalls=deferredCalls+1 end)
assert(deferredCalls==0 and #deferred==1,'UI callback was not deferred by one game-thread frame')
deferred[1]();assert(deferredCalls==1)
print('PASS key intents and UI callbacks remain on game-thread scheduling')
local portraitReady=0
assert(ctx.portrait({role=82},function()portraitReady=portraitReady+1 end)=='material')
assert(portraitReady==1 and calls.render==0,'Portrait completion must update its subscriber, not rebuild the menu')
current=nil;loop()
assert(calls.itemReset>0,'Leaving campaign did not reset ItemFeedback native hook')
assert(calls.craftReset>0,'Leaving campaign did not reset Crafting native hook')
assert(calls.adminTick>0,'Leaving campaign did not reset admin via tick')
assert(calls.portraitClear==1,'Leaving campaign did not release portrait render targets')
ui.opened=false;keys[Key.F6]();loop() -- no active snapshot: no controller dereference
print('PASS main campaign-exit native hook cleanup')
current={offline=true,worldId='world2'};ui.tick=function()error('UI drawing failed')end;loop();loop();loop();assert(calls.itemTick>0,'UI error prevented native observers from ticking')
assert(calls.inputTick>0,'Closed menu still needs pause-entry input polling')
assert(calls.portraitTick>0);print('PASS optional portrait callbacks and UI errors preserve independent module ticks')
items.shutdown=function()return false,'Hook restoration failed'end
local ok=ctx.shutdown()
assert(ok==false,'Shutdown concealed native hook restoration failure')
print('PASS main shutdown propagates native cleanup failure')
items.shutdown=function()return true end;loop();assert(ctx.shutdownStatus().complete,'Pending shutdown was not retried');print('PASS shutdown retry completes after restoration succeeds')
dofile=real_dofile
