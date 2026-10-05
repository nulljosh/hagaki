# Hagaki

Real Gmail triage app (web + iOS/macOS) as of 2026-09-11, plus the original `/mail` Claude Code skill for dev-tool-alert filing. This is a deliberate exception to the "no server-side triage" note that used to live here — the app itself now does real, user-invoked (never scheduled) OAuth + Gmail API reads, spam scoring, and smart folders (seven boxes: Receipts, Travel, Dev, Newsletters, Social, Promotions, Junk, filed not deleted), unsubscribe/archive/delete. Still no cron, no background polling, per `~/CLAUDE.md`.

Renamed Sieve to Siftbox 2026-09-11, to Pare 2026-10-04, then to Hagaki the same day because Apple already had a "Pare". Hagaki is Japanese for postcard (leaf-letter, the tarayō leaf on the icon). One name everywhere: repo `nulljosh/hagaki`, folder, Xcode project/target/scheme (`Hagaki.xcodeproj`), Swift and entitlements filenames, display name, landing copy, ASC listing, and the domain `hagaki.heyitsmejosh.com`. `pare`, `siftbox` and `sieve` hosts still resolve (same Worker, extra routes). `GOOGLE_REDIRECT` and `MS_REDIRECT` in `worker.js` now use the hagaki host; the hagaki, pare, siftbox and sieve callbacks are all saved in GCP Web client 1, so keep every route. Bundle ID stays `com.nulljosh.sieve`, and the `sieve_session` cookie and `sieve_token` key keep their names so nobody gets signed out.

- `worker.js`: the whole backend, now three providers. Gmail: `/auth/start` + `/auth/callback` (web OAuth, confidential client + secret). Outlook: `/auth/start/outlook` + `/auth/callback/outlook` (Microsoft identity platform v2, Graph API `Mail.ReadWrite`) — needs an Azure app registration, blocked on Joshua, `MS_OAUTH_CLIENT_ID`/`MS_CLIENT_SECRET` not yet set. iCloud: `/auth/icloud` (POST email + app-specific password, no OAuth exists for Apple Mail) — verified by one IMAP login before the session is stored, then real inbox reads go over raw IMAP (`imap.mail.me.com:993`) via `cloudflare:sockets`, one connection per request. `/auth/native` (iOS/macOS hands over PKCE-obtained tokens for Gmail/Outlook, gets back an opaque session token) mints a session stored in the `SESSIONS` KV namespace, tagged with `provider`. `/api/messages` and `/api/action` dispatch on `session.provider` to the matching list/action functions; scoring rules are shared across all three. `/api/runs` is the older skill-run history log (GET public, POST bearer-gated via `RUN_TOKEN`), unrelated to the mail API.
- `landing/index.html`: washi-and-sumi Japanese theme built on the name (葉書, tarayō leaf, the seven red postcode boxes = the seven folders). The actual inbox UI (Connect Gmail → seven-box summary → File everything / per-row File, Archive, Unsubscribe, Delete), plus the marketing copy and run-history panel. Native loads it with `?embed&native=1`; the Connect link becomes `hagakinative://connect` under that flag so the native wrapper can intercept it (see below) instead of letting Google's OAuth page load inside a WKWebView, which Google blocks outright.
- `ios/App/HagakiApp.swift` (struct `HagakiApp`): WKWebView wrapper. Its navigation delegate intercepts `hagakinative://connect`, runs `ASWebAuthenticationSession` (system browser, not the WKWebView) against a **second, iOS-type OAuth client** (public, PKCE, no secret), exchanges the code directly with Google, POSTs the tokens to `/auth/native`, then reloads the WKWebView with `?token=` so the same JS that handles the web flow picks up the session.
- Google Cloud project `jaybulb-signin` is shared across apps for OAuth — don't spin up a new GCP project per app. "Web client 1" (confidential, used by Hagaki's web flow and Supabase social sign-in — redirect URIs pile up on one client, not one client per app) and "Sieve iOS/macOS" (public, PKCE) are both on it. Gmail API + `gmail.modify` scope enabled on that project. App is unverified (testing/100-user cap) — real use is fine, just shows Google's "unverified app" click-through; formal verification is a follow-up, not required to work.
- Secrets: `GOOGLE_OAUTH_CLIENT_ID`/`GOOGLE_CLIENT_SECRET` as Worker secrets (`npx wrangler secret put`), also mirrored in `secrets.fish` as `GOOGLE_OAUTH_CLIENT_ID`/`SIEVE_GOOGLE_CLIENT_SECRET`.
- `SKILL.md` is still the dev-tool-alert half of the product (App Store Connect/Vercel/Sentry/GitHub Actions emails → matched to project → fixed or filed) — that needs a coding agent, so it stays a Claude Code skill, not something the app can do itself. Symlinked into the actual skill path via `dotfiles/claude/claude-skills/mail` → this repo.
- ASC app id `6811141466`, bundle `com.nulljosh.sieve`. Store listing name is **Hagaki**.
- The README is the house writing reference. Do not loosen it.

## Follow-ups
- Submit for Google OAuth verification to drop the "unverified app" warning and lift the 100-user cap (App Store review will likely expect this).
- Screenshots + submit for review once signing/build is confirmed working.
- Outlook needs an Azure app registration (client ID + secret, redirect URI `https://hagaki.heyitsmejosh.com/auth/callback/outlook`) — blocked on Joshua, the code path is done but dead until secrets are set.
- Native (iOS/macOS) wrapper only handles Gmail's PKCE flow today. Outlook needs a second `ASWebAuthenticationSession` client registered in Azure (public/PKCE); iCloud just needs the email+app-password form, no native OAuth work at all.

## Build (native)
```bash
cd ios && xcodegen generate
xcodebuild build -project Hagaki.xcodeproj -scheme Hagaki -destination 'platform=macOS'
xcodebuild build -project Hagaki.xcodeproj -scheme Hagaki -destination 'generic/platform=iOS Simulator'
```

## Deploy
```bash
npx wrangler deploy
```

## Real-mail test, 2026-10-04
Ran `scoreMessage` + `categorize` over Joshua's Mail.app inboxes (iCloud 21, Gmail "Ja" 9; sender + subject only, Mail.app's Envelope Index has no snippet or unsubscribe header).
- Rules missed Apple review/TestFlight/Twilio/GitGuardian/Apify mail, Stripe webhook alerts, "order has been received" and Gumroad letters. Fixed in `DEV`, `DEV_WORDS`, `RECEIPT`, `LETTER_SITES`, with asserts in `test.js`.
- Added `llmRefine`: one Workers AI call (`@cf/meta/llama-3.3-70b-instruct-fp8-fast`, `[ai]` binding) re-sorts whatever the rules leave in Inbox, fails open. Cold "saw your app" outreach goes to Junk there, since the spam score never fires on it.
- After the fixes: iCloud 15 of 21 filed, Ja 5 of 9; everything left is a person, school or a collections notice.
- Filed for real in Mail.app via AppleScript into `Hagaki/<Folder>`. Gotcha: `mailbox "Hagaki/Dev"` does not resolve, use `mailbox "Dev" of mailbox "Hagaki"`, and re-query each message (move invalidates the list).
