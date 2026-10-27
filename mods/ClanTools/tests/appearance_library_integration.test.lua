local M=dofile('mods/ClanTools/Scripts/appearance.lua')
local function fixture()
 local f={files={},calls={},queue={},commits=0,s={profile='profile-A',slot=0,chapter='Chapter00',gs=17,clan=4,offline=true},cat={role=77,clan=4,living=true,name='Cloudflower'}}
 local a={};for i=1,24 do a[i]=1 end;local cosmetics=table.concat(a,' ')
 f.ctx={characterKey=function(s)return s.profile..'_'..s.slot..'_'..(s.generation or'generation1')end,root='memory/',read=function(p)return f.files[p]end,write=function(p,s)f.files[p]=s end,
  snapshot=function()return f.s end,getCats=function()return{f.cat}end,backupSave=function()return true end,
  native=function(cmd)f.calls[#f.calls+1]=cmd;if f.fail==cmd then return nil,'Rejected '..cmd end;return{action=(cmd=='ORIGINAL_READ'or cmd=='PREVIEW_READ')and'COSMETICS '..cosmetics or cmd}end,
  openAppearanceEditor=function(_,callbacks)f.callbacks=callbacks;return'editor'end,
  closeAppearanceEditor=function()return true end,defer=function(fn)f.queue[#f.queue+1]=fn end,
  catNames={prepare=function(s,c,value)return{name=value}end,commit=function(r)f.commits=f.commits+1;f.savedName=r.name end,generate=function()return'Sunleaf'end}}
 f.mod=M.new(f.ctx)
 function f:open()assert(self.mod:begin(77));assert(self.callbacks.ready(4096));assert(self.callbacks.initializeScreen(8192))end
 function f:close()self.callbacks.closed();for _=1,2 do local q=self.queue;self.queue={};for _,fn in ipairs(q)do fn()end end end
 return f
end
do
 local f=fixture();f:open();assert(f.mod:setName('Free Name'));assert(f.callbacks.getName()=='Free Name')
 assert(f.callbacks.compare());assert(f.callbacks.comparisonActive());assert(f.callbacks.apply())
 local n=#f.calls;assert(f.calls[n-2]=='COMPARE 0'and f.calls[n-1]=='CAPTURE'and f.calls[n]=='APPLY')
 assert(f.commits==1 and f.savedName=='Free Name');f:close();assert(f.mod.phase=='idle')
 print('PASS integrated Apply exits comparison before capture and persists staged name only after native commit')
end
do
 local f=fixture();f:open();assert(f.callbacks.generateName());assert(f.callbacks.getName()=='Sunleaf');assert(f.callbacks.compare());f.fail='COMPARE 0'
 assert(not f.callbacks.apply());assert(f.commits==0 and f.mod.phase=='editing'and f.calls[#f.calls]=='COMPARE 0')
 f.fail='RESET';assert(not f.callbacks.reset());assert(f.callbacks.getName()=='Sunleaf')
 f.fail=nil;assert(f.callbacks.reset());assert(f.callbacks.getName()=='Cloudflower'and not f.callbacks.comparisonActive())
 assert(f.callbacks.cancel());f:close();assert(f.commits==0)
 print('PASS failed comparison restore blocks Apply; successful Reset clears both staged name and cosmetic comparison')
end
do
 local f=fixture();f:open();assert(f.mod:setName('Canceled'));assert(f.callbacks.randomize());assert(f.callbacks.cancel());f:close()
 assert(f.commits==0);local old=f.callbacks;f:open();local n=#f.calls;old.randomize();assert(#f.calls==n,'Old footer callbacks cannot mutate new preview')
 f.s.profile='profile-B';assert(not f.callbacks.randomize());assert(#f.calls==n)
 assert(not f.callbacks.apply());assert(f.calls[#f.calls]=='CANCEL'and f.commits==0)
 print('PASS canceled rename stays unsaved; stale footer epoch and profile change cannot randomize or apply')
end
