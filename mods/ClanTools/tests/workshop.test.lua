local M=dofile('mods/ClanTools/Scripts/workshop.lua')
local function fixture()
 local s={offline=true,phase=4,profile='p',slot=0,worldId='world',pawn={GetAddress=function()return 1 end},pc={}}
 local entry={index=1,name='Moss Nest',tag='Gameplay.Inventory.Decoration.1',category='Decoration',costs={{quantity=3,name='Moss'}}}
 local current,material,time,den,allowed=0,8,0,true,1
 local calls,backups=0,0;local onBackup
 local adapter={identity=function()return 'inventory'end,probe=function(_,_,_,q,free)
  return{current=current,allowed=allowed==1 and(free or material>=3*q)and 1 or 2,stamp=current..':'..material,cost1=material}
 end,craft=function(_,_,_,q,free)
  calls=calls+1;local before=current;current=current+q;if not free then material=material-3*q end
  return{current=before,after=current}
 end}
 local ctx={workshopVerified=true,workshopAdapter=adapter,workshopCatalog={entry},snapshot=function()return s end,
 valid=function(o)return o~=nil end,workshopDiscover=function()return den and{actors={{}},session='den'}end,now=function()return time end,
 backupSave=function()backups=backups+1;if onBackup then onBackup()end;return 'backup'end}
 local api=M.new(ctx)
 return api,ctx,s,function(k,v)if k=='material'then material=v elseif k=='time'then time=v elseif k=='den'then den=v elseif k=='backup'then onBackup=v elseif k=='allowed'then allowed=v end end,
 function()return current,material,calls,backups end
end
do
 local a,_,_,_,state=fixture();local ok,p=a.preview(1,2,false);assert(ok and p.costs[1].need==6)
 local applied,r=a.apply(p.token);assert(applied and r.complete);local c,m,n,b=state();assert(c==2 and m==2 and n==1 and b==1)
 assert(not a.apply(p.token));assert(select(3,state())==1,'Single-use confirmation')
end
do
 local a,_,_,_,state=fixture();local ok,p=a.preview(1,2,true);assert(ok and p.costs[1].need==0);assert(a.apply(p.token))
 local c,m=state();assert(c==2 and m==8,'Free craft preserves materials')
end
for _,case in ipairs({'stale','den','combat','expired','backup','disabled'})do
 local a,c,s,set,state=fixture();local _,p=a.preview(1,1,false)
 if case=='stale'then set('material',7)elseif case=='den'then set('den',false)elseif case=='combat'then s.combat=true
 elseif case=='expired'then set('time',61)elseif case=='disabled'then c.workshopVerified=false
 else set('backup',function()s.profile='new'end)end
 assert(not a.apply(p.token),case);assert(select(3,state())==0,case..' cannot mutate')
end
do
 local a,c,s,set,state=fixture();assert(not a.preview(1,0,true));assert(not a.preview(1,100,true))
 set('material',0);local _,p=a.preview(1,1,false);assert(not p.allowed);assert(not a.apply(p.token));assert(select(3,state())==0)
 assert(#a.catalog('nest','Decoration')==1 and #a.catalog('missing')==0)
 a.shutdown();assert(not a.available())
end
do
 local a,c=fixture();c.workshopAdapter.craft=function()error('uncertain native call')end
 local _,p=a.preview(1,1,true);local ok,r=a.apply(p.token);assert(not ok and r.uncertain and r.backup=='backup')
 assert(not a.apply(p.token),'Uncertain craft cannot be replayed')
end
print('PASS workshop cost/free operations, stale session/count/den/combat/expiry/backup guards, quantity bounds and single-use/uncertain results')
