import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

// Load the real Worker without Cloudflare's socket import; no network calls.
const source = readFileSync(new URL('./worker.js', import.meta.url), 'utf8')
  .replace('import { connect } from "cloudflare:sockets";', '')
  .replace('export default', 'const worker =');
let archiveOk = false;
const { scoreMessage, gmailAction } = runInNewContext(
  source + '\n;({ scoreMessage, gmailAction });',
  { fetch: async () => ({ ok: archiveOk }) },
);
const message = domain => ({
  from: `Apple <alerts@${domain}>`, replyTo: '', subject: 'Act now',
  snippet: 'Dear customer', listUnsubscribe: '',
});
for (const domain of ['github.com.evil.example', 'fakeapple.com', 'evilstripe.com', 'itunesconnect.evil.example']) {
  assert.equal(scoreMessage(message(domain)).isJunk, true, domain);
}
for (const domain of ['apple.com', 'appleid.apple.com', 'notifications.github.com', 'STRIPE.COM', 'supabase.io']) {
  assert.equal(scoreMessage(message(domain)).isJunk, false, domain);
}
for (archiveOk of [false, true]) {
  const result = await gmailAction({ access_token: 'test' }, { messageId: 'test', action: 'unsubscribe' });
  assert.equal(result.archived, archiveOk);
  assert.equal(result.unsubscribed, false);
}
console.log('sender scoring and archive results: ok');

for (const archived of [false, true]) {
  let closed = false;
  const client = {
    async cmd(command) {
      if (command.startsWith('UID MOVE') && !archived) throw new Error('move rejected');
    },
    async quit() { closed = true; },
  };
  const action = runInNewContext(
    source + '\n;imapLogin = async () => client; icloudAction;',
    { client },
  );
  const result = await action({}, { messageId: '1', action: 'unsubscribe' });
  assert.equal(result.archived, archived);
  assert.equal(result.unsubscribed, false);
  assert.equal(closed, true);
}
console.log('iCloud archive results and connection cleanup: ok');
