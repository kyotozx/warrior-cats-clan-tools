-- Run outside the game using a separate copied DLL directory.
-- Validates request parsing/build rejection before any native object access.
local bin=assert(arg[1],'Provide isolated test DLL directory ending in /')
local probe=assert(package.loadlib(bin..'admin-heal.dll','ClanToolsHeal_probe'))
local apply=assert(package.loadlib(bin..'admin-heal.dll','ClanToolsHeal_apply'))
local function run(text,expected,fn)
    local f=assert(io.open(bin..'admin-heal-request.txt','wb'));f:write(text);f:close()
    fn()
    f=assert(io.open(bin..'admin-heal-status.txt','rb'));local s=f:read('*a');f:close()
    assert(s:find('status='..expected,1,true),s)
end
run('', 'Invalid request',probe)
run('1 1 1 1 trailing', 'Invalid request',probe)
run('0 1 1 1', 'Invalid request',probe)
run('1 1 1 1', 'Unsupported game build',probe)
run('2 ffffffffffffffff ffffffffffffffff ffffffffffffffff','Unsupported game build',apply)
print('5 native heal guard tests passed; no game process accessed.')
