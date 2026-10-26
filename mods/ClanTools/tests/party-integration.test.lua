local source=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local json=dofile(source..'../Scripts/json.lua');local M=dofile(source..'../Scripts/party.lua')
local originalLoad=package.loadlib;local files={};local state={{role=78,tag=4}};local failOnce=false;local writesFail=false;local applies=0;local validRoster=true
local clans={'ThunderClan','ShadowClan','RiverClan','WindClan'}
function FName(tag)local i;for n,c in ipairs(clans)do if tag=='Gameplay.Combat.Character.Cat.'..c then i=n end end;return {ToString=function()return tag end,GetComparisonIndex=function()return assert(i)end}end
local function nativeRead()
 local rows={tostring(#state)};for _,v in ipairs(state)do rows[#rows+1]=v.role..' '..v.tag..' 0'end
 files['test/bin/snapshot.txt']=table.concat(rows,'\n')..'\n';files['test/bin/bridge-status.txt']='READ OK\n'
end
local function nativeApply()
 applies=applies+1
 if failOnce then failOnce=false;files['test/bin/bridge-status.txt']='ERROR transient\n';return end
 local p={};for role,tag in files['test/bin/request.txt']:gmatch('(%d+) (%d+) 0')do p[#p+1]={role=tonumber(role),tag=tonumber(tag)}end
 state=p;files['test/bin/bridge-status.txt']='APPLIED OK\n'
end
package.loadlib=function(_,symbol)return symbol=='ClanParty_read'and nativeRead or nativeApply end
local ctx={root='test/',clans=clans,json=json,log=function()end,backupSave=function()return true end,
 read=function(p)return files[p]end,write=function(p,s)if writesFail and p:find('party%-character%-profile_0%.json')then writesFail=false;error('disk write failed')end;files[p]=s end,
 snapshot=function()return{profile='profile',slot=0,chapter='Chapter00',clan=4,offline=true,phase=4,combat=false}end,
 getCats=function()return {{role=78},{role=82}},{valid=validRoster,reason='Snapshot incomplete'}end,
 validateCat=function()return true end}
local api=M.new(ctx)
failOnce=true;assert(not pcall(api.select,{82}));assert(state[1].role==78);assert(not json.decode(files['test/state/party-character-profile_0.json']).enabled)
assert(api.select({82}));assert(state[1].role==82 and api.error==nil);print('PASS party retries after native failure without persisting failed selection')
writesFail=true;assert(not pcall(api.select,{}));assert(state[1].role==82);assert(json.decode(files['test/state/party-character-profile_0.json']).roles[1]==82);print('PASS party restores gameplay and prior config after persistence failure')
assert(api.select({}));assert(#state==0);assert(api.restore());assert(state[1].role==78);print('PASS empty party and original story restoration')
local before=applies;assert(not pcall(api.select,{82,82}));assert(applies==before);print('PASS duplicate selection rejected before native mutation')
validRoster=false;assert(not pcall(api.select,{78}));assert(applies==before);print('PASS unavailable saved roster cannot remove or replace companions')
validRoster=true
local selectedSlot=3;ctx.snapshot=function()return{profile='profile',slot=selectedSlot,chapter='Chapter00',clan=4,offline=true,phase=4,combat=false}end
files['test/state/party-profile.json']=json.encode({enabled=true,roles={82}})
local old=applies;api.tick();assert(applies==old,'Legacy profile-wide selection must not replay into another character')
assert(api.select({82}));selectedSlot=4;state={{role=78,tag=4}};old=applies;api.tick();assert(applies==old and state[1].role==78)
assert(api.select({}));selectedSlot=3;api.tick();assert(#state==1 and state[1].role==82)
selectedSlot=4;api.tick();assert(#state==0)
assert(files['test/state/party-profile.json']~=nil)
print('PASS per-character party configuration and original-story records; legacy files remain untouched')
package.loadlib=originalLoad
