local directory=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local Module=dofile(directory..'../Scripts/settings_extensions.lua')
local function clone(t)local o={};for k,v in pairs(t)do o[k]=type(v)=='table'and clone(v)or v end;return o end
local video={limit=60,vsync=true,smooth=true,fixed=false};local saved=clone(video);local preferences;local writes=0;local wrong=false;local prefsFail=false
local count,seconds=100,1
local sharedVSync=true;local sharedFailure=false
local rows={{command=65,key='E',raw='0,Player_Interact,E,1.000000.1'},{command=70,key='LeftShift',raw='0,Player_Run,LeftShift,1.000000.1'},{command=89,key='Enter',raw='-'}}
local indexes={E=10,F=11,LeftShift=12,Enter=13,G=14};local names={};for k,v in pairs(indexes)do names[v]=k end
local controlsFail=false;local requests=0;local custom=false
local ctx={load_preferences=function()return preferences end,save_preferences=function(v)if prefsFail then error('disk full')end;preferences=clone(v)end,
 video={identity=1,get=function()return clone(video)end,apply=function(v)video=clone(v)end,save=function()writes=writes+1;saved=clone(video)end,persisted=function()local v=clone(saved);if wrong then v.limit=59 end;return v end,
 shared_vsync=function(v)if v~=nil then if sharedFailure then sharedFailure=false;error('Shared VSync save failed')end;sharedVSync=v end;return sharedVSync end},
 frame_sample=function()return count,seconds end,key_name=function(i)return names[i]end,
 save_controls=function()if controlsFail then controlsFail=false;error('save failed')end;return true end,
 key_native=function(action,command,value)
  if action=='LIST'then local out={'1 OK','M '..(custom and'1'or'0')};for _,r in ipairs(rows)do out[#out+1]=string.format('B %d 0 %d 0 1 %d %s',r.command,indexes[r.key],r.command==89 and 0 or 1,r.raw)end;return table.concat(out,'\n')end
  if action=='MODE'then custom=command==1;return'1 OK'end
  requests=requests+1;for _,r in ipairs(rows)do if r.command==command then
   if action=='SET'then custom=true;r.key=value;r.raw='0,Player_Interact,'..value
   else r.raw=value;r.key=value=='-'and'E'or value:match('^[^,]+,[^,]+,([^,]+)')end
  end end;return'1 OK\n'
 end}
local api=Module.new(ctx)
assert(api.set_fps(144));assert(video.limit==144 and video.smooth==false and video.vsync==true);assert(saved.limit==144 and preferences.custom_limit)
assert(api.status().vsync_note);assert(api.set_fps('unlimited'));assert(video.limit==0 and video.vsync)
assert(api.set_vsync(false));assert(not video.vsync and not sharedVSync);assert(api.restore_video());assert(video.limit==60 and video.smooth and video.vsync and sharedVSync)
print('PASS native video apply/save/readback, Unlimited, VSync preservation and original restore')
local before=writes;assert(not api.set_fps(-5));assert(not api.set_fps(0/0));assert(not api.set_fps(2001));assert(writes==before)
video.fixed=true;assert(not api.set_fps(120));assert(writes==before);video.fixed=false
print('PASS unsafe/invalid limits and fixed engine timestep rejected before mutation')
wrong=true;assert(not api.set_fps(144));assert(video.limit==60 and video.smooth);wrong=false
prefsFail=true;assert(not api.set_fps(144));assert(video.limit==60 and video.smooth);prefsFail=false
print('PASS persistent readback and preference-write failures restore original video state')
assert(api.set_counter(true));assert(api.tick({}));count=160;seconds=2;assert(api.tick({}));assert(api.status().fps==60)
count=200;seconds=0.1;assert(api.tick({}));assert(api.status().fps==nil);assert(api.set_counter(false));assert(api.status().fps==nil)
print('PASS FPS counter measures actual frame-count/time deltas and resets across world changes')
assert(api.set_fps(120));local restart=Module.new(ctx);video.smooth=true;assert(restart.tick(nil));assert(not video.smooth and video.limit==120)
assert(restart.restore_video());print('PASS persisted custom-limit preference reapplies smoothing override and keeps original restore')
local list=api.bindings();assert(#list==3 and list[1].editable and not list[3].editable)
assert(api.rebind(65,'F'));assert(rows[1].key=='F');assert(api.reset_binding(65));assert(rows[1].key=='E'and rows[1].raw=='-')
print('PASS real command-binding adapter changes/readbacks/saves and per-action reset')
before=requests;assert(not api.rebind(65,'LeftShift'));assert(not api.rebind(65,'Escape'));assert(not api.rebind(89,'F'));assert(not api.rebind(65,'FakeKey'));assert(requests==before)
print('PASS collisions, menu keys, unsupported actions and unknown keys rejected before native mutation')
controlsFail=true;assert(not api.rebind(65,'G'));assert(rows[1].key=='E'and rows[1].raw=='-')
assert(api.rebind(65,'G'));assert(rows[1].key=='G');assert(api.shutdown())
print('PASS failed game save rolls back key binding; explicit retry succeeds')
assert(api.set_custom_controls(false));assert(not custom);controlsFail=true;assert(not api.set_custom_controls(true));assert(not custom)
assert(api.rebind(65,'F'));assert(custom);assert(api.set_custom_controls(false));assert(not custom)
print('PASS explicit native custom-controls mode, enabling on rebind, save failure restores mode')
sharedFailure=true;assert(not api.set_vsync(false));assert(video.vsync and saved.vsync and sharedVSync)
prefsFail=true;assert(not api.set_vsync(false));assert(video.vsync and sharedVSync);prefsFail=false
print('PASS VSync persists to native shared settings; failures roll back both stores')
