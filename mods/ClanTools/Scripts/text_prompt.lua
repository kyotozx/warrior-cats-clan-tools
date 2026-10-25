-- Shared native-styled keyboard/controller text dialog. Its owning screen routes
-- key/command input exclusively here while open; underlying controls stay still.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local model=dofile(folder..'text_entry.lua')
local skin=dofile(folder..'native_skin.lua')
local M={}
function M.new(ctx)
 local api={};local active;local stopped=false
 local lib=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
 local layout=StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
 local function later(fn)ctx.defer(fn)end
 local function close()
  local h=active;active=nil
  if h and ctx.valid(h.widget)then h.widget:RemoveFromParent()end
  lib:SetFocusToGameViewport()
 end
 function api.active()return active~=nil end
 function api.open(options)
  assert(not stopped and not active,'Finish the current text dialog first.')
  local s=assert(ctx.snapshot(),'Load an offline campaign.')
  local pause=assert(options.pause,'Native menu unavailable.')
  local owner=options.owner or pause
  local class=LoadAsset('/Game/Art/UXD/Blueprints/Controls/gui_common/WBP_GuiClanScreenBackground.WBP_GuiClanScreenBackground_C')
  local w=lib:Create(s.gameState,class,s.pc);assert(ctx.valid(w),'Text dialog could not open.')
  local h={widget=w,buttons={},pc=s.pc};active=h
  local good,err=pcall(function()
   local r=w.WidgetTree.RootWidget;r:GetChildAt(0):SetVisibility(2)
   local view=layout:GetViewportSize(s.gameState);local factor=math.min(view.X/1920,view.Y/1080)
   local unit=factor/layout:GetViewportScale(s.gameState);local width,height=view.X/factor,view.Y/factor
   local x=(width-1220)/2;local y=(height-780)/2
   local title=skin.find(ctx,pause.WidgetTree.RootWidget,'mcGuiTitle')
   local body=skin.find(ctx,pause.mcGuiFooter.WidgetTree.RootWidget,'mcGuiTextConfirm')
   local frame=skin.find(ctx,pause.mcGuiPanelGeneral.WidgetTree.RootWidget,'mcGuiFrameStanceInfo_2')
   assert(ctx.valid(title)and ctx.valid(body)and ctx.valid(frame),'Native text dialog style unavailable.')
   local function put(o,xx,yy,ww,hh,z)local slot=r:AddChild(o);slot:SetPosition({X=xx*unit,Y=yy*unit});slot:SetSize({X=ww*unit,Y=hh*unit});slot:SetZOrder(z or 2);return o end
   local dim=StaticConstructObject(StaticFindObject('/Script/UMG.Image'),w.WidgetTree);dim:SetColorAndOpacity({R=0.01,G=0.025,B=0.03,A=0.97});dim:SetVisibility(3);put(dim,0,0,width,height,0)
   skin.cloneImage(ctx,r,w,frame,x,y,1220,780,1/unit,1)
   local function label(value,xx,yy,ww,size,heading)
    local t=StaticConstructObject(StaticFindObject('/Script/UMG.TextBlock'),w.WidgetTree)
    t:SetText(FText(value));t:SetFont((heading and title or body).Font);local font=t.Font;font.Size=size*unit;t:SetFont(font)
    t:SetColorAndOpacity(body.ColorAndOpacity);t:SetVisibility(3);return put(t,xx,yy,ww,size*2.3,3)
   end
   label(options.title or'Enter text',x+45,y+28,1130,34,true)
   h.value=label('',x+45,y+102,1130,28,true)
   h.status=label('',x+45,y+164,1130,18)
   h.model=model.new({value=options.value,maxLength=options.maxLength,validate=options.validate,
    accept=function(value)local result,why=options.accept(value);if result==false then return false,why end;later(function()if active==h then close()end end);return true end,
    cancel=function()if options.cancel then options.cancel()end;later(function()if active==h then close()end end)end})
   for i,key in ipairs(h.model.keys)do
    local column=(i-1)%10;local row=math.floor((i-1)/10)
    local b,bs=skin.createButton(setmetatable({nativeFocusable=false},{__index=ctx}),r,owner,pause,key,x+45+column*113,y+232+row*88,106,70,1/unit,false)
    h.buttons[i]={object=b,skin=bs};b.Slot:SetZOrder(4)
   end
   label('Type on your keyboard, or choose letters with D-pad / arrows. A: select · B: cancel',x+45,y+700,1130,17)
   w:AddToViewport(1000040);lib:SetFocusToGameViewport()
  end)
  if not good then close();error(err)end
  api.tick();return true
 end
 function api.key(name)
  local h=active;if not h then return false end
  h.keys=h.keys or{};if h.keys[name]then return true end
  h.keys[name]=true;later(function()h.keys[name]=nil end)
  local shift=false
  if ctx.valid(h.pc)then shift=h.pc:IsInputKeyDown({KeyName=FName('LeftShift')})or h.pc:IsInputKeyDown({KeyName=FName('RightShift')})end
  if h.model.key(name,shift)then h.rawHandled=true;later(function()h.rawHandled=false end);api.tick()end
  return true
 end
 function api.command(command,event)
  local h=active;if not h then return false end
  if h.rawHandled or h.model.closed then return true end
  if event~=0 and event~=2 then return true end
  h.commands=h.commands or{};local canonical=({[15]=1,[16]=2,[17]=3,[18]=4})[command]or command
  if h.commands[canonical]then return true end
  h.commands[canonical]=true
  -- Native semantic Confirm can precede raw Enter in the same input frame.
  -- Wait for raw text handling before activating a controller keyboard key.
  later(function()
   h.commands[canonical]=nil
   if active~=h or h.rawHandled or h.model.closed then return end
   local dir=({[1]='up',[2]='down',[3]='right',[4]='left',[15]='up',[16]='down',[17]='right',[18]='left'})[command]
   if dir then h.model.navigate(dir)
   elseif event==0 and command==26 then h.model.activate()
   elseif event==0 and command==25 then h.model.cancel()end
   api.tick()
  end)
  return true
 end
 function api.tick()
  local h=active;if not h then return end
  if not ctx.valid(h.widget)then close();return end
  h.value:SetText(FText(h.model.text..'|'));h.status:SetText(FText(h.model.error or'Done saves this text. Cancel keeps the previous value.'))
  for i,b in ipairs(h.buttons)do b.skin:setSelected(i==h.model.index);local k=h.model.keys[i];b.skin:setLabel(#k==1 and(h.model.upper and k or k:lower())or k);b.skin:tick()end
 end
 local pre,post=RegisterHook('/Script/SwtEngine.GuiControl:OnControlClick',function(o)
  local h=active;local object=o:get();if not h or not ctx.valid(object)then return end
  for i,b in ipairs(h.buttons)do if ctx.valid(b.object)and object:GetAddress()==b.object:GetAddress()then later(function()if active==h then h.model.activate(i);api.tick()end end);return end end
 end)
 function api.cancel()if active then active.model.cancel();close()end end
 function api.shutdown()api.cancel();stopped=true;UnregisterHook('/Script/SwtEngine.GuiControl:OnControlClick',pre,post);return true end
 return api
end
return M
