// Demo backend: a pretend roofing company stored on this device, so the app can be
// tried (and shown off) without any setup. Switch who you're "signed in" as from Settings.
import { toRow, fromRow } from './shape.js';

const KEY = 'ridgeline-teams.demo.v1';
const WS = '00000000-0000-4000-8000-000000000001';
export const DEMO_USERS = [
  { user_id: 'u-jordan', display_name: 'Jordan Price', role: 'owner', title: 'Director of Sales' },
  { user_id: 'u-marcus', display_name: 'Marcus Hill', role: 'rep' },
  { user_id: 'u-dana',   display_name: 'Dana Cole', role: 'rep' },
  { user_id: 'u-tyler',  display_name: 'Tyler Reed', role: 'rep' },
  { user_id: 'u-kim',    display_name: 'Kim Alvarez', role: 'office' }
];
const uuid = () => (crypto.randomUUID ? crypto.randomUUID() : 'x' + Math.random().toString(16).slice(2) + Date.now().toString(16));
const now = () => new Date().toISOString();
const day = 864e5;

function seed(){
  const T = Date.now(), base = { lat: 34.7204, lng: -80.7709 };
  const streets = [
    { name: 'Barr St',    a: [34.7230, -80.7790], b: [34.7230, -80.7660] },
    { name: 'Arch St',    a: [34.7205, -80.7790], b: [34.7205, -80.7660] },
    { name: 'Dunlap St',  a: [34.7180, -80.7790], b: [34.7180, -80.7660] },
    { name: 'Catawba St', a: [34.7260, -80.7745], b: [34.7150, -80.7745] }
  ];
  const reps = ['u-marcus', 'u-dana', 'u-tyler'];
  const statuses = ['Not Home','Not Home','Not Home','Not Interested','Follow Up','Be Back','Inspection Scheduled','Inspected','No Damage','Claim Pending','Sold'];
  const names = ['R. Owens','T. Brooks','L. Sims','J. Carter','M. Ford','D. Neal','A. Price','K. Moore','B. Ellis','S. Grant','P. Lane','C. Hart'];
  const leads = []; let n = 0;
  streets.forEach((st, si) => {
    for (let i = 0; i < 12; i++){
      const t = (i + .5) / 12, side = i % 2 ? 1 : -1;
      const lat = st.a[0] + (st.b[0] - st.a[0]) * t + (st.name === 'Catawba St' ? 0 : side * .00018);
      const lng = st.a[1] + (st.b[1] - st.a[1]) * t + (st.name === 'Catawba St' ? side * .00022 : 0);
      const owner = reps[(si + Math.floor(i / 4)) % 3];
      const status = statuses[(i * 7 + si * 3) % statuses.length];
      const ago = ((i * 5 + si * 3) % 13) * day + 3600e3 * (9 + (i % 7));
      const knocks = [{ t: T - ago, r: 'Not Home', d: 1, by: owner, gps: { lat: lat + .00004, lng: lng - .00003 } }];
      if (['Sold','Claim Pending','No Damage','Cancelled','Finance Denied'].includes(status)) knocks.push({ t: T - ago + day * .4, r: 'Inspected', d: 1, by: owner, gps: { lat, lng } });
      if (status !== 'Not Home') knocks.push({ t: T - ago + day * .8, r: status, d: 1, by: owner, gps: { lat, lng } });
      const id = 'lead-demo' + (n++);
      const l = {
        id, workspace_id: WS, owner_id: owner, created_by: owner, origin: 'self', pool: false, status,
        num: String(100 + i * 4 + (side > 0 ? 2 : 1)), street: st.name, city: 'Lancaster, SC',
        name: status === 'Not Home' ? '' : names[(i + si) % names.length], phone: status === 'Not Home' ? '' : '(803) 555-0' + (100 + n),
        geo: { lat, lng }, pinned_lat: knocks[0].gps.lat, pinned_lng: knocks[0].gps.lng,
        followAt: ['Follow Up','Be Back','Inspection Scheduled'].includes(status) ? new Date(T + ((i % 5) - 1) * day * .7).toISOString().slice(0, 16) : '',
        knocks, log: [], fuDone: [], roof: {}, ins: {}, storms: [], findings: '', photos: [], docs: [],
        sale: { type: 'Insurance', value: '', upgrades: '', supplements: '', rate: '', commOverride: '', cstatus: 'none', paidAt: '', soldAt: '', stage: '' },
        est: { lines: [], notes: '', sig: null, sigName: '', sigAt: '' },
        created: T - ago, updated: T - ago + day, protected_until: new Date(T - ago + 30 * day).toISOString()
      };
      if (status === 'Sold'){
        const v = 9800 + ((i * 1733 + si * 911) % 9000);
        l.sale = { ...l.sale, value: String(v), upgrades: String((i % 3) * 400), supplements: String((si % 2) * 1100), soldAt: new Date(T - ((i + si) % 9) * day).toISOString().slice(0, 10), cstatus: (i + si) % 3 ? 'pending' : 'paid', paidAt: (i + si) % 3 ? '' : new Date(T - 2 * day).toISOString().slice(0, 10), stage: (i + si) % 3 ? 'Claim filed' : 'Final check paid' };
      }
      leads.push(toRow(WS, l));
      leads.at(-1).created_at = new Date(l.created).toISOString();
    }
  });
  const posted = [
    { num: '412', street: 'Meadow Creek Rd', city: 'Lancaster, SC', name: 'Gloria Banks', phone: '(803) 555-0177', lat: 34.7290, lng: -80.7620, job: 'Storm damage', insurance: true, window: 'Tomorrow morning', source: 'Phone call', notes: 'Shingles in the yard after Tuesday storm' },
    { num: '88', street: 'Hilltop Dr', city: 'Lancaster, SC', name: 'Ray Whitfield', phone: '(803) 555-0142', lat: 34.7135, lng: -80.7820, job: 'Leak', insurance: false, window: 'Today after 4 PM', source: 'Website', notes: 'Ceiling stain in back bedroom' },
    { num: '2201', street: 'Flat Creek Rd', city: 'Lancaster, SC', name: 'Nora Pate', phone: '(803) 555-0119', lat: 34.7342, lng: -80.7555, job: 'Inspection', insurance: true, window: 'Any weekday', source: 'Referral', notes: 'Neighbor of Owens job' }
  ].map((p, i) => {
    const l = { id: 'lead-open' + i, owner_id: null, created_by: 'u-kim', origin: 'company', pool: true, posted_by: 'u-kim', posted_at: new Date(T - (i + 1) * 3600e3 * 2).toISOString(),
      status: 'Inspection Scheduled', num: p.num, street: p.street, city: p.city, name: p.name, phone: p.phone, geo: { lat: p.lat, lng: p.lng },
      post: { job: p.job, insurance: p.insurance, window: p.window, source: p.source, public_notes: p.notes }, knocks: [{ t: T - (i + 1) * 7200e3, r: 'Posted', by: 'u-kim' }],
      log: [], roof: {}, ins: {}, storms: [], photos: [], docs: [], sale: { type: p.insurance ? 'Insurance' : 'Retail', value: '', upgrades: '', supplements: '', rate: '', commOverride: '', cstatus: 'none', paidAt: '', soldAt: '', stage: '' }, est: { lines: [], notes: '', sig: null, sigName: '', sigAt: '' }, updated: T };
    const r = toRow(WS, l); r.created_at = l.posted_at; return r;
  });
  const feed = [
    { user_id: 'u-dana', kind: 'sale', body: 'closed a $16,400 insurance job on Arch St', amount: 16400, ago: 5 },
    { user_id: 'u-marcus', kind: 'streak', body: 'hit a 7-day streak', ago: 20 },
    { user_id: 'u-jordan', kind: 'post', body: 'Team passed 300 doors this month. Let’s get to 500 before Thanksgiving.', ago: 30 },
    { user_id: 'u-tyler', kind: 'milestone', body: 'logged his first sale', ago: 50 }
  ].map(f => ({ id: uuid(), workspace_id: WS, user_id: f.user_id, kind: f.kind, body: f.body, amount: f.amount ?? null, created_at: new Date(T - f.ago * 3600e3).toISOString() }));
  const reactions = [{ feed_id: feed[0].id, user_id: 'u-marcus', emoji: '🔥' }, { feed_id: feed[0].id, user_id: 'u-jordan', emoji: '👊' }, { feed_id: feed[3].id, user_id: 'u-dana', emoji: '🙌' }];
  const msg = (channel, thread, sender, body, ago, extra = {}) => ({ id: uuid(), workspace_id: WS, channel, thread, participants: [], lead_id: null, sender_id: sender, body, image_path: null, created_at: new Date(T - ago * 60e3).toISOString(), ...extra });
  const dmMD = 'dm:u-dana:u-marcus';
  const messages = [
    msg('announce', 'announce', 'u-jordan', 'Hail came through east Lancaster Tuesday. Focus on Barr, Arch and Catawba this week. Office will post call-ins on the Open Leads board.', 600),
    msg('team', 'team', 'u-marcus', 'Anybody near Flat Creek? Got a callback I can’t make till 6.', 140),
    msg('team', 'team', 'u-dana', 'I’m 5 min out, I can swing by.', 132),
    msg('team', 'team', 'u-tyler', 'Arch St is hot today, 3 inspections set 🔥', 45),
    msg('dm', dmMD, 'u-marcus', 'Thanks for covering earlier', 120, { participants: ['u-dana', 'u-marcus'] }),
    msg('dm', dmMD, 'u-dana', 'Anytime 👊', 118, { participants: ['u-dana', 'u-marcus'] }),
    msg('lead', 'lead:lead-demo10', 'u-kim', 'Adjuster meeting confirmed for Thursday 10 AM.', 300, { lead_id: 'lead-demo10' })
  ];
  const territories = [
    { id: uuid(), workspace_id: WS, name: 'East side', color: '#2F6BFF', points: [[34.7275, -80.7700], [34.7275, -80.7640], [34.7140, -80.7640], [34.7140, -80.7700]], rep_ids: ['u-marcus', 'u-dana'], created_at: now() },
    { id: uuid(), workspace_id: WS, name: 'West side', color: '#12A150', points: [[34.7275, -80.7800], [34.7275, -80.7710], [34.7140, -80.7710], [34.7140, -80.7800]], rep_ids: ['u-tyler'], created_at: now() }
  ];
  const skip_zones = [
    { id: uuid(), workspace_id: WS, name: 'Brookstone (re-roofed 2025)', reason: 'New roofs', note: 'Whole subdivision replaced after the April 2025 hail.', points: [[34.7262, -80.7752], [34.7262, -80.7722], [34.7238, -80.7722], [34.7238, -80.7752]], created_by: 'u-marcus', created_at: now() }
  ];
  return {
    me: 'u-jordan',
    workspaces: [{ id: WS, name: 'Demo Roofing Co', kind: 'company', owner_id: 'u-jordan', created_at: now(), settings: {
      rates: { self: { Insurance: 10, Retail: 10, Repair: 10 }, company: { Insurance: 7, Retail: 7, Repair: 7 } },
      claim_deadline_hours: 2, claim_cap: 3, protect_days: 30, teammate_pins: true, leaderboards: true, goal: 6000,
      team_goal: { label: 'Doors in November', metric: 'doors', target: 500 },
      terms: 'By signing, the homeowner agrees to have the contractor perform the work listed above at the stated price, subject to insurance approval where marked Insurance. This agreement may be cancelled in writing within 3 business days.' } }],
    members: DEMO_USERS.map(u => ({ workspace_id: WS, user_id: u.user_id, role: u.role, display_name: u.display_name, phone: '', active: true, prefs: {}, joined_at: now() })),
    invites: [], leads: [...leads, ...posted], feed, reactions, messages, reads: [], reports: [], blocks: [], territories, skip_zones, sessions: []
  };
}

