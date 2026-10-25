local M={}
function M.new(ctx,p)
 local api={}
 local function configure(key,value)local ok,why=ctx.photoTools.configure(key,value);assert(ok,why);p.refresh()end
 function api.page()
  local r=ctx.photoTools.status();local s=r.settings
  p.text('Photo tools',430,135,1350,36,nil,true)
  p.text('Set your preferences here, then open Photo Mode from the original game menu.',432,198,1340,17)
  if ctx.skyTools then
   local sky=ctx.skyTools.status()
   p.button('Sky / Lighting: '..sky.mode..(sky.pending and' (on resume)'or''),1100,126,680,62,function()
    local nextMode=({Automatic='Day',Day='Night',Night='Automatic'})[sky.mode]
    ctx.skyTools.set(nextMode);p.refresh()
   end)
  end
  p.panel(430,280,1350,180);p.text('Field of view: '..(s.fov and tostring(s.fov)..'°'or'Game default'),460,300,1280,27,nil,true)
  p.button('− 5°',460,370,380,65,function()configure('fov',math.max(30,(s.fov or 70)-5))end,false,(s.fov or 70)>30)
  p.button('Use game default',870,370,440,65,function()configure('fov',nil)end)
  p.button('+ 5°',1340,370,410,65,function()configure('fov',math.min(110,(s.fov or 70)+5))end,false,(s.fov or 70)<110)
  p.panel(430,485,1350,180);p.text('Camera roll: '..s.roll..'°',460,505,1280,27,nil,true)
  p.button('− 5°',460,575,380,65,function()configure('roll',math.max(-30,s.roll-5))end,false,s.roll> -30)
  p.button('Level camera',870,575,440,65,function()configure('roll',0)end)
  p.button('+ 5°',1340,575,410,65,function()configure('roll',math.min(30,s.roll+5))end,false,s.roll<30)
  for i,row in ipairs({{'hideUI','Hide photo UI'},{'hideNames','Hide names'},{'freezeCharacters','Freeze characters'}})do
   p.button(row[2]..': '..(s[row[1]]and'On'or'Off'),430+(i-1)*458,715,434,85,function()configure(row[1],not s[row[1]])end,s[row[1]])
  end
  p.text(r.error or'Camera movement stays native. Exit Photo Mode to restore the scene and camera.',450,836,1300,18)
  p.button('Restore photo defaults',430,914,1350,62,function()local ok,why=ctx.photoTools.defaults();assert(ok,why);p.refresh()end)
 end
 return api
end
return M
