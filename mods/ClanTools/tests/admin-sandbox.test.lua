local M=dofile('mods/ClanTools/Scripts/admin_sandbox.lua')
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
local function fixture()
 local s={offline=true,phase=4,profile='a',slot=0,chapter='Chapter00',worldId='world'}
 local stats={current=169,maximum=500,level=11,max_level=50};local calls={backup=0,add=0,fill=0}
 local ctx={snapshot=function()return s end,backupSave=function()calls.backup=calls.backup+1 end}
 local adapter={probeXP=function()return stats end,addXP=function(_,amount,p)calls.add=calls.add+1;assert(p.level==11 and amount==100);return{after=269,after_level=11,maximum=500}end,
 fillStamina=function()calls.fill=calls.fill+1;return true end}
 local options={adapter=adapter,verified={xp=true,stamina=true}}
 return M.new(ctx,options),s,stats,calls,ctx,adapter,options
end
test('XP preview is read-only then native apply runs once after backup',function()
 local a,s,st,c=fixture();local ok,p=a.preview_xp(100);assert(ok and p.level==11 and c.add==0 and c.backup==0)
 local good,r=a.apply_xp(p.token);assert(good and r.current==269 and c.add==1 and c.backup==1);assert(not a.apply_xp(p.token));assert(c.add==1)
end)
test('XP bounds and max level fail before backup',function()
 local a,s,st,c=fixture();for _,n in ipairs({0,-1,100001,1.5,'100'})do assert(not a.preview_xp(n))end
 st.level=50;assert(not a.preview_xp(100));assert(c.backup==0 and c.add==0)
end)

test('capped zero XP reports maximum level without attempting a mutation',function()
 local a,s,st,c=fixture();st.level=20;st.max_level=20;st.current=0;st.maximum=0
 local ok,why=a.preview_xp(100)
 assert(not ok and tostring(why):find('already at maximum level',1,true),tostring(why))
 assert(c.backup==0 and c.add==0)
end)

