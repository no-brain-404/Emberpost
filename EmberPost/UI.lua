local E = EmberPost
local W, H = 640, 520
local C = { gold = {1, 0.82, 0.22}, text = {0.9, 0.9, 0.92}, muted = {0.62, 0.62, 0.66},
    green = {0.42, 0.9, 0.2}, red = {1, 0.4, 0.35}, line = {0.25, 0.25, 0.28}, panel = {0.12, 0.12, 0.13} }
local serial = 0
local function name(prefix) serial = serial + 1; return "EmberPost" .. prefix .. serial end

local function place(f, parent, x, y, w, h)
    if f.SetFrameLevel then
        f:SetFrameLevel(parent:GetFrameLevel() + 1)
        f:SetFrameStrata(parent:GetFrameStrata())
    end
    f:SetWidth(w); f:SetHeight(h); f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    return f
end

local function rect(parent, x, y, w, h, color, alpha, layer)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    place(t, parent, x, y, w, h)
    t:SetTexture(color[1], color[2], color[3], alpha or 1)
    return t
end

local function border(parent, w, h, color)
    local lines = { rect(parent, 0, 0, w, 1, color, 1, "BORDER"), rect(parent, 0, h-1, w, 1, color, 1, "BORDER"),
        rect(parent, 0, 0, 1, h, color, 1, "BORDER"), rect(parent, w-1, 0, 1, h, color, 1, "BORDER") }
    return lines
end

local function tint(lines, r, g, b)
    for _, line in ipairs(lines) do line:SetTexture(r, g, b, 1) end
end

local function privateFont(size)
    local font = CreateFont(name("Font"))
    local source = size <= 14 and (GameFontHighlightSmall or GameFontNormalSmall) or GameFontNormal
    if source or GameFontNormal then font:SetFontObject(source or GameFontNormal) end
    -- SetFont silently does nothing when the face is not loaded. Start with a
    -- small stock font, and measure the actual result rather than assuming size.
    font:SetFont("Fonts\\ARIALN.TTF", size)
    return font
end

