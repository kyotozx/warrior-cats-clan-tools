local bin=assert(arg[1]);local run=assert(package.loadlib(bin..'workshop.dll','ClanWorkshop_run'));local n=0
local function check(request,expected)
 local f=assert(io.open(bin..'workshop-request.txt','wb'));f:write(request);f:close();run()
 f=assert(io.open(bin..'workshop-status.txt','rb'));local raw=f:read('*a');f:close()
 assert(raw:find('status='..expected,1,true),raw);n=n+1
end
check('','Invalid request')
check('1 ADD 1 1 1 1 1 1 1 1 0','Invalid request')
check('1 CRAFT 1 1 1 1 1 0 1 1 0','Invalid request')
check('1 CRAFT 1 1 1 1 1 190 1 1 0','Invalid request')
check('1 CRAFT 1 1 1 1 1 1 -1 1 0','Invalid request')
check('1 CRAFT 1 1 1 1 1 1 100 1 0','Invalid request')
check('1 CRAFT 1 1 1 1 1 1 1 2 0','Invalid request')
check('1 CRAFT 1 1 1 1 1 1 1 1 0 trailing','Invalid request')
check('1 CRAFT ffffffffffffffff 1 1 1 1 1 1 1 0','Unsupported game build')
check('1 PROBE 1 1 1 1 1 1 1 1 0','Unsupported game build')
print(n..' native workshop guards passed; no game process accessed')
