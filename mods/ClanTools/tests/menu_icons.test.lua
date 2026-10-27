local calls=0;local broken=false;local lastPath
local lib={valid=true}
function lib:ImportFileAsTexture2D(owner,path,...)
 assert(select('#',...)==0,'Native import expects exactly two arguments')
 assert(owner=='menu');calls=calls+1;lastPath=path
 if broken then error('missing file')end
 return{valid=true}
end
function StaticFindObject()return lib end
local get=dofile('mods/ClanTools/Scripts/menu_icons.lua').new(function(o)return type(o)=='table'and o.valid end)
local first=get('clan-tools','menu');assert(first and calls==1)
assert(get('clan-tools','menu')==first and calls==1,'Refresh must reuse the texture')
assert(lastPath:match('/assets/icons/clan%-tools%.png$'))
first.valid=false;assert(get('clan-tools','menu')~=first and calls==2,'Garbage-collected textures must be reloaded')
assert(get('../outside','menu')==nil and calls==2)
broken=true;assert(get('missing','menu')==nil and calls==3)
assert(get('missing','menu')==nil and calls==3,'Missing art must not retry on every refresh')
print('PASS menu icon reuse, expired texture recovery, missing art and contained filenames')
