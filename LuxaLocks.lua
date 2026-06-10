local addonName = ...

LuxaLocksDB = LuxaLocksDB or {}

local BAG_IDS = {0, 1, 2, 3, 4}
local TEST_MODE_IGNORE_CLASS_LEVEL = false
local DEFAULT_FONT_PATH = "Fonts\\FRIZQT__.TTF"
local DEFAULT_FONT_SIZE = 12
local DEFAULT_OPACITY = 0.90
local TITLE_FONT_OFFSET = 4
local MIN_FONT_SIZE = 8
local MAX_FONT_SIZE = 24
local MIN_OPACITY = 0.20
local MAX_OPACITY = 1.00
local DEFAULT_FONT_KEY = "Friz Quadrata TT"

local DEFAULT_FRAME = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 0,
    width = 520,
    height = 320,
}

local ROW_HEIGHT = 20
local FRAME_PADDING = 12
local SCROLLBAR_WIDTH = 20
local RESIZE_GRIP_SIZE = 18

local state = {
    frame = nil,
    header = nil,
    scrollFrame = nil,
    scrollChild = nil,
    title = nil,
    summary = nil,
    settingsPanel = nil,
    settingsCategory = nil,
    fontScrollFrame = nil,
    fontScrollChild = nil,
    fontSizeSlider = nil,
    opacitySlider = nil,
    fontRows = {},
    rows = {},
    dropdown = nil,
    minimapButton = nil,
}

local function ensureDB()
    LuxaLocksDB.characters = LuxaLocksDB.characters or {}
    LuxaLocksDB.frame = LuxaLocksDB.frame or {}
    LuxaLocksDB.minimap = LuxaLocksDB.minimap or {}
    LuxaLocksDB.settings = LuxaLocksDB.settings or {}
    LuxaLocksDB.accountName = LuxaLocksDB.accountName or nil
end

local function getSharedMedia()
    if not LibStub then
        return nil
    end

    local ok, lib = pcall(LibStub, "LibSharedMedia-3.0", true)
    if ok then
        return lib
    end

    return nil
end

local function ensureSettings()
    ensureDB()

    local settings = LuxaLocksDB.settings
    settings.fontKey = settings.fontKey or DEFAULT_FONT_KEY
    settings.fontSize = tonumber(settings.fontSize) or DEFAULT_FONT_SIZE
    settings.opacity = tonumber(settings.opacity) or DEFAULT_OPACITY
    settings.fontSize = math.max(MIN_FONT_SIZE, math.min(MAX_FONT_SIZE, math.floor(settings.fontSize + 0.5)))
    settings.opacity = math.max(MIN_OPACITY, math.min(MAX_OPACITY, settings.opacity))

    local media = getSharedMedia()
    local hasFont = false
    if media and media.IsValid and media:IsValid("font", settings.fontKey) then
        hasFont = true
    end

    if not hasFont then
        settings.fontKey = DEFAULT_FONT_KEY
    end

    return settings
end

local function getAccountName()
    local accountName = nil

    if GetCVar then
        local ok, value = pcall(GetCVar, "accountName")
        if ok and type(value) == "string" and value ~= "" then
            accountName = value
        end
    end

    return accountName or "unknown"
end

local function getCharacterName()
    return UnitName("player") or "unknown"
end

local function getRealmName()
    return GetRealmName() or "unknown"
end

local function abbreviateRealmName(realmName)
    if realmName == "Pyrewood Village" then
        return "PV"
    end

    if realmName == "Mirage Raceway" then
        return "MR"
    end

    if realmName == "Nethergarde Keep" then
        return "NK"
    end

    return realmName
end

local function getCharacterKey()
    return getCharacterName() .. "@" .. getRealmName()
end

local function getRecordKey()
    return getAccountName() .. "|" .. getCharacterKey()
end

local function getLocationName()
    local zone = GetRealZoneText() or GetZoneText() or "Unknown"
    local subZone = GetSubZoneText() or ""

    if subZone ~= "" and subZone ~= zone then
        return zone .. " - " .. subZone
    end

    return zone
end

