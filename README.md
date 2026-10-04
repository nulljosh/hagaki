<img src="icon.svg" width="80" style="border-radius:18px">

# Hagaki

![version](https://img.shields.io/badge/version-v1.0.0-blue) ![license](https://img.shields.io/badge/license-MIT-green) [![GitHub](https://img.shields.io/badge/GitHub-nulljosh%2Fhagaki-black?logo=github)](https://github.com/nulljosh/hagaki)

An inbox fills up whether you look at it or not. Dev-tool alerts that actually need a fix. Newsletters you never asked twice for. Notification spam wearing a real sender's name. Sorting it by hand is the same ten minutes every day, spent the same way.

That's the gap.

<img src="progress.svg" width="460">

## What it does

Connect Gmail or iCloud and Hagaki reads your inbox. It files everything into seven boxes: Receipts, Travel, Dev, Newsletters, Social, Promotions and Junk. In Gmail they are labels under a label called Hagaki. In iCloud they are folders. Mail from a real person stays in your inbox.

Nothing is deleted. Filing moves mail out of the inbox and into its box, junk included. Delete is its own button, and in Gmail it goes to Trash. Unsubscribe sends the sender's own one-click request. The list is a preview, and nothing moves until you press File everything.

The Claude Code side (`/mail`) still exists for the dev-tool-alert half of the job — matching an App Store Connect or GitHub Actions email to the right project and fixing or filing it — since that needs a coding agent, not a mail client. The two share the same spam-scoring rules.

## Why this and not a filter rule

A filter rule is static — it catches what you already know to catch. This reads the actual message, decides what kind of thing it is, and takes the next real step: unsubscribe and move on, or (via `/mail`) file a bug or fix a build. The difference between a spam folder and someone who actually reads your mail.

## The name

Hagaki (はがき, 葉書) is Japanese for postcard. 葉 is leaf, 書 is write. One theory says the word comes from the tarayō tree, whose leaves take writing when you scratch them with a stick.

Every Japanese postcard has seven red boxes for the postal code, so machines can sort the mail. Hagaki sorts your inbox the same way. Seven boxes, every letter in one.

## Run it

Open [hagaki.heyitsmejosh.com](https://hagaki.heyitsmejosh.com) (or the iOS/macOS app), connect Gmail, triage. For the dev-tool-alert side, from a Claude Code session:

```
/mail                 dry run — read, classify, report, touch nothing
/mail apply            real pass — file, fix, archive/delete, unsubscribe
```

Full triage logic, spam scoring, and unsubscribe handling: [SKILL.md](SKILL.md).

## Screenshots

<img src="screenshots/iphone/01-inbox.png" width="200"> <img src="screenshots/ipad/01-inbox.png" width="280"> <img src="screenshots/mac/01-inbox.png" width="360">

## Architecture

<img src="architecture.svg" width="600">
