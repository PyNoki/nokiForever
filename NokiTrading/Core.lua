-- Noki local beta: native price-table reader and auction browse scanner.
NokiUnifiedCore = {listeners={}, phase="idle", active=false, working={}}
local core=NokiUnifiedCore
local function now() return (GetServerTime and GetServerTime()) or time() end
local regions={[1]="us",[2]="kr",[3]="eu",[4]="tw",[5]="cn"}
function core.Market()
  local faction=UnitFactionGroup and UnitFactionGroup("player")
  local region=GetCurrentRegion and regions[GetCurrentRegion()]
  local realm=GetRealmName and GetRealmName()
  if type(faction)~="string" or not region or type(realm)~="string" then return nil,"Cannot identify faction, region or realm" end
  local words={};for word in realm:lower():gmatch("[%a]+") do words[word]=true end
  local p=words.pvp or words.jcj or words.jxj;local r=words.rp or words.jdr or words.gdr or words.rol
  local rules=words.hardcore and "hardcore" or (words.rppvp or (p and r)) and "rppvp" or p and "pvp" or r and "rp" or (words.normal or words.pve or words.jce or words.jve) and "normal"
  if not rules then return nil,"Cannot identify realm ruleset" end
  return "forever/"..rules.."/"..faction:lower().."/"..region
end
function core.AutoScanEnabled() return not NokiUnifiedCoreDB or NokiUnifiedCoreDB.autoScan~=false end
function core.AutoScanInterval() return math.max(30,tonumber(NokiUnifiedCoreDB and NokiUnifiedCoreDB.scanIntervalMinutes) or 30) end
function core.SetAutoScan(enabled) if NokiUnifiedCoreDB then NokiUnifiedCoreDB.autoScan=enabled and true or false end end
function core.SetAutoScanInterval(minutes) if NokiUnifiedCoreDB then NokiUnifiedCoreDB.scanIntervalMinutes=math.max(30,math.floor(tonumber(minutes) or 30)) end end
function core.AutoScanDue()
  if not core.AutoScanEnabled() then return false end
  local market=core.Market();if not market then return false end
  local attempts=NokiUnifiedCoreDB and NokiUnifiedCoreDB.lastScanAttempt
  local book=NokiUnifiedCoreDB and NokiUnifiedCoreDB.prices and NokiUnifiedCoreDB.prices[market]
  local last=math.max((attempts and attempts[market]) or 0,(book and book.observed) or 0)
  return last==0 or now()-last>=core.AutoScanInterval()*60
end
-- Restore quantities from the already-saved complete scan when its timestamp
-- matches the price cache. This does not rewrite or fabricate a market scan.
function core.RestoreQuantitiesFromScan()
  local market=core.Market();local book=market and NokiUnifiedCoreDB and NokiUnifiedCoreDB.prices and NokiUnifiedCoreDB.prices[market]
  if not book or type(book.items)~="table" or type(book.observed)~="number" then return end
  if book.quantitiesRestoredAt==book.observed then return end
  local key=(GetRealmName() or "Unknown realm").." - "..(UnitFactionGroup("player") or "Unknown faction")
  local scan
  for _,db in ipairs({NokiUnifiedMarketDB or false,NokiUnifiedCraftDB or false}) do
    local entry=db and db.markets and db.markets[key]
    local candidate=entry and entry.latestScan
    if candidate and candidate.source=="noki_beta_browse_v2" and candidate.completed==book.observed and type(candidate.rows)=="table" then scan=candidate;break end
  end
  if not scan then return end
  local seen,unknown={},{}
  for _,row in ipairs(scan.rows) do
    local item=row.itemID and book.items[row.itemID]
    local variant=tostring(row.itemLevel or 0)..":"..tostring(row.itemSuffix or 0)..":"..tostring(row.battlePetSpeciesID or 0)
    if item and not item.carried and item.variant==variant then
      local qty=type(row.quantity)=="number" and row.quantity>=0 and row.quantity or nil
      if seen[row.itemID] and item.quantity~=qty then unknown[row.itemID]=true end
      if not seen[row.itemID] then item.quantity=qty;item.observed=book.observed;seen[row.itemID]=true end
    end
  end
  for id in pairs(unknown) do book.items[id].quantity=nil end
  book.rowCount=#scan.rows;book.quantitiesRestoredAt=book.observed
