"""Convert an AHledger loot-db schema 2 export into the beta's Lua data file.

Run with Python and lupa: python build-loot.py loot-db.json NokiTradingBeta/LootData.lua
Existing level references are retained for NPCs found in the new export.
"""
import json
import pathlib
import sys

from lupa import LuaRuntime

source, target = map(pathlib.Path, sys.argv[1:3])
data = json.loads(source.read_text(encoding="utf-8"))
assert data["schemaVersion"] == 2
assert len(data["npcs"]) == data["npcCount"]
assert sum(len(n["items"]) for n in data["npcs"]) == data["itemCount"]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(target.read_text(encoding="utf-8"))
old = lua.globals().NokiTradingLoot.mobs
quote = lambda value: json.dumps(value or "", ensure_ascii=False)
lines = ["-- AHledger loot export; drop rates are observed estimates, not guaranteed.",
         "NokiTradingLoot={snapshot=" + quote(data["generatedAt"]) + ",items={},mobs={}}"]
for key, item in sorted(data["items"].items(), key=lambda x: int(x[0])):
    lines.append("NokiTradingLoot.items[%d]=%s" % (int(key), quote(item["name"])))
for npc in data["npcs"]:
    npc_id = npc["npcId"]
    previous = old[npc_id]
    low = int(previous["min"] or 0) if previous else 0
    high = int(previous["max"] or 0) if previous else 0
    level_source = previous["levelSource"] if previous else None
    locations = []
    for loc in npc.get("locations", []):
        zone, subzone = loc.get("zone") or "", loc.get("subzone") or ""
        value = zone + (" - " + subzone if subzone else "")
        if value and value not in locations:
            locations.append(value)
    lines.append("NokiTradingLoot.mobs[%d]={name=%s,min=%d,max=%d,levelSource=%s,zone=%s,locations={%s},drops={}}" % (
        npc_id, quote(npc["name"]), low, high, quote(level_source), quote(npc.get("zone")), ",".join(map(quote, locations))))
    for drop in npc["items"]:
        rate = drop.get("dropPercent")
        rate_lua = str(rate) if isinstance(rate, (int, float)) else "false"
        lines.append("NokiTradingLoot.mobs[%d].drops[#NokiTradingLoot.mobs[%d].drops+1]={%d,%d,%d,0,%s,%d,%s,%s}" % (
            npc_id, npc_id, drop["itemId"], drop.get("hitCount") or 0, drop.get("sampleCount") or 0,
            quote(drop.get("method")), npc.get("reporters") or 0, "true" if drop.get("lowSample") else "false", rate_lua))
target.write_text("\n".join(lines) + "\n", encoding="utf-8")
print("Generated %d monsters and %d drops" % (len(data["npcs"]), data["itemCount"]))
