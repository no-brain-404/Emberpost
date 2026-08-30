local E = EmberPost

local function modifiers()
    return IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown()
end

local function emptyCursor()
    return not CursorHasItem() and not CursorHasMoney() and not CursorHasSpell() and not SpellIsTargeting()
end

function E:PostalConflict()
    return Postal ~= nil or (IsAddOnLoaded and IsAddOnLoaded("Postal"))
end

function E:InstallHooks()
    if self.original then return end
    local original = { PickupContainerItem = PickupContainerItem, UseContainerItem = UseContainerItem,
        SplitContainerItem = SplitContainerItem, ClearCursor = ClearCursor }
    self.original = original

    local function reserved(bag, slot)
        if E.open and not E.nativeMode and E:Reserved(bag, slot) then
            E:SetStatus("That stack is queued for mail. Remove it from the queue first.", true)
            return true
        end
    end

    PickupContainerItem = function(bag, slot, ...)
        if reserved(bag, slot) then return end
        local item = emptyCursor() and E:BagItem(bag, slot)
        original.PickupContainerItem(bag, slot, ...)
        E.cursorOrigin = item and CursorHasItem() and item or nil
    end
    SplitContainerItem = function(bag, slot, ...)
        if reserved(bag, slot) then return end
        -- A split cursor is not the original whole stack; never guess its count.
        original.SplitContainerItem(bag, slot, ...)
        E.cursorOrigin = nil
    end
    ClearCursor = function(...)
        E.cursorOrigin = nil
        return original.ClearCursor(...)
    end
    for _, source in ipairs({"PickupInventoryItem", "PickupMerchantItem", "PickupBagFromSlot"}) do
        local pickup = _G[source]
        if type(pickup) == "function" then
            original[source] = pickup
            _G[source] = function(...) E.cursorOrigin = nil; return pickup(...) end
        end
    end
    UseContainerItem = function(bag, slot, ...)
        if E:PostalConflict() then return original.UseContainerItem(bag, slot, ...) end
        if reserved(bag, slot) then return end
        if not modifiers() and emptyCursor() then
            if E.open and not E.nativeMode and E.ui.frame:IsVisible() and E.tab == "send" then
                E:AddAttachment(bag, slot)
                return
            end
            -- Postal's other convenience: offer an item into the first empty
            -- trade slot. This never accepts a trade or moves trade money.
            if TradeFrame and TradeFrame:IsVisible() then
                local item = E:BagItem(bag, slot)
                if item and not item.locked then
                    for i = 1, 6 do
                        local link = GetTradePlayerItemLink(i)
                        if not link or link == "" then
                            original.PickupContainerItem(bag, slot)
                            if CursorHasItem() then ClickTradeButton(i) end
                            return
                        end
                    end
                    E:SetStatus("All six trade item slots are occupied.", true)
                    return
                end
            end
        end
        return original.UseContainerItem(bag, slot, ...)
    end
end

function E:HideNative()
    -- The event order and Blizzard frame names are not specified in the wiki.
    -- Wrap only this frame's hide callback, only during our own hide operation.
    -- Ordinary closes keep their original behavior; no global CloseMail hook.
    local frame = MailFrame
    if not frame then return end
    if self.nativeFrame ~= frame then
        self.nativeFrame = frame
        local onHide, onShow = frame:GetScript("OnHide"), frame:GetScript("OnShow")
        frame:SetScript("OnHide", function(...)
            if not E.hidingNative and onHide then return onHide(...) end
        end)
        frame:SetScript("OnShow", function(...)
            if onShow then onShow(...) end
            if E.open and not E.nativeMode then E.nativeHidePending = true end
        end)
    end
    self.hidingNative = true
    frame:Hide()
    self.hidingNative = false
end

function E:OpenMailbox()
    if self:PostalConflict() then
        self:SetStatus("Disable the original Postal addon, then restart the client. EmberPost did not take over this mailbox.", true)
        return
    end
    self:Initialize()
    if self.open then return end -- repeated MAIL_SHOW must not reset an active job
    self.open, self.nativeMode = true, false
    self.selected, self.readerIndex, self.page = {}, nil, 1
    self.inbox = self:Snapshot() or {}
    self.nativeHidePending, self.nextPoll, self.dirty = true, 0, true
    self.ui.frame:Show()
    self:SetEscapeEnabled(true)
    self:SetStatus("Mailbox ready. Bulk collection skips COD; letter deletion is optional.")
    if self.sendUncertain or self.inboxUncertain then self:CanAct() end
    CheckInbox()
end

function E:EndSession()
    if not self.open then return end
    if self.job then self:Stop("Mailbox closed. The queue was stopped; completed actions cannot be undone.") end
    self.open, self.nativeMode, self.nativeHidePending = false, false, nil
    self.confirmAction, self.cursorOrigin, self.readerIndex = nil, nil, nil
    self.ownsDraft = false -- CloseMail / MAIL_CLOSED owns native draft cleanup
    self:SetEscapeEnabled(false)
    self:SetInputState(false)
    self.ui.modal:Hide()
    self.hidingOwn = true; self.ui.frame:Hide(); self.hidingOwn = false
    self:ClearComposer()
    self.selected = {}
