local M=dofile('mods/ClanTools/Scripts/admin_inventory.lua')
local json=dofile('mods/ClanTools/Scripts/json.lua');local file=assert(io.open('mods/ClanTools/data/admin-inventory.json','rb'));local catalog=json.decode(file:read('*a'));file:close()
local function object(address)return{GetAddress=function()return address end}end
local function fixture()
 local f={clock=100,counts={},adds={},probes=0,backups=0,identity='inventory-A',s={profile='A',slot=0,chapter='Chapter00',worldId='World',phase=4,offline=true,pawn=object(1)}}
 f.ctx={inventoryCatalog=catalog,inventoryVerified=true,valid=function(o)return type(o)=='table'and not o.dead end,snapshot=function()return f.s end,now=function()return f.clock end,
  backupSave=function()f.backups=f.backups+1;if f.onBackup then f.onBackup()end;if f.backupFailure then return nil end;return'backup.sav'end}
 f.ctx.inventoryAdapter={identity=function()return f.identity end,
  probe=function(s,index,q,identity)assert(identity==f.identity);f.probes=f.probes+1;return{current=f.counts[index]or 0,allowed=(f.full or f.fullAfter and #f.adds>=f.fullAfter)and 0 or 1}end,
  add=function(s,index,q,current,identity)
   assert(identity==f.identity and current==(f.counts[index]or 0));f.adds[#f.adds+1]=index;f.counts[index]=current+q
   if f.failAt==#f.adds then error('native readback uncertain')end
   return{current=current,after=f.badReadback and current or current+q,allowed=1}
  end}
 f.api=M.new(f.ctx);return f
end
do
 local f=fixture();local scans=0;local snapshot=f.ctx.snapshot
 f.ctx.snapshot=function()scans=scans+1;return snapshot()end
 for _=1,100 do f.api.tick()end;assert(scans==0,'Idle inventory tools should not inspect the campaign')
 local ok,p=f.api.preview(1,1);assert(ok);local before=scans
 f.s.offline=false;f.api.tick();assert(scans>before)
 f.s.offline=true;assert(not f.api.apply(p.token),'A preview invalidated by leaving offline play must stay invalid')
 print('PASS inventory only polls pending previews and invalidates them across transitions')
end
do
 local f=fixture();assert(#f.api.catalog()==52 and #f.api.catalog('comfrey')==2 and #f.api.catalog('', 'Materials')==27)
 assert(#f.api.bundles()==4);assert(not f.api.preview(53,1));assert(not f.api.preview(1,0));assert(not f.api.preview(1,1000));assert(not f.api.preview(1,1.5))
 f.ctx.inventoryVerified=false;local ok,p=f.api.preview(1,10);assert(ok and not p.enabled and #f.adds==0)
 assert(not f.api.apply(p.token));assert(f.backups==0 and #f.adds==0)
 print('PASS allowlisted catalog/search/bundles/quantity validation; unverified mode permits probes only')
end
do
 local f=fixture();f.counts[1]=3;local ok,p=f.api.preview(1,9);assert(ok and p.rows[1].current==3 and p.rows[1].after==12)
 local good,r=f.api.apply(p.token);assert(good and r.complete and r.backup=='backup.sav'and f.counts[1]==12 and #f.adds==1 and f.backups==1)
 assert(not f.api.apply(p.token));assert(#f.adds==1)
 print('PASS backup, native count preview/readback and single-use confirmation')
end
do
 for _,change in ipairs({'count','profile','slot','chapter','world','pawn','inventory','offline','combat','expired'})do
  local f=fixture();local ok,p=f.api.preview(1,2);assert(ok)
  if change=='count'then f.counts[1]=1 elseif change=='profile'then f.s.profile='B'elseif change=='slot'then f.s.slot=1
  elseif change=='chapter'then f.s.chapter='Chapter01'elseif change=='world'then f.s.worldId='Other'elseif change=='pawn'then f.s.pawn=object(2)
  elseif change=='inventory'then f.identity='inventory-B'elseif change=='offline'then f.s.offline=false elseif change=='combat'then f.s.combat=true elseif change=='expired'then f.clock=161 end
  assert(not f.api.apply(p.token),change);assert(#f.adds==0 and f.backups==0,change)
 end
 print('PASS stale count/save/slot/chapter/world/player/owner, offline/combat and expiry refusal')
end
do
 for _,change in ipairs({'backup','count','inventory','gate','capacity'})do
  local f=fixture();local ok,p=f.api.preview(1,2);assert(ok)
  f.onBackup=function()if change=='backup'then f.backupFailure=true elseif change=='count'then f.counts[1]=1 elseif change=='inventory'then f.identity='B'elseif change=='gate'then f.ctx.inventoryVerified=false else f.full=true end end
  assert(not f.api.apply(p.token),change);assert(#f.adds==0 and f.backups==1,change)
 end
 print('PASS backup failure and post-backup quantity/identity/gate/capacity rechecks prevent mutation')
end
do
 local f=fixture();local ok,p=f.api.previewBundle('materials',5);assert(ok and #p.rows==6 and p.total==30)
 local good,r=f.api.apply(p.token);assert(good and #r.rows==6 and #f.adds==6 and f.backups==1)
 local g=fixture();local _,q=g.api.previewBundle('healing',2);g.fullAfter=1
 local applied,stopped=g.api.apply(q.token);assert(not applied and #stopped.rows==1 and not stopped.uncertain and #g.adds==1 and stopped.message:find('1 confirmed',1,true))
 assert(not g.api.apply(q.token));assert(#g.adds==1)
 print('PASS full bundle grants with one backup; capacity changes stop later additions and invalidate token')
end
do
 local f=fixture();local _,p=f.api.previewBundle('healing',2);f.failAt=2
 local ok,r=f.api.apply(p.token);assert(not ok and #r.rows==1 and r.uncertain and #f.adds==2 and r.backup=='backup.sav')
 assert(not f.api.apply(p.token));assert(#f.adds==2)
 local g=fixture();g.badReadback=true;local _,q=g.api.preview(1,1);local good,bad=g.api.apply(q.token);assert(not good and bad.uncertain and #bad.rows==0 and #g.adds==1)
 print('PASS ambiguous native failures/readback never auto-retry or rollback saves; partial additions explicit')
end
do
 local f=fixture();local _,p=f.api.preview(1,1);f.api.cancelPreview();assert(not f.api.apply(p.token))
 local _,q=f.api.preview(1,1);f.api.preview(2,1);assert(not f.api.apply(q.token));f.api.shutdown();assert(not f.api.preview(1,1))
 local good='nonce=7\nstatus=READY\ncurrent=5\nafter=5\nallowed=1\n';assert(M.parse(good,7,'PROBE').current==5)
 for _,bad in ipairs({good:gsub('nonce=7','nonce=6'),good:gsub('current=5','current=nan'),good..'allowed=1\n',good:gsub('READY','APPLIED'),good:gsub('allowed=1','allowed=2')})do assert(not pcall(M.parse,bad,7,'PROBE'))end
 print('PASS cancellation/new-selection/shutdown invalidation and strict nonce/status/numeric response parser')
end
