-- Estimated five-second rule. Spell cost and casting events may be restricted or
-- may not reflect temporary free-cast effects, so this is never server proof.
local timer = CreateFrame("Frame", "NokiForeverManaRegen", UIParent, "BackdropTemplate")
timer:SetSize(36, 36)
timer:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
timer:SetMovable(true)
timer:SetClampedToScreen(true)
timer:EnableMouse(true)
timer:RegisterForDrag("LeftButton")
timer:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1})
timer:SetBackdropColor(0.035, 0.05, 0.075, 0.8)
timer:SetBackdropBorderColor(0.3, 0.42, 0.51, 1)
local iconBase = timer:CreateTexture(nil, "BACKGROUND")
iconBase:SetPoint("TOPLEFT", 3, -3)
iconBase:SetPoint("BOTTOMRIGHT", -3, 3)
iconBase:SetTexture("Interface\\Icons\\INV_Elemental_Primal_Mana")
iconBase:SetDesaturated(true)
iconBase:SetAlpha(0.22)
local iconFill = timer:CreateTexture(nil, "ARTWORK")
iconFill:SetPoint("BOTTOMLEFT", 3, 3)
iconFill:SetWidth(30)
iconFill:SetTexture("Interface\\Icons\\INV_Elemental_Primal_Mana")
local glow = timer:CreateTexture(nil, "OVERLAY")
glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
glow:SetBlendMode("ADD")
glow:SetPoint("CENTER")
glow:SetSize(62, 62)
glow:SetVertexColor(0.25, 0.7, 1, 0.85)
glow:Hide()
local unknown = timer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
unknown:SetPoint("CENTER")
unknown:SetText("?")
local ends, known = nil, false
local function secret(value) return issecretvalue and issecretvalue(value) end
local function updateVisibility()
  if not ForeverRangeAccessDB then timer:Hide(); return end
  local ok, maximum = pcall(UnitPowerMax, "player", 0)
  local hasMana = ok and not secret(maximum) and type(maximum) == "number" and maximum > 0
  timer:SetShown(not ForeverRangeAccessDB.manaRegenHidden and hasMana)
end
NokiForeverUpdateManaVisibility = updateVisibility
timer:SetScript("OnDragStart", function(self) self:StartMoving() end)
timer:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local x, y = self:GetCenter()
  local px, py = UIParent:GetCenter()
  if x and y and px and py and ForeverRangeAccessDB then
    ForeverRangeAccessDB.manaRegenX, ForeverRangeAccessDB.manaRegenY = x - px, y - py
  end
end)
timer:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:AddLine("Mana regeneration estimate")
  GameTooltip:AddLine("The icon fills over five seconds and glows when regeneration is estimated to resume. ? means unknown.", 1, 1, 1, true)
  GameTooltip:AddLine("Based on mana-cost spell casts; free casts and client restrictions may affect accuracy.", 1, 1, 1, true)
  GameTooltip:AddLine("Drag to move. Change visibility in /noki.", 1, 1, 1, true)
  GameTooltip:Show()
end)
timer:SetScript("OnLeave", GameTooltip_Hide)
timer:SetScript("OnUpdate", function(self)
  if not known then
    unknown:Show()
    iconFill:Hide()
    glow:Hide()
    self:SetBackdropBorderColor(0.3, 0.42, 0.51, 1)
  elseif ends and GetTime() < ends then
    local left = ends - GetTime()
    local fraction = math.max(0.001, math.min(1, 1 - left / 5))
    unknown:Hide()
    glow:Hide()
    iconFill:SetHeight(30 * fraction)
    iconFill:SetTexCoord(0, 1, 1 - fraction, 1)
    iconFill:SetAlpha(0.35 + 0.65 * fraction)
    iconFill:Show()
    self:SetBackdropBorderColor(0.55, 0.46, 0.3, 1)
  else
    unknown:Hide()
    iconFill:SetHeight(30)
    iconFill:SetTexCoord(0, 1, 0, 1)
    iconFill:SetAlpha(1)
    iconFill:Show()
    glow:SetAlpha(InCombatLockdown() and 0.85 or 0.5)
    glow:Show()
    self:SetBackdropBorderColor(0.4, 0.8, 1, 1)
  end
end)
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UNIT_MAXPOWER")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:SetScript("OnEvent", function(_, event, unit, _, spellID)
  if event == "ADDON_LOADED" and unit == "NokiForever" then
    if ForeverRangeAccessDB and ForeverRangeAccessDB.manaRegenX and ForeverRangeAccessDB.manaRegenY then
      timer:ClearAllPoints()
      timer:SetPoint("CENTER", UIParent, "CENTER", ForeverRangeAccessDB.manaRegenX, ForeverRangeAccessDB.manaRegenY)
    end
    updateVisibility()
  elseif event == "PLAYER_ENTERING_WORLD" or (event == "UNIT_MAXPOWER" and unit == "player") then
    updateVisibility()
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" then
    if not spellID or not C_Spell or not C_Spell.GetSpellPowerCost then known = false; return end
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
    if not ok or secret(costs) or type(costs) ~= "table" then known = false; return end
    for _, cost in ipairs(costs) do
      if secret(cost.type) or secret(cost.cost) then known = false; return end
      if cost.type == 0 and type(cost.cost) == "number" and cost.cost > 0 then
        known, ends = true, GetTime() + 5
        timer:SetBackdropBorderColor(0.55, 0.46, 0.3, 1)
        return
      end
    end
  end
end)