local function text(parent, x, y, w, h, value, size, color, justify)
    -- Re-anchoring a FontString after its parent is scaled produces displaced
    -- labels on the UE client. Give every label a fixed frame and zero-offset
    -- anchor once, before the root is scaled. Text updates never touch layout.
    local holder = place(CreateFrame("Frame", name("Label"), parent), parent, x, y, w, h)
    holder:EnableMouse(false)
    local fs = holder:CreateFontString(name("Text"), "OVERLAY")
    local font = privateFont(size or 12)
    fs:SetFontObject(font)
    fs:SetWidth(0); fs:SetHeight(0)
    fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
    color = color or C.text
    fs:SetTextColor(color[1], color[2], color[3], 1)
    local anchor = justify == "RIGHT" and "RIGHT" or justify == "CENTER" and "CENTER" or "LEFT"
    fs:SetPoint(anchor, holder, anchor, 0, 0)
    local label = { raw = fs, holder = holder, font = font, maxWidth = w, maxHeight = h }
    function label:SetText(v)
        local s = E.Display(v):gsub("[\r\n]", " ")
        fs:SetText(s)
        if fs:GetStringWidth() > w then
            repeat s = E.Clip(s, #s-1); fs:SetText(s .. "...") until #s == 0 or fs:GetStringWidth() <= w
            if fs:GetStringWidth() > w then fs:SetText("") end
        end
    end
    function label:GetText() return fs:GetText() end
    function label:GetStringWidth() return fs:GetStringWidth() end
    function label:SetTextColor(...) fs:SetTextColor(...) end
    function label:Show() fs:Show() end
    function label:Hide() fs:Hide() end
    function label:IsShown() return fs:IsShown() end
    function label:IsVisible() return fs:IsVisible() end
    label:SetText(value or "")
    return label
end

local function fit(fs, value, maxWidth)
    if fs.raw then fs:SetText(value); return end
    value = E.Display(value):gsub("[\r\n]", " ")
    fs:SetText(value)
    if fs:GetStringWidth() <= maxWidth then return end
    while #value > 0 do
        value = E.Clip(value, #value - 1)
        fs:SetText(value .. "...")
        if fs:GetStringWidth() <= maxWidth then return end
    end
    fs:SetText("...")
end

local function button(parent, x, y, w, h, label, action, accent)
    local b = place(CreateFrame("Button", name("Button"), parent), parent, x, y, w, h)
    b.accent = accent
    b:EnableMouse(true); b:RegisterForClicks("LeftButtonUp")
    b.fill = rect(b, 0, 0, w, h, accent and {0.24, 0.24, 0.27} or {0.16, 0.16, 0.18})
    b.edges = border(b, w, h, C.line)
    b.label = text(b, 4, 0, w-8, h, label, 12, accent and C.gold or C.text, "CENTER")
    b:SetScript("OnClick", function() if b:IsEnabled() == 1 then action() end end)
    b:SetScript("OnEnter", function() if b:IsEnabled() == 1 then b.fill:SetTexture(0.3, 0.3, 0.33, 1) end end)
    b:SetScript("OnLeave", function() local v = b.accent and 0.24 or 0.16; b.fill:SetTexture(v, v, v+0.02, 1) end)
    return b
end

local function enabled(b, on)
    if on then b:Enable(); b.label:SetTextColor(unpack(b.accent and C.gold or C.text))
    else b:Disable(); b.label:SetTextColor(0.42, 0.42, 0.45) end
end

local function edit(parent, x, y, w, h, maxBytes, multi)
    local box = place(CreateFrame("EditBox", name("Edit"), parent), parent, x, y, w, h)
    if not multi then rect(box, 0, 0, w, h, {0.055, 0.055, 0.06}); border(box, w, h, C.line) end
    local font = privateFont(12)
    box:SetFontObject(font) -- creates the inner font string before other setters
    box:SetTextColor(unpack(C.text)); box:SetTextInsets(8, 8, 5, 5)
    box:SetMaxBytes(maxBytes); box:SetMaxLetters(maxBytes); box:SetAutoFocus(false)
    box:SetMultiLine(not not multi); box:SetJustifyH("LEFT"); box:SetJustifyV(multi and "TOP" or "CENTER")
    box:EnableMouse(true); box:SetText("")
    box:SetScript("OnEscapePressed", function() box:ClearFocus() end)
    box:SetScript("OnTextChanged", function() E.dirty = true end)
    return box
end

local function icon(parent, x, y, size, action)
    local b = button(parent, x, y, size, size, "", action)
    b.image = b:CreateTexture(nil, "ARTWORK")
    place(b.image, b, 4, 4, size-8, size-8)
    b.image:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    b.count = text(b, 4, size-22, size-9, 18, "", 14, C.text, "RIGHT")
    local restoreFill = b:GetScript("OnLeave")
    b:SetScript("OnLeave", function()
        restoreFill(b) -- restore the same idle color as a newly created slot
        if GameTooltip then GameTooltip:Hide() end
    end)
    return b
end

local function setIcon(b, item)
    if item and item.texture and item.texture ~= "" then
        b.image:SetTexture(item.texture); b.image:Show()
        b.count:SetText(item.count and item.count > 1 and tostring(item.count) or "")
        local r, g, bl = 0.22, 0.3, 0.28
        if item.quality and item.quality >= 2 then r, g, bl = GetItemQualityColor(item.quality) end
        tint(b.edges, r, g, bl)
    else
        b.image:Hide(); b.count:SetText(""); tint(b.edges, unpack(C.line))
    end
end

function E:TooltipBag(b, item)
    if not GameTooltip or not item then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if self:SameBagItem(item, true) then GameTooltip:SetBagItem(item.bag, item.slot)
    else GameTooltip:SetText("Stack moved or changed", 1, 0.4, 0.3) end
    GameTooltip:Show()
end

function E:SwitchTab(tab)
    if self:Busy() then return end
    self.tab = tab; self.dirty = true
    if tab == "send" then self.readerIndex = nil end
end

function E:SavePosition()
    local point, relative, rp, x, internalY = self.ui.frame:GetPoint(1)
    if point and x and internalY then
        self.settings.position = { point = point, relativePoint = rp, x = x, y = -internalY }
    end
end

function E:RestorePosition(reset)
    local f = self.ui.frame
    local fitScale = math.min((GetScreenWidth()-24) / W, (GetScreenHeight()-24) / H, self.settings.scale)
    f:SetScale(math.max(0.4, fitScale))
    f:ClearAllPoints()
    local p = not reset and self.settings.position
    if type(p) == "table" and type(p.point) == "string" and type(p.relativePoint) == "string" and type(p.x) == "number" and type(p.y) == "number" then
        f:SetPoint(p.point, UIParent, p.relativePoint, p.x, p.y)
    else f:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
end

function E:SetEscapeEnabled(active)
    if type(UISpecialFrames) ~= "table" then return end
    local found = false
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == "EmberPostFrame" then
            if not active or found then table.remove(UISpecialFrames, i) else found = true end
        end
    end
    if active and not found then table.insert(UISpecialFrames, "EmberPostFrame") end
end

function E:SetInputState(active)
    local ui = self.ui
    if not ui then return end
    active = not not (active and self.open and not self.nativeMode and ui.frame:IsVisible())
    for _, box in ipairs({ui.search, ui.to, ui.subject, ui.body, ui.gold, ui.silver, ui.copper}) do
        local on = not not (active and box:IsVisible() and (box ~= ui.search or not self.readerIndex))
        if box.emberPostInputEnabled ~= on then
            box:EnableMouse(on); box:EnableKeyboard(on)
            box.emberPostInputEnabled = on
        end
        if not on then box:ClearFocus() end
    end
end

function E:BuildUI()
    local ui = {}; self.ui = ui
    local f = place(CreateFrame("Frame", "EmberPostFrame", UIParent), UIParent, 0, 0, W, H)
    ui.frame = f
    f:Hide(); f:SetFrameStrata("DIALOG"); f:SetFrameLevel(20); f:EnableMouse(true)
    f:SetMovable(true); f:SetClampedToScreen(true); f:SetToplevel(true)
    rect(f, -4, -4, W+8, H+8, {0, 0, 0}, 0.4)
    rect(f, 0, 0, W, H, C.panel, 0.98)
    border(f, W, H, C.line); rect(f, 1, 1, W-2, 2, {0.5, 0.42, 0.18})
    local header = place(CreateFrame("Frame", name("Header"), f), f, 2, 2, 152, 36)
    header:EnableMouse(true)
    header:SetScript("OnMouseDown", function(_, mouse) if (mouse or arg1) == "LeftButton" then f:StartMoving() end end)
    header:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); E:SavePosition() end)
    ui.title = text(header, 10, 2, 138, 32, "EmberPost", 20, C.gold)
    ui.close = button(f, W-36, 8, 26, 26, "X", function() E:CloseMailbox() end)
    ui.close.label:SetTextColor(unpack(C.red))
    ui.inboxTab = button(f, 162, 8, 68, 26, "Inbox", function() E:SwitchTab("inbox") end, true)
    ui.sendTab = button(f, 236, 8, 68, 26, "Send", function() E:SwitchTab("send") end)
    ui.balance = text(f, 314, 8, 190, 26, "", 12, C.gold, "RIGHT")
    ui.native = button(f, 516, 8, 78, 26, "WoW UI", function() E:NativeMailbox() end)
    ui.inboxPanel = place(CreateFrame("Frame", name("InboxPanel"), f), f, 10, 44, 620, 426)
    ui.sendPanel = place(CreateFrame("Frame", name("SendPanel"), f), f, 10, 44, 620, 426)
    self:BuildInbox(ui.inboxPanel)
    self:BuildSend(ui.sendPanel)
    ui.progressBG = rect(f, 10, 470, W-20, 2, C.line)
    ui.progress = {}
    for i = 1, 21 do
        ui.progress[i] = rect(f, 10+(i-1)*(W-20)/21, 470, (W-20)/21, 2, C.gold, 0.8, "ARTWORK")
    end
    ui.status = text(f, 10, 478, 538, 20, "", 11, C.muted)
    ui.stop = button(f, 556, 477, 74, 24, "Stop", function() E:Stop("Stopped by you. Completed actions cannot be undone.") end)
    ui.footer = text(f, 10, 502, 620, 14, "/emberpost debug     /emberpost help", 10, C.muted, "CENTER")
    f:SetScript("OnHide", function() if E.open and not E.hidingOwn then E:CloseMailbox() end end)
    -- Some client Escape handlers consume registered frames even while hidden.
    -- Register only during an EmberPost mailbox visit, never for the whole login.
    self:SetEscapeEnabled(false)
    self.scanOwner = CreateFrame("Frame", "EmberPostScanOwner", UIParent); self.scanOwner:Hide()
    self.scanTooltip = CreateFrame("GameTooltip", "EmberPostScanTooltip", self.scanOwner)
    self.scanTooltip:Hide()
    self:BuildConfirmation()
    self:RestorePosition()
    self:SetInputState(false)
