local M=dofile('mods/ClanTools/Scripts/admin_sandbox_stats.lua')
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
local function fixture()
 local s={id='a'};local r={level=11,stat0=155,stat1=140,stat2=155,stat3=135,stat4=140,stat5=100};local hp={current=120,maximum=155}
 local calls={backup=0,set=0,health=0};local enabled=true
 local a={probeXP=function()local out={};for k,v in pairs(r)do out[k]=v end;return out end,probeHealth=function()return{current=hp.current,maximum=hp.maximum}end}
 function a.setStat(_,i,value,p)assert(calls.backup>0 and r.level==p.level and r['stat'..i]==p.before);calls.set=calls.set+1;r['stat'..i]=value end
 function a.setHealthMaximum(_,value,expected)assert(hp.maximum==expected);calls.health=calls.health+1;hp.maximum=value;hp.current=math.min(hp.current,value)end
 local ctx={backupSave=function()calls.backup=calls.backup+1 end}
 local o={adapter=a,snapshot=function()assert(s.id,'No campaign');return s end,identity=function(v)return v.id end,verified=function()return enabled end}
 return M.new(ctx,o),s,r,hp,calls,a,ctx,o
end
test('preview is read-only and stat commit backs up and consumes token',function()
 local api,s,r,h,c=fixture();local ok,p=api.preview('strength',200);assert(ok and p.before==140 and p.original==140 and c.set==0 and c.backup==0)
 local good,result=api.apply(p.token);assert(good and result.after==200 and r.stat1==200 and c.backup==1);assert(not api.apply(p.token));assert(c.set==1)
end)
test('Prowess refreshes maximum through native health setter without free heal',function()
 local api,s,r,h,c=fixture();local ok,p=api.preview('prowess',100);assert(ok);assert(api.apply(p.token));assert(r.stat0==100 and h.maximum==100 and h.current==100 and c.health==1)
end)
test('temporary health maximum override prevents stat commit',function()
 local api,s,r,h,c=fixture();h.maximum=200;assert(not api.preview('prowess',300));assert(c.backup==0 and c.set==0)
end)
test('original reflects first observed stat this campaign and resets on change',function()
 local api,s,r=fixture();local ok,p=api.preview('strength',200);assert(api.apply(p.token));local _,p2=api.preview('strength',300);assert(p2.original==140 and p2.before==200)
 s.id='b';r.stat1=80;local _,p3=api.preview('strength',100);assert(p3.original==80)
end)
test('invalid key, no-op, fractions and out of range are rejected before backup',function()
 local api,s,r,h,c=fixture();assert(not api.preview('unknown',2));for _,v in ipairs({0,-1,10001,2.5,'100',140})do assert(not api.preview('strength',v))end;assert(c.backup==0)
end)
test('changed stat, level or campaign invalidates preview before backup',function()
 for _,change in ipairs({function(s,r)s.id='b'end,function(s,r)r.stat1=99 end,function(s,r)r.level=12 end})do
  local api,s,r,h,c=fixture();local _,p=api.preview('strength',200);change(s,r);assert(not api.apply(p.token));assert(c.set==0 and c.backup==0)
 end
end)
test('campaign transition or stat change during backup cannot mutate',function()
 for _,change in ipairs({function(s,r)s.id='b'end,function(s,r)r.stat1=99 end})do
  local api,s,r,h,c,a,ctx=fixture();local _,p=api.preview('strength',200);ctx.backupSave=function()change(s,r)end;assert(not api.apply(p.token));assert(c.set==0)
 end
end)
test('native health failure restores saved stat before reporting failure',function()
 local api,s,r,h,c,a=fixture();local _,p=api.preview('prowess',200);a.setHealthMaximum=function()error('native setter unavailable')end
 local ok,why=api.apply(p.token);assert(not ok and why:find('Original stat restored',1,true));assert(r.stat0==155 and c.set==2);assert(not api.apply(p.token))
end)
test('uncertain health failure cannot roll back into another profile',function()
 local api,s,r,h,c,a=fixture();local _,p=api.preview('prowess',200);a.setHealthMaximum=function()s.id='b';error('scene changed')end
 local ok,why=api.apply(p.token);assert(not ok and why:find('automatic backup',1,true));assert(c.set==1)
end)
test('native stat failure consumes token without implicit retry',function()
 local api,s,r,h,c,a=fixture();local _,p=api.preview('strength',200);a.setStat=function()c.set=c.set+1;error('uncertain')end
 assert(not api.apply(p.token));assert(not api.apply(p.token));assert(c.set==1)
end)
test('unverified stat gate blocks preview and outstanding apply',function()
 local api,s,r,h,c,a,ctx,o=fixture();local _,p=api.preview('strength',200);o.verified=function()return false end;assert(not api.apply(p.token));assert(not api.preview('strength',200));assert(c.backup==0)
end)
print(count..' stat transaction tests passed; no game process accessed.')
