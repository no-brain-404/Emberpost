local E = EmberPost
local function encode(v)
    local s = tostring(v or "")
    return #s .. ":" .. s
end

-- Classification uses cached header presentation only. It must never call
-- GetInboxText while listing mail because doing so marks unread mail as read.
function E.MailCategory(sender, subject, cod, returned, gm)
    sender, subject = string.lower(tostring(sender or "")), string.lower(tostring(subject or ""))
    if gm then return "GM", "Game Master mail" end
    if returned then return "Returned", "Returned mail" end
    local auction = sender:find("auction house", 1, true) or subject:find("auction", 1, true)
    if auction then
        if subject:find("expired", 1, true) then return "Expired", "Expired auction" end
        if subject:find("outbid", 1, true) then return "Outbid", "Auction outbid" end
        if subject:find("cancelled", 1, true) or subject:find("canceled", 1, true) then return "Cancelled", "Cancelled auction" end
        if subject:find("successful", 1, true) or subject:find("sold", 1, true) then return "Sold", "Successful auction sale" end
        if subject:find("won", 1, true) then return "Won", "Won auction" end
        if subject:find("pending", 1, true) then return "Pending", "Pending auction sale" end
        return "Auction", "Auction House mail"
    end
    if (cod or 0) > 0 then return "COD", "Cash on delivery" end
    if sender == "" or sender:find("postmaster", 1, true) or sender:find("customer support", 1, true) then
        return "System", "System mail"
    end
    return "Player", "Direct player mail"
end

function E.MailCategoryPrefix(mail, titleUsesSubject)
    if not mail or not mail.category then return "" end
    if titleUsesSubject then
        local subject = string.lower(tostring(mail.subject or ""))
        local words = {
            Expired = {"expired"}, Sold = {"successful", "sold"}, Won = {"won"}, Outbid = {"outbid"},
            Cancelled = {"cancelled", "canceled"}, Pending = {"pending"}, Auction = {"auction"}
        }
        for _, word in ipairs(words[mail.category] or {}) do
            if subject:find(word, 1, true) then return "" end
        end
    end
    return "(" .. mail.category .. ") "
end

function E:ReadMail(index)
    local icon, stationery, sender, subject, money, cod, days, hasItem, read, returned, copied, reply, gm = GetInboxHeaderInfo(index)
    if subject == nil then return nil end
    local name, texture, count, quality = GetInboxItem(index)
    local mail = { index = index, icon = texture or icon or stationery, texture = texture or "", sender = sender or "",
        subject = subject, money = money or 0, cod = cod or 0, days = days or 0,
        hasItem = not not hasItem, read = not not read, returned = not not returned,
        copied = not not copied, reply = not not reply, gm = not not gm,
        itemName = name or "", count = count or 0, quality = quality or 1 }
    mail.category, mail.categoryDetail = E.MailCategory(mail.sender, mail.subject, mail.cod, mail.returned, mail.gm)
    -- Sender and stationery may also be nil/empty until their caches resolve.
    -- Stable transition identity therefore uses only header fields documented
    -- as intrinsic to the message, not cache-dependent presentation fields.
    mail.base = encode(subject) .. encode(returned) .. encode(reply) .. encode(gm)
    -- GetInboxItem may temporarily return nil while the item cache loads, then
    -- fire an inbox update when name/count become available. Those display-only
    -- fields must not make an otherwise unchanged mail row look replaced.
    mail.key = E.MailKey(mail.base, mail.money, mail.cod, mail.hasItem, mail.copied)
    return mail
end

function E:Snapshot()
    local list = {}
    for i = 1, GetInboxNumItems() do
        local mail = self:ReadMail(i)
        if not mail then return nil end
        list[i] = mail
    end
    return list
end

function E.SameInbox(a, b)
    if not a or not b or #a ~= #b then return false end
    for i = 1, #a do if a[i].key ~= b[i].key then return false end end
    return true
end

function E.MailKey(base, money, cod, hasItem, copied)
    return base .. encode(money) .. encode(cod) .. encode(hasItem) .. encode(copied)
end

