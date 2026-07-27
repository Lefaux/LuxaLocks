local addonName = ...

local PREFIX = "LuxaLocks2"
local PROTOCOL = "1"
local SUMMON_SPELL_ID = 698
local PENDING_SECONDS = 120
local ELYSIUM = "elysium"
local ROW_HEIGHT = 22

local S = {
    frame = nil,
    currentRows = {},
    otherRows = {},
    settingsPanel = nil,
    settingsRows = {},
    conflictRows = {},
    roster = {},
    inCombat = false,
    overrideRequest = nil,
}

LuxaLocksSummoning = LuxaLocksSummoning or {}

local function now()
    return GetServerTime and GetServerTime() or time()
end

local function playerIdentity()
    local name = UnitName("player") or "Unknown"
    local realm = GetRealmName() or "Unknown"
    return name .. "-" .. realm, name, realm
end

local function normalizeName(name)
    if not name then return "" end
    local base, realm = strsplit("-", name, 2)
    if not realm or realm == "" then realm = GetRealmName() or "" end
    return string.lower((base or "") .. "-" .. realm)
end

local function isEligibleCharacter()
    local _, class = UnitClass("player")
    return class == "WARLOCK" and (UnitLevel("player") or 0) >= 20
end

local function ensureDB()
    LuxaLocksDB = LuxaLocksDB or {}
    local db = LuxaLocksDB.summoning
    if not db then
        db = {}
        LuxaLocksDB.summoning = db
    end
    db.warlocks = db.warlocks or {}
    db.queues = db.queues or {}
    db.tombstones = db.tombstones or {}
    db.conflicts = db.conflicts or {}
    db.frame = db.frame or {
        point = "CENTER", relativePoint = "CENTER", x = 80, y = -40,
        width = 720, height = 430, shown = false,
    }
    return db
end

local function escape(value)
    return tostring(value or ""):gsub("%%", "%%25"):gsub("|", "%%7C"):gsub(",", "%%2C")
end

local function unescape(value)
    return (value or ""):gsub("%%2C", ","):gsub("%%7C", "|"):gsub("%%25", "%%")
end

local function splitWords(text)
    local out, seen = {}, {}
    for word in string.gmatch(string.lower(text or ""), "%S+") do
        if not seen[word] then
            seen[word] = true
            table.insert(out, word)
        end
    end
    table.sort(out)
    return out
end

local function canonicalKeywords(text)
    return table.concat(splitWords(text), " ")
end

local function send(message)
    if not isEligibleCharacter() or not IsInGroup() then return end
    local channel = IsInRaid() and "RAID" or "PARTY"
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, message, channel)
    elseif SendAddonMessage then
        SendAddonMessage(PREFIX, message, channel)
    end
end

local refreshQueue, refreshSettings, broadcastAll

local function queueFont()
    local settings = LuxaLocksDB and LuxaLocksDB.settings or {}
    local path = "Fonts\\FRIZQT__.TTF"
    if LibStub and settings.fontKey then
        local ok, media = pcall(LibStub, "LibSharedMedia-3.0", true)
        if ok and media and media.Fetch then path = media:Fetch("font", settings.fontKey, true) or path end
    end
    return path, tonumber(settings.fontSize) or 12
end

local function applyQueueAppearance()
    if not S.frame then return end
    local settings = LuxaLocksDB and LuxaLocksDB.settings or {}
    S.frame:SetAlpha(tonumber(settings.opacity) or .90)
    local path, size = queueFont()
    for _, pool in ipairs({S.currentRows, S.otherRows}) do
        for _, row in ipairs(pool) do row.text:SetFont(path, size, "") end
    end
end

local function ensureCurrentWarlock()
    if not isEligibleCharacter() then return nil end
    local key, name, realm = playerIdentity()
    key = normalizeName(key)
    local db = ensureDB()
    if not db.warlocks[key] then
        db.warlocks[key] = {
            key = key, name = name, realm = realm, keywords = "",
            revision = now(), writer = key,
        }
    end
    db.queues[key] = db.queues[key] or {}
    return key
end

local function requestKey(lockKey, player)
    return lockKey .. "|" .. normalizeName(player)
end

