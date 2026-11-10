-- Record only completed purchases; a commodity quote is not a verified receipt.
local panel,rows,status,offset,quote,pending=nil,{},nil,0,nil,nil
local recentCommodity,pendingItem,recentItem
local function now() return (GetServerTime and GetServerTime()) or time() end
local pageSize=8
local function history()
  if not NokiUnifiedCoreDB then return nil end
  NokiUnifiedCoreDB.purchaseHistory=NokiUnifiedCoreDB.purchaseHistory or {}
  return NokiUnifiedCoreDB.purchaseHistory
end
local function money(copper)
  if type(copper)~="number" then return "--" end
  return string.format("%dg %ds %dc",math.floor(copper/10000),math.floor(copper%10000/100),copper%100)
end
local function render()
  if not panel then return end
  local entries=history() or {};offset=math.max(0,math.min(offset,math.max(0,#entries-pageSize)))
  for i,row in ipairs(rows) do
    local entry=entries[#entries-offset-i+1]
    if entry then
      local name=GetItemInfo and GetItemInfo(entry.itemID)
      row:SetText(string.format("%s   %s-%s   %s   Qty: %s   %s",date("%Y-%m-%d %H:%M",entry.time),entry.character or "?",entry.realm or "?",name or ("Item #"..entry.itemID),entry.quantity or "--",entry.paidTotal and ("Paid: "..money(entry.paidTotal)) or entry.quotedTotal and ("Quote: "..money(entry.quotedTotal)) or "Price: --"));row:Show()
    else row:Hide() end
  end
  status:SetText(#entries==0 and "No purchases recorded yet." or ("Showing "..(offset+1).."-"..math.min(offset+pageSize,#entries).." of "..#entries.." purchases"))
end
local function record(itemID,quantity,quotedTotal,kind,paidTotal)
  local entries=history()
  if not entries or type(itemID)~="number" then return end
  entries[#entries+1]={itemID=itemID,quantity=quantity,quotedTotal=quotedTotal,paidTotal=paidTotal,kind=kind,time=now(),character=(UnitName and UnitName("player")) or "?",realm=(GetRealmName and GetRealmName()) or "?"}
  offset=0;render()
end
local function createPanel()
  if panel or not AuctionHouseFrame or not NokiUnifiedTabs then return end
  panel=CreateFrame("Frame",nil,AuctionHouseFrame,"BackdropTemplate");panel:Hide()
  panel:SetPoint("TOPLEFT",AuctionHouseFrame,"TOPLEFT",12,-75);panel:SetPoint("BOTTOMRIGHT",AuctionHouseFrame,"BOTTOMRIGHT",-12,35)
  panel:SetFrameStrata("DIALOG");panel:SetFrameLevel(AuctionHouseFrame:GetFrameLevel()+50)
  panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1});panel:SetBackdropColor(.055,.065,.07,1);panel:SetBackdropBorderColor(.24,.30,.28,1)
  local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-14);title:SetText("PURCHASE HISTORY")
  local note=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");note:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-40);note:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-16,-40);note:SetJustifyH("LEFT");note:SetText("Confirmed purchases recorded from now on. Quotes are not verified payments; -- means unavailable. Bids won later may be missing.")
  for i=1,pageSize do
    local row=panel:CreateFontString(nil,"OVERLAY","GameFontHighlight");row:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-75-(i-1)*28);row:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-16,-75-(i-1)*28);row:SetJustifyH("LEFT");rows[i]=row
  end
  status=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");status:SetPoint("BOTTOMLEFT",panel,"BOTTOMLEFT",16,45)
  local older=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");older:SetSize(80,22);older:SetPoint("BOTTOMLEFT",panel,"BOTTOMLEFT",16,15);older:SetText("Older");older:SetScript("OnClick",function() offset=offset+pageSize;render() end)
  local newer=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");newer:SetSize(80,22);newer:SetPoint("LEFT",older,"RIGHT",8,0);newer:SetText("Newer");newer:SetScript("OnClick",function() offset=math.max(0,offset-pageSize);render() end)
  local oldWidth,oldHeight
  panel:SetScript("OnShow",function() if not oldWidth then oldWidth,oldHeight=AuctionHouseFrame:GetWidth(),AuctionHouseFrame:GetHeight();AuctionHouseFrame:SetSize(oldWidth+220,oldHeight+160) end;render() end)
  panel:SetScript("OnHide",function() if oldWidth then AuctionHouseFrame:SetSize(oldWidth,oldHeight);oldWidth=nil;oldHeight=nil end end)
  NokiUnifiedTabs:CreateTab("NokiPurchaseHistory",panel,"Purchases");render()
end
local hooked=false
local function setupHooks()
  if hooked or not hooksecurefunc or not C_AuctionHouse then return end
  if not C_AuctionHouse.StartCommoditiesPurchase or not C_AuctionHouse.ConfirmCommoditiesPurchase then return end
  hooked=true
  hooksecurefunc(C_AuctionHouse,"StartCommoditiesPurchase",function(itemID,quantity) quote=nil;recentCommodity=nil;pending={itemID=itemID,quantity=quantity} end)
  hooksecurefunc(C_AuctionHouse,"ConfirmCommoditiesPurchase",function(itemID,quantity)
    if pending and pending.itemID==itemID and pending.quantity==quantity then pending.quotedTotal=quote else pending={itemID=itemID,quantity=quantity} end
    pending.confirmed=true
  end)
  if C_AuctionHouse.PlaceBid then hooksecurefunc(C_AuctionHouse,"PlaceBid",function(auctionID,amount)
    recentItem=nil;pendingItem=nil
    local ok,detail=pcall(function()
      local info=C_AuctionHouse.GetAuctionInfoByID and C_AuctionHouse.GetAuctionInfoByID(auctionID)
      local key=info and info.itemKey
      local buyFrame=AuctionHouseFrame and AuctionHouseFrame.ItemBuyFrame
      local selected=buyFrame and buyFrame.ItemList and buyFrame.ItemList.GetSelectedEntry and buyFrame.ItemList:GetSelectedEntry()
      if selected and selected.auctionID~=auctionID then selected=nil end
      key=key or (selected and selected.itemKey) or (selected and buyFrame.itemKey)
      local buyout=(info and info.buyoutAmount) or (selected and selected.buyoutAmount)
      if key and type(key.itemID)=="number" and type(buyout)=="number" and amount==buyout then return {auctionID=auctionID,itemID=key.itemID,quantity=selected and selected.quantity,paidTotal=amount,time=now()} end
    end)
    if ok then pendingItem=detail end
  end) end
end
local events=CreateFrame("Frame")
for _,event in ipairs({"AUCTION_HOUSE_SHOW","AUCTION_HOUSE_CLOSED","AUCTION_HOUSE_SHOW_ERROR","COMMODITY_PRICE_UPDATED","COMMODITY_PURCHASE_FAILED","COMMODITY_PURCHASE_SUCCEEDED","COMMODITY_PURCHASED","ITEM_PURCHASED","AUCTION_HOUSE_PURCHASE_COMPLETED","GET_ITEM_INFO_RECEIVED"}) do pcall(events.RegisterEvent,events,event) end
events:SetScript("OnEvent",function(_,event,a,b)
  if event=="AUCTION_HOUSE_SHOW" then setupHooks();if C_Timer and C_Timer.After then C_Timer.After(.5,createPanel) else createPanel() end
  elseif event=="AUCTION_HOUSE_SHOW_ERROR" then pendingItem=nil
  elseif event=="AUCTION_HOUSE_CLOSED" or event=="COMMODITY_PURCHASE_FAILED" then quote=nil;pending=nil;if event=="AUCTION_HOUSE_CLOSED" then pendingItem=nil;recentItem=nil;recentCommodity=nil end
  elseif event=="COMMODITY_PRICE_UPDATED" then quote=type(b)=="number" and b or nil
  elseif event=="COMMODITY_PURCHASE_SUCCEEDED" then
    if pending and pending.confirmed then
      record(pending.itemID,pending.quantity,pending.quotedTotal,"commodity")
      recentCommodity={itemID=pending.itemID,quantity=pending.quantity,time=now()};pending=nil;quote=nil
    end
  elseif event=="COMMODITY_PURCHASED" then
    local total=pending and pending.itemID==a and pending.quantity==b and pending.quotedTotal or nil
    if not (recentCommodity and recentCommodity.itemID==a and recentCommodity.quantity==b and now()-recentCommodity.time<=5) then record(a,b,total,"commodity") end
    recentCommodity=nil;quote=nil;pending=nil
  elseif event=="ITEM_PURCHASED" then
    if not (recentItem and recentItem.itemID==a and now()-recentItem.time<=5) then
      local detail=pendingItem and pendingItem.itemID==a and now()-pendingItem.time<=60 and pendingItem
      record(a,detail and detail.quantity,nil,"item",detail and detail.paidTotal)
      if detail then detail.recorded=true end
    end
    recentItem=nil
  elseif event=="AUCTION_HOUSE_PURCHASE_COMPLETED" then
    if pendingItem and pendingItem.auctionID==a and now()-pendingItem.time<=60 then
      if not pendingItem.recorded then record(pendingItem.itemID,pendingItem.quantity,nil,"item",pendingItem.paidTotal);recentItem={itemID=pendingItem.itemID,time=now()} end
      pendingItem=nil
    end
  elseif event=="GET_ITEM_INFO_RECEIVED" then render() end
end)
