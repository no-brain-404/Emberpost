# EmberPost

EmberPost is a compact mailbox addon built specifically for **Emberveil's Unreal Azeroth client**. It replaces the default mailbox with a faster, cleaner interface for collecting and sending large amounts of mail.

It is a standalone addon and does not require Postal, TradeSkillMaster, Ace, or any other addon library.

## Features

- Compact, modern inbox and send-mail interface
- Searchable inbox with visible mail categories
- Open All for non-COD items and coins
- Optional deletion of empty letters
- Selection and collection across multiple inbox pages
- Up to 21 queued item stacks, sent as separate letters
- Automatic subjects based on the first attached item
- Attachment icons, stack counts, quality borders, and native tooltips
- Recent-recipient list and a fallback bag-item picker
- Access to the original mailbox through the **WoW UI** button
- Transaction checks designed to avoid duplicate sends and collections

## Installation

1. Download the latest ZIP from [Releases](https://github.com/no-brain-404/Emberpost/releases/latest).
2. Fully close the game client.
3. Extract the ZIP into the client's `Interface/AddOns` directory.
4. Confirm that the final path is `Interface/AddOns/EmberPost/EmberPost.toc`.
5. Start the client and open a mailbox.

Replace the entire `EmberPost` folder when upgrading. Do not merge a new release with files from an older version.

## Usage

**Open All Mail** collects every available non-COD attachment and coin payment. COD messages are always skipped. Empty letters are preserved unless **Delete empty** is enabled.

To collect specific messages, select them in the inbox and choose **Collect selected**.

On the Send tab, add item stacks by right-clicking or dragging them from your bags. EmberPost sends one stack per letter and numbers multipart subjects automatically.

## Commands

| Command | Description |
| --- | --- |
| `/emberpost` | Show EmberPost during a mailbox visit |
| `/emberpost help` | Show the available commands |
| `/emberpost debug` | Print recent mail events for troubleshooting |
| `/emberpost stop` | Stop the current queue |
| `/emberpost native` | Switch to the original mailbox for the current visit |
| `/emberpost reset` | Restore the default position and compact scale |
| `/emberpost scale 0.6` | Set the interface scale |

`/epost` is available as a shorter alias.

## Compatibility

EmberPost targets the WoW 1.12.1 / Lua 5.1 API exposed by Emberveil's Unreal Azeroth client. It is not intended for official Classic Era, Retail, or other private-server clients.

Test with inexpensive mail first after a client update. Mailbox behavior ultimately depends on the client and server.

## Releases and versioning

Published builds are available from the [GitHub Releases page](https://github.com/no-brain-404/Emberpost/releases). Releases use semantic version tags such as `v1.0.15`. Changes are recorded in [CHANGELOG.md](CHANGELOG.md).

## License

EmberPost is released under the [GNU General Public License v3.0](LICENSE).

This is a community project and is not an official Emberveil addon.
