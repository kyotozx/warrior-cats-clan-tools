-- Native authored lighting presets; this is not a simulated clock/weather system.
local M={}
function M.new(ctx)
 local api={};local desired='Automatic';local actor,world;local pending=false;local applied=false;local wasPaused=false
 local function restore()
  if ctx.valid(actor)and applied then actor:StopCinematicNight({TagName=FName('None')});actor:DoZoneDetectionFunction(false)end
  actor=nil;world=nil;applied=false
 end
 function api.status()return{mode=desired,pending=pending,applied=applied}end
 function api.set(mode)
  assert(mode=='Automatic'or mode=='Day'or mode=='Night','Unsupported sky preset.')
  local s=assert(ctx.snapshot(),'Load an offline campaign.');assert(s.offline and not s.combat and s.phase==4,'Lighting controls require offline exploration.')
  desired=mode;pending=true;return true
 end
 function api.tick(s)
  if not s or not s.offline or s.combat or s.phase~=4 or(world and world~=s.worldId)then
   restore();desired='Automatic';pending=false;return
  end
  local gameplay=StaticFindObject('/Script/Engine.Default__GameplayStatics')
  local paused=ctx.appearanceActive or(ctx.ui and ctx.ui.opened)or gameplay:IsGamePaused(s.gameState)
  if paused then wasPaused=true;return end
  if wasPaused then wasPaused=false;if applied then pending=true end end
  if not pending then return end
  restore();if desired=='Automatic'then pending=false;return end
  local candidates={}
  for _,a in ipairs(FindAllOf('BP_DayNightSky_C')or{})do
   if ctx.valid(a)and not a.IsUsedInMenu and not a.IsUsedInCatCreator then
    local level=a:GetLevel();if ctx.valid(level)and level.bIsVisible and ctx.valid(gameplay:GetGameState(a))and gameplay:GetGameState(a):GetAddress()==s.gs then candidates[#candidates+1]=a end
   end
  end
  assert(#candidates==1,'A single active gameplay sky is required.')
  actor=candidates[1];world=s.worldId
  -- Reuse the sky actor's own zone-detection blocker, released on restore.
  -- Without it the next zone update immediately replaces the requested sky.
  actor:OnStartCinematicNight();applied=true
  actor:ApplyStraight(desired=='Day'and 1 or 4);pending=false
 end
 function api.shutdown()restore();pending=false;desired='Automatic';return true end
 return api
end
return M
