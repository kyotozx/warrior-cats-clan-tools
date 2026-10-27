-- Clan Appearance Editor controller. All functions/callbacks run on the game
-- thread. The root UI supplies real game widgets; this module owns transactions.
local M = {}
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local function copy(t)
    local r = {}; for k,v in pairs(t) do r[k] = v end; return r
end
local function same(a,b)
    return a and b and a.profile == b.profile and a.slot == b.slot
        and a.chapter == b.chapter and a.gs == b.gs and a.worldId == b.worldId
end
local function nativeTransport(directory,dllName)
    assert(type(directory) == "string", "appearance nativeDir is required")
    local slash = directory:sub(-1) == "/" or directory:sub(-1) == "\\"
    local path = directory .. (slash and "" or "/")
    dllName=dllName or 'clanappearance.dll'
    assert(type(dllName)=='string'and dllName:match('^[%w_-]+%.dll$'),'Invalid appearance bridge filename')
    local dispatch, loadError = package.loadlib(path .. dllName, "ClanAppearance_dispatch")
    if not dispatch then return function() return nil, "Appearance bridge unavailable: " .. tostring(loadError) end end
    local id = 0
    return function(command)
        id = id + 1
        local f, err = io.open(path .. "appearance-request.txt", "w")
        if not f then return nil, "Cannot write appearance request: " .. tostring(err) end
        f:write(tostring(id), " ", command, "\n"); f:close()
        local ok, failure = pcall(dispatch)
        if not ok then return nil, "Appearance bridge failed: " .. tostring(failure) end
        f = io.open(path .. "appearance-response.txt", "r")
        if not f then return nil, "Appearance bridge did not respond" end
        local line = f:read("*l") or ""; local details = f:read("*a") or ""; f:close()
        local responseId, status, text = line:match("^(%d+) (%u+) (.*)$")
        if tonumber(responseId) ~= id then return nil, "Stale appearance response" end
        if status ~= "OK" then return nil, text or line, {details=details} end
        return { action = text, details = details }
    end
end
M.nativeTransport = nativeTransport

