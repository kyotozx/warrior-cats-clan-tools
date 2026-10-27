local d=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local M=dofile(d..'../Scripts/registry.lua');local json=dofile(d..'../Scripts/json.lua')
local files={['root/../mods.txt']='Other : 1\r\nClanLoader : 1\r\nClanTools : 1\r\n',['root/registry.json']=json.encode({schema=1,mods={{id='ClanLoader',name='Loader',version='1'},{id='ClanTools',name='Tools',version='1'}}})}
local a=M.new({root='root/',read=function(p)return files[p]end,write=function(p,s)files[p]=s end})
assert(not a.list()[2].restart);a.toggle('ClanTools');local m=a.list()[2];assert(m.restart and not m.enabled and m.atStartup)
assert(M.states(files['root/../mods.txt']).other);a.toggle('ClanTools');assert(not a.list()[2].restart)
assert(not pcall(a.toggle,'ClanLoader'));assert(not pcall(a.toggle,'unknown'));assert(not pcall(M.states,'X : 1\nX : 0\n'))
assert(not pcall(M.update,'','../X',true))
assert(not pcall(M.states,'Example : 1\nexample : 0\n'))
local canonical=M.update('clantools : 0\nOther : 1\n','ClanTools',true)
assert(M.states(canonical).clantools and M.states(canonical).other)
assert(not canonical:find('clantools :',1,true))

local function fixture(failure,dependent)
 local list='root/../mods.txt';local marker='root/../ClanTools/enabled.txt'
 local mods={{id='ClanLoader',name='Loader',version='1',dependencies={}},{id='ClanTools',name='Tools',version='1',dependencies={'clanloader'}}}
 if dependent then mods[#mods+1]={id='Dependent',name='Dependent',version='1',dependencies={'clantools'}}end
 local f={[list]='ClanLoader : 1\nclantools : 0\nDependent : 0\n',[marker]='marker bytes',['root/registry.json']=json.encode({schema=1,mods=mods})}
 if dependent then f['root/../Dependent/enabled.txt']=''end
 local once=true
 local api=M.new({root='root/',read=function(p)return f[p]end,write=function(p,s)
  if once and p==list and failure=='write' then once=false;f[p]='partial';error('injected write failure')end
  f[p]=s
 end,remove=function(p)
  if failure=='remove' then error('injected marker removal failure')end
  if failure=='noop' then return end
  f[p]=nil
  if failure=='after-remove' then error('injected failure after marker removal')end
 end})
 return api,f,list,marker
end
local b,f,list,marker=fixture()
assert(b.list()[2].enabled and b.list()[2].atStartup and not b.list()[2].restart)
b.toggle('ClanTools')
assert(f[marker]==nil and f[marker..'.clanloader-backup']=='marker bytes')
assert(not M.states(f[list]).clantools and b.list()[2].restart and b.list()[2].atStartup)
b.toggle('ClanTools');assert(M.states(f[list]).clantools and f[marker]==nil and not b.list()[2].restart)
for _,failure in ipairs({'write','remove','after-remove','noop'})do
 local c,g,lp,mp=fixture(failure);local original=g[lp]
 assert(not pcall(c.toggle,'ClanTools'))
 assert(g[lp]==original and g[mp]=='marker bytes',failure..' did not restore activation')
 assert(c.list()[2].enabled and not c.list()[2].restart)
end
local c,g,lp,mp=fixture(nil,true);local original=g[lp]
assert(not pcall(c.toggle,'ClanTools'));assert(g[lp]==original and g[mp]=='marker bytes')
c.toggle('Dependent');c.toggle('ClanTools');assert(not c.list()[2].enabled and not c.list()[3].enabled)
print('PASS manager restart state, marker activation, transactional rollback, dependencies and ID casing')
