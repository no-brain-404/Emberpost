-- Fresh Lua 5.1 implementation for Emberveil. No Ace or Blizzard templates.
EmberPost = { version = "1.0.15", maxAttachments = 21, timeout = 15, interval = 0.35,
    sendInterval = 0.08, sendPause = 0.10, collectInterval = 0.08, collectPause = 0.15,
    collectSettle = 0.60, collectFailureGrace = 5.0, collectBackoff = 0.50,
    collectMaxPause = 0.75, collectRetryLimit = 1,
    inboxRemovePause = 1.0,
    defaultScale = 0.60, minScale = 0.45, maxScale = 1.25 }
local E = EmberPost
E.selected, E.attachments, E.inbox = {}, {}, {}
E.tab, E.page, E.bagPage = "inbox", 1, 1
E.status, E.open = "Visit a mailbox to begin.", false

function E.Trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function E.Display(s)
    -- Mail is text, never executable code or interactive markup.
    return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", ""))
end

function E.Clip(s, bytes)
    s = tostring(s or "")
    if #s <= bytes then return s end
    local n = bytes
    while n > 0 and s:byte(n + 1) and s:byte(n + 1) >= 128 and s:byte(n + 1) < 192 do n = n - 1 end
    return s:sub(1, n)
end

function E.Money(amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    return string.format("%dg %02ds %02dc", math.floor(amount / 10000), math.floor(amount / 100) % 100, amount % 100)
end

function E.Amount(gold, silver, copper)
    local values = { gold, silver, copper }
    for i = 1, 3 do
        local s = E.Trim(values[i])
        if s == "" then s = "0" end
        if not s:match("^%d+$") or #s > 9 then return nil, "Enter whole, non-negative coin amounts." end
        values[i] = tonumber(s)
    end
    if values[2] > 99 or values[3] > 99 then return nil, "Silver and copper must be between 0 and 99." end
    local total = values[1] * 10000 + values[2] * 100 + values[3]
    if total > 2000000000 then return nil, "That amount exceeds the addon safety limit." end
    return total
end

function E:SetStatus(message, warn)
    self.status = message
    if warn and DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("EmberPost: " .. message, 1, 0.65, 0.3) end
    self.dirty = true
end

function E:Initialize()
    if self.initialized then return end
    self.initialized = true
    if type(EmberPostDB) ~= "table" then EmberPostDB = {} end
    self.db = EmberPostDB
    if type(self.db.characters) ~= "table" then self.db.characters = {} end
    local key = (GetRealmName() or "") .. ":" .. (UnitName("player") or "")
    if type(self.db.characters[key]) ~= "table" then self.db.characters[key] = {} end
    self.settings = self.db.characters[key]
    local savedScale = tonumber(self.settings.scale)
    -- Migrate the original oversized default once. Preserve custom scales and
    -- subsequent deliberate choices of 1.0 without deleting saved preferences.
    if not self.settings.scaleRevision and savedScale == 1 then savedScale = nil end
    self.settings.scale = math.max(self.minScale, math.min(self.maxScale, savedScale or self.defaultScale))
    self.settings.scaleRevision = 1
    if type(self.settings.recent) ~= "table" then self.settings.recent = {} end
    if RegisterForSave then RegisterForSave("EmberPostDB") end
    self:BuildUI()
    self:InstallHooks()
end

function E:Remember(name)
    local list = self.settings.recent
    for i = #list, 1, -1 do if string.lower(list[i]) == string.lower(name) then table.remove(list, i) end end
    table.insert(list, 1, name)
    while #list > 8 do table.remove(list) end
end

function E:BagItem(bag, slot)
    local texture, count, locked, quality = GetContainerItemInfo(bag, slot)
    local link = GetContainerItemLink(bag, slot)
    if not texture or texture == "" or not count or count < 1 or not link or link == "" then return nil end
    local name = GetItemInfo(link)
    return { bag = bag, slot = slot, texture = texture, count = count, locked = locked,
        quality = quality or 1, link = link, name = name or link:match("%[(.-)%]") or "Item" }
end

function E:CountBagItem(name, texture)
    if not name or name == "" or not texture or texture == "" then return nil end
    local total = 0
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local item = self:BagItem(bag, slot)
            if item and item.name == name and item.texture == texture then total = total + item.count end
        end
    end
    return total
end

function E:SameBagItem(item, allowLocked)
    local now = self:BagItem(item.bag, item.slot)
    return now and now.link == item.link and now.count == item.count and (allowLocked or not now.locked)
end

function E:Reserved(bag, slot)
    for _, item in ipairs(self.attachments) do
        if item.bag == bag and item.slot == slot then return true end
    end
    return false
end

function E:CheckMailable(item)
    local tip = self.scanTooltip
    tip:SetOwner(self.scanOwner, "ANCHOR_NONE")
    tip:ClearLines()
    -- Tooltip construction is only an optional early restriction check. Some
    -- client builds return false/nil for valid bag items on a hidden tooltip.
    -- That does not mean the bag slot is empty or the item cannot be mailed.
    tip:SetBagItem(item.bag, item.slot)
    local bad = { ITEM_SOULBOUND, ITEM_BIND_QUEST, ITEM_CONJURED, ITEM_BIND_ON_PICKUP }
    local reason
    for i = 1, tip:NumLines() do
        local line = _G[tip:GetName() .. "TextLeft" .. i]
        local text = line and line:GetText()
        for _, flag in pairs(bad) do if flag and text == flag then reason = text end end
    end
    tip:Hide()
    if reason then return false, "Cannot mail this item: " .. reason end
    -- If no tooltip was built, queue the verified bag snapshot and defer the
    -- restriction check to ClickSendMailItemButton. The native attachment and
    -- its exact identity are verified in Send.lua before any SendMail call.
    return true
end

function E:Stop(reason, uncertain)
    local job = self.job
    self.job = nil
    if job and job.kind == "send" then
        if job.phase == "settling" and not job.reconciled then
            -- An acknowledgement alone is insufficient after contradictory
            -- events. Do not let stop/close or another late notification unlock
            -- a draft whose bag and balance transaction was never verified.
            uncertain, self.sendVerificationFailed = true, true
            reason = (reason or "Stopped.") .. " The reported success is unverified; restart the client before another send."
        end
        reason = string.format("%d/%d letters confirmed. %s", job.confirmed or job.pos - 1, job.total, reason or "Stopped. Completed actions cannot be undone.")
        -- Never unlock or replay a send whose server result is unknown.
        if uncertain or job.phase == "sending" then
            self.sendUncertain = true
        elseif self.ownsDraft then
            if self.preparingCursor and CursorHasItem() then ClearCursor() end
            self.preparingCursor = nil
            ClearSendMail()
            self.ownsDraft = false
        end
    elseif job and job.pending then
        self.inboxUncertain = true
        self.stoppedInbox = job
        reason = (reason or "Stopped.") .. " A request may still finish. Wait for confirmation; restart the client if it never arrives."
    end
    self:SetStatus(reason or "Stopped. Completed actions cannot be undone.", true)
end

function E:Busy()
    return self.job ~= nil or self.sendUncertain or self.inboxUncertain or self.confirmAction ~= nil
end

function E:CanAct()
    if not self.open or self.nativeMode then self:SetStatus("Open the EmberPost mailbox first.", true); return false end
    if self.sendUncertain or self.inboxUncertain then
        self:SetStatus("An earlier mail request is unconfirmed. Wait for its result, or restart the client. Check your bags/inbox before retrying.", true); return false
    end
    if self:Busy() then self:SetStatus("Finish or stop the current action first.", true); return false end
    return true
end

function E:Tick()
    local now = GetTime()
    if self.cursorOrigin and not CursorHasItem() then self.cursorOrigin = nil end
    if self.open and self.stoppedInbox and now >= (self.nextStoppedPoll or 0) then
        self.nextStoppedPoll = now + self.interval
        local list = self:Snapshot()
        if list and self:InboxTransition(self.stoppedInbox, list) == "done" then
            self.stoppedInbox, self.inboxUncertain = nil, false
            self:SetStatus("The stopped inbox request finished. Review the inbox before starting another action.", true)
        end
    end
    if self.open and not self.nativeMode and self.nativeHidePending then self:HideNative(); self.nativeHidePending = nil end
    if self.open and self.job and now >= (self.job.nextAt or 0) then
        if self.job.kind == "send" then self:TickSend(now) else self:TickInbox(now) end
    end
    if self.open and now >= (self.nextPoll or 0) then
        self.nextPoll = now + 0.4
        self:RefreshInbox()
        self.dirty = true -- also catches EditBox:Insert (no OnTextChanged here).
    end
    if self.dirty and self.ui and self.ui.frame:IsShown() then self.dirty = false; self:Render() end
end
