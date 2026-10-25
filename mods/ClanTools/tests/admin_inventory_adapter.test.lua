local M=dofile('mods/ClanTools/Scripts/admin_inventory.lua')
local function object(address)return{GetAddress=function()return address end}end
local class,manager,owner,component=object(30),object(40),object(20),object(10)
owner.InventoryComponent=component;function component:GetClass()return class end;function component:GetOwner()return owner end
StaticFindObject=function(path)assert(path=='/Script/Wrc.WrcInventoryComponent');return class end
FindFirstOf=function(name)assert(name=='WrcSaveManager');return manager end
local oldOpen,oldLoad=io.open,package.loadlib;local files={};local requests={};local current=4
io.open=function(path,mode)
 if mode=='wb'then return{write=function(self,text)files[path]=text;return self end,close=function()return true end}end
 assert(files[path],path);return{read=function()return files[path]end,close=function()return true end}
end
package.loadlib=function(path,symbol)
 assert(path=='memory/admin-inventory.dll'and symbol=='ClanInventory_run')
 return function()
  local fields={};for value in files['memory/admin-inventory-request.txt']:gmatch('%S+')do fields[#fields+1]=value end
  requests[#requests+1]=fields;assert(#fields==9 and fields[3]=='a'and fields[4]=='14'and fields[5]=='1e'and fields[6]=='28'and fields[7]=='1')
  local before=current;local command=fields[2];if command=='ADD'then assert(tonumber(fields[9])==current);current=current+tonumber(fields[8])end
  files['memory/admin-inventory-status.txt']=string.format('nonce=%s\nstatus=%s\ncurrent=%d\nafter=%d\nallowed=1\n',fields[1],command=='PROBE'and'READY'or'APPLIED',before,current)
 end
end
local ok,why=pcall(function()
 local adapter=M.nativeAdapter({valid=function(o)return type(o)=='table'and not o.dead end},'memory/')
 local s={offline=true,phase=4,pc={PlayerState=owner}};local identity=adapter.identity(s)
 local p=adapter.probe(s,1,3,identity);assert(p.current==4 and p.after==4)
 local r=adapter.add(s,1,3,4,identity);assert(r.after==7 and #requests==2 and requests[2][1]=='2')
 local old=owner;owner=object(21);owner.InventoryComponent=component;s.pc.PlayerState=owner
 assert(not pcall(adapter.add,s,1,1,7,identity));assert(#requests==2);owner=old
 s.offline=false;assert(not pcall(adapter.probe,s,1,1,identity));assert(#requests==2)
end)
io.open,package.loadlib=oldOpen,oldLoad
assert(ok,why)
print('PASS native adapter exact owner/class/manager mailbox protocol, nonce, expected count and identity/offline guards')
