local module=dofile('mods/ClanTools/Scripts/admin_enemy_cleanup.lua')
local oldOpen,oldLoad,oldFind=io.open,package.loadlib,StaticFindObject
local request,response,mode,passed='','','safe',0
local function obj(id,name)
 return {IsValid=function()return true end,GetAddress=function()return id end,GetFullName=function()return name end}
end
local cls=obj(11,'BlueprintGeneratedClass /Game/Gameplay/Blueprints/WorldElements/BP_Enemy_Generator.BP_Enemy_Generator_C')
local generator=obj(10);generator.GetClass=function()return cls end
local player=obj(12);local enemy=obj(13)
StaticFindObject=function()return enemy end
io.open=function(path,access)
 if access=='wb'then return {write=function(_,text)request=text;return true end,close=function()end}end
 return {read=function()return response end,close=function()end}
end
package.loadlib=function(path,symbol)
 assert(symbol=='ClanEnemy_cleanup_probe')
 return function()
  local nonce=request:match('^(%d+)')
  if mode=='safe'then response=nonce..' SAFE 2 1\n'
  elseif mode=='stale'then response='0 SAFE 2 1\n'
  elseif mode=='badcount'then response=nonce..' SAFE 2 3\n'
  else response=nonce..' REFUSED protected_player\n'end
 end
end
local function test(name,fn)
 local ok,err=xpcall(fn,debug.traceback);if not ok then io.open=oldOpen;package.loadlib=oldLoad;StaticFindObject=oldFind;error(err)end
 passed=passed+1;print('PASS '..name)
end
local check=module.new('isolated/')
test('safe native response requires exact nonce and bounded counts',function()
 mode='safe';local ok,info=check(generator,player);assert(ok and info.total==2 and info.live==1);assert(request:match('^1 a b c d\n$'))
end)
test('native player refusal propagates',function()mode='refused';assert(not pcall(check,generator,player))end)
test('stale native response blocks cleanup',function()mode='stale';assert(not pcall(check,generator,player))end)
test('invalid native counts block cleanup',function()mode='badcount';assert(not pcall(check,generator,player))end)
io.open=oldOpen;package.loadlib=oldLoad;StaticFindObject=oldFind
print(passed..' enemy cleanup mailbox model tests passed.')
