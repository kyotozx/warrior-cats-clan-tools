-- Reviewed, den-only recipes. Completed items enter the original inventory;
-- decorations can then be placed using the game's existing den customization.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local json=dofile(folder..'json.lua')
local crafting=dofile(folder..'crafting.lua')
local M={}
local function int(n,lo,hi)return type(n)=='number'and n%1==0 and n>=lo and n<=hi end
local function copy(v)if type(v)~='table'then return v end;local r={};for k,x in pairs(v)do r[k]=copy(x)end;return r end
function M.parse(text,nonce,command)
 assert(type(text)=='string'and #text<4096,'Invalid workshop response.')
 local r={};for line in text:gmatch('[^\r\n]+')do local k,v=line:match('^(%w+)=(.+)$');assert(k and not r[k],'Malformed workshop response.');r[k]=v end
 assert(tonumber(r.nonce)==nonce,'Stale workshop response.')
 assert(r.status==(command=='CRAFT'and'APPLIED'or'READY'),r.status or'Missing workshop response.')
 for _,k in ipairs({'current','after','allowed','mutated','cost1','cost2','cost3','cost4','need1','need2','need3','need4'})do r[k]=tonumber(r[k]);assert(int(r[k],0,100000000),'Invalid workshop count.')end
 assert(r.allowed<=3 and r.mutated<=1 and r.stamp and r.stamp:match('^%x+$')and #r.stamp<=16,'Invalid workshop state.')
 return r
end
function M.nativeAdapter(ctx)
 local bin=ctx.root..'bin/';local dispatch;local nonce=os.time()*1000
 local function addr(o)assert(ctx.valid(o),'Workshop object unavailable.');return o:GetAddress()end
 local function objects(s,den)
  local owner=s.pc.PlayerState;local component=owner.InventoryComponent
  local cls=StaticFindObject('/Script/Wrc.WrcInventoryComponent');local manager=FindFirstOf('WrcSaveManager')
  assert(addr(component:GetClass())==addr(cls)and addr(component:GetOwner())==addr(owner),'Inventory owner changed.')
  return{addr(component),addr(owner),addr(cls),addr(manager),addr(den)}
 end
 local function invoke(s,den,command,index,quantity,free,stamp,identity)
  local o=objects(s,den);assert(table.concat(o,':')==identity,'Workshop identity changed.')
  assert(int(index,1,189)and int(quantity,1,99)and type(free)=='boolean','Invalid workshop request.')
  stamp=stamp or'0';assert(stamp:match('^%x+$')and #stamp<=16,'Invalid preview stamp.')
  if not dispatch then dispatch=assert(package.loadlib(bin..'workshop.dll','ClanWorkshop_run'))end
  nonce=nonce+1
  local f=assert(io.open(bin..'workshop-request.txt','wb'))
  assert(f:write(string.format('%d %s %x %x %x %x %x %d %d %d %s\n',nonce,command,o[1],o[2],o[3],o[4],o[5],index,quantity,free and 1 or 0,stamp)));assert(f:close())
  dispatch();f=assert(io.open(bin..'workshop-status.txt','rb'));local raw=f:read('*a');f:close();return M.parse(raw,nonce,command)
 end
 return{identity=function(s,den)return table.concat(objects(s,den),':')end,
  probe=function(s,d,i,q,f,id)return invoke(s,d,'PROBE',i,q,f,nil,id)end,
  craft=function(s,d,i,q,f,stamp,id)return invoke(s,d,'CRAFT',i,q,f,stamp,id)end}
end
function M.new(ctx)
 local api={};local adapter=ctx.workshopAdapter or M.nativeAdapter(ctx)
 local catalog=ctx.workshopCatalog or json.decode(assert(ctx.read(ctx.root..'data/workshop.json')))
 assert(type(catalog)=='table'and #catalog>0,'Workshop catalog unavailable.')
 local byIndex={};for i,e in ipairs(catalog)do
  assert(e.index==i and type(e.name)=='string'and e.tag:match('^Gameplay%.Inventory%.')and type(e.costs)=='table'and #e.costs<=4,'Invalid workshop catalog.')
  byIndex[i]=e
 end
 local pending,sequence,closed=nil,0,false;local now=ctx.now or os.time
 local function current()
  assert(not closed,'Workshop is closed.')
  local s=ctx.snapshot();assert(s and s.offline==true and s.phase==4 and not s.combat and not ctx.appearanceActive,'Workshop requires offline exploration.')
  assert(ctx.valid(s.pawn)and ctx.valid(s.pc)and type(s.profile)=='string'and int(s.slot,0,99),'Active save unavailable.')
  local den=(ctx.workshopDiscover or crafting.discover)(s)
  assert(den and den.actors and den.actors[1],'Enter your den to use the workshop.')
  local actor=den.actors[1];local identity=adapter.identity(s,actor)
  local key=table.concat({s.profile,s.slot,s.chapter or'',s.worldId or'',den.session,identity,tostring(s.pawn:GetAddress())},'|')
  return s,actor,identity,key
 end
 function api.available()local ok,why=pcall(current);return ok,ok and'Ready in your den.'or tostring(why)end
 function api.catalog(query,category)
  local rows={};query=tostring(query or''):lower()
  for _,e in ipairs(catalog)do if(not category or category=='all'or category==e.category)and(query==''or e.name:lower():find(query,1,true))then rows[#rows+1]=copy(e)end end
  table.sort(rows,function(a,b)return a.name<b.name end);return rows
 end
 function api.cancel()pending=nil;return true end
 function api.preview(index,quantity,free)
  pending=nil
  local ok,result=pcall(function()
   assert(int(quantity,1,99)and type(free)=='boolean','Choose a quantity from 1 to 99.')
   local e=assert(byIndex[index],'Choose an item.');local s,d,id,key=current()
   local r=adapter.probe(s,d,index,quantity,free,id)
   assert(int(r.current,0,100000000)and int(r.allowed,0,3)and type(r.stamp)=='string','Invalid recipe preview.')
   sequence=sequence+1
   local p={token=tostring(sequence),entry=copy(e),quantity=quantity,free=free,current=r.current,after=r.current+quantity,
    allowed=r.allowed==1,reason=({[0]='Not enough inventory space.',[1]='Ready to craft.',[2]='Not enough materials.',[3]='No original recipe. Switch to Free crafting.'})[r.allowed],costs={},stamp=r.stamp,session=key,identity=id,created=now()}
   for i,cost in ipairs(e.costs)do local row=copy(cost);row.current=r['cost'..i];row.need=free and 0 or cost.quantity*quantity;p.costs[#p.costs+1]=row end
   pending=p;return copy(p)
  end)
  return ok,ok and result or tostring(result)
 end
 function api.apply(token)
  local p=pending;pending=nil;local attempted=false;local backup
  local ok,result=pcall(function()
   assert(ctx.workshopVerified==true,'Workshop is awaiting validation.')
   assert(p and token==p.token,'Review the recipe again before crafting.')
   assert(p.allowed and now()>=p.created and now()-p.created<=60,'Recipe preview expired or requirements are not met.')
   local s,d,id,key=current();assert(key==p.session and id==p.identity,'Your den or active save changed.')
   local function check()
    local r=adapter.probe(s,d,p.entry.index,p.quantity,p.free,id)
    assert(r.allowed==1 and r.stamp==p.stamp,'Inventory changed. Review the recipe again.')
   end
   check();backup=ctx.backupSave(s);assert(type(backup)=='string'and #backup>0,'Save backup failed.')
   s,d,id,key=current();assert(key==p.session and id==p.identity and ctx.workshopVerified==true,'Workshop context changed during backup.');check()
   attempted=true
   local r=adapter.craft(s,d,p.entry.index,p.quantity,p.free,p.stamp,id)
   assert(r.after==p.after and r.current==p.current,'Crafted quantity was not confirmed.')
   return{complete=true,message='Crafted '..p.quantity..' × '..p.entry.name..'.',entry=p.entry,after=r.after,backup=backup}
  end)
  if ok then return true,result end
  return false,{complete=false,message=(attempted and'Crafting stopped; inventory may have changed. Check quantities before retrying. 'or'')..tostring(result),uncertain=attempted,backup=backup}
 end
 function api.shutdown()pending=nil;closed=true;return true end
 return api
end
return M
