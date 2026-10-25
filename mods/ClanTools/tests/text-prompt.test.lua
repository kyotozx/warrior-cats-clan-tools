-- Exercise the actual dialog's raw/semantic event ordering with engine UI mocks.
local original=dofile;local queue={};local saved
local function object()
 local t={Font={Size=20},ColorAndOpacity={}}
 return setmetatable(t,{__index=function(self,k)
  if k=='Slot'then local s=object();rawset(self,k,s);return s end
  if k=='GetAddress'then return function()return 1 end end
  if k=='IsInputKeyDown'then return function()return false end end
  if k=='AddChild'or k=='GetChildAt'then return function()return object()end end
  return function()end
 end})
end
local skin={find=function()return object()end,cloneImage=function()end,createButton=function()return object(),object()end}
dofile=function(p)if p:match('native_skin.lua$')then return skin end;return original(p)end
local lib={SetFocusToGameViewport=function()end,Create=function()local w=object();w.WidgetTree={RootWidget=object()};return w end}
StaticFindObject=function(path)
 if path:find('WidgetBlueprintLibrary',1,true)then return lib end
 if path:find('WidgetLayoutLibrary',1,true)then return{GetViewportSize=function()return{X=1920,Y=1080}end,GetViewportScale=function()return 1 end}end
 return object()
end
StaticConstructObject=object;LoadAsset=object;FText=function(v)return v end;FName=FText
RegisterHook=function()return 1,2 end;UnregisterHook=function()end
local M=dofile('mods/ClanTools/Scripts/text_prompt.lua');dofile=original
local function flush()local q=queue;queue={};for _,fn in ipairs(q)do fn()end end
local pause={WidgetTree={RootWidget=object()},mcGuiFooter={WidgetTree={RootWidget=object()}},mcGuiPanelGeneral={WidgetTree={RootWidget=object()}}}
local prompt=M.new({valid=function(v)return type(v)=='table'end,defer=function(fn)queue[#queue+1]=fn end,snapshot=function()return{gameState=object(),pc=object()}end})
local function open()saved=nil;prompt.open({value='Name',pause=pause,accept=function(v)saved=v;return true end})end
open();prompt.command(26,0);prompt.key('Enter');flush();assert(saved=='Name'and not prompt.active());print('PASS semantic Confirm before raw Enter does not insert the selected letter')
open();prompt.key('X');prompt.key('X');flush();prompt.key('Enter');prompt.command(26,0);flush();assert(saved=='Namex');print('PASS duplicate screen key events insert one character')
open();prompt.command(26,0);prompt.command(26,0);flush();prompt.key('Enter');flush();assert(saved=='Nameq');print('PASS controller confirmation inserts exactly one selected letter')
prompt.shutdown()
