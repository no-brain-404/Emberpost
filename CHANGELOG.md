# Changelog

All notable public changes to EmberPost are documented here.

## [1.0.17] - 2026-09-09

### Fixed

- Stopped registering the EmberPost window in `UISpecialFrames`, which could make Unreal Azeroth consume Escape after a mailbox visit and prevent the game menu from opening.
- Added cleanup for stale and duplicate `EmberPostFrame` registrations left by an older addon version in the current UI session.
- Kept keyboard focus cleanup for every hidden mailbox input. EmberPost now closes through its red **X**, leaving Escape to the game.

### Compatibility

- Confirmed that EmberPost already accepts the four-argument `OnCursorChanged(CursorX, CursorY, CursorW, CursorH)` callback added in client patch 2333; no cursor code change was required.
- Updated the money warning for patch 2333. EmberPost still checks the exact outgoing coin and COD values immediately before every send, so an older or faulty client cannot silently attach the wrong amount.
- Reviewed all 13 newly announced Lua globals. EmberPost does not depend on them, so no new API calls were added.

## [1.0.16] - 2026-08-31

### Security

- Blocked COD whenever more than one item stack is queued. Unreal Azeroth sends each stack as a separate letter, so charging only the first letter could allow the remaining items to be collected for free.
- Prevented enabling COD with an existing multi-stack queue and prevented adding a second stack while COD is active.
- Kept a final validation check before the confirmation dialog so the restriction cannot be bypassed through UI ordering.

### Fixed

- `/emberpost help` now prints a few short lines in chat instead of placing the full command list in the mailbox status line.
- Scale/reset confirmations and invalid scale guidance now print only in chat and no longer replace the current mailbox status.
- Updated the Send tab note and confirmation text to describe the single-stack COD rule clearly.

## [1.0.15] - 2026-08-31

### Added

- Compact inbox, mail reader, and multipart send interface
- Search, pagination, mail classification, attachment previews, and recent recipients
- Bulk collection of non-COD attachments and coins
- Optional cleanup of empty letters
- Selected-message collection across multiple inbox pages
- Queueing and sending of up to 21 item stacks as separate letters
- Automatic subjects and numbered multipart subjects
- Native mailbox fallback and session-only mail diagnostics

### Reliability

- Stable mail identity checks for selected collection
- Live inbox rescanning for Open All
- Bounded handling of contradictory client `MAIL_FAILED` notifications
- Bag, mailbox, postage, and outgoing-attachment verification
- No blind retry of outgoing mail or unknown transaction results

[1.0.15]: https://github.com/no-brain-404/Emberpost/releases/tag/v1.0.15
[1.0.16]: https://github.com/no-brain-404/Emberpost/releases/tag/v1.0.16
[1.0.17]: https://github.com/no-brain-404/Emberpost/releases/tag/v1.0.17
