-- Flight yaw fallback around the game's existing orbit camera. Keep its pitch,
-- collision arm, zoom and smoothing. Account for native yaw so input is not
-- applied twice when the exploration handler accepts it in MOVE_Flying.
local M={}
local function wrap(a)return(a+180)%360-180 end
local function rotation(r)return{pitch=r.pitch or r.Pitch,Yaw=r.Yaw,Roll=r.Roll}end
function M.new(ctx)
 local api={};local record
 local function alive(o)return o and ctx.valid(o)end
 function api.reset()
  if record and alive(record.camera)and record.camera:GetAddress()==record.address then
   record.camera:K2_SetActorRotation(record.original,true)
  end
  record=nil
 end
 function api.tick(s,axis,dt)
  if not s or s.offline~=true or s.phase~=4 or s.combat then api.reset();return end
  local camera=s.gameState and s.gameState.CameraActor
  if not alive(camera)or not alive(s.pc)then api.reset();return end
  local target=s.pc:GetViewTarget()
  if not alive(target)or target:GetAddress()~=camera:GetAddress()or s.pc:IsLookInputIgnored()then api.reset();return end
  if alive(camera.SplineActor)or alive(s.pawn.ActiveCameraSpline)then api.reset();return end
  local arm=camera.AdventureArmComponent
  if not alive(arm)then api.reset();return end
  if record and(record.address~=camera:GetAddress()or record.world~=s.worldId or record.pawn~=s.pawn:GetAddress())then api.reset()end
  local r=rotation(camera:K2_GetActorRotation())
  local native=wrap(arm:K2_GetComponentRotation().Yaw-r.Yaw)
  if not record then record={camera=camera,address=camera:GetAddress(),world=s.worldId,pawn=s.pawn:GetAddress(),original=r,native=native};return end
  local nativeDelta=wrap(native-record.native);record.native=native
  if axis==0 then return end
  local step=math.max(-1,math.min(1,axis))*100*math.max(0,math.min(dt or .016,.05))
  -- Ignore unrelated camera resets/large automatic turns. Small native motion
  -- in the requested direction counts toward the same requested orbit step.
  if nativeDelta*step>0 and math.abs(nativeDelta)<15 then step=step-nativeDelta end
  r.Yaw=wrap(r.Yaw+step)
  camera:K2_SetActorRotation(r,true)
 end
 return api
end
return M
