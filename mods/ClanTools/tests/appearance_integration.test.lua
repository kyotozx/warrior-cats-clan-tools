local factory=dofile('mods/ClanTools/Scripts/appearance_integration.lua')
local transaction=dofile('mods/ClanTools/Scripts/appearance.lua')
local realDofile=dofile
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
local function fixture()
 local f={calls={},queue={},session={profile='A',slot=0,chapter='Chapter00',gs=1,worldId='world',offline=true,clan=4}}
 local function record(value)f.calls[#f.calls+1]=value end
 f.pause={visible=2,IsInViewport=function()return true end,GetVisibility=function(self)return self.visible end,SetVisibility=function(self,v)self.visible=v;record('pause:'..v)end}
 f.cat={role=77,clan=4,living=true,name='Darkfeather'}
 local controls={attach=function()return{}end,tick=function()record('controls.tick')end,shutdown=function()record('controls.shutdown')end}
 local active,adapters
 local editor={}
 function editor:open(cat,callbacks)
  record('editor.open');assert(not f.ctx.ui.opened,'Native background was not restored before editor initialization')
  assert(f.pause.visible==0,'Pause hierarchy not restored before editor initialization')
  active={callbacks=callbacks,widget={IsInViewport=function()return not f.screenRemoved end}}
  f.callbacks=callbacks
  assert(callbacks.ready(4096));assert(callbacks.cameraReady(8192));assert(callbacks.initializeScreen(12288));assert(callbacks.screenReady(12288))
  if f.openFail then return nil,'Open failed'end
  adapters.onAppearanceOpened(active);return active
 end
 function editor:close()
  if not active or active.closed then return true end
  record('editor.close');if f.closeFail then return false,'Close failed'end
  assert(active.callbacks.detachScreen());active.closed=true
  adapters.onAppearanceClosed(active);return active.callbacks.closed()
 end
 function editor:release()
  record('editor.release');if f.releaseFail then return false,'Release failed'end
  assert(active.closed);active=nil;return true
 end
 function editor:state()return active end
 function editor:tick()record('editor.tick')end
 local ui={opened=true,tab='appearance',close=function()record('ui.close');f.ctx.ui.opened=false;f.pause.visible=0 end,
  open=function(p)assert(p==f.pause);assert(not f.ctx.appearanceActive,'Menu reopened before editor input guard was released');record('ui.open');f.ctx.ui.opened=true end,notify=function()record('notify')end}
 f.ctx={root='mock/',valid=function(o)return o~=nil end,ui=ui,snapshot=function()return f.session end,
  playerName=function()return'Player'end,getCats=function()return{f.cat}end,backupSave=function()record('backup');return'backup.sav'end,
  defer=function(fn)f.queue[#f.queue+1]=fn end,validateCat=function()return not f.invalid,'Cat changed'end,
  native=function(cmd)record(cmd);if f.failNative==cmd then return nil,'Native failure'end;return{details='intent='..(f.intent or 0)}end,
  portraits={invalidate=function(_,role)assert(role==77);record('invalidate')end},log=function()end}
 f.ctx.appearanceWorldFactory={new=function()return{refresh=function()record('world.refresh');return 1,0 end}end}
 function dofile(path)
  local name=path:match('([^/\\]+)$')
  if name=='appearance.lua'then return transaction end
  if name=='appearance_editor.lua'then return{new=function(a)adapters=a;return editor end}end
  if name=='appearance_controls.lua'then return{new=function()return controls end}end
  error('Unexpected module '..path)
 end
 function FindAllOf()return f.pauseMissing and{}or{f.pause}end
 f.mod=factory.new(f.ctx);dofile=realDofile
 function f:frame()local q=self.queue;self.queue={};for _,fn in ipairs(q)do fn()end;return self.mod.tick()end
 function f:has(v)for _,c in ipairs(self.calls)do if c==v then return true end end;return false end
 return f
end
test('restores native menu before opening and keeps inputs guarded through END',function()
 local f=fixture();assert(f.ctx.editAppearance(f.cat));assert(f.ctx.appearanceActive);assert(f.pause.visible==2)
 assert(f.callbacks.cancel());assert(f.pause.visible==0);assert(f.ctx.appearanceActive)
 f:frame();assert(not f:has('END'));assert(not f:has('ui.open'))
 f:frame();assert(f:has('END')and f:has('editor.release')and f:has('ui.open'));assert(not f.ctx.appearanceActive)
 assert(not f:has('APPLY'))
end)
test('apply commits then invalidates portrait and reopens after cleanup',function()
 local f=fixture();assert(f.mod.begin(f.cat));assert(f.callbacks.apply());assert(f:has('APPLY')and f:has('invalidate'))
 f:frame();f:frame();assert(f.mod.state().phase=='idle'and f.ctx.ui.opened)
end)
test('profile change cancels and never reopens stale menu',function()
 local f=fixture();assert(f.mod.begin(f.cat));f.session={profile='B',slot=0,chapter='Chapter00',gs=1,worldId='world',offline=true,clan=4}
 assert(f.mod.tick());f:frame();f:frame();assert(f:has('CANCEL')and not f:has('ui.open'))
end)
test('shutdown waits for native END and never reopens menu',function()
 local f=fixture();assert(f.mod.begin(f.cat));assert(f.mod.shutdown()==false);assert(not f:has('controls.shutdown'))
 f:frame();f:frame();assert(f.mod.shutdown());assert(f:has('controls.shutdown')and not f:has('ui.open'))
 assert(f.ctx.editAppearance==nil and f.ctx.appearance==nil and not f.ctx.appearanceActive)
end)
test('partial open failure cleans up without committing',function()
 local f=fixture();f.openFail=true;assert(not f.mod.begin(f.cat));f:frame();f:frame()
 assert(f.mod.state().phase=='idle'and not f:has('APPLY')and f:has('ui.open'))
end)
test('failed END retries while keeping editor input guard',function()
 local f=fixture();assert(f.mod.begin(f.cat));assert(f.callbacks.cancel());f.failNative='END';f:frame();assert(not f:frame())
 assert(f.mod.state().phase=='guarded_error'and f.ctx.appearanceActive and not f:has('ui.open'))
 f.failNative=nil;assert(f.mod.tick());assert(f.mod.state().phase=='idle'and f:has('ui.open'))
end)
test('failed actor release remains owned and retries before reopening',function()
 local f=fixture();assert(f.mod.begin(f.cat));f.releaseFail=true;assert(f.callbacks.cancel());f:frame();assert(not f:frame())
 assert(f.ctx.appearanceActive and not f:has('ui.open'));f.releaseFail=nil;assert(f.mod.tick());assert(f:has('ui.open'))
end)
test('native removed screen cancels instead of committing',function()
 local f=fixture();assert(f.mod.begin(f.cat));f.screenRemoved=true;assert(f.mod.tick());f:frame();f:frame();assert(not f:has('APPLY'))
end)
test('failed close after Apply retries without issuing Cancel',function()
 local f=fixture();assert(f.mod.begin(f.cat));f.closeFail=true;assert(not f.callbacks.apply())
 assert(f.mod.state().phase=='applied'and f:has('APPLY'));f.closeFail=nil;assert(f.mod.tick())
 f:frame();f:frame();assert(not f:has('CANCEL')and f:has('ui.open'))
end)
test('live eligibility and combat refusals happen before backup/native BEGIN',function()
 local f=fixture();f.invalid=true;assert(not f.mod.begin(f.cat));assert(#f.calls==0)
 f.invalid=false;f.session.combat=true;assert(not f.mod.begin(f.cat));assert(#f.calls==0)
end)
test('missing native pause refuses before backup and never acquires input guard',function()
 local f=fixture();f.pauseMissing=true
 local ok,err=f.mod.begin(f.cat);assert(not ok and err:find('pause menu',1,true))
 assert(#f.calls==0 and f.mod.state().phase=='idle'and not f.ctx.appearanceActive)
end)
test('pause vanishing after BEGIN finishes native guards without an editor handle',function()
 local f=fixture()
 -- Simulate the pause going away during backup. The integration's defensive
 -- second pause lookup occurs after BEGIN and must unwind native state.
 f.ctx.backupSave=function()f.calls[#f.calls+1]='backup';f.pauseMissing=true;return'backup'end
 assert(not f.mod.begin(f.cat));assert(f:has('BEGIN 77 4')and not f:has('editor.open'))
 f:frame();f:frame();assert(f:has('END')and f.mod.state().phase=='idle'and not f.ctx.appearanceActive)
end)
print(count..' appearance integration tests passed')
