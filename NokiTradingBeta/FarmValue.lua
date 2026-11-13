-- Estimated AH value per observed corpse, assuming one item per recorded drop.
local core=NokiUnifiedCore
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
