local ADDON = ...
local frame = CreateFrame("Frame")
local houseOpen = false
local elapsed = 0
local SAMPLE_INTERVAL = 300
local MAX_SAMPLES = 500
local db, market

local function say(message) print("|cff33ccffNoki Market:|r " .. message) end
local function now() return (GetServerTime and GetServerTime()) or time() end
local function marketKey()
  local realm = (GetRealmName and GetRealmName()) or "Unknown realm"
  local faction = (UnitFactionGroup and UnitFactionGroup("player")) or "Unknown faction"
  return realm .. " - " .. faction
end
local function initialize()
  NokiMarketDB = NokiMarketDB or {}
  db = NokiMarketDB
  db.schema = 1
  if db.autoScan == nil then db.autoScan = true end
  if not db.rotationSetup then db.scanIntervalMinutes = 5; db.rotationSetup = true end
  db.scanIntervalMinutes = math.max(1, tonumber(db.scanIntervalMinutes) or 5)
  db.itemCatalog = db.itemCatalog or {}
  db.vendorOffers = db.vendorOffers or {}
  db.markets = db.markets or {}
  local key = marketKey()
  db.markets[key] = db.markets[key] or {watch = {}, items = {}}
  market = db.markets[key]
  market.watch = market.watch or {}
  market.items = market.items or {}
end
local nameQueue, nameIndex, nameSeen = {}, 1, {}
local merchantOpen = false
local catalogElapsed = 0
local function catalogItem(id)
  if not id then return end
  local key = tostring(id)
  db.itemCatalog[key] = db.itemCatalog[key] or {}
  return db.itemCatalog[key]
end
local function updateItemInfo(id)
  if not db or not id or not C_Item or not C_Item.GetItemInfo then return end
  local values = {pcall(C_Item.GetItemInfo, id)}
  if not values[1] then return end
  local item = catalogItem(id)
  if type(values[2]) == "string" then item.name = values[2] end
  if type(values[12]) == "number" then item.vendorSell = values[12] end
  if type(values[9]) == "number" and values[9] > 0 then item.maxStack = values[9] end
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if api and api.GetVendorPriceByItemID then
    local ok, price = pcall(api.GetVendorPriceByItemID, ADDON, id)
    if ok and type(price) == "number" and price > 0 then item.auctionatorVendorBuy = price end
  end
