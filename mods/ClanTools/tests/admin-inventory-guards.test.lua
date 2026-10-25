local bin=assert(arg[1]);local run=assert(package.loadlib(bin..'admin-inventory.dll','ClanInventory_run'))
local n=0
local function check(request,expected)
 local f=assert(io.open(bin..'admin-inventory-request.txt','wb'));f:write(request);f:close();run()
 f=assert(io.open(bin..'admin-inventory-status.txt','rb'));local raw=f:read('*a');f:close()
 assert(raw:find('status='..expected,1,true),raw);n=n+1
end
check('','Invalid request')
check('1 ADD 1 1 1 1 0 1 0','Invalid request')
check('1 ADD 1 1 1 1 9999 1 0','Invalid request')
check('1 ADD 1 1 1 1 1 -1 0','Invalid request')
check('1 ADD 1 1 1 1 1 1000 0','Invalid request')
check('1 ADD 1 1 1 1 1 1 -1','Invalid request')
check('1 ADD 1 1 1 1 1 1 0 trailing','Invalid request')
check('1 ADD ffffffffffffffff ffffffffffffffff 1 1 1 1 0','Unsupported game build')
check('1 PROBE 1 1 1 1 1 1 0','Unsupported game build')
print(n..' native inventory guards passed; no game process accessed')
