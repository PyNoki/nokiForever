local core=NokiUnifiedCore
local frame, body, title, mini, coinCheck, filter, maxFilter, search, rows, summary, areaCheck, sortButton
local sortMode='score'
local detail, detailRows, detailTitle, detailNote, detailPageText, selected, detailPage, detailDrops
local page, currentTab, results = 1, 'Bag', {}
local itemRequests={}
local function requestItem(id)
  if not itemRequests[id] then
    itemRequests[id]=true
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID,id) end
  end
end
local function itemName(id)
  local bundled=NokiTradingLoot.items[id]
  if type(bundled)=='string' and bundled~='' and bundled~=('Item '..id) then return bundled end
  local getter=GetItemInfo or (C_Item and C_Item.GetItemInfo)
  if getter then
    local ok,name=pcall(getter,id)
    if ok and not (issecretvalue and issecretvalue(name)) and type(name)=='string' and name~='' then return name end
  end
  requestItem(id)
  return 'Item '..id
end
local function itemIcon(id)
  local getter=(C_Item and C_Item.GetItemIconByID) or GetItemIcon
  if getter then local ok,icon=pcall(getter,id);if ok and icon and not (issecretvalue and issecretvalue(icon)) then return icon end end
  requestItem(id)
  return 134400
end
local function text(parent, template, x, y, width)
  local f=parent:CreateFontString(nil,'OVERLAY',template);f:SetPoint('TOPLEFT',x,y);if width then f:SetWidth(width);f:SetJustifyH('LEFT') end;return f
end
local function button(parent,label,x,y,w,action)
  local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');b:SetSize(w,26);b:SetPoint('TOPLEFT',x,y);b:SetText(label);b:SetScript('OnClick',action);return b
end
local function band(parent,x,y,width,height,r,g,b,a)
  local t=parent:CreateTexture(nil,'BACKGROUND');t:SetPoint('TOPLEFT',x,y);t:SetSize(width,height);t:SetColorTexture(r,g,b,a or 1);return t
end
local function salesText(n)
  if type(n)~='number' then return '--' end
  if n>=1000 then return string.format('%.1fk',n/1000) end
  if n>=100 then return string.format('%.0f',n) end
  return string.format('%.1f',n):gsub('%.0$','')
end
local function price(id)
  local market=core.Market();local book=market and NokiBetaCoreDB.prices and NokiBetaCoreDB.prices[market];local r=book and book.items and book.items[id]
  if r and not r.carried and type(r.price)=='number' and r.price>0 then
    return r.price,r.observed or book.observed,'AH scan',r.quantity
  end
end
local function money(c)
  c=math.floor(c+.5);local g=math.floor(c/10000);local s=math.floor(c%10000/100);local copper=c%100
  if g>0 then return g..'g '..s..'s '..copper..'c' end
  if s>0 then return s..'s '..copper..'c' end
  return copper..'c'
end
local function scanAge()
  local market=core.Market()
  local book=market and NokiBetaCoreDB and NokiBetaCoreDB.prices and NokiBetaCoreDB.prices[market]
  if not book or type(book.observed)~='number' then return 'No completed AH scan' end
  local current=(GetServerTime and GetServerTime()) or time()
  local minutes=math.max(0,math.floor((current-book.observed)/60))
  if minutes<60 then return 'AH scan: '..minutes..'m ago' end
  local hours=math.floor(minutes/60)
  if hours<48 then return 'AH scan: '..hours..'h '..(minutes%60)..'m ago' end
  return 'AH scan: '..math.floor(hours/24)..'d '..(hours%24)..'h ago'
end
local function farmScenario()
  local db=NokiBetaCoreDB or {}
  local kills=math.max(1,math.min(10000,tonumber(db.farmScenarioKills) or 100))
  local share=math.max(1,math.min(100,tonumber(db.farmScenarioShare) or 10))
  return kills,share/100
