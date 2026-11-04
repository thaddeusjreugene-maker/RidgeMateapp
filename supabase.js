// Live backend: Supabase (logins, database, photo storage, realtime).
import { createClient } from '../../vendor/supabase.esm.js'; // supabase-js 2.118.0, bundled locally
import { toRow, fromRow } from './shape.js';

export function supabaseApi(url, key){
  const sb = createClient(url, key, { auth: { persistSession: true, autoRefreshToken: true } });
  const must = ({ data, error }) => { if (error) throw new Error(error.message || String(error)); return data; };
  let uid = null;

  const api = {
    mode: 'live',
    async session(){ const { data } = await sb.auth.getSession(); uid = data.session?.user?.id || null; return data.session ? { user: { id: uid, email: data.session.user.email } } : null; },
    async sendCode(email){ must(await sb.auth.signInWithOtp({ email, options: { shouldCreateUser: true } })); },
    async verifyCode(email, code){ const d = must(await sb.auth.verifyOtp({ email, token: code.trim(), type: 'email' })); uid = d.user?.id; return { user: { id: uid, email } }; },
    async signOut(){ await sb.auth.signOut(); uid = null; },
    onAuthChange(cb){ sb.auth.onAuthStateChange((_e, s) => { uid = s?.user?.id || null; cb(s ? { user: { id: uid, email: s.user.email } } : null); }); },
    me(){ return uid; },

    // workspaces
    async workspaces(){
      const mem = must(await sb.from('members').select('workspace_id, role, display_name, active').eq('user_id', uid).eq('active', true));
      if (!mem.length) return [];
      const ws = must(await sb.from('workspaces').select('*').in('id', mem.map(m => m.workspace_id)));
      return ws.map(w => ({ ...w, role: mem.find(m => m.workspace_id === w.id).role }));
    },
    async createWorkspace(name, kind, displayName){ return must(await sb.rpc('create_workspace', { p_name: name, p_kind: kind, p_display_name: displayName })); },
    async joinWorkspace(code, displayName){ return must(await sb.rpc('join_workspace', { p_code: code, p_display_name: displayName })); },
    async updateWorkspace(ws, patch){ must(await sb.from('workspaces').update(patch).eq('id', ws)); },
    async members(ws){ return must(await sb.from('members').select('*').eq('workspace_id', ws).order('joined_at')); },
    async updateMember(ws, user, patch){ must(await sb.from('members').update(patch).eq('workspace_id', ws).eq('user_id', user)); },
    async createInvite(ws, role){ return must(await sb.rpc('create_invite', { ws, p_role: role })); },

    // leads
    async listLeads(ws){ const rows = must(await sb.from('leads').select('*').eq('workspace_id', ws).order('updated_at', { ascending: false }).limit(5000)); return rows.map(fromRow); },
    async saveLead(ws, l){
      const row = toRow(ws, l);
      if (!l._saved){ must(await sb.from('leads').insert(row)); l._saved = true; return; }
      // never resend board/claim bookkeeping from the client; the server owns those columns
      const { id, workspace_id, created_by, pool, posted_by, posted_at, claimed_at, ...upd } = row;
      must(await sb.from('leads').update(upd).eq('id', l.id));
    },
    async deleteLead(ws, id){ must(await sb.from('leads').delete().eq('id', id)); },
    async teamPins(ws){ return must(await sb.rpc('team_pins', { ws })) || []; },
    async pinHistory(id){ return must(await sb.rpc('pin_history', { lid: id })); },
    async openLeads(ws){ return must(await sb.rpc('open_leads', { ws })) || []; },
    async postOpenLead(ws, l){ l.owner_id = null; l.pool = true; l.origin = 'company'; l.posted_by = uid; l.posted_at = new Date().toISOString(); l.created_by = uid; must(await sb.from('leads').insert(toRow(ws, l))); l._saved = true; },
    async claimLead(id){ return must(await sb.rpc('claim_lead', { lid: id })); },
    async releaseLead(id, reason){ must(await sb.rpc('release_lead', { lid: id, p_reason: reason || '' })); },
    async assignLead(id, user){ must(await sb.rpc('assign_lead', { lid: id, p_user: user })); },
    async takeOverDoor(id){ return must(await sb.rpc('take_over_door', { lid: id })); },
    async releaseStale(ws){ try { return must(await sb.rpc('release_stale_leads', { ws })); } catch (e) { return 0; } },

    // files
    async uploadFile(ws, folder, blob, ext){
      const path = `${ws}/${folder}/${crypto.randomUUID()}.${ext}`;
      must(await sb.storage.from('photos').upload(path, blob, { contentType: blob.type || 'image/jpeg', upsert: false }));
      return path;
    },
    async signedUrls(paths){
      const out = {}; const list = [...new Set(paths)].filter(Boolean); if (!list.length) return out;
      for (let i = 0; i < list.length; i += 100){
        const { data } = await sb.storage.from('photos').createSignedUrls(list.slice(i, i + 100), 60 * 60 * 6);
        (data || []).forEach(d => { if (d.signedUrl) out[d.path] = d.signedUrl; });
      }
      return out;
    },
    async deleteFile(path){ await sb.storage.from('photos').remove([path]); },

    // team
    async leaderboard(ws, from, to){ return must(await sb.rpc('leaderboard', { ws, p_from: from.toISOString(), p_to: to.toISOString() })) || []; },
    async feed(ws, limit = 60){
      const f = must(await sb.from('feed').select('*').eq('workspace_id', ws).order('created_at', { ascending: false }).limit(limit));
      if (!f.length) return [];
      const r = must(await sb.from('reactions').select('*').in('feed_id', f.map(x => x.id)));
      return f.map(x => ({ ...x, reactions: r.filter(y => y.feed_id === x.id) }));
    },
    async postFeed(ws, item){ must(await sb.from('feed').insert({ workspace_id: ws, user_id: uid, ...item })); },
    async toggleReaction(feedId, emoji){
      const { data } = await sb.from('reactions').select('*').eq('feed_id', feedId).eq('user_id', uid).eq('emoji', emoji);
      if (data && data.length) must(await sb.from('reactions').delete().eq('feed_id', feedId).eq('user_id', uid).eq('emoji', emoji));
      else must(await sb.from('reactions').insert({ feed_id: feedId, user_id: uid, emoji }));
    },

    // messages
    async threadMessages(ws, thread, limit = 200){
      const m = must(await sb.from('messages').select('*').eq('workspace_id', ws).eq('thread', thread).order('created_at', { ascending: false }).limit(limit));
      return m.reverse();
    },
    async recentMessages(ws, limit = 300){ return must(await sb.from('messages').select('*').eq('workspace_id', ws).order('created_at', { ascending: false }).limit(limit)); },
    async sendMessage(ws, msg){ return must(await sb.from('messages').insert({ workspace_id: ws, sender_id: uid, ...msg }).select().single()); },
    async markRead(ws, thread){ await sb.from('message_reads').upsert({ workspace_id: ws, user_id: uid, thread, last_read_at: new Date().toISOString() }); },
    async myReads(ws){ return must(await sb.from('message_reads').select('*').eq('workspace_id', ws).eq('user_id', uid)); },
    async announceReads(ws){ return must(await sb.rpc('announce_reads', { ws })) || []; },
    async reportMessage(id, reason){ must(await sb.from('message_reports').insert({ message_id: id, reporter_id: uid, reason })); },
    async block(user){ must(await sb.from('blocks').upsert({ user_id: uid, blocked_id: user })); },
    async unblock(user){ must(await sb.from('blocks').delete().eq('user_id', uid).eq('blocked_id', user)); },
    async blocks(){ return (must(await sb.from('blocks').select('blocked_id').eq('user_id', uid)) || []).map(b => b.blocked_id); },
    async exportMessages(ws){ return must(await sb.rpc('export_messages', { ws })); },
    subscribe(ws, h){
      const ch = sb.channel('ws-' + ws)
        .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages', filter: `workspace_id=eq.${ws}` }, p => h.onMessage && h.onMessage(p.new))
        .on('postgres_changes', { event: '*', schema: 'public', table: 'feed', filter: `workspace_id=eq.${ws}` }, () => h.onFeed && h.onFeed())
        .on('postgres_changes', { event: '*', schema: 'public', table: 'reactions' }, () => h.onFeed && h.onFeed())
        .subscribe();
      return () => sb.removeChannel(ch);
    },

    // territories + sessions
    async territories(ws){ return must(await sb.from('territories').select('*').eq('workspace_id', ws).order('created_at')); },
    async saveTerritory(ws, t){ if (t.id) must(await sb.from('territories').update({ name: t.name, color: t.color, points: t.points, rep_ids: t.rep_ids }).eq('id', t.id)); else must(await sb.from('territories').insert({ workspace_id: ws, name: t.name, color: t.color, points: t.points, rep_ids: t.rep_ids })); },
    async deleteTerritory(id){ must(await sb.from('territories').delete().eq('id', id)); },
    async skipZones(ws){ return must(await sb.from('skip_zones').select('*').eq('workspace_id', ws).order('created_at')); },
    async saveSkipZone(ws, z){ const row = { name: z.name || '', reason: z.reason || '', note: z.note || '', points: z.points };
      if (z.id) must(await sb.from('skip_zones').update(row).eq('id', z.id)); else must(await sb.from('skip_zones').insert({ workspace_id: ws, created_by: uid, ...row })); },
    async deleteSkipZone(id){ must(await sb.from('skip_zones').delete().eq('id', id)); },
    async saveSession(ws, s){ must(await sb.from('knock_sessions').insert({ workspace_id: ws, user_id: uid, started_at: new Date(s.start).toISOString(), ended_at: new Date(s.end).toISOString(), doors: s.k, contacts: s.c, appts: s.a })); },
    async sessions(ws){ return must(await sb.from('knock_sessions').select('*').eq('workspace_id', ws).eq('user_id', uid).order('started_at', { ascending: false }).limit(20)); }
  };
  return api;
}
