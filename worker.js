import { connect } from "cloudflare:sockets";

const RUNS_KEY = "history";
const MAX_RUNS = 50;

const GOOGLE_AUTH = "https://accounts.google.com/o/oauth2/v2/auth";
const GOOGLE_TOKEN = "https://oauth2.googleapis.com/token";
const GMAIL = "https://gmail.googleapis.com/gmail/v1/users/me";
const GMAIL_SCOPE = "https://www.googleapis.com/auth/gmail.modify";
const GOOGLE_REDIRECT = "https://hagaki.heyitsmejosh.com/auth/callback"; // registered in GCP console (Web client 1), pare/siftbox/sieve stay registered too

const MS_AUTH = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize";
const MS_TOKEN = "https://login.microsoftonline.com/common/oauth2/v2.0/token";
const GRAPH = "https://graph.microsoft.com/v1.0/me";
const MS_SCOPE = "offline_access Mail.ReadWrite";
const MS_REDIRECT = "https://hagaki.heyitsmejosh.com/auth/callback/outlook";

const IMAP_HOST = "imap.mail.me.com";
const IMAP_PORT = 993;

// ponytail: JSON blob in KV per session id, no schema migrations needed for a single-user-per-row store.
async function getSession(env, id) {
  if (!id) return null;
  return (await env.SESSIONS.get(`sess:${id}`, "json")) || null;
}
async function putSession(env, id, data) {
  await env.SESSIONS.put(`sess:${id}`, JSON.stringify(data), { expirationTtl: 60 * 60 * 24 * 30 });
}

function cookie(req, name) {
  const raw = req.headers.get("Cookie") || "";
  const m = raw.match(new RegExp(`${name}=([^;]+)`));
  return m ? m[1] : null;
}

function sessionIdFromRequest(req) {
  const auth = req.headers.get("Authorization") || "";
  if (auth.startsWith("Bearer ")) return auth.slice(7);
  return cookie(req, "sieve_session");
}

async function refreshIfNeeded(env, id, session) {
  if (session.provider === "icloud" || session.provider === "demo") return session; // app-password login, re-authenticates every call
  if (session.expires_at > Date.now() + 30_000) return session;
  const tokenUrl = session.provider === "outlook" ? MS_TOKEN : GOOGLE_TOKEN;
  const body = new URLSearchParams({
    client_id: session.client_id,
    refresh_token: session.refresh_token,
    grant_type: "refresh_token",
  });
  if (session.client_secret) body.set("client_secret", session.client_secret);
  if (session.provider === "outlook") body.set("scope", MS_SCOPE);
  const r = await fetch(tokenUrl, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body });
  if (!r.ok) return null;
  const tok = await r.json();
  session.access_token = tok.access_token;
  if (tok.refresh_token) session.refresh_token = tok.refresh_token;
  session.expires_at = Date.now() + tok.expires_in * 1000;
  await putSession(env, id, session);
  return session;
}

// --- spam scoring, ported from SKILL.md's rules ---
const URGENCY = /\b(act now|expires? today|verify your account|suspend|limited time|click here|claim now|final notice)\b/i;
const KNOWN_SERVICES = /^(?:[a-z0-9-]+\.)*(?:apple\.com|vercel\.com|sentry\.io|github\.com|stripe\.com|supabase\.(?:io|com)|cloudflare\.com)$/i;

function domainOf(addr) {
  const m = addr.match(/@([^ >]+)/);
  return m ? m[1].toLowerCase() : "";
}

function scoreMessage({ from, replyTo, subject, snippet, listUnsubscribe }) {
  let score = 0;
  const reasons = [];
  const fromDomain = domainOf(from);
  const displayName = (from.match(/^"?([^"<]*)"?\s*</) || [, ""])[1].trim();

  if (displayName && !KNOWN_SERVICES.test(fromDomain) && /paypal|apple|amazon|bank|google|microsoft/i.test(displayName) && !fromDomain.includes(displayName.toLowerCase().split(" ")[0])) {
    score += 2; reasons.push("sender name/domain mismatch");
  }
  if (URGENCY.test(subject) || URGENCY.test(snippet)) { score += 1; reasons.push("urgency language"); }
  if (/dear (customer|user|member)/i.test(snippet)) { score += 1; reasons.push("generic bulk greeting"); }
  if (listUnsubscribe && !KNOWN_SERVICES.test(fromDomain)) { score += 1; reasons.push("unsubscribe header, unfamiliar sender"); }
  if (replyTo && domainOf(replyTo) && domainOf(replyTo) !== fromDomain) { score += 1; reasons.push("reply-to domain differs"); }

  return { score, reasons, isJunk: score >= 2 && !KNOWN_SERVICES.test(fromDomain) };
}

