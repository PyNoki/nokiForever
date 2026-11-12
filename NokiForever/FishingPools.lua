-- Experimental nearby fishing-pool detection. Only minimap detections are shown.
local enabled=false
local scan,found,lastStatus,lastRun=nil,{},"Disabled",0
local mapPins={}
local driver=CreateFrame("Frame")
local function secret(v) return issecretvalue and issecretvalue(v) end
local function safe(v) return not secret(v) end
local function say(message) print("Noki fishing: "..message) end
local function setStatus(message)
  lastStatus=message
  if NokiForeverUpdateFishingStatus then NokiForeverUpdateFishingStatus() end
end
function NokiForeverFishingStatus() return lastStatus end
local function fishTracking()
  if not C_Minimap or not C_Minimap.GetNumTrackingTypes or not C_Minimap.GetTrackingInfo then return nil,nil end
  local spellName=C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(43308)
  local ok,count=pcall(C_Minimap.GetNumTrackingTypes)
  if not ok or not safe(count) or type(count)~="number" then return nil,nil end
  for i=1,count do
    local good,info=pcall(C_Minimap.GetTrackingInfo,i)
    if good and safe(info) and type(info)=="table" and safe(info.spellID) and safe(info.name) and safe(info.active) then
      if info.spellID==43308 or (spellName and info.name==spellName) or info.name=="Find Fish" then return info.active and true or false,i end
    end
  end
  return false,nil
end
local function ensureFishTracking()
  local active,index=fishTracking()
  if active then return true end
  if active==nil then setStatus("Find Fish status unavailable.");return false end
  if not index then setStatus("Find Fish unavailable or not learned.");return false end
  if not C_Minimap.SetTracking then setStatus("Cannot enable Find Fish automatically.");return false end
  if InCombatLockdown and InCombatLockdown() then setStatus("Find Fish resumes after combat.");return false end
  local ok=pcall(C_Minimap.SetTracking,index,true)
  if not ok then setStatus("Could not enable Find Fish.");return false end
  local enabledNow=fishTracking()
  if enabledNow then return true end
  setStatus("Waiting for Find Fish to turn on.");return false
end
local function fishName(text)
  if type(text)~="string" or not safe(text) then return false end
  local s=text:lower()
  return s:find("school",1,true) or s:find("shoal",1,true) or s:find("wreckage",1,true) or s:find("oil spill",1,true) or s:find("floating debris",1,true) or s:find("floating trunks",1,true) or s:find("fish pool",1,true) or s:find("sagefish",1,true) or s:find("blackmouth",1,true) or s:find("firefin",1,true)
end
local function position()
  if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition or not C_Map.GetMapWorldSize then return end
  local ok,id=pcall(C_Map.GetBestMapForUnit,"player");if not ok or not safe(id) or not id then return end
  local good,p=pcall(C_Map.GetPlayerMapPosition,id,"player");if not good or not p or not safe(p) then return end
  local x,y=p:GetXY();local w,h=C_Map.GetMapWorldSize(id)
  if not (safe(x) and safe(y) and safe(w) and safe(h)) or not x or not y or not w or not h or w<=0 or h<=0 then return end
  return id,x,y,w,h
