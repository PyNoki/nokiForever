-- Show the last scanned unit price on hover and expanded valuation on Shift.
local function money(n)
  local c=math.floor(n*100+0.5)/100;local g=math.floor(c/10000);local s=math.floor(c%10000/100);c=c%100
  local gold="|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t"
  local silver="|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:0:0|t"
  local copper="|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:0:0|t"
  local parts={}
  if g>0 then parts[#parts+1]=g..gold end
  if s>0 then parts[#parts+1]=s..silver end
  if c>0 or #parts==0 then parts[#parts+1]=string.format("%.2f",c):gsub("0+$",""):gsub("%.$","")..copper end
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
  if AuctionHouseFrame then
    for _,key in ipairs({"CommoditiesSellFrame","ItemSellFrame"}) do
      local frame=AuctionHouseFrame[key]
      local cursor=owner
      for _=1,8 do
        if not cursor then break end
        if frame and cursor==frame then
          local location=frame.GetItem and frame:GetItem()
          local itemID=location and C_Item and C_Item.GetItemID and C_Item.GetItemID(location)
          local quantity=frame.GetQuantity and frame:GetQuantity()
          if itemID==id and type(quantity)=="number" and quantity>0 then return quantity,nil,false,true end
          break
        end
        cursor=cursor.GetParent and cursor:GetParent()
      end
    end
  end
  -- Forever bank buttons expose tab and slot separately, not GetBagID/GetID.
  if owner.GetBankTabID and owner.GetContainerSlotID and C_Container and C_Container.GetContainerItemInfo then
    local okBag,bank=pcall(owner.GetBankTabID,owner)
    local okSlot,bankSlot=pcall(owner.GetContainerSlotID,owner)
    if okBag and okSlot and type(bank)=="number" and type(bankSlot)=="number" then
      local ok,info=pcall(C_Container.GetContainerItemInfo,bank,bankSlot)
      local itemID=ok and type(info)=="table" and (info.itemID or (info.hyperlink and tonumber(info.hyperlink:match("item:(%d+)"))))
      if itemID==id and type(info.stackCount)=="number" and info.stackCount>0 then return info.stackCount end
    end
  end
  -- Some item buttons provide an ItemLocation instead of container IDs.
  if owner.GetItemLocation and C_Item and C_Item.GetItemID and C_Item.GetStackCount then
    local ok,location=pcall(owner.GetItemLocation,owner)
    if ok and location then
      local idOK,itemID=pcall(C_Item.GetItemID,location)
      if idOK and itemID==id then
        local countOK,quantity=pcall(C_Item.GetStackCount,location)
        if countOK and type(quantity)=="number" and quantity>0 then return quantity end
      end
    end
  end
  local bag=owner.GetBagID and owner:GetBagID()
  local slot=owner.GetID and owner:GetID()
  local name=owner.GetName and owner:GetName()
  -- The main bank uses its own item buttons rather than a container frame.
  if name and name:match("^BankFrameItem%d+$") then
    bag=(Enum and Enum.BagIndex and Enum.BagIndex.Bank) or BANK_CONTAINER or -1
  end
  local parent=owner.GetParent and owner:GetParent()
  if type(bag)~="number" and parent and parent.GetName and (parent:GetName() or ""):match("^ContainerFrame%d+") then bag=parent.GetID and parent:GetID() end
  if type(bag)=="number" and type(slot)=="number" and C_Container and C_Container.GetContainerItemInfo then
    local info=C_Container.GetContainerItemInfo(bag,slot)
    if type(info)=="table" and (not info.itemID or info.itemID==id) and type(info.stackCount)=="number" and info.stackCount>0 then return info.stackCount end
  end
  return nil
end
NokiUnifiedCore.ItemStackContext=stackCount
local function vendorSellValue(id,link)
  local getInfo=(C_Item and C_Item.GetItemInfo) or GetItemInfo
  if getInfo then
    local info={pcall(getInfo,link or id)}
    if info[1] and type(info[12])=="number" then return info[12] end
  end
  -- Catalog values are keyed by item ID and may differ for a modified item.
  if not link then
    local catalog=NokiUnifiedMarketDB and NokiUnifiedMarketDB.itemCatalog
    local item=catalog and (catalog[tostring(id)] or catalog[id])
    if item and type(item.vendorSell)=="number" then return item.vendorSell end
  end
  if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID,id) end
end
-- These are observed vendor offers, not a guarantee a vendor is accessible or stocked.
local vendorBuyIndex
local function vendorBuyReference(id)
  if not vendorBuyIndex then
    if type(NokiUnifiedMarketVendorData)~="table" then return nil end
    vendorBuyIndex={}
    for _,offer in ipairs(NokiUnifiedMarketVendorData) do
      local item,price,pack=offer[1],offer[4],offer[5]
      if type(item)=="number" and type(price)=="number" and price>0 and type(pack)=="number" and pack>0 then
        local unit=price/pack
        if not vendorBuyIndex[item] or unit<vendorBuyIndex[item] then vendorBuyIndex[item]=unit end
      end
    end
  end
  return vendorBuyIndex[id]
end
local function addValue(tooltip,data)
  if tooltip.IsForbidden and tooltip:IsForbidden() then return end
  local id=data and data.id
  local link;if tooltip.GetItem then local _;_,link=tooltip:GetItem() end
  if not id then id=link and tonumber(link:match("item:(%d+)")) end
  if not id then return end
  local market=NokiUnifiedCore.Market();local book=market and NokiUnifiedCoreDB and NokiUnifiedCoreDB.prices and NokiUnifiedCoreDB.prices[market]
  local row=book and book.items and book.items[id];local count,cost,isMerchant,isAuction=stackCount(tooltip,id)
  local now=(GetServerTime and GetServerTime()) or time()
  local scanAge=book and type(book.observed)=="number" and math.max(0,math.floor((now-book.observed)/60))
  local priceAge
  local function pair(label,value)
    if tooltip.AddDoubleLine then tooltip:AddDoubleLine(label,value,.45,.9,.7,1,1,1)
    else tooltip:AddLine(label.."  "..value,.45,.9,.7) end
  end
  local sell=vendorSellValue(id,link)
  pair("Vendor sell / unit",sell and money(sell) or "Loading...")
  if isMerchant and type(cost)=="number" and cost>0 and count and count>0 then
    pair("Vendor buy / unit",money(cost/count))
  else
    local buy=vendorBuyReference(id)
    pair("Vendor buy / unit (ref)",buy and money(buy) or "--")
  end
  if row and type(row.price)=="number" and row.price>0 then
    local observed=type(row.observed)=="number" and math.max(0,math.floor((now-row.observed)/60)) or scanAge
    pair("AH / unit"..(observed and (" ("..observed.."m ago)") or ""),money(row.price))
  else
    local reference=NokiUnifiedAPI and NokiUnifiedAPI.GetPrice(id)
    if reference and type(reference.minBuyout)=="number" and reference.minBuyout>0 then
      local minutes=type(reference.updated)=="number" and math.max(0,math.floor((now-reference.updated)/60))
      pair("AH reference / unit"..(minutes and (" ("..minutes.."m ago)") or ""),money(reference.minBuyout))
    else pair("AH / unit","--") end
  end
  if not IsShiftKeyDown or not IsShiftKeyDown() then tooltip:Show();return end
  if row and type(row.price)=="number" and row.price>0 then
    priceAge=type(row.observed)=="number" and math.max(0,math.floor((now-row.observed)/60)) or scanAge
    if count then
      local gross=row.price*count;local net=math.floor(gross*95/100)
      pair((isAuction and "Auction quantity (" or "Stack price (")..count..")",money(gross))
      pair("After 5% AH cut",money(net))
      if isMerchant and type(cost)=="number" and cost>=0 then
        pair("Vendor pack cost",money(cost))
        local gain=net-cost
        pair("Est. pack profit",(gain<0 and "-" or "")..money(math.abs(gain)))
      end
    else tooltip:AddLine("Stack size unavailable",.8,.8,.8) end
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
local function itemTooltipCallback(tooltip,data)
  if securecallfunction then securecallfunction(addValue,tooltip,data) else addValue(tooltip,data) end
end
if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,itemTooltipCallback)
elseif GameTooltip and GameTooltip.HookScript then GameTooltip:HookScript("OnTooltipSetItem",itemTooltipCallback) end
local f=CreateFrame("Frame");f:RegisterEvent("MODIFIER_STATE_CHANGED");f:RegisterEvent("GET_ITEM_INFO_RECEIVED");f:SetScript("OnEvent",function(_,event,key,success)
  if not GameTooltip or not GameTooltip.IsShown or not GameTooltip:IsShown() or not GameTooltip.RefreshData or not GameTooltip.GetItem then return end
  if GameTooltip.IsForbidden and GameTooltip:IsForbidden() then return end
  local ok,_,link=pcall(GameTooltip.GetItem,GameTooltip)
  local itemID=ok and type(link)=="string" and tonumber(link:match("item:(%d+)"))
  if not itemID then return end
  if event=="MODIFIER_STATE_CHANGED" then
    if key~="LSHIFT" and key~="RSHIFT" then return end
  else
    if not success or itemID~=key then return end
  end
  if securecallfunction then securecallfunction(GameTooltip.RefreshData,GameTooltip) else GameTooltip:RefreshData() end
end)