end
local function queueItem(id)
  if type(id) ~= "number" or nameSeen[id] then return end
  nameSeen[id] = true; nameQueue[#nameQueue + 1] = id
end
local function captureMerchant()
  if not merchantOpen or not db or not GetMerchantNumItems then return end
  local ok, count = pcall(GetMerchantNumItems)
  if not ok or type(count) ~= "number" then return end
  local merchantName = UnitName("npc") or "Unknown vendor"
  local guid = UnitGUID and UnitGUID("npc") or "unknown"
  local zone = GetRealZoneText and GetRealZoneText() or "Unknown zone"
  for i = 1, count do
    local success, info
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then success, info = pcall(C_MerchantFrame.GetItemInfo, i) end
    local idOK, id = pcall(GetMerchantItemID, i)
    if success and type(info) == "table" and idOK and type(id) == "number" then
      local item = catalogItem(id)
      if type(info.name) == "string" then item.name = info.name end
      queueItem(id)
      local key = marketKey() .. "|" .. tostring(guid) .. "|" .. id
      local offer = {itemID = id, market = marketKey(), vendor = merchantName, vendorGUID = guid, zone = zone, observed = now(), price = info.price, stack = info.stackCount, available = info.numAvailable, purchasable = info.isPurchasable, extended = info.hasExtendedCost, currencyID = info.currencyID}
      db.vendorOffers[key] = offer
    end
  end
end
local function itemRecord(id)
  local key = tostring(id)
  market.items[key] = market.items[key] or {samples = {}}
  return market.items[key]
end
local function record(id, sample)
  local item = itemRecord(id)
  item.samples = item.samples or {}
  local samples = item.samples
  -- Repeat events often describe the same result. Keep changed values or a five-minute heartbeat.
  local last = samples[#samples]
  if sample.source ~= "item_search" and last and last.source == sample.source and last.price == sample.price and last.quantity == sample.quantity and last.complete == sample.complete and sample.time - last.time < SAMPLE_INTERVAL then return false end
  samples[#samples + 1] = sample
  if #samples > MAX_SAMPLES then table.remove(samples, 1) end
  return true
end
local function auctionatorSample(id)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not api or not api.GetAuctionPriceByItemID then return false end
  local ok, price = pcall(api.GetAuctionPriceByItemID, ADDON, id)
  if not ok or type(price) ~= "number" or price <= 0 then return false end
  local age
  if api.GetAuctionAgeByItemID then
    local ageOK, value = pcall(api.GetAuctionAgeByItemID, ADDON, id)
    if ageOK and type(value) == "number" then age = value end
  end
  return record(id, {time = now(), source = "auctionator_cache", price = price, ageDays = age})
end
local function sampleWatch()
  local count = 0
  for key in pairs(market.watch) do
    if auctionatorSample(tonumber(key)) then count = count + 1 end
  end
  return count
end
local function saveDetail(id, kind, key, rows, complete)
  table.sort(rows, function(a,b) return a.unitPrice < b.unitPrice end)
  while #rows > 5 do table.remove(rows) end
  market.details = market.details or {}
  market.details[#market.details + 1] = {time = now(), itemID = id, kind = kind, itemKey = key, complete = complete, rows = rows}
end
local function collectCommodity(id)
  local ah = C_AuctionHouse
  if not id or not ah or not ah.GetNumCommoditySearchResults or not ah.GetCommoditySearchResultInfo then return end
  local ok, count = pcall(ah.GetNumCommoditySearchResults, id)
  if not ok or type(count) ~= "number" or count == 0 then return end
  local quantity, lowest, detailRows = 0, nil, {}
  for i = 1, count do
    local success, row = pcall(ah.GetCommoditySearchResultInfo, id, i)
    if not success or type(row) ~= "table" or type(row.quantity) ~= "number" or type(row.unitPrice) ~= "number" then return end
    quantity = quantity + row.quantity
    if row.unitPrice > 0 then detailRows[#detailRows + 1] = {unitPrice = row.unitPrice, quantity = row.quantity} end
    if row.unitPrice > 0 and (not lowest or row.unitPrice < lowest) then lowest = row.unitPrice end
  end
  local complete = false
  if ah.HasFullCommoditySearchResults then
    local success, full = pcall(ah.HasFullCommoditySearchResults, id)
    complete = success and full == true
  end
  saveDetail(id, "commodity_price_levels", {itemID = id}, detailRows, complete)
  record(id, {time = now(), source = "commodity_search", price = lowest, quantity = quantity, complete = complete})
end
local function collectItem(key)
  local ah = C_AuctionHouse
  if type(key) ~= "table" or not key.itemID or not ah or not ah.GetNumItemSearchResults or not ah.GetItemSearchResultInfo then return end
  local ok, count = pcall(ah.GetNumItemSearchResults, key)
  if not ok or type(count) ~= "number" or count == 0 then return end
  local quantity, lowest, detailRows = 0, nil, {}
  for i = 1, count do
    local success, row = pcall(ah.GetItemSearchResultInfo, key, i)
    if not success or type(row) ~= "table" or type(row.quantity) ~= "number" then return end
    quantity = quantity + row.quantity
    if type(row.buyoutAmount) == "number" and row.buyoutAmount > 0 and row.quantity > 0 then
      local price = row.buyoutAmount / row.quantity
      detailRows[#detailRows + 1] = {unitPrice = price, buyoutAmount = row.buyoutAmount, quantity = row.quantity, auctionID = row.auctionID, itemLink = row.itemLink, timeLeft = row.timeLeft}
      if not lowest or price < lowest then lowest = price end
    end
  end
  local complete = false
  if ah.HasFullItemSearchResults then
    local success, full = pcall(ah.HasFullItemSearchResults, key)
    complete = success and full == true
  end
  saveDetail(key.itemID, "item_listings", {itemID = key.itemID, itemLevel = key.itemLevel, itemSuffix = key.itemSuffix, battlePetSpeciesID = key.battlePetSpeciesID}, detailRows, complete)
  -- Retain the search key: variants of one item must not be treated as a whole market.
  record(key.itemID, {time = now(), source = "item_search", price = lowest, quantity = quantity, complete = complete, itemKey = {itemID = key.itemID, itemLevel = key.itemLevel, itemSuffix = key.itemSuffix, battlePetSpeciesID = key.battlePetSpeciesID}})
end
local autoElapsed = 0
local scanBusy = false
local scanHooked = false
local nextAttempt = 0
-- Keep every completed scan until the user exports and explicitly clears data.
local function copyBrowseFields(row)
  local result = {}
  for key, value in pairs(row) do
    if type(key) == "string" and (not issecretvalue or not issecretvalue(value)) then
      if type(value) == "number" or type(value) == "string" or type(value) == "boolean" then
        result[key] = value
      elseif type(value) == "table" then
        local fields = {}
        for nestedKey, nestedValue in pairs(value) do
          if type(nestedKey) == "string" and (not issecretvalue or not issecretvalue(nestedValue)) and (type(nestedValue) == "number" or type(nestedValue) == "string" or type(nestedValue) == "boolean") then fields[nestedKey] = nestedValue end
        end
        result[key] = fields
      end
    end
  end
  return result
end
local function hookScans()
  if scanHooked then return true end
  local a = Auctionator
  local events = a and a.IncrementalScan and a.IncrementalScan.Events
  if not (a and a.EventBus and events and events.ScanStart and events.ScanComplete and events.ScanFailed) then return false end
  local listener = {}
  function listener:ReceiveEvent(event, rows)
    if not market then return end
    if event == events.ScanStart then
      scanBusy = true
      market.lastScanStarted = now()
      nextAttempt = now() + (db.scanIntervalMinutes or 5) * 60
    elseif event == events.ScanFailed then
      scanBusy = false
      market.lastScanFailure = now()
      say("Auctionator scan failed; will retry at the next interval.")
    elseif event == events.ScanComplete then
      scanBusy = false
      if type(rows) ~= "table" then say("Scan completed without usable browse rows."); return end
      local scan = {started = market.lastScanStarted, completed = now(), source = "auctionator_browse", rows = {}}
      for _, row in ipairs(rows) do
        local key = row.itemKey
        if type(key) == "table" and type(key.itemID) == "number" and type(row.totalQuantity) == "number" then
          queueItem(key.itemID)
          scan.rows[#scan.rows + 1] = {itemID = key.itemID, itemLevel = key.itemLevel, itemSuffix = key.itemSuffix, battlePetSpeciesID = key.battlePetSpeciesID, price = row.minPrice, quantity = row.totalQuantity, browse = copyBrowseFields(row)}
        end
      end
      market.scans = market.scans or {}
      market.latestScan = scan
      if NokiMarketRefreshFlips then NokiMarketRefreshFlips() end

      sampleWatch()
      say("Updated current market snapshot: " .. #scan.rows .. " browse rows.")
    end
  end
  local ok = pcall(a.EventBus.Register, a.EventBus, listener, {events.ScanStart, events.ScanComplete, events.ScanFailed})
  scanHooked = ok
  return ok
end
local function startScan(manual)
  if not houseOpen or (not manual and not db.autoScan) or scanBusy then
    if manual then say("A scan is already running or the auction house is closed.") end
    return
  end
  local a = Auctionator
  local scanner = a and a.State and a.State.IncrementalScanFrameRef
  if not hookScans() or not scanner or not scanner.InitiateScan then
    nextAttempt = now() + 60
    if manual then say("Auctionator scanner is not ready. Check that Auctionator is enabled.") end
    return
  end
  if scanner.doingFullScan or (a.State.FullScanFrameRef and a.State.FullScanFrameRef.inProgress) then
    if manual then say("Auctionator is already scanning.") end
    nextAttempt = now() + 60
    return
  end
  if a.AH and a.AH.IsNotThrottled then
    local ok, ready = pcall(a.AH.IsNotThrottled)
    if not ok or not ready then
      if manual then say("Auction house requests are busy; try again shortly.") end
      nextAttempt = now() + 30; return
    end
  end
  -- Use the same incremental scanner as Auctionator's default Scan button.
  nextAttempt = now() + (db.scanIntervalMinutes or 5) * 60
  local ok, err = pcall(scanner.InitiateScan, scanner)
  if not ok then scanBusy = false; say("Could not start automatic scan: " .. tostring(err)) end
end

local function showStatus()
  local watched, items, samples = 0, 0, 0
  for _ in pairs(market.watch) do watched = watched + 1 end
  for _, item in pairs(market.items) do items = items + 1; samples = samples + #(item.samples or {}) end
  say(marketKey() .. ": " .. watched .. " watched, " .. items .. " items, " .. samples .. " observations. AH " .. (houseOpen and "open" or "closed") .. ".")
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  say("Automatic market scans " .. (db.autoScan and "on" or "off") .. " (" .. db.scanIntervalMinutes .. " minutes); completed scans saved: " .. #(market.scans or {}) .. ".")
  say("Auctionator API " .. (api and api.GetAuctionPriceByItemID and "available" or "unavailable") .. ". Listing quantity is supply, not sales.")
end
local function report(id)
  local item = market.items[tostring(id)]
  if not item or not item.samples or #item.samples == 0 then say("No observations for item " .. id .. "."); return end
  local s = item.samples[#item.samples]
  local price = s.price and (math.floor(s.price + 0.5) .. "c/unit") or "no buyout"
  say("Item " .. id .. ": " .. price .. ", " .. s.source .. (s.quantity and (", " .. s.quantity .. " listed" .. (s.complete and " (complete results)" or " (possibly partial)")) or "") .. (s.ageDays and (", cache age " .. s.ageDays .. " days") or "") .. ", observed " .. date("%Y-%m-%d %H:%M", s.time) .. ".")
end
function NokiMarketRequestScan() startScan(true) end
function NokiMarketToggleAuto()
  if not db then return end
  db.autoScan = not db.autoScan
  nextAttempt = math.max(now() + 10, (market.lastScanStarted or 0) + db.scanIntervalMinutes * 60)
  say("Automatic scans " .. (db.autoScan and "on" or "off") .. ".")
end
function NokiMarketCycleInterval()
  if not db then return end
  local choices={1,2,5,10,15,30,60,120}
  local chosen=choices[1]
  for _,minutes in ipairs(choices) do if minutes>db.scanIntervalMinutes then chosen=minutes;break end end
  db.scanIntervalMinutes=chosen
  nextAttempt=math.max(now()+10,(market.lastScanStarted or 0)+chosen*60)
  say("Scan interval: " .. chosen .. " minutes.")
end
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_CLOSED")
pcall(frame.RegisterEvent, frame, "MERCHANT_UPDATE")
pcall(frame.RegisterEvent, frame, "GET_ITEM_INFO_RECEIVED")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
-- Unsupported events are ignored on clients with a different auction API.
pcall(frame.RegisterEvent, frame, "COMMODITY_SEARCH_RESULTS_UPDATED")
pcall(frame.RegisterEvent, frame, "ITEM_SEARCH_RESULTS_UPDATED")
frame:SetScript("OnEvent", function(_, event, arg)
  if event == "ADDON_LOADED" and arg == ADDON then initialize(); hookScans(); local scans = market.scans or {}; local last = market.latestScan or scans[#scans]; if last then for _, row in ipairs(last.rows or {}) do queueItem(row.itemID) end end
  elseif not market then return
  elseif event == "MERCHANT_SHOW" then merchantOpen = true; captureMerchant(); if C_Timer and C_Timer.After then C_Timer.After(1, captureMerchant) end
  elseif event == "MERCHANT_UPDATE" then captureMerchant()
  elseif event == "MERCHANT_CLOSED" then merchantOpen = false
  elseif event == "GET_ITEM_INFO_RECEIVED" then updateItemInfo(arg)
  elseif event == "AUCTION_HOUSE_SHOW" then houseOpen = true; elapsed = 0; sampleWatch(); hookScans(); nextAttempt = math.max(now() + 10, (market.lastScanStarted or 0) + db.scanIntervalMinutes * 60)
  elseif event == "AUCTION_HOUSE_CLOSED" then houseOpen = false; scanBusy = false
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" and houseOpen then collectCommodity(arg)
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" and houseOpen then collectItem(arg) end
end)
frame:SetScript("OnUpdate", function(_, delta)
  if not market then return end
  catalogElapsed = catalogElapsed + delta
  if nameIndex <= #nameQueue and catalogElapsed >= 0.2 then
    catalogElapsed = 0
    for _ = 1, 10 do
      local id = nameQueue[nameIndex]; if not id then break end
      nameIndex = nameIndex + 1; updateItemInfo(id)
      if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    end
  end
  if not houseOpen then return end
  autoElapsed = autoElapsed + delta
  if autoElapsed >= 5 then
    autoElapsed = 0
    if now() >= nextAttempt then startScan(false) end
  end
  elapsed = elapsed + delta
  if elapsed >= SAMPLE_INTERVAL then elapsed = 0; sampleWatch() end
end)
SLASH_NOKIMARKET1 = "/nm"
SlashCmdList.NOKIMARKET = function(message)
  if not market then return end
  local command, value = message:match("^%s*(%S*)%s*(.-)%s*$")
  command = command:lower()
  local id = tonumber(value:match("item:(%d+)") or value:match("^(%d+)$"))
  if command == "why" and id and NokiMarketExplainItem then
    NokiMarketExplainItem(id)
  elseif command == "auto" and (value == "on" or value == "off") then
    db.autoScan = value == "on"; nextAttempt = math.max(now() + 10, (market.lastScanStarted or 0) + db.scanIntervalMinutes * 60); say("Automatic scans " .. value .. ".")
  elseif command == "interval" and tonumber(value) and tonumber(value) >= 1 then
    db.scanIntervalMinutes = math.floor(tonumber(value)); nextAttempt = math.max(now() + 10, (market.lastScanStarted or 0) + db.scanIntervalMinutes * 60); say("Scan interval: " .. db.scanIntervalMinutes .. " minutes.")
  elseif command == "add" and id and id > 0 then
    market.watch[tostring(id)] = true; auctionatorSample(id); say("Watching item " .. id .. ".")
  elseif command == "remove" and id then
    market.watch[tostring(id)] = nil; say("Stopped watching item " .. id .. "; history retained.")
  elseif command == "item" and id then report(id)
  elseif command == "sample" then say("Recorded " .. sampleWatch() .. " Auctionator cache observations.")
  elseif command == "list" then
    local ids = {}; for key in pairs(market.watch) do ids[#ids + 1] = tonumber(key) end; table.sort(ids)
    local labels = {}; for _, value in ipairs(ids) do labels[#labels + 1] = tostring(value) end
    say("Watchlist: " .. (#labels > 0 and table.concat(labels, ", ") or "empty"))
  elseif command == "" or command == "status" then showStatus()
  else say("Commands: /nm add <item ID or link>, remove <ID>, item <ID>, list, sample, status, auto on|off, interval <minutes (1+)> ") end
end















