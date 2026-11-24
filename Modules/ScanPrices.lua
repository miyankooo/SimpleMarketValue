local addonName, AP = ...

-- While Full Scan Reads Every Listing is ticked, the price of an item in each scan that sees every one of its listings, kept per
-- day for the 14-day average (AP.Trend.AverageFor), which takes Auctionator's lowest buyout of the day on days without
-- one. Two scans see them all: Auctionator's replicate full scan, which reads the whole Auction House, and its searches
-- for one item, from Sale Scan, the Selling tab and the buy screens. Auctionator's incremental scan and the Shopping
-- tab's lists see only each item's lowest price, so they add none. Unticked, the average rests on the lowest buyouts
-- alone, so nothing is recorded
AP.ScanPrices = {}

-- ===== Scan price =====
-- TSM's Market Value of one scan (TSM support, "How is AuctionDB Market Value calculated?", and its AuctionDB
-- data.lua): the cheapest 15% of the units on offer always, more up to 30% until a unit costs 20% or more than the
-- one before; then the band's units within 1.5 standard deviations of its mean, averaged. Buyers buy from the bottom,
-- so the band is where items sell, and the deviation cut drops the odd listing far from the rest, such as a new
-- player's one priced 10% too low
local MIN_SHARE, MAX_SHARE, MAX_JUMP, MAX_DEVIATIONS = 0.15, 0.30, 1.2, 1.5

-- Scratch lists reused by every call: the listings in price order and the units each gives the band
local sorted, taken = {}, {}

local function byPrice(a, b) return a.price < b.price end

-- The scan price of one item from its buyout listings, each { price = unit price in copper, available = units },
-- Auctionator's shape; nil without any. Rounded to the copper. A listing without both numbers is skipped, since this
-- runs inside Auctionator's event dispatch, where an error would also stop the listeners after this one
function AP.ScanPrices.FromListings(listings)
    local count, total = 0, 0
    for _, listing in ipairs(listings) do
        local price, units = listing.price, listing.available
        if type(price) == "number" and type(units) == "number" and price > 0 and units > 0 then
            count = count + 1
            sorted[count] = listing
            total = total + listing.available
        end
    end
    for index = #sorted, count + 1, -1 do sorted[index] = nil end
    if count == 0 then return nil end
    table.sort(sorted, byPrice)

    -- Unit i joins as TSM's loop has it: the first always, any within 15%, and up to 30% while its price is under
    -- 1.2 times the one before. Units of one listing share a price, so a jump can only come at a listing's first unit
    local cap = math.max(1, math.floor(total * MAX_SHARE))
    local units, sum, bandEnd = 0, 0, 0
    for index = 1, count do
        local listing = sorted[index]
        if units >= cap then break end
        if units > 0 and units + 1 > total * MIN_SHARE and listing.price >= MAX_JUMP * sorted[index - 1].price then break end
        local take = math.min(listing.available, cap - units)
        taken[index] = take
        units = units + take
        sum = sum + take * listing.price
        bandEnd = index
    end

    local mean, spread = sum / units, 0
    for index = 1, bandEnd do
        local offset = sorted[index].price - mean
        spread = spread + taken[index] * offset * offset
    end
    -- At most, rather than TSM's under, so a band of one price keeps its units
    local limit, keptUnits, keptSum = MAX_DEVIATIONS * math.sqrt(spread / units), 0, 0
    for index = 1, bandEnd do
        local price = sorted[index].price
        if math.abs(price - mean) <= limit then
            keptUnits = keptUnits + taken[index]
            keptSum = keptSum + taken[index] * price
        end
    end
    return math.floor(keptSum / keptUnits + 0.5)
end

-- ===== Daily store =====
-- Per realm, like Auctionator's own database: price-database key to { s = { [day] = sum of the day's scan prices },
-- n = { [day] = scans that day } }, so a day's price is the mean of its scans, as TSM combines a day's scans. Days are
-- Auctionator's scan days, kept for the 14 days the average looks back
local KEEP_DAYS = 14
local store

-- Auctionator's day index, days since SCAN_DAY_0
function AP.ScanPrices.Today()
    return math.floor((time() - Auctionator.Constants.SCAN_DAY_0) / 86400)
end

-- The key's days, { s = sums, n = scans }; nil without any
function AP.ScanPrices.History(dbKey)
    return store and store[dbKey]
end

local function add(dbKey, price)
    if not (store and price) then return end
    local history = store[dbKey]
    if not history then
        history = { s = {}, n = {} }
        store[dbKey] = history
    end
    local day = AP.ScanPrices.Today()
    history.s[day] = (history.s[day] or 0) + price
    history.n[day] = (history.n[day] or 0) + 1
