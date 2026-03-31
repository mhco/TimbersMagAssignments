local ADDON_NAME = ...

local TMA = CreateFrame("Frame", "TimbersMagAssignmentsFrame")
local PREFIX = "TMA1"
local ROW_COUNT = 5
local MSG_REQUEST = "REQ"
local MSG_SYNC = "SYNC"
local MSG_SEPARATOR = "|"

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

    return db
end

TMA.db = nil
TMA.mainWindow = nil
TMA.importExportWindow = nil
TMA.overlayFrame = nil
TMA.minimapButton = nil
TMA.cells = {}
TMA.cellDropdownMenu = nil
TMA.dropdownClickCatcher = nil
TMA.currentGroupKey = "SOLO"
TMA.receivedSyncForGroup = false
TMA.awaitingInitialSyncForGroup = false
TMA.addonTitle = nil
TMA.addonVersion = nil
TMA.debugOverlay = false

function TMA:IsInMagtheridonDungeon()
    local name, instanceType = GetInstanceInfo()
    if not name or name == "" then
        return false
    end

    local normalizedName = string.lower(name)
    return instanceType == "raid" and string.find(normalizedName, "magtheridon", 1, true) ~= nil
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

    if not skipSyncBroadcast then
        self:BroadcastAssignmentsToGroup()
    end
end

function TMA:ClearAllAssignments(skipSyncBroadcast)
    local keepFourClickers = self.db and self.db.assignments and self.db.assignments.useFourClickers
    self.db.assignments = BuildDefaultAssignments(keepFourClickers)
    self:RefreshMainWindow()
    self:RefreshOverlay()

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

function TMA:RefreshOverlay()
    if not self.overlayFrame then
        return
    end

    if not self.debugOverlay and not self:IsInMagtheridonDungeon() then
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
    local sent = 0
    local attempted = 0

    for i = 1, ROW_COUNT do
        local row = self.db.assignments.rows[i]
        local iconIndex = row.symbol or DEFAULT_SYMBOLS[i]

        local rolesToWhisper = self.db.assignments.useFourClickers and CLICKER_ROLES or {"primary", "backup"}
        for _, role in ipairs(rolesToWhisper) do
            local target = row[role]
            if target and target ~= "" then
                SendChatMessage(AssignmentMessage(iconIndex, role), "WHISPER", nil, target)
                attempted = attempted + 1
                sent = sent + 1
            end
        end
    end

    Print("Sent " .. sent .. " assignment whisper(s) from " .. attempted .. " attempt(s).")
end

