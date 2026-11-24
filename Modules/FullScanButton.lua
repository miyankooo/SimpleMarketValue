local _, AP = ...

-- "Full Scan" on Auctionator's Shopping tab: starts the full scan Full Scan Reads Every Listing picks, Auctionator's incremental
-- scan of each item's lowest price or its replicate scan of every listing, and shows the scan's progress in its label.
-- While Blizzard holds the next replicate scan back it greys out, and its tooltip says for how long and when the last
-- full scan on the realm finished
AP.FullScanButton = {}

local BUTTON_LABEL = "Full Scan"

-- Fixed, so the progress label never resizes the button or moves the checkbox after it
local BUTTON_WIDTH = 112

-- How long the final percentage stays before the label returns to Full Scan
local RESULT_SECONDS = 2

-- The first step for a new player: prices before any percentage can show
local TIP_TEXT = "Click Full Scan to load today's prices for every percentage and average."

local scanButton, showTip, waitTimer, resetTimer
local lastPercent = 0

-- The scan's label from its start until its result has shown, nil while idle, so a button made mid-scan shows it too
local scanLabel

-- When each realm's last full scan finished, as time()
local function lastScans()
    local db = AP.DB()
    if type(db.lastFullScan) ~= "table" then db.lastFullScan = {} end
    return db.lastFullScan
end

-- A wait in whole minutes, rounded up, as Auctionator's own message counts them
local function minutesOf(seconds)
    return math.ceil(seconds / 60)
end

local function stopWaiting()
    if waitTimer then
        waitTimer:Cancel()
        waitTimer = nil
    end
end

-- Enabled once Auctionator would start a scan, else greyed; while it shows and waits, one timer enables it again
local function refresh()
    stopWaiting()
    if not scanButton then return end
    local wait = AP.Bridge.FullScanWait()
    scanButton:SetEnabled(wait == 0)
    if wait > 0 and scanButton:IsVisible() then waitTimer = C_Timer.NewTimer(wait, refresh) end
end

local function setLabel(text)
    scanLabel = text
    if scanButton then scanButton:SetText(text or BUTTON_LABEL) end
end

local function cancelReset()
    if resetTimer then
        resetTimer:Cancel()
        resetTimer = nil
    end
end

local function percentLabel(percent)
    return ("%s %d%%"):format(BUTTON_LABEL, percent)
end

local function showProgress(percent)
    cancelReset()
    lastPercent = percent
    setLabel(percentLabel(percent))
end

-- Green at 100% after a finished scan, red at the reached percentage after a failed one, then back to Full Scan
local function showResult(percent, color)
    cancelReset()
    setLabel(color:WrapTextInColorCode(percentLabel(percent)))
    resetTimer = C_Timer.NewTimer(RESULT_SECONDS, function()
        resetTimer = nil
        setLabel(nil)
    end)
end