export function demoApi(){
  let db;
  try { db = JSON.parse(localStorage.getItem(KEY) || 'null'); } catch (e) {}
  if (!db) db = seed();
  const persist = () => { try { localStorage.setItem(KEY, JSON.stringify(db)); } catch (e) {} };
  persist();
  const listeners = new Set();
  const emit = (type, payload) => listeners.forEach(h => { if (type === 'message' && h.onMessage) h.onMessage(payload); if (type === 'feed' && h.onFeed) h.onFeed(); });
  const role = ws => (db.members.find(m => m.workspace_id === ws && m.user_id === db.me && m.active) || {}).role;
  const viewAll = ws => ['owner', 'manager', 'office'].includes(role(ws));
  const isMgr = ws => ['owner', 'manager'].includes(role(ws));
  const settings = ws => (db.workspaces.find(w => w.id === ws) || {}).settings || {};
  const knockAppend = (r, entry) => { r.data = r.data || {}; r.data.knocks = [...(r.data.knocks || []), { t: Date.now(), ...entry }]; };
  const canSeeLead = id => { const l = db.leads.find(x => x.id === id); return !!l && (viewAll(l.workspace_id) || l.owner_id === db.me); };
  const files = {};
  const wait = (v) => new Promise(r => setTimeout(() => r(v), 60));

  const api = {
    mode: 'demo', users: DEMO_USERS,
    switchUser(u){ db.me = u; persist(); },
    reset(){ localStorage.removeItem(KEY); db = seed(); persist(); },
    async session(){ return { user: { id: db.me, email: db.me.replace('u-', '') + '@demo.roofing' } }; },
    async sendCode(){}, async verifyCode(){ return this.session(); }, async signOut(){}, onAuthChange(){},
    me(){ return db.me; },

    async workspaces(){ return wait(db.workspaces.filter(w => role(w.id)).map(w => ({ ...w, role: role(w.id) }))); },
    async createWorkspace(name, kind, displayName){ const id = uuid(); db.workspaces.push({ id, name, kind, owner_id: db.me, settings: { ...settings(WS), team_goal: null }, created_at: now() }); db.members.push({ workspace_id: id, user_id: db.me, role: 'owner', display_name: displayName, phone: '', active: true, prefs: {}, joined_at: now() }); persist(); return id; },
    async joinWorkspace(code, displayName){ const inv = db.invites.find(i => i.code === code.trim().toUpperCase()); if (!inv) throw new Error('That invite code is not valid'); if (!db.members.find(m => m.workspace_id === inv.workspace_id && m.user_id === db.me)) db.members.push({ workspace_id: inv.workspace_id, user_id: db.me, role: inv.role, display_name: displayName, phone: '', active: true, prefs: {}, joined_at: now() }); persist(); return inv.workspace_id; },
    async updateWorkspace(ws, patch){ if (!isMgr(ws)) throw new Error('Only managers can change company settings'); Object.assign(db.workspaces.find(w => w.id === ws), patch); persist(); },
    async members(ws){ return wait(db.members.filter(m => m.workspace_id === ws).map(m => ({ ...m }))); },
    async updateMember(ws, user, patch){ if (!isMgr(ws) && user !== db.me) throw new Error('Not allowed'); const m = db.members.find(x => x.workspace_id === ws && x.user_id === user); if (m.role === 'owner' && patch.role && patch.role !== 'owner') throw new Error('The owner can’t be changed'); Object.assign(m, patch); persist(); },
    async createInvite(ws, r){ if (!isMgr(ws)) throw new Error('Only managers can invite'); const code = Math.random().toString(36).slice(2, 8).toUpperCase(); db.invites.push({ code, workspace_id: ws, role: r }); persist(); return code; },

    async listLeads(ws){ return wait(db.leads.filter(r => r.workspace_id === ws && (viewAll(ws) || r.owner_id === db.me)).map(r => fromRow(JSON.parse(JSON.stringify(r))))); },
    async saveLead(ws, l){
      const row = toRow(ws, l); const i = db.leads.findIndex(r => r.id === l.id);
      if (i < 0){ row.created_at = new Date(l.created || Date.now()).toISOString(); db.leads.push(row); l._saved = true; }
      else { const cur = db.leads[i]; if (!(isMgr(ws) || cur.owner_id === db.me)) throw new Error('This lead belongs to someone else'); db.leads[i] = { ...cur, ...row, created_by: cur.created_by, pool: cur.pool, posted_by: cur.posted_by, posted_at: cur.posted_at, claimed_at: cur.claimed_at }; }
      persist();
    },
    async deleteLead(ws, id){ db.leads = db.leads.filter(r => r.id !== id); persist(); },
    async teamPins(ws){
      const all = viewAll(ws), show = settings(ws).teammate_pins !== false;
      return wait(db.leads.filter(r => r.workspace_id === ws && r.lat != null && !r.pool && (show || all || r.owner_id === db.me))
        .map(r => ({ id: r.id, owner_id: r.owner_id, created_by: r.created_by, status: r.status, lat: r.lat, lng: r.lng, num: all || r.owner_id === db.me ? r.num : '', street: r.street, protected_until: r.protected_until, created_at: r.created_at, updated_at: r.updated_at, pinned_lat: all ? r.data?.pinned_lat : null, pinned_lng: all ? r.data?.pinned_lng : null })));
    },
    async pinHistory(id){ const r = db.leads.find(x => x.id === id); if (!r) return null; const full = viewAll(r.workspace_id) || r.owner_id === db.me; return { created_by: r.created_by, created_at: r.created_at, owner_id: r.owner_id, knocks: (r.data?.knocks || []).map(k => full ? k : (({ gps, ...rest }) => rest)(k)) }; },
    async openLeads(ws){ return wait(db.leads.filter(r => r.workspace_id === ws && r.pool && !r.owner_id).sort((a, b) => (b.posted_at || '').localeCompare(a.posted_at || '')).map(r => ({ id: r.id, street: r.street, city: r.city, lat: Math.round(r.lat * 1000) / 1000, lng: Math.round(r.lng * 1000) / 1000, job: r.data?.post?.job || '', insurance: !!r.data?.post?.insurance, window_text: r.data?.post?.window || '', source: r.data?.post?.source || '', notes: r.data?.post?.public_notes || '', posted_at: r.posted_at, posted_by: r.posted_by }))); },
    async postOpenLead(ws, l){ if (!viewAll(ws)) throw new Error('Only the office or a manager can post leads'); Object.assign(l, { owner_id: null, pool: true, origin: 'company', posted_by: db.me, posted_at: now(), created_by: db.me }); const r = toRow(ws, l); r.created_at = now(); db.leads.push(r); l._saved = true; persist(); },
    async claimLead(id){
      const r = db.leads.find(x => x.id === id); if (!r) throw new Error('Lead not found');
      if (!r.pool || r.owner_id) return 'taken';
      const held = db.leads.filter(x => x.workspace_id === r.workspace_id && x.owner_id === db.me && x.origin === 'company' && !x.contacted_at && x.claimed_at).length;
      if (held >= (settings(r.workspace_id).claim_cap || 3)) return 'cap';
      Object.assign(r, { owner_id: db.me, pool: false, claimed_at: now(), status: 'Inspection Scheduled', updated_at: now() }); knockAppend(r, { r: 'Claimed', by: db.me }); persist(); return 'ok';
    },
    async releaseLead(id, reason){ const r = db.leads.find(x => x.id === id); if (r.owner_id !== db.me) throw new Error('Not your lead'); Object.assign(r, { owner_id: null, pool: true, claimed_at: null, contacted_at: null }); knockAppend(r, { r: 'Released', by: db.me, note: reason || '' }); persist(); },
    async assignLead(id, user){ const r = db.leads.find(x => x.id === id); if (!isMgr(r.workspace_id)) throw new Error('Only managers can assign'); Object.assign(r, { owner_id: user, pool: !user, claimed_at: user ? now() : null, contacted_at: null, updated_at: now() }); knockAppend(r, { r: user ? 'Assigned' : 'Returned to board', by: db.me, to: user }); persist(); },
    async takeOverDoor(id){ const r = db.leads.find(x => x.id === id); if (r.owner_id === db.me) return 'mine'; if (r.protected_until && Date.parse(r.protected_until) > Date.now()) return 'protected'; const from = r.owner_id; Object.assign(r, { owner_id: db.me, protected_until: new Date(Date.now() + (settings(r.workspace_id).protect_days || 30) * day).toISOString(), updated_at: now() }); knockAppend(r, { r: 'Taken over', by: db.me, from }); persist(); return 'ok'; },
    async releaseStale(ws){ const hrs = settings(ws).claim_deadline_hours || 2; let n = 0; for (const r of db.leads) if (r.workspace_id === ws && r.origin === 'company' && !r.pool && r.owner_id && r.claimed_at && !r.contacted_at && Date.now() - Date.parse(r.claimed_at) > hrs * 3600e3){ const was = r.owner_id; Object.assign(r, { owner_id: null, pool: true, claimed_at: null }); knockAppend(r, { r: 'Returned to board', by: was }); n++; } if (n) persist(); return n; },

    async uploadFile(ws, folder, blob, ext){ const p = `demo/${folder}/${uuid()}.${ext}`; files[p] = URL.createObjectURL(blob); try { const d = await new Promise(r => { const f = new FileReader(); f.onload = () => r(f.result); f.readAsDataURL(blob); }); if (d.length < 400000) localStorage.setItem('rlt.f.' + p, d); } catch (e) {} return p; },
    async signedUrls(paths){ const o = {}; for (const p of paths){ if (files[p]) o[p] = files[p]; else { const d = localStorage.getItem('rlt.f.' + p); if (d) o[p] = d; } } return o; },
    async deleteFile(p){ delete files[p]; localStorage.removeItem('rlt.f.' + p); },

    async leaderboard(ws, from, to){
      const f = +from, t = +to;
      return wait(db.members.filter(m => m.workspace_id === ws && m.active).map(m => {
        let doors = 0, contacts = 0, appts = 0, insp = 0, sales = 0, volume = 0;
        for (const r of db.leads.filter(x => x.workspace_id === ws && x.owner_id === m.user_id)){
          for (const k of r.data?.knocks || []){ if (k.t < f || k.t > t) continue; if (k.d){ doors++; if (k.r !== 'Not Home') contacts++; } if (k.r === 'Inspection Scheduled') appts++; if (k.r === 'Inspected') insp++; }
          const s = r.data?.sale || {}; const sd = s.soldAt ? Date.parse(s.soldAt + 'T12:00') : 0;
          if (r.status === 'Sold' && sd >= f - day && sd <= t + day){ sales++; volume += ['value', 'upgrades', 'supplements'].reduce((a, k) => a + (parseFloat(String(s[k] || '').replace(/[^0-9.]/g, '')) || 0), 0); }
        }
        return { user_id: m.user_id, display_name: m.display_name, doors, contacts, appts, inspections: insp, sales, volume };
      }));
    },
    async feed(ws){ return wait(db.feed.filter(f => f.workspace_id === ws).sort((a, b) => b.created_at.localeCompare(a.created_at)).slice(0, 60).map(f => ({ ...f, reactions: db.reactions.filter(r => r.feed_id === f.id) }))); },
    async postFeed(ws, item){ db.feed.push({ id: uuid(), workspace_id: ws, user_id: db.me, created_at: now(), amount: null, ...item }); persist(); emit('feed'); },
    async toggleReaction(feedId, emoji){ const i = db.reactions.findIndex(r => r.feed_id === feedId && r.user_id === db.me && r.emoji === emoji); if (i >= 0) db.reactions.splice(i, 1); else db.reactions.push({ feed_id: feedId, user_id: db.me, emoji }); persist(); emit('feed'); },

    async threadMessages(ws, thread){ return wait(db.messages.filter(m => m.workspace_id === ws && m.thread === thread && api._canRead(m)).sort((a, b) => a.created_at.localeCompare(b.created_at))); },
    async recentMessages(ws){ return wait(db.messages.filter(m => m.workspace_id === ws && api._canRead(m)).sort((a, b) => b.created_at.localeCompare(a.created_at)).slice(0, 300)); },
    _canRead(m){ return m.channel === 'announce' || m.channel === 'team' || (m.channel === 'dm' && m.participants.includes(db.me)) || (m.channel === 'lead' && canSeeLead(m.lead_id)); },
    async sendMessage(ws, msg){ if (msg.channel === 'announce' && !isMgr(ws)) throw new Error('Only managers can post announcements'); const m = { id: uuid(), workspace_id: ws, sender_id: db.me, created_at: now(), participants: [], lead_id: null, image_path: null, ...msg }; db.messages.push(m); persist(); emit('message', m); return m; },
    async markRead(ws, thread){ const r = db.reads.find(x => x.workspace_id === ws && x.user_id === db.me && x.thread === thread); if (r) r.last_read_at = now(); else db.reads.push({ workspace_id: ws, user_id: db.me, thread, last_read_at: now() }); persist(); },
    async myReads(ws){ return db.reads.filter(r => r.workspace_id === ws && r.user_id === db.me); },
    async announceReads(ws){ return db.reads.filter(r => r.workspace_id === ws && r.thread === 'announce'); },
    async reportMessage(id, reason){ db.reports.push({ id: uuid(), message_id: id, reporter_id: db.me, reason }); persist(); },
    async block(u){ if (!db.blocks.find(b => b.user_id === db.me && b.blocked_id === u)) db.blocks.push({ user_id: db.me, blocked_id: u }); persist(); },
    async unblock(u){ db.blocks = db.blocks.filter(b => !(b.user_id === db.me && b.blocked_id === u)); persist(); },
    async blocks(){ return db.blocks.filter(b => b.user_id === db.me).map(b => b.blocked_id); },
    async exportMessages(ws){ if (role(ws) !== 'owner') throw new Error('Only the account owner can export messages'); return db.messages.filter(m => m.workspace_id === ws); },
    subscribe(ws, h){ listeners.add(h); return () => listeners.delete(h); },

    async territories(ws){ return wait(db.territories.filter(t => t.workspace_id === ws)); },
    async saveTerritory(ws, t){ if (!isMgr(ws)) throw new Error('Only managers can edit territories'); if (t.id){ Object.assign(db.territories.find(x => x.id === t.id), t); } else db.territories.push({ ...t, id: uuid(), workspace_id: ws, created_at: now() }); persist(); },
    async skipZones(ws){ if (!db.skip_zones) db.skip_zones = []; return wait(db.skip_zones.filter(z => z.workspace_id === ws)); },
    async saveSkipZone(ws, z){ if (!db.skip_zones) db.skip_zones = []; const row = { name: z.name || '', reason: z.reason || '', note: z.note || '', points: z.points };
      if (z.id){ const cur = db.skip_zones.find(x => x.id === z.id); if (!cur) throw new Error('Zone not found'); if (cur.created_by !== db.me && !isMgr(ws)) throw new Error('Only the person who drew this zone or a manager can change it'); Object.assign(cur, row); }
      else db.skip_zones.push({ id: uuid(), workspace_id: ws, created_by: db.me, created_at: now(), ...row }); persist(); return wait(true); },
    async deleteSkipZone(id){ const cur = (db.skip_zones || []).find(x => x.id === id); if (cur && cur.created_by !== db.me && !isMgr(cur.workspace_id)) throw new Error('Only the person who drew this zone or a manager can delete it'); db.skip_zones = (db.skip_zones || []).filter(z => z.id !== id); persist(); },
    async deleteTerritory(id){ db.territories = db.territories.filter(t => t.id !== id); persist(); },
    async saveSession(ws, s){ db.sessions.push({ id: uuid(), workspace_id: ws, user_id: db.me, started_at: new Date(s.start).toISOString(), ended_at: new Date(s.end).toISOString(), doors: s.k, contacts: s.c, appts: s.a }); persist(); },
    async sessions(ws){ return db.sessions.filter(s => s.workspace_id === ws && s.user_id === db.me).sort((a, b) => b.started_at.localeCompare(a.started_at)).slice(0, 20); }
  };
  return api;
}
