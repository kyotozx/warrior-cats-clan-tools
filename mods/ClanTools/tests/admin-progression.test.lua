local module=dofile('mods/ClanTools/Scripts/admin_progression.lua')
local passed=0
local function fixture()
 local s={offline=true,phase=4,combat=false,worldId='World /Game/Art/Maps/Gameplay/L_WorldMap_01_P.L_WorldMap_01_P',profile='test',slot=0,chapter='1',clan=1,pawn={IsValid=function()return true end,GetAddress=function()return 123 end}}
 local cat={role=4,clan=1,living=true,name='Test cat'};local pile,bond,backups,writes=25,28,0,0
 local ctx={snapshot=function()return s end,verified={pile=true,bonds=true},getCats=function()return {cat},{valid=true,profile=s.profile,slot=s.slot}end,validateCat=function()return true end,backupSave=function()backups=backups+1;return 'test.sav'end}
 ctx.progressionAdapter={pileProbe=function()return{current=pile,maximum=100}end,pileFill=function()writes=writes+1;pile=100;return{after=pile}end,bondProbe=function()return{current=bond,maximum=100,rank=2}end,bondSet=function(_,_,_,value)writes=writes+1;bond=value;return{after=bond,after_rank=4}end}
 return module.new(ctx),ctx,s,cat,function()return pile,bond,backups,writes end,function(value)bond=value end
end
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function preview(api,kind,args)local ok,p=api.preview(kind,args);assert(ok,p);return p end
test('pile uses actual maximum and backs up once',function()local a,c,s,cat,state=fixture();local p=preview(a,'pile');assert(a.action('fill_pile',{token=p.token}));local pile,bond,backups,writes=state();assert(pile==100 and backups==1 and writes==1)end)
test('bond bounds reject before backup/write',function()local a,c,s,cat,state=fixture();local p=preview(a,'bond',{role=4});for _,value in ipairs({-1,101,1.5,math.huge})do assert(not a.action('set_bond',{token=p.token,value=value}))end;local _,_,b,w=state();assert(b==0 and w==0)end)
test('restore selected original after multiple edits',function()local a,c,s,cat,state=fixture();local p=preview(a,'bond',{role=4});assert(a.action('set_bond',{token=p.token,value=73}));p=preview(a,'bond',{role=4});assert(a.action('set_bond',{token=p.token,value=100}));p=preview(a,'bond',{role=4});assert(a.action('restore_bond',{token=p.token}));local _,bond,b,w=state();assert(bond==28 and b==3 and w==3)end)
test('consumed preview cannot repeat',function()local a,c,s,cat,state=fixture();local p=preview(a,'bond',{role=4});assert(a.action('set_bond',{token=p.token,value=73}));assert(not a.action('set_bond',{token=p.token,value=73}));local _,_,b,w=state();assert(b==1 and w==1)end)
test('stale native value rejected',function()local a,c,s,cat,state,set=fixture();local p=preview(a,'bond',{role=4});set(29);assert(not a.action('set_bond',{token=p.token,value=73}));local _,_,b,w=state();assert(b==0 and w==0)end)
test('unknown online fails closed',function()local a,c,s=fixture();s.offline=nil;assert(not a.preview('pile'));s.offline=false;assert(not a.preview('pile'))end)
test('unverified action is disabled while read-only preview works',function()local a,c,s,cat,state=fixture();c.verified={};local p=preview(a,'pile');assert(not p.enabled and not a.action('fill_pile',{token=p.token}));local _,_,b,w=state();assert(b==0 and w==0)end)
test('save change invalidates transaction and restore history',function()local a,c,s=fixture();local p=preview(a,'bond',{role=4});s.profile='different';assert(not a.action('set_bond',{token=p.token,value=73}));p=preview(a,'bond',{role=4});assert(not a.action('restore_bond',{token=p.token}))end)
test('backup failure prevents mutation',function()local a,c,s,cat,state=fixture();c.backupSave=function()error('disk error')end;local p=preview(a,'pile');assert(not a.action('fill_pile',{token=p.token}));local _,_,b,w=state();assert(w==0)end)
test('live clan identity checked again at apply',function()local a,c,s,cat,state=fixture();local p=preview(a,'bond',{role=4});cat.clan=2;assert(not a.action('set_bond',{token=p.token,value=73}));local _,_,b,w=state();assert(w==0)end)
test('combat and shutdown refuse edits',function()local a,c,s=fixture();s.combat=true;assert(not a.preview('pile'));s.combat=false;a.shutdown();assert(not a.preview('pile'))end)
print(passed..' progression transaction tests passed (mock adapters; runtime evidence required).')
