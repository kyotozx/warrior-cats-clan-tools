-- Fit measured cat height into the right-hand preview area. Keeping this math
-- separate makes kitten/adult framing independent of an inventory lens preset.
local M={}
function M.plan(camera,point,height,aspect,sensor,fill)
 local dx,dy,dz=point.X-camera.X,point.Y-camera.Y,point.Z-camera.Z
 local distance=math.sqrt(dx*dx+dy*dy+dz*dz)
 if distance<1 or height<1 or aspect<.5 or sensor<1 then return nil end
 local halfWidth=height*aspect/(2*fill)
 local focal=math.max(10,math.min(300,sensor*distance/(2*halfWidth)))
 -- Recompute the offset after lens clamping so the cat stays in the right
 -- panel even at unusual viewport aspect ratios or extreme body sizes.
 return{focal=focal,rightOffset=.52*sensor*distance/(2*focal)}
end
return M
