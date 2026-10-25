-- Reuse the game's complete button visual trees, materials, fonts, glows and
-- state canvases. The only added widget is an invisible hit target for tabs.
local M={}
local function named(o)return o:GetFullName():match('([^%.]+)$')end
local function classes()
    return {panel=StaticFindObject('/Script/UMG.PanelWidget'),canvasSlot=StaticFindObject('/Script/UMG.CanvasPanelSlot'),
        text=StaticFindObject('/Script/UMG.TextBlock'),size=StaticFindObject('/Script/UMG.SizeBox'),
        userWidget=StaticFindObject('/Script/UMG.UserWidget')}
end
local function walk(ctx,root,fn,c,seen,depth)
    if not ctx.valid(root)then return end
    seen=seen or {};depth=depth or 0
    if depth>64 then return end
    local address=root:GetAddress();if seen[address]then return end;seen[address]=true
    fn(root)
    if root:IsA(c.panel)then
        for i=0,root:GetChildrenCount()-1 do walk(ctx,root:GetChildAt(i),fn,c,seen,depth+1)end
    elseif root:IsA(c.userWidget)then
        -- Blueprint GuiText and other controls own separate WidgetTrees; they
        -- are not PanelWidgets. Their actual state TextBlocks still need the
        -- same caption size as direct children of CanvasNormal/Disabled.
        local tree=root.WidgetTree
        if ctx.valid(tree)then walk(ctx,tree.RootWidget,fn,c,seen,depth+1)end
    end
end
function M.find(ctx,root,name)
    local result;walk(ctx,root,function(o)if named(o)==name then result=o end end,classes());return result
end
local function setLabel(ctx,b,label)
    label=tostring(label):upper()
    b.Text=FText(label)
    for _,field in ipairs({'mcGuiTextNormal','mcGuiTextSelected','mcGuiTextDisabled','mcGuiTextPressed','mcGuiTextOver'})do
        local text=b[field];if ctx.valid(text)then text:SetText(FText(label))end
    end
end
local function reflow(ctx,content,width,height,c)
    local size=content.Slot:GetSize();assert(size.X>0 and size.Y>0,'Native button has no measured design size')
    local fx,fy=width/size.X,height/size.Y
    walk(ctx,content,function(o)
        if o~=content and ctx.valid(o.Slot)and o.Slot:IsA(c.canvasSlot)then
            local p=o.Slot:GetOffsets()
            o.Slot:SetOffsets({Left=p.Left*fx,Top=p.Top*fy,Right=p.Right*fx,Bottom=p.Bottom*fy})
        end
        if o:IsA(c.text)then
            -- Resize only the instance font size. Keep its real typeface,
            -- outline, material, letter spacing and all state colors.
            local font=o.Font;font.Size=math.max(8,font.Size*fy);o:SetFont(font)
        elseif o:IsA(c.size)then
            if o.bOverride_WidthOverride~=0 and o.bOverride_WidthOverride~=false then o:SetWidthOverride(o.WidthOverride*fx)end
            if o.bOverride_HeightOverride~=0 and o.bOverride_HeightOverride~=false then o:SetHeightOverride(o.HeightOverride*fy)end
            if o.bOverride_MinDesiredWidth~=0 and o.bOverride_MinDesiredWidth~=false then o:SetMinDesiredWidth(o.MinDesiredWidth*fx)end
            if o.bOverride_MinDesiredHeight~=0 and o.bOverride_MinDesiredHeight~=false then o:SetMinDesiredHeight(o.MinDesiredHeight*fy)end
            if o.bOverride_MaxDesiredWidth~=0 and o.bOverride_MaxDesiredWidth~=false then o:SetMaxDesiredWidth(o.MaxDesiredWidth*fx)end
            if o.bOverride_MaxDesiredHeight~=0 and o.bOverride_MaxDesiredHeight~=false then o:SetMaxDesiredHeight(o.MaxDesiredHeight*fy)end
        end
    end,c)
    -- Common1 reserves only 400 of its 1024 design units for its caption.
    -- Wider labels need a wider native ScaleBox, not a smaller replacement font.
    walk(ctx,content,function(o)
        if o:IsA(c.text)then
            local parent=o:GetParent()
            if ctx.valid(parent)and ctx.valid(parent.Slot)and parent.Slot:IsA(c.canvasSlot)then
                local name=parent:GetClass():GetFullName()
                if name:find('ScaleBox',1,true)or name:find('SizeBox',1,true)then
                    local extent=parent.Slot:GetSize();parent.Slot:SetSize({X=width*.82,Y=extent.Y})
                end
            end
        end
    end,c)
    content.Slot:SetAnchors({Minimum={X=0,Y=0},Maximum={X=0,Y=0}})
    content.Slot:SetAlignment({X=0,Y=0});content.Slot:SetPosition({X=0,Y=0});content.Slot:SetSize({X=width,Y=height})
    return size.X,size.Y
