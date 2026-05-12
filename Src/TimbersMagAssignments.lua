local ADDON_NAME = ...

local TMA = CreateFrame("Frame", "TimbersMagAssignmentsFrame")
local PREFIX = "TMA1"
local ROW_COUNT = 5
local MSG_REQUEST = "REQ"
local MSG_SYNC = "SYNC"
local MSG_SEPARATOR = "|"
local BLAST_NOVA_SPELL_ID = 30616
local BLAST_NOVA_CAST_SECONDS = 2
local BLAST_NOVA_COOLDOWN_SECONDS = 60
local SHADOW_CAGE_SPELL_ID = 30168
local SHADOW_CAGE_DURATION_SECONDS = 10
local MAG_ACTIVE_FALLBACK_SECONDS = 120
local HELLFIRE_CHANNELER_NAME = "hellfire channeler"
local MONITOR_SYMBOL_ROWS = ROW_COUNT
local MONITOR_CLICKER_COLUMNS = 4
local MONITOR_BAR_WIDTH = 78
local MONITOR_BAR_HEIGHT = 14
local WHISPER_SYMBOL_DELAY_SECONDS = 1

local RAID_ICON_NAMES = {
    [8] = "Skull",
    [7] = "Cross",
    [6] = "Square",
    [5] = "Moon",
    [4] = "Triangle",
    [3] = "Diamond",
    [2] = "Circle",
    [1] = "Star",
}

local DEFAULT_SYMBOLS = {8, 7, 6, 4, 3}
local CLICKER_ROLES = {"primary", "backup", "third", "fourth"}
local CLICKER_ROLE_LABELS = {
    primary = "Primary",
    backup = "Back-up",
    third = "Third",
    fourth = "Fourth",
}

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff5fc9ffTMA:|r " .. tostring(msg))
end

local function Trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function NormalizePlayerName(name)
    if not name or name == "" then
        return nil
    end
    local normalized = Trim(name):gsub("%s+", "")
    normalized = normalized:gsub("^([a-z])", string.upper)
    return normalized
end

local function CanonicalNameKey(name)
    if not name or name == "" then
        return nil
    end
    return string.lower(Trim(name):gsub("%s+", ""))
end

local function NormalizeFullIdentity(name, realm)
    if not name or name == "" then
        return ""
    end

    local playerName = Trim(name):lower()
    local realmName = realm or GetRealmName() or ""
    realmName = Trim(realmName):lower():gsub("%s+", "")

    if string.find(playerName, "-", 1, true) then
        return playerName:gsub("%s+", "")
    end

    return playerName:gsub("%s+", "") .. "-" .. realmName
end

local function IconTextureString(iconIndex)
    return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. iconIndex .. ":0|t"
end

local function IconLabel(iconIndex)
    local iconName = RAID_ICON_NAMES[iconIndex] or ("Icon " .. tostring(iconIndex))
    return IconTextureString(iconIndex) .. " " .. iconName
end

local function AssignmentMessage(iconIndex, role)
    local roleText = "primary"
    if role == "backup" then
        roleText = "back-up"
    elseif role == "third" then
        roleText = "third"
    elseif role == "fourth" then
        roleText = "fourth"
    end
    local iconName = RAID_ICON_NAMES[iconIndex] or ("Icon " .. tostring(iconIndex))
    return "You are the " .. roleText .. " clicker for {" .. string.lower(iconName) .. "}."
end

local function DeepCopyAssignments(src)
    local out = { rows = {}, useFourClickers = src.useFourClickers and true or false }
    for i = 1, ROW_COUNT do
        local row = src.rows[i] or {}
        out.rows[i] = {
            symbol = row.symbol,
            primary = row.primary,
            backup = row.backup,
            third = row.third,
            fourth = row.fourth,
        }
    end
    return out
end

local function BuildDefaultAssignments(useFourClickers)
    local assignments = { rows = {}, useFourClickers = useFourClickers and true or false }
    for i = 1, ROW_COUNT do
        assignments.rows[i] = {
            symbol = DEFAULT_SYMBOLS[i],
            primary = nil,
            backup = nil,
            third = nil,
            fourth = nil,
        }
    end
    return assignments
end

