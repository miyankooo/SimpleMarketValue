local _, AP = ...

-- The addon's page in Blizzard's Settings window, under Options > AddOns

local function plusPercent(value) return ("+%d%%"):format(value) end
local function minusPercent(value) return ("-%d%%"):format(value) end
local function percent(value) return ("%d%%"):format(value) end

-- Sections in display order; a row is key, label, help, then for a slider its min, max, step and value formatter, and
-- a row marked checkbox is a checkbox instead. A row marked tsm only applies with the TSM app's sale rates and greys
-- out without them; a sale rate slider also greys out while its kind's Ignore TSM Sale Rate, the key in ignore, is
-- ticked. Labels say what a row sets in the player's words, so the page reads without its tooltips
local SECTIONS = {
    { "Scanning", {
        { "scanEveryListing", "Full Scan Reads Every Listing", "Unticked, Full Scan reads the lowest price of each item, as often as you like, and the market value averages each day's lowest price. Ticked, it reads every listing, once every 15 minutes, and the market value averages the cheapest 15 to 30% of each item's listings, as TSM does, so a single underpriced listing cannot pull it down.", checkbox = true },
    } },
    { "Selling", {
        { "sellThresholdPct", "Good Selling Price", "While you sell, a price at least this far above the market value shows green, and the item glows green in Auctionator's Selling tab. As far below shows red, anything between yellow.", 5, 100, 1, plusPercent },
    } },
    { "Buying Gear", {
        { "gearDealPct", "Good Buying Price", "While you buy weapons, armor or profession tools, a price at least this far below the market value shows green and counts as a deal, which glows green in the buy lists while Highlight Deals is ticked on Auctionator's Shopping tab. As far above shows red.", 5, 100, 1, minusPercent },
        { "gearSaleRatePct", "Minimum TSM Sale Rate", "With the TSM desktop app, gear only counts as a deal when TSM sees it sell at least this often in your region, so gear that rarely sells never glows. Gear sells less often than goods sold in stacks.", 0, 100, 1, percent, tsm = true, ignore = "gearIgnoreSaleRate" },
        { "gearIgnoreSaleRate", "Ignore TSM Sale Rate", "Ticked, gear counts as a deal by its price alone, however rarely TSM sees it sell.", checkbox = true, tsm = true },
    } },
    { "Buying Other Items", {
        { "otherDealPct", "Good Buying Price", "While you buy anything but gear, such as cloth, herbs and potions, a price at least this far below the market value shows green and counts as a deal, which glows green in the buy lists while Highlight Deals is ticked on Auctionator's Shopping tab. As far above shows red.", 5, 100, 1, minusPercent },
        { "otherSaleRatePct", "Minimum TSM Sale Rate", "With the TSM desktop app, anything but gear only counts as a deal when TSM sees it sell at least this often in your region, so an item that rarely sells never glows.", 0, 100, 1, percent, tsm = true, ignore = "otherIgnoreSaleRate" },
        { "otherIgnoreSaleRate", "Ignore TSM Sale Rate", "Ticked, anything but gear counts as a deal by its price alone, however rarely TSM sees it sell.", checkbox = true, tsm = true },
    } },
}

-- What the addon does, where it works and what the colours mean, before any row asks for a choice. One paragraph, so
-- the intro and the four sections fit the 601 px canvas; the rows' tooltips carry the rest
local INTRO = "Shows every auction price as a percentage above or below its market value, the 14-day average of your "
    .. "scans, in item tooltips, Auctionator's tabs and Blizzard's auction lists. Green marks a good price by the "
    .. "settings below, red a poor one, yellow one in between and gray one with under 3 days of scans. With the TSM "
    .. "desktop app, TSM's region sale average is the market value wherever it has one."

-- The addon's page in Blizzard's Settings window, as its own canvas, copying the settings list's look
-- (Blizzard_SettingsList.xml:14-30, Blizzard_SettingControls.xml, Blizzard_SettingControls.lua). Never a settings
-- list: a pick in a list dropdown runs addon code in Blizzard's pooled controls and taints its settings until /reload.
local ROW_HEIGHT, ROW_SPACING, LABEL_X, INTRO_Y, INTRO_GAP = 26, 9, 37, -64, 16
local categoryID

local function BuildPanel(introText, restoreDefaults)
    local panel = CreateFrame("Frame")
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    title:SetJustifyH("LEFT")
    title:SetPoint("TOPLEFT", 7, -22)
    title:SetText(AP.title)
    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    divider:SetPoint("TOP", 0, -50)
    local defaults = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    defaults:SetSize(96, 22)
    defaults:SetPoint("TOPRIGHT", -36, -16)
    defaults:SetText(SETTINGS_DEFAULTS)
    defaults:SetScript("OnClick", restoreDefaults)
    panel.intro = AP.CreateText(panel, GameFontHighlight)
    panel.intro:SetPoint("TOPLEFT", LABEL_X, INTRO_Y)
    panel.intro:SetPoint("TOPRIGHT", -LABEL_X, INTRO_Y)
    panel.intro:SetText(introText)
    return panel
