# Mailbag

Inbox triage app (web + iOS/macOS), plus the original `/mail` Claude Code skill for dev-tool-alert filing. One button, Clear inbox: machine mail goes into seven folders (Receipts, Travel, Dev, Newsletters, Social, Promotions, Junk), people go to the archive, nothing is deleted. Reads are user-invoked only. No cron, no background polling, per `~/CLAUDE.md`.

Names so far: Sieve, Siftbox (2026-09-11), Pare, Hagaki, Outtray (all 2026-10-04), now **Mailbag** (2026-10-04, Apple accepted it as a listing name). Joshua found Hagaki too Japanese and Outtray hard to say. What carries which name:
- Mailbag: display name, Xcode project/target/scheme (`Mailbag.xcodeproj`), landing, docs, icon, the `Mailbag/<Folder>` labels, `mailbag.heyitsmejosh.com`.
- Still Hagaki: the ASC listing (6811141466) and the 1.0 build in review. The listing was flipped back to Hagaki on purpose so it matches the build Apple is looking at. Rename the listing and submit a Mailbag build in the same move, never one without the other.
- `hagaki.heyitsmejosh.com` stays the API and OAuth host: `GOOGLE_REDIRECT`, `MS_REDIRECT` and the apps' `apiBase` point at it because that callback is the one saved in GCP Web client 1. `pare`, `siftbox` and `sieve` hosts still resolve too. Add `https://mailbag.heyitsmejosh.com/auth/callback` in GCP before moving any of that.
- Never renamed: bundle ID `com.nulljosh.sieve`, Worker name `sieve`, the `sieve_session` cookie and `sieve_token` key.
- Launch flags are name-free and take a value: `-demo YES`, `-clear YES`, `-signedOut YES`, `-dark YES`, `-macMail YES` (Debug). A bare `-demo` swallows the next argument and the app opens no window.

- `worker.js`: the whole backend, now three providers. Gmail: `/auth/start` + `/auth/callback` (web OAuth, confidential client + secret). Outlook: `/auth/start/outlook` + `/auth/callback/outlook` (Microsoft identity platform v2, Graph API `Mail.ReadWrite`) — needs an Azure app registration, blocked on Joshua, `MS_OAUTH_CLIENT_ID`/`MS_CLIENT_SECRET` not yet set. iCloud: `/auth/icloud` (POST email + app-specific password, no OAuth exists for Apple Mail) — verified by one IMAP login before the session is stored, then real inbox reads go over raw IMAP (`imap.mail.me.com:993`) via `cloudflare:sockets`, one connection per request. `/auth/native` (iOS/macOS hands over PKCE-obtained tokens for Gmail/Outlook, gets back an opaque session token) mints a session stored in the `SESSIONS` KV namespace, tagged with `provider`. `/api/messages` and `/api/action` dispatch on `session.provider` to the matching list/action functions; scoring rules are shared across all three. `/api/runs` is the older skill-run history log (GET public, POST bearer-gated via `RUN_TOKEN`), unrelated to the mail API.
- `landing/index.html`: white page, one blue accent, system font. Hero, the live inbox UI (Connect Gmail, seven-folder counts, Clear inbox, File everything, per-row File/Archive/Unsubscribe/Delete), feature cards, run history.
- `ios/App/`: native SwiftUI, no web view. Mac is `SimpleInboxView` (a count and one button, with loading, zero, error and Gmail-left states) plus `SettingsView` (accounts, the Smart sorting switch, sign out). iPhone and iPad are `InboxView` (the list). `SignInView` has both layouts. `GoogleAuth` runs `ASWebAuthenticationSession` against the iOS-type PKCE client and trades tokens at `/auth/native`. `appName` comes from the bundle, so views never spell the name.
- `ios/App/MacMail.swift` (Debug only): Mail.app mode. Reads every non-Gmail inbox over Apple Events, sends sender and subject to `/api/sort`, files into `Mailbag/<Folder>` and archives people. Needs the Apple Events entitlement in `Mailbag-macOS-Debug.entitlements`, which the store build must never carry. Gmail accounts in Mail.app are counted but not moved: Mail.app's move bounces back after a sync, so Gmail is cleared through the Gmail sign-in.
- Smart sorting: `llmRefine` in `worker.js` sends what the rules left in Inbox to Workers AI in one call. `?ai=0` on `/api/messages` or `ai: false` on `/api/sort` turns it off (the Settings switch). The sign-in screen and `privacy.html` both say so. Keep all three in step.
- Google Cloud project `jaybulb-signin` is shared across apps for OAuth — don't spin up a new GCP project per app. "Web client 1" (confidential, used by Mailbag's web flow and Supabase social sign-in — redirect URIs pile up on one client, not one client per app) and "Sieve iOS/macOS" (public, PKCE) are both on it. Gmail API + `gmail.modify` scope enabled on that project. App is unverified (testing/100-user cap) — real use is fine, just shows Google's "unverified app" click-through; formal verification is a follow-up, not required to work.
- Secrets: `GOOGLE_OAUTH_CLIENT_ID`/`GOOGLE_CLIENT_SECRET` as Worker secrets (`npx wrangler secret put`), also mirrored in `secrets.fish` as `GOOGLE_OAUTH_CLIENT_ID`/`SIEVE_GOOGLE_CLIENT_SECRET`.
- `SKILL.md` is still the dev-tool-alert half of the product (App Store Connect/Vercel/Sentry/GitHub Actions emails → matched to project → fixed or filed) — that needs a coding agent, so it stays a Claude Code skill, not something the app can do itself. Symlinked into the actual skill path via `dotfiles/claude/claude-skills/mail` → this repo.
- ASC app id `6811141466`, bundle `com.nulljosh.sieve`. Store listing name is **Mailbag**.
- The README is the house writing reference. Do not loosen it.

## Follow-ups
- Store build: the 1.0 in review is the old Hagaki build (red, list UI on Mac). Next submission is the Mailbag build: new icon, blue, the one-button Mac window, new screenshots (`-demo YES`), description and review notes in `metadata/` are already rewritten. Flip the listing name to Mailbag in the same move. Needs 6 GB free disk for the archives first.
- Add `https://mailbag.heyitsmejosh.com/auth/callback` to GCP Web client 1 (jaybulb-signin, Chrome account jatrommel@gmail.com), then point `GOOGLE_REDIRECT` and `apiBase` at the mailbag host. Until then a web Gmail sign-in lands on hagaki.heyitsmejosh.com.
- Mail.app mode still has folders named Hagaki in Joshua's iCloud and Ja accounts from the 2026-10-04 test. New filing goes to Mailbag.
- Submit for Google OAuth verification to drop the "unverified app" warning and lift the 100-user cap.
- Outlook needs an Azure app registration (client ID + secret, redirect URI `https://hagaki.heyitsmejosh.com/auth/callback/outlook`). Blocked on Joshua. The code path is done but dead until the secrets are set.

## Build (native)
```bash
cd ios && xcodegen generate
xcodebuild build -project Mailbag.xcodeproj -scheme Mailbag -destination 'platform=macOS'
xcodebuild build -project Mailbag.xcodeproj -scheme Mailbag -destination 'generic/platform=iOS Simulator'
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
- Filed for real in Mail.app via AppleScript into `Mailbag/<Folder>`. Gotcha: `mailbox "Mailbag/Dev"` does not resolve, use `mailbox "Dev" of mailbox "Mailbag"`, and re-query each message (move invalidates the list).