end
-- Coordinates and dimensions use the caller's design units; scale converts to
-- UMG units, matching ui.lua's x/scale convention. owner is the parent screen.
-- Return values: the real UGuiButtonState, and an optional controller containing
-- .click, :setSelected(bool), :setEnabled(bool), :tick(), :setLabel(text).
function M.createButton(ctx,parentRoot,owner,pause,label,x,y,width,height,scale,isTab)
    assert(type(ctx.valid)=='function'and ctx.valid(parentRoot),'Native button parent is unavailable')
    assert(width>0 and height>0 and scale>0,'Invalid native button dimensions')
    local s=assert(ctx.snapshot(),'Campaign is unavailable')
    local prototype=not ctx.nativeButtonClass and (isTab and pause.mcGuiTabParty or pause.mcGuiPanelGeneral.mcGuiButtonResume)
    assert(ctx.nativeButtonClass or ctx.valid(prototype),'Native pause button template is unavailable')
    local lib=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
    local b=lib:Create(s.gameState,ctx.nativeButtonClass or prototype:GetClass(),s.pc);assert(ctx.valid(b),'Could not create native button')
    b.ParentScreen=owner
    local c=classes();local tree=b.WidgetTree.RootWidget
    local content=M.find(ctx,tree,'CanvasContent');assert(ctx.valid(content),'Native button content is unavailable')
    local naturalWidth,naturalHeight=reflow(ctx,content,width/scale,height/scale,c)
    -- The original menu's font is already sized for its runtime DPI; scaling
    -- it again by the 256-unit art canvas height makes captions unreadable.
    -- Give owned captions a readable design size, keeping the game's complete
    -- font/typeface/material/outline configuration and native ScaleBox fitting.
    local captionSize=math.min(22,height*.40)/scale
    local function sizeCaptions()
        walk(ctx,content,function(o)
            if o:IsA(c.text)then local font=o.Font;font.Size=captionSize;o:SetFont(font)end
        end,c)
    end
    sizeCaptions()
    setLabel(ctx,b,label)
    local slot=parentRoot:AddChild(b);slot:SetPosition({X=x/scale,Y=y/scale});slot:SetSize({X=width/scale,Y=height/scale});slot:SetZOrder(30)
    local oldClick=b.mcGuiButtonCollision
    if ctx.valid(oldClick)then oldClick:RemoveFromParent()end
    -- A new invisible hit widget sets focusability before Slate construction.
    -- Changing the raw IsFocusable property of an already-built SButton may
    -- otherwise leave its previous keyboard/gamepad behavior cached.
    local click=StaticConstructObject(StaticFindObject('/Script/UMG.Button'),b.WidgetTree)
    click.IsFocusable=ctx.nativeFocusable==true
    local hit=tree:AddChild(click);hit:SetAnchors({Minimum={X=0,Y=0},Maximum={X=1,Y=1}})
    hit:SetAlignment({X=0,Y=0});hit:SetOffsets({Left=0,Top=0,Right=0,Bottom=0});hit:SetZOrder(999)
    click:SetBackgroundColor({R=0,G=0,B=0,A=0});b.mcGuiButtonCollision=click
    for _,binding in ipairs({{'OnClicked','OnControlClick'},{'OnHovered','OnGotFocus'},{'OnUnhovered','OnLostFocus'},
        {'OnPressed','OnControlPress'},{'OnReleased','OnControlRelease'}})do
        click[binding[1]]:Remove(b,binding[2]);click[binding[1]]:Add(b,binding[2])
    end
    local control={object=b,click=click,selected=false,enabled=true,naturalWidth=naturalWidth,naturalHeight=naturalHeight}
    local previous
    function control:tick()
        if not ctx.valid(b)or not ctx.valid(click)then return end
        local state=not self.enabled and 3 or click:IsPressed()and 4 or(self.selected or click:IsHovered()or click:HasKeyboardFocus())and 2 or 1
        if previous==state then return end;previous=state
        b:OnChangeState(state)
        -- Native state callbacks may restore authored text style. Normalize
        -- only the size after that callback, retaining typeface/tint/material.
        sizeCaptions()
        local show=state==3 and'CanvasDisabled'or state==4 and'CanvasPressed'or state==2 and'CanvasSelected'or'CanvasNormal'
        if not ctx.valid(b[show])then show=state==3 and'CanvasNormal'or'CanvasSelected'end
        for _,field in ipairs({'CanvasNormal','CanvasSelected','CanvasDisabled','CanvasPressed','CanvasOver'})do
            local panel=b[field];if ctx.valid(panel)then panel:SetVisibility(field==show and 3 or 2)end
        end
    end
    function control:setSelected(selected)
        local value=selected==true;if self.selected==value then self:tick();return end
        self.selected=value;previous=nil;self:tick()
    end
    function control:setEnabled(enabled)
        local value=enabled~=false;if self.enabled==value then return end
        self.enabled=value;click:SetIsEnabled(value);previous=nil;self:tick()
    end
    function control:setLabel(value)setLabel(ctx,b,value)end
    control:tick();return b,control
end
-- Copy an actual game Image's full Slate brush, tint and opacity. Useful for
-- native pause panel frames; no replacement rectangle/material is invented.
function M.cloneImage(ctx,parentRoot,owner,source,x,y,width,height,scale,z)
    assert(ctx.valid(source),'Native image source is unavailable')
    local image=StaticConstructObject(StaticFindObject('/Script/UMG.Image'),owner.WidgetTree)
    image:SetBrush(source.Brush);image:SetColorAndOpacity(source.ColorAndOpacity);image:SetRenderOpacity(source:GetRenderOpacity());image:SetVisibility(3)
    local slot=parentRoot:AddChild(image);slot:SetPosition({X=x/scale,Y=y/scale});slot:SetSize({X=width/scale,Y=height/scale});slot:SetZOrder(z or 5)
    return image
end
return M
