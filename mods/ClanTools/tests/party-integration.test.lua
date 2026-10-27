local source=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local json=dofile(source..'../Scripts/json.lua');local M=dofile(source..'../Scripts/party.lua')
local originalLoad=package.loadlib;local files={};local state={{role=78,tag=4}};local failOnce=false;local writesFail=false;local applies=0;local validRoster=true
local bridgeRoot='test/'
local clans={'ThunderClan','ShadowClan','RiverClan','WindClan'}
function FName(tag)local i;for n,c in ipairs(clans)do if tag=='Gameplay.Combat.Character.Cat.'..c then i=n end end;return {ToString=function()return tag end,GetComparisonIndex=function()return assert(i)end}end
local function nativeRead()
 local rows={tostring(#state)};for _,v in ipairs(state)do rows[#rows+1]=v.role..' '..v.tag..' 0'end
 files[bridgeRoot..'bin/snapshot.txt']=table.concat(rows,'\n')..'\n';files[bridgeRoot..'bin/bridge-status.txt']='READ OK\n'
end
local function nativeApply()
 applies=applies+1
 if failOnce then failOnce=false;files[bridgeRoot..'bin/bridge-status.txt']='ERROR transient\n';return end
 local p={};for role,tag in files[bridgeRoot..'bin/request.txt']:gmatch('(%d+) (%d+) 0')do p[#p+1]={role=tonumber(role),tag=tonumber(tag)}end
 state=p;files[bridgeRoot..'bin/bridge-status.txt']='APPLIED OK\n'
end
package.loadlib=function(_,symbol)return symbol=='ClanParty_read'and nativeRead or nativeApply end
local generation=string.rep('a',64)
local ctx={characterKey=function(s)return s.profile..'_'..s.slot..'_'..generation end,root='test/',clans=clans,json=json,log=function()end,backupSave=function()return true end,
 read=function(p)return files[p]end,write=function(p,s)if writesFail and p:find('party%-v3%-profile_0_vkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkva%.json')then writesFail=false;error('disk write failed')end;files[p]=s end,
 snapshot=function()return{profile='profile',slot=0,chapter='Chapter00',clan=4,offline=true,phase=4,combat=false}end,
 getCats=function()return {{role=78},{role=82}},{valid=validRoster,reason='Snapshot incomplete'}end,
 validateCat=function()return true end}
local api=M.new(ctx)
failOnce=true;assert(not pcall(api.select,{82}));assert(state[1].role==78);assert(not json.decode(files['test/state/party-v3-profile_0_vkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkva.json']).enabled)
assert(api.select({82}));assert(state[1].role==82 and api.error==nil);print('PASS party retries after native failure without persisting failed selection')
writesFail=true;assert(not pcall(api.select,{}));assert(state[1].role==82);assert(json.decode(files['test/state/party-v3-profile_0_vkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkvkva.json']).roles[1]==82);print('PASS party restores gameplay and prior config after persistence failure')
assert(api.select({}));assert(#state==0);assert(api.restore());assert(state[1].role==78);print('PASS empty party and original story restoration')
local before=applies;assert(not pcall(api.select,{82,82}));assert(applies==before);print('PASS duplicate selection rejected before native mutation')
validRoster=false;assert(not pcall(api.select,{78}));assert(applies==before);print('PASS unavailable saved roster cannot remove or replace companions')
validRoster=true
local selectedSlot=3;ctx.snapshot=function()return{profile='profile',slot=selectedSlot,chapter='Chapter00',clan=4,offline=true,phase=4,combat=false}end
files['test/state/party-profile.json']=json.encode({enabled=true,roles={82}})
files['test/state/party-character-profile_3.json']=json.encode({enabled=true,roles={82}})
local old=applies;api.tick();assert(applies==old,'Legacy profile-wide selection must not replay into another character')
assert(api.select({82}));selectedSlot=4;state={{role=78,tag=4}};old=applies;api.tick();assert(applies==old and state[1].role==78)
assert(api.select({}));selectedSlot=3;api.tick();assert(#state==1 and state[1].role==82)
selectedSlot=4;api.tick();assert(#state==0)
assert(files['test/state/party-profile.json']~=nil)
assert(files['test/state/party-character-profile_3.json']~=nil)
print('PASS per-character party configuration and original-story records; legacy files remain untouched')
generation=string.rep('b',64);state={{role=78,tag=4}};old=applies;api.tick();assert(applies==old and state[1].role==78)
assert(api.restore()and state[1].role==78,'A reused slot must not restore the prior character story party')
assert(api.select({82}));assert(api.restore()and state[1].role==78)
generation=string.rep('a',64);api.tick();assert(#state==0,'Previous generation settings remain intact')
print('PASS reused slot cannot replay old selections or original-story backups')
local writes=0;for _ in pairs(files)do writes=writes+1 end
ctx.characterKey=function()return nil,'Missing generation'end;old=applies;api.tick();assert(applies==old)
assert(not pcall(api.select,{82}));assert(not pcall(api.restore));local after=0;for _ in pairs(files)do after=after+1 end;assert(after==writes)
print('PASS missing live generation rejects party mutation without sidecar writes')
local function availableIdentity(s)return s.profile..'_'..s.slot..'_'..generation end
ctx.characterKey=availableIdentity;api.tick();assert(#state==0)
ctx.characterKey=function()return nil,'Temporary generation lookup failure'end
old=applies;api.tick();assert(api.error and applies==old)
state={{role=78,tag=4}};ctx.characterKey=availableIdentity;api.tick()
assert(api.error==nil and #state==0,'Party enforcement must recover when the same generation becomes readable again')
-- Recovery from an identity outage must not silently clear an actual native
-- write failure, which still needs a deliberate user retry.
state={{role=78,tag=4}};failOnce=true;api.tick();local writeError=api.error;assert(writeError)
ctx.characterKey=function()return nil,'Temporary generation lookup failure'end;api.tick()
ctx.characterKey=availableIdentity;old=applies;api.tick()
assert(applies==old and api.error==writeError,'An identity retry must preserve a latched native failure')
print('PASS transient generation failure recovers without clearing native application failures')
bridgeRoot='C:/Program Files (x86)/Steam/steamapps/common/Warrior Cats Clans of the Forest/Wrc/Binaries/Win64/ue4ss/Mods/ClanTools/Scripts/../'
ctx.root=bridgeRoot;ctx.snapshot=function()return{profile=string.rep('a',32),slot=0,chapter='Chapter00',clan=4,offline=true,phase=4,combat=false}end
local writes=ctx.write;local storyWrites=0
ctx.write=function(path,bytes)assert(#path<260,'Windows filename is too long: '..#path);if path:match('%.story.txt$')then storyWrites=storyWrites+1 end;writes(path,bytes)end
api=M.new(ctx);assert(api.select({}));assert(api.restore());assert(storyWrites>0)
print('PASS original story backup and configuration fit the default Steam path')
package.loadlib=originalLoad
