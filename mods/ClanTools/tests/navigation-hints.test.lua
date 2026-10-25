local M=dofile('mods/ClanTools/Scripts/navigation_hints.lua')
local x=M.build();assert(x.actions=='Enter / A (Cross): select     Backspace / B (Circle): back')
local y=M.build({{command=26,device='keyboard',key='F'},
 {command=5,device='gamepad',key='Gamepad_FaceButton_Left'},
 {command=1,device='keyboard',original='Up',key='I'},
 {command=9,device='keyboard',key='Q'},
 {command=25,device='gamepad'}})
assert(y.actions:find('F / X (Square)',1,true));assert(y.navigate:find('I / Down',1,true));assert(y.tabs:find('Q / 2',1,true))
print('PASS navigation hints respect active keyboard/controller remaps and missing native aliases')
