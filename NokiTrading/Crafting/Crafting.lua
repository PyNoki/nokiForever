-- Captures learned recipes visible in the classic profession window and ranks them
-- against the current auction scan. Recipe data is character-scoped.
local function characterKey()
  return (GetRealmName() or "?") .. "|" .. (UnitName("player") or "?")
end
-- Bring forward books captured before crafting became a separate addon.
-- PLAYER_LOGIN runs after enabled addons have loaded their saved variables.
local function migrateBooks()
  if not NokiUnifiedCraftDB or type(NokiMarketDB)~="table" or type(NokiMarketDB.crafting)~="table" then return end
  NokiUnifiedCraftDB.crafting=NokiUnifiedCraftDB.crafting or {}
  local copied=0
  local function copy(value)
    if type(value)~="table" then return value end
    local result={}; for k,v in pairs(value) do result[k]=copy(v) end; return result
  end
  for character,books in pairs(NokiMarketDB.crafting) do
    if type(books)=="table" then
      NokiUnifiedCraftDB.crafting[character]=NokiUnifiedCraftDB.crafting[character] or {}
      for profession,book in pairs(books) do
        if type(book)=="table" and not NokiUnifiedCraftDB.crafting[character][profession] then
          NokiUnifiedCraftDB.crafting[character][profession]=copy(book); copied=copied+1
        end
      end
    end
  end
  if copied>0 then print("Noki crafting: imported "..copied.." saved profession books from Noki Market.") end
end
local migrationFrame=CreateFrame("Frame")
migrationFrame:RegisterEvent("PLAYER_LOGIN")
migrationFrame:SetScript("OnEvent",migrateBooks)
local function idFromLink(link, kind)
  return type(link)=="string" and tonumber(link:match(kind .. ":(%d+)")) or nil
end
local function captureModern()
  if not C_TradeSkillUI or not C_TradeSkillUI.GetAllRecipeIDs or not C_TradeSkillUI.GetRecipeInfo then return false end
  if not NokiUnifiedCraftDB or not NokiUnifiedCraftCraftCatalog or not NokiUnifiedCraftCraftCatalog.recipes then return false end
  local ok, ids=pcall(C_TradeSkillUI.GetAllRecipeIDs)
  if not ok or type(ids)~="table" or #ids==0 then
    print("Noki crafting: open a profession window and wait for its recipes to load."); return true
  end
  local groups, unknown={},0
  for _,id in ipairs(ids) do
    local recipe=NokiUnifiedCraftCraftCatalog.recipes[id]
    local success,info=pcall(C_TradeSkillUI.GetRecipeInfo,id)
    if not success or type(info)~="table" then
      print("Noki crafting: profession data incomplete; no capture was saved. Try again.");return true
    end
    if recipe and recipe.profession then
      local group=groups[recipe.profession] or {recipes={}}
      groups[recipe.profession]=group
      if info.learned == true then group.recipes[id]={id=id,name=info.name or recipe.name}; end
    else unknown=unknown+1 end
  end
  if not next(groups) then print("Noki crafting: none of this profession's recipes match the local catalog; no capture saved.");return true end
  NokiUnifiedCraftDB.crafting=NokiUnifiedCraftDB.crafting or {}
  local key=characterKey();NokiUnifiedCraftDB.crafting[key]=NokiUnifiedCraftDB.crafting[key] or {}
  local count=0
  for profession,book in pairs(groups) do
    book.observed=(GetServerTime and GetServerTime()) or time()
    NokiUnifiedCraftDB.crafting[key][profession]=book
    for _ in pairs(book.recipes) do count=count+1 end
  end
  print("Noki crafting: captured "..count.." learned recipes; "..unknown.." recipes not in local catalog. Data reflects the current profession window; recipe restrictions still need checking.")
  return true