end
local function hidePins() for _,pin in ipairs(mapPins) do pin:Hide() end end
local function updateMap()
  local map=WorldMapFrame
  if not enabled or not map or not map:IsShown() or not map.GetCanvas or not map.GetMapID then hidePins();return end
  local canvas=map:GetCanvas();local current=map:GetMapID()
  if not canvas or not safe(current) or not current then hidePins();return end
  local width,height=canvas:GetWidth(),canvas:GetHeight()
  if not width or not height or width<=0 or height<=0 then hidePins();return end
  local n=0;local t=GetTime()
  for _,v in ipairs(found) do
    if t-v.at<15 then
      local x,y
      if OpenMapAPI and OpenMapAPI.IsStitched and OpenMapAPI.IsStitched() and OpenMapAPI.WorldFromMap and OpenMapAPI.MapFromWorld then
        local u,w=OpenMapAPI.WorldFromMap(v.map,v.x,v.y)
        if u and w then x,y=OpenMapAPI.MapFromWorld(current,u,w) end
      elseif current==v.map then x,y=v.x,v.y end
      if x and y and safe(x) and safe(y) then
        n=n+1
        local pin=mapPins[n]
        if not pin then
          pin=CreateFrame("Frame",nil,canvas);pin:SetSize(20,20);pin:EnableMouse(true)
          local icon=pin:CreateTexture(nil,"OVERLAY");icon:SetAllPoints();icon:SetTexture("Interface\\Icons\\Trade_Fishing")
          pin:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText(self.label or "Fishing pool");GameTooltip:AddLine("Detected on minimap recently; position is approximate.",1,1,1,true);GameTooltip:Show() end)
          pin:SetScript("OnLeave",function() GameTooltip:Hide() end)
          mapPins[n]=pin
        end
        pin:ClearAllPoints();pin:SetPoint("CENTER",canvas,"TOPLEFT",x*width,-y*height)
        if OpenMapAPI and OpenMapAPI.ArtTopLevel then local level=OpenMapAPI.ArtTopLevel();if type(level)=="number" then pin:SetFrameLevel(level+10) end end
        pin.label=v.name;pin:Show()
      end
    end
  end
  for i=n+1,#mapPins do mapPins[i]:Hide() end
