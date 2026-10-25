-- Optional exact-build native health adapter. Called only after admin's guard.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local M={}
local valid=dofile(folder..'runtime_valid.lua').valid
function M.new(bin,library)
    bin=bin or (folder..'../bin/')
    library=library or 'admin-heal.dll'
    local probe=assert(package.loadlib(bin..library,'ClanToolsHeal_probe'))
    local apply=assert(package.loadlib(bin..library,'ClanToolsHeal_apply'))
    local nonce=0
    local function invoke(s,mutate)
        assert(s and s.offline==true and s.phase==4,'Healing requires offline exploration.')
        local pawn=assert(s.pawn);assert(valid(pawn),'Player unavailable.')
        local class=StaticFindObject('/Script/SwtQuest.SwtQuestHealthComponent')
        assert(valid(class),'Health class unavailable.')
        local component=pawn:GetComponentByClass(class)
        assert(valid(component),'Player health component unavailable.')
        assert(component:GetOwner():GetAddress()==pawn:GetAddress(),'Health owner mismatch.')
        assert(component:GetClass():GetAddress()==class:GetAddress(),'Unsupported health component subclass.')
        nonce=nonce+1
        local request=assert(io.open(bin..'admin-heal-request.txt','wb'))
        assert(request:write(string.format('%d %x %x %x\n',nonce,component:GetAddress(),pawn:GetAddress(),class:GetAddress())))
        request:close()
        if mutate then apply() else probe() end
        local file=assert(io.open(bin..'admin-heal-status.txt','rb'));local text=file:read('*a');file:close()
        local result={};for key,value in text:gmatch('([%w_]+)=([^\r\n]+)')do result[key]=value end
        assert(tonumber(result.nonce)==nonce,'Stale health response.')
        assert(result.status==(mutate and 'HEALED' or 'READY'),result.status or 'Missing health response.')
        result.current=tonumber(result.current);result.maximum=tonumber(result.maximum);result.after=tonumber(result.after)
        return result
    end
    return {probe=function(s)return invoke(s,false)end,heal=function(s)invoke(s,true);return true end}
end
return M