local function getContainerSlotCount(bagId)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bagId) or 0
    end

    if GetContainerNumSlots then
        return GetContainerNumSlots(bagId) or 0
    end

    return 0
end

local function countEmptyBagSlots()
    local totalSlots = 0
    local occupiedSlots = 0

    for _, bagId in ipairs(BAG_IDS) do
        local bagSlots = getContainerSlotCount(bagId)
        totalSlots = totalSlots + bagSlots

        for slot = 1, bagSlots do
            local itemInfo

            if C_Container and C_Container.GetContainerItemInfo then
                itemInfo = C_Container.GetContainerItemInfo(bagId, slot)
            elseif GetContainerItemInfo then
                itemInfo = {GetContainerItemInfo(bagId, slot)}
            end

            if itemInfo and (itemInfo.itemID or itemInfo.hyperlink or itemInfo.texture) then
                occupiedSlots = occupiedSlots + 1
            end
        end
    end

    return totalSlots - occupiedSlots, totalSlots
end

local function shouldTrackCharacter()
    if TEST_MODE_IGNORE_CLASS_LEVEL then
        return true
    end

    local _, classToken = UnitClass("player")
    local level = UnitLevel("player") or 0

    return classToken == "WARLOCK" and level >= 20
end

local function buildRecord()
    local emptySlots, totalSlots = countEmptyBagSlots()

    return {
        accountName = getAccountName(),
        characterName = getCharacterName(),
        realmName = getRealmName(),
        locationName = getLocationName(),
        emptyBagSlots = emptySlots,
        totalBagSlots = totalSlots,
        classToken = select(2, UnitClass("player")),
        level = UnitLevel("player") or 0,
        updatedAt = date("!%Y-%m-%dT%H:%M:%SZ"),
    }
end

local function recordsAsArray()
    ensureDB()

    local records = {}
    for key, record in pairs(LuxaLocksDB.characters) do
        table.insert(records, {
            key = key,
            record = record,
        })
    end

    table.sort(records, function(left, right)
        local a = left.record
        local b = right.record

        local aLocation = a.locationName or ""
        local bLocation = b.locationName or ""
        if aLocation ~= bLocation then
            return aLocation < bLocation
        end

        local aName = a.characterName or ""
        local bName = b.characterName or ""
        if aName ~= bName then
            return aName < bName
        end

        return (a.realmName or "") < (b.realmName or "")
    end)

    return records
end

local function saveCurrentCharacter(force)
    if not shouldTrackCharacter() then
        return false
    end

    ensureDB()

    local recordKey = getRecordKey()
    local nextRecord = buildRecord()
    local existing = LuxaLocksDB.characters[recordKey]

    if not force and existing then
        local unchanged =
            existing.emptyBagSlots == nextRecord.emptyBagSlots and
            existing.locationName == nextRecord.locationName and
            existing.totalBagSlots == nextRecord.totalBagSlots and
            existing.classToken == nextRecord.classToken and
            existing.level == nextRecord.level

        if unchanged then
            return false
        end
    end

    LuxaLocksDB.accountName = nextRecord.accountName
    LuxaLocksDB.characters[recordKey] = nextRecord
    return true
end

local function saveFramePosition(frame)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    ensureDB()
    LuxaLocksDB.frame.point = point
    LuxaLocksDB.frame.relativePoint = relativePoint
    LuxaLocksDB.frame.x = math.floor(x + 0.5)
    LuxaLocksDB.frame.y = math.floor(y + 0.5)
    LuxaLocksDB.frame.width = math.floor(frame:GetWidth() + 0.5)
    LuxaLocksDB.frame.height = math.floor(frame:GetHeight() + 0.5)
end

local function getSavedFrame()
    ensureDB()

    LuxaLocksDB.frame.point = LuxaLocksDB.frame.point or DEFAULT_FRAME.point
    LuxaLocksDB.frame.relativePoint = LuxaLocksDB.frame.relativePoint or DEFAULT_FRAME.relativePoint
    LuxaLocksDB.frame.x = LuxaLocksDB.frame.x or DEFAULT_FRAME.x
    LuxaLocksDB.frame.y = LuxaLocksDB.frame.y or DEFAULT_FRAME.y
    LuxaLocksDB.frame.width = LuxaLocksDB.frame.width or DEFAULT_FRAME.width
    LuxaLocksDB.frame.height = LuxaLocksDB.frame.height or DEFAULT_FRAME.height

    return LuxaLocksDB.frame