end

function E:CloseMailbox()
    if not self.open then return end
    self:EndSession()
    CloseMail()
end

function E:NativeMailbox()
    if not self.open then self:SetStatus("Visit a mailbox first.", true); return end
    if self.job or self.sendUncertain or self.inboxUncertain then
        self:SetStatus("Cannot switch UI during an active or unconfirmed request. Wait for its result, or restart the client.", true)
        return
    end
    if not MailFrame then self:SetStatus("This client does not expose MailFrame. Close the mailbox and disable EmberPost to use the native UI.", true); return end
    self.confirmAction = nil; self.ui.modal:Hide()
    self:ClearComposer()
    self.nativeMode, self.nativeHidePending = true, nil
    self:SetEscapeEnabled(false)
    self:SetInputState(false)
    self.hidingOwn = true; self.ui.frame:Hide(); self.hidingOwn = false
    MailFrame:Show()
    self:SetStatus("Native mailbox enabled for this visit. /emberpost restores EmberPost.")
end

function E:MailError(message)
    local job = self.job
    if not job then return end
    message = type(message) == "string" and message or "Unknown client mail error"
    if ERR_ITEM_MAX_COUNT and message == ERR_ITEM_MAX_COUNT and job.kind == "collect" and job.all and
        job.pending and job.pending.action == "item" then
        job.skipKeys = job.skipKeys or {}
        job.skipKeys[job.pending.before.key] = true
        job.pending = nil
        job.uniqueSkipped = (job.uniqueSkipped or 0) + 1
        job.nextAt = GetTime() + self.collectInterval
        self:SetStatus("Unique-item limit: skipped that message and continuing Open All.", true)
        return
    end
    -- Unique-item failures may skip one whole message, but only while waiting
    -- for an item take and while every mailbox row still matches its snapshot.
    if ERR_ITEM_MAX_COUNT and message == ERR_ITEM_MAX_COUNT and job.kind == "collect" and
        job.pending and job.pending.action == "item" and self.SameInboxSet(job.expected, self:Snapshot()) then
        job.pending, job.pos = nil, job.pos + 1
        job.uniqueSkipped = (job.uniqueSkipped or 0) + 1
        job.nextAt = GetTime() + self.interval
        self:SetStatus("Unique-item limit: skipped that message; its contents remain in the inbox.", true)
        return
    end
    if job.kind ~= "send" and ((ERR_INV_FULL and message == ERR_INV_FULL) or (ERR_ITEM_MAX_COUNT and message == ERR_ITEM_MAX_COUNT)) then
        job.pending = nil -- explicit rejection, no successful action to await
    end
    self:Stop("Stopped after client error: " .. self.Display(message) .. ". Check the mailbox before trying again.", job.kind == "send" and job.phase == "sending")
end

function E:TraceMail(eventName, first, second)
    local job = self.job
    local detail = job and string.format("%s %s %d/%d", job.kind, job.phase or "pending", job.pos, job.total) or "idle"
    if job and job.kind == "send" and job.phase == "settling" then
        detail = string.format("send settling after %d/%d (%d verified)", job.pos-1, job.total, job.confirmed or 0)
    end
    if job and job.sentAt then detail = detail .. string.format(" +%.2fs", GetTime()-job.sentAt) end
    for _, value in ipairs({ first == nil and "" or first, second == nil and "" or second }) do
        if type(value) == "string" or type(value) == "number" then
            local safe = self.Clip(self.Display(value):gsub("[%c]", " "), 120)
            if safe ~= "" then detail = detail .. " | " .. safe end
        end
    end
    self.mailTrace = self.mailTrace or {}
    table.insert(self.mailTrace, string.format("%.2f %s: %s", GetTime(), eventName, detail))
    while #self.mailTrace > 20 do table.remove(self.mailTrace, 1) end
    return detail
end

