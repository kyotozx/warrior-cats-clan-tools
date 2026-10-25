local originalDofile=dofile
local sequence=0;local hooks={};local queue={};local calls={}
local function obj(t)
 t=t or{};sequence=sequence+1;t.address=sequence
 function t:GetAddress()return self.address end
 function t:SetVisibility(v)self.visibility=v end
 function t:SetText(v)self.text=v end
 function t:SetFont(v)self.Font=v end
 function t:SetColorAndOpacity(v)self.color=v end
 function t:RemoveFromParent()self.removed=true end
 return t
end
local function root()
 local r=obj({children={}})
 function r:GetChildAt()return obj()end
 function r:AddChild(o)
  self.children[#self.children+1]=o
  return{SetPosition=function()end,SetSize=function()end,SetZOrder=function()end}
 end
 return r
end
local style=obj({Font={},ColorAndOpacity={}})
local skin={find=function()return style end,cloneImage=function()end}
function skin.createButton(_,r,_,_,label)
 local b=obj({label=label});r.children[#r.children+1]=b
 local c={click=b,setSelected=function(self,v)self.selected=v end,tick=function()end,setLabel=function(_,v)b.label=v end}
 return b,c
end
function dofile(path)if path:match('native_skin.lua$')then return skin end;return originalDofile(path)end
local M=dofile('mods/ClanTools/Scripts/appearance_controls.lua');dofile=originalDofile
function RegisterHook(path,fn)hooks[path]=fn;return 1,2 end
function UnregisterHook()end
function FText(s)return s end
local lib={SetFocusToGameViewport=function()end,Create=function()return obj({WidgetTree={RootWidget=root()},AddToViewport=function()end})end}
function StaticFindObject(path)
 if path:find('WidgetBlueprintLibrary')then return lib end
 if path:find('WidgetLayoutLibrary')then return{GetViewportScale=function()return 1 end,GetViewportSize=function()return{X=1920,Y=1080}end}end
 return obj()
end
function StaticConstructObject()return obj()end
function LoadAsset()return obj()end
local pause=obj({mcGuiTabParty=obj(),WidgetTree={RootWidget=root()},mcGuiFooter={WidgetTree={RootWidget=root()}},mcGuiPanelGeneral={WidgetTree={RootWidget=root()}}})
function FindAllOf()return{pause}end
local textActive=false
local ctx={valid=function(o)return type(o)=='table'and not o.removed end,snapshot=function()return{}end,defer=function(fn)queue[#queue+1]=fn end,
 textPrompt={active=function()return textActive end,command=function(c)calls[#calls+1]='text:'..c end,key=function(k)calls[#calls+1]='key:'..k end}}
local function flush()local q=queue;queue={};for _,f in ipairs(q)do f()end end
local cb={getName=function()return'Custom Name'end,presets=function()return{{label='Saved look'}},1 end,comparisonActive=function()return false end}
for _,name in ipairs({'apply','cancel','reset','randomize','compare','renameName','generateName','restoreOriginal','savePreset','loadPreset','deletePreset','selectPreset'})do
 cb[name]=function()calls[#calls+1]=name;return true end
end
local api=M.new(ctx);local editor=obj();local h=api:attach(editor,{name='Original'},cb)
api:tick();assert(h.nameLabel.text=='Custom Name');assert(#h.buttons==6 and h.footerActions[6]=='apply')
local function command(value,event)
 local v=value;hooks['/Script/SwtEngine.SwtScreen:OnListenCommand']({get=function()return editor end},{get=function()return v end,set=function(_,n)v=n end},{get=function()return event or 0 end})
 flush();return v
end
assert(command(27)==0 and calls[#calls]=='randomize')
command(23);assert(h.footerIndex==5)
command(4);command(26);assert(h.page=='tools'and #h.buttons==5)
command(25);assert(h.page=='main')
command(4);command(4);command(26);assert(h.page=='library')
api:tick();assert(h.status.text:find('Saved look',1,true))
command(25);assert(h.page=='main')
textActive=true;local n=#calls;assert(command(27)==0 and calls[n+1]=='text:27')
textActive=false;h.close();api:shutdown();assert(h.closed)
print('PASS native footer pages, pending-name header, semantic randomize, preset status, Back and exclusive text-prompt routing')
