local M=dofile('mods/ClanTools/Scripts/character_identity.lua')
local hash=string.rep('a',64);local calls=0;local profile='abc';local slot=0;local failure
local key=M.new(function()
 calls=calls+1
 if failure then return nil,failure end
 return {action='GENERATION profile='..profile..' slot='..slot..' hash='..hash}
end)
local function snapshot()return{profile='abc',slot=0,offline=true}end
local s=snapshot()
for _=1,100 do assert(key(s)=='abc_0_'..hash)end
assert(calls==1,'A roster snapshot must query live identity only once, not once per cat')
assert(key(snapshot())=='abc_0_'..hash and calls==2,'Fresh snapshots must not trust a cache keyed only by slot')
hash=string.rep('b',64);assert(key(snapshot())=='abc_0_'..hash)
print('PASS live generation is memoized only within a snapshot and reused slots get distinct keys')
profile='other';assert(not key(snapshot()));profile='abc';slot=1;assert(not key(snapshot()));slot=0
for _,invalid in ipairs({'',string.rep('a',63),string.rep('a',65),'../unsafe',string.rep('z',64)})do hash=invalid;assert(not key(snapshot()))end
failure='Missing live generation';s=snapshot();local value,why=key(s);assert(not value and why==failure)
local before=calls;assert(not key(s)and calls==before,'Unavailable identity is also memoized within a roster')
print('PASS absent, malformed and mismatched live generations fail closed without a fabricated identity')
failure=nil;hash=string.rep('A',64);assert(key(snapshot())=='abc_0_'..hash:lower())
for _,invalid in ipairs({{profile='../escape',slot=0,offline=true},{profile='abc',slot=-1,offline=true},{profile='abc',slot=0.5,offline=true},{profile='abc',slot=0,offline=false}})do before=calls;assert(not key(invalid)and calls==before)end
local throwing=M.new(function()error('native unavailable')end);assert(not throwing(snapshot()))
print('PASS unsafe profile/slot, online state and transport exceptions never produce a persistence key')
local prefix='profile-A_0_'
assert(M.fileKey(prefix..string.rep('0',64))==prefix..string.rep('a',52))
assert(M.fileKey(prefix..string.rep('f',64))==prefix..string.rep('7',51)..'q')
local sequence='';for i=0,31 do sequence=sequence..string.format('%02x',i)end
assert(M.fileKey(prefix..sequence)==prefix..'aaaqeayeaudaocajbifqydiob4ibceqtcqkrmfyydenbwha5dypq')
local seen={}
for value=0,255 do
 local token=M.fileKey(prefix..string.rep('0',62)..string.format('%02x',value)):lower()
 assert(not seen[token],'Every final-byte value must stay distinct on a case-insensitive filesystem');seen[token]=true
end
assert(M.fileKey('profile-A_0_'..sequence)~=M.fileKey('profile-A_1_'..sequence))
assert(M.fileKey('profile-A_0_'..sequence)~=M.fileKey('other_0_'..sequence))
for _,invalid in ipairs({'','profile_0_'..string.rep('0',63),'../profile_0_'..string.rep('0',64)})do assert(not pcall(M.fileKey,invalid))end
print('PASS compact file identities preserve all hash bits with a case-insensitive-safe alphabet')
