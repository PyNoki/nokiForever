-- A user-started, read-only scan of the first two distinct buyout tiers.
local core=NokiUnifiedCore
local panel,search,threshold,status,footer,scanButton,rows=nil,nil,nil,nil,nil,nil,{}
local queue,results,filtered={},{},{}
local index,checked,skipped,offset=1,0,0,0
local running,inflight=false,false
local pageSize=9
local function money(n)
  if type(n)~="number" then return "--" end
  if n<0 then return "-"..money(-n) end
  local g=math.floor(n/10000);local s=math.floor(n%10000/100);local c=n%100
  local gold="|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t";local silver="|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:0:0|t";local copper="|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:0:0|t"
  local p={};if g>0 then p[#p+1]=g..gold end;if s>0 then p[#p+1]=s..silver end
  if c>0 or #p==0 then p[#p+1]=string.format("%.2f",c):gsub("0+$",""):gsub("%.$","")..copper end
  return table.concat(p," ")
end
local function cell(parent,x,width,font)
  local t=parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlightSmall");t:SetPoint("LEFT",parent,"LEFT",x,0);t:SetWidth(width);t:SetJustifyH("LEFT");t:SetWordWrap(false);return t
end
local function draw()
  if not panel then return end
  local limit=tonumber(threshold:GetText())
  if not limit or limit<0 or limit>100 then status:SetText("Enter a discount from 0 to 100%.");return end
  local term=(search:GetText() or ""):lower():match("^%s*(.-)%s*$")
  filtered={}
  for _,item in ipairs(results) do if item.discount>=limit and (term=="" or item.name:lower():find(term,1,true) or tostring(item.id):find(term,1,true)) then filtered[#filtered+1]=item end end
  table.sort(filtered,function(a,b) if a.discount==b.discount then return a.id<b.id end;return a.discount>b.discount end)
  offset=math.max(0,math.min(offset,math.max(0,#filtered-pageSize)))
  for i,row in ipairs(rows) do
    local item=filtered[offset+i];row.item=item
    if item then
      row.name:SetText(item.name.." |cff829494#"..item.id.."|r");row.low:SetText(money(item.low));row.next:SetText(money(item.next));row.discount:SetText(string.format("%.1f%%",item.discount));row.quantity:SetText(tostring(item.quantity));row.cost:SetText(money(item.cost));row.profit:SetText(money(item.profit));row.sales:SetText(item.sales and string.format("%.1f",item.sales) or "--");row:Show()
    else row:Hide() end
  end
  local state=running and "Checking" or inflight and "Pausing after current check" or index>#queue and #queue>0 and "Finished" or #queue>0 and "Paused" or "Ready"
  status:SetText(state.." | "..checked.." / "..#queue.." checked | "..skipped.." no comparison or unavailable | "..#filtered.." match")
  footer:SetText((#filtered==0 and "No matching results yet" or ((offset+1).."-"..math.min(offset+pageSize,#filtered).." of "..#filtered)).." | Scroll to browse | Recheck before buying")
  scanButton:SetText(running and "Pause" or (#queue>0 and index<=#queue and "Resume" or "Check prices"))
end
local function buildQueue()
  local market=core.Market();local book=market and NokiUnifiedCoreDB and NokiUnifiedCoreDB.prices and NokiUnifiedCoreDB.prices[market]
  if not book or not book.items then return nil,"Run a market scan first." end
  local out={};local catalog=NokiUnifiedMarketDB and NokiUnifiedMarketDB.itemCatalog or {}
  local activityMarket=NokiUnifiedMarketActivityMarket and NokiUnifiedMarketActivityMarket()
  local activityAvailable=type(market)=="string" and activityMarket==market:lower():gsub("/", ".") and NokiUnifiedAPI and NokiUnifiedAPI.GetPrice
  for id,item in pairs(book.items) do
    if type(id)=="number" and type(item)=="table" and not item.carried and type(item.price)=="number" and item.price>0 then
      local level,suffix,pet=(item.variant or "0:0:0"):match("^([^:]+):([^:]+):([^:]+)$")
      local key={itemID=id,itemLevel=tonumber(level) or 0,itemSuffix=tonumber(suffix) or 0,battlePetSpeciesID=tonumber(pet) or 0}
      local saved=catalog[tostring(id)] or catalog[id];local name=(saved and saved.name) or (GetItemInfo and GetItemInfo(id)) or ("Item #"..id)
      local activity=activityAvailable and NokiUnifiedAPI.GetPrice(id);local sales=activity and activity.soldPerDay
      if type(sales)~="number" or sales<0 or sales~=sales or sales==math.huge then sales=nil end
      out[#out+1]={id=id,key=key,name=name,price=item.price,sales=sales}
    end
  end
  table.sort(out,function(a,b) local x,y=a.sales or -1,b.sales or -1;if x==y then return a.id<b.id end;return x>y end)
  if #out==0 then return nil,"No unambiguous items in the latest scan." end
  return out
end
local function checkNext()
  if not running or inflight or index>#queue then return end
  local candidate=queue[index];inflight=true;index=index+1
  local ok,err=core.CheckBuyout(candidate.key,function(result,message)
    inflight=false;checked=checked+1
    if result and #result.tiers>=2 then
      local first,second=result.tiers[1],result.tiers[2]
      local market=NokiUnifiedMarketActivityMarket and NokiUnifiedMarketActivityMarket()
      local activity=market and NokiUnifiedMarketActivity and NokiUnifiedMarketActivity(candidate.id,market)
      local resell=math.ceil(second.price)-1
      local catalog=NokiUnifiedMarketDB and NokiUnifiedMarketDB.itemCatalog;local saved=catalog and (catalog[tostring(candidate.id)] or catalog[candidate.id])
      local name=(saved and saved.name) or (GetItemInfo and GetItemInfo(candidate.id)) or candidate.name
      results[#results+1]={id=candidate.id,key=candidate.key,name=name,low=first.price,next=second.price,nextQuantity=second.quantity,quantity=first.quantity,cost=first.totalCost,discount=(second.price-first.price)/second.price*100,profit=math.floor(resell*first.quantity*.95)-first.totalCost,sales=activity and activity.sales,checked=result.checked}
    else skipped=skipped+1 end
    if index>#queue then running=false end
    draw()
  end)
  if not ok then index=index-1;inflight=false;if not err or not err:find("Another price check") then running=false;status:SetText(err or "Price check unavailable.");return end end
  draw()
end
local function build()
  if panel or not AuctionHouseFrame or not NokiUnifiedTabs then return end
  panel=CreateFrame("Frame",nil,AuctionHouseFrame,"BackdropTemplate");panel:Hide();panel:SetPoint("TOPLEFT",AuctionHouseFrame,"TOPLEFT",12,-75);panel:SetPoint("BOTTOMRIGHT",AuctionHouseFrame,"BOTTOMRIGHT",-12,35);panel:SetFrameStrata("DIALOG");panel:SetFrameLevel(AuctionHouseFrame:GetFrameLevel()+50);panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1});panel:SetBackdropColor(.055,.065,.07,1);panel:SetBackdropBorderColor(.24,.30,.28,1)
  local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-12);title:SetText("MISPRICED ITEMS")
  local hint=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");hint:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-35);hint:SetText("Checks one item at a time, higher estimated activity first. A full scan may take a long time.")
  search=CreateFrame("EditBox",nil,panel,"InputBoxTemplate");search:SetSize(170,24);search:SetPoint("TOPLEFT",panel,"TOPLEFT",20,-59);search:SetAutoFocus(false);search:SetMaxLetters(60);search:SetScript("OnTextChanged",function() offset=0;draw() end);search:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
  local label=panel:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");label:SetPoint("TOPLEFT",panel,"TOPLEFT",210,-64);label:SetText("MIN % (ENTER)")
  threshold=CreateFrame("EditBox",nil,panel,"InputBoxTemplate");threshold:SetSize(50,24);threshold:SetPoint("TOPLEFT",panel,"TOPLEFT",325,-59);threshold:SetAutoFocus(false);threshold:SetNumeric(true);threshold:SetText("50");threshold:SetScript("OnEnterPressed",function(self) self:ClearFocus();offset=0;draw() end);threshold:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
  scanButton=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");scanButton:SetSize(115,23);scanButton:SetPoint("TOPLEFT",panel,"TOPLEFT",395,-59);scanButton:SetText("Check prices")
  scanButton:SetScript("OnClick",function()
    if running then running=false;draw();return end
    if #queue==0 or index>#queue then
      if inflight then return end
      local newQueue,err=buildQueue();if not newQueue then status:SetText(err);return end
      queue=newQueue;results={};checked=0;skipped=0;index=1;offset=0
    end
    running=true;draw();checkNext()
  end)
  status=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");status:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-91);status:SetWidth(900);status:SetJustifyH("LEFT")
  local header=CreateFrame("Frame",nil,panel,"BackdropTemplate");header:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-110);header:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-20,-110);header:SetHeight(22);header:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});header:SetBackdropColor(.13,.18,.17,1)
  for _,col in ipairs({{"ITEM",5,220},{"LOW / UNIT",225,100},{"NEXT / UNIT",325,100},{"DISCOUNT",425,85},{"LOW QTY",510,75},{"BUY COST",585,100},{"EST. PROFIT",685,105},{"EST. / DAY",790,80}}) do cell(header,col[2],col[3],"GameFontNormalSmall"):SetText(col[1]) end
  for i=1,pageSize do
    local row=CreateFrame("Frame",nil,panel,"BackdropTemplate");row:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-133-(i-1)*30);row:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-20,-133-(i-1)*30);row:SetHeight(29);row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});row:SetBackdropColor(i%2==0 and .12 or .08,.12,.12,.95)
    row.name=cell(row,5,215);row.low=cell(row,225,95);row.next=cell(row,325,95);row.discount=cell(row,425,80);row.quantity=cell(row,510,70);row.cost=cell(row,585,95);row.profit=cell(row,685,100);row.sales=cell(row,790,75)
    row.view=CreateFrame("Button",nil,row,"UIPanelButtonTemplate");row.view:SetSize(52,22);row.view:SetPoint("LEFT",row,"LEFT",875,0);row.view:SetText("View")
    row.view:SetScript("OnClick",function()
      local item=row.item;if not item then return end
      if running or inflight or core.phase~="idle" or core.working.competition or core.working.buyout or core.working.pending then print("Noki Trading: pause and wait for the current auction check before opening an item.");return end
      if not AuctionHouseFrame.SelectBrowseResult then print("Noki Trading: auction buy view unavailable.");return end
      NokiUnifiedTabs:HideAll();local ok,err=pcall(AuctionHouseFrame.SelectBrowseResult,AuctionHouseFrame,{itemKey=item.key,minPrice=item.low});if not ok then print("Noki Trading: could not open item: "..tostring(err)) end
    end)
    row:EnableMouse(true);row:SetScript("OnEnter",function(self) if self.item and GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetItemByID(self.item.id);GameTooltip:AddLine("Next price tier: "..self.item.nextQuantity.." units.",1,1,1,true);GameTooltip:AddLine("Checked "..date("%H:%M:%S",self.item.checked)..". Prices may have changed.",1,.8,.3,true);GameTooltip:Show() end end);row:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end);rows[i]=row
  end
  footer=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");footer:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-410)
  local note=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");note:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-433);note:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-20,-433);note:SetJustifyH("LEFT");note:SetText("Discount = (next price - low price) / next price. Estimated profit assumes buying the entire low tier and selling all units at 1 copper under the next tier, after a 5% cut; deposits excluded. Other listings, prices, and demand may change. Own/account listings and incomplete or ambiguous results are skipped.")
  local function wheel(_,delta) offset=math.max(0,math.min(math.max(0,#filtered-pageSize),offset-delta));draw() end
  panel:EnableMouseWheel(true);panel:SetScript("OnMouseWheel",wheel);for _,row in ipairs(rows) do row:EnableMouseWheel(true);row:SetScript("OnMouseWheel",wheel) end
  local width,height
  panel:SetScript("OnShow",function() if not width then width,height=AuctionHouseFrame:GetWidth(),AuctionHouseFrame:GetHeight();AuctionHouseFrame:SetSize(width+220,height+160) end;draw() end)
  panel:SetScript("OnHide",function() running=false;if width then AuctionHouseFrame:SetSize(width,height);width=nil;height=nil end end)
  NokiUnifiedTabs:CreateTab("NokiMispriced",panel,"Mispriced");draw()
end
local events=CreateFrame("Frame");events:RegisterEvent("AUCTION_HOUSE_SHOW");events:RegisterEvent("AUCTION_HOUSE_CLOSED")
events:SetScript("OnEvent",function(_,event) if event=="AUCTION_HOUSE_SHOW" then if C_Timer and C_Timer.After then C_Timer.After(.5,build) else build() end else running=false end end)
local elapsed=0;events:SetScript("OnUpdate",function(_,delta) if not running then return end;elapsed=elapsed+delta;if elapsed<.5 then return end;elapsed=0;checkNext() end)