end

-- One row below the previous one, its label in GameFontNormal from x 37 to the row's centre less 85. Its slider, a
-- MinimalSliderWithSteppersTemplate 250 wide, starts at the row's CENTER -40, 3 up. `above` is panel.intro for the
-- first row.
local CONTROL_X, SLIDER_WIDTH = -40, 250
local function AddRow(panel, above, label, fillTooltip)
    local gap = above == panel.intro and INTRO_GAP or ROW_SPACING
    local row = CreateFrame("Frame", nil, panel)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", above, "BOTTOMLEFT", above == panel.intro and -LABEL_X or 0, -gap)
    row:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", above == panel.intro and LABEL_X or 0, -gap)
    row:EnableMouse(true)
    AP.AttachTooltip(row, fillTooltip)
    row.label = AP.CreateText(row, GameFontNormal)
    row.label:SetPoint("LEFT", LABEL_X, 0)
    row.label:SetPoint("RIGHT", row, "CENTER", -85, 0)
    row.label:SetText(label)
    return row
end

-- Blizzard's section header for a group of rows: a 45 px slot, the title in GameFontHighlightLarge at 7, -16
-- (Blizzard_SettingControls.xml:12-20). The next row anchors below it with `above` set to the header.
local function AddSectionHeader(panel, above, title)
    local header = CreateFrame("Frame", nil, panel)
    header:SetHeight(45)
    header:SetPoint("TOPLEFT", above, "BOTTOMLEFT", above == panel.intro and -LABEL_X or 0, 0)
    header:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", above == panel.intro and LABEL_X or 0, 0)
    local text = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    text:SetJustifyH("LEFT")
    text:SetPoint("TOPLEFT", 7, -16)
    text:SetText(title)
    return header
end

local function RegisterPanel(panel)
    local category = Settings.RegisterCanvasLayoutCategory(panel, AP.title)
    Settings.RegisterAddOnCategory(category)
    categoryID = category:GetID()
end

-- Opening in combat waits for combat to end, since the settings panel's open path has restrictions.
local waitingForCombat = false
function AP.OpenSettings()
    if not categoryID then return end
    if InCombatLockdown() then
        AP.Print("Opens after combat.")
        if not waitingForCombat then
            waitingForCombat = true
            EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_REGEN_ENABLED", function()
                waitingForCombat = false
                AP.OpenSettings()
            end)
        end
        return
    end
    Settings.OpenToCategory(categoryID)
end

-- The slider Blizzard's own settings use. Its Init takes a step count, not a step size.
local function CreateSlider(parent, width, name)
    local slider = CreateFrame("Frame", name, parent, "MinimalSliderWithSteppersTemplate")
    slider:SetWidth(width)
    return slider
end

-- Blizzard's settings slider row lifts the slider 3 px (SettingsSliderControlMixin:OnLoad, Blizzard_SettingControls.lua:715)
local SLIDER_Y = 3

-- Each control by its setting key, and each sale rate row with its slider and the Ignore TSM Sale Rate key it follows
local controls, rateRows = {}, {}

local function setValue(key, value)
    AP.DB()[key] = value
    -- Painted glows and colours depend on the thresholds and the market value
    AP.SettingsChanged()
    if key == "sellThresholdPct" or key == "scanEveryListing" then AP.BagGlow.Repaint() end
end

-- A greyed row says why it is off in a red line, as Blizzard's dungeon finder does
local function fillFor(def)
    return function(tooltip)
        GameTooltip_SetTitle(tooltip, def[2])
        GameTooltip_AddNormalLine(tooltip, def[3])
        if def.tsm and not AP.TSM.HasSaleRates() then
            GameTooltip_AddErrorLine(tooltip, "Needs the TSM desktop app's data.")
        elseif def.ignore and AP.DB()[def.ignore] then
            GameTooltip_AddErrorLine(tooltip, "Off while Ignore TSM Sale Rate is ticked.")
        end
    end
end

-- A row that does not apply greys out, as Blizzard's settings list does: label in GRAY_FONT_COLOR, control disabled
local function SetRowEnabled(row, control, enabled)
    row.label:SetTextColor((enabled and NORMAL_FONT_COLOR or GRAY_FONT_COLOR):GetRGB())
    control:SetEnabled(enabled)
end

