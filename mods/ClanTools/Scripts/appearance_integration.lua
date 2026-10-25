-- Game-thread integration for the native appearance editor. Instantiate after
-- ctx.ui; call tick() from the normal game-thread loop, and honor shutdown's
-- false result until native END and owned preview cleanup have completed.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local M={}
local function same(a,b)
 return a and b and a.profile==b.profile and a.slot==b.slot and a.chapter==b.chapter
  and a.gs==b.gs and a.worldId==b.worldId
end
function M.new(ctx)
 for _,name in ipairs({'valid','snapshot','getCats','backupSave','defer'})do
  assert(type(ctx[name])=='function','Appearance integration requires ctx.'..name)
 end
 assert(ctx.ui and type(ctx.ui.close)=='function','Create Clan Tools UI before appearance integration')
 assert(not ctx.appearance,'Appearance integration is already installed')
 local api={};local controller,editor,controls
 local closing,stopped=false,false
 local menu,cleanupError
 local previousEdit=ctx.editAppearance
 local adapters=setmetatable({nativeDir=ctx.root..'bin/'},{__index=ctx})
 adapters.getCats=function()
  local rows=ctx.getCats();local result={};for _,cat in ipairs(rows)do result[#result+1]=cat end
  local s=ctx.snapshot();if s then result[#result+1]={role=0,player=true,clan=s.clan,living=true,name=ctx.playerName(),rank='Your cat'}end
  return result
 end
 local world=(ctx.appearanceWorldFactory or dofile(folder..'appearance_world.lua')).new(adapters)
 local function notify(message)
  if ctx.ui and ctx.ui.notify then ctx.ui.notify(tostring(message))
  elseif ctx.log then ctx.log('Appearance: '..tostring(message))end
 end
 local function findPause()
  for _,p in ipairs(FindAllOf('GuiScreenPause')or{})do
   if ctx.valid(p)and p:IsInViewport()then return p end
  end
 end
 local function restorePause()
  if menu and menu.hidden and ctx.valid(menu.pause)then
   menu.pause:SetVisibility(menu.visibility);menu.hidden=false
  end
 end
 local function finishMenu()
  if not menu then return end
  restorePause()
  local receipt=menu;menu=nil
  if not closing and receipt.reopen and same(receipt.session,ctx.snapshot())
   and ctx.valid(receipt.pause)and receipt.pause:IsInViewport()then
   ctx.ui.tab=receipt.tab;ctx.ui.open(receipt.pause)
  end
 end
 adapters.notify=notify
 adapters.promptAppearanceName=function(value,accept)
  local h=editor:state();assert(h and not h.closed and ctx.textPrompt,'Name editor unavailable.')
  local pause=findPause();assert(pause,'Native menu unavailable.')
  return ctx.textPrompt.open({title='Clanmate name',value=value,maxLength=40,pause=pause,owner=h.widget,
   validate=dofile(folder..'cat_names.lua').validate,accept=accept})
 end
 adapters.attachAppearanceControls=function(widget,cat,callbacks)return controls:attach(widget,cat,callbacks)end
 adapters.openAppearanceEditor=function(cat,callbacks)
  local pause=assert(findPause(),'Open the pause menu before editing appearances')
  -- close() restores the borrowed native background/footer before native editor
  -- initialization searches the pause hierarchy or switches the camera.
  menu={pause=pause,session=ctx.snapshot(),tab=ctx.ui.tab,reopen=ctx.ui.opened==true}
  if ctx.ui.opened then ctx.ui.close()end
  menu.visibility=pause:GetVisibility()
  return editor:open(cat,callbacks)
 end
 adapters.closeAppearanceEditor=function(handle)
  if ctx.textPrompt and ctx.textPrompt.active()then ctx.textPrompt.cancel()end
  -- An integration precondition can fail before editor:open allocates a handle.
  -- In that case there is no widget/actor to close and no callback will arrive.
  -- Still finish the already-started native transaction through deferred END.
  if not editor:state()then return controller:onEditorClosed()end
  return editor:close(handle)
 end
 adapters.releaseAppearanceEditor=function(handle)
  local ok,err=editor:release(handle)
  if ok==false then error(err or 'The appearance preview could not be released')end
  return true
 end
 adapters.onAppearanceOpened=function(handle)
  if menu and ctx.valid(menu.pause)then menu.pause:SetVisibility(2);menu.hidden=true end
  if ctx.onAppearanceOpened then ctx.onAppearanceOpened(handle)end
 end
 adapters.onAppearanceClosed=function(handle)
  restorePause()
  if ctx.onAppearanceClosed then ctx.onAppearanceClosed(handle)end
 end
 adapters.refreshCat=function(cat)
  if ctx.portraits then ctx.portraits:invalidate(cat.role)end
  if cat.player then
   local command=dofile(folder..'appearance.lua').nativeTransport(ctx.root..'bin/',ctx.appearanceDllName)
   local s=assert(ctx.snapshot());assert(command(string.format('PLAYER_REFRESH %x',s.pawn:GetAddress())))
   return
  end
  local updated,skipped=world:refresh(cat,editor:state())
  if ctx.log then ctx.log('Appearance world refresh: '..tostring(updated)..' updated, '..tostring(skipped)..' skipped')end
  if ctx.refreshCat then ctx.refreshCat(cat)end
 end
 adapters.onChanged=function(state)
  -- Keep inputs blocked until tick observes native END and release complete.
  if state.phase~='idle'then ctx.appearanceActive=true end
  if ctx.onAppearanceChanged then ctx.onAppearanceChanged(state)end
 end
 controls=dofile(folder..'appearance_controls.lua').new(adapters)
 editor=dofile(folder..'appearance_editor.lua').new(adapters)
 controller=dofile(folder..'appearance.lua').new(adapters)
 function api.state()
  local state=controller:state();state.cleanupError=cleanupError;state.stopped=stopped;return state
 end
 function api.begin(cat,skinValues)
  if closing or stopped then return nil,'The appearance editor is shutting down'end
  if controller:state().phase~='idle' or editor:state() or menu then return nil,'Finish the current appearance edit first'end
  local snapshot=ctx.snapshot()
  if not snapshot or snapshot.offline~=true or snapshot.combat then return nil,'Open the appearance editor outside combat in an offline campaign.'end
  if not findPause()then return nil,'Open the pause menu before editing appearances.'end
  if type(cat)~='table' or type(cat.role)~='number'then return nil,'Choose a living clanmate.'end
  if not cat.player and ctx.validateCat then local ok,err=ctx.validateCat(cat,snapshot);if not ok then return nil,err end end
  if cat.player and (cat.role~=0 or cat.clan~=snapshot.clan)then return nil,'Active player changed.'end
  ctx.appearanceActive=true
  local ok,result,err=pcall(function()return controller:begin(cat.role)end)
  if not ok then cleanupError=tostring(result);return nil,cleanupError end
  if not result and controller:state().phase=='idle'and not editor:state()then
   ctx.appearanceActive=false;finishMenu()
  end
  if result and skinValues then local loaded,why=controller:loadSkin(skinValues);if not loaded then controller:cancel();return nil,why end end
  return result,err
 end
 function api.player(values)
  local s=ctx.snapshot();if not s then return nil,'Load a player character first.'end
  return api.begin({role=0,player=true,clan=s.clan,living=true,name=ctx.playerName(),rank='Your cat'},values)
 end
 local edit=function(cat)
  local ok,err=api.begin(cat)
  if not ok then notify(err or 'The appearance editor could not open.')end
  return ok,err
 end
 ctx.editAppearance=edit;ctx.appearance=api;ctx.appearanceActive=false
 function api.tick()
  if stopped then return true end
  local ok,err=pcall(function()
   local phase=controller:state().phase
   if phase=='opening'or phase=='editing'then
    if closing then assert(controller:cancel())else assert(controller:checkContext())end
   end
   phase=controller:state().phase
   if phase=='editing'then
    local h=editor:state()
    -- A removed/destroyed native screen is cancellation, never implicit Apply.
    if not h or not ctx.valid(h.widget)or not h.widget:IsInViewport()then assert(controller:cancel())
    else assert(controller:pollNativeIntent());editor:tick();controls:tick()end
   elseif phase=='closing'then
    if not editor:state()then assert(controller:onEditorClosed())
    else assert(controller:cancel())end -- retries a failed adapter close
   elseif phase=='applied'then
    assert(editor:close()) -- preserve applied state while retrying teardown
   elseif phase=='guarded_error'then
    local h=editor:state()
    if h and not h.closed then assert(editor:close(h))end
    if controller:state().phase=='guarded_error'then assert(controller:retryCleanup())end
   end
   if controller:state().phase=='idle'then
    -- The transaction's release callback is best-effort; retain/retry ownership
    -- here if destroying the preview failed instead of silently losing it.
    local h=editor:state()
    if h then assert(h.closed,'Appearance preview is still open');assert(editor:release(h))end
    ctx.appearanceActive=false;finishMenu()
   end
  end)
  if not ok then
   if cleanupError~=tostring(err)and ctx.log then ctx.log('Appearance integration: '..tostring(err))end
   cleanupError=tostring(err);return false,cleanupError
  end
  cleanupError=nil;return true
 end
 function api.shutdown()
  if stopped then return true end
  closing=true
  local ok,err=api.tick();if not ok then return false,err end
  if controller:state().phase~='idle'or editor:state()then return false,'Appearance editor cleanup is pending'end
  controls:shutdown();stopped=true
  if ctx.editAppearance==edit then ctx.editAppearance=previousEdit end
  if ctx.appearance==api then ctx.appearance=nil end
  ctx.appearanceActive=false;return true
 end
 return api
end
return M
