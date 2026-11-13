local core=NokiUnifiedCore
local frame, body, title, mini, coinCheck, filter, search, rows, summary
local detail, detailRows, detailTitle, detailNote, detailPageText, selected, detailPage, detailDrops
local page, currentTab, results = 1, 'Bag', {}
local itemRequests={}
local function itemName(id)
  local bundled=NokiTradingLoot.items[id]
  if type(bundled)=='string' and bundled~='' then return bundled end
  local getter=GetItemInfo or (C_Item and C_Item.GetItemInfo)
  if getter then
    local ok,name=pcall(getter,id)
    if ok and not (issecretvalue and issecretvalue(name)) and type(name)=='string' and name~='' then return name end
  end
  if not itemRequests[id] then
    itemRequests[id]=true
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID,id) end
  end
  return 'Item '..id
end
local function text(parent, template, x, y, width)
  local f=parent:CreateFontString(nil,'OVERLAY',template);f:SetPoint('TOPLEFT',x,y);if width then f:SetWidth(width);f:SetJustifyH('LEFT') end;return f
end
local function button(parent,label,x,y,w,action)
  local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');b:SetSize(w,26);b:SetPoint('TOPLEFT',x,y);b:SetText(label);b:SetScript('OnClick',action);return b
end
local function price(id)
  local market=core.Market();local book=market and NokiBetaCoreDB.prices and NokiBetaCoreDB.prices[market];local r=book and book.items and book.items[id]
  local scan=r and type(r.price)=='number' and r.price>0 and r or nil
  local p=NokiUnifiedAPI.GetPrice(id);local imported=p and type(p.minBuyout)=='number' and p.minBuyout>0 and p or nil
  local scanTime=scan and (scan.observed or book.observed)
  if scan and (not imported or not imported.updated or (scanTime and scanTime>=imported.updated)) then return scan.price,scanTime,scan.carried and 'Earlier AH scan' or 'AH scan' end
  if imported then return imported.minBuyout,imported.updated,'AHledger' end
  if scan then return scan.price,scanTime,scan.carried and 'Earlier AH scan' or 'AH scan' end
end
local function money(c)
  c=math.floor(c+.5);local g=math.floor(c/10000);local s=math.floor(c%10000/100);local copper=c%100
  if g>0 then return g..'g '..s..'s '..copper..'c' end
  if s>0 then return s..'s '..copper..'c' end
  return copper..'c'
end
local function levelFor(id,mob)
  if mob.min>0 then return mob.min,mob.max,mob.levelSource or 'Classic reference' end
  local observed=NokiBetaCoreDB.farmObservedLevels and NokiBetaCoreDB.farmObservedLevels[id]
  if observed then return observed.min,observed.max,'observed' end
  return mob.min,mob.max,'Classic'
