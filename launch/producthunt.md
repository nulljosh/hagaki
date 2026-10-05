# Product Hunt - Mailbag

## Name
Mailbag

## Tagline (<=60)
Read your inbox, score the junk, clear it in one tap

## Description (<=260)
Mailbag connects to Gmail or iCloud, scores every message in your inbox for junk signals, and clears it with one tap: real one-click unsubscribe where the sender supports it, archive or delete otherwise. Nothing moves until you tap it. Free today.

## Topics (3)
- Productivity
- Email
- Gmail

## First comment (maker story)
An inbox fills up the same way every day: real mail mixed in with junk that outnumbers it ten to one. Most triage tools want a login of their own and a place to sit between you and your mail forever. I wanted something that just reads the inbox I already have and does the boring part.

Mailbag signs in with Google (or an iCloud app-specific password) and reads your actual inbox over the Gmail API or IMAP. Every message gets scored before anything is touched: sender and display-name mismatch, urgency language, an unsubscribe header from someone you don't recognize, a reply-to domain that doesn't match the sender. Two or more signals confirms junk, because a single signal is too easy for a real sender to trip by accident. Most bulk senders already support RFC 8058 one-click unsubscribe, so Mailbag POSTs to it directly instead of opening a browser. Archive, delete, or unsubscribe are each one tap, nothing happens on its own.

It runs on web, iOS, and macOS, same backend, same scoring rules. There's also a Claude Code skill (`/mail`) that shares the scoring logic for the half of the job that needs a coding agent: matching a dev-tool alert to the right project and fixing it.

Mailbag is free right now, full stop. No paid tier exists yet. If that changes later, anyone using it while it's free keeps it free.

## Pricing
Free. No paid tier exists today.

## Links
- Web app: https://mailbag.heyitsmejosh.com