end

local function getSavedMinimap()
    ensureDB()

    LuxaLocksDB.minimap.point = LuxaLocksDB.minimap.point or "TOPRIGHT"
    LuxaLocksDB.minimap.relativePoint = LuxaLocksDB.minimap.relativePoint or "TOPRIGHT"
    LuxaLocksDB.minimap.x = LuxaLocksDB.minimap.x or -6
    LuxaLocksDB.minimap.y = LuxaLocksDB.minimap.y or -6

    return LuxaLocksDB.minimap
end

local function saveMinimapPosition(button)
    local point, _, relativePoint, x, y = button:GetPoint(1)
    ensureDB()
    LuxaLocksDB.minimap.point = point
    LuxaLocksDB.minimap.relativePoint = relativePoint
    LuxaLocksDB.minimap.x = math.floor(x + 0.5)
    LuxaLocksDB.minimap.y = math.floor(y + 0.5)
end

local function getFontSettings()
    local settings = ensureSettings()
    local media = getSharedMedia()
    local fontPath = media and media.Fetch and media:Fetch("font", settings.fontKey) or nil
    return fontPath or DEFAULT_FONT_PATH, settings.fontSize
end

local function getRowHeight()
    local _, fontSize = getFontSettings()
    return math.max(ROW_HEIGHT, fontSize + 8)
end

local function formatCharacterLabel(record)
    local label = record.characterName or "unknown"
    if record.realmName and record.realmName ~= "" then
        label = label .. " - " .. abbreviateRealmName(record.realmName)
    end

    if record.level then
        label = label .. " (" .. tostring(record.level) .. ")"
    end

    return label
end

local function formatLocationLabel(record)
    return record.locationName or "Unknown"
end

local function applyFont(fontString, sizeOffset)
    local fontPath, fontSize, fontFlags = getFontSettings()
    fontString:SetFont(fontPath, fontSize + (sizeOffset or 0), fontFlags)
end

local updateFontList

local function applyMainWindowTypography()
    if state.title then
        applyFont(state.title, TITLE_FONT_OFFSET)
    end

    if state.summary then
        applyFont(state.summary, 0)
    end

    for _, row in ipairs(state.rows) do
        if row.name then
            applyFont(row.name, 0)
        end
        if row.empty then
            applyFont(row.empty, 0)
        end
        if row.location then
            applyFont(row.location, 0)
        end
        if row then
            row:SetHeight(getRowHeight())
        end
    end
end

local function selectFontKey(fontKey)
    ensureSettings().fontKey = fontKey
    applyMainWindowTypography()
    updateFontList()
    applyTypography()
end

local function applyOpacity()
    if state.frame then
        state.frame:SetAlpha(ensureSettings().opacity)
    end
end

local function getAvailableFonts()
    local media = getSharedMedia()
    local fonts = {}

    if media and media.List then
        local entries = media:List("font") or {}
        for _, key in ipairs(entries) do
            table.insert(fonts, {
                key = key,
                label = key,
            })
        end
    end

    if #fonts == 0 then
        fonts = {
            {label = "Friz Quadrata TT", key = "Friz Quadrata TT"},
            {label = "Arial Narrow", key = "Arial Narrow"},
            {label = "Morpheus", key = "Morpheus"},
            {label = "Skurri", key = "Skurri"},
        }
    end

    table.sort(fonts, function(left, right)
        return left.label < right.label
    end)

    return fonts
end

local function ensureRow(index)
    local row = state.rows[index]
    if row then
        return row
    end

    row = CreateFrame("Frame", nil, state.scrollChild)
    row:SetHeight(getRowHeight())

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", 0, 0)
    name:SetJustifyH("LEFT")
    name:SetTextColor(0.95, 0.95, 0.95, 1)
    name:SetWidth(220)
    applyFont(name, 0)

    local empty = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    empty:SetPoint("LEFT", name, "RIGHT", 8, 0)
    empty:SetJustifyH("CENTER")
    empty:SetWidth(70)
    applyFont(empty, 0)

    local location = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    location:SetPoint("LEFT", empty, "RIGHT", 8, 0)
    location:SetJustifyH("LEFT")
    applyFont(location, 0)

    row.name = name
    row.empty = empty
    row.location = location
    state.rows[index] = row

    return row
