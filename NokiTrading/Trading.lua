-- Noki local beta: owned auction view. Cancellation only occurs from a row click.
local core=NokiUnifiedCore
local owned, competitions={},{}
local state={queue={},index=1,search=nil,alerted=false}
local startChecks
local panel, summary, status, page, rows, scrollOffset
local requestedNames={}
scrollOffset=0
local function formatMoney(n)
  if type(n)~="number" then return "--" end
  local value=math.floor(n*100+0.5)/100;local g=math.floor(value/10000);local s=math.floor((value-g*10000)/100);local c=value-g*10000-s*100
  local copper=string.format("%.2f",c):gsub("0+$",""):gsub("%.$","")
  local goldIcon="|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t"
  local silverIcon="|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:0:0|t"
  local copperIcon="|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:0:0|t"
  local parts={}
  if g>0 then parts[#parts+1]=g..goldIcon end
  if s>0 then parts[#parts+1]=s..silverIcon end
  if copper~="0" or #parts==0 then parts[#parts+1]=copper..copperIcon end
  return table.concat(parts," ")
end
local function timeLeft(info)
  if type(info.timeLeftSeconds)=="number" then local t=math.max(0,info.timeLeftSeconds);if t>=3600 then return math.ceil(t/3600).."h" end;return math.max(1,math.ceil(t/60)).."m" end
  if info.timeLeft~=nil then return ({[0]="<30m",[1]="30m-2h",[2]="2h-12h",[3]="12h-48h"})[info.timeLeft] or "unknown" end
  return "unknown"
end
local function rowText(parent,x,y,width)
  local t=parent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");t:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);t:SetWidth(width);t:SetJustifyH("LEFT");return t
end
local function keyString(k)
  return table.concat({k.itemID or 0,k.itemLevel or 0,k.itemSuffix or 0,k.battlePetSpeciesID or 0},":")
end
local function itemName(item)
  local key=item.itemKey
  if C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo then
    local ok,info=pcall(C_AuctionHouse.GetItemKeyInfo,key)
    if ok and type(info)=="table" and type(info.itemName)=="string" and info.itemName~="" then return info.itemName end
  end
  if GetItemInfo then
    local ok,name=pcall(GetItemInfo,item.itemLink or key.itemID)
    if ok and type(name)=="string" and name~="" then return name end
  end
  if C_Item and C_Item.GetItemInfo then
    local ok,name=pcall(C_Item.GetItemInfo,item.itemLink or key.itemID)
    if ok and type(name)=="string" and name~="" then return name end
  end
  if not requestedNames[key.itemID] and C_Item and C_Item.RequestLoadItemDataByID then
    requestedNames[key.itemID]=true;pcall(C_Item.RequestLoadItemDataByID,key.itemID)
  end
  return "Loading #"..tostring(key.itemID)
end
-- Owned commodity buyout is per unit; non-commodity buyout is for the stack.
local function auctionValues(item)
  local quantity=item.quantity
  local buyout=item.buyoutAmount
  if type(quantity)~="number" or quantity<=0 or type(buyout)~="number" or buyout<=0 then return nil,nil end
  local ok,info=false,nil
  if C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo then ok,info=pcall(C_AuctionHouse.GetItemKeyInfo,item.itemKey) end
  if not ok or type(info)~="table" or type(info.isCommodity)~="boolean" then return nil,nil end
  if info.isCommodity then return buyout,buyout*quantity end
  return buyout/quantity,buyout
end
core.OwnedAuctionValues=auctionValues
-- The owned-auction API may not return the original posting deposit.
local function auctionDeposit(item)
  local amount=item.depositAmount
  if amount==nil then amount=item.depositCost end
  if type(amount)=="number" and amount>=0 then return amount end
  return nil
end
core.OwnedAuctionDeposit=auctionDeposit
-- The market low includes the player's own listings when present in search results.
local function lowestPrice(result)
  if not result or not result.complete then return nil end
  local lowest
  for _,row in ipairs(result.rows or {}) do
    if type(row.price)=="number" and row.price>0 and (not lowest or row.price<lowest) then lowest=row.price end
  end
  return lowest
end
core.LowestAuctionPrice=lowestPrice
-- Counts only units at strictly lower prices, never treating ties as ahead.
local function comparison(auction)
  local key=auction.itemKey;local result=key and competitions[keyString(key)]
  if not result or not result.complete then return "checking",nil end
  local unit=auctionValues(auction)
  if not unit then return "price unknown",nil end
  local lower=0;local uncertain=false
  for _,r in ipairs(result.rows) do
    if r.price<unit then
      if r.ownMixed then uncertain=true else lower=lower+r.quantity end
    end
  end
  if uncertain then return "comparison uncertain",nil end
  return lower>0 and "undercut" or "no lower price",lower
end
core.CompareOwned=comparison
local function render()
  if not panel then return end
  local total,count=0,0
  for _,a in ipairs(owned) do local _,value=auctionValues(a);if value then total=total+value else count=count+1 end end
  local net=math.floor(total*95/100)
  summary:SetText((state.ownedComplete and "Gross: " or "Partial gross: ")..formatMoney(total).." | Est. after 5%: "..formatMoney(net)..(count>0 and (" | "..count.." price unknown") or "").." | Deposits excluded")
  for i,row in ipairs(rows) do
    local item=owned[scrollOffset+i];row.item=item
    if item then
      local name=itemName(item)
      local unit,total=auctionValues(item)
      local condition,ahead=comparison(item)
      local marketLow=lowestPrice(item.itemKey and competitions[keyString(item.itemKey)])
      row.name:SetText(name);row.quantity:SetText(tostring(item.quantity or "?"));row.unit:SetText(formatMoney(unit));row.total:SetText(formatMoney(total));row.low:SetText(formatMoney(marketLow));row.state:SetText(condition=="no lower price" and "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t" or condition);row.ahead:SetText(ahead~=nil and tostring(ahead) or "--");row.deposit:SetText(formatMoney(auctionDeposit(item)));row.time:SetText(timeLeft(item))
      row.state:SetTextColor(condition=="undercut" and 1 or .75,condition=="undercut" and .3 or .85,.4)
      row.cancel:SetEnabled(not state.cancelPending and item.auctionID~=nil);row:Show()
    else row:Hide() end
  end
  status:SetText(#owned.." active auctions | "..(state.search and "Checking competition..." or (#state.queue>0 and state.index<=#state.queue and "Competition scan queued" or (#state.queue>0 and "Competition checks complete" or "Use Scan market to refresh comparisons"))))
  page:SetText((#owned==0 and "No listings" or ((scrollOffset+1).."-"..math.min(scrollOffset+8,#owned).." of "..#owned)).."  |  Market low is per unit and can include yours  |  -- = unavailable")
end
local function refreshOwned()
  if not core.active or not C_AuctionHouse or not C_AuctionHouse.GetNumOwnedAuctions or not C_AuctionHouse.GetOwnedAuctionInfo then return end
  local result={}
  for i=1,C_AuctionHouse.GetNumOwnedAuctions() do
    local row=C_AuctionHouse.GetOwnedAuctionInfo(i)
    if type(row)=="table" and row.itemKey and row.auctionID and (row.status==nil or row.status==0 or (Enum and Enum.AuctionStatus and row.status==Enum.AuctionStatus.Active)) then result[#result+1]=row end
  end
  owned=result;state.cancelPending=false;scrollOffset=math.min(scrollOffset,math.max(0,#owned-8));render()
  state.ownedComplete=not C_AuctionHouse.HasFullOwnedAuctionResults or C_AuctionHouse.HasFullOwnedAuctionResults()
  if state.ownedComplete then state.needOwned=false end
  if state.ownedComplete and state.needChecks and startChecks then state.needChecks=false;startChecks() end
  render()
end
local function requestOwned()
  if not core.active or not C_AuctionHouse or not C_AuctionHouse.QueryOwnedAuctions then return end
  if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then return end
  local ok=pcall(C_AuctionHouse.QueryOwnedAuctions,{})
  if ok then state.ownedRequested=(GetServerTime and GetServerTime()) or time() end
end
local function createPanel()
  if panel or not AuctionHouseFrame or not NokiUnifiedTabs then return end
  panel=CreateFrame("Frame",nil,AuctionHouseFrame,"BackdropTemplate");panel:Hide();panel:SetPoint("TOPLEFT",AuctionHouseFrame,"TOPLEFT",12,-75);panel:SetPoint("BOTTOMRIGHT",AuctionHouseFrame,"BOTTOMRIGHT",-12,35);panel:SetFrameStrata("DIALOG");panel:SetFrameLevel(AuctionHouseFrame:GetFrameLevel()+50);panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1});panel:SetBackdropColor(.055,.065,.07,1);panel:SetBackdropBorderColor(.24,.30,.28,1)
  local previousWidth,previousHeight
  panel:SetScript("OnShow",function() if not previousWidth then previousWidth,previousHeight=AuctionHouseFrame:GetWidth(),AuctionHouseFrame:GetHeight();AuctionHouseFrame:SetSize(previousWidth+220,previousHeight+160) end end)
  panel:SetScript("OnHide",function() if StaticPopup_Hide then StaticPopup_Hide("NOKI_CONFIRM_CANCEL_AUCTION") end;if previousWidth and previousHeight then AuctionHouseFrame:SetSize(previousWidth,previousHeight) end;previousWidth=nil;previousHeight=nil end)
  StaticPopupDialogs["NOKI_CONFIRM_CANCEL_AUCTION"]={text="Cancel the auction for %s?",button1="Cancel auction",button2="Keep auction",timeout=0,whileDead=true,hideOnEscape=true,OnAccept=function(_,id)
    if not core.active or state.cancelPending or not C_AuctionHouse or not C_AuctionHouse.CancelAuction then return end
    local found=false;for _,auction in ipairs(owned) do if auction.auctionID==id then found=true;break end end
    if not found then print("Noki Trading: that auction is no longer available.");return end
    if C_AuctionHouse.CanCancelAuction and not C_AuctionHouse.CanCancelAuction(id) then print("Noki Trading: this auction cannot be cancelled.");return end
    local ok,err=pcall(C_AuctionHouse.CancelAuction,id)
    if ok then state.cancelPending=true;render() else print("Noki Trading: cancel failed: "..tostring(err)) end
  end}
  local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-12);title:SetText("YOUR AUCTIONS")
  local scan=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");scan:SetSize(120,24);scan:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-20,-8);scan:SetText("Scan market");scan:SetScript("OnClick",function() local ok,err=core.Scan();if not ok then print("Noki Trading: "..tostring(err)) end end)
  summary=rowText(panel,16,-40,700);status=rowText(panel,16,-60,700)
  local header=CreateFrame("Frame",nil,panel,"BackdropTemplate");header:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-82);header:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-12,-82);header:SetHeight(21);header:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});header:SetBackdropColor(.13,.18,.17,1)
  for _,col in ipairs({{"ITEM",4,200},{"QTY",205,65},{"UNIT",270,80},{"TOTAL",350,90},{"MKT LOW",440,85},{"STATUS",525,75},{"LOWER",600,65},{"DEPOSIT",665,80},{"TIME",745,60}}) do local label=header:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");label:SetPoint("TOPLEFT",header,"TOPLEFT",col[2],-4);label:SetWidth(col[3]);label:SetJustifyH("LEFT");label:SetText(col[1]) end
  rows={}
  for i=1,8 do
    local row=CreateFrame("Frame",nil,panel,"BackdropTemplate");row:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-104-(i-1)*32);row:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-12,-104-(i-1)*32);row:SetHeight(30);row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});row:SetBackdropColor(i%2==0 and .12 or .08,.12,.12,.95)
    row.name=rowText(row,4,-8,200);row.quantity=rowText(row,205,-8,65);row.unit=rowText(row,270,-8,80);row.total=rowText(row,350,-8,90);row.low=rowText(row,440,-8,85);row.state=rowText(row,525,-8,75);row.ahead=rowText(row,600,-8,65);row.deposit=rowText(row,665,-8,80);row.time=rowText(row,745,-8,60)
    row.view=CreateFrame("Button",nil,row,"UIPanelButtonTemplate");row.view:SetSize(50,22);row.view:SetPoint("RIGHT",row,"RIGHT",-60,0);row.view:SetText("View");row.view:SetScript("OnClick",function()
      local item=row.item
      if not item or not item.itemKey or not core.active then return end
      if core.phase~="idle" then print("Noki Trading: wait for the market scan to finish, then select View.");return end
      if not AuctionHouseFrame or type(AuctionHouseFrame.SelectBrowseResult)~="function" then print("Noki Trading: the auction house buy view is unavailable.");return end
      local low=lowestPrice(competitions[keyString(item.itemKey)])
      if not low then print("Noki Trading: wait for competition checks or select Scan market before viewing this item.");return end
      state.queue={};state.index=1;state.search=nil;state.needChecks=false;core.SetWorking("competition",false)
      local ok,err=pcall(AuctionHouseFrame.SelectBrowseResult,AuctionHouseFrame,{itemKey=item.itemKey,minPrice=low})
      if not ok then print("Noki Trading: could not open the buy view: "..tostring(err));return end
      NokiUnifiedTabs:HideAll()
    end)
    row.cancel=CreateFrame("Button",nil,row,"UIPanelButtonTemplate");row.cancel:SetSize(54,22);row.cancel:SetPoint("RIGHT",row,"RIGHT",-4,0);row.cancel:SetText("Cancel");row.cancel:SetScript("OnClick",function()
      local item=row.item
      if not item or state.cancelPending or not core.active or not C_AuctionHouse.CancelAuction then return end
      StaticPopup_Show("NOKI_CONFIRM_CANCEL_AUCTION",itemName(item),nil,item.auctionID)
    end)
    rows[i]=row
  end
  page=rowText(panel,16,-370,700)
  panel:EnableMouseWheel(true);panel:SetScript("OnMouseWheel",function(_,delta) scrollOffset=math.max(0,math.min(math.max(0,#owned-8),scrollOffset-delta));render() end)
  panel:Hide();NokiUnifiedTabs:CreateTab("NokiUnifiedOwned",panel,"Your auctions");render()
end
local function checkDone()
  local search=state.search;if not search then return end
  local api=C_AuctionHouse;local complete,count,get
  if search.commodity then
    complete=api.HasFullCommoditySearchResults and api.HasFullCommoditySearchResults(search.key.itemID);count=api.GetNumCommoditySearchResults;get=api.GetCommoditySearchResultInfo
  else complete=api.HasFullItemSearchResults and api.HasFullItemSearchResults(search.key);count=api.GetNumItemSearchResults;get=api.GetItemSearchResultInfo end
  if not count or not get then return end
  if not complete then
    local ready=not C_AuctionHouse.IsThrottledMessageSystemReady or C_AuctionHouse.IsThrottledMessageSystemReady()
    if ready then
      if search.commodity and api.RequestMoreCommoditySearchResults then pcall(api.RequestMoreCommoditySearchResults,search.key.itemID)
      elseif not search.commodity and api.RequestMoreItemSearchResults then pcall(api.RequestMoreItemSearchResults,search.key) end
    end
    return
  end
  local arg=search.commodity and search.key.itemID or search.key;local rows={}
  for i=1,count(arg) do
    local info=get(arg,i)
    if info and type(info.quantity)=="number" and info.quantity>0 then
      local price=search.commodity and info.unitPrice or (info.buyoutAmount and info.buyoutAmount/info.quantity)
      if type(price)=="number" and price>0 then rows[#rows+1]={price=price,quantity=info.quantity,ownMixed=info.containsOwnerItem==true} end
    end
  end
  competitions[search.keyString]={complete=true,rows=rows};state.search=nil;state.index=state.index+1;render()
end
local function pump()
  if not core.active or core.phase~="idle" or state.search or state.index>#state.queue then return end
  if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then return end
  local key=state.queue[state.index];local info=C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.GetItemKeyInfo(key)
  if not info or type(info.isCommodity)~="boolean" then state.index=state.index+1;return end
  state.search={key=key,keyString=keyString(key),commodity=info.isCommodity,started=(GetServerTime and GetServerTime()) or time()}
  local ok=pcall(C_AuctionHouse.SendSearchQuery,key,{},true)
  if not ok then state.search=nil;state.index=state.index+1 end
end
startChecks=function()
  competitions={};state.queue={};state.index=1;state.search=nil;state.alerted=false
  local seen={};for _,auction in ipairs(owned) do local key=auction.itemKey;local k=keyString(key);if not seen[k] then seen[k]=true;state.queue[#state.queue+1]=key end end
  core.SetWorking("competition",#state.queue>0)
  if #state.queue==0 and state.ownedComplete then state.alerted=true;print("Noki Trading: no active auctions to check.") end
  render()
end
function core.OnBrowseComplete() if state.needChecks then refreshOwned() end end
function core.OnScanStarted() state.autoScanPending=false;state.autoRetryAfter=nil end
function core.OnOpen()
  owned={};competitions={};state.ownedComplete=false;state.needOwned=true;state.ownedRequested=nil;state.needChecks=true
  state.alerted=false;state.autoScanPending=core.AutoScanDue();state.opened=(GetServerTime and GetServerTime()) or time();state.scanPendingSince=state.opened;state.autoRetryAfter=nil
  core.SetWorking("pending",state.autoScanPending)
  if C_Timer and C_Timer.After then C_Timer.After(1,function() if core.active then createPanel();requestOwned() end end) end
end
local f=CreateFrame("Frame")
for _,e in ipairs({"OWNED_AUCTIONS_UPDATED","AUCTION_CANCELED","ITEM_SEARCH_RESULTS_UPDATED","ITEM_SEARCH_RESULTS_ADDED","COMMODITY_SEARCH_RESULTS_UPDATED","COMMODITY_SEARCH_RESULTS_ADDED","AUCTION_HOUSE_CLOSED","GET_ITEM_INFO_RECEIVED","ITEM_KEY_ITEM_INFO_RECEIVED"}) do pcall(f.RegisterEvent,f,e) end
f:SetScript("OnEvent",function(_,event,arg)
  if event=="OWNED_AUCTIONS_UPDATED" then refreshOwned()
  elseif event=="AUCTION_CANCELED" then requestOwned()
  elseif event=="GET_ITEM_INFO_RECEIVED" or event=="ITEM_KEY_ITEM_INFO_RECEIVED" then render()
  elseif event=="AUCTION_HOUSE_CLOSED" then state.queue={};state.index=1;state.search=nil;core.SetWorking("competition",false);core.SetWorking("pending",false)
  elseif state.search and ((state.search.commodity and (event=="COMMODITY_SEARCH_RESULTS_UPDATED" or event=="COMMODITY_SEARCH_RESULTS_ADDED") and arg==state.search.key.itemID) or (not state.search.commodity and (event=="ITEM_SEARCH_RESULTS_UPDATED" or event=="ITEM_SEARCH_RESULTS_ADDED") and type(arg)=="table" and keyString(arg)==state.search.keyString)) then state.search.seen=true;checkDone() end
end)
local interval=0;f:SetScript("OnUpdate",function(_,delta)
  interval=interval+delta;if interval<.5 then return end;interval=0
  if state.needOwned and core.active then
    local n=(GetServerTime and GetServerTime()) or time()
    if not state.ownedRequested or n-state.ownedRequested>10 then requestOwned() end
  end
  if core.active and not state.autoScanPending and ((GetServerTime and GetServerTime()) or time())>=(state.autoRetryAfter or 0) and core.AutoScanDue() then
    state.autoScanPending=true;state.scanPendingSince=(GetServerTime and GetServerTime()) or time();core.SetWorking("pending",true)
  end
  if state.autoScanPending and not core.AutoScanEnabled() then state.autoScanPending=false;core.SetWorking("pending",false) end
  if state.autoScanPending and core.active then
    local n=(GetServerTime and GetServerTime()) or time()
    if core.working.competition then state.scanPendingSince=n
    elseif n-(state.scanPendingSince or n)>45 then state.autoScanPending=false;state.autoRetryAfter=n+core.AutoScanInterval()*60;core.SetWorking("pending",false);print("Noki Trading: automatic scan could not start; use Scan now to retry.")
    elseif n-(state.scanPendingSince or n)>=3 and core.phase=="idle" then
      local ok=core.Scan();if ok then state.autoScanPending=false end
    end
  end
  if state.search then local n=(GetServerTime and GetServerTime()) or time();if n-state.search.started>20 then state.search=nil;state.index=state.index+1 elseif state.search.seen then checkDone() end end
  pump()
  if #state.queue>0 and state.index>#state.queue and not state.search and not state.alerted then
    state.alerted=true;core.SetWorking("competition",false);local under,unknown=0,0
    for _,a in ipairs(owned) do local outcome=comparison(a);if outcome=="undercut" then under=under+1 elseif outcome=="checking" or outcome=="comparison uncertain" then unknown=unknown+1 end end
    print("Noki Trading: "..under.." listing(s) undercut"..(unknown>0 and ("; "..unknown.." could not be checked") or "")..".")
  end
end)
