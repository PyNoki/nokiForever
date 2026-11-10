-- The player installs AHledger separately; no sales snapshot is shipped by Noki.
-- AHledger's documented in-game API supplies market-wide estimates, not sales.
local function normalized(value)
  if type(value)~="string" then return nil end
  local s=value:lower():gsub("/", ".")
  if not s:match("^forever%.[%w_%-]+%.[%w_%-]+%.[%w_%-]+$") then return nil end
  return s
end
function NokiCraftingActivityMarket()
  if type(AHledgerAPI)~="table" or type(AHledgerAPI.GetMarket)~="function" or type(AHledgerAPI.GetPrice)~="function" then
    return nil,"Install or enable AHledger for estimated sales/day"
  end
  local ok,market=pcall(AHledgerAPI.GetMarket)
  market=ok and normalized(market) or nil
  if not market then return nil,"AHledger market unavailable; check /ahl status" end
  local _,ruleset,faction,region=market:match("^(forever)%.([%w_%-]+)%.([%w_%-]+)%.([%w_%-]+)$")
  local playerFaction=UnitFactionGroup and UnitFactionGroup("player")
  local playerRegion=GetCurrentRegion and GetCurrentRegion()
  local regions={[1]="us",[2]="kr",[3]="eu",[4]="tw",[5]="cn"}
  if type(playerFaction)~="string" or faction~=playerFaction:lower() or not regions[playerRegion] or region~=regions[playerRegion] then
    return nil,"AHledger market does not match player faction/region"
  end
  -- AHledger can be pinned to a different market. Only use it when the
  -- realm name explicitly identifies the same ruleset; do not guess Normal.
  local realm=GetRealmName and GetRealmName()
  if type(realm)~="string" then return nil,"Cannot verify realm type for AHledger market" end
  local words={}
  for word in realm:lower():gmatch("[%a]+") do words[word]=true end
  local hasPvp=words.pvp or words.jcj or words.jxj
  local hasRp=words.rp or words.jdr or words.gdr or words.rol
  local realmType
  if words.hardcore then realmType="hardcore"
  elseif words.rppvp then realmType="rppvp"
  elseif hasRp and hasPvp then realmType="rppvp"
  elseif hasPvp then realmType="pvp"
  elseif hasRp then realmType="rp"
  elseif words.normal or words.pve or words.jce or words.jve then realmType="normal" end
  if not realmType then return nil,"Cannot verify realm type; check AHledger market" end
  if realmType~=ruleset then return nil,"AHledger market does not match realm type" end
  return market
end
function NokiCraftingActivity(itemID, expectedMarket)
  local market,err=NokiCraftingActivityMarket()
  if not market or (expectedMarket and expectedMarket~=market) then return nil,err or "AHledger market changed" end
  local ok,price=pcall(AHledgerAPI.GetPrice,itemID)
  if not ok or type(price)~="table" then return nil,"No AHledger activity for item" end
  local recordMarket=normalized(price.market)
  if not recordMarket or recordMarket~=market then return nil,"AHledger item market mismatch" end
  local sales=price.soldPerDay
  if type(sales)~="number" or sales~=sales or sales<0 or sales==math.huge then return nil,"AHledger sales/day unknown" end
  -- GetPrice.updated can refer to the player's newer scan while sales/day
  -- still comes from the older price table. Use table metadata for activity.
  local tableInfo
  if type(AHledgerAPI.GetTableInfo)=="function" then
    local infoOK,info=pcall(AHledgerAPI.GetTableInfo)
    if infoOK and type(info)=="table" and normalized(info.market)==market then tableInfo=info end
  end
  local updated=tableInfo and tableInfo.updated
  if type(updated)~="number" or updated<=0 then updated=nil
  elseif updated>1000000000000 then updated=updated/1000 end
  local snapshot
  if tableInfo and type(tableInfo.snapshot)=="boolean" then snapshot=tableInfo.snapshot end
  return {sales=sales,market=market,observed=updated,snapshot=snapshot}
end
function NokiCraftingActivityLabel(row)
  if not row then return "AHledger unavailable" end
  local age="age ?"
  if row.observed then
    local now=(GetServerTime and GetServerTime()) or time()
    local minutes=math.max(0,math.floor((now-row.observed)/60))
    age=minutes.."m"..(minutes>=1440 and " STALE" or "")
  end
  return "AHledger "..row.market.." "..age..(row.snapshot==true and " SNAPSHOT" or (row.snapshot==nil and " SOURCE ?" or ""))
end