local function ReadAddonMetadata(field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(ADDON_NAME, field)
    end
    if type(GetAddOnMetadata) == "function" then
        return GetAddOnMetadata(ADDON_NAME, field)
    end
    return nil
end

local function GetAddonTitle()
    return ReadAddonMetadata("Title") or "Timber's Mag Assignments"
end

local function GetAddonVersion()
    return ReadAddonMetadata("Version") or "unknown"
end

local function EnsureDB()
    if not TimbersMagAssignmentsDB then
        TimbersMagAssignmentsDB = {}
    end
    local db = TimbersMagAssignmentsDB

    db.assignments = db.assignments or BuildDefaultAssignments()
    db.minimap = db.minimap or { hide = false, angle = 210 }
    db.overlay = db.overlay or { x = 0, y = 0 }
    db.monitor = db.monitor or { enabled = false, x = 0, y = 160, onlyInMagsLair = true }

    if not db.assignments.rows then
        db.assignments = BuildDefaultAssignments()
    end

    for i = 1, ROW_COUNT do
        db.assignments.rows[i] = db.assignments.rows[i] or {
            symbol = DEFAULT_SYMBOLS[i],
            primary = nil,
            backup = nil,
            third = nil,
            fourth = nil,
        }
        if not db.assignments.rows[i].symbol then
            db.assignments.rows[i].symbol = DEFAULT_SYMBOLS[i]
        end
        if db.assignments.rows[i].third == "" then
            db.assignments.rows[i].third = nil
        end
        if db.assignments.rows[i].fourth == "" then
            db.assignments.rows[i].fourth = nil
        end
    end

    if db.assignments.useFourClickers == nil then
        db.assignments.useFourClickers = false
    else
        db.assignments.useFourClickers = db.assignments.useFourClickers and true or false
    end

    db.monitor.enabled = db.monitor.enabled and true or false
    if type(db.monitor.x) ~= "number" then
        db.monitor.x = 0
    end
    if type(db.monitor.y) ~= "number" then
        db.monitor.y = 160
    end
    if db.monitor.onlyInMagsLair == nil then
        db.monitor.onlyInMagsLair = true
    else
        db.monitor.onlyInMagsLair = db.monitor.onlyInMagsLair and true or false
    end

    return db
end

TMA.db = nil
TMA.mainWindow = nil
TMA.importExportWindow = nil
TMA.overlayFrame = nil
TMA.monitorFrame = nil
TMA.minimapButton = nil
TMA.cells = {}
TMA.cellDropdownMenu = nil
TMA.dropdownClickCatcher = nil
TMA.monitorHealthUnits = {}
TMA.monitorHealthDirty = true
TMA.monitorUpdateElapsed = 0
TMA.blastNova = {
    castStartTime = nil,
    castEndTime = nil,
    nextCastTime = nil,
    activeFallbackTime = nil,
    lastObservedCastStartTime = nil,
    shadowCageStartTime = nil,
    shadowCageEndTime = nil,
    cooldownSeconds = BLAST_NOVA_COOLDOWN_SECONDS,
}
TMA.pendingChannelerCombatStart = false
TMA.monitorCombatEndedAt = nil
TMA.currentGroupKey = "SOLO"
TMA.receivedSyncForGroup = false
TMA.awaitingInitialSyncForGroup = false
TMA.addonTitle = nil
TMA.addonVersion = nil
TMA.debugOverlay = false
TMA.addonUsers = {}
TMA.whisperDispatchInProgress = false

function TMA:IsInMagtheridonDungeon()
    local name, instanceType = GetInstanceInfo()
    if not name or name == "" then
        return false
    end

    local normalizedName = string.lower(name)
    return instanceType == "raid" and string.find(normalizedName, "magtheridon", 1, true) ~= nil
end

function TMA:IsMagsLairGateOpen()
    if not self.db or not self.db.monitor or not self.db.monitor.onlyInMagsLair then
        return true
    end

    return self:IsInMagtheridonDungeon()
end

function TMA:IsMonitorTrackingAllowed()
    return self:IsMagsLairGateOpen()
end

function TMA:ResetAddonPresence()
    self.addonUsers = {}
    self:MarkAddonUser(UnitName("player") or "")
end

function TMA:MarkAddonUser(name)
    local normalized = NormalizePlayerName(name)
    if not normalized then
        return
    end

    local key = CanonicalNameKey(normalized)
    if key then
        self.addonUsers[key] = true
    end

    local simple = string.match(normalized, "^([^-]+)")
    if simple then
        self.addonUsers[CanonicalNameKey(simple)] = true
    end

    if not string.find(normalized, "-", 1, true) then
        local realm = Trim(GetRealmName() or ""):gsub("%s+", "")
        if realm ~= "" then
            self.addonUsers[CanonicalNameKey(normalized .. "-" .. realm)] = true
        end
    end
end

function TMA:IsAddonUser(name)
    local normalized = NormalizePlayerName(name)
    if not normalized then
        return false
    end

    local direct = CanonicalNameKey(normalized)
    if direct and self.addonUsers[direct] then
        return true
    end

    local simple = string.match(normalized, "^([^-]+)")
    if simple and self.addonUsers[CanonicalNameKey(simple)] then
        return true
    end

    if not string.find(normalized, "-", 1, true) then
        local realm = Trim(GetRealmName() or ""):gsub("%s+", "")
        if realm ~= "" and self.addonUsers[CanonicalNameKey(normalized .. "-" .. realm)] then
            return true
        end
    end

    return false
end

function TMA:IsSpecialAssigner()
    local name = UnitName("player") or ""
    local realm = GetRealmName() or ""
    local full = NormalizeFullIdentity(name, realm)
    return full == "timberwind-dreamscythe" or full == "serol-dreamscythe"
end

function TMA:IsAssigner()
    if self:IsSpecialAssigner() then
        return true
    end

    if IsInGroup() then
        return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    end

    return false
end

function TMA:GetGroupChannel()
    if UnitInRaid("player") then
        return "RAID"
    end
    if UnitInParty("player") then
        return "PARTY"
    end
    return nil
end

function TMA:IsSenderSelf(sender)
    if not sender or sender == "" then
        return false
    end

    local senderFull = NormalizeFullIdentity(sender)
    local playerFull = NormalizeFullIdentity(UnitName("player") or "", GetRealmName() or "")
    return senderFull ~= "" and playerFull ~= "" and senderFull == playerFull
end

function TMA:GetCurrentGroupKey()
    local channel = self:GetGroupChannel()
    if not channel then
        return "SOLO"
    end

    local names = self:GetRaidRosterNames()
    return channel .. ":" .. table.concat(names, ",")
end

function TMA:RequestAssignmentsFromGroup()
    local channel = self:GetGroupChannel()
    if not channel then
        return
    end

    C_ChatInfo.SendAddonMessage(PREFIX, MSG_REQUEST, channel)
end

function TMA:SendAssignmentsToTarget(target)
    if not target or target == "" then
        return
    end
    if not self:IsAssigner() then
        return
    end

    local payload = MSG_SYNC .. MSG_SEPARATOR .. self:EncodeAssignments()
    C_ChatInfo.SendAddonMessage(PREFIX, payload, "WHISPER", target)
end

function TMA:BroadcastAssignmentsToGroup()
    local channel = self:GetGroupChannel()
    if not channel then
        return
    end
    if not self:IsAssigner() then
        return
    end

    local payload = MSG_SYNC .. MSG_SEPARATOR .. self:EncodeAssignments()
    C_ChatInfo.SendAddonMessage(PREFIX, payload, channel)
end

function TMA:HandleGroupStateChange()
    local newKey = self:GetCurrentGroupKey()
    if newKey == self.currentGroupKey then
        return
    end

    self.currentGroupKey = newKey
    self:ResetAddonPresence()
    self.receivedSyncForGroup = false
    self.awaitingInitialSyncForGroup = false

    if newKey ~= "SOLO" then
        self.awaitingInitialSyncForGroup = true
        self:RequestAssignmentsFromGroup()
    end
end

function TMA:GetRaidRosterNames()
    local names = {}
    local seen = {}

    if UnitInRaid("player") then
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, realm = GetRaidRosterInfo(i)
            if name and name ~= "" then
                local merged = name
                if realm and realm ~= "" then
                    merged = name .. "-" .. realm
                end
                merged = NormalizePlayerName(merged)
                if merged and not seen[merged] then
                    names[#names + 1] = merged
                    seen[merged] = true
                end
            end
        end
    elseif UnitInParty("player") then
        local playerName = UnitName("player")
        if playerName and playerName ~= "" then
            playerName = NormalizePlayerName(playerName)
            names[#names + 1] = playerName
            seen[playerName] = true
        end
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            local name = UnitName(unit)
            if name then
                name = NormalizePlayerName(name)
                if name and not seen[name] then
                    names[#names + 1] = name
                    seen[name] = true
                end
            end
        end
    else
        local playerName = UnitName("player")
        if playerName and playerName ~= "" then
            names[#names + 1] = NormalizePlayerName(playerName)
        end
    end

    table.sort(names)
    return names
end

function TMA:GetCurrentRaidPresenceLookup()
    local lookup = {}
    if not UnitInRaid("player") then
        return lookup
    end

    for i = 1, GetNumGroupMembers() do
        local name, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, realm = GetRaidRosterInfo(i)
        if name and name ~= "" then
            local simple = NormalizePlayerName(name)
            if simple then
                lookup[simple] = true
            end

            if realm and realm ~= "" then
                local merged = NormalizePlayerName(name .. "-" .. realm)
                if merged then
                    lookup[merged] = true
                end
            end
        end
    end

    return lookup
end

function TMA:GetCurrentOnlineLookup()
    local lookup = {}

    if UnitInRaid("player") then
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, _, _, online, _, _, _, _, _, _, _, _, realm = GetRaidRosterInfo(i)
            if name and name ~= "" then
                local normalizedSimple = NormalizePlayerName(name)
                if normalizedSimple then
                    lookup[normalizedSimple] = online and true or false
                end

                if realm and realm ~= "" and not string.find(name, "-", 1, true) then
                    local normalizedFull = NormalizePlayerName(name .. "-" .. realm)
                    if normalizedFull then
                        lookup[normalizedFull] = online and true or false
                    end
                end
            end
        end
    elseif UnitInParty("player") then
        local function AddPartyUnit(unit)
            if not UnitExists(unit) then
                return
            end

            local name, realm = UnitName(unit)
            if not name or name == "" then
                return
            end

            local connected = UnitIsConnected(unit) and true or false
            local normalizedSimple = NormalizePlayerName(name)
            if normalizedSimple then
                lookup[normalizedSimple] = connected
            end

            if realm and realm ~= "" then
                local normalizedFull = NormalizePlayerName(name .. "-" .. realm)
                if normalizedFull then
                    lookup[normalizedFull] = connected
                end
            end
        end

        AddPartyUnit("player")
        for i = 1, GetNumSubgroupMembers() do
            AddPartyUnit("party" .. i)
        end
    end

    return lookup
end

function TMA:IsAssignedNameOffline(name, onlineLookup)
    local normalized = NormalizePlayerName(name)
    if not normalized then
        return false
    end

    local status = onlineLookup and onlineLookup[normalized]
    return status == false
end

function TMA:ApplyOfflineButtonStyle(button, assignedName, onlineLookup)
    if not button then
        return
    end

    local offline = self:IsAssignedNameOffline(assignedName, onlineLookup)
    if offline then
        button:SetAlpha(0.55)
        if button:GetFontString() then
            button:GetFontString():SetTextColor(0.65, 0.65, 0.65)
        end
    else
        button:SetAlpha(1)
        if button:GetFontString() then
            button:GetFontString():SetTextColor(1, 1, 1)
        end
    end
end

function TMA:UpdateRaidPresenceDot(dotTexture, assignedName, raidPresenceLookup)
    if not dotTexture then
        return
    end

    local normalized = NormalizePlayerName(assignedName)
    if not normalized then
        dotTexture:Hide()
        return
    end

    if raidPresenceLookup and raidPresenceLookup[normalized] then
        dotTexture:Show()
    else
        dotTexture:Hide()
    end
end

function TMA:ClearNameFromAssignments(name)
    if not name or name == "" then
        return
    end
    for i = 1, ROW_COUNT do
        local row = self.db.assignments.rows[i]
        for _, role in ipairs(CLICKER_ROLES) do
            if row[role] == name then
                row[role] = nil
            end
        end
    end
end

function TMA:SetCellName(rowIndex, role, name, skipSyncBroadcast)
    local row = self.db.assignments.rows[rowIndex]
    if not row then
        return
    end

    local normalized = NormalizePlayerName(name)
    if normalized == "" then
        normalized = nil
    end

    if normalized then
        self:ClearNameFromAssignments(normalized)
        row[role] = normalized
    else
        row[role] = nil
    end

    self:RefreshMainWindow()
    self:RefreshOverlay()
    self:RefreshMonitor()

    if not skipSyncBroadcast then
        self:BroadcastAssignmentsToGroup()
    end
end

function TMA:SetCellSymbol(rowIndex, iconIndex, skipSyncBroadcast)
    local row = self.db.assignments.rows[rowIndex]
    if not row then
        return
    end
    row.symbol = iconIndex
    self:RefreshMainWindow()
    self:RefreshOverlay()
    self:RefreshMonitor()

    if not skipSyncBroadcast then
        self:BroadcastAssignmentsToGroup()
    end
end

function TMA:ClearAllAssignments(skipSyncBroadcast)
    local keepFourClickers = self.db and self.db.assignments and self.db.assignments.useFourClickers
    self.db.assignments = BuildDefaultAssignments(keepFourClickers)
    self:RefreshMainWindow()
    self:RefreshOverlay()
    self:RefreshMonitor()

    if not skipSyncBroadcast then
        self:BroadcastAssignmentsToGroup()
    end
end

function TMA:EncodeAssignments()
    local fields = {}
    fields[#fields + 1] = self.db.assignments.useFourClickers and "M1" or "M0"
    for i = 1, ROW_COUNT do
        local row = self.db.assignments.rows[i]
        fields[#fields + 1] = tostring(row.symbol or DEFAULT_SYMBOLS[i])
        fields[#fields + 1] = row.primary or ""
        fields[#fields + 1] = row.backup or ""
        fields[#fields + 1] = row.third or ""
        fields[#fields + 1] = row.fourth or ""
    end
    return table.concat(fields, "^")
end

function TMA:DecodeAssignments(payload)
    local parts = {}
    for part in string.gmatch((payload or "") .. "^", "(.-)%^") do
        parts[#parts + 1] = part
    end

    local hasModePrefix = parts[1] == "M0" or parts[1] == "M1"
    local fieldsPerRow = hasModePrefix and 5 or 3
    local startIndex = hasModePrefix and 2 or 1

    if #parts < (startIndex - 1) + (ROW_COUNT * fieldsPerRow) then
        return nil
    end

    local parsed = BuildDefaultAssignments()
    parsed.useFourClickers = hasModePrefix and (parts[1] == "M1") or false

    local idx = startIndex
    for i = 1, ROW_COUNT do
        local symbol = tonumber(parts[idx])
        local primary = Trim(parts[idx + 1] or "")
        local backup = Trim(parts[idx + 2] or "")
        local third = Trim(parts[idx + 3] or "")
        local fourth = Trim(parts[idx + 4] or "")

        if symbol and symbol >= 1 and symbol <= 8 then
            parsed.rows[i].symbol = symbol
        end

        parsed.rows[i].primary = primary ~= "" and NormalizePlayerName(primary) or nil
        parsed.rows[i].backup = backup ~= "" and NormalizePlayerName(backup) or nil
        if fieldsPerRow == 5 then
            parsed.rows[i].third = third ~= "" and NormalizePlayerName(third) or nil
            parsed.rows[i].fourth = fourth ~= "" and NormalizePlayerName(fourth) or nil
        end

        idx = idx + fieldsPerRow
    end

    return parsed
end

function TMA:SendAssignmentsToGroup()
    self:BroadcastAssignmentsToGroup()
    Print("Assignments sent to group.")
end

function TMA:ImportAssignmentsFromText(text)
    local lines = {}
    for line in string.gmatch((text or "") .. "\n", "([^\r\n]*)[\r\n]") do
        local n = NormalizePlayerName(Trim(line))
        if n and n ~= "" then
            lines[#lines + 1] = n
        end
    end

    self:ClearAllAssignments(true)

    local rolesToImport = self.db.assignments.useFourClickers and CLICKER_ROLES or {"primary", "backup"}
    local slot = 1
    for i = 1, ROW_COUNT do
        for _, role in ipairs(rolesToImport) do
            if lines[slot] then
                self:SetCellName(i, role, lines[slot], true)
            end
            slot = slot + 1
        end
    end

    self:RefreshMainWindow()
    self:RefreshOverlay()
    self:RefreshMonitor()
    self:BroadcastAssignmentsToGroup()
end

function TMA:ExportAssignmentsToText()
    local out = {}
    local rolesToExport = self.db.assignments.useFourClickers and CLICKER_ROLES or {"primary", "backup"}
    for i = 1, ROW_COUNT do
        local row = self.db.assignments.rows[i]
        for _, role in ipairs(rolesToExport) do
            out[#out + 1] = row[role] or ""
        end
    end
    return table.concat(out, "\n")
end

function TMA:FindMyAssignment()
    local playerName = NormalizePlayerName(UnitName("player") or "")
    if not playerName or playerName == "" then
        return nil
    end

    for i = 1, ROW_COUNT do
        local row = self.db.assignments.rows[i]
        for _, role in ipairs(CLICKER_ROLES) do
            if row[role] == playerName then
                return row.symbol or DEFAULT_SYMBOLS[i], role
            end
        end
    end

    return nil
end

function TMA:GetActiveClickerRoles()
    if self.db and self.db.assignments and self.db.assignments.useFourClickers then
        return CLICKER_ROLES
    end

    return {"primary", "backup"}
end

function TMA:ResetBlastNovaTracking()
    self.blastNova.castStartTime = nil
    self.blastNova.castEndTime = nil
    self.blastNova.nextCastTime = nil
    self.blastNova.activeFallbackTime = nil
    self.blastNova.lastObservedCastStartTime = nil
    self.blastNova.shadowCageStartTime = nil
    self.blastNova.shadowCageEndTime = nil
    self.blastNova.cooldownSeconds = BLAST_NOVA_COOLDOWN_SECONDS
    self.pendingChannelerCombatStart = false
    self.monitorCombatEndedAt = nil
    self:UpdateMonitorCastBar()
end

function TMA:StartMagActiveFallbackTimer()
    if not self:IsMonitorTrackingAllowed() then
        return
    end

    local now = GetTime()
    self.monitorCombatEndedAt = nil
    self.blastNova.castStartTime = nil
    self.blastNova.castEndTime = nil
    self.blastNova.nextCastTime = nil
    self.blastNova.activeFallbackTime = now + MAG_ACTIVE_FALLBACK_SECONDS
    self:UpdateMonitorCastBar()
end

function TMA:IsHellfireChannelerName(name)
    local lower = string.lower(name or "")
    return string.find(lower, HELLFIRE_CHANNELER_NAME, 1, true) ~= nil
end

function TMA:IsMagtheridonName(name)
    local lower = string.lower(name or "")
    return string.find(lower, "magtheridon", 1, true) ~= nil
end

function TMA:IsShadowCageSpell(spellId, spellName)
    if spellId == SHADOW_CAGE_SPELL_ID then
        return true
    end

    local localizedShadowCageName = GetSpellInfo(SHADOW_CAGE_SPELL_ID)
    if localizedShadowCageName and spellName and string.lower(spellName) == string.lower(localizedShadowCageName) then
        return true
    end

    local lowerSpellName = string.lower(spellName or "")
    return lowerSpellName ~= "" and string.find(lowerSpellName, "shadow cage", 1, true) ~= nil
end

function TMA:StartShadowCageWindow()
    local now = GetTime()
    self.blastNova.shadowCageStartTime = now
    self.blastNova.shadowCageEndTime = now + SHADOW_CAGE_DURATION_SECONDS
    self:UpdateMonitorCastBar()
end

function TMA:EndShadowCageWindow()
    self.blastNova.shadowCageStartTime = nil
    self.blastNova.shadowCageEndTime = nil
    self:UpdateMonitorCastBar()
end

function TMA:TryStartMagFallbackFromChannelerCombat(sourceName, destName)
    if not self.pendingChannelerCombatStart or not self:IsMonitorTrackingAllowed() then
        return
    end

    if self.blastNova.activeFallbackTime or self.blastNova.nextCastTime or self.blastNova.castStartTime then
        self.pendingChannelerCombatStart = false
        return
    end

    if self:IsHellfireChannelerName(sourceName) or self:IsHellfireChannelerName(destName) then
        self.pendingChannelerCombatStart = false
        self:StartMagActiveFallbackTimer()
    end
end

function TMA:StartFirstBlastNovaTimer()
    if not self:IsMonitorTrackingAllowed() then
        return
    end

    self.pendingChannelerCombatStart = false
    self.monitorCombatEndedAt = nil
    local now = GetTime()
    self.blastNova.castStartTime = nil
    self.blastNova.castEndTime = nil
    self.blastNova.activeFallbackTime = nil
    self.blastNova.lastObservedCastStartTime = nil
    self.blastNova.cooldownSeconds = BLAST_NOVA_COOLDOWN_SECONDS
    self.blastNova.nextCastTime = now + BLAST_NOVA_COOLDOWN_SECONDS
    self:UpdateMonitorCastBar()
end

function TMA:StartBlastNovaCast()
    if not self:IsMonitorTrackingAllowed() then
        return
    end

    self.pendingChannelerCombatStart = false
    self.monitorCombatEndedAt = nil
    local now = GetTime()

    if self.blastNova.lastObservedCastStartTime then
        local delta = now - self.blastNova.lastObservedCastStartTime
        if delta >= 40 and delta <= 80 then
            self.blastNova.cooldownSeconds = delta
        end
    end
    self.blastNova.lastObservedCastStartTime = now

    self.blastNova.castStartTime = now
    self.blastNova.castEndTime = now + BLAST_NOVA_CAST_SECONDS
    self.blastNova.nextCastTime = nil
    self.blastNova.activeFallbackTime = nil
    self:RefreshMonitor()
end

function TMA:MaybeResetBlastNovaAfterCombatDrop(now)
    now = now or GetTime()
    if not self.monitorCombatEndedAt then
        return
    end

    if now - self.monitorCombatEndedAt <= 5 then
        return
    end

    self.monitorCombatEndedAt = nil
    self:ResetBlastNovaTracking()
end

function TMA:AdvanceBlastNovaState(now)
    now = now or GetTime()
    local cooldown = self.blastNova.cooldownSeconds or BLAST_NOVA_COOLDOWN_SECONDS

    if self.blastNova.castEndTime and now >= self.blastNova.castEndTime then
        local castStartTime = self.blastNova.castStartTime or now
        self.blastNova.castStartTime = nil
        self.blastNova.castEndTime = nil
        self.blastNova.nextCastTime = castStartTime + cooldown
    end

    if self.blastNova.activeFallbackTime and now >= self.blastNova.activeFallbackTime then
        self.blastNova.nextCastTime = self.blastNova.activeFallbackTime + cooldown
        self.blastNova.activeFallbackTime = nil
    end

    if self.blastNova.shadowCageEndTime and now >= self.blastNova.shadowCageEndTime then
        self.blastNova.shadowCageStartTime = nil
        self.blastNova.shadowCageEndTime = nil
    end
end

function TMA:RebuildMonitorHealthUnits()
    for key in pairs(self.monitorHealthUnits) do
        self.monitorHealthUnits[key] = nil
    end

    local function AddUnit(unit)
        if not UnitExists(unit) then
            return
        end

        local name, realm = UnitName(unit)
        local normalized = NormalizePlayerName(name)
        if normalized then
            self.monitorHealthUnits[normalized] = unit
        end

        if name and realm and realm ~= "" then
            local normalizedFull = NormalizePlayerName(name .. "-" .. realm)
            if normalizedFull then
                self.monitorHealthUnits[normalizedFull] = unit
            end
        end
    end

    AddUnit("player")

    if UnitInRaid("player") then
        for i = 1, GetNumGroupMembers() do
            AddUnit("raid" .. i)
        end
    elseif UnitInParty("player") then
        for i = 1, GetNumSubgroupMembers() do
            AddUnit("party" .. i)
        end
    end

    self.monitorHealthDirty = false
end

function TMA:GetMonitorHealthPercent(name)
    if self.monitorHealthDirty then
        self:RebuildMonitorHealthUnits()
    end

    local normalized = NormalizePlayerName(name)
    local unit = normalized and self.monitorHealthUnits[normalized]
    if not unit or not UnitExists(unit) or not UnitIsConnected(unit) then
        return nil
    end

    local maxHealth = UnitHealthMax(unit) or 0
    if maxHealth <= 0 then
        return nil
    end

    local health = UnitHealth(unit) or 0
    if health < 0 then
        health = 0
    elseif health > maxHealth then
        health = maxHealth
    end

    return health / maxHealth
end

function TMA:SetMonitorStatusBarColor(bar, percent)
    if not percent then
        bar:SetStatusBarColor(0.35, 0.35, 0.35, 0.85)
        return
    end

    if percent <= 0.25 then
        bar:SetStatusBarColor(0.8, 0.12, 0.08, 0.95)
    elseif percent <= 0.55 then
        bar:SetStatusBarColor(0.9, 0.58, 0.12, 0.95)
    else
        bar:SetStatusBarColor(0.18, 0.72, 0.24, 0.95)
    end
end

function TMA:UpdateMonitorCastBar()
    local f = self.monitorFrame
    if not f or not f.castBar then
        return
    end

    local now = GetTime()
    local bar = f.castBar
    self:AdvanceBlastNovaState(now)

    if self.blastNova.shadowCageEndTime and self.blastNova.shadowCageStartTime then
        local duration = self.blastNova.shadowCageEndTime - self.blastNova.shadowCageStartTime
        local remaining = self.blastNova.shadowCageEndTime - now
        if remaining < 0 then
            remaining = 0
        end
        local progress = 1
        if duration > 0 then
            progress = 1 - (remaining / duration)
        end
        if progress < 0 then
            progress = 0
        elseif progress > 1 then
            progress = 1
        end
        bar:SetValue(progress)
        bar:SetStatusBarColor(0.72, 0.28, 0.9, 0.95)
        f.castText:SetText("Shadow Cage ends in " .. tostring(math.ceil(remaining)) .. "s")
        return
    end

    if self.blastNova.castEndTime and self.blastNova.castStartTime then
        local duration = self.blastNova.castEndTime - self.blastNova.castStartTime
        local progress = (now - self.blastNova.castStartTime) / duration
        if progress < 0 then
            progress = 0
        elseif progress > 1 then
            progress = 1
        end
        bar:SetValue(progress)
        bar:SetStatusBarColor(0.9, 0.22, 0.14, 0.95)
        f.castText:SetText("Blast Nova casting")
        return
    end

    if self.blastNova.nextCastTime then
        local remaining = self.blastNova.nextCastTime - now
        if remaining < 0 then
            remaining = 0
        end
        local cooldown = self.blastNova.cooldownSeconds or BLAST_NOVA_COOLDOWN_SECONDS
        local progress = 1 - (remaining / cooldown)
        if progress < 0 then
            progress = 0
        elseif progress > 1 then
            progress = 1
        end
        bar:SetValue(progress)
        bar:SetStatusBarColor(0.18, 0.52, 0.9, 0.95)
        f.castText:SetText("Blast Nova in " .. tostring(math.ceil(remaining)) .. "s")
        return
    end

    if self.blastNova.activeFallbackTime then
        local remaining = self.blastNova.activeFallbackTime - now
        if remaining < 0 then
            remaining = 0
        end
        local progress = 1 - (remaining / MAG_ACTIVE_FALLBACK_SECONDS)
        if progress < 0 then
            progress = 0
        elseif progress > 1 then
            progress = 1
        end
        bar:SetValue(progress)
        bar:SetStatusBarColor(0.65, 0.42, 0.9, 0.95)
        f.castText:SetText("Channelled state ends in " .. tostring(math.ceil(remaining)) .. "s")
        return
    end

    bar:SetValue(0)
    bar:SetStatusBarColor(0.28, 0.28, 0.28, 0.9)
    f.castText:SetText("Blast Nova ready")
end

function TMA:UpdateMonitorHealthBars()
    local f = self.monitorFrame
    if not f or not f.gridCells then
        return
    end

    local activeRoleCount = self.db.assignments.useFourClickers and 4 or 2

    for symbolRow = 1, MONITOR_SYMBOL_ROWS do
        local assignmentRow = self.db.assignments.rows[symbolRow]
        local iconIndex = (assignmentRow and assignmentRow.symbol) or DEFAULT_SYMBOLS[symbolRow]
        if f.rowSymbols and f.rowSymbols[symbolRow] then
            f.rowSymbols[symbolRow]:SetText(IconTextureString(iconIndex))
        end

        for roleCol = 1, MONITOR_CLICKER_COLUMNS do
            local cell = f.gridCells[symbolRow] and f.gridCells[symbolRow][roleCol]
            if cell then
                if roleCol <= activeRoleCount then
                    local role = CLICKER_ROLES[roleCol]
                    local name = assignmentRow and assignmentRow[role] or nil
                    local percent = name and self:GetMonitorHealthPercent(name) or nil

                    cell.nameText:SetText(name or "-")
                    cell.healthBar:SetValue(percent or 0)
                    self:SetMonitorStatusBarColor(cell.healthBar, percent)
                    if percent then
                        cell.nameText:SetTextColor(1, 1, 1)
                    else
                        cell.nameText:SetTextColor(0.65, 0.65, 0.65)
                    end
                    cell:Show()
                else
                    cell:Hide()
                end
            end
        end
    end
end

function TMA:RefreshMonitor()
    if not self.monitorFrame then
        return
    end

    local f = self.monitorFrame
    local canShow = self.db and self.db.monitor and self.db.monitor.enabled and self:IsMagsLairGateOpen()
    if not canShow then
        f:Hide()
        return
    end

    local activeRoleCount = self.db.assignments.useFourClickers and 4 or 2
    local totalHeight = 88 + (MONITOR_SYMBOL_ROWS * (MONITOR_BAR_HEIGHT + 5))
    local totalWidth = 44 + (activeRoleCount * (MONITOR_BAR_WIDTH + 6))
    f:SetWidth(totalWidth)
    f:SetHeight(totalHeight)

    if f.gridCells then
        for symbolRow = 1, MONITOR_SYMBOL_ROWS do
            for roleCol = 1, MONITOR_CLICKER_COLUMNS do
                local cell = f.gridCells[symbolRow] and f.gridCells[symbolRow][roleCol]
                if cell then
                    local x = 32 + ((roleCol - 1) * (MONITOR_BAR_WIDTH + 6))
                    local y = -58 - ((symbolRow - 1) * (MONITOR_BAR_HEIGHT + 5))
                    cell:ClearAllPoints()
                    cell:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
                end
            end
        end
    end

    if f.rowSymbols then
        for symbolRow = 1, MONITOR_SYMBOL_ROWS do
            local icon = f.rowSymbols[symbolRow]
            if icon then
                local y = -58 - ((symbolRow - 1) * (MONITOR_BAR_HEIGHT + 5)) - math.floor(MONITOR_BAR_HEIGHT / 2)
                icon:ClearAllPoints()
                icon:SetPoint("CENTER", f, "TOPLEFT", 16, y)
            end
        end
    end

    self:MaybeResetBlastNovaAfterCombatDrop()
    self:UpdateMonitorCastBar()
    self:UpdateMonitorHealthBars()
    f:Show()
end

function TMA:ToggleMonitor()
    self.db.monitor.enabled = not self.db.monitor.enabled
    self:RefreshMainWindow()
    self:RefreshMonitor()
end

function TMA:OnMonitorUpdate(elapsed)
    self.monitorUpdateElapsed = self.monitorUpdateElapsed + elapsed

    local now = GetTime()
    self:MaybeResetBlastNovaAfterCombatDrop(now)
    self:AdvanceBlastNovaState(now)
    self:UpdateMonitorCastBar()

    if self.monitorUpdateElapsed >= 0.2 then
        self.monitorUpdateElapsed = 0
        self:UpdateMonitorHealthBars()
    end
end

function TMA:RefreshOverlay()
    if not self.overlayFrame then
        return
    end

    if not self.debugOverlay and not self:IsMagsLairGateOpen() then
        self.overlayFrame:Hide()
        return
    end

    local iconIndex, role = self:FindMyAssignment()
    if not iconIndex then
        self.overlayFrame:Hide()
        return
    end

    local roleText = "Primary Clicker"
    if role == "backup" then
        roleText = "Back-up Clicker"
    elseif role == "third" then
        roleText = "Third Clicker"
    elseif role == "fourth" then
        roleText = "Fourth Clicker"
    end
    self.overlayFrame.text:SetText(IconTextureString(iconIndex) .. " " .. roleText .. " " .. IconTextureString(iconIndex))
    self.overlayFrame:Show()
end

function TMA:WhisperAssignments()
    if self.whisperDispatchInProgress then
        Print("Assignment whispers are already in progress.")
        return
    end

    self.whisperDispatchInProgress = true
    local sent = 0
    local attempted = 0
    local rolesToWhisper = self.db.assignments.useFourClickers and CLICKER_ROLES or {"primary", "backup"}

    local function SendRow(rowIndex)
        if rowIndex > ROW_COUNT then
            TMA.whisperDispatchInProgress = false
            Print("Sent " .. sent .. " assignment whisper(s) from " .. attempted .. " attempt(s).")
            return
        end

        local row = TMA.db.assignments.rows[rowIndex]
        local iconIndex = row.symbol or DEFAULT_SYMBOLS[rowIndex]

        for _, role in ipairs(rolesToWhisper) do
            local target = row[role]
            if target and target ~= "" then
                SendChatMessage(AssignmentMessage(iconIndex, role), "WHISPER", nil, target)
                attempted = attempted + 1
                sent = sent + 1
            end
        end

        if rowIndex < ROW_COUNT and C_Timer and C_Timer.After then
            C_Timer.After(WHISPER_SYMBOL_DELAY_SECONDS, function()
                SendRow(rowIndex + 1)
            end)
        else
            SendRow(rowIndex + 1)
        end
    end

    SendRow(1)
end

function TMA:RefreshMainWindow()
    if not self.mainWindow then
        return
    end

    local canEdit = self:IsAssigner()
    local useFourClickers = self.db.assignments.useFourClickers and true or false
    local tableTop = -74
    local rowStartY = -96
    local rowHeight = 44

    local left = 18
    local symbolWidth = 80
    local gap = 10
    local visibleNameColumns = useFourClickers and 4 or 2
    local nameWidth = useFourClickers and 140 or 198
    local tableWidth = symbolWidth + (visibleNameColumns * nameWidth) + (visibleNameColumns * gap)
    local rowBackdropWidth = tableWidth + 4
    local frameWidth = (left - 4) + rowBackdropWidth + 26
    local raidPresenceLookup = self:GetCurrentRaidPresenceLookup()
    local onlineLookup = self:GetCurrentOnlineLookup()

    self.mainWindow:SetWidth(frameWidth)

    if self.mainWindow.importButton and self.mainWindow.sendButton and self.mainWindow.clearButton and self.mainWindow.monitorButton then
        self.mainWindow.monitorButton:SetText(self.db.monitor.enabled and "Hide Overlay" or "Show Overlay")
        self.mainWindow.monitorButton:Show()

        if canEdit then
            self.mainWindow.importButton:Show()
            if self.mainWindow.exportButton then
                self.mainWindow.exportButton:Hide()
            end
            self.mainWindow.sendButton:Show()
            self.mainWindow.clearButton:Show()
            self.mainWindow:SetHeight(410)

            self.mainWindow.importButton:ClearAllPoints()
            self.mainWindow.importButton:SetPoint("TOPRIGHT", self.mainWindow, "TOPRIGHT", -18, -36)

            self.mainWindow.sendButton:ClearAllPoints()
            self.mainWindow.sendButton:SetPoint("BOTTOMLEFT", self.mainWindow, "BOTTOMLEFT", 18, 42)
            self.mainWindow.monitorButton:ClearAllPoints()
            self.mainWindow.monitorButton:SetPoint("LEFT", self.mainWindow.sendButton, "RIGHT", 8, 0)
            self.mainWindow.clearButton:ClearAllPoints()
            self.mainWindow.clearButton:SetPoint("BOTTOMRIGHT", self.mainWindow, "BOTTOMRIGHT", -18, 42)
        else
            self.mainWindow.importButton:Hide()
            if self.mainWindow.exportButton then
                self.mainWindow.exportButton:Hide()
            end
            self.mainWindow.sendButton:Hide()
            self.mainWindow.clearButton:Hide()
            self.mainWindow:SetHeight(360)
            self.mainWindow.monitorButton:ClearAllPoints()
            self.mainWindow.monitorButton:SetPoint("BOTTOMLEFT", self.mainWindow, "BOTTOMLEFT", 18, 18)
        end
    end

    if self.mainWindow.modeCheck and self.mainWindow.modeCheckLabel and self.mainWindow.magOnlyCheck and self.mainWindow.magOnlyCheckLabel then
        self.mainWindow.modeCheck:SetChecked(useFourClickers)
        self.mainWindow.magOnlyCheck:SetChecked(self.db.monitor.onlyInMagsLair)
        self.mainWindow.magOnlyCheck:Show()
        self.mainWindow.magOnlyCheckLabel:Show()
        self.mainWindow.magOnlyCheck:Enable()
        self.mainWindow.magOnlyCheckLabel:SetTextColor(1, 0.82, 0)
        if canEdit then
            self.mainWindow.modeCheck:Show()
            self.mainWindow.modeCheckLabel:Show()
            self.mainWindow.modeCheck:Enable()
            self.mainWindow.modeCheckLabel:SetTextColor(1, 0.82, 0)
            self.mainWindow.modeCheck:ClearAllPoints()
            self.mainWindow.modeCheck:SetPoint("TOPLEFT", self.mainWindow, "TOPLEFT", 14, -34)
            self.mainWindow.modeCheckLabel:ClearAllPoints()
            self.mainWindow.modeCheckLabel:SetPoint("LEFT", self.mainWindow.modeCheck, "RIGHT", 2, 1)
            self.mainWindow.magOnlyCheck:ClearAllPoints()
            self.mainWindow.magOnlyCheck:SetPoint("LEFT", self.mainWindow.modeCheckLabel, "RIGHT", 22, -1)
        else
            self.mainWindow.modeCheck:Hide()
            self.mainWindow.modeCheckLabel:Hide()
            self.mainWindow.magOnlyCheck:ClearAllPoints()
            self.mainWindow.magOnlyCheck:SetPoint("TOPLEFT", self.mainWindow, "TOPLEFT", 14, -34)
        end
    end

    if self.mainWindow.symbolHeader and self.mainWindow.primaryHeader and self.mainWindow.backupHeader and self.mainWindow.thirdHeader and self.mainWindow.fourthHeader then
        local primaryCenterX = left + symbolWidth + gap + (nameWidth * 0.5)
        local backupCenterX = left + symbolWidth + gap + nameWidth + gap + (nameWidth * 0.5)
        local thirdCenterX = left + symbolWidth + gap + (nameWidth + gap) * 2 + (nameWidth * 0.5)
        local fourthCenterX = left + symbolWidth + gap + (nameWidth + gap) * 3 + (nameWidth * 0.5)

        self.mainWindow.symbolHeader:ClearAllPoints()
        self.mainWindow.symbolHeader:SetPoint("TOPLEFT", self.mainWindow, "TOPLEFT", 32, tableTop)
        self.mainWindow.primaryHeader:ClearAllPoints()
        self.mainWindow.primaryHeader:SetPoint("TOP", self.mainWindow, "TOPLEFT", primaryCenterX, tableTop)
        self.mainWindow.backupHeader:ClearAllPoints()
        self.mainWindow.backupHeader:SetPoint("TOP", self.mainWindow, "TOPLEFT", backupCenterX, tableTop)

        if useFourClickers then
            self.mainWindow.primaryHeader:SetText("Clicker 1")
            self.mainWindow.backupHeader:SetText("Clicker 2")
            self.mainWindow.thirdHeader:ClearAllPoints()
            self.mainWindow.thirdHeader:SetPoint("TOP", self.mainWindow, "TOPLEFT", thirdCenterX, tableTop)
            self.mainWindow.thirdHeader:SetText("Clicker 3")
            self.mainWindow.thirdHeader:Show()
            self.mainWindow.fourthHeader:ClearAllPoints()
            self.mainWindow.fourthHeader:SetPoint("TOP", self.mainWindow, "TOPLEFT", fourthCenterX, tableTop)
            self.mainWindow.fourthHeader:SetText("Clicker 4")
            self.mainWindow.fourthHeader:Show()
        else
            self.mainWindow.primaryHeader:SetText("Primary")
            self.mainWindow.backupHeader:SetText("Back-up")
            self.mainWindow.thirdHeader:Hide()
            self.mainWindow.fourthHeader:Hide()
        end
    end

    for i = 1, ROW_COUNT do
        local row = self.db.assignments.rows[i]
        local cell = self.cells[i]
        if cell then
            local y = rowStartY - ((i - 1) * rowHeight)
            if cell.rowBackdrop and cell.symbolButton and cell.primaryButton and cell.backupButton and cell.thirdButton and cell.fourthButton then
                cell.rowBackdrop:ClearAllPoints()
                cell.rowBackdrop:SetPoint("TOPLEFT", self.mainWindow, "TOPLEFT", 14, y + 4)
                cell.rowBackdrop:SetWidth(rowBackdropWidth)

                cell.symbolButton:ClearAllPoints()
                cell.symbolButton:SetPoint("TOPLEFT", self.mainWindow, "TOPLEFT", 18, y)

                cell.primaryButton:SetWidth(nameWidth)
                cell.backupButton:SetWidth(nameWidth)
                cell.thirdButton:SetWidth(nameWidth)
                cell.fourthButton:SetWidth(nameWidth)

                cell.primaryButton:ClearAllPoints()
                cell.primaryButton:SetPoint("LEFT", cell.symbolButton, "RIGHT", gap, 0)
                cell.backupButton:ClearAllPoints()
                cell.backupButton:SetPoint("LEFT", cell.primaryButton, "RIGHT", gap, 0)

                if useFourClickers then
                    cell.thirdButton:ClearAllPoints()
                    cell.thirdButton:SetPoint("LEFT", cell.backupButton, "RIGHT", gap, 0)
                    cell.thirdButton:Show()
                    cell.fourthButton:ClearAllPoints()
                    cell.fourthButton:SetPoint("LEFT", cell.thirdButton, "RIGHT", gap, 0)
                    cell.fourthButton:Show()
                else
                    cell.thirdButton:Hide()
                    cell.fourthButton:Hide()
                end
            end

            local primaryName = row.primary
            local backupName = row.backup
            local thirdName = row.third
            local fourthName = row.fourth

            cell.symbol:SetText(IconTextureString(row.symbol or DEFAULT_SYMBOLS[i]))
            cell.primary:SetText(primaryName or "-")
            cell.backup:SetText(backupName or "-")
            cell.third:SetText(thirdName or "-")
            cell.fourth:SetText(fourthName or "-")

            self:ApplyOfflineButtonStyle(cell.primaryButton, primaryName, onlineLookup)
            self:ApplyOfflineButtonStyle(cell.backupButton, backupName, onlineLookup)
            self:ApplyOfflineButtonStyle(cell.thirdButton, thirdName, onlineLookup)
            self:ApplyOfflineButtonStyle(cell.fourthButton, fourthName, onlineLookup)

            self:UpdateRaidPresenceDot(cell.primaryDot, primaryName, raidPresenceLookup)
            self:UpdateRaidPresenceDot(cell.backupDot, backupName, raidPresenceLookup)
            self:UpdateRaidPresenceDot(cell.thirdDot, thirdName, raidPresenceLookup)
            self:UpdateRaidPresenceDot(cell.fourthDot, fourthName, raidPresenceLookup)

            if primaryName and self:IsAddonUser(primaryName) then
                cell.primaryRightDot:Show()
            else
                cell.primaryRightDot:Hide()
            end
            if backupName and self:IsAddonUser(backupName) then
                cell.backupRightDot:Show()
            else
                cell.backupRightDot:Hide()
            end
            if thirdName and self:IsAddonUser(thirdName) then
                cell.thirdRightDot:Show()
            else
                cell.thirdRightDot:Hide()
            end
            if fourthName and self:IsAddonUser(fourthName) then
                cell.fourthRightDot:Show()
            else
                cell.fourthRightDot:Hide()
            end

            if not useFourClickers then
                if cell.thirdDot then
                    cell.thirdDot:Hide()
                end
                if cell.fourthDot then
                    cell.fourthDot:Hide()
                end
                if cell.thirdRightDot then
                    cell.thirdRightDot:Hide()
                end
                if cell.fourthRightDot then
                    cell.fourthRightDot:Hide()
                end
            end
        end
    end
end

function TMA:EnsureCellDropdownMenu()
    if self.cellDropdownMenu then
        return
    end
    self.cellDropdownMenu = CreateFrame("Frame", "TMACellDropdownMenu", UIParent, "UIDropDownMenuTemplate")
    self.cellDropdownMenu.displayMode = "MENU"
end

function TMA:EnsureDropdownClickCatcher()
    if self.dropdownClickCatcher then
        return
    end

    local catcher = CreateFrame("Button", "TMADropdownClickCatcher", UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("LOW")
    catcher:SetFrameLevel(0)
    catcher:EnableMouse(true)
    catcher:RegisterForClicks("LeftButtonDown", "RightButtonDown")
    catcher:SetScript("OnClick", function()
        CloseDropDownMenus()
        TMA:HideDropdownClickCatcher()
    end)
    catcher:Hide()

    self.dropdownClickCatcher = catcher
end

function TMA:ShowDropdownClickCatcher()
    self:EnsureDropdownClickCatcher()
    self.dropdownClickCatcher:Show()
end

function TMA:HideDropdownClickCatcher()
    if self.dropdownClickCatcher then
        self.dropdownClickCatcher:Hide()
    end
end

local function ShowDropdownMenu(menuFrame, entries, anchor, useCursor)
    UIDropDownMenu_Initialize(menuFrame, function(_, level)
        if not level or level ~= 1 then
            return
        end

        for _, entry in ipairs(entries) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = entry.text
            info.func = function(...)
                if entry.func then
                    entry.func(...)
                end
                TMA:HideDropdownClickCatcher()
            end
            info.notCheckable = entry.notCheckable
            info.isTitle = entry.isTitle
            info.disabled = entry.disabled
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")

    if useCursor then
        ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
    else
        ToggleDropDownMenu(1, nil, menuFrame, anchor, 0, 0)
    end

    if DropDownList1 and DropDownList1:IsShown() then
        TMA:ShowDropdownClickCatcher()
    else
        TMA:HideDropdownClickCatcher()
    end
end

function TMA:OpenCellDropdown(rowIndex, kind, anchor)
    if not self:IsAssigner() then
        return
    end

    self:EnsureCellDropdownMenu()

    local entries = {}

    if kind == "symbol" then
        for iconIndex = 8, 1, -1 do
            entries[#entries + 1] = {
                text = IconLabel(iconIndex),
                notCheckable = true,
                func = function()
                    TMA:SetCellSymbol(rowIndex, iconIndex)
                end,
            }
        end
    else
        local names = self:GetRaidRosterNames()
        if #names == 0 then
            entries[#entries + 1] = {
                text = "No raid members found",
                notCheckable = true,
                func = function() end,
            }
        else
            for _, name in ipairs(names) do
                entries[#entries + 1] = {
                    text = name,
                    notCheckable = true,
                    func = function()
                        TMA:SetCellName(rowIndex, kind, name)
                    end,
                }
            end
        end
    end

    ShowDropdownMenu(self.cellDropdownMenu, entries, anchor, false)
end

function TMA:CreateImportExportWindow()
    if self.importExportWindow then
        return
    end

    local f = CreateFrame("Frame", "TMAImportExportWindow", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(420, 280)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", function(selfFrame)
        selfFrame:StartMoving()
    end)
    f:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
    end)
    f:SetScript("OnShow", function(selfFrame)
        selfFrame:Raise()
    end)
    f:Hide()

    if not tContains(UISpecialFrames, "TMAImportExportWindow") then
        table.insert(UISpecialFrames, "TMAImportExportWindow")
    end

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("LEFT", f.TitleBg, "LEFT", 8, 0)
    f.title:SetText("Import/Export")

    f.hintText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.hintText:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -34)
    f.hintText:SetText("One character per line")

    local scroll = CreateFrame("ScrollFrame", "TMAMultiLineEditScroll", f, "InputScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -50)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 16)

    local editBox = scroll.EditBox
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(350)
    editBox:SetScript("OnEscapePressed", function()
        f:Hide()
    end)

    scroll:SetScript("OnShow", function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)

    if scroll.CharCount then
        scroll.CharCount:Hide()
        scroll.CharCount.Show = function() end
    end

    local charCount = _G["TMAMultiLineEditScrollCharCount"]
    if charCount then
        charCount:Hide()
        charCount.Show = function() end
    end

    local applyImportButton = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    applyImportButton:SetSize(90, 22)
    applyImportButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 14)
    applyImportButton:SetText("Save")
    applyImportButton:SetScript("OnClick", function()
        if not TMA:IsAssigner() then
            Print("Only assigners can save assignments.")
            return
        end

        local text = f.editBox:GetText() or ""
        TMA:ImportAssignmentsFromText(text)
        f:Hide()
        Print("Assignments saved.")
    end)

    f.editBox = editBox
    f.scroll = scroll
    f.applyImportButton = applyImportButton
    self.importExportWindow = f
end

function TMA:ShowImportExport()
    self:CreateImportExportWindow()
    local f = self.importExportWindow
    f.mode = "importexport"
    f:SetHeight(280)
    f.scroll:ClearAllPoints()
    f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -50)
    f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 46)
    f.applyImportButton:Show()
    f.title:SetText("Import/Export")
    f.editBox:SetText(self:ExportAssignmentsToText())
    f.editBox:HighlightText()

    f:Show()
    f:Raise()
end

function TMA:CreateOverlay()
    if self.overlayFrame then
        return
    end

    local f = CreateFrame("Frame", "TMAOverlayFrame", UIParent, "BackdropTemplate")
    f:SetSize(260, 50)
    f:SetPoint("CENTER", UIParent, "CENTER", self.db.overlay.x, self.db.overlay.y)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(selfFrame)
        if IsShiftKeyDown() then
            selfFrame:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
        local _, _, _, x, y = selfFrame:GetPoint()
        TMA.db.overlay.x = math.floor(x + 0.5)
        TMA.db.overlay.y = math.floor(y + 0.5)
    end)

    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })

    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("CENTER", f, "CENTER", 0, 7)
    text:SetText("")
    f.text = text

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("CENTER", f, "CENTER", 0, -11)
    hint:SetText("Hold Shift to drag")
    f.hint = hint

    local openBtn = CreateFrame("Button", nil, f)
    openBtn:SetSize(18, 18)
    openBtn:SetPoint("BOTTOMLEFT", f, "TOPRIGHT", -9, -9)
    openBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-Maximize-Up")
    openBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-Maximize-Down")
    openBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    openBtn:SetScript("OnClick", function() TMA:ToggleMainWindow() end)
    f.openButton = openBtn

    f:Hide()

    self.overlayFrame = f
end

function TMA:CreateMonitor()
    if self.monitorFrame then
        return
    end

    local f = CreateFrame("Frame", "TMAMonitorOverlay", UIParent, "BackdropTemplate")
    f:SetSize(360, 260)
    f:SetPoint("CENTER", UIParent, "CENTER", self.db.monitor.x, self.db.monitor.y)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", function(selfFrame)
        selfFrame:StartMoving()
    end)
    f:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
        local _, _, _, x, y = selfFrame:GetPoint()
        TMA.db.monitor.x = math.floor((x or 0) + 0.5)
        TMA.db.monitor.y = math.floor((y or 0) + 0.5)
    end)
    f:SetScript("OnUpdate", function(_, elapsed)
        TMA:OnMonitorUpdate(elapsed)
    end)

    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(0, 0, 0, 0.82)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
    title:SetText("Magtheridon Clickers")
    f.title = title

    local closeButton = CreateFrame("Button", nil, f)
    closeButton:SetSize(18, 18)
    closeButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    closeButton:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeButton:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeButton:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    closeButton:SetScript("OnClick", function()
        TMA.db.monitor.enabled = false
        TMA:RefreshMainWindow()
        TMA:RefreshMonitor()
    end)
    f.closeButton = closeButton

    local assignmentsButton = CreateFrame("Button", nil, f)
    assignmentsButton:SetSize(18, 18)
    assignmentsButton:SetPoint("RIGHT", closeButton, "LEFT", -2, 0)
    assignmentsButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-Maximize-Up")
    assignmentsButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-Maximize-Down")
    assignmentsButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    assignmentsButton:SetScript("OnClick", function()
        TMA:CreateMainWindow()
        if not TMA.mainWindow:IsShown() then
            TMA.mainWindow:Show()
        end
        TMA.mainWindow:Raise()
        TMA:RefreshMainWindow()
    end)
    assignmentsButton:SetScript("OnEnter", function(selfButton)
        GameTooltip:SetOwner(selfButton, "ANCHOR_LEFT")
        GameTooltip:AddLine("Open assignments")
        GameTooltip:Show()
    end)
    assignmentsButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    f.assignmentsButton = assignmentsButton

    local castBar = CreateFrame("StatusBar", nil, f)
    castBar:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -24)
    castBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -24)
    castBar:SetHeight(14)
    castBar:SetMinMaxValues(0, 1)
    castBar:SetValue(0)
    castBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    castBar:SetStatusBarColor(0.28, 0.28, 0.28, 0.9)
    castBar.bg = castBar:CreateTexture(nil, "BACKGROUND")
    castBar.bg:SetAllPoints(castBar)
    castBar.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    castBar.bg:SetVertexColor(0.06, 0.06, 0.06, 0.9)

    local castText = castBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    castText:SetPoint("CENTER", castBar, "CENTER", 0, 0)
    castText:SetText("Blast Nova ready")
    f.castBar = castBar
    f.castText = castText

    f.rowSymbols = {}
    for rowIndex = 1, MONITOR_SYMBOL_ROWS do
        local iconText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        iconText:SetText(IconTextureString(DEFAULT_SYMBOLS[rowIndex]))
        f.rowSymbols[rowIndex] = iconText
    end

    f.gridCells = {}
    for rowIndex = 1, MONITOR_SYMBOL_ROWS do
        f.gridCells[rowIndex] = {}
        for col = 1, MONITOR_CLICKER_COLUMNS do
            local cell = CreateFrame("Frame", nil, f)
            cell:SetSize(MONITOR_BAR_WIDTH, MONITOR_BAR_HEIGHT)

            local healthBar = CreateFrame("StatusBar", nil, cell)
            healthBar:SetAllPoints(cell)
            healthBar:SetMinMaxValues(0, 1)
            healthBar:SetValue(0)
            healthBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            healthBar:SetStatusBarColor(0.35, 0.35, 0.35, 0.85)
            healthBar.bg = healthBar:CreateTexture(nil, "BACKGROUND")
            healthBar.bg:SetAllPoints(healthBar)
            healthBar.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
            healthBar.bg:SetVertexColor(0.05, 0.05, 0.05, 0.9)

            local nameText = healthBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nameText:SetPoint("CENTER", healthBar, "CENTER", 0, 0)
            nameText:SetJustifyH("CENTER")
            nameText:SetText("-")

            cell.healthBar = healthBar
            cell.nameText = nameText
            f.gridCells[rowIndex][col] = cell
        end
    end

    f:Hide()
    self.monitorFrame = f
end

function TMA:CreateMainWindow()
    if self.mainWindow then
        return
    end

    local f = CreateFrame("Frame", "TMAMainWindow", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(540, 410)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", function(selfFrame)
        selfFrame:StartMoving()
    end)
    f:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
    end)
    f:SetScript("OnShow", function(selfFrame)
        selfFrame:Raise()
    end)
    f:Hide()

    if not tContains(UISpecialFrames, "TMAMainWindow") then
        table.insert(UISpecialFrames, "TMAMainWindow")
    end

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("LEFT", f.TitleBg, "LEFT", 8, 0)
    f.title:SetText((self.addonTitle or GetAddonTitle()) .. " " .. (self.addonVersion or GetAddonVersion()))

    local importButton = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    importButton:SetSize(120, 22)
    importButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -36)
    importButton:SetText("Import/Export")
    importButton:SetScript("OnClick", function()
        if not TMA:IsAssigner() then
            Print("Only assigners can edit assignments.")
            return
        end

        TMA:ShowImportExport()
    end)

    local exportButton = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    exportButton:SetSize(100, 22)
    exportButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -36)
    exportButton:SetText("Export")
    exportButton:Hide()
    exportButton:SetScript("OnClick", function()
        TMA:ShowImportExport()
    end)

    local modeCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    modeCheck:SetSize(24, 24)
    modeCheck:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -34)
    modeCheck:SetScript("OnClick", function(selfButton)
        if not TMA:IsAssigner() then
            selfButton:SetChecked(TMA.db.assignments.useFourClickers)
            return
        end

        TMA.db.assignments.useFourClickers = selfButton:GetChecked() and true or false
        TMA:RefreshMainWindow()
        TMA:RefreshMonitor()
        TMA:BroadcastAssignmentsToGroup()
    end)

    local modeCheckLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    modeCheckLabel:SetPoint("LEFT", modeCheck, "RIGHT", 2, 1)
    modeCheckLabel:SetText("Use 4 clickers per icon")

    local magOnlyCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    magOnlyCheck:SetSize(24, 24)
    magOnlyCheck:SetPoint("LEFT", modeCheckLabel, "RIGHT", 22, -1)
    magOnlyCheck:SetScript("OnClick", function(selfButton)
        TMA.db.monitor.onlyInMagsLair = selfButton:GetChecked() and true or false
        if TMA.db.monitor.onlyInMagsLair and not TMA:IsInMagtheridonDungeon() then
            TMA:ResetBlastNovaTracking()
        end
        TMA:RefreshOverlay()
        TMA:RefreshMonitor()
    end)

    local magOnlyCheckLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    magOnlyCheckLabel:SetPoint("LEFT", magOnlyCheck, "RIGHT", 2, 1)
    magOnlyCheckLabel:SetText("Show overlay only in Mag's Lair")

    local tableTop = -74
    local left = 18

    local symbolHeader = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    symbolHeader:SetPoint("TOPLEFT", f, "TOPLEFT", left + 14, tableTop)
    symbolHeader:SetText("Symbol")

    local primaryHeader = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    primaryHeader:SetPoint("TOP", f, "TOPLEFT", 207, tableTop)
    primaryHeader:SetText("Primary")

    local backupHeader = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    backupHeader:SetPoint("TOP", f, "TOPLEFT", 415, tableTop)
    backupHeader:SetText("Back-up")

    local thirdHeader = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    thirdHeader:SetPoint("TOP", f, "TOPLEFT", 0, tableTop)
    thirdHeader:SetText("Third")

    local fourthHeader = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fourthHeader:SetPoint("TOP", f, "TOPLEFT", 0, tableTop)
    fourthHeader:SetText("Fourth")
    thirdHeader:Hide()
    fourthHeader:Hide()

    f.symbolHeader = symbolHeader
    f.primaryHeader = primaryHeader
    f.backupHeader = backupHeader
    f.thirdHeader = thirdHeader
    f.fourthHeader = fourthHeader

    local rowStartY = -96
    local rowHeight = 44
    local function CreateRaidPresenceDot(button)
        local dot = button:CreateTexture(nil, "OVERLAY")
        dot:SetSize(8, 8)
        dot:SetPoint("LEFT", button, "LEFT", 8, 0)
        dot:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        dot:SetVertexColor(0.35, 0.95, 0.45)
        dot:Hide()
        return dot
    end
    local function CreatePurpleAssignmentDot(button)
        local dot = button:CreateTexture(nil, "OVERLAY")
        dot:SetSize(8, 8)
        dot:SetPoint("RIGHT", button, "RIGHT", -8, 0)
        dot:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        dot:SetVertexColor(0.85, 0.35, 1.0)
        dot:Hide()
        return dot
    end

    for i = 1, ROW_COUNT do
        local y = rowStartY - ((i - 1) * rowHeight)

        local rowBackdrop = CreateFrame("Frame", nil, f, "BackdropTemplate")
        rowBackdrop:SetPoint("TOPLEFT", f, "TOPLEFT", left - 4, y + 4)
        rowBackdrop:SetSize(500, 38)
        rowBackdrop:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 8,
            edgeSize = 8,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        rowBackdrop:SetBackdropColor(0, 0, 0, 0.35)

        local symbolButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        symbolButton:SetSize(80, 28)
        symbolButton:SetPoint("TOPLEFT", f, "TOPLEFT", left, y)
        symbolButton:SetScript("OnClick", function(selfButton)
            TMA:OpenCellDropdown(i, "symbol", selfButton)
        end)

        local symbolText = symbolButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        symbolText:SetPoint("CENTER", symbolButton, "CENTER", 0, 0)
        symbolButton:SetText("")

        local primaryButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        primaryButton:SetSize(198, 28)
        primaryButton:SetPoint("LEFT", symbolButton, "RIGHT", 10, 0)
        primaryButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        primaryButton:SetScript("OnClick", function(selfButton, button)
            if button == "RightButton" then
                if TMA:IsAssigner() then
                    TMA:SetCellName(i, "primary", nil)
                end
                return
            end
            TMA:OpenCellDropdown(i, "primary", selfButton)
        end)

        local backupButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        backupButton:SetSize(198, 28)
        backupButton:SetPoint("LEFT", primaryButton, "RIGHT", 10, 0)
        backupButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        backupButton:SetScript("OnClick", function(selfButton, button)
            if button == "RightButton" then
                if TMA:IsAssigner() then
                    TMA:SetCellName(i, "backup", nil)
                end
                return
            end
            TMA:OpenCellDropdown(i, "backup", selfButton)
        end)

        local thirdButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        thirdButton:SetSize(198, 28)
        thirdButton:SetPoint("LEFT", backupButton, "RIGHT", 10, 0)
        thirdButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        thirdButton:SetScript("OnClick", function(selfButton, button)
            if button == "RightButton" then
                if TMA:IsAssigner() then
                    TMA:SetCellName(i, "third", nil)
                end
                return
            end
            TMA:OpenCellDropdown(i, "third", selfButton)
        end)

        local fourthButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        fourthButton:SetSize(198, 28)
        fourthButton:SetPoint("LEFT", thirdButton, "RIGHT", 10, 0)
        fourthButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        fourthButton:SetScript("OnClick", function(selfButton, button)
            if button == "RightButton" then
                if TMA:IsAssigner() then
                    TMA:SetCellName(i, "fourth", nil)
                end
                return
            end
            TMA:OpenCellDropdown(i, "fourth", selfButton)
        end)
        thirdButton:Hide()
        fourthButton:Hide()

        local primaryDot = CreateRaidPresenceDot(primaryButton)
        local backupDot = CreateRaidPresenceDot(backupButton)
        local thirdDot = CreateRaidPresenceDot(thirdButton)
        local fourthDot = CreateRaidPresenceDot(fourthButton)
        local primaryRightDot = CreatePurpleAssignmentDot(primaryButton)
        local backupRightDot = CreatePurpleAssignmentDot(backupButton)
        local thirdRightDot = CreatePurpleAssignmentDot(thirdButton)
        local fourthRightDot = CreatePurpleAssignmentDot(fourthButton)

        self.cells[i] = {
            rowBackdrop = rowBackdrop,
            symbolButton = symbolButton,
            primaryButton = primaryButton,
            backupButton = backupButton,
            thirdButton = thirdButton,
            fourthButton = fourthButton,
            primaryDot = primaryDot,
            backupDot = backupDot,
            thirdDot = thirdDot,
            fourthDot = fourthDot,
            primaryRightDot = primaryRightDot,
            backupRightDot = backupRightDot,
            thirdRightDot = thirdRightDot,
            fourthRightDot = fourthRightDot,
            symbol = symbolText,
            primary = primaryButton:GetFontString(),
            backup = backupButton:GetFontString(),
            third = thirdButton:GetFontString(),
            fourth = fourthButton:GetFontString(),
        }
    end

    local sendButton = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    sendButton:SetSize(170, 26)
    sendButton:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 18)
    sendButton:SetText("Send Assignments")
    sendButton:SetScript("OnClick", function()
        if not TMA:IsAssigner() then
            Print("Only assigners can send assignments.")
            return
        end
        TMA:WhisperAssignments()
    end)

    local monitorButton = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    monitorButton:SetSize(132, 26)
    monitorButton:SetPoint("LEFT", sendButton, "RIGHT", 8, 0)
    monitorButton:SetScript("OnClick", function()
        TMA:ToggleMonitor()
    end)

    local clearButton = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    clearButton:SetSize(170, 26)
    clearButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 18)
    clearButton:SetText("Clear All")
    clearButton:SetScript("OnClick", function()
        if not TMA:IsAssigner() then
            Print("Only assigners can clear assignments.")
            return
        end
        TMA:ClearAllAssignments()
    end)

    f.importButton = importButton
    f.exportButton = exportButton
    f.sendButton = sendButton
    f.monitorButton = monitorButton
    f.clearButton = clearButton
    f.modeCheck = modeCheck
    f.modeCheckLabel = modeCheckLabel
    f.magOnlyCheck = magOnlyCheck
    f.magOnlyCheckLabel = magOnlyCheckLabel

    self.mainWindow = f
