local M=dofile('mods/ClanTools/Scripts/context.lua')
local serial=0
local function object(fields)
 serial=serial+1;local address=serial;local o=fields or{}
 function o:IsValid()return not self.dead end
 function o:GetAddress()return address end
 function o:GetFullName()return 'object'..address end
 function o:IsA(class)return self.kind==class.kind end
 return o
end
local classes={}
classes['/Script/Wrc.WrcGameplayGameState']=object({kind='state'})
classes['/Script/Wrc.WrcGameplayPlayerController']=object({kind='controller'})
classes['/Script/SwtAdventure.SwtAdventureGameConfig']=object({kind='config'})
PropertyTypes={IntProperty=1}
local registrations,verifications=0,0
RegisterCustomProperty=function(p)registrations=registrations+1;assert(p.BelongsToClass=='/Script/SwtAdventure.SwtAdventureGameConfig'and p.OffsetInternal==0x154 and p.Type==1)end
M.native=function(command)assert(command=='CONTEXT_LAYOUT');verifications=verifications+1;return{action='CONTEXT_LAYOUT config_slot=340'}end
classes['/Script/SwtQuest.Default__BFLSwtQuest']=object({GetChapter=function(_,gs,out)out.chapter={ToString=function()return gs.chapter end}end})
local standalone=true
classes['/Script/Engine.Default__KismetSystemLibrary']=object({IsStandalone=function()return standalone end})
local function scene(label)
 local world=object();local pawn=object({MeshCustomizationComponent={CustomData={ClanType=4}}})
 function pawn:GetWorld()return world end
 local pc=object({kind='controller',Pawn=pawn});pawn.Controller=pc
 local gs=object({kind='state',MainCharacter=pawn,CurrentPhase=4,chapter=label});world.GameState=gs
 return world,pawn,pc,gs
end
local world,pawn,pc,gs=scene('first')
local save=object({CurrentSaveSlotIndex=0,saveSlots={ForEach=function(_,fn)
 for i,name in ipairs({'a','b'})do fn(i,{get=function()return{ToString=function()return name end}end})end
end}})
local config=object({kind='config',ClanToolsCurrentCharacterSlot=3})
local viewport=object({World=world,GameInstance=object({SaveManager=object({SaveGame=save}),GameConfig=config,FlowManager=object({kind='flow',ClanToolsCurrentCharacterSlot=0})})})
local engine=object({GameViewport=viewport});local searches=0
FindFirstOf=function(name)assert(name=='GameEngine');searches=searches+1;return engine end
StaticFindObject=function(path)return assert(classes[path],path)end
for i=1,100 do local s=assert(M.snapshot());assert(s.pawn==pawn and s.pc==pc and s.profile=='a'and s.chapter=='first'and s.slot==3 and s.profileIndex==0)end
assert(registrations==1 and verifications==1,'Identity lookup must not perform repeated native requests')
config.ClanToolsCurrentCharacterSlot=7;assert(M.snapshot().slot==7)
config.ClanToolsCurrentCharacterSlot=-1;assert(M.snapshot()==nil)
config.ClanToolsCurrentCharacterSlot=0;assert(M.snapshot().slot==0)
config.kind='foreign';assert(M.snapshot()==nil);config.kind='config'
assert(searches==1,'Steady-state snapshots must not perform global actor searches')
print('PASS direct viewport traversal keeps fresh campaign state without global actor scans')
save.CurrentSaveSlotIndex=1;assert(M.snapshot().profile=='b')
standalone=false;assert(M.snapshot().offline==false);standalone=true
gs.Director=object();assert(M.snapshot().combat);gs.Director=nil
pc.Pawn=object();assert(M.snapshot()==nil);pc.Pawn=pawn
pc.kind='foreign';assert(M.snapshot()==nil);pc.kind='controller'
viewport.World=object({GameState=object({kind='menu'})});assert(M.snapshot()==nil)
viewport.World=world;assert(M.snapshot())
local other,otherPawn,otherPC=scene('second');viewport.World=other
local s=assert(M.snapshot());assert(s.pawn==otherPawn and s.pc==otherPC and s.chapter=='second')
other.GameState.MainCharacter=pawn;assert(M.snapshot()==nil,'A valid pawn from the old world must be rejected')
other.GameState.MainCharacter=otherPawn
engine.dead=true;engine=object({GameViewport=viewport});assert(M.snapshot());assert(searches==2)
viewport.World=nil;assert(M.snapshot()==nil)
print('PASS world, profile, combat, ownership and engine replacement are revalidated immediately')
