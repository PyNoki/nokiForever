-- Estimated five-second rule. Spell cost and casting events may be restricted or
-- may not reflect temporary free-cast effects, so this is never server proof.
local timer = CreateFrame("Frame", "NokiForeverManaRegen", UIParent, "BackdropTemplate")
timer:SetSize(142, 38)
timer:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
timer:SetMovable(true)
timer:SetClampedToScreen(true)
timer:EnableMouse(true)
timer:RegisterForDrag("LeftButton")
timer:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1})
timer:SetBackdropColor(0.035, 0.05, 0.075, 0.92)
timer:SetBackdropBorderColor(0.3, 0.42, 0.51, 1)
local icon = timer:CreateTexture(nil, "ARTWORK")
icon:SetSize(23, 23)
icon:SetPoint("LEFT", 7, 0)
icon:SetTexture("Interface\\Icons\\INV_Elemental_Primal_Mana")
local text = timer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
text:SetPoint("TOPLEFT", icon, "TOPRIGHT", 7, -1)
text:SetText("REGEN ?")
local background = timer:CreateTexture(nil, "BACKGROUND")
background:SetTexture("Interface\\Buttons\\WHITE8X8")
background:SetVertexColor(0.15, 0.2, 0.25, 1)
background:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 7, 2)
background:SetSize(92, 4)
local progress = timer:CreateTexture(nil, "ARTWORK")
progress:SetTexture("Interface\\Buttons\\WHITE8X8")
progress:SetPoint("LEFT", background, "LEFT")
progress:SetHeight(4)
local ends, known, justCompleted = nil, false, false
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
  GameTooltip:AddLine("Based on mana-cost spell casts; free casts and client restrictions may affect accuracy.", 1, 1, 1, true)
  GameTooltip:AddLine("Drag to move. Change visibility in /noki.", 1, 1, 1, true)
  GameTooltip:Show()
end)
timer:SetScript("OnLeave", GameTooltip_Hide)
timer:SetScript("OnUpdate", function(self)
  if not known then
    text:SetText("REGEN ?")
    text:SetTextColor(0.7, 0.7, 0.7)
    progress:SetWidth(0.1)
  elseif ends and GetTime() < ends then
    local left = ends - GetTime()
    text:SetText(string.format("WAIT  %.1fs", left))
    text:SetTextColor(0.9, 0.76, 0.5)
    progress:SetVertexColor(0.83, 0.65, 0.3, 1)
    progress:SetWidth(math.max(0.1, 92 * (1 - left / 5)))
    icon:SetAlpha(0.45)
    justCompleted = true
  else
    text:SetText("REGEN ~")
    text:SetTextColor(0.4, 0.8, 1)
    progress:SetVertexColor(0.28, 0.7, 1, 1)
    progress:SetWidth(92)
    icon:SetAlpha(InCombatLockdown() and 1 or 0.6)
    if justCompleted then
      justCompleted = false
      self:SetBackdropBorderColor(0.4, 0.8, 1, 1)
      if C_Timer and C_Timer.After then
        C_Timer.After(1, function()
          if not ends or GetTime() >= ends then self:SetBackdropBorderColor(0.3, 0.42, 0.51, 1) end
        end)
      end
    end
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