end

function E:BuildInbox(p)
    local ui = self.ui
    ui.search = edit(p, 0, 0, 492, 28, 100)
    ui.searchHint = text(ui.search, 9, 0, 470, 28, "Search sender, subject, or item...", 12, C.muted)
    ui.refresh = button(p, 500, 0, 120, 28, "Refresh", function() if not E:Busy() then CheckInbox(); E:SetStatus("Requested inbox refresh (client cache limit: 60 seconds).") end end)
    rect(p, 0, 36, 620, 290, {0.015, 0.015, 0.018})
    rect(p, 0, 36, 620, 24, {0.17, 0.17, 0.19})
    text(p, 28, 36, 342, 24, "Item / Subject", 11, C.muted)
    text(p, 384, 36, 76, 24, "Expires", 11, C.muted)
    text(p, 474, 36, 134, 24, "Gold / COD", 11, C.muted, "RIGHT")
    rect(p, 376, 36, 1, 290, C.line); rect(p, 466, 36, 1, 290, C.line)
    ui.rows = {}
    for n = 1, 11 do
        local row = button(p, 0, 62+(n-1)*24, 620, 24, "", function() end)
        row.fill:SetTexture(0.025, 0.025, 0.03, 1)
        for _, edge in ipairs(row.edges) do edge:Hide() end
        rect(row, 376, 0, 1, 24, C.line); rect(row, 466, 0, 1, 24, C.line)
        row.check = button(row, 3, 4, 16, 16, "", function()
            if not E:Busy() and row.index then E.selected[row.index] = not E.selected[row.index]; E.dirty = true end
        end)
        row.subject = text(row, 28, 0, 340, 24, "", 12, C.text)
        row.amount = text(row, 474, 0, 134, 24, "", 11, C.green, "RIGHT")
        row.days = text(row, 384, 0, 76, 24, "", 11, C.green)
        row:SetScript("OnClick", function() if row.index then E:ReadLetter(row.index) end end)
        row:SetScript("OnEnter", function()
            local m = row.index and E.inbox[row.index]
            if not m or not GameTooltip then return end
            row.fill:SetTexture(0.13, 0.13, 0.15, 1)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            if m.hasItem then GameTooltip:SetInboxItem(row.index) else GameTooltip:SetText(E.Display(m.subject)) end
            GameTooltip:AddLine("Type: " .. E.Display(m.categoryDetail), 1, 0.82, 0.22)
            GameTooltip:AddLine("From: " .. E.Display(m.sender), 0.8, 0.8, 0.8)
            GameTooltip:AddLine(E.Display(m.subject), 0.8, 0.8, 0.8)
            if m.money > 0 then GameTooltip:AddLine("Enclosed: " .. E.Money(m.money), 1, 0.83, 0.26) end
            if m.cod > 0 then GameTooltip:AddLine("COD: " .. E.Money(m.cod), 1, 0.4, 0.35) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() row.fill:SetTexture(0.025, 0.025, 0.03, 1); if GameTooltip then GameTooltip:Hide() end end)
        ui.rows[n] = row
    end
    ui.empty = text(p, 20, 166, 580, 44, "Your inbox is empty.", 14, C.muted, "CENTER")
    ui.summary = text(p, 0, 330, 620, 22, "", 11, C.muted, "CENTER")
    ui.selectAll = button(p, 0, 360, 96, 26, "Select page", function()
        if E:Busy() then return end
        local all = true
        for _, row in ipairs(ui.rows) do if row.index and not E.selected[row.index] then all = false end end
        for _, row in ipairs(ui.rows) do if row.index then E.selected[row.index] = not all end end
        E.dirty = true
    end)
    ui.prev = button(p, 104, 360, 26, 26, "<", function() E.page = math.max(1, E.page-1); E.dirty = true end)
    ui.pageLabel = text(p, 134, 360, 130, 26, "", 11, C.muted, "CENTER")
    ui.next = button(p, 268, 360, 26, 26, ">", function() E.page = E.page+1; E.dirty = true end)
    ui.collect = button(p, 306, 360, 156, 26, "Collect selected", function() E:StartCollect(false, E.cleanup) end)
    ui.cleanup = button(p, 470, 360, 150, 26, "[ ] Delete empty", function() if not E:Busy() then E.cleanup = not E.cleanup; E.dirty = true end end)
    ui.collectAll = button(p, 0, 396, 620, 30, "Open All Mail (skip COD)", function() E:StartCollect(true, E.cleanup) end, true)
    ui.reader = place(CreateFrame("Frame", name("Reader"), p), p, 0, 0, 620, 426)
    local r = ui.reader
    r:SetFrameLevel(50); r:EnableMouse(true)
    rect(r, 0, 0, 620, 426, C.panel)
    ui.readerBack = button(r, 0, 0, 100, 28, "< Inbox", function() if not E:Busy() then E.readerIndex = nil; E.dirty = true end end)
    ui.readerTitle = text(r, 112, 0, 508, 28, "", 14, C.gold)
    ui.readerSender = text(r, 0, 38, 620, 22, "", 12, C.text)
    ui.readerAttachment = icon(r, 0, 64, 54, function() E:SingleAction("item") end)
    local attachmentLeave = ui.readerAttachment:GetScript("OnLeave")
    ui.readerAttachment:SetScript("OnEnter", function(slot)
        local m = E.readerIndex and E.inbox[E.readerIndex]
        if not m or m.key ~= E.readerKey or not m.hasItem or not GameTooltip then return end
        slot.fill:SetTexture(0.3, 0.3, 0.33, 1)
        GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
        GameTooltip:SetInboxItem(E.readerIndex)
        GameTooltip:AddLine(m.cod > 0 and "Click to review COD and take this item." or "Click to take this item.", 1, 0.82, 0.22)
        GameTooltip:Show()
    end)
    ui.readerAttachment:SetScript("OnLeave", attachmentLeave)
    ui.readerItemName = text(r, 66, 64, 554, 26, "", 13, C.gold)
    ui.readerNote = text(r, 66, 92, 554, 22, "", 11, C.muted)
    ui.readerPlainNote = text(r, 0, 64, 620, 54, "", 11, C.muted)
    rect(r, 0, 126, 620, 172, {0.04, 0.04, 0.045})
    ui.bodyLines = {}
    for i = 1, 8 do ui.bodyLines[i] = text(r, 10, 131+(i-1)*20, 600, 20, "", 12, C.text) end
    ui.bodyPageLabel = text(r, 38, 308, 544, 24, "", 11, C.muted, "CENTER")
    ui.bodyPrev = button(r, 0, 308, 28, 24, "<", function() E.bodyPage = math.max(1, (E.bodyPage or 1)-1); E.dirty = true end)
    ui.bodyNext = button(r, 592, 308, 28, 24, ">", function() E.bodyPage = (E.bodyPage or 1)+1; E.dirty = true end)
    ui.takeItem = button(r, 0, 350, 124, 28, "Take item", function() E:SingleAction("item") end, true)
    ui.takeMoney = button(r, 132, 350, 124, 28, "Take coins", function() E:SingleAction("money") end)
    ui.reply = button(r, 264, 350, 112, 28, "Reply", function()
        if E:Busy() then return end
        local m = E.inbox[E.readerIndex or 0]
        if m and m.key == E.readerKey and m.reply and m.sender ~= "" then
            E:SwitchTab("send"); ui.to:SetText(m.sender); ui.subject:SetText(E.Clip("Re: " .. m.subject, 64)); ui.body:SetFocus()
        end
    end)
    ui.returnMail = button(r, 384, 350, 112, 28, "Return", function() E:SingleAction("return") end)
    ui.delete = button(r, 504, 350, 116, 28, "Delete", function() E:SingleAction("delete") end)
    ui.copy = button(r, 0, 396, 620, 30, "Keep letter as an item", function() E:SingleAction("copy") end)
    r:Hide()