end
local tableCache={}
local function getTable()
  local market,err=core.Market();if not market then return nil,err end
  local src=type(NokiUnifiedTables)=="table" and NokiUnifiedTables[market]
  local imported=NokiUnifiedCoreDB and NokiUnifiedCoreDB.importedTables and NokiUnifiedCoreDB.importedTables[market]
  if type(imported)=="table" and type(imported.text)=="string" and (type(src)~="table" or (tonumber(imported.updated) or 0)>(tonumber(src.updated) or 0)) then src=imported end
  if type(src)~="table" or type(src.text)~="string" then return nil,"No market table; use the Noki Market Updater" end
  local cache=tableCache[market]
  if cache and cache.src==src then return cache end
  local rows={};local n=0
  for line in src.text:gmatch("[^\n;]+") do
    local id,median,low,qty,m7,m30,lo,hi,sold=line:match("^(%d+):(%d*):(%d*):(%d*):(%d*):(%d*):(%d*):(%d*):?(%d*)$")
    if id then rows[tonumber(id)]={minBuyout=tonumber(low),quantity=tonumber(qty),soldPerDay=tonumber(sold) and tonumber(sold)/10 or nil};n=n+1 end
  end
  cache={src=src,market=market,updated=src.updated,count=n,items=rows,snapshot=false};tableCache[market]=cache;return cache
