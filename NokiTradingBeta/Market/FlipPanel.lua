-- Noki Market auction-house tab. Vendor observations are reference data.
local TAB_ID = "NokiUnifiedMarketFlips"
local CRAFT_TAB_ID = "NokiUnifiedMarketCrafting"
local applyMode
local panel, tabLib, budgetBox, minSalesBox, minStackProfitBox, searchBox, sortButton, status, pageText, detailTitle, detailBody
local rows, results, filtered = {}, {}, {}
local scrollOffset, sortMode, selectedID = 0, "gain", nil
local scrollbar, updatingScrollbar
local viewMode, modeButton, headerTexts, flipControls, title, subtitle = "flips", nil, {}, {}, nil, nil
local marketViewMode="flips"
local selectedItem,resaleCheckButton,resaleViewButton
local openResale,checkResaleItem,tryOpenResale
local returningFromResaleView,skipNextMarketRefresh,resaleReturnItem=false,false,nil
local resaleQueue,resaleIndex,resaleEpoch,resaleChecked,resaleUnavailable,resaleUnknown={},1,0,0,0,0
local resaleInflight,resaleOpenRequest,resaleScanTime=false,nil,nil
local resaleCache
local knownButton, captureButton, minProfitLabel, searchHint
local sortLabels = {gain="Gain per unit", roi="Return %", activity="Est. sales/day",gap="Gap"}
local gapAscending=false
local function marketGap(item)
  local sales=item.remote and item.remote.sales
  if item.variant or type(item.quantity)~="number" or type(sales)~="number" then return nil end
  return sales-item.quantity
end
local function gapLess(a,b)
  local av,bv=marketGap(a),marketGap(b)
  if av==nil or bv==nil then if av~=bv then return av~=nil end
  elseif av~=bv then if gapAscending then return av<bv else return av>bv end end
  if a.name~=b.name then return a.name:lower()<b.name:lower() end
  return tostring(a.key or a.id)<tostring(b.key or b.id)
end
local ROWS_PER_PAGE = 7

local function copper(value)
  if value == nil then return "--" end
  if value < 0 then return "-" .. copper(-value) end
  local gold = math.floor(value / 10000)
  local silver = math.floor((value - gold * 10000) / 100)
  local rest = value - gold * 10000 - silver * 100
  local remainder = string.format("%.3f", rest):gsub("0+$", ""):gsub("%.$", "")
  if gold > 0 then return string.format("%dg %ds %sc", gold, silver, remainder) end
  if silver > 0 then return string.format("%ds %sc", silver, remainder) end
  return remainder .. "c"
end
local function market()
  if not NokiBetaMarketDB or not NokiBetaMarketDB.markets then return nil end
  return NokiBetaMarketDB.markets[(GetRealmName() or "Unknown realm") .. " - " .. (UnitFactionGroup("player") or "Unknown faction")]
end
local function latestSnapshot()
  local data = market()
  if not data then return nil end
  local scans = data.scans or {}
  local scan=data.latestScan or scans[#scans]
  if scan and scan.source=="noki_beta_browse" then return nil end
  return scan
end
local function usableHistory()
  return NokiUnifiedMarketActivityMarket()
end
-- Keep the last batch snapshot only for its historical supply deltas.
-- Daily sales always come from AHledger's in-game API.
local function marketActivity(id, market)
  local activity = market and NokiUnifiedMarketActivity(id, market) or nil
  local old = NokiUnifiedMarketRemoteData
  if market and old and old.market == market and old.items then
    local historical = old.items[id] or old.items[tostring(id)]
    if historical then
      activity=activity or {market=market}
      activity.d1=historical.d1;activity.d2=historical.d2;activity.d8=historical.d8;activity.d24=historical.d24
      activity.historyObserved=old.observed
    end
  end
  return activity
end
local function number(value)
  if value == nil then return "--" end
  if value > 0 then return "+" .. tostring(value) end
  return tostring(value)
end
local function historyText(remote)
  if not remote then return "AHledger sales/day unavailable. Install or update AHledger data." end
  local result="AHledger est. sales/day: "..(remote.sales~=nil and tostring(remote.sales) or "unknown").." | "..NokiUnifiedMarketActivityLabel(remote).." | Prices from AHledger (ahledger.com)"
  if remote.historyObserved then
    result=result.."\nPrevious batch supply changes (snapshot "..date("%Y-%m-%d %H:%M",remote.historyObserved).."): "..number(remote.d1).." / "..number(remote.d2).." / "..number(remote.d8).." / "..number(remote.d24).." (1h / 2h / 8h / 24h)"
  end
  return result
end
local function makeText(parent, anchor, x, y, width, font)
  local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  text:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); text:SetWidth(width); text:SetJustifyH("LEFT"); text:SetWordWrap(false)
  return text
