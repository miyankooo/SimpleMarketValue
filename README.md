<img src="https://raw.githubusercontent.com/miyankooo/SimpleMarketValue/main/.github/icon.png" width="64" height="64" alt="">

# Simple Market Value

A WoW Forever addon that shows every auction price as a percentage of its market value, so you see at a glance what is a deal and what is worth selling. The market value is the 14-Day Average, worked out as TSM works out its Market Value: each scan averages the cheapest 15 to 30% of an item's listings, without the odd listing far from the rest, such as one a new player priced too low, and the last 14 days of scans combine with the newest days counting most. A day without such a scan takes Auctionator's lowest price of that day, so every item Auctionator has priced shows an average. It works in Auctionator and in Blizzard's Auction House. It needs only Auctionator, which the CurseForge app installs with it. If you also run the TSM desktop app, it adds TSM's sale data on top and measures against TSM's region Sale Average.

## Features

- A Relative column in Auctionator's Shopping and Selling tabs, on its buy screens for items and commodities, and in Blizzard's auction lists, where it sits beside the item name in search results.
- Every percentage is green for a good price, yellow for a fair one and red for a poor one, by your Deal Threshold while you shop and your Sell Threshold while you sell.
- Item tooltips add an Auctionator section right under Auctionator's own Vendor and Auction lines: how old its price is, the 14-Day Average, and Now vs Average, the percentage of the latest lowest buyout against it.
- Highlight Deals, a checkbox beside Full Scan, lights deals green and great deals gold in every buy list, Blizzard's and Auctionator's. Great deals are items priced at least your Commodity Threshold, or for items, meaning weapons and armor, your Item Threshold, below their market value, 20% by default for both. Its label counts the great deals in your Shopping results; untick it and no row glows.
- Items worth selling glow green in Auctionator's Selling tab.
- Sale Scan refreshes the prices of everything in your bags with one click.
- A Full Scan button on Auctionator's Shopping tab reads every listing on the Auction House, with its progress on the button. The Auction House allows one every 15 minutes, so in between the button shows the minutes left, and its tooltip says how long ago the last full scan was.
- Optional, with the TSM desktop app: the tooltip adds a TSM section with the region Sale Average, what the item actually sold for, Now vs Sale Avg, the percentage of the same latest lowest buyout against it, and the Sale Rate (green from 80%, yellow from 60%, orange from 40%, red below). Great deals must then also sell at least your Commodity Sale Rate, 80% by default, or for items your Item Sale Rate, 60% by default, and great deals and the Relative column in the auction lists measure against TSM's Sale Average wherever TSM has one.

## Usage

1. Open the Auction House and click Full Scan in Auctionator's Shopping tab, or Sale Scan in its Selling tab, so prices exist.
2. Hover an item to see its market value. A gray percentage rests on fewer than 3 days of scans.
3. Browse and shop as usual. With Highlight Deals ticked, green rows are deals and gold rows great deals. Sort by Relative to find the cheapest listings.
4. Type `/smv`, or pick Simple Market Value in the addon menu, to set the Sell Threshold and the Deal Threshold, which decide both the colours and the glows, and, for Highlight Deals, a threshold and a sale rate each for commodities and for items. `/smv help` lists the commands.

- For the TSM section, install the TSM desktop app and the TradeSkillMaster addon, and log in with the addon enabled once per ruleset and faction, so the app knows which data to fetch. After that the section shows even while the TradeSkillMaster addon is disabled. New data shows after a login or /reload.
- The download includes Simple Market Value TSM, a small helper that reads the TSM app's data. It loads only when TSM is installed, so without TSM it does nothing.
