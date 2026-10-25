local module=dofile('mods/ClanTools/Scripts/pile_lock.lua')
local count=0;local function test(name,fn)fn();count=count+1;print('PASS '..name)end
local function fixture()
 local f={value=60,maximum=100,calls=0,backups=0}
 f.s={profile='abc',slot=0,worldId='world',gameState={GetAddress=function()return 100 end},offline=true,phase=4}
 f.ctx={snapshot=function()return f.s end,pileLockVerified=true,backupSave=function()f.backups=f.backups+1;return 'backup'end}
 f.adapter={pileProbe=function()return{current=f.value,maximum=f.maximum}end,pileSet=function(_,p,value)assert(p.current==f.value);f.calls=f.calls+1;if not f.fail then f.value=value end;return{after=f.value}end}
 f.api=module.new(f.ctx,f.adapter);return f
end
test('locks chosen value and backs up once',function()local f=fixture();assert(f.api.set(true,80));assert(f.value==80 and f.backups==1);f.value=75;f.api.tick();assert(f.value==80 and f.backups==1);f.api.tick();assert(f.calls==2)end)
test('disable leaves normal food consumption active',function()local f=fixture();assert(f.api.set(true));assert(f.api.set(false));f.value=20;f.api.tick();assert(f.value==20)end)
test('profile transition never changes another save',function()local f=fixture();assert(f.api.set(true));f.s.profile='other';f.value=20;f.api.tick();assert(f.value==20 and not f.api.state().enabled)end)
test('combat and online transitions stop maintenance',function()for _,change in ipairs({function(s)s.combat=true end,function(s)s.offline=false end})do local f=fixture();assert(f.api.set(true));change(f.s);f.value=20;f.api.tick();assert(f.value==20 and not f.api.state().enabled)end end)
test('capacity changes and native failure disable lock',function()local f=fixture();assert(f.api.set(true));f.maximum=120;f.api.tick();assert(not f.api.state().enabled);f=fixture();assert(f.api.set(true));f.fail=true;f.value=10;f.api.tick();assert(not f.api.state().enabled and f.api.state().error)end)
test('verification and numeric bounds fail closed',function()local f=fixture();f.ctx.pileLockVerified=false;assert(not f.api.set(true));f.ctx.pileLockVerified=true;assert(not f.api.set(true,101));assert(not f.api.set(true,0/0));assert(f.backups==0)end)
print(count..' pile lock tests passed')
