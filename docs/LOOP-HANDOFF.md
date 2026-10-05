# Mailbag loop handoff (2026-10-04, night)

## What the loop is

Get every inbox to zero with the app itself, get the Mac app to A+, add Outlook, then submit one Mailbag build to the App Store.

## Where things stand

- Inboxes: iCloud, Ja (Gmail) and Gmail all read 0, and still read 0 after a Mail sync. iCloud was cleared by Mail.app mode. Ja was cleared through the app's Gmail sign-in after Mail.app moves bounced back twice.
- Mac app: one number, one Clear inbox button, Settings window, loading, zero, error and Gmail-left states, light and dark. Graded A. Mac unit and UI tests pass. The UI test opens a window with Cmd-N because the test runner launches the app with none. A normal launch always has one. Cause not found.
- Web: live at mailbag.heyitsmejosh.com with Clear inbox and the blue palette.
- Outlook: server code is written and never run against a real mailbox. `/api/providers` reports it off and the page hides the button until `MS_OAUTH_CLIENT_ID` and `MS_CLIENT_SECRET` exist. `az` is installed. Nothing is registered with Microsoft yet.
- App Store: listing says Hagaki and the old 1.0 build is in review. No Mailbag build has been archived. iPhone and iPad screenshots in `screenshots/` are still the old red ones. `metadata/` already describes Mailbag.

## Next, in order

1. Joshua runs `az login --allow-no-subscriptions`. Then register the Entra app (any org plus personal accounts, web redirects for the mailbag and hagaki hosts, a public-client redirect for the native apps), make a secret, `wrangler secret put` both values, deploy.
2. Joshua signs in with his Outlook test account on the web. Check list, Clear inbox, archive and delete against the real mailbox. Fix what breaks.
3. Add "Continue with Outlook" to the native sign-in (PKCE, same shape as `GoogleAuth`).
4. Retake iPhone, iPad and Mac screenshots with `-demo YES`.
5. Check disk (`df -h /`, about 4 GB free tonight). Archive iOS and macOS, upload, then cancel the old review, set the listing name to Mailbag and submit, all in one move.
6. Add `https://mailbag.heyitsmejosh.com/auth/callback` in GCP Web client 1, then move `GOOGLE_REDIRECT` and `apiBase` to the mailbag host.

## Restart prompt

```
/loop until Outlook works on a real mailbox and the Mailbag build is submitted to the App Store
```
