-- Small transparent overlay for the real game appearance screen. Only the
-- header/footer occupy hit-test space; the game's editing controls remain live.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local nativeSkin=dofile(folder..'native_skin.lua')
local commands=dofile(folder..'appearance_commands.lua')
local M={}
local hookPath='/Script/SwtEngine.GuiControl:OnControlClick'
function M.new(ctx)
    assert(type(ctx.valid)=='function','Appearance controls require ctx.valid')
    local api={};local handles,actions={},{};local stopped=false
    local skinContext=setmetatable({nativeFocusable=false},{__index=ctx})
    local lib=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
    local layout=StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
    local function later(fn)
        if ctx.defer then ctx.defer(fn)
        else ExecuteInGameThreadAfterFrames(1,fn)end
    end
    local function notify(h,message)
        h.message=tostring(message)
        if h.status and ctx.valid(h.status)then h.status:SetText(FText(tostring(message)))end
        if ctx.log then ctx.log('Appearance: '..tostring(message))end
    end
    local function invoke(h,fn)
        if h.closed or h.queued then return end
        h.queued=true
        later(function()
            if h.closed then return end
            h.queued=false
            if not ctx.valid(h.editor)then return end
            if not h.deleteArmed then h.message=nil end
            local ok,result,err=pcall(fn)
            if not ok or not result then notify(h,ok and(err or 'The preview could not be updated.')or result)end
        end)
    end
    local pre,post=RegisterHook(hookPath,function(o)
        local object=o:get();if not ctx.valid(object)then return end
        local action=actions[object:GetAddress()]
        if action then invoke(action.handle,action.fn)end
    end)
    local inputPath='/Script/SwtEngine.SwtScreen:OnListenCommand'
    local function route(h,value,phase)
        if phase==0 and(value==3 or value==4 or value==17 or value==18)then h.message=nil;h.deleteArmed=false end
        if ctx.appearanceTraceInput and ctx.log then ctx.log('Appearance command '..value..' event '..phase)end
        local consumed=commands.route_once(h,value,phase,function(action)
            local callback=h.callbacks[action];if callback then invoke(h,callback)end
        end,later)
        if consumed and(value==23 or value==8)and phase==0 then
            -- Slate's default Tab navigation otherwise focuses a native
            -- scrollbar and sends subsequent arrows to the underlying pause.
            later(function()if not h.closed then lib:SetFocusToGameViewport()end end)
        end
        return consumed
    end
    local inputPre,inputPost=RegisterHook(inputPath,function(o,command,event)
        if stopped then return end
        if ctx.textPrompt and ctx.textPrompt.active()then ctx.textPrompt.command(command:get(),event:get());command:set(0);return end
        local object=o:get();if not ctx.valid(object)then return end
        for h in pairs(handles)do
            if not h.closed and ctx.valid(h.editor)and(object:GetAddress()==h.editor:GetAddress()or object:GetAddress()==h.pauseAddress)then
                local consumed=route(h,command:get(),event:get())
                -- The existing pause stays mounted behind our native editor;
                -- it must never change tabs or close during this transaction.
                if consumed or object:GetAddress()==h.pauseAddress then command:set(0)end
                return
            end
        end
    end)
    local keyPath='/Script/SwtEngine.SwtScreen:OnKeyPressed'
    local keyPre,keyPost=RegisterHook(keyPath,function(o,key)
        if stopped then return end
        if ctx.textPrompt and ctx.textPrompt.active()then ctx.textPrompt.key(key:get().KeyName:ToString());return end
        local object=o:get();if not ctx.valid(object)then return end
        for h in pairs(handles)do
            if not h.closed and ctx.valid(h.editor)and(object:GetAddress()==h.editor:GetAddress()or object:GetAddress()==h.pauseAddress)then
                local keyName=key:get().KeyName:ToString()
                if ctx.appearanceTraceInput and ctx.log then ctx.log('Appearance key '..keyName)end
                local value=commands.key_command(h,keyName)
                if value then route(h,value,0)end
                return
            end
        end
    end)
    function api:attach(editor,cat,callbacks)
        assert(not stopped,'Appearance controls have shut down')
        assert(ctx.valid(editor),'Appearance editor is unavailable')
        local s=assert(ctx.snapshot(),'Campaign is unavailable')
        local pause
        for _,p in ipairs(FindAllOf('GuiScreenPause')or{})do
            if ctx.valid(p)and ctx.valid(p.mcGuiTabParty)then pause=p;break end
        end
        assert(pause,'Open the pause menu before editing appearances')
        local class=LoadAsset('/Game/Art/UXD/Blueprints/Controls/gui_common/WBP_GuiClanScreenBackground.WBP_GuiClanScreenBackground_C')
        local w=lib:Create(s.gameState,class,s.pc);assert(ctx.valid(w),'Could not create appearance controls')
        local root=w.WidgetTree.RootWidget
        root:GetChildAt(0):SetVisibility(2);root:SetVisibility(4);w:SetVisibility(4)
        local h={widget=w,editor=editor,pauseAddress=pause:GetAddress(),buttons={},closed=false,queued=false,callbacks=callbacks,footerIndex=2,page='main'}
        local dpi=layout:GetViewportScale(s.gameState);local viewport=layout:GetViewportSize(s.gameState)
        local factor=math.min(viewport.X/1920,viewport.Y/1080)
        local width=viewport.X/factor;local height=viewport.Y/factor;local unit=factor/dpi
        local titleStyle=nativeSkin.find(ctx,pause.WidgetTree.RootWidget,'mcGuiTitle')
        local bodyStyle=nativeSkin.find(ctx,pause.mcGuiFooter.WidgetTree.RootWidget,'mcGuiTextConfirm')
        local frameStyle=nativeSkin.find(ctx,pause.mcGuiPanelGeneral.WidgetTree.RootWidget,'mcGuiFrameStanceInfo_2')
        assert(ctx.valid(titleStyle)and ctx.valid(bodyStyle)and ctx.valid(frameStyle),'Native menu styles are unavailable')
        local function create(name)return StaticConstructObject(StaticFindObject('/Script/UMG.'..name),w.WidgetTree)end
        local function put(o,x,y,ww,hh,z)
            local slot=root:AddChild(o);slot:SetPosition({X=x*unit,Y=y*unit});slot:SetSize({X=ww*unit,Y=hh*unit});slot:SetZOrder(z or 1);return o
        end
        local function label(value,x,y,ww,size,title)
            local style=title and titleStyle or bodyStyle
            local t=create('TextBlock');t:SetText(FText(value));t:SetFont(style.Font)
            local font=t.Font;font.Size=math.max(10,size*unit);t:SetFont(font)
            t:SetColorAndOpacity(style.ColorAndOpacity);t:SetVisibility(3)
            return put(t,x,y,ww,size*2,3)
        end
        local function button(value,x,ww,fn,accent)
            local b,skin=nativeSkin.createButton(skinContext,root,editor,pause,value,x,height-91,ww,66,1/unit,false)
            skin:setSelected(accent==true)
            local a={object=b,click=skin.click,skin=skin,handle=h,fn=fn};actions[b:GetAddress()]=a;h.buttons[#h.buttons+1]=a
            return skin.click
        end
        local showPage
        local function invokeAndRefresh(name,...)
            local callback=callbacks[name];if not callback then return nil,'This editor action is unavailable.'end
            local ok,err=callback(...)
            if ok then h.message=nil end
            return ok,err
        end
        local handlers=setmetatable({},{__index=callbacks})
        h.callbacks=handlers
        handlers.library=function()showPage('library');return true end
        handlers.tools=function()showPage('tools');return true end
        handlers.editor=function()showPage('main');return true end
        handlers.previousPreset=function()return invokeAndRefresh('selectPreset',-1)end
        handlers.nextPreset=function()return invokeAndRefresh('selectPreset',1)end
        -- Delete is reversible through the library's previous-file backup, but
        -- still ask for a second deliberate activation to avoid a stray press.
        handlers.deletePreset=function()
            if not h.deleteArmed then h.deleteArmed=true;h.message='Delete selected preset? Select Delete again to confirm.';return true end
            h.deleteArmed=false;return invokeAndRefresh('deletePreset')
        end
        showPage=function(page)
            for _,a in ipairs(h.buttons)do actions[a.object:GetAddress()]=nil;if ctx.valid(a.object)then a.object:RemoveFromParent()end end
            h.buttons={};h.footerActions={};h.page=page;h.message=nil;h.deleteArmed=false
            local specs
            if page=='library'then
                specs={{'previousPreset','Previous'},{'nextPreset','Next'},{'loadPreset','Preview preset'},{'savePreset','Save preview'},{'deletePreset','Delete'},{'editor','Back'}}
                h.footerDefault=6;h.backAction='editor'
            elseif page=='tools'then
                specs=cat.player and {{'restoreOriginal','Restore original'},{'reset','Reset preview'},{'editor','Back'}} or {{'renameName','Rename'},{'generateName','Generate name'},{'restoreOriginal','Restore original'},{'reset','Reset preview'},{'editor','Back'}}
                h.footerDefault=#specs;h.backAction='editor'
            else
                specs={{'randomize','Randomize'},{'compare','Compare'},{'library','Presets'},{'tools','More'},{'cancel','Cancel'},{'apply','Apply'}}
                h.footerDefault=5;h.backAction=nil
            end
            local gap=18;local bw=(width-84-gap*(#specs-1))/#specs
            for i,spec in ipairs(specs)do
                h.footerActions[i]=spec[1]
                button(spec[2],42+(i-1)*(bw+gap),bw,function()return handlers[spec[1]]()end,spec[1]=='apply')
            end
            h.footerIndex=h.footerDefault;h.footerMode=true
        end
        local ok,err=pcall(function()
            nativeSkin.cloneImage(ctx,root,w,frameStyle,0,0,width,94,1/unit,1)
            label(cat.player and'Your Cat' or'Clanmate Editor',42,19,380,31,true);h.nameLabel=label(cat.name or cat.roleName or 'Clanmate',450,22,width-500,27,true)
            nativeSkin.cloneImage(ctx,root,w,frameStyle,0,height-181,width,181,1/unit,1)
            h.help=label('',42,height-174,width-84,18,false)
            h.status=label('',42,height-135,width-84,18,false)
            showPage('main');h.footerMode=false
            -- Native screen commands own navigation. Enabling Slate focus on
            -- the category menu here made Tab focus it instead of our actions.
            w:AddToViewport(1000020)
        end)
        function h.close()
            if h.closed then return true end
            h.closed=true
            for _,a in ipairs(h.buttons)do if a.object then actions[a.object:GetAddress()]=nil end end
            if ctx.valid(w)then w:RemoveFromParent()end
            handles[h]=nil;return true
        end
        function h.focus()
            if not h.closed then h.footerMode=true;h.footerIndex=h.footerDefault;return true end
            return false
        end
        function h.setName(value)
            if not h.closed and ctx.valid(h.nameLabel)then h.nameLabel:SetText(FText(tostring(value or'Clanmate')))end
        end
        function h.tick()
            if h.closed then return end
            if callbacks.getName then h.setName(callbacks.getName())end
            h.comparing=callbacks.comparisonActive and callbacks.comparisonActive()or false
            local status=h.message
            if not status and h.page=='library'then
                local list,index,why=callbacks.presets();local item=list[index]
                status=why or(item and('Preset '..index..' / '..#list..': '..item.label..' | Preview, then Apply in the editor.')or'Your library is empty. Save the current preview to begin.')
            elseif not status and h.comparing then status='Showing original. Select Compare to return to your edited preview.'
            elseif not status then status='Preview only; Apply saves changes. R / X (Square): randomize. Backspace / B (Circle): '..(h.page=='main'and'cancel'or'back')..'.'end
            local rotation=ctx.appearanceRotationHint or'Q / E or right stick'
            h.help:SetText(FText(h.footerMode
                and('ACTIONS  |  Left / Right or D-pad: choose   Enter / A (Cross): select   Tab / Y (Triangle): editor')
                or('EDITOR  |  Arrows / D-pad: edit   '..rotation..': rotate   Tab / Y (Triangle): actions')))
            h.status:SetText(FText(status))
            for i,a in ipairs(h.buttons)do
                if h.footerActions[i]=='compare'then a.skin:setLabel(h.comparing and'Edited preview'or'Compare')end
                a.skin:setSelected(h.footerMode and h.footerIndex==i or(not h.footerMode and h.footerActions[i]=='apply'))
                a.skin:tick()
            end
        end
        if not ok then h.close();error(err)end
        handles[h]=true
        return h
    end
    function api:tick()for h in pairs(handles)do h.tick()end end
    function api:shutdown()
        for h in pairs(handles)do h.close()end
        if not stopped then
            UnregisterHook(hookPath,pre,post);UnregisterHook(inputPath,inputPre,inputPost);stopped=true
            UnregisterHook(keyPath,keyPre,keyPost)
        end
    end
    return api
end
return M

