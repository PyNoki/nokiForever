-- Noki local beta: Shift-hover valuation using the latest completed native scan.
local function money(n)
  local c=math.floor(n+0.5);local g=math.floor(c/10000);local s=math.floor(c%10000/100);c=c%100
  local gold="|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t"
  local silver="|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:0:0|t"
  local copper="|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:0:0|t"
  local parts={}
  if g>0 then parts[#parts+1]=g..gold end
  if s>0 then parts[#parts+1]=s..silver end
  if c>0 or #parts==0 then parts[#parts+1]=c..copper end
  return table.concat(parts," ")
end
local function merchantDetails(tooltip,id)
  local owner=tooltip.GetOwner and tooltip:GetOwner()
  if not owner or not MerchantFrame or not MerchantFrame.IsShown or not MerchantFrame:IsShown() then return nil end
  local name=owner.GetName and owner:GetName()
  local merchant=name and tonumber(name:match("^MerchantItem(%d+)ItemButton$"))
  local parent=owner.GetParent and owner:GetParent()
  if not merchant and parent and parent.GetName then merchant=tonumber((parent:GetName() or ""):match("^MerchantItem(%d+)$")) end
  local cursor=owner;local belongs=false
  for _=1,8 do if not cursor then break end;if cursor==MerchantFrame then belongs=true;break end;local n=cursor.GetName and cursor:GetName();if n and n:match("^MerchantItem%d+") then belongs=true;break end;cursor=cursor.GetParent and cursor:GetParent() end
  if not belongs then return nil end
  if merchant and GetMerchantItemID and id and GetMerchantItemID(merchant)~=id then merchant=nil end
  if not merchant and id and GetMerchantNumItems and GetMerchantItemID then
    local count=GetMerchantNumItems() or 0
    for i=1,count do if GetMerchantItemID(i)==id then if merchant then return nil end;merchant=i end end
  end
  if not merchant then return nil end
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local ok,info=pcall(C_MerchantFrame.GetItemInfo,merchant)
    if ok and type(info)=="table" and type(info.stackCount)=="number" and info.stackCount>0 then return info.stackCount,info.price end
  end
  if GetMerchantItemInfo then local _,_,price,quantity=GetMerchantItemInfo(merchant);if type(quantity)=="number" and quantity>0 then return quantity,price end end
  return nil
end
NokiUnifiedCore.MerchantDetails=merchantDetails
local function stackCount(tooltip,id)
  local count,cost=merchantDetails(tooltip,id)
  if count then return count,cost,true end
  local owner=tooltip.GetOwner and tooltip:GetOwner()
  if not owner then return nil end
  local bag=owner.GetBagID and owner:GetBagID()
  local slot=owner.GetID and owner:GetID()
  local parent=owner.GetParent and owner:GetParent()
  if type(bag)~="number" and parent and parent.GetName and (parent:GetName() or ""):match("^ContainerFrame%d+") then bag=parent.GetID and parent:GetID() end
  if type(bag)=="number" and type(slot)=="number" and C_Container and C_Container.GetContainerItemInfo then
    local info=C_Container.GetContainerItemInfo(bag,slot)
    if type(info)=="table" and type(info.stackCount)=="number" and info.stackCount>0 then return info.stackCount end
  end
  return nil
end
NokiUnifiedCore.ItemStackContext=stackCount
local function addValue(tooltip,data)
  if not IsShiftKeyDown() or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
  local id=data and data.id
  if not id and tooltip.GetItem then local _,link=tooltip:GetItem();id=link and tonumber(link:match("item:(%d+)")) end
  if not id then return end
  local market=NokiUnifiedCore.Market();local book=market and NokiUnifiedCoreDB and NokiUnifiedCoreDB.prices and NokiUnifiedCoreDB.prices[market]
  local row=book and book.items and book.items[id];local count,cost,isMerchant=stackCount(tooltip,id)
  local now=(GetServerTime and GetServerTime()) or time()
  local scanAge=book and type(book.observed)=="number" and math.max(0,math.floor((now-book.observed)/60))
  local priceAge
  local function pair(label,value)
    if tooltip.AddDoubleLine then tooltip:AddDoubleLine(label,value,.45,.9,.7,1,1,1)
    else tooltip:AddLine(label.."  "..value,.45,.9,.7) end
  end
  if row and type(row.price)=="number" and row.price>0 then
    priceAge=type(row.observed)=="number" and math.max(0,math.floor((now-row.observed)/60)) or scanAge
    if count then
      local gross=row.price*count;local net=math.floor(gross*95/100)
      pair("Stack price ("..count..")",money(gross))
      pair("After 5% AH cut",money(net))
      if isMerchant and type(cost)=="number" and cost>=0 then
        pair("Vendor pack cost",money(cost))
        local gain=net-cost
        pair("Est. pack profit",(gain<0 and "-" or "")..money(math.abs(gain)))
      end
    else pair("Price per item",money(row.price));tooltip:AddLine("Stack size unavailable",.8,.8,.8) end
    pair("Listed (last scan)",(not row.carried and type(row.quantity)=="number") and tostring(row.quantity) or "--")
  else tooltip:AddLine("Noki: no matching scan price. Scan the auction house.",1,.7,.3) end
  local activity=NokiUnifiedAPI and NokiUnifiedAPI.GetPrice(id)
  local info=NokiUnifiedAPI and NokiUnifiedAPI.GetTableInfo()
  if activity and type(activity.soldPerDay)=="number" then
    local minutes=info and type(info.updated)=="number" and math.max(0,math.floor((((GetServerTime and GetServerTime()) or time())-info.updated)/60))
    pair("Est. sales / day",tostring(activity.soldPerDay)..(minutes and (" ("..minutes.."m ago)") or " (age ?)") )
    local ageText="Scan: "..(scanAge and (scanAge.."m ago") or "age ?")
    if row and row.carried then ageText="Price: "..(priceAge and (priceAge.."m ago") or "age ?").." | "..ageText end
    tooltip:AddLine(ageText.." | Prices from AHledger (ahledger.com)",.7,.8,.75)
  elseif scanAge then
    local ageText="Scan: "..scanAge.."m ago"
    if row and row.carried then ageText="Price: "..(priceAge and (priceAge.."m ago") or "age ?").." | "..ageText end
    tooltip:AddLine(ageText.." | Sales data unavailable",.7,.8,.75)
  end
  tooltip:Show()
end
if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,addValue)
elseif GameTooltip and GameTooltip.HookScript then GameTooltip:HookScript("OnTooltipSetItem",addValue) end
local f=CreateFrame("Frame");f:RegisterEvent("MODIFIER_STATE_CHANGED");f:SetScript("OnEvent",function(_,_,key)
  if key~="LSHIFT" and key~="RSHIFT" then return end
  if GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown() and GameTooltip.RefreshData then GameTooltip:RefreshData() end
end)
