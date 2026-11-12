-- Estimated auction value of items carried in the combined bags.
local core=NokiUnifiedCore
local display, valueButton, pending
local function money(value)
  value=math.floor(value+0.5)
  local gold=math.floor(value/10000)
  local silver=math.floor(value%10000/100)
  local copper=value%100
  return gold.."|TInterface\\MoneyFrame\\UI-GoldIcon:14:14:0:0|t "..
    silver.."|TInterface\\MoneyFrame\\UI-SilverIcon:14:14:0:0|t "..
    copper.."|TInterface\\MoneyFrame\\UI-CopperIcon:14:14:0:0|t"
end
local function refresh()
  pending=false
  if not valueButton then return end
  local market=core.Market()
  local book=market and NokiUnifiedCoreDB and NokiUnifiedCoreDB.prices and NokiUnifiedCoreDB.prices[market]
  local total,missing,priced=0,0,0
  local container=C_Container
  if not container or not container.GetContainerNumSlots or not container.GetContainerItemInfo then
    valueButton.valueText="--"
    valueButton.detail="Bag contents are unavailable."
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
  valueButton.valueText=priced>0 and money(total) or "--"
  valueButton.detail=missing.." item stack"..(missing==1 and "" or "s").." without a price."
end
local function schedule()
  if pending then return end
  pending=true
  if C_Timer and C_Timer.After then C_Timer.After(0,refresh) else refresh() end
end
local function restorePosition()
  local bags=_G.ContainerFrameCombinedBags
  local pos=NokiUnifiedCoreDB and NokiUnifiedCoreDB.bagPosition
  if not bags or not pos or type(pos.x)~="number" or type(pos.y)~="number" then return end
  if InCombatLockdown and InCombatLockdown() then return end
  local x,y=pos.x,pos.y
  -- Older releases saved coordinates in UIParent units.
  if pos.version~=2 then local scale=bags:GetEffectiveScale()/UIParent:GetEffectiveScale();x,y=x/scale,y/scale end
  bags:ClearAllPoints()
  bags:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",x,y)
end
local function updateDrag(self)
  if not self.dragging or (InCombatLockdown and InCombatLockdown()) then return end
  local bags=self:GetParent()
  local scale=bags:GetEffectiveScale()
  local x,y=GetCursorPosition()
  x=x/scale-self.dragOffsetX;y=y/scale-self.dragOffsetY
  local uiScale=UIParent:GetEffectiveScale()/scale
  x=math.max(0,math.min(x,math.max(0,UIParent:GetWidth()*uiScale-bags:GetWidth())))
  y=math.max(0,math.min(y,math.max(0,UIParent:GetHeight()*uiScale-bags:GetHeight())))
  bags:ClearAllPoints()
  bags:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",x,y)
  self.dragX,self.dragY=x,y
end
local function finishDrag(self)
  if not self.dragging then return end
  self.dragging=nil;self:SetScript("OnUpdate",nil)
  if self.dragX and self.dragY and NokiUnifiedCoreDB then
    NokiUnifiedCoreDB.bagPosition={x=self.dragX,y=self.dragY,version=2}
  end