local function broadcastWarlock(record, forced)
    send(table.concat({
        forced and "F" or "W", PROTOCOL, escape(record.key), escape(record.name),
        escape(record.realm), escape(record.keywords), tostring(record.revision or 0),
        escape(record.writer),
    }, "|"))
end

local function broadcastRequest(lockKey, request)
    send(table.concat({
        "Q", PROTOCOL, escape(lockKey), escape(request.player), tostring(request.createdAt),
        escape(request.keyword), escape(request.guildStatus), escape(request.classToken),
        tostring(request.updatedAt or request.createdAt),
    }, "|"))
end

local function broadcastRemoval(key, removedAt)
    send(table.concat({"R", PROTOCOL, escape(key), tostring(removedAt)}, "|"))
end

local function removeRequest(lockKey, player, shouldBroadcast)
    local db = ensureDB()
    local key = requestKey(lockKey, player)
    local stamp = now()
    db.tombstones[key] = math.max(db.tombstones[key] or 0, stamp)
    if db.queues[lockKey] then
        db.queues[lockKey][normalizeName(player)] = nil
    end
    if shouldBroadcast then broadcastRemoval(key, stamp) end
    if refreshQueue then refreshQueue() end
end

local function removePlayerEverywhere(player)
    local db = ensureDB()
    for lockKey, queue in pairs(db.queues) do
        if queue[normalizeName(player)] then
            removeRequest(lockKey, player, true)
        end
    end
end

local function addRequest(lockKey, player, keyword, createdAt, shouldBroadcast)
    local db = ensureDB()
    db.queues[lockKey] = db.queues[lockKey] or {}
    local pkey = normalizeName(player)
    local key = requestKey(lockKey, player)
    createdAt = tonumber(createdAt) or now()
    if (db.tombstones[key] or 0) >= createdAt then return end
    if db.queues[lockKey][pkey] then return end
    local request = {
        player = player,
        createdAt = createdAt,
        updatedAt = createdAt,
        keyword = keyword or "",
        guildStatus = "unknown",
        classToken = "",
    }
    db.queues[lockKey][pkey] = request
    if shouldBroadcast then broadcastRequest(lockKey, request) end
    if refreshQueue then refreshQueue() end
end

local function findWarlockForKeyword(keyword, fallbackKey)
    if not keyword or keyword == "" then return fallbackKey end
    for key, record in pairs(ensureDB().warlocks) do
        for _, configured in ipairs(splitWords(record.keywords)) do
            if configured == keyword then return key end
        end
    end
    return fallbackKey
end

local function handleWhisper(message, sender)
    if not isEligibleCharacter() then return end
    local first, keyword = string.match(message or "", "^%s*(%S+)%s*(%S*)")
    if not first or string.lower(first) ~= "123" then return end
    keyword = string.lower(keyword or "")
    local currentKey = ensureCurrentWarlock()
    local lockKey = findWarlockForKeyword(keyword, currentKey)
    addRequest(lockKey, sender, keyword, now(), true)
end

local function updateRoster()
    wipe(S.roster)
    local count = GetNumGroupMembers() or 0
    local prefix = IsInRaid() and "raid" or "party"
    if count == 0 then return end
    if not IsInRaid() then
        local full = UnitName("player")
        if full then S.roster[normalizeName(full)] = "player" end
    end
    local limit = IsInRaid() and count or math.max(0, count - 1)
    for i = 1, limit do
        local unit = prefix .. i
        local name = UnitName(unit)
        if name then S.roster[normalizeName(name)] = unit end
    end
end

local function updateRequestKnowledge()
    updateRoster()
    local changed = false
    for _, queue in pairs(ensureDB().queues) do
        for pkey, request in pairs(queue) do
            local unit = S.roster[pkey]
            if unit then
                local _, class = UnitClass(unit)
                local guild = GetGuildInfo(unit)
                local status = guild and string.lower(guild) == ELYSIUM and "guild" or "nonguild"
                if request.classToken ~= (class or "") or request.guildStatus ~= status then
                    request.classToken = class or ""
                    request.guildStatus = status
                    request.updatedAt = now()
                    changed = true
                end
            end
        end
    end
    if changed then broadcastAll() end
end

