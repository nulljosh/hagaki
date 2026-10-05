<!-- Note: this sub is strict about no self-promo speak and wants genuinely novel/polished web tools, not "check out my app" posts. Verify current posting rules before submitting - ask Joshua, don't guess. Public web app, no App Store link (no approved build exists yet). -->

## Title
A web app that scores your inbox for junk and one-click unsubscribes the real way (RFC 8058)

## Body

Mailbag connects to Gmail or iCloud and reads your inbox, then scores each message for junk signals: sender/display-name mismatch, urgency language, an unrecognized unsubscribe header, a reply-to domain that doesn't match the sender. Two or more signals confirms junk.

The part I think is worth sharing here: most bulk senders already support RFC 8058 one-click unsubscribe (`List-Unsubscribe-Post: List-Unsubscribe=One-Click`), and almost nothing actually uses it. Mailbag POSTs to that URL directly, no browser tab, no landing page, just a confirmed unsubscribe. Archive/delete/unsubscribe are each an explicit tap, nothing runs automatically.

Free to use right now.

https://mailbag.heyitsmejosh.com
