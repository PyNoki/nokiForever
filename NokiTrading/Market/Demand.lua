-- A research table: listed supply is a snapshot; daily sales are estimates.
local core=NokiUnifiedCore
local panel,search,status,footer,rows,columns=nil,nil,nil,nil,{},{}
local data,filtered={},{}
local sortKey,ascending,offset="pressure",false,0
local pageSize=10
local function money(n)
  if type(n)~="number" then return "--" end
  local g=math.floor(n/10000);local s=math.floor(n%10000/100);local c=n%100
  return (g>0 and (g.."g ") or "")..(s>0 and (s.."s ") or "")..string.format("%.2f",c):gsub("0+$",""):gsub("%.$","").."c"
end
local function number(n,decimals)
  if type(n)~="number" then return "--" end
  return string.format(decimals and "%.2f" or "%.1f",n):gsub("%.?0+$","")
end
local function cell(parent,x,width,font)
  local text=parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlightSmall");text:SetPoint("LEFT",parent,"LEFT",x,0);text:SetWidth(width);text:SetJustifyH("LEFT");text:SetWordWrap(false);return text
end
local function render()
  if not panel then return end
  offset=math.max(0,math.min(offset,math.max(0,#filtered-pageSize)))
  for i,row in ipairs(rows) do
    local item=filtered[offset+i];row.item=item
    if item then
      row.name:SetText(item.name.."  |cff829494#"..item.id.."|r");row.price:SetText(money(item.price));row.listed:SetText(item.listed and tostring(item.listed) or "--")
      row.sales:SetText(number(item.sales));row.coverage:SetText(number(item.coverage,true));row.gap:SetText(item.gap and number(item.gap) or "--");row.pressure:SetText(number(item.pressure,true));row:Show()
    else row:Hide() end
  end
  footer:SetText((#filtered==0 and "No matching items" or ((offset+1).."-"..math.min(offset+pageSize,#filtered).." of "..#filtered)).." | Scroll to browse | -- = unavailable")
  for _,col in ipairs(columns) do col.button:SetText(col.label..(sortKey==col.key and (ascending and " ^" or " v") or "")) end
end
local function filter()
  local term=search and (search:GetText() or ""):lower():match("^%s*(.-)%s*$") or ""
  filtered={}
  for _,item in ipairs(data) do if term=="" or item.name:lower():find(term,1,true) or tostring(item.id):find(term,1,true) then filtered[#filtered+1]=item end end
  table.sort(filtered,function(a,b)
    local av,bv=a[sortKey],b[sortKey]
    if av==nil and bv~=nil then return false elseif bv==nil and av~=nil then return true end
    if av==bv then return a.id<b.id end
    if type(av)=="string" then av=av:lower();bv=bv:lower() end
    if av==bv then return a.id<b.id end
    return ascending and av<bv or (not ascending and av>bv)
  end)
  offset=0;render()
end
local function refresh()
  if not panel then return end
  data={}
  local market=core.Market();local activityMarket,err=NokiUnifiedMarketActivityMarket()
  local book=market and NokiUnifiedCoreDB and NokiUnifiedCoreDB.prices and NokiUnifiedCoreDB.prices[market]
  local info=activityMarket and activityMarket==market and NokiUnifiedAPI and NokiUnifiedAPI.GetTableInfo and NokiUnifiedAPI.GetTableInfo()
  local now=(GetServerTime and GetServerTime()) or time()
  local catalog=NokiUnifiedMarketDB and NokiUnifiedMarketDB.itemCatalog or {}
  if book and book.items then
    for id,price in pairs(book.items) do
      if type(id)=="number" and type(price)=="table" and not price.carried and type(price.price)=="number" then
        local saved=catalog[tostring(id)] or catalog[id];local name=(saved and saved.name) or (GetItemInfo and GetItemInfo(id)) or ("Item #"..id)
        local remote=info and NokiUnifiedAPI.GetPrice(id);local sales=remote and remote.soldPerDay
        if type(sales)~="number" or sales<0 or sales~=sales or sales==math.huge then sales=nil end
        local listed=type(price.quantity)=="number" and price.quantity>=0 and price.quantity or nil
        local coverage=sales and sales>0 and listed and listed/sales or nil
        local pressure=coverage and math.sqrt(math.min(sales,1000))/(.25+coverage) or nil
        data[#data+1]={id=id,name=name,price=price.price,listed=listed,sales=sales,coverage=coverage,gap=sales and listed and sales-listed or nil,pressure=pressure}
      end
    end
  end
  local scanAge=book and book.observed and math.max(0,math.floor((now-book.observed)/60))
  local sourceAge=info and type(info.updated)=="number" and math.max(0,math.floor((now-info.updated)/60))
  status:SetText("Scan "..(scanAge and (scanAge.."m"..(scanAge>=60 and " OLD" or "")) or "unavailable").." | AHledger "..(sourceAge and (sourceAge.."m"..(sourceAge>=1440 and " STALE" or "")) or (err or "unavailable")).." | "..(market or "market unavailable"))
  filter()
end
local function build()
  if panel or not AuctionHouseFrame or not NokiUnifiedTabs then return end
  panel=CreateFrame("Frame",nil,AuctionHouseFrame,"BackdropTemplate");panel:Hide();panel:SetPoint("TOPLEFT",AuctionHouseFrame,"TOPLEFT",12,-75);panel:SetPoint("BOTTOMRIGHT",AuctionHouseFrame,"BOTTOMRIGHT",-12,35);panel:SetFrameStrata("DIALOG");panel:SetFrameLevel(AuctionHouseFrame:GetFrameLevel()+50);panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1});panel:SetBackdropColor(.055,.065,.07,1);panel:SetBackdropBorderColor(.24,.30,.28,1)
  local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-14);title:SetText("DEMAND RESEARCH")
  search=CreateFrame("EditBox",nil,panel,"InputBoxTemplate");search:SetSize(180,24);search:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-43);search:SetAutoFocus(false);search:SetMaxLetters(60);search:SetScript("OnTextChanged",filter);search:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
  local reload=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");reload:SetSize(105,22);reload:SetPoint("LEFT",search,"RIGHT",12,0);reload:SetText("Refresh table");reload:SetScript("OnClick",refresh)
  status=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");status:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-74);status:SetJustifyH("LEFT")
  local header=CreateFrame("Frame",nil,panel,"BackdropTemplate");header:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-96);header:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-25,-96);header:SetHeight(24);header:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});header:SetBackdropColor(.13,.18,.17,1)
  local defs={{"ITEM","name",5,260},{"AH LOW","price",265,105},{"LISTED","listed",370,85},{"EST. / DAY","sales",455,105},{"LISTED / DAY","coverage",560,115},{"GAP / DAY","gap",675,100},{"PRESSURE","pressure",775,105}}
  for _,def in ipairs(defs) do
    local col={label=def[1],key=def[2]};local button=CreateFrame("Button",nil,header,"UIPanelButtonTemplate");button:SetPoint("LEFT",header,"LEFT",def[3],0);button:SetSize(def[4]-3,22);col.button=button;columns[#columns+1]=col
    button:SetScript("OnClick",function() if sortKey==col.key then ascending=not ascending else sortKey=col.key;ascending=col.key=="name" or col.key=="coverage" end;filter() end)
  end
  for i=1,pageSize do
    local row=CreateFrame("Frame",nil,panel,"BackdropTemplate");row:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-121-(i-1)*26);row:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-25,-121-(i-1)*26);row:SetHeight(25);row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});row:SetBackdropColor(i%2==0 and .12 or .08,.12,.12,.95)
    row.name=cell(row,5,250);row.price=cell(row,265,100);row.listed=cell(row,370,80);row.sales=cell(row,455,100);row.coverage=cell(row,560,110);row.gap=cell(row,675,95);row.pressure=cell(row,775,95);rows[i]=row
    row:EnableMouse(true);row:SetScript("OnEnter",function(self) if self.item and GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetItemByID(self.item.id);GameTooltip:Show() end end);row:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
  end
  footer=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");footer:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-388)
  local note=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");note:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-410);note:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-20,-410);note:SetJustifyH("LEFT");note:SetText("Listed / day = listed units / estimated sales per day. Gap = estimated sales per day - listed units. Pressure = sqrt(min(sales/day, 1,000)) / (0.25 + listed/day). This is a ranking, not a shortage forecast. Supply and prices are snapshots.")
  local function wheel(_,delta) offset=math.max(0,math.min(math.max(0,#filtered-pageSize),offset-delta));render() end
  panel:EnableMouseWheel(true);panel:SetScript("OnMouseWheel",wheel);for _,row in ipairs(rows) do row:EnableMouseWheel(true);row:SetScript("OnMouseWheel",wheel) end
  local width,height
  panel:SetScript("OnShow",function() if not width then width,height=AuctionHouseFrame:GetWidth(),AuctionHouseFrame:GetHeight();AuctionHouseFrame:SetSize(width+220,height+160) end;refresh() end)
  panel:SetScript("OnHide",function() if width then AuctionHouseFrame:SetSize(width,height);width=nil;height=nil end end)
  NokiUnifiedTabs:CreateTab("NokiDemand",panel,"Demand")
end
local events=CreateFrame("Frame");for _,event in ipairs({"AUCTION_HOUSE_SHOW","GET_ITEM_INFO_RECEIVED"}) do pcall(events.RegisterEvent,events,event) end
local namesPending=false
events:SetScript("OnEvent",function(_,event)
  if event=="AUCTION_HOUSE_SHOW" then if C_Timer and C_Timer.After then C_Timer.After(.5,build) else build() end
  elseif panel and panel:IsShown() and not namesPending then
    namesPending=true
    if C_Timer and C_Timer.After then C_Timer.After(1,function() namesPending=false;if panel:IsShown() then refresh() end end) else namesPending=false end
  end
end)
core.Subscribe(function(event) if event=="complete" and panel and panel:IsShown() then refresh() end end)