local function sortedQueue(lockKey)
    local list = {}
    for _, request in pairs(ensureDB().queues[lockKey] or {}) do
        if request.pendingUntil and request.pendingUntil <= now() then
            request.pendingUntil = nil
        end
        table.insert(list, request)
    end
    table.sort(list, function(a, b)
        if a.createdAt == b.createdAt then return normalizeName(a.player) < normalizeName(b.player) end
        return a.createdAt < b.createdAt
    end)
    return list
end

local function findUnit(player)
    updateRoster()
    return S.roster[normalizeName(player)]
end

local function nextAvailable()
    local currentKey = ensureCurrentWarlock()
    for _, request in ipairs(sortedQueue(currentKey)) do
        if not request.pendingUntil and findUnit(request.player) then return request end
    end
end

local function requestColor(request)
    local inGroup = findUnit(request.player) ~= nil
    if request.guildStatus == "unknown" then return 1.0, 0.45, 0.70 end
    if request.guildStatus == "nonguild" then
        if inGroup then return 1.0, 0.15, 0.15 end
        return 0.48, 0.08, 0.08
    end
    if not inGroup then return 0.50, 0.50, 0.50 end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[request.classToken]
    return c and c.r or 1, c and c.g or 1, c and c.b or 1
end

local function formatAge(stamp)
    local seconds = math.max(0, now() - (stamp or now()))
    if seconds < 60 then return seconds .. "s" end
    if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
    return math.floor(seconds / 3600) .. "h"
end

local function showEntryMenu(row, request, lockKey, isCurrent)
    local function remove() removeRequest(lockKey, request.player, true) end
    local function selectOverride()
        S.overrideRequest = request
        refreshQueue()
        UIErrorsFrame:AddMessage("LuxaLocks: " .. request.player .. " is armed on the Summon button.", .4, .8, 1)
    end
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(row, function(_, root)
            if isCurrent then
                local button = root:CreateButton("Summon player (arm button)", selectOverride)
                if not findUnit(request.player) or S.inCombat then button:SetEnabled(false) end
            end
            root:CreateButton("Remove from this queue", remove)
        end)
    elseif EasyMenu then
        local menu = {}
        if isCurrent then
            table.insert(menu, {text = "Summon player (arm button)", notCheckable = true,
                disabled = not findUnit(request.player) or S.inCombat, func = selectOverride})
        end
        table.insert(menu, {text = "Remove from this queue", notCheckable = true, func = remove})
        S.dropdown = S.dropdown or CreateFrame("Frame", addonName .. "SummonDropdown", UIParent, "UIDropDownMenuTemplate")
        EasyMenu(menu, S.dropdown, row, 0, 0, "MENU")
    end
end

local function acquireRow(parent, pool, index)
    local row = pool[index]
    if row then row:Show() return row end
    row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:RegisterForClicks("RightButtonUp")
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 4, 0)
    row.text:SetPoint("RIGHT", -4, 0)
    row.text:SetJustifyH("LEFT")
    local path, size = queueFont()
    row.text:SetFont(path, size, "")
    pool[index] = row
    return row
end

local function hidePool(pool, from)
    for i = from, #pool do pool[i]:Hide() end
end