// --- smart folders: seven boxes, like the seven red boxes on a Japanese postcard ---
// Mail from real people has no folder and stays in the inbox. Everything else gets filed, never deleted.
const FOLDER_PARENT = "Hagaki";
const FOLDERS = ["Receipts", "Travel", "Dev", "Newsletters", "Social", "Promotions", "Junk"];
const DEV = /(?:github|gitlab|vercel|sentry|cloudflare|supabase|netlify|npmjs|circleci|atlassian|linear|appstoreconnect|itunesconnect|developer\.apple|testflight|twilio|kaggle|apify|getgitguardian)\./i;
const DEV_WORDS = /\b(build (?:failed|succeeded)|deploy(?:ment)?|pull request|workflow run|app store connect|testflight|new sign-in|your [^.]{1,60} submission|uploaded build|available to test|invited you to test)\b/i;
const RECEIPT = /\b(receipts?|invoices?|your order|order confirmation|payment|statement|billing|renewal|charged|bill is ready)\b/i;
const PAYMENTS = /(?:stripe|paypal|square|squareup|shopify|venmo)\./i;
const TRAVEL = /\b(flights?|boarding pass|itinerary|booking confirmation|reservation|hotel|check-in)\b/i;
const TRAVEL_SITES = /(?:airbnb|expedia|booking|aircanada|westjet|kayak|tripadvisor|airlines?)\./i;
const SOCIAL = /(?:linkedin|facebookmail|twitter|instagram|reddit|redditmail|discord|pinterest|tiktok|snapchat|nextdoor)\./i;
const PROMO_WORDS = /\b(sale|\d+% off|deals?|offers?|coupon|discount|free shipping|limited time)\b/i;
const LETTER_SITES = /(?:substack|medium|beehiiv|mailchimp|convertkit|buttondown)\./i;
const LETTER_WORDS = /\b(newsletter|digest|weekly|monthly|issue #?\d+)\b/i;

function categorize({ from, subject, snippet, listUnsubscribe, isJunk, labelIds = [] }) {
  if (isJunk) return "Junk";
  const d = domainOf(from) + ".";
  const text = `${subject || ""} ${snippet || ""}`;
  if (DEV.test(d) || DEV_WORDS.test(subject || "")) return "Dev";
  if (PAYMENTS.test(d) || RECEIPT.test(subject || "")) return "Receipts";
  if (TRAVEL_SITES.test(d) || TRAVEL.test(subject || "")) return "Travel";
  if (SOCIAL.test(d) || labelIds.includes("CATEGORY_SOCIAL")) return "Social";
  if (labelIds.includes("CATEGORY_PROMOTIONS") || (listUnsubscribe && PROMO_WORDS.test(text))) return "Promotions";
  if (LETTER_SITES.test(d) || LETTER_WORDS.test(text) || listUnsubscribe || labelIds.includes("CATEGORY_UPDATES") || labelIds.includes("CATEGORY_FORUMS")) return "Newsletters";
  return "Inbox";
}

// group [{ messageId, category }] by folder, dropping anything that is not one of the seven
function groupByFolder(items) {
  const groups = {};
  for (const { messageId, category } of items || []) {
    if (messageId && FOLDERS.includes(category)) (groups[category] ||= []).push(String(messageId));
  }
  return groups;
}

function header(headers, name) {
  const h = headers.find((h) => h.name.toLowerCase() === name.toLowerCase());
  return h ? h.value : "";
}

async function unsubscribe(listUnsubscribe, oneClick) {
  const urlMatch = listUnsubscribe.match(/<(https?:[^>]+)>/);
  if (urlMatch && oneClick) {
    const r = await fetch(urlMatch[1], { method: "POST", body: "List-Unsubscribe=One-Click", headers: { "Content-Type": "application/x-www-form-urlencoded" } });
    return r.ok || r.status === 204;
  }
  if (urlMatch) {
    const r = await fetch(urlMatch[1]);
    return r.ok;
  }
  return false;
}

// ======================= Gmail =======================
async function gmailFetch(session, path, opts = {}) {
  return fetch(`${GMAIL}${path}`, { ...opts, headers: { ...(opts.headers || {}), Authorization: `Bearer ${session.access_token}` } });
}

async function gmailList(session) {
  const listRes = await gmailFetch(session, "/messages?maxResults=30&labelIds=INBOX");
  if (!listRes.ok) throw new Error(`gmail list failed: ${listRes.status}`);
  const { messages = [] } = await listRes.json();
  const out = [];
  for (const m of messages) {
    const r = await gmailFetch(session, `/messages/${m.id}?format=metadata&metadataHeaders=From&metadataHeaders=Subject&metadataHeaders=Reply-To&metadataHeaders=List-Unsubscribe&metadataHeaders=List-Unsubscribe-Post`);
    if (!r.ok) continue;
    const msg = await r.json();
    const headers = msg.payload?.headers || [];
    const from = header(headers, "From");
    const subject = header(headers, "Subject");
    const replyTo = header(headers, "Reply-To");
    const listUnsubscribe = header(headers, "List-Unsubscribe");
    const oneClick = /one-click/i.test(header(headers, "List-Unsubscribe-Post"));
    const snippet = msg.snippet || "";
    const { score, reasons, isJunk } = scoreMessage({ from, replyTo, subject, snippet, listUnsubscribe });
    const category = categorize({ from, subject, snippet, listUnsubscribe, isJunk, labelIds: msg.labelIds || [] });
    out.push({ id: m.id, from, subject, snippet, score, reasons, isJunk, category, listUnsubscribe, oneClick });
  }
  return out;
}

async function gmailAction(session, { messageId, action, listUnsubscribe, oneClick }) {
  if (action === "unsubscribe") {
    const ok = listUnsubscribe ? await unsubscribe(listUnsubscribe, oneClick) : false;
    const r = await gmailFetch(session, `/messages/${messageId}/modify`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ removeLabelIds: ["INBOX"] }) });
    return { unsubscribed: ok, archived: r.ok };
  }
  if (action === "archive") {
    const r = await gmailFetch(session, `/messages/${messageId}/modify`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ removeLabelIds: ["INBOX"] }) });
    return { archived: r.ok };
  }
  if (action === "delete") {
    const r = await gmailFetch(session, `/messages/${messageId}/trash`, { method: "POST" });
    return { deleted: r.ok };
  }
  return { error: "unknown action" };
}

