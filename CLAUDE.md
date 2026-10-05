# Mailbag

Inbox triage app (web + iOS/macOS), plus the original `/mail` Claude Code skill for dev-tool-alert filing. One button, Clear inbox: machine mail goes into seven folders (Receipts, Travel, Dev, Newsletters, Social, Promotions, Junk), people go to the archive, nothing is deleted. Reads are user-invoked only. No cron, no background polling, per `~/CLAUDE.md`.

Names so far: Sieve, Siftbox (2026-09-11), Pare, Hagaki, Outtray (all 2026-10-04), now **Mailbag** (2026-10-04, Apple accepted it as a listing name). Joshua found Hagaki too Japanese and Outtray hard to say. What carries which name:
- Mailbag: display name, Xcode project/target/scheme (`Mailbag.xcodeproj`), landing, docs, icon, the `Mailbag/<Folder>` labels, `mailbag.heyitsmejosh.com`.
- Still Hagaki: the ASC listing (6811141466) and the 1.0 build in review. The listing was flipped back to Hagaki on purpose so it matches the build Apple is looking at. Rename the listing and submit a Mailbag build in the same move, never one without the other.
- `hagaki.heyitsmejosh.com` stays the API and Google OAuth host: `GOOGLE_REDIRECT` and the apps' `apiBase` point at it because that callback is the one saved in GCP Web client 1. `MS_REDIRECT` already uses the mailbag host, since the Microsoft registration is new. `pare`, `siftbox` and `sieve` hosts still resolve too. Add `https://mailbag.heyitsmejosh.com/auth/callback` in GCP before moving any of that.
- Never renamed: bundle ID `com.nulljosh.sieve`, Worker name `sieve`, the `sieve_session` cookie and `sieve_token` key.
- Launch flags are name-free and take a value: `-demo YES`, `-clear YES`, `-signedOut YES`, `-dark YES`, `-macMail YES` (Debug). `-demo` and `-signedOut` run on a throwaway session (`Session.scripted`, also true inside the unit-test host): they never read or write the saved sign-in. The demo is never saved either. Before this, one test run left the installed app sitting in the demo inbox.

- `worker.js`: the whole backend, now three providers. Gmail: `/auth/start` + `/auth/callback` (web OAuth, confidential client + secret). Outlook: `/auth/start/outlook` + `/auth/callback/outlook` (Microsoft identity platform v2, Graph API `Mail.ReadWrite`) — not registered with Microsoft yet, `MS_OAUTH_CLIENT_ID`/`MS_CLIENT_SECRET` not set, so `/auth/start/outlook` answers 503. iCloud: `/auth/icloud` (POST email + app-specific password, no OAuth exists for Apple Mail) — verified by one IMAP login before the session is stored, then real inbox reads go over raw IMAP (`imap.mail.me.com:993`) via `cloudflare:sockets`, one connection per request. `/auth/native` (iOS/macOS hands over PKCE-obtained tokens for Gmail/Outlook, gets back an opaque session token) mints a session stored in the `SESSIONS` KV namespace, tagged with `provider`. `/api/messages` and `/api/action` dispatch on `session.provider` to the matching list/action functions; scoring rules are shared across all three. `/api/runs` is the older skill-run history log (GET public, POST bearer-gated via `RUN_TOKEN`), unrelated to the mail API.
- `landing/index.html`: white page, one blue accent, system font. Hero, the live inbox UI (Connect Gmail, seven-folder counts, Clear inbox, File everything, per-row File/Archive/Unsubscribe/Delete), feature cards, run history.
- `ios/App/`: native SwiftUI, no web view. On the Mac the one window is made by `MacWindow` (an AppKit delegate in `MailbagApp.swift`), not by a `WindowGroup`: a WindowGroup did not present its window when the app launched without being brought to the front, and the app then ran with no window at all. `MacWindow` makes it at launch every time, sizes it to its content, and closing it quits. Do not move the Mac window back into a WindowGroup. Mac content is `SimpleInboxView` (a count and one button, with loading, zero, error and Gmail-left states) plus `SettingsView` (accounts, the Smart sorting switch, sign out). iPhone and iPad are `InboxView` (the list). `SignInView` has both layouts. `GoogleAuth` runs `ASWebAuthenticationSession` against the iOS-type PKCE client and trades tokens at `/auth/native`. `appName` comes from the bundle, so views never spell the name.
- `ios/App/MacMail.swift` (Debug only): Mail.app mode. Reads every non-Gmail inbox over Apple Events, sends sender and subject to `/api/sort`, files into `Mailbag/<Folder>` and archives people. Needs the Apple Events entitlement in `Mailbag-macOS-Debug.entitlements`, which the store build must never carry. Mail.app cannot move Gmail (its moves never reach Google and bounce back after a sync), so each Gmail account in Mail.app gets its own Gmail sign-in kept next to Mail.app mode: `Session.gmailTokens`, keyed by address, matched to the account through `/api/whoami`. The window's number and Clear inbox cover every source at once (`SimpleInboxView.sources`). A Gmail account with no sign-in is counted from Mail.app and offered as "Sign in to Gmail".
- Joshua's own copy is the Debug build copied to `/Applications/Mailbag.app` (`ditto` from the DerivedData product). With nothing saved it starts in Mail.app mode by itself. Reinstall it after changes he should see.
- Smart sorting: `llmRefine` in `worker.js` sends what the rules left in Inbox to Workers AI in one call. `?ai=0` on `/api/messages` or `ai: false` on `/api/sort` turns it off (the Settings switch). The sign-in screen and `privacy.html` both say so. Keep all three in step.
- Google Cloud project `jaybulb-signin` is shared across apps for OAuth — don't spin up a new GCP project per app. "Web client 1" (confidential, used by Mailbag's web flow and Supabase social sign-in — redirect URIs pile up on one client, not one client per app) and "Sieve iOS/macOS" (public, PKCE) are both on it. Gmail API + `gmail.modify` scope enabled on that project. App is unverified (testing/100-user cap) — real use is fine, just shows Google's "unverified app" click-through; formal verification is a follow-up, not required to work.
- Secrets: `GOOGLE_OAUTH_CLIENT_ID`/`GOOGLE_CLIENT_SECRET` as Worker secrets (`npx wrangler secret put`), also mirrored in `secrets.fish` as `GOOGLE_OAUTH_CLIENT_ID`/`SIEVE_GOOGLE_CLIENT_SECRET`.
- `SKILL.md` is still the dev-tool-alert half of the product (App Store Connect/Vercel/Sentry/GitHub Actions emails → matched to project → fixed or filed) — that needs a coding agent, so it stays a Claude Code skill, not something the app can do itself. Symlinked into the actual skill path via `dotfiles/claude/claude-skills/mail` → this repo.
- ASC app id `6811141466`, bundle `com.nulljosh.sieve`. Store listing name is still **Hagaki** (see the names list above).
- The README is the house writing reference. Do not loosen it.