-- Required ctx adapters:
-- snapshot() -> {profile=string,slot=number,chapter=string,gs=stable identity,
--               clan=integer,offline=true}; getCats() -> array of
-- {role=integer,clan=integer,living=true,name=string,...}.
-- backupSave(snapshot,cat) -> non-false receipt (must finish before BEGIN).
-- openAppearanceEditor(cat,callbacks) -> handle (or true for asynchronous open).
-- callbacks.ready(actorAddress) BEFORE widget creation, callbacks.screenReady(widgetAddress),
-- callbacks.apply(), callbacks.cancel(),
-- callbacks.closed() AFTER game editor teardown; callback methods return ok,error.
-- closeAppearanceEditor(handle) begins closing; it MUST eventually call closed.
-- defer(fn) schedules on a later game tick. Never call immediately.
-- Optional native(command) allows tests/custom transport; otherwise nativeDir.
-- Optional notify(message), refreshCat(cat), onChanged(state).
function M.new(ctx)
    for _,name in ipairs({"snapshot","getCats","backupSave","openAppearanceEditor","closeAppearanceEditor","defer"}) do
        assert(type(ctx[name]) == "function", "appearance requires ctx." .. name)
    end
    local command = ctx.native or nativeTransport(ctx.nativeDir,ctx.appearanceDllName)
    local self = { phase = "idle", target = nil, handle = nil, lastError = nil }
    local token, backup, closeRequested, epoch = nil,nil,false,0
    local pendingName
    -- Sparse transaction breadcrumbs, without player names or save contents.
    local function trace(stage)
        if ctx.log then pcall(ctx.log,'Appearance apply: '..stage) end
    end
    local function state()
        return {phase=self.phase,target=self.target and copy(self.target),lastError=self.lastError,backup=backup}
    end
    local function changed()
        if ctx.onChanged then pcall(ctx.onChanged,state()) end
    end
    local function fail(message)
        self.lastError = tostring(message); changed()
        if ctx.notify then pcall(ctx.notify,self.lastError) end
        return nil,self.lastError
    end
    local function currentTarget(r)
        for _,cat in ipairs(ctx.getCats()) do if cat.role == r then return cat end end
    end
    local function eligible(cat,snapshot)
        return cat and type(cat.role)=="number" and cat.role%1==0 and cat.role>=0 and cat.role<255 and (cat.role~=0 or cat.player==true)
            and cat.living==true and cat.clan==snapshot.clan
            and type(cat.clan)=="number" and cat.clan>=1 and cat.clan<=5
    end
    local function contextValid()
        local s=ctx.snapshot()
        return same(s,token) and s.offline==true and eligible(currentTarget(self.target.role),s)
    end
    local library
    if ctx.root and ctx.read and ctx.write then
        library=dofile(folder..'appearance_library.lua').new(setmetatable({native=command,
            ensureEditable=function()return self.phase=='editing'and contextValid(),'No editable appearance preview.'end,
            target=function()return self.target end},{__index=ctx}))
    end
    local function close()
        if closeRequested then return true end
        closeRequested=true
        local ok,result,err=pcall(ctx.closeAppearanceEditor,self.handle)
        if not ok or result==false then
            closeRequested=false
            return fail(ok and (err or "The appearance editor could not close") or result)
        end
        return true
    end
    function self:state() return state() end
    function self:loadSkin(values)
        if self.phase~='editing' or not contextValid() then return fail('Open your cat preview first.') end
        return command('PREVIEW_LOAD '..values)
    end
    function self:list()
        local s=ctx.snapshot(); local result={}
        if not s or s.offline~=true then return result end
        for _,cat in ipairs(ctx.getCats()) do if eligible(cat,s) then result[#result+1]=copy(cat) end end
        table.sort(result,function(a,b) return tostring(a.name or a.role)<tostring(b.name or b.role) end)
        return result
    end
    function self:begin(role)
        if self.phase~="idle" then return fail("Finish the current appearance edit first") end
        local s=ctx.snapshot()
        if not s or s.offline~=true or type(s.profile)~="string" or s.profile=="" then return fail("Load an offline clan before editing appearances") end
        s=copy(s)
        local cat=currentTarget(role)
        if not eligible(cat,s) then return fail("Choose a living cat from your clan") end
        local ok,receipt,err=pcall(ctx.backupSave,s,cat)
        if not ok or not receipt then return fail(ok and (err or "A save backup is required before editing") or receipt) end
        -- A backup may take time: check context again before touching native state.
        if not same(s,ctx.snapshot()) then return fail("The active profile changed; reopen the editor") end
        local result,metadata; result,err,metadata=command(string.format("BEGIN %d %d",cat.role,cat.clan))
        if not result then
            if metadata and metadata.details and metadata.details:match("active=1") then
                self.phase="guarded_error";self.target=copy(cat);token=copy(s);backup=receipt
            end
            return fail(err)
        end
        token=copy(s);backup=receipt;self.target=copy(cat);self.phase="opening";self.lastError=nil
        pendingName=nil
        self.handle=nil;closeRequested=false;epoch=epoch+1;local myEpoch=epoch
        changed()
        local callbacks={}
        local function live() return epoch==myEpoch and self.phase~="idle" end
        callbacks.ready=function(address) if live() then return self:bind(address) end end
        callbacks.cameraReady=function(address) if live() then return self:borrowCamera(address) end end
        callbacks.cameraTarget=function(index,address)if live()then return self:cameraTarget(index,address)end end
        callbacks.initializeScreen=function(address) if live() then return self:initializeScreen(address) end end
        callbacks.screenReady=function(address) if live() then return self:guardScreen(address) end end
        callbacks.detachScreen=function() if live() then return command('DETACH_SCREEN') end end
        callbacks.apply=function() if live() then return self:apply() end end
        callbacks.cancel=function() if live() then return self:cancel() end end
        callbacks.reset=function() if live() then return self:reset() end end
        callbacks.getName=function()return pendingName or(self.target and self.target.name)or''end
        callbacks.renameName=function()
            if not live()or not ctx.promptAppearanceName then return false,'Name editor is unavailable.'end
            return ctx.promptAppearanceName(callbacks.getName(),function(value)return self:setName(value)end)
        end
        callbacks.generateName=function()
            if not live()or not ctx.catNames then return false,'Name generation is unavailable.'end
            return self:setName(ctx.catNames.generate(self.target,callbacks.getName()))
        end
        if library then
            for _,method in ipairs({'randomize','compare','restoreOriginal','savePreset','loadPreset','deletePreset','selectPreset'})do
                callbacks[method]=function(...)if live()then return library[method](...)end end
            end
            callbacks.presets=library.presets;callbacks.comparisonActive=library.comparisonActive
        end
        callbacks.closed=function() if live() then return self:onEditorClosed() end end
        ok,result,err=pcall(ctx.openAppearanceEditor,copy(cat),callbacks)
        if not ok or not result then
            -- The adapter must close any partially created screen, then invoke closed.
            command("CANCEL");self.phase="closing";changed();close()
            return fail(ok and (err or "The game appearance editor could not open") or result)
        end
        if type(result)~="boolean" then self.handle=result end
        return true
    end
    function self:bind(address)
        if self.phase~="opening" then return fail("Appearance preview is not awaiting an actor") end
        if not contextValid() then self:cancel();return fail("The active cat or profile changed") end
        local numeric=type(address)=="number" and address or tonumber(address)
        if not numeric or numeric<=0 or numeric%1~=0 then return fail("The game preview actor is not ready") end
        local ok,err=command(string.format("BIND %x",numeric))
        if not ok then return fail(err) end
        self.phase="editing";changed();return true
    end
    function self:reset()
        if self.phase~="editing" or not contextValid() then return fail("No editable appearance preview") end
        local ok,err
        if library then ok,err=library.reset()else ok,err=command('RESET')end
        if not ok then return fail(err)end
        pendingName=nil;changed()
        return true
    end
    function self:setName(value)
        if self.phase~='editing'or not contextValid()or not ctx.catNames then return fail('No editable clanmate name.')end
        local ok,receipt=pcall(ctx.catNames.prepare,ctx.snapshot(),self.target,value)
        if not ok then return fail(receipt)end
        pendingName=receipt.name;changed();return true
    end
    function self:guardScreen(address)
        if self.phase~="editing" or not contextValid() then return fail("Preview must be ready before attaching the editor") end
        local numeric=type(address)=="number" and address or tonumber(address)
        if not numeric or numeric<=0 or numeric%1~=0 then return fail("Invalid game editor widget") end
        local ok,err=command(string.format("GUARD_SCREEN %x",numeric))
        if not ok then return fail(err) end
        return true
    end
    function self:initializeScreen(address)
        if self.phase~="editing" or not contextValid() then return fail("Preview must be ready before initializing the editor") end
        local numeric=type(address)=="number" and address or tonumber(address)
        if not numeric or numeric<=0 or numeric%1~=0 then return fail("Invalid game editor widget") end
        local ok,err=command(string.format("INIT_SCREEN %x",numeric))
        if not ok then return fail(err) end
        if library then local good,why=library.begin();if not good and ctx.notify then ctx.notify(why)end end
        return true
    end
    function self:borrowCamera(address)
        if self.phase~="editing" or not contextValid() then return fail("Preview must be ready before attaching the camera") end
        local numeric=type(address)=="number" and address or tonumber(address)
        if not numeric or numeric<=0 or numeric%1~=0 then return fail("Invalid game camera helper") end
        local ok,err=command(string.format("BORROW_CAMERA %x",numeric))
        if not ok then return fail(err) end
        return true
    end
    function self:cameraTarget(index,address)
        if self.phase~="editing" or not contextValid()then return fail("Preview must be ready before attaching cameras")end
        if type(index)~='number'or index%1~=0 or index<1 or index>5 then return fail('Invalid preview camera slot')end
        local numeric=type(address)=='number'and address or tonumber(address)
        if not numeric or numeric<=0 or numeric%1~=0 then return fail('Invalid preview camera actor')end
        local ok,err=command(string.format('CAMERA_TARGET %d %x',index,numeric))
        if not ok then return fail(err)end;return true
    end
    function self:pollNativeIntent()
        if self.phase~="editing" then return true end
        local result,err=command("STATUS");if not result then return fail(err) end
        local intent=tonumber((result.details or ""):match("intent=(%d+)"))
        if intent==1 then return self:apply() end
        if intent==2 then return self:cancel() end
        return true
    end
    function self:apply()
        trace('validate')
        if self.phase~="editing" then return fail("Wait for the appearance preview to load") end
        if not contextValid() then self:cancel();return fail("The active cat or profile changed; changes were not applied") end
        if library then local editable,why=library.leaveComparison();if not editable then return fail(why)end end
        local nameReceipt
        if pendingName and ctx.catNames and not self.target.player then
            local prepared,result=pcall(ctx.catNames.prepare,ctx.snapshot(),self.target,pendingName)
            if not prepared then return fail(result)end;nameReceipt=result
        end
        trace('capture preview')
        local ok,err=command("CAPTURE");if not ok then trace('capture rejected');return fail(err) end
        trace('commit appearance')
        ok,err=command("APPLY")
        if not ok then trace('appearance rejected');return fail(err) end
        local appearanceChanged=ok.action~='UNCHANGED'
        trace(appearanceChanged and 'appearance committed' or 'appearance unchanged')
        self.phase="applied";changed()
        if nameReceipt then
            trace('save display name')
            local saved,nameError=pcall(ctx.catNames.commit,nameReceipt)
            if saved then self.target.name=pendingName
            elseif ctx.notify then pcall(ctx.notify,'Appearance saved, but the name could not be saved: '..tostring(nameError))end
            trace(saved and 'display name saved' or 'display name failed')
        end
        -- A display-name edit must not invoke the native NPC role/mesh refresh.
        -- The normal name overlay picks up the committed alias after teardown.
        if appearanceChanged and ctx.refreshCat then
            trace('refresh world appearance')
            local refreshOK,refreshError=pcall(ctx.refreshCat,self.target)
            if not refreshOK and ctx.notify then pcall(ctx.notify,"Appearance saved. The world preview will refresh when reloaded: "..tostring(refreshError)) end
            trace(refreshOK and 'world refreshed' or 'world refresh failed')
        end
        trace('close editor')
        return close()
    end
    function self:cancel()
        if self.phase=="idle" then return true end
        if self.phase~="applied" then
            local ok,err=command("CANCEL");if not ok then return fail(err) end
        end
        self.phase="closing";changed();return close()
    end
    function self:onEditorClosed()
        if self.phase=="idle" or self.phase=="finishing" then return true end
        -- Escape/native Back can close the editor without our Cancel callback.
        if self.phase~="applied" then
            local ok,err=command("CANCEL");if not ok then return fail(err) end
        end
        self.phase="finishing";changed();local myEpoch=epoch
        ctx.defer(function() ctx.defer(function()
            if epoch~=myEpoch or self.phase~="finishing" then return end
            trace('release transaction')
            local ok,err=command("END")
            if not ok then self.phase="guarded_error";fail(err);return end
            if ctx.releaseAppearanceEditor then pcall(ctx.releaseAppearanceEditor,self.handle)end
            self.phase="idle";self.target=nil;self.handle=nil;token=nil;closeRequested=false;changed()
            trace('transaction closed')
        end) end)
        return true
    end
    function self:retryCleanup()
        if self.phase~="guarded_error" then return fail("No pending editor cleanup") end
        -- The root must have observed the actual editor closed before this call.
        local ok,err=command("END");if not ok then return fail(err) end
        if ctx.releaseAppearanceEditor then pcall(ctx.releaseAppearanceEditor,self.handle)end
        self.phase="idle";self.target=nil;self.handle=nil;token=nil;closeRequested=false;changed();return true
    end
    function self:checkContext()
        if self.phase=="opening" or self.phase=="editing" then
            if not contextValid() then return self:cancel() end
        end
        return true
    end
    return self
end
return M
