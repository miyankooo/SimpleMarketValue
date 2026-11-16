local _, AP = ...

-- "Highlight Deals", a checkbox beside Full Scan on Auctionator's Shopping tab. While it is ticked, deals past the Deal
-- Threshold glow green in the buy lists, Blizzard's and Auctionator's alike, and great deals gold; unticked, no row
-- glows. A great deal is at least its kind's threshold under the market value, the items' (weapons and armor) or the
-- commodities'; with the TSM app it must also sell at least its kind's sale rate (AP.Trend.IsGreatDeal). The label
-- counts the great deals in the Shopping tab's results. The choice is saved, like a filter, and starts ticked
AP.GreatDeals = {}

local LABEL = "Highlight Deals"

-- Space between the checkbox and Full Scan, the gap between related controls
local GAP = 8

-- Blizzard's own row highlight, the glow deal rows take in every buy list: green for a deal, the gold of Blizzard's
-- headings for a great deal, so both show at once
local GLOW_ATLAS = "auctionhouse-ui-row-highlight"
AP.GreatDeals.DEAL_COLOR, AP.GreatDeals.GREAT_COLOR = GREEN_FONT_COLOR, NORMAL_FONT_COLOR

-- Auctionator's buy lists, by the global name of the frame holding each: shopping results, and the buy screens of one
-- item and of one commodity. Auctionator makes them on or shortly after the first Auction House visit
local LISTING_HOLDERS = { "AuctionatorShoppingFrame", "AuctionatorBuyItemFrame", "AuctionatorBuyCommodityFrame" }
local COUNTED_HOLDER = "AuctionatorShoppingFrame"

local checkbox
local attached = {}

function AP.GreatDeals.IsOn()
    return AP.DB().greatDeals ~= false
end

-- ===== Auctionator's rows =====
-- Per-row state lives here, keyed by Auctionator's rows, never on their frames
local WEAK = { __mode = "k" }
local glows, paintedData, paintedRevision = setmetatable({}, WEAK), setmetatable({}, WEAK), setmetatable({}, WEAK)

local function glowFor(row)
    local glow = glows[row]
    if not glow then
        -- Over the row stripe Auctionator draws in OVERLAY at sublevel 0
        glow = row:CreateTexture(nil, "OVERLAY", nil, 1)
        glow:SetAtlas(GLOW_ATLAS)
        glow:SetAllPoints()
        glow:SetBlendMode("ADD")
        glows[row] = glow
    end
    return glow
end

-- The switch and the settings revision of the pass under way, read once per frame instead of once per row
local passOn, passRevision

-- The Relative column marks deals and great deals on each entry as it decorates it, so a row only reads its marks,
-- and only on a change of its entry or of a setting
local function paintRow(row)
    local rowData = row.rowData
    if paintedData[row] == rowData and paintedRevision[row] == passRevision then return end
    paintedData[row], paintedRevision[row] = rowData, passRevision

    local entry = passOn and type(rowData) == "table" and rowData or nil
    local great = entry ~= nil and entry.apGreatDeal == true
    if great or (entry and entry.apDeal) then
        local glow = glowFor(row)
        glow:SetVertexColor((great and AP.GreatDeals.GREAT_COLOR or AP.GreatDeals.DEAL_COLOR):GetRGB())
        glow:Show()
    elseif glows[row] then
        glows[row]:Hide()
    end
end

-- The label with the number of great deals in the Shopping tab's results, counted again only when those results or a
-- setting change; the plain label while there are no results
local countedResults, countedSize, countedRevision

local function updateCount(provider)
    if not checkbox then return end
    local results = provider and provider.results
    local size = type(results) == "table" and #results or 0
    if results == countedResults and size == countedSize and countedRevision == AP.settingsRevision then return end
    countedResults, countedSize, countedRevision = results, size, AP.settingsRevision

    local label = LABEL
    if size > 0 then
        local great = 0
        for index = 1, size do
            if results[index].apGreatDeal then great = great + 1 end
        end
        label = ("%s (%d)"):format(LABEL, great)
    end
    checkbox.Text:SetText(label)
    checkbox:SetHitRectInsets(0, -(4 + checkbox.Text:GetStringWidth()), 0, 0)
end

-- One painter per listing, a child of it, so it only runs while the listing shows; true once all are in place
local function attachListings()
    local done = true
    for _, holderName in ipairs(LISTING_HOLDERS) do
        local holder = _G[holderName]
        local listing = holder and holder.ResultsListing
        local scrollBox = listing and listing.ScrollArea and listing.ScrollArea.ScrollBox
        if not attached[holderName] and scrollBox then
            local provider = holderName == COUNTED_HOLDER and holder.DataProvider or nil
            local painter = CreateFrame("Frame", nil, listing)
            painter:SetScript("OnUpdate", function()
                passOn, passRevision = AP.GreatDeals.IsOn(), AP.settingsRevision
                scrollBox:ForEachFrame(paintRow)
                if provider then updateCount(provider) end
            end)
            attached[holderName] = true
        end
        done = done and attached[holderName] == true
    end
    return done
end

-- ===== Checkbox =====
local function fillTooltip(tooltip)
    GameTooltip_SetTitle(tooltip, LABEL)
    local db, rule = AP.DB()
    if AP.TSM.HasSaleRates() then
        rule = ("commodities priced at least %d%% below TSM's sale average that TSM sees sell at least %d%% of "
            .. "the time, and items at least %d%% below that sell at least %d%% of the time"):format(
            db.greatDealCommodityPct, db.greatDealCommodityRatePct, db.greatDealGearPct, db.greatDealGearRatePct)
    else
        rule = ("commodities priced at least %d%% and items at least %d%% below Auctionator's 14-day average")
            :format(db.greatDealCommodityPct, db.greatDealGearPct)
    end
    GameTooltip_AddNormalLine(tooltip, "Ticked, deals past your Deal Threshold glow green in every buy list and great "
        .. "deals gold: " .. rule .. ". The number counts the great deals in these results. Type /smv to change the "
        .. "thresholds.")
end

-- To the right of Full Scan, on the Export Results row, with its parent, so it hides whenever a buy screen covers the
-- results; true once the checkbox and every listing painter are in place
function AP.GreatDeals.Ensure()
    local listingsReady = attachListings()
    if checkbox then return listingsReady end
    local scanButton = AP.FullScanButton.Button()
    if not scanButton then return false end

    checkbox = AP.CreateCheckbox(scanButton:GetParent(), LABEL)
    checkbox:SetPoint("LEFT", scanButton, "RIGHT", GAP, 0)
    checkbox:SetChecked(AP.GreatDeals.IsOn())
    AP.AttachTooltip(checkbox, fillTooltip)
    -- The template plays no sound, so the click plays the checkbox sounds Blizzard's options use
    checkbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        AP.DB().greatDeals = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        AP.SettingsChanged()
    end)
    return listingsReady
end