end

function TMA:ToggleMainWindow()
    self:CreateMainWindow()
    if self.mainWindow:IsShown() then
        self.mainWindow:Hide()
    else
        self.mainWindow:Show()
        self.mainWindow:Raise()
        self:RefreshMainWindow()
    end
end

function TMA:ToggleMinimapButtonVisibility()
    self.db.minimap.hide = not self.db.minimap.hide
    if self.db.minimap.hide then
        self.minimapButton:Hide()
        Print("Minimap button hidden.")
    else
        self.minimapButton:Show()
        Print("Minimap button shown.")
    end
end

function TMA:UpdateMinimapButtonPosition()
    local angle = self.db.minimap.angle or 210
    local radius = 82
    local x = math.cos(math.rad(angle)) * radius
    local y = math.sin(math.rad(angle)) * radius
    self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function TMA:CreateMinimapButton()
    if self.minimapButton then
        return
    end

    local b = CreateFrame("Button", "TMAMinimapButton", Minimap)
    b:SetSize(32, 32)
    b:SetFrameStrata("MEDIUM")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    bg:SetSize(54, 54)
    bg:SetPoint("TOPLEFT", -11, 11)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\TimbersMagAssignments\\Media\\icon.blp")
    icon:SetSize(16, 16)
    icon:SetPoint("CENTER", b, "CENTER", -8, 8)

    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(selfButton)
        selfButton.isMoving = true
    end)
    b:SetScript("OnDragStop", function(selfButton)
        selfButton.isMoving = false
    end)
    b:SetScript("OnUpdate", function(selfButton)
        if not selfButton.isMoving then
            return
        end
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        px = px / scale
        py = py / scale

        local angle = math.deg(math.atan2(py - my, px - mx))
        TMA.db.minimap.angle = angle
        TMA:UpdateMinimapButtonPosition()
    end)

    local menuFrame = CreateFrame("Frame", "TMAMinimapMenu", UIParent, "UIDropDownMenuTemplate")

    local function OpenMenu(anchor)
        local menu = {
            {
                text = TMA.addonTitle or GetAddonTitle(),
                isTitle = true,
                notCheckable = true,
            },
            {
                text = "Assignments",
                notCheckable = true,
                func = function()
                    TMA:ToggleMainWindow()
                end,
            },
            {
                text = "Help",
                notCheckable = true,
                func = function()
                    TMA:PrintHelp()
                end,
            },
            {
                text = "Hide Minimap Button",
                notCheckable = true,
                func = function()
                    TMA:ToggleMinimapButtonVisibility()
                end,
            },
        }
        ShowDropdownMenu(menuFrame, menu, anchor, true)
    end

    b:SetScript("OnClick", function(_, button)
        if button == "LeftButton" then
            TMA:ToggleMainWindow()
        else
            OpenMenu(b)
        end
    end)

    b:SetScript("OnEnter", function(selfButton)
        GameTooltip:SetOwner(selfButton, "ANCHOR_LEFT")
        GameTooltip:AddLine(TMA.addonTitle or GetAddonTitle())
        GameTooltip:AddLine("Left-click: Toggle assignments", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Right-click: Options menu", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)

    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    self.minimapButton = b
    self:UpdateMinimapButtonPosition()

    if self.db.minimap.hide then
        b:Hide()
    else
        b:Show()
    end
end

function TMA:PrintHelp()
    Print("/tma - Opens assignment window")
    Print("/tma help - Prints this help")
    Print("/tma version or /tma v - Prints version")
    Print("/tma minimap - Toggles minimap button")
end

function TMA:HandleSlashCommand(msg)
    local arg = Trim(string.lower(msg or ""))
    if arg == "" then
        self:ToggleMainWindow()
        return
    end

    if arg == "help" then
        self:PrintHelp()
        return
    end

    if arg == "version" or arg == "v" then
        Print("Version: " .. tostring(self.addonVersion or GetAddonVersion()))
        return
    end

    if arg == "minimap" then
        self:ToggleMinimapButtonVisibility()
        return
    end

    if arg == "debugoverlay" then
        self.debugOverlay = not self.debugOverlay
        if self.debugOverlay then
            Print("Debug overlay enabled.")
        else
            Print("Debug overlay disabled.")
        end
        self:RefreshOverlay()
        return
    end

    Print("Unknown command. Use /tma help")
end

function TMA:ApplyRemoteAssignments(assignments, sender)
    if not assignments then
        return
    end

    self.db.assignments = DeepCopyAssignments(assignments)
    self:RefreshMainWindow()
    self:RefreshOverlay()
    self:RefreshMonitor()
end

function TMA:OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= ADDON_NAME then
            return
        end

        self.db = EnsureDB()
        self:ResetAddonPresence()
        self.addonTitle = GetAddonTitle()
        self.addonVersion = GetAddonVersion()
        self:CreateOverlay()
        self:CreateMonitor()
        self:CreateMainWindow()
        self:CreateMinimapButton()
        self:RefreshMainWindow()
        self:RefreshOverlay()
        self:RefreshMonitor()

        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

        SLASH_TMA1 = "/tma"
        SlashCmdList.TMA = function(msg)
            TMA:HandleSlashCommand(msg)
        end

        Print("Loaded. Type /tma for assignments.")
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, payload, _, sender = ...
        if prefix ~= PREFIX then
            return
        end

        self:MarkAddonUser(sender)
        self:RefreshMainWindow()

        if self:IsSenderSelf(sender) then
            return
        end

        if payload == MSG_REQUEST then
            if self:IsAssigner() then
                self:SendAssignmentsToTarget(sender)
            end
            return
        end

        local syncPrefix = MSG_SYNC .. MSG_SEPARATOR
        if string.sub(payload or "", 1, string.len(syncPrefix)) == syncPrefix then
            local encodedAssignments = string.sub(payload, string.len(syncPrefix) + 1)
            local parsedSync = self:DecodeAssignments(encodedAssignments)
            if parsedSync then
                if self.awaitingInitialSyncForGroup then
                    if self.receivedSyncForGroup then
                        return
                    end
                    self.receivedSyncForGroup = true
                    self.awaitingInitialSyncForGroup = false
                    self:ApplyRemoteAssignments(parsedSync, sender)
                else
                    self:ApplyRemoteAssignments(parsedSync, sender)
                end
            end
            return
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        self.monitorHealthDirty = true
        if not self:IsMonitorTrackingAllowed() then
            self:ResetBlastNovaTracking()
        end
        self:HandleGroupStateChange()
        self:RefreshMainWindow()
        self:RefreshOverlay()
        self:RefreshMonitor()
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_CONNECTION" then
        self:UpdateMonitorHealthBars()
    elseif event == "PLAYER_REGEN_DISABLED" then
        self.monitorCombatEndedAt = nil
        if self:IsMonitorTrackingAllowed() then
            self.pendingChannelerCombatStart = true
        else
            self.pendingChannelerCombatStart = false
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        self.pendingChannelerCombatStart = false
        self.monitorCombatEndedAt = GetTime()
    elseif event == "CHAT_MSG_MONSTER_YELL" then
        local message, sender = ...
        local lowerMessage = string.lower(message or "")
        local lowerSender = string.lower(sender or "")
        if self:IsMonitorTrackingAllowed()
            and (lowerSender == "" or string.find(lowerSender, "magtheridon", 1, true))
            and string.find(lowerMessage, "unleashed", 1, true) then
            self:StartFirstBlastNovaTimer()
        end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not self:IsMonitorTrackingAllowed() then
            return
        end
        if type(CombatLogGetCurrentEventInfo) ~= "function" then
            return
        end

        local _, subevent, _, _, sourceName, _, _, _, destName, _, _, spellId, spellName = CombatLogGetCurrentEventInfo()
        self:TryStartMagFallbackFromChannelerCombat(sourceName, destName)

        if subevent == "SPELL_CAST_START" and spellId == BLAST_NOVA_SPELL_ID then
            self:StartBlastNovaCast()
        elseif (subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH")
            and self:IsMagtheridonName(destName)
            and self:IsShadowCageSpell(spellId, spellName) then
            self:StartShadowCageWindow()
        elseif subevent == "SPELL_AURA_REMOVED"
            and self:IsMagtheridonName(destName)
            and self:IsShadowCageSpell(spellId, spellName) then
            self:EndShadowCageWindow()
        end
    end
end

TMA:SetScript("OnEvent", function(_, event, ...)
    TMA:OnEvent(event, ...)
end)

TMA:RegisterEvent("ADDON_LOADED")
TMA:RegisterEvent("CHAT_MSG_ADDON")
TMA:RegisterEvent("GROUP_ROSTER_UPDATE")
TMA:RegisterEvent("PLAYER_ENTERING_WORLD")
TMA:RegisterEvent("ZONE_CHANGED_NEW_AREA")
TMA:RegisterEvent("UNIT_HEALTH")
TMA:RegisterEvent("UNIT_MAXHEALTH")
TMA:RegisterEvent("UNIT_CONNECTION")
TMA:RegisterEvent("PLAYER_REGEN_DISABLED")
TMA:RegisterEvent("PLAYER_REGEN_ENABLED")
TMA:RegisterEvent("CHAT_MSG_MONSTER_YELL")
TMA:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