function E:MailFailed(first, second)
    local detail = self:TraceMail("MAIL_FAILED", first, second)
    local job = self.job
    if job and job.kind == "send" and job.phase == "settling" then
        -- Observed on Unreal Azeroth: MAIL_SEND_SUCCESS followed by MAIL_FAILED
        -- for the same dispatch, before another SendMail call. There is no
        -- pending next-letter request to reject. Keep the anomaly in the trace;
        -- TickSend still requires BOTH the sent bag-slot change and exact money
        -- deduction before it may prepare a different stack. Never resend this one.
        job.successFailure = true
        -- Keep the ordinary verification progress visible. The raw client event
        -- is already in /emberpost debug; it is not a failure of the next send.
        return
    end
    if job and job.kind ~= "send" then
        -- The client can pair MAIL_FAILED with a successful TakeInbox* request,
        -- just as it does after SendMail. MAIL_FAILED has no documented request
        -- identifier, so do not replay the request or guess which result won.
        -- TickInbox accepts only the exact targeted row transition with every
        -- surrounding row unchanged. A truly unchanged failure stops after the
        -- ordinary confirmation timeout and is then safe to unlock.
        if job.pending then
            local firstFailure = not job.pending.failureAt
            job.pending.failureReported = true
            job.pending.failureAt = job.pending.failureAt or GetTime()
            job.pending.failureCount = (job.pending.failureCount or 0) + 1
            if job.kind == "collect" and firstFailure then
                job.pause = math.min(self.collectMaxPause,
                    math.max(self.collectBackoff, (job.pause or self.collectPause) * 2))
            end
            job.nextAt = GetTime()
            if job.all then
                self:SetStatus("Client reported MAIL_FAILED; waiting briefly for the bag or inbox update before deciding.")
            end
        end
        return
    end
    if self.job then
        -- MAIL_FAILED is a terminal negative acknowledgement, not a timeout.
        self.job.phase = "failed"
        self:Stop("Mail request failed (" .. detail .. "). No automatic retry; review the mailbox and bags. /emberpost debug shows recent mail events.")
    elseif self.sendUncertain or self.inboxUncertain then
        if self.sendVerificationFailed then
            self:SetStatus("Another failure notification arrived for an unverified transaction. Restart the client and check your bags.")
            return
        end
        if self.ownsDraft then ClearSendMail(); self.ownsDraft = false end
        self.sendUncertain, self.inboxUncertain, self.stoppedInbox = false, false, nil
        self:SetStatus("The stopped mail request reported failure. Review the mailbox and bags before trying again.", true)
    end
end

function E:Event(eventName, first, second)
    if eventName == "PLAYER_LOGIN" then
        if not self:PostalConflict() then self:Initialize() end
    elseif eventName == "MAIL_SHOW" then self:OpenMailbox()
    elseif eventName == "MAIL_CLOSED" then self:EndSession()
    elseif eventName == "MAIL_SEND_SUCCESS" then self:TraceMail(eventName); self:SendSucceeded()
    elseif eventName == "MAIL_FAILED" then self:MailFailed(first, second)
    elseif eventName == "UI_ERROR_MESSAGE" then
        if self.job then self:TraceMail(eventName, first, second) end
        self:MailError(type(first) == "string" and first or second)
    elseif eventName == "MAIL_INBOX_UPDATE" then self.readerNeedsRefresh, self.dirty = true, true
    elseif eventName == "DISPLAY_SIZE_CHANGED" then if self.ui then self:RestorePosition() end
    else self.dirty = true end
end

function E:Slash(command)
    local verb, value = self.Trim(command):match("^(%S*)%s*(.-)$")
    verb = string.lower(verb or "")
    if verb == "stop" then
        if self.job then self:Stop("Stopped by you. Completed actions cannot be undone.") end
    elseif verb == "native" then self:NativeMailbox()
    elseif verb == "debug" then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("EmberPost " .. self.version .. " recent mail events (session only):")
            for _, line in ipairs(self.mailTrace or {}) do DEFAULT_CHAT_FRAME:AddMessage(line) end
        end
    elseif verb == "help" then
        self:SetStatus("Visit a mailbox to collect or compose. /emberpost reset (compact) | scale " .. self.minScale .. "-" .. self.maxScale .. " | stop | native | debug | help", true)
    elseif verb == "reset" or verb == "scale" then
        self:Initialize()
        if verb == "reset" then self.settings.position = nil; self.settings.scale = self.defaultScale; self:RestorePosition(true)
        else
            local scale = tonumber(value)
            if not scale or scale < self.minScale or scale > self.maxScale then self:SetStatus("Use /emberpost scale " .. self.minScale .. " through " .. self.maxScale, true); return end
            self.settings.scale = scale; self:RestorePosition()
        end
        self:SetStatus("Window layout updated.", true)
    elseif self.open then
        self.nativeMode, self.nativeHidePending = false, true
        self.ui.frame:Show(); self:SetEscapeEnabled(true); self.dirty = true
    else self:SetStatus("Visit a mailbox first. Use /emberpost help for commands.", true) end
end

SLASH_EMBERPOST1, SLASH_EMBERPOST2 = "/emberpost", "/epost"
SlashCmdList = SlashCmdList or {}
SlashCmdList.EMBERPOST = function(message) E:Slash(message) end
E.events = CreateFrame("Frame", "EmberPostEvents", UIParent)
E.events:SetWidth(1); E.events:SetHeight(1); E.events:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
for _, eventName in ipairs({ "PLAYER_LOGIN", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "MAIL_SEND_SUCCESS",
    "MAIL_FAILED", "UI_ERROR_MESSAGE", "BAG_UPDATE", "ITEM_LOCK_CHANGED", "PLAYER_MONEY", "DISPLAY_SIZE_CHANGED" }) do E.events:RegisterEvent(eventName) end
E.events:SetScript("OnEvent", function(_, eventName, first, second)
    E:Event(eventName or event, first or arg1, second or arg2)
end)
E.events:SetScript("OnUpdate", function() E:Tick() end)
