local ADDON = ...
local events = CreateFrame("Frame")
local spellID
local button = CreateFrame("Frame", "ForeverRangeAccessCast", UIParent, "BackdropTemplate")
button:SetSize(260, 60)
button:SetMovable(true)
button:SetClampedToScreen(true)
button:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
button:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=3})
button:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
button:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

local caption = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
caption:SetPoint("CENTER")
caption:SetText("NO SPELL SELECTED")

local display = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
display:SetSize(260, 56)
display:SetPoint("BOTTOM", button, "TOP", 0, 5)
display:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=3})
display:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
local status = display:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
status:SetPoint("CENTER")
status:SetText("SELECT AN ENEMY")
local plateText, plateOwner, plateMarker
-- Bag scaling is opt-in so the default UI remains untouched until requested.
local bagFramesHooked, scalingBag = {}, false
local function setBagScale(frame)
  local scale = ForeverRangeAccessDB and ForeverRangeAccessDB.bagScale
  if not scale or InCombatLockdown() or scalingBag then return end
  scalingBag = true
  pcall(frame.SetScale, frame, scale)
  scalingBag = false
end
local function applyBagScale()
  if not ForeverRangeAccessDB or not ForeverRangeAccessDB.bagScale then return end
  if InCombatLockdown() then return end
  local function apply(frame)
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
    if not bagFramesHooked[frame] then
      frame:HookScript("OnShow", function()
        setBagScale(frame)
        if C_Timer and C_Timer.After then C_Timer.After(0, function() setBagScale(frame) end) end
      end)
      -- Blizzard may recalculate bag scale after showing or laying out the bags.
      pcall(hooksecurefunc, frame, "SetScale", function(self, scale)
        if not scalingBag and ForeverRangeAccessDB and ForeverRangeAccessDB.bagScale
          and scale ~= ForeverRangeAccessDB.bagScale then setBagScale(self) end
      end)
      bagFramesHooked[frame] = true
    end
    setBagScale(frame)
  end
  apply(_G.ContainerFrameCombinedBags)
  for i = 1, (NUM_CONTAINER_FRAMES or 13) do apply(_G["ContainerFrame" .. i]) end
end
local function ask(fn, ...)
  if not fn then return nil end
  local ok, value = pcall(fn, ...)
  if not ok or (issecretvalue and issecretvalue(value)) then return nil end
  if value == true or value == 1 then return true end
  if value == false or value == 0 then return false end
  return nil
end
local function setSpell(id)
  if InCombatLockdown() then print("Noki Forever: configure spells outside combat."); return end
  local info = C_Spell and C_Spell.GetSpellInfo(id)
  if not info or not info.name or (C_SpellBook and C_SpellBook.IsSpellKnown and not C_SpellBook.IsSpellKnown(id)) then
    print("Noki Forever: spell ID not found or not learned."); return
  end
  spellID = id
  ForeverRangeAccessDB.spellID = id
  caption:SetText("SPELL: " .. info.name)
  print("Noki Forever: tracking " .. info.name .. " on your target.")
end

-- The handle moves the protected cast button and its attached range panel together.
local handle = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
handle:SetSize(260, 28)
handle:SetPoint("BOTTOM", display, "TOP", 0, 3)
handle:SetText("DRAG TO MOVE  |  RIGHT-CLICK: SPELLS")
handle:RegisterForClicks("LeftButtonUp", "RightButtonUp")
handle:RegisterForDrag("LeftButton")
handle:SetScript("OnDragStart", function()
  if InCombatLockdown() then print("Noki Forever: move the panel outside combat."); return end
  button:StartMoving()
  handle.moving = true
end)
handle:SetScript("OnDragStop", function()
  if not handle.moving then return end
  handle.moving = nil
  button:StopMovingOrSizing()
  if InCombatLockdown() then return end
  local x, y = button:GetCenter()
  local px, py = UIParent:GetCenter()
  if x and px then
    ForeverRangeAccessDB.x, ForeverRangeAccessDB.y = x - px, y - py
    button:ClearAllPoints()
    button:SetPoint("CENTER", UIParent, "CENTER", x - px, y - py)
  end
end)

local picker = CreateFrame("Frame", "NokiForeverSpellPicker", UIParent, "BackdropTemplate")
picker:SetSize(320, 390)
picker:SetPoint("CENTER")
picker:SetFrameStrata("DIALOG")
picker:SetMovable(true)
picker:EnableMouse(true)
picker:RegisterForDrag("LeftButton")
picker:SetScript("OnDragStart", picker.StartMoving)
picker:SetScript("OnDragStop", picker.StopMovingOrSizing)
picker:SetClampedToScreen(true)
picker:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=3})
picker:SetBackdropColor(0.05, 0.05, 0.05, 0.98)
picker:SetBackdropBorderColor(0.9, 0.75, 0.2, 1)
picker:Hide()
local heading = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
heading:SetPoint("TOP", 0, -15)
heading:SetText("CHOOSE A SPELL")
local hint = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hint:SetPoint("TOP", heading, "BOTTOM", 0, -7)
hint:SetText("Select a learned spell outside combat")
local close = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -2, -2)
local rows, spells, page = {}, {}, 1
local pageLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
pageLabel:SetPoint("BOTTOM", 0, 15)
local renderPicker
for i = 1, 8 do
  local row = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
  row:SetSize(280, 30)
  row:SetPoint("TOP", 0, -57 - (i - 1) * 34)
  row:SetScript("OnClick", function(self)
    if InCombatLockdown() then print("Noki Forever: choose a spell outside combat."); return end
    if self.spellID then setSpell(self.spellID); picker:Hide() end
  end)
  rows[i] = row
