# Noki Forever

A World of Warcraft Forever addon with target range information and an experimental bag-size control.

## Install and update on Windows

Download [Update Noki Forever.bat](https://raw.githubusercontent.com/PyNoki/nokiForever/main/NokiForeverUpdater/Update%20Noki%20Forever.bat), close WoW, and run it. It downloads the current updater and addon from this repository. Confirm the detected Forever folder, or select your World of Warcraft or `_forever_` folder. Run the same file again whenever you want an update.

Open the settings menu with `/noki`, the toolkit's **NOKI SETTINGS** button, or a right-click on the N minimap icon. The menu includes spell selection, bag size, and a party nameplate color dropdown with a preview. Party name colors require accessible friendly nameplates and need in-game testing.

Use `/fra bag 1.25` to enlarge the default bags and `/fra bag 1` to restore normal scale. This feature needs in-game testing and may conflict with other bag addons. `/fra` opens spell selection.

Turn on Fishing Pool Detection in Noki settings to automatically enable Find Fish when available and scan nearby pools. The settings show when Find Fish is unavailable or a scan cannot be verified. Markers are approximate recent observations, not proof a pool is still active; missing markers do not mean no pools exist. Find Fish must be learned, and enabling it may change the active minimap tracking type. This English-name prototype depends on minimap probing that recent Forever builds may restrict, and needs in-game testing.

The addon only reports range and does not cast spells. Its range estimates are approximate and depend on client behavior. GitHub's main branch is the update source; changes published there are distributed the next time users run the updater.

Marketeer Forever (previously Noki Trading) has moved to [its own repository](https://github.com/PyNoki/Marketeer-Forever).
