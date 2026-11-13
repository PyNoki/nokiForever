"""Exercise the farming ranking model with lupa (run from the repository root)."""
from pathlib import Path
from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('NokiUnifiedCore={}; GetServerTime=function() return 100000 end')
lua.execute(Path('NokiTradingBeta/FarmValue.lua').read_text(encoding='utf-8'))
lua.execute('''
local c=NokiUnifiedCore
local drop={1,2,58,0,'corpse',1,false,3.4}
local function market(price,sales,listed)
  return {price=price,listed=listed,activity={sales=sales,observed=99999}}
end
local zero,_,weight=c.FarmDropScore(drop,market(200000,0,50))
assert(zero==0 and weight==0, 'zero demand must not inflate score')
local slow=c.FarmDropScore(drop,market(200000,1,100))
local fast=c.FarmDropScore(drop,market(200000,100,100))
local moreSupply=c.FarmDropScore(drop,market(200000,100,1000))
assert(fast>slow and fast>moreSupply and slow>zero, 'demand and supply monotonicity')
local missing,why=c.FarmDropScore(drop,market(100,1,nil));assert(missing==nil and why=='supply')
local noSales,noReason=c.FarmDropScore(drop,{price=100,listed=10});assert(noSales==nil and noReason=='activity')
local bad,reason=c.FarmDropScore({1,9,2,0,'corpse',0,false,20},market(100,1,1));assert(bad==nil and reason=='sample')
local _,_,_,lower=c.FarmDropScore(drop,market(200000,100,100));assert(lower>0 and lower<2/58)
local missingRate={2,0,0,0,'corpse',0,true,false}
local mob={drops={drop,missingRate}}
local result=c.FarmValue(mob,function()return market(200000,0,10) end)
assert(result.value==0 and result.gross==6800 and result.missingRate==1 and result.scored==1)
local partial=c.FarmValue(mob,function()return {price=200000,listed=10} end)
assert(partial.value==nil and partial.gross==6800 and partial.missingActivity==1)
''')
print('Farm score tests passed.')
