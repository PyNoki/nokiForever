-- Estimated five-second rule. Only observed mana loss near a successful cast
-- starts the timer; inaccessible power data produces an unknown state.
local timer = CreateFrame("Frame", "NokiForeverManaRegen", UIParent, "BackdropTemplate")
timer:SetSize(36, 36)
timer:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
timer:SetMovable(true)
timer:SetClampedToScreen(true)
timer:EnableMouse(true)
timer:RegisterForDrag("LeftButton")
-- Horizontal strips form a transparent, softly shaded droplet with no square icon.
local strips = {}
for i = 1, 26 do
  local y = (i - 0.5) / 26
  local halfWidth
  if y < 0.45 then halfWidth = 12 * math.sqrt(math.max(0, 1 - ((y - 0.45) / 0.45) ^ 2))
  else halfWidth = 12 * ((1 - y) / 0.55) ^ 0.72 end
  local strip = timer:CreateTexture(nil, "ARTWORK")
  strip:SetTexture("Interface\\Buttons\\WHITE8X8")
  strip:SetPoint("BOTTOM", timer, "BOTTOM", 0, 4 + i)
  strip:SetSize(math.max(0.5, 2 * halfWidth), 1.2)
  strips[i] = strip
end
local particles = {}
for _, point in ipairs({{-15, 5, 2}, {15, -5, 2}, {-11, -13, 1.5}, {13, 12, 1.5}}) do
  local dot = timer:CreateTexture(nil, "OVERLAY")
  dot:SetTexture("Interface\\Buttons\\WHITE8X8")
  dot:SetPoint("CENTER", timer, "CENTER", point[1], point[2])
  dot:SetSize(point[3], point[3])
  dot:SetVertexColor(0.48, 0.85, 1, 1)
  particles[#particles + 1] = dot
end
local glow = timer:CreateTexture(nil, "OVERLAY")
glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
glow:SetBlendMode("ADD")
glow:SetPoint("CENTER")
glow:SetSize(62, 62)
glow:SetVertexColor(0.25, 0.7, 1, 0.85)
glow:Hide()
local ends, known = nil, false
local function secret(value) return issecretvalue and issecretvalue(value) end
local previousMana, lastLoss, lastCast
local function observeMana()
  local ok, value = pcall(UnitPower, "player", 0)
  if not ok or secret(value) or type(value) ~= "number" then
    previousMana, lastLoss, lastCast, known = nil, nil, nil, false
    return
  end
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
  GameTooltip:AddLine(known and "Status: estimated from observed mana use." or "Status: unknown until mana use can be observed.", 1, 1, 1, true)
  GameTooltip:AddLine("Based on observed mana loss near a successful cast. Free casts do not restart it. Client restrictions can make it unknown.", 1, 1, 1, true)
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
    glow:Hide()
  elseif ends and GetTime() < ends then
    local left = ends - GetTime()
    fraction = math.max(0, math.min(1, 1 - left / 5))
    glow:Hide()
  else
    fraction, isReady = 1, true
    glow:SetAlpha(InCombatLockdown() and 0.85 or 0.5)
    glow:Show()
  end
  for i, strip in ipairs(strips) do
    local filled = known and i / #strips <= fraction
    if filled then strip:SetVertexColor(0.23 + 0.16 * i / #strips, 0.64 + 0.22 * i / #strips, 1, 0.9)
    else strip:SetVertexColor(0.25, 0.49, 0.61, known and 0.28 or 0.18) end
  end
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
events:SetScript("OnEvent", function(_, event, unit, powerType)
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
    local now = GetTime()
    lastCast = now
    observeMana()
    if lastLoss and now - lastLoss <= 1 then
      ends, known = lastLoss + 5, true
      lastLoss, lastCast = nil, nil
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.15, observeMana) end
  end
end)

