-- AHledger provides an estimate for the configured market, not confirmed sales.
local function addActivity(tooltip, data)
  if not IsShiftKeyDown() or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
  local id = data and data.id
  if not id and tooltip.GetItem then
    local _, link = tooltip:GetItem()
    id = link and tonumber(link:match("item:(%d+)"))
  end
  if not id then return end
  local item = NokiMarketActivity(id)
  local value = item and item.sales
  tooltip:AddLine("Noki Market: " .. (type(value) == "number" and (tostring(value) .. " est. sales/day") or "daily activity unavailable"), 0.4, 0.9, 0.75)
  if type(value) == "number" then tooltip:AddLine(NokiMarketActivityLabel(item) .. " | Prices from AHledger (ahledger.com)", 0.7, 0.7, 0.7) end
  tooltip:Show()
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, addActivity)
elseif GameTooltip and GameTooltip.HookScript then
  GameTooltip:HookScript("OnTooltipSetItem", addActivity)
end

-- Rebuild the hovered tooltip when Shift changes so the line appears immediately.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("MODIFIER_STATE_CHANGED")
watcher:SetScript("OnEvent", function(_, _, key)
  if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
  local tooltip = GameTooltip
  if not tooltip or not tooltip:IsShown() then return end
  if tooltip.RefreshData then
    tooltip:RefreshData()
  else
    local owner = tooltip:GetOwner()
    local onEnter = owner and owner:GetScript("OnEnter")
    if onEnter then onEnter(owner) end
  end
end)
