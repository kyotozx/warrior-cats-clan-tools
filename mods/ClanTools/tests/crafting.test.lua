local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local M=dofile(folder..'../Scripts/crafting.lua');local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function eq(a,b)assert(a==b,tostring(a)..' ~= '..tostring(b))end
local function object(addr)return {IsValid=function()return true end,GetAddress=function()return addr end}end
local sample='CRAFTING 1 1\nP abc 1 14400 100 15 0\nP def 3 0 200 16 0\n'
test('native project mailbox has authoritative state and elapsed',function()local p,why,e=M.parse(sample);eq(why,nil);eq(e,1);eq(p[1].duration,14400);eq(p[2].state,3)end)
test('invalid and duplicated project records fail closed',function()
 for _,s in ipairs({'',sample:gsub('CRAFTING 1','CRAFTING 2'),sample:gsub(' 14400 ',' -1 '),sample:gsub('P def','P abc'),sample:gsub(' 100 ',' nan '),sample:gsub('P abc 1','P abc 4')})do assert(not M.parse(s))end
end)
test('speed changes target duration without faking elapsed progress',function()
 local p=assert(M.parse(sample))[1];eq(M.remaining(p,1),14300);eq(M.remaining(p,2),7100);eq(M.remaining(p,5),2780);eq(M.remaining(p,10),1340);eq(M.remaining(p,'instant'),0)
 eq(M.remaining(p,3),nil);p.duration=7;p.elapsed=1;eq(M.remaining(p,2),3)
end)
test('complete verifies live building state and rejects repeated claim',function()
 local messages,complete=0,0;local stage=1;local epoch=0;local available=true
 local native={configure=function(s)epoch=tonumber(s:match('^1 (%d+)'));return 'CONFIGURED'end,remove=function()return 'REMOVED'end,
  scan=function()return string.format('CRAFTING 1 %d\nP abc %d 14400 100 1 0\n',epoch,stage)end,
  complete=function(s)complete=complete+1;assert(s==epoch..' abc\n');stage=3;return 'COMPLETED'end}
 local api=M.new({crafting_native=native,snapshot=function()return {}end,crafting_context=function()if available then return {actors={object(0xabc)},session='world1'}end end,notify=function()messages=messages+1 end})
 api.tick();eq(api.status().attached,true);eq(#api.status().projects,1);assert(api.complete_now('abc'));eq(complete,1);eq(messages,1);eq(#api.status().projects,0);eq(api.status().hotspot_count,1)
 assert(not api.complete_now('abc'));eq(complete,1);available=false;api.tick();eq(api.status().attached,false)
end)
test('unsupported native build cannot report completion',function()
 local calls=0;local api=M.new({crafting_native={configure=function()return 'ERROR unsupported build'end,remove=function()return 'REMOVED'end,complete=function()calls=calls+1;return 'COMPLETED'end},crafting_context=function()return{actors={object(0xabc)},session='w'}end})
 api.tick();eq(api.status().attached,false);assert(not api.complete_now('abc'));eq(calls,0)
end)
test('changing scene restores the old hook before new context',function()
 local phase='world1';local restores=0;local epoch=0
 local api=M.new({crafting_context=function()return {actors={object(0xabc)},session=phase}end,crafting_native={configure=function(s)epoch=tonumber(s:match('^1 (%d+)'));return 'CONFIGURED'end,remove=function()restores=restores+1;return 'REMOVED'end,scan=function()return 'CRAFTING 1 '..epoch..'\n'end}})
 api.tick();phase='world2';api.tick();eq(restores,1);api.shutdown();eq(restores,2)
end)
test('streamed den membership uses visible level OwningWorld, not outer world',function()
 local world=object(100);local other=object(200);local hidden=object(300)
 local level=object(101);level.OwningWorld=world;level.bIsVisible=true
 local pawn=object(1);pawn.GetLevel=function()return level end
 pawn.K2_GetActorLocation=function()return {X=0,Y=0,Z=0}end
 local function hotspot(id,owner,visible,tag)
  local l=object(id+1000);l.OwningWorld=owner;l.bIsVisible=visible
  local o=object(id);o.GetLevel=function()return l end;o.GetWorld=function()error('Outer-world wrapper must not be used')end;o.K2_GetActorLocation=function()return {X=1,Y=0,Z=0}end;o.UniqueHotspotTag={TagName={ToString=function()return tag or'Gameplay.Den.Hotspot.Personal.3'end}};return o,l
 end
 local accepted,denLevel=hotspot(0xabc,world,true);local wrong=hotspot(0xdef,other,true);local unloaded=hotspot(0x123,world,false);local noTag=hotspot(0x456,world,true,'None');local dead=hotspot(0x789,world,true);dead.IsValid=function()return false end
 local outside=hotspot(0x888,world,true);outside.K2_GetActorLocation=function()return{X=100,Y=0,Z=0}end
 local box=object(20);box.K2_GetComponentToWorld=function()return{rotation='real transform'}end;box.GetUnscaledBoxExtent=function()return{X=5,Y=5,Z=5}end
 local door=object(21);door.GetLevel=function()return level end;door.Clan=4;door.bIsExit=true;door.HotspotsContainerAreaComponent=box
 door.AllHotspots={ForEach=function(_,fn)for i,o in ipairs({accepted,wrong,unloaded,noTag,dead,outside,accepted})do fn(i,{get=function()return o end})end end}
 local old,oldFind=FindAllOf,StaticFindObject;FindAllOf=function(class)if class=='WrcHousingHotspot'then return{accepted,wrong,unloaded,noTag,dead,outside,accepted}end;eq(class,'WrcHousingDoorActor');return{door}end
 local mathLib=object(22);mathLib.IsPointInBoxWithTransform=function(_,p,t,e)eq(t.rotation,'real transform');return math.abs(p.X)<=e.X end;StaticFindObject=function()return mathLib end
 local watch,epoch,removed;local s={offline=true,combat=false,pawn=pawn,world=world,worldId='play',profile='p',slot=0,clan=4}
 local api=M.new({snapshot=function()return s end,load_crafting_preferences=function()end,crafting_native={configure=function(v)watch=v;epoch=tonumber(v:match('^1 (%d+)'));return'CONFIGURED'end,scan=function()return'CRAFTING 1 '..epoch..'\n'end,remove=function()removed=true;return'REMOVED'end}})
 api.tick();assert(api.status().attached);eq(watch,'1 1 1 1\nabc\n');denLevel.bIsVisible=false;api.tick();assert(removed and not api.status().attached);denLevel.bIsVisible=true
 door.Clan=3;eq(M.discover(s),nil);door.Clan=4;door.bIsExit=false;eq(M.discover(s),nil);door.bIsExit=true
 pawn.K2_GetActorLocation=function()return{X=100,Y=0,Z=0}end;eq(M.discover(s),nil)
 pawn.K2_GetActorLocation=function()return{X=0,Y=0,Z=0}end
 local cache=door.AllHotspots;door.AllHotspots={ForEach=function()end}
 local loaded=M.discover(s);assert(loaded and #loaded.actors==1 and loaded.actors[1]==accepted,'Teleport fallback must retain all membership checks')
 door.AllHotspots=cache
 local duplicate=object(23);for k,v in pairs(door)do if k~='GetAddress'then duplicate[k]=v end end
 FindAllOf=function()return{door,duplicate}end;eq(M.discover(s),nil)
 FindAllOf=old;StaticFindObject=oldFind
end)
test('chosen speed persists outside den and reloads without packaging user preferences',function()
 local stored;local ctx={load_crafting_preferences=function()return stored end,save_crafting_preferences=function(v)stored=v;return true end,crafting_context=function()return nil end}
 local api=M.new(ctx);assert(api.set_speed(5));eq(api.status().speed,5);eq(stored.speed,5);assert(api.shutdown());local again=M.new(ctx);eq(again.status().speed,5);assert(again.set_speed(1));eq(stored.speed,1)
end)
test('speed persistence or native apply failure restores previous live speed',function()
 local stored={version=1,speed=2};local failSave=false;local failNative=false;local factor,epoch
 local ctx={load_crafting_preferences=function()return stored end,save_crafting_preferences=function(v)if failSave then error('disk full')end;stored=v;return true end,crafting_context=function()return{actors={object(0xabc)},session='w'}end,
 crafting_native={configure=function(v)if failNative then failNative=false;return'ERROR inject'end;epoch,factor=v:match('^1 (%d+) (%d+)');return'CONFIGURED'end,scan=function()return'CRAFTING 1 '..epoch..'\n'end,remove=function()return'REMOVED'end}}
 local api=M.new(ctx);api.tick();eq(factor,'2');failSave=true;assert(not api.set_speed(10));eq(api.status().speed,2);eq(factor,'2');eq(stored.speed,2)
 failSave=false;failNative=true;assert(not api.set_speed('instant'));eq(api.status().speed,2);eq(factor,'2');eq(stored.speed,2);assert(api.set_speed(5));eq(stored.speed,5);eq(factor,'5')
end)
test('invalid saved speed stays at normal speed and partial cleanup retries',function()
 local failRemove=true;local api=M.new({load_crafting_preferences=function()return{version=1,speed=500}end,crafting_context=function()return{actors={object(0xabc)},session='w'}end,crafting_native={configure=function()return'ERROR inject'end,remove=function()return failRemove and'ERROR remove'or'REMOVED'end}})
 eq(api.status().speed,1);api.tick();assert(api.status().attached);assert(not api.shutdown());failRemove=false;assert(api.shutdown());assert(not api.status().attached)
end)
test('identical attach failures log once and wait before retry',function()
 local oldTime=os.time;local now=100;os.time=function()return now end;local logs,attempts=0,0
 local api=M.new({load_crafting_preferences=function()end,log=function()logs=logs+1 end,crafting_context=function()return{actors={object(0xabc)},session='w'}end,crafting_native={configure=function()attempts=attempts+1;return'ERROR fixture'end,remove=function()return'REMOVED'end}})
 api.tick();api.tick();eq(attempts,1);eq(logs,1);now=103;api.tick();eq(attempts,2);eq(logs,1);assert(api.shutdown());os.time=oldTime
end)
print(passed..' crafting tests passed.')
