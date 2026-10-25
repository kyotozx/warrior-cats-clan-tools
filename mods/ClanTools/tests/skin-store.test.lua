local d=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local M=dofile(d..'../Scripts/skin_store.lua');local json=dofile(d..'../Scripts/json.lua')
local files={};local fail=false
local ctx={root='memory/',read=function(p)return files[p]end,write=function(p,s)if fail and p=='memory/skins.json'then error('disk full')end;files[p]=s end}
local zero=string.rep('0 ',23)..'0';local other=string.rep('1 ',23)..'1'
local s=M.new(ctx);local id=s.save('  My cat  ',zero);assert(id==1 and s.get(id).label=='My cat')
s.favorite(id);s.rename(id,'Moon');assert(s.get(id).favorite)
local detached=s.get(id);detached.label='changed';assert(s.get(id).label=='Moon')
local exported=s.export(id);files['memory/skin-import.json']=files[exported];assert(s.import()==2)
local e=json.decode(files[exported]);e.progression={xp=999};files['memory/skin-import.json']=json.encode(e);assert(not pcall(s.import))
e.progression=nil;e.gameBuild='other';files['memory/skin-import.json']=json.encode(e);assert(not pcall(s.import))
assert(not pcall(s.save,'bad',zero..' 1'));assert(not pcall(s.save,string.rep('x',41),zero))
local before=files['memory/skins.json'];fail=true;assert(not pcall(s.rename,id,'Lost'));fail=false;assert(files['memory/skins.json']==before and s.get(id).label=='Moon')
s.delete(2);assert(#s.list()==1 and files['memory/skins.json.previous.txt'])
assert(M.new(ctx).get(1).label=='Moon')
local function nums(v)local a={};for n in v:gmatch('%d+')do a[#a+1]=tonumber(n)end;return a end
for part,range in pairs({Shape={1,15},Coat={16,20},Eyes={21,22}})do
 local a=nums(M.merge(zero,other,part));for i=1,24 do local yes=i>=range[1]and i<=range[2]or(part=='Coat'and i>=23);assert(a[i]==(yes and 1 or 0))end
end
files['memory/skins.json']='broken';local broken=M.new(ctx);local rows,why=broken.list();assert(#rows==0 and why);assert(not pcall(broken.save,'Keep',zero));assert(files['memory/skins.json']=='broken')
print('PASS skin persistence, identity isolation, partial copies, strict import and failure preservation')
