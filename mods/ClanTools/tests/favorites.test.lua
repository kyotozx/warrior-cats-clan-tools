local module=dofile('mods/ClanTools/Scripts/favorites.lua');local json=dofile('mods/ClanTools/Scripts/json.lua')
local files={};local calls=0;local allowed=true
local ctx={root='',json=json,read=function(p)return files[p]end,write=function(p,s)files[p]=s end}
local registry={heal={label='Heal',available=function()return allowed,'Unavailable'end,run=function()calls=calls+1;return true end},fly={label='Fly',run=function()return true end}}
local a=module.new(ctx,registry);assert(#a.list()==0);a.toggle('heal');assert(a.has('heal'));assert(a.run('heal'));assert(calls==1)
allowed=false;assert(not pcall(a.run,'heal')and calls==1);allowed=true
local b=module.new(ctx,registry);assert(b.has('heal'));b.toggle('heal');assert(#b.list()==0);assert(not pcall(b.toggle,'unregistered'))
files['state/favorites.json']='{"version":1,"actions":["unknown","fly","fly"]}'
local c=module.new(ctx,registry);assert(#c.list()==1 and c.list()[1].id=='fly');assert(#c.list(true)==2)
ctx.write=function()error('Disk full')end;assert(not pcall(c.toggle,'heal'));assert(not c.has('heal'))
print('PASS favorites persistence, deduplication, registered actions, current eligibility and write failure')