-- Presentation fields are unsuitable for general inbox identity because their
-- caches may resolve late. They are useful as a narrower action fingerprint
-- when retrying one explicitly rejected Open All request.
function E.CollectActionKey(mail)
    return mail.key .. encode(mail.itemName) .. encode(mail.count) .. encode(mail.texture)
end

local function keyCounts(list)
    local counts = {}
    for _, mail in ipairs(list or {}) do counts[mail.key] = (counts[mail.key] or 0) + 1 end
    return counts
end

-- Unreal Azeroth rebuilds/reorders its cached inbox after removing a message.
-- Compare the exact multiset of stable row states rather than their positions.
function E.SameInboxSet(a, b)
    if not a or not b or #a ~= #b then return false end
    local counts = keyCounts(a)
    for _, mail in ipairs(b) do
        local n = counts[mail.key]
        if not n or n == 0 then return false end
        counts[mail.key] = n - 1
    end
    for _, n in pairs(counts) do if n ~= 0 then return false end end
    return true
end

-- Require the new inbox to equal the old multiset with exactly one verified
-- target state removed, optionally replaced by its calculated post-action state.
function E.ExactInboxKeyChange(old, new, removeKey, addKey)
    if not old or not new or not removeKey or #new ~= #old + (addKey and 0 or -1) then return false end
    local counts = keyCounts(old)
    if not counts[removeKey] or counts[removeKey] == 0 then return false end
    counts[removeKey] = counts[removeKey] - 1
    if addKey then counts[addKey] = (counts[addKey] or 0) + 1 end
    for _, mail in ipairs(new) do
        local n = counts[mail.key]
        if not n or n == 0 then return false end
        counts[mail.key] = n - 1
    end
    for _, n in pairs(counts) do if n ~= 0 then return false end end
    return true
end