// Files messages into Hagaki/<Folder> labels and takes them out of the inbox. Nothing is trashed.
async function gmailOrganize(session, items) {
  const groups = groupByFolder(items);
  const organized = {};
  let failed = 0;
  if (!Object.keys(groups).length) return { organized, failed };
  const json = { "Content-Type": "application/json" };
  const listRes = await gmailFetch(session, "/labels");
  if (!listRes.ok) throw new Error(`gmail labels failed: ${listRes.status}`);
  const labels = Object.fromEntries(((await listRes.json()).labels || []).map((l) => [l.name, l.id]));
  for (const [folder, ids] of Object.entries(groups)) {
    const name = `${FOLDER_PARENT}/${folder}`;
    if (!labels[name]) {
      const r = await gmailFetch(session, "/labels", { method: "POST", headers: json, body: JSON.stringify({ name, labelListVisibility: "labelShow", messageListVisibility: "show" }) });
      if (r.ok) labels[name] = (await r.json()).id;
    }
    if (!labels[name]) { failed += ids.length; continue; }
    const r = await gmailFetch(session, "/messages/batchModify", { method: "POST", headers: json, body: JSON.stringify({ ids, addLabelIds: [labels[name]], removeLabelIds: ["INBOX"] }) });
    if (r.ok) organized[folder] = ids.length; else failed += ids.length;
  }
  return { organized, failed };
}

// ======================= Outlook (Microsoft Graph) =======================
async function graphFetch(session, path, opts = {}) {
  return fetch(`${GRAPH}${path}`, { ...opts, headers: { ...(opts.headers || {}), Authorization: `Bearer ${session.access_token}` } });
}

function graphHeader(internetMessageHeaders, name) {
  const h = (internetMessageHeaders || []).find((h) => h.name.toLowerCase() === name.toLowerCase());
  return h ? h.value : "";
}

