-- Configurable vendor-versus-auction indicators for bag slots.
local core=NokiUnifiedCore
local dots=setmetatable({},{__mode="k"})
local pending,window,rows,status=false,nil,{},nil
local defaults={{threshold=20,r=1,g=.82,b=.2},{threshold=0,r=.25,g=.85,b=.35}}
local function rules()
  if not NokiUnifiedCoreDB then return {} end
  local db=NokiUnifiedCoreDB
  if type(db.bagRules)~="table" then
    db.bagRules={}
    for i,v in ipairs(defaults) do db.bagRules[i]={threshold=v.threshold,r=v.r,g=v.g,b=v.b} end
    db.bagRulesVersion=3
  elseif db.bagRulesVersion~=3 then
    local converted={}
    for _,v in ipairs(db.bagRules) do
      local threshold
      if db.bagRulesVersion==2 and type(v.threshold)=="number" then threshold=100-v.threshold
      elseif type(v.min)=="number" and type(v.max)=="number" then threshold=v.min end
      if threshold and threshold>=-9900 and threshold<=100 then converted[#converted+1]={threshold=threshold,r=v.r,g=v.g,b=v.b} end
    end
    table.sort(converted,function(a,b) return a.threshold>b.threshold end)
    db.bagRules=converted;db.bagRulesVersion=3
  end
  return db.bagRules
end
local function priceFor(id)
  local market=core.Market()
  local book=market and NokiUnifiedCoreDB and NokiUnifiedCoreDB.prices and NokiUnifiedCoreDB.prices[market]
  local row=book and book.items and book.items[id]
  if row and type(row.price)=="number" and row.price>0 then return row.price end
  local reference=NokiUnifiedAPI and NokiUnifiedAPI.GetPrice(id)
  return reference and reference.minBuyout
end
local function vendorFor(id,link)
  local getInfo=(C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not getInfo then return nil end
  local values={pcall(getInfo,link or id)}
  if values[1] and type(values[12])=="number" then return values[12] end
  if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID,id) end
end
local function paint(button,bag,slot)
  local dot=dots[button]
  local info=C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag,slot)
  local id=info and (info.itemID or (info.hyperlink and tonumber(info.hyperlink:match("item:(%d+)"))))
  local selected
  if id then
    local ah=priceFor(id);local vendor=vendorFor(id,info.hyperlink)
    if type(ah)=="number" and ah>0 and type(vendor)=="number" and vendor>0 then
      local percent=(ah-vendor)*100/ah
      for _,rule in ipairs(rules()) do
        if type(rule.threshold)=="number" and percent>rule.threshold then selected=rule;break end
      end
    end
  end
  if not selected then if dot then dot:Hide() end;return end
  if not dot then
    dot=button:CreateTexture(nil,"OVERLAY",nil,7);dot:SetSize(9,9);dot:SetPoint("BOTTOMLEFT",button,"BOTTOMLEFT",3,3);dots[button]=dot
  end
  dot:SetColorTexture(selected.r or 1,selected.g or 1,selected.b or 1,1);dot:Show()
end
local function paintFrame(frame)
  if not frame or not frame.GetID then return end
  local bag=frame:GetID()
  if frame.EnumerateValidItems then
    for a,b in frame:EnumerateValidItems() do
      local button=type(b)=="table" and b or a
      if type(button)=="table" and button.GetID then
        local id=(button.GetBagID and button:GetBagID()) or bag
        if type(id)=="number" then pcall(paint,button,id,button:GetID()) end
      end
    end
  elseif frame.GetName and frame:GetName() then
    local name=frame:GetName()
    for i=1,(frame.size or 36) do
      local button=_G[name.."Item"..i]
      if button and button.IsShown and button:IsShown() and button.GetID then pcall(paint,button,bag,button:GetID()) end
    end
  end
