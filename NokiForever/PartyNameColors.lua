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
panel:SetSize(430, 490)
panel:SetPoint("CENTER")
panel:SetFrameStrata("DIALOG")
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
panel:SetClampedToScreen(true)
panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=2})
panel:SetBackdropColor(0.035, 0.045, 0.065, 0.98)
panel:SetBackdropBorderColor(0.52, 0.42, 0.24, 1)
panel:Hide()
local accent = panel:CreateTexture(nil, "ARTWORK")
accent:SetTexture("Interface\\Buttons\\WHITE8X8")
accent:SetVertexColor(0.82, 0.66, 0.35, 1)
accent:SetPoint("TOPLEFT", 2, -2)
accent:SetPoint("TOPRIGHT", -2, -2)
accent:SetHeight(3)
local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 24, -23)
title:SetText("NOKI  |  FOREVER")
title:SetTextColor(0.95, 0.83, 0.59)
local description = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -7)
description:SetText("YOUR TOOLKIT, YOUR WAY")
description:SetTextColor(0.58, 0.65, 0.7)
local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -8, -10)

local function label(text, x, y, font)
  local item = panel:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
  item:SetPoint("TOPLEFT", x, y)
  item:SetText(text)
  return item
end
local function divider(y)
  local line = panel:CreateTexture(nil, "ARTWORK")
  line:SetTexture("Interface\\Buttons\\WHITE8X8")
  line:SetVertexColor(0.32, 0.36, 0.39, 0.6)
  line:SetPoint("TOPLEFT", 24, y)
  line:SetPoint("TOPRIGHT", -24, y)
  line:SetHeight(1)
end
divider(-68)
label("SPELL TRACKING", 25, -86)
local spellLabel = label("Choose a spell to track its range.", 25, -105, "GameFontHighlightSmall")
spellLabel:SetTextColor(0.7, 0.73, 0.75)
local spellButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
spellButton:SetSize(120, 27)
spellButton:SetPoint("TOPRIGHT", -24, -86)
spellButton:SetText("Choose spell")
spellButton:SetScript("OnClick", function() if SlashCmdList.FOREVERRANGEACCESS then SlashCmdList.FOREVERRANGEACCESS("") end end)

divider(-135)
label("BAG SIZE", 25, -153)
local bagHint = label("Scale from 0.5 to 2.0", 25, -174, "GameFontHighlightSmall")
bagHint:SetTextColor(0.7, 0.73, 0.75)
local bagInput = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
bagInput:SetSize(65, 26)
bagInput:SetPoint("TOPRIGHT", -112, -155)
bagInput:SetAutoFocus(false)
bagInput:SetMaxLetters(4)
local bagButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
bagButton:SetSize(75, 27)
bagButton:SetPoint("TOPRIGHT", -24, -153)
bagButton:SetText("Apply")
local function applyBag()
  local scale = tonumber(bagInput:GetText())
  if not scale or scale < 0.5 or scale > 2 then
    print("Noki Forever: bag scale must be between 0.5 and 2.")
    return
  end
  if SlashCmdList.FOREVERRANGEACCESS then SlashCmdList.FOREVERRANGEACCESS("bag " .. tostring(scale)) end
  bagInput:ClearFocus()
end
bagButton:SetScript("OnClick", applyBag)
bagInput:SetScript("OnEnterPressed", applyBag)
bagInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

divider(-208)
label("PARTY NAME COLOR", 25, -226)
local colorHint = label("Names above party members", 25, -246, "GameFontHighlightSmall")
colorHint:SetTextColor(0.7, 0.73, 0.75)
local dropdown = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
dropdown:SetSize(130, 28)
dropdown:SetPoint("TOPRIGHT", -24, -225)
local preview = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
preview:SetPoint("TOPLEFT", 25, -280)
preview:SetText("Preview: Party Member")
divider(-308)
label("MANA REGEN TIMER", 25, -325)
local manaHint = label("Drag the indicator to move it", 25, -345, "GameFontHighlightSmall")
manaHint:SetTextColor(0.7, 0.73, 0.75)
local manaButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
manaButton:SetSize(110, 27)
manaButton:SetPoint("TOPRIGHT", -24, -325)
divider(-365)
label("FISHING POOL DETECTION", 25, -383)
local fishHint = label("Experimental: needs Find Fish", 25, -403, "GameFontHighlightSmall")
fishHint:SetTextColor(0.7, 0.73, 0.75)
local fishButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
fishButton:SetSize(110, 27)
fishButton:SetPoint("TOPRIGHT", -24, -382)
local footer = label("Drag this window to move it", 25, -466, "GameFontHighlightSmall")
footer:SetTextColor(0.48, 0.55, 0.59)
local list = CreateFrame("Frame", nil, panel, "BackdropTemplate")
list:SetSize(130, #options * 25 + 6)
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
  bagInput:SetText(tostring(ForeverRangeAccessDB and ForeverRangeAccessDB.bagScale or 1))
  manaButton:SetText(ForeverRangeAccessDB and ForeverRangeAccessDB.manaRegenHidden and "Show" or "Hide")
  fishButton:SetText(ForeverRangeAccessDB and ForeverRangeAccessDB.fishDetection and "Disable" or "Enable")
end
fishButton:SetScript("OnClick", function()
  if SlashCmdList.NOKIFISH then SlashCmdList.NOKIFISH(ForeverRangeAccessDB and ForeverRangeAccessDB.fishDetection and "off" or "on") end
  refresh()
end)
manaButton:SetScript("OnClick", function()
  ForeverRangeAccessDB.manaRegenHidden = not ForeverRangeAccessDB.manaRegenHidden
  if NokiForeverUpdateManaVisibility then NokiForeverUpdateManaVisibility() end
  refresh()
end)
for i, color in ipairs(options) do
  local row = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
  row:SetSize(122, 24)
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
function NokiForeverToggleMenu()
  refresh()
  panel:SetShown(not panel:IsShown())
end
SlashCmdList.NOKIFOREVER = function(message)
  if message:match("^%s*$") or message:match("^%s*color%s*$") then NokiForeverToggleMenu()
  else print("Noki Forever: type /noki to open the settings menu.") end
end

