local _, AP = ...

-- The relative value: a price against the item's market value. That is the 14-day average of its daily prices, from
-- Auctionator's own history and, while Full Scan Reads Every Listing is ticked, the addon's scan prices (AP.ScanPrices); for
-- players who run the TSM app too, TSM's region sale average wherever TSM has one
AP.Trend = {}

-- ===== The 14-day average =====
-- TSM's weights for a day's price by its age in days, today first, the table its AuctionDB data.lua weighs its
-- Market Value with, so the newest 3 days carry about half and the newest 7 about four fifths. A fresh realm's prices
-- move fast, so recent days count most. Age 14, TSM's last, falls outside the window the average looks back
local DAY_WEIGHTS = { [0] = 132, 125, 100, 75, 45, 34, 33, 38, 28, 21, 15, 10, 7, 5 }

-- An average built from fewer days of prices says little, so its percentage shows in grey and moves no glow
AP.Trend.MIN_DAYS = 3

-- The average price for one price-database key, the weighted mean of its daily prices inside the window, and the
-- days it rests on; nil without any. A day's price is Auctionator's lowest buyout of that day, what its default scan
-- reads. While Full Scan Reads Every Listing is ticked, a day where a scan saw every listing takes that scan price instead, and
-- the other days keep the lowest buyout, so every item Auctionator has priced keeps an average, Auctionator being the
-- one required source. A day without either is left out, its weight with it, so the days that have a price share the
-- whole weight and no price is made up, as TSM skips them
local function averageFor(dbKey)
    local history = AP.DB().scanEveryListing and AP.ScanPrices.History(dbKey)
    local today = AP.ScanPrices.Today()
    local total, weights, days = 0, 0, 0
    if history then
        for day, sum in pairs(history.s) do
            local weight, scans = DAY_WEIGHTS[today - day], history.n[day]
            if weight and scans and scans > 0 then
                total = total + weight * sum / scans
                weights = weights + weight
                days = days + 1
            end
        end
    end
    for _, entry in ipairs(AP.Bridge.PriceHistory(dbKey)) do
        local day, lowest = tonumber(entry.rawDay), tonumber(entry.minSeen)
        local weight = day and DAY_WEIGHTS[today - day]
        if weight and lowest and lowest > 0 and not (history and history.n[day]) then
            total = total + weight * lowest
            weights = weights + weight
            days = days + 1
        end
    end
    if weights == 0 then return nil end
    return { math.floor(total / weights + 0.5), days }
end

-- Averages of this frame, false for keys without history. A listing decorates every row of one item in one pass, so they share one history build. Shortcut: cleared next frame, so prices recorded later never read stale, but distinct items still build their history each time; a cache cleared when a scan price comes in would cover that
local frameAverages

local function cachedAverage(dbKey)
    if not frameAverages then
        frameAverages = {}
        C_Timer.After(0, function() frameAverages = nil end)
    end
    if frameAverages[dbKey] == nil then
        frameAverages[dbKey] = averageFor(dbKey) or false
    end
    return frameAverages[dbKey] or nil
end

-- First key with usable history, so a suffix or item-level key measures against its own market before the pooled
-- base item, matching Auctionator's price lookups, the days of history behind it and that key
function AP.Trend.AverageFor(itemRef)
    for _, dbKey in ipairs(AP.Bridge.DBKeys(itemRef) or {}) do
        local average = cachedAverage(dbKey)
        if average and average[1] > 0 then return average[1], average[2], dbKey end
    end
    return nil
end

-- Browse rows carry an item key, item rows a link and commodity rows only an item id
function AP.Trend.RefFor(entry)
    if entry.itemLink then return entry.itemLink end
    if entry.itemKey then return entry.itemKey end
    if entry.itemID then return AP.Bridge.BaseItemKey(entry.itemID) end
    return nil
end

-- ===== Relative value =====
-- Colour modes: UP_GREEN for selling (an increase is good), UP_RED for buying
AP.Trend.UP_GREEN = "upGreen"
AP.Trend.UP_RED = "upRed"

-- Header of the percentage column in Auctionator's and Blizzard's lists
AP.Trend.HEADER = "Relative"

-- Whole-percent deviation of currentPrice from average; nil when either input is unusable
function AP.Trend.Percent(currentPrice, average)
    if type(currentPrice) ~= "number" or currentPrice <= 0 then return nil end
    if type(average) ~= "number" or average <= 0 then return nil end
    return math.floor((currentPrice - average) / average * 100 + 0.5)
end

-- ===== Kinds =====
-- The settings of each kind a buyer's deal goes by, by their keys: gear, meaning weapons, armor and profession tools,
-- and all other items
AP.Trend.GEAR = { deal = "gearDealPct", rate = "gearSaleRatePct", ignore = "gearIgnoreSaleRate" }
AP.Trend.OTHER = { deal = "otherDealPct", rate = "otherSaleRatePct", ignore = "otherIgnoreSaleRate" }

