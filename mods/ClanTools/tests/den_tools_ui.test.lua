local M=dofile('mods/ClanTools/Scripts/den_tools_ui.lua')
local buttons={};local texts={};local canceled=0;local state={active=true,rows={{tag='test',name='SM_Fern_Pot',copies=0}}}
local b={status=function()return state end,begin=function(tag)assert(tag=='test');state.preview={tag=tag,selected=0,layout={offset={x=0,y=0,z=0,yaw=0},copies={}}};return true end,
 cancel=function()canceled=canceled+1;state.preview=nil;return true end}
local p={button=function(label,x,y,w,h,fn,selected,enabled)
 assert(w>=410 and h>=62 and x>=430 and x+w<=1780 and y+h<=990);buttons[label]={fn=fn,enabled=enabled~=false}
end,text=function(label)texts[#texts+1]=label end,panel=function()end,refresh=function()end,notify=function(m)error(m)end}
local ui=M.new({denTools=b},p);ui.page();assert(buttons['Fern Pot']);buttons['Fern Pot'].fn()
buttons={};ui.page();assert(buttons['Apply layout']and buttons['Cancel preview']);assert(not buttons['Remove copy'].enabled)
assert(ui.back()and canceled==1);assert(not ui.back())
state.active=false;buttons={};ui.page();assert(buttons['Refresh decorations'])
print('PASS den native UI sizing, completed-decoration selection, preview actions and Back cancellation')
