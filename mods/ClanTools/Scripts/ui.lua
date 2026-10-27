-- In-game UMG interface. Art and fonts are loaded from the owner's game.
local M={}
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local nativeSkin=dofile(folder..'native_skin.lua')
local navigationHints=dofile(folder..'navigation_hints.lua')
local themes={dark={bg={.018,.044,.048,1},panel={.035,.077,.078,.96},card={.065,.115,.113,.98},text={.91,.94,.86,1},muted={.51,.66,.63,1},accent={.75,.83,.48,1},line={.14,.25,.23,1}},light={bg={.72,.76,.65,1},panel={.84,.85,.73,.96},card={.91,.91,.81,.98},text={.045,.095,.085,1},muted={.20,.31,.26,1},accent={.24,.40,.17,1},line={.49,.58,.44,1}}}
local function color(c)return{R=c[1],G=c[2],B=c[3],A=c[4]or 1}end
function M.new(ctx)
 local iconTexture=dofile(folder..'menu_icons.lua').new(ctx.valid)
 local api={opened=false,alive=true,tab='party',page=1,selection={},notice=nil}
 local w,root,pause,scale= nil,nil,nil,1
 local widgets,actions,focus={}, {},1
 local controllerFocus=true
 local activationPending=false
 local portraitGeneration=0
 local openedSession
 local function session(s)return s and table.concat({s.profile,tostring(s.slot),tostring(s.gs),tostring(s.worldId)},'|')end
 local function currentSession()return openedSession and openedSession==session(ctx.snapshot())end
 local nativeBackground=dofile(folder..'native_background.lua').new(ctx)
 local backgroundReceipt,nativeFrame
 local tabs={{'party','Party'},{'appearance','Appearance'},{'feedback','Item feedback'},{'admin','Offline admin'},{'crafting','Den crafting'}}
 local settingsTabs={{'keybinds','Game controls'}}
 local settingsMode,returnScreen,returnVisibility,pauseVisibility
 local settingsRenderer,progressionRenderer,travelRenderer,partyRenderer,inventoryRenderer,favoritesRenderer,sandboxRenderer
 local function activeTabs()return settingsMode and settingsTabs or tabs end
 local entries={}
 local toast,toastExpiry
 local hints,hintsAt=navigationHints.build(),-math.huge
 local craftLabels,craftSignature,craftSecond={},'',0
 local lib=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
 local layout=StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
 local titleFont,bodyFont,bgClass
 local palette=themes.dark
 local function put(o,x,y,width,height,z)
  local slot=root:AddChild(o);slot:SetPosition({X=x/scale,Y=y/scale});slot:SetSize({X=width/scale,Y=height/scale});slot:SetZOrder(z or 10);widgets[#widgets+1]=o;return o
 end
 local function construct(class)return StaticConstructObject(StaticFindObject('/Script/UMG.'..class),w.WidgetTree)end
 local function rect(x,y,width,height,c,z)
  local o=construct('Image');o:SetColorAndOpacity(color(c));o:SetVisibility(3);return put(o,x,y,width,height,z)
 end
 local function text(label,x,y,width,size,c,title)
  local o=construct('TextBlock');o:SetText(FText(tostring(label)));o:SetFont({FontObject=title and titleFont or bodyFont,Size=math.floor(size/scale+.5),TypefaceFontName=FName(title and'Regular'or'Catamaran-Medium')});o:SetColorAndOpacity({SpecifiedColor=color(c or palette.text),ColorUseRule=0});o:SetVisibility(3);return put(o,x,y,width,size*2.1,20)
 end
 local function image(asset,x,y,size)
  local o=construct('Image');local a=type(asset)=='string'and LoadAsset(asset)or asset
  if ctx.valid(a)then o:SetBrushFromTexture(a,false)end;o:SetVisibility(3);put(o,x,y,size,size,20);return o
 end
 local function act(fn)
  if api.opened and not currentSession()then api.close();return end
  local ok,r=pcall(fn);if not ok then api.notify(tostring(r))elseif type(r)=='string'then api.notify(r)end
 end
 local function defer(fn)
  local expected=openedSession
  ExecuteInGameThreadAfterFrames(1,function()
   if api.alive and(not expected or(expected==openedSession and currentSession()))then fn()end
  end)
 end
 local function button(label,x,y,width,height,fn,selected,enabled)
  local b,skin=nativeSkin.createButton(ctx,root,pause,pause,label:upper(),x,y,width,height,scale,false)
  widgets[#widgets+1]=b;skin:setEnabled(enabled~=false)
  actions[#actions+1]={object=b,click=skin.click,skin=skin,fn=fn,label=label,enabled=enabled~=false,selected=selected,x=x+width/2,y=y+height/2};return b
 end
 local function panel(x,y,width,height)
  local o=nativeSkin.cloneImage(ctx,root,w,nativeFrame,x,y,width,height,scale,8);widgets[#widgets+1]=o;return o
 end
 local function refresh()if api.opened then api.render()end end
 local primitives={text=text,button=button,panel=panel,image=image,refresh=refresh,notify=function(message)api.notify(message)end}
 primitives.icon=function(name,x,y,size)local texture=iconTexture(name,w);if texture then return image(texture,x,y,size)end end
 primitives.prompt=function(options)options.pause=pause;options.owner=pause;return ctx.textPrompt.open(options)end
 partyRenderer=dofile(folder..'party_tools_ui.lua').new(ctx,primitives)
 settingsRenderer=dofile(folder..'settings_ui.lua').new(ctx,primitives)
 progressionRenderer=dofile(folder..'admin_progression_ui.lua').new(ctx,primitives)
 travelRenderer=dofile(folder..'admin_travel_ui.lua').new(ctx,primitives)
 inventoryRenderer=dofile(folder..'admin_inventory_ui.lua').new(ctx,primitives)
 sandboxRenderer=dofile(folder..'admin_sandbox_ui.lua').new(ctx,primitives)
 ctx.photoToolsUI=dofile(folder..'photo_tools_ui.lua').new(ctx,primitives)
 ctx.denToolsUI=dofile(folder..'den_tools_ui.lua').new(ctx,primitives)
 ctx.workshopUI=dofile(folder..'workshop_ui.lua').new(ctx,primitives)
 local skinsRenderer
 local favoriteActions={}
 for _,entry in ipairs({{'flight','Toggle flight'},{'noclip','Toggle walk through walls'},{'god','Toggle infinite health'},{'heal','Restore health'},{'return_position','Return to previous position'},{'clear_spawned','Clear spawned actors'}})do
  local id,label=entry[1],entry[2];favoriteActions[id]={label=label,run=function()return ctx.admin.action(id,{})end}
 end
 favoriteActions.regroup={label='Regroup companions',run=function()return ctx.followers.command('regroup')end}
 favoriteActions.ignore_enemies={label='Toggle Ignore Enemies',run=function()local b=assert(ctx.avoidance,'Encounter tools unavailable.');return b.set_enabled(not b.status().enabled)end}
 favoriteActions.stamina={label='Toggle infinite stamina',run=function()local b=assert(ctx.sandbox,'Stamina tools unavailable.');return b.set_infinite_stamina(not b.state().infinite_stamina)end}
 favoritesRenderer=dofile(folder..'favorites_ui.lua').new(ctx,primitives,favoriteActions)
 local function selected(role)for i,r in ipairs(api.selection)do if r==role then return i end end end
 local function catByRole(role)for _,c in ipairs(api.cats)do if c.role==role then return c end end end
 local function portrait(cat,x,y,size)
  local im=image('/Game/Art/UXD/Textures/gui_icons/gui_icons_clans/T_UI_Icon_Small_'..ctx.clans[cat.clan]:gsub('Clan','clan')..'.T_UI_Icon_Small_'..ctx.clans[cat.clan]:gsub('Clan','clan'),x,y,size)
  local generation=portraitGeneration
  local function ready(material)
   if api.opened and generation==portraitGeneration and ctx.valid(im)and ctx.valid(material)then im:SetBrushFromMaterial(material)end
  end
  if ctx.portrait then local ok,a=pcall(ctx.portrait,cat,ready);if ok then ready(a)end end
 end
 local function roster(edit)
  local first=(api.page-1)*8+1
  text(edit and 'Choose a clanmate' or 'Your clan',430,edit and 270 or 430,900,25,nil,true)
  text(#api.cats..' cats',1630,edit and 280 or 440,180,16,palette.muted)
  for offset=0,7 do local cat=api.cats[first+offset];if cat then
   local x=430+(offset%2)*690;local y=(edit and 340 or 500)+math.floor(offset/2)*105;local is=selected(cat.role)
   panel(x,y,660,91)
   portrait(cat,x+14,y+11,66);text(cat.name,x+99,y+12,350,20,nil,true);text(cat.rank:gsub('MedicineCat','Medicine cat'),x+99,y+48,300,15,palette.muted)
   button(edit and'Edit' or is and'Remove' or'Add',x+503,y+20,137,53,function()
    if edit then assert(ctx.editAppearance,'Appearance editor is loading.');ctx.editAppearance(cat)
    elseif is then table.remove(api.selection,is);refresh()
    elseif #api.selection<2 then api.selection[#api.selection+1]=cat.role;refresh()
    else api.notify('Your party has two companions. Remove one to add another cat.')end
   end,false,true)
  end end
  local pages=math.max(1,math.ceil(#api.cats/8));local y=edit and 800 or 950
  button('Previous',430,y,160,48,function()api.page=math.max(1,api.page-1);refresh()end,false,api.page>1)
  text('Page '..api.page..' of '..pages,630,y+12,180,15,palette.muted)
  button('Next',820,y,160,48,function()api.page=math.min(pages,api.page+1);refresh()end,false,api.page<pages)
 end
 local function partyPage()
  if api.subtab=='companions'then partyRenderer.page(api.selection,function()api.selection={};for _,c in ipairs(ctx.party.read())do api.selection[#api.selection+1]=c.role end;refresh()end);return end
  text('Choose your companions',430,135,1300,38,nil,true)
  if ctx.followers then local f=ctx.followers.state();button('Companion tools',1400,135,380,60,function()api.subtab='companions';refresh()end,f.enabled,f.supported)end
  text('Explore your story with the clanmates you choose. Two companion slots, including an empty party.',430,202,1330,17,palette.muted)
  for i=1,2 do local x=430+(i-1)*690;panel(x,270,660,124);local cat=catByRole(api.selection[i])
   if cat then portrait(cat,x+18,290,83);text(cat.name,x+120,289,345,25,nil,true);text('COMPANION '..i,x+122,337,300,13,palette.muted);button('Remove',x+495,302,140,50,function()table.remove(api.selection,i);refresh()end)
   else text('+',x+38,292,65,33,palette.muted,true);text('Empty companion slot',x+120,298,460,23,palette.muted,true);text('Add a cat from your clan below',x+122,344,450,14,palette.muted)end
  end
  roster(false)
  button('Restore story party',1100,950,290,50,function()assert(ctx.party.restore());api.selection={};for _,c in ipairs(ctx.party.read())do api.selection[#api.selection+1]=c.role end;api.notify('Story party restored.');refresh()end)
  button('Apply party',1450,945,330,60,function()assert(ctx.party.select(api.selection));api.notify('Party updated. Reopen the pause menu to refresh the game’s Party tab.');refresh()end,true)
 end
 skinsRenderer=dofile(folder..'skins_ui.lua').new(ctx,setmetatable({portrait=portrait},{__index=primitives}))
 local function appearancePage()
  if api.subtab=='skins'then skinsRenderer.page();return end
  button('Your cat / Skins',1400,135,380,62,function()api.subtab='skins';refresh()end)
  text('Make every cat their own',430,135,940,38,nil,true)
  text('Edit names and appearances, randomize a look, or use your saved cosmetic presets.',430,202,1330,17,palette.muted)
  roster(true)
  panel(430,900,1350,98);text('Preview before you save',455,915,1200,21,nil,true);text('Apply the new appearance, cancel your edits, or restore the original look.',455,954,1200,16,palette.muted)
 end
 local function feedbackPage()
  text('Every herb, clearly accounted for',430,135,1350,38,nil,true)
  text('See what you used, what remains, and how much health or stamina was actually restored.',430,202,1330,17,palette.muted)
  panel(430,285,730,430);text('Item-use feedback',465,318,650,28,nil,true)
  button(ctx.settings.feedback and'Notifications: On' or'Notifications: Off',465,390,570,60,function()ctx.settings.feedback=not ctx.settings.feedback;ctx.saveSettings();if ctx.items then ctx.items.set_enabled(ctx.settings.feedback)end;refresh()end,true)
  button('Display time: '..ctx.settings.duration..' seconds',465,480,570,60,function()local d=ctx.settings.duration;ctx.settings.duration=d==3 and 5 or d==5 and 8 or 3;ctx.saveSettings();refresh()end)
  text('The original item-use sound is preserved.',465,595,640,18,palette.muted)
  text('No extra sound is layered over the game.',465,632,640,16,palette.muted)
  panel(1200,285,580,430);text('Notification preview',1235,318,510,24,nil,true)
  text('Used Horsetail Stalks',1235,405,510,24,palette.accent,true);text('4 remaining',1235,460,510,18,palette.muted)
  text('You: HP +25 · 75/100',1235,512,510,22);text('Stamina 42/50',1235,558,510,19,palette.muted)
  text('Example only. Live values reflect the actual item use.',1235,650,510,14,palette.muted)
 end
 local function craftingPage()
  if api.subtab=='workshop'then ctx.workshopUI.page();return end
  if api.subtab=='layout'then ctx.denToolsUI.page();return end
  text('Make your den feel like home',430,135,1350,38,nil,true)
  text('Manage project timers, craft items in your den, or arrange your decorations.',430,202,1330,17,palette.muted)
  local c=ctx.crafting and ctx.crafting.status()or{speed=1,projects={}}
  panel(430,280,1350,180);text('Crafting speed: '..(c.speed=='instant'and'Instant'or tostring(c.speed)..'x'),460,300,1250,26,nil,true)
  local speeds={1,2,5,10,'instant'}
  for i,speed in ipairs(speeds)do button(speed=='instant'and'Instant'or speed..'x',460+(i-1)*252,365,228,60,function()local ok,msg=ctx.crafting.set_speed(speed);assert(ok,msg);api.notify('Crafting speed: '..(speed=='instant'and'Instant'or speed..'x'));refresh()end,c.speed==speed)end
  text('Applies while you are inside your den. Your speed preference is saved. Choose 1x for normal time.',460,485,1250,16,palette.muted)
  text('Current projects',430,555,480,27,nil,true)
  button('Craft any item',970,540,390,62,function()api.subtab='workshop';refresh()end)
  button('Arrange decorations',1390,540,390,62,function()api.subtab='layout';refresh()end)
  local active={};for _,p in ipairs(c.projects or{})do if p.state==1 then active[#active+1]=p end end
  local pages=math.max(1,math.ceil(#active/4));api.page=math.min(api.page,pages);craftLabels={}
  for i=1,4 do local p=active[(api.page-1)*4+i];if p then local y=620+(i-1)*82;panel(430,y,1350,68)
    text(p.name,450,y+15,750,20,nil,true)
    local seconds=math.max(0,math.ceil(p.remaining or 0));local hours=math.floor(seconds/3600);local minutes=math.ceil((seconds%3600)/60)
    craftLabels[p.actor]=text(hours..'h '..minutes..'m remaining',1160,y+20,340,16,palette.muted)
    button('Complete now',1500,y+8,260,52,function()local ok,msg=ctx.crafting.complete_now(p.actor);assert(ok,msg);api.notify('Decoration completed.');refresh()end,true)
  end end
  if #active==0 then text(c.attached and'No decorations are currently being crafted.'or'Enter your den to view its crafting projects.',460,645,1260,23,palette.muted,true)end
  if pages>1 then button('Previous projects',430,960,280,48,function()api.page=math.max(1,api.page-1);refresh()end,false,api.page>1);text('Page '..api.page..' of '..pages,750,968,420,16,palette.muted);button('Next projects',1500,960,280,48,function()api.page=math.min(pages,api.page+1);refresh()end,false,api.page<pages)end
  if c.error then text(c.error,460,925,1260,14,palette.muted)end
 end
 local function adminPage()
  if api.subtab=='progression'then progressionRenderer.page();return end
  if api.subtab=='travel'then travelRenderer.page();return end
  if api.subtab=='items'then inventoryRenderer.page();return end
  if api.subtab=='favorites'then favoritesRenderer.page();return end
  if api.subtab=='sandbox'then sandboxRenderer.page();return end
  if api.subtab=='photo'then ctx.photoToolsUI.page();return end
  text('Your offline sandbox',430,135,1350,38,nil,true);text(ctx.flightInput and ctx.flightInput.tooltip or'Fly: V / B. Camera: arrows / right stick.',430,202,1330,17,palette.muted)
  local cap=ctx.admin.capabilities();local function action(id,args)local ok,msg=ctx.admin.action(id,args);api.notify(msg);refresh();return ok end
  if api.subtab=='movement'then
   local options={{'flight','Flight',cap.flight},{'noclip','Walk through walls',cap.noclip},{'god','Infinite health',cap.god},{'heal','Restore health'},{'speed','Movement speed: '..cap.speed..'x'}}
   for i,o in ipairs(options)do button(o[2]..(o[3]~=nil and(o[3]and'  On'or'  Off')or''),430+((i-1)%2)*690,290+math.floor((i-1)/2)*135,660,105,function()action(o[1],o[1]=='speed'and{multiplier=cap.speed>=3 and 1 or cap.speed+1}or{})end,o[3],cap.actions[o[1]].enabled)end
   local a=ctx.avoidance and ctx.avoidance.status()or{}
   button('Ignore Enemies: '..(a.enabled and'On'or'Off'),1120,560,660,105,function()local _,message=ctx.avoidance.set_enabled(not a.enabled);api.notify(message);refresh()end,a.enabled,a.available)
   local stamina=ctx.sandbox and ctx.sandbox.state()or{}
   button('Infinite stamina: '..(stamina.infinite_stamina and'On'or'Off'),430,695,660,105,function()local _,message=ctx.sandbox.set_infinite_stamina(not stamina.infinite_stamina);api.notify(message);refresh()end,stamina.infinite_stamina,stamina.stamina_supported)
   if a.restoring then text('Enemy detection will resume once you are clear of nearby enemies.',430,822,1340,17,palette.muted)end
  elseif api.subtab=='enemies'then
   local list=cap.enemies;local page=api.spawnPage or 1
   button(api.training and'Training: no XP or item rewards'or'Normal encounters',430,270,1350,64,function()api.training=not api.training;refresh()end,api.training,cap.actions.spawn_training.enabled)
   local spawnAction=api.training and'spawn_training'or'spawn_enemy'
   for i=1,12 do local e=list[(page-1)*12+i];if e then button(e.label,430+((i-1)%3)*458,360+math.floor((i-1)/3)*115,434,92,function()action(spawnAction,{id=e.id,quantity=1})end,false,cap.actions[spawnAction].enabled)end end
   if #list>12 then button('More enemies',430,825,1350,54,function()api.spawnPage=page*12<#list and page+1 or 1;refresh()end)end
  else
   local sections={{'favorites','Favorite actions','Your most-used tools'},{'movement','Movement & survival','Flight, stamina and Ignore Enemies'},{'travel','Map & saved locations','Travel and personal bookmarks'},{'items','Items & supplies','Search, quantities and bundles'},{'enemies','Spawn enemies','Choose an encounter'},{'sandbox','Player progression','XP, moves and combat tools'},{'progression','Clan progression','Fresh-kill pile, bonds and quests'}}
   if ctx.photoTools then sections[#sections+1]={'photo','Photo tools','Camera and scene controls'}end
   if api.subtab=='photo'and ctx.photoToolsUI then ctx.photoToolsUI.page();return end
   for i,row in ipairs(sections)do local x=430+((i-1)%2)*690;local y=275+math.floor((i-1)/2)*143
    button(row[2],x,y,660,89,function()api.subtab=row[1];refresh()end)
    text(row[3],x+14,y+96,630,15,palette.muted)
   end
  end
  button('Remove spawned actors ('..cap.spawned..')',430,900,650,60,function()action('clear_spawned')end)
  button('Reset temporary cheats',1120,900,660,60,function()
   if ctx.sandbox then ctx.sandbox.set_infinite_stamina(false);ctx.sandbox.set_one_hit(false);ctx.sandbox.set_damage_multiplier(1)end
   if ctx.pileLock then ctx.pileLock.reset()end
   if ctx.avoidance then ctx.avoidance.reset()end
   action('reset')
  end,true)
 end
 function api.notify(event)
  if type(event)~='table'then
   local raw=tostring(event)
   -- Keep diagnostic paths in the log; show the actionable message in game.
   event=raw:gsub('^.-%.lua:%d+: ',''):gsub('\nstack traceback:.*','')
   if event~=raw then ctx.log(raw)end
  end
  if type(event)=='table'then api.notice=event.title..'  '..table.concat(event.lines or{},'  •  ')else api.notice=tostring(event)end
  api.noticeUntil=os.time()+ctx.settings.duration;ctx.log(api.notice)
  if toast and ctx.valid(toast)then toast:RemoveFromParent()end
  local s=ctx.snapshot();if not s then return end
  local bc=LoadAsset('/Game/Art/UXD/Blueprints/Controls/gui_common/WBP_GuiClanScreenBackground.WBP_GuiClanScreenBackground_C')
  toast=lib:Create(s.gameState,bc,s.pc);local tr=toast.WidgetTree.RootWidget;tr:GetChildAt(0):SetVisibility(2)
  local dpi=layout:GetViewportScale(s.gameState);local view=layout:GetViewportSize(s.gameState);local width=math.min(600,view.X*.45);local x=view.X-width-40
  local sourceLines=type(event)=='table'and event.lines or{tostring(event)};local lines={}
  for _,line in ipairs(sourceLines or{})do local current='';for word in line:gmatch('%S+')do if #current+#word+1>55 then lines[#lines+1]=current;current=word else current=current==''and word or current..' '..word end end;if current~=''then lines[#lines+1]=current end end
  while #lines>4 do table.remove(lines)end
  local title=type(event)=='table'and event.title or'Clan Tools';local height=85+#lines*33
  local function add(o,px,py,ww,hh)local sl=tr:AddChild(o);sl:SetPosition({X=px/dpi,Y=py/dpi});sl:SetSize({X=ww/dpi,Y=hh/dpi});o:SetVisibility(3);return o end
  local y=view.Y-height-120
  local frame=nativeFrame
  if not ctx.valid(frame)then for _,p in ipairs(FindAllOf('GuiScreenPause')or{})do if ctx.valid(p)then frame=nativeSkin.find(ctx,p.mcGuiPanelGeneral.WidgetTree.RootWidget,'mcGuiFrameStanceInfo_2');if ctx.valid(frame)then break end end end end
  if ctx.valid(frame)then nativeSkin.cloneImage(ctx,tr,toast,frame,x,y,width,height,dpi,5)end
  local font=LoadAsset('/Game/Art/UXD/Fonts/Catamaran/Catamaran.Catamaran')
  local function label(value,yy,size,c)local t=add(StaticConstructObject(StaticFindObject('/Script/UMG.TextBlock'),toast.WidgetTree),x+25,yy,width-50,38);t.Slot:SetZOrder(20);t:SetText(FText(value));t:SetFont({FontObject=font,Size=math.floor(size/dpi),TypefaceFontName=FName('Catamaran-Medium')});t:SetColorAndOpacity({SpecifiedColor=color(c),ColorUseRule=0})end
  label(title,y+18,24,themes.dark.accent);for i,line in ipairs(lines)do label(line,y+60+(i-1)*33,19,themes.dark.text)end
  toast:SetVisibility(3);toast:AddToViewport(1000001);toastExpiry=os.time()+ctx.settings.duration
 end
 function api.render()
  if not w or not ctx.valid(w)then return end
  if not currentSession()then api.close();return end
  portraitGeneration=portraitGeneration+1
  if ctx.portraits then ctx.portraits:beginView()end
  local previousFocus=actions[focus]
  for _,o in ipairs(widgets)do if ctx.valid(o)then o:RemoveFromParent()end end;widgets={};actions={}
  palette=themes[ctx.settings.theme]or themes.dark
  if os.clock()-hintsAt>1 then
   hintsAt=os.clock()
   if ctx.keybinds then local ok,rows=pcall(ctx.keybinds.bindings);if ok and type(rows)=='table'then hints=navigationHints.build(rows)end end
  end
  if ctx.settings.theme=='light'then rect(0,0,1920,1080,{.72,.76,.65,.82},-1)end
  local mark=iconTexture(settingsMode and'keybinds'or'clan-tools',w)
  if mark then image(mark,65,68,48)end
  text(settingsMode and'SETTINGS'or'CLAN TOOLS',mark and 128 or 65,62,550,35,nil,true)
  local clan=ctx.clans[ctx.snapshot().clan];local emblem='T_UI_Icon_Small_'..clan:gsub('Clan','clan')
  image('/Game/Art/UXD/Textures/gui_icons/gui_icons_clans/'..emblem..'.'..emblem,65,222,60)
  text(ctx.playerName():upper(),145,217,220,23,nil,true);text(clan,145,257,210,18,palette.muted)
  local tabIcons={party='party',appearance='appearance',feedback='item-feedback',admin='offline-admin',crafting='den-workshop',keybinds='keybinds'}
  for i,t in ipairs(activeTabs())do
   local y=342+(i-1)*84
   button(t[2],85,y,280,66,function()api.tab=t[1];api.page=1;api.subtab=nil;settingsRenderer.reset();refresh()end,api.tab==t[1])
   local texture=iconTexture(tabIcons[t[1]],w);if texture then image(texture,58,y+17,32)end
  end
  text('NAVIGATION',65,770,300,17,nil,true)
  text(hints.navigate,65,805,310,16,palette.muted)
  text(hints.tabs..': tabs',65,837,320,14,palette.muted)
  button(ctx.settings.theme=='dark'and'Theme: Moonlight'or'Theme: Daylight',60,868,275,62,function()ctx.settings.theme=ctx.settings.theme=='dark'and'light'or'dark';ctx.saveSettings();refresh()end)
  button('Back to game menu',60,958,275,58,api.close)
  if settingsMode then settingsRenderer.keybindPage()
  elseif api.tab=='party'then partyPage()elseif api.tab=='appearance'then appearancePage()elseif api.tab=='feedback'then feedbackPage()elseif api.tab=='admin'then adminPage()elseif api.tab=='crafting'then craftingPage()end
  -- Pause footer labels describe its previous tab (for example Track Quest).
  -- Keep our binding-aware actions visible without borrowing that stale footer.
  text(hints.actions,430,1022,1000,19)
  text(settingsMode and'F7: Controls'or'F6: open / close Clan Tools',1100,1024,470,16,palette.muted)
  if previousFocus then for i,a in ipairs(actions)do if a.enabled and a.x==previousFocus.x and a.y==previousFocus.y then focus=i;break end end end
  if not actions[focus]or not actions[focus].enabled then for i,a in ipairs(actions)do if a.enabled then focus=i;break end end end
 end
 function api.navigate(direction)
  if not api.opened then return end
  if ctx.textPrompt and ctx.textPrompt.active()then ctx.textPrompt.command(({up=1,down=2,right=3,left=4})[direction],0);return end
  controllerFocus=true
  local current=actions[focus]
  if not current or not current.enabled then
   for i,a in ipairs(actions)do if a.enabled then focus=i;return end end;return
  end
  local best,score
  for i,a in ipairs(actions)do if i~=focus and a.enabled then
   local dx,dy=a.x-current.x,a.y-current.y
   local forward=direction=='left'and -dx or direction=='right'and dx or direction=='up'and -dy or dy
   local cross=(direction=='left'or direction=='right')and math.abs(dy)or math.abs(dx)
   local vertical=direction=='up'or direction=='down'
   local sameColumn=(a.x<400)==(current.x<400)
   if forward>1 and(not vertical or sameColumn)then local candidate=forward+cross*3+cross*cross/math.max(forward,1)
    if direction=='right'and current.x<400 and a.x>400 then candidate=cross*10+forward*.1 end
    if not score or candidate<score then best,score=i,candidate end
   end
  end end
  if best then focus=best end
 end
 function api.activate()
  if ctx.textPrompt and ctx.textPrompt.active()then ctx.textPrompt.command(26,0);return end
  local a=actions[focus];if activationPending or not api.opened or not a or not a.enabled then return end
  activationPending=true
  local fn=a.fn;defer(function()activationPending=false;if api.opened then act(fn)end end)
 end
 function api.back()
  if ctx.textPrompt and ctx.textPrompt.active()then ctx.textPrompt.cancel();return end
  if settingsMode and settingsRenderer.back()then return end
  if api.subtab=='favorites'and favoritesRenderer.back()then return end
  if api.subtab=='sandbox'and sandboxRenderer.back()then return end
  if api.subtab=='items'and inventoryRenderer.back()then return end
  if api.subtab=='layout'and ctx.denToolsUI.back()then return end
  if api.subtab=='workshop'and ctx.workshopUI.back()then return end
  if api.subtab=='progression'and progressionRenderer.back()then return end
  if api.subtab=='travel'then travelRenderer.back()end
  if api.subtab then api.subtab=nil;api.spawnPage=1;api.render()else api.close()end
 end
 function api.cycleTab(delta)
  if not api.opened then return end
  if ctx.textPrompt and ctx.textPrompt.active()then return end
  local list=activeTabs();local index=1;for i,t in ipairs(list)do if t[1]==api.tab then index=i end end
  index=((index-1+delta)%#list)+1
  api.tab=list[index][1];api.page=1;api.subtab=nil;settingsRenderer.reset();focus=index;controllerFocus=true;api.render()
 end
 function api.open(nativePause)
  if api.opened or not api.alive or ctx.appearanceActive then return end
  pause=nativePause;local s=assert(ctx.snapshot(),'Load a campaign first.');assert(ctx.valid(pause),'Open the pause menu first.')
  openedSession=session(s)
  titleFont=LoadAsset('/Game/Art/UXD/Fonts/Amarante/Amarante.Amarante')
  bodyFont=LoadAsset('/Game/Art/UXD/Fonts/Catamaran/Catamaran.Catamaran')
  bgClass=LoadAsset('/Game/Art/UXD/Blueprints/Controls/gui_common/WBP_GuiClanScreenBackground.WBP_GuiClanScreenBackground_C')
  api.cats=ctx.getCats();api.selection={};for _,c in ipairs(ctx.party.read())do api.selection[#api.selection+1]=c.role end
  scale=layout:GetViewportScale(s.gameState);local view=layout:GetViewportSize(s.gameState);scale=scale/(view.X/1920)
  w=lib:Create(s.gameState,bgClass,s.pc);root=w.WidgetTree.RootWidget;api.widget=w
  root:GetChildAt(0):SetVisibility(2)
  nativeFrame=assert(nativeSkin.find(ctx,pause.mcGuiPanelGeneral.WidgetTree.RootWidget,'mcGuiFrameStanceInfo_2'),'Native menu frame unavailable')
  backgroundReceipt=nativeBackground.attach(pause,root)
  pauseVisibility=pause:GetVisibility()
  w:AddToViewport(1000000);pause:SetVisibility(2);api.opened=true;focus=1
  for i,t in ipairs(activeTabs())do if t[1]==api.tab then focus=i end end
  controllerFocus=true;api.render();lib:SetInputMode_GameOnly(s.pc,false)
 end
 function api.close()
  portraitGeneration=portraitGeneration+1
  if ctx.portraits then ctx.portraits:cancelPending()end
  if ctx.textPrompt and ctx.textPrompt.active()then ctx.textPrompt.cancel()end
  if backgroundReceipt then nativeBackground.restore(backgroundReceipt);backgroundReceipt=nil end
  if w and ctx.valid(w)then w:RemoveFromParent()end
  if pause and ctx.valid(pause)then pause:SetVisibility(pauseVisibility or 0)end
  if returnScreen and ctx.valid(returnScreen)then returnScreen:SetVisibility(returnVisibility or 0)end
  returnScreen=nil;returnVisibility=nil;pauseVisibility=nil
  if settingsMode then api.tab='party'end;settingsMode=false;settingsRenderer.reset()
  api.opened=false;activationPending=false;widgets={};actions={};w=nil;openedSession=nil;api.cats={};api.selection={};api.notice=nil;api.subtab=nil
 end
 function api.tick()
  progressionRenderer.tick()
  if toast and toastExpiry and os.time()>=toastExpiry then if ctx.valid(toast)then toast:RemoveFromParent()end;toast=nil end
  if api.opened and(not currentSession()or not ctx.valid(pause)or not pause:IsInViewport())then api.close()end
  if api.opened then for i,a in ipairs(actions)do a.skin:setSelected(controllerFocus and i==focus and a.enabled or false)end end
  if api.opened and api.tab=='crafting'and ctx.crafting and os.time()~=craftSecond then
   craftSecond=os.time();local current=ctx.crafting.status();local ids={}
   for _,p in ipairs(current.projects or{})do if p.state==1 then ids[#ids+1]=p.actor;local label=craftLabels[p.actor];if label and ctx.valid(label)then local seconds=math.max(0,math.ceil(p.remaining or 0));label:SetText(FText(math.floor(seconds/3600)..'h '..math.ceil((seconds%3600)/60)..'m remaining'))end end end
   local signature=table.concat(ids,',');if signature~=craftSignature then craftSignature=signature;api.render()end
  end
 end
 function api.attach(p)
  if not ctx.valid(p)or not p:IsInViewport()then return end
  local id=p:GetAddress();local controls=ctx.valid(p.CurrentPanel)and ctx.valid(p.mcGuiPanelControls)and p.CurrentPanel:GetAddress()==p.mcGuiPanelControls:GetAddress()
  if entries[id]and ctx.valid(entries[id].button)then entries[id].page=controls and'keybinds'or nil;entries[id].skin:setLabel(controls and'EDIT KEYBINDS  [F7 / Y]'or'CLAN TOOLS  [F6 / Y]');return end
  local s=ctx.snapshot();if not s then return end
  local r=p.WidgetTree.RootWidget
  local dpi=layout:GetViewportScale(s.gameState);local viewport=layout:GetViewportSize(s.gameState)
  local b,skin=nativeSkin.createButton(ctx,r,p,p,'CLAN TOOLS  [F6 / Y]',viewport.X-465,32,400,70,dpi,true)
  b.Slot:SetZOrder(999);entries[id]={button=b,pause=p,owner=p,skin=skin,page=controls and'keybinds'or nil}
 end
 function api.attachSettings(screen,p)
  if not ctx.valid(screen)or not screen:IsInViewport()then return end
  local id=screen:GetAddress();if entries[id]and ctx.valid(entries[id].button)then return end
  local s=ctx.snapshot();if not s then return end
  local dpi=layout:GetViewportScale(s.gameState);local viewport=layout:GetViewportSize(s.gameState)
  local b,skin=nativeSkin.createButton(ctx,screen.WidgetTree.RootWidget,screen,p,'EDIT KEYBINDS  [F7 / Y]',viewport.X-465,32,400,70,dpi,true)
  b.Slot:SetZOrder(999);entries[id]={button=b,pause=p,owner=screen,skin=skin,page='keybinds'}
 end
 function api.openSettings(p,page,owner)
  if ctx.appearanceActive then return end
  if api.opened then api.close()end
  settingsMode=true;api.tab='keybinds';api.subtab=nil
  if owner and owner:GetAddress()~=p:GetAddress()then returnScreen=owner;returnVisibility=owner:GetVisibility();owner:SetVisibility(2)end
  api.open(p)
 end
 function api.openEntry(p)
  local e=entries[p:GetAddress()]
  if e and e.page then api.openSettings(e.pause,e.page,e.owner)else api.open(p)end
 end
 function api.requestSettings(page)
  local function show()
   local p,owner
   for _,screen in ipairs(FindAllOf('GuiScreenPause')or{})do if ctx.valid(screen)and screen:IsInViewport()then p=screen;break end end
   for _,screen in ipairs(FindAllOf('GuiPopupCommonSettings')or{})do if ctx.valid(screen)and screen:IsInViewport()and screen:GetVisibility()~=2 then owner=screen;break end end
   if p then api.openSettings(p,page,owner);return true end
  end
  if show()then return end
  local s=ctx.snapshot();if not s then return end;s.pc:OnListenCommand(89,0)
  ExecuteInGameThreadWithDelay(250,function()if api.alive and not ctx.appearanceActive then show()end end)
 end
 function api.pointerEntry()
  if api.opened or ctx.appearanceActive then return end
  local s=ctx.snapshot();if not s then return end
  local mouse={};if not s.pc:GetMousePosition(mouse,mouse)then return end
  local view=layout:GetViewportSize(s.gameState)
  if mouse.LocationX<view.X-465 or mouse.LocationX>view.X-65 or mouse.LocationY<32 or mouse.LocationY>102 then return end
  for _,entry in pairs(entries)do if ctx.valid(entry.owner)and entry.owner:IsInViewport()and entry.owner:GetVisibility()~=2 then api.openEntry(entry.owner);return end end
 end
 local hookPre,hookPost=RegisterHook('/Script/SwtEngine.GuiControl:OnControlClick',function(o)
  local object=o:get();if not ctx.valid(object)then return end
  local id=object:GetAddress();for _,a in ipairs(actions)do if a.enabled and ctx.valid(a.object)and a.object:GetAddress()==id then
   -- Let Slate finish dispatching before rebuilding/removing its widget tree.
   local fn=a.fn;defer(function()if api.opened then act(fn)end end);return
  end end
  if not api.opened and not ctx.appearanceActive then for _,entry in pairs(entries)do if ctx.valid(entry.button)and entry.button:GetAddress()==id then defer(function()act(function()api.openEntry(entry.owner)end)end);return end end end
 end)
 -- The original screen remains mounted so its camera and pause state survive.
 -- Route commands exclusively to this panel while that exact screen is hidden.
 local commandPre,commandPost=RegisterHook('/Script/SwtEngine.SwtScreen:OnListenCommand',function(o,command,event)
  if not api.alive then return end
  if api.opened and ctx.textPrompt and ctx.textPrompt.active()then ctx.textPrompt.command(command:get(),event:get());command:set(0);return end
  if ctx.appearanceActive then
   local target=o:get()
   if ctx.valid(target)and ctx.valid(pause)and target:GetAddress()==pause:GetAddress()then command:set(0)end
   return
  end
  if api.opened and ctx.valid(pause)then
   local target=o:get()
   if ctx.valid(target)and(target:GetAddress()==pause:GetAddress()or(ctx.valid(returnScreen)and target:GetAddress()==returnScreen:GetAddress()))then
    local value,phase=command:get(),event:get();command:set(0)
    if returnScreen and target:GetAddress()~=returnScreen:GetAddress()then return end
    local direction=({[1]='up',[2]='down',[3]='right',[4]='left',[15]='up',[16]='down',[17]='right',[18]='left'})[value]
    if direction and(phase==0 or phase==2)then api.navigate(direction)
    elseif phase==0 then
     if value==26 then api.activate()
     elseif value==25 then defer(function()if api.opened then api.back()end end)
     elseif value==9 or value==10 then defer(function()api.cycleTab(value==9 and -1 or 1)end)end
    end
   end
  elseif event:get()==0 and command:get()==8 then
   local target=o:get();if ctx.valid(target)then local entry=entries[target:GetAddress()]
    if entry and entry.owner:IsInViewport()and entry.owner:GetVisibility()~=2 then command:set(0);defer(function()api.openEntry(entry.owner)end)end
   end
  end
 end)
 local keyPre,keyPost=RegisterHook('/Script/SwtEngine.SwtScreen:OnKeyPressed',function(o,key)
  if api.opened and ctx.textPrompt and ctx.textPrompt.active()then ctx.textPrompt.key(key:get().KeyName:ToString());return end
  if api.opened or not api.alive or ctx.appearanceActive then return end
  local target=o:get();if not ctx.valid(target)then return end
  local entry=entries[target:GetAddress()];if not entry or not entry.owner:IsInViewport()or entry.owner:GetVisibility()==2 then return end
  if key:get().KeyName:ToString()=='Gamepad_FaceButton_Top'then defer(function()api.openEntry(entry.owner)end)end
 end)
 function api.shutdown()
  api.alive=false
  api.close();if toast and ctx.valid(toast)then toast:RemoveFromParent()end
  for _,e in pairs(entries)do if ctx.valid(e.button)then e.button:RemoveFromParent()end end;entries={}
  UnregisterHook('/Script/SwtEngine.GuiControl:OnControlClick',hookPre,hookPost)
  UnregisterHook('/Script/SwtEngine.SwtScreen:OnListenCommand',commandPre,commandPost)
  UnregisterHook('/Script/SwtEngine.SwtScreen:OnKeyPressed',keyPre,keyPost)
 end
 function api.navigationState()local a=actions[focus];return{index=focus,label=a and a.label,tab=api.tab,opened=api.opened}end
 return api
end
return M