end

local function layoutRows()
    if not state.scrollChild or not state.scrollFrame then
        return
    end

    local records = recordsAsArray()
    local width = math.max(1, (state.scrollFrame:GetWidth() or 0) - 12)
    local yOffset = -4

    for index, entry in ipairs(records) do
        local row = ensureRow(index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", state.scrollChild, "TOPLEFT", 0, yOffset)
        row:SetHeight(getRowHeight())
        row:SetWidth(width)
        row.name:SetWidth(math.max(140, math.floor(width * 0.42)))
        row.empty:SetWidth(70)
        row.location:ClearAllPoints()
        row.location:SetPoint("LEFT", row.empty, "RIGHT", 8, 0)
        row.location:SetWidth(math.max(80, width - row.name:GetWidth() - row.empty:GetWidth() - 24))
        row.name:SetText(formatCharacterLabel(entry.record))
        row.empty:SetText(tostring(entry.record.emptyBagSlots or 0))
        row.empty:SetTextColor(0.35, 0.85, 0.35, 1)
        row.location:SetText(formatLocationLabel(entry.record))
        row:Show()
        yOffset = yOffset - getRowHeight()
    end

    for index = #records + 1, #state.rows do
        if state.rows[index] then
            state.rows[index]:Hide()
        end
    end

    state.scrollChild:SetHeight(math.max(1, math.abs(yOffset) + 10))

    if state.summary then
        local current = LuxaLocksDB.characters[getRecordKey()]
        local currentEmpty = current and current.emptyBagSlots or 0
        state.summary:SetText(string.format("Tracked: %d | Current: %d empty slots", #records, currentEmpty))
    end
end

local function refreshDisplay()
    if not state.frame then
        return
    end

    layoutRows()
end

local function ensureMenuFrame()
    if state.dropdown then
        return state.dropdown
    end

    state.dropdown = CreateFrame("Frame", addonName .. "Dropdown", UIParent, "UIDropDownMenuTemplate")
    return state.dropdown
end

local function toggleFrame()
    local frame = state.frame or nil
    if not frame then
        return
    end

    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        refreshDisplay()
    end
end

local function showMenu(anchor)
    local menu = {
        {
            text = "Refresh data",
            notCheckable = true,
            func = function()
                saveCurrentCharacter(true)
                refreshDisplay()
            end,
        },
        {
            text = "Show / hide window",
            notCheckable = true,
            func = toggleFrame,
        },
        {
            text = "Close",
            notCheckable = true,
            func = function()
                if state.frame then
                    state.frame:Hide()
                end
            end,
        },
    }

    EasyMenu(menu, ensureMenuFrame(), anchor, 0, 0, "MENU")
end

local function ensureMinimapButton()
    if state.minimapButton then
        return state.minimapButton
    end

    local button = CreateFrame("Button", addonName .. "MinimapButton", Minimap)
    local saved = getSavedMinimap()

    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetClampedToScreen(true)
    button:SetMovable(true)
    button:EnableMouse(true)
    button:RegisterForDrag("LeftButton")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetClampRectInsets(0, -3, 0, 0)
    button:SetPoint(saved.point, Minimap, saved.relativePoint, saved.x, saved.y)
    button:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self:StartMoving()
        end
    end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveMinimapPosition(self)
    end)

    button:SetHighlightTexture(136477)

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture(136430)
    overlay:SetPoint("TOPLEFT")
    button.overlay = overlay

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture(136467)
    background:SetPoint("TOPLEFT", 7, -5)
    button.background = background

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture("Interface\\Icons\\Spell_Shadow_SummonImp")
    button.icon = icon

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "LeftButton" then
            if IsShiftKeyDown() then
                return
            end
            toggleFrame()
            return
        end

        if mouseButton == "RightButton" then
            showMenu(button)
        end
    end)

    state.minimapButton = button
    return button
end

local function ensureFrame()
    if state.frame then
        return state.frame
    end

    local saved = getSavedFrame()

    local frame = CreateFrame("Frame", addonName .. "Frame", UIParent, "BackdropTemplate")
    frame:SetSize(saved.width, saved.height)
    frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    frame:SetBackdrop({
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        edgeSize = 16,
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.90)
    frame:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(360, 220)
    elseif frame.SetMinResize then
        frame:SetMinResize(360, 220)
    end
    frame:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveFramePosition(self)
    end)
    frame:SetScript("OnSizeChanged", function(self)
        saveFramePosition(self)
        refreshDisplay()
    end)
    frame:SetScript("OnShow", function()
        applyOpacity()
        refreshDisplay()
    end)
    frame:Hide()

    local frameBackground = frame:CreateTexture(nil, "BACKGROUND")
    frameBackground:SetAllPoints()
    frameBackground:SetTexture("Interface\\Buttons\\WHITE8X8")
    frameBackground:SetVertexColor(0.05, 0.05, 0.05, 0.90)
    state.frameBackground = frameBackground

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    header:SetHeight(30)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetFrameLevel(frame:GetFrameLevel() + 2)
    local headerBackdrop = header:CreateTexture(nil, "BACKGROUND")
    headerBackdrop:SetAllPoints()
    headerBackdrop:SetTexture("Interface\\Buttons\\WHITE8X8")
    headerBackdrop:SetVertexColor(0.12, 0.12, 0.12, 0.90)
    header:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        saveFramePosition(frame)
    end)
    header:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            frame:StartMoving()
        end
    end)
    header:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        saveFramePosition(frame)
    end)
    state.header = header

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", FRAME_PADDING, -8)
    title:SetText("LuxaLocks")
    applyFont(title, TITLE_FONT_OFFSET)
    state.title = title

    local closeButton = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -2, -2)
    closeButton:SetFrameLevel(header:GetFrameLevel() + 1)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    local summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", frame, "TOPLEFT", FRAME_PADDING, -34)
    summary:SetText("Tracked: 0 | Current: 0 empty slots")
    applyFont(summary, 0)
    state.summary = summary

    local scrollFrame = CreateFrame("ScrollFrame", addonName .. "ScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", -2, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SCROLLBAR_WIDTH - FRAME_PADDING, FRAME_PADDING + 18)
    scrollFrame:EnableMouseWheel(true)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)
    state.scrollFrame = scrollFrame
    state.scrollChild = scrollChild

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local scrollBar = self.ScrollBar
        if not scrollBar then
            return
        end

        local step = ROW_HEIGHT
        local minValue, maxValue = scrollBar:GetMinMaxValues()
        local newValue = scrollBar:GetValue() - (delta * step)
        if newValue < minValue then
            newValue = minValue
        elseif newValue > maxValue then
            newValue = maxValue
        end
        scrollBar:SetValue(newValue)
    end)

    local resizeGrip = CreateFrame("Button", nil, frame)
    resizeGrip:SetSize(RESIZE_GRIP_SIZE, RESIZE_GRIP_SIZE)
    resizeGrip:SetPoint("BOTTOMRIGHT", -2, 2)
    resizeGrip:EnableMouse(true)
    resizeGrip:RegisterForDrag("LeftButton")
    resizeGrip:SetScript("OnDragStart", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        saveFramePosition(frame)
    end)

    local gripTexture = resizeGrip:CreateTexture(nil, "ARTWORK")
    gripTexture:SetAllPoints()
    gripTexture:SetTexture("Interface\\CHATFRAME\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip.texture = gripTexture

    state.frame = frame
    ensureMinimapButton()
    ensureSettingsPanel()
    applyTypography()
    applyOpacity()
    refreshDisplay()
    return frame
end

local function ensureFontRow(index)
    local row = state.fontRows[index]
    if row then
        return row
    end

    local parent = state.fontScrollChild
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(280, 20)

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.12)
    button.highlight = highlight

    local selected = button:CreateTexture(nil, "BACKGROUND")
    selected:SetAllPoints()
    selected:SetColorTexture(1, 0.82, 0.2, 0.18)
    selected:Hide()
    button.selected = selected

    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", 6, 0)
    text:SetJustifyH("LEFT")
    button.text = text

    button:SetScript("OnClick", function()
        local fontKey = button.fontKey
        if fontKey then
            selectFontKey(fontKey)
        end
    end)

    state.fontRows[index] = button
    return button
