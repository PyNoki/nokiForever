-- A research table: listed supply is a snapshot; daily sales are estimates.
local core=NokiUnifiedCore
local panel,search,status,footer,rows,columns=nil,nil,nil,nil,{},{}
local data,filtered={},{}
local sortKey,ascending,offset="pressure",false,0
local selectedID,analysis,analysisStatus,analysisSummary,analysisRows,analysisPage=nil,nil,nil,nil,{},0
local lastClickedID
local analysisMode="best"
local refreshAnalysis,refreshRecipes
local recipeRows,recipeOffset,recipeList={},0,{}
local pageSize=10
local function money(n)
  if type(n)~="number" then return "--" end
  if n<0 then return "-"..money(-n) end
  local g=math.floor(n/10000);local s=math.floor(n%10000/100);local c=n%100
  return (g>0 and (g.."g ") or "")..(s>0 and (s.."s ") or "")..string.format("%.2f",c):gsub("0+$",""):gsub("%.$","").."c"
end
local function number(n,decimals)
  if type(n)~="number" then return "--" end
  return string.format(decimals and "%.2f" or "%.1f",n):gsub("%.?0+$","")
end
function core.DemandRecipes(itemID)
  local found={}
  for _,recipe in pairs((NokiUnifiedCraftCraftCatalog and NokiUnifiedCraftCraftCatalog.recipes) or {}) do
    for _,material in ipairs(recipe.materials or {}) do
      if material.id==itemID then
        found[#found+1]={name=recipe.name or ("Recipe #"..tostring(recipe.id)),profession=recipe.profession or "?",skill=tonumber(recipe.required),trainerSkill=tonumber(recipe.trainerSkill),quantity=material.quantity}
        break
      end
    end
  end
  table.sort(found,function(a,b)
    local x,y=a.skill or math.huge,b.skill or math.huge
    if x~=y then return x<y end
    if a.name~=b.name then return a.name<b.name end
    return a.profession<b.profession
  end)
  return found
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
      if item.id==lastClickedID then row:SetBackdropColor(.18,.32,.25,1) else row:SetBackdropColor(i%2==0 and .12 or .08,.12,.12,.95) end
      row.name:SetText(item.name.."  |cff829494#"..item.id.."|r");row.price:SetText(money(item.price));row.listed:SetText(item.listed and tostring(item.listed) or "--")
      row.sales:SetText(number(item.sales));row.coverage:SetText(number(item.coverage,true));row.gap:SetText(item.gap and number(item.gap) or "--");row.pressure:SetText(number(item.pressure,true));row:Show()
      row.expand:SetText(selectedID==item.id and "-" or "+")
    else row:Hide() end
  end
  footer:SetText((#filtered==0 and "No matching items" or ((offset+1).."-"..math.min(offset+pageSize,#filtered).." of "..#filtered)).." | Scroll to browse | -- = unavailable")
  for _,col in ipairs(columns) do col.button:SetText(col.label..(sortKey==col.key and (ascending and " ^" or " v") or "")) end
end
local function filter(preservePosition)
  local previousOffset=offset
  local anchor=preservePosition and filtered[offset+1] and filtered[offset+1].id
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
  offset=preservePosition and previousOffset or 0
  if anchor then for i,item in ipairs(filtered) do if item.id==anchor then offset=i-1;break end end end
  render()
end
local function refresh()
  if not panel then return end
  data={}
  local market=core.Market();local activityMarket,err=NokiUnifiedMarketActivityMarket()
  local book=market and NokiUnifiedCoreDB and NokiUnifiedCoreDB.prices and NokiUnifiedCoreDB.prices[market]
  local normalizedMarket=type(market)=="string" and market:lower():gsub("/", ".") or nil
  local info=activityMarket and activityMarket==normalizedMarket and NokiUnifiedAPI and NokiUnifiedAPI.GetTableInfo and NokiUnifiedAPI.GetTableInfo()
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
        local level,suffix,pet=(price.variant or "0:0:0"):match("^([^:]+):([^:]+):([^:]+)$")
        local key={itemID=id,itemLevel=tonumber(level) or 0,itemSuffix=tonumber(suffix) or 0,battlePetSpeciesID=tonumber(pet) or 0}
        data[#data+1]={id=id,key=key,name=name,price=price.price,listed=listed,sales=sales,coverage=coverage,gap=sales and listed and sales-listed or nil,pressure=pressure}
      end
    end
  end
  local scanAge=book and book.observed and math.max(0,math.floor((now-book.observed)/60))
  local sourceAge=info and type(info.updated)=="number" and math.max(0,math.floor((now-info.updated)/60))
  status:SetText("Scan "..(scanAge and (scanAge.."m"..(scanAge>=60 and " OLD" or "")) or "unavailable").." | AHledger "..(sourceAge and (sourceAge.."m"..(sourceAge>=1440 and " STALE" or "")) or (err or "unavailable")).." | "..(market or "market unavailable"))
  filter(true)
end
local function build()
  if panel or not AuctionHouseFrame or not NokiUnifiedTabs then return end
  panel=CreateFrame("Frame",nil,AuctionHouseFrame,"BackdropTemplate");panel:Hide();panel:SetPoint("TOPLEFT",AuctionHouseFrame,"TOPLEFT",12,-75);panel:SetPoint("BOTTOMRIGHT",AuctionHouseFrame,"BOTTOMRIGHT",-12,35);panel:SetFrameStrata("DIALOG");panel:SetFrameLevel(AuctionHouseFrame:GetFrameLevel()+50);panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1});panel:SetBackdropColor(.055,.065,.07,1);panel:SetBackdropBorderColor(.24,.30,.28,1)
  local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-14);title:SetText("DEMAND RESEARCH")
  search=CreateFrame("EditBox",nil,panel,"InputBoxTemplate");search:SetSize(180,24);search:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-43);search:SetAutoFocus(false);search:SetMaxLetters(60);search:SetScript("OnTextChanged",function() filter() end);search:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
  local reload=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");reload:SetSize(105,22);reload:SetPoint("LEFT",search,"RIGHT",12,0);reload:SetText("Refresh table");reload:SetScript("OnClick",refresh)
  status=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");status:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-74);status:SetJustifyH("LEFT")
  local header=CreateFrame("Frame",nil,panel,"BackdropTemplate");header:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-96);header:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-25,-96);header:SetHeight(24);header:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});header:SetBackdropColor(.13,.18,.17,1)
  local defs={{"ITEM","name",5,260},{"AH LOW","price",265,105},{"LISTED","listed",370,85},{"EST. / DAY","sales",455,105},{"LISTED / DAY","coverage",560,115},{"GAP / DAY","gap",675,100},{"PRESSURE","pressure",775,75}}
  for _,def in ipairs(defs) do
    local col={label=def[1],key=def[2]};local button=CreateFrame("Button",nil,header,"UIPanelButtonTemplate");button:SetPoint("LEFT",header,"LEFT",def[3],0);button:SetSize(def[4]-3,22);col.button=button;columns[#columns+1]=col
    button:SetScript("OnClick",function() if sortKey==col.key then ascending=not ascending else sortKey=col.key;ascending=col.key=="name" or col.key=="coverage" end;filter() end)
  end
  for i=1,pageSize do
    local row=CreateFrame("Frame",nil,panel,"BackdropTemplate");row:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-121-(i-1)*26);row:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-25,-121-(i-1)*26);row:SetHeight(25);row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});row:SetBackdropColor(i%2==0 and .12 or .08,.12,.12,.95)
    row.name=cell(row,5,250);row.price=cell(row,265,100);row.listed=cell(row,370,80);row.sales=cell(row,455,100);row.coverage=cell(row,560,110);row.gap=cell(row,675,95);row.pressure=cell(row,775,72);rows[i]=row
    row.expand=CreateFrame("Button",nil,row,"UIPanelButtonTemplate");row.expand:SetSize(28,21);row.expand:SetPoint("LEFT",row,"LEFT",851,0)
    row.expand:SetScript("OnClick",function()
      local item=row.item;if not item then return end
      lastClickedID=item.id
      if selectedID==item.id then selectedID=nil;analysis=nil;analysisPage=0;recipeList={};recipeOffset=0;refreshRecipes();refreshAnalysis();render();return end
      selectedID=item.id;analysis=nil;analysisPage=0;analysisMode="best";recipeList=core.DemandRecipes(item.id);recipeOffset=0;refreshRecipes();analysisStatus:SetText("Queued: "..item.name.." | checking when the current scan or listing query finishes...");refreshAnalysis(true);render()
      local ok,err=core.CheckBuyout(item.key,function(result,message)
        if selectedID~=item.id then return end
        analysis=result;analysisPage=0;analysisStatus:SetText(result and ("LIVE BUYOUT: "..item.name.." | Checked "..date("%H:%M:%S",result.checked)) or ("BUYOUT: "..item.name.." | "..(message or "Unavailable")));refreshAnalysis(true)
      end)
      if not ok then analysisStatus:SetText("BUYOUT: "..item.name.." | "..err);refreshAnalysis(true) end
    end)
    row.view=CreateFrame("Button",nil,row,"UIPanelButtonTemplate");row.view:SetSize(48,21);row.view:SetPoint("LEFT",row,"LEFT",882,0);row.view:SetText("View")
    row.view:SetScript("OnClick",function()
      local item=row.item;if not item then return end
      lastClickedID=item.id;render()
      if core.phase~="idle" or core.working.buyout or core.working.competition or core.working.pending then print("Noki Trading: wait for the active scan or price check to finish.");return end
      if not AuctionHouseFrame.SelectBrowseResult then print("Noki Trading: the auction buy view is unavailable.");return end
      NokiUnifiedTabs:HideAll()
      local ok,err=pcall(AuctionHouseFrame.SelectBrowseResult,AuctionHouseFrame,{itemKey=item.key,minPrice=item.price})
      if not ok then print("Noki Trading: could not open item: "..tostring(err)) end
    end)
    row:EnableMouse(true);row:SetScript("OnMouseDown",function(self) if self.item then lastClickedID=self.item.id;render() end end);row:SetScript("OnEnter",function(self) if self.item and GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetItemByID(self.item.id);GameTooltip:Show() end end);row:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
  end
  footer=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");footer:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-388)
  local note=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");note:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-410);note:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-20,-410);note:SetJustifyH("LEFT");note:SetText("Listed/day = listed units / estimated sales per day. Pressure = sqrt(min(sales/day, 1,000)) / (0.25 + listed/day). Click + for live buyout tiers; View opens the game's buy screen.")
  analysisStatus=panel:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");analysisStatus:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-445);analysisStatus:SetWidth(560);analysisStatus:SetJustifyH("LEFT");analysisStatus:SetText("Select + to check buyout tiers and recipe uses.")
  analysisSummary=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");analysisSummary:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-464);analysisSummary:SetWidth(560);analysisSummary:SetJustifyH("LEFT");analysisSummary:SetWordWrap(true)
  local listTitle=panel:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");listTitle:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-554);listTitle:SetJustifyH("LEFT")
  for i=1,4 do local line=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");line:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-572-(i-1)*18);line:SetWidth(560);line:SetJustifyH("LEFT");line:SetWordWrap(false);analysisRows[i]=line end
  local older=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");older:SetSize(80,21);older:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-648);older:SetText("Previous")
  local newer=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");newer:SetSize(80,21);newer:SetPoint("LEFT",older,"RIGHT",8,0);newer:SetText("Next")
  local mode=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");mode:SetSize(130,21);mode:SetPoint("LEFT",newer,"RIGHT",12,0)
  local visibleTiers={}
  refreshAnalysis=function(keepStatus)
    if not keepStatus then analysisStatus:SetText("Select + to check buyout tiers and recipe uses.") end
    analysisSummary:SetText("");listTitle:SetText("");for _,line in ipairs(analysisRows) do line:SetText("") end
    if not analysis then older:Hide();newer:Hide();mode:Hide();return end
    visibleTiers={}
    for _,tier in ipairs(analysis.tiers) do if analysisMode=="all" or (tier.profit and tier.profit>0) then visibleTiers[#visibleTiers+1]=tier end end
    if analysisMode=="best" then table.sort(visibleTiers,function(a,b) if a.profit==b.profit then return a.totalCost<b.totalCost end;return a.profit>b.profit end) end
    analysisPage=math.max(0,math.min(analysisPage,math.max(0,#visibleTiers-4)))
    local best=analysis.best
    if best then
      local roi=best.totalCost>0 and string.format("%.0f%%",best.profit/best.totalCost*100) or "--"
      analysisSummary:SetText("|cff7fe5a4BEST STOP: buy "..best.totalQuantity.." units through "..money(best.price).." each|r\nSPEND "..money(best.totalCost).."  |  EST. PROFIT "..money(best.profit).." ("..roi..")\nRELIST "..money(best.resell).." each  |  AFTER CUT "..money(best.net).."\nNext tier: "..best.nextQuantity.." units at "..money(best.nextPrice).."; thin tiers may vanish.\nBuy all: "..analysis.totalQuantity.." for "..money(analysis.totalCost)..". Assumes all sell; no deposits.")
    else analysisSummary:SetText("No positive resale breakpoint found.\nBuy all: "..analysis.totalQuantity.." units for "..money(analysis.totalCost)..".\nNo next price remains after buying the final tier.") end
    listTitle:SetText(analysisMode=="best" and ("TOP ESTIMATED BREAKPOINTS ("..#visibleTiers..")") or "ALL PRICE TIERS")
    for i,line in ipairs(analysisRows) do local t=visibleTiers[analysisPage+i];if t then line:SetText("Stop "..money(t.price).." | "..t.totalQuantity.." units | Spend "..money(t.totalCost).." | Sell "..(t.resell and money(t.resell) or "--").." | Profit "..(t.profit and money(t.profit) or "--")..(t==best and " *" or "")) end end
    older:SetShown(analysisPage>0);newer:SetShown(analysisPage+4<#visibleTiers);mode:SetText(analysisMode=="best" and "Show all tiers" or "Show best");mode:Show()
  end
  older:SetScript("OnClick",function() analysisPage=math.max(0,analysisPage-4);refreshAnalysis(true) end)
  newer:SetScript("OnClick",function() analysisPage=math.min(math.max(0,#visibleTiers-4),analysisPage+4);refreshAnalysis(true) end)
  mode:SetScript("OnClick",function() analysisMode=analysisMode=="best" and "all" or "best";analysisPage=0;refreshAnalysis(true) end)
  refreshAnalysis()
  local recipeFrame=CreateFrame("Frame",nil,panel,"BackdropTemplate");recipeFrame:SetPoint("TOPLEFT",panel,"TOPLEFT",590,-440);recipeFrame:SetPoint("BOTTOMRIGHT",panel,"TOPRIGHT",-20,-671);recipeFrame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1});recipeFrame:SetBackdropColor(.08,.11,.11,.95);recipeFrame:SetBackdropBorderColor(.24,.3,.28,1)
  local recipeTitle=recipeFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");recipeTitle:SetPoint("TOPLEFT",recipeFrame,"TOPLEFT",10,-10);recipeTitle:SetJustifyH("LEFT")
  local skillTitle=recipeFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");skillTitle:SetPoint("TOPRIGHT",recipeFrame,"TOPRIGHT",-12,-10);skillTitle:SetText("SKILL")
  local recipePage=recipeFrame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");recipePage:SetPoint("BOTTOMLEFT",recipeFrame,"BOTTOMLEFT",10,8);recipePage:SetJustifyH("LEFT")
  for i=1,9 do
    local line=CreateFrame("Frame",nil,recipeFrame);line:SetPoint("TOPLEFT",recipeFrame,"TOPLEFT",10,-30-(i-1)*19);line:SetPoint("TOPRIGHT",recipeFrame,"TOPRIGHT",-10,-30-(i-1)*19);line:SetHeight(18)
    line.name=line:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");line.name:SetPoint("LEFT",line,"LEFT",0,0);line.name:SetPoint("RIGHT",line,"RIGHT",-42,0);line.name:SetJustifyH("LEFT");line.name:SetWordWrap(false)
    line.skill=line:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");line.skill:SetPoint("RIGHT",line,"RIGHT",0,0);line.skill:SetWidth(38);line.skill:SetJustifyH("RIGHT");recipeRows[i]=line
  end
  local recipeUp=CreateFrame("Button",nil,recipeFrame,"UIPanelButtonTemplate");recipeUp:SetSize(25,19);recipeUp:SetPoint("BOTTOMRIGHT",recipeFrame,"BOTTOMRIGHT",-39,4);recipeUp:SetText("^")
  local recipeDown=CreateFrame("Button",nil,recipeFrame,"UIPanelButtonTemplate");recipeDown:SetSize(25,19);recipeDown:SetPoint("LEFT",recipeUp,"RIGHT",4,0);recipeDown:SetText("v")
  refreshRecipes=function()
    recipeOffset=math.max(0,math.min(recipeOffset,math.max(0,#recipeList-9)))
    recipeTitle:SetText("RECIPE USES ("..#recipeList..")")
    for i,row in ipairs(recipeRows) do
      local recipe=recipeList[recipeOffset+i]
      if recipe then row.name:SetText(recipe.name.." | "..recipe.profession);row.skill:SetText(recipe.skill and (tostring(recipe.skill)..(recipe.trainerSkill and "*" or "")) or "?");row:Show() else row:Hide() end
    end
    recipePage:SetText(not selectedID and "Select an item" or #recipeList==0 and "No cataloged recipes; catalog incomplete" or ((recipeOffset+1).."-"..math.min(recipeOffset+9,#recipeList).." of "..#recipeList.." | * check trainer"))
    recipeUp:SetShown(recipeOffset>0);recipeDown:SetShown(recipeOffset+9<#recipeList)
  end
  local function recipeScroll(_,delta) recipeOffset=recipeOffset-delta;refreshRecipes() end
  recipeFrame:EnableMouseWheel(true);recipeFrame:SetScript("OnMouseWheel",recipeScroll)
  recipeUp:SetScript("OnClick",function() recipeOffset=recipeOffset-9;refreshRecipes() end)
  recipeDown:SetScript("OnClick",function() recipeOffset=recipeOffset+9;refreshRecipes() end)
  refreshRecipes()
  local function wheel(_,delta) offset=math.max(0,math.min(math.max(0,#filtered-pageSize),offset-delta));render() end
  panel:EnableMouseWheel(true);panel:SetScript("OnMouseWheel",wheel);for _,row in ipairs(rows) do row:EnableMouseWheel(true);row:SetScript("OnMouseWheel",wheel) end
  local width,height
  panel:SetScript("OnShow",function() if not width then width,height=AuctionHouseFrame:GetWidth(),AuctionHouseFrame:GetHeight();AuctionHouseFrame:SetSize(width+220,height+365) end;refresh() end)
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
