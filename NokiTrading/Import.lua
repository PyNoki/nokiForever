-- Validated market-data import. Pasted text is data, never executable Lua.
local core=NokiUnifiedCore
function core.ImportTable(text)
  if type(text)~="string" or #text==0 then return nil,"Paste an import string first." end
  if #text>2000000 then return nil,"Import is too large." end
  text=text:gsub("\r\n","\n"):gsub("\r","\n"):gsub("^%s+","")
  local header,body=text:match("^([^\n]+)\n(.*)$")
  if not header then return nil,"Missing table header or rows." end
  header=header:gsub("||","|")
  local market,updated,declared=header:match("^AHL1|([%w/%-]+)|(%d+)|(%d+)%s*$")
  updated,declared=tonumber(updated),tonumber(declared)
  if not market or not updated or not declared or declared<1 or declared>100000 then return nil,"Invalid market table header." end
  local expected,marketErr=core.Market()
  if not expected then return nil,marketErr or "Cannot identify your market." end
  if market~=expected then return nil,"Wrong market: expected "..expected..", received "..market.."." end
  local timestamp=(GetServerTime and GetServerTime()) or time()
  if updated<=0 or updated>timestamp+300 then return nil,"Invalid table timestamp." end
  local seen,count={},0
  for line in body:gmatch("[^\n]+") do
    if line:match("%S") then
      local id,median,low,quantity,m7,m30,lo,hi,sold=line:match("^(%d+):(%d*):(%d*):(%d*):(%d*):(%d*):(%d*):(%d*):?(%d*)$")
      id=tonumber(id)
      if not id or id<=0 or id>=2147483648 or seen[id] then return nil,"Invalid or duplicate item row." end
      for _,v in ipairs({median,low,quantity,m7,m30,lo,hi,sold}) do
        if v~="" then local number=tonumber(v);if not number or number~=number or number>1000000000000 then return nil,"Invalid numeric value in table." end end
      end
      if sold~="" and tonumber(sold)>100000000 then return nil,"Invalid sales estimate." end
      seen[id]=true;count=count+1
      if count>declared then return nil,"Row count exceeds the header." end
    end
  end
  if count~=declared then return nil,"Incomplete table: expected "..declared.." rows, received "..count.."." end
  local current=NokiUnifiedAPI.GetTableInfo()
  if current and type(current.updated)=="number" and current.updated>updated then return nil,"Current data is newer; the older import was not applied." end
  NokiUnifiedCoreDB=NokiUnifiedCoreDB or {};NokiUnifiedCoreDB.importedTables=NokiUnifiedCoreDB.importedTables or {}
  NokiUnifiedCoreDB.importedTables[market]={updated=updated,count=count,text=body}
  if NokiUnifiedMarketRefreshFlips then NokiUnifiedMarketRefreshFlips() end
  if NokiUnifiedCraftRefreshFlips then NokiUnifiedCraftRefreshFlips() end
  return {market=market,count=count,updated=updated}
end
local window,box,resultText
local function createImport()
  if window then return end
  window=CreateFrame("Frame","NokiUnifiedImportFrame",UIParent,"BackdropTemplate");window:SetSize(600,400);window:SetPoint("CENTER");window:SetFrameStrata("FULLSCREEN_DIALOG");window:SetClampedToScreen(true);window:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1});window:SetBackdropColor(.055,.065,.07,1);window:SetBackdropBorderColor(.3,.38,.34,1)
  local title=window:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("TOPLEFT",window,"TOPLEFT",16,-14);title:SetText("IMPORT MARKET DATA")
  local instructions=window:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");instructions:SetPoint("TOPLEFT",window,"TOPLEFT",16,-40);instructions:SetWidth(560);instructions:SetJustifyH("LEFT");instructions:SetText("At devvy.xyz/noki-crafting/, choose your market, copy the import string, and paste it below.")
  local background=CreateFrame("Frame",nil,window,"BackdropTemplate");background:SetPoint("TOPLEFT",window,"TOPLEFT",13,-68);background:SetPoint("BOTTOMRIGHT",window,"BOTTOMRIGHT",-17,57);background:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1});background:SetBackdropColor(.02,.025,.025,1);background:SetBackdropBorderColor(.3,.35,.32,1)
  local scroll=CreateFrame("ScrollFrame","NokiUnifiedImportScroll",window,"UIPanelScrollFrameTemplate");scroll:SetPoint("TOPLEFT",window,"TOPLEFT",18,-72);scroll:SetPoint("BOTTOMRIGHT",window,"BOTTOMRIGHT",-34,62)
  box=CreateFrame("EditBox","NokiUnifiedImportBox",scroll);box:SetMultiLine(true);box:SetFontObject("ChatFontNormal");box:SetAutoFocus(false);box:SetWidth(530);box:SetMaxLetters(0);box:SetScript("OnEscapePressed",function(self) self:ClearFocus() end);scroll:SetScrollChild(box)
  resultText=window:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");resultText:SetPoint("BOTTOMLEFT",window,"BOTTOMLEFT",16,38);resultText:SetWidth(550);resultText:SetJustifyH("LEFT")
  local import=CreateFrame("Button",nil,window,"UIPanelButtonTemplate");import:SetSize(110,24);import:SetPoint("BOTTOMRIGHT",window,"BOTTOMRIGHT",-135,10);import:SetText("Import");import:SetScript("OnClick",function()
    local result,err=core.ImportTable(box:GetText())
    if result then resultText:SetText("Imported "..result.count.." items for "..result.market..".");box:SetText("");box:ClearFocus()
    else resultText:SetText(err or "Import failed; previous data kept.") end
  end)
  local close=CreateFrame("Button",nil,window,"UIPanelButtonTemplate");close:SetSize(110,24);close:SetPoint("BOTTOMRIGHT",window,"BOTTOMRIGHT",-16,10);close:SetText("Close");close:SetScript("OnClick",function() window:Hide() end)
  window:Hide()
end
function core.ShowImport()
  createImport();resultText:SetText("Select the box and paste your market's import string.");window:Show();box:SetFocus()
end
