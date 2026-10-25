local route=dofile('mods/ClanTools/Scripts/appearance_commands.lua').route
local h={footerIndex=2};local called={}
local function dispatch(a)called[#called+1]=a end
assert(not route(h,4,0,dispatch)) -- native slider remains available
assert(route(h,25,0,dispatch)and called[1]=='cancel')
assert(route(h,25,1,dispatch)and route(h,25,2,dispatch)and #called==1)
assert(route(h,23,0,dispatch)and h.footerMode and h.footerIndex==2)
assert(route(h,23,1,dispatch)and h.footerMode) -- release does not toggle twice
assert(route(h,3,0,dispatch)and h.footerIndex==3)
assert(route(h,26,0,dispatch)and called[2]=='apply')
assert(route(h,26,2,dispatch)and #called==2) -- held confirm never reapplies
assert(route(h,3,2,dispatch)and h.footerIndex==1) -- wrapped directional repeat
assert(route(h,26,0,dispatch)and called[3]=='reset')
assert(route(h,1,0,dispatch)and not h.footerMode)
assert(not route(h,3,0,dispatch))
assert(not route(h,7,0,dispatch),'Keyboard E must not randomize the cat')
assert(route(h,8,0,dispatch)and h.footerMode and h.footerIndex==2)
h.closed=true;assert(not route(h,25,0,dispatch)and #called==3)
print('PASS native editor slider pass-through, Cancel press/release, footer navigation, confirm debounce and closed-handle refusal')
local module=dofile('mods/ClanTools/Scripts/appearance_commands.lua')
local h2={footerIndex=2};local pending,events={},{}
local function later(fn)pending[#pending+1]=fn end
local function nextframe()for _,fn in ipairs(pending)do fn()end;pending={}end
local function dispatch2(a)events[#events+1]=a end
assert(module.key_command(h2,'Right')==nil)
assert(module.route_once(h2,module.key_command(h2,'Tab'),0,dispatch2,later));assert(h2.footerMode)
assert(module.route_once(h2,8,0,dispatch2,later));assert(h2.footerMode,'Semantic duplicate must not toggle back')
nextframe()
assert(module.route_once(h2,module.key_command(h2,'Right'),0,dispatch2,later));assert(h2.footerIndex==3)
assert(module.route_once(h2,17,0,dispatch2,later));assert(h2.footerIndex==3,'Raw+semantic right must move once')
nextframe()
module.route_once(h2,26,0,dispatch2,later);module.route_once(h2,module.key_command(h2,'Enter'),0,dispatch2,later)
assert(#events==1 and events[1]=='apply')
nextframe();module.route_once(h2,module.key_command(h2,'BackSpace'),0,dispatch2,later)
assert(events[2]=='cancel')
print('PASS raw/semantic aliases across editor/pause dispatch once per frame; native sliders retain input outside footer')
do
 local x={footerActions={'randomize','compare','library','tools','cancel','apply'},footerDefault=5};local log={}
 local function call(action)log[#log+1]=action end
 assert(module.route(x,23,0,call)and x.footerIndex==5)
 module.route(x,3,0,call);module.route(x,26,0,call);assert(log[1]=='apply')
 module.route(x,3,0,call);module.route(x,26,0,call);assert(log[2]=='randomize')
 module.route(x,27,0,call);module.route(x,27,1,call);module.route(x,27,2,call);assert(#log==3)
 x.footerActions={'previous','next','load','save','delete','editor'};x.footerDefault=6;x.backAction='editor'
 module.route(x,25,0,call);assert(log[4]=='editor')
 x.footerMode=false;x.comparing=true;assert(module.route(x,4,0,call));assert(#log==4)
 assert(module.key_command(x,'R')==27 and module.key_command(x,'Gamepad_FaceButton_Left')==27)
 print('PASS expandable footer, native randomize press-only, library Back and comparison edit lock')
end
