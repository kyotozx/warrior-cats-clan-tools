local M=dofile('mods/ClanTools/Scripts/appearance.lua')
local tests=0
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local function fixture()
    local f={calls={},queue={},s={profile='profile-A',slot=0,chapter='Chapter00',gs=17,clan=4,offline=true},
      cats={{role=77,clan=4,living=true,name='Darkfeather'},{role=78,clan=4,living=false,name='Dead'},
      {role=45,clan=1,living=true,name='Other clan'}},backup=true}
    f.ctx={snapshot=function() return f.s end,getCats=function() return f.cats end,
      backupSave=function() return f.backup end,
      native=function(cmd) f.calls[#f.calls+1]=cmd;if f.fail==cmd then return nil,'Rejected '..cmd end;return {action=cmd=='APPLY'and f.applyResult or cmd} end,
      openAppearanceEditor=function(cat,callbacks) f.callbacks=callbacks;return 'editor' end,
      closeAppearanceEditor=function(handle) f.closedHandle=handle;return true end,
      defer=function(fn) f.queue[#f.queue+1]=fn end}
    f.mod=M.new(f.ctx)
    function f:tick() local q=self.queue;self.queue={};for _,fn in ipairs(q) do fn() end end
    return f
end
local function test(name,fn) fn();tests=tests+1;print('PASS '..name) end
test('lists only living clan cats',function() local f=fixture();eq(#f.mod:list(),1);eq(f.mod:list()[1].role,77) end)
test('does not begin dead or foreign cats',function() local f=fixture();assert(not f.mod:begin(78));assert(not f.mod:begin(45));eq(#f.calls,0) end)
test('backup is mandatory before hook installation',function() local f=fixture();f.backup=false;assert(not f.mod:begin(77));eq(#f.calls,0) end)
test('cancel never sends APPLY and keeps guard until close settles',function()
    local f=fixture();assert(f.mod:begin(77));assert(f.callbacks.ready(4096));assert(f.mod:cancel())
    eq(f.calls[#f.calls],'CANCEL');eq(f.mod.phase,'closing');f.callbacks.closed();eq(f.mod.phase,'finishing')
    f:tick();eq(f.mod.phase,'finishing');f:tick();eq(f.mod.phase,'idle');eq(f.calls[#f.calls],'END')
    for _,c in ipairs(f.calls) do assert(c~='APPLY') end
end)
test('apply captures then commits then waits for actual editor close',function()
    local f=fixture();assert(f.mod:begin(77));assert(f.callbacks.ready(4096));assert(f.callbacks.apply())
    eq(f.calls[#f.calls-1],'CAPTURE');eq(f.calls[#f.calls],'APPLY');eq(f.mod.phase,'applied');eq(f.closedHandle,'editor')
    f.callbacks.closed();f:tick();f:tick();eq(f.mod.phase,'idle')
end)
test('profile switch refuses Apply and cancels guarded transaction',function()
    local f=fixture();assert(f.mod:begin(77));assert(f.callbacks.ready(4096));f.s.profile='profile-B'
    assert(not f.mod:apply());eq(f.calls[#f.calls],'CANCEL');eq(f.mod.phase,'closing')
end)
test('death while editing refuses Apply',function()
    local f=fixture();assert(f.mod:begin(77));assert(f.callbacks.ready(4096));f.cats[1].living=false
    assert(not f.mod:apply());eq(f.calls[#f.calls],'CANCEL')
end)
test('native guard failure cannot open editor',function()
    local f=fixture();f.fail='BEGIN 77 4';assert(not f.mod:begin(77));eq(f.callbacks,nil);eq(f.mod.phase,'idle')
end)
test('native capture failure never commits',function()
    local f=fixture();assert(f.mod:begin(77));assert(f.callbacks.ready(4096));f.fail='CAPTURE';assert(not f.mod:apply())
    eq(f.calls[#f.calls],'CAPTURE');eq(f.mod.phase,'editing')
end)
test('reset only resets preview',function()
    local f=fixture();assert(f.mod:begin(77));assert(f.callbacks.ready(4096));assert(f.mod:reset());eq(f.calls[#f.calls],'RESET');eq(f.mod.phase,'editing')
end)
test('failed END retains guarded state and offers retry',function()
    local f=fixture();assert(f.mod:begin(77));assert(f.callbacks.ready(4096));f.fail='END';f.callbacks.closed();f:tick();f:tick()
    eq(f.mod.phase,'guarded_error');f.fail=nil;assert(f.mod:retryCleanup());eq(f.mod.phase,'idle')
end)
test('stale callbacks cannot close a subsequent editor',function()
    local f=fixture();assert(f.mod:begin(77));local old=f.callbacks;old.closed();f:tick();f:tick()
    assert(f.mod:begin(77));old.closed();eq(f.mod.phase,'opening')
end)
test('name-only Apply saves alias without native world role refresh',function()
    local f=fixture();local files={};local logs={}
    f.ctx.root='';f.ctx.json=dofile('mods/ClanTools/Scripts/json.lua')
    f.ctx.read=function(path)return files[path]end
    f.ctx.write=function(path,value)files[path]=value end
    f.ctx.catNames=dofile('mods/ClanTools/Scripts/cat_names.lua').new(f.ctx)
    f.ctx.refreshCat=function()error('Unchanged appearance must not refresh NPCs')end
    f.ctx.log=function(line)logs[#logs+1]=line end
    f.applyResult='UNCHANGED'
    assert(f.mod:begin(77));assert(f.callbacks.ready(4096))
    assert(f.mod:setName('Moonlight'));assert(f.callbacks.apply())
    eq(f.ctx.catNames.get(f.s,77,'Original'),'Moonlight')
    assert(files['state/cat-names-character-v2-profile-A_0.json'])
    assert(not table.concat(logs,'\n'):find('refresh world appearance',1,true))
    f.callbacks.closed();f:tick();f:tick();eq(f.mod.phase,'idle')
    eq(logs[#logs],'Appearance apply: transaction closed')
end)
test('cosmetic Apply still refreshes the changed cat',function()
    local f=fixture();local refreshed
    f.ctx.refreshCat=function(cat)refreshed=cat.role end
    f.applyResult='APPLIED_QUEUED'
    assert(f.mod:begin(77));assert(f.callbacks.ready(4096));assert(f.callbacks.apply())
    eq(refreshed,77)
end)
test('world transition with reused game-state identity blocks Apply',function()
    local f=fixture();f.s.worldId='World-A'
    assert(f.mod:begin(77));assert(f.callbacks.ready(4096));f.s.worldId='World-B'
    assert(not f.callbacks.apply());eq(f.calls[#f.calls],'CANCEL')
end)
print(tests..' appearance transaction tests passed')