test('XP grant reaching capped zero XP completes once',function()
 local a,s,st,c,ctx,adapter=fixture();st.level=19;st.max_level=20;st.current=499
 adapter.addXP=function(_,amount,p)
  assert(amount==100 and p.level==19);c.add=c.add+1
  return{after=0,after_level=20,maximum=0}
 end
 local ok,p=a.preview_xp(100);assert(ok)
 local applied,r=a.apply_xp(p.token)
 assert(applied and r.current==0 and r.level==20 and r.maximum==0)
 assert(c.add==1 and c.backup==1);assert(not a.apply_xp(p.token));assert(c.add==1)
end)
test('stale XP or changed campaign invalidates preview',function()
 for _,change in ipairs({function(s,st)s.profile='b'end,function(s,st)st.current=170 end,function(s,st)s.combat=true end})do
  local a,s,st,c=fixture();local ok,p=a.preview_xp(100);assert(ok);change(s,st);assert(not a.apply_xp(p.token));assert(c.add==0 and c.backup==0)
 end
end)
test('backup transition cannot mutate another campaign',function()
 local a,s,st,c,ctx=fixture();local ok,p=a.preview_xp(100);ctx.backupSave=function()s.slot=1 end
 assert(not a.apply_xp(p.token));assert(c.add==0)
end)
test('native apply failure consumes preview and is never retried implicitly',function()
 local a,s,st,c,ctx,adapter=fixture();local ok,p=a.preview_xp(100);adapter.addXP=function()c.add=c.add+1;error('uncertain result')end
 assert(not a.apply_xp(p.token));assert(not a.apply_xp(p.token));assert(c.add==1)
end)
test('unverified builds and online sessions cannot enable or edit',function()
 local a,s,st,c,ctx,ad,opt=fixture();opt.verified.xp=false;opt.verified.stamina=false;assert(not a.preview_xp(100));assert(not a.set_infinite_stamina(true))
 opt.verified.xp=true;opt.verified.stamina=true;s.offline=false;assert(not a.preview_xp(100));assert(not a.set_infinite_stamina(true));assert(c.add==0 and c.fill==0)
end)
test('stamina tick is throttled; combat stays enabled in same campaign',function()
 local a,s,st,c=fixture();assert(a.set_infinite_stamina(true));assert(c.fill==1);a.tick(1);assert(c.fill==2);a.tick(1.1);assert(c.fill==2)
 s.combat=true;a.tick(2);assert(c.fill==3 and a.state().infinite_stamina);assert(a.set_infinite_stamina(false));a.tick(3);assert(c.fill==3)
end)
test('stamina automatically turns off after profile change or load screen',function()
 for _,change in ipairs({function(s)s.profile='b'end,function(s)s.phase=3 end,function(s)s.offline=false end})do
  local a,s,st,c=fixture();assert(a.set_infinite_stamina(true));change(s);a.tick(1);assert(not a.state().infinite_stamina and c.fill==1)
 end
end)
test('resource failure disables refill and reports reason without looping',function()
 local a,s,st,c,ctx,ad=fixture();a.set_infinite_stamina(true);ad.fillStamina=function()error('stale component')end
 assert(not a.tick(1));assert(a.state().error and not a.state().infinite_stamina);assert(a.tick(2))
end)
test('shutdown stops toggles and rejects outstanding XP preview',function()
 local a,s,st,c=fixture();a.set_infinite_stamina(true);local ok,p=a.preview_xp(100);assert(a.shutdown());assert(not a.apply_xp(p.token));assert(not a.set_infinite_stamina(true));a.tick(2);assert(c.fill==1 and c.add==0)
end)
test('move catalog shows current clan plus universal and native unlocked state',function()
 local a,s,st,c,ctx,adapter,opt=fixture();s.clan=1;ctx.clans={'ThunderClan','ShadowClan'};opt.verified.moves=true
 opt.moves={{tag='universal',name='Quick Claw',clan='None'},{tag='thunder',name='Thunder Strike',clan='ThunderClan'},{tag='shadow',name='Shadow Strike',clan='ShadowClan'}}
 adapter.tagIndex=function(tag)return({universal=1,thunder=2,shadow=3})[tag]end;adapter.moves=function()return{[1]=true}end
 a=M.new(ctx,opt);local ok,list=a.moves();assert(ok and #list==2 and list[1].unlocked and not list[2].unlocked)
end)
test('move unlock uses native path after backup and excludes another clans moves',function()
 local a,s,st,c,ctx,adapter,opt=fixture();s.clan=1;ctx.clans={'ThunderClan'};opt.verified.moves=true
 opt.moves={{tag='valid',name='Quick Claw',clan='None'},{tag='other',name='Other',clan='RiverClan'}}
 adapter.tagIndex=function()return 1 end;adapter.moves=function()return{}end;local unlocks=0
 adapter.unlock=function(_,tag)assert(c.backup==1 and tag=='valid');unlocks=unlocks+1 end
 a=M.new(ctx,opt);assert(not a.unlock_move('other'));assert(not a.unlock_move('invented'));assert(a.unlock_move('valid'));assert(unlocks==1 and c.backup==1)
end)
test('already unlocked move and backup session change cannot unlock twice',function()
 local a,s,st,c,ctx,adapter,opt=fixture();opt.verified.moves=true;opt.moves={{tag='valid',name='Quick Claw',clan='None'}}
 adapter.tagIndex=function()return 1 end;adapter.moves=function()return{[1]=true}end
 adapter.unlock=function()error('must not invoke')end;a=M.new(ctx,opt);assert(not a.unlock_move('valid'));assert(c.backup==0)
 adapter.moves=function()return{}end;ctx.backupSave=function()s.profile='other'end;assert(not a.unlock_move('valid'))
end)
test('shipped move catalog excludes enemy attacks and has English labels',function()
 local json=dofile('mods/ClanTools/Scripts/json.lua');local f=assert(io.open('mods/ClanTools/data/admin-moves.json','rb'));local rows=json.decode(f:read('*a'));f:close();assert(#rows==75)
 local tags={};for _,m in ipairs(rows)do assert(m.category=='Universal'or m.category=='Clan'or m.category=='Ancestor');assert(type(m.name)=='string'and m.name~=''and not tags[m.tag]);tags[m.tag]=true end
end)
test('native stamina adapter tolerates empty combat transition and rejects oversized parties',function()
 local original=package.loadlib;local calls=0
 package.loadlib=function()return function()calls=calls+1;error('Unexpected native refill')end end
 local a=M.nativeAdapter({root='unused/'})
 package.loadlib=original
 local party={};local director={IsValid=function()return true end,GetAddress=function()return 1 end}
 director.PlayerParty={ForEach=function(_,fn)for i,v in ipairs(party)do fn(i,{get=function()return v end})end end}
 assert(a.fillStamina({combat=true,gameState={Director=director}}));assert(calls==0)
 local actor={IsValid=function()return true end}
 for i=1,4 do party[i]={IsValid=function()return true end,GetOwner=function()return actor end}end
 local ok,why=pcall(a.fillStamina,{combat=true,gameState={Director=director}})
 assert(not ok and tostring(why):find('Unexpected player combat party size',1,true));assert(calls==0)
end)
print(count..' sandbox transaction and lifecycle model tests passed.')
