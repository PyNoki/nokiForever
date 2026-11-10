-- Record only completed purchases; a commodity quote is not a verified receipt.
local panel,rows,status,offset,quote,pending=nil,{},nil,0,nil,nil
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
      row:SetText(string.format("%s   %s-%s   %s   Qty: %s   %s",date("%Y-%m-%d %H:%M",entry.time),entry.character or "?",entry.realm or "?",name or ("Item #"..entry.itemID),entry.quantity or "--",entry.quotedTotal and ("Quote: "..money(entry.quotedTotal)) or "Price: --"));row:Show()
    else row:Hide() end
  end
  status:SetText(#entries==0 and "No purchases recorded yet." or ("Showing "..(offset+1).."-"..math.min(offset+pageSize,#entries).." of "..#entries.." purchases"))
end
local function record(itemID,quantity,quotedTotal,kind)
  local entries=history()
  if not entries or type(itemID)~="number" then return end
  entries[#entries+1]={itemID=itemID,quantity=quantity,quotedTotal=quotedTotal,kind=kind,time=(GetServerTime and GetServerTime()) or time(),character=(UnitName and UnitName("player")) or "?",realm=(GetRealmName and GetRealmName()) or "?"}
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
  hooksecurefunc(C_AuctionHouse,"StartCommoditiesPurchase",function(itemID,quantity) quote=nil;pending={itemID=itemID,quantity=quantity} end)
  hooksecurefunc(C_AuctionHouse,"ConfirmCommoditiesPurchase",function(itemID,quantity)
    if pending and pending.itemID==itemID and pending.quantity==quantity then pending.quotedTotal=quote else pending={itemID=itemID,quantity=quantity} end
  end)
end
local events=CreateFrame("Frame")
for _,event in ipairs({"AUCTION_HOUSE_SHOW","AUCTION_HOUSE_CLOSED","COMMODITY_PRICE_UPDATED","COMMODITY_PURCHASE_FAILED","COMMODITY_PURCHASED","ITEM_PURCHASED","GET_ITEM_INFO_RECEIVED"}) do pcall(events.RegisterEvent,events,event) end
events:SetScript("OnEvent",function(_,event,a,b)
  if event=="AUCTION_HOUSE_SHOW" then setupHooks();if C_Timer and C_Timer.After then C_Timer.After(.5,createPanel) else createPanel() end
  elseif event=="AUCTION_HOUSE_CLOSED" or event=="COMMODITY_PURCHASE_FAILED" then quote=nil;pending=nil
  elseif event=="COMMODITY_PRICE_UPDATED" then quote=type(b)=="number" and b or nil
  elseif event=="COMMODITY_PURCHASED" then
    local total=pending and pending.itemID==a and pending.quantity==b and pending.quotedTotal or nil
    record(a,b,total,"commodity");quote=nil;pending=nil
  elseif event=="ITEM_PURCHASED" then record(a,nil,nil,"item")
  elseif event=="GET_ITEM_INFO_RECEIVED" then render() end
end)
