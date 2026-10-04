<!-- Note: check subreddit rules before posting - self-promo day requirements and flair vary by mod team, ask Joshua, don't guess. Public web app post, no App Store link (no approved build exists on iOS or macOS right now). -->

## Title
I built a tool that reads your inbox and clears junk mail in one tap

## Body

My inbox fills up the same way every day: real mail mixed in with junk that outnumbers it ten to one. Filter rules only catch what you already know to catch, and most triage tools want a login of their own and a place to sit between you and your mail forever.

So I built Pare. Sign in with Google (or an iCloud app-specific password) and it reads your actual inbox over the Gmail API or IMAP. Every message gets scored before anything is touched: sender/display-name mismatch, urgency language, an unsubscribe header from someone you don't recognize, a reply-to domain that doesn't match the sender. Two or more signals confirms junk, one alone is too easy for a real sender to trip by accident.

Most bulk senders already support RFC 8058 one-click unsubscribe, so it POSTs to that directly instead of making you open a browser. Archive, delete, or unsubscribe are each one tap, nothing happens on its own. It's a Cloudflare Worker backend, web app plus iOS/macOS wrappers.

It's free right now, no paid tier exists. Would love feedback, especially on false positives where it flags a real sender.

https://pare.heyitsmejosh.com
