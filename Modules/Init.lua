local addonName, AP = ...

-- The toc Title, the addon's in-game name, for chat lines, the settings page and the addon menu
AP.title = C_AddOns.GetAddOnMetadata(addonName, "Title")

-- Setting defaults; the settings panel uses the same keys as its variable keys
AP.Defaults = {
    sellThresholdPct = 15,
    -- Buying, per kind, gear and all other items: a deal is 20% under the market value at a TSM sale rate of 60% for
    -- gear, which sells less often, and 80% for the rest. On a full scan of Forever's EU auction house (2026-11-15),
    -- 20% matched 19 items at 80% and 104 at 60%
    gearDealPct = 20,
    gearSaleRatePct = 60,
    gearIgnoreSaleRate = false,
    otherDealPct = 20,
    otherSaleRatePct = 80,
    otherIgnoreSaleRate = false,
}

-- Up to 2.6.0 a deal's thresholds and sale rates were kept per commodity and item, beside one Deal Threshold for the
-- rest; the per-kind ones and the Highlight Deals switch carry over to the new keys once, and the old keys go
local RENAMED = {
    greatDealGearPct = "gearDealPct",
    greatDealGearRatePct = "gearSaleRatePct",
    greatDealCommodityPct = "otherDealPct",
    greatDealCommodityRatePct = "otherSaleRatePct",
    dealThresholdPct = false,
    greatDeals = "highlightDeals",
}

-- The table last seeded, so the defaults are filled once per saved table instead of on every call
local seededDB

-- Account-wide store for the settings. Seeds missing defaults itself, so readers never see nil even before the settings panel registers
function AP.DB()
    if type(SimpleMarketValueDB) ~= "table" then
        SimpleMarketValueDB = {}
    end
    if seededDB ~= SimpleMarketValueDB then
        for old, new in pairs(RENAMED) do
            if new and SimpleMarketValueDB[new] == nil then SimpleMarketValueDB[new] = SimpleMarketValueDB[old] end
            SimpleMarketValueDB[old] = nil
        end
        for key, value in pairs(AP.Defaults) do
            if SimpleMarketValueDB[key] == nil then SimpleMarketValueDB[key] = value end
        end
        seededDB = SimpleMarketValueDB
    end
    return SimpleMarketValueDB
end

-- An absent saved table at load marks the account's first run, which the welcome line waits for. The table is made
-- now, so the next login is no first run
EventUtil.ContinueOnAddOnLoaded(addonName, function()
    AP.firstRun = SimpleMarketValueDB == nil
    AP.DB()
end)

-- ===== Setting changes =====
-- Bumped on every change of a setting, so the list painters, which keep it per row, repaint the rows it changes
AP.settingsRevision = 0
local settingsListeners = {}

-- fn runs after every change of a setting, such as Auctionator's lists working out their rows again
function AP.OnSettingsChanged(fn)
    settingsListeners[#settingsListeners + 1] = fn
end

function AP.SettingsChanged()
    AP.settingsRevision = AP.settingsRevision + 1
    for _, fn in ipairs(settingsListeners) do fn() end
end

-- "13m" for a time(): minutes within the hour, hours within the day, days after that
function AP.Age(when)
    local minutes = math.max(0, math.floor((time() - when) / 60))
    if minutes < 60 then return ("%dm"):format(math.max(1, minutes)) end
    if minutes < 1440 then return ("%dh"):format(math.floor(minutes / 60)) end
    return ("%dd"):format(math.floor(minutes / 1440))
end

-- Every chat line: the bracketed title in the gold of Blizzard's own chat links, the message uncoloured
function AP.Print(message)
    print(NORMAL_FONT_COLOR:WrapTextInColorCode("[" .. AP.title .. "]") .. ": " .. message)
end

-- Another addon's link may be secret. issecretvalue is declared SecretArguments = "AllowedWhenUntainted"; whether the
-- flag makes it raise for addon code is unsettled, so pcall answers right either way, because a raise means secret,
-- and nil never reaches the predicate.
function AP.CanAccess(value)
    if value == nil then return true end

    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

-- Text in a font role: GameFontNormal (heading, gold), GameFontHighlight (body, white), GameFontDisable (muted,
-- grey), GameFontNormalLarge (title, 16 px, a dialog's subject line only).
function AP.CreateText(parent, fontObject, layer)
    local text = parent:CreateFontString(nil, layer or "ARTWORK")
    text:SetFontObject(fontObject or GameFontHighlight)
    text:SetJustifyH("LEFT")
    return text
end

-- A GameTooltip owned by the hovered frame, filled with Blizzard's GameTooltip_* line helpers. A frame whose
-- template already sets OnEnter gets HookScript instead.
function AP.AttachTooltip(frame, fill, anchor)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        fill(GameTooltip, self)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

-- A content button one row (24) tall. Without a width it fits its label the way UIPanelButtonTemplate's FitToText
-- does (text plus 40, SecureUIPanelTemplates.xml:42), at least 64, rounded up to 8 so neighbours share widths.
function AP.CreateButton(parent, label, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetText(label)
    width = width or math.max(64, math.ceil((button:GetTextWidth() + 40) / 8) * 8)
    button:SetSize(width, 24)
    return button
end

-- SpinnerTemplate (Blizzard_SharedXML/Spinner.xml), the Auction House's own loading spinner, at the 24 px of a button
-- row and hidden until work starts. It sits beside the button that started the work, 4 px off, as the housing
-- bulletin board places one by its invite button (Blizzard_HousingBulletinBoard.xml:345-350). Its template plays and
-- stops the animation on show and hide.
function AP.CreateSpinner(parent)
    local spinner = CreateFrame("Frame", nil, parent, "SpinnerTemplate")
    spinner:SetSize(24, 24)
    spinner:Hide()
    return spinner
end

-- CheckboxWithLabelTemplate (Blizzard_SharedXML/Shared/Button/CheckButtonTemplates.xml:78), the minimal art Blizzard's
-- Settings use, at the 24 px AddonList gives it (Blizzard_AddOnList/AddonList.xml:73-74). The label joins the hit rect,
-- so a click on it toggles the box.
function AP.CreateCheckbox(parent, label)
    local checkbox = CreateFrame("CheckButton", nil, parent, "CheckboxWithLabelTemplate")
    checkbox:SetSize(24, 24)
    checkbox.Text:SetFontObject(GameFontHighlight)
    checkbox.Text:ClearAllPoints()
    checkbox.Text:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
    checkbox.Text:SetText(label)
    checkbox:SetHitRectInsets(0, -(4 + checkbox.Text:GetStringWidth()), 0, 0)
    return checkbox
end
