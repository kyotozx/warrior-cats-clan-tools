local M=dofile('scripts/probe-quest-accept.lua')
local function obj(id)return{GetAddress=function()return id end}end
local function fixture()
 local q=obj(3);q.QuestStatus=1;q.QuestResult=0;q.GetClass=function()return{GetFullName=function()return'Class /Script/SwtAdventure.SwtAdventureMultiObjectiveQuest'end}end
 local g=obj(4);g.QuestBase=q;g.questTag={TagName={ToString=function()return'Quest.Procedural.Combat.MarkTerritory'end}};q.QuestGraph=g
 local entries={q};local manager=obj(5);local calls,backups=0,0
 manager.Quests={ForEach=function(_,fn)for i,v in ipairs(entries)do fn(i,{get=function()return{Quest=v}end})end end}
 manager.StartQuestOfTag=function(_,tag,pc)assert(tag==g.questTag and pc);calls=calls+1;q.QuestStatus=2 end
 FindFirstOf=function()return manager end
 local s={offline=true,phase=4,worldId='World /Game/Art/Maps/Gameplay/L_WorldMap_01_P.L_WorldMap_01_P',profile='test',slot=0,chapter='one',pawn=obj(1),pc=obj(2)}
 local ctx={valid=function(x)return type(x)=='table'end,snapshot=function()return s end,backupSave=function()backups=backups+1;return'backup.sav'end}
 return{api=M.new(ctx),q=q,s=s,ctx=ctx,entries=entries,counts=function()return calls,backups end}
end
local n=0;local function test(name,fn)fn();n=n+1;print('PASS '..name)end
test('preview never mutates; acceptance backs up and calls native once',function()local f=fixture();assert(f.api.preview().status==1);assert(f.counts()==0);local r=f.api.accept();assert(r.status==2 and r.backup=='backup.sav');local c,b=f.counts();assert(c==1 and b==1);assert(not pcall(f.api.accept));assert(not pcall(f.api.preview))end)
test('all active, complete or dialogue statuses reject before backup',function()for _,status in ipairs({2,3,5})do local f=fixture();f.q.QuestStatus=status;assert(not pcall(f.api.preview));local c,b=f.counts();assert(c==0 and b==0)end end)
test('changed save and duplicate quest reject',function()local f=fixture();f.api.preview();f.s.slot=1;assert(not pcall(f.api.accept));assert(f.counts()==0);f=fixture();f.entries[2]=f.q;assert(not pcall(f.api.preview))end)
test('transition during backup prevents native acceptance',function()local f=fixture();f.api.preview();f.ctx.backupSave=function()f.s.phase=3;return'backup'end;assert(not pcall(f.api.accept));assert(f.counts()==0)end)
test('failed native call is consumed and cannot retry',function()local f=fixture();f.api.preview();local m=FindFirstOf();m.StartQuestOfTag=function()error('uncertain native outcome')end;assert(not pcall(f.api.accept));assert(not pcall(f.api.accept));assert(not pcall(f.api.preview))end)
test('first native match is authoritative; later inactive copy is harmless',function()
 local f=fixture();local other=obj(9);for k,v in pairs(f.q)do if k~='GetAddress'then other[k]=v end end;other.QuestStatus=0;f.entries[2]=other
 assert(f.api.preview().id=='3');assert(f.api.accept().status==2)
 f=fixture();other.QuestStatus=1;f.entries[2]=other;assert(not pcall(f.api.preview))
 f=fixture();f.q.QuestStatus=0;f.entries[2]=other;assert(not pcall(f.api.preview))
end)
print(n..' guarded quest acceptance probe tests passed.')
