-- Colors available through Blizzard's accessible party-member nameplates.
local options = {
  {label = "Default"},
  {label = "White", 1, 1, 1},
  {label = "Yellow", 1, 0.88, 0.12},
  {label = "Green", 0.2, 1, 0.35},
  {label = "Cyan", 0.2, 0.9, 1},
  {label = "Blue", 0.4, 0.6, 1},
  {label = "Purple", 0.78, 0.5, 1},
  {label = "Pink", 1, 0.48, 0.76},
  {label = "Orange", 1, 0.6, 0.2},
}
local tracked = {}
local function restore(text)
  local old = tracked[text]
  if old then
    pcall(text.SetTextColor, text, old[1], old[2], old[3], old[4])
    tracked[text] = nil
  end
end
local function updateNames()
  if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
  local index = ForeverRangeAccessDB and tonumber(ForeverRangeAccessDB.partyNameColor) or 1
  local color = options[index] or options[1]
  local current = {}
  local ok, plates = pcall(C_NamePlate.GetNamePlates)
  if not ok or type(plates) ~= "table" then return end
  for _, plate in ipairs(plates) do
    pcall(function()
      if plate.IsForbidden and plate:IsForbidden() then return end
      local unitFrame = plate.UnitFrame
      local text = unitFrame and unitFrame.name
      local unit = unitFrame and (unitFrame.unit or unitFrame.namePlateUnitToken)
      if not text or not unit then return end
      local isParty = UnitInParty(unit)
      if issecretvalue and issecretvalue(isParty) then return end
      if color[1] and isParty then
        current[text] = true
        if not tracked[text] then tracked[text] = {text:GetTextColor()} end
        text:SetTextColor(color[1], color[2], color[3])
      end
    end)
  end
  for text in pairs(tracked) do if not current[text] then restore(text) end end
end

local panel = CreateFrame("Frame", "NokiForeverPartyColors", UIParent, "BackdropTemplate")
panel:SetSize(290, 150)
panel:SetPoint("CENTER")
panel:SetFrameStrata("DIALOG")
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
panel:SetClampedToScreen(true)
panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=2})
panel:SetBackdropColor(0.05, 0.05, 0.05, 0.98)
panel:SetBackdropBorderColor(0.9, 0.75, 0.2, 1)
panel:Hide()
local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -15)
title:SetText("PARTY NAME COLOR")
local description = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
description:SetPoint("TOP", title, "BOTTOM", 0, -8)
description:SetText("Names above party members")
local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -2, -2)
local dropdown = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
dropdown:SetSize(190, 28)
dropdown:SetPoint("TOP", description, "BOTTOM", 0, -12)
local preview = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
preview:SetPoint("TOP", dropdown, "BOTTOM", 0, -12)
preview:SetText("Preview: Party Member")
local list = CreateFrame("Frame", nil, panel, "BackdropTemplate")
list:SetSize(190, #options * 25 + 6)
list:SetPoint("TOP", dropdown, "BOTTOM", 0, -1)
list:SetFrameStrata("DIALOG")
list:SetFrameLevel(panel:GetFrameLevel() + 20)
list:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1})
list:SetBackdropColor(0.08, 0.08, 0.08, 1)
list:Hide()
local function refresh()
  local index = ForeverRangeAccessDB and tonumber(ForeverRangeAccessDB.partyNameColor) or 1
  local color = options[index] or options[1]
  dropdown:SetText(color.label .. "  v")
  preview:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1)
end
for i, color in ipairs(options) do
  local row = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
  row:SetSize(182, 24)
  row:SetPoint("TOP", 0, -3 - (i - 1) * 25)
  row:SetText(color.label)
  row:GetFontString():SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1)
  row:SetScript("OnClick", function()
    ForeverRangeAccessDB.partyNameColor = i
    list:Hide()
    refresh()
    updateNames()
  end)
end
dropdown:SetScript("OnClick", function() list:SetShown(not list:IsShown()) end)
panel:SetScript("OnHide", function() list:Hide() end)
local listener = CreateFrame("Frame")
listener:RegisterEvent("PLAYER_ENTERING_WORLD")
listener:RegisterEvent("NAME_PLATE_UNIT_ADDED")
listener:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
listener:RegisterEvent("GROUP_ROSTER_UPDATE")
listener:SetScript("OnEvent", function() if C_Timer and C_Timer.After then C_Timer.After(0, updateNames) else updateNames() end end)
local elapsed = 0
listener:SetScript("OnUpdate", function(_, delta)
  elapsed = elapsed + delta
  if elapsed >= 1 then elapsed = 0; if next(tracked) or (ForeverRangeAccessDB and (ForeverRangeAccessDB.partyNameColor or 1) ~= 1) then updateNames() end end
end)
SLASH_NOKIFOREVER1 = "/noki"
SlashCmdList.NOKIFOREVER = function(message)
  if message:match("^%s*color%s*$") then
    refresh()
    panel:SetShown(not panel:IsShown())
  else
    print("Noki Forever: type /noki color to choose a party name color.")
  end
end

