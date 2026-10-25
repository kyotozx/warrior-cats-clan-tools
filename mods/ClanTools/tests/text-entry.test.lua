local M=dofile('mods/ClanTools/Scripts/text_entry.lua');local n=0
local function test(name,fn)fn();n=n+1;print('PASS '..name)end
test('typing and UTF8 deletion preserve complete characters',function()local m=M.new({value='Café'});m.delete();assert(m.text=='Caf');m.key('E',true);assert(m.text=='CafE')end)
test('limit rejection does not lose existing text',function()local m=M.new({value='cat',maxLength=3});assert(not m.insert('s'));assert(m.text=='cat')end)
test('cancel does not accept a draft',function()local saved=false;local m=M.new({accept=function()saved=true end});m.key('A');m.cancel();assert(m.closed and not saved);assert(not m.insert('b'))end)
test('validation and save failure keep the dialog editable',function()local m=M.new({validate=function(v)if v==''then return nil,'Empty'end;return v end,accept=function()return false,'Disk error'end});assert(not m.confirm());assert(m.error=='Empty');m.key('A');assert(not m.confirm());assert(not m.closed and m.error=='Disk error')end)
test('keyboard/controller insertion uses one shared draft',function()local result;local m=M.new({accept=function(v)result=v end});m.activate(1);m.key('A');m.insert('-');m.key('B',true);assert(m.confirm());assert(result=='qa-B');assert(not m.confirm())end)
test('directional navigation wraps safely',function()local m=M.new();m.navigate('left');assert(m.index==#m.keys);m.navigate('right');assert(m.index==1);m.navigate('up');assert(m.index>=1 and m.index<=#m.keys)end)
test('boolean validators preserve text and reject false',function()local saved;local m=M.new({value='Home',validate=function()return true end,accept=function(v)saved=v end});assert(m.confirm()and saved=='Home');local b=M.new({value='Home',validate=function()return false,'Duplicate'end});assert(not b.confirm()and b.error=='Duplicate')end)
print(n..' text entry tests passed')
