local dir=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local json=dofile(dir..'json.lua')
local M={root=dir..'../',clans={'ThunderClan','ShadowClan','RiverClan','WindClan'}}
function M.read(path) local f=io.open(path,'rb');if not f then return nil end;local s=f:read('*a');f:close();return s:gsub('\r\n','\n')end
function M.write(path,s) local f=assert(io.open(path,'wb'),'Cannot write '..path);assert(f:write(s));f:close()end
M.valid=dofile(dir..'runtime_valid.lua').valid
function M.log(s) print('[ClanTools] '..tostring(s)..'\n')end
M.catalog=json.decode(assert(M.read(M.root..'data/catalog.json')))
M.saveDir=(os.getenv('LOCALAPPDATA')or'')..'/Wrc/Saved/SaveGames/'
local function snapshot()
 local gs=FindFirstOf('WrcGameplayGameState');if not M.valid(gs)then return nil end
 local p=gs.MainCharacter;if not M.valid(p)then return nil end
 local manager=FindFirstOf('WrcSaveManager');if not M.valid(manager)then return nil end
 local save=manager.SaveGame;if not M.valid(save)then return nil end
 local profile;save.saveSlots:ForEach(function(i,v)if i==save.CurrentSaveSlotIndex+1 then profile=v:get():ToString()end end)
 if not profile then return nil end
 local chapter={};StaticFindObject('/Script/SwtQuest.Default__BFLSwtQuest'):GetChapter(gs,chapter)
 local w=p:GetWorld();if not M.valid(w)then return nil end
 local pc=FindFirstOf('WrcGameplayPlayerController');if not M.valid(pc)then return nil end
 local standalone=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary'):IsStandalone(gs)
 return {gs=gs:GetAddress(),gameState=gs,pawn=p,world=w,worldId=w:GetFullName(),phase=gs.CurrentPhase,
  offline=standalone==true,combat=M.valid(gs.Director),profile=profile,slot=save.CurrentSaveSlotIndex,chapter=chapter.chapter:ToString(),
  clan=p.MeshCustomizationComponent.CustomData.ClanType,pc=pc}
end
function M.snapshot()local ok,s=pcall(snapshot);if ok then return s end;return nil end
local function field(s,key) if type(s)~='string'then return ''end;return s:match(key..'="([^"]*)"')or s:match(key..'=([^,()]*)')or'' end
local function name(custom,definition,fallback)
 local prefix,suffix=field(custom,'PrefixNameId'),field(custom,'SuffixNameId')
 local rank=field(custom,'Role');if suffix==''then suffix=rank=='Kit'and'_KIT'or rank=='Apprentice'and'_PAW'or''end
 local key=definition and definition.IsIconic and definition.IconicName or prefix..suffix
 return M.catalog.Names[key]or fallback
end
local function savedProfile(s)
 local raw=M.read(M.saveDir..'WrcGame.json');if not raw then return nil,'Save snapshot unavailable'end
 local ok,all=pcall(json.decode,raw);if not ok or type(all)~='table'then return nil,'Save snapshot is incomplete'end
 local profile=all[s.profile];local data=type(profile)=='table'and profile[tostring(s.slot)]
 if type(data)~='table'then return nil,'Active profile is missing from save snapshot'end
 return data
end
function M.getCats()
 local s=M.snapshot();if not s then return {},{valid=false,reason='No active campaign'}end
 local data,why=savedProfile(s);if not data then return {},{valid=false,reason=why}end
 if type(data.NPCData)~='table'or type(data.NPCData.NarrativeRoles)~='table'then return {},{valid=false,reason='Roster is missing from save snapshot'}end
 local out={};local clan=M.clans[s.clan];if not clan then return {},{valid=false,reason='Active clan unavailable'}end
 for role,custom in pairs((data.NPCData or{}).NarrativeRoles or{})do
  local rank=field(custom,'Role');local c=field(custom,'ClanType')
  if c==clan and rank~=''and rank~='None'and rank~='Dead'and rank~='StarClanAncestor'and rank~='Manifestation'and M.catalog.Enums[role]then
   local def;for _,d in ipairs(M.catalog.Roles)do if d.CampaignClan==clan and d.NarrativeRole==role then def=d;break end end
   local originalName=name(custom,def,role);local displayName=originalName
   if M.catNames then displayName=M.catNames.get(s,M.catalog.Enums[role],originalName)end
   out[#out+1]={role=M.catalog.Enums[role],roleName=role,name=displayName,originalName=originalName,rank=rank,clan=s.clan,living=true,custom=custom}
  end
 end
 table.sort(out,function(a,b)return a.name<b.name end);return out,{valid=true,source='saved snapshot',profile=s.profile,slot=s.slot}
end
function M.playerName()
 local s=M.snapshot();if not s then return 'Clan Tools'end
 local d=savedProfile(s);d=d and d.GameplayProgression and d.GameplayProgression['Gameplay.Combat.Character.Cat.Player']
 return d and name(d.Customization,nil,'Your cat')or'Your cat'
end
local metadataTransport
function M.validateCat(cat,s)
 s=s or M.snapshot()
 if not s or not s.offline or type(cat)~='table'or type(cat.role)~='number'or cat.role%1~=0 or cat.role<=0 or cat.role>=255 then return false,'Load an offline clan and choose a named clanmate.'end
 if not metadataTransport then metadataTransport=M.native or dofile(dir..'appearance.lua').nativeTransport(M.root..'bin/')end
 local result,why=metadataTransport('META '..cat.role)
 if not result then return false,why or'Live clanmate data unavailable'end
 local role,clan,rank=tostring(result.action):match('^META narrative=(%d+) clan=(%d+) rank=(%d+)$')
 role,clan,rank=tonumber(role),tonumber(clan),tonumber(rank)
 if role~=cat.role or clan~=s.clan then return false,'This cat is no longer in your current clan.'end
 -- EGiverRole from runtime SDK: None0, StarClanAncestor9, Dead12,
 -- Manifestation13 are not living companions. Other ranks are supported.
 if not rank or rank<1 or rank>=12 or rank==9 then return false,'This cat is not a living clanmate.'end
 return true
end
local backupSequence=0
function M.backupSave(s,cat)
 local stamp=os.date('%Y%m%d-%H%M%S')
 -- Binary saves must not pass through newline normalization.
 local f=assert(io.open(M.saveDir..'WrcGame.sav','rb'));local bytes=f:read('*a');f:close()
 local path;repeat backupSequence=backupSequence+1;path=M.root..'backups/'..stamp..'-'..s.profile..'-'..tostring(cat and cat.role or'party')..'-'..backupSequence..'.sav';f=io.open(path,'rb');if f then f:close()end until not f
 M.write(path,bytes);return path
end
function M.validateSettings(value)
 local out={theme='dark',feedback=true,sound=true,duration=5};if type(value)~='table'then return out end
 if value.theme=='dark'or value.theme=='light'then out.theme=value.theme end
 for _,k in ipairs({'feedback','sound'})do if type(value[k])=='boolean'then out[k]=value[k]end end
 if value.duration==3 or value.duration==5 or value.duration==8 then out.duration=value.duration end
 return out
end
M.settings=M.validateSettings(nil)
local cfg=M.read(M.root..'settings.json');if cfg then local ok,v=pcall(json.decode,cfg);if ok then M.settings=M.validateSettings(v)end end
function M.saveSettings()M.write(M.root..'settings.json',json.encode(M.settings))end
M.json=json
return M
