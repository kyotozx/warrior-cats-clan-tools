-- Own only a presentation component on a Clan Tools visual actor. No quest
-- identity, overlap sphere, NPC role or interaction registration is assigned.
local M={}
local path='/Game/Art/UXD/Blueprints/Controls/gui_actor_widgets/WBP_GuiQuestActorName.WBP_GuiQuestActorName_C'
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local valid=dofile(folder..'runtime_valid.lua').valid
local ranks={MedicineCat='MEDICINE CAT',RogueCat='ROGUE',RogueCatLeader='ROGUE LEADER',StarClanAncestor='STARCLAN ANCESTOR'}
function M.rank(value)return ranks[value]or tostring(value or''):gsub('(%l)(%u)','%1 %2'):upper()end
function M.new(actor,cat,s,options)
 options=options or{}
 local component,widget,visible,closed=nil,nil,false,false
 local near,far=options.near or 450,options.far or 550
 assert(near>0 and far>=near,'Invalid follower nameplate range.')
 local function owns()
  return valid(actor)and valid(component)and valid(component:GetOwner())and component:GetOwner():GetAddress()==actor:GetAddress()
 end
 local function show(value)
  if owns()then component:SetVisibility(value,false);component:SetHiddenInGame(not value,false)end
  if valid(widget)then widget:SetVisibility(value and 4 or 2)end
  visible=value
 end
 local api={}
 function api.destroy()
  if closed then return true end
  show(false)
  if valid(widget)then widget:RemoveFromParent()end
  if owns()then component:SetWidget(nil);component:K2_DestroyComponent(actor)end
  if owns()then return false,'Follower nameplate cleanup pending.'end
  closed=true;component=nil;widget=nil;return true
 end
 local ok,err=pcall(function()
  assert(valid(actor)and valid(s.pc),'Follower nameplate owner unavailable.')
  local class=StaticFindObject(path);if not valid(class)then class=LoadAsset(path)end
  assert(valid(class),'Native NPC nameplate asset unavailable.')
  widget=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary'):Create(s.gameState,class,s.pc)
  assert(valid(widget)and valid(widget.mcGuiTextName)and valid(widget.mcGuiTextRole),'Native NPC nameplate fields unavailable.')
  -- This native label includes its own vertical spacing; anchor its top near
  -- the head instead of adding the whole desired widget height above it.
  local height=20
  if valid(actor.CapsuleComponent)then height=math.max(8,actor.CapsuleComponent:GetScaledCapsuleHalfHeight()-5)end
  component=actor:AddComponentByClass(StaticFindObject('/Script/UMG.WidgetComponent'),false,
   {Rotation={X=0,Y=0,Z=0,W=1},Translation={X=0,Y=0,Z=height},Scale3D={X=1,Y=1,Z=1}},false)
  assert(owns(),'Follower nameplate component ownership failed.')
  component:SetCollisionEnabled(0);component:SetGenerateOverlapEvents(false)
  component:SetWidgetSpace(1);component:SetDrawSize({X=650,Y=150});component:SetPivot({X=.5,Y=0})
  component:SetDrawAtDesiredSize(true);component:SetWidget(widget)
  widget.mcGuiTextName:SetText(FText(tostring(cat.name or'Clanmate')))
  widget.mcGuiTextRole:SetText(FText(M.rank(cat.rank)))
  if valid(widget.mcGuiTextExtraInfo)then widget.mcGuiTextExtraInfo:SetText(FText(''));widget.mcGuiTextExtraInfo:SetVisibility(2)end
  -- The native asset retains its fonts, outline, colour and layout. It contains
  -- no trade/quest icon; don't invent a BARTERING status for a visual follower.
  show(false)
 end)
 if not ok then pcall(api.destroy);error(err)end
 local lastName,lastRank=cat.name,cat.rank
 function api.update(snapshot,currentCat)
  if closed then return false end
  if not owns()or not valid(widget)or not valid(snapshot.pawn)then show(false);return false end
  if currentCat and(currentCat.name~=lastName or currentCat.rank~=lastRank)then
   widget.mcGuiTextName:SetText(FText(tostring(currentCat.name or'Clanmate')))
   widget.mcGuiTextRole:SetText(FText(M.rank(currentCat.rank)));lastName,lastRank=currentCat.name,currentCat.rank
  end
  local paused
  if options.paused then paused=options.paused(snapshot)else paused=StaticFindObject('/Script/Engine.Default__GameplayStatics'):IsGamePaused(snapshot.pawn)end
  if snapshot.offline~=true or snapshot.phase~=4 or snapshot.combat or paused or(options.hidden and options.hidden())then show(false);return true end
  local a,b=actor:K2_GetActorLocation(),snapshot.pawn:K2_GetActorLocation()
  local distance=(a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2
  local limit=visible and far or near
  show(distance<=limit*limit);return true
 end
 function api.state()return{visible=visible,closed=closed,name=lastName,rank=lastRank}end
 return api
end
return M
