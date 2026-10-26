local M=dofile('mods/ClanTools/Scripts/native_cat_names.lua');local n=0
local function test(name,fn)fn();n=n+1;print('PASS '..name)end
local function fixture()
 local s={offline=true,profile='p',slot=0,clan=1,worldId='world'};local serial=0
 local function object(fields)
  serial=serial+1;local id=serial;fields=fields or{};fields.valid=true;fields.GetAddress=function()return id end
  fields.GetWorld=function()return{GetFullName=function()return'world'end,valid=true}end
  fields.IsA=function(self,class)return self.class==class end;fields.IsInViewport=function(self)return self.visible~=false end;fields.IsVisible=fields.IsInViewport
  return fields
 end
 local function text(value)local o=object({value=value,writes=0});function o:GetText()return self.value end;function o:SetText(value)self.value=value;self.writes=self.writes+1 end;return o end
 local name=text('Hareblaze');local role=text('Medicine cat');local widget=object({mcGuiTextName=name,mcGuiTextRole=role})
 local npc=object({class='/Script/SwtAdventure.SwtAdventureQuestActor',narrativeRole=7,ClanType=1,GiverRole=5,QuestWidgetComponent=object({WidgetsContainer=object({mcGuiActorName=widget})})})
 local dialogueText=text('Hareblaze');local node=object({class='/Script/SwtQuest.QuestDialogueTalkingNode',TalkingSource=0})
 local dialog=object({NpcRef=npc,CurrentDialogueNode=node,mcGuiDialogueTalker=object({mcGuiTextName=dialogueText})})
 local combatText=text('Hareblaze');local combat=object({class='/Script/SwtAdventure.SwtAdventureCharacter',CharacterType=2,ActorIdentifier='ENarrativeRole::ClanCat7',MeshCustomizationComponent=object({CustomData={ClanType=1,Role=5}})})
 local slot=object({CharacterRef=combat,mcGuiTextCatName=combatText})
 local partyText=text('Hareblaze');local playerText=text('Player');local pause=object({mcGuiPanelParty=object({mcGuiCatParty1=object({mcGuiTextName=playerText}),mcGuiCatParty2=object({mcGuiTextName=partyText})})})
 local all={SwtAdventureQuestActor={npc},QuestGiverWidget={dialog},GuiCombatCharacterSlot={slot},GuiScreenPause={pause}};local party={{role=7}}
 FindAllOf=function(class)return all[class]or{}end;StaticFindObject=function(class)return class end
 local ctx={snapshot=function()return s end,valid=function(o)return type(o)=='string'or type(o)=='table'and o.valid==true end,make_text=function(v)return v end,
 catalog={Enums={ClanCat7=7}},party={read=function()return party end}}
 local cats={{role=7,name='Willowmist',originalName='Hareblaze',living=true,clan=1}}
 ctx.getCats=function()return cats,{valid=true}end
 local a=M.new(ctx)
 return{a=a,s=s,ctx=ctx,cats=cats,name=name,role=role,npc=npc,dialog=dialog,node=node,dialogueText=dialogueText,combat=combat,combatText=combatText,party=party,partyText=partyText,playerText=playerText,all=all}
end
test('exact enum identifiers only, unknown names and display text are rejected',function()
 assert(M.roleFromIdentifier('ENarrativeRole::ClanCat7',{ClanCat7=7})==7);assert(M.roleFromIdentifier('ClanCat7',{ClanCat7=7})==7)
 assert(not M.roleFromIdentifier('Hareblaze',{ClanCat7=7}));assert(not M.roleFromIdentifier('Other::ClanCat7',{ClanCat7=7}));assert(not M.roleFromIdentifier('None',{None=0}))
end)
test('NPC dialogue combat and party use native identities; role and player labels stay intact',function()
 local f=fixture();assert(f.a.tick());assert(f.name.value=='Willowmist'and f.dialogueText.value=='Willowmist'and f.combatText.value=='Willowmist'and f.partyText.value=='Willowmist')
 assert(f.role.value=='Medicine cat'and f.playerText.value=='Player');assert(f.a.status().count==4);assert(f.a.tick());assert(f.name.writes==1)
end)
test('player and custom dialogue sources are never labelled as NPC',function()
 for _,source in ipairs({1,2,3})do local f=fixture();f.node.TalkingSource=source;assert(f.a.tick());assert(f.dialogueText.value=='Hareblaze')end
 local f=fixture();f.a.tick();f.node.TalkingSource=1;f.dialogueText.value='Player';f.a.tick();assert(f.dialogueText.value=='Player')
end)
test('ambiguous display names cannot attach an alias to a different native role',function()
 local f=fixture();f.combat.ActorIdentifier='OtherCat';f.npc.narrativeRole=8;f.party[1].role=8;f.a.tick()
 assert(f.name.value=='Hareblaze'and f.dialogueText.value=='Hareblaze'and f.combatText.value=='Hareblaze'and f.partyText.value=='Hareblaze')
end)
test('native refreshed caption is retained for restoration and newer captions win',function()
 local f=fixture();f.a.tick();f.name.value='Translated original';f.a.tick();assert(f.name.value=='Willowmist');f.dialogueText.value='A newer native caption'
 assert(f.a.shutdown());assert(f.name.value=='Translated original'and f.combatText.value=='Hareblaze'and f.partyText.value=='Hareblaze'and f.dialogueText.value=='A newer native caption')
end)
test('foreign clan dead cat unknown combat identifier or absent roster gets no alias',function()
 local f=fixture();f.npc.ClanType=2;f.combat.MeshCustomizationComponent.CustomData.Role=12;f.cats[1].living=false;assert(f.a.tick());assert(f.a.status().count==0)
end)
test('campaign transitions never restore old original names over a reused widget',function()
 local f=fixture();f.a.tick();f.s.profile='new-profile';f.cats={};f.ctx.getCats=function()return{}, {valid=true}end;assert(f.a.tick());assert(f.a.status().count==0);assert(f.name.value=='Willowmist')
end)
test('name removal restores old caption while unchanged role remains owned',function()
 local f=fixture();f.a.tick();f.cats[1].name=f.cats[1].originalName;assert(f.a.tick());assert(f.name.value=='Hareblaze'and f.a.status().count==0)
end)
test('profiles without overrides skip save parsing and native discovery; removal restores labels',function()
 local f=fixture();assert(f.a.tick());assert(f.name.value=='Willowmist')
 f.ctx.catNames={hasOverrides=function(s)assert(s==f.s);return false end}
 f.ctx.getCats=function()error('Full save must not be parsed without overrides')end
 FindAllOf=function()error('Native objects must not be scanned without overrides')end
 for i=1,100 do assert(f.a.tick())end
 assert(f.name.value=='Hareblaze'and f.a.status().count==0)
end)
test('no applicable living aliases skip native discovery',function()
 local f=fixture();f.cats[1].living=false
 FindAllOf=function()error('No applicable alias requires widget discovery')end
 assert(f.a.tick())
end)
print(n..' native cat label tests passed (reflected model; live widget acceptance pending).')
