-- Choose item IDs to omit from the bag-value total. All stacks of an item are excluded.
local core=NokiUnifiedCore
local window,rows,status=nil,{},nil
local entries,offset,pageSize={},0,8
local requested={}
local function excludedItems()
  NokiBetaCoreDB=NokiBetaCoreDB or {}
  NokiBetaCoreDB.bagValueExclusions=NokiBetaCoreDB.bagValueExclusions or {}
  return NokiBetaCoreDB.bagValueExclusions
end
local function itemInfo(id)
  local getInfo=(C_Item and C_Item.GetItemInfo) or GetItemInfo
  local name,icon
  if getInfo then
    local values={pcall(getInfo,id)}
    if values[1] then name,icon=values[2],values[11] end
  end
  if not icon and C_Item and C_Item.GetItemIconByID then local ok,value=pcall(C_Item.GetItemIconByID,id);if ok then icon=value end end
  if not name and not requested[id] and C_Item and C_Item.RequestLoadItemDataByID then requested[id]=true;pcall(C_Item.RequestLoadItemDataByID,id) end
  return name or ("Item #"..id),icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end
local function collect()
  local items={};local container=C_Container
  if container and container.GetContainerNumSlots and container.GetContainerItemInfo then
    local last=(Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or NUM_BAG_SLOTS or 4
    for bag=0,last do
      for slot=1,(container.GetContainerNumSlots(bag) or 0) do
        local info=container.GetContainerItemInfo(bag,slot)
        local id=info and (info.itemID or (info.hyperlink and tonumber(info.hyperlink:match("item:(%d+)"))))
        if id then
          local item=items[id] or {id=id,count=0};item.count=item.count+(info.stackCount or 1);items[id]=item
        end
      end
    end
  end
  for key,enabled in pairs(excludedItems()) do
    local id=tonumber(key)
    if enabled and id and not items[id] then items[id]={id=id,count=0} end
  end
  local list={}
  for _,item in pairs(items) do item.name,item.icon=itemInfo(item.id);list[#list+1]=item end
  table.sort(list,function(a,b)
    if (a.count>0)~=(b.count>0) then return a.count>0 end
    if a.name~=b.name then return a.name<b.name end
    return a.id<b.id
  end)
  return list
end
local function render(rebuild)
  if not window or not window:IsShown() then return end
  if rebuild then entries=collect() end
  offset=math.max(0,math.min(offset,math.max(0,#entries-pageSize)))
  local excluded=excludedItems()
  for i,row in ipairs(rows) do
    local item=entries[offset+i]
    if item then
      row.itemID=item.id;row.icon:SetTexture(item.icon);row.name:SetText(item.name)
      row.count:SetText(item.count>0 and ("In bags: "..item.count) or "Not in bags")
      row.check:SetChecked(excluded[tostring(item.id)] and true or false);row:Show()
    else row.itemID=nil;row:Hide() end
  end
  status:SetText(#entries==0 and "No bag items or exclusions found." or ("Showing "..(offset+1).."-"..math.min(offset+pageSize,#entries).." of "..#entries))
end
local function build()
  if window then return end
  window=CreateFrame("Frame","NokiBagExclusionsWindow",UIParent,"BackdropTemplate")
  window:SetSize(530,430);window:SetPoint("CENTER");window:SetFrameStrata("FULLSCREEN_DIALOG");window:SetMovable(true);window:EnableMouse(true);window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart",function(self) self:StartMoving() end);window:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
  window:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1});window:SetBackdropColor(.055,.065,.07,.98);window:SetBackdropBorderColor(.35,.42,.37,1)
  local title=window:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("TOPLEFT",16,-16);title:SetText("EXCLUDE FROM BAG VALUE")
  local note=window:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");note:SetPoint("TOPLEFT",16,-43);note:SetPoint("TOPRIGHT",-16,-43);note:SetJustifyH("LEFT");note:SetText("Check an item to exclude all of its stacks from your bag value. Uncheck to include it again. Exclusions are shared across characters.")
  for i=1,pageSize do
    local row=CreateFrame("Frame",nil,window,"BackdropTemplate");row:SetPoint("TOPLEFT",16,-84-(i-1)*35);row:SetPoint("TOPRIGHT",-16,-84-(i-1)*35);row:SetHeight(34);row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});row:SetBackdropColor(i%2==0 and .12 or .08,.12,.12,.95)
    row.check=CreateFrame("CheckButton",nil,row,"UICheckButtonTemplate");row.check:SetSize(25,25);row.check:SetPoint("LEFT",4,0)
    row.icon=row:CreateTexture(nil,"ARTWORK");row.icon:SetSize(25,25);row.icon:SetPoint("LEFT",row.check,"RIGHT",5,0)
    row.name=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");row.name:SetPoint("LEFT",row.icon,"RIGHT",7,0);row.name:SetWidth(275);row.name:SetJustifyH("LEFT");row.name:SetWordWrap(false)
    row.count=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");row.count:SetPoint("RIGHT",-8,0);row.count:SetWidth(105);row.count:SetJustifyH("RIGHT")
    row.check:SetScript("OnClick",function(self)
      if not row.itemID then return end
      local excluded=excludedItems();excluded[tostring(row.itemID)]=self:GetChecked() and true or nil
      if core.RefreshBagValue then core.RefreshBagValue() end
      render(true)
    end)
    row:EnableMouse(true);row:SetScript("OnEnter",function(self) if self.itemID and GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetItemByID(self.itemID);GameTooltip:Show() end end);row:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
    rows[i]=row
  end
  status=window:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");status:SetPoint("BOTTOMLEFT",20,48)
  local previous=CreateFrame("Button",nil,window,"UIPanelButtonTemplate");previous:SetSize(80,24);previous:SetPoint("BOTTOMLEFT",20,14);previous:SetText("Previous");previous:SetScript("OnClick",function() offset=offset-pageSize;render(false) end)
  local nextButton=CreateFrame("Button",nil,window,"UIPanelButtonTemplate");nextButton:SetSize(80,24);nextButton:SetPoint("LEFT",previous,"RIGHT",8,0);nextButton:SetText("Next");nextButton:SetScript("OnClick",function() offset=offset+pageSize;render(false) end)
  local close=CreateFrame("Button",nil,window,"UIPanelButtonTemplate");close:SetSize(90,24);close:SetPoint("BOTTOMRIGHT",-20,14);close:SetText("Close");close:SetScript("OnClick",function() window:Hide() end)
  local function wheel(_,delta) offset=offset-delta;render(false) end
  window:EnableMouseWheel(true);window:SetScript("OnMouseWheel",wheel)
  for _,row in ipairs(rows) do row:EnableMouseWheel(true);row:SetScript("OnMouseWheel",wheel) end
  window:SetScript("OnShow",function() offset=0;render(true) end)
  window:Hide()
end
function core.ShowBagExclusions()
  build();window:Show()
end
local events=CreateFrame("Frame")
events:RegisterEvent("BAG_UPDATE_DELAYED");events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent",function() if window and window:IsShown() then render(true) end end)
