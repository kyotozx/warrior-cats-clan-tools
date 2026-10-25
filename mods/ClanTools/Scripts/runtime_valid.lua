-- UE4SS UObject:IsValid only checks registration/unreachable state. It may
-- remain true for destroyed actors; call Engine IsValid before dereferencing.
local M={};local system,check
function M.valid(object)
    if object==nil then return false end
    local ok,result=pcall(function()
        if object:IsValid()~=true then return false end
        -- Lua ownership wrappers and test fixtures implement their own lifetime.
        if type(object)=='table' then return true end
        if type(StaticFindObject)~='function' then return false end
        if not system or not system:IsValid() then system=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')end
        if not check or not check:IsValid() then check=StaticFindObject('/Script/Engine.KismetSystemLibrary:IsValid')end
        if not system or not system:IsValid() or not check or not check:IsValid() then return false end
        -- Function-first invokes UFunction.__call with explicit calling context.
        -- Context-first CallFunction is broken in this UE4SS source: it tests
        -- derives_from_function(), but UFunction overrides derives_from_ufunction().
        -- system:IsValid(object) would hit UE4SS's shadowing helper instead.
        return check(system,object)==true
    end)
    return ok and result==true
end
return M
