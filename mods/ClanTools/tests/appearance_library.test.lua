local M=dofile('mods/ClanTools/Scripts/appearance_library.lua')
local json=dofile('mods/ClanTools/Scripts/json.lua')
local function vector(n)local a={};for i=1,24 do a[i]=n end;a[23]=1;a[24]=1;return table.concat(a,' ')end
local original,edited=vector(2),vector(4)
local function fixture(existing)
 local f={files={},calls={},editable=true,target={role=77,name='Cloudflower'},snapshot={profile='A',slot=0,chapter='Chapter00'}}
 if existing then f.files['memory/appearance-presets.json']=existing end
 f.ctx={root='memory/',read=function(p)return f.files[p]end,write=function(p,s)if f.writeFailure then error('disk full')end;f.files[p]=s end,
  ensureEditable=function()return f.editable end,target=function()return f.target end,snapshot=function()return f.snapshot end,
  native=function(command)
   f.calls[#f.calls+1]=command
   if f.reject==command then return nil,'native refusal'end
   return {action=command=='ORIGINAL_READ'and'COSMETICS '..original or command=='PREVIEW_READ'and'COSMETICS '..edited or command}
  end}
 f.api=M.new(f.ctx);return f
end
do
 assert(M.values(edited)==edited);assert(not M.values(edited..' 9'));assert(not M.values(edited:gsub('4','-1',1)))
 assert(not M.values(edited:gsub('4','1e2',1)));assert(not M.values(edited:gsub('4','256',1)))
 local f=fixture();assert(f.api.begin());local first=f.files['memory/appearance-presets.json']
 assert(f.api.begin()and f.files['memory/appearance-presets.json']==first)
 assert(f.api.savePreset());local list,index=f.api.presets();assert(#list==1 and index==1 and list[1].label=='Cloudflower 1')
 f.target={role=79,name='Other cat'};assert(f.api.loadPreset());assert(f.calls[#f.calls]=='PREVIEW_LOAD '..edited)
 assert(f.api.begin());assert(f.api.restoreOriginal());assert(f.calls[#f.calls]=='PREVIEW_LOAD '..original)
 for _,c in ipairs(f.calls)do assert(c~='APPLY','Presets never commit a save')end
 local again=fixture(f.files['memory/appearance-presets.json']);assert(#again.api.presets()==1)
 print('PASS strict cosmetic schema, original once-per-cat, cross-cat copy and persistent library without save commits')
end
do
 local f=fixture();assert(f.api.compare()and f.api.comparisonActive());assert(f.api.randomize())
 assert(f.calls[2]=='COMPARE 0'and f.calls[3]=='RANDOMIZE'and not f.api.comparisonActive())
 assert(f.api.compare());f.reject='COMPARE 0';assert(not f.api.randomize());assert(f.calls[#f.calls]=='COMPARE 0')
 f.reject=nil;assert(f.api.reset()and not f.api.comparisonActive())
 f.editable=false;local count=#f.calls;assert(not f.api.randomize());assert(#f.calls==count)
 print('PASS comparison exits before mutations, failed restore blocks randomize, context refusal sends no native command')
end
do
 local f=fixture();assert(f.api.savePreset('First'));assert(f.api.savePreset('Second'))
 assert(f.api.selectPreset(-1));local list,index=f.api.presets();assert(index==1 and #list==2)
 assert(f.api.deletePreset());list,index=f.api.presets();assert(#list==1 and index==1 and list[1].label=='Second 2')
 assert(f.files['memory/appearance-presets.json.previous.txt'])
 local raw=f.files['memory/appearance-presets.json'];f.writeFailure=true;assert(not f.api.savePreset());assert(#f.api.presets()==1)
 assert(f.files['memory/appearance-presets.json']==raw)
 local corrupt=fixture('{broken');assert(not corrupt.api.savePreset());assert(corrupt.files['memory/appearance-presets.json']=='{broken')
 print('PASS preset navigation/delete backup, failed persistence rollback and corrupt library preservation')
end
do
 local f=fixture();for _=1,32 do assert(f.api.savePreset())end
 local before=#f.calls;assert(not f.api.savePreset());assert(#f.calls==before)
 assert(f.api.selectPreset(1));local _,i=f.api.presets();assert(i==1)
 print('PASS bounded 32-preset library and wrap navigation')
end
do
 local f=fixture();assert(f.api.savePreset(string.rep('猫',80)))
 local list=f.api.presets();assert(utf8.len(list[1].label)==72 and list[1].label==string.rep('猫',70)..' 1')
 print('PASS preset label truncation preserves UTF-8 character boundaries')
end
