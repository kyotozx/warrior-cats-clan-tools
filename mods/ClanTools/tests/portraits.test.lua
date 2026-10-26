local dir=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local valid=function(o)return type(o)=='table'and o.valid~=false end
local created,released,destroyed,captures,snapshots=0,0,0,0,0
local function object(t)t=t or{};t.valid=true;return t end
local function container()
 return object{AddChild=function(_,child)return child end}
end
local rendering={
 CreateRenderTarget2D=function()created=created+1;return object{}end,
 ReleaseRenderTarget2D=function(_,o)assert(o.valid);o.valid=false;released=released+1 end,
}
local materials={CreateDynamicMaterialInstance=function()return object{SetTextureParameterValue=function(self,_,target)self.target=target end}end}
local widgetLib={Create=function()return object{WidgetTree=object{RootWidget=container()},SetVisibility=function()end,AddToViewport=function()end,RemoveFromParent=function(self)self.valid=false end}end}
function StaticFindObject(path)
 if path:find('KismetRenderingLibrary',1,true)then return rendering end
 if path:find('KismetMaterialLibrary',1,true)then return materials end
 if path:find('WidgetBlueprintLibrary',1,true)then return widgetLib end
 return object{}
end
function StaticConstructObject()return object{SetBrushFromMaterial=function(self,m)self.material=m end,RemoveFromParent=function(self)self.valid=false end}end
function LoadAsset()return object{}end
function FName(s)return s end
function FindFirstOf()return object{MaterialCatFaceRT=object{}}end
local current={profile='profile',slot=0,gs=1,worldId='world1',pawn=object{},pc=object{},gameState=object{}}
local ctx={root='test/',valid=valid,native=function()return true end,snapshot=function()snapshots=snapshots+1;return current end}
ctx.createPortraitActor=function()
 local capture=object{ClearShowOnlyComponents=function()end,ShowOnlyActorComponents=function()end,CaptureScene=function()captures=captures+1 end}
 return object{CaptureComponent=capture,GetAddress=function()return 100 end,K2_DestroyActor=function(self)self.valid=false;destroyed=destroyed+1 end}
end
local api=dofile(dir..'../Scripts/portraits.lua').new(ctx)
local function finish()for _=1,6 do api:tick()end end
local callbacks=0
local function receive(m)assert(valid(m));callbacks=callbacks+1 end
api:beginView()
assert(api:get({role=1},receive)==nil)
assert(api:get({role=1},receive)==nil)
finish()
assert(created==1 and captures==1 and callbacks==2,'Duplicate visible cats need one capture and both image subscribers')
assert(destroyed==1,'Idle capture actor must not continue animating outside the map')
local first=api:get({role=1});assert(valid(first)and created==1)
local before=snapshots;for _=1,100 do api:tick()end
assert(snapshots==before,'An idle portrait cache must not poll campaign state')
print('PASS portraits capture once, update all subscribers and stop idle work')

api:get({role=2},receive);api:tick();local oldCallbacks=callbacks
api:cancelPending();finish()
assert(callbacks==oldCallbacks and released==1,'Closing the menu must cancel its unfinished capture')
assert(api:get({role=1})==first,'Closing should preserve completed portraits')
api:get({role=3},receive);api:beginView();finish();assert(callbacks==oldCallbacks,'Changing pages must cancel stale queued images')
print('PASS closed and replaced views cancel work while retaining completed images')

for role=4,45 do api:beginView();api:get({role=role},receive);finish()end
assert(created-released<=32,'Portrait render targets must have a bounded cache')
assert(api:get({role=45})~=nil,'The current view must remain cached')
assert(api:get({role=1})==nil,'Old portraits should be evicted before recent ones')
api:cancelPending()
api:get({role=46},receive);api:tick();api:invalidate(46);finish();assert(callbacks==oldCallbacks+42,'Invalidation must cancel stale appearance work')
current.worldId='world2';api:get({role=45},receive)
assert(created==released,'World changes must release old-world targets')
finish();api:clear();assert(created==released)
print('PASS cache bounds, appearance invalidation and world changes release targets')
