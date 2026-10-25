local frame=dofile('mods/ClanTools/Scripts/appearance_framing.lua').plan
local camera={X=-140,Y=0,Z=20};local point={X=0,Y=0,Z=20}
local small=assert(frame(camera,point,25,16/9,36,.55))
local large=assert(frame(camera,point,50,16/9,36,.55))
assert(math.abs(small.focal/large.focal-2)<1e-9)
for _,pair in ipairs({{small,25},{large,50}})do
 local p,height=pair[1],pair[2]
 local halfWidth=36*140/(2*p.focal)
 assert(math.abs(height/(2*halfWidth/(16/9))-.55)<1e-9)
 assert(math.abs(p.rightOffset/halfWidth-.52)<1e-9)
end
assert(not frame(camera,point,0,16/9,36,.55))
print('PASS kitten/adult size-independent coverage and consistent right-panel composition')
