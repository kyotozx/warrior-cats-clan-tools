-- Native travel page; the host owns widgets, focus and parent navigation.
local M={}
function M.new(ctx,p)
 assert(ctx.admin and p.text and p.button and p.panel and p.refresh and p.notify,'Travel UI context required.')
 local api={};local rows,reason;local tab='clans';local page=1;local deleting
 local function load()
  local ok,a,b=pcall(ctx.admin.destinations)
  rows=ok and a and b or{};reason=not ok and tostring(a)or(not a and tostring(b)or nil)
 end
 local function apply(id,args)
  local ok,a,b=pcall(ctx.admin.action,id,args)
  p.notify(tostring(ok and b or a));load();p.refresh();return ok and a==true
 end
 local function switch(value)tab=value;page=1;deleting=nil;p.refresh()end
 local function create(c)
  if not p.prompt then return end
  p.prompt({title='Save this location',value='',maxLength=32,
   validate=function(value)
    if not value:match('^[%w _%-]+$')or not value:find('%S')or #value<1 or #value>32 then return false,'Use 1-32 letters, numbers, spaces, dashes or underscores.'end
    for _,row in ipairs(c.waypoints or{})do if row.name==value then return false,'This name is already saved. Choose another name.'end end
    return true
   end,
   accept=function(value)
    -- Validate against fresh state as well: never silently overwrite a bookmark.
    for _,row in ipairs(ctx.admin.capabilities().waypoints or{})do if row.name==value then return false,'This name is already saved. Choose another name.'end end
    local ok,a,b=pcall(ctx.admin.action,'save_waypoint',{name=value})
    if not ok or not a then return false,tostring(ok and b or a)end
    page=1;p.notify(b);p.refresh();return true,b
   end})
 end
 function api.page()
  if not rows then load()end
  local c=ctx.admin.capabilities();local permission=(c.actions or{}).teleport_destination
  local canTravel=c.available and not c.noclip
  p.text('Travel',430,135,1340,31,nil,true)
  p.text('Clan locations, your saved waypoints and the original world map.',432,192,1340,17)
  for i,entry in ipairs({{'clans','Clan locations'},{'waypoints','My waypoints'},{'map','World map travel'}})do
   p.button(entry[2],430+(i-1)*460,245,430,64,function()switch(entry[1])end,tab==entry[1])
  end
  p.panel(430,335,1350,480)
  if deleting then
   p.text('Delete waypoint?',465,370,1270,27,nil,true)
   p.text(deleting,465,433,1270,24)
   p.text('Only this saved location will be removed.',465,492,1270,18)
   p.button('Keep waypoint',465,610,600,84,function()deleting=nil;p.refresh()end)
   p.button('Delete waypoint',1110,610,635,84,function()local name=deleting;deleting=nil;apply('delete_waypoint',{name=name})end,false,c.available)
  elseif tab=='clans'then
   if reason then p.text(reason:sub(1,140),450,360,1290,18)
   elseif #rows==0 then p.text('No loaded clan spawn points are available.',450,360,1290,22)
   else for i,row in ipairs(rows)do if i<=4 then
    p.button(row.label,450,350+(i-1)*110,1310,88,function()apply('teleport_destination',{id=row.id})end,false,permission and permission.enabled and not c.noclip)
   end end end
  elseif tab=='waypoints'then
   local points=c.waypoints or{};local pages=math.max(1,math.ceil(#points/4));page=math.max(1,math.min(page,pages))
   if c.waypointError then p.text(tostring(c.waypointError):sub(1,140),450,355,1290,18)
   elseif #points==0 then
    p.text('Your places, one button away.',465,380,1250,27,nil,true)
    p.text('Save your current position with a name. Waypoints stay with this campaign and save slot.',465,455,1250,18)
   else for i=1,4 do local row=points[(page-1)*4+i];if row then
    p.button(row.name,450,350+(i-1)*96,960,78,function()apply('teleport_waypoint',{name=row.name})end,false,canTravel)
    p.button('Delete',1430,350+(i-1)*96,330,78,function()deleting=row.name;p.refresh()end,false,c.available)
   end end end
   p.button('Previous',450,747,300,56,function()page=page-1;p.refresh()end,false,page>1)
   p.text('Page '..page..' / '..pages,810,758,350,18)
   p.button('Next',1190,747,300,56,function()page=page+1;p.refresh()end,false,page<pages)
   p.button('Save current location',430,836,1350,62,function()create(c)end,false,c.available and not c.waypointError and #points<20 and p.prompt~=nil)
  else
   local status=ctx.mapTravel and ctx.mapTravel.status()or{verified=false}
   p.text('Choose a point on the original map',465,370,1270,27,nil,true)
   p.text('Close Clan Tools and open the world map with your normal map control.',465,435,1270,19)
   p.text('Move the native map pointer to your destination.',465,494,1270,19)
   p.text('Press F9 / L3 to preview. Release, then press again to travel.',465,553,1270,22)
   p.text('Moving the map cancels the preview. Only clear, loaded, walkable ground is allowed.',465,621,1270,18)
   p.text(status.verified and'Terrain and nearby encounters are checked again before travel.'or'Map travel is waiting for compatibility verification on this game build.',465,697,1270,18)
  end
  if tab~='waypoints'or deleting then
   local notice=c.noclip and'Turn noclip off before teleporting.'or not canTravel and'Travel is unavailable outside verified offline exploration.'or'The destination is checked again before every teleport.'
   p.text(notice,450,844,1290,17)
  end
  p.button('Return to previous position',430,914,860,62,function()apply('return_position')end,false,canTravel and c.hasReturn)
  p.button('Refresh locations',1320,914,460,62,function()load();p.refresh()end)
 end
 function api.back()
  if deleting then deleting=nil;p.refresh();return true end
  if tab~='clans'then switch('clans');return true end
  rows,reason=nil,nil;return false
 end
 function api.reset()rows,reason=nil,nil;tab='clans';page=1;deleting=nil end
 return api
end
return M
