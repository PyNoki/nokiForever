-- Estimated AH value per observed corpse, assuming one item per recorded drop.
local core=NokiUnifiedCore
-- Forever client Group Finder zone brackets, build 1.60.1.70888.
-- https://forevermastery.com/en/tools/world-map
-- Zephras 1-12: Blizzard's Skyborne starting-zone guidance.
local zoneLevels={
  ['Durotar']={1,14},['Mulgore']={1,14},['Teldrassil']={1,14},['Dun Morogh']={1,14},['Elwynn Forest']={1,14},['Tirisfal Glades']={1,14},['Zephras Isle']={1,12},
  ['Darkshore']={8,24},['The Barrens']={8,30},['Loch Modan']={8,24},['Silverpine Forest']={8,24},['Westfall']={8,24},
  ['Stonetalon Mountains']={13,32},['Redridge Mountains']={13,30},['Ashenvale']={18,34},['Duskwood']={18,34},['Hillsbrad Foothills']={18,34},['Wetlands']={18,34},
  ['Thousand Needles']={23,40},['Desolace']={28,44},['Alterac Mountains']={28,44},['Arathi Highlands']={28,44},['Stranglethorn Vale']={28,50},
  ['Dustwallow Marsh']={33,50},['Badlands']={33,50},['Swamp of Sorrows']={33,50},['Riverglades']={33,54},
  ['Feralas']={38,54},['Tanaris']={38,54},['The Hinterlands']={38,54},['Azshara']={43,60},['Blasted Lands']={43,60},['Searing Gorge']={43,60},
  ["Un'Goro Crater"]={45,60},['Felwood']={46,60},['Burning Steppes']={48,60},['Western Plaguelands']={48,60},['Eastern Plaguelands']={53,60},['Silithus']={53,60},['Winterspring']={53,60},['Mount Hyjal']={55,60},
}
function core.FarmZoneLevel(mob)
  local zone=mob and zoneLevels[mob.zone]
  if zone then return zone[1],zone[2] end
end
-- A conservative score, not a measured probability: assume homogeneous items,
-- a stable pool of competing listings and Poisson sales distributed evenly.
-- The 90% one-sided Wilson lower bound reduces sensitivity to tiny samples.
function core.FarmDropScore(drop,market)
  if type(drop[8])~='number' then return nil,'rate' end
  if not market or type(market.price)~='number' or market.price<=0 then return nil,'price' end
  local a=market.activity
  if not a or type(a.sales)~='number' or a.sales<0 then return nil,'activity' end
  local saleWeight
  if a.sales==0 then saleWeight=0
  elseif type(market.listed)=='number' and market.listed>=0 then saleWeight=1-math.exp(-a.sales/(market.listed+1))
  else return nil,'supply' end
  local hits,samples=drop[2],drop[3]
  if type(hits)~='number' or type(samples)~='number' or samples<=0 or hits<0 or hits>samples then return nil,'sample' end
  local p=hits/samples;local z=1.2815515655;local z2=z*z
  local lower=(p+z2/(2*samples)-z*math.sqrt((p*(1-p)+z2/(4*samples))/samples))/(1+z2/samples)
  lower=math.max(0,math.min(1,lower))
  return lower*market.price*.95*saleWeight,nil,saleWeight,lower
end
function core.FarmValue(mob,getMarket)
  local gross,score,priced,scored,missingPrice,missingRate,missingActivity,missingSupply,missingSample,stale=0,0,0,0,0,0,0,0,0,0
  for _,drop in ipairs(mob.drops or {}) do
    if type(drop[8])~='number' then missingRate=missingRate+1
    else
      local market=getMarket(drop[1])
      if market and type(market.price)=='number' and market.price>0 then gross=gross+market.price*drop[8]/100;priced=priced+1 else missingPrice=missingPrice+1 end
      local value,reason=core.FarmDropScore(drop,market)
      if value~=nil then
        score=score+value;scored=scored+1
        local a=market.activity;local now=(GetServerTime and GetServerTime()) or time()
        if not a.observed or now-a.observed>=86400 then stale=stale+1 end
      elseif reason=='activity' then missingActivity=missingActivity+1
      elseif reason=='supply' then missingSupply=missingSupply+1
      elseif reason=='sample' then missingSample=missingSample+1 end
    end
  end
  return {value=scored>0 and score or nil,gross=priced>0 and gross or nil,missingPrice=missingPrice,missingRate=missingRate,missingActivity=missingActivity,missingSupply=missingSupply,missingSample=missingSample,stale=stale,priced=priced,scored=scored}
end
function core.FarmInZone(mob,zone)
  if type(zone)~='string' or zone=='' then return false end
  zone=zone:lower()
  if type(mob.zone)=='string' and mob.zone:lower()==zone then return true end
  for _,location in ipairs(mob.locations or {}) do
    local name=location:match('^(.-) %- ') or location
    if name:lower()==zone then return true end
  end
  return false
end
