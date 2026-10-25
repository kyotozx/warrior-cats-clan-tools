-- Restore every borrowed gameplay UI/controller setting on cancel, apply or
-- partial-open failure. All widget/title changes belong to the owned editor.
local M={}
function M.new(ctx)
 local valid=ctx.valid
 local panel=StaticFindObject('/Script/UMG.PanelWidget')
 local user=StaticFindObject('/Script/UMG.UserWidget')
 local text=StaticFindObject('/Script/UMG.TextBlock')
 local api={}
 local function hideCreatorTitle(h)
  if not valid(h.widget)then return end
  -- Native category transitions make these creator navigation widgets visible
  -- again. They belong to our private screen and must stay hidden while the
  -- mod's transactional Cancel/Apply footer owns editor completion.
  for _,name in ipairs({'canvasPanelTitle','mcGuiFooter','HoldButtonBack','mcGuiScreenStep'})do
   local control=h.widget[name];if valid(control)then control:SetVisibility(2)end
  end
  local seen={}
  local function walk(w,depth)
   if depth>64 or not valid(w)or seen[w:GetAddress()]then return end
   seen[w:GetAddress()]=true
   if w:IsA(text)then
    local value=w:GetText():ToString():upper():gsub('%s+',' ')
    if value=='CAT CREATION'then w:SetText(FText(''))end
   end
   if w:IsA(panel)then for i=0,w:GetChildrenCount()-1 do walk(w:GetChildAt(i),depth+1)end
   elseif w:IsA(user)and valid(w.WidgetTree)then walk(w.WidgetTree.RootWidget,depth+1)end
  end
  if valid(h.widget.WidgetTree)then walk(h.widget.WidgetTree.RootWidget,0)end
 end
 function api:open(h)
  h.presentation=h.presentation or{hud={}}
  local p=h.presentation
  assert(valid(h.pc),'Appearance controller unavailable')
  p.fullTick=h.pc.bShouldPerformFullTickWhenPaused
  assert(type(p.fullTick)=='boolean'or p.fullTick==0 or p.fullTick==1,'Cannot preserve paused camera ticking')
  h.pc.bShouldPerformFullTickWhenPaused=type(p.fullTick)=='boolean'and true or 1
  p.tickSaved=true
  for _,hud in ipairs(FindAllOf('GuiHudWrc')or{})do
   if valid(hud)and hud:IsInViewport()then
    p.hud[#p.hud+1]={widget=hud,visibility=hud:GetVisibility()}
    hud:SetVisibility(2)
   end
  end
  hideCreatorTitle(h)
 end
 function api:tick(h)
  if not h.presentation then return end
  for _,saved in ipairs(h.presentation.hud)do if valid(saved.widget)then saved.widget:SetVisibility(2)end end
  hideCreatorTitle(h)
 end
 function api:restore(h,final)
  local p=h.presentation;if not p then return end
  for _,saved in ipairs(p.hud)do if valid(saved.widget)then saved.widget:SetVisibility(saved.visibility)end end
  p.hud={}
  -- Keep the camera updating through the two closing frames so it refreshes
  -- the restored gameplay view before paused ticking returns to its old value.
  if final then
   if p.tickSaved and valid(h.pc)then h.pc.bShouldPerformFullTickWhenPaused=p.fullTick;p.tickSaved=false end
   h.presentation=nil
  end
 end
 return api
end
return M
