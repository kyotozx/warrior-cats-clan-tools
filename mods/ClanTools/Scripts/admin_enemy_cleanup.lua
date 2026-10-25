-- Read-only check of the generator's actual native weak child array.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local valid=dofile(folder..'runtime_valid.lua').valid
local M={}
function M.new(bin,library)
 bin=bin or folder..'../bin/'
 local probe=assert(package.loadlib(bin..(library or'enemy-cleanup.dll'),'ClanEnemy_cleanup_probe'))
 local nonce=0
 local enemyPath='/Game/Gameplay/Blueprints/Characters/ExplorationCharacters/BP_Exploration_Character_Base.BP_Exploration_Character_Base_C'
 local generatorName='BlueprintGeneratedClass /Game/Gameplay/Blueprints/WorldElements/BP_Enemy_Generator.BP_Enemy_Generator_C'
 return function(generator,player)
  assert(valid(generator)and valid(player),'Encounter cleanup requires the original player and generator.')
  local class=generator:GetClass();assert(valid(class)and class:GetFullName()==generatorName,'Unsupported encounter generator class.')
  local enemyClass=StaticFindObject(enemyPath);assert(valid(enemyClass),'Enemy class is unavailable.')
  nonce=nonce+1
  local f=assert(io.open(bin..'enemy-cleanup-request.txt','wb'))
  assert(f:write(string.format('%d %x %x %x %x\n',nonce,generator:GetAddress(),class:GetAddress(),player:GetAddress(),enemyClass:GetAddress())));f:close()
  probe()
  f=assert(io.open(bin..'enemy-cleanup-status.txt','rb'));local response=f:read('*a');f:close()
  local responseNonce,status,detail=response:match('^(%d+) (%u+) ([^\r\n]*)')
  assert(tonumber(responseNonce)==nonce,'Stale encounter cleanup response.')
  assert(status=='SAFE','Native encounter cleanup refused: '..tostring(detail or response))
  local total,live=detail:match('^(%d+) (%d+)$');total=tonumber(total);live=tonumber(live)
  assert(total and live and total<=128 and live<=total,'Invalid encounter cleanup response.')
  return true,{total=total,live=live}
 end
end
return M
