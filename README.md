<img src="https://raw.githubusercontent.com/miyankooo/SimpleMarketValue/main/.github/icon.png" width="64" height="64" alt="">

# Simple Market Value

Use your Auctionator and TSM price data without shopping in their Auction House UI.

- **Reads** the prices Auctionator and the TSM desktop app store
- **Calculates** each item's 14-day market value itself
- **Shows** every auction price as a % of it, right in Blizzard's Auction House

## Why use it

- **Blizzard's Auction House stays your shop.** The % column sits in its search results, buy and sell lists.
- **Auctionator becomes a data source.** Its price history turns into a 14-day average, weighted like TSM's Market Value.
- **TSM without the TSM addon.** Reads the TSM desktop app's data directly, even with TradeSkillMaster disabled.
- **Deals jump out.** Cheap listings glow green.

## Features

### Relative column

- In Blizzard's auction lists and Auctionator's Shopping and Selling tabs
- Green is a good price, yellow fair, red poor
- Gray rests on fewer than 3 days of prices
- Sort by it to find the cheapest listings

### Tooltips

- **Auctionator:** price age, 14-Day Average, Now vs Average
- **TSM (optional):** region Sale Average, Now vs Sale Avg, Sale Rate

### Highlight Deals

- Deals glow green in Blizzard's and Auctionator's buy lists
- A deal is at least 20% below market value by default
- With TSM, a deal must also sell often: Sale Rate 60% for gear, 80% for other items by default
- The checkbox label counts the deals found

### Selling

- Items worth selling glow green in Auctionator's Selling tab
- **Sale Scan** refreshes the prices of everything in your bags in one click

### Full Scan

- One click on Auctionator's Shopping tab reads the lowest price of every item
- Progress shows on the button, such as Full Scan 42%
- Optional: read every listing for a TSM-style Market Value, the cheapest 15 to 30% of listings without outliers. Blizzard allows it once every 15 minutes.

## How the market value works

- Each day's lowest price from Auctionator
- Averaged over 14 days, newest days counting most, as TSM weighs its Market Value
- With TSM, lists and deals measure against TSM's region Sale Average wherever it has one

## Quick start

1. Open the Auction House
2. Click **Full Scan** on Auctionator's Shopping tab
3. Shop in Blizzard's or Auctionator's lists: green is a deal
4. Type `/smv` for settings, `/smv help` for commands

## Settings

Type `/smv` or pick Simple Market Value in the addon menu.

- Good Buying Price, for gear and for other items
- Good Selling Price
- Minimum TSM Sale Rate, or ignore it
- Full Scan Reads Every Listing

## Requirements

- **Auctionator**, which the CurseForge app installs with it
- **Optional:** the TSM desktop app and the TradeSkillMaster addon
  - Log in once per ruleset and faction with TradeSkillMaster enabled, so the app fetches the right data
  - After that, TradeSkillMaster can stay disabled
  - New TSM data shows after a login or /reload
- The included Simple Market Value TSM helper loads only when TSM is installed
