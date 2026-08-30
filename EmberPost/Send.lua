local E = EmberPost

function E:AddAttachment(bag, slot, fromCursor)
    if not self:CanAct() or self.tab ~= "send" then return false end
    if type(bag) ~= "number" or bag < 0 or bag > 4 then self:SetStatus("Only items carried in your bags can be queued.", true); return false end
    if self:Reserved(bag, slot) then self:SetStatus("That stack is already queued."); return false end
    if #self.attachments >= self.maxAttachments then self:SetStatus("The queue holds at most 21 stacks.", true); return false end
    local item = self:BagItem(bag, slot)
    if not item then self:SetStatus("That bag slot is empty or not cached.", true); return false end
    if item.locked and not fromCursor then self:SetStatus("That stack is locked. Try again shortly.", true); return false end
    local ok, reason = self:CheckMailable(item)
    if not ok then self:SetStatus(reason, true); return false end
    table.insert(self.attachments, item)
    self:SetStatus(#self.attachments .. "/21 stacks queued. Each stack is sent in a separate letter.")
    return true
end

function E:DropAttachment()
    if self:Busy() or not self.open or self.tab ~= "send" then return end
    local item = self.cursorOrigin
    if not CursorHasItem() or not item then
        self:SetStatus("Drag a whole stack from a bag, or use Add items.", true); return
    end
    if not self:SameBagItem(item, true) then
        self:SetStatus("The dragged stack changed. Put it back and select it again.", true); return
    end
    if self:AddAttachment(item.bag, item.slot, true) then ClearCursor(); self.cursorOrigin = nil end
end

function E:RemoveAttachment(index)
    if self:Busy() then return end
    table.remove(self.attachments, index)
    self:SetStatus("Stack removed from the queue. It stays in your bags.")
end

function E:ValidateDraft(draft)
    draft.to = self.Trim(draft.to)
    draft.subject = self.Trim(draft.subject)
    if draft.to == "" or #draft.to > 48 or draft.to:find("[%c|]") then return nil, "Enter a valid recipient name (up to 48 bytes)." end
    if string.lower(draft.to) == string.lower(UnitName("player") or "") then return nil, "Choose another recipient; you cannot mail yourself." end
    if draft.subject == "" then
        local first = self.attachments[1]
        draft.subject = first and self.Clip(self.Display(first.name):gsub("[%c]", " "), 64) or "[No Subject]"
    end
    if #draft.subject > 64 or draft.subject:find("[%c|]") then return nil, "Subject must fit in 64 bytes and contain no control characters or pipes." end
    draft.body = draft.body or ""
    if #draft.body > 5000 then return nil, "Letter text is limited to 5000 bytes." end
    if not draft.amount or draft.amount < 0 or draft.amount > 2000000000 or draft.amount ~= math.floor(draft.amount) then return nil, "Invalid money amount." end
    if draft.cod and (#self.attachments == 0 or draft.amount == 0) then return nil, "COD needs an attached stack and a positive amount." end
    local total = math.max(1, #self.attachments)
    local cost = GetSendMailPrice() * total + (not draft.cod and draft.amount or 0)
    if cost > GetMoney() then return nil, "Not enough money for all postage and enclosed coins." end
    if CursorHasItem() or CursorHasMoney() or CursorHasSpell() or SpellIsTargeting() then return nil, "Put away the cursor item, money, or targeting spell first." end
    if GetSendMailItem() or GetSendMailMoney() > 0 or GetSendMailCOD() > 0 then return nil, "Another outgoing draft exists. Clear it in the native mailbox first." end
    for _, item in ipairs(self.attachments) do
        if not self:SameBagItem(item) then return nil, "A queued stack moved, changed, or is locked. Remove it and select it again." end
    end
    return total
end

function E:StartSend(draft)
    if not self:CanAct() then return end
    local total, errorText = self:ValidateDraft(draft)
    if not total then self:SetStatus(errorText, true); return end
    local queue = {}
    for i, item in ipairs(self.attachments) do queue[i] = item end
    local text = string.format("Send %d letter(s) to %s?\nSubject: %s\nPostage: %s", total, self.Display(draft.to), self.Display(draft.subject), self.Money(GetSendMailPrice() * total))
    if draft.amount > 0 then
        text = text .. "\n" .. (draft.cod and "COD charged on the FIRST letter only: " or "Coins enclosed in the FIRST letter only: ") .. self.Money(draft.amount)
    end
    text = text .. "\nItems and coins sent cannot be recalled."
    self:Confirm("Review outgoing mail", text, function()
        if not self.open or self.job or self.sendUncertain then return end
        if #queue ~= #self.attachments then self:SetStatus("The attachment queue changed. Review again.", true); return end
        for i, item in ipairs(queue) do if self.attachments[i] ~= item then self:SetStatus("The attachment queue changed. Review again.", true); return end end
        local valid, why = self:ValidateDraft(draft)
        if not valid then self:SetStatus(why, true); return end
        self.job = { kind = "send", queue = queue, draft = draft, total = total, pos = 1, confirmed = 0,
            phase = "prepare", nextAt = GetTime() + self.sendInterval }
        self:SetStatus("Preparing mail 1/" .. total .. "...")
    end)
end

function E:TickSend(now)
    local job = self.job
    if job.phase == "sending" then
        if now - job.sentAt > self.timeout then self:Stop("Send confirmation timed out. Wait for its result, or restart the client; check your bags before retrying. Reopening alone cannot clear this lock.", true) end
        return
    end
    if job.phase == "settling" then
        -- Success can arrive before the client's bag/draft cleanup finishes.
        -- Do not clear/reuse the native draft from its event callback. Wait for
        -- the sent stack to leave its slot and pace the next letter separately
        -- from inbox polling. A timer never retries an unconfirmed request.
        local bagPending = job.sentItem and self:SameBagItem(job.sentItem, true)
        local moneyPending = GetMoney() ~= job.expectedBalance
        if not job.reconciled and (bagPending or moneyPending) then
            if now - job.ackAt > self.timeout then
                return self:Stop("Success was reported, but " .. (bagPending and "the sent bag slot has not updated" or "the postage/coin balance does not match") .. ". Nothing else was sent. Restart the client and check your bags before retrying.", true)
            end
            job.nextAt = now + self.sendInterval
            return
        end
        if not job.reconciled then
            job.reconciled, job.confirmed = true, job.confirmed + 1
            if job.sentItem then
                for i = #self.attachments, 1, -1 do
                    if self.attachments[i] == job.sentItem then table.remove(self.attachments, i); break end
                end
            end
            self:TraceMail("Send reconciled")
            self:SetStatus(job.confirmed .. "/" .. job.total .. " sent and verified. Preparing to continue...")
        end
        -- The old two-second pause predated the confirmed success/failure
        -- event-order fix. Keep a short settling turn; never skip reconciliation.
        local pause = job.pos > job.total and self.sendInterval or self.sendPause
        if now < job.ackAt + pause then
            job.nextAt = job.ackAt + pause
            return
        end
        if self.ownsDraft then ClearSendMail(); self.ownsDraft = false end
        job.phase, job.nextAt = "prepare", now + self.sendInterval
        return
    end
    if job.pos > job.total then
        self.job, self.ownsDraft = nil, false
        self:Remember(job.draft.to)
        self:ClearComposer()
        self:SetStatus("Sent " .. job.total .. " letter(s) to " .. self.Display(job.draft.to) .. ".")
        return
    end
    if CursorHasItem() or CursorHasMoney() or CursorHasSpell() or SpellIsTargeting() then return self:Stop("Cursor became occupied. Stopped before sending.") end
    if job.phase == "prepare" then
        for i = job.pos, #job.queue do
            if not self:SameBagItem(job.queue[i]) then return self:Stop("A queued stack moved, changed, or locked. Stopped before sending.") end
        end
        if GetSendMailItem() or GetSendMailMoney() > 0 or GetSendMailCOD() > 0 then return self:Stop("Another outgoing attachment or amount appeared. Stopped safely.") end
        self.ownsDraft = true
        ClearSendMail()
        local item = job.queue[job.pos]
        if item then
            self.preparingCursor = true
            self.original.PickupContainerItem(item.bag, item.slot)
            if not CursorHasItem() then return self:Stop("Could not pick up the queued stack.") end
            ClickSendMailItemButton()
            if self.job ~= job then return end -- synchronous native error event
            if CursorHasItem() then ClearCursor(); return self:Stop("The client rejected that attachment. This letter was not sent.") end
            self.preparingCursor = nil
        end
        job.phase, job.preparedAt, job.nextAt = "verify", now, now + self.sendInterval
        return
    end
    local item = job.queue[job.pos]
    local name, texture, count = GetSendMailItem()
    if item then
        if not name or name ~= item.name or count ~= item.count or texture ~= item.texture or not self:SameBagItem(item, true) then
            return self:Stop("Outgoing attachment does not match the selected stack. This letter was not sent.")
        end
    elseif name then return self:Stop("Unexpected outgoing attachment. This letter was not sent.") end
    local amount = job.pos == 1 and job.draft.amount or 0
    local cost = GetSendMailPrice() * (job.total - job.pos + 1) + (not job.draft.cod and amount or 0)
    if GetMoney() < cost then return self:Stop("Not enough money for the remaining letters.") end
    -- Do NOT use SetSendMailMoney(0) to reset: this client's documented setter
    -- attaches the player's whole balance even when zero was requested.
    if amount > 0 then
        if job.draft.cod then SetSendMailCOD(amount) else SetSendMailMoney(amount) end
        if self.job ~= job then return end
    end
    local expectedMoney = not job.draft.cod and amount or 0
    local expectedCOD = job.draft.cod and amount or 0
    if GetSendMailMoney() ~= expectedMoney or GetSendMailCOD() ~= expectedCOD then
        return self:Stop("Client money/COD mismatch: draft cleared, this letter NOT sent. This client may attach your entire balance instead of the requested amount.")
    end
    local suffix = job.total > 1 and string.format(" (Part %d of %d)", job.pos, job.total) or ""
    local subject = self.Clip(job.draft.subject, 64 - #suffix) .. suffix
    job.expectedBalance = GetMoney() - GetSendMailPrice() - expectedMoney
    job.phase, job.sentAt = "sending", now
    self:TraceMail("SendMail")
    self:SetStatus("Sending " .. job.pos .. "/" .. job.total .. " to " .. self.Display(job.draft.to) .. "...")
    SendMail(job.draft.to, subject, job.draft.body)
end

function E:SendSucceeded()
    local job = self.job
    if self.sendUncertain and not job then
        if self.sendVerificationFailed then
            self:SetStatus("Another success notification arrived, but the stopped transaction was not verified. Restart the client and check your bags.")
            return
        end
        self.sendUncertain = false
        if self.ownsDraft then ClearSendMail(); self.ownsDraft = false end
        self:SetStatus("The stopped send was confirmed. Check your bags; the queue will not resume automatically.", true)
        return
    end
    if not self.open or not job or job.kind ~= "send" or job.phase ~= "sending" then return end
    local item = job.queue[job.pos]
    -- Only MAIL_SEND_SUCCESS advances the queue. Never timer-retry SendMail.
    job.sentItem, job.ackAt = item, GetTime()
    job.successFailure, job.reconciled = nil, nil
    job.pos, job.phase, job.nextAt = job.pos + 1, "settling", GetTime() + self.sendInterval
    self:SetStatus("Success reported for " .. (job.pos-1) .. "/" .. job.total .. ". Checking the bag update and postage...")
    self.dirty = true
end
