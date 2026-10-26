local source=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local M=dofile(source..'../Scripts/context.lua')
local function eq(a,b)assert(a==b,tostring(a)..' ~= '..tostring(b))end
local s=M.validateSettings({theme='oops',duration='five',feedback='false',sound=false,extra=true})
eq(s.theme,'dark');eq(s.duration,5);eq(s.feedback,true);eq(s.sound,false);eq(s.extra,nil)
eq(M.validateSettings(42).duration,5);eq(M.validateSettings({theme='light',duration=8,feedback=false}).feedback,false)
print('PASS settings recover from scalar JSON and invalid field types')
local live=true;local object={IsValid=function()return live end};eq(M.valid(object),true)
live=false;eq(M.valid(object),false)
-- Reflected userdata validation is covered independently in runtime-valid.test.lua.
print('PASS Lua ownership wrappers retain their explicit lifetime checks')
local snapshot={profile='profile',slot=0,clan=4,offline=true}
M.snapshot=function()return snapshot end
local raw='{broken';M.read=function()return raw end
local cats,metadata=M.getCats();eq(#cats,0);eq(metadata.valid,false)
raw=M.json.encode({profile={['0']={NPCData={NarrativeRoles={WindClanKit='(ClanType=WindClan,Role=Kit)',WindClanMedicineCat='(ClanType=WindClan,Role=Dead)'}}}}})
cats,metadata=M.getCats();eq(#cats,1);eq(metadata.valid,true);eq(cats[1].role,M.catalog.Enums.WindClanKit)
print('PASS incomplete saved snapshot is unavailable rather than an empty eligible clan')
local rank,clan=5,4
M.native=function(cmd)local role=tonumber(cmd:match('META (%d+)'));return{action=string.format('META narrative=%d clan=%d rank=%d',role,clan,rank)}end
eq(M.validateCat({role=82},snapshot),true);rank=12;eq(M.validateCat({role=82},snapshot),false);rank=9;eq(M.validateCat({role=82},snapshot),false);rank=5;clan=2;eq(M.validateCat({role=82},snapshot),false)
print('PASS party eligibility checks current native rank and clan before mutation')
local decode=M.json.decode;local parses=0
M.json.decode=function(value)parses=parses+1;return decode(value)end
raw=raw..' '
for i=1,100 do cats,metadata=M.getCats();eq(metadata.valid,true)end
eq(parses,1)
raw='{partial';cats,metadata=M.getCats();eq(metadata.valid,false)
raw=nil;cats,metadata=M.getCats();eq(metadata.valid,false)
raw=M.json.encode({profile={['0']={NPCData={NarrativeRoles={}}}}})
cats,metadata=M.getCats();eq(metadata.valid,true);eq(#cats,0)
M.json.decode=decode
print('PASS unchanged save bytes reuse parsing; changed, missing or partial files never return stale roster data')
local function character(role)
 return{NPCData={NarrativeRoles={[role]='(ClanType=WindClan,Role=Warrior)'}}}
end
raw=M.json.encode({profile={Shared={General={CurrentCatSlot=0}},['0']=character('WindClanKit'),['3']=character('WindClanMedicineCat')}})
snapshot.slot=0;cats,metadata=M.getCats();eq(cats[1].roleName,'WindClanKit')
snapshot.slot=3;cats,metadata=M.getCats();eq(cats[1].roleName,'WindClanMedicineCat');eq(metadata.slot,3)
snapshot.slot=0;cats=M.getCats();eq(cats[1].roleName,'WindClanKit')
snapshot.slot=8;cats,metadata=M.getCats();eq(metadata.valid,false);eq(#cats,0)
print('PASS live character selection overrides stale disk CurrentCatSlot and never falls back to the first cat')