async function outlookList(session) {
  const r = await graphFetch(session, "/mailFolders/inbox/messages?$top=30&$select=subject,from,bodyPreview,internetMessageHeaders");
  if (!r.ok) throw new Error(`outlook list failed: ${r.status}`);
  const { value = [] } = await r.json();
  return value.map((m) => {
    const from = m.from?.emailAddress ? `${m.from.emailAddress.name || ""} <${m.from.emailAddress.address}>` : "";
    const subject = m.subject || "";
    const snippet = m.bodyPreview || "";
    const replyTo = graphHeader(m.internetMessageHeaders, "Reply-To");
    const listUnsubscribe = graphHeader(m.internetMessageHeaders, "List-Unsubscribe");
    const oneClick = /one-click/i.test(graphHeader(m.internetMessageHeaders, "List-Unsubscribe-Post"));
    const { score, reasons, isJunk } = scoreMessage({ from, replyTo, subject, snippet, listUnsubscribe });
    const category = categorize({ from, subject, snippet, listUnsubscribe, isJunk });
    return { id: m.id, from, subject, snippet, score, reasons, isJunk, category, listUnsubscribe, oneClick };
  });
}

// ponytail: untested until the Azure app registration exists. One folder per category, found by display name.
async function outlookOrganize(session, items) {
  const groups = groupByFolder(items);
  const organized = {};
  let failed = 0;
  const json = { "Content-Type": "application/json" };
  for (const [folder, ids] of Object.entries(groups)) {
    const displayName = `${FOLDER_PARENT} ${folder}`;
    const found = await graphFetch(session, `/mailFolders?$filter=${encodeURIComponent(`displayName eq '${displayName}'`)}`);
    let folderId = found.ok ? ((await found.json()).value || [])[0]?.id : null;
    if (!folderId) {
      const made = await graphFetch(session, "/mailFolders", { method: "POST", headers: json, body: JSON.stringify({ displayName }) });
      if (made.ok) folderId = (await made.json()).id;
    }
    if (!folderId) { failed += ids.length; continue; }
    let moved = 0;
    for (const id of ids) {
      const r = await graphFetch(session, `/messages/${id}/move`, { method: "POST", headers: json, body: JSON.stringify({ destinationId: folderId }) });
      if (r.ok) moved++; else failed++;
    }
    if (moved) organized[folder] = moved;
  }
  return { organized, failed };
}

async function outlookAction(session, { messageId, action, listUnsubscribe, oneClick }) {
  if (action === "unsubscribe") {
    const ok = listUnsubscribe ? await unsubscribe(listUnsubscribe, oneClick) : false;
    const r = await graphFetch(session, `/messages/${messageId}/move`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ destinationId: "archive" }) });
    return { unsubscribed: ok, archived: r.ok };
  }
  if (action === "archive") {
    const r = await graphFetch(session, `/messages/${messageId}/move`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ destinationId: "archive" }) });
    return { archived: r.ok };
  }
  if (action === "delete") {
    const r = await graphFetch(session, `/messages/${messageId}`, { method: "DELETE" });
    return { deleted: r.ok || r.status === 204 };
  }
  return { error: "unknown action" };
}

// ======================= iCloud (raw IMAP, no OAuth for Apple Mail) =======================
// ponytail: one connection per request, no pooling — Workers don't hold state between requests anyway.
class ImapClient {
  constructor(socket) {
    this.socket = socket;
    this.reader = socket.readable.getReader();
    this.writer = socket.writable.getWriter();
    this.buf = new Uint8Array(0);
    this.tag = 0;
  }
  async _fill() {
    const { value, done } = await this.reader.read();
    if (done) throw new Error("imap: connection closed");
    const merged = new Uint8Array(this.buf.length + value.length);
    merged.set(this.buf); merged.set(value, this.buf.length);
    this.buf = merged;
  }
  async readLine() {
    for (;;) {
      const nl = this.buf.indexOf(10);
      if (nl !== -1) {
        const line = this.buf.slice(0, nl);
        this.buf = this.buf.slice(nl + 1);
        return new TextDecoder().decode(line).replace(/\r$/, "");
      }
      await this._fill();
    }
  }
  async readBytes(n) {
    while (this.buf.length < n) await this._fill();
    const out = this.buf.slice(0, n);
    this.buf = this.buf.slice(n);
    return new TextDecoder().decode(out);
  }
  async cmd(text) {
    const tag = `a${++this.tag}`;
    await this.writer.write(new TextEncoder().encode(`${tag} ${text}\r\n`));
    const lines = [];
    for (;;) {
      const line = await this.readLine();
      const literal = line.match(/\{(\d+)\}\s*$/);
      if (literal) {
        lines.push(line);
        lines.push(await this.readBytes(Number(literal[1])));
        continue;
      }
      lines.push(line);
      if (line.startsWith(`${tag} `)) break;
    }
    const status = lines[lines.length - 1];
    if (!new RegExp(`^${tag} OK`, "i").test(status)) throw new Error(`imap ${text.split(" ")[0]} failed: ${status}`);
    return lines;
  }
  async quit() {
    try { await this.writer.write(new TextEncoder().encode("aq LOGOUT\r\n")); } catch {}
    await this.writer.close().catch(() => {});
  }
}