refreshQueue = function()
    if not S.frame or not S.frame:IsShown() then return end
    updateRequestKnowledge()
    applyQueueAppearance()
    local currentKey = ensureCurrentWarlock()
    local y, index = -4, 1
    local current = sortedQueue(currentKey)
    for position, request in ipairs(current) do
        local requestForRow = request
        local row = acquireRow(S.currentChild, S.currentRows, index)
        row:SetPoint("TOPLEFT", 0, y)
        row:SetPoint("RIGHT", 0, 0)
        local status = request.pendingUntil and "  |cffffff00Summoning…|r" or ""
        row.text:SetText(string.format("%d. %s  [%s]  %s%s", position, request.player,
            request.keyword ~= "" and request.keyword or "direct", formatAge(request.createdAt), status))
        row.text:SetTextColor(requestColor(request))
        row:SetScript("OnClick", function(self) showEntryMenu(self, requestForRow, currentKey, true) end)
        y, index = y - ROW_HEIGHT, index + 1
    end
    hidePool(S.currentRows, index)
    S.currentChild:SetHeight(math.max(1, -y))

    y, index = -4, 1
    local keys = {}
    for key in pairs(ensureDB().warlocks) do if key ~= currentKey then table.insert(keys, key) end end
    table.sort(keys)
    for _, lockKey in ipairs(keys) do
        local record = ensureDB().warlocks[lockKey]
        local header = acquireRow(S.otherChild, S.otherRows, index)
        header:SetPoint("TOPLEFT", 0, y)
        header:SetPoint("RIGHT", 0, 0)
        header.text:SetText("|cff66ccff" .. (record.name or lockKey) .. "|r")
        header:SetScript("OnClick", nil)
        y, index = y - ROW_HEIGHT, index + 1
        for position, request in ipairs(sortedQueue(lockKey)) do
            local requestForRow, lockForRow = request, lockKey
            local row = acquireRow(S.otherChild, S.otherRows, index)
            row:SetPoint("TOPLEFT", 0, y)
            row:SetPoint("RIGHT", 0, 0)
            row.text:SetText(string.format("  %d. %s [%s] %s", position, request.player,
                request.keyword ~= "" and request.keyword or "direct", formatAge(request.createdAt)))
            row.text:SetTextColor(requestColor(request))
            row:SetScript("OnClick", function(self) showEntryMenu(self, requestForRow, lockForRow, false) end)
            y, index = y - ROW_HEIGHT, index + 1
        end
    end
    hidePool(S.otherRows, index)
    S.otherChild:SetHeight(math.max(1, -y))
    local candidate = S.overrideRequest
    if candidate and (candidate.pendingUntil or not findUnit(candidate.player)) then
        S.overrideRequest = nil
        candidate = nil
    end
    candidate = candidate or nextAvailable()
    S.summonButton:SetEnabled(candidate ~= nil and not S.inCombat)
    S.summonButton:SetText(S.inCombat and "Not available in combat"
        or (S.overrideRequest and ("Summon " .. candidate.player) or "Summon next available player"))
    S.summonButton.candidate = candidate
    if not S.inCombat then
        if candidate then
            local spellName = GetSpellInfo and GetSpellInfo(SUMMON_SPELL_ID) or "Ritual of Summoning"
            S.summonButton:SetAttribute("type", "macro")
            S.summonButton:SetAttribute("macrotext",
                "/targetexact " .. candidate.player .. "\n/cast " .. (spellName or "Ritual of Summoning"))
        else
            S.summonButton:SetAttribute("type", nil)
            S.summonButton:SetAttribute("macrotext", nil)
        end
    end
end

local function saveFrame()
    if not S.frame then return end
    local db = ensureDB()
    local point, _, relativePoint, x, y = S.frame:GetPoint(1)
    db.frame.point, db.frame.relativePoint, db.frame.x, db.frame.y = point, relativePoint, x, y
    db.frame.width, db.frame.height = S.frame:GetSize()
    db.frame.shown = S.frame:IsShown()
end

local function ensureQueueFrame()
    if S.frame then return S.frame end
    local saved = ensureDB().frame
    local f = CreateFrame("Frame", addonName .. "QueueFrame", UIParent, "BackdropTemplate")
    f:SetSize(saved.width, saved.height)
    f:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    f:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 16,
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.90)
    f:SetClampedToScreen(true)
    f:SetMovable(true); f:SetResizable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); saveFrame() end)
    f:SetScript("OnSizeChanged", function() if S.currentScroll then
        local half = math.floor((f:GetWidth() - 42) * .58)
        S.currentScroll:SetWidth(half)
        S.otherScroll:SetPoint("TOPLEFT", S.currentScroll, "TOPRIGHT", 22, 0)
    end end)
    f:SetScript("OnShow", function() ensureDB().frame.shown = true; refreshQueue() end)
    f:SetScript("OnHide", function() ensureDB().frame.shown = false end)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12); title:SetText("LuxaLocks Summoning")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    local summon = CreateFrame("Button", addonName .. "SecureSummonButton", f,
        "UIPanelButtonTemplate,SecureActionButtonTemplate")
    summon:SetPoint("TOPLEFT", 14, -38); summon:SetSize(210, 25)
    summon:SetText("Summon next available player")
    summon:SetScript("PostClick", function(self)
        local request = self.candidate
        if request and findUnit(request.player) then
            request.pendingUntil = now() + PENDING_SECONDS
            S.overrideRequest = nil
            refreshQueue()
        end
    end)
    S.summonButton = summon
    local leftTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leftTitle:SetPoint("TOPLEFT", 16, -74); leftTitle:SetText("My queue")
    local rightTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rightTitle:SetPoint("TOP", 150, -74); rightTitle:SetText("Other queues")
    local currentScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    currentScroll:SetPoint("TOPLEFT", 14, -94); currentScroll:SetPoint("BOTTOMLEFT", 14, 14)
    local currentChild = CreateFrame("Frame", nil, currentScroll); currentChild:SetWidth(380)
    currentScroll:SetScrollChild(currentChild)
    local otherScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    otherScroll:SetPoint("TOPLEFT", currentScroll, "TOPRIGHT", 22, 0)
    otherScroll:SetPoint("BOTTOMRIGHT", -30, 14)
    local otherChild = CreateFrame("Frame", nil, otherScroll); otherChild:SetWidth(260)
    otherScroll:SetScrollChild(otherChild)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(20, 20); grip:SetPoint("BOTTOMRIGHT")
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); saveFrame() end)
    S.frame, S.currentScroll, S.currentChild, S.otherScroll, S.otherChild = f, currentScroll, currentChild, otherScroll, otherChild
    f:GetScript("OnSizeChanged")()
    return f
