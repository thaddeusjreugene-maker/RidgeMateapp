// Ridgeline Teams — "push" Edge Function.
// Sends the notifications queued in push_outbox to every phone/computer that turned them on.
// Paste this whole file into Supabase → Edge Functions → Deploy a new function → Via Editor,
// name it  push , and turn OFF "Verify JWT". It makes its own sending keys the first time it runs.
// No imports and no secrets to set: it uses the project URL and service key Supabase provides.

const SB_URL = (Deno.env.get('SUPABASE_URL') || '').replace(/\/$/, '');
// Server keys Supabase gives every function: the new secret key(s) and/or the legacy service_role key.
const SB_KEYS: string[] = (() => {
  const out: string[] = [];
  try { const j = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}'); for (const v of Object.values(j)) if (typeof v === 'string' && v) out.push(v); } catch (_) { /* not set */ }
  for (const k of ['SUPABASE_SERVICE_ROLE_KEY', 'SERVICE_ROLE_KEY']) { const v = Deno.env.get(k); if (v && !out.includes(v)) out.push(v); }
  return out;
})();
let SB_KEY = SB_KEYS[0] || '';
const FN_URL = SB_URL + '/functions/v1/push';
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*', 'Access-Control-Allow-Methods': 'GET, POST, OPTIONS' };

// ---------- small helpers ----------
const te = new TextEncoder();
const b64u = (buf: ArrayBuffer | Uint8Array) => {
  const b = buf instanceof Uint8Array ? buf : new Uint8Array(buf); let s = '';
  for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};
const unb64u = (s: string) => {
  s = s.replace(/-/g, '+').replace(/_/g, '/'); while (s.length % 4) s += '=';
  const bin = atob(s); const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i); return out;
};
const cat = (...parts: Uint8Array[]) => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0)); let o = 0;
  for (const p of parts) { out.set(p, o); o += p.length; } return out;
};
async function hmac(key: Uint8Array, data: Uint8Array) {
  const k = await crypto.subtle.importKey('raw', key, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return new Uint8Array(await crypto.subtle.sign('HMAC', k, data));
}

// ---------- database (PostgREST with the service key) ----------
async function rpc(fn: string, args: Record<string, unknown>) {
  const call = (key: string) => {
    const h: Record<string, string> = { apikey: key, 'Content-Type': 'application/json' };
    if (key.startsWith('eyJ')) h.Authorization = 'Bearer ' + key;
    return fetch(`${SB_URL}/rest/v1/rpc/${fn}`, { method: 'POST', headers: h, body: JSON.stringify(args) });
  };
  let r = await call(SB_KEY);
  if (r.status === 401 || r.status === 403) for (const k of SB_KEYS) if (k !== SB_KEY) { const r2 = await call(k); if (r2.status !== 401 && r2.status !== 403) { SB_KEY = k; r = r2; break; } }
  const t = await r.text();
  if (!r.ok) throw new Error(`${fn}: ${r.status} ${t.slice(0, 300)}`);
  return t ? JSON.parse(t) : null;
}

// ---------- VAPID keys (made once, stored in push_keys) ----------
type Keys = { public_key: string; private_jwk: JsonWebKey; fn_url: string };
async function makeKeys() {
  const kp = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']) as CryptoKeyPair;
  const pub = new Uint8Array(await crypto.subtle.exportKey('raw', kp.publicKey));
  const jwk = await crypto.subtle.exportKey('jwk', kp.privateKey);
  return { pub: b64u(pub), jwk };
}
async function ensureKeys(): Promise<Keys> {
  try { return await rpc('push_init', { p_public: null, p_private: null, p_url: FN_URL }); }
  catch (e) {
    if (!String((e as Error).message).includes('no keys')) throw e;
    const k = await makeKeys();
    return await rpc('push_init', { p_public: k.pub, p_private: k.jwk, p_url: FN_URL });
  }
}

// ---------- Web Push: VAPID header + aes128gcm body (RFC 8291 / 8292) ----------
const jwtCache = new Map<string, { h: string; exp: number }>();
export async function vapidHeader(endpoint: string, keys: Keys, subject: string) {
  const aud = new URL(endpoint).origin; const now = Math.floor(Date.now() / 1000);
  const hit = jwtCache.get(aud); if (hit && hit.exp - now > 600) return hit.h;
  const exp = now + 12 * 3600;
  const head = b64u(te.encode(JSON.stringify({ typ: 'JWT', alg: 'ES256' })));
  const body = b64u(te.encode(JSON.stringify({ aud, exp, sub: subject })));
  const key = await crypto.subtle.importKey('jwk', { ...keys.private_jwk, key_ops: ['sign'], ext: true }, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, te.encode(head + '.' + body)));
  const h = `vapid t=${head}.${body}.${b64u(sig)}, k=${keys.public_key}`;
  jwtCache.set(aud, { h, exp }); return h;
}
export async function encrypt(payload: Uint8Array, p256dh: string, authSecret: string) {
  const uaPub = unb64u(p256dh), auth = unb64u(authSecret);
  const eph = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']) as CryptoKeyPair;
  const asPub = new Uint8Array(await crypto.subtle.exportKey('raw', eph.publicKey));
  const uaKey = await crypto.subtle.importKey('raw', uaPub, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: uaKey }, eph.privateKey, 256));
  const prkKey = await hmac(auth, shared);
  const ikm = (await hmac(prkKey, cat(te.encode('WebPush: info\0'), uaPub, asPub, new Uint8Array([1])))).slice(0, 32);
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const prk = await hmac(salt, ikm);
  const cek = (await hmac(prk, cat(te.encode('Content-Encoding: aes128gcm\0'), new Uint8Array([1])))).slice(0, 16);
  const nonce = (await hmac(prk, cat(te.encode('Content-Encoding: nonce\0'), new Uint8Array([1])))).slice(0, 12);
  const k = await crypto.subtle.importKey('raw', cek, 'AES-GCM', false, ['encrypt']);
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, k, cat(payload, new Uint8Array([2]))));
  const rs = new Uint8Array([0, 0, 16, 0]); // record size 4096
  return cat(salt, rs, new Uint8Array([asPub.length]), asPub, ct);
}
type Sub = { endpoint: string; user_id: string; p256dh: string; auth: string; prefs: Record<string, unknown> };
export async function sendOne(sub: Sub, msg: unknown, keys: Keys, subject: string) {
  const body = await encrypt(te.encode(JSON.stringify(msg)), sub.p256dh, sub.auth);
  const r = await fetch(sub.endpoint, { method: 'POST', body, headers: {
    Authorization: await vapidHeader(sub.endpoint, keys, subject),
    'Content-Encoding': 'aes128gcm', 'Content-Type': 'application/octet-stream', TTL: '86400', Urgency: 'high' } });
  const text = r.ok ? '' : (await r.text()).slice(0, 200);
  return { status: r.status, text };
}

