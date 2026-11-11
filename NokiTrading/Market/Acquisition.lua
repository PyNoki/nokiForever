-- Estimated acquisition costs in the native auction buy view.
local core=NokiUnifiedCore
local function money(value)
  local c=math.floor(value*100+0.5)/100
  local g=math.floor(c/10000);local s=math.floor(c%10000/100);c=c%100
  local parts={};local function add(n,icon) parts[#parts+1]=n.."|TInterface\\MoneyFrame\\UI-"..icon.."Icon:12:12:0:0|t" end
  if g>0 then add(g,"Gold") end;if s>0 then add(s,"Silver") end
  if c>0 or #parts==0 then add(string.format("%.2f",c):gsub("0+$",""):gsub("%.$",""),"Copper") end
  return table.concat(parts," ")
end
local vendorIndex,recipeIndex
local function indexes()
  if not vendorIndex then
    vendorIndex={}
    for _,v in ipairs(NokiUnifiedMarketVendorData or {}) do
      if type(v[1])=="number" and type(v[4])=="number" and v[4]>=0 and type(v[5])=="number" and v[5]>0 then
        vendorIndex[v[1]]=vendorIndex[v[1]] or {};table.insert(vendorIndex[v[1]],v)
      end
    end
  end
  if not recipeIndex then
    recipeIndex={}
    for _,r in pairs((NokiUnifiedCraftCraftCatalog and NokiUnifiedCraftCraftCatalog.recipes) or {}) do
      if type(r.output)=="number" then recipeIndex[r.output]=recipeIndex[r.output] or {};table.insert(recipeIndex[r.output],r) end
    end
  end
end
local function vendorCost(id,quantity,ah)
  local best,bestOffer,auctionCount=ah and ah*quantity,nil,ah and quantity or nil
  for _,v in ipairs(vendorIndex[id] or {}) do
    local pack,price=v[5],v[4]
    -- For one vendor and the auction low, the cheapest mix is at an endpoint.
    local count=math.floor(quantity/pack)
    for _,packs in ipairs({count,count+1}) do
      if packs>0 then
        local remaining=math.max(0,quantity-packs*pack)
        if remaining==0 or ah then
          local cost=packs*price+remaining*(ah or 0)
          if not best or cost<best then best,bestOffer,auctionCount=cost,v,remaining end
        end
      end
    end
  end
  return best,bestOffer,auctionCount
end
function core.AcquisitionEstimate(id)
  indexes()
  local market=core.Market();local book=market and NokiUnifiedCoreDB and NokiUnifiedCoreDB.prices and NokiUnifiedCoreDB.prices[market]
  local prices=book and book.items or {};local bestVendor
  for _,v in ipairs(vendorIndex[id] or {}) do if not bestVendor or v[4]/v[5]<bestVendor[4]/bestVendor[5] then bestVendor=v end end
  local bestCraft,knownRecipes,missing
  for _,recipe in ipairs(recipeIndex[id] or {}) do
    knownRecipes=true
    if not recipe.review and type(recipe.yieldMin)=="number" and recipe.yieldMin>0 and type(recipe.materials)=="table" and #recipe.materials>0 then
      local total,details=0,{}
      for _,mat in ipairs(recipe.materials) do
        local row=prices[mat.id];local ah=row and not row.carried and type(row.price)=="number" and row.price>0 and row.price or nil
        local cost,offer,auctionCount=vendorCost(mat.id,mat.quantity,ah)
        if not cost then total=nil;break end
        total=total+cost
        local source=offer and ((auctionCount and auctionCount>0) and "vendor + AH" or "vendor") or "AH"
        details[#details+1]=mat.quantity.." x "..(mat.name or ("Item #"..mat.id)).." ("..source..")"
      end
      if total then
        local unit=total/recipe.yieldMin
        if not bestCraft or unit<bestCraft.unit then bestCraft={unit=unit,total=total,recipe=recipe,details=details} end
      else missing=true end
    else missing=true end
  end
  return {vendor=bestVendor,craft=bestCraft,recipes=knownRecipes,missing=missing,scan=book and book.observed}
end
local widgets={}
local function widget(parent)
  if widgets[parent] then return widgets[parent] end
  local box=CreateFrame("Frame",nil,parent,"BackdropTemplate");box:SetSize(228,32);box:SetPoint("TOPLEFT",parent,"TOPLEFT",150,-8);box:SetFrameLevel(parent:GetFrameLevel()+10);box:EnableMouse(true)
  local function line(x,y,width,text)
    local t=box:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");t:SetPoint("TOPLEFT",box,"TOPLEFT",x,y);t:SetWidth(width);t:SetHeight(14);t:SetJustifyH("LEFT");t:SetWordWrap(false);if text then t:SetText(text) end;return t
  end
  line(0,0,108,"Craft / unit");line(118,0,110,"Vendor / unit")
  local craft=line(0,-15,108);local vendor=line(118,-15,110)
  box.craft=craft;box.vendor=vendor
  box:SetScript("OnEnter",function(self)
    if not GameTooltip or not self.estimate then return end
    local e=self.estimate;GameTooltip:SetOwner(self,"ANCHOR_LEFT");GameTooltip:SetText("Estimated acquisition cost")
    if e.craft then
      local r=e.craft.recipe;GameTooltip:AddLine("Craft: "..r.name.." ("..(r.profession or "profession unknown")..")",1,1,1,true)
      GameTooltip:AddLine("Materials: "..table.concat(e.craft.details,", "),.8,.8,.8,true)
      GameTooltip:AddLine("Total "..money(e.craft.total).." per craft; assumes at least "..r.yieldMin.." produced.",.8,.8,.8,true)
    else GameTooltip:AddLine(e.recipes and "Crafting cost unavailable: recipe or material prices missing." or "No recipe in the catalog.",.8,.8,.8,true) end
    if e.vendor then local v=e.vendor;GameTooltip:AddLine("Vendor: "..v[3].."; "..v[5].." for "..money(v[4])..(v[8] and " (limited stock)" or ""),1,1,1,true) end
    GameTooltip:AddLine("Estimates use scanned AH lows and vendor reference prices. Check availability, pack sizes, recipe access and binding.",1,.8,.3,true);GameTooltip:Show()
  end)
  box:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
  widgets[parent]=box;return box
end
local generation=0
local function showCost(_,result)
  generation=generation+1;local current=generation
  local key=result and result.itemKey;local id=key and key.itemID
  for _,box in pairs(widgets) do box:Hide() end
  if type(id)~="number" then return end
  local function update()
    if current~=generation or not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return end
    local estimate=core.AcquisitionEstimate(id)
    for _,name in ipairs({"ItemBuyFrame","CommoditiesBuyFrame"}) do
      local parent=AuctionHouseFrame[name]
      if parent then
        local box=widget(parent);box.estimate=estimate
        box.craft:SetText(estimate.craft and ("~"..money(estimate.craft.unit)) or "--")
        box.vendor:SetText(estimate.vendor and ("~"..money(estimate.vendor[4]/estimate.vendor[5])) or "--")
        box:Show()
      end
    end
  end
  update();if C_Timer and C_Timer.After then C_Timer.After(0,update) end
end
local hooked=false
local events=CreateFrame("Frame");events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:SetScript("OnEvent",function()
  if not hooked and AuctionHouseFrame and type(AuctionHouseFrame.SelectBrowseResult)=="function" and hooksecurefunc then
    hooksecurefunc(AuctionHouseFrame,"SelectBrowseResult",showCost);hooked=true
  end
end)