end
local function finishScan(s)
  local repeats,maxRepeats=0,0
  for _,count in pairs(s.responses) do repeats=repeats+1;if count>maxRepeats then maxRepeats=count end end
  -- A client that ignores probe positions can return the same hovered tooltip for every point.
  if #s.points>0 and maxRepeats>#s.points*.35 then
    found={};setStatus("Minimap probe unavailable on this client.")
  else
    found=s.hits
    setStatus(#found>0 and (#found.." pool(s) detected recently.") or "No pool confirmed; detection may be unavailable.")
  end
  scan=nil;updateMap()
  if s.manual then say(lastStatus) end
end
local function startScan(manual)
  if scan then if manual then say("A scan is already running.") end;return end
  if not enabled then if manual then say("Turn detection on first: /nokifish on") end;return end
  if not Minimap or not Minimap:IsVisible() or not Minimap.UpdateMouseoverAtPoint or not Minimap.SetUsingSoftCursor or not C_TooltipInfo or not C_TooltipInfo.GetMinimapMouseover or not C_Minimap or not C_Minimap.GetViewRadius then
    setStatus("Minimap detection unavailable.");if manual then say(lastStatus) end;return
  end
  if InCombatLockdown and InCombatLockdown() then if manual then say("Try outside combat.") end;return end
  if not ensureFishTracking() then found={};updateMap();if manual then say(lastStatus) end;return end
  local map,x,y,w,h=position();local left,bottom=Minimap:GetLeft(),Minimap:GetBottom();local width,height=Minimap:GetWidth(),Minimap:GetHeight();local radius=C_Minimap.GetViewRadius()
  if not map or not left or not bottom or not width or not height or not safe(radius) or not radius or radius<=0 then setStatus("Map position unavailable.");if manual then say(lastStatus) end;return end
  local rotate=(C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("rotateMinimap")=="1") or false
  local facing=rotate and GetPlayerFacing and GetPlayerFacing() or 0
  if not safe(facing) or not facing then if manual then say("Minimap direction unavailable.") end;return end
  local points={};local step=7;local halfW,halfH=width/2,height/2
  for yy=step/2,height,step do for xx=step/2,width,step do
    local nx,ny=(xx-halfW)/halfW,(yy-halfH)/halfH
    if nx*nx+ny*ny<=.94 then points[#points+1]={x=xx,y=yy} end
  end end
  scan={points=points,next=1,hits={},responses={},map=map,x=x,y=y,w=w,h=h,left=left,bottom=bottom,width=width,height=height,radius=radius,facing=facing,rotate=rotate,manual=manual}
  lastRun=GetTime();setStatus("Scanning nearby pools...")
end
local function processScan()
  local s=scan;if not s then return end
  if not enabled or (InCombatLockdown and InCombatLockdown()) or not Minimap:IsVisible() then scan=nil;return end
  local map,x,y=position()
  if map~=s.map or not x or math.abs(x-s.x)>.00005 or math.abs(y-s.y)>.00005 then scan=nil;setStatus("Waiting until you stop moving.");return end
  if s.rotate and GetPlayerFacing then local f=GetPlayerFacing();if not safe(f) or not f or math.abs((f-s.facing+math.pi)%(2*math.pi)-math.pi)>.02 then scan=nil;setStatus("Waiting until you stop turning.");return end end
  local scale=Minimap:GetEffectiveScale()
  local ok=pcall(function()
    Minimap:SetUsingSoftCursor(true)
    for i=s.next,math.min(s.next+11,#s.points) do
      local p=s.points[i];Minimap:UpdateMouseoverAtPoint((s.left+p.x)*scale,(s.bottom+p.y)*scale)
      local data=C_TooltipInfo.GetMinimapMouseover()
      if data and safe(data) and type(data.lines)=="table" and safe(data.lines) then
        for _,line in ipairs(data.lines) do
          local text=safe(line) and type(line)=="table" and line.leftText or nil
          if fishName(text) then
            s.responses[text]=(s.responses[text] or 0)+1
            local duplicate=false
            for _,hit in ipairs(s.hits) do if hit.name==text and (hit.px-p.x)^2+(hit.py-p.y)^2<144 then duplicate=true;break end end
            if not duplicate then
              local dx=(p.x-s.width/2)/(s.width/2);local dy=(p.y-s.height/2)/(s.height/2)
              local distance=math.sqrt(dx*dx+dy*dy)*s.radius
              local bearing=math.atan2(dx,dy)-(s.rotate and s.facing or 0)
              s.hits[#s.hits+1]={name=text,map=s.map,x=s.x+distance*math.sin(bearing)/s.w,y=s.y-distance*math.cos(bearing)/s.h,px=p.x,py=p.y,at=GetTime()}
            end
          end
        end
      end
    end
  end)
  pcall(Minimap.SetUsingSoftCursor,Minimap,false)
  if not ok then scan=nil;found={};setStatus("Minimap probe unavailable on this client.");updateMap();if s.manual then say(lastStatus) end;return end
  s.next=s.next+12
  if s.next>#s.points then finishScan(s) end
end
function NokiForeverSetFishingDetection(on)
  enabled=on and true or false
  ForeverRangeAccessDB=ForeverRangeAccessDB or {};ForeverRangeAccessDB.fishDetection=enabled
  if enabled then
    setStatus("Starting automatic scan...")
    startScan(false)
  else
    scan=nil;found={};hidePins();setStatus("Disabled")
  end
end
SLASH_NOKIFISH1="/nokifish"
SlashCmdList.NOKIFISH=function(message)
  local cmd=(message or ""):lower():match("^%s*(%S*)")
  if cmd=="on" then NokiForeverSetFishingDetection(true)
  elseif cmd=="off" then NokiForeverSetFishingDetection(false)
  elseif cmd=="scan" then startScan(true)
  else say(lastStatus) end
end
local elapsed=0
driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent",function() enabled=ForeverRangeAccessDB and ForeverRangeAccessDB.fishDetection==true or false;if enabled then setStatus("Starting automatic scan...");lastRun=-10 end end)
driver:SetScript("OnUpdate",function(_,dt)
  if scan then processScan() end
  elapsed=elapsed+dt;if elapsed<.5 then return end;elapsed=0
  if enabled and not scan and GetTime()-lastRun>=10 then lastRun=GetTime();startScan(false) end
  updateMap()
end)