-- Both scan modes report the same steps under their own event names, with progress as a fraction
local SCAN_STEPS = { "ScanStart", "ScanProgress", "ScanComplete", "ScanFailed" }
local stepOf, scanEvents = {}, {}
for _, events in ipairs({ Auctionator.FullScan.Events, Auctionator.IncrementalScan.Events }) do
    for _, step in ipairs(SCAN_STEPS) do
        local eventName = events[step]
        if eventName then
            stepOf[eventName] = step
            scanEvents[#scanEvents + 1] = eventName
        end
    end
end

AP.Bridge.Listen(scanEvents, function(_, eventName, progress)
    local step = stepOf[eventName]
    if step == "ScanStart" then
        showProgress(0)
    elseif step == "ScanProgress" then
        showProgress(math.min(99, math.floor((progress or 0) * 100)))
        return
    elseif step == "ScanComplete" then
        lastScans()[AP.Bridge.Realm()] = time()
        showResult(100, GREEN_FONT_COLOR)
    else
        showResult(lastPercent, RED_FONT_COLOR)
    end
    refresh()
end)

-- Full Scan Reads Every Listing decides whether the button waits
AP.OnSettingsChanged(refresh)

-- Blizzard's yellow glowing callout, the one the Auction House uses for its undercut tip
-- (Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseSellFrame.lua:507), as an own HelpTipTemplate frame on the
-- target. HelpTip:Show would take a frame from Blizzard's shared pool, and writing to that pool from addon code would
-- taint the help tips Blizzard shows later. It shows each time the target shows until the player closes it or uses
-- the feature, then never again on the account; it hides with the target without being marked. Reset runs before
-- every Init: only Blizzard's pool resets a tip, and Init leaves `acknowledged` set (HelpTip.lua:419-431, 495, 687),
-- so a tip closed once and brought back by /smv intro would count as seen when it merely hides with its target.
local function AttachTip(target, text, targetPoint, relativeRegion)
    local tip
    local info = {
        text = text,
        buttonStyle = HelpTip.ButtonStyle.Close,
        targetPoint = targetPoint,
        onAcknowledgeCallback = function() AP.DB().tipSeen = true end,
    }
    local function ShowTip()
        if AP.DB().tipSeen or (tip and tip:IsShown()) then return end
        if not tip then
            tip = CreateFrame("Frame", nil, target, "HelpTipTemplate")
            tip.width = HelpTip.width
            tip:SetWidth(tip.width)
        end
        tip:Reset()
        tip:Init(target, info, relativeRegion or target)
        tip:Show()
    end
    target:HookScript("OnShow", ShowTip)
    -- Auctionator's button can be made while its tab already shows, so it gets no OnShow of its own
    if target:IsVisible() then ShowTip() end

    -- The player used the feature: the tip goes for good, shown or not.
    local function Retire()
        if tip and tip.info then tip:Acknowledge() else AP.DB().tipSeen = true end
    end
    return ShowTip, Retire
end

-- The button once placed, for the Highlight Deals checkbox after it; nil before
function AP.FullScanButton.Button()
    return scanButton
end

-- /smv intro brings the tip back now while Full Scan shows, otherwise at its next show
function AP.FullScanButton.ShowTip()
    if showTip and scanButton:IsVisible() then showTip() end
end

-- Bottom-left of the results inset, on the Export Results row. Parented to that button so it hides with it whenever a
-- buy screen covers the results
function AP.FullScanButton.Ensure()
    if scanButton then return true end
    local shoppingFrame = AuctionatorShoppingFrame
    local inset = shoppingFrame and shoppingFrame.ShoppingResultsInset
    local exportButton = shoppingFrame and shoppingFrame.ExportCSV
    if not inset or not exportButton then return false end

    local button = AP.CreateButton(exportButton, scanLabel or BUTTON_LABEL, BUTTON_WIDTH)
    AP.AttachTooltip(button, function(tooltip)
        GameTooltip_SetTitle(tooltip, BUTTON_LABEL)
        GameTooltip_AddNormalLine(tooltip, AP.DB().scanEveryListing
            and "Reads every listing on the Auction House through Auctionator's full scan, so every price and average is current. The Auction House allows one every 15 minutes."
            or "Reads the lowest price of every item on the Auction House through Auctionator's full scan, so every price and average is current.")
        local last = lastScans()[AP.Bridge.Realm()]
        GameTooltip_AddNormalLine(tooltip, last and ("Last full scan: %s ago."):format(AP.Age(last))
            or "No full scan on this realm yet.")
        local wait = AP.Bridge.FullScanWait()
        if wait > 0 then
            GameTooltip_AddErrorLine(tooltip, ("Next full scan in %d |4minute:minutes;."):format(minutesOf(wait)))
        end
        if AP.Bridge.BlockedBySearch() then
            GameTooltip_AddErrorLine(tooltip, "Wait for the shopping search to finish first.")
        end
    end)
    -- Greyed while it waits, it still explains itself
    button:SetMotionScriptsWhileDisabled(true)
    button:SetPoint("LEFT", inset, "LEFT", 0, 0)
    button:SetPoint("BOTTOM", exportButton, "BOTTOM", 0, 0)
    -- Above the button, where the results list leaves room
    local retireTip
    showTip, retireTip = AttachTip(button, TIP_TEXT, HelpTip.Point.TopEdgeCenter)
    button:SetScript("OnClick", function()
        retireTip()
        if not AP.Bridge.BlockedBySearch() then AP.Bridge.StartFullScan() end
    end)
    button:HookScript("OnShow", refresh)
    button:HookScript("OnHide", stopWaiting)

    scanButton = button
    refresh()
    return true
end
