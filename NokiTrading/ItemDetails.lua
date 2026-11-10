-- Item analysis from local scans, market estimates, vendor offers and the bundled recipe catalog.
local core=NokiUnifiedCore
local window,body,heading
local function cash(value)
  if type(value)~="number" then return "--" end
  if value<0 then return "-"..cash(-value) end
  value=math.floor(value+.5);local g=math.floor(value/10000);local s=math.floor(value%10000/100);local c=value%100
  local t={};if g>0 then t[#t+1]=g.."g" end;if s>0 then t[#t+1]=s.."s" end;if c>0 or #t==0 then t[#t+1]=c.."c" end;return table.concat(t," ")
end
local function timeAge(timestamp)
  if type(timestamp)~="number" then return "unknown" end
  local n=(GetServerTime and GetServerTime()) or time();return math.max(0,math.floor((n-timestamp)/60)).."m ago"
end
local function bookForMarket()
  local key=core.Market();return key and NokiUnifiedCoreDB and NokiUnifiedCoreDB.prices and NokiUnifiedCoreDB.prices[key],key
end
local function makeWindow()
  if window then return end
  window=CreateFrame("Frame","NokiTradingItemDetails",UIParent,"BackdropTemplate");window:SetSize(700,550);window:SetPoint("CENTER");window:SetFrameStrata("DIALOG");window:SetClampedToScreen(true);window:SetMovable(true);window:EnableMouse(true);window:RegisterForDrag("LeftButton");window:SetScript("OnDragStart",function(self) self:StartMoving() end);window:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
  window:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1});window:SetBackdropColor(.055,.065,.07,.98);window:SetBackdropBorderColor(.3,.38,.34,1)
  heading=window:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");heading:SetPoint("TOPLEFT",window,"TOPLEFT",18,-16);heading:SetWidth(600);heading:SetJustifyH("LEFT")
  local close=CreateFrame("Button",nil,window,"UIPanelCloseButton");close:SetPoint("TOPRIGHT",window,"TOPRIGHT",-5,-5)
  local scroll=CreateFrame("ScrollFrame","NokiTradingItemDetailsScroll",window,"UIPanelScrollFrameTemplate");scroll:SetPoint("TOPLEFT",window,"TOPLEFT",18,-48);scroll:SetPoint("BOTTOMRIGHT",window,"BOTTOMRIGHT",-35,16)
  local content=CreateFrame("Frame",nil,scroll);content:SetSize(640,1100);scroll:SetScrollChild(content)
  body=content:CreateFontString(nil,"OVERLAY","GameFontHighlight");body:SetPoint("TOPLEFT",content,"TOPLEFT",0,0);body:SetWidth(640);body:SetJustifyH("LEFT");body:SetJustifyV("TOP");body:SetWordWrap(true)
  window:Hide()
