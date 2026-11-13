-- Read-only buyout analysis. Never place bids or buy items.
local core=NokiUnifiedCore
local pending
local function now() return (GetServerTime and GetServerTime()) or time() end
local function finish(result,err)
  local request=pending;pending=nil;core.SetWorking("buyout",false)
  if request and request.callback then request.callback(result,err) end
end
local function keyEqual(a,b)
  return a and b and a.itemID==b.itemID and (a.itemLevel or 0)==(b.itemLevel or 0) and (a.itemSuffix or 0)==(b.itemSuffix or 0) and (a.battlePetSpeciesID or 0)==(b.battlePetSpeciesID or 0)
end
-- Tiers must include all offers at a price before using the next price as a benchmark.
function core.CalculateBuyout(offers)
  table.sort(offers,function(a,b) return a.price<b.price end)
  local tiers={}
  for _,offer in ipairs(offers) do
    local tier=tiers[#tiers]
    if not tier or tier.price~=offer.price then tier={price=offer.price,quantity=0};tiers[#tiers+1]=tier end
    tier.quantity=tier.quantity+offer.quantity
  end
  local total,cost,best=0,0,nil
  for i,tier in ipairs(tiers) do
    total=total+tier.quantity;cost=cost+tier.price*tier.quantity
    tier.totalQuantity=total;tier.totalCost=cost
    local nextTier=tiers[i+1]
    if nextTier and nextTier.price>1 then
      tier.nextPrice=nextTier.price;tier.nextQuantity=nextTier.quantity;tier.resell=math.ceil(nextTier.price)-1
      tier.net=math.floor(tier.resell*total*.95);tier.profit=tier.net-cost
      if tier.profit>0 and (not best or tier.profit>best.profit) then best=tier end
    end
  end
  return {tiers=tiers,totalQuantity=total,totalCost=cost,best=best}
end
local function collect()
  local p=pending;if not p or not p.seen then return end
  local api=C_AuctionHouse
  local full=p.commodity and api.HasFullCommoditySearchResults and api.HasFullCommoditySearchResults(p.key.itemID) or (not p.commodity and api.HasFullItemSearchResults and api.HasFullItemSearchResults(p.key))
  if not full then
    if not p.requested and (not api.IsThrottledMessageSystemReady or api.IsThrottledMessageSystemReady()) then
      local more=p.commodity and api.RequestMoreCommoditySearchResults or api.RequestMoreItemSearchResults
      if not more then finish(nil,"Cannot load all price tiers.");return end
      local ok=pcall(more,p.commodity and p.key.itemID or p.key);if not ok then finish(nil,"Could not load more price tiers.");return end;p.requested=true
    end
    return
  end
  local count=p.commodity and api.GetNumCommoditySearchResults or api.GetNumItemSearchResults
  local get=p.commodity and api.GetCommoditySearchResultInfo or api.GetItemSearchResultInfo
  if not count or not get then finish(nil,"Price-tier data unavailable.");return end
  local arg=p.commodity and p.key.itemID or p.key;local offers={}
  for i=1,count(arg) do
    local info=get(arg,i)
    if not info then finish(nil,"Price-tier data is incomplete.");return end
    local quantity=info.quantity
    local price=p.commodity and info.unitPrice or core.ItemSearchUnitPrice(p.key.itemID,info.buyoutAmount,quantity)
    local owned=info.containsOwnerItem or info.containsAccountItem
    local bidOnly=p.vendorCeiling and not p.commodity and (type(info.buyoutAmount)~="number" or info.buyoutAmount<=0)
    if not bidOnly then
      if type(quantity)~="number" or quantity<=0 or type(price)~="number" or price<=0 then finish(nil,"Some listings lack a reliable unit price or buyout.");return end
      if owned and (not p.vendorCeiling or price<p.vendorCeiling) then finish(nil,"Your/account listings are mixed into these results; buyout totals are unavailable.");return end
      if not owned then offers[#offers+1]={price=price,quantity=quantity} end
    end
  end
  if #offers==0 then finish(nil,"No buyout listings found.");return end
  local result=core.CalculateBuyout(offers);result.checked=now();finish(result)
end
local function tryStart()
  local p=pending
  if not p or p.started or core.phase~="idle" or (core.IsCompetitionSearchActive and core.IsCompetitionSearchActive()) then return end
  local api=C_AuctionHouse
  if api.IsThrottledMessageSystemReady and not api.IsThrottledMessageSystemReady() then return end
  local okInfo,info=pcall(api.GetItemKeyInfo,p.key)
  if not okInfo or type(info)~="table" or type(info.isCommodity)~="boolean" then
    p.detailsStarted=p.detailsStarted or now()
    if not p.requestedItem and C_Item and C_Item.RequestLoadItemDataByID then p.requestedItem=true;pcall(C_Item.RequestLoadItemDataByID,p.key.itemID) end
    if now()-p.detailsStarted>15 then finish(nil,"Item details did not load; try again.") end
    return
  end
  p.commodity=info.isCommodity;p.started=now()
  local ok=pcall(api.SendSearchQuery,p.key,{},true)
  if not ok then finish(nil,"Could not request price tiers.") end
end
function core.CheckBuyout(key,callback,options)
  if not core.active or not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return false,"Open the auction house first." end
  if pending then return false,"Another price check is running; try again shortly." end
  local api=C_AuctionHouse
  if not api or not api.SendSearchQuery or not api.GetItemKeyInfo then return false,"Auction search is unavailable." end
  local ceiling=type(options)=="table" and options.vendorCeiling
  if type(ceiling)~="number" or ceiling<=0 then ceiling=nil end
  pending={key=key,queued=now(),callback=callback,vendorCeiling=ceiling};core.SetWorking("buyout",true)
  tryStart()
  return true
end
function core.CancelQueuedBuyout(reason)
  if not pending or pending.started then return false end
  finish(nil,reason or "Price check cancelled.");return true
end
local events=CreateFrame("Frame")
for _,event in ipairs({"COMMODITY_SEARCH_RESULTS_UPDATED","COMMODITY_SEARCH_RESULTS_ADDED","ITEM_SEARCH_RESULTS_UPDATED","ITEM_SEARCH_RESULTS_ADDED","AUCTION_HOUSE_CLOSED"}) do pcall(events.RegisterEvent,events,event) end
events:SetScript("OnEvent",function(_,event,arg)
  if event=="AUCTION_HOUSE_CLOSED" then if pending then finish(nil,"Auction house closed.") end;return end
  local p=pending;if not p or not p.started then return end
  if (p.commodity and (event=="COMMODITY_SEARCH_RESULTS_UPDATED" or event=="COMMODITY_SEARCH_RESULTS_ADDED") and arg==p.key.itemID) or (not p.commodity and (event=="ITEM_SEARCH_RESULTS_UPDATED" or event=="ITEM_SEARCH_RESULTS_ADDED") and keyEqual(arg,p.key)) then p.seen=true;p.requested=false;collect() end
end)
local elapsed=0;events:SetScript("OnUpdate",function(_,delta)
  if not pending then return end;elapsed=elapsed+delta;if elapsed<.5 then return end;elapsed=0
  if not pending.started then
    if now()-pending.queued>240 then finish(nil,"Price check waited too long; try again.") else tryStart() end
  elseif now()-pending.started>45 then finish(nil,"Price check timed out; try again.") else collect() end
end)