end
local function refresh()
  pending=false
  for _,dot in pairs(dots) do dot:Hide() end
  for i=1,(NUM_CONTAINER_FRAMES or 13) do
    local frame=_G["ContainerFrame"..i]
    if frame and frame.IsShown and frame:IsShown() then pcall(paintFrame,frame) end
  end
  local frame=_G.ContainerFrameCombinedBags
  if frame and frame.IsShown and frame:IsShown() then pcall(paintFrame,frame) end
end
local function schedule()
  if pending then return end
  pending=true
  if C_Timer and C_Timer.After then C_Timer.After(.1,refresh) else refresh() end
end
core.RefreshBagRules=schedule
local hooked=setmetatable({},{__mode="k"})
local function hookFrames()
  if not hooksecurefunc then return end
  local function hook(frame)
    if frame and frame.UpdateItems and not hooked[frame] then
      hooksecurefunc(frame,"UpdateItems",function() schedule() end);hooked[frame]=true
    end
  end
  for i=1,(NUM_CONTAINER_FRAMES or 13) do hook(_G["ContainerFrame"..i]) end
  hook(_G.ContainerFrameCombinedBags)
end
local function chooseColor(row)
  if not ColorPickerFrame then return end
  local r,g,b=row.r,row.g,row.b
  local function setColor()
    local nr,ng,nb=ColorPickerFrame:GetColorRGB()
    row.r,row.g,row.b=nr,ng,nb;row.swatch:SetColorTexture(nr,ng,nb,1)
  end
  local function cancel() row.r,row.g,row.b=r,g,b;row.swatch:SetColorTexture(r,g,b,1) end
  if ColorPickerFrame.SetupColorPickerAndShow then
    ColorPickerFrame:SetupColorPickerAndShow({r=r,g=g,b=b,hasOpacity=false,swatchFunc=setColor,cancelFunc=cancel})
  else
    ColorPickerFrame.func=setColor;ColorPickerFrame.cancelFunc=cancel;ColorPickerFrame.hasOpacity=false
    ColorPickerFrame:SetColorRGB(r,g,b);ColorPickerFrame:Show()
  end
