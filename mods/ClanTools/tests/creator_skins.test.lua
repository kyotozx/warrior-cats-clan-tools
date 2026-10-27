local originalDofile=dofile
local hooks,opened,closed={},0,0
local current,active,label,renderPanel
local panel={active=function()return active end,close=function()active=false;closed=closed+1 end,tick=function()end,shutdown=function()end}
function panel.open(owner,render)assert(owner==current);active=true;opened=opened+1;renderPanel=render;return true end
local function object(id)
 return{GetAddress=function()return id end,RemoveFromParent=function(self)self.dead=true end,Slot={SetZOrder=function()end}}
end
local skin={createButton=function(_,_,_,_,caption)label=caption;return object(100),{tick=function()end}end}
function dofile(path)
 if path:match('native_skin.lua$')then return skin end
 if path:match('native_panel.lua$')then return{new=function()return panel end}end
 return originalDofile(path)
end
function RegisterHook(path,fn)hooks[path]=fn;return 1,2 end
function UnregisterHook()end
function StaticFindObject()return{GetViewportSize=function()return{X=1920,Y=1080}end,GetViewportScale=function()return 1 end}end
function LoadAsset()return object(200)end
function FindAllOf()return current and{current}or{}end
local ctx={valid=function(o)return type(o)=='table'and not o.dead end,log=function(s)error(s)end,skins={store={list=function()return{}end}}}
local function creator(id)
 local o=object(id);o.CatRef=object(id+1);o.CurrentPanel=object(id+2);o.WidgetTree={RootWidget=object(id+3)};o.mounted=true
 function o:IsInViewport()return self.mounted end
 function o:GetOwningPlayer()return object(300)end
 return o
end
local api=dofile('mods/ClanTools/Scripts/creator_skins.lua').new(ctx);dofile=originalDofile
local function key(name)
 hooks['/Script/SwtEngine.SwtScreen:OnKeyPressed']({get=function()return current end},{get=function()return{KeyName={ToString=function()return name end}}end})
end
current=creator(1);api.tick(nil,true);assert(label=='Skins  [F6 / L3]')
key('Gamepad_FaceButton_Top');api.tick(nil,true);assert(opened==0,'Y must remain the native creator confirmation')
key('Gamepad_LeftThumbstick');api.tick(nil,true);assert(opened==1 and active)
local back
renderPanel({text=function()end,button=function(c,_,_,_,fn)if c=='Back to creator'then back=fn end end,close=panel.close})
assert(back);back();assert(not active)
assert(api.request());api.tick(nil,true);assert(opened==2 and active,'F6 still opens the library')
assert(api.request());api.tick(nil,true);assert(not active,'F6 closes the library')
assert(api.request());current=creator(20);api.tick(nil,true);assert(opened==2,'Do not transfer a queued request to another creator')
current.mounted=false;assert(not api.request());api.tick(nil,true);assert(not active)
current=creator(40);api.tick(nil,true);assert(api.request());current.CatRef.dead=true;api.tick(nil,true);assert(opened==2,'Do not open after native confirmation removes the preview')
api.shutdown()
print('PASS creator confirmation isolation, F6/L3 library, Back and stale-owner requests')
