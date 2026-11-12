-- Show pending auction-sale payouts from the mailbox, before money is delivered.
local mailOpen=false
local panel,amountText,detailText
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
local function scanMailbox()
  if not mailOpen or not panel then return end
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
  showResult(amount,count,unknown,headersUnavailable or type(total)~="number" or total>loaded)
end
local events=CreateFrame("Frame")
for _,event in ipairs({"MAIL_SHOW","MAIL_INBOX_UPDATE","MAIL_CLOSED"}) do pcall(events.RegisterEvent,events,event) end
events:SetScript("OnEvent",function(_,event)
  if event=="MAIL_SHOW" then
    mailOpen=true;createPanel()
    if panel then amountText:SetText("Amount: --");detailText:SetText("Waiting for mailbox data.");panel:Show() end
  elseif event=="MAIL_CLOSED" then mailOpen=false;if panel then panel:Hide() end
  elseif event=="MAIL_INBOX_UPDATE" then scanMailbox() end
end)
