# Architecture

Pare helps people clean out a messy inbox fast. It connects to Gmail, Outlook, or iCloud Mail, scores each message for how likely it is junk (mismatched sender domain, spammy bulk patterns, fake urgency, unsubscribe headers), and lets the user clear junk, unsubscribe, or archive with one tap. It runs as a web app and native iOS/macOS apps, all signing in with the mail provider's own login. It only checks mail when the user opens it, never on a schedule in the background.

## How it runs

User signs in with Google/Microsoft/Apple OAuth (native uses system browser via `ASWebAuthenticationSession`). Worker exchanges tokens with the provider, verifies IMAP/API access, stores session in KV with provider tag. Web/native UIs call `/api/messages` (lists inbox with scores) and `/api/action` (archive/delete/unsubscribe). Worker dispatches to provider-specific logic: Gmail and Outlook use REST APIs; iCloud uses raw IMAP over cloudflare:sockets. Scoring rules (sender domain mismatch, generic bulk greeting, urgency language, unsubscribe headers) are shared. Unsubscribe uses RFC 8058 one-click (POST to List-Unsubscribe URL).

| File | What it owns |
|---|---|
| `worker.js` | Cloudflare Worker. OAuth endpoints (`/auth/start`, `/auth/callback`, `/auth/native`), message listing (`/api/messages`), actions (`/api/action`, `unsubscribe/archive/delete`). Dispatches on provider (Gmail/Outlook/iCloud) to matching logic. Shared scoring rules across all three. |
| `landing/index.html` | Inbox UI (Connect button, message list, action buttons), marketing copy, run-history panel. Loads from Worker with `?embed&native=1` for native wrappers. |
| `ios/App/PareApp.swift` | WKWebView wrapper. Intercepts `parenative://connect`, runs `ASWebAuthenticationSession` against Google's public PKCE client, exchanges tokens with `/auth/native`, passes session token back to the web UI. |
| `ios/project.yml` + `ios/Pare.xcodeproj` | xcodegen project definition. iOS + macOS targets (shared Swift code, different size constraints). |
| `SKILL.md` | Claude Code skill for dev-tool alerting (Vercel/GitHub Actions/App Store Connect emails → filed to project). Separate from the app (requires Claude, not user-facing). |
| `wrangler.toml` | Cloudflare Worker deployment, KV namespace for sessions, secrets for OAuth client IDs. |