end
local function buildWindow()
  if window then return end
  window=CreateFrame("Frame","NokiBagRulesWindow",UIParent,"BackdropTemplate")
  window:SetSize(530,420);window:SetPoint("CENTER");window:SetFrameStrata("DIALOG");window:SetMovable(true);window:EnableMouse(true);window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart",function(self) self:StartMoving() end);window:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
  window:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1});window:SetBackdropColor(.055,.065,.07,.98);window:SetBackdropBorderColor(.35,.42,.37,1)
  local title=window:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("TOPLEFT",16,-16);title:SetText("BAG SELLING RULES")
  local note=window:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");note:SetPoint("TOPLEFT",16,-43);note:SetPoint("TOPRIGHT",-16,-43);note:SetJustifyH("LEFT");note:SetText("Difference is measured as a percentage of the AH price. Example: AH 1g, vendor 50s = 50% difference. The highest matching rule wins.")
  for i=1,6 do
    local row={};rows[i]=row
    local y=-110-(i-1)*39
    local label=window:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");label:SetPoint("TOPLEFT",20,y-5);label:SetText("AH difference greater than")
    row.threshold=CreateFrame("EditBox",nil,window,"InputBoxTemplate");row.threshold:SetSize(55,24);row.threshold:SetPoint("TOPLEFT",170,y);row.threshold:SetAutoFocus(false);row.threshold:SetMaxLetters(8)
    local suffix=window:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");suffix:SetPoint("TOPLEFT",230,y-5);suffix:SetText("% of AH   Color =")
    row.color=CreateFrame("Button",nil,window,"BackdropTemplate");row.color:SetSize(27,24);row.color:SetPoint("TOPLEFT",375,y);row.color:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1});row.color:SetBackdropBorderColor(.8,.8,.8,1)
    row.swatch=row.color:CreateTexture(nil,"ARTWORK");row.swatch:SetPoint("TOPLEFT",2,-2);row.swatch:SetPoint("BOTTOMRIGHT",-2,2)
    row.color:SetScript("OnClick",function() chooseColor(row) end)
    row.remove=CreateFrame("Button",nil,window,"UIPanelButtonTemplate");row.remove:SetSize(80,24);row.remove:SetPoint("TOPLEFT",425,y);row.remove:SetText("Remove")
    row.remove:SetScript("OnClick",function()
      for n=i,5 do local nextRow=rows[n+1];local dest=rows[n];dest.threshold:SetText(nextRow.threshold:GetText());dest.r,dest.g,dest.b=nextRow.r,nextRow.g,nextRow.b;dest.swatch:SetColorTexture(dest.r,dest.g,dest.b,1) end
      local last=rows[6];last.threshold:SetText("");last.r,last.g,last.b=1,1,1;last.swatch:SetColorTexture(1,1,1,1)
    end)
  end
  status=window:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");status:SetPoint("BOTTOMLEFT",20,49);status:SetWidth(490);status:SetJustifyH("LEFT")
  local save=CreateFrame("Button",nil,window,"UIPanelButtonTemplate");save:SetSize(100,25);save:SetPoint("BOTTOMRIGHT",-126,14);save:SetText("Save rules")
  save:SetScript("OnClick",function()
    local nextRules={};local seen={}
    for _,row in ipairs(rows) do
      local value=row.threshold:GetText()
      if value~="" then
        local threshold=tonumber(value)
        if not threshold or threshold < -9900 or threshold>100 then status:SetText("Enter a percentage from -9900 to 100.");return end
        if seen[threshold] then status:SetText("Each percentage must be different.");return end
        seen[threshold]=true
        nextRules[#nextRules+1]={threshold=threshold,r=row.r,g=row.g,b=row.b}
      end
    end
    table.sort(nextRules,function(a,b) return a.threshold>b.threshold end)
    NokiUnifiedCoreDB=NokiUnifiedCoreDB or {};NokiUnifiedCoreDB.bagRules=nextRules;NokiUnifiedCoreDB.bagRulesVersion=3
    status:SetText("Rules saved. Items without matching prices have no marker.");schedule()
  end)
  local excluded=CreateFrame("Button",nil,window,"UIPanelButtonTemplate");excluded:SetSize(125,25);excluded:SetPoint("BOTTOMLEFT",20,14);excluded:SetText("Excluded items")
  excluded:SetScript("OnClick",function() if core.ShowBagExclusions then core.ShowBagExclusions() end end)
  local close=CreateFrame("Button",nil,window,"UIPanelButtonTemplate");close:SetSize(90,25);close:SetPoint("BOTTOMRIGHT",-22,14);close:SetText("Close");close:SetScript("OnClick",function() window:Hide() end)
  window:SetScript("OnShow",function()
    local saved=rules()
    for i,row in ipairs(rows) do local rule=saved[i];row.threshold:SetText(rule and tostring(rule.threshold) or "");row.r,row.g,row.b=rule and rule.r or 1,rule and rule.g or 1,rule and rule.b or 1;row.swatch:SetColorTexture(row.r,row.g,row.b,1) end
    status:SetText("Prices use the last scan, then the AHledger low. AH cut, binding and deposits are not included.")
  end)
  window:Hide()
end
function core.ToggleBagRules()
  buildWindow()
  if window:IsShown() then window:Hide() else window:Show() end
end
local events=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_LOGIN","ADDON_LOADED","BAG_UPDATE_DELAYED","GET_ITEM_INFO_RECEIVED"}) do events:RegisterEvent(event) end
events:SetScript("OnEvent",function(_,event) if event=="PLAYER_LOGIN" or event=="ADDON_LOADED" then hookFrames() end;schedule() end)
core.Subscribe(schedule)
