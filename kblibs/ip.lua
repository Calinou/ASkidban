--[[

  ip/netrange object, ipset for matching ranges.

]]--

local fp, L = require"kblibs.fp", require"kblibs.lambda"
local map, pick, range, I = fp.map, fp.pick, fp.range, fp.I

local hasbit32, bit32, shift = pcall(L"require'bit32'")
local clearbits = hasbit32
  and function(ip, mask) local s = 32 - mask return bit32.lshift(bit32.rshift(ip, s), s) end
  or L"_1 - _1 % (2 ^ (32 - _2))"
local function matches(ipmask, ip) return clearbits(ip.ip, ipmask.mask) == ipmask.ip end
local function ipstring(ipmask)
  local ip, mask = ipmask.ip, ipmask.mask
  return string.format("%d.%d.%d.%d%s", math.modf(ip/0x1000000)%0x100, math.modf(ip/0x10000)%0x100, math.modf(ip/0x100)%0x100, ip%0x100, mask < 32 and ('/' .. mask) or '')
end
local function sameip(ip1, ip2) return ip1.ip == ip2.ip and ip1.mask == ip2.mask end

local function ip(desc, _mask)
  local ip, mask = 0
  if type(desc) == "string" then
    local octs = { desc:match("^([0-9]+)%.([0-9]+)%.([0-9]+)%.([0-9]+)(/?([0-9]*))$") }
    for i = 1, 4 do
      local o = tonumber(octs[i])
      if not o or o ~= math.floor(o) or o < 0 or o > 255 then return end
      ip = ip * 0x100 + o
    end
    if octs[5] ~= "" then mask = tonumber(octs[6]) end
  elseif type(desc) == "table" then ip, mask = desc.ip, desc.mask
  else
    if desc < 0 or desc > 0x100000000 or math.floor(desc) ~= desc then return end
    ip = desc
  end
  mask = _mask or mask or 32
  if mask < 0 or mask > 32 or math.floor(mask) ~= mask then return end
  return setmetatable({}, {__newindex = L"", __tostring = ipstring, __eq = sameip, __index =
    { ip = clearbits(ip, mask), mask = mask, matches = matches }
  })
end

--ipset

local function ipkey(ip, mask, shadow) return clearbits(ip, mask) * 0x80 + mask + (shadow and 0x40 or 0) end
local function keyip(key) return ip(math.modf(key / 0x80), key % 0x40) end

local function matcherof(ipset, ip)
  for mask = ip.mask, ipset.min, -1 do
    local key = ipkey(ip.ip, mask)
    local value = ipset[key]
    if value then return keyip(key), value end
  end
end

local function matchesof(ipset, ip)
  local matchestable = {}
  for key in pairs(ipset[ipkey(ip.ip, ip.mask, true)] or matchestable) do
    matchestable[keyip(key)] = ipset[key]
  end
  return matchestable
end

local function remove(ipset, ip)
  local realkey = ipkey(ip.ip, ip.mask)
  if not ipset[realkey] then return end
  for mask = ip.mask, ipset.min, -1 do
    local shadowkey = ipkey(ip.ip, mask, true)
    local shadowtable = ipset[shadowkey]
    shadowtable[realkey] = nil
    if not next(shadowtable) then ipset[shadowkey] = nil end
  end
  ipset[realkey] = nil
  return true
end

local function put(ipset, ip, value)
  assert(ip.mask >= ipset.min, "Cannot insert an ip with mask smaller than ipset.min")
  local matcher, matchervalue = matcherof(ipset, ip)
  if matcher then return false, { matcher = { matcher, matchervalue } } end
  local matches = matchesof(ipset, ip)
  if next(matches) then return false, matches end
  local realkey = ipkey(ip.ip, ip.mask)
  for mask = ip.mask, ipset.min, -1 do
    local shadowkey = ipkey(ip.ip, mask, true)
    local shadowtable = ipset[shadowkey] or {}
    shadowtable[realkey] = true
    ipset[shadowkey] = shadowtable
  end
  ipset[realkey] = value == nil and true or value
  return true
end

local function enum(ipset)
  return map.zf(function(key, value) return keyip(key), value end, pick.zp(L"_ % 0x80 < 0x40", ipset))
end

local function ipset(min)
  min = min ~= nil and tonumber(min) or 0
  assert(math.floor(min) == min and min >= 0 and min <= 32, "Invalid minimum mask specification")
  return setmetatable({}, {__index =
    { matcherof = matcherof, matchesof = matchesof, remove = remove, put = put, min = min, enum = enum }})
end

--lipset, does not check inconsistencies (overlaps, removing non existent ranges etc) and does not provide :matchesof

local function remove_l(ipset, ip)
  ipset[ipkey(ip.ip, ip.mask)] = nil
  return true
end

local function put_l(ipset, ip, value)
  ipset[ipkey(ip.ip, ip.mask)] = value == nil and true or value
  return true
end

local function enum_l(ipset)
  return map.zp(function(key, value) return keyip(key), value end, ipset)
end

local function ipset_l(min)
  min = min ~= nil and tonumber(min) or 0
  return setmetatable({}, {__index =
    { matcherof = matcherof, remove = remove_l, put = put_l, min = min, enum = enum_l }})
end

return {ip = ip, ipset = ipset, lipset = ipset_l}
