-- Standalone native menu, usable before a campaign exists (creator / mod hub).
local dir=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local skin=dofile(dir..'native_skin.lua')
local M={}
function M.new(ctx)
 local api={};local h;local lib=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
 local layout=StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
 local function later(fn)ExecuteInGameThreadAfterFrames(1,fn)end
 function api.active()return h~=nil end
 function api.close()
  if not h then return end
  local old=h;h=nil;if old then if ctx.valid(old.widget)then old.widget:RemoveFromParent()end;if ctx.valid(old.owner)then old.owner:SetVisibility(old.visibility)end;if old.closed then old.closed()end end
  lib:SetFocusToGameViewport()
 end
 function api.open(owner,render,closed)
  if h then return false,'Close the current mod panel first.'end
  assert(ctx.valid(owner),'Native screen unavailable.');local pc=owner:GetOwningPlayer();assert(ctx.valid(pc),'Menu controller unavailable.')
  h={owner=owner,visibility=owner:GetVisibility(),pc=pc,render=render,closed=closed,index=1,buttons={},widgets={},seen={}}
  local ok,why=pcall(function()
   local class=LoadAsset('/Game/Art/UXD/Blueprints/Controls/gui_common/WBP_GuiClanScreenBackground.WBP_GuiClanScreenBackground_C')
   h.widget=lib:Create(owner,class,pc);assert(ctx.valid(h.widget),'Could not create native menu.');h.root=h.widget.WidgetTree.RootWidget
   local backdrop=StaticConstructObject(StaticFindObject('/Script/UMG.Image'),h.widget.WidgetTree)
   backdrop:SetColorAndOpacity({R=.012,G=.026,B=.035,A=1});backdrop:SetVisibility(3)
   local bs=h.root:AddChild(backdrop);bs:SetAnchors({Minimum={X=0,Y=0},Maximum={X=1,Y=1}});bs:SetOffsets({Left=0,Top=0,Right=0,Bottom=0});bs:SetZOrder(-100)
   local v=layout:GetViewportSize(owner);h.scale=layout:GetViewportScale(owner)/math.min(v.X/1920,v.Y/1080)
   h.context=setmetatable({snapshot=function()return{gameState=owner,pc=pc}end,nativeButtonClass=LoadAsset('/Game/Art/UXD/Blueprints/Buttons/WBP_GuiButtonCommon1.WBP_GuiButtonCommon1_C'),nativeFocusable=false},{__index=ctx})
   h.widget:AddToViewport(1000030);owner:SetVisibility(2);api.refresh();lib:SetFocusToGameViewport()
  end)
  if not ok then api.close();return false,tostring(why)end;return true
 end
 function api.refresh()
  if not h then return end;local current=h
  for _,w in ipairs(h.widgets)do if ctx.valid(w)then w:RemoveFromParent()end end;h.widgets={};h.buttons={}
  local p={}
  function p.text(value,x,y,width,size,heading)
   local t=StaticConstructObject(StaticFindObject('/Script/UMG.TextBlock'),h.widget.WidgetTree)
   t:SetText(FText(tostring(value)));t:SetAutoWrapText(true);t:SetFont({FontObject=LoadAsset(heading and'/Game/Art/UXD/Fonts/Amarante/Amarante.Amarante'or'/Game/Art/UXD/Fonts/Catamaran/Catamaran.Catamaran'),Size=size/h.scale,TypefaceFontName=FName(heading and'Regular'or'Catamaran-Medium')})
   t:SetColorAndOpacity({SpecifiedColor={R=.91,G=.94,B=.86,A=1},ColorUseRule=0});t:SetVisibility(3)
   local slot=h.root:AddChild(t);slot:SetPosition({X=x/h.scale,Y=y/h.scale});slot:SetSize({X=width/h.scale,Y=size*2.2/h.scale});slot:SetZOrder(20);h.widgets[#h.widgets+1]=t
  end
  function p.button(label,x,y,width,fn,enabled)
   local b,s=skin.createButton(h.context,h.root,h.owner,nil,label,x,y,width,66,h.scale,false);s:setEnabled(enabled~=false)
   h.widgets[#h.widgets+1]=b;h.buttons[#h.buttons+1]={object=b,skin=s,fn=fn,enabled=enabled~=false}
  end
  p.refresh=api.refresh;p.close=api.close
  p.notify=function(message)if h then h.message=tostring(message):gsub('^.-:%d+: ','');api.refresh()end end
  h.render(p);if h~=current then return end
  p.text(h.message or'Arrows / D-pad: choose   Enter / A (Cross): select   Backspace / B (Circle): back',110,1000,1700,18)
  h.index=math.max(1,math.min(h.index,#h.buttons));api.tick()
 end
 local function action(fn)
  local old=h;if not old or old.busy then return end;old.busy=true
  later(function()if h~=old then return end;old.busy=false;local ok,r=pcall(fn);if not ok and h==old then old.message=tostring(r):gsub('^.-:%d+: ','');api.refresh()end end)
 end
 local function route(command)
  if not h then return end;local old=h
  if old.seen[command]then return end;old.seen[command]=true;later(function()old.seen[command]=nil end)
  if command==25 then action(api.close)
  elseif command==26 then local b=h.buttons[h.index];if b and b.enabled then action(b.fn)end
  elseif command>=1 and command<=4 then
   local delta=(command==1 or command==4)and -1 or 1;local start=h.index
   if #h.buttons>0 then repeat h.index=(h.index-1+delta)%#h.buttons+1 until h.buttons[h.index].enabled or h.index==start end
   api.tick()
  end
 end
 local path='/Script/SwtEngine.SwtScreen:OnListenCommand'
 local pre,post=RegisterHook(path,function(o,c,e)
  if h and ctx.valid(o:get())and o:get():GetAddress()==h.owner:GetAddress()then local command=c:get();c:set(0);if e:get()==0 then route(({[15]=1,[16]=2,[17]=3,[18]=4})[command]or command)end end
 end)
 local keyPath='/Script/SwtEngine.SwtScreen:OnKeyPressed'
 local kp,kq=RegisterHook(keyPath,function(o,key)
  if h and ctx.valid(o:get())and o:get():GetAddress()==h.owner:GetAddress()then
   local c=({Up=1,Down=2,Right=3,Left=4,Enter=26,BackSpace=25,Escape=25})[key:get().KeyName:ToString()];if c then route(c)end
  end
 end)
 local clickPath='/Script/SwtEngine.GuiControl:OnControlClick'
 local cp,cq=RegisterHook(clickPath,function(o)if h then for _,b in ipairs(h.buttons)do if ctx.valid(o:get())and o:get():GetAddress()==b.object:GetAddress()and b.enabled then action(b.fn);return end end end end)
 function api.tick()
  if not h then return end
  if not ctx.valid(h.owner)or not h.owner:IsInViewport()then api.close();return end
  for i,b in ipairs(h.buttons)do b.skin:setSelected(i==h.index);b.skin:tick()end
 end
 function api.shutdown()api.close();UnregisterHook(path,pre,post);UnregisterHook(keyPath,kp,kq);UnregisterHook(clickPath,cp,cq)end
 return api
end
return M