end
local function showDetails(item)
  selected=item;detailPage=1
  if not detail then
    detail=CreateFrame('Frame','NokiTradingLootDetails',UIParent,'BackdropTemplate');detail:SetSize(670,520);detail:SetPoint('CENTER',UIParent,'CENTER',120,0);detail:SetFrameStrata('DIALOG');detail:SetMovable(true);detail:EnableMouse(true);detail:RegisterForDrag('LeftButton');detail:SetClampedToScreen(true)
    detail:SetScript('OnDragStart',function(s)s:StartMoving()end);detail:SetScript('OnDragStop',function(s)s:StopMovingOrSizing()end)
    detail:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1});detail:SetBackdropColor(.035,.055,.055,.98);detail:SetBackdropBorderColor(.55,.42,.19,1)
    detailTitle=text(detail,'GameFontNormalLarge',20,-20,580)
    detailNote=text(detail,'GameFontHighlightSmall',20,-50,625)
    text(detail,'GameFontNormalSmall',27,-101,245):SetText('ITEM')
    text(detail,'GameFontNormalSmall',283,-101,140):SetText('DROP OBSERVATIONS')
    text(detail,'GameFontNormalSmall',430,-101,105):SetText('AH / ITEM')
    text(detail,'GameFontNormalSmall',540,-101,100):SetText('PRICE SOURCE')
    button(detail,'X',625,-14,28,function()detail:Hide()end)
    detailRows={}
    for i=1,11 do
      local row=CreateFrame('Frame',nil,detail,'BackdropTemplate');row:SetPoint('TOPLEFT',20,-123-(i-1)*29);row:SetSize(630,28);row:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8'});row:SetBackdropColor(i%2==0 and .10 or .07,.13,.12,.95)
      row.name=text(row,'GameFontHighlightSmall',7,-7,245);row.rate=text(row,'GameFontHighlightSmall',263,-7,140);row.unit=text(row,'GameFontHighlightSmall',410,-7,105);row.total=text(row,'GameFontHighlightSmall',520,-7,100)
      row:EnableMouse(true);row:SetScript('OnEnter',function(s)
        local x=s.entry;if not x then return end;local d=x.drop
        GameTooltip:SetOwner(s,'ANCHOR_RIGHT');GameTooltip:AddLine(itemName(d[1]));GameTooltip:AddLine('AHledger: '..d[5]..' loot'..(d[3]>0 and (', '..d[2]..' / '..d[3]..' observations') or ', sample unavailable')..(d[6]>0 and ('; '..d[6]..' reporters.') or '.'),1,1,1,true)
        if d[7] or type(d[8])~='number' then GameTooltip:AddLine('Drop percentage unavailable: not enough sample data.',1,.55,.2,true) end
        GameTooltip:AddLine((x.source or 'Price unavailable')..' observed: '..(x.when and date('%Y-%m-%d %H:%M',x.when) or 'unknown'),1,1,1);GameTooltip:Show()
      end);row:SetScript('OnLeave',function()GameTooltip:Hide()end);detailRows[i]=row
    end
    detailPageText=text(detail,'GameFontHighlightSmall',220,-465,300)
    button(detail,'Previous',20,-460,90,function()detailPage=detailPage-1;detail.render()end)
    button(detail,'Next',118,-460,90,function()detailPage=detailPage+1;detail.render()end)
    button(detail,'Scan market',515,-460,135,function()local ok,err=core.Scan();detailNote:SetText(ok and 'Scanning the open auction house. Prices update when the scan finishes.' or ('Cannot scan: '..tostring(err))) end)
    detail.render=function()
      detailDrops={}
      for _,d in ipairs(selected.mob.drops) do local p,when,source=price(d[1]);detailDrops[#detailDrops+1]={drop=d,unit=p,when=when,source=source} end
      table.sort(detailDrops,function(a,b) if (a.unit or -1)==(b.unit or -1) then return a.drop[1]<b.drop[1] end return (a.unit or -1)>(b.unit or -1) end)
      local pages=math.max(1,math.ceil(#detailDrops/11));detailPage=math.max(1,math.min(detailPage,pages))
      detailTitle:SetText(selected.mob.name..'  |  LOOT')
      detailNote:SetText('AHledger drop rates are observed estimates. Hover for sample details and price age.')
      detailPageText:SetText('Page '..detailPage..' / '..pages..'  |  '..#detailDrops..' recorded drops')
      for i,row in ipairs(detailRows) do
        local x=detailDrops[(detailPage-1)*11+i];if x then local d=x.drop;row.entry=x;row.name:SetText(itemName(d[1]));local rate=type(d[8])=='number' and string.format('%.1f%% (%d/%d)',d[8],d[2],d[3]) or 'Not enough data';row.rate:SetText(rate);row.unit:SetText(x.unit and money(x.unit) or 'No price');row.total:SetText(x.source or '--');row:Show() else row:Hide() end
      end
    end
  end
  detail:Show();detail.render()
end
local function refresh()
  if not frame or not frame:IsShown() then return end
  body:SetShown(currentTab=='Bag');filter:SetShown(currentTab=='Farm');search:SetShown(currentTab=='Farm');summary:SetShown(currentTab=='Farm')
  for _,r in ipairs(rows) do r:Hide() end
  title:SetText(currentTab=='Bag' and 'BAG TOOLS' or 'FARMING  |  MONSTER DROPS')
  if currentTab=='Bag' then coinCheck:SetChecked(NokiBetaCoreDB.bagCoinEnabled==true);return end
  local level=tonumber(filter:GetText());local query=search:GetText():lower();results={}
  for id,mob in pairs(NokiTradingLoot.mobs) do
    local low,high,levelSource=levelFor(id,mob)
    local location=table.concat(mob.locations or {},' | ')
    if (not level or (low>0 and low<=level and high>=level)) and (query=='' or mob.name:lower():find(query,1,true) or (mob.zone or ''):lower():find(query,1,true) or location:lower():find(query,1,true)) then
      local missing,lowSamples=0,0
      for _,d in ipairs(mob.drops) do if not price(d[1]) then missing=missing+1 end;if d[7] or type(d[8])~='number' then lowSamples=lowSamples+1 end end
      results[#results+1]={id=id,mob=mob,missing=missing,lowSamples=lowSamples,low=low,high=high,levelSource=levelSource}
    end
  end
  table.sort(results,function(a,b) if a.mob.name==b.mob.name then return a.id<b.id end return a.mob.name:lower()<b.mob.name:lower() end)
  page=math.max(1,math.min(page,math.max(1,math.ceil(#results/8))))
  summary:SetText('Click a mob for loot and AH prices. Hover for level source. Page '..page..' / '..math.max(1,math.ceil(#results/8)))
  for i,r in ipairs(rows) do
    local item=results[(page-1)*8+i];if item then
      r.item=item;r.name:SetText(item.mob.name..'  |cff899998'..(item.low>0 and (item.low..'-'..item.high) or 'level ?')..'|r');r.value:SetText(#item.mob.drops..' drops');r.note:SetText(item.mob.zone~='' and item.mob.zone or 'Zone unknown');r:Show()
    end
  end
end
local function build()
  if frame then return end
  frame=CreateFrame('Frame','NokiTradingMenu',UIParent,'BackdropTemplate');frame:SetSize(630,480);frame:SetPoint('CENTER');frame:SetMovable(true);frame:EnableMouse(true);frame:RegisterForDrag('LeftButton');frame:SetClampedToScreen(true)
  frame:SetScript('OnDragStart',function(s)s:StartMoving()end);frame:SetScript('OnDragStop',function(s)s:StopMovingOrSizing()end)
  frame:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1});frame:SetBackdropColor(.035,.055,.055,.98);frame:SetBackdropBorderColor(.55,.42,.19,1)
  local brand=text(frame,'GameFontNormalLarge',22,-20);brand:SetText('NOKI  |  TRADING')
  local subtitle=text(frame,'GameFontHighlightSmall',23,-44);subtitle:SetText('Your market companion')
  button(frame,'X',585,-14,28,function()frame:Hide()end)
  button(frame,'Bag',22,-75,100,function()currentTab='Bag';refresh()end)
  button(frame,'Farm',130,-75,100,function()currentTab='Farm';page=1;refresh()end)
  title=text(frame,'GameFontNormal',22,-118)
  body=CreateFrame('Frame',nil,frame);body:SetAllPoints()
  local intro=text(body,'GameFontHighlight',24,-151,565);intro:SetText('Keep your bag tools close at hand. Deploy the coin, drag it anywhere, and click it to return here.')
  coinCheck=CreateFrame('CheckButton',nil,body,'UICheckButtonTemplate');coinCheck:SetPoint('TOPLEFT',22,-205);coinCheck:SetSize(30,30)
  local label=text(body,'GameFontHighlight',56,-212);label:SetText('Show movable bag coin')
  coinCheck:SetScript('OnClick',function(s)NokiBetaCoreDB.bagCoinEnabled=s:GetChecked() and true or false;if core.UpdateBagCoinVisibility then core.UpdateBagCoinVisibility() end end)
  button(body,'Bag selling rules',24,-265,160,function()if core.ToggleBagRules then core.ToggleBagRules()end end)
  button(body,'Excluded items',192,-265,160,function()if core.ShowBagExclusions then core.ShowBagExclusions()end end)
  local hint=text(body,'GameFontHighlightSmall',24,-310,550);hint:SetText('The coin tooltip shows estimated bag value. Selling rules and exclusions use your existing settings.')
  filter=CreateFrame('EditBox',nil,frame,'InputBoxTemplate');filter:SetSize(85,25);filter:SetPoint('TOPLEFT',31,-151);filter:SetAutoFocus(false);filter:SetNumeric(true);filter:SetMaxLetters(2);filter:SetScript('OnEnterPressed',function(s)s:ClearFocus();page=1;refresh()end);filter:SetScript('OnEscapePressed',function(s)s:ClearFocus()end)
  local fl=text(frame,'GameFontHighlightSmall',125,-155);fl:SetText('Level')
  search=CreateFrame('EditBox',nil,frame,'InputBoxTemplate');search:SetSize(180,25);search:SetPoint('TOPLEFT',305,-151);search:SetAutoFocus(false);search:SetMaxLetters(50);search:SetScript('OnEnterPressed',function(s)s:ClearFocus();page=1;refresh()end);search:SetScript('OnEscapePressed',function(s)s:ClearFocus()end)
  local searchLabel=text(frame,'GameFontHighlightSmall',500,-155);searchLabel:SetText('Name / zone; Enter')
  rows={};for i=1,8 do
    local row=CreateFrame('Button',nil,frame,'BackdropTemplate');row:SetPoint('TOPLEFT',22,-188-(i-1)*27);row:SetSize(585,26);row:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8'});row:SetBackdropColor(i%2==0 and .10 or .07,.13,.12,.95)
    row.name=text(row,'GameFontHighlightSmall',8,-6,260);row.value=text(row,'GameFontNormalSmall',275,-6,95);row.note=text(row,'GameFontHighlightSmall',375,-6,205)
    row:EnableMouse(true);row:SetScript('OnEnter',function(s)
      local v=s.item;if not v then return end
      GameTooltip:SetOwner(s,'ANCHOR_RIGHT');GameTooltip:AddLine(v.mob.name)
      if v.mob.zone and v.mob.zone~='' then GameTooltip:AddLine('Zone: '..v.mob.zone,1,1,1,true) end
      for _,location in ipairs(v.mob.locations or {}) do GameTooltip:AddLine(location,.75,.85,.8,true) end
      GameTooltip:AddLine(v.low>0 and ('Level source: '..v.levelSource) or 'Level unknown',1,1,1,true)
      if v.low>0 and v.levelSource:find('observed') then GameTooltip:AddLine('Observed levels may not include the full range.',1,1,1,true) end
      GameTooltip:AddLine(#v.mob.drops..' recorded drops; '..v.missing..' unpriced; '..v.lowSamples..' low sample.',1,1,1,true)
      GameTooltip:AddLine('Click for individual drop observations and AH prices.',1,.8,.3,true);GameTooltip:Show()
    end);row:SetScript('OnLeave',function()GameTooltip:Hide()end);row:SetScript('OnClick',function(s)if s.item then showDetails(s.item) end end);rows[i]=row
  end
  summary=text(frame,'GameFontHighlightSmall',24,-412,580)
  local prev=button(frame,'Previous',24,-443,85,function()page=page-1;refresh()end);local nextb=button(frame,'Next',117,-443,85,function()page=page+1;refresh()end)
  local oldRefresh=refresh;refresh=function()oldRefresh();local show=currentTab=='Farm';fl:SetShown(show);searchLabel:SetShown(show);prev:SetShown(show);nextb:SetShown(show)end
  frame:SetScript('OnShow',function()refresh()end);frame:Hide()
end
function core.OpenTradingMenu(tab) build();currentTab=tab or 'Bag';frame:Show();refresh() end
local function setupMini()
 if mini then return end
 mini=CreateFrame('Button','NokiTradingMinimapButton',Minimap);mini:SetSize(32,32);mini:SetFrameStrata('MEDIUM');mini:RegisterForDrag('LeftButton');mini:RegisterForClicks('LeftButtonUp')
 local bg=mini:CreateTexture(nil,'BACKGROUND');bg:SetAllPoints();bg:SetTexture('Interface\\MoneyFrame\\UI-GoldIcon')
 local border=mini:CreateTexture(nil,'OVERLAY');border:SetSize(54,54);border:SetPoint('TOPLEFT',-1,1);border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
 local function position(a)local rad=math.rad(a or 135);local radius=(Minimap:GetWidth() or 140)/2+5;mini:ClearAllPoints();mini:SetPoint('CENTER',Minimap,'CENTER',math.cos(rad)*radius,math.sin(rad)*radius)end
 position(NokiBetaCoreDB.tradingMinimapAngle)
 mini:SetScript('OnDragStart',function(s)s.dragged=true;s:SetScript('OnUpdate',function()local x,y=GetCursorPosition();local scale=Minimap:GetEffectiveScale();local cx,cy=Minimap:GetCenter();if cx and cy then local a=math.deg(math.atan2(y/scale-cy,x/scale-cx));NokiBetaCoreDB.tradingMinimapAngle=a;position(a)end end)end)
 mini:SetScript('OnDragStop',function(s)s:SetScript('OnUpdate',nil)end)
 mini:SetScript('OnMouseDown',function(s)s.dragged=false end);mini:SetScript('OnClick',function(s)if not s.dragged then core.OpenTradingMenu('Bag')end end)
 mini:SetScript('OnEnter',function(s)GameTooltip:SetOwner(s,'ANCHOR_LEFT');GameTooltip:AddLine('Noki Trading');GameTooltip:AddLine('Click: open menu | Drag: move',1,1,1);GameTooltip:Show()end);mini:SetScript('OnLeave',function()GameTooltip:Hide()end)
end
SLASH_NOKITRADINGMENU1='/ntrading';SlashCmdList.NOKITRADINGMENU=function()core.OpenTradingMenu('Bag')end
local events=CreateFrame('Frame');events:RegisterEvent('PLAYER_LOGIN');events:RegisterEvent('PLAYER_TARGET_CHANGED');events:RegisterEvent('GET_ITEM_INFO_RECEIVED');events:SetScript('OnEvent',function(_,event,id,success)
  if event=='PLAYER_LOGIN' then setupMini();return end
  if event=='GET_ITEM_INFO_RECEIVED' then
    if id and itemRequests[id] and success and detail and detail:IsShown() then detail.render() end
    return
  end
  if not NokiBetaCoreDB or not UnitGUID or not UnitLevel then return end
  local ok,guid=pcall(UnitGUID,'target');if not ok or (issecretvalue and issecretvalue(guid)) or type(guid)~='string' then return end
  local kind,id=guid:match('^(%a+)%-[^%-]+%-[^%-]+%-[^%-]+%-[^%-]+%-(%d+)%-')
  id=tonumber(id);if kind~='Creature' or not id or not NokiTradingLoot.mobs[id] then return end
  local good,lvl=pcall(UnitLevel,'target');if not good or (issecretvalue and issecretvalue(lvl)) or type(lvl)~='number' or lvl<1 or lvl>100 then return end
  NokiBetaCoreDB.farmObservedLevels=NokiBetaCoreDB.farmObservedLevels or {};local entry=NokiBetaCoreDB.farmObservedLevels[id]
  if entry then entry.min=math.min(entry.min,lvl);entry.max=math.max(entry.max,lvl) else NokiBetaCoreDB.farmObservedLevels[id]={min=lvl,max=lvl} end
  refresh()
end)
core.Subscribe(function(event)
  if event=='complete' then
    if detail and detail:IsShown() then detail.render() end
    refresh()
  elseif event=='failed' and detail and detail:IsShown() then
    detailNote:SetText('Market scan failed or was interrupted; previous prices are still shown.')
  end
end)