end

function E:BuildSend(p)
    local ui = self.ui
    text(p, 0, 0, 64, 28, "To", 12, C.muted)
    ui.to = edit(p, 64, 0, 448, 28, 48)
    ui.recent = button(p, 520, 0, 100, 28, "Recent", function()
        if E:Busy() then return end
        local list = E.settings.recent
        if #list == 0 then E:SetStatus("Successful recipients will appear here."); return end
        E.recentIndex = (E.recentIndex or 0) % #list + 1; ui.to:SetText(list[E.recentIndex])
    end)
    text(p, 0, 36, 64, 28, "Subject", 12, C.muted)
    ui.subject = edit(p, 64, 36, 556, 28, 64)
    ui.subjectHint = text(p, 64, 67, 556, 18, "", 11, C.muted)
    text(p, 0, 90, 152, 20, "Attachments", 12, C.gold)
    ui.attachmentCount = text(p, 160, 90, 156, 20, "0 / 21 stacks", 11, C.muted, "RIGHT")
    ui.slots = {}
    for i = 1, 21 do
        local index = i
        local b = icon(p, ((i-1)%7)*46, 114+math.floor((i-1)/7)*46, 40, function()
            if CursorHasItem() then E:DropAttachment() else E:RemoveAttachment(index) end
        end)
        b:SetScript("OnReceiveDrag", function() E:DropAttachment() end)
        b:SetScript("OnEnter", function() E:TooltipBag(b, E.attachments[index]) end)
        ui.slots[i] = b
    end
    text(p, 0, 252, 620, 20, "One stack per letter. Right-click or drag bag items here; click a queued item to remove it.", 11, C.muted)
    text(p, 340, 90, 280, 20, "Message", 12, C.gold)
    -- A scroll child keeps long text editable without overflowing the window.
    local scroll = place(CreateFrame("ScrollFrame", name("BodyScroll"), p), p, 340, 114, 280, 132)
    ui.bodyScroll = scroll
    rect(scroll, 0, 0, 280, 132, {0.055, 0.055, 0.06}); border(scroll, 280, 132, C.line)
    ui.body = edit(scroll, 0, 0, 276, 132, 5000, true)
    ui.bodyMeasure = text(scroll, 0, 0, 260, 20, "", 12, C.text); ui.bodyMeasure:Hide()
    ui.bodyScrollMax = 0
    scroll:SetScrollChild(ui.body); scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        scroll:SetVerticalScroll(math.max(0, math.min(ui.bodyScrollMax, scroll:GetVerticalScroll() - (delta or arg1 or 0)*32)))
    end)
    ui.body:SetScript("OnCursorChanged", function(_, x, y, width, height)
        y = math.abs(tonumber(y) or 0); height = tonumber(height) or 16
        local current = scroll:GetVerticalScroll()
        if y < current then scroll:SetVerticalScroll(y)
        elseif y + height > current + 128 then scroll:SetVerticalScroll(math.min(ui.bodyScrollMax, y + height - 128)) end
    end)
    ui.send = button(p, 0, 386, 620, 40, "Review & send", function()
        local amount, why = E.Amount(ui.gold:GetText(), ui.silver:GetText(), ui.copper:GetText())
        if not amount then E:SetStatus(why, true); return end
        E:StartSend({ to = ui.to:GetText(), subject = ui.subject:GetText(), body = ui.body:GetText(), amount = amount, cod = E.cod })
    end, true)
    ui.clear = button(p, 132, 344, 120, 30, "Clear draft", function()
        if E:Busy() then return end
        E:Confirm("Clear draft?", "Discard the queued stacks and letter text?\nYour bag items are not deleted.", function() E:ClearComposer(); E:SetStatus("Draft cleared.") end)
    end)
    ui.postage = text(p, 264, 344, 356, 30, "", 12, C.muted, "RIGHT")
    ui.cod = button(p, 0, 282, 120, 28, "[ ] COD", function()
        if E:Busy() then return end
        if not E.cod and #E.attachments > 1 then
            E:SetStatus("COD supports one stack per send. Remove the other queued stacks.", true)
            return
        end
        E.cod = not E.cod; E.dirty = true
    end)
    text(p, 140, 282, 40, 28, "Gold", 11, C.gold)
    ui.gold = edit(p, 188, 282, 112, 28, 6)
    text(p, 320, 282, 44, 28, "Silver", 11, C.muted)
    ui.silver = edit(p, 372, 282, 68, 28, 2)
    text(p, 460, 282, 64, 28, "Copper", 11, C.muted)
    ui.copper = edit(p, 532, 282, 88, 28, 2)
    ui.gold:SetTextInsets(4, 4, 5, 5)
    ui.silver:SetTextInsets(3, 3, 5, 5); ui.copper:SetTextInsets(3, 3, 5, 5)
    ui.moneyNote = text(p, 0, 314, 620, 20, "COD: one stack per send. Coins apply to the first letter only.", 11, C.muted)
    ui.addItems = button(p, 0, 344, 120, 30, "Add items", function() if not E:Busy() then E.bagOpen = not E.bagOpen; E.dirty = true end end)
    local inputs = { ui.to, ui.subject, ui.body, ui.gold, ui.silver, ui.copper }
    for i, box in ipairs(inputs) do
        local index = i
        box:SetScript("OnTabPressed", function()
            box:ClearFocus()
            local nextIndex = IsShiftKeyDown() and ((index-2)%#inputs)+1 or index%#inputs+1
            inputs[nextIndex]:SetFocus()
        end)
        if box ~= ui.body then box:SetScript("OnEnterPressed", function() box:ClearFocus(); inputs[index%#inputs+1]:SetFocus() end) end
    end
    self:BuildBagPicker(p)
end

function E:BuildBagPicker(parent)
    local ui = self.ui
    local p = place(CreateFrame("Frame", name("BagPicker"), parent), parent, 0, 78, 620, 348)
    ui.bagPicker = p; p:SetFrameLevel(60); p:EnableMouse(true)
    rect(p, 0, 0, 620, 348, C.panel); border(p, 620, 348, C.line)
    text(p, 14, 10, 540, 25, "Your bags  /  Click a stack to queue it", 13, C.gold)
    button(p, 578, 10, 28, 25, "X", function() E.bagOpen = false; E.dirty = true end)
    ui.bagSlots = {}
    for i = 1, 32 do
        local b
        b = icon(p, 14+((i-1)%8)*75, 49+math.floor((i-1)/8)*60, 50, function()
            if b.item then E:AddAttachment(b.item.bag, b.item.slot) end
        end)
        b:SetScript("OnEnter", function() E:TooltipBag(b, b.item) end)
        ui.bagSlots[i] = b
    end
    ui.bagPrev = button(p, 14, 307, 34, 26, "<", function() E.bagPage = math.max(1, E.bagPage-1); E.dirty = true end)
    ui.bagNext = button(p, 572, 307, 34, 26, ">", function() E.bagPage = E.bagPage+1; E.dirty = true end)
    ui.bagPageLabel = text(p, 61, 307, 498, 26, "", 11, C.muted, "CENTER")
end

function E:BuildConfirmation()
    local ui = self.ui
    local shade = place(CreateFrame("Frame", name("Modal"), ui.frame), ui.frame, 0, 0, W, H)
    ui.modal = shade; shade:SetFrameLevel(100); shade:EnableMouse(true)
    rect(shade, 0, 0, W, H, {0, 0, 0}, 0.78)
    local p = place(CreateFrame("Frame", name("Dialog"), shade), shade, 40, 98, 560, 312)
    rect(p, 0, 0, 560, 312, C.panel); border(p, 560, 312, C.line)
    ui.modalTitle = text(p, 22, 16, 516, 32, "", 18, C.gold)
    ui.modalLines = {}
    for i = 1, 9 do ui.modalLines[i] = text(p, 22, 62+(i-1)*20, 516, 20, "", 12, C.text) end
    ui.confirm = button(p, 306, 260, 110, 30, "Confirm", function()
        local action = E.confirmAction
        E.confirmAction = nil; shade:Hide()
        if action and E.open then action() end
        E.dirty = true
    end, true)
    ui.cancel = button(p, 428, 260, 110, 30, "Cancel", function() E.confirmAction = nil; shade:Hide(); E.dirty = true end)
    shade:Hide()
end

function E:Wrap(value, measure, width)
    measure = measure.raw or measure
    local result = {}
    value = self.Display(value):gsub("\r", "")
    for paragraph in (value .. "\n"):gmatch("(.-)\n") do
        local current = ""
        for word in paragraph:gmatch("%S+") do
            measure:SetText(current == "" and word or current .. " " .. word)
            if measure:GetStringWidth() > width and current ~= "" then table.insert(result, current); current = "" end
            while #word > 0 do
                measure:SetText(word)
                if measure:GetStringWidth() <= width then break end
                local part = word
                repeat part = self.Clip(part, #part-1); measure:SetText(part) until #part == 0 or measure:GetStringWidth() <= width
                if part == "" then break end
                table.insert(result, part); word = word:sub(#part+1)
            end
            if word ~= "" then current = current == "" and word or current .. " " .. word end
        end
        table.insert(result, current)
    end
    return result
end

function E:Confirm(title, message, action)
    if self.confirmAction or self.job then return end
    local lines = self:Wrap(message, self.ui.modalLines[1], 516)
    if #lines > #self.ui.modalLines then self:SetStatus("Confirmation text is too long to display safely. Use the native mailbox for this message.", true); return end
    self.confirmAction = action
    self.ui.modalTitle:SetText(title)
    for i, line in ipairs(self.ui.modalLines) do line:SetText(lines[i] or "") end
    self.ui.modal:Show(); self.dirty = true
end

function E:ClearComposer()
    self.attachments, self.cod, self.bagOpen = {}, false, false
    for _, box in ipairs({ self.ui.to, self.ui.subject, self.ui.body, self.ui.gold, self.ui.silver, self.ui.copper }) do box:SetText(""); box:ClearFocus() end
    self.ui.bodyScroll:SetVerticalScroll(0)
    self.dirty = true
end

function E:RenderReader()
    local ui = self.ui
    local m = self.readerIndex and self.inbox[self.readerIndex]
    if m and m.key ~= self.readerKey then m = nil end
    local idle = self.open and not self:Busy()
    if m then ui.reader:Show() else ui.reader:Hide() end
    enabled(ui.readerBack, idle)
    fit(ui.readerTitle, m and (self.MailCategoryPrefix(m, true) .. m.subject) or "", 508)
    fit(ui.readerSender, m and ("From " .. (m.sender ~= "" and m.sender or "Unknown sender")) or "", 620)
    if m and m.hasItem then
        ui.readerAttachment:Show(); ui.readerItemName:Show(); ui.readerNote:Show(); ui.readerPlainNote:Hide()
        setIcon(ui.readerAttachment, m)
        ui.readerItemName:SetText(m.itemName ~= "" and m.itemName or "Item details are loading...")
        local details = m.count > 0 and ("Stack: " .. m.count) or "Attachment cache pending"
        if m.cod > 0 then details = details .. "  |  COD: " .. self.Money(m.cod)
        elseif m.money > 0 then details = details .. "  |  Coins: " .. self.Money(m.money) end
        ui.readerNote:SetText(details .. "  |  Click the icon to take it.")
    else
        ui.readerAttachment:Hide(); ui.readerItemName:Hide(); ui.readerNote:Hide(); ui.readerPlainNote:Show()
        ui.readerPlainNote:SetText(m and (m.money > 0 and ("No item attached  |  Coins: " .. self.Money(m.money)) or "No item attached.") or "")
    end
    if m and self.readerNeedsRefresh then
        self.readerNeedsRefresh = nil
        local body, _, copy, invoice = GetInboxText(self.readerIndex)
        self.readerBody = body or self.readerBody; self.canCopy, self.isInvoice = copy, invoice
        self.readerLines = self:Wrap(self.readerBody, ui.bodyLines[1], 600)
        if invoice then
            local kind, itemName, playerName, bid, buyout, deposit, fee = GetInboxInvoiceInfo(self.readerIndex)
            if kind then
                self.readerLines = self:Wrap((body or "") .. "\n\nAuction " .. kind .. ": " .. (itemName or "") .. "\n" .. (playerName or "") .. "\nBid: " .. self.Money(bid) .. "\nBuyout: " .. self.Money(buyout) .. "\nDeposit: " .. self.Money(deposit) .. "\nFee: " .. self.Money(fee), ui.bodyLines[1], 600)
            end
        end
    end
    local lines = m and self.readerLines or {}
    local perPage = #ui.bodyLines
    local pages = math.max(1, math.ceil(#lines/perPage))
    self.bodyPage = math.min(self.bodyPage or 1, pages)
    for i, line in ipairs(ui.bodyLines) do line:SetText(lines[(self.bodyPage-1)*perPage+i] or "") end
    ui.bodyPageLabel:SetText(m and string.format("Text %d / %d", self.bodyPage, pages) or "")
    enabled(ui.bodyPrev, m and self.bodyPage > 1); enabled(ui.bodyNext, m and self.bodyPage < pages)
    ui.takeItem.label:SetText(m and m.cod > 0 and "Pay COD..." or "Take item")
    enabled(ui.readerAttachment, idle and m and m.hasItem)
    enabled(ui.takeItem, idle and m and m.hasItem)
    enabled(ui.takeMoney, idle and m and m.money > 0)
    enabled(ui.reply, idle and m and m.reply and m.sender ~= "")
    enabled(ui.returnMail, idle and m and m.reply and not m.returned and (m.hasItem or m.money > 0))
    enabled(ui.delete, idle and m and not m.hasItem and m.money == 0 and m.cod == 0)
    enabled(ui.copy, idle and m and self.canCopy and not m.copied)
end

function E:Render()
    local ui, idle = self.ui, self.open and not self:Busy()
    local body = ui.body:GetText()
    if body ~= ui.lastBody then
        ui.lastBody = body
        local lines = self:Wrap(self.Clip(body, 5000), ui.bodyMeasure, 260)
        local height = math.max(132, #lines * 20 + 20)
        ui.body:SetHeight(height); ui.bodyScrollMax = height - 132
        ui.bodyScroll:SetVerticalScroll(math.min(ui.bodyScrollMax, ui.bodyScroll:GetVerticalScroll()))
    end
    ui.balance:SetText(self.Money(GetMoney()))
    fit(ui.status, self.status, 538)
    ui.inboxTab.accent, ui.sendTab.accent = self.tab == "inbox", self.tab == "send"
    enabled(ui.stop, self.job ~= nil); enabled(ui.inboxTab, not self:Busy()); enabled(ui.sendTab, not self:Busy())
    enabled(ui.native, idle)
    if self.tab == "inbox" then ui.inboxPanel:Show(); ui.sendPanel:Hide() else ui.inboxPanel:Hide(); ui.sendPanel:Show() end
    self:SetInputState(idle)
    tint(ui.inboxTab.edges, unpack(self.tab == "inbox" and C.gold or C.line))
    tint(ui.sendTab.edges, unpack(self.tab == "send" and C.gold or C.line))
    local unread, coins, chosen, stacks = 0, 0, 0, 0
    for i, m in ipairs(self.inbox) do
        if not m.read then unread = unread + 1 end
        coins = coins + m.money
        if m.hasItem then stacks = stacks + 1 end
        if self.selected[i] then chosen = chosen+1 end
    end
    local matches, query = {}, string.lower(self.Trim(ui.search:GetText()))
    for i, m in ipairs(self.inbox) do
        if query == "" or string.find(string.lower(m.sender .. " " .. m.subject .. " " .. m.itemName .. " " .. m.category .. " " .. m.categoryDetail), query, 1, true) then table.insert(matches, i) end
    end
    if query == "" then ui.searchHint:Show() else ui.searchHint:Hide() end
    ui.summary:SetText(string.format("%d / %d mails  |  %d unread  |  %d stacks  |  Total: %s", #matches, #self.inbox, unread, stacks, self.Money(coins)))
    local rowsPerPage = #ui.rows
    local pages = math.max(1, math.ceil(#matches/rowsPerPage)); self.page = math.max(1, math.min(self.page, pages))
    for n, row in ipairs(ui.rows) do
        local index = matches[(self.page-1)*rowsPerPage+n]; local m = index and self.inbox[index]
        row.index = index
        if m then
            row:Show()
            local itemTitle = m.hasItem and m.itemName ~= ""
            local title = itemTitle and (m.itemName .. (m.count > 1 and " (" .. m.count .. ")" or "")) or m.subject
            row.subject:SetText((m.read and "" or "* ") .. self.MailCategoryPrefix(m, not itemTitle) .. title)
            row.check.label:SetText(self.selected[index] and "x" or "")
            local amount = m.cod > 0 and ("COD " .. self.Money(m.cod)) or m.money > 0 and self.Money(m.money) or ""
            row.amount:SetText(amount); row.amount:SetTextColor(unpack(m.cod > 0 and C.red or C.green))
            row.days:SetText(m.days < 1 and "< 1 day" or string.format("%d days", math.ceil(m.days)))
            row.days:SetTextColor(unpack(m.days < 3 and C.red or C.green))
            enabled(row.check, idle)
        else row:Hide() end
    end
    if #matches == 0 then ui.empty:Show(); ui.empty:SetText(query == "" and "Your inbox is empty." or "No matching messages.") else ui.empty:Hide() end
    ui.pageLabel:SetText(string.format("%d/%d | %d selected", self.page, pages, chosen))
    enabled(ui.prev, self.page > 1); enabled(ui.next, self.page < pages)
    enabled(ui.refresh, idle); enabled(ui.selectAll, idle and #matches > 0)
    enabled(ui.collect, idle and chosen > 0); enabled(ui.collectAll, idle and #self.inbox > 0)
    enabled(ui.cleanup, idle); ui.cleanup.label:SetText((self.cleanup and "[x]" or "[ ]") .. " Delete empty")
    self:RenderReader()
    local first = self.attachments[1]
    ui.subjectHint:SetText(self.Trim(ui.subject:GetText()) == "" and ("Auto subject: " .. (first and first.name or "[No Subject]")) or "Multiple stacks are sent as numbered letters.")
    ui.attachmentCount:SetText(#self.attachments .. " / 21 stacks")
    for i, b in ipairs(ui.slots) do
        local item = self.attachments[i]; setIcon(b, item)
        if item then
            local valid = self:SameBagItem(item, true)
            b.image:SetDesaturated(not valid)
            if not valid then tint(b.edges, unpack(C.red)) end
        end
    end
    ui.cod.label:SetText((self.cod and "[x]" or "[ ]") .. " COD")
    enabled(ui.send, idle); enabled(ui.clear, idle); enabled(ui.addItems, idle); enabled(ui.cod, idle); enabled(ui.recent, idle)
    ui.postage:SetText("Postage: " .. self.Money(GetSendMailPrice()*math.max(1, #self.attachments)))
    if self.bagOpen and self.tab == "send" and idle then
        ui.bagPicker:Show()
        local items = {}
        for bag = 0, 4 do for slot = 1, GetContainerNumSlots(bag) do
            local item = self:BagItem(bag, slot); if item then table.insert(items, item) end
        end end
        local bagPages = math.max(1, math.ceil(#items/32)); self.bagPage = math.max(1, math.min(self.bagPage, bagPages))
        for i, b in ipairs(ui.bagSlots) do
            b.item = items[(self.bagPage-1)*32+i]; setIcon(b, b.item)
            if b.item then b.image:SetDesaturated(self:Reserved(b.item.bag, b.item.slot) or b.item.locked) end
        end
        enabled(ui.bagPrev, self.bagPage > 1); enabled(ui.bagNext, self.bagPage < bagPages)
        ui.bagPageLabel:SetText(string.format("Page %d / %d   -   %d stacks queued", self.bagPage, bagPages, #self.attachments))
    else ui.bagPicker:Hide() end
    local job = self.job
    -- Fixed segments also avoid changing texture geometry after root scaling.
    local completed = job and math.floor(21*(job.confirmed or job.pos-1)/job.total) or 0
    for i, segment in ipairs(ui.progress) do if i <= completed then segment:Show() else segment:Hide() end end
end
