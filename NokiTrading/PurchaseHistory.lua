-- Record only completed purchases; a commodity quote is not a verified receipt.
local panel,rows,status,offset,quote,pending=nil,{},nil,0,nil,nil
local recentCommodity,pendingItem,recentItem
local requestedItems={}
local function now() return (GetServerTime and GetServerTime()) or time() end
local pageSize=8
local function history()
  if not NokiUnifiedCoreDB then return nil end
  NokiUnifiedCoreDB.purchaseHistory=NokiUnifiedCoreDB.purchaseHistory or {}
  return NokiUnifiedCoreDB.purchaseHistory
end
local function money(copper)
  if type(copper)~="number" then return "--" end
  local g=math.floor(copper/10000);local s=math.floor(copper%10000/100);local c=math.floor(copper%100)
  local parts={};local icons={"|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t","|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:0:0|t","|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:0:0|t"}
  if g>0 then parts[#parts+1]=g..icons[1] end
  if s>0 then parts[#parts+1]=s..icons[2] end
  if c>0 or #parts==0 then parts[#parts+1]=c..icons[3] end
  return table.concat(parts," ")
end
local function render()
  if not panel then return end
  local entries=history() or {};offset=math.max(0,math.min(offset,math.max(0,#entries-pageSize)))
  for i,row in ipairs(rows) do
    local entry=entries[#entries-offset-i+1]
    if entry then
      local name,icon
      if GetItemInfo then local itemName,_,_,_,_,_,_,_,_,itemIcon=GetItemInfo(entry.itemID);name,icon=itemName,itemIcon end
      if not icon and C_Item and C_Item.GetItemIconByID then local ok,result=pcall(C_Item.GetItemIconByID,entry.itemID);if ok then icon=result end end
      if not name and not requestedItems[entry.itemID] and C_Item and C_Item.RequestLoadItemDataByID then requestedItems[entry.itemID]=true;pcall(C_Item.RequestLoadItemDataByID,entry.itemID) end
      row.itemID=entry.itemID;row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
      row.item:SetText(name or ("Item #"..entry.itemID));row.when:SetText(date("%Y-%m-%d %H:%M",entry.time));row.character:SetText(entry.character or "?");row.quantity:SetText(entry.quantity and tostring(entry.quantity) or "--")
      row.price:SetText(entry.paidTotal and ("Paid: "..money(entry.paidTotal)) or entry.quotedTotal and ("Quote: "..money(entry.quotedTotal)) or "--");row:Show()
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
  local header=CreateFrame("Frame",nil,panel,"BackdropTemplate");header:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-70);header:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-20,-70);header:SetHeight(22);header:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});header:SetBackdropColor(.13,.18,.17,1)
  local function text(parent,x,width,font)
    local label=parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlightSmall");label:SetPoint("LEFT",parent,"LEFT",x,0);label:SetWidth(width);label:SetJustifyH("LEFT");label:SetWordWrap(false);return label
  end
  for _,col in ipairs({{"ITEM",32,220},{"DATE",265,145},{"CHARACTER",415,120},{"QTY",545,50},{"TOTAL",610,160}}) do text(header,col[2],col[3],"GameFontNormalSmall"):SetText(col[1]) end
  for i=1,pageSize do
    local row=CreateFrame("Frame",nil,panel,"BackdropTemplate");row:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-93-(i-1)*32);row:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-20,-93-(i-1)*32);row:SetHeight(31);row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});row:SetBackdropColor(i%2==0 and .12 or .08,.12,.12,.95)
    row.icon=row:CreateTexture(nil,"ARTWORK");row.icon:SetSize(24,24);row.icon:SetPoint("LEFT",row,"LEFT",4,0)
    row.item=text(row,32,225);row.when=text(row,265,145);row.character=text(row,415,120);row.quantity=text(row,545,50);row.price=text(row,610,160)
    row:EnableMouse(true);row:SetScript("OnEnter",function(self) if self.itemID and GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetItemByID(self.itemID);GameTooltip:Show() end end);row:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
    rows[i]=row
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
