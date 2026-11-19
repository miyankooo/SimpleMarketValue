local addonName, AP = ...

-- TSM's figures for an item, read straight from the TSM desktop app's data file, so the TradeSkillMaster addon can be
-- disabled or load in any order: the region sale average (the market value the list percentages measure against
-- wherever it exists), the region sale rate, and how old they are. Never a single auction's price: that comes from
-- Auctionator, which holds what the player saw in the Auction House. The app's AppData.lua hands each block to
-- AP.LoadData, as TradeSkillMaster_AppHelper's own load of the same file hands it to TSM (see Loading below). Every
-- figure is nil without the app's data for this region. Tags, keys, fields and packing as TSM v4.15.6 reads them
-- (LibTSMService AppHelper/AppHelper.lua and AuctionDB/AuctionDB.lua, LibTSMApp Config/AuctionDBConfig.lua)
AP.TSM = {}

-- ===== The region's sale block =====
-- The one block read, the region's sale figures, filed as Forever-<region> or Forever-HC-<region> (LibTSMWoW
-- SessionInfo.lua, LibTSMService AppHelper.lua)
local SALE_TAG = "AUCTIONDB_REGION_SALE"

local function regionKey()
    local hardcore = C_GameRules.IsGameRuleActive(Enum.GameRule.HardcoreRuleset)
    return ((hardcore and "Forever-HC-" or "Forever-") .. GetCurrentRegionName()):lower()
end

-- This region's key, false where the client cannot say; and the block, { fields = field to column, built = time(),
-- body = its rows as text until the first lookup parses them into rows }
local region, sale

-- AppData.lua calls this once per block as select(2, ...).LoadData(tag, realmOrRegion, data). The block is kept as
-- text and parsed at its first lookup, so login pays only for a few string matches
function AP.LoadData(tag, realmOrRegion, data)
    if tag ~= SALE_TAG or type(realmOrRegion) ~= "string" or type(data) ~= "string" then return end
    -- An error here would stop the rest of the file, so an unknown region only means no block matches
    if region == nil then
        local ok, key = pcall(regionKey)
        region = ok and key or false
    end
    if realmOrRegion:lower() ~= region then return end

    -- The payload reads return {downloadTime=...,fields={"itemString",...},data={{item,value,...},...}}
    local _, dataStart = data:find(",data={", 1, true)
    local fieldList = dataStart and data:sub(1, dataStart):match("fields={(.-)}")
    if not fieldList then return end
    -- itemString is the first field and the key of each row, so the nth field is the row's (n - 1)th value
    local fields, column = {}, 0
    for field in fieldList:gmatch('"([^"]+)"') do
        if column > 0 then fields[field] = column end
        column = column + 1
    end
    -- downloadTime is when TSM built the block, the time TSM's own "last updated" goes by (AuctionDB.lua)
    local built = tonumber(data:sub(1, dataStart):match("downloadTime=(%d+)"))
    sale = { fields = fields, built = built, body = data:sub(dataStart + 1, -3) }
end

-- Rows by item string, "i:<itemID>" for a plain item. A variant such as i:259891::i1 also answers for its base item,
-- since the addon looks items up by item ID and TSM falls back to the base item
local function rows()
    if not sale.rows then
        local parsed = {}
        for item, values in sale.body:gmatch('{"?([^,"]+)"?,([^}]+)}') do
            local key = tonumber(item) and ("i:" .. item) or item
            local base = key:match("^i:%d+")
            if base and base ~= key and not parsed[base] then parsed[base] = values end
            parsed[key] = values
        end
        sale.rows, sale.body = parsed, nil
    end
    return sale.rows
end

-- TSM packs each value in base 32 and cuts values over 6 digits in two, since tonumber only holds 32 bits
local function unpack32(packed)
    if #packed > 6 then
        local low, high = tonumber(packed:sub(-6), 32), tonumber(packed:sub(1, -7), 32)
        return low and high and low + high * 2 ^ 30 or 0
    end
    return tonumber(packed, 32) or 0
end

-- An item's field; nil when missing or zero, as TSM's own lookup. A row is unpacked at its first lookup and kept
-- unpacked, as TSM does. Takes a link, an item string or an auction item key
local function value(field, itemRef)
    local column = sale and sale.fields[field]
    local itemID = column and (type(itemRef) == "table" and itemRef.itemID
        or type(itemRef) == "string" and (itemRef:match("item:(%d+)") or itemRef:match("^i:(%d+)")))
    if not itemID then return nil end
    local all, key = rows(), "i:" .. itemID
    local row = all[key]
    if type(row) == "string" then
        local values = { strsplit(",", row) }
        for index, packed in ipairs(values) do values[index] = unpack32(packed) end
        all[key], row = values, values
    end
    local amount = row and row[column]
    return amount and amount > 0 and amount or nil
end

-- ===== Figures =====
-- What the item sold for across the region, in copper (DBRegionSaleAvg)
function AP.TSM.SaleAverage(itemRef)
    return value("regionSale", itemRef)
end

-- The share of the item's auctions that sell across the region, from 0 to 1; the app writes it in thousandths
-- (DBRegionSaleRate)
function AP.TSM.SaleRate(itemRef)
    local permille = value("regionSalePercent", itemRef)
    return permille and permille / 1000
end

-- Whether the app's data for this region carries sale rates, which deals need
function AP.TSM.HasSaleRates()
    return sale ~= nil and sale.fields.regionSalePercent ~= nil
end

-- When TSM built the region's figures, as time(), about daily. Not when the app last synced, which says only that
-- the app looked for news. nil without them
function AP.TSM.BuiltTime()
    return sale and sale.built
end

-- ===== Loading =====
-- AppData.lua lives in TSM's AppHelper folder, which players without TSM do not have, and a toc line naming a missing
-- file raises a Lua warning at every login (seen in game on 2026-11-12). So the file is listed by a load-on-demand
-- helper shipped with the addon, SimpleMarketValue_TSM, loaded only where the AppHelper folder exists, enabled or not
local HELPER, APP_HELPER = "SimpleMarketValue_TSM", "TradeSkillMaster_AppHelper"

-- The helper's first file hands AppData.lua's blocks to this, a global, since add-ons share no tables
function SimpleMarketValue_LoadTSMData(tag, realmOrRegion, data)
    AP.LoadData(tag, realmOrRegion, data)
end

-- Loads the app's data through the helper where TSM's AppHelper folder exists; once, as the client loads an add-on
function AP.TSM.LoadAppData()
    if C_AddOns.DoesAddOnExist(APP_HELPER) and C_AddOns.DoesAddOnExist(HELPER) then
        C_AddOns.LoadAddOn(HELPER)
    end
end

-- At this addon's own load, before login, so the data is there for the first tooltip and the welcome line
EventUtil.ContinueOnAddOnLoaded(addonName, AP.TSM.LoadAppData)
