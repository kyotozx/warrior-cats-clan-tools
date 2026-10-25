local M=dofile('mods/ClanTools/Scripts/workshop_ui.lua')
local buttons,texts={},{};local available=false;local canceled,applied=0,0;local options
local entry={index=1,name='Moss Nest',category='Decoration',size='Medium',icon='native/icon'}
local b={catalog=function()return{entry}end,available=function()return available end,cancel=function()canceled=canceled+1 end,
 preview=function(_,q,free)return true,{token='one',entry=entry,quantity=q,free=free,current=0,after=q,allowed=true,costs={{name='Moss',icon='native/moss',current=7,need=free and 0 or 3}}}end,
 apply=function(token)assert(token=='one');applied=applied+1;return true,{complete=true,message='Crafted.',entry=entry,after=1,backup='saved'}end}
local p={button=function(label,x,y,w,h,fn,selected,enabled)
 assert(x>=430 and x+w<=1780 and y+h<=990 and w>=215 and h>=55,label);buttons[label]={fn=fn,enabled=enabled~=false}
end,text=function(label)texts[#texts+1]=label end,panel=function()end,image=function()end,refresh=function()end,notify=function(m)error(m)end,prompt=function(o)options=o end}
local ui=M.new({workshop=b,workshopVerified=true},p)
ui.page();assert(not buttons['Moss Nest'].enabled);available=true;ui.page();assert(buttons['Moss Nest'].enabled)
buttons['Quantity: 1'].fn();assert(options.validate('0')==nil and options.validate('99')=='99')
buttons['Cost: Materials'].fn();ui.page();assert(buttons['Cost: Free'])
buttons['Moss Nest'].fn();buttons={};ui.page();assert(buttons['Confirm free craft'].enabled)
assert(ui.back()and canceled==1);assert(not ui.back())
ui.page();buttons['Moss Nest'].fn();ui.page();buttons['Confirm free craft'].fn();ui.page();assert(applied==1 and buttons['Back to workshop'])
buttons['Back to workshop'].fn();assert(not ui.back())
print('PASS workshop native UI bounds, den gating, quantity validation, free review, confirmation and Back navigation')
