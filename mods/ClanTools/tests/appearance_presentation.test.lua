local module=dofile('mods/ClanTools/Scripts/appearance_presentation.lua')
function StaticFindObject(name)return name end
function FText(s)return s end
local hud={visibility=4,IsInViewport=function()return true end,GetVisibility=function(s)return s.visibility end,SetVisibility=function(s,v)s.visibility=v end}
function FindAllOf(name)assert(name=='GuiHudWrc');return{hud}end
local pc={bShouldPerformFullTickWhenPaused=false}
local title={value='CAT CREATION',GetAddress=function()return 1 end,
 IsA=function(_,c)return c=='/Script/UMG.TextBlock'end,
 GetText=function(s)return{ToString=function()return s.value end}end,SetText=function(s,v)s.value=v end}
local h={pc=pc,widget={WidgetTree={RootWidget=title}}}
for _,name in ipairs({'mcGuiFooter','HoldButtonBack','mcGuiScreenStep'})do h.widget[name]={visibility=0,SetVisibility=function(s,v)s.visibility=v end}end
local api=module.new({valid=function(o)return o~=nil and not o.dead end})
api:open(h);assert(pc.bShouldPerformFullTickWhenPaused and hud.visibility==2 and title.value=='')
hud.visibility=0;title.value='CAT CREATION';api:tick(h);assert(hud.visibility==2 and title.value=='')
for _,name in ipairs({'mcGuiFooter','HoldButtonBack','mcGuiScreenStep'})do assert(h.widget[name].visibility==2);h.widget[name].visibility=0 end
api:tick(h)
for _,name in ipairs({'mcGuiFooter','HoldButtonBack','mcGuiScreenStep'})do assert(h.widget[name].visibility==2,'Native category change must not restore creator navigation')end
api:restore(h);assert(hud.visibility==4 and pc.bShouldPerformFullTickWhenPaused)
api:restore(h,true);assert(not pc.bShouldPerformFullTickWhenPaused and not h.presentation)
api:restore(h,true)
pc.bShouldPerformFullTickWhenPaused=true;api:open(h);api:restore(h,true);assert(pc.bShouldPerformFullTickWhenPaused)
print('PASS HUD/title isolation, exact visibility restoration and paused-camera ticking retained through closing frames')
