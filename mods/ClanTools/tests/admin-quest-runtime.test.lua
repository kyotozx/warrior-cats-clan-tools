-- Adapter contract only; mailbox is in-memory and no native library is loaded.
local originalOpen,originalLoadlib,originalFirst,originalAll=io.open,package.loadlib,FindFirstOf,FindAllOf
local files,calls={},0;local rejectForeign
io.open=function(path,mode)
 if mode:find('w',1,true)then return{write=function(_,s)files[path]=s;return true end,close=function()end}end
 return{read=function()return assert(files[path],'Missing test mailbox')end,close=function()end}
end
local persisted={['Quest.Main.4']=2,['Quest.Main.7']=0};local nativeAlias='Quest.Main.4'
package.loadlib=function()return function()
 calls=calls+1;local nonce=assert(files['test/admin-quest-request.txt']:match('^(%d+)'))
 local address=files['test/admin-quest-request.txt']:match('^%d+ %S+ (%x+)')
 local status=rejectForeign and address=='3'and'Quest belongs to another player'or'READY'
 files['test/admin-quest-status.txt']='nonce='..nonce..'\nstatus='..status..'\nquest_status='..persisted[nativeAlias]..'\nresult=0\ncount=0\nactive=1\nin_progress=1\nafter=2\nstepped=0\n'
end end
local function object(id)local o={};function o:IsValid()return true end;function o:GetAddress()return id end;function o:GetFullName()return'Object '..id end;return o end
local function tag(name)return{TagName={ToString=function()return name end}}end
local q=object(1);q.QuestStatus=0
local g=object(2);g.questTag=tag('Quest.Procedural.Combat.MarkTerritory');g.QuestAlias=tag(nativeAlias);g.QuestBase=q;q.QuestGraph=g
local inactive=object(3);local ig=object(4);ig.questTag=g.questTag;ig.QuestAlias=tag('Quest.Main.7');ig.QuestBase=inactive;inactive.QuestGraph=ig;inactive.QuestStatus=0
local manager=object(5);function manager:GetQuestStatus(alias)return persisted[alias.TagName:ToString()]or 0 end
local save,pc=object(6),object(7)
FindFirstOf=function(name)return name=='QuestManager'and manager or save end
FindAllOf=function(name)return name=='MultiObjectiveQuest'and{q,inactive}or{}end
local runtime=dofile('mods/ClanTools/Scripts/admin_quest_runtime.lua').new({},'test/','fake.dll')
local snapshot={offline=true,phase=4,pc=pc}
local n=0;local function test(name,fn)fn();n=n+1;print('PASS '..name)end
test('persisted alias discovers active quest despite zero reflected cache',function()
 local rows,d=runtime.listQuests(snapshot);assert(#rows==1 and d.candidates==1 and calls==1);assert(rows[1].id=='1'and rows[1].alias=='Quest.Main.4'and rows[1].quest_status==2)
end)
test('alias change invalidates an existing selected quest before native dispatch',function()
 local rows=runtime.listQuests(snapshot);local before=calls;g.QuestAlias=tag('Quest.Main.7');assert(not pcall(runtime.questProbe,snapshot,rows[1]));assert(calls==before);g.QuestAlias=tag(nativeAlias)
end)
test('inactive persisted alias never dispatches a quest mutation probe',function()
 persisted[nativeAlias]=0;local before=calls;local rows=runtime.listQuests(snapshot);assert(#rows==0 and calls==before)
end)
test('foreign owner is excluded before counting actionable candidates',function()
 persisted[nativeAlias]=2;persisted['Quest.Main.7']=2;rejectForeign=true
 local rows,d=runtime.listQuests(snapshot);assert(#rows==1 and d.candidates==1 and d.foreign_owners==1 and #d.errors==0)
end)
print(n..' quest runtime adapter tests passed (mock mailbox).')
io.open,package.loadlib,FindFirstOf,FindAllOf=originalOpen,originalLoadlib,originalFirst,originalAll