end

local function updateFontList()
    if not state.fontScrollChild or not state.fontScrollFrame then
        return
    end

    local fonts = getAvailableFonts()
    local rowHeight = 20
    local totalHeight = math.max(rowHeight, #fonts * rowHeight)
    local selectedFontKey = ensureSettings().fontKey

    for index, entry in ipairs(fonts) do
        local row = ensureFontRow(index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", state.fontScrollChild, "TOPLEFT", 0, -(index - 1) * rowHeight)
        row:SetWidth(state.fontScrollChild:GetWidth() or 280)
        row.fontKey = entry.key
        row.text:SetText(entry.label)
        if row.selected then
            if selectedFontKey == entry.key then
                row.selected:Show()
            else
                row.selected:Hide()
            end
        end
        if selectedFontKey == entry.key then
            row.text:SetTextColor(1, 0.82, 0.2, 1)
        else
            row.text:SetTextColor(0.95, 0.95, 0.95, 1)
        end
        row:Show()
    end

    for index = #fonts + 1, #state.fontRows do
        if state.fontRows[index] then
            state.fontRows[index]:Hide()
        end
    end

    state.fontScrollChild:SetHeight(totalHeight)
    state.fontScrollFrame:SetVerticalScroll(0)
    if state.fontScrollFrame.UpdateScrollChildRect then
        state.fontScrollFrame:UpdateScrollChildRect()
    end
end

local function applyTypography()
    applyMainWindowTypography()

    if state.fontSizeSlider then
        state.fontSizeSlider:SetValue(ensureSettings().fontSize)
    end

    if state.opacitySlider then
        state.opacitySlider:SetValue(ensureSettings().opacity)
    end

    updateFontList()
    applyOpacity()
    refreshDisplay()
end

local function ensureSettingsPanel()
    if state.settingsPanel then
        return state.settingsPanel
    end

    local panel = CreateFrame("Frame", addonName .. "SettingsPanel", UIParent)
    panel.name = "LuxaLocks"

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("LuxaLocks")

    local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Configure the font used by the LuxaLocks window.")

    local fontLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -18)
    fontLabel:SetText("Font")

    local fontScrollFrame = CreateFrame("ScrollFrame", addonName .. "FontScrollFrame", panel, "UIPanelScrollFrameTemplate")
    fontScrollFrame:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", 0, -8)
    fontScrollFrame:SetSize(300, 150)
    fontScrollFrame:EnableMouseWheel(true)

    local fontScrollChild = CreateFrame("Frame", nil, fontScrollFrame)
    fontScrollChild:SetPoint("TOPLEFT", fontScrollFrame, "TOPLEFT", 0, 0)
    fontScrollChild:SetWidth(280)
    fontScrollChild:SetHeight(1)
    fontScrollFrame:SetScrollChild(fontScrollChild)
    state.fontScrollFrame = fontScrollFrame
    state.fontScrollChild = fontScrollChild

    fontScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local scrollBar = self.ScrollBar
        if not scrollBar then
            return
        end

        local step = 24
        local minValue, maxValue = scrollBar:GetMinMaxValues()
        local newValue = scrollBar:GetValue() - (delta * step)
        if newValue < minValue then
            newValue = minValue
        elseif newValue > maxValue then
            newValue = maxValue
        end
        scrollBar:SetValue(newValue)
    end)

    local sizeLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sizeLabel:SetPoint("TOPLEFT", fontScrollFrame, "BOTTOMLEFT", 16, -12)
    sizeLabel:SetText("Font size")

    local slider = CreateFrame("Slider", addonName .. "FontSizeSlider", panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", 0, -12)
    slider:SetWidth(240)
    slider:SetMinMaxValues(MIN_FONT_SIZE, MAX_FONT_SIZE)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(ensureSettings().fontSize)
    _G[slider:GetName() .. "Low"]:SetText(tostring(MIN_FONT_SIZE))
    _G[slider:GetName() .. "High"]:SetText(tostring(MAX_FONT_SIZE))
    _G[slider:GetName() .. "Text"]:SetText("Font size")
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        local settings = ensureSettings()
        if settings.fontSize == value then
            return
        end
        settings.fontSize = value
        applyTypography()
    end)
    state.fontSizeSlider = slider

    local opacityLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    opacityLabel:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -20)
    opacityLabel:SetText("Window opacity")

    local opacitySlider = CreateFrame("Slider", addonName .. "OpacitySlider", panel, "OptionsSliderTemplate")
    opacitySlider:SetPoint("TOPLEFT", opacityLabel, "BOTTOMLEFT", 0, -12)
    opacitySlider:SetWidth(240)
    opacitySlider:SetMinMaxValues(MIN_OPACITY, MAX_OPACITY)
    opacitySlider:SetValueStep(0.01)
    opacitySlider:SetObeyStepOnDrag(true)
    opacitySlider:SetValue(ensureSettings().opacity)
    _G[opacitySlider:GetName() .. "Low"]:SetText(string.format("%.0f%%", MIN_OPACITY * 100))
    _G[opacitySlider:GetName() .. "High"]:SetText(string.format("%.0f%%", MAX_OPACITY * 100))
    _G[opacitySlider:GetName() .. "Text"]:SetText("Window opacity")
    opacitySlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor((value * 100) + 0.5) / 100
        local settings = ensureSettings()
        if settings.opacity == value then
            return
        end
        settings.opacity = value
        applyOpacity()
    end)
    state.opacitySlider = opacitySlider

    panel:SetScript("OnShow", function()
        updateFontList()
        if state.fontSizeSlider then
            state.fontSizeSlider:SetValue(ensureSettings().fontSize)
        end
        if state.opacitySlider then
            state.opacitySlider:SetValue(ensureSettings().opacity)
        end
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        category.ID = panel.name
        Settings.RegisterAddOnCategory(category)
        state.settingsCategory = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end

    state.settingsPanel = panel
    updateFontList()
    return panel
end

local function showFrame()
    local frame = ensureFrame()
    frame:Show()
    refreshDisplay()
end

local function handleSlashCommand(msg)
    local command = string.lower(strtrim(msg or ""))

    if command == "" or command == "show" then
        showFrame()
        return
    end

    if command == "hide" then
        if state.frame then
            state.frame:Hide()
        end
        return
    end

    if command == "refresh" then
        saveCurrentCharacter(true)
        refreshDisplay()
        print("|cff66ccffLuxaLocks|r refreshed current character data.")
        return
    end

    if command == "options" or command == "config" then
        local panel = ensureSettingsPanel()
        if Settings and Settings.OpenToCategory and state.settingsCategory then
            Settings.OpenToCategory(state.settingsCategory.ID)
        elseif InterfaceOptionsFrame_Show and InterfaceOptionsFrame_OpenToCategory then
            InterfaceOptionsFrame_Show()
            InterfaceOptionsFrame_OpenToCategory(panel)
        elseif panel.Show then
            panel:Show()
        end
        return
    end

    print("|cff66ccffLuxaLocks|r commands: /luxalocks, /luxalocks show, /luxalocks hide, /luxalocks refresh, /luxalocks options")
end

local function handleUpdate()
    local changed = saveCurrentCharacter(false)
    if changed and state.frame and state.frame:IsShown() then
        refreshDisplay()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "ADDON_LOADED" then
        ensureDB()
        ensureSettings()
        ensureSettingsPanel()
        return
    end

    if event == "PLAYER_LOGIN" then
        SLASH_LUXALOCKS1 = "/luxalocks"
        SlashCmdList["LUXALOCKS"] = handleSlashCommand
        ensureDB()
        ensureSettings()
        ensureFrame()
        saveCurrentCharacter(true)
        refreshDisplay()
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        saveCurrentCharacter(false)
        refreshDisplay()
        return
    end

    handleUpdate()
end)