-- A sale rate row applies with the TSM app's sale rates while its kind's Ignore TSM Sale Rate is unticked. The app's data
-- loads with the addon, before the page is built, and stays for the session
local function refreshRateRows()
    local rates, db = AP.TSM.HasSaleRates(), AP.DB()
    for _, rateRow in ipairs(rateRows) do
        SetRowEnabled(rateRow.row, rateRow.slider, rates and not db[rateRow.ignore])
    end
end

local function addSlider(panel, above, def)
    local key, label, _, minValue, maxValue, step, formatter = unpack(def)
    local fill = fillFor(def)
    local row = AddRow(panel, above, label, fill)
    local slider = CreateSlider(row, SLIDER_WIDTH)
    slider:SetPoint("LEFT", row, "CENTER", CONTROL_X, SLIDER_Y)
    slider:Init(AP.DB()[key], minValue, maxValue, (maxValue - minValue) / step, {
        [MinimalSliderWithSteppersMixin.Label.Right] = formatter,
    })
    if def.ignore then rateRows[#rateRows + 1] = { row = row, slider = slider, ignore = def.ignore } end
    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        -- Whole steps, whatever fraction the step division leaves
        setValue(key, math.floor(value + 0.5))
    end, row)
    -- The template's slider sets its own OnEnter, so the tooltip hooks it
    slider.Slider:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        fill(GameTooltip)
        GameTooltip:Show()
    end)
    slider.Slider:HookScript("OnLeave", GameTooltip_Hide)
    controls[key] = slider
    return row, slider
end

-- Blizzard's settings checkbox at the controls' edge. A click on the row ticks it too, as SettingsCheckboxControlMixin
-- has it (Blizzard_SettingControls.lua:616-620); the template plays no sound, so a change plays the checkbox sounds
-- Blizzard's options use. Its tooltip fills SettingsTooltip, the one the template shows
local function addCheckbox(panel, above, def)
    local key, label = def[1], def[2]
    local fill = fillFor(def)
    local row = AddRow(panel, above, label, fill)
    local checkbox = CreateFrame("CheckButton", nil, row, "SettingsCheckboxTemplate")
    checkbox:SetPoint("LEFT", row, "CENTER", CONTROL_X, 0)
    checkbox:Init(AP.DB()[key], function() fill(SettingsTooltip) end)
    checkbox:RegisterCallback(SettingsCheckboxMixin.Event.OnValueChanged, function(_, checked)
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        setValue(key, checked)
        refreshRateRows()
    end, row)
    row:SetScript("OnMouseUp", function()
        if checkbox:IsEnabled() then checkbox:Click() end
    end)
    if def.tsm then SetRowEnabled(row, checkbox, AP.TSM.HasSaleRates()) end
    controls[key] = checkbox
    return row, checkbox
end

local function restoreDefaults()
    local db = AP.DB()
    for key, value in pairs(AP.Defaults) do
        db[key] = value
        controls[key]:SetValue(value)
    end
    refreshRateRows()
    AP.SettingsChanged()
    AP.BagGlow.Repaint()
end

EventUtil.ContinueOnPlayerLogin(function()
    local panel = BuildPanel(INTRO, restoreDefaults)
    local above = panel.intro
    for _, section in ipairs(SECTIONS) do
        local title, rows = unpack(section)
        above = AddSectionHeader(panel, above, title)
        for _, def in ipairs(rows) do
            above = (def.checkbox and addCheckbox or addSlider)(panel, above, def)
        end
    end
    refreshRateRows()
    RegisterPanel(panel)
end)

-- One long command and the short alias /smv. The bare command opens the settings; help and intro are the shared words, and any other word prints the hint.
SLASH_SIMPLEMARKETVALUE1, SLASH_SIMPLEMARKETVALUE2 = "/simplemarketvalue", "/smv"
SlashCmdList.SIMPLEMARKETVALUE = function(message)
    local command = strtrim(message or ""):lower()
    if command == "" then
        AP.OpenSettings()
    elseif command == "help" or command == "?" then
        AP.Print("Type /smv for the settings, /smv intro to see the welcome line and the tip again, or /smv help for this list.")
    elseif command == "intro" then
        AP.ReplayIntro()
    else
        AP.Print("Unknown command. Type /smv help for the list.")
    end
end

-- Addon Compartment entry points named in the toc. Blizzard calls them with the addon name first, then the menu row.
function SimpleMarketValue_CompartmentClick()
    AP.OpenSettings()
end

function SimpleMarketValue_CompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    GameTooltip_SetTitle(GameTooltip, AP.title)
    GameTooltip_AddInstructionLine(GameTooltip, "Click to open the settings.")
    GameTooltip:Show()
end

function SimpleMarketValue_CompartmentLeave()
    GameTooltip:Hide()
end
