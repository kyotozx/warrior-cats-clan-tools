local module=dofile('mods/ClanTools/Scripts/appearance_world.lua')
local original={ClanType=4,Role=1,Gender=false,PrefixNameId='Cloud',SuffixNameId='kit',CombatStats={TagName='Kit'},BodyValue=9}
local edited={};for k,v in pairs(original)do edited[k]=v end;edited.BodyValue=8
local gs={GetAddress=function()return 42 end};local called={}
local function actor(role,rank,data)
 return{narrativeRole=role,GiverRole=rank,DefaultCustomData=data,MeshCustomizationComponent={},IsA=function()return true end}
end
local good=actor(79,1,original);local dead=actor(79,12,original);local other=actor(77,1,original)
local wrongName={};for k,v in pairs(original)do wrongName[k]=v end;wrongName.PrefixNameId='Different'
local wrong=actor(79,1,wrongName)
function StaticFindObject(path)
 if path:find('GameplayStatics',1,true)then return{GetGameState=function()return gs end}end
 if path:find(':UpdatedRole',1,true)then return function(a,r,rank,data)called[#called+1]=a;assert(a==good and r==79 and rank==1 and data.BodyValue==8)end end
 return{}
end
function FindAllOf()return{good,dead,other,wrong}end
local api=module.new({valid=function(o)return o~=nil end,snapshot=function()return{offline=true,gameState=gs}end})
local updated,skipped=api:refresh({role=79},{actor={CustomizableMeshComponent={CustomData=edited}}})
assert(updated==1 and skipped==2 and #called==1)
assert(good.GiverRole==1 and good.DefaultCustomData.BodyValue==9)
print('PASS matched live world NPC refresh; different role/name and Dead branch excluded; original identity retained')
