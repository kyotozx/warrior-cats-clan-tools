local directory=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local Module=dofile(directory..'../Scripts/key_rebind.lua')
local function clone(t)local o={};for k,v in pairs(t)do o[k]=type(v)=='table'and clone(v)or v end;return o end
local base={
 {device='keyboard',command=60,kind=1,original='W',key='W',scale_bits=1065353216},
 {device='keyboard',command=60,kind=1,original='S',key='S',scale_bits=3212836864},
 {device='keyboard',command=67,kind=0,original='E',key='E',scale_bits=1065353216},
 {device='keyboard',command=91,kind=0,original='Enter',key='Enter',scale_bits=1065353216},
 {device='gamepad',command=60,kind=1,original='Gamepad_LeftY',key='Gamepad_LeftY',scale_bits=1065353216},
 {device='gamepad',command=72,kind=0,original='Gamepad_LeftShoulder',key='Gamepad_LeftShoulder',scale_bits=1065353216},
 {device='gamepad',command=91,kind=0,original='Gamepad_Special_Right',key='Gamepad_Special_Right',scale_bits=1065353216},
}
local function id(r)return table.concat({r.device,r.command,r.kind,r.original,r.scale_bits},':')end
local current={input=1,pc=2,world='world1',profile='profile1',object_index='Input1'};local active={};local persisted;local saveFail=false;local removeFail=false;local applyFail=false;local removed=0
local ctx={snapshot=function()return current end,remap_context=function(s)assert(s);return clone(s)end,
 load_keybinds=function()return persisted end,save_keybinds=function(v)if saveFail then error('disk full')end;persisted=clone(v);return true end,
 remap_native={list=function()local rows=clone(base);for _,r in ipairs(rows)do for _,rule in ipairs(active)do if id(r)==id(rule)then r.key=rule.key end end end;return rows end,
 apply=function(_,rules)active=clone(rules);if applyFail then applyFail=false;error('native readback failed')end;return true end,
 remove=function()if removeFail then return false end;active={};removed=removed+1;return true end}}
local api=Module.new(ctx);local list=api.bindings();assert(#list==7 and list[1].editable and not list[7].editable)
assert(api.rebind(list[1].id,'Up'));assert(active[1].original=='W'and active[1].key=='Up');assert(api.bindings()[2].key=='S')
print('PASS positive movement key remaps independently of negative movement side')
assert(api.rebind(list[5].id,'Gamepad_RightY'));assert(api.bindings()[5].key=='Gamepad_RightY')
assert(not api.rebind(list[5].id,'Gamepad_FaceButton_Top'));assert(not api.rebind(list[6].id,'Gamepad_LeftX'));assert(not api.rebind(list[7].id,'Gamepad_FaceButton_Top'))
assert(not api.rebind(list[3].id,'F6'));assert(not api.rebind(list[3].id,'UnknownMadeUpKey'));assert(not api.rebind(list[3].id,'Gamepad_FaceButton_Top'))
print('PASS controller axes/buttons stay type-compatible; pause recovery and F6 stay available')
assert(not api.rebind(list[3].id,'Up'));assert(api.rebind(list[3].id,'Up',{allow_conflict=true}));assert(api.reset_binding(list[3].id));assert(api.bindings()[3].key=='E')
print('PASS cross-command conflicts require explicit opt-in; per-binding reset restores original')
saveFail=true;assert(not api.rebind(list[3].id,'F'));saveFail=false;assert(api.bindings()[3].key=='E')
applyFail=true;assert(not api.rebind(list[3].id,'F'));assert(api.bindings()[3].key=='E')
print('PASS persistence or partial native-apply failure rolls back prior mappings')
current.profile='profile2';assert(api.tick(current));assert(#active==0 and removed>0);assert(api.status().overrides==0)
current.profile='profile1';assert(api.tick(current));assert(#active==2)
print('PASS profile switch removes overrides; returning restores that profile only')
removeFail=true;assert(not api.shutdown());assert(api.status().attached);removeFail=false;assert(api.shutdown());assert(not api.status().attached and #active==0)
local restart=Module.new(ctx);assert(restart.tick(current));assert(#active==2);assert(restart.reset_all());assert(#active==0 and #persisted.profiles.profile1==0)
print('PASS shutdown cleanup retries; saved overrides reapply and Reset All persists')
persisted={version=1,profiles={profile1={{device='keyboard',command=65,kind=0,original='E',key='Invalid',scale_bits=1065353216}}}}
local invalid=Module.new(ctx);assert(invalid.status().error);assert(invalid.tick(current));assert(#active==0)
print('PASS invalid persisted key names fail closed without native application')
assert(invalid.shutdown());persisted=nil
base[#base+1]={device='keyboard',command=26,kind=0,original='Enter',key='Enter',scale_bits=1065353216}
base[#base+1]={device='gamepad',command=24,kind=0,original='Gamepad_Special_Right',key='Gamepad_Special_Right',scale_bits=1065353216}
local menus=Module.new(ctx);local menuRows=menus.bindings();assert(menuRows[8].editable and not menuRows[9].editable)
assert(menus.rebind(menuRows[8].id,'F'));assert(menus.bindings()[8].key=='F');assert(menus.shutdown())
local reloaded=Module.new(ctx);assert(reloaded.tick(current));assert(reloaded.bindings()[8].key=='F');assert(reloaded.reset_all());assert(reloaded.shutdown())
print('PASS native menu Confirm binding persists and reloads; controller Start recovery is protected')
persisted={version=1,profiles={profile1={{device='keyboard',command=65,kind=0,original='E',key='F',scale_bits=1065353216}}}}
local migrated=Module.new(ctx);assert(migrated.tick(current));assert(active[1].command==67 and active[1].key=='F')
assert(persisted.version==1,'Loading must not rewrite personal settings')
assert(migrated.rebind(migrated.bindings()[3].id,'G'));assert(persisted.version==2 and persisted.profiles.profile1[1].command==67)
assert(migrated.shutdown());local again=Module.new(ctx);assert(again.tick(current));assert(active[1].command==67,'Do not migrate twice');assert(again.shutdown())
local commands=dofile(directory..'../Scripts/input_commands.lua')
assert(commands[66]=='Player_Customization_Yaw' and commands[91]=='Player_Pause' and commands[109]=='Map_Axis_Zoom')
print('PASS patch 1.1 command migration preserves old controls and protects the new pause command')
persisted={version=2,profiles={profile1={clone(base[1]),clone(base[3])}}}
persisted.profiles.profile1[1].key='Up';persisted.profiles.profile1[2].key='F7'
local reserved=Module.new(ctx);assert(reserved.tick(current));assert(#active==1 and active[1].key=='Up')
assert(#persisted.profiles.profile1==2,'Loading must not rewrite personal settings')
local row=reserved.bindings()[3];local choices={};for _,key in ipairs(reserved.available_keys(row))do choices[key]=true end
for _,key in ipairs({'F6','F7','F8','F9','F10'})do
 assert(not choices[key],key..' must not be offered');assert(not reserved.rebind(row.id,key,{allow_conflict=true}))
end
assert(reserved.shutdown())
print('PASS suite shortcuts are reserved and old conflicts do not discard unrelated bindings')
