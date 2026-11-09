-- Estimated five-second rule. Prefer observed mana loss; if mana is secret,
-- fall back to the reported current spell cost when it is readable.
local timer = CreateFrame("Frame", "NokiForeverManaRegen", UIParent, "BackdropTemplate")
timer:SetSize(36, 36)
timer:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
timer:SetMovable(true)
timer:SetClampedToScreen(true)
timer:EnableMouse(true)
timer:RegisterForDrag("LeftButton")
local iconBase = timer:CreateTexture(nil, "BACKGROUND")
iconBase:SetPoint("TOPLEFT", 3, -3)
iconBase:SetPoint("BOTTOMRIGHT", -3, 3)
iconBase:SetTexture("Interface\\Icons\\INV_Elemental_Primal_Mana")
iconBase:SetDesaturated(true)
iconBase:SetAlpha(0.3)
local iconFill = timer:CreateTexture(nil, "ARTWORK")
iconFill:SetPoint("BOTTOMLEFT", 3, 3)
iconFill:SetWidth(30)
iconFill:SetTexture("Interface\\Icons\\INV_Elemental_Primal_Mana")
local particles = {}
for _, point in ipairs({{-15, 5, 2}, {15, -5, 2}, {-11, -13, 1.5}, {13, 12, 1.5}}) do
  local dot = timer:CreateTexture(nil, "OVERLAY")
  dot:SetTexture("Interface\\Buttons\\WHITE8X8")
  dot:SetPoint("CENTER", timer, "CENTER", point[1], point[2])
  dot:SetSize(point[3], point[3])
  dot:SetVertexColor(0.48, 0.85, 1, 1)
  particles[#particles + 1] = dot
end
local trim = CreateFrame("Frame", nil, timer, "BackdropTemplate")
trim:SetAllPoints(timer)
trim:SetFrameLevel(timer:GetFrameLevel() + 2)
trim:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1})
trim:SetBackdropBorderColor(0.85, 0.67, 0.32, 0.65)
local ends, known = nil, false
local function secret(value) return issecretvalue and issecretvalue(value) end
local previousMana, lastLoss, lastCast, powerReadable
local function observeMana()
  local ok, value = pcall(UnitPower, "player", 0)
  if not ok or secret(value) or type(value) ~= "number" then
    previousMana, lastLoss, powerReadable = nil, nil, false
    return
  end
  powerReadable = true
  local now = GetTime()
  if previousMana and value < previousMana then
    lastLoss = now
    if lastCast and math.abs(now - lastCast) <= 1 then
      ends, known = now + 5, true
      lastLoss, lastCast = nil, nil
    end
  end
  previousMana = value
end
local function reportedManaCost(spellID)
  if secret(spellID) or not spellID or not C_Spell or not C_Spell.GetSpellPowerCost then return nil end
  local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
  if not ok or secret(costs) or type(costs) ~= "table" then return nil end
  for _, cost in ipairs(costs) do
    if secret(cost.type) then return nil end
    if cost.type == 0 then
      if secret(cost.cost) or secret(cost.costPercent) then return nil end
      if type(cost.cost) ~= "number" and type(cost.costPercent) ~= "number" then return nil end
      return (cost.cost or 0) > 0 or (cost.costPercent or 0) > 0
    end
  end
  return false
end
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
  GameTooltip:AddLine("The droplet fills over five seconds and glows when regeneration is estimated to resume.", 1, 1, 1, true)
  GameTooltip:AddLine(known and "Status: estimated timer." or "Status: unknown until a mana cost can be identified.", 1, 1, 1, true)
  GameTooltip:AddLine("Uses observed mana loss or a reported spell cost. Free-cast effects may not always be reported accurately.", 1, 1, 1, true)
  GameTooltip:AddLine("Drag to move. Change visibility in /noki.", 1, 1, 1, true)
  GameTooltip:Show()
end)
timer:SetScript("OnLeave", GameTooltip_Hide)
local drawElapsed = 0
timer:SetScript("OnUpdate", function(self, delta)
  drawElapsed = drawElapsed + delta
  if drawElapsed < 0.04 then return end
  drawElapsed = 0
  local fraction, isReady = 0, false
  if not known then
    trim:SetBackdropBorderColor(0.65, 0.5, 0.25, 0.55)
  elseif ends and GetTime() < ends then
    local left = ends - GetTime()
    fraction = math.max(0, math.min(1, 1 - left / 5))
    trim:SetBackdropBorderColor(0.78, 0.6, 0.28, 0.75)
  else
    fraction, isReady = 1, true
    trim:SetBackdropBorderColor(1, 0.8, 0.4, 1)
  end
  if known then
    local visible = math.max(0.001, fraction)
    iconFill:SetHeight(30 * visible)
    iconFill:SetTexCoord(0, 1, 1 - visible, 1)
    iconFill:SetAlpha(0.35 + 0.65 * fraction)
    iconFill:Show()
  else iconFill:Hide() end
  for i, dot in ipairs(particles) do
    dot:SetAlpha(isReady and (0.55 + 0.35 * math.sin(GetTime() * 2 + i)) or 0.2 + fraction * 0.45)
  end
end)
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UNIT_MAXPOWER")
events:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
events:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:SetScript("OnEvent", function(_, event, unit, powerType, spellID)
  if event == "ADDON_LOADED" and unit == "NokiForever" then
    if ForeverRangeAccessDB and ForeverRangeAccessDB.manaRegenX and ForeverRangeAccessDB.manaRegenY then
      timer:ClearAllPoints()
      timer:SetPoint("CENTER", UIParent, "CENTER", ForeverRangeAccessDB.manaRegenX, ForeverRangeAccessDB.manaRegenY)
    end
    updateVisibility()
    observeMana()
  elseif event == "PLAYER_ENTERING_WORLD" or (event == "UNIT_MAXPOWER" and unit == "player") then
    updateVisibility()
    previousMana, lastLoss, lastCast, known = nil, nil, nil, false
    observeMana()
  elseif (event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE") and unit == "player" then
    if not secret(powerType) and (not powerType or powerType == "MANA") then observeMana() end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" then
    -- Wand Shoot does not spend mana. Some clients do not report its cost,
    -- which must not discard a valid timer or its completed glow.
    if not secret(spellID) and spellID == 5019 then return end
    local now = GetTime()
    lastCast = now
    observeMana()
    if lastLoss and now - lastLoss <= 1 then
      ends, known = lastLoss + 5, true
      lastLoss, lastCast = nil, nil
    end
    if C_Timer and C_Timer.After then
      local cost = reportedManaCost(spellID)
      C_Timer.After(0.15, function()
        observeMana()
        if not powerReadable then
          if cost == true then ends, known = now + 5, true
          elseif cost == nil then known = false end
        end
      end)
    end
  end
end)