function TMA:RefreshMainWindow()
    if not self.mainWindow then
        return
    end

    local canEdit = self:IsAssigner()
    local useFourClickers = self.db.assignments.useFourClickers and true or false
    local tableTop = canEdit and -74 or -54
    local rowStartY = canEdit and -96 or -76
    local rowHeight = 44

    local left = 18
    local symbolWidth = 80
    local gap = 10
    local visibleNameColumns = useFourClickers and 4 or 2
    local nameWidth = useFourClickers and 140 or 198
    local tableWidth = symbolWidth + (visibleNameColumns * nameWidth) + (visibleNameColumns * gap)
    local rowBackdropWidth = tableWidth + 4
    local frameWidth = (left - 4) + rowBackdropWidth + 26

    self.mainWindow:SetWidth(frameWidth)

    if self.mainWindow.importButton and self.mainWindow.exportButton and self.mainWindow.sendButton and self.mainWindow.clearButton then
        if canEdit then
            self.mainWindow.importButton:Show()
            self.mainWindow.exportButton:Show()
            self.mainWindow.sendButton:Show()
            self.mainWindow.clearButton:Show()
            self.mainWindow:SetHeight(410)

            self.mainWindow.exportButton:ClearAllPoints()
            self.mainWindow.exportButton:SetPoint("TOPRIGHT", self.mainWindow, "TOPRIGHT", -18, -36)
            self.mainWindow.importButton:ClearAllPoints()
            self.mainWindow.importButton:SetPoint("RIGHT", self.mainWindow.exportButton, "LEFT", -8, 0)

            self.mainWindow.sendButton:ClearAllPoints()
            self.mainWindow.sendButton:SetPoint("BOTTOMLEFT", self.mainWindow, "BOTTOMLEFT", 18, 42)
            self.mainWindow.clearButton:ClearAllPoints()
            self.mainWindow.clearButton:SetPoint("BOTTOMRIGHT", self.mainWindow, "BOTTOMRIGHT", -18, 42)
        else
            self.mainWindow.importButton:Hide()
            self.mainWindow.exportButton:Hide()
            self.mainWindow.sendButton:Hide()
            self.mainWindow.clearButton:Hide()
            self.mainWindow:SetHeight(320)
        end
    end

    if self.mainWindow.modeCheck and self.mainWindow.modeCheckLabel then
        self.mainWindow.modeCheck:SetChecked(useFourClickers)
        if canEdit then
            self.mainWindow.modeCheck:Show()
            self.mainWindow.modeCheckLabel:Show()
            self.mainWindow.modeCheck:Enable()
            self.mainWindow.modeCheckLabel:SetTextColor(1, 0.82, 0)
        else
            self.mainWindow.modeCheck:Hide()
            self.mainWindow.modeCheckLabel:Hide()
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

            cell.symbol:SetText(IconTextureString(row.symbol or DEFAULT_SYMBOLS[i]))
            cell.primary:SetText(row.primary or "-")
            cell.backup:SetText(row.backup or "-")
            cell.third:SetText(row.third or "-")
            cell.fourth:SetText(row.fourth or "-")
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
    applyImportButton:SetText("Import")
    applyImportButton:SetScript("OnClick", function()
        if not TMA:IsAssigner() then
            Print("Only assigners can import.")
            return
        end

        local text = f.editBox:GetText() or ""
        TMA:ImportAssignmentsFromText(text)
        f:Hide()
        Print("Import complete.")
    end)

    f.editBox = editBox
    f.scroll = scroll
    f.applyImportButton = applyImportButton
    self.importExportWindow = f
end

function TMA:ShowImportExport(mode)
    self:CreateImportExportWindow()
    local f = self.importExportWindow
    f.mode = mode

    if mode == "import" then
        f:SetHeight(280)
        f.scroll:ClearAllPoints()
        f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -50)
        f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 46)
        f.applyImportButton:Show()
        f.title:SetText("Import")
        f.editBox:SetText("")
    else
        f:SetHeight(250)
        f.scroll:ClearAllPoints()
        f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -50)
        f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 16)
        f.applyImportButton:Hide()
        f.title:SetText("Export")
        f.editBox:SetText(self:ExportAssignmentsToText())
        f.editBox:HighlightText()
    end

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
    importButton:SetSize(100, 22)
    importButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -126, -36)
    importButton:SetText("Import")
    importButton:SetScript("OnClick", function()
        if not TMA:IsAssigner() then
            Print("Only assigners can import.")
            return
        end

        TMA:ShowImportExport("import")
    end)

    local exportButton = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    exportButton:SetSize(100, 22)
    exportButton:SetPoint("LEFT", importButton, "RIGHT", 8, 0)
    exportButton:SetText("Export")
    exportButton:SetScript("OnClick", function()
        TMA:ShowImportExport("export")
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
        TMA:BroadcastAssignmentsToGroup()
    end)

    local modeCheckLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    modeCheckLabel:SetPoint("LEFT", modeCheck, "RIGHT", 2, 1)
    modeCheckLabel:SetText("Use 4 clickers per icon")

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

        self.cells[i] = {
            rowBackdrop = rowBackdrop,
            symbolButton = symbolButton,
            primaryButton = primaryButton,
            backupButton = backupButton,
            thirdButton = thirdButton,
            fourthButton = fourthButton,
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
    f.clearButton = clearButton
    f.modeCheck = modeCheck
    f.modeCheckLabel = modeCheckLabel

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
end

function TMA:OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= ADDON_NAME then
            return
        end

        self.db = EnsureDB()
        self.addonTitle = GetAddonTitle()
        self.addonVersion = GetAddonVersion()
        self:CreateOverlay()
        self:CreateMainWindow()
        self:CreateMinimapButton()
        self:RefreshMainWindow()
        self:RefreshOverlay()

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
        self:HandleGroupStateChange()
        self:RefreshMainWindow()
        self:RefreshOverlay()
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
