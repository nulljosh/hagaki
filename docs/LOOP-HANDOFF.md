# Mailbag loop handoff (2026-10-04, late)

## What the loop is

Keep every inbox on Joshua's Mac at zero with the app itself, add Outlook, then submit one Mailbag build to the App Store.

## Where things stand

- Inboxes: iCloud, Ja (Gmail) and Gmail read 0 in Mail.app.
- The Mac app is installed at `/Applications/Mailbag.app` (Debug build, Mail.app mode). Two bugs made it "not work" for Joshua and are fixed: it opened no window when launched without focus (now `MacWindow` owns the window), and test runs left it stuck in the demo inbox (now tests and the demo never touch the saved sign-in).
- One window covers every account: Mail.app for iCloud, plus a Gmail sign-in per Gmail account. Joshua's earlier Gmail sign-in was lost to a relaunch, so both Gmail accounts (Ja and Gmail) need one sign-in each. The window offers it.
- Sorter was tightened after real misfiles: people are never filed or sent to the model, debt and legal notices are never filed, Junk needs scam signs. See "Who may be filed" in CLAUDE.md.
- Misfiled mail: the TSI collections notice is back in the Ja inbox at Joshua's request (he asked, so it was moved by hand). Gmail still shows the old `Mailbag/Junk` label on it, which Mail.app cannot remove without risking Trash. Two school emails are still in `Mailbag/Newsletters`. Nothing was deleted.
- Outlook: parked. Joshua only has a school Microsoft account (langleyschools.ca) and that directory does not let users register apps. Needs a personal Microsoft account with its own directory. `az` is still logged in to the school tenant: do not register anything there.
- App Store: nothing changed on Apple's side. Listing says Hagaki, old 1.0 build still in review. Local prep only: build number bumped, a Debug `-shot NAME -shotDelay N` flag writes a 4x window PNG to the app's temp folder for Mac screenshots. Mac screenshot composition was started and not finished (captions overlap the window, corners unrounded). iPhone and iPad screenshots are still the old red ones. Joshua stopped the session here: he was sick of the app opening and closing on his screen. Do the rest without launching the app in front of him (`open -g`, or when he is away).

## Next, in order

1. Joshua says he signed in to at least one Gmail account in the app, but no Gmail sign-in is saved in the Keychain (checked with `security find-generic-password -s com.nulljosh.sieve -a gmail`). Treat as a possible bug in `Session.addGmail`/`saveGmail` until he reopens the app and it either shows the account as signed in (Settings) or still offers "Sign in to Gmail". Do not launch the app in front of him to find out; ask him, or read the Keychain after he has used it.
2. Outlook waits for a personal Microsoft account with its own directory. Then `az login`, register the Entra app, make a secret, `wrangler secret put` both values, deploy, test.
3. Add "Continue with Outlook" to the native sign-in.
4. Retake iPhone, iPad and Mac screenshots with `-demo YES`.
5. Check disk, archive iOS and macOS, upload, then cancel the old review, set the listing name to Mailbag and submit, all in one move.
6. Add `https://mailbag.heyitsmejosh.com/auth/callback` in GCP Web client 1, then move `GOOGLE_REDIRECT` and `apiBase` to the mailbag host.

## Restart prompt

```
/loop until every inbox on this Mac clears from the Mailbag window, Outlook works on a real mailbox, and the Mailbag build is submitted
```
