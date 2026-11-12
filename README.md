# Noki Forever

A World of Warcraft Forever addon with target range information and an experimental bag-size control.

## Install and update on Windows

Download [Update Noki Forever.bat](https://raw.githubusercontent.com/PyNoki/nokiForever/main/NokiForeverUpdater/Update%20Noki%20Forever.bat), close WoW, and run it. It downloads the current updater and addon from this repository. Confirm the detected Forever folder, or select your World of Warcraft or `_forever_` folder. Run the same file again whenever you want an update.

Open the settings menu with `/noki`, the toolkit's **NOKI SETTINGS** button, or a right-click on the N minimap icon. The menu includes spell selection, bag size, and a party nameplate color dropdown with a preview. Party name colors require accessible friendly nameplates and need in-game testing.

Use `/fra bag 1.25` to enlarge the default bags and `/fra bag 1` to restore normal scale. This feature needs in-game testing and may conflict with other bag addons. `/fra` opens spell selection.

The addon only reports range and does not cast spells. Its range estimates are approximate and depend on client behavior. GitHub's main branch is the update source; changes published there are distributed the next time users run the updater.

## Noki Trading

Noki Trading combines Market, Crafting, auction tracking, scanning, tooltips, and Help in one addon. It works without the AHledger or Auctionator addons. Daily sales estimates come from market data maintained by AHledger (ahledger.com).

[Download Noki Trading 1.0.60](https://github.com/PyNoki/nokiForever/raw/refs/heads/main/NokiTrading-1.0.60.zip). Close WoW, extract the ZIP, and copy the `NokiTrading` folder to `World of Warcraft/_forever_/Interface/AddOns/`. Enable **Noki Trading** at the character screen and disable older Noki Market, Noki Crafting, Noki Trading Core, and unified beta addons.

Hover over the coin beside chat to see the estimated auction value of carried items; drag it to reposition it and click it to configure up to six colored bag-slot rules. Each rule marks items when the difference between the auction and vendor price exceeds a chosen percentage of the auction price. The highest matching threshold takes priority; leave rows blank to disable them. Items without both prices have no marker. The markers do not account for binding, auction fees or deposits. It uses the last scanned price, falling back to the imported auction reference, and reports item stacks without prices. Drag the grip in the combined bag footer to move the window outside combat; its position is saved. The estimate includes bound items and excludes auction fees; prices may be stale. This feature needs in-game testing.

Vendor Flip Finder shows the current character’s active selling quantity beside each item; -- means owned auctions have not finished loading. In Noki Market, select Vendor resale for a shopping list of items whose last scanned auction low is below their known vendor sell price. The list automatically checks live prices and totals the quantity, purchase cost, and vendor profit across all buyable tiers below the vendor price. View waits for the game's item details before opening its buy screen; returning preserves the list position and completed checks. A completed full market scan automatically rebuilds the shopping list and rechecks its candidates. Use Recheck to refresh one item after buying, or Refresh list to rebuild the whole list manually. Item tooltips show the vendor sell value per unit and a vendor purchase price per unit when known. Merchant items use the current merchant price; otherwise the purchase price is an observed vendor reference, which may be stale or unavailable to the character. The auction buy view shows estimated crafting and vendor purchase costs per unit when data is available; hover the cost summary for sources and assumptions. Totals can be unavailable when your own profitable listings cannot be distinguished. Verify current prices, quantity, binding, and vendor acceptance before buying; values and available listings can change.

The Demand tab shows scanned items with their auction low, listed quantity, estimated sales per day, listed-to-sales ratio, gap, and a pressure ranking. Search by name or item ID and click a column heading to sort. The table includes items outside the crafting catalog; missing data appears as `--`. These are snapshots and estimates, not confirmed shortages. Scan and AHledger ages matter.

The Mispriced tab checks individual items from the latest market scan for a gap between their two lowest distinct price tiers. Set a minimum gap and estimated sales/day, maximum low-tier quantity, and maximum cost in gold; blank optional filters are unrestricted. The default minimum is 3,000 estimated sales/day. Enter applies filters, and New scan rebuilds the candidate list after changing search or minimum sales. The scan checks every unambiguous item matching those criteria, in order of estimated activity, and continues automatically while the tab is open. With a sales minimum, items lacking estimated activity cannot be evaluated against it. Live price checks remain subject to auction-house throttling. Results show the live discount relative to the next tier, low-tier quantity and cost, estimated daily sales, and hypothetical profit after a 5% cut if every low-tier unit resells one copper below the next tier. Deposits, new supply, and sales risk are excluded; verify current prices before buying. Incomplete, ambiguous, or own/account results are skipped.

On a Demand row, View opens the normal auction buy screen. The + button requests live price tiers, waiting for a running scan or listing query if needed, highlights the best estimated stopping point, spend, resale price and profit, and shows cataloged recipe uses sorted by required skill. Scroll over the recipe list or use its arrows; the catalog can be incomplete and a star marks trainer requirements to check. The suggested breakpoint maximizes estimated proceeds after a 5% cut, assuming every bought unit resells at one copper below the next tier; deposits and future changes are excluded. The last tier has no next price, so it has no estimated resale profit. Incomplete, ambiguous, or own/account listings prevent a buyout estimate.

The Purchases tab records purchase events while the addon is enabled and shows the average price per item (total divided by quantity). Commodity prices are quotes, not verified payments; missing quantities and prices show as `--`. Earlier purchases and bids won later may not be recorded.

For new listings made through the normal sell screen, Your Auctions saves the displayed deposit when it can match the confirmed listing. Deposits for older listings and ambiguous multi-item posts may be unavailable.

Run `Noki Trading Updater.exe` from the ZIP, choose your region, ruleset and faction, and click **Update now**. Reload the game after updates. The updater also checks for newer addon versions; click **Install addon update** when one is available. For existing beta users, close WoW and use **Migrate old data** before opening the game. Existing saves remain intact. The updater is unsigned and Windows may show a warning.

To import manually, visit https://devvy.xyz/noki-crafting/, choose your market, copy the string, and paste it into **Import data** in Noki Market. The website may still show instructions for the older AHledger addon; use the Noki Market import box. Market estimates are not confirmed sales, and auction deposits and restrictions can affect profit.

Previous standalone Market and Crafting source remains available in [the previous repository revision](https://github.com/PyNoki/nokiForever/tree/e2c7406).
