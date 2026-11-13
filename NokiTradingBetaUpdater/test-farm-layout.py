"""Simulate the farm window to check selection and tab visibility."""
from pathlib import Path
from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
objects={}; local function new(kind,name,parent)
 local o={scripts={},shown=true,name=name,parent=parent,kind=kind,level=1,checked=false,content=''}
 local methods={SetScript=function(s,k,v)s.scripts[k]=v end,GetScript=function(s,k)return s.scripts[k] end,SetText=function(s,v)s.content=v end,GetText=function(s)return s.content end,SetWidth=function(s,v)s.width=v end,SetSize=function(s,w,h)s.width=w;s.height=h end,SetShown=function(s,v)s.shown=v end,IsShown=function(s)return s.shown end,Hide=function(s)s.shown=false end,Show=function(s)s.shown=true;if s.scripts.OnShow then s.scripts.OnShow(s) end end,GetFrameLevel=function(s)return s.level end,SetFrameLevel=function(s,v)s.level=v end,GetWidth=function(s)return s.width or 1920 end,GetHeight=function(s)return s.height or 1080 end,GetChecked=function(s)return s.checked end,CreateFontString=function(s)return new('font',nil,s)end,CreateTexture=function(s)return new('texture',nil,s)end,IsMouseOver=function()return false end}
 setmetatable(o,{__index=function(_,k)return methods[k] or function() end end});if name then _G[name]=o end;objects[#objects+1]=o;return o
end
CreateFrame=new;UIParent=new('frame','UIParent');UIParent.width=1920;UIParent.height=1080;Minimap=new('frame','Minimap');SlashCmdList={}
NokiBetaCoreDB={prices={x={observed=100,items={[1]={price=100,quantity=3}}}}}
NokiTradingLoot={items={[1]='Test'},mobs={[9]={name='Test mob',min=1,max=2,levelSource='observed',zone='Elwynn Forest',locations={},drops={{1,2,5,0,'corpse',2,false,40}}}}}
NokiUnifiedCore={Market=function()return 'x' end,Subscribe=function()end,FarmZoneLevel=function()end,FarmInZone=function()return true end,FarmValue=function()return {value=10,gross=20,missingPrice=0,missingRate=0,missingActivity=0,missingSupply=0,missingSample=0,stale=0} end}
GetServerTime=function()return 100 end;GetRealZoneText=function()return 'Elwynn Forest' end
''')
lua.execute(Path('NokiTradingBeta/Menu.lua').read_text(encoding='utf-8'))
lua.execute('''
NokiUnifiedCore.OpenTradingMenu('Farm');assert(NokiTradingMenu.width==1300)
local chosen;for _,o in ipairs(objects) do local item=rawget(o,'item');if item and item.id==9 then chosen=o;break end end
assert(chosen and chosen.scripts.OnClick);chosen.scripts.OnClick(chosen)
assert(NokiTradingLootDetails.parent==NokiTradingMenu and NokiTradingLootDetails:IsShown())
NokiUnifiedCore.OpenTradingMenu('Bag');assert(NokiTradingMenu.width==630 and not NokiTradingLootDetails:IsShown())
NokiUnifiedCore.OpenTradingMenu('Farm');assert(NokiTradingMenu.width==1300 and NokiTradingLootDetails:IsShown())
''')
print('Embedded farm detail, selection, and tab sizing passed.')