## Follow-ups
- Store build: the 1.0 in review is the old Hagaki build (red, list UI on Mac). Next submission is the Mailbag build: new icon, blue, the one-button Mac window, new screenshots (`-demo YES`), description and review notes in `metadata/` are already rewritten. Flip the listing name to Mailbag in the same move. Needs 6 GB free disk for the archives first.
- Add `https://mailbag.heyitsmejosh.com/auth/callback` to GCP Web client 1 (jaybulb-signin, Chrome account jatrommel@gmail.com), then point `GOOGLE_REDIRECT` and `apiBase` at the mailbag host. Until then a web Gmail sign-in lands on hagaki.heyitsmejosh.com.
- Joshua's iCloud folder from the 2026-10-04 test was renamed Hagaki to Mailbag. His Ja Gmail may still carry a few `Hagaki/...` labels next to the new `Mailbag/...` ones.
- Submit for Google OAuth verification to drop the "unverified app" warning and lift the 100-user cap.
- Outlook: see `docs/LOOP-HANDOFF.md`. Needs an Entra app registration (`az` is installed, Joshua has to `az login` first), then `MS_OAUTH_CLIENT_ID` and `MS_CLIENT_SECRET` as Worker secrets. `/api/providers` keeps the button hidden until both exist. The Graph code has never run against a real mailbox.

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

## Who may be filed (changed 2026-10-04, after real misfiles)
The first Gmail clear put a TSI collections notice in Junk and two school emails in Newsletters. The rules now are, in `worker.js`:
- `scoreMessage`: Junk means scam signs (name/domain mismatch, urgency plus a generic greeting, a different reply-to). An unsubscribe header no longer adds to the score. Bulk mail with an unsubscribe link and no impersonation is never Junk.
- `fileable`: mail may be filed only if `looksAutomated` (unsubscribe header, Gmail bulk label, no-reply style local part, or a domain the rules know) and it does not match `NEEDS_YOU` (collections, debt, overdue, court). Everything else is `Inbox` and is only ever archived.
- `llmRefine` only receives `fileable` leftovers, so mail from people never reaches the model. The site, README, sign-in screen, Settings and `privacy.html` all say this. Keep them true.
- Known soft spot: any bulk mail with an unsubscribe header that no rule names still falls to Newsletters.

## The loop

State: `docs/LOOP-HANDOFF.md`. Goal: Outlook working on a real mailbox, then one Mailbag build submitted to the App Store.
