local module=dofile('mods/ClanTools/Scripts/admin_progression.lua');local passed=0
local function fixture()
 local s={offline=true,phase=4,combat=false,worldId='World /Game/Art/Maps/Gameplay/L_WorldMap_01_P.L_WorldMap_01_P',profile='test',slot=0,chapter='1',pawn={IsValid=function()return true end,GetAddress=function()return 123 end}}
 local q={id='42',tag='Test.Quest',name='Test quest',quest_status=2,result=0,count=0,active=2,in_progress=2};local calls,turns,backups=0,0,0
 local ctx={snapshot=function()return s end,verified={quests=true},backupSave=function()backups=backups+1;return'test.sav'end}
 ctx.progressionAdapter={listQuests=function()return{q}end,questProbe=function()local out={};for k,v in pairs(q)do out[k]=v end;return out end,questStep=function()calls=calls+1;q.in_progress=q.in_progress-1;if q.in_progress==0 then q.quest_status=3;q.result=1 end;return{stepped=1}end,questTurnIn=function()turns=turns+1;q.quest_status=4;return{after=4}end}
 return module.new(ctx),ctx,s,q,function()return calls,turns,backups end
end
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function start(a)local ok,list=a.preview('quests');assert(ok,list);local ok,r=a.action('complete_quest',{token=list[1].token});assert(ok,r);return list[1].token end
test('one objective per step and one genuine turn-in',function()local a,c,s,q,state=fixture();local token=start(a);a.tick(.5);assert(q.in_progress==1);a.tick(.5);assert(q.quest_status==3);a.tick(.5);assert(q.quest_status==4);a.tick(.5);local steps,turns,b=state();assert(steps==2 and turns==1 and b==1 and a.questState().status=='complete');assert(not a.action('complete_quest',{token=token}))end)
test('phase change cancels before next objective',function()local a,c,s,q,state=fixture();start(a);a.tick(.5);s.phase=5;a.tick(.5);s.phase=4;a.tick(.5);local steps,turns=state();assert(steps==1 and turns==0 and a.questState().status=='stopped')end)
test('chapter transition cannot advance another quest',function()local a,c,s,q,state=fixture();start(a);s.chapter='2';a.tick(.5);local steps,turns=state();assert(steps==0 and turns==0)end)
test('failed quest cannot grant success rewards',function()local a,c,s,q,state=fixture();start(a);q.quest_status=3;q.result=2;a.tick(.5);local steps,turns=state();assert(steps==0 and turns==0 and a.questState().status=='stopped')end)
test('inactive objectives do not get fabricated completion',function()local a,c,s,q,state=fixture();start(a);q.in_progress=0;a.tick(.5);local steps,turns=state();assert(steps==0 and turns==0)end)
test('cancel retains completed steps without more changes',function()local a,c,s,q,state=fixture();start(a);a.tick(.5);assert(a.action('cancel_quest'));a.tick(.5);local steps,turns=state();assert(steps==1 and turns==0)end)
test('missing verification blocks queue',function()local a,c,s,q,state=fixture();c.verified.quests=false;local ok,list=a.preview('quests');assert(ok and not list[1].enabled);assert(not a.action('complete_quest',{token=list[1].token}));local steps,turns,b=state();assert(steps==0 and turns==0 and b==0)end)
test('native failure is not retried or rewarded',function()local a,c,s,q,state=fixture();c.progressionAdapter.questStep=function()error('Native refusal')end;start(a);a.tick(.5);a.tick(.5);local _,turns=state();assert(turns==0 and a.questState().status=='stopped')end)
print(passed..' selected quest transaction tests passed (mock adapters only).')