end
local function levelFor(id,mob)
  if mob.min>0 then return mob.min,mob.max,mob.levelSource or 'Classic reference' end
  local observed=NokiBetaCoreDB.farmObservedLevels and NokiBetaCoreDB.farmObservedLevels[id]
  if observed then return observed.min,observed.max,'observed' end
  local zoneMin,zoneMax=core.FarmZoneLevel(mob)
  if zoneMin then return zoneMin,zoneMax,'zone range' end
  return 0,0,'unknown'
end
local function showDetails(item)
  selected=item;detailPage=1
  if not detail then
    detail=CreateFrame('Frame','NokiTradingLootDetails',UIParent,'BackdropTemplate');detail:SetSize(670,520);detail:SetPoint('CENTER',UIParent,'CENTER',120,0);detail:SetFrameStrata('DIALOG');detail:SetMovable(true);detail:EnableMouse(true);detail:RegisterForDrag('LeftButton');detail:SetClampedToScreen(true)
    detail:SetScript('OnDragStart',function(s)s:StartMoving()end);detail:SetScript('OnDragStop',function(s)s:StopMovingOrSizing()end)
    detail:SetScript('OnUpdate',function(self,elapsed)
      self.ageElapsed=(self.ageElapsed or 0)+elapsed
      if self.ageElapsed>=60 then self.ageElapsed=0;if self.render then self.render() end end
    end)
    detail:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1});detail:SetBackdropColor(.025,.045,.038,.98);detail:SetBackdropBorderColor(.20,.43,.29,1)
    band(detail,1,-1,668,77,.045,.10,.068,.98);band(detail,20,-79,630,2,.24,.65,.39,.9)
    band(detail,20,-95,630,25,.09,.17,.125,.95)
    detailTitle=text(detail,'GameFontNormalLarge',20,-20,580)
    detailNote=text(detail,'GameFontHighlightSmall',20,-50,625)
    text(detail,'GameFontNormalSmall',27,-101,245):SetText('ITEM')
    text(detail,'GameFontNormalSmall',283,-101,140):SetText('DROP RATE')
    text(detail,'GameFontNormalSmall',430,-101,105):SetText('AH / ITEM')
    text(detail,'GameFontNormalSmall',540,-101,100):SetText('EST. SOLD / DAY')
    button(detail,'X',625,-14,28,function()detail:Hide()end)
    detailRows={}
    for i=1,11 do
      local row=CreateFrame('Frame',nil,detail,'BackdropTemplate');row:SetPoint('TOPLEFT',20,-123-(i-1)*29);row:SetSize(630,28);row:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8'});row:SetBackdropColor(i%2==0 and .075 or .045,i%2==0 and .13 or .095,i%2==0 and .095 or .07,.95)
      row.icon=row:CreateTexture(nil,'ARTWORK');row.icon:SetSize(22,22);row.icon:SetPoint('TOPLEFT',4,-3)
      row.name=text(row,'GameFontHighlightSmall',32,-7,220);row.rate=text(row,'GameFontHighlightSmall',263,-7,140);row.unit=text(row,'GameFontHighlightSmall',410,-7,105);row.total=text(row,'GameFontHighlightSmall',520,-7,100)
      row:EnableMouse(true);row:SetScript('OnEnter',function(s)
        local x=s.entry;if not x then return end;local d=x.drop
        s:SetBackdropColor(.11,.23,.15,1)
        GameTooltip:SetOwner(s,'ANCHOR_RIGHT')
        local ok=false
        if GameTooltip.SetItemByID then ok=pcall(GameTooltip.SetItemByID,GameTooltip,d[1]) end
        if not ok and GameTooltip.SetHyperlink then ok=pcall(GameTooltip.SetHyperlink,GameTooltip,'item:'..d[1]) end
        if not ok then GameTooltip:AddLine(itemName(d[1])) end
        GameTooltip:AddLine('AHledger: '..d[5]..' loot'..(d[3]>0 and (', '..d[2]..' / '..d[3]..' observations') or ', sample unavailable')..(d[6]>0 and ('; '..d[6]..' reporters.') or '.'),1,1,1,true)
        if d[7] or type(d[8])~='number' then GameTooltip:AddLine('Drop percentage unavailable: not enough sample data.',1,.55,.2,true) end
        GameTooltip:AddLine((x.source or 'Price unavailable')..' observed: '..(x.when and date('%Y-%m-%d %H:%M',x.when) or 'unknown'),1,1,1)
        if x.activity then
          GameTooltip:AddLine('AHledger estimated sales / day: '..salesText(x.activity.sales),.7,1,.75,true)
          GameTooltip:AddLine(NokiUnifiedMarketActivityLabel(x.activity),.8,.8,.8,true)
          GameTooltip:AddLine('Market-wide estimate, not confirmed sales or a guarantee of selling.',.8,.8,.8,true)
        else GameTooltip:AddLine('Sales estimate unavailable: '..(x.activityError or 'no activity data'),1,.75,.4,true) end
        local kills,share=farmScenario()
        local contribution,reason,weight,lower,modeled,farmed,cap=core.FarmDropScore(d,x.market,kills,share)
        if contribution then
          GameTooltip:AddLine('Conservative drop rate: '..string.format('%.1f%%',lower*100)..' | Liquidity weight: '..string.format('%.1f%%',weight*100),.7,1,.75,true)
          GameTooltip:AddLine('Last scan listed: '..(type(x.market.listed)=='number' and tostring(x.market.listed) or 'unavailable')..' | Estimated sold / day: '..salesText(x.activity.sales),.8,.9,.8,true)
          GameTooltip:AddLine(string.format('For %d kills: %.1f drops, %.1f demand share cap, %.1f modeled sales.',kills,farmed,cap,modeled),.8,.9,.8,true)
          GameTooltip:AddLine('Score contribution: '..money(contribution)..' / kill; assumes one item and 5% AH cut.',.8,.9,.8,true)
        else
          local labels={rate='drop rate unavailable',price='current scan price unavailable',activity='sales estimate unavailable',supply='listed quantity unavailable',sample='drop sample unavailable'}
          GameTooltip:AddLine('No 24h score contribution: '..(labels[reason] or 'data unavailable')..'.',1,.75,.4,true)
        end
        GameTooltip:Show()
      end);row:SetScript('OnLeave',function(s)s:SetBackdropColor(i%2==0 and .075 or .045,i%2==0 and .13 or .095,i%2==0 and .095 or .07,.95);GameTooltip:Hide()end);detailRows[i]=row
    end
    detailPageText=text(detail,'GameFontHighlightSmall',220,-465,300)
    button(detail,'Previous',20,-460,90,function()detailPage=detailPage-1;detail.render()end)
    button(detail,'Next',118,-460,90,function()detailPage=detailPage+1;detail.render()end)
    button(detail,'Scan market',515,-460,135,function()local ok,err=core.Scan();detailNote:SetText(ok and 'Scanning the open auction house. Prices update when the scan finishes.' or ('Cannot scan: '..tostring(err))) end)
    detail.render=function()
      detailDrops={}
      for _,d in ipairs(selected.mob.drops) do
        local p,when,source,listed=price(d[1]);local activity,err
        if NokiUnifiedMarketActivity then activity,err=NokiUnifiedMarketActivity(d[1]) end
        detailDrops[#detailDrops+1]={drop=d,unit=p,when=when,source=source,activity=activity,activityError=err,market={price=p,listed=listed,activity=activity}}
      end
      table.sort(detailDrops,function(a,b) if (a.unit or -1)==(b.unit or -1) then return a.drop[1]<b.drop[1] end return (a.unit or -1)>(b.unit or -1) end)
      local pages=math.max(1,math.ceil(#detailDrops/11));detailPage=math.max(1,math.min(detailPage,pages))
      detailTitle:SetText(selected.mob.name..'  |  LOOT')
      detailNote:SetText(scanAge()..' | Prices: latest AH scan  |  Drops & estimated sales: AHledger')
      detailPageText:SetText('Page '..detailPage..' / '..pages..'  |  '..#detailDrops..' recorded drops')
      for i,row in ipairs(detailRows) do
        local x=detailDrops[(detailPage-1)*11+i];if x then local d=x.drop;row.entry=x;row.name:SetText(itemName(d[1]));row.icon:SetTexture(itemIcon(d[1]));local rate=type(d[8])=='number' and string.format('%.1f%% (%d/%d)',d[8],d[2],d[3]) or 'Not enough data';row.rate:SetText(rate);row.unit:SetText(x.unit and money(x.unit) or 'No scan price');row.total:SetText(x.activity and salesText(x.activity.sales) or '--');row:Show() else row:Hide() end
      end
    end
  end
  detail:Show();detail.render()
end
local function refresh()
  if not frame or not frame:IsShown() then return end
  body:SetShown(currentTab=='Bag');filter:SetShown(currentTab=='Farm');maxFilter:SetShown(currentTab=='Farm');search:SetShown(currentTab=='Farm');summary:SetShown(currentTab=='Farm');areaCheck:SetShown(currentTab=='Farm');sortButton:SetShown(currentTab=='Farm')
  for _,r in ipairs(rows) do r:Hide() end
  title:SetText(currentTab=='Bag' and 'BAG TOOLS' or 'FARMING  |  MONSTER DROPS')
  if currentTab=='Bag' then coinCheck:SetChecked(NokiBetaCoreDB.bagCoinEnabled==true);return end
  local minLevel=tonumber(filter:GetText());local maxLevel=tonumber(maxFilter:GetText());local query=search:GetText():lower();local kills,share=farmScenario();results={}
  local zone=(GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText())
  if issecretvalue and issecretvalue(zone) then zone=nil end
  local markets={};local function cachedMarket(id)
    if not markets[id] then
      local p,_,_,listed=price(id);local activity=NokiUnifiedMarketActivity and NokiUnifiedMarketActivity(id)
      markets[id]={price=p,listed=listed,activity=activity}
    end
    return markets[id]
  end
  for id,mob in pairs(NokiTradingLoot.mobs) do
    local low,high,levelSource=levelFor(id,mob)
    local location=table.concat(mob.locations or {},' | ')
    if (not minLevel and not maxLevel or (low>0 and (not minLevel or high>=minLevel) and (not maxLevel or low<=maxLevel))) and (not areaCheck:GetChecked() or core.FarmInZone(mob,zone)) and (query=='' or mob.name:lower():find(query,1,true) or (mob.zone or ''):lower():find(query,1,true) or location:lower():find(query,1,true)) then
      local estimate=core.FarmValue(mob,cachedMarket,kills,share)
      results[#results+1]={id=id,mob=mob,estimate=estimate,low=low,high=high,levelSource=levelSource}
    end
  end
  table.sort(results,function(a,b)
    if sortMode=='score' and (a.estimate.value or -1)~=(b.estimate.value or -1) then return (a.estimate.value or -1)>(b.estimate.value or -1) end
    if sortMode=='gross' and (a.estimate.gross or -1)~=(b.estimate.gross or -1) then return (a.estimate.gross or -1)>(b.estimate.gross or -1) end
    if sortMode=='level' then local al=a.low>0 and a.low or 9999;local bl=b.low>0 and b.low or 9999;if al~=bl then return al<bl end end
    if a.mob.name==b.mob.name then return a.id<b.id end return a.mob.name:lower()<b.mob.name:lower()
  end)
  page=math.max(1,math.min(page,math.max(1,math.ceil(#results/8))))
  summary:SetText(scanAge()..' | '..kills..' kills, '..math.floor(share*100+.5)..'% demand | * partial | Page '..page..' / '..math.max(1,math.ceil(#results/8)))
  for i,r in ipairs(rows) do
    local item=results[(page-1)*8+i];if item then
      local e=item.estimate;local shown=e.value;if sortMode=='gross' then shown=e.gross end;local partial=(e.missingPrice+e.missingRate+(sortMode=='gross' and 0 or e.missingActivity+e.missingSupply+e.missingSample+e.stale))>0;r.item=item;r.name:SetText(item.mob.name..'  |cff899998'..(item.low>0 and ((item.levelSource=='zone range' and 'zone ' or 'lvl ')..item.low..'-'..item.high) or 'level ?')..'|r');r.value:SetText(shown and (money(shown)..(partial and '*' or '')) or '--');r.note:SetText(item.mob.zone~='' and item.mob.zone or 'Zone unknown');r:Show()
    end
  end
end
local function build()
  if frame then return end
  frame=CreateFrame('Frame','NokiTradingMenu',UIParent,'BackdropTemplate');frame:SetSize(630,520);frame:SetPoint('CENTER');frame:SetMovable(true);frame:EnableMouse(true);frame:RegisterForDrag('LeftButton');frame:SetClampedToScreen(true)
  frame:SetScript('OnDragStart',function(s)s:StartMoving()end);frame:SetScript('OnDragStop',function(s)s:StopMovingOrSizing()end)
  frame:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1});frame:SetBackdropColor(.025,.045,.038,.98);frame:SetBackdropBorderColor(.20,.43,.29,1)
  band(frame,1,-1,628,65,.045,.10,.068,.98);band(frame,22,-111,585,2,.24,.65,.39,.9)
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
  filter=CreateFrame('EditBox',nil,frame,'InputBoxTemplate');filter:SetSize(48,25);filter:SetPoint('TOPLEFT',31,-151);filter:SetAutoFocus(false);filter:SetNumeric(true);filter:SetMaxLetters(3);filter:SetScript('OnEnterPressed',function(s)s:ClearFocus();page=1;refresh()end);filter:SetScript('OnEscapePressed',function(s)s:ClearFocus()end)
  maxFilter=CreateFrame('EditBox',nil,frame,'InputBoxTemplate');maxFilter:SetSize(48,25);maxFilter:SetPoint('TOPLEFT',112,-151);maxFilter:SetAutoFocus(false);maxFilter:SetNumeric(true);maxFilter:SetMaxLetters(3);maxFilter:SetScript('OnEnterPressed',function(s)s:ClearFocus();page=1;refresh()end);maxFilter:SetScript('OnEscapePressed',function(s)s:ClearFocus()end)
  local fl=text(frame,'GameFontHighlightSmall',83,-155);fl:SetText('to')
  local fl2=text(frame,'GameFontHighlightSmall',168,-155);fl2:SetText('Level range')
  search=CreateFrame('EditBox',nil,frame,'InputBoxTemplate');search:SetSize(180,25);search:SetPoint('TOPLEFT',305,-151);search:SetAutoFocus(false);search:SetMaxLetters(50);search:SetScript('OnEnterPressed',function(s)s:ClearFocus();page=1;refresh()end);search:SetScript('OnEscapePressed',function(s)s:ClearFocus()end)
  local searchLabel=text(frame,'GameFontHighlightSmall',500,-155);searchLabel:SetText('Name / zone; Enter')
  areaCheck=CreateFrame('CheckButton',nil,frame,'UICheckButtonTemplate');areaCheck:SetSize(25,25);areaCheck:SetPoint('TOPLEFT',23,-181);areaCheck:SetScript('OnClick',function()page=1;refresh()end)
  local areaLabel=text(frame,'GameFontHighlightSmall',53,-187);areaLabel:SetText('Current zone')
  sortButton=button(frame,'Sort: Score',160,-180,125,function()sortMode=sortMode=='score' and 'gross' or sortMode=='gross' and 'level' or sortMode=='level' and 'name' or 'score';sortButton:SetText('Sort: '..(sortMode=='score' and 'Score' or sortMode=='gross' and 'Gross' or sortMode=='level' and 'Level' or 'Name'));page=1;refresh()end)
  local valueLabel=text(frame,'GameFontNormalSmall',298,-187);valueLabel:SetText('24H SCORE / KILL')
  rows={};for i=1,8 do
    local row=CreateFrame('Button',nil,frame,'BackdropTemplate');row:SetPoint('TOPLEFT',22,-218-(i-1)*27);row:SetSize(585,26);row:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8'});row:SetBackdropColor(i%2==0 and .075 or .045,i%2==0 and .13 or .095,i%2==0 and .095 or .07,.95)
    row.name=text(row,'GameFontHighlightSmall',8,-6,260);row.value=text(row,'GameFontNormalSmall',275,-6,95);row.note=text(row,'GameFontHighlightSmall',375,-6,205)
    row:EnableMouse(true);row:SetScript('OnEnter',function(s)
      local v=s.item;if not v then return end;s:SetBackdropColor(.11,.23,.15,1)
      GameTooltip:SetOwner(s,'ANCHOR_RIGHT');GameTooltip:AddLine(v.mob.name)
      if v.mob.zone and v.mob.zone~='' then GameTooltip:AddLine('Zone: '..v.mob.zone,1,1,1,true) end
      for _,location in ipairs(v.mob.locations or {}) do GameTooltip:AddLine(location,.75,.85,.8,true) end
      GameTooltip:AddLine(v.low>0 and ('Level source: '..v.levelSource) or 'Level unknown',1,1,1,true)
      if v.levelSource=='zone range' then GameTooltip:AddLine('Zone bracket only; the monster can be outside this range.',1,.8,.3,true) end
      if v.low>0 and v.levelSource:find('observed') then GameTooltip:AddLine('Observed levels may not include the full range.',1,1,1,true) end
      local e=v.estimate
      GameTooltip:AddLine('24h score / kill: '..(e.value and money(e.value) or 'unavailable')..' | Gross estimate: '..(e.gross and money(e.gross) or 'unavailable'),1,1,1,true)
      local kills,share=farmScenario()
      GameTooltip:AddLine('Scenario: '..kills..' kills; '..math.floor(share*100+.5)..'% of daily market demand.',1,1,1,true)
      GameTooltip:AddLine('Modeled sales are limited by expected drops, demand share, and a listing competition weight. Score divides their after-cut value by kills.',1,1,1,true)
      GameTooltip:AddLine('Drop rate uses a 90% one-sided Wilson lower bound from observed loot windows.',1,1,1,true)
      GameTooltip:AddLine('Heuristic assumes stable, equally competing listings and one item per drop. It is not a sale prediction; coin and deposits are excluded.',1,1,1,true)
      GameTooltip:AddLine('Missing: '..e.missingPrice..' prices, '..e.missingRate..' rates, '..e.missingActivity..' sales, '..e.missingSupply..' listed quantities, '..e.missingSample..' samples. Old or undated activity: '..e.stale..'.',1,.8,.3,true)
      GameTooltip:AddLine('Click for individual drop observations and AH prices.',1,.8,.3,true);GameTooltip:Show()
    end);row:SetScript('OnLeave',function(s)s:SetBackdropColor(i%2==0 and .075 or .045,i%2==0 and .13 or .095,i%2==0 and .095 or .07,.95);GameTooltip:Hide()end);row:SetScript('OnClick',function(s)if s.item then showDetails(s.item) end end);rows[i]=row
  end
  summary=text(frame,'GameFontHighlightSmall',24,-444,580)
  local prev=button(frame,'Previous',24,-478,85,function()page=page-1;refresh()end);local nextb=button(frame,'Next',117,-478,85,function()page=page+1;refresh()end)
  local settings
  local scenario=button(frame,'Scenario',210,-478,100,function()
    if settings then settings:SetShown(not settings:IsShown());return end
    settings=CreateFrame('Frame',nil,frame,'BackdropTemplate');settings:SetSize(370,218);settings:SetPoint('CENTER');settings:SetFrameLevel(frame:GetFrameLevel()+30);settings:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1});settings:SetBackdropColor(.025,.06,.04,1);settings:SetBackdropBorderColor(.20,.43,.29,1)
    text(settings,'GameFontNormal',16,-15,330):SetText('FARMING SCENARIO')
    text(settings,'GameFontHighlightSmall',16,-41,335):SetText('Estimate sales over one day. Your market share is an assumption, not a measured value.')
    text(settings,'GameFontHighlightSmall',16,-90,190):SetText('Kills per session')
    text(settings,'GameFontHighlightSmall',16,-125,190):SetText('Your share of daily sales (%)')
    local k=CreateFrame('EditBox',nil,settings,'InputBoxTemplate');k:SetSize(65,24);k:SetPoint('TOPLEFT',250,-84);k:SetAutoFocus(false);k:SetNumeric(true);k:SetMaxLetters(5)
    local s=CreateFrame('EditBox',nil,settings,'InputBoxTemplate');s:SetSize(65,24);s:SetPoint('TOPLEFT',250,-119);s:SetAutoFocus(false);s:SetNumeric(true);s:SetMaxLetters(3)
    local status=text(settings,'GameFontHighlightSmall',16,-153,330)
    button(settings,'Save',158,-180,90,function()
      local n,p=tonumber(k:GetText()),tonumber(s:GetText())
      if not n or n<1 or n>10000 or not p or p<1 or p>100 then status:SetText('Enter 1-10000 kills and 1-100% share.');return end
      NokiBetaCoreDB.farmScenarioKills=math.floor(n);NokiBetaCoreDB.farmScenarioShare=math.floor(p);settings:Hide();page=1;refresh();if detail and detail:IsShown() then detail.render() end
    end)
    button(settings,'Close',257,-180,90,function()settings:Hide()end)
    settings:SetScript('OnShow',function()local n,p=farmScenario();k:SetText(tostring(n));s:SetText(tostring(math.floor(p*100+.5)));status:SetText('')end)
    local n,p=farmScenario();k:SetText(tostring(n));s:SetText(tostring(math.floor(p*100+.5)))
  end)
  local oldRefresh=refresh;refresh=function()oldRefresh();local show=currentTab=='Farm';fl:SetShown(show);fl2:SetShown(show);areaLabel:SetShown(show);valueLabel:SetText(sortMode=='gross' and 'GROSS / KILL' or '24H SCORE / KILL');valueLabel:SetShown(show);searchLabel:SetShown(show);prev:SetShown(show);nextb:SetShown(show);scenario:SetShown(show);if not show and settings then settings:Hide() end end
  frame:SetScript('OnShow',function(self)self.ageElapsed=0;refresh()end)
  frame:SetScript('OnUpdate',function(self,elapsed)
    self.ageElapsed=(self.ageElapsed or 0)+elapsed
    if self.ageElapsed>=60 then self.ageElapsed=0;refresh() end
  end)
  frame:Hide()
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
local events=CreateFrame('Frame');events:RegisterEvent('PLAYER_LOGIN');events:RegisterEvent('PLAYER_TARGET_CHANGED');events:RegisterEvent('GET_ITEM_INFO_RECEIVED');events:RegisterEvent('MODIFIER_STATE_CHANGED');events:SetScript('OnEvent',function(_,event,id,success)
  if event=='PLAYER_LOGIN' then setupMini();return end
  if event=='MODIFIER_STATE_CHANGED' then
    if detail and detail:IsShown() then for _,row in ipairs(detailRows or {}) do if row:IsShown() and row:IsMouseOver() then local handler=row:GetScript('OnEnter');if handler then handler(row) end;break end end end
    return
  end
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
