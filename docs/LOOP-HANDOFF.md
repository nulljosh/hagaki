# Mailbag loop handoff (2026-10-04, evening)

## What the loop is

Clear every inbox to zero and get the Mac app to A+ quality. Machine mail goes into seven smart folders, people go to the archive, nothing is deleted. Real mail flow tested and working on Joshua's own inboxes.

## Where things stand (2026-10-04)

- iCloud inbox: cleared from 21 to 0. Machine mail filed into seven folders (Receipts, Travel, Dev, Newsletters, Social, Promotions, Junk), people archived. Rules plus a Workers AI pass (`llama-3.3-70b`) sort what the rules miss.
- Gmail "Ja" account: 5 messages stubborn (tried Mail.app twice, bounced back both times). Waiting on Joshua to click "Sign in to Gmail" in the app so it can use Gmail directly. After sign-in, confirm it reads 0 and stays 0 after a real Gmail sync.
- Mac app: rebuilt as one big number and one "Clear inbox" button plus Settings window (accounts, smart sorting toggle, sign out). White background, San Francisco font, blue icon (letter dropping into a tray). UI grades A in light and dark. Mac UI test failing: the test runner sees no window due to hidden title bar and launch flags. Direct launches show the window fine.
- iOS/macOS 1.0 builds: ready to submit, need 6 GB free disk to archive. Screenshots retaken with `-demo YES` (iPhone and iPad). ASC listing still says Hagaki with the old 1.0 build in review; flip the listing name to Mailbag and submit the Mailbag build in the same move.
- Web: live at mailbag.heyitsmejosh.com.
- OAuth callbacks: still at hagaki.heyitsmejosh.com. Add `https://mailbag.heyitsmejosh.com/auth/callback` in GCP Web client 1 before moving the callbacks.

## Next, in order

1. Joshua clicks "Sign in to Gmail" in the Mailbag window, confirm Ja inbox reads 0 and still reads 0 after a Mail sync, then quit the app.
2. Fix the Mac UI test (ios/UITests/MailbagUITests.swift: the test runner sees no window since the hidden title bar and launch-flag changes; direct launches show the window fine).
3. Retake iPhone and iPad screenshots with `-demo YES`.
4. Free disk to 6 GB, archive iOS and macOS builds, then flip the ASC listing name to Mailbag and resubmit in the same move.
5. Add the mailbag OAuth callback in GCP Web client 1 (jaybulb-signin, Chrome account jatrommel@gmail.com).

## Restart prompt

```
/loop until every inbox is 0 and the Mailbag Mac app is A+, then submit the Mailbag build
```
