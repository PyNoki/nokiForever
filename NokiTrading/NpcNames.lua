-- EG Link community observation, CC BY 4.0: https://guide.wow4ever.se/en/npc/260803
-- Keep fixes separate from LootData.lua so database regeneration preserves them.
local mob=NokiTradingLoot and NokiTradingLoot.mobs and NokiTradingLoot.mobs[260803]
if mob and (mob.name=='' or mob.name=='NPC 260803') then
  mob.name='Highland Spider'
  mob.nameSource='EG Link community observation'
end