end
local function setSelected(item)
  selectedID = item and (item.key or item.id) or nil
  selectedItem=item
  if resaleCheckButton then resaleCheckButton:SetEnabled(item~=nil and not item.checking) end
  if resaleViewButton then resaleViewButton:SetEnabled(item~=nil) end
  if not item then
    detailTitle:SetText("SELECT AN ITEM")
    detailBody:SetText(viewMode=="resale" and "Select an item to see all live listings priced below vendor value." or "Choose a row to see vendor pack details and market history.")
    return
  end
  if viewMode=="resale" then
    detailTitle:SetText(item.name.." | #"..item.id)
    local details=item.checking and "Checking live price tiers..." or item.live and ("Buy "..item.lowQuantity.." units through "..copper(item.buyThrough).."/unit | Cost "..copper(item.buyCost).." | Vendor value "..copper(item.vendorSell*item.lowQuantity).." | Profit "..copper(item.totalGain)) or (item.checkError and ("Live prices unavailable: "..item.checkError) or item.viewed and "Previously viewed; live prices are being rechecked." or "Waiting for the live price check.")
    detailBody:SetText("AH low "..copper(item.ah).."/unit | Vendor sell "..copper(item.vendorSell).."/unit | "..(item.unitGain>0 and "Gain " or "Loss ")..copper(math.abs(item.unitGain)).."/unit\n"..details.."\nVendor sell value is a reference; verify current price, quantity, binding and vendor acceptance before buying.")
    return
  end
  if viewMode == "craft" then
    local r=item.recipe;local inputs={}
    for _,m in ipairs(r.materials) do
      local name=(GetItemInfo and GetItemInfo(m.id)) or m.name or ("#"..m.id)
      inputs[#inputs+1]=m.quantity.." x "..name.." @ "..copper(item.prices[m.id])
    end
    local range=r.yieldMin==r.yieldMax and tostring(r.yieldMin) or (r.yieldMin.."-"..r.yieldMax)
    detailTitle:SetText(r.name.." | "..r.profession..(r.trainerSkill and " | Recipe skill: " or " | Required skill: ")..tostring(r.required or "unknown")..(r.trainerSkill and (" | Trainer: "..r.trainerSkill.." (check)") or "")..(item.known and " | KNOWN" or " | knowledge unknown"))
    detailBody:SetText("Materials (AH lows): "..table.concat(inputs, ", ").."\nCost "..copper(item.cost).." / craft | Yield "..range.." | Sell "..copper(item.sell).." / unit\nProfit "..copper(item.gainMin)..(item.gainMin~=item.gainMax and (" to "..copper(item.gainMax)) or "").." / craft"..(item.conditional and " | HIGHER YIELD REQUIRED" or "").." | Est. "..item.sales.." units/day\n5% cut; no deposits. "..(r.trainerSkill and "*Recipe and trainer requirements differ; check in game. " or "").."Prices from AHledger (ahledger.com). Trainer data: Efficient Games (CC BY 4.0). Check live prices and binding.")
    return
  end
  local remote = item.remote
  if viewMode == "lookup" then
    local history = historyText(remote)
    local offer = item.cost and ("Vendor reference: " .. item.vendor .. " | " .. copper(item.cost) .. " for " .. item.stack .. (item.limited and " | LIMITED STOCK" or "")) or "No vendor purchase offer recorded in reference data."
    detailTitle:SetText(item.name .. " | #" .. item.id .. (item.variant and (" | " .. item.variant) or ""))
    detailBody:SetText("Last scan: low " .. copper(item.ah) .. "/unit | listed " .. tostring(item.quantity or "unknown") .. "\n" .. offer .. "\n" .. history .. "\nActivity is an estimate; supply changes are not confirmed sales. Vendor and history data are item-wide.")
    return
  end
  local history = historyText(remote)
  detailTitle:SetText(item.name .. "  |  #" .. item.id)
  detailBody:SetText("Vendor: " .. item.vendor .. "  |  " .. (item.stack > 1 and "PACK: " or "") .. copper(item.cost) .. " for " .. item.stack .. "  |  standing " .. tostring(item.standing) .. (item.limited and "  |  LIMITED STOCK" or "") .. "\nSell " .. copper(item.sellUnit) .. "/unit (scanned low " .. copper(item.ah) .. ")  |  est. gain " .. copper(item.gainPack) .. "/pack after 5%\n" .. history .. "\nDeposits excluded; tax rounding, availability, binding and sales can vary.")
end
local function render()
  if not panel then return end
  local maxOffset = math.max(0, #filtered - ROWS_PER_PAGE)
  scrollOffset = math.max(0, math.min(scrollOffset, maxOffset))
  if scrollbar then
    updatingScrollbar = true
    scrollbar:SetMinMaxValues(0, maxOffset)
    scrollbar:SetValue(scrollOffset)
    scrollbar:SetShown(maxOffset > 0)
    updatingScrollbar = false
  end
  local found
  for i, row in ipairs(rows) do
    local item = filtered[scrollOffset + i]
    row.item = item
    if item then
      if viewMode=="flips" then
        row.name:SetWidth(155);row.name:SetText(item.name)
        local quantity=NokiUnifiedCore.OwnedItemQuantity and NokiUnifiedCore.OwnedItemQuantity(item.id)
        local display=quantity~=nil and ((BreakUpLargeNumbers and BreakUpLargeNumbers(quantity)) or tostring(quantity)) or "--"
        row.selling:SetText("|cff73e6a3"..display.." selling|r");row.selling:Show()
      else row.name:SetWidth(245);row.name:SetText(item.name .. "  |cff829494#" .. item.id .. "|r");row.selling:Hide() end
      row.gain:SetTextColor(.45,.9,.64)
      if viewMode == "resale" then
        row.vendor:SetText(item.checking and "Checking live prices..." or item.live and "Live profitable tiers checked" or item.checkError and "Live prices unavailable" or item.viewed and "Viewed; awaiting recheck" or "Awaiting live price check")
        row.buy:SetText(copper(item.ah));row.ah:SetText(copper(item.vendorSell));row.gain:SetText(copper(item.unitGain));row.stackGain:SetText(item.lowQuantity and tostring(item.lowQuantity) or "--")
        row.gain:SetTextColor(item.unitGain>0 and .45 or 1,item.unitGain>0 and .9 or .35,item.unitGain>0 and .64 or .35)
      elseif viewMode == "craft" then
        local r=item.recipe
        row.vendor:SetText(r.profession.." | skill "..tostring(r.required or "?")..(r.trainerSkill and "*" or "")..(item.known and " | known" or " | unknown")..(item.conditional and " | needs higher yield" or ""))
        row.buy:SetText(copper(item.cost));row.ah:SetText(copper(item.sell))
        row.gain:SetText(copper(item.gainMin));row.stackGain:SetText(r.yieldMin==r.yieldMax and tostring(r.yieldMin) or (r.yieldMin.."-"..r.yieldMax))
      elseif viewMode == "lookup" then
        row.vendor:SetText(item.cost and (item.vendor..(item.variant and (" | "..item.variant) or "")) or (item.variant or "No vendor purchase offer"))
        row.buy:SetText(item.cost and copper(item.cost / item.stack) or "--")
        row.ah:SetText(copper(item.ah))
        row.gain:SetText(item.quantity ~= nil and tostring(item.quantity) or "--")
        row.stackGain:SetText(item.cost and (item.stack .. " / " .. copper(item.cost)) or "--")
      else
        row.vendor:SetText((item.stack > 1 and ("|cffffd36aPACK " .. item.stack .. " for " .. copper(item.cost) .. "|r  ·  ") or "") .. item.vendor .. (item.limited and "  |cffffba70LIMITED|r" or ""))
        row.buy:SetText(copper(item.buyUnit)); row.ah:SetText(copper(item.sellUnit))
        row.gain:SetText(copper(item.gainUnit)); row.stackGain:SetText(copper(item.gainPack))
      end
      row.activity:SetText(viewMode=="resale" and copper(item.buyCost) or viewMode == "craft" and (tostring(item.sales).."/day") or (item.remote and item.remote.sales ~= nil and tostring(item.remote.sales) .. "/day" or "--"))
      local listed=item.quantity
      row.listed:SetText(viewMode=="resale" and copper(item.totalGain) or viewMode=="flips" and type(listed)=="number" and tostring(listed) or "--")
      row.listed:SetShown(viewMode=="flips" or viewMode=="resale")
      row.gap:SetShown(viewMode~="craft" and viewMode~="resale")
      row.resaleView:SetShown(viewMode=="resale")
      if viewMode=="resale" then
        row.gap:SetText(item.remote and item.remote.sales and tostring(item.remote.sales).."/day" or "--");row.gap:SetTextColor(.8,.8,.8)
      elseif viewMode~="craft" and not item.variant and type(listed)=="number" and type(item.remote and item.remote.sales)=="number" then
        local gap=item.remote.sales-listed
        local value=math.floor(math.abs(gap)*10+0.5)/10
        row.gap:SetText(value==0 and "0" or ((gap>0 and "+" or "-")..string.format("%.1f",value):gsub("%.0$","")))
        if value==0 then row.gap:SetTextColor(0.8,0.8,0.8) elseif gap>0 then row.gap:SetTextColor(0.45,0.9,0.64) else row.gap:SetTextColor(1,0.35,0.35) end
      else row.gap:SetText("--");row.gap:SetTextColor(0.8,0.8,0.8) end
      row:Show()
      if (item.key or item.id) == selectedID then found = item end
    else row:Hide() end
  end
  if found then setSelected(found) elseif not selectedID and filtered[1] then setSelected(filtered[1]) end
  if headerTexts[8] and (viewMode=="flips" or viewMode=="lookup") then headerTexts[8]:SetText("GAP"..(sortMode=="gap" and (gapAscending and " ^" or " v") or "")) end
  pageText:SetText((#filtered == 0 and "0" or (scrollOffset + 1) .. "-" .. math.min(scrollOffset + ROWS_PER_PAGE, #filtered)) .. " OF " .. #filtered .. (viewMode == "lookup" and " ITEMS" or " CANDIDATES") .. "  |  SCROLL TO BROWSE")
end
local function filterAndSort(resetScroll)
  local text = (searchBox:GetText() or ""):lower():match("^%s*(.-)%s*$")
  filtered = {}
  for _, item in ipairs(results) do
    if not (viewMode=="resale" and (item.soldOut or (item.live and item.unitGain<=0))) and (text == "" or item.name:lower():find(text,1,true) or (item.vendor or ""):lower():find(text,1,true) or tostring(item.id):find(text,1,true)) then filtered[#filtered + 1] = item end
  end
  table.sort(filtered, function(a,b)
    if viewMode=="resale" then if a.unitGain==b.unitGain then return a.id<b.id end;return a.unitGain>b.unitGain end
    if sortMode=="gap" and (viewMode=="flips" or viewMode=="lookup") then return gapLess(a,b) end
    if viewMode == "craft" then
      local av,bv
      if sortMode=="activity" then av,bv=a.sales,b.sales
      elseif sortMode=="roi" then av,bv=a.gainMin/a.cost,b.gainMin/b.cost
      else av,bv=a.gainMin,b.gainMin end
      if av==bv then return a.key<b.key end
      return av>bv
    end
    if viewMode == "lookup" then
      if (a.cost~=nil)~=(b.cost~=nil) then return a.cost~=nil end
      if a.name:lower() ~= b.name:lower() then return a.name:lower() < b.name:lower() end
      return a.key < b.key
    end
    local av,bv
    if sortMode == "roi" then av,bv=a.roi,b.roi
    elseif sortMode == "activity" then av,bv=a.remote and a.remote.sales or -1,b.remote and b.remote.sales or -1
    else av,bv=a.gainUnit,b.gainUnit end
    if av == bv then return a.id < b.id end
    return av > bv
  end)
  if resetScroll then scrollOffset=0 end
  selectedID=nil;setSelected(nil);render()
  if #filtered==0 and text~="" then
    detailTitle:SetText(viewMode == "lookup" and "NO MATCHING ITEMS" or "NO MATCHING CANDIDATES")
    detailBody:SetText(viewMode == "lookup" and "No match in the loaded scan, vendor reference, or history." or "Check filters or switch to Item lookup to see all available items.")
  end
end
local function calculateLookup()
  results = {}
  local byKey, seenID, offers = {}, {}, {}
  for _, offer in ipairs(NokiUnifiedMarketVendorData or {}) do
    local id, name, vendor, cost, stack = unpack(offer)
    if id and type(cost) == "number" and type(stack) == "number" and stack > 0 then
      local old = offers[id]
      if not old or cost / stack < old[4] / old[5] then offers[id] = offer end
    end
  end
  local activityMarket,activityError = usableHistory()
  local catalog = NokiBetaMarketDB.itemCatalog or {}
  local function add(id, row)
    if not id then return end
    local suffix = row and (row.itemSuffix or 0) or 0
    local level = row and (row.itemLevel or 0) or 0
    local pet = row and (row.battlePetSpeciesID or 0) or 0
    local key = table.concat({id, level, suffix, pet}, ":")
    local item = byKey[key]
    if not item then
      local offer = offers[id]
      local saved = catalog[tostring(id)] or catalog[id]
      local gameName = GetItemInfo and GetItemInfo(id)
      local name = (saved and saved.name) or (offer and offer[2]) or gameName or ("Item #" .. id)
      item = {key=key,id=id,name=name,vendor=offer and offer[3] or "",cost=offer and offer[4],stack=offer and offer[5],standing=offer and offer[6],limited=offer and offer[8],remote=marketActivity(id,activityMarket)}
      if suffix ~= 0 or pet ~= 0 or level ~= 0 then item.variant = "Level " .. level .. " / suffix " .. suffix .. (pet ~= 0 and (" / pet " .. pet) or "") end
      byKey[key]=item; seenID[id]=true; results[#results+1]=item
    end
    if row and type(row.price)=="number" and row.price>0 and (not item.ah or row.price<item.ah) then
      item.ah=row.price; item.quantity=row.quantity
    end
  end
  local scan=latestSnapshot()
  if scan then for _,row in ipairs(scan.rows or {}) do add(row.itemID,row) end end
  for id in pairs(offers) do if not seenID[id] then add(id) end end
  for key in pairs(catalog) do local id=tonumber(key); if id and not seenID[id] then add(id) end end
  local age=scan and scan.completed and math.max(0,math.floor((((GetServerTime and GetServerTime()) or time())-scan.completed)/60))
  local source=activityMarket or activityError or "not loaded"
  status:SetText("ITEM LOOKUP | Vendor offers first | Scan " .. (age and (age .. "m ago") or "unavailable") .. " | AHledger " .. source)
  filterAndSort()
end
local function updateResaleStatus()
  if not status or viewMode~="resale" then return end
  local now=(GetServerTime and GetServerTime()) or time()
  local function age(observed) return type(observed)=="number" and (math.max(0,math.floor((now-observed)/60)).."m ago") or "unavailable" end
  local marketID=NokiUnifiedCore and NokiUnifiedCore.Market()
  local book=marketID and NokiBetaCoreDB and NokiBetaCoreDB.prices and NokiBetaCoreDB.prices[marketID]
  local latest=book and book.observed
  local scanText="Latest scan "..age(latest).." | List "..age(resaleScanTime)
  if type(latest)=="number" and type(resaleScanTime)=="number" and latest>resaleScanTime then scanText=scanText.." | Refresh list" end
  local prefix=resaleOpenRequest and ("PREPARING "..resaleOpenRequest.item.name.." | ") or "VENDOR RESALE | "
  status:SetText(prefix..resaleChecked.."/"..#resaleQueue.." checked | "..resaleUnavailable.." unavailable | "..resaleUnknown.." vendor unknown | "..scanText)
end
local function calculateResale()
  results={};selectedID=nil;resaleEpoch=resaleEpoch+1;resaleQueue={};resaleIndex=1;resaleChecked=0;resaleUnavailable=0;resaleUnknown=0;resaleScanTime=nil;resaleOpenRequest=nil
  resaleCache={results=results}
  local marketID=NokiUnifiedCore and NokiUnifiedCore.Market()
  local book=marketID and NokiBetaCoreDB and NokiBetaCoreDB.prices and NokiBetaCoreDB.prices[marketID]
  if not book or not book.items then status:SetText("NO SCAN | Open the auction house and run a scan.");filterAndSort();return end
  local catalog=NokiBetaMarketDB.itemCatalog or {};local activityMarket=usableHistory();local unknown=0
  for id,row in pairs(book.items) do
    if type(id)=="number" and type(row)=="table" and not row.carried and type(row.price)=="number" and row.price>0 then
      local saved=catalog[tostring(id)] or catalog[id];local vendor=saved and saved.vendorSell;local name=saved and saved.name
      if type(vendor)~="number" then
        local getInfo=(C_Item and C_Item.GetItemInfo) or GetItemInfo
        if getInfo then local fields={pcall(getInfo,id)};if fields[1] then vendor=fields[12];name=name or fields[2] end end
      end
      if type(vendor)~="number" then unknown=unknown+1
      elseif vendor>0 and row.price<vendor then
        local level,suffix,pet=(row.variant or "0:0:0"):match("^([^:]+):([^:]+):([^:]+)$")
        results[#results+1]={id=id,name=name or ("Item #"..id),ah=row.price,vendorSell=vendor,unitGain=vendor-row.price,remote=marketActivity(id,activityMarket),auctionKey={itemID=id,itemLevel=tonumber(level) or 0,itemSuffix=tonumber(suffix) or 0,battlePetSpeciesID=tonumber(pet) or 0}}
      end
    end
  end
  resaleScanTime=book.observed;resaleUnknown=unknown
  for _,item in ipairs(results) do resaleQueue[#resaleQueue+1]=item end
  table.sort(resaleQueue,function(a,b) if a.unitGain==b.unitGain then return a.id<b.id end;return a.unitGain>b.unitGain end)
  updateResaleStatus()
  filterAndSort()
end
local function calculate()
  if not panel or not NokiBetaMarketDB then return end
  if viewMode == "lookup" then calculateLookup(); return end
  if viewMode == "resale" then calculateResale(); return end
  if viewMode == "craft" then
    results={};selectedID=nil
    local budget=tonumber(budgetBox:GetText());local sales=tonumber(minSalesBox:GetText());local gain=tonumber(minStackProfitBox:GetText())
    if not sales or sales<0 or not gain or gain<0 or (budgetBox:GetText():match("%S") and (not budget or budget<0)) then
      status:SetText("Enter non-negative filters; max spend may be blank.");filterAndSort();return
    end
    NokiBetaMarketDB.craftBudgetSilver=budgetBox:GetText();NokiBetaMarketDB.craftMinSales=sales;NokiBetaMarketDB.craftMinProfit=gain
    local found,err,stats=NokiUnifiedMarketCraftCandidates(gain,sales,NokiBetaMarketDB.flipMatchPrice==true,NokiBetaMarketDB.craftKnownOnly==true,budget and budget*100 or nil)
    if err then status:SetText(err);filterAndSort();return end
    for _,item in ipairs(found) do
      item.id=item.recipe.output;item.key=tostring(item.recipe.id);item.name=item.recipe.name;item.vendor=item.recipe.profession
      results[#results+1]=item
    end
    local age=stats.scan and math.max(0,math.floor((((GetServerTime and GetServerTime()) or time())-stats.scan)/60))
    local activityAge=stats.activity and math.max(0,math.floor((((GetServerTime and GetServerTime()) or time())-stats.activity)/60))
    status:SetText("SCAN "..(age and age.."m" or "?").." | AHledger "..(activityAge and activityAge.."m" or "?").." | Missing prices "..stats.missing.." | Sales filter "..stats.activityExcluded.." | Review "..stats.review)
    filterAndSort();return
  end
  local scan=latestSnapshot();results={};selectedID=nil
  if not scan or not scan.rows then status:SetText("NO SCAN  |  Open the auction house and run a scan.");filterAndSort();return end
  local function readField(box)
    local text=box:GetText()
    if not text or text:match("^%s*$") then return nil end
    return tonumber(text)
  end
  local silver=readField(budgetBox)
  if (budgetBox:GetText():match("%S") and not silver) or (silver and (silver < 0 or silver > 1000000)) then status:SetText("Enter a budget between 0 and 1,000,000 silver, or leave blank.");filterAndSort();return end
  local minSales=readField(minSalesBox)
  if (minSalesBox:GetText():match("%S") and not minSales) or (minSales and (minSales < 0 or minSales > 1000000)) then status:SetText("Enter a minimum activity between 0 and 1,000,000 per day, or leave blank.");filterAndSort();return end
  local minPackSilver=readField(minStackProfitBox)
  if (minStackProfitBox:GetText():match("%S") and not minPackSilver) or (minPackSilver and (minPackSilver < 0 or minPackSilver > 1000000)) then status:SetText("Enter a non-negative minimum pack profit, or leave blank.");filterAndSort();return end
  NokiBetaMarketDB.flipMinPackProfitSilver=minPackSilver or ""
  NokiBetaMarketDB.flipBudgetSilver=silver or ""
  NokiBetaMarketDB.flipMinSalesPerDay=minSales or ""
  local budget=silver and math.floor(silver*100) or nil
  local matchPrice=NokiBetaMarketDB.flipMatchPrice == true
  local priceByItem,variants={},{ }
  for _,row in ipairs(scan.rows) do
    if row.itemID and ((row.itemSuffix or 0)~=0 or (row.battlePetSpeciesID or 0)~=0) then variants[row.itemID]=false end
    if row.itemID and (row.itemSuffix or 0)==0 and (row.battlePetSpeciesID or 0)==0 and type(row.price)=="number" and row.price>0 then
      local old=priceByItem[row.itemID]
      if not old or row.price<old.price then priceByItem[row.itemID]=row end
      local key=tostring(row.itemLevel or 0)..":"..tostring(row.itemSuffix or 0)..":"..tostring(row.battlePetSpeciesID or 0)
      local prior=variants[row.itemID]
      if prior==nil then variants[row.itemID]=key elseif prior~=key then variants[row.itemID]=false end
    end
  end
  local best, unknown, zero, below = {}, {}, {}, {}
  local activityMarket,activityError=usableHistory()
  local activityInfo
  for _,offer in ipairs(NokiUnifiedMarketVendorData or {}) do
    local id,name,vendor,cost,stack,standing,observed,limited=unpack(offer)
    local ah=priceByItem[id]
    if ah and cost and cost>0 and stack and stack>0 and (not budget or cost<=budget) then
      local packs=budget and math.floor(budget/cost) or 1
      local buyUnit=cost/stack
      local sellUnit=math.floor(ah.price)-(matchPrice and 0 or 1)
      local gainUnit=sellUnit*0.95-buyUnit
      if sellUnit>=1 and gainUnit>0 then
        local remote=marketActivity(id,activityMarket)
        if remote and (not activityInfo or (remote.observed and (not activityInfo.observed or remote.observed<activityInfo.observed))) then activityInfo=remote end
        local sales=remote and remote.sales
        if minSales and minSales > 0 and type(sales) ~= "number" then unknown[id]=true
        elseif minSales and minSales > 0 and sales <= 0 then zero[id]=true
        elseif minSales and minSales > 0 and sales < minSales then below[id]=true
        else
        local gainPack=gainUnit*stack
        if minPackSilver and gainPack < minPackSilver*100 then below[id]=true
        else
        local spend=packs*cost
        local quantity=variants[id]~=false and type(ah.quantity)=="number" and ah.quantity>=0 and ah.quantity or nil
        local candidate={id=id,name=name,vendor=vendor,cost=cost,stack=stack,standing=standing,observed=observed,limited=limited,packs=packs,units=packs*stack,spend=spend,ah=ah.price,buyUnit=buyUnit,sellUnit=sellUnit,gainUnit=gainUnit,gainPack=gainPack,roi=gainUnit/buyUnit,quantity=quantity,remote=remote}
        if not best[id] or gainUnit>best[id].gainUnit then best[id]=candidate end
        end
        end
      end
    end
  end
  for _,item in pairs(best) do results[#results+1]=item end
  local age=scan.completed and math.max(0,math.floor(((GetServerTime and GetServerTime()) or time())-scan.completed)) or nil
  local sourceAge=activityInfo and NokiUnifiedMarketActivityLabel(activityInfo) or (activityError or ("AHledger "..tostring(activityMarket).." no activity"))
  local function count(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
  status:SetText("SCAN " .. (age and (math.floor(age/60) .. "m ago") or "unknown") .. "  |  " .. sourceAge .. "  | " .. (matchPrice and "MATCH" or "UNDERCUT 1c") .. " | excluded: " .. count(unknown) .. " unknown, " .. count(zero) .. " zero, " .. count(below) .. " below minimum")
  filterAndSort()
end
function NokiUnifiedCore.VendorResaleTotals(vendorSell,tiers)
  if type(vendorSell)~="number" or vendorSell<=0 or type(tiers)~="table" then return nil end
  local last
  for _,tier in ipairs(tiers) do
    if type(tier.price)~="number" or type(tier.totalQuantity)~="number" or type(tier.totalCost)~="number" then return nil end
    if tier.price>=vendorSell then break end
    last=tier
  end
  if not last then return nil end
  return {quantity=last.totalQuantity,cost=last.totalCost,profit=vendorSell*last.totalQuantity-last.totalCost,through=last.price}
end
checkResaleItem=function(item,onComplete)
  if not item or item.checking then return false,"Already checking" end
  item.checking=true;item.checkError=nil
  if selectedItem==item and viewMode=="resale" then setSelected(item) end
  local ok,err=NokiUnifiedCore.CheckBuyout(item.auctionKey,function(result,message)
    item.checking=false
    if result and result.tiers and result.tiers[1] then
      local first=result.tiers[1];local totals=NokiUnifiedCore.VendorResaleTotals(item.vendorSell,result.tiers)
      item.ah=first.price;item.unitGain=item.vendorSell-first.price;item.live=true;item.viewed=false;item.soldOut=false;item.checkError=nil
      item.lowQuantity=totals and totals.quantity;item.buyCost=totals and totals.cost;item.totalGain=totals and totals.profit;item.buyThrough=totals and totals.through
      if item.unitGain>0 and not totals then item.live=false;item.checkError="Incomplete tier totals" end
    else item.live=false;item.lowQuantity=nil;item.buyCost=nil;item.totalGain=nil;item.checkError=message or "No usable listings";item.soldOut=message=="No buyout listings found." end
    local belongs=false;for _,candidate in ipairs(results) do if candidate==item then belongs=true;break end end
    if belongs and panel and panel:IsShown() and viewMode=="resale" then
      if item.soldOut or (item.live and item.unitGain<=0) then filterAndSort(false) else render() end
    end
    if onComplete then onComplete(result,message) end
  end,{vendorCeiling=item.vendorSell})
  if not ok then item.checking=false;item.checkError=err or "Price check unavailable";if selectedItem==item and viewMode=="resale" then setSelected(item) end end
  return ok,err
end
openResale=function(item)
  if viewMode~="resale" or not item then return end
  if not AuctionHouseFrame.SelectBrowseResult then print("Noki Market: auction buy view unavailable.");return end
  setSelected(item);resaleOpenRequest={item=item};NokiUnifiedCore.SetWorking("resaleView",true);updateResaleStatus()
  if resaleInflight and NokiUnifiedCore.CancelQueuedBuyout then NokiUnifiedCore.CancelQueuedBuyout("Deferred for View") end
  tryOpenResale()
end
tryOpenResale=function()
  local request=resaleOpenRequest;if not request then return end
  local item=request.item
  if item.soldOut or (item.live and item.unitGain<=0) then resaleOpenRequest=nil;NokiUnifiedCore.SetWorking("resaleView",false);updateResaleStatus();print("Noki Market: this item is sold out or no longer profitable to vendor.");return end
  if NokiUnifiedCore.phase~="idle" or NokiUnifiedCore.working.buyout or (NokiUnifiedCore.IsCompetitionSearchActive and NokiUnifiedCore.IsCompetitionSearchActive()) then return end
  local api=C_AuctionHouse
  if not api or not api.GetItemKeyInfo then resaleOpenRequest=nil;NokiUnifiedCore.SetWorking("resaleView",false);updateResaleStatus();print("Noki Market: auction item details are unavailable.");return end
  local ok,info=pcall(api.GetItemKeyInfo,item.auctionKey)
  if not ok or type(info)~="table" or type(info.isCommodity)~="boolean" then
    local now=(GetServerTime and GetServerTime()) or time();request.loadStarted=request.loadStarted or now
    if not request.requested and C_Item and C_Item.RequestLoadItemDataByID then request.requested=true;pcall(C_Item.RequestLoadItemDataByID,item.id) end
    if now-request.loadStarted>15 then resaleOpenRequest=nil;NokiUnifiedCore.SetWorking("resaleView",false);updateResaleStatus();print("Noki Market: item details did not load; try View again.") end
    return
  end
  resaleOpenRequest=nil;returningFromResaleView=true;resaleReturnItem=item
  NokiUnifiedTabs:HideAll()
  local opened,err=pcall(AuctionHouseFrame.SelectBrowseResult,AuctionHouseFrame,{itemKey=item.auctionKey,minPrice=item.ah})
  if not opened then returningFromResaleView=false;resaleReturnItem=nil;NokiUnifiedCore.SetWorking("resaleView",false);print("Noki Market: could not open item: "..tostring(err));if tabLib then tabLib:SetSelected(TAB_ID) end end
end
local function resaleVisible()
  if not panel or viewMode~="resale" then return false end
  if panel.IsVisible then return panel:IsVisible() end
  return panel:IsShown()
end
local function pumpResale()
  if not resaleVisible() then if resaleOpenRequest then resaleOpenRequest=nil;NokiUnifiedCore.SetWorking("resaleView",false) end;return end
  if resaleOpenRequest then tryOpenResale();return end
  if resaleInflight or NokiUnifiedCore.working.buyout or resaleIndex>#resaleQueue then return end
  local item=resaleQueue[resaleIndex]
  if item.live or item.soldOut then resaleIndex=resaleIndex+1;resaleChecked=resaleChecked+1;updateResaleStatus();return end
  local epoch=resaleEpoch;resaleIndex=resaleIndex+1;resaleInflight=true
  local ok=checkResaleItem(item,function(result,message)
    resaleInflight=false
    if epoch==resaleEpoch then
      if message=="Deferred for View" then resaleIndex=resaleIndex-1;item.checkError=nil
      else resaleChecked=resaleChecked+1;if not result or item.checkError then resaleUnavailable=resaleUnavailable+1 end end
      updateResaleStatus()
    end
    if resaleOpenRequest and resaleVisible() then tryOpenResale() end
  end)
  if not ok then resaleInflight=false;resaleIndex=resaleIndex-1 end
end
local function createPanel()
  if panel or not AuctionHouseFrame then return panel end
  panel=CreateFrame("Frame","NokiUnifiedMarketFlipPanel",AuctionHouseFrame,"BackdropTemplate")
  panel:Hide()
  panel:SetFrameStrata("DIALOG");panel:SetFrameLevel(AuctionHouseFrame:GetFrameLevel()+50)
  panel:SetPoint("TOPLEFT",AuctionHouseFrame,"TOPLEFT",12,-75);panel:SetPoint("BOTTOMRIGHT",AuctionHouseFrame,"BOTTOMRIGHT",-12,35)
  panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
  panel:SetBackdropColor(0.055,0.065,0.07,0.97);panel:SetBackdropBorderColor(0.22,0.29,0.28,1)
  title=makeText(panel,nil,16,-12,350,"GameFontNormalLarge");title:SetText("VENDOR FLIP FINDER")
  local scan=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");scan:SetSize(90,23);scan:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-215,-8);scan:SetText("Scan now");scan:SetScript("OnClick",function() if NokiUnifiedMarketRequestScan then NokiUnifiedMarketRequestScan() end end)
  local auto=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");auto:SetSize(88,23);auto:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-120,-8)
  local interval=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");interval:SetSize(88,23);interval:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-25,-8)
  local function updateControls() if NokiUnifiedCore then auto:SetText("Auto: " .. (NokiUnifiedCore.AutoScanEnabled() and "ON" or "OFF"));interval:SetText("Every " .. NokiUnifiedCore.AutoScanInterval() .. "m") end end
  auto:SetScript("OnClick",function() if NokiUnifiedMarketToggleAuto then NokiUnifiedMarketToggleAuto() end;updateControls() end)
  interval:SetScript("OnClick",function() if NokiUnifiedMarketCycleInterval then NokiUnifiedMarketCycleInterval() end;updateControls() end)
  updateControls()
  subtitle=makeText(panel,nil,16,-33,680,"GameFontHighlightSmall");subtitle:SetText("One-pack vendor cost vs sell price per unit. Enter filters; select a row for details.")
  local budgetLabel=makeText(panel,nil,18,-59,85,"GameFontNormalSmall");budgetLabel:SetText("MAX (SILVER)")
  budgetBox=CreateFrame("EditBox",nil,panel,"InputBoxTemplate");budgetBox:SetSize(50,24);budgetBox:SetPoint("TOPLEFT",panel,"TOPLEFT",105,-54);budgetBox:SetAutoFocus(false);budgetBox:SetNumeric(true);budgetBox:SetFontObject("GameFontHighlight");budgetBox:SetText(tostring((NokiBetaMarketDB and NokiBetaMarketDB.flipBudgetSilver) or 15))
  budgetBox:SetScript("OnEnterPressed",function(self) self:ClearFocus();calculate() end);budgetBox:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
  local minLabel=makeText(panel,nil,170,-59,90,"GameFontNormalSmall");minLabel:SetText("MIN EST./DAY")
  minSalesBox=CreateFrame("EditBox",nil,panel,"InputBoxTemplate");minSalesBox:SetSize(48,24);minSalesBox:SetPoint("TOPLEFT",panel,"TOPLEFT",260,-54);minSalesBox:SetAutoFocus(false);minSalesBox:SetFontObject("GameFontHighlight");minSalesBox:SetText(tostring((NokiBetaMarketDB and NokiBetaMarketDB.flipMinSalesPerDay) or 1));minSalesBox:SetScript("OnEnterPressed",function(self) self:ClearFocus();calculate() end);minSalesBox:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
  searchBox=CreateFrame("EditBox",nil,panel,"InputBoxTemplate");searchBox:SetSize(125,24);searchBox:SetPoint("TOPLEFT",panel,"TOPLEFT",330,-54);searchBox:SetAutoFocus(false);searchBox:SetMaxLetters(60);searchBox:SetScript("OnTextChanged",function() if panel and status then filterAndSort(true) end end);searchBox:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
  searchBox:SetScript("OnEnterPressed",function(self) self:ClearFocus();scrollOffset=0;if viewMode=="resale" then filterAndSort() else calculate() end end)
  searchHint=makeText(panel,nil,365,-80,130,"GameFontDisableSmall");searchHint:SetText("Search name, vendor or ID")
  sortButton=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");sortButton:SetSize(140,24);sortButton:SetPoint("TOPLEFT",panel,"TOPLEFT",470,-54);sortButton:SetText("Sort: " .. sortLabels[sortMode]);sortButton:SetScript("OnClick",function() sortMode=sortMode=="gain" and "roi" or sortMode=="roi" and "activity" or sortMode=="activity" and viewMode=="flips" and "gap" or "gain";gapAscending=false;sortButton:SetText("Sort: " .. (viewMode=="craft" and sortMode=="gain" and "Gain per craft" or sortLabels[sortMode]));filterAndSort(true) end)
  local pricing=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");pricing:SetSize(95,24);pricing:SetPoint("TOPLEFT",panel,"TOPLEFT",620,-54)
  local undercut=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");undercut:SetSize(110,24);undercut:SetPoint("TOPLEFT",panel,"TOPLEFT",720,-54)
  local function updatePricing()
    pricing:SetText(NokiBetaMarketDB.flipMatchPrice and "Match: ON" or "Match: OFF")
    undercut:SetText(NokiBetaMarketDB.flipMatchPrice and "Under 1c: OFF" or "Under 1c: ON")
  end
  local function setPricing(match) NokiBetaMarketDB.flipMatchPrice=match;updatePricing();calculate() end
  pricing:SetScript("OnClick",function() setPricing(true) end)
  undercut:SetScript("OnClick",function() setPricing(false) end)
  local function pricingTip(self)
    if GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_TOP");GameTooltip:SetText("Price used for profit calculations");GameTooltip:AddLine("Match the scanned low, or undercut it by 1 copper. This does not post an auction.",1,1,1,true);GameTooltip:Show() end
  end
  pricing:SetScript("OnEnter",pricingTip);undercut:SetScript("OnEnter",pricingTip)
  pricing:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end);undercut:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
  updatePricing()
  minProfitLabel=makeText(panel,nil,18,-80,125,"GameFontNormalSmall");minProfitLabel:SetText("MIN PACK GAIN (S)")
  minStackProfitBox=CreateFrame("EditBox",nil,panel,"InputBoxTemplate");minStackProfitBox:SetSize(48,20);minStackProfitBox:SetPoint("TOPLEFT",panel,"TOPLEFT",155,-74);minStackProfitBox:SetAutoFocus(false);minStackProfitBox:SetFontObject("GameFontHighlight");minStackProfitBox:SetText(tostring((NokiBetaMarketDB and NokiBetaMarketDB.flipMinPackProfitSilver) or 0));minStackProfitBox:SetScript("OnEnterPressed",function(self) self:ClearFocus();calculate() end);minStackProfitBox:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
  status=makeText(panel,nil,18,-101,690,"GameFontHighlightSmall");status:SetText("Waiting for auction data.")
  local header=CreateFrame("Frame",nil,panel,"BackdropTemplate");header:SetPoint("TOPLEFT",panel,"TOPLEFT",10,-122);header:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-10,-122);header:SetHeight(22);header:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});header:SetBackdropColor(0.13,0.18,0.17,1)
  local cols={{"ITEM / VENDOR",8,245},{"BUY / UNIT",265,95},{"SELL / UNIT",370,95},{"GAIN / UNIT",475,95},{"GAIN / PACK",580,100},{"ACTIVITY",690,90},{"LISTED",790,75},{"GAP",875,90}}
  for i,c in ipairs(cols) do local t=makeText(header,nil,c[2],-5,c[3],"GameFontNormalSmall");t:SetText(c[1]);headerTexts[i]=t end
  local gapHeader=CreateFrame("Button",nil,header);gapHeader:SetPoint("TOPLEFT",header,"TOPLEFT",875,0);gapHeader:SetSize(90,22)
  gapHeader:SetScript("OnClick",function()
    if viewMode~="flips" and viewMode~="lookup" then return end
    if sortMode=="gap" then gapAscending=not gapAscending else sortMode="gap";gapAscending=false end
    sortButton:SetText("Sort: "..sortLabels[sortMode]);filterAndSort(true)
  end)
  gapHeader:SetScript("OnEnter",function(self) if viewMode=="flips" or viewMode=="lookup" then GameTooltip:SetOwner(self,"ANCHOR_TOP");GameTooltip:AddLine("Sort by gap");GameTooltip:AddLine("Estimated sales per day minus the quantity listed. Click again to reverse.",1,1,1,true);GameTooltip:Show() end end)
  gapHeader:SetScript("OnLeave",function() GameTooltip:Hide() end)
  rows={}
  for i=1,ROWS_PER_PAGE do
    local row=CreateFrame("Button",nil,panel,"BackdropTemplate");row:SetPoint("TOPLEFT",panel,"TOPLEFT",10,-145-(i-1)*34);row:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-32,-145-(i-1)*34);row:SetHeight(33);row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});row:SetBackdropColor(i%2==0 and 0.10 or 0.075,0.10,0.11,0.95)
    row.name=makeText(row,nil,8,-4,245,"GameFontHighlightSmall");row.vendor=makeText(row,nil,8,-19,245,"GameFontDisableSmall")
    row.selling=makeText(row,nil,166,-4,88,"GameFontHighlightSmall");row.selling:SetJustifyH("RIGHT")
    row.buy=makeText(row,nil,265,-11,95);row.ah=makeText(row,nil,370,-11,95);row.gain=makeText(row,nil,475,-11,95);row.gain:SetTextColor(0.45,0.9,0.64);row.stackGain=makeText(row,nil,580,-11,100);row.stackGain:SetTextColor(0.45,0.9,0.64);row.activity=makeText(row,nil,690,-11,90);row.listed=makeText(row,nil,790,-11,75);row.gap=makeText(row,nil,875,-11,90)
    row.resaleView=CreateFrame("Button",nil,row,"UIPanelButtonTemplate");row.resaleView:SetSize(52,22);row.resaleView:SetPoint("TOPRIGHT",row,"TOPRIGHT",-5,-5);row.resaleView:SetText("View");row.resaleView:Hide();row.resaleView:SetScript("OnClick",function() if row.item then openResale(row.item) end end)
    row:SetScript("OnClick",function(self) if self.item then setSelected(self.item) end end);rows[i]=row
  end
  scrollbar=CreateFrame("Slider","NokiUnifiedMarketResultsScrollBar",panel,"UIPanelScrollBarTemplate")
  scrollbar:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-14,-161);scrollbar:SetSize(16,195)
  scrollbar:SetMinMaxValues(0,0);scrollbar:SetValueStep(1)
  if scrollbar.SetObeyStepOnDrag then scrollbar:SetObeyStepOnDrag(true) end
  scrollbar:SetScript("OnValueChanged",function(_,value)
    if updatingScrollbar then return end
    local nextOffset=math.floor(value+0.5)
    if nextOffset~=scrollOffset then scrollOffset=nextOffset;render() end
  end)
  local function onWheel(_,delta)
    local maxOffset=math.max(0,#filtered-ROWS_PER_PAGE)
    local nextOffset=math.max(0,math.min(maxOffset,scrollOffset-delta))
    if nextOffset~=scrollOffset then scrollOffset=nextOffset;render() end
  end
  panel:EnableMouseWheel(true);panel:SetScript("OnMouseWheel",onWheel)
  for _,row in ipairs(rows) do row:EnableMouseWheel(true);row:SetScript("OnMouseWheel",onWheel) end
  scrollbar:EnableMouseWheel(true);scrollbar:SetScript("OnMouseWheel",onWheel)
  pageText=makeText(panel,nil,18,-391,450,"GameFontHighlightSmall")
  detailTitle=makeText(panel,nil,18,-416,850,"GameFontNormalSmall")
  detailBody=makeText(panel,nil,18,-432,850,"GameFontHighlightSmall");detailBody:SetWordWrap(true)
  resaleCheckButton=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");resaleCheckButton:SetSize(105,22);resaleCheckButton:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-115,-411);resaleCheckButton:SetText("Recheck")
  resaleCheckButton:SetScript("OnClick",function()
    if viewMode=="resale" then checkResaleItem(selectedItem) end
  end)
  resaleViewButton=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");resaleViewButton:SetSize(80,22);resaleViewButton:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-25,-411);resaleViewButton:SetText("View")
  resaleViewButton:SetScript("OnClick",function()
    openResale(selectedItem)
  end)
  flipControls={budgetLabel,budgetBox,minLabel,minSalesBox,minProfitLabel,minStackProfitBox,sortButton,pricing,undercut}
  modeButton=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");modeButton:SetSize(125,22);modeButton:SetPoint("TOPLEFT",panel,"TOPLEFT",220,-77)
  knownButton=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");knownButton:SetSize(125,22);knownButton:SetPoint("TOPLEFT",panel,"TOPLEFT",335,-77)
  knownButton:SetScript("OnClick",function() NokiBetaMarketDB.craftKnownOnly=not NokiBetaMarketDB.craftKnownOnly;knownButton:SetText(NokiBetaMarketDB.craftKnownOnly and "Known only" or "All recipes");calculate() end)
  captureButton=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");captureButton:SetSize(110,22);captureButton:SetPoint("TOPLEFT",panel,"TOPLEFT",590,-77);captureButton:SetText("Capture recipes");captureButton:SetScript("OnClick",function() if NokiUnifiedMarketCaptureRecipes then NokiUnifiedMarketCaptureRecipes();calculate() end end)
  local importButton=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");importButton:SetSize(115,22);importButton:SetPoint("TOPLEFT",panel,"TOPLEFT",845,-77);importButton:SetText("Import data");importButton:SetScript("OnClick",function() NokiUnifiedCore.ShowImport() end)
  local applyButton=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");applyButton:SetSize(110,22);applyButton:SetPoint("TOPLEFT",panel,"TOPLEFT",470,-77);applyButton:SetText("Apply / Search");applyButton:SetScript("OnClick",function() scrollOffset=0;calculate() end)
  applyMode=function(preserveResale)
    local lookup=viewMode=="lookup";local resale=viewMode=="resale";local simple=lookup or resale;local craft=viewMode=="craft"
    if craft and sortMode=="gap" then sortMode="gain" end
    applyButton:SetText(resale and "Refresh list" or "Apply / Search")
    searchBox:ClearAllPoints();searchBox:SetPoint("TOPLEFT",panel,"TOPLEFT",simple and 90 or 330,-54)
    searchHint:ClearAllPoints();searchHint:SetPoint("TOPLEFT",panel,"TOPLEFT",simple and 18 or 365,simple and -59 or -80);searchHint:SetText(simple and "SEARCH" or "Search name, vendor or ID")
    modeButton:ClearAllPoints();modeButton:SetPoint("TOPLEFT",panel,"TOPLEFT",simple and 355 or 220,simple and -54 or -77)
    applyButton:ClearAllPoints();applyButton:SetPoint("TOPLEFT",panel,"TOPLEFT",simple and 235 or 470,simple and -54 or -77)
    importButton:ClearAllPoints();importButton:SetPoint("TOPLEFT",panel,"TOPLEFT",simple and 495 or 845,simple and -54 or -77)
    for _,control in ipairs(flipControls) do control:SetShown(not simple) end
    resaleCheckButton:SetShown(resale);resaleViewButton:SetShown(resale);detailTitle:SetWidth(resale and 600 or 850);detailBody:SetWidth(resale and 650 or 850)
    knownButton:SetShown(craft);captureButton:SetShown(craft);searchHint:SetShown(not craft)
    knownButton:SetText(NokiBetaMarketDB.craftKnownOnly and "Known only" or "All recipes")
    minProfitLabel:SetText(craft and "MIN CRAFT GAIN (S)" or "MIN PACK GAIN (S)")
    sortButton:SetText("Sort: "..(craft and sortMode=="gain" and "Gain per craft" or sortLabels[sortMode]))
    budgetBox:SetText(tostring(craft and (NokiBetaMarketDB.craftBudgetSilver or "") or (NokiBetaMarketDB.flipBudgetSilver or 15)))
    minSalesBox:SetText(tostring(craft and (NokiBetaMarketDB.craftMinSales or 1) or (NokiBetaMarketDB.flipMinSalesPerDay or 1)))
    minStackProfitBox:SetText(tostring(craft and (NokiBetaMarketDB.craftMinProfit or 0) or (NokiBetaMarketDB.flipMinPackProfitSilver or 0)))
    modeButton:SetShown(not craft)
    modeButton:SetText(lookup and "Vendor flips" or resale and "Item lookup" or "Vendor resale")
    title:SetText(lookup and "ITEM LOOKUP" or resale and "SELL TO VENDOR" or craft and "CRAFTING PROFIT" or "VENDOR FLIP FINDER")
    subtitle:SetText(lookup and "Search loaded items by name, vendor or ID." or resale and "Automatically checks all listings priced below each item's vendor value." or craft and "Buy materials at AH lows; profit is per craft. Capture recipes with a profession open." or "One-pack vendor cost vs sell price per unit. Select a row for details.")
    local labels=resale and {"ITEM","AH / UNIT","VENDOR / UNIT","GAIN / UNIT","BUY QTY","BUY TOTAL","PROFIT TOTAL","VIEW"} or lookup and {"ITEM / VARIANT","VENDOR / UNIT","AH LOW / UNIT","LISTED","VENDOR PACK","EST. / DAY","","GAP"} or craft and {"RECIPE / PROFESSION","COST / CRAFT","SELL / UNIT","GAIN / CRAFT","YIELD","EST. / DAY","",""} or {"ITEM / VENDOR","BUY / UNIT","SELL / UNIT","GAIN / UNIT","GAIN / PACK","EST. / DAY","LISTED","GAP"}
    for i,label in ipairs(labels) do headerTexts[i]:SetText(label) end
    if preserveResale then render() else calculate() end
  end
  modeButton:SetScript("OnClick",function()
    if viewMode=="resale" and resaleCache then resaleCache.scrollOffset=scrollOffset;resaleCache.selectedID=selectedID end
    viewMode=viewMode=="flips" and "resale" or viewMode=="resale" and "lookup" or "flips";marketViewMode=viewMode;scrollOffset=0
    local preserve=viewMode=="resale" and resaleCache~=nil
    if preserve then results=resaleCache.results;filterAndSort(false);scrollOffset=resaleCache.scrollOffset or 0;selectedID=resaleCache.selectedID;updateResaleStatus() end
    applyMode(preserve)
  end)
  applyMode()
  panel:SetScript("OnShow",function()
    updateControls()
    if skipNextMarketRefresh or (viewMode=="resale" and resaleCache) then skipNextMarketRefresh=false;render() else calculate() end
  end);panel:Hide()
  return panel
end
function NokiUnifiedMarketExplainItem(id)
  local scan=latestSnapshot()
  if not scan then print("Noki Market: no completed market scan available."); return end
  local lowest, quantity
  for _,row in ipairs(scan.rows or {}) do
    if row.itemID==id and (row.itemSuffix or 0)==0 and (row.battlePetSpeciesID or 0)==0 and type(row.price)=="number" and row.price>0 and (not lowest or row.price<lowest) then lowest=row.price;quantity=row.quantity end
  end
  if not lowest then print("Noki Market: item " .. id .. " has no matching price in the last completed scan.");return end
  local sell=math.floor(lowest)-((NokiBetaMarketDB and NokiBetaMarketDB.flipMatchPrice) and 0 or 1)
  local remote=marketActivity(id,usableHistory())
  print("Noki Market: item " .. id .. "; last scan low " .. copper(lowest) .. "; proposed sale " .. copper(sell) .. "; listed " .. tostring(quantity or "unknown") .. "; est/day " .. tostring(remote and remote.sales or "unknown") .. ".")
  if sell<1 then print("Noki Market: excluded because a 1c auction cannot be undercut by 1c. Use MATCH if desired.");return end
  local budget=tonumber(NokiBetaMarketDB.flipBudgetSilver)
  if budget then budget=budget*100 end
  local minimum=tonumber(NokiBetaMarketDB.flipMinSalesPerDay) or 0
  local offers=0
  for _,offer in ipairs(NokiUnifiedMarketVendorData or {}) do
    if offer[1]==id then
      offers=offers+1
      local cost, stack=offer[4],offer[5]
      local gain=(type(cost)=="number" and type(stack)=="number" and stack>0) and (sell*0.95-cost/stack) or nil
      print("Noki Market: " .. tostring(offer[3]) .. ": " .. copper(cost) .. " for " .. tostring(stack) .. "; estimated gain/unit " .. copper(gain) .. (cost and budget and cost>budget and " (over budget)" or "") .. ".")
      if offers>=3 then break end
    end
  end
  if offers==0 then print("Noki Market: no vendor offer is in the bundled reference dataset.") end
  if minimum > 0 then
    if not remote or type(remote.sales)~="number" then print("Noki Market: activity is unknown; the activity filter excludes this item.")
    elseif remote.sales<minimum then print("Noki Market: estimated daily activity is below the configured minimum.") end
  end
  print("Noki Market: also check the minimum pack gain and any active search text. Estimates exclude deposits.")
end
local function registerTab()
  if tabLib or not AuctionHouseFrame or not NokiUnifiedTabs then return end
  local lib=NokiUnifiedTabs
  local frame=createPanel()
  local function makeHost(mode)
    local host=CreateFrame("Frame",nil,AuctionHouseFrame)
    host:Hide()
    local previousWidth,previousHeight
    host:SetPoint("TOPLEFT",AuctionHouseFrame,"TOPLEFT",12,-75)
    host:SetPoint("BOTTOMRIGHT",AuctionHouseFrame,"BOTTOMRIGHT",-12,35)
    host:SetScript("OnShow",function(self)
      if not previousWidth then
        previousWidth,previousHeight=AuctionHouseFrame:GetWidth(),AuctionHouseFrame:GetHeight()
        AuctionHouseFrame:SetSize(previousWidth+220,previousHeight+160)
      end
      frame:Hide();frame:SetParent(self);frame:ClearAllPoints();frame:SetAllPoints(self)
      local preserve=mode=="flips" and marketViewMode=="resale" and resaleCache~=nil
      returningFromResaleView=false
      viewMode=mode=="flips" and marketViewMode or mode;if not preserve then scrollOffset=0 end
      if preserve then results=resaleCache.results;filterAndSort(false);scrollOffset=resaleCache.scrollOffset or 0;selectedID=resaleCache.selectedID;updateResaleStatus() end
      applyMode(preserve);skipNextMarketRefresh=preserve;frame:Show()
      resaleReturnItem=nil
    end)
    host:SetScript("OnHide",function()
      if viewMode=="resale" and resaleCache then resaleCache.scrollOffset=scrollOffset;resaleCache.selectedID=selectedID end
      if previousWidth and previousHeight then AuctionHouseFrame:SetSize(previousWidth,previousHeight) end
      previousWidth=nil;previousHeight=nil
    end)
    host:Hide()
    return host
  end
  local success,err=pcall(function()
    if not lib:DoesIDExist(TAB_ID) then lib:CreateTab(TAB_ID,makeHost("flips"),"Noki Market","Noki Market") end
  end)
  if success then tabLib=lib else print("Noki Market: tab registration failed: "..tostring(err)) end
end
local events=CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
events:RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent",function(_,event,id)
  if event=="AUCTION_HOUSE_CLOSED" then returningFromResaleView=false;resaleReturnItem=nil;skipNextMarketRefresh=false;resaleOpenRequest=nil;resaleCache=nil;resaleEpoch=resaleEpoch+1;NokiUnifiedCore.SetWorking("resaleView",false)
  elseif event=="ITEM_KEY_ITEM_INFO_RECEIVED" then if resaleOpenRequest and resaleOpenRequest.item.id==id and resaleVisible() then tryOpenResale() end
  elseif C_Timer and C_Timer.After then C_Timer.After(0.5,registerTab) else registerTab() end
end)
local resaleElapsed,statusElapsed=0,0;events:SetScript("OnUpdate",function(_,delta)
  resaleElapsed=resaleElapsed+delta;statusElapsed=statusElapsed+delta
  if statusElapsed>=30 then statusElapsed=0;if resaleVisible() then updateResaleStatus() end end
  if resaleElapsed<.75 then return end;resaleElapsed=0;pumpResale()
end)
function NokiUnifiedMarketRefreshFlips()
  if panel and panel:IsShown() then if viewMode=="resale" then updateResaleStatus() else calculate() end end
end
function NokiUnifiedMarketOwnedChanged() if panel and panel:IsShown() and viewMode=="flips" then render() end end
NokiUnifiedCore.Subscribe(function(event)
  if event~="complete" then return end
  resaleCache=nil
  if resaleVisible() then calculateResale() end
end)
function NokiUnifiedMarketShowCrafting()
  if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then print("Noki Market: open the auction house first.");return end
  registerTab()
  if tabLib then tabLib:SetSelected(CRAFT_TAB_ID) else print("Noki Market: auction tab not ready.") end
end
function NokiUnifiedMarketShowFlips()
  if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then print("Noki Market: open the auction house first.");return end
  registerTab()
  if tabLib then tabLib:SetSelected(TAB_ID) else print("Noki Market: auction tab not ready. Reopen the auction house.") end
end
SLASH_NOKIUNIFIEDMARKETFLIPS1="/nokiunimflips"
SlashCmdList.NOKIUNIFIEDMARKETFLIPS=NokiUnifiedMarketShowFlips
SLASH_NOKIUNIFIEDMARKETCRAFTTAB1="/nokiunimcrafttab"
SlashCmdList.NOKIUNIFIEDMARKETCRAFTTAB=NokiUnifiedMarketShowCrafting
