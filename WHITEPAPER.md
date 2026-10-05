# Mailbag Technical Whitepaper

**v2.1.0** | October 2026

An inbox fills up the same way every day: real mail mixed in with junk that
outnumbers it ten to one, and most triage tools want a login of their own
and a place to sit between you and your mail forever. Mailbag connects to
Gmail directly — web, iOS, macOS — reads the inbox, scores each message, and
clears the whole inbox in one tap, because triage is a one-tap decision
repeated a hundred times a day, not a product you should have to configure.

## What it does

Mailbag reads an inbox over the Gmail API, Microsoft Graph or iCloud IMAP and puts every message in one of seven boxes: Receipts, Travel, Dev, Newsletters, Social, Promotions or Junk. A message from a person with no bulk signals has no box and stays in the inbox. The categorizer is a short list of sender, subject and Gmail category rules, shared by all three providers, and the same junk scorer runs first.

Before any rule runs, one question decides who may be filed at all: does this mail show a sign of a machine? An unsubscribe header, a Gmail bulk label, a no-reply style address, a sender domain the rules know. Mail with none of these is treated as written by a person. It is never filed and never leaves for the model. Mail about debts, collections or legal notices is never filed either, whoever sends it. Junk is reserved for scam signs, a sender name that does not match its domain or urgency with a generic greeting. A sender that offers an unsubscribe link and impersonates nobody is a promotion, not junk.

The rules cannot place every machine. So machine mail that is still unplaced goes, in one batched call, to a small language model on Cloudflare Workers AI. It sees the sender, the subject and a short preview, and it may move a message into a box. It can never pull one out. If the model fails or answers badly, the rules result stands. All of this is a guess. That is why nothing is ever deleted.

Clear inbox is the whole product in one button. It files every message that has a box, then archives the rest. People are never filed, only archived. The inbox is empty when it returns. File everything is the same without the archive step.

Filing is one call per box. Gmail: create the `Mailbag/<Box>` label if it is missing, then `batchModify` to add it and remove INBOX. iCloud: `CREATE` the folder, then `UID MOVE`. Nothing is trashed. Delete and Archive stay as separate, explicit actions.

## Unsubscribing

Most bulk senders already support RFC 8058 one-click unsubscribe —
`List-Unsubscribe-Post: List-Unsubscribe=One-Click` alongside a
`List-Unsubscribe` URL. Mailbag POSTs to it directly; a 2xx/204 confirms it,
no browser required, because opening a browser to click one more button
defeats the point of automating the tedious part. The message is archived
either way once you act on it — archive, delete, or unsubscribe are each one
tap, nothing happens on its own.

## Cross-platform auth

Google blocks OAuth consent screens from loading inside an embedded WebView,
so a plain wrapper around the web login is a dead end on native, not a
shortcut. The web app runs a normal confidential-client OAuth flow. The
iOS and macOS apps are native SwiftUI. They open the system browser via
`ASWebAuthenticationSession` against a second, public PKCE OAuth client,
exchange the code directly with Google, and hand the resulting tokens to the
same backend. One API, two login paths. The Mac app is one number and one
button: how much mail is in the inbox, and Clear inbox.

## Where the old skill fits

The original Claude Code skill (`/mail`) still exists for the half of the
job that needs a coding agent, not a mail client: matching an App Store
Connect or GitHub Actions alert to the right project, pulling the real
failure log, and fixing or filing it. That half needs a coding agent making
judgment calls, not a scoring rule, so it stays a skill instead of folding
into the app. Mailbag and `/mail` share the same spam-scoring rules but run
independently.

## Design

- **Nothing moves until you tap it.** Reading and scoring never mutates
  anything; clear/file/archive/delete/unsubscribe are each an explicit action, because
  an inbox is the one place a wrong automated guess (a real email archived
  by mistake) causes real harm.
- **No background automation.** No cron, no polling — every read is
  triggered by opening the app, so nothing touches your mail while you're
  not looking.

## License

MIT 2026, Joshua Trommel
