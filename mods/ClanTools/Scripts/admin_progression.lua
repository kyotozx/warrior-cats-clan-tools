-- Exact-build progression transactions. All entry points run on the game thread.
-- Persistent edits require a fresh preview, a save backup, and a verified gate.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local valid=dofile(folder..'runtime_valid.lua').valid
local M={}
local function integer(v,lo,hi)return type(v)=='number' and v%1==0 and v>=lo and v<=hi end
local function address(x)assert(valid(x),'Object is no longer available.');return x:GetAddress()end
function M.nativeAdapter(ctx,bin,library)
    bin=bin or folder..'../bin/'
    local run=assert(package.loadlib(bin..(library or 'admin-progression.dll'),'ClanProgression_run'))
    local nonce=0
    local function invoke(s,command,cat,expected,target)
        assert(s and s.offline==true and s.phase==4,'Progression requires offline exploration.')
        local manager=FindFirstOf('WrcSaveManager');local managerAddress=address(manager)
        local object,owner,class=0,0,0
        if command:match('^PILE_')then
            local gs=assert(s.gameState,'Gameplay state unavailable.')
            owner=address(gs);local component=gs.FreshKillPileComponent;object=address(component)
            local c=StaticFindObject('/Script/SwtAdventure.SwtAdventureFreshKillPileComponent');class=address(c)
            assert(address(component:GetClass())==class,'Unsupported pile class.')
            assert(address(component:GetOwner())==owner,'Pile owner changed.')
        else
            assert(cat and integer(cat.role,1,254),'Choose a named clanmate.')
            assert(ctx.validateCat and ctx.validateCat(cat,s)==true,'Selected clanmate is unavailable.')
        end
        nonce=nonce+1
        local f=assert(io.open(bin..'admin-progression-request.txt','wb'))
        assert(f:write(string.format('%d %s %x %x %x %x %d %.9g %.9g\n',nonce,command,object,owner,class,managerAddress,cat and cat.role or 0,expected or 0,target or 0)));f:close()
        run()
        f=assert(io.open(bin..'admin-progression-status.txt','rb'));local text=f:read('*a');f:close()
        local r={};for k,v in text:gmatch('([%w_]+)=([^\r\n]+)')do r[k]=v end
        assert(tonumber(r.nonce)==nonce,'Stale progression response.')
        assert(r.status==(command:match('PROBE$')and'READY'or'APPLIED'),r.status or'Missing progression response.')
        for _,k in ipairs({'current','maximum','after','rank','after_rank'})do r[k]=tonumber(r[k])end
        return r
    end
    local adapter={
        pileProbe=function(s)return invoke(s,'PILE_PROBE')end,
        pileFill=function(s,preview)return invoke(s,'PILE_FILL',nil,preview.current,preview.maximum)end,
        pileSet=function(s,preview,target)return invoke(s,'PILE_SET',nil,preview.current,target)end,
        bondProbe=function(s,cat)return invoke(s,'BOND_PROBE',cat)end,
        bondSet=function(s,cat,preview,target)return invoke(s,'BOND_SET',cat,preview.current,target)end,
    }
    local quests=dofile(folder..'admin_quest_runtime.lua').new(ctx,bin)
    for k,v in pairs(quests)do adapter[k]=v end
    return adapter
