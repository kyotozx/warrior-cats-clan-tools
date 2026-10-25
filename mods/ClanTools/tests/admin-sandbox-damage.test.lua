local M=dofile('mods/ClanTools/Scripts/admin_sandbox_damage.lua');local count=0
local function test(n,f)f();count=count+1;print('PASS '..n)end
local function object(id)return{IsValid=function()return true end,GetAddress=function()return id end}end
local function fixture()
 local player,enemy=object(1),object(2)
 local function party(actor)return{ForEach=function(_,fn)fn(1,{get=function()return{IsValid=function()return true end,GetOwner=function()return actor end}end})end}end
 local director=object(3);director.PlayerParty=party(player);director.EnemyParty=party(enemy);director.CurrentTurnAttackCharacter=player
 local s={offline=true,phase=4,profile='p',slot=0,chapter='c',worldId='w',combat=true,gameState=object(4)};s.gameState.Director=director
 local callback;local removed=0
 local api=M.new({snapshot=function()return s end},{verified=true,register=function(_,fn)callback=fn;return 1,2 end,unregister=function()removed=removed+1 end})
 local function send(damage,miss,target)
  local d={Damage=damage,bMissed=miss,Character=target or enemy};callback({get=function()return director end},{get=function()return d end});return d.Damage
 end
 return api,s,director,player,enemy,send,function()return removed end
end
test('only valid player-to-enemy queued damage gets multiplied',function()
 local a,s,d,p,e,send=fixture();assert(a.set_multiplier(4));assert(send(25,false)==100);d.CurrentTurnAttackCharacter=e;assert(send(25,false,p)==25)
 d.CurrentTurnAttackCharacter=p;assert(send(25,false,p)==25)
end)
test('misses and zero-damage status moves retain original results',function()
 local a,s,d,p,e,send=fixture();a.set_multiplier(10);assert(send(25,true)==25 and send(0,false)==0)
end)
test('one-hit uses bounded integer damage and restores multiplier when off',function()
 local a,s,d,p,e,send=fixture();a.set_multiplier(2);a.set_one_hit(true);assert(send(25,false)==1000000);a.set_one_hit(false);assert(send(25,false)==50)
end)
test('profile changes and online sessions disable before mutating damage',function()
 for _,change in ipairs({function(s)s.profile='other'end,function(s)s.offline=false end})do local a,s,d,p,e,send=fixture();a.set_multiplier(10);change(s);assert(send(25,false)==25);assert(a.state().multiplier==1 and not a.state().one_hit)end
end)
test('malformed damage disables override without crashing native processing',function()
 local a,s,d,p,e,send=fixture();a.set_multiplier(10);assert(send(1.5,false)==1.5);assert(a.state().error and a.state().multiplier==1)
end)
test('multiplier is bounded and shutdown unregisters once',function()
 local a,s,d,p,e,send,removed=fixture();assert(not a.set_multiplier(0));assert(not a.set_multiplier(101));a.set_multiplier(100);assert(send(20000,false)==1000000)
 assert(a.shutdown());assert(removed()==1);assert(a.shutdown());assert(removed()==1);assert(send(25,false)==25)
end)
test('reset works unverified outside gameplay and does not register hook',function()
 local registered=0;local api=M.new({snapshot=function()error('no game')end},{verified=false,register=function()registered=registered+1 end})
 assert(api.set_multiplier(1));assert(api.set_one_hit(false));assert(registered==0);assert(api.shutdown());assert(api.set_multiplier(1));assert(api.set_one_hit(false));assert(registered==0)
end)
test('each reset preserves the other independent override',function()
 local a,s,d,p,e,send=fixture();a.set_multiplier(4);a.set_one_hit(true);a.set_multiplier(1);assert(send(25,false)==1000000)
 a.set_multiplier(4);a.set_one_hit(false);assert(send(25,false)==100)
 s.offline=false;assert(a.set_multiplier(1));assert(a.set_one_hit(false));assert(a.state().multiplier==1 and not a.state().one_hit)
end)
print(count..' queued damage model tests passed; live hook dispatch requires validation.')
