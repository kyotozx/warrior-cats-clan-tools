-- Isolated outside-game process only; do not point this at the runtime bin.
local bin=assert(arg[1],'Pass isolated DLL test directory ending in /')
local native=assert(package.loadlib(bin..'follower-appearance.dll','ClanFollowers_appearance'))
local function check(input,status)
    local f=assert(io.open(bin..'follower-request.txt','w'));f:write(input);f:close();native()
    f=assert(io.open(bin..'follower-status.txt','r'));local text=f:read('*a');f:close()
    assert(text:find('status='..status,1,true),text)
end
check('','Invalid request')
check('1 1 1 1 1 0 1','Invalid request')
check('1 1 1 1 1 7 1 extra','Invalid request')
check('1 1 1 1 1 7 1','Unsupported game build')
check('2 ffffffffffffffff ffffffffffffffff ffffffffffffffff ffffffffffffffff 7 1','Unsupported game build')
print('5 native follower guard tests passed; no game process accessed.')
