# Changelog

All notable public changes to EmberPost are documented here.

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
