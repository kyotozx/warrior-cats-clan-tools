local M=dofile('mods/ClanTools/Scripts/party_presets.lua')
local json=dofile('mods/ClanTools/Scripts/json.lua')
local n=0
local function test(name,fn)fn();n=n+1;print('PASS '..name)end
local function fixture()
 local s={offline=true,phase=4,profile='profileA',clan=1,slot=0}
 local cats={{role=7,living=true,clan=1},{role=8,living=true,clan=1}}
 local store,current,applies={},{{role=7},{role=8}},0
 local party={read=function()return current end,select=function(roles)applies=applies+1;current={};for _,r in ipairs(roles)do current[#current+1]={role=r}end;return true end}
 local ctx={characterKey=function(s)return s.profile..'_'..s.slot..'_'..(s.generation or string.rep('a',64))end,root='root/',snapshot=function()return s end,json=json,read=function(p)return store[p]end,write=function(p,v)store[p]=v end,
  getCats=function()return cats,{valid=true,profile=s.profile,slot=s.slot}end}
 return M.new(ctx,party),s,cats,store,party,ctx,function()return current,applies end
end
test('save current party list and load preserves order',function()
 local p,s,c,store,party,ctx,current=fixture();assert(p.save('Patrol'));local a=p.list();assert(#a==1 and a[1].roles[1]==7 and a[1].roles[2]==8)
 party.select({8});assert(p.load(a[1].id));local active=current();assert(active[1].role==7 and active[2].role==8)
end)
test('empty preset works and same name replaces without duplicating',function()
 local p=fixture();assert(p.save('Solo',{}));assert(p.save('Solo',{8}));local a=p.list();assert(#a==1 and a[1].roles[1]==8);assert(p.save('Solo',{}));assert(p.load(a[1].id))
end)

test('preset persistence fits the default Steam path',function()
 local p,s,c,store,party,ctx=fixture();s.profile=string.rep('a',32)
 ctx.root='C:/Program Files (x86)/Steam/steamapps/common/Warrior Cats Clans of the Forest/Wrc/Binaries/Win64/ue4ss/Mods/ClanTools/Scripts/../'
 local write=ctx.write;ctx.write=function(path,bytes)assert(#path<260,'Windows filename is too long: '..#path);write(path,bytes)end
 assert(p.save('Patrol',{7}));assert(p.list()[1].roles[1]==7)
end)
test('profile and clan isolation prevent cross-save or cross-clan loads',function()
 local p,s=fixture();assert(p.save('Patrol',{7}));local id=p.list()[1].id;s.clan=2;assert(#p.list()==0 and not p.load(id));s.clan=1;s.profile='profileB';assert(#p.list()==0 and not p.load(id))
end)
test('same-clan characters have independent presets and ignore ambiguous legacy files',function()
 local p,s,c,store=fixture();store['root/state/party-presets-profileA.json']='{"version":9}'
 store['root/state/party-presets-character-profileA_0.json']='{"version":9}'
 assert(#p.list()==0)
 assert(p.save('Patrol',{7}));s.slot=3;assert(#p.list()==0 and not p.load(1))
 assert(p.save('Patrol',{8}));assert(p.list()[1].roles[1]==8)
 s.slot=0;assert(p.list()[1].roles[1]==7)
 assert(store['root/state/party-presets-profileA.json']=='{"version":9}')
 assert(store['root/state/party-presets-character-profileA_0.json']=='{"version":9}')
end)
test('dead absent or another-clan companions reject entire preset',function()
 for _,change in ipairs({function(c)c[2].living=false end,function(c)c[2].clan=2 end,function(c)c[2]=nil end})do
  local p,s,c,store,party,ctx,current=fixture();assert(p.save('Patrol'));change(c);assert(not p.load(1));local active,applied=current();assert(applied==0 and #active==2)
 end
end)
test('invalid names duplicate roles and oversized parties never write',function()
 local p,s,c,store=fixture()
 for _,label in ipairs({'','  ','bad\nname',string.rep('a',41),string.char(255)})do assert(not p.save(label,{7}))end
 assert(not p.save('Bad',{7,7}));assert(not p.save('Bad',{7,8,9}));assert(next(store)==nil)
 assert(p.save('Équipe de caça',{7}))
end)
test('native apply failure leaves preset and selection untouched',function()
 local p,s,c,store,party,ctx,current=fixture();assert(p.save('Patrol'));local before=store['root/state/party-presets-v3-profileA_0_vkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkva.json']
 party.select=function()error('native readback failed; rollback restored')end
 assert(not p.load(1));assert(store['root/state/party-presets-v3-profileA_0_vkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkva.json']==before);local active=current();assert(#active==2)
end)
test('corrupt storage does not get overwritten',function()
 local p,s,c,store=fixture();local path='root/state/party-presets-v3-profileA_0_vkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkva.json';store[path]='{"version":9}';assert(not p.save('Patrol'));assert(store[path]=='{"version":9}')
end)
test('roster session mismatch and online sessions fail before changes',function()
 local p,s,c,store,party,ctx=fixture();ctx.getCats=function()return c,{valid=true,profile='other',slot=0}end;assert(not p.save('Patrol'))
 s.offline=false;assert(not p.save('Patrol'));assert(next(store)==nil)
end)
test('preset removal and cap preserve unrelated entries',function()
 local p=fixture();for i=1,12 do assert(p.save('Patrol '..i,{}))end;assert(not p.save('Overflow',{}));assert(p.remove(4));local list=p.list();assert(#list==11 and list[4].id==5);assert(p.save('Replacement',{}))
end)
test('listing returns copies rather than mutable stored roles',function()
 local p=fixture();assert(p.save('Patrol'));local list=p.list();list[1].roles[1]=99;assert(p.list()[1].roles[1]==7)
end)
print(n..' party preset model tests passed.')
test('reusing a deleted character slot cannot inherit or load its party presets',function()
 local p,s=fixture();s.generation=string.rep('a',64);assert(p.save('Old patrol',{7}));s.generation=string.rep('b',64)
 assert(#p.list()==0 and not p.load(1));assert(p.save('New patrol',{8}));assert(p.list()[1].roles[1]==8)
 s.generation=string.rep('a',64);assert(p.list()[1].roles[1]==7)
end)
test('missing live generation blocks writes and preserves ambiguous files',function()
 local p,s,c,store,party,ctx=fixture();local old='root/state/party-presets-character-v2-profileA_0.json'
 store[old]='{"version":9}';ctx.characterKey=function()return nil,'Missing generation'end
 assert(not p.save('Patrol',{7})and not p.load(1)and not p.remove(1));assert(store[old]=='{"version":9}')
 local count=0;for _ in pairs(store)do count=count+1 end;assert(count==1)
end)
