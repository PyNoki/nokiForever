-- Noki Market auction-house tab. Vendor observations are reference data.
local TAB_ID = "NokiUnifiedMarketFlips"
local CRAFT_TAB_ID = "NokiUnifiedMarketCrafting"
local applyMode
local panel, tabLib, budgetBox, minSalesBox, minStackProfitBox, searchBox, sortButton, status, pageText, detailTitle, detailBody
local rows, results, filtered = {}, {}, {}
local scrollOffset, sortMode, selectedID = 0, "gain", nil
local scrollbar, updatingScrollbar
local viewMode, modeButton, headerTexts, flipControls, title, subtitle = "lookup", nil, {}, {}, nil, nil
local knownButton, captureButton, minProfitLabel, searchHint
local sortLabels = {gain="Gain per unit", roi="Return %", activity="Est. sales/day"}
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
  if not NokiUnifiedMarketDB or not NokiUnifiedMarketDB.markets then return nil end
  return NokiUnifiedMarketDB.markets[(GetRealmName() or "Unknown realm") .. " - " .. (UnitFactionGroup("player") or "Unknown faction")]
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
  if not item then
    detailTitle:SetText("SELECT AN ITEM")
    detailBody:SetText("Choose a row to see vendor pack details and market history.")
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
      row.name:SetText(item.name .. "  |cff829494#" .. item.id .. "|r")
      if viewMode == "craft" then
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
      row.activity:SetText(viewMode == "craft" and (tostring(item.sales).."/day") or (item.remote and item.remote.sales ~= nil and tostring(item.remote.sales) .. "/day" or "--"))
      local listed=item.quantity
      row.listed:SetText(viewMode=="flips" and type(listed)=="number" and tostring(listed) or "--")
      row.listed:SetShown(viewMode=="flips")
      row.gap:SetShown(viewMode~="craft")
      if viewMode~="craft" and not item.variant and type(listed)=="number" and type(item.remote and item.remote.sales)=="number" then
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
  pageText:SetText((#filtered == 0 and "0" or (scrollOffset + 1) .. "-" .. math.min(scrollOffset + ROWS_PER_PAGE, #filtered)) .. " OF " .. #filtered .. (viewMode == "lookup" and " ITEMS" or " CANDIDATES") .. "  |  SCROLL TO BROWSE")
end
local function filterAndSort(resetScroll)
  local text = (searchBox:GetText() or ""):lower():match("^%s*(.-)%s*$")
  filtered = {}
  for _, item in ipairs(results) do
    if text == "" or item.name:lower():find(text,1,true) or (item.vendor or ""):lower():find(text,1,true) or tostring(item.id):find(text,1,true) then filtered[#filtered + 1] = item end
  end
  table.sort(filtered, function(a,b)
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
  local catalog = NokiUnifiedMarketDB.itemCatalog or {}
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
local function calculate()
  if not panel or not NokiUnifiedMarketDB then return end
  if viewMode == "lookup" then calculateLookup(); return end
  if viewMode == "craft" then
    results={};selectedID=nil
    local budget=tonumber(budgetBox:GetText());local sales=tonumber(minSalesBox:GetText());local gain=tonumber(minStackProfitBox:GetText())
    if not sales or sales<0 or not gain or gain<0 or (budgetBox:GetText():match("%S") and (not budget or budget<0)) then
      status:SetText("Enter non-negative filters; max spend may be blank.");filterAndSort();return
    end
    NokiUnifiedMarketDB.craftBudgetSilver=budgetBox:GetText();NokiUnifiedMarketDB.craftMinSales=sales;NokiUnifiedMarketDB.craftMinProfit=gain
    local found,err,stats=NokiUnifiedMarketCraftCandidates(gain,sales,NokiUnifiedMarketDB.flipMatchPrice==true,NokiUnifiedMarketDB.craftKnownOnly==true,budget and budget*100 or nil)
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
  NokiUnifiedMarketDB.flipMinPackProfitSilver=minPackSilver or ""
  NokiUnifiedMarketDB.flipBudgetSilver=silver or ""
  NokiUnifiedMarketDB.flipMinSalesPerDay=minSales or ""
  local budget=silver and math.floor(silver*100) or nil
  local matchPrice=NokiUnifiedMarketDB.flipMatchPrice == true
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
  budgetBox=CreateFrame("EditBox",nil,panel,"InputBoxTemplate");budgetBox:SetSize(50,24);budgetBox:SetPoint("TOPLEFT",panel,"TOPLEFT",105,-54);budgetBox:SetAutoFocus(false);budgetBox:SetNumeric(true);budgetBox:SetFontObject("GameFontHighlight");budgetBox:SetText(tostring((NokiUnifiedMarketDB and NokiUnifiedMarketDB.flipBudgetSilver) or 15))
  budgetBox:SetScript("OnEnterPressed",function(self) self:ClearFocus();calculate() end);budgetBox:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
  local minLabel=makeText(panel,nil,170,-59,90,"GameFontNormalSmall");minLabel:SetText("MIN EST./DAY")
  minSalesBox=CreateFrame("EditBox",nil,panel,"InputBoxTemplate");minSalesBox:SetSize(48,24);minSalesBox:SetPoint("TOPLEFT",panel,"TOPLEFT",260,-54);minSalesBox:SetAutoFocus(false);minSalesBox:SetFontObject("GameFontHighlight");minSalesBox:SetText(tostring((NokiUnifiedMarketDB and NokiUnifiedMarketDB.flipMinSalesPerDay) or 1));minSalesBox:SetScript("OnEnterPressed",function(self) self:ClearFocus();calculate() end);minSalesBox:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
  searchBox=CreateFrame("EditBox",nil,panel,"InputBoxTemplate");searchBox:SetSize(125,24);searchBox:SetPoint("TOPLEFT",panel,"TOPLEFT",330,-54);searchBox:SetAutoFocus(false);searchBox:SetMaxLetters(60);searchBox:SetScript("OnTextChanged",function() if panel and status then filterAndSort(true) end end);searchBox:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
  searchBox:SetScript("OnEnterPressed",function(self) self:ClearFocus();scrollOffset=0;calculate() end)
  searchHint=makeText(panel,nil,365,-80,130,"GameFontDisableSmall");searchHint:SetText("Search name, vendor or ID")
  sortButton=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");sortButton:SetSize(140,24);sortButton:SetPoint("TOPLEFT",panel,"TOPLEFT",470,-54);sortButton:SetText("Sort: " .. sortLabels[sortMode]);sortButton:SetScript("OnClick",function() sortMode=sortMode=="gain" and "roi" or sortMode=="roi" and "activity" or "gain";sortButton:SetText("Sort: " .. (viewMode=="craft" and sortMode=="gain" and "Gain per craft" or sortLabels[sortMode]));filterAndSort(true) end)
  local pricing=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");pricing:SetSize(95,24);pricing:SetPoint("TOPLEFT",panel,"TOPLEFT",620,-54)
  local undercut=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");undercut:SetSize(110,24);undercut:SetPoint("TOPLEFT",panel,"TOPLEFT",720,-54)
  local function updatePricing()
    pricing:SetText(NokiUnifiedMarketDB.flipMatchPrice and "Match: ON" or "Match: OFF")
    undercut:SetText(NokiUnifiedMarketDB.flipMatchPrice and "Under 1c: OFF" or "Under 1c: ON")
  end
  local function setPricing(match) NokiUnifiedMarketDB.flipMatchPrice=match;updatePricing();calculate() end
  pricing:SetScript("OnClick",function() setPricing(true) end)
  undercut:SetScript("OnClick",function() setPricing(false) end)
  local function pricingTip(self)
    if GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_TOP");GameTooltip:SetText("Price used for profit calculations");GameTooltip:AddLine("Match the scanned low, or undercut it by 1 copper. This does not post an auction.",1,1,1,true);GameTooltip:Show() end
  end
  pricing:SetScript("OnEnter",pricingTip);undercut:SetScript("OnEnter",pricingTip)
  pricing:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end);undercut:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
  updatePricing()
  minProfitLabel=makeText(panel,nil,18,-80,125,"GameFontNormalSmall");minProfitLabel:SetText("MIN PACK GAIN (S)")
  minStackProfitBox=CreateFrame("EditBox",nil,panel,"InputBoxTemplate");minStackProfitBox:SetSize(48,20);minStackProfitBox:SetPoint("TOPLEFT",panel,"TOPLEFT",155,-74);minStackProfitBox:SetAutoFocus(false);minStackProfitBox:SetFontObject("GameFontHighlight");minStackProfitBox:SetText(tostring((NokiUnifiedMarketDB and NokiUnifiedMarketDB.flipMinPackProfitSilver) or 0));minStackProfitBox:SetScript("OnEnterPressed",function(self) self:ClearFocus();calculate() end);minStackProfitBox:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
  status=makeText(panel,nil,18,-101,690,"GameFontHighlightSmall");status:SetText("Waiting for auction data.")
  local header=CreateFrame("Frame",nil,panel,"BackdropTemplate");header:SetPoint("TOPLEFT",panel,"TOPLEFT",10,-122);header:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-10,-122);header:SetHeight(22);header:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});header:SetBackdropColor(0.13,0.18,0.17,1)
  local cols={{"ITEM / VENDOR",8,245},{"BUY / UNIT",265,95},{"SELL / UNIT",370,95},{"GAIN / UNIT",475,95},{"GAIN / PACK",580,100},{"ACTIVITY",690,90},{"LISTED",790,75},{"GAP / 1D",875,90}}
  for i,c in ipairs(cols) do local t=makeText(header,nil,c[2],-5,c[3],"GameFontNormalSmall");t:SetText(c[1]);headerTexts[i]=t end
  rows={}
  for i=1,ROWS_PER_PAGE do
    local row=CreateFrame("Button",nil,panel,"BackdropTemplate");row:SetPoint("TOPLEFT",panel,"TOPLEFT",10,-145-(i-1)*34);row:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-32,-145-(i-1)*34);row:SetHeight(33);row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});row:SetBackdropColor(i%2==0 and 0.10 or 0.075,0.10,0.11,0.95)
    row.name=makeText(row,nil,8,-4,245,"GameFontHighlightSmall");row.vendor=makeText(row,nil,8,-19,245,"GameFontDisableSmall")
    row.buy=makeText(row,nil,265,-11,95);row.ah=makeText(row,nil,370,-11,95);row.gain=makeText(row,nil,475,-11,95);row.gain:SetTextColor(0.45,0.9,0.64);row.stackGain=makeText(row,nil,580,-11,100);row.stackGain:SetTextColor(0.45,0.9,0.64);row.activity=makeText(row,nil,690,-11,90);row.listed=makeText(row,nil,790,-11,75);row.gap=makeText(row,nil,875,-11,90)
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
  flipControls={budgetLabel,budgetBox,minLabel,minSalesBox,minProfitLabel,minStackProfitBox,sortButton,pricing,undercut}
  modeButton=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");modeButton:SetSize(125,22);modeButton:SetPoint("TOPLEFT",panel,"TOPLEFT",220,-77)
  knownButton=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");knownButton:SetSize(125,22);knownButton:SetPoint("TOPLEFT",panel,"TOPLEFT",335,-77)
  knownButton:SetScript("OnClick",function() NokiUnifiedMarketDB.craftKnownOnly=not NokiUnifiedMarketDB.craftKnownOnly;knownButton:SetText(NokiUnifiedMarketDB.craftKnownOnly and "Known only" or "All recipes");calculate() end)
  captureButton=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");captureButton:SetSize(110,22);captureButton:SetPoint("TOPLEFT",panel,"TOPLEFT",590,-77);captureButton:SetText("Capture recipes");captureButton:SetScript("OnClick",function() if NokiUnifiedMarketCaptureRecipes then NokiUnifiedMarketCaptureRecipes();calculate() end end)
  local importButton=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");importButton:SetSize(115,22);importButton:SetPoint("TOPLEFT",panel,"TOPLEFT",845,-77);importButton:SetText("Import data");importButton:SetScript("OnClick",function() NokiUnifiedCore.ShowImport() end)
  local applyButton=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");applyButton:SetSize(110,22);applyButton:SetPoint("TOPLEFT",panel,"TOPLEFT",470,-77);applyButton:SetText("Apply / Search");applyButton:SetScript("OnClick",function() scrollOffset=0;calculate() end)
  applyMode=function()
    local lookup=viewMode=="lookup";local craft=viewMode=="craft"
    for _,control in ipairs(flipControls) do control:SetShown(not lookup) end
    knownButton:SetShown(craft);captureButton:SetShown(craft);searchHint:SetShown(not craft)
    knownButton:SetText(NokiUnifiedMarketDB.craftKnownOnly and "Known only" or "All recipes")
    minProfitLabel:SetText(craft and "MIN CRAFT GAIN (S)" or "MIN PACK GAIN (S)")
    sortButton:SetText("Sort: "..(craft and sortMode=="gain" and "Gain per craft" or sortLabels[sortMode]))
    budgetBox:SetText(tostring(craft and (NokiUnifiedMarketDB.craftBudgetSilver or "") or (NokiUnifiedMarketDB.flipBudgetSilver or 15)))
    minSalesBox:SetText(tostring(craft and (NokiUnifiedMarketDB.craftMinSales or 1) or (NokiUnifiedMarketDB.flipMinSalesPerDay or 1)))
    minStackProfitBox:SetText(tostring(craft and (NokiUnifiedMarketDB.craftMinProfit or 0) or (NokiUnifiedMarketDB.flipMinPackProfitSilver or 0)))
    modeButton:SetShown(not craft)
    modeButton:SetText(lookup and "Vendor flips" or "Item lookup")
    title:SetText(lookup and "ITEM LOOKUP" or craft and "CRAFTING PROFIT" or "VENDOR FLIP FINDER")
    subtitle:SetText(lookup and "Search loaded items by name, vendor or ID." or craft and "Buy materials at AH lows; profit is per craft. Capture recipes with a profession open." or "One-pack vendor cost vs sell price per unit. Select a row for details.")
    local labels=lookup and {"ITEM / VARIANT","VENDOR / UNIT","AH LOW / UNIT","LISTED","VENDOR PACK","EST. / DAY","","GAP / 1D"} or craft and {"RECIPE / PROFESSION","COST / CRAFT","SELL / UNIT","GAIN / CRAFT","YIELD","EST. / DAY","",""} or {"ITEM / VENDOR","BUY / UNIT","SELL / UNIT","GAIN / UNIT","GAIN / PACK","EST. / DAY","LISTED","GAP / 1D"}
    for i,label in ipairs(labels) do headerTexts[i]:SetText(label) end
    calculate()
  end
  modeButton:SetScript("OnClick",function() viewMode=viewMode=="lookup" and "flips" or "lookup";scrollOffset=0;applyMode() end)
  applyMode()
  panel:SetScript("OnShow",function() updateControls();calculate() end);panel:Hide()
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
  local sell=math.floor(lowest)-((NokiUnifiedMarketDB and NokiUnifiedMarketDB.flipMatchPrice) and 0 or 1)
  local remote=marketActivity(id,usableHistory())
  print("Noki Market: item " .. id .. "; last scan low " .. copper(lowest) .. "; proposed sale " .. copper(sell) .. "; listed " .. tostring(quantity or "unknown") .. "; est/day " .. tostring(remote and remote.sales or "unknown") .. ".")
  if sell<1 then print("Noki Market: excluded because a 1c auction cannot be undercut by 1c. Use MATCH if desired.");return end
  local budget=tonumber(NokiUnifiedMarketDB.flipBudgetSilver)
  if budget then budget=budget*100 end
  local minimum=tonumber(NokiUnifiedMarketDB.flipMinSalesPerDay) or 0
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
      viewMode=mode;scrollOffset=0;applyMode();frame:Show()
    end)
    host:SetScript("OnHide",function()
      if previousWidth and previousHeight then AuctionHouseFrame:SetSize(previousWidth,previousHeight) end
      previousWidth=nil;previousHeight=nil
    end)
    host:Hide()
    return host
  end
  local success,err=pcall(function()
    if not lib:DoesIDExist(TAB_ID) then lib:CreateTab(TAB_ID,makeHost("lookup"),"Noki Market","Noki Market") end
  end)
  if success then tabLib=lib else print("Noki Market: tab registration failed: "..tostring(err)) end
end
local events=CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:SetScript("OnEvent",function() if C_Timer and C_Timer.After then C_Timer.After(0.5,registerTab) else registerTab() end end)
function NokiUnifiedMarketRefreshFlips() if panel and panel:IsShown() then calculate() end end
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