end
local function capture()
  if captureModern() then return end
  if not NokiUnifiedCraftDB or not GetTradeSkillLine or not GetNumTradeSkills or not GetTradeSkillInfo or not GetTradeSkillItemLink or not GetTradeSkillNumMade or not GetTradeSkillNumReagents or not GetTradeSkillReagentInfo or not GetTradeSkillReagentItemLink then
    print("Noki crafting: profession API unavailable."); return
  end
  local profession, skill = GetTradeSkillLine()
  if not profession or profession == "UNKNOWN" then print("Noki crafting: open a profession window first."); return end
  local count=GetNumTradeSkills()
  if not count or count == 0 then print("Noki crafting: no visible recipes; expand the profession categories and try again."); return end
  NokiUnifiedCraftDB.crafting=NokiUnifiedCraftDB.crafting or {}
  local characters=NokiUnifiedCraftDB.crafting
  characters[characterKey()]=characters[characterKey()] or {}
  local character=characters[characterKey()]
  character[profession]=character[profession] or {recipes={}}
  local book=character[profession]
  book.skill=skill; book.observed=(GetServerTime and GetServerTime()) or time()
  local saved, incomplete=0,0
  for i=1,count do
    local name, kind=GetTradeSkillInfo(i)
    if name and kind~="header" then
      local output=idFromLink(GetTradeSkillItemLink(i),"item")
      local link=GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i)
      local recipeID=idFromLink(link,"enchant") or idFromLink(link,"spell")
      local minMade,maxMade=GetTradeSkillNumMade(i)
      local number=GetTradeSkillNumReagents(i)
      local materials, complete={},true
      if type(number)~="number" or number<1 then complete=false else
        for j=1,number do
          local reagentName,_,qty=GetTradeSkillReagentInfo(i,j)
          local id=idFromLink(GetTradeSkillReagentItemLink(i,j),"item")
          if not id or type(qty)~="number" or qty<=0 then complete=false; break end
          materials[#materials+1]={id=id,name=reagentName or ("Item #"..id),quantity=qty}
        end
      end
      if recipeID and output and type(minMade)=="number" and minMade>0 and (maxMade == nil or (type(maxMade)=="number" and maxMade>=minMade)) and complete then
        book.recipes[recipeID]={id=recipeID,name=name,output=output,yieldMin=minMade,yieldMax=maxMade,materials=materials}
        saved=saved+1
      else incomplete=incomplete+1 end
    end
  end
  print("Noki crafting: captured "..saved.." visible "..profession.." recipes at skill "..tostring(skill or "?").."; skipped "..incomplete.." incomplete or non-item recipes. Expand collapsed categories and capture again. Required recipe skill and binding are not available here.")
end
local function money(n)
  if not n then return "?" end
  return string.format("%.2fc",n)
end
function NokiUnifiedCraftCraftCandidates(minProfitSilver,minSales,match,knownOnly,budget,professionFilter)
  if not NokiUnifiedCraftDB then return {}, "Database not ready" end
  local books=NokiUnifiedCraftDB.crafting and NokiUnifiedCraftDB.crafting[characterKey()]
  books=books or {}
  local catalog=NokiUnifiedCraftCraftCatalog and NokiUnifiedCraftCraftCatalog.recipes
  if not catalog or not next(catalog) then return {}, "Recipe catalog is empty" end
  local key=(GetRealmName() or "Unknown realm").." - "..(UnitFactionGroup("player") or "Unknown faction")
  local market=NokiUnifiedCraftDB.markets and NokiUnifiedCraftDB.markets[key]
  local scans=market and market.scans or {}
  local scan=market and (market.latestScan or scans[#scans])
  if not scan or not scan.rows or scan.source=="noki_beta_browse" then return {}, "No completed auction scan" end
  local activityMarket,activityError=NokiUnifiedCraftActivityMarket()
  if not activityMarket then return {},activityError end
  local prices, variants, quantities, quantityUnknown={},{},{},{}
  for _,row in ipairs(scan.rows) do
    if row.itemID and type(row.price)=="number" and row.price>0 and (row.itemSuffix or 0)==0 and (row.battlePetSpeciesID or 0)==0 then
      local id=row.itemID
      local variant=tostring(row.itemLevel or 0)..":"..tostring(row.itemSuffix or 0)..":"..tostring(row.battlePetSpeciesID or 0)
      variants[id]=variants[id] or {}; variants[id][variant]=true
      if type(row.quantity)~="number" or row.quantity<0 then quantityUnknown[id]=true
      elseif quantities[id]~=nil and quantities[id]~=row.quantity then quantityUnknown[id]=true
      else quantities[id]=row.quantity end
      if not prices[id] or row.price<prices[id] then prices[id]=row.price end
    end
  end
  for id,keys in pairs(variants) do local n=0; for _ in pairs(keys) do n=n+1 end; if n>1 then prices[id]=nil end end
  local results={};local missing,activity,failed,unknownYield,review,overBudget=0,0,0,0,0,0
  local eligible,missingSales,zeroSales,belowSales=0,0,0,0
  local activityInfo=nil
  for recipeID,recipe in pairs(catalog) do
    local book=books[recipe.profession]
    local known=book and book.recipes and book.recipes[recipeID] ~= nil
    if (not professionFilter or recipe.profession==professionFilter) and (not knownOnly or known) then
      eligible=eligible+1
      local low=prices[recipe.output];local cost=0
      for _,mat in ipairs(recipe.materials) do if not prices[mat.id] then cost=nil;break else cost=cost+prices[mat.id]*mat.quantity end end
      local remote=NokiUnifiedCraftActivity(recipe.output,activityMarket)
      if remote and (not activityInfo or (remote.observed and (not activityInfo.observed or remote.observed<activityInfo.observed))) then activityInfo=remote end
      local sales=remote and remote.sales
      if recipe.review then review=review+1
      elseif not recipe.yieldMin or not recipe.yieldMax then unknownYield=unknownYield+1
      elseif not low or not cost then missing=missing+1
      elseif budget and cost>budget then overBudget=overBudget+1
      elseif type(sales)~="number" then activity=activity+1; missingSales=missingSales+1
      elseif sales<=0 then activity=activity+1; zeroSales=zeroSales+1
      elseif sales<minSales then activity=activity+1; belowSales=belowSales+1
      else
        local sell=math.floor(low)-(match and 0 or 1)
        local gainMin=recipe.yieldMin*sell*0.95-cost
        local gainMax=recipe.yieldMax*sell*0.95-cost
        if sell>=1 and gainMax>0 and gainMax>=minProfitSilver*100 then
          local listed=not quantityUnknown[recipe.output] and quantities[recipe.output] or nil
          results[#results+1]={recipe=recipe,profession=recipe.profession,skill=recipe.required,known=known,cost=cost,sell=sell,gainMin=gainMin,gainMax=gainMax,conditional=gainMin<=0 or gainMin<minProfitSilver*100,sales=sales,listed=listed,gap=listed~=nil and sales-listed or nil,prices=prices}
        else failed=failed+1 end
      end
    end
  end
  table.sort(results,function(a,b) if a.conditional~=b.conditional then return not a.conditional end; if a.gainMin~=b.gainMin then return a.gainMin>b.gainMin end; return a.recipe.id<b.recipe.id end)
  return results, nil, {scan=scan.completed, activity=activityInfo and activityInfo.observed, activityInfo=activityInfo, market=activityMarket, eligible=eligible, missing=missing, review=review, unknownYield=unknownYield, activityExcluded=activity, missingSales=missingSales, zeroSales=zeroSales, belowSales=belowSales, failed=failed, overBudget=overBudget}
end
function NokiUnifiedCraftCaptureRecipes() capture() end
local function find(minProfitSilver,minSales,match,knownOnly)
  local results,err,stats=NokiUnifiedCraftCraftCandidates(minProfitSilver,minSales,match,knownOnly)
  if err then print("Noki crafting: "..err);return end
  print("Noki crafting: "..#results.." candidates | "..(knownOnly and "CAPTURED KNOWN" or "ALL RECIPES"))
  for i=1,math.min(10,#results) do
    local r=results[i]
    print(i..". "..r.recipe.name.." ["..r.profession.."] | cost "..money(r.cost).." | gain "..money(r.gainMin).." to "..money(r.gainMax).."/craft | est. "..r.sales.." units/day")
  end
  print("Noki crafting: AH material lows, 5% cut, no deposits. Verify sellability, cooldowns and demand. Prices from AHledger (ahledger.com).")
end
SLASH_NOKIUNIFIEDCRAFTCRAFT1="/nokiunimcraft"
SlashCmdList.NOKIUNIFIEDCRAFTCRAFT=function(msg)
  local args={};for s in (msg or ""):gmatch("%S+") do args[#args+1]=s:lower() end
  if args[1]=="capture" then capture();return end
  if args[1]=="find" then
    local profit=tonumber(args[2] or "0");local sales=tonumber(args[3] or "1")
    if not profit or not sales or profit<0 or sales<0 or (args[4] and args[4]~="match" and args[4]~="under") or (args[5] and args[5]~="known" and args[5]~="all") then print("Noki crafting: /nmcraft find [min profit silver] [min sales/day] [under|match] [all|known]");return end
    find(profit,sales,args[4]=="match",args[5]=="known");return
  end
  print("Noki crafting: /nmcraft capture (open profession and expand categories); /nmcraft find [min profit silver] [min sales/day] [under|match] [all|known].")
end
