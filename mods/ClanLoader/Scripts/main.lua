local dir=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local ctx={root=dir..'../',valid=dofile(dir..'runtime_valid.lua').valid}
function ctx.read(p)local f=io.open(p,'rb');if not f then return end;local s=f:read('*a');f:close();return s end
function ctx.write(p,s)local f=assert(io.open(p,'wb'));assert(f:write(s));f:close()end
function ctx.log(s)print('[ClanLoader] '..tostring(s)..'\n')end
local registry=dofile(dir..'registry.lua').new(ctx)
local panel,owner,button,visual;local requested=false;local selected,page=1,1;local lastError
local function render(p)
 local rows=registry.list();selected=math.max(1,math.min(selected,#rows));local current=rows[selected]
 p.text('Mods',110,95,1000,48,true)
 p.text('Manage your community mods',112,175,1600,23)
 local pages=math.max(1,math.ceil(#rows/6));page=math.max(1,math.min(page,pages))
 for i=1,6 do local m=rows[(page-1)*6+i];if m then
  p.button((m.enabled and'ON   'or'OFF   ')..m.name..(m.restart and'  *'or''),110,260+(i-1)*95,730,function()selected=(page-1)*6+i;p.refresh()end)
 end end
 if current then
  p.text(current.name,930,265,850,38,true);p.text('Version '..current.version,932,340,800,23)
  p.text(current.description,932,405,800,22)
  p.text('At startup: '..(current.atStartup and'Enabled'or'Disabled'),932,570,800,22)
  p.text(current.restart and'Restart required to apply this change.'or'Configuration matches this session.',932,625,800,22)
  p.button(current.enabled and'Disable on next launch'or'Enable on next launch',930,710,850,function()registry.toggle(current.id);p.refresh()end,current.id~='ClanLoader')
  p.button(owner:IsA(StaticFindObject('/Script/Wrc.GuiScreenPause'))and'Open settings'or'Load a campaign for settings',930,810,850,function()
   ctx.write(ctx.root..'open-clantools.txt',tostring(os.time()));p.close()
  end,current.id=='ClanTools'and current.atStartup and owner:IsA(StaticFindObject('/Script/Wrc.GuiScreenPause')))
 end
 p.button('Previous',110,900,340,function()page=page-1;p.refresh()end,page>1)
 p.button('Next',480,900,360,function()page=page+1;p.refresh()end,page<pages)
 p.button('Back to game menu',930,900,850,p.close)
end
RegisterKeyBind(Key.F10,function()requested=true end)
local keyPath='/Script/SwtEngine.SwtScreen:OnKeyPressed'
RegisterHook(keyPath,function(o,k)
 if ctx.valid(owner)and ctx.valid(o:get())and o:get():GetAddress()==owner:GetAddress()and k:get().KeyName:ToString()=='Gamepad_RightThumbstick'then requested=true end
end)
RegisterHook('/Script/SwtEngine.GuiControl:OnControlClick',function(o)if ctx.valid(button)and ctx.valid(o:get())and o:get():GetAddress()==button:GetAddress()then requested=true end end)
LoopInGameThreadWithDelay(150,function()
 local ok,err=pcall(function()
  if not panel then panel=dofile(dir..'native_panel.lua').new(ctx)end
  panel.tick();local found=panel.active()and owner or nil
  for _,class in ipairs(found and{}or{'GuiScreenPause','GuiScreenMainMenu'})do
   for _,s in ipairs(FindAllOf(class)or{})do if ctx.valid(s)and s:IsInViewport()and s:GetVisibility()~=2 then found=s;break end end
   if found then break end
  end
  if not found or not ctx.valid(owner)or found:GetAddress()~=owner:GetAddress()then
   panel.close();if ctx.valid(button)then button:RemoveFromParent()end;button=nil;visual=nil;owner=found
  end
  if owner and not button then
   local pc=owner:GetOwningPlayer();local layout=StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary');local v=layout:GetViewportSize(owner)
   local scale=layout:GetViewportScale(owner)/math.min(v.X/1920,v.Y/1080)
   local a=setmetatable({snapshot=function()return{gameState=owner,pc=pc}end,nativeButtonClass=LoadAsset('/Game/Art/UXD/Blueprints/Buttons/WBP_GuiButtonCommon1.WBP_GuiButtonCommon1_C')},{__index=ctx})
   local x=owner:IsA(StaticFindObject('/Script/Wrc.GuiScreenPause'))and 1010 or 1420
   button,visual=dofile(dir..'native_skin.lua').createButton(a,owner.WidgetTree.RootWidget,owner,nil,'Mods  [F10 / R3]',x,25,390,64,scale,false);button.Slot:SetZOrder(998)
  end
  if visual then visual:tick()end
  if requested then requested=false;if panel.active()then panel.close()elseif owner then assert(panel.open(owner,render))else ctx.log('Open the original pause or main menu to manage mods.')end end
 end)
 if not ok and tostring(err)~=lastError then lastError=tostring(err);ctx.log(err)elseif ok then lastError=nil end
end)
ctx.log('Ready. Open the original game menu: Mods [F10 / R3].')