end

-- Days past the window and keys left empty go at load
EventUtil.ContinueOnAddOnLoaded(addonName, function()
    local db = AP.DB()
    if type(db.scanPrices) ~= "table" then db.scanPrices = {} end
    local realm = AP.Bridge.Realm()
    if type(db.scanPrices[realm]) ~= "table" then db.scanPrices[realm] = {} end
    store = db.scanPrices[realm]

    local oldest = AP.ScanPrices.Today() - KEEP_DAYS
    for dbKey, history in pairs(store) do
        if type(history) ~= "table" or type(history.s) ~= "table" or type(history.n) ~= "table" then
            store[dbKey] = nil
        else
            for day in pairs(history.s) do
                if type(day) ~= "number" or day <= oldest then history.s[day], history.n[day] = nil, nil end
            end
            if next(history.s) == nil then store[dbKey] = nil end
        end
    end
end)

-- ===== Full scan =====
-- The replicate scan hands every auction to Auctionator's database in one ProcessScan call, grouped by key as
-- { price = buyout / count, available = count }, bid-only auctions left out (Source_ModernAH/FullScan/Mixins/Frame.lua,
-- MergeInfo). The incremental scan passes the same shape with each item's lowest price alone, so a call is only read
-- once the full scan reports ScanComplete, which Auctionator fires from that call's callback through its synchronous
-- event bus. A later ProcessScan cancels the running one and its ScanComplete with it, so the call remembered then is
-- always the full scan's
local lastScan
AP.Bridge.AfterProcessScan(function(itemIndexes) lastScan = itemIndexes end)

-- Keys priced per frame, as Auctionator steps through the same data, so a large Auction House never stalls a frame.
-- The first batch waits a frame too, so none of it runs inside Auctionator's own ProcessScan callback
local KEYS_PER_FRAME = 200

local function recordFullScan()
    local itemIndexes, dbKey = lastScan, nil
    lastScan = nil
    if type(itemIndexes) ~= "table" then return end
    local function step()
        for _ = 1, KEYS_PER_FRAME do
            dbKey = next(itemIndexes, dbKey)
            if dbKey == nil then return end
            add(dbKey, AP.ScanPrices.FromListings(itemIndexes[dbKey]))
        end
        C_Timer.After(0, step)
    end
    C_Timer.After(0, step)
end

-- ===== Item searches =====
-- Auctionator reports a search as ready once results exist, which for a large market can be the first page only, so
-- only a complete set counts. A commodity listing carries its unit price
local function recordCommodity(itemID)
    if type(itemID) ~= "number" or not C_AuctionHouse.HasFullCommoditySearchResults(itemID) then return end
    local listings = {}
    for index = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
        local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
        if result then listings[#listings + 1] = { price = result.unitPrice, available = result.quantity } end
    end
    local price = AP.ScanPrices.FromListings(listings)
    for _, dbKey in ipairs(AP.Bridge.DBKeys(C_AuctionHouse.MakeItemKey(itemID)) or {}) do add(dbKey, price) end
end

-- An item search can answer with several variants, such as gear suffixes, so each listing joins the keys of its own
-- item, as the replicate scan files them. The buyout is the item's price, as Auctionator reads it; a bid-only listing
-- says nothing about the price an item sells for at once
local function recordItems(itemKey)
    if type(itemKey) ~= "table" or not C_AuctionHouse.HasFullItemSearchResults(itemKey) then return end
    local groups = {}
    for index = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
        local result = C_AuctionHouse.GetItemSearchResultInfo(itemKey, index)
        if result and result.buyoutAmount then
            local listing = { price = result.buyoutAmount, available = result.quantity }
            for _, dbKey in ipairs(AP.Bridge.DBKeys(result.itemKey) or {}) do
                local group = groups[dbKey]
                if not group then
                    group = {}
                    groups[dbKey] = group
                end
                group[#group + 1] = listing
            end
        end
    end
    for dbKey, listings in pairs(groups) do add(dbKey, AP.ScanPrices.FromListings(listings)) end
end

-- Registered before Sale Scan's own listener, so a bag item's price is in when Sale Scan repaints the bag glow
AP.Bridge.Listen({
    Auctionator.FullScan.Events.ScanComplete,
    Auctionator.AH.Events.CommoditySearchResultsReady,
    Auctionator.AH.Events.ItemSearchResultsReady,
}, function(_, eventName, payload)
    if not AP.DB().scanEveryListing then return end
    if eventName == Auctionator.FullScan.Events.ScanComplete then
        recordFullScan()
    elseif eventName == Auctionator.AH.Events.CommoditySearchResultsReady then
        recordCommodity(payload)
    else
        recordItems(payload)
    end
end)
