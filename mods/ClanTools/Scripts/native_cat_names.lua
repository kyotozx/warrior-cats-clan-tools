-- Display-only aliases on widgets with an explicit, current native cat identity.
-- No localization/global text hook; role IDs, dialogue, saves and bindings stay native.
local M={}
local function stringValue(v)if type(v)=='string'then return v end;return v:ToString()end
function M.roleFromIdentifier(value,enums)
 local name=stringValue(value):gsub('^ENarrativeRole::','')
 if not name:match('^[%w_]+$')then return nil end
 local role=enums[name];if type(role)=='number'and role>0 and role<255 and role%1==0 then return role end
end
function M.new(ctx)
 assert(ctx.snapshot and ctx.valid and ctx.getCats,'Native names require the current campaign context.')
 local api={};local records={};local closed=false;local lastError;local classes={}
 local makeText=ctx.make_text or FText
 local function class(name)if not ctx.valid(classes[name])then classes[name]=StaticFindObject(name)end;return classes[name]end
 local function sameWorld(o,s)
  if not ctx.valid(o)then return false end
  local world=o:GetWorld();return ctx.valid(world)and world:GetFullName()==s.worldId
 end
 local function livingRank(rank)return type(rank)=='number'and rank>=1 and rank<=11 and rank~=9 end
 local function npcRole(actor,s)
  if not sameWorld(actor,s)or not actor:IsA(class('/Script/SwtAdventure.SwtAdventureQuestActor'))or actor.ClanType~=s.clan or not livingRank(actor.GiverRole)then return nil end
  return actor.narrativeRole
 end
 local function combatRole(actor,s)
  if not sameWorld(actor,s)or not actor:IsA(class('/Script/SwtAdventure.SwtAdventureCharacter'))or(actor.CharacterType~=1 and actor.CharacterType~=2)then return nil end
  local mesh=actor.MeshCustomizationComponent;if not ctx.valid(mesh)or mesh.CustomData.ClanType~=s.clan or not livingRank(mesh.CustomData.Role)then return nil end
  return M.roleFromIdentifier(actor.ActorIdentifier,ctx.catalog.Enums)
 end
 local function collect(s)
  if ctx.nativeNamesAdapter then return ctx.nativeNamesAdapter.collect(s)end
  local out={}
  local function add(widget,owner,identity,kind)
   if ctx.valid(widget)and ctx.valid(owner)then
    local role=identity();if role then out[#out+1]={widget=widget,owner=owner,role=role,identity=identity,kind=kind}end
   end
  end
  local function each(name,fn)
   for _,o in ipairs(FindAllOf(name)or{})do if ctx.valid(o)then
    local ok,why=pcall(fn,o);if not ok then lastError=tostring(why)end
   end end
  end
  each('SwtAdventureQuestActor',function(actor)
   if npcRole(actor,s)then
    local c=actor.QuestWidgetComponent
    if ctx.valid(c)and ctx.valid(c.WidgetsContainer)and ctx.valid(c.WidgetsContainer.mcGuiActorName)then
     add(c.WidgetsContainer.mcGuiActorName.mcGuiTextName,actor,function()return npcRole(actor,s)end,'npc')
    end
   end
  end)
  each('QuestGiverWidget',function(screen)
   if not sameWorld(screen,s)or not screen:IsInViewport()or not screen:IsVisible()then return end
   local function identity()
    if not ctx.valid(screen)then return nil end
    local node=screen.CurrentDialogueNode
    if not ctx.valid(node)or not node:IsA(class('/Script/SwtQuest.QuestDialogueTalkingNode'))or node.TalkingSource~=0 then return nil end
    return npcRole(screen.NpcRef,s)
   end
   if ctx.valid(screen.mcGuiDialogueTalker)then add(screen.mcGuiDialogueTalker.mcGuiTextName,screen,identity,'dialogue')end
  end)
  each('GuiCombatCharacterSlot',function(slot)
   if sameWorld(slot,s)and slot:IsVisible()then add(slot.mcGuiTextCatName,slot,function()return ctx.valid(slot)and combatRole(slot.CharacterRef,s)or nil end,'combat')end
  end)
  if ctx.party and ctx.party.read then each('GuiScreenPause',function(pause)
   if not sameWorld(pause,s)or not pause:IsInViewport()or not pause:IsVisible()or not ctx.valid(pause.mcGuiPanelParty)or not pause.mcGuiPanelParty:IsVisible()then return end
   local party=ctx.party.read();assert(#party<=2,'Unexpected native companion count.')
   for i=1,2 do local row=party[i];local slot=pause.mcGuiPanelParty['mcGuiCatParty'..(i+1)]
    if row and ctx.valid(slot)and slot:IsVisible()then
     add(slot.mcGuiTextName,pause,function()
      if not ctx.valid(pause)or not pause:IsInViewport()then return nil end
      local current=ctx.party.read();return current[i]and current[i].role
     end,'party')
    end
   end
  end)end
  return out
 end
 local function restore(record)
  if not ctx.valid(record.widget)or not ctx.valid(record.owner)then return true end
  local s=ctx.snapshot()
  if not s or s.profile~=record.profile or s.slot~=record.slot or s.worldId~=record.world then return true end
  local ok,why=pcall(function()
   -- A recycled widget or a newer native caption belongs to the game again.
   if record.identity()==record.role and stringValue(record.widget:GetText())==record.written then record.widget:SetText(makeText(record.original))end
  end)
  return ok,why
 end
 local function reset()
  local keep={};local why
  for id,r in pairs(records)do local ok,err=restore(r);if not ok then keep[id]=r;why=tostring(err)end end
  records=keep;return next(keep)==nil,why
 end
 local function tick()
  if closed then return false,'Native names are shut down.'end
  local s=ctx.snapshot()
  if not s or s.offline~=true or type(s.profile)~='string'or type(s.slot)~='number'or type(s.worldId)~='string'then return reset()end
  local cats,meta=ctx.getCats();assert(type(cats)=='table'and(not meta or meta.valid~=false),'Clan names are unavailable.')
  local aliases={}
  for _,cat in ipairs(cats)do if cat.living==true and cat.clan==s.clan and type(cat.role)=='number'and type(cat.name)=='string'and cat.name~=cat.originalName then aliases[cat.role]=cat.name end end
  local scope=s.profile..'|'..s.slot..'|'..s.worldId;local desired={}
  lastError=nil
  for _,target in ipairs(collect(s))do
   local alias=aliases[target.role]
   if alias and ctx.valid(target.widget)and ctx.valid(target.owner)and target.identity()==target.role then
    local id=tostring(target.widget:GetAddress());local identity=scope..'|'..target.role..'|'..target.owner:GetAddress()
    assert(not desired[id],'Native name widget has ambiguous ownership.')
    desired[id]={target=target,alias=alias,identity=identity}
   end
  end
  for id,r in pairs(records)do
   local d=desired[id]
   if not d or d.identity~=r.key then local ok,why=restore(r);assert(ok,why);records[id]=nil end
  end
  for id,d in pairs(desired)do
   local t=d.target;local current=stringValue(t.widget:GetText());local r=records[id]
   if not r then r={widget=t.widget,owner=t.owner,role=t.role,identity=t.identity,key=d.identity,original=current,kind=t.kind,profile=s.profile,slot=s.slot,world=s.worldId};records[id]=r
   elseif current~=r.written then r.original=current end -- the game refreshed its localized name
   if current~=d.alias then t.widget:SetText(makeText(d.alias))end
   r.written=d.alias;r.identity=t.identity
  end
  return true
 end
 function api.tick()
  local ok,a,b=pcall(tick)
  if not ok or a==false then lastError=tostring(ok and b or a);reset();return false,lastError end
  return a,b
 end
 function api.reset()return reset()end
 function api.shutdown()local ok,why=reset();if ok then closed=true end;return ok,why end
 function api.status()local count=0;for _ in pairs(records)do count=count+1 end;return{count=count,error=lastError,coverage='Nearby NPCs, NPC dialogue speakers, combat slots and pause party slots. Bonds and embedded dialogue text are unchanged.'}end
 return api
end
return M
