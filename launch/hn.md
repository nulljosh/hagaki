## Title (<=80 chars)
Show HN: Hagaki – connect Gmail or iCloud, score junk mail, clear it in a tap

## Body

Hagaki reads your actual inbox over the Gmail API or IMAP (iCloud, app-specific password) and scores each message before anything is touched: sender/display-name mismatch, urgency language, an unsubscribe header from a sender you don't recognize, a reply-to domain that doesn't match the sender. Two or more signals confirms junk, since one signal alone is too easy for a real sender to trip by accident.

Most bulk senders already support RFC 8058 one-click unsubscribe, so Hagaki POSTs to the `List-Unsubscribe` URL directly instead of opening a browser. Archive, delete, or unsubscribe are each an explicit tap. Nothing runs on a schedule, no background polling, every read happens because you opened the app.

It's a Cloudflare Worker backend with a web app, plus iOS and macOS wrappers that use `ASWebAuthenticationSession` for native Gmail OAuth since Google blocks its consent screen inside an embedded WebView.

Free today, no paid tier exists yet. Would love feedback on the scoring rules, especially false positives on real senders.

https://hagaki.heyitsmejosh.com