end
local function setupValueButton()
  if valueButton or not ChatFrame1 then return end
  valueButton=CreateFrame("Button","NokiBagValueButton",UIParent,"BackdropTemplate")
  valueButton:SetSize(24,24)
  local pos=NokiUnifiedCoreDB and NokiUnifiedCoreDB.bagValueButtonPosition
  if pos and type(pos.x)=="number" and type(pos.y)=="number" then valueButton:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",pos.x,pos.y)
  else valueButton:SetPoint("BOTTOMLEFT",ChatFrame1,"TOPRIGHT",6,-24) end
  valueButton:SetMovable(true);valueButton:SetClampedToScreen(true);valueButton:RegisterForDrag("LeftButton")
  valueButton:SetScript("OnMouseDown",function(self) self.wasDragged=false end)
  valueButton:SetScript("OnDragStart",function(self) self.wasDragged=true;self:StartMoving() end)
  valueButton:SetScript("OnDragStop",function(self)
    self:StopMovingOrSizing()
    local x,y=self:GetLeft(),self:GetBottom()
    if x and y and NokiUnifiedCoreDB then
      local scale=self:GetEffectiveScale()/UIParent:GetEffectiveScale()
      NokiUnifiedCoreDB.bagValueButtonPosition={x=x*scale,y=y*scale}
    end
  end)
  valueButton:SetScript("OnClick",function(self) if not self.wasDragged and core.ToggleBagRules then core.ToggleBagRules() end end)
  valueButton:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
  valueButton:SetBackdropColor(.07,.08,.07,.9);valueButton:SetBackdropBorderColor(.48,.38,.20,1)
  local icon=valueButton:CreateTexture(nil,"ARTWORK")
  icon:SetPoint("CENTER");icon:SetSize(19,19);icon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
  valueButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
  valueButton:SetScript("OnEnter",function(self)
    GameTooltip:SetOwner(self,"ANCHOR_TOP")
    GameTooltip:AddLine("Estimated bag value")
    GameTooltip:AddLine(self.valueText or "--",1,1,1)
    GameTooltip:AddLine("Uses your last scanned auction price, then the imported auction reference price. Stack quantities are included.",1,1,1,true)
    GameTooltip:AddLine("Prices may be old. Bound items are included; auction fees are not deducted.",1,1,1,true)
    GameTooltip:AddLine(self.detail or "",1,.8,.3,true)
    GameTooltip:AddLine("Click for bag selling rules; drag to move this icon.",.7,.8,.75,true)
    GameTooltip:Show()
  end)
  valueButton:SetScript("OnLeave",function() GameTooltip:Hide() end)
end
local function setup()
  local bags=_G.ContainerFrameCombinedBags
  if display or not bags then return end
  display=CreateFrame("Frame",nil,bags)
  display:SetFrameLevel(bags:GetFrameLevel()+20)
  display:SetPoint("BOTTOMLEFT",bags,"BOTTOMLEFT",18,5)
  display:SetSize(26,18)
  local grip=display:CreateFontString(nil,"OVERLAY","GameFontNormal")
  grip:SetPoint("CENTER");grip:SetText(":::")
  display:EnableMouse(true)
  display:RegisterForDrag("LeftButton")
  display:SetScript("OnDragStart",function(self)
    if InCombatLockdown and InCombatLockdown() then return end
    local left,bottom=bags:GetLeft(),bags:GetBottom()
    if not left or not bottom then return end
    local scale=bags:GetEffectiveScale()
    local x,y=GetCursorPosition()
    self.dragOffsetX=x/scale-left;self.dragOffsetY=y/scale-bottom
    self.dragX,self.dragY=left,bottom
    self.dragging=true
    self:SetScript("OnUpdate",updateDrag)
  end)
  display:SetScript("OnDragStop",finishDrag)
  display:SetScript("OnHide",finishDrag)
  display:SetScript("OnEnter",function(self)
    GameTooltip:SetOwner(self,"ANCHOR_TOP")
    GameTooltip:AddLine("Drag to move bags")
    GameTooltip:AddLine("Available outside combat. Position is saved.",1,1,1,true)
    GameTooltip:Show()
  end)
  display:SetScript("OnLeave",function() GameTooltip:Hide() end)
  bags:HookScript("OnShow",function()
    schedule()
    if C_Timer and C_Timer.After then C_Timer.After(0,restorePosition) else restorePosition() end
  end)
  schedule()
end
local events=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_LOGIN","ADDON_LOADED","BAG_UPDATE_DELAYED","PLAYER_REGEN_ENABLED","PLAYER_REGEN_DISABLED"}) do events:RegisterEvent(event) end
events:SetScript("OnEvent",function(_,event)
  if event=="PLAYER_LOGIN" or event=="ADDON_LOADED" then setupValueButton();setup() end
  if event=="PLAYER_REGEN_DISABLED" and display then finishDrag(display) end
  if event=="PLAYER_LOGIN" or event=="PLAYER_REGEN_ENABLED" then restorePosition() end
  schedule()
end)
core.Subscribe(schedule)
