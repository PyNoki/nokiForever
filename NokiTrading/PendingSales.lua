-- Show pending auction-sale payouts from the mailbox, before money is delivered.
local core=NokiUnifiedCore
local mailOpen=false
local panel,amountText,detailText
local function owner() return UnitGUID and UnitGUID("player") end
local function now() return (GetServerTime and GetServerTime()) or time() end
function core.CapturePendingOwned(rows)
  if type(rows)~="table" or not NokiUnifiedCoreDB then return end
  local id=owner();if not id then return end
  local sold=(Enum and Enum.AuctionStatus and Enum.AuctionStatus.Sold) or 1
  local amount,count,unknown=0,0,0
  for _,row in ipairs(rows) do
    if row.status==sold then
      count=count+1
      -- Blizzard displays buyoutAmount directly for a sold row, including commodities.
      if type(row.buyoutAmount)=="number" and row.buyoutAmount>0 then amount=amount+row.buyoutAmount else unknown=unknown+1 end
    end
  end
  NokiUnifiedCoreDB.pendingAuctionSnapshots=NokiUnifiedCoreDB.pendingAuctionSnapshots or {}
  NokiUnifiedCoreDB.pendingAuctionSnapshots[id]={amount=amount,count=count,unknown=unknown,checked=now()}
end
local function snapshot()
  local id=owner();local saved=NokiUnifiedCoreDB and NokiUnifiedCoreDB.pendingAuctionSnapshots
  return id and saved and saved[id] or nil
end
local function money(amount)
  if GetCoinTextureString then return GetCoinTextureString(amount) end
  local gold=math.floor(amount/10000);local silver=math.floor(amount%10000/100);local copper=amount%100
  return gold.."g "..silver.."s "..copper.."c"
end
local function createPanel()
  if panel or not MailFrame then return end
  panel=CreateFrame("Frame","NokiPendingSalesMailbox",MailFrame,"BackdropTemplate")
  panel:SetSize(245,95);panel:SetPoint("TOPLEFT",MailFrame,"TOPRIGHT",8,-42);panel:SetClampedToScreen(true)
  panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1});panel:SetBackdropColor(.055,.065,.07,.97);panel:SetBackdropBorderColor(.35,.42,.37,1)
  local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormal");title:SetPoint("TOPLEFT",10,-9);title:SetText("AUCTION SALES ON THE WAY")
  amountText=panel:CreateFontString(nil,"OVERLAY","GameFontHighlight");amountText:SetPoint("TOPLEFT",10,-32);amountText:SetPoint("TOPRIGHT",-10,-32);amountText:SetJustifyH("LEFT")
  detailText=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");detailText:SetPoint("TOPLEFT",10,-54);detailText:SetPoint("TOPRIGHT",-10,-54);detailText:SetJustifyH("LEFT");detailText:SetWordWrap(true)
end
local function showResult(amount,count,unknown,partial)
  if not panel then return end
  local incomplete=partial or unknown>0
  if incomplete and amount==0 then amountText:SetText("Amount: --")
  else amountText:SetText((incomplete and "At least: " or "Pending: ")..money(amount)) end
  local note=incomplete and "Mailbox data is incomplete. " or ""
  if unknown>0 then note=note..unknown.." pending amount(s) unavailable. " end
  detailText:SetText(note.."Only sales awaiting payment; delivered mail excluded.")
end
local function showAuctionSnapshot()
  local saved=snapshot()
  if not saved or not panel then return false end
  local amount=type(saved.amount)=="number" and saved.amount or 0
  local unknown=type(saved.unknown)=="number" and saved.unknown or 0
  if unknown>0 and amount==0 then amountText:SetText("AH incoming: --")
  else amountText:SetText((unknown>0 and "AH incoming (partial): " or "AH incoming: ")..money(amount)) end
  local age=type(saved.checked)=="number" and math.max(0,math.floor((now()-saved.checked)/60)) or nil
  local note="Last AH check: "..(age and (age.."m ago") or "unknown")..". May have changed or arrived."
  if unknown>0 then note=note.." "..unknown.." amount(s) unavailable." end
  detailText:SetText(note)
  return true
end
local function scanMailbox()
  if not mailOpen or not panel then return end
  if showAuctionSnapshot() then return end
  if not GetInboxNumItems or not GetInboxInvoiceInfo then amountText:SetText("Amount: --");detailText:SetText("Pending invoice data is unavailable on this client.");return end
  local ok,loaded,total=pcall(GetInboxNumItems)
  if not ok or type(loaded)~="number" or loaded<0 then amountText:SetText("Amount: --");detailText:SetText("Mailbox data unavailable.");return end
  local subjectTemplate=(type(AUCTION_INVOICE_MAIL_SUBJECT)=="string" and AUCTION_INVOICE_MAIL_SUBJECT) or "Sale Pending: %s"
  local pendingPrefix=subjectTemplate:gsub("%%s.*$","")
  local headersUnavailable=not GetInboxHeaderInfo or pendingPrefix==""
  local amount,count,unknown=0,0,0
  for i=1,loaded do
    local pendingSubject=false
    if GetInboxHeaderInfo and pendingPrefix~="" then
      local headerOK,_,_,_,subject=pcall(GetInboxHeaderInfo,i)
      if not headerOK or type(subject)~="string" then headersUnavailable=true
      else pendingSubject=subject:sub(1,#pendingPrefix)==pendingPrefix end
    end
    local success,kind,itemName,playerName,bid,buyout,deposit,cut=pcall(GetInboxInvoiceInfo,i)
    if not success then unknown=unknown+1
    elseif kind=="seller_temp_invoice" then
      count=count+1
      if type(bid)=="number" and bid>=0 and type(deposit)=="number" and deposit>=0 and type(cut)=="number" and cut>=0 and bid+deposit>=cut then
        amount=amount+bid+deposit-cut
      else unknown=unknown+1 end
    elseif pendingSubject then unknown=unknown+1 end
  end
  if count==0 and unknown==0 then
    amountText:SetText("AH incoming: --")
    detailText:SetText("Visit the auction house to load sold auctions, then reopen your mailbox.")
  else showResult(amount,count,unknown,headersUnavailable or type(total)~="number" or total>loaded) end
end
local events=CreateFrame("Frame")
for _,event in ipairs({"MAIL_SHOW","MAIL_INBOX_UPDATE","MAIL_CLOSED"}) do pcall(events.RegisterEvent,events,event) end
events:SetScript("OnEvent",function(_,event)
  if event=="MAIL_SHOW" then
    mailOpen=true;createPanel()
    if panel then if not showAuctionSnapshot() then amountText:SetText("Amount: --");detailText:SetText("Waiting for mailbox data.") end;panel:Show() end
  elseif event=="MAIL_CLOSED" then mailOpen=false;if panel then panel:Hide() end
  elseif event=="MAIL_INBOX_UPDATE" then scanMailbox() end
end)
