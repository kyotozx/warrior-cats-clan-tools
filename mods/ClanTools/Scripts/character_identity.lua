-- A slot number can be reused after deletion. Only the game's existing live
-- generation may identify character-owned sidecars; never synthesize one.
local M={}
-- Keep all generation bits, but avoid MAX_PATH at the default Steam location.
-- Logical identities remain unchanged; only filenames use this compact form.
function M.fileKey(key)
 assert(type(key)=='string','Invalid character file identity.')
 local prefix,hash=key:match('^([%w_-]+_%d+)_(%x+)$')
 assert(prefix and hash and #hash==64,'Invalid character file identity.')
 local bytes=hash:gsub('%x%x',function(pair)return string.char(tonumber(pair,16))end)
 -- A single-case alphabet is essential on Windows: base64 would make distinct
 -- hashes collide when their encodings differ only by letter case.
 local alphabet='abcdefghijklmnopqrstuvwxyz234567'
 local out,bits,value={},0,0
 for i=1,#bytes do
  value=value*256+bytes:byte(i);bits=bits+8
  while bits>=5 do
   bits=bits-5;local divisor=2^bits;local index=value//divisor
   out[#out+1]=alphabet:sub(index+1,index+1);value=value%divisor
  end
 end
 if bits>0 then local index=value*2^(5-bits);out[#out+1]=alphabet:sub(index+1,index+1)end
 return prefix..'_'..table.concat(out)
end
function M.new(readGeneration)
 local memo=setmetatable({},{__mode='k'})
 return function(s)
  if type(s)~='table'or s.offline~=true or type(s.profile)~='string'or not s.profile:match('^[%w_-]+$')or #s.profile>128 or type(s.slot)~='number'or s.slot%1~=0 or s.slot<0 then return nil,'Load an offline campaign.'end
  local previous=memo[s]
  if previous and previous.profile==s.profile and previous.slot==s.slot then return previous.key,previous.error end
  local ok,result,why=pcall(readGeneration)
  local profile,slot,hash
  if ok and type(result)=='table'then profile,slot,hash=tostring(result.action):match('^GENERATION profile=([%w_-]+) slot=(%d+) hash=(%x+)$')end
  local key
  if profile==s.profile and tonumber(slot)==s.slot and hash and #hash==64 then key=s.profile..'_'..s.slot..'_'..hash:lower()end
  local err=not key and (ok and why or nil)or nil
  if not key then err=err or'Character identity is unavailable. Reload your campaign before changing saved settings.'end
  memo[s]={profile=s.profile,slot=s.slot,key=key,error=err}
  return key,err
 end
end
return M
