-- A FILE userdata stands in for UE4SS userdata; no game/native pointer involved.
local object=assert(io.tmpfile());local original=debug.getmetatable(object)
local registered,engineValid,calls=true,false,0
debug.setmetatable(object,{__index={IsValid=function()return registered end}})
local system={IsValid=function()return true end,CallFunction=function()error('Broken context-first call must never be used.')end}
-- Models the documented UFunction __call stack, not a guessed UObject method.
-- LuaUObject.cpp:100-128 consumes function first, then explicit object context.
local reflectFails=false
local fn=setmetatable({IsValid=function()return true end},{__call=function(_,context,o)
    assert(context==system and o==object);calls=calls+1
    if reflectFails then error('reflection unavailable')end
    return engineValid
end})
_G.StaticFindObject=function(path)if path:match(':IsValid$')then return fn end;return system end
local valid=dofile('mods/ClanTools/Scripts/runtime_valid.lua').valid
assert(valid(object)==false and calls==1,'Pending destruction must fail engine validity.')
engineValid=true;assert(valid(object)==true and calls==2)
registered=false;assert(valid(object)==false and calls==2,'Unregistered userdata must not call engine.')
registered=true;reflectFails=true
assert(valid(object)==false,'Engine validity failure must fail closed.')
assert(valid({IsValid=function()return false end})==false)
debug.setmetatable(object,original);object:close()
print('5 runtime validity cases passed; no game process accessed.')
