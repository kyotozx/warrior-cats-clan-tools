local source=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local M=dofile(source..'../Scripts/item_feedback.lua')
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function eq(a,b)assert(a==b,tostring(a)..' ~= '..tostring(b))end
local function event(before,after)
 return {epoch=1,sequence=1,tag_index=101,tag_number=0,before=before,after=after,requested=1,targets={{actor='abc',health={valid=true,before=95,after=100,max_before=100,max_after=100},stamina={valid=true,before=10.5,after=10.5,max_before=50,max_after=50}}}}
end
local info={tag='Gameplay.Inventory.Consumable.SmallHealingHerb',name='Horsetail Stalks',target_names={abc='You'}}
test('actual partial healing and remaining stack',function()
 local m=assert(M.format(event(5,4),info));eq(m.kind,'item_used');eq(m.remaining,4);eq(m.resources[1].health.recovered,5)
 assert(table.concat(m.lines,'\n'):find('HP +5 · 100/100',1,true));eq(m.original_sound,true)
end)
test('empty stack still confirms last consumed item',function()local m=assert(M.format(event(1,0),info));eq(m.remaining,0);eq(m.consumed,1)end)
test('blocked full state does not claim success or recovery',function()
 local e=event(5,5);e.targets[1].health.before=100
 local m=assert(M.format(e,info));eq(m.kind,'item_blocked');eq(m.consumed,0);eq(m.resources,nil)
 assert(not table.concat(m.lines,' '):find('Restored',1,true))
end)
test('non-restorative consumption never invents healing',function()
 local e=event(2,1);e.targets[1].health.after=95
 local m=assert(M.format(e,{name='Chamomile Poultice',tag='XP'}));eq(m.kind,'item_used');eq(m.resources[1].health.recovered,0)
 assert(not table.concat(m.lines,' '):find('HP +',1,true))
end)
test('invalid counts and missing measurements fail closed',function()
 for _,pair in ipairs({{1,2},{3,0},{-1,0}})do local m=M.format(event(pair[1],pair[2]),info);eq(m,nil)end
 local e=event(2,1);e.targets[1].health.before=0/0;e.targets[1].stamina.valid=false
 local m=assert(M.format(e,info));eq(m.resources[1].health,nil);eq(#m.lines,1)
end)
test('multi-target effects retain measured individual gains',function()
 local e=event(3,2);e.targets[2]={actor='def',health={valid=true,before=10,after=60,max_before=120,max_after=120}}
 local m=assert(M.format(e,info));eq(m.resources[1].health.recovered,5);eq(m.resources[2].health.recovered,50)
end)
local sample='ITEM_EVENTS 1 0\nE 1 1 101 0 5 4 1 1\nT abc 1 95 100 100 100 1 10.5 10.5 50 50\n'
test('native mailbox parsing and corruption refusal',function()
 local events,err,dropped=M.parse_events(sample);eq(err,nil);eq(dropped,0);eq(#events,1);eq(events[1].targets[1].health.after,100)
 for _,bad in ipairs({'','ITEM_EVENTS 2 0\n',sample:gsub('T abc','T invalid'),sample:gsub('1 1\nT','1 5\nT'),sample:sub(1,-8)})do assert(not M.parse_events(bad))end
end)
local function object(addr)
 return {IsValid=function()return true end,GetAddress=function()return addr end}
end
test('module native lifecycle, duplicate and stale-generation suppression',function()
 local messages,installs,removes={},0,0
 local actor,inv=object(0xabc),object(0xdef)
 local c={inventory=inv,targets={{actor=actor,name='You'}},session='campaign1'}
 local native={install=function(watch)installs=installs+1;assert(watch:match('^1 1 def 1'));return 'INSTALLED\n'end,drain=function()return sample end,remove=function()removes=removes+1;return 'REMOVED\n'end}
 local api=M.new({notify=function(m)messages[#messages+1]=m end,item_native=native,item_context=function()return c end,item_tag_index=function(tag)if tag==info.tag then return 101 else return 202 end end,item_name=function()return info.name end})
 api.tick({});eq(installs,1);eq(#messages,1);api.tick({});eq(#messages,1)
 local stale=event(5,4);stale.sequence=2;stale.epoch=99;eq(api.accept(stale,info),false)
 api.set_enabled(false);eq(removes,1);api.tick({});eq(#messages,1);eq(api.status().attached,false)
 api.shutdown()
end)
test('failed install never produces feedback',function()
 local n=0
 local api=M.new({notify=function()n=n+1 end,item_context=function()return {inventory=object(10),targets={}}end,item_tag_index=function()return 1 end,item_native={install=function()return 'ERROR unsupported build'end,drain=function()return sample end,remove=function()return 'REMOVED'end}})
 api.tick({});eq(n,0);eq(api.status().attached,false)
end)
test('combat discovery watches director cats and reset logs only state changes',function()
 local inv,pawn,cat,health,stamina,director,gs=object(10),object(11),object(12),object(13),object(14),object(15),object(16)
 local pc=object(19);pc.PlayerState=object(17);pc.PlayerState.InventoryComponent=inv
 local turn=object(18);turn.GetOwner=function()return cat end
 director.PlayerParty={ForEach=function(_,cb)cb(1,{get=function()return turn end})end};gs.Director=director
 health.GetOwner=function()return cat end;stamina.GetOwner=function()return cat end
 local old=FindAllOf;FindAllOf=function(class)if class=='SwtQuestHealthComponent'then return {health}elseif class=='SwtCombatStaminaComponent'then return {stamina}else return {}end end
 local watch,logs;logs={}
 local api=M.new({notify=function()end,log=function(s)logs[#logs+1]=s end,item_tag_index=function()return 101 end,item_native={install=function(w)watch=w;return 'INSTALLED'end,drain=function()return 'ITEM_EVENTS 1 0\n'end,remove=function()return 'REMOVED'end}})
 api.tick({offline=true,combat=true,pawn=pawn,pc=pc,gameState=gs,profile='test',worldId=1})
 assert(watch:find('c d e',1,true));assert(not watch:find('b ',1,true));eq(api.status().attached,true)
 api.reset('no active campaign');local n=#logs;api.reset('no active campaign');api.reset('no active campaign');eq(#logs,n)
 FindAllOf=old
end)
print(string.format('%d item-feedback tests passed.',passed))
