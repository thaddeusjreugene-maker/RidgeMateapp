// Converts between the app's lead object and a database row.
export const DATA_KEYS = ['email','source','knocks','log','fuDone','ref','roof','ins','storms','findings','photos','docs','sale','est','post','pinned_lat','pinned_lng'];

export function toRow(ws, l){
  const data = {};
  for (const k of DATA_KEYS) if (l[k] !== undefined) data[k] = l[k];
  return {
    id: l.id, workspace_id: ws,
    owner_id: l.owner_id ?? null, created_by: l.created_by,
    origin: l.origin || 'self', pool: !!l.pool,
    posted_by: l.posted_by ?? null, posted_at: l.posted_at ?? null,
    claimed_at: l.claimed_at ?? null, contacted_at: l.contacted_at ?? null,
    protected_until: l.protected_until ?? null,
    status: l.status || 'Not Home', follow_at: l.followAt || '',
    num: l.num || '', street: l.street || '', city: l.city || '',
    name: l.name || '', phone: l.phone || '',
    lat: l.geo ? l.geo.lat : null, lng: l.geo ? l.geo.lng : null,
    data, updated_at: new Date(l.updated || Date.now()).toISOString()
  };
}

export function fromRow(r){
  const d = r.data || {};
  const l = {
    id: r.id, kind: 'lead', workspace_id: r.workspace_id,
    owner_id: r.owner_id, created_by: r.created_by, origin: r.origin, pool: r.pool,
    posted_by: r.posted_by, posted_at: r.posted_at, claimed_at: r.claimed_at,
    contacted_at: r.contacted_at, protected_until: r.protected_until,
    status: r.status, followAt: r.follow_at || '',
    num: r.num, street: r.street, city: r.city, name: r.name, phone: r.phone,
    geo: r.lat != null && r.lng != null ? { lat: r.lat, lng: r.lng } : null,
    created: Date.parse(r.created_at) || Date.now(), updated: Date.parse(r.updated_at) || Date.now(),
    _saved: true
  };
  for (const k of DATA_KEYS) if (d[k] !== undefined) l[k] = d[k];
  return l;
}