end
local previous = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
previous:SetSize(65, 24); previous:SetPoint("BOTTOMLEFT", 20, 9); previous:SetText("Previous")
previous:SetScript("OnClick", function() page = math.max(1, page - 1); renderPicker() end)
local nextPage = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
nextPage:SetSize(65, 24); nextPage:SetPoint("BOTTOMRIGHT", -20, 9); nextPage:SetText("Next")
nextPage:SetScript("OnClick", function() page = math.min(math.max(1, math.ceil(#spells / 8)), page + 1); renderPicker() end)
renderPicker = function()
  for i, row in ipairs(rows) do
    local spell = spells[(page - 1) * 8 + i]
    row.spellID = spell and spell.id
    if spell then row:SetText(spell.name); row:Show() else row:Hide() end
  end
  pageLabel:SetText(#spells == 0 and "No spells found" or (page .. " / " .. math.ceil(#spells / 8)))
end
local function openPicker()
  if InCombatLockdown() then print("Noki Forever: choose a spell outside combat."); return end
  spells, page = {}, 1
  local seen = {}
  if C_SpellBook and Enum and Enum.SpellBookSpellBank then
    local bank = Enum.SpellBookSpellBank.Player
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
      local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
      if info then
        for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
          local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
          local id = item and item.spellID
          local spell = id and C_Spell.GetSpellInfo(id)
          local passive = C_SpellBook.IsSpellBookItemPassive and C_SpellBook.IsSpellBookItemPassive(slot, bank)
          if spell and spell.name and not passive and not seen[id] then
            seen[id] = true
            spells[#spells + 1] = {id = id, name = spell.name}
          end
        end
      end
    end
  end
  table.sort(spells, function(a,b) return a.name < b.name end)
  renderPicker()
  picker:Show()
end
handle:SetScript("OnClick", function(_, mouseButton)
  if mouseButton == "RightButton" then openPicker() end
end)
local choose = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
choose:SetSize(260, 28)
choose:SetPoint("TOP", button, "BOTTOM", 0, -3)
choose:SetText("CHOOSE SPELL")
choose:SetScript("OnClick", openPicker)

-- Drag around the minimap; click to hide or restore the toolkit.
local mini = CreateFrame("Button", "NokiForeverMinimapButton", Minimap)
mini:SetSize(32, 32)
mini:SetFrameStrata("MEDIUM")
mini:SetMovable(true)
mini:RegisterForDrag("LeftButton")
mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
local miniBg = mini:CreateTexture(nil, "BACKGROUND")
miniBg:SetAllPoints()
miniBg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
miniBg:SetVertexColor(0.1, 0.1, 0.1)
local miniText = mini:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
miniText:SetPoint("CENTER"); miniText:SetText("N")
local miniBorder = mini:CreateTexture(nil, "OVERLAY")
miniBorder:SetSize(54, 54); miniBorder:SetPoint("TOPLEFT", -1, 1)
miniBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
local function positionMini(angle)
  local radians = math.rad(angle or 225)
  local radius = (Minimap:GetWidth() or 140) / 2 + 5
  mini:ClearAllPoints()
  mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * radius, math.sin(radians) * radius)
end
local function setToolkitVisible(visible)
  button:SetShown(visible); display:SetShown(visible); handle:SetShown(visible); choose:SetShown(visible)
  ForeverRangeAccessDB.hidden = not visible
end
mini:SetScript("OnDragStart", function(self)
  self.dragging = true
  self:SetScript("OnUpdate", function()
    local x, y = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = Minimap:GetCenter()
    if not cx or not cy then return end
    local angle = math.deg(math.atan2(y / scale - cy, x / scale - cx))
    ForeverRangeAccessDB.minimapAngle = angle
    positionMini(angle)
  end)
end)
mini:SetScript("OnDragStop", function(self) self.dragging = false; self:SetScript("OnUpdate", nil) end)
mini:SetScript("OnClick", function(self, mouseButton)
  if self.dragging then return end
  if mouseButton == "RightButton" then openPicker()
  else setToolkitVisible(ForeverRangeAccessDB.hidden) end
end)
mini:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("Noki Forever")
  GameTooltip:AddLine("Click: show or hide toolkit", 1, 1, 1)
  GameTooltip:AddLine("Right-click: choose spell | Drag: move", 1, 1, 1)
  GameTooltip:Show()
end)
mini:SetScript("OnLeave", GameTooltip_Hide)
local function updatePlate(text, rangeState)
  local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit("target")
  local owner = plate and not plate:IsForbidden() and plate.UnitFrame
  if plateOwner ~= owner then
    if plateText then plateText:Hide() end
    if plateMarker then plateMarker:Hide() end
    plateText, plateMarker, plateOwner = nil, nil, owner
  end
  if owner and not plateText and owner.nokiRangeText then
    plateText, plateMarker = owner.nokiRangeText, owner.nokiRangeMarker
  end
  if owner and not plateText and not InCombatLockdown() then
    local ok, result, marker = pcall(function()
      local label = owner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
      local anchor = owner.LevelFrame or owner
      label:SetPoint("LEFT", anchor, "RIGHT", 5, 0)
      local marker = owner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
      local health = owner.healthBar or (owner.HealthBarsContainer and owner.HealthBarsContainer.healthBar)
      marker:SetPoint("CENTER", health or owner, "CENTER", 0, 0)
      marker:SetText("[+]")
      return label, marker
    end)
    if ok then
      plateText, plateMarker = result, marker
      owner.nokiRangeText, owner.nokiRangeMarker = result, marker
    end
  end
  if plateText then plateText:SetText(text); plateText:Show() end
  if plateMarker then
    if rangeState == true then
      plateMarker:SetText("[+]"); plateMarker:SetTextColor(0.2, 1, 0.25); plateMarker:Show()
    elseif rangeState == false then
      plateMarker:SetText("[X]"); plateMarker:SetTextColor(1, 0.2, 0.2); plateMarker:Show()
    else
      plateMarker:SetText("[?]"); plateMarker:SetTextColor(1, 1, 1); plateMarker:Show()
    end
  end
end
local function update()
  if not UnitExists("target") or not ask(UnitCanAttack, "player", "target") then
    status:SetText("SELECT AN ENEMY")
    display:SetBackdropBorderColor(0.6,0.6,0.6,1)
    updatePlate("")
    if plateMarker then plateMarker:Hide() end
    return
  end
  local near = ask(CheckInteractDistance, "target", 3)
  local mid = ask(CheckInteractDistance, "target", 4)
  local distance = "RANGE UNKNOWN"
  if near == true and mid == false then distance = "RANGE UNKNOWN"
  elseif near == true then distance = "WITHIN ~8 YD"
  elseif mid == true and near == false then distance = "~8–28 YD"
  elseif mid == true then distance = "WITHIN ~28 YD"
  elseif mid == false then distance = "OVER ~28 YD" end
  local inRange
  if spellID and C_Spell then inRange = ask(C_Spell.IsSpellInRange, spellID, "target") end
  local state, r, g, b = "SPELL RANGE UNKNOWN", 0.7, 0.7, 0.7
  if inRange == true then state,r,g,b = "[+] SPELL IN RANGE", 0.2,1,0.3
  elseif inRange == false then state,r,g,b = "[X] SPELL OUT OF RANGE", 1,0.2,0.2 end
  status:SetText(distance .. "\n" .. state)
  display:SetBackdropBorderColor(r,g,b,1)
  updatePlate(distance, inRange)
end

local elapsed = 0
events:SetScript("OnUpdate", function(_, delta)
  elapsed = elapsed + delta
  if elapsed >= 0.25 then elapsed = 0; update() end
end)
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == ADDON then
    ForeverRangeAccessDB = ForeverRangeAccessDB or {}
    if ForeverRangeAccessDB.x and ForeverRangeAccessDB.y then
      button:ClearAllPoints()
      button:SetPoint("CENTER", UIParent, "CENTER", ForeverRangeAccessDB.x, ForeverRangeAccessDB.y)
    end
    positionMini(ForeverRangeAccessDB.minimapAngle)
    setToolkitVisible(not ForeverRangeAccessDB.hidden)
    if ForeverRangeAccessDB.spellID then setSpell(ForeverRangeAccessDB.spellID) end
  end
  if event == "PLAYER_LOGIN" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD"
    or event == "BAG_UPDATE_DELAYED" or event == "ADDON_LOADED" then applyBagScale() end
end)
SLASH_FOREVERRANGEACCESS1 = "/fra"
SlashCmdList.FOREVERRANGEACCESS = function(message)
  local bag = message:match("^%s*bag%s+([%d%.]+)%s*$")
  if bag then
    local scale = tonumber(bag)
    if not scale or scale < 0.5 or scale > 2 then
      print("Noki Forever: bag scale must be between 0.5 and 2.")
    else
      ForeverRangeAccessDB.bagScale = scale
      applyBagScale()
      print("Noki Forever: bag scale set to " .. scale .. (InCombatLockdown() and " (applies after combat)." or "."))
    end
    return
  end
  local id = message:match("^%s*spell%s+(%d+)%s*$")
  if id then setSpell(tonumber(id)) else openPicker() end
end









