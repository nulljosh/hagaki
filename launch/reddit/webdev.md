<!-- Note: frame as "built X to solve Y", not a launch announcement. Check self-promo/flair rules first - ask Joshua, don't guess. Public web app post, no App Store link. -->

## Title
Built a Gmail/IMAP inbox triage tool on a Cloudflare Worker, here's the OAuth-in-native-app problem I hit

## Body

I built Pare to deal with my own inbox: connects to Gmail over OAuth or iCloud over IMAP, scores each message for junk signals server-side, and unsubscribes/archives/deletes in one tap. Backend is a single Cloudflare Worker, KV for sessions and run history, no database.

The interesting problem was cross-platform auth. Google blocks its OAuth consent screen from loading inside an embedded WebView, so a plain wrapper around the web login is a dead end on iOS/macOS. The web app runs a normal confidential-client OAuth flow. The native wrapper instead intercepts the "Connect Gmail" action, opens `ASWebAuthenticationSession` (the system browser, not the WebView) against a second, public PKCE OAuth client, exchanges the code directly with Google, and hands the tokens to the same backend. One shared UI, one shared API, two login paths.

Also implemented RFC 8058 one-click unsubscribe server-side (POST to `List-Unsubscribe`, no browser needed) since most bulk senders already support it and almost nothing uses it.

Free to use, no backend framework, just Workers + KV + vanilla JS on the frontend.

https://pare.heyitsmejosh.com
