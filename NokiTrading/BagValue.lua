-- Estimated auction value of items carried in the combined bags.
local core=NokiUnifiedCore
local display, pending
local function money(value)
  value=math.floor(value+0.5)
  local gold=math.floor(value/10000)
  local silver=math.floor(value%10000/100)
  local copper=value%100
  return gold.."|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t "..
    silver.."|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:0:0|t "..
    copper.."|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:0:0|t"
end
local function refresh()
  pending=false
  if not display or not display:IsVisible() then return end
  local market=core.Market()
  local book=market and NokiUnifiedCoreDB and NokiUnifiedCoreDB.prices and NokiUnifiedCoreDB.prices[market]
  local total,missing,priced=0,0,0
  local container=C_Container
  if not container or not container.GetContainerNumSlots or not container.GetContainerItemInfo then
    display.text:SetText("Bag value: --")
    display.detail="Bag contents are unavailable."
    return
  end
  local lastBag=(Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or NUM_BAG_SLOTS or 4
  for bag=0,lastBag do
    for slot=1,(container.GetContainerNumSlots(bag) or 0) do
      local item=container.GetContainerItemInfo(bag,slot)
      if item then
        local id=item.itemID or (item.hyperlink and tonumber(item.hyperlink:match("item:(%d+)")))
        local row=id and book and book.items and book.items[id]
        local price=row and row.price
        if not (type(price)=="number" and price>0) and id and NokiUnifiedAPI then
          local reference=NokiUnifiedAPI.GetPrice(id)
          price=reference and reference.minBuyout
        end
        if type(price)=="number" and price>0 then
          total=total+price*(item.stackCount or 1);priced=priced+1
        else missing=missing+1 end
      end
    end
  end
  display.text:SetText("Bag value: "..(priced>0 and money(total) or "--")..(missing>0 and " *" or ""))
  display.detail=missing.." item stack"..(missing==1 and "" or "s").." without a price."
end
local function schedule()
  if pending then return end
  pending=true
  if C_Timer and C_Timer.After then C_Timer.After(0,refresh) else refresh() end
end
local function setup()
  local bags=_G.ContainerFrameCombinedBags
  if display or not bags then return end
  display=CreateFrame("Frame",nil,bags)
  display:SetPoint("BOTTOMLEFT",bags,"BOTTOMLEFT",18,10)
  display:SetSize(220,18)
  display.text=display:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  display.text:SetPoint("LEFT")
  display.text:SetJustifyH("LEFT")
  display:EnableMouse(true)
  display:SetScript("OnEnter",function(self)
    GameTooltip:SetOwner(self,"ANCHOR_TOP")
    GameTooltip:AddLine("Estimated bag value")
    GameTooltip:AddLine("Uses your last scanned auction price, then the imported auction reference price. Stack quantities are included.",1,1,1,true)
    GameTooltip:AddLine("Prices may be old; bound items and auction fees are not excluded.",1,1,1,true)
    GameTooltip:AddLine(self.detail or "",1,.8,.3,true)
    GameTooltip:Show()
  end)
  display:SetScript("OnLeave",function() GameTooltip:Hide() end)
  bags:HookScript("OnShow",schedule)
  schedule()
end
local events=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_LOGIN","ADDON_LOADED","BAG_UPDATE_DELAYED"}) do events:RegisterEvent(event) end
events:SetScript("OnEvent",function(_,event)
  if event=="PLAYER_LOGIN" or event=="ADDON_LOADED" then setup() end
  schedule()
end)
core.Subscribe(schedule)
