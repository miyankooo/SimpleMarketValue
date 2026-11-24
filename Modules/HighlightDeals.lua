local _, AP = ...

-- "Highlight Deals", a checkbox beside Full Scan on Auctionator's Shopping tab. While it is ticked, deals glow green in
-- the buy lists, Blizzard's and Auctionator's alike; unticked, no row glows. A deal is at least its kind's Good Buying
-- Price under the market value, gear's or other items', and with the TSM app sells at least its kind's Minimum TSM Sale
-- Rate unless the kind ignores it (AP.Trend.IsDeal). The label counts the deals in the Shopping tab's results. The
-- choice is saved, like a filter, and starts ticked
AP.HighlightDeals = {}

local LABEL = "Highlight Deals"

-- Space between the checkbox and Full Scan, the gap between related controls
local GAP = 8

-- Blizzard's own row highlight, the glow deal rows take in every buy list, in the green of a deal's percentage
local GLOW_ATLAS = "auctionhouse-ui-row-highlight"
AP.HighlightDeals.DEAL_COLOR = GREEN_FONT_COLOR

-- Auctionator's buy lists, by the global name of the frame holding each: shopping results, and the buy screens of one
-- item and of one commodity. Auctionator makes them on or shortly after the first Auction House visit
local LISTING_HOLDERS = { "AuctionatorShoppingFrame", "AuctionatorBuyItemFrame", "AuctionatorBuyCommodityFrame" }
local COUNTED_HOLDER = "AuctionatorShoppingFrame"

local checkbox
local attached = {}

function AP.HighlightDeals.IsOn()
    return AP.DB().highlightDeals ~= false
end

-- ===== Auctionator's rows =====
-- Per-row glows live here, keyed by Auctionator's rows, never on their frames
local glows = setmetatable({}, { __mode = "k" })

-- The Relative column marks deals on each entry as it decorates it, so a row only reads its mark. Runs each time its
-- listing lays the row out, which every listing does again for all its rows once a setting changes, the switch
-- included, since the column then works the entries out again (TrendColumn.lua)
local function paintRow(_, row)
    local rowData = row.rowData
    if AP.HighlightDeals.IsOn() and type(rowData) == "table" and rowData.apDeal then
        local glow = glows[row]
        if not glow then
            -- Over the row stripe Auctionator draws in OVERLAY at sublevel 0
            glow = row:CreateTexture(nil, "OVERLAY", nil, 1)
            glow:SetAtlas(GLOW_ATLAS)
            glow:SetAllPoints()
            glow:SetBlendMode("ADD")
            glow:SetVertexColor(AP.HighlightDeals.DEAL_COLOR:GetRGB())
            glows[row] = glow
        end
        glow:Show()
    elseif glows[row] then
        glows[row]:Hide()
    end
end

-- The label with the number of deals in the Shopping tab's results, counted each time the listing shows them anew;
-- the plain label while there are none
local function updateCount()
    local provider = _G[COUNTED_HOLDER] and _G[COUNTED_HOLDER].DataProvider
    local results = provider and provider.results
    local size = type(results) == "table" and #results or 0
    local label = LABEL
    if size > 0 then
        local deals = 0
        for index = 1, size do
            if results[index].apDeal then deals = deals + 1 end
        end
        label = ("%s (%d)"):format(LABEL, deals)
    end
    checkbox.Text:SetText(label)
    checkbox:SetHitRectInsets(0, -(4 + checkbox.Text:GetStringWidth()), 0, 0)
end

-- Each listing paints a row as its scroll box lays it out, after Auctionator has filled it in; the shopping results
-- also count their deals after every update. True once all are in place
local function attachListings()
    local done = true
    for _, holderName in ipairs(LISTING_HOLDERS) do
        local holder = _G[holderName]
        local listing = holder and holder.ResultsListing
        local scrollBox = listing and listing.ScrollArea and listing.ScrollArea.ScrollBox
        if not attached[holderName] and scrollBox then
            ScrollUtil.AddInitializedFrameCallback(scrollBox, paintRow, AP)
            if holderName == COUNTED_HOLDER then
                hooksecurefunc(listing, "UpdateTable", function() if checkbox then updateCount() end end)
            end
            attached[holderName] = true
        end
        done = done and attached[holderName] == true
    end
    return done
end

-- ===== Checkbox =====
-- One kind's rule, such as "gear at least 20% below it", and where its Minimum TSM Sale Rate counts, the rate it must
-- sell at
local function kindRule(kind, items, below, rates)
    local db = AP.DB()
    local rule = ("%s at least %d%% below %s"):format(items, db[kind.deal], below)
    if rates and not db[kind.ignore] then
        rule = rule .. (" that TSM sees sell at least %d%% of the time"):format(db[kind.rate])
    end
    return rule
end

local function fillTooltip(tooltip)
    GameTooltip_SetTitle(tooltip, LABEL)
    local rates = AP.TSM.HasSaleRates()
    local average = rates and "TSM's sale average" or "Auctionator's 14-day average"
    GameTooltip_AddNormalLine(tooltip, "Ticked, deals glow green in every buy list: "
        .. kindRule(AP.Trend.GEAR, "gear", average, rates) .. ", and "
        .. kindRule(AP.Trend.OTHER, "all other items", "it", rates)
        .. ". The number counts the deals in these results. Type /smv to change what counts as a deal.")
end

-- On the Export Results row after Full Scan, with its parent, so it hides whenever a buy screen
-- covers the results; true once the checkbox and every listing are in place
function AP.HighlightDeals.Ensure()
    local listingsReady = attachListings()
    if checkbox then return listingsReady end
    local scanButton = AP.FullScanButton.Button()
    if not scanButton then return false end

    checkbox = AP.CreateCheckbox(scanButton:GetParent(), LABEL)
    checkbox:SetPoint("LEFT", scanButton, "RIGHT", GAP, 0)
    checkbox:SetChecked(AP.HighlightDeals.IsOn())
    AP.AttachTooltip(checkbox, fillTooltip)
    -- The template plays no sound, so the click plays the checkbox sounds Blizzard's options use
    checkbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        AP.DB().highlightDeals = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        AP.SettingsChanged()
    end)
    updateCount()
    return listingsReady
end
