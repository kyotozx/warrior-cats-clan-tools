local module=dofile('mods/ClanTools/Scripts/cat_names.lua')
local json=dofile('mods/ClanTools/Scripts/json.lua')
local passed=0;local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function fixture()
 local f={files={},s={profile='abc',slot=0,offline=true,clan=4},cat={role=77,clan=4,living=true,rank='Warrior'}}
 f.ctx={root='',json=json,read=function(p)return f.files[p]end,write=function(p,s)if f.fail then error('disk failed')end;f.files[p]=s end,
  snapshot=function()return f.s end,validateCat=function()return true end,catalog={Names={STR_CAT_NAME1_PAW='Woodpaw',STR_CAT_NAME1_KIT='Woodkit',STR_CAT_NAME1_WING='Woodwing',STR_CAT_NAME2_FUR='Emberfur',STR_CAT_NAME2_STAR='Emberstar'}}}
 f.api=module.new(f.ctx);return f
end
test('validates free Unicode names and excludes markup/control text',function()
 assert(module.validate('  Café Moon  ')=='Café Moon');assert(not module.validate(''));assert(not module.validate('a\nb'));assert(not module.validate('<b>cat'));assert(not module.validate(string.rep('a',41)))
end)
test('prepare is preview-only and commit survives a fresh module',function()
 local f=fixture();local receipt=f.api.prepare(f.s,f.cat,'Moonlight');assert(next(f.files)==nil)
 assert(f.api.get(f.s,77,'Original')=='Original');assert(f.api.commit(receipt));assert(module.new(f.ctx).get(f.s,77,'Original')=='Moonlight')
end)
test('names remain scoped to profile and slot',function()
 local f=fixture();assert(f.api.commit(f.api.prepare(f.s,f.cat,'One')));f.s.slot=1;assert(f.api.get(f.s,77,'Original')=='Original')
 f.s.slot=0;f.s.profile='other';assert(f.api.get(f.s,77,'Original')=='Original')
end)
test('profile switch and duplicate commit are refused',function()
 local f=fixture();local r=f.api.prepare(f.s,f.cat,'One');f.s.profile='other';assert(not pcall(f.api.commit,r));f.s.profile='abc';assert(f.api.commit(r));assert(not pcall(f.api.commit,r))
end)
test('failed persistence does not update cached display name',function()
 local f=fixture();local r=f.api.prepare(f.s,f.cat,'One');f.fail=true;assert(not pcall(f.api.commit,r));assert(f.api.get(f.s,77,'Original')=='Original')
end)
test('partial sidecar failure restores previous names from backup',function()
 local f=fixture();assert(f.api.commit(f.api.prepare(f.s,f.cat,'Before')))
 local receipt=f.api.prepare(f.s,f.cat,'After');local original=f.ctx.write;local once=true
 f.ctx.write=function(path,raw)if once and path:match('%.json$')then once=false;f.files[path]='broken';error('partial write')end;original(path,raw)end
 assert(not pcall(f.api.commit,receipt));assert(f.api.get(f.s,77,'Original')=='Before');f.api.invalidate();assert(f.api.get(f.s,77,'Original')=='Before')
end)
test('generated names match rank and differ from current when possible',function()
 local f=fixture();f.cat.rank='Kit';assert(f.api.generate(f.cat)=='Woodkit');f.cat.rank='Leader';assert(f.api.generate(f.cat)=='Emberstar');f.cat.rank='Warrior';assert(f.api.generate(f.cat,'Woodwing')=='Emberfur')
end)
test('dead foreign and invalid profile identities are rejected',function()
 local f=fixture();f.cat.living=false;assert(not pcall(f.api.prepare,f.s,f.cat,'Cat'));f.cat.living=true;f.cat.clan=1;assert(not pcall(f.api.prepare,f.s,f.cat,'Cat'));f.s.profile='../bad';assert(not pcall(f.api.get,f.s,77,'Original'))
end)
test('override checks are cached and follow commits and profile switches',function()
 local f=fixture();local reads=0;local read=f.ctx.read
 f.ctx.read=function(path)reads=reads+1;return read(path)end
 for i=1,100 do assert(not f.api.hasOverrides(f.s))end
 assert(reads==1,'No repeated filesystem reads for an unchanged profile')
 assert(f.api.commit(f.api.prepare(f.s,f.cat,'Moonlight')));assert(f.api.hasOverrides(f.s))
 f.s.slot=1;assert(not f.api.hasOverrides(f.s));f.s.slot=0;assert(f.api.hasOverrides(f.s))
end)
print(passed..' cat name tests passed')
test('ambiguous legacy aliases never rename the first character after upgrade',function()
 local f=fixture();f.files['state/cat-names-abc_0.json']=json.encode({version=1,names={['77']='Other campaign'}})
 f.files['state/cat-names-character-abc_0.json']=json.encode({version=1,names={['77']='Wrong owner before GameConfig fix'}})
 assert(f.api.get(f.s,77,'Native name')=='Native name')
 assert(f.files['state/cat-names-abc_0.json']~=nil)
 assert(f.files['state/cat-names-character-abc_0.json']~=nil)
end)