-- The item's kind by Auctionator's own rule for gear, from the item's class, which the client knows without loading
-- the item; an item key or a link, anything else counting as another item
local function kindOf(itemRef)
    local itemID = type(itemRef) == "table" and itemRef.itemID
        or type(itemRef) == "string" and tonumber(itemRef:match("item:(%d+)"))
    local gear = itemID and AP.Bridge.IsEquipment(select(6, C_Item.GetItemInfoInstant(itemID)))
    return gear and AP.Trend.GEAR or AP.Trend.OTHER
end

-- "+N%" / "-N%" / "0%" in the colour of its distance from the market value: green from the threshold the glows use on
-- the good side of mode (the Good Selling Price for a seller, the Good Buying Price of the item's kind for a buyer), red as
-- far on the bad side, yellow in between, so green figures match the price a deal needs. Grey when fewer than MIN_DAYS
-- of history back it; nil pct yields nil so callers can skip an empty trend
function AP.Trend.Colorize(pct, mode, days, itemRef)
    if type(pct) ~= "number" then return nil end

    local text = pct == 0 and "0%" or string.format("%+d%%", pct)
    if days and days < AP.Trend.MIN_DAYS then return GRAY_FONT_COLOR:WrapTextInColorCode(text) end
    local db = AP.DB()
    local seller = mode == AP.Trend.UP_GREEN
    local threshold = seller and db.sellThresholdPct or db[kindOf(itemRef).deal]
    local gain = seller and pct or -pct
    local color = gain >= threshold and GREEN_FONT_COLOR or gain <= -threshold and RED_FONT_COLOR or YELLOW_FONT_COLOR
    return color:WrapTextInColorCode(text)
end

-- The item's market value, which every percentage in the auction lists measures against: TSM's region sale average
-- where the TSM app has one for the item, with no days; otherwise Auctionator's 14-day average and the days of
-- history behind it. So a player without TSM, and any item TSM has no figure for, rests on Auctionator alone
function AP.Trend.MarketValue(itemRef)
    local saleAverage = AP.TSM.SaleAverage(itemRef)
    if saleAverage then return saleAverage, nil end
    local average, days = AP.Trend.AverageFor(itemRef)
    return average, days
end

-- A price against the item's market value, in the colours of mode. Returns the coloured text, the percentage and
-- whether enough data backs it for a glow, which a thin Auctionator history does not; nil text without a market value
function AP.Trend.Relative(price, itemRef, mode)
    local value, days = AP.Trend.MarketValue(itemRef)
    local pct = AP.Trend.Percent(price, value)
    return AP.Trend.Colorize(pct, mode, days, itemRef), pct, pct ~= nil and (days == nil or days >= AP.Trend.MIN_DAYS)
end

-- ===== Deals =====
-- A sale rate of 0.779 as the whole percent 78, the figure the tooltip shows and colours and deals go by
function AP.Trend.SalePercent(rate)
    return rate and math.floor(rate * 100 + 0.5)
end

-- Whether a buyer's percentage from AP.Trend.Relative makes a deal, the rows Highlight Deals lights, by the settings
-- of the item's kind: trusted, and at least the kind's Good Buying Price under the market value. With the TSM app's sale
-- rates loaded, TSM must also see the item sell at least the kind's Minimum TSM Sale Rate, unless the kind ignores it, so an item
-- that rarely sells is no deal however cheap. Auctionator alone knows no sale rate, so it asks for none
function AP.Trend.IsDeal(pct, trusted, itemRef)
    if not trusted then return false end
    local db, kind = AP.DB(), kindOf(itemRef)
    if pct > -db[kind.deal] then return false end
    if db[kind.ignore] or not AP.TSM.HasSaleRates() then return true end
    local salePercent = AP.Trend.SalePercent(AP.TSM.SaleRate(itemRef))
    return salePercent ~= nil and salePercent >= db[kind.rate]
end

-- ===== The player's side =====
local function shown(frame)
    return frame and frame:IsVisible()
end

-- The player's side in the view that shows, the same rule as the lists: a seller outside the Auction House, while
-- posting and among their own auctions, a buyer while browsing, buying and among their bids
function AP.Trend.Mode()
    local ah = AuctionHouseFrame
    if not shown(ah) then return AP.Trend.UP_GREEN end
    local auctions = ah.AuctionsFrame
    if shown(AuctionatorSellingFrame) or shown(AuctionatorCancellingFrame) or shown(ah.ItemSellFrame) or shown(ah.CommoditiesSellFrame)
        or (shown(auctions) and not auctions:IsDisplayingBids()) then
        return AP.Trend.UP_GREEN
    end
    return AP.Trend.UP_RED
end
