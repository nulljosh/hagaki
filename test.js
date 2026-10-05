import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

// Load the real Worker without Cloudflare's socket import; no network calls.
const source = readFileSync(new URL('./worker.js', import.meta.url), 'utf8')
  .replace('import { connect } from "cloudflare:sockets";', '')
  .replace('export default', 'const worker =');
let archiveOk = false;
const { scoreMessage, gmailAction, demoList, performAction } = runInNewContext(
  source + '\n;({ scoreMessage, gmailAction, demoList, performAction });',
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

// demo inbox: real scorer over sample mail, and actions never leave the worker
{
  const demo = demoList();
  assert.ok(demo.filter(m => m.isJunk).length >= 3, 'demo has junk');
  assert.ok(demo.filter(m => !m.isJunk).length >= 3, 'demo has legit mail');
  assert.equal(demo.filter(m => m.isJunk && m.listUnsubscribe && m.from.includes('dealdrop')).length, 2, 'repeat sender for the rollup');
  assert.equal(JSON.stringify(performAction({ provider: 'demo' }, { action: 'archive' })), JSON.stringify({ demo: true, archived: true }));
}

// smart folders: seven boxes, real people stay in the inbox, nothing is deleted
{
  const calls = [];
  const fetchMock = async (url, opts = {}) => {
    calls.push({ url, method: opts.method || 'GET', body: opts.body ? JSON.parse(opts.body) : null });
    if (url.endsWith('/labels') && !opts.method) return { ok: true, json: async () => ({ labels: [{ id: 'L1', name: 'Hagaki/Receipts' }] }) };
    if (url.endsWith('/labels')) return { ok: true, json: async () => ({ id: 'L2' }) };
    return { ok: true, json: async () => ({}) };
  };
  const ctx = runInNewContext(source + '\n;({ categorize, groupByFolder, gmailOrganize, FOLDERS });', { fetch: fetchMock });
  const mail = (from, subject, extra = {}) => ctx.categorize({ from, subject, snippet: '', listUnsubscribe: '', isJunk: false, ...extra });
  assert.equal(ctx.FOLDERS.length, 7, 'seven boxes');
  assert.equal(mail('GitHub <noreply@github.com>', 'Run failed'), 'Dev');
  assert.equal(mail('Stripe <receipts@stripe.com>', 'Your receipt from Acme'), 'Receipts');
  assert.equal(mail('Air Canada <noreply@aircanada.com>', 'Your boarding pass'), 'Travel');
  assert.equal(mail('LinkedIn <n@linkedin.com>', 'You appeared in 4 searches'), 'Social');
  assert.equal(mail('Shop <a@shop.example>', '50% off today', { listUnsubscribe: '<https://x>' }), 'Promotions');
  assert.equal(mail('Letter <a@weekly.example>', 'Issue 42', { listUnsubscribe: '<https://x>' }), 'Newsletters');
  assert.equal(mail('Sam <sam@example.org>', 'Lunch Thursday?'), 'Inbox');
  assert.equal(mail('App Store Connect <no_reply@email.apple.com>', 'Review of your Talli (macOS) submission is complete.'), 'Dev');
  assert.equal(mail('TestFlight <testflight_no_reply@email.apple.com>', 'Bookrank 1.1.0 for iOS is now available to test.'), 'Dev');
  assert.equal(mail('Stripe <notifications@stripe.com>', 'Stripe webhook delivery issues'), 'Dev');
  assert.equal(mail('Shop <orders@shop.example>', 'Your Shop order has been received!'), 'Receipts');
  assert.equal(mail('Jordi <a@creators.gumroad.com>', 'MacWhisper 15.2'), 'Newsletters');
  assert.equal(mail('Jeremy <sysadmin@myeducation.gov.bc.ca>', 'Online Fall Start-Up 2026'), 'Inbox');
  assert.equal(mail('GitGuardian <security@getgitguardian.com>', 'Password exposed on GitHub'), 'Dev');
  assert.equal(mail('Bad <a@bad.example>', 'x', { isJunk: true }), 'Junk');
  assert.deepEqual(JSON.parse(JSON.stringify(ctx.groupByFolder([{ messageId: 'a', category: 'Dev' }, { messageId: 'b', category: 'Inbox' }, { messageId: 'c', category: 'Dev' }]))), { Dev: ['a', 'c'] });
  const result = await ctx.gmailOrganize({ access_token: 't' }, [{ messageId: 'm1', category: 'Receipts' }, { messageId: 'm2', category: 'Travel' }, { messageId: 'm3', category: 'Inbox' }]);
  assert.deepEqual(JSON.parse(JSON.stringify(result)), { organized: { Receipts: 1, Travel: 1 }, failed: 0 });
  const batches = calls.filter(c => c.url.endsWith('/messages/batchModify'));
  assert.equal(batches.length, 2);
  assert.deepEqual(batches.map(b => b.body.removeLabelIds[0]), ['INBOX', 'INBOX']);
  assert.ok(!calls.some(c => /trash|DELETE/.test(c.url + c.method)), 'organizing never deletes');
  assert.equal(calls.filter(c => c.method === 'POST' && c.url.endsWith('/labels')).length, 1, 'only the missing label is created');
}
console.log('smart folders: ok');

// iCloud: folder is created, then the move uses it, and the connection closes
{
  const cmds = [];
  const client = { async cmd(c) { cmds.push(c); if (c.startsWith('CREATE')) throw new Error('exists'); }, async quit() { cmds.push('QUIT'); } };
  const organize = runInNewContext(source + '\n;imapLogin = async () => client; icloudOrganize;', { client });
  const result = await organize({}, [{ messageId: '7', category: 'Receipts' }, { messageId: '8', category: 'Receipts' }, { messageId: 'x', category: 'Dev' }]);
  assert.deepEqual(JSON.parse(JSON.stringify(result)), { organized: { Receipts: 2 }, failed: 1 });
  assert.ok(cmds.includes('UID MOVE 7,8 "Hagaki/Receipts"'));
  assert.equal(cmds.at(-1), 'QUIT');
}
console.log('iCloud smart folders: ok');

// LLM pass: only leftovers move, bad output and missing binding leave the rules result alone
{
  const ctx = runInNewContext(source + '\n;({ llmRefine });');
  const mk = () => [{ category: 'Inbox', from: 'a', subject: 'x' }, { category: 'Dev', from: 'b', subject: 'y' }, { category: 'Inbox', from: 'c', subject: 'z' }];
  const ai = (response) => ({ AI: { run: async () => ({ response }) } });
  const out = await ctx.llmRefine(ai('sure: [{"i":0,"c":"Junk"},{"i":1,"c":"Bogus"}]'), mk());
  assert.deepEqual(out.map(m => m.category), ['Junk', 'Dev', 'Inbox']);
  assert.deepEqual((await ctx.llmRefine(ai('nonsense'), mk())).map(m => m.category), ['Inbox', 'Dev', 'Inbox']);
  assert.deepEqual((await ctx.llmRefine(ai([{ i: 1, c: 'Promotions' }]), mk())).map(m => m.category), ['Inbox', 'Dev', 'Promotions']);
  assert.deepEqual((await ctx.llmRefine({}, mk())).map(m => m.category), ['Inbox', 'Dev', 'Inbox']);
}
console.log('llm pass: ok');

// Mac Mail mode: sortItems scores and files client-side mail the same way
{
  const ctx = runInNewContext(source + '\n;({ sortItems });');
  const out = ctx.sortItems([{ id: 1, from: 'GitHub <n@github.com>', subject: 'Run failed' }, { id: 'b', from: 'Mom <m@shaw.ca>', subject: 'dinner' }]);
  assert.deepEqual(out.map(m => [m.id, m.category]), [['1', 'Dev'], ['b', 'Inbox']]);
}
console.log('mac sort: ok');