async function imapLogin(email, appPassword) {
  const socket = connect({ hostname: IMAP_HOST, port: IMAP_PORT }, { secureTransport: "on" });
  const client = new ImapClient(socket);
  await client.readLine(); // server greeting
  await client.cmd(`LOGIN ${JSON.stringify(email)} ${JSON.stringify(appPassword)}`);
  return client;
}

function parseImapHeaders(text) {
  const headers = [];
  for (const raw of text.split(/\r\n(?=\S)/)) {
    const m = raw.match(/^([^:]+):\s*([\s\S]*)$/);
    if (m) headers.push({ name: m[1].trim(), value: m[2].replace(/\r\n\s+/g, " ").trim() });
  }
  return headers;
}

async function icloudList(session) {
  const client = await imapLogin(session.email, session.appPassword);
  try {
    const selectLines = await client.cmd("SELECT INBOX");
    const exists = Number((selectLines.find((l) => / EXISTS$/.test(l)) || "0 0").split(" ")[1]) || 0;
    if (!exists) return [];
    const searchLines = await client.cmd("UID SEARCH ALL");
    const searchLine = searchLines.find((l) => l.startsWith("* SEARCH"));
    const uids = searchLine ? searchLine.replace("* SEARCH", "").trim().split(/\s+/).filter(Boolean) : [];
    const wanted = uids.slice(-30);
    if (!wanted.length) return [];
    const fetchLines = await client.cmd(`UID FETCH ${wanted.join(",")} (BODY.PEEK[HEADER.FIELDS (FROM SUBJECT REPLY-TO LIST-UNSUBSCRIBE LIST-UNSUBSCRIBE-POST)])`);
    const out = [];
    for (let i = 0; i < fetchLines.length; i++) {
      const m = fetchLines[i].match(/^\* \d+ FETCH \(UID (\d+)/);
      if (!m) continue;
      const headerText = fetchLines[i + 1] || "";
      const headers = parseImapHeaders(headerText);
      const from = header(headers, "From");
      const subject = header(headers, "Subject");
      const replyTo = header(headers, "Reply-To");
      const listUnsubscribe = header(headers, "List-Unsubscribe");
      const oneClick = /one-click/i.test(header(headers, "List-Unsubscribe-Post"));
      const { score, reasons, isJunk } = scoreMessage({ from, replyTo, subject, snippet: "", listUnsubscribe });
      const category = categorize({ from, subject, snippet: "", listUnsubscribe, isJunk });
      out.push({ id: m[1], from, subject, snippet: "", score, reasons, isJunk, category, listUnsubscribe, oneClick });
    }
    return out.reverse();
  } finally {
    await client.quit();
  }
}

async function icloudAction(session, { messageId, action, listUnsubscribe, oneClick }) {
  const client = await imapLogin(session.email, session.appPassword);
  try {
    await client.cmd("SELECT INBOX");
    if (action === "unsubscribe") {
      const ok = listUnsubscribe ? await unsubscribe(listUnsubscribe, oneClick) : false;
      const archived = await client.cmd(`UID MOVE ${messageId} Archive`).then(() => true, () => false);
      return { unsubscribed: ok, archived };
    }
    if (action === "archive") {
      await client.cmd(`UID MOVE ${messageId} Archive`);
      return { archived: true };
    }
    if (action === "delete") {
      await client.cmd(`UID STORE ${messageId} +FLAGS (\\Deleted)`);
      await client.cmd("EXPUNGE");
      return { deleted: true };
    }
    return { error: "unknown action" };
  } finally {
    await client.quit();
  }
}

async function icloudOrganize(session, items) {
  const groups = groupByFolder(items);
  const organized = {};
  let failed = 0;
  if (!Object.keys(groups).length) return { organized, failed };
  const client = await imapLogin(session.email, session.appPassword);
  try {
    await client.cmd("SELECT INBOX");
    for (const [folder, ids] of Object.entries(groups)) {
      const uids = ids.filter((id) => /^\d+$/.test(id));
      failed += ids.length - uids.length;
      if (!uids.length) continue;
      const mailbox = JSON.stringify(`${FOLDER_PARENT}/${folder}`);
      await client.cmd(`CREATE ${mailbox}`).catch(() => {}); // already there is fine
      const moved = await client.cmd(`UID MOVE ${uids.join(",")} ${mailbox}`).then(() => true, () => false);
      if (moved) organized[folder] = uids.length; else failed += uids.length;
    }
    return { organized, failed };
  } finally {
    await client.quit();
  }
}

// ======================= demo inbox =======================
// Sample mail for App Review and curious visitors: no Google or Apple account, no network calls.
// It goes through the same scoreMessage as a real inbox, so the triage you see is the real triage.
const DEMO_MAIL = [
  { id: "d1", from: "Apple <alerts@fakeapple-support.example>", replyTo: "help@mailer.example", subject: "Act now: verify your account", snippet: "Dear customer, your Apple ID will be suspended.", listUnsubscribe: "" },
  { id: "d2", from: "PayPal <service@paypa1-secure.example>", replyTo: "", subject: "Final notice: confirm your payment", snippet: "Dear member, click here to claim now.", listUnsubscribe: "" },
  { id: "d3", from: "DealDrop <hello@dealdrop.example>", replyTo: "", subject: "Limited time: 60% off everything", snippet: "Dear customer, shop the sale.", listUnsubscribe: "<https://dealdrop.example/u/1>", oneClick: true },
  { id: "d4", from: "DealDrop <hello@dealdrop.example>", replyTo: "", subject: "Last chance, sale ends today", snippet: "Dear customer, do not miss out.", listUnsubscribe: "<https://dealdrop.example/u/2>", oneClick: true },
  { id: "d5", from: "GitHub <noreply@github.com>", replyTo: "", subject: "[hagaki] Pull request merged", snippet: "Your pull request was merged into main.", listUnsubscribe: "" },
  { id: "d6", from: "Stripe <receipts@stripe.com>", replyTo: "", subject: "Your receipt from Acme", snippet: "Thanks for your payment.", listUnsubscribe: "" },
  { id: "d7", from: "Sam Rivera <sam@example.org>", replyTo: "", subject: "Lunch Thursday?", snippet: "Are you free around noon?", listUnsubscribe: "" },
  { id: "d8", from: "Air Canada <noreply@aircanada.com>", replyTo: "", subject: "Your boarding pass for YVR to NRT", snippet: "Check-in is open.", listUnsubscribe: "" },
  { id: "d9", from: "The Weekly Letter <hello@weekly.example>", replyTo: "", subject: "Issue 42: small tools", snippet: "This week: three small tools worth knowing.", listUnsubscribe: "<https://weekly.example/u>", oneClick: true },
  { id: "d10", from: "LinkedIn <notifications@linkedin.com>", replyTo: "", subject: "You appeared in 4 searches", snippet: "See who is looking.", listUnsubscribe: "" },
];

function demoList() {
  return DEMO_MAIL.map((m) => {
    const scored = scoreMessage(m);
    return { ...m, ...scored, category: categorize({ ...m, isJunk: scored.isJunk }), oneClick: !!m.oneClick };
  });
}

// --- LLM pass: whatever the rules left in the inbox gets one batched Workers AI call ---
// ponytail: one call, first 30 leftovers, fails open (rules result stands). Add paging if inboxes outgrow it.
const LLM_MODEL = "@cf/meta/llama-3.1-8b-instruct";
async function llmRefine(env, items) {
  const left = items.filter((m) => m.category === "Inbox").slice(0, 30);
  if (!env.AI || !left.length) return items;
  const list = left.map((m, i) => `${i}. from: ${m.from} | subject: ${m.subject} | ${(m.snippet || "").slice(0, 120)}`).join("\n");
  const prompt = `Sort each email into exactly one of: ${FOLDERS.join(", ")}, Inbox.
Inbox = a real person writing to the user personally (friends, family, a human reply). Cold sales outreach, growth-hack pitches, "saw your app" spam = Junk. Promo from a store = Promotions. Product or service system notices (support tickets, badges, 2FA) = Dev. Reply with only a JSON array like [{"i":0,"c":"Junk"}].
${list}`;
  try {
    const r = await env.AI.run(LLM_MODEL, { messages: [{ role: "user", content: prompt }], max_tokens: 800 });
    const picks = JSON.parse((String(r.response).match(/\[[\s\S]*\]/) || ["[]"])[0]);
    for (const { i, c } of picks) if (left[i] && FOLDERS.includes(c)) { left[i].category = c; left[i].llm = true; }
  } catch (e) { /* rules result stands */ }
  return items;
}

// ======================= dispatch =======================
function listMessages(session) {
  if (session.provider === "demo") return demoList();
  if (session.provider === "outlook") return outlookList(session);
  if (session.provider === "icloud") return icloudList(session);
  return gmailList(session);
}
function organizeMessages(session, items) {
  if (session.provider === "demo") {
    const organized = {};
    for (const [folder, ids] of Object.entries(groupByFolder(items))) organized[folder] = ids.length;
    return { demo: true, organized, failed: 0 };
  }
  if (session.provider === "outlook") return outlookOrganize(session, items);
  if (session.provider === "icloud") return icloudOrganize(session, items);
  return gmailOrganize(session, items);
}
function performAction(session, body) {
  if (body.action === "organize") return organizeMessages(session, [{ messageId: body.messageId, category: body.category }]);
  if (session.provider === "demo") return { demo: true, [body.action === "unsubscribe" ? "unsubscribed" : body.action === "delete" ? "deleted" : "archived"]: true };
  if (session.provider === "outlook") return outlookAction(session, body);
  if (session.provider === "icloud") return icloudAction(session, body);
  return gmailAction(session, body);
}

export default {
  async fetch(request, env) {
    const { pathname, searchParams } = new URL(request.url);

    // --- OAuth: Gmail web flow (confidential client, redirect to /auth/callback/google with a session cookie) ---
    if (pathname === "/auth/start") {
      const url = new URL(GOOGLE_AUTH);
      url.searchParams.set("client_id", env.GOOGLE_OAUTH_CLIENT_ID);
      url.searchParams.set("redirect_uri", GOOGLE_REDIRECT);
      url.searchParams.set("response_type", "code");
      url.searchParams.set("scope", GMAIL_SCOPE);
      url.searchParams.set("access_type", "offline");
      url.searchParams.set("prompt", "consent");
      return Response.redirect(url.toString(), 302);
    }

    // --- OAuth: Outlook web flow ---
    if (pathname === "/auth/start/outlook") {
      const url = new URL(MS_AUTH);
      url.searchParams.set("client_id", env.MS_OAUTH_CLIENT_ID);
      url.searchParams.set("redirect_uri", MS_REDIRECT);
      url.searchParams.set("response_type", "code");
      url.searchParams.set("response_mode", "query");
      url.searchParams.set("scope", MS_SCOPE);
      return Response.redirect(url.toString(), 302);
    }

    if (pathname === "/auth/callback" && !searchParams.has("native")) {
      const code = searchParams.get("code");
      if (!code) return new Response("missing code", { status: 400 });
      const body = new URLSearchParams({
        code, client_id: env.GOOGLE_OAUTH_CLIENT_ID, client_secret: env.GOOGLE_CLIENT_SECRET,
        redirect_uri: GOOGLE_REDIRECT, grant_type: "authorization_code",
      });
      const tokRes = await fetch(GOOGLE_TOKEN, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body });
      if (!tokRes.ok) return new Response("token exchange failed", { status: 502 });
      const tok = await tokRes.json();
      const id = crypto.randomUUID();
      await putSession(env, id, {
        provider: "gmail",
        access_token: tok.access_token, refresh_token: tok.refresh_token,
        expires_at: Date.now() + tok.expires_in * 1000,
        client_id: env.GOOGLE_OAUTH_CLIENT_ID, client_secret: env.GOOGLE_CLIENT_SECRET,
      });
      return new Response(null, {
        status: 302,
        headers: { Location: "/?connected=1", "Set-Cookie": `sieve_session=${id}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=2592000` },
      });
    }

    if (pathname === "/auth/callback/outlook" && !searchParams.has("native")) {
      const code = searchParams.get("code");
      if (!code) return new Response("missing code", { status: 400 });
      const body = new URLSearchParams({
        code, client_id: env.MS_OAUTH_CLIENT_ID, client_secret: env.MS_CLIENT_SECRET,
        redirect_uri: MS_REDIRECT, grant_type: "authorization_code", scope: MS_SCOPE,
      });
      const tokRes = await fetch(MS_TOKEN, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body });
      if (!tokRes.ok) return new Response("token exchange failed", { status: 502 });
      const tok = await tokRes.json();
      const id = crypto.randomUUID();
      await putSession(env, id, {
        provider: "outlook",
        access_token: tok.access_token, refresh_token: tok.refresh_token,
        expires_at: Date.now() + tok.expires_in * 1000,
        client_id: env.MS_OAUTH_CLIENT_ID, client_secret: env.MS_CLIENT_SECRET,
      });
      return new Response(null, {
        status: 302,
        headers: { Location: "/?connected=1", "Set-Cookie": `sieve_session=${id}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=2592000` },
      });
    }

    // Native (iOS/macOS) PKCE flow: app exchanges the code itself against Google/Microsoft (public client,
    // no secret needed), then hands sieve the resulting tokens to mint a session it can hand back
    // as a bearer token — same session store, same /api/* routes as the web app.
    if (pathname === "/auth/native" && request.method === "POST") {
      const { access_token, refresh_token, expires_in, client_id, provider } = await request.json();
      if (!access_token || !refresh_token) return new Response("missing tokens", { status: 400 });
      const id = crypto.randomUUID();
      await putSession(env, id, { provider: provider === "outlook" ? "outlook" : "gmail", access_token, refresh_token, expires_at: Date.now() + expires_in * 1000, client_id });
      return Response.json({ token: id });
    }

    // iCloud (and any IMAP+app-password provider): no OAuth exists, so the form posts the
    // email + app-specific password directly. We verify by logging in once before storing.
    if (pathname === "/auth/icloud" && request.method === "POST") {
      const { email, appPassword } = await request.json();
      if (!email || !appPassword) return new Response("missing email or app password", { status: 400 });
      try {
        const client = await imapLogin(email, appPassword);
        await client.quit();
      } catch (e) {
        return new Response(`icloud login failed: ${e}`, { status: 401 });
      }
      const id = crypto.randomUUID();
      await putSession(env, id, { provider: "icloud", email, appPassword });
      return Response.json({ token: id });
    }

    // Demo inbox: a session that never touches Google or Apple. Nothing real can be changed.
    if (pathname === "/auth/demo" && request.method === "POST") {
      const id = crypto.randomUUID();
      await putSession(env, id, { provider: "demo" });
      return Response.json({ token: id });
    }

    if (pathname === "/auth/logout") {
      const id = sessionIdFromRequest(request);
      if (id) await env.SESSIONS.delete(`sess:${id}`);
      return new Response(null, { status: 302, headers: { Location: "/", "Set-Cookie": "sieve_session=; Path=/; Max-Age=0" } });
    }

    // --- mail API, session-gated ---
    if (pathname === "/api/messages" && request.method === "GET") {
      const id = sessionIdFromRequest(request);
      let session = await getSession(env, id);
      if (!session) return new Response("not connected", { status: 401 });
      session = await refreshIfNeeded(env, id, session);
      if (!session) return new Response("session expired", { status: 401 });
      try {
        return Response.json(await llmRefine(env, await listMessages(session)));
      } catch (e) {
        return new Response(String(e), { status: 502 });
      }
    }

    if (pathname === "/api/action" && request.method === "POST") {
      const id = sessionIdFromRequest(request);
      let session = await getSession(env, id);
      if (!session) return new Response("not connected", { status: 401 });
      session = await refreshIfNeeded(env, id, session);
      if (!session) return new Response("session expired", { status: 401 });
      const body = await request.json();
      try {
        return Response.json(await performAction(session, body));
      } catch (e) {
        return new Response(String(e), { status: 502 });
      }
    }

    // bulk: file every message into its smart folder in one pass
    if (pathname === "/api/organize" && request.method === "POST") {
      const id = sessionIdFromRequest(request);
      let session = await getSession(env, id);
      if (!session) return new Response("not connected", { status: 401 });
      session = await refreshIfNeeded(env, id, session);
      if (!session) return new Response("session expired", { status: 401 });
      const { items } = await request.json();
      try {
        return Response.json(await organizeMessages(session, items));
      } catch (e) {
        return new Response(String(e), { status: 502 });
      }
    }

    // --- run history (skill-reported dry-run/apply summaries) ---
    if (pathname === "/api/runs" && request.method === "GET") {
      return Response.json((await env.RUNS.get(RUNS_KEY, "json")) || []);
    }
    if (pathname === "/api/runs" && request.method === "POST") {
      if (request.headers.get("Authorization") !== `Bearer ${env.RUN_TOKEN}`) return new Response("unauthorized", { status: 401 });
      const body = await request.json();
      const run = {
        at: new Date().toISOString(),
        mode: body.mode === "apply" ? "apply" : "dry-run",
        filed: body.filed | 0, fixed: body.fixed | 0, unsubscribed: body.unsubscribed | 0, archived: body.archived | 0,
      };
      const runs = [run, ...((await env.RUNS.get(RUNS_KEY, "json")) || [])].slice(0, MAX_RUNS);
      await env.RUNS.put(RUNS_KEY, JSON.stringify(runs));
      return Response.json(run, { status: 201 });
    }

    return env.ASSETS.fetch(request);
  },
};