end
local function detailText(id,quantity,merchantCost)
  local book,market=bookForMarket();local row=book and book.items and book.items[id];local price=row and row.price
  if type(price)~="number" or price<=0 then price=nil end
  local activity=NokiUnifiedAPI and NokiUnifiedAPI.GetPrice(id);local info=NokiUnifiedAPI and NokiUnifiedAPI.GetTableInfo()
  local lines={"|cffffd100MARKET|r", "Market: "..tostring(market or "unavailable"),"Lowest scanned unit: "..cash(price).."  |  Price age: "..timeAge(row and row.observed or book and book.observed),"Listed units: "..((row and not row.carried and type(row.quantity)=="number") and tostring(row.quantity) or "--").."  |  Scan: "..timeAge(book and book.observed),"Estimated sold/day: "..(activity and activity.soldPerDay~=nil and tostring(activity.soldPerDay) or "--").."  |  Estimate age: "..timeAge(info and info.updated)}
  if row and not row.carried and type(row.quantity)=="number" and activity and type(activity.soldPerDay)=="number" then local gap=activity.soldPerDay-row.quantity;lines[#lines+1]="Daily demand minus listed: "..string.format("%+.1f",gap).." units (rough indicator)" end
  if quantity and quantity>0 then local gross=price and price*quantity;local net=gross and math.floor(gross*.95);lines[#lines+1]="\n|cffffd100SELECTED STACK / PACK|r";lines[#lines+1]="Quantity: "..quantity.."  |  Match gross: "..cash(gross).."  |  After 5%: "..cash(net);if type(merchantCost)=="number" and merchantCost>=0 then lines[#lines+1]="Current vendor pack: "..cash(merchantCost).."  |  Est. match profit: "..cash(net and net-merchantCost) end end
  lines[#lines+1]="\n|cffffd100VENDOR|r"
  local vendor=core.OwnedVendorCost and core.OwnedVendorCost(id,quantity and quantity>0 and quantity or 1)
  if vendor then
    lines[#lines+1]=(vendor.observed and "Last observed: " or "Reference: ")..tostring(vendor.vendor).."  |  "..vendor.pack.." units for "..cash(vendor.price)..(vendor.limited and "  |  LIMITED STOCK" or "")
    if price then local gross=price*vendor.pack;lines[#lines+1]="At match: pack gross "..cash(gross).."  |  Est. profit after 5% "..cash(math.floor(gross*.95)-vendor.price);local under=math.floor(price)-1;if under>=1 then local g=under*vendor.pack;lines[#lines+1]="Under 1c: "..cash(under).."/unit  |  Pack gross "..cash(g).."  |  Est. profit "..cash(math.floor(g*.95)-vendor.price) end end
    lines[#lines+1]="Vendor price and availability may change."
  else lines[#lines+1]="No vendor purchase offer recorded." end
  lines[#lines+1]="\n|cffffd100CRAFTING|r"
  local recipes={};local catalog=NokiUnifiedCraftCraftCatalog and NokiUnifiedCraftCraftCatalog.recipes or {}
  for _,recipe in pairs(catalog) do if recipe.output==id then recipes[#recipes+1]=recipe end end
  table.sort(recipes,function(a,b)return (a.required or 9999)<(b.required or 9999) end)
  if #recipes==0 then lines[#lines+1]="No recipe in the bundled catalog." end
  for index=1,math.min(3,#recipes) do
    local r=recipes[index];local low,high=r.yieldMin,r.yieldMax;local yieldText=low and high and (low==high and tostring(low) or low.."-"..high) or "unknown"
    local character=(GetRealmName and GetRealmName() or "?").."|"..(UnitName and UnitName("player") or "?")
    local books=NokiUnifiedCraftDB and NokiUnifiedCraftDB.crafting and NokiUnifiedCraftDB.crafting[character]
    local book=books and books[r.profession];local knowledge=book and book.recipes and book.recipes[r.id] and "known" or "not captured"
    lines[#lines+1]=(r.name or "Recipe").."  |  "..(r.profession or "?").."  |  Skill "..tostring(r.required or "?").."  |  "..knowledge.."  |  Yield "..yieldText..(r.review and "  |  VERIFY RECIPE" or "")
    local cost=0;local missing=false;local mats={}
    for _,m in ipairs(r.materials or {}) do local p=book and book.items and book.items[m.id];local mp=p and not p.carried and p.price;if type(mp)~="number" or mp<=0 then missing=true else cost=cost+mp*m.quantity end;local name=(GetItemInfo and GetItemInfo(m.id)) or m.name or ("#"..m.id);mats[#mats+1]=tostring(m.quantity).." x "..name.." ("..cash(mp).."/ea)" end
    lines[#lines+1]="Materials: "..table.concat(mats,", ")
    if missing then lines[#lines+1]="Craft cost: -- (missing material prices)" else
      lines[#lines+1]="Cost/craft: "..cash(cost)..(price and low and high and ("  |  Match profit: "..cash(math.floor(price*low*.95)-cost)..(low~=high and (" to "..cash(math.floor(price*high*.95)-cost)) or "")) or "  |  Profit: --")
    end
  end
  if #recipes>3 then lines[#lines+1]="Plus "..(#recipes-3).." more recipes; open Noki Crafting for the full list." end
  lines[#lines+1]="\nSales/day is an estimate, not confirmed sales. Prices from AHledger (ahledger.com). Deposits and acquisition costs beyond those shown are excluded."
  return table.concat(lines,"\n")
end
function core.ShowItemDetails(id,quantity,merchantCost)
  id=tonumber(id);if not id or id<=0 then return false end
  makeWindow();local name=(GetItemInfo and GetItemInfo(id)) or ("Item #"..id);heading:SetText(name.."  |  #"..id);body:SetText(detailText(id,quantity,merchantCost));window:Show();return true
end
core.ItemDetailText=detailText
SLASH_NOKITRADINGITEM1="/nokiitem"
SlashCmdList.NOKITRADINGITEM=function(msg) local id=tonumber((msg or ""):match("%d+"));if not core.ShowItemDetails(id) then print("Noki Trading: use /nokiitem ITEM_ID") end end

-- Catch Alt-left-click on the hovered merchant/bag item, without passing the click
-- to the underlying purchase, sell, pickup or move handler.
local overlay=CreateFrame("Button",nil,UIParent);overlay:Hide();overlay:SetFrameStrata("FULLSCREEN_DIALOG");overlay:RegisterForClicks("LeftButtonUp")
core.ItemDetailsOverlay=overlay
if overlay.SetPropagateMouseClicks then overlay:SetPropagateMouseClicks(false) end
local target,targetID,targetQuantity,targetCost
local function clear() overlay:Hide();target=nil;targetID=nil;targetQuantity=nil;targetCost=nil end
-- MouseIsOver can report false for the original button once the overlay is on
-- top of it. Check its screen rectangle so the overlay does not flicker.
local function cursorWithin(frame)
  if not frame or (frame.IsVisible and not frame:IsVisible()) then return false end
  if GetCursorPosition and frame.GetRect and frame.GetEffectiveScale then
    local left,bottom,width,height=frame:GetRect();local scale=frame:GetEffectiveScale()
    if type(left)=="number" and type(bottom)=="number" and type(width)=="number" and type(height)=="number" and type(scale)=="number" and scale>0 then
      local x,y=GetCursorPosition();if type(x)=="number" and type(y)=="number" then x=x/scale;y=y/scale;return x>=left and x<=left+width and y>=bottom and y<=bottom+height end
    end
  end
  return MouseIsOver and (MouseIsOver(frame) or MouseIsOver(overlay)) or false
end
local function supported(owner)
  local node=owner
  for _=1,8 do
    if not node then break end
    local name=node.GetName and node:GetName() or ""
    if name:match("^MerchantItem%d+") or name:match("^ContainerFrame") then return true end
    if node==MerchantFrame then return true end
    if node.GetBagID and node.GetID then local ok,bag=pcall(node.GetBagID,node);local yes,slot=pcall(node.GetID,node);if ok and yes and type(bag)=="number" and type(slot)=="number" then return true end end
    node=node.GetParent and node:GetParent()
  end
  return false
end
overlay:SetScript("OnClick",function(_,button) if button=="LeftButton" and IsAltKeyDown and IsAltKeyDown() then local id,q,c=targetID,targetQuantity,targetCost;clear();core.ShowItemDetails(id,q,c) end end)
local ticker=CreateFrame("Frame");ticker:SetScript("OnUpdate",function()
  if not IsAltKeyDown or not IsAltKeyDown() or (InCombatLockdown and InCombatLockdown()) then if target then clear() end;return end
  if target then if cursorWithin(target) then return else clear() end end
  if not GameTooltip or not GameTooltip.IsShown or not GameTooltip:IsShown() or not GameTooltip.GetOwner or not GameTooltip.GetItem then return end
  local owner=GameTooltip:GetOwner();if not owner or not supported(owner) then return end
  local _,link=GameTooltip:GetItem();local id=link and tonumber(link:match("item:(%d+)"));if not id then return end
  local q,c=core.ItemStackContext(GameTooltip,id)
  target=owner;targetID=id;targetQuantity=q;targetCost=c;overlay:ClearAllPoints();overlay:SetAllPoints(owner);overlay:Show()
end)