end
NokiUnifiedAPI={}
function NokiUnifiedAPI.GetMarket() return core.Market() end
function NokiUnifiedAPI.GetTableInfo() local t=getTable();if not t then return nil end;return {market=t.market,updated=t.updated,count=t.count,snapshot=false} end
function NokiUnifiedAPI.GetPrice(id) local t=getTable();local r=t and t.items[tonumber(id)];if not r then return nil end;return {market=t.market,updated=t.updated,soldPerDay=r.soldPerDay,minBuyout=r.minBuyout,quantity=r.quantity} end
function core.Subscribe(fn) core.listeners[#core.listeners+1]=fn end
local indicator
local function updateIndicator()
  if not indicator and AuctionHouseFrame then
    indicator=CreateFrame("Frame",nil,AuctionHouseFrame,"BackdropTemplate")
    indicator:SetSize(140,34);indicator:SetPoint("TOPLEFT",AuctionHouseFrame,"TOPRIGHT",8,-75)
    indicator:SetFrameStrata("DIALOG");indicator:SetClampedToScreen(true)
    indicator:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    indicator:SetBackdropColor(.06,.07,.07,.98);indicator:SetBackdropBorderColor(.30,.36,.32,1)
    indicator.icon=indicator:CreateTexture(nil,"ARTWORK");indicator.icon:SetSize(21,21);indicator.icon:SetPoint("LEFT",indicator,"LEFT",7,0);indicator.icon:SetTexture("Interface\\Icons\\Trade_Engineering")
    indicator.label=indicator:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");indicator.label:SetPoint("LEFT",indicator.icon,"RIGHT",7,0);indicator.label:SetJustifyH("LEFT")
    local angle=0;indicator:SetScript("OnUpdate",function(self,delta) angle=(angle+delta*2.5)%(2*math.pi);if self.icon.SetRotation then self.icon:SetRotation(angle) end end)
    indicator:Hide()
  end
  if not indicator then return end
  local label=core.working.browse and "Scanning AH..." or core.working.competition and "Checking listings..." or core.working.pending and "Preparing scan..."
  if core.active and label then indicator.label:SetText(label);indicator:Show() else indicator:Hide() end
end
function core.SetWorking(task,active)
  core.working[task]=active and true or nil
  updateIndicator()
end
local function announce(event,rows)
  if event=="start" then core.SetWorking("pending",false);core.SetWorking("browse",true)
  elseif event=="complete" or event=="failed" then core.SetWorking("browse",false) end
  for _,fn in ipairs(core.listeners) do local ok,err=pcall(fn,event,rows);if not ok then print("Noki Trading listener: "..tostring(err)) end end
end
local function ready()
  if not C_AuctionHouse then return false end
  if C_AuctionHouse.IsThrottledMessageSystemReady then return C_AuctionHouse.IsThrottledMessageSystemReady() end
  return true
end
function core.Scan()
  if not core.active then return false,"Open the auction house first" end
  if core.phase~="idle" then return false,"Another Noki scan is running" end
  if core.working.competition then return false,"Listing checks are running; retry shortly" end
  if not C_AuctionHouse or not C_AuctionHouse.SendBrowseQuery or not C_AuctionHouse.GetBrowseResults or not C_AuctionHouse.HasFullBrowseResults or not C_AuctionHouse.RequestMoreBrowseResults then return false,"Complete browse API unavailable" end
  if not ready() then return false,"Auction requests are throttled; retry shortly" end
  core.phase="browse";core.browseStarted=now();core.browseSeen=false;core.browseRows={};core.moreRequested=false;announce("start")
  local ok,err=pcall(C_AuctionHouse.SendBrowseQuery,{searchString="",sorts={},filters={},itemClassFilters={}})
  if not ok then core.phase="idle";announce("failed");return false,tostring(err) end
  local market=core.Market()
  if market and NokiUnifiedCoreDB then NokiUnifiedCoreDB.lastScanAttempt=NokiUnifiedCoreDB.lastScanAttempt or {};NokiUnifiedCoreDB.lastScanAttempt[market]=now() end
  if core.OnScanStarted then core.OnScanStarted() end
  return true
end
local function requestMore()
  if core.phase~="browse" or not core.browseSeen or core.moreRequested or not ready() then return end
  core.moreRequested=true
  local ok=pcall(C_AuctionHouse.RequestMoreBrowseResults)
  if not ok then core.moreRequested=false end
end
local function browseResults(event,payload)
  if core.phase~="browse" then return end
  local rows
  if event=="AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
    if core.browseSeen then core.phase="idle";announce("failed");print("Noki Trading: browse results changed during scan; retry.");return end
    local ok,initial=pcall(C_AuctionHouse.GetBrowseResults)
    if not ok or type(initial)~="table" then core.phase="idle";announce("failed");return end
    rows=initial;core.browseSeen=true
  elseif event=="AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
    if not core.browseSeen or type(payload)~="table" then core.phase="idle";announce("failed");return end
    rows=payload;core.moreRequested=false
  else return end
  for _,row in ipairs(rows) do core.browseRows[#core.browseRows+1]=row end
  if C_AuctionHouse.HasFullBrowseResults and not C_AuctionHouse.HasFullBrowseResults() then
    requestMore()
    return
  end
  rows=core.browseRows
  local market=core.Market()
  if market and NokiUnifiedCoreDB then
    local old=NokiUnifiedCoreDB.prices[market]
    local oldCount=old and old.rowCount
    if not oldCount and old and type(old.items)=="table" then oldCount=0;for _ in pairs(old.items) do oldCount=oldCount+1 end end
    if #rows==0 or (oldCount and oldCount>=1000 and #rows<oldCount/2) then
      core.phase="idle";announce("failed");print("Noki Trading: scan returned too few rows; previous prices kept. Try Scan now again.");return
    end
    local prices,ambiguous,quantityUnknown={},{ },{}
    local observed=now()
    for _,row in ipairs(rows) do
      local key=row.itemKey;local id=key and key.itemID
      if id and type(row.minPrice)=="number" and row.minPrice>0 then
        local variant=tostring(key.itemLevel or 0)..":"..tostring(key.itemSuffix or 0)..":"..tostring(key.battlePetSpeciesID or 0)
        if prices[id] and prices[id].variant~=variant then ambiguous[id]=true end
        local qty=type(row.totalQuantity)=="number" and row.totalQuantity>=0 and row.totalQuantity or nil
        if prices[id] and prices[id].variant==variant and (qty==nil or prices[id].quantity~=qty) then quantityUnknown[id]=true end
        if not prices[id] then prices[id]={price=row.minPrice,variant=variant,quantity=qty,observed=observed}
        elseif row.minPrice<prices[id].price then prices[id].price=row.minPrice end
      end
    end
    for id in pairs(quantityUnknown) do if prices[id] then prices[id].quantity=nil end end
    for id in pairs(ambiguous) do prices[id]=nil end
    if old and type(old.items)=="table" then
      for id,previous in pairs(old.items) do
        if not prices[id] and not ambiguous[id] and type(previous)=="table" and type(previous.price)=="number" and previous.price>0 then
          prices[id]={price=previous.price,variant=previous.variant,observed=previous.observed or old.observed,carried=true}
        end
      end
    end
    NokiUnifiedCoreDB.prices[market]={observed=observed,rowCount=#rows,items=prices}
  end
  core.phase="idle";core.lastBrowseAt=now();core.lastBrowse=rows;announce("complete",rows)
  if core.OnBrowseComplete then core.OnBrowseComplete(rows) end
end
local events=CreateFrame("Frame")
for _,event in ipairs({"ADDON_LOADED","PLAYER_LOGIN","AUCTION_HOUSE_SHOW","AUCTION_HOUSE_CLOSED","AUCTION_HOUSE_BROWSE_RESULTS_UPDATED","AUCTION_HOUSE_BROWSE_RESULTS_ADDED","AUCTION_HOUSE_BROWSE_FAILURE","AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED"}) do pcall(events.RegisterEvent,events,event) end
events:SetScript("OnEvent",function(_,event,arg)
  if event=="ADDON_LOADED" and arg=="NokiTrading" then NokiUnifiedCoreDB=NokiUnifiedCoreDB or {};NokiUnifiedCoreDB.prices=NokiUnifiedCoreDB.prices or {};if NokiUnifiedCoreDB.autoScan==nil then NokiUnifiedCoreDB.autoScan=true end;core.SetAutoScanInterval(NokiUnifiedCoreDB.scanIntervalMinutes or 30)
  elseif event=="PLAYER_LOGIN" then core.RestoreQuantitiesFromScan()
  elseif event=="AUCTION_HOUSE_SHOW" then core.active=true;if core.OnOpen then core.OnOpen() end
  elseif event=="AUCTION_HOUSE_CLOSED" then
    core.active=false;if core.phase~="idle" then core.phase="idle";announce("failed") end
    core.working={};updateIndicator()
    if NokiUnifiedTabs then NokiUnifiedTabs:HideAll() end
  elseif core.phase=="browse" and (event=="AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event=="AUCTION_HOUSE_BROWSE_RESULTS_ADDED") then browseResults(event,arg)
  elseif core.phase=="browse" and event=="AUCTION_HOUSE_BROWSE_FAILURE" then core.phase="idle";announce("failed");print("Noki Trading: auction browse scan failed.")
  elseif core.phase=="browse" and event=="AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED" then requestMore() end
end)
local elapsed=0;events:SetScript("OnUpdate",function(_,delta)
  if core.phase=="browse" then elapsed=elapsed+delta;if elapsed>=1 then elapsed=0;if now()-(core.browseStarted or now())>180 then core.phase="idle";announce("failed");print("Noki Trading: scan timed out; previous data retained.") else requestMore() end end end
end)
-- Independent auction-house tabs; native tabs hide the Noki overlay when selected.
NokiUnifiedTabs={tabs={},ordered={}}
function NokiUnifiedTabs:DoesIDExist(id) return self.tabs[id]~=nil end
function NokiUnifiedTabs:HideAll()
  self.selected=nil
  for _,entry in ipairs(self.ordered) do
    entry.host:Hide()
    if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(entry.button) end
  end
end
function NokiUnifiedTabs:CreateTab(id,host,label)
  if not self.hooked then
    self.hooked=true
    if type(AuctionHouseFrame.Tabs)=="table" then
      for _,native in ipairs(AuctionHouseFrame.Tabs) do
        if native.HookScript then native:HookScript("OnClick",function() self:HideAll() end) end
      end
    end
    if hooksecurefunc and type(AuctionHouseFrame.SetDisplayMode)=="function" then
      hooksecurefunc(AuctionHouseFrame,"SetDisplayMode",function(_,mode)
        if self.selected and type(mode)=="table" and next(mode) then self:HideAll() end
      end)
    end
  end
  local previous=self.ordered[#self.ordered]
  local native=type(AuctionHouseFrame.Tabs)=="table" and AuctionHouseFrame.Tabs[#AuctionHouseFrame.Tabs]
  local button=CreateFrame("Button",nil,AuctionHouseFrame,"AuctionHouseFrameDisplayModeTabTemplate")
  button:SetText(label);button:SetSize(110,26)
  if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize,button,20,nil,95) end
  if previous then button:SetPoint("TOPLEFT",previous.button,"TOPRIGHT",0,0)
  elseif native then button:SetPoint("TOPLEFT",native,"TOPRIGHT",0,0)
  else button:SetPoint("TOPLEFT",AuctionHouseFrame,"BOTTOMLEFT",270,0) end
  local entry={host=host,button=button};self.tabs[id]=entry;self.ordered[#self.ordered+1]=entry
  if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(button) end
  button:SetScript("OnClick",function() self:SetSelected(id) end)
end
function NokiUnifiedTabs:SetSelected(id)
  self:HideAll()
  local tab=self.tabs[id]
  if tab then
    -- Ask the game's own frame to hide its browse/sell panels while a Noki tab is open.
    if AuctionHouseFrame.SetDisplayMode then AuctionHouseFrame:SetDisplayMode({}) end
    if type(AuctionHouseFrame.Tabs)=="table" and PanelTemplates_DeselectTab then for _,native in ipairs(AuctionHouseFrame.Tabs) do PanelTemplates_DeselectTab(native) end end
    if PanelTemplates_SelectTab then PanelTemplates_SelectTab(tab.button) end
    self.selected=id
    tab.host:Show()
  end
end
