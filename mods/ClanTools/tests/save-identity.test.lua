local M=dofile('mods/ClanTools/Scripts/save_identity.lua')
PropertyTypes={IntProperty=1}
local registered=0;RegisterCustomProperty=function(p)registered=registered+1;assert(p.BelongsToClass=='/Script/SwtAdventure.SwtAdventureFlowManager'and p.OffsetInternal==340)end
local class={};StaticFindObject=function()return class end
local flow={ClanToolsCurrentCharacterSlot=4,IsA=function(_,c)return c==class end}
local instance={FlowManager=flow};local attempts=0
local ctx={valid=function(o)return type(o)=='table'and not o.dead end,verify=function()attempts=attempts+1;return{action='CONTEXT_LAYOUT flow_slot=340'}end}
local read=M.new(ctx)
for i=1,500 do assert(read(instance)==4)end
assert(attempts==1 and registered==1)
for _,n in ipairs({0,1,8,100})do flow.ClanToolsCurrentCharacterSlot=n;assert(read(instance)==n)end
for _,n in ipairs({-1,1.5,'0',false,2147483648})do flow.ClanToolsCurrentCharacterSlot=n;assert(read(instance)==nil)end
instance.FlowManager=nil;assert(read(instance)==nil)
ctx.verify=function()attempts=attempts+1;return nil end
read=M.new(ctx);for i=1,100 do assert(read(instance)==nil)end
assert(attempts==2 and registered==1,'Unsupported builds must fail closed without I/O polling')
ctx.verify=function()return{action='STATUS'}end
assert(M.new(ctx)(instance)==nil,'An old bridge must not authorize an unverified offset')
print('PASS live character identity, missing state and build guard; no disk-save or slot-zero fallback')