// ---------- group the queue so a bulk import doesn't buzz someone 50 times ----------
type Row = { id: number; user_id: string; kind: string; title: string; body: string; url: string; tag: string };
export function group(rows: Row[]) {
  const g = new Map<string, Row[]>();
  for (const r of [...rows].sort((a, b) => a.id - b.id)) {
    const key = r.user_id + '|' + (['board', 'assigned'].includes(r.kind) ? r.kind : (r.tag || 'id' + r.id));
    if (!g.has(key)) g.set(key, []); g.get(key)!.push(r);
  }
  const out: (Row & { n: number })[] = [];
  for (const list of g.values()) {
    const last = list[list.length - 1], n = list.length;
    if (n === 1) { out.push({ ...last, n }); continue; }
    if (last.kind === 'board') out.push({ ...last, n, title: `${n} new open leads`, body: `${list[0].body} and ${n - 1} more`, url: './#board', tag: 'board' });
    else if (last.kind === 'assigned') out.push({ ...last, n, title: `${n} leads assigned to you`, body: `${list[0].body.split(' · from ')[0]} and ${n - 1} more`, url: './#leads', tag: 'assigned' });
    else out.push({ ...last, n, body: last.body + ` (+${n - 1} more)` });
  }
  return out;
}

async function drain(keys: Keys) {
  const subject = Deno.env.get('VAPID_SUBJECT') || SB_URL || 'mailto:support@ridgeline.app';
  let sent = 0, failed = 0, dropped = 0; const errors: string[] = [];
  for (let round = 0; round < 5; round++) {
    const rows: Row[] = await rpc('push_claim', { p_limit: 200 });
    if (!rows || !rows.length) break;
    const users = [...new Set(rows.map(r => r.user_id))];
    const subs: Sub[] = await rpc('push_targets', { p_users: users }) || [];
    const dead: string[] = []; const jobs: Promise<void>[] = [];
    for (const m of group(rows)) for (const s of subs.filter(x => x.user_id === m.user_id && (x.prefs || {})[m.kind] !== false)) {
      jobs.push(sendOne(s, { title: m.title, body: m.body, url: m.url, tag: m.tag, kind: m.kind }, keys, subject).then(r => {
        if (r.status >= 200 && r.status < 300) sent++;
        else { failed++; if (r.status === 404 || r.status === 410) dead.push(s.endpoint); else if (errors.length < 5) errors.push(`${r.status} ${r.text}`); }
      }).catch(e => { failed++; if (errors.length < 5) errors.push(String(e?.message || e)); }));
    }
    await Promise.all(jobs);
    if (dead.length) { await rpc('push_drop', { p_endpoints: dead }); dropped += dead.length; }
    if (rows.length < 200) break;
  }
  return { sent, failed, dropped, errors };
}

const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

if (typeof Deno !== 'undefined' && Deno.serve) Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  try {
    if (!SB_URL || !SB_KEY) return json({ ok: false, error: 'Missing SUPABASE_URL / service key in the function environment' }, 500);
    const keys = await ensureKeys();
    if (new URL(req.url).searchParams.has('key')) return json({ ok: true, publicKey: keys.public_key });
    return json({ ok: true, ...(await drain(keys)) });
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message || e) }, 500);
  }
});