end

local function duplicateKeywords()
    local owners, duplicates = {}, {}
    for key, record in pairs(ensureDB().warlocks) do
        for _, keyword in ipairs(splitWords(record.keywords)) do
            if owners[keyword] and owners[keyword] ~= key then duplicates[keyword] = true else owners[keyword] = key end
        end
    end
    local list = {}
    for keyword in pairs(duplicates) do table.insert(list, keyword) end
    table.sort(list)
    return list
end

local function saveKeywords(key, edit)
    local record = ensureDB().warlocks[key]
    if not record then return end
    record.keywords = canonicalKeywords(edit:GetText())
    record.revision = now()
    record.writer = normalizeName((playerIdentity()))
    edit:SetText(record.keywords)
    broadcastWarlock(record, false)
    refreshSettings()
end

refreshSettings = function()
    if not S.settingsPanel or not S.settingsPanel:IsShown() then return end
    local panel = S.settingsPanel
    local y, index = -60, 1
    local keys = {}
    for key in pairs(ensureDB().warlocks) do table.insert(keys, key) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local record = ensureDB().warlocks[key]
        local row = S.settingsRows[index]
        if not row then
            row = CreateFrame("Frame", nil, panel)
            row:SetSize(600, 30)
            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.label:SetPoint("LEFT", 0, 0); row.label:SetWidth(190); row.label:SetJustifyH("LEFT")
            row.edit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            row.edit:SetPoint("LEFT", 200, 0); row.edit:SetSize(330, 24); row.edit:SetAutoFocus(false)
            row.save = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.save:SetPoint("LEFT", row.edit, "RIGHT", 8, 0); row.save:SetSize(60, 22); row.save:SetText("Apply")
            S.settingsRows[index] = row
        end
        row:SetPoint("TOPLEFT", 18, y); row:Show()
        row.label:SetText((record.name or key) .. ":")
        row.edit:SetText(record.keywords or "")
        local keyForRow, editForRow = key, row.edit
        row.save:SetScript("OnClick", function() saveKeywords(keyForRow, editForRow) end)
        y, index = y - 34, index + 1
    end
    hidePool(S.settingsRows, index)
    local dupes = duplicateKeywords()
    S.duplicateWarning:SetText(#dupes > 0 and ("|cffff4444Warning: duplicate keywords: " .. table.concat(dupes, ", ") .. "|r") or "")
    y = y - 12
    local cindex = 1
    for key, conflict in pairs(ensureDB().conflicts) do
        local keyForRow, conflictForRow = key, conflict
        local row = S.conflictRows[cindex]
        if not row then
            row = CreateFrame("Frame", nil, panel)
            row:SetSize(650, 52)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("TOPLEFT"); row.text:SetWidth(470); row.text:SetJustifyH("LEFT")
            row.localButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.localButton:SetPoint("TOPRIGHT", -92, 0); row.localButton:SetSize(86, 22); row.localButton:SetText("Keep local")
            row.remoteButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.remoteButton:SetPoint("TOPRIGHT", 0, 0); row.remoteButton:SetSize(86, 22); row.remoteButton:SetText("Use remote")
            S.conflictRows[cindex] = row
        end
        row:SetPoint("TOPLEFT", 18, y); row:Show()
        row.text:SetText(string.format("|cffffff00Conflict for %s|r\nLocal: %s   Remote: %s",
            conflict.localRecord.name or key, conflict.localRecord.keywords or "", conflict.remoteRecord.keywords or ""))
        row.localButton:SetScript("OnClick", function()
            local chosen = conflictForRow.localRecord; chosen.revision = now(); chosen.writer = normalizeName((playerIdentity()))
            ensureDB().warlocks[keyForRow] = chosen; ensureDB().conflicts[keyForRow] = nil; broadcastWarlock(chosen, true); refreshSettings()
        end)
        row.remoteButton:SetScript("OnClick", function()
            local chosen = conflictForRow.remoteRecord; chosen.revision = now(); chosen.writer = normalizeName((playerIdentity()))
            ensureDB().warlocks[keyForRow] = chosen; ensureDB().conflicts[keyForRow] = nil; broadcastWarlock(chosen, true); refreshSettings()
        end)
        y, cindex = y - 56, cindex + 1
    end
    hidePool(S.conflictRows, cindex)
end

local function ensureSettingsPanel()
    if S.settingsPanel then return end
    local panel = CreateFrame("Frame", addonName .. "SummoningSettings", UIParent)
    panel.name = "Summoning"
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16); title:SetText("LuxaLocks: Summoning")
    local help = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 18, -40); help:SetText("One-word, space-separated location keywords for each warlock.")
    local addEdit = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    addEdit:SetPoint("TOPRIGHT", -112, -16); addEdit:SetSize(180, 24); addEdit:SetAutoFocus(false)
    addEdit:SetText("")
    local addButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addButton:SetPoint("LEFT", addEdit, "RIGHT", 8, 0); addButton:SetSize(86, 22); addButton:SetText("Add warlock")
    addButton:SetScript("OnClick", function()
        local input = strtrim(addEdit:GetText() or "")
        if input == "" then return end
        local name, realm = strsplit("-", input, 2)
        realm = realm and realm ~= "" and realm or (GetRealmName() or "Unknown")
        local key = normalizeName(name .. "-" .. realm)
        local db = ensureDB()
        if not db.warlocks[key] then
            db.warlocks[key] = {
                key = key, name = name, realm = realm, keywords = "",
                revision = now(), writer = normalizeName((playerIdentity())),
            }
            db.queues[key] = db.queues[key] or {}
            broadcastWarlock(db.warlocks[key], false)
        end
        addEdit:SetText("")
        refreshSettings()
    end)
    local warning = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    warning:SetPoint("BOTTOMLEFT", 18, 18); warning:SetWidth(650); warning:SetJustifyH("LEFT")
    S.duplicateWarning = warning
    panel:SetScript("OnShow", refreshSettings)
    if Settings and Settings.RegisterCanvasLayoutSubcategory and LuxaLocksSettingsCategory then
        Settings.RegisterCanvasLayoutSubcategory(LuxaLocksSettingsCategory, panel, panel.name)
    elseif Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "LuxaLocks - Summoning")
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        panel.parent = "LuxaLocks"
        InterfaceOptions_AddCategory(panel)
    end
    S.settingsPanel = panel
