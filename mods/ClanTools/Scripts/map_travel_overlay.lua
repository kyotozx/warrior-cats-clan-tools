-- Non-interactive native-font hint above the map footer. Never takes focus.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local skin=dofile(folder..'native_skin.lua')
local M={}
function M.new(ctx)
 local api={};local widget,caption,body,footer;local last
 function api.hide()
  if ctx.valid(widget)then widget:RemoveFromParent()end
  widget,caption,body,footer,last=nil,nil,nil,nil,nil
 end
 local function create(s)
  local lib=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
  local layout=StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
  local class=LoadAsset('/Game/Art/UXD/Blueprints/Controls/gui_common/WBP_GuiClanScreenBackground.WBP_GuiClanScreenBackground_C')
  assert(ctx.valid(lib)and ctx.valid(layout)and ctx.valid(class),'Native map hint assets are unavailable.')
  widget=lib:Create(s.gameState,class,s.pc);assert(ctx.valid(widget),'Could not create map hint.')
  local root=widget.WidgetTree.RootWidget;assert(ctx.valid(root),'Native map hint root is unavailable.')
  local background=root:GetChildAt(0);if ctx.valid(background)then background:SetVisibility(2)end
  local dpi=layout:GetViewportScale(s.gameState);local view=layout:GetViewportSize(s.gameState)
  assert(type(dpi)=='number'and dpi>0 and view.X>0 and view.Y>0,'Map viewport is unavailable.')
  local scale=math.min(view.X/1920,view.Y/1080);local width=math.min(view.X-40*scale,1060*scale)
  local x=(view.X-width)/2;local y=view.Y-270*scale
  -- Reuse an existing native pause frame if loaded. Text still uses the game's
  -- fonts when pause has never been opened; no substitute panel is invented.
  for _,pause in ipairs(FindAllOf('GuiScreenPause')or{})do if ctx.valid(pause)then
   local ok,frame=pcall(function()return skin.find(ctx,pause.mcGuiPanelGeneral.WidgetTree.RootWidget,'mcGuiFrameStanceInfo_2')end)
   if ok and ctx.valid(frame)then skin.cloneImage(ctx,root,widget,frame,x,y,width,164*scale,dpi,5);break end
  end end
  local font=LoadAsset('/Game/Art/UXD/Fonts/Catamaran/Catamaran.Catamaran');assert(ctx.valid(font),'Native map hint font is unavailable.')
  local function text(yOffset,size)
   local t=StaticConstructObject(StaticFindObject('/Script/UMG.TextBlock'),widget.WidgetTree)
   t:SetFont({FontObject=font,Size=math.max(12,math.floor(size*scale/dpi)),TypefaceFontName=FName('Catamaran-Medium')})
   t:SetColorAndOpacity({SpecifiedColor={R=1,G=1,B=1,A=1},ColorUseRule=0})
   t:SetShadowColorAndOpacity({R=0,G=0,B=0,A=1});t:SetShadowOffset({X=1,Y=1})
   local slot=root:AddChild(t);slot:SetPosition({X=(x+25*scale)/dpi,Y=(y+yOffset*scale)/dpi});slot:SetSize({X=(width-50*scale)/dpi,Y=48*scale/dpi});slot:SetZOrder(10)
   t:SetVisibility(3);return t
  end
  caption=text(12,23);body=text(58,20);footer=text(103,18)
  widget:SetVisibility(3);widget:AddToViewport(1000030)
 end
 function api.show(s,title,line,detail)
  local ok,why=pcall(function()
   if not ctx.valid(widget)then create(s)end
   local value=title..'\n'..line..'\n'..detail
   if value~=last then caption:SetText(FText(title));body:SetText(FText(line));footer:SetText(FText(detail));last=value end
  end)
  if not ok then api.hide();return false,tostring(why)end
  return true
 end
 return api
end
return M
