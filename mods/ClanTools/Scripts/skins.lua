local dir=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local storeModule=dofile(dir..'skin_store.lua')
local M={}
function M.new(ctx)
 local api={store=storeModule.new(ctx)}
 local native=dofile(dir..'appearance.lua').nativeTransport(ctx.root..'bin/',ctx.appearanceDllName)
 local function unpack(r,err)assert(r,err);return assert(dofile(dir..'appearance_library.lua').values(tostring(r.action):match('^COSMETICS%s+(.+)$')),'Invalid native skin.')end
 function api.current()local s=assert(ctx.snapshot(),'Load an offline player character.');assert(s.offline and not s.combat,'Skins require offline exploration.');return unpack(native('PLAYER_READ'))end
 function api.save(label)return api.store.save(label,api.current())end
 function api.preview(id,part)
  local e=assert(api.store.get(id),'Select a skin.');local values=storeModule.merge(api.current(),e.values,part or'All')
  return ctx.appearance.player(values)
 end
 function api.creatorRead(screen)return unpack(native(string.format('CREATOR_READ %x',screen:GetAddress())))end
 function api.creatorLoad(screen,id,part)
  local e=assert(api.store.get(id),'Select a skin.');local values=storeModule.merge(api.creatorRead(screen),e.values,part or'All')
  return native(string.format('CREATOR_LOAD %x %s',screen:GetAddress(),values))
 end
 return api
end
return M