end

local function receiveWarlock(parts, forced)
    local key = normalizeName(unescape(parts[3]))
    local incoming = {
        key = key, name = unescape(parts[4]), realm = unescape(parts[5]),
        keywords = canonicalKeywords(unescape(parts[6])),
        revision = tonumber(parts[7]) or 0, writer = unescape(parts[8]),
    }
    local db, existing = ensureDB(), ensureDB().warlocks[key]
    if not existing or forced or existing.keywords == incoming.keywords then
        if not existing or forced or incoming.revision >= (existing.revision or 0) then db.warlocks[key] = incoming end
    else
        db.conflicts[key] = {localRecord = existing, remoteRecord = incoming}
    end
    db.queues[key] = db.queues[key] or {}
end

local function receiveRequest(parts)
    local lockKey, player = normalizeName(unescape(parts[3])), unescape(parts[4])
    local createdAt, updatedAt = tonumber(parts[5]) or 0, tonumber(parts[9]) or 0
    local db, pkey = ensureDB(), normalizeName(player)
    local key = requestKey(lockKey, player)
    if (db.tombstones[key] or 0) >= createdAt then return end
    db.queues[lockKey] = db.queues[lockKey] or {}
    local existing = db.queues[lockKey][pkey]
    if not existing then
        db.queues[lockKey][pkey] = {
            player = player, createdAt = createdAt, keyword = unescape(parts[6]),
            guildStatus = unescape(parts[7]), classToken = unescape(parts[8]), updatedAt = updatedAt,
        }
    elseif updatedAt > (existing.updatedAt or 0) then
        existing.guildStatus, existing.classToken, existing.updatedAt =
            unescape(parts[7]), unescape(parts[8]), updatedAt
    end
