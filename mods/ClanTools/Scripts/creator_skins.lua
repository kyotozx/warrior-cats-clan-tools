local dir=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local nativeSkin=dofile(dir..'native_skin.lua')
local M={}
function M.new(ctx)
 local api={};local panel=dofile(dir..'native_panel.lua').new(ctx);local owner,button,visual;local requested=false;local page=1
 local lib=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
 local function render(p)
  p.text('Your skins',110,100,1700,42,true)
  p.text('Choose a saved look, then continue the original character creator. Your new cat gets its own save.',112,172,1670,21)
  local rows,why=ctx.skins.store.list();local pages=math.max(1,math.ceil(#rows/8));page=math.min(page,pages)
  for i=1,8 do local e=rows[(page-1)*8+i];if e then
   p.button((e.favorite and'* 'or'')..e.label,110+((i-1)%2)*860,280+math.floor((i-1)/2)*135,810,function()
    assert(ctx.valid(owner)and owner:IsInViewport(),'Creator closed.');local ok,err=ctx.skins.creatorLoad(owner,e.id,'All');assert(ok,err);p.close()
   end)
  end end
  if #rows==0 then p.text(why or'No saved skins. Save your current player look from Clan Tools > Appearance > Your cat / Skins.',112,350,1660,23)end
  p.text('Page '..page..' / '..pages..'  |  Applying a skin changes only the preview. The original creator handles saving.',112,820,1660,18)
  p.button('Previous',110,900,380,function()page=page-1;p.refresh()end,page>1)
  p.button('Next',520,900,380,function()page=page+1;p.refresh()end,page<pages)
  p.button('Save this preview',930,900,440,function()ctx.skins.store.save('Creator look '..os.date('%m-%d %H:%M'),ctx.skins.creatorRead(owner));p.notify('Preview saved to your shared skin library.')end)
  p.button('Back to creator',1400,900,410,p.close)
 end
 local function open()if panel.active()then panel.close()elseif ctx.valid(owner)then local ok,err=panel.open(owner,render);if not ok then ctx.log('Creator skins: '..err)end end end
 function api.request()if owner then requested=true;return true end;return false end
 local path='/Script/SwtEngine.SwtScreen:OnKeyPressed'
 local pre,post=RegisterHook(path,function(o,k)
  if ctx.valid(owner)and ctx.valid(o:get())and o:get():GetAddress()==owner:GetAddress()and k:get().KeyName:ToString()=='Gamepad_FaceButton_Top'then requested=true end
 end)
 local clickPath='/Script/SwtEngine.GuiControl:OnControlClick'
 local cp,cq=RegisterHook(clickPath,function(o)if ctx.valid(button)and ctx.valid(o:get())and o:get():GetAddress()==button:GetAddress()then requested=true end end)
 function api.tick(snapshot,snapshotKnown)
  panel.tick();local found
  if not snapshotKnown then snapshot=ctx.snapshot()end
  if not ctx.appearanceActive and not snapshot then
   for _,screen in ipairs(FindAllOf('GuiScreenCustomization')or{})do if ctx.valid(screen)and screen:IsInViewport()and ctx.valid(screen.CatRef)and ctx.valid(screen.CurrentPanel)then found=screen;break end end
  end
  if not found or not ctx.valid(owner)or found:GetAddress()~=owner:GetAddress()then
   panel.close();if ctx.valid(button)then button:RemoveFromParent()end;button=nil;visual=nil;owner=found
  end
  if owner and not button then
   local pc=owner:GetOwningPlayer();local a=setmetatable({snapshot=function()return{gameState=owner,pc=pc}end,nativeButtonClass=LoadAsset('/Game/Art/UXD/Blueprints/Buttons/WBP_GuiButtonCommon1.WBP_GuiButtonCommon1_C')},{__index=ctx})
   local layout=StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary');local v=layout:GetViewportSize(owner);local scale=layout:GetViewportScale(owner)/(v.X/1920)
   button,visual=nativeSkin.createButton(a,owner.WidgetTree.RootWidget,owner,nil,'Skins  [F6 / Y]',1420,25,390,64,scale,false);button.Slot:SetZOrder(999)
  end
  if visual then visual:tick()end
  if requested then requested=false;if owner then open()end end
 end
 function api.shutdown()panel.shutdown();if ctx.valid(button)then button:RemoveFromParent()end;UnregisterHook(path,pre,post);UnregisterHook(clickPath,cp,cq)end
 return api
end
return M
