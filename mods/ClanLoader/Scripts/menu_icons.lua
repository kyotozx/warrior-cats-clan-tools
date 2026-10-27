-- Original mod emblems, imported only when a menu needs them.
local dir=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local M={}
function M.new(valid)
 local cache={}
 return function(name,owner)
  if type(name)~='string' or not name:match('^[a-z][a-z%-]*$')then return end
  local cached=cache[name]
  if cached==false then return end
  if cached and valid(cached)then return cached end
  local ok,texture=pcall(function()
   local lib=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary')
   assert(valid(lib),'Texture import library unavailable')
   local filename=(dir..'../assets/icons/'..name..'.png'):gsub('\\','/')
   return lib:ImportFileAsTexture2D(owner,filename)
  end)
  if ok and valid(texture)then cache[name]=texture;return texture end
  -- A missing icon must never prevent opening a menu or retry every frame.
  cache[name]=false
  print('[MenuIcons] Could not load '..name..': '..tostring(texture)..'\n')
 end
end
return M