function E:TraceInboxMismatch(job, list, stage)
    local first = 0
    local limit = math.max(#job.expected, #list)
    for i = 1, limit do
        if not job.expected[i] or not list[i] or job.expected[i].key ~= list[i].key then first = i; break end
    end
    self:TraceMail("INBOX_MISMATCH", stage,
        string.format("expected=%d current=%d first=%d empty=%d", #job.expected, #list, first, job.emptyRow and job.emptyRow.index or 0))
end

function E:RefreshInbox()
    local list = self:Snapshot()
    if not list then return end
    if not self.SameInbox(self.inbox, list) and not self.job then
        self.selected, self.readerIndex = {}, nil
    end
    self.inbox = list
end

function E:StartCollect(all, cleanup)
    if not self:CanAct() then return end
    local list = self:Snapshot()
    if not self.SameInbox(list, self.inbox) then
        self:RefreshInbox(); self:SetStatus("Inbox changed. Review the list and select again.", true); return
    end
    local targets, skipped, empty = {}, 0, 0
    for i = #list, 1, -1 do
        if all or self.selected[i] then
            if list[i].cod > 0 then skipped = skipped + 1
            elseif list[i].hasItem or list[i].money > 0 or cleanup then
                table.insert(targets, { key = list[i].key, itemName = list[i].itemName, count = list[i].count, sender = list[i].sender })
            elseif InboxItemCanDelete(i) then empty = empty + 1
            end
        end
    end
    if #targets == 0 then
        if empty > 0 then
            self:SetStatus("No contents remain." .. self.EmptyLetterNotice(empty))
        else
            self:SetStatus("Nothing to collect. COD mail is always skipped.")
        end
        return
    end
    local function start()
        local current = self:Snapshot()
        if not self.open or self.job or not self.SameInboxSet(list, current) then
            self:SetStatus("Inbox changed. Collection cancelled.", true); return
        end
        self.selected, self.readerIndex = {}, nil
        self.job = { kind = "collect", expected = current, targets = targets, pos = 1, total = #targets, all = all,
            cleanup = cleanup, skipped = skipped, items = 0, money = 0,
            pause = all and self.collectPause or self.interval, failureRetries = {},
            nextAt = GetTime() + (all and self.collectInterval or self.interval) }
        self:SetStatus("Collecting mail; COD skipped. Stop is always available.")
    end
    if cleanup then self:Confirm("Collect and delete?", "Delete emptied messages, including their letter text?\nCOD mail is skipped. Deleted letters cannot be restored.", start)
    else start() end
end

function E:ReadLetter(index)
    if self:Busy() or not self.open then return end
    local list = self:Snapshot()
    if not self.SameInbox(list, self.inbox) then self:RefreshInbox(); return end
    self.readerIndex, self.readerKey = index, list[index] and list[index].key
    if not self.readerKey then return end
    local body, stationery, canCopy, isInvoice = GetInboxText(index)
    self.readerBody, self.canCopy, self.isInvoice = body, canCopy, isInvoice
    self.readerBody = self.readerBody or "(No text, or text is still loading.)"
    self.readerNeedsRefresh = true
    self.bodyPage = 1
    self.dirty = true
end

function E:SingleAction(action)
    if not self:CanAct() then return end
    local index, list = self.readerIndex, self:Snapshot()
    local mail = index and list and list[index]
    if not mail or mail.key ~= self.readerKey then self:SetStatus("That message changed. Open it again.", true); return end
    local title, message
    if action == "item" then
        if not mail.hasItem then return end
        if mail.cod > GetMoney() then self:SetStatus("Not enough money for this COD.", true); return end
        if mail.cod > 0 then title, message = "Pay COD?", "Pay " .. self.Money(mail.cod) .. " to " .. self.Display(mail.sender) .. " for " .. self.Display(mail.itemName) .. "?" end
    elseif action == "money" then if mail.money <= 0 then return end
    elseif action == "delete" then
        if mail.hasItem or mail.money > 0 or mail.cod > 0 or not InboxItemCanDelete(index) then self:SetStatus("Only empty messages can be deleted here.", true); return end
        title, message = "Delete letter?", "Permanently delete '" .. self.Display(mail.subject) .. "' and its text?"
    elseif action == "return" then
        if not mail.reply or mail.returned or mail.gm or (not mail.hasItem and mail.money == 0) then self:SetStatus("This message cannot safely be returned.", true); return end
        title, message = "Return mail?", "Return this message and its contents to " .. self.Display(mail.sender) .. "?"
    elseif action == "copy" then if not self.canCopy or mail.copied then return end
    else return end
    local function start()
        if not self.open or self.job or not self.SameInbox(list, self:Snapshot()) then self:SetStatus("Inbox changed. Action cancelled.", true); return end
        self.job = { kind = "single", expected = list, targets = { { key = mail.key } }, pos = 1, total = 1,
            action = action, items = 0, money = 0, skipped = 0, nextAt = GetTime() + self.interval }
        self:SetStatus("Waiting for mailbox action...")
    end
    if title then self:Confirm(title, message, start) else start() end
end

local functions = { item = "TakeInboxItem", money = "TakeInboxMoney", delete = "DeleteInboxItem", ["return"] = "ReturnInboxItem", copy = "TakeInboxTextItem" }

-- The API has no mail IDs and this client reorders rows after a deletion.
-- Accept only an exact multiset transition for the dispatched target state.
function E:InboxTransition(job, nowList)
    local p, old = job.pending, job.expected
    local before = p.before
    if self.SameInboxSet(old, nowList) then return "waiting" end
    if (p.action == "delete" or p.action == "return" or
        (p.action == "item" and before.money == 0) or
        (p.action == "money" and not before.hasItem)) and
        self.ExactInboxKeyChange(old, nowList, before.key, nil) then return "done", true end
    local afterKey
    if p.action == "item" then
        afterKey = self.MailKey(before.base, before.money, 0, false, before.copied)
    elseif p.action == "money" then
        afterKey = self.MailKey(before.base, 0, before.cod, before.hasItem, before.copied)
    elseif p.action == "copy" then
        afterKey = self.MailKey(before.base, before.money, before.cod, before.hasItem, true)
    end
    if afterKey and self.ExactInboxKeyChange(old, nowList, before.key, afterKey) then return "done", false, afterKey end
    return "changed"
end

function E:FindInboxTarget(list, target, allowAmbiguous)
    local matches = {}
    for i = #list, 1, -1 do if list[i].key == target.key then table.insert(matches, i) end end
    if #matches == 1 or (#matches > 0 and allowAmbiguous) then
        local index = matches[1]
        return index, list[index]
    end
    if #matches > 1 and target.itemName and target.itemName ~= "" then
        local found
        for _, index in ipairs(matches) do
            local mail = list[index]
            if mail.itemName == target.itemName and mail.count == target.count then
                if found then return nil end
                found = index
            end
        end
        if found then return found, list[found] end
    end
end

function E.InboxAggregates(list)
    local stacks, money = 0, 0
    for _, mail in ipairs(list or {}) do
        if mail.hasItem then stacks = stacks + 1 end
        money = money + (mail.money or 0)
    end
    return #list, stacks, money
end

function E:CountDeletableEmptyLetters(list)
    local empty = 0
    for i, mail in ipairs(list or {}) do
        if mail.cod == 0 and not mail.hasItem and mail.money == 0 and InboxItemCanDelete(i) then
            empty = empty + 1
        end
    end
    return empty
end

function E.EmptyLetterNotice(count)
    count = tonumber(count) or 0
    if count < 1 then return "" end
    return string.format(" %d empty letter%s remain%s (use Delete empty).",
        count, count == 1 and "" or "s", count == 1 and "s" or "")
end

function E:FindCollectAllAction(job, list)
    local retry = job.retryTarget
    if retry then
        job.retryTarget = nil
        for i = #list, 1, -1 do
            local mail = list[i]
            if mail.cod == 0 and self.CollectActionKey(mail) == retry.actionKey then
                local available = (retry.action == "item" and mail.hasItem) or
                    (retry.action == "money" and mail.money > 0) or
                    (retry.action == "delete" and job.cleanup and InboxItemCanDelete(i))
                if available then return i, mail, retry.action end
            end
        end
    end
    for i = #list, 1, -1 do
        local mail = list[i]
        if mail.cod == 0 and not (job.skipKeys and job.skipKeys[mail.key]) then
            if mail.hasItem then return i, mail, "item" end
            if mail.money > 0 then return i, mail, "money" end
            if job.cleanup and InboxItemCanDelete(i) then return i, mail, "delete" end
        end
    end
end

-- Open All is deliberately permissive. The client rebuilds its inbox in ways
-- that invalidate row identities, so this path never compares whole snapshots.
-- It confirms only the relevant aggregate moved, then rescans the current inbox
-- for another non-COD action. An explicitly rejected, unchanged action may be
-- retried once after a long cooldown; timeouts and ambiguous outcomes never are.
function E:TickCollectAll(now)
    local job = self.job
    local list = self:Snapshot()
    if not list then return self:Stop("Inbox data unavailable; stopped safely.") end
    local count, stacks, money = self.InboxAggregates(list)
    if job.pending then
        local p = job.pending
        local inboxDone = (p.action == "item" and stacks < p.stacks) or
            (p.action == "money" and money < p.money) or
            (p.action == "delete" and count < p.count)
        local bagDone = p.action == "item" and p.bagCount and p.before.count > 0 and
            (self:CountBagItem(p.before.itemName, p.before.texture) or p.bagCount) >= p.bagCount + p.before.count
        if inboxDone or bagDone then
            if p.action == "item" then job.items = job.items + 1 end
            if p.action == "money" then job.money = job.money + p.before.money end
            if count < p.count then job.completed = (job.completed or 0) + 1 end
            if bagDone and not inboxDone then
                -- The client can move an item into the bags while its inbox
                -- cache still reports the old attachment. Never request that
                -- observed row state again; continue with other live rows.
                job.skipKeys = job.skipKeys or {}
                job.skipKeys[p.before.key] = true
                job.cacheConfirmed = (job.cacheConfirmed or 0) + 1
            end
            job.pending, job.expected = nil, list
            local mayRemove = (p.action == "item" and p.before.money == 0) or
                (p.action == "money" and not p.before.hasItem) or p.action == "delete"
            if inboxDone and mayRemove and count >= p.count then
                job.settleCount, job.settleUntil = p.count, now + self.collectSettle
            else
                job.settleCount, job.settleUntil = nil, nil
            end
            job.nextAt = now + (job.pause or self.collectPause)
            self.inbox = list
            self:SetStatus(string.format("Open All: %d stack(s), %s collected.%s", job.items, self.Money(job.money),
                bagDone and not inboxDone and " Item reached the bags; bypassing the stale inbox row." or " Rescanning current inbox."))
            return
        end
        local limit = p.failureAt and self.collectFailureGrace or self.timeout
        local since = p.failureAt or p.at
        if now - since > limit then
            local actionKey = p.actionKey or self.CollectActionKey(p.before)
            local retries = job.failureRetries and (job.failureRetries[actionKey] or 0) or 0
            if p.failureAt and retries < self.collectRetryLimit then
                job.failureRetries[actionKey] = retries + 1
                job.retryTarget = { actionKey = actionKey, action = p.action }
                job.pending, job.expected = nil, list
                job.nextAt = now + (job.pause or self.collectBackoff)
                self:SetStatus("The client explicitly rejected one Open All request. Retrying that unchanged mail once after the cooldown.", true)
                return
            end
            job.skipKeys = job.skipKeys or {}
            job.skipKeys[p.before.key] = true
            job.failedSkipped = (job.failedSkipped or 0) + 1
            job.pending, job.expected = nil, list
            job.nextAt = now + (job.pause or self.collectPause)
            self:SetStatus(p.failureAt and
                "The client rejected the same Open All request twice. It was skipped; continuing with other mail." or
                "One Open All request made no observable progress and was skipped without retrying. Continuing with other mail.", true)
            return
        end
        if p.failureAt then
            self:SetStatus(string.format("Client reported MAIL_FAILED; waiting up to %d more second(s) for the bag or inbox update...",
                math.max(0, math.ceil(self.collectFailureGrace - (now - p.failureAt)))))
        end
        job.nextAt = now + self.collectInterval
        return
    end
    if job.settleUntil then
        if count < (job.settleCount or count) or now >= job.settleUntil then
            job.settleCount, job.settleUntil = nil, nil
        else
            job.nextAt = now + self.collectInterval
            return
        end
    end
    local index, mail, action = self:FindCollectAllAction(job, list)
    if not index then
        self.job, self.readerIndex, self.selected = nil, nil, {}
        self.inbox = list
        local empty = not job.cleanup and self:CountDeletableEmptyLetters(list) or 0
        self:SetStatus(string.format("Done: %d stack(s), %s. %d COD, %d unique/failed messages skipped.%s",
            job.items, self.Money(job.money), job.skipped, (job.uniqueSkipped or 0) + (job.failedSkipped or 0),
            ((job.cacheConfirmed or 0) > 0 and (" " .. job.cacheConfirmed .. " item(s) verified in bags despite stale inbox cache.") or "") ..
            self.EmptyLetterNotice(empty)))
        return
    end
    job.expected = list
    job.pending = { index = index, action = action, at = now, before = mail,
        actionKey = self.CollectActionKey(mail),
        count = count, stacks = stacks, money = money,
        bagCount = action == "item" and self:CountBagItem(mail.itemName, mail.texture) or nil }
    _G[functions[action]](index)
end

function E:TickInbox(now)
    local job = self.job
    if job.kind == "collect" and job.all then return self:TickCollectAll(now) end
    local list = self:Snapshot()
    if not list then return self:Stop("Inbox data unavailable; stopped safely.") end
    if job.pending then
        local state, removed, afterKey = self:InboxTransition(job, list)
        if state == "changed" then
            self:TraceInboxMismatch(job, list, "pending")
            return self:Stop("Inbox changed unexpectedly. Stopped; review the mailbox.")
        end
        if state == "waiting" then
            local p = job.pending
            local limit = p.failureAt and self.collectFailureGrace or self.timeout
            local since = p.failureAt or p.at
            if now - since > limit then
                if job.pending.failureReported then
                    local retryKey = p.before.key .. ":" .. p.action
                    local retries = job.failureRetries[retryKey] or 0
                    if retries < self.collectRetryLimit then
                        job.failureRetries[retryKey] = retries + 1
                        job.pending = nil
                        job.nextAt = now + (job.pause or self.collectBackoff)
                        self:SetStatus("The client explicitly rejected the selected-mail request. Retrying that unchanged message once after the cooldown.", true)
                        return
                    end
                    job.pending = nil
                    return self:Stop("The client rejected the same selected-mail request twice. Collection stopped; review that message and continue when ready.")
                end
                return self:Stop("No mailbox confirmation. Stopped without retrying.")
            end
            job.nextAt = now + self.interval
            return
        end
        local p = job.pending
        if p.action == "money" then job.money = job.money + p.before.money end
        if p.action == "item" then job.items = job.items + 1 end
        job.expected, job.pending = list, nil
        local target = job.targets[job.pos]
        if target and afterKey then target.key = afterKey end
        if removed or job.kind == "single" then
            job.pos = job.pos + 1
        elseif job.kind == "collect" and (p.action == "item" or p.action == "money") then
            if afterKey and p.before and
                ((p.action == "item" and p.before.money == 0) or
                (p.action == "money" and not p.before.hasItem)) then
                -- Do not issue the next request yet. The client may publish the
                -- successful take first and auto-remove this empty row shortly
                -- afterward. Remember exactly which verified row may disappear.
                job.emptyRow = { index = p.index, key = afterKey, at = now, advanced = false }
            end
        end
        job.nextAt = now + (job.pause or self.interval)
        self.inbox = list
        self:SetStatus(string.format("Collected %d stack(s), %s. %d/%d messages.", job.items, self.Money(job.money), job.pos - 1, job.total))
        return
    end
    if not self.SameInboxSet(job.expected, list) then
        local empty = job.emptyRow
        if empty and self.ExactInboxKeyChange(job.expected, list, empty.key, nil) then
            job.expected, job.emptyRow = list, nil
            if not empty.advanced then job.pos = job.pos + 1 end
            job.nextAt = now + (job.pause or self.interval)
            self.inbox = list
            return
        end
        self:TraceInboxMismatch(job, list, "before next")
        return self:Stop("Inbox changed before the next action. Stopped safely. /emberpost debug shows the mismatch shape.")
    end
    -- Pure row reordering is not a content change. Keep the current ordering so
    -- the next queued stable identity can be resolved to its new API index.
    job.expected = list
    if job.emptyRow then
        local empty = job.emptyRow
        if now - empty.at < self.inboxRemovePause then
            job.nextAt = now + (job.pause or self.interval)
            return
        end
        if job.cleanup then
            -- The server retained the empty letter, so explicit cleanup may now
            -- delete it through the normal guarded request path.
            job.emptyRow = nil
        elseif not empty.advanced then
            -- Retained player letters are valid. Mark this message complete, but
            -- leave one final polling interval in which a late exact removal can
            -- still be reconciled before the next request is dispatched.
            empty.advanced = true
            job.pos = job.pos + 1
            job.nextAt = now + (job.pause or self.interval)
            return
        else
            job.emptyRow = nil
        end
    end
    local target = job.targets[job.pos]
    if not target then
        self.job, self.readerIndex, self.selected = nil, nil, {}
        if job.kind == "single" then self:SetStatus("Mailbox action confirmed.")
        else
            local empty = not job.cleanup and self:CountDeletableEmptyLetters(list) or 0
            self:SetStatus(string.format("Done: %d stack(s), %s. %d COD, %d unique-limit messages skipped.%s",
                job.items, self.Money(job.money), job.skipped, job.uniqueSkipped or 0, self.EmptyLetterNotice(empty)))
        end
        return
    end
    local index, mail = self:FindInboxTarget(list, target, job.all)
    if not index or not mail then return self:Stop("A queued message changed or disappeared before its action. Stopped safely.") end
    local action = job.action
    if job.kind == "collect" then
        if mail.cod > 0 then return self:Stop("Message became COD. Collection stopped.") end
        if mail.hasItem then action = "item"
        elseif mail.money > 0 then action = "money"
        elseif job.cleanup and InboxItemCanDelete(index) then action = "delete"
        else job.pos = job.pos + 1; job.nextAt = now + (job.pause or self.interval); return end
    end
    job.pending = { index = index, action = action, at = now, before = mail }
    _G[functions[action]](index)
end