end

local function receiveRemoval(parts)
    local key, stamp = unescape(parts[3]), tonumber(parts[4]) or 0
    local db = ensureDB()
    if stamp <= (db.tombstones[key] or 0) then return end
    db.tombstones[key] = stamp
    local lockKey, playerKey = string.match(key, "^(.-)|(.*)$")
    if lockKey and db.queues[lockKey] then db.queues[lockKey][playerKey] = nil end
end

broadcastAll = function()
    if not IsInGroup() then return end
    for _, record in pairs(ensureDB().warlocks) do broadcastWarlock(record, false) end
    for lockKey, queue in pairs(ensureDB().queues) do
        for _, request in pairs(queue) do broadcastRequest(lockKey, request) end
    end
    for key, stamp in pairs(ensureDB().tombstones) do broadcastRemoval(key, stamp) end
end

local function receiveAddon(prefix, message, _, sender)
    if prefix ~= PREFIX or normalizeName(sender) == normalizeName((playerIdentity())) then return end
    local parts = {strsplit("|", message)}
    if parts[2] ~= PROTOCOL then return end
    if parts[1] == "H" then broadcastAll()
    elseif parts[1] == "W" then receiveWarlock(parts, false)
    elseif parts[1] == "F" then receiveWarlock(parts, true)
    elseif parts[1] == "Q" then receiveRequest(parts)
    elseif parts[1] == "R" then receiveRemoval(parts)
    end
    if refreshQueue then refreshQueue() end
    if refreshSettings then refreshSettings() end
end

function LuxaLocksSummoning.ToggleQueue()
    if not isEligibleCharacter() then
        UIErrorsFrame:AddMessage("LuxaLocks summoning requires a level 20+ warlock.", 1, .2, .2)
        return
    end
    local frame = ensureQueueFrame()
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

function LuxaLocksSummoning.Sync()
    if not isEligibleCharacter() or not IsInGroup() then
        UIErrorsFrame:AddMessage("LuxaLocks: Join a group to synchronize.", 1, .2, .2)
        return
    end
    send("H|" .. PROTOCOL)
    broadcastAll()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("CHAT_MSG_WHISPER")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded ~= addonName then return end
        ensureDB()
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
        ensureSettingsPanel()
    elseif event == "PLAYER_LOGIN" then
        if not isEligibleCharacter() then return end
        ensureCurrentWarlock()
        ensureQueueFrame()
        if not ensureDB().frame.shown then S.frame:Hide() end
        C_Timer.After(3, function() if IsInGroup() then LuxaLocksSummoning.Sync() end end)
    elseif event == "PLAYER_LOGOUT" then
        saveFrame()
    elseif event == "CHAT_MSG_WHISPER" then
        handleWhisper(...)
    elseif event == "CHAT_MSG_ADDON" then
        receiveAddon(...)
    elseif event == "GROUP_ROSTER_UPDATE" then
        if not isEligibleCharacter() then return end
        updateRequestKnowledge()
        C_Timer.After(1, function() if IsInGroup() then send("H|" .. PROTOCOL) end end)
        refreshQueue()
    elseif event == "PLAYER_REGEN_DISABLED" then
        S.inCombat = true; refreshQueue()
    elseif event == "PLAYER_REGEN_ENABLED" then
        S.inCombat = false; refreshQueue()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subevent, _, _, _, _, _, _, destName = CombatLogGetCurrentEventInfo()
        if subevent == "SPELL_SUMMON" and destName then removePlayerEverywhere(destName) end
    end
end)

local ticker = C_Timer.NewTicker(1, function()
    if S.frame and S.frame:IsShown() then refreshQueue() end
end)
