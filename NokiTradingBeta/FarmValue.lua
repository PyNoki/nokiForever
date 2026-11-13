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
function core.FarmValue(mob,getPrice)
  local total,priced,missingPrice,missingRate=0,0,0,0
  for _,drop in ipairs(mob.drops or {}) do
    if type(drop[8])~='number' then missingRate=missingRate+1
    else
      local unit=getPrice(drop[1])
      if type(unit)=='number' and unit>0 then total=total+unit*drop[8]/100;priced=priced+1
      else missingPrice=missingPrice+1 end
    end
  end
  return {value=priced>0 and total or nil,missingPrice=missingPrice,missingRate=missingRate,priced=priced}
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
