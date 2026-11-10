# Noki Forever

A World of Warcraft Forever addon with target range information and an experimental bag-size control.

## Install and update on Windows

Download [Update Noki Forever.bat](https://raw.githubusercontent.com/PyNoki/nokiForever/main/NokiForeverUpdater/Update%20Noki%20Forever.bat), close WoW, and run it. It downloads the current updater and addon from this repository. Confirm the detected Forever folder, or select your World of Warcraft or `_forever_` folder. Run the same file again whenever you want an update.

Open the settings menu with `/noki`, the toolkit's **NOKI SETTINGS** button, or a right-click on the N minimap icon. The menu includes spell selection, bag size, and a party nameplate color dropdown with a preview. Party name colors require accessible friendly nameplates and need in-game testing.

Use `/fra bag 1.25` to enlarge the default bags and `/fra bag 1` to restore normal scale. This feature needs in-game testing and may conflict with other bag addons. `/fra` opens spell selection.

The addon only reports range and does not cast spells. Its range estimates are approximate and depend on client behavior. GitHub's main branch is the update source; changes published there are distributed the next time users run the updater.

## Noki Trading

Noki Trading combines Market, Crafting, auction tracking, scanning, tooltips, and Help in one addon. It works without the AHledger or Auctionator addons. Daily sales estimates come from market data maintained by AHledger (ahledger.com).

[Download Noki Trading 1.0.6](https://github.com/PyNoki/nokiForever/raw/refs/heads/main/NokiTrading-1.0.6.zip). Close WoW, extract the ZIP, and copy the `NokiTrading` folder to `World of Warcraft/_forever_/Interface/AddOns/`. Enable **Noki Trading** at the character screen and disable older Noki Market, Noki Crafting, Noki Trading Core, and unified beta addons.

Run `Noki Trading Updater.exe` from the ZIP, choose your region, ruleset and faction, and click **Update now**. Reload the game after updates. The updater also checks for newer addon versions; click **Install addon update** when one is available. For existing beta users, close WoW and use **Migrate old data** before opening the game. Existing saves remain intact. The updater is unsigned and Windows may show a warning.

To import manually, visit https://devvy.xyz/noki-crafting/, choose your market, copy the string, and paste it into **Import data** in Noki Market. The website may still show instructions for the older AHledger addon; use the Noki Market import box. Market estimates are not confirmed sales, and auction deposits and restrictions can affect profit.

Previous standalone Market and Crafting source remains available in [the previous repository revision](https://github.com/PyNoki/nokiForever/tree/e2c7406).