end
function M.new(ctx)
    assert(type(ctx.snapshot)=='function','Progression requires a snapshot provider.')
    local adapter=ctx.progressionAdapter or {};local api={};local previews,originals={},{}
    local session,sequence,closed=nil,0,false
    local job,lastQuestResult=nil,nil
    local function snapshot()
        assert(not closed,'Progression tools are closed.')
        local s=ctx.snapshot()
        assert(s and s.offline==true and s.phase==4 and not s.combat,'Progression requires offline exploration.')
        assert(valid(s.pawn),'Player is unavailable.')
        assert(s.worldId=='World /Game/Art/Maps/Gameplay/L_WorldMap_01_P.L_WorldMap_01_P','Unsupported campaign world.')
        assert(type(s.profile)=='string' and #s.profile>0 and integer(s.slot,0,99),'Active save is unavailable.')
        local key=table.concat({s.worldId,s.profile,s.slot,s.chapter or'',s.pawn:GetAddress()},'|')
        if session~=key then
            if job then lastQuestResult={status='stopped',message='Active save, chapter or player changed.'};job=nil end
            previews,originals={},{};session=key
        end
        return s
    end
    local function supported(feature)
        if not(ctx.verified and ctx.verified[feature]==true)then return false end
        if feature=='pile'then return type(adapter.pileProbe)=='function' and type(adapter.pileFill)=='function'end
        if feature=='bonds'then return type(adapter.bondProbe)=='function' and type(adapter.bondSet)=='function'end
        if feature=='quests'then return type(adapter.listQuests)=='function' and type(adapter.questStep)=='function' and type(adapter.questTurnIn)=='function' and type(adapter.questProbe)=='function'end
        return false
    end
    local function catByRole(role,s)
        assert(integer(role,1,254),'Choose a named clanmate.')
        local cats,meta=ctx.getCats();assert(meta and meta.valid,'Clan roster unavailable.')
        assert(meta.profile==s.profile and meta.slot==s.slot,'Clan roster belongs to another save.')
        for _,cat in ipairs(cats)do if cat.role==role then
            assert(cat.clan==s.clan and cat.living==true,'Choose a living clanmate.')
            assert(ctx.validateCat and ctx.validateCat(cat,s)==true,'Clanmate data has changed.')
            return cat
        end end
        error('The selected cat is no longer in this clan.')
    end
    local function preview(kind,args)
        local s=snapshot();local r,cat
        if kind=='quests'then
            assert(adapter.listQuests,'Quest adapter unavailable.')
            local out={}
            local entries,diagnostics=adapter.listQuests(s)
            if #entries==0 and diagnostics and diagnostics.errors and #diagnostics.errors>0 then
                error('Active quest preview unavailable: '..tostring(diagnostics.errors[1].reason))
            end
            for _,e in ipairs(entries)do
                sequence=sequence+1;local token=tostring(sequence)
                previews[token]={kind='quest',session=session,entry=e,quest_status=e.quest_status,count=e.count}
                out[#out+1]={token=token,id=e.id,tag=e.tag,name=e.name,status=e.quest_status,result=e.result,active=e.active,in_progress=e.in_progress,enabled=supported('quests')}
            end
            return out
        end
        if kind=='pile'then assert(adapter.pileProbe,'Pile adapter unavailable.');r=adapter.pileProbe(s)
        elseif kind=='bond'then cat=catByRole(args.role,s);assert(adapter.bondProbe,'Bond adapter unavailable.');r=adapter.bondProbe(s,cat)
        else error('Unknown preview.')end
        assert(type(r.current)=='number' and r.current==r.current and type(r.maximum)=='number' and r.maximum>0 and r.maximum<=1000000 and r.current>=0 and r.current<=r.maximum,'Invalid progression bounds.')
        if kind=='bond'then assert(integer(r.current,0,100)and r.maximum==100,'Invalid bond bounds.')end
        sequence=sequence+1;local token=tostring(sequence)
        previews[token]={kind=kind,current=r.current,maximum=r.maximum,role=cat and cat.role,session=session,rank=r.rank}
        return {token=token,current=r.current,maximum=r.maximum,rank=r.rank,role=cat and cat.role,name=cat and cat.name,enabled=supported(kind=='bond'and'bonds'or'pile')}
    end
    function api.preview(kind,args)
        local ok,result=pcall(preview,kind,args or{});if ok then return true,result end;return false,tostring(result)
    end
    function api.capabilities()return {pile=supported('pile'),bonds=supported('bonds'),quests=supported('quests')}end
    local function mutate(id,args)
        local s=snapshot()
        assert(not job,'Wait for the selected quest to finish or cancel it.')
        if id=='complete_quest'then
            assert(supported('quests'),'Quest completion has not been verified in this game build.')
            local p=previews[tostring(args.token)]
            assert(p and p.kind=='quest'and p.session==session,'Refresh the quest list before completing a quest.')
            local now=adapter.questProbe(s,p.entry)
            assert((now.quest_status==2 or(now.quest_status==3 and now.result==1))and now.quest_status==p.quest_status and now.count==p.count,'The selected quest changed or is already finished.')
            assert(type(ctx.backupSave)=='function','Save backup unavailable.')
            local backup=ctx.backupSave(s);assert(type(backup)=='string'and#backup>0,'Save backup failed.')
            snapshot();assert(p.session==session,'The active save changed.')
            previews[tostring(args.token)]=nil
            job={entry=p.entry,session=session,backup=backup,steps=0,elapsed=0,total=0}
            lastQuestResult={status='running',message='Completing the selected quest through its active objectives.',tag=p.entry.tag}
            return {queued=true,tag=p.entry.tag,backup=backup}
        end
        local kind=id=='fill_pile'and'pile'or'bond'
        assert(id=='fill_pile'or id=='set_bond'or id=='restore_bond','Unknown progression action.')
        assert(supported(kind=='pile'and'pile'or'bonds'),'This progression action has not been verified in this game build.')
        local p=previews[tostring(args.token)];assert(p and p.kind==kind and p.session==session,'Refresh the preview before applying changes.')
        local cat=kind=='bond'and catByRole(p.role,s)or nil
        local target=kind=='pile'and p.maximum or args.value
        if id=='restore_bond'then target=assert(originals[p.role],'No original bond is stored for this session.')end
        if kind=='bond'then assert(integer(target,0,100),'Bond must be a whole number from 0 to 100.')end
        local now=kind=='pile'and adapter.pileProbe(s)or adapter.bondProbe(s,cat)
        assert(now.current==p.current and now.maximum==p.maximum,'The value changed. Refresh the preview.')
        assert(type(ctx.backupSave)=='function','Save backup is unavailable.')
        local backup=ctx.backupSave(s,cat);assert(type(backup)=='string'and#backup>0,'Save backup failed.')
        -- Recheck identity after the backup and consume before invoking native code.
        snapshot();assert(p.session==session,'The active save changed.')
        previews[tostring(args.token)]=nil
        if kind=='bond'and originals[p.role]==nil then originals[p.role]=p.current end
        local r=kind=='pile'and adapter.pileFill(s,p)or adapter.bondSet(s,cat,p,target)
        assert(type(r)=='table'and type(r.after)=='number'and math.abs(r.after-target)<0.01,'Progression readback did not match. Refresh before retrying.')
        return {before=p.current,after=r.after,maximum=p.maximum,backup=backup,role=p.role,rank=r.after_rank}
    end
    function api.action(id,args)
        if id=='cancel_quest'then job=nil;lastQuestResult={status='stopped',message='Quest completion cancelled; completed objectives remain saved.'};return true,lastQuestResult end
        local ok,r=pcall(mutate,id,args or{});if ok then return true,r end;return false,tostring(r)
    end
    function api.questState()local out={};for k,v in pairs(lastQuestResult or{status='idle'})do out[k]=v end;return out end
    function api.reset()
        if job then lastQuestResult={status='stopped',message='Quest completion stopped after a session or phase transition.'}end
        job=nil;previews,originals={},{};session=nil;return true
    end
    function api.tick(seconds)
        local ok,s=pcall(snapshot);if not ok then api.reset();return end
        if not job then return end
        local current=job
        local good,why=pcall(function()
            assert(supported('quests'),'Quest completion was disabled.')
            assert(current.session==session,'Selected quest belongs to another session.')
            local dt=type(seconds)=='number'and math.max(0,math.min(seconds,5))or 0.5
            current.total=current.total+dt;current.elapsed=current.elapsed+dt
            assert(current.total<=120 and current.steps<128,'Quest completion stopped at its safety limit; inspect the current objective.')
            if current.elapsed<0.5 then return end;current.elapsed=0
            local state=adapter.questProbe(s,current.entry)
            if state.quest_status==4 then
                lastQuestResult={status='complete',message='Quest turned in through the game reward pathway.',tag=current.entry.tag,steps=current.steps,backup=current.backup};job=nil
            elseif state.quest_status==3 then
                assert(state.result==1,'The selected quest did not succeed.')
                local r=adapter.questTurnIn(s,current.entry,state);assert(r.after==4,'Quest turn-in was not confirmed.')
                lastQuestResult={status='complete',message='Quest turned in through the game reward pathway.',tag=current.entry.tag,steps=current.steps,backup=current.backup};job=nil
            else
                assert(state.quest_status==2 and state.in_progress>0,'No active objective is ready. Resume the quest normally before retrying.')
                local r=adapter.questStep(s,current.entry,state);assert(r.stepped==1,'Objective completion was not confirmed.')
                current.steps=current.steps+1
                lastQuestResult={status='running',message='Advancing active quest objectives.',tag=current.entry.tag,steps=current.steps,backup=current.backup}
            end
        end)
        if not good then job=nil;lastQuestResult={status='stopped',message=tostring(why),tag=current.entry.tag,steps=current.steps,backup=current.backup}end
    end
    function api.shutdown()api.reset();closed=true;return true end
    return api
end
return M
