local d=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local M=dofile(d..'../Scripts/registry.lua');local json=dofile(d..'../Scripts/json.lua')
local files={['root/../mods.txt']='Other : 1\r\nClanLoader : 1\r\nClanTools : 1\r\n',['root/registry.json']=json.encode({schema=1,mods={{id='ClanLoader',name='Loader',version='1'},{id='ClanTools',name='Tools',version='1'}}})}
local a=M.new({root='root/',read=function(p)return files[p]end,write=function(p,s)files[p]=s end})
assert(not a.list()[2].restart);a.toggle('ClanTools');local m=a.list()[2];assert(m.restart and not m.enabled and m.atStartup)
assert(M.states(files['root/../mods.txt']).Other);a.toggle('ClanTools');assert(not a.list()[2].restart)
assert(not pcall(a.toggle,'ClanLoader'));assert(not pcall(a.toggle,'unknown'));assert(not pcall(M.states,'X : 1\nX : 0\n'))
assert(not pcall(M.update,'','../X',true));print('PASS manager restart state, preservation and invalid requests')
