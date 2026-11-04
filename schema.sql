-- =====================================================================
-- Ridgeline Teams — database schema for Supabase (Postgres)
-- Run this whole file once in Supabase: SQL Editor → New query → paste → Run.
-- It is safe to re-run: objects are created "if not exists" / replaced.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Workspaces: an individual rep, or a company with a team
-- ---------------------------------------------------------------------
create table if not exists public.workspaces (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  kind        text not null check (kind in ('individual','company')),
  owner_id    uuid not null,
  settings    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

create table if not exists public.members (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id      uuid not null,
  role         text not null check (role in ('owner','manager','rep','office')),
  display_name text not null default '',
  phone        text not null default '',
  active       boolean not null default true,
  prefs        jsonb not null default '{}'::jsonb,   -- per-rep commission overrides, goal, etc.
  joined_at    timestamptz not null default now(),
  primary key (workspace_id, user_id)
);
create index if not exists members_user_idx on public.members(user_id);

create table if not exists public.invites (
  code         text primary key,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  role         text not null check (role in ('manager','rep','office')),
  created_by   uuid not null,
  expires_at   timestamptz not null default now() + interval '14 days',
  max_uses     int not null default 25,
  uses         int not null default 0,
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Leads (a pinned door, a call-in lead, a customer). Everything a lead
-- carries beyond the indexed columns lives in `data` (knock history,
-- notes, roof, insurance, photos metadata, estimate, sale, follow-ups).
-- ---------------------------------------------------------------------
create table if not exists public.leads (
  id              text primary key,                       -- client-generated 'lead-…'
  workspace_id    uuid not null references public.workspaces(id) on delete cascade,
  owner_id        uuid,                                   -- rep who works it; null = on the Open Leads board
  created_by      uuid not null,                          -- who pinned / posted it
  origin          text not null default 'self' check (origin in ('self','company')),
  pool            boolean not null default false,         -- true while posted to Open Leads
  posted_by       uuid,
  posted_at       timestamptz,
  claimed_at      timestamptz,
  contacted_at    timestamptz,
  protected_until timestamptz,
  status          text not null default 'Not Home',
  follow_at       text not null default '',
  num             text not null default '',
  street          text not null default '',
  city            text not null default '',
  name            text not null default '',
  phone           text not null default '',
  lat             double precision,
  lng             double precision,
  data            jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists leads_ws_idx    on public.leads(workspace_id);
create index if not exists leads_owner_idx on public.leads(workspace_id, owner_id);
create index if not exists leads_pool_idx  on public.leads(workspace_id) where pool;

create table if not exists public.territories (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  name         text not null,
  color        text not null default '#2F6BFF',
  points       jsonb not null default '[]'::jsonb,   -- [[lat,lng], …]
  rep_ids      uuid[] not null default '{}',
  created_at   timestamptz not null default now()
);

-- Skip zones: areas the whole team should not canvass (new roofs, no-soliciting, etc.)
create table if not exists public.skip_zones (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  name         text not null default '',
  reason       text not null default '',
  note         text not null default '',
  points       jsonb not null default '[]'::jsonb,   -- [[lat,lng], …]
  created_by   uuid not null default auth.uid(),
  created_at   timestamptz not null default now()
);
create index if not exists skip_zones_ws_idx on public.skip_zones(workspace_id);

create table if not exists public.knock_sessions (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id      uuid not null,
  started_at   timestamptz not null,
  ended_at     timestamptz not null,
  doors        int not null default 0,
  contacts     int not null default 0,
  appts        int not null default 0
);

-- ---------------------------------------------------------------------
-- Team feed, reactions, messages
-- ---------------------------------------------------------------------
create table if not exists public.feed (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id      uuid not null,
  kind         text not null,              -- sale, streak, milestone, goal, post
  body         text not null,
  amount       numeric,
  created_at   timestamptz not null default now()
);
create table if not exists public.reactions (
  feed_id    uuid not null references public.feed(id) on delete cascade,
  user_id    uuid not null,
  emoji      text not null,
  primary key (feed_id, user_id, emoji)
);

-- channel is one of: 'announce' | 'team' | 'dm' | 'lead'
-- dm: participants holds both user ids; lead: lead_id set
create table if not exists public.messages (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  channel      text not null check (channel in ('announce','team','dm','lead')),
  thread       text not null,                -- 'announce' | 'team' | 'dm:<a>:<b>' | 'lead:<id>'
  participants uuid[] not null default '{}',
  lead_id      text,
  sender_id    uuid not null,
  body         text not null default '',
  image_path   text,
  created_at   timestamptz not null default now()
);
create index if not exists messages_thread_idx on public.messages(workspace_id, thread, created_at);

create table if not exists public.message_reads (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id      uuid not null,
  thread       text not null,
  last_read_at timestamptz not null default now(),
  primary key (workspace_id, user_id, thread)
);
create table if not exists public.message_reports (
  id          uuid primary key default gen_random_uuid(),
  message_id  uuid not null references public.messages(id) on delete cascade,
  reporter_id uuid not null,
  reason      text not null default '',
  created_at  timestamptz not null default now()
);
create table if not exists public.blocks (
  user_id    uuid not null,
  blocked_id uuid not null,
  primary key (user_id, blocked_id)
);

-- ---------------------------------------------------------------------
-- Helper functions (security definer so policies can call them safely)
-- ---------------------------------------------------------------------
create or replace function public.my_role(ws uuid) returns text
language sql stable security definer set search_path = public as $$
  select role from members where workspace_id = ws and user_id = auth.uid() and active
$$;
create or replace function public.is_member(ws uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from members where workspace_id = ws and user_id = auth.uid() and active)
$$;
create or replace function public.is_manager(ws uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role(ws) in ('owner','manager'), false)
$$;
create or replace function public.can_view_all(ws uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role(ws) in ('owner','manager','office'), false)
$$;

-- ---------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------
alter table public.workspaces      enable row level security;
alter table public.members         enable row level security;
alter table public.invites         enable row level security;
alter table public.leads           enable row level security;
alter table public.territories     enable row level security;
alter table public.skip_zones      enable row level security;
alter table public.knock_sessions  enable row level security;
alter table public.feed            enable row level security;
alter table public.reactions       enable row level security;
alter table public.messages        enable row level security;
alter table public.message_reads   enable row level security;
alter table public.message_reports enable row level security;
alter table public.blocks          enable row level security;

-- workspaces
drop policy if exists ws_read   on public.workspaces;
drop policy if exists ws_update on public.workspaces;
create policy ws_read   on public.workspaces for select using (public.is_member(id));
create policy ws_update on public.workspaces for update using (public.is_manager(id)) with check (public.is_manager(id));

-- members: everyone in the workspace sees the roster; managers edit it; anyone edits their own name/phone
drop policy if exists mem_read on public.members;
drop policy if exists mem_mgr  on public.members;
drop policy if exists mem_self on public.members;
create policy mem_read on public.members for select using (public.is_member(workspace_id));
create policy mem_mgr  on public.members for update using (public.is_manager(workspace_id)) with check (public.is_manager(workspace_id));
create policy mem_self on public.members for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Guard on member edits from the app: nobody moves a row to another workspace/user, only managers
-- change role/active, and nobody changes or removes the owner (or makes someone owner).
-- Functions running as the schema owner (join_workspace etc.) and the service role are not limited.
create or replace function public.members_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user not in ('authenticated','anon') then return new; end if;
  if new.workspace_id is distinct from old.workspace_id or new.user_id is distinct from old.user_id then
    raise exception 'Members cannot be moved';
  end if;
  if new.role is distinct from old.role or new.active is distinct from old.active then
    if not public.is_manager(old.workspace_id) then raise exception 'Only managers can change roles'; end if;
    if old.role = 'owner' or new.role = 'owner' then raise exception 'The account owner cannot be changed here'; end if;
  end if;
  return new;
end $$;
drop trigger if exists members_guard on public.members;
create trigger members_guard before update on public.members for each row execute function public.members_guard();

-- Managers edit workspace settings, but the owner never changes from the app
create or replace function public.workspaces_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user not in ('authenticated','anon') then return new; end if;
  if new.owner_id is distinct from old.owner_id or new.id is distinct from old.id then
    raise exception 'The account owner cannot be changed here';
  end if;
  return new;
end $$;
drop trigger if exists workspaces_guard on public.workspaces;
create trigger workspaces_guard before update on public.workspaces for each row execute function public.workspaces_guard();

-- invites: managers only
drop policy if exists inv_mgr on public.invites;
create policy inv_mgr on public.invites for all using (public.is_manager(workspace_id)) with check (public.is_manager(workspace_id));

-- leads: managers/office see everything; reps see their own. Teammates' pins and the
-- Open Leads board are served through functions below, with contact details removed.
drop policy if exists lead_read   on public.leads;
drop policy if exists lead_insert on public.leads;
drop policy if exists lead_update on public.leads;
drop policy if exists lead_delete on public.leads;
create policy lead_read on public.leads for select
  using (public.can_view_all(workspace_id) or (public.is_member(workspace_id) and owner_id = auth.uid()));
create policy lead_insert on public.leads for insert
  with check (public.is_member(workspace_id) and created_by = auth.uid()
              and ((owner_id = auth.uid() and not pool) or (owner_id is null and pool and public.can_view_all(workspace_id))
                   or public.is_manager(workspace_id)));
create policy lead_update on public.leads for update
  using (public.is_manager(workspace_id) or (public.is_member(workspace_id) and owner_id = auth.uid()))
  with check (public.is_manager(workspace_id) or (public.is_member(workspace_id) and owner_id = auth.uid() and not pool));

-- Reps editing their own lead can't touch board/claim bookkeeping (owner, origin, pool, claim time…);
-- those change only through claim_lead / release_lead / assign_lead / take_over_door, or by a manager.
create or replace function public.leads_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user not in ('authenticated','anon') then return new; end if;
  if public.is_manager(old.workspace_id) and public.is_manager(new.workspace_id) then return new; end if;
  if new.workspace_id is distinct from old.workspace_id or new.owner_id is distinct from old.owner_id
     or new.created_by is distinct from old.created_by or new.origin is distinct from old.origin
     or new.pool is distinct from old.pool or new.posted_by is distinct from old.posted_by
     or new.posted_at is distinct from old.posted_at or new.claimed_at is distinct from old.claimed_at then
    raise exception 'Only a manager can change who owns a lead or its board status';
  end if;
  return new;
end $$;
drop trigger if exists leads_guard on public.leads;
create trigger leads_guard before update on public.leads for each row execute function public.leads_guard();
create policy lead_delete on public.leads for delete
  using (public.is_manager(workspace_id) or (public.is_member(workspace_id) and owner_id = auth.uid() and origin = 'self'));

-- territories
drop policy if exists terr_read on public.territories;
drop policy if exists terr_mgr  on public.territories;
create policy terr_read on public.territories for select using (public.is_member(workspace_id));
create policy terr_mgr  on public.territories for all using (public.is_manager(workspace_id)) with check (public.is_manager(workspace_id));

-- skip zones: everyone on the team sees them; anyone can add; the person who drew it or a manager can change or remove it
drop policy if exists sz_read   on public.skip_zones;
drop policy if exists sz_insert on public.skip_zones;
drop policy if exists sz_update on public.skip_zones;
drop policy if exists sz_delete on public.skip_zones;
create policy sz_read   on public.skip_zones for select using (public.is_member(workspace_id));
create policy sz_insert on public.skip_zones for insert with check (public.is_member(workspace_id) and created_by = auth.uid());
create policy sz_update on public.skip_zones for update
  using (public.is_member(workspace_id) and (created_by = auth.uid() or public.is_manager(workspace_id)))
  with check (public.is_member(workspace_id) and (created_by = auth.uid() or public.is_manager(workspace_id)));
create policy sz_delete on public.skip_zones for delete
  using (public.is_member(workspace_id) and (created_by = auth.uid() or public.is_manager(workspace_id)));

-- knock sessions
drop policy if exists sess_read  on public.knock_sessions;
drop policy if exists sess_write on public.knock_sessions;
create policy sess_read  on public.knock_sessions for select using (user_id = auth.uid() or public.can_view_all(workspace_id));
create policy sess_write on public.knock_sessions for insert with check (user_id = auth.uid() and public.is_member(workspace_id));

-- feed + reactions
drop policy if exists feed_read   on public.feed;
drop policy if exists feed_write  on public.feed;
drop policy if exists feed_delete on public.feed;
create policy feed_read   on public.feed for select using (public.is_member(workspace_id));
create policy feed_write  on public.feed for insert with check (user_id = auth.uid() and public.is_member(workspace_id));
create policy feed_delete on public.feed for delete using (user_id = auth.uid() or public.is_manager(workspace_id));
drop policy if exists react_read  on public.reactions;
drop policy if exists react_write on public.reactions;
drop policy if exists react_del   on public.reactions;
create policy react_read  on public.reactions for select using (exists(select 1 from feed f where f.id = feed_id and public.is_member(f.workspace_id)));
create policy react_write on public.reactions for insert with check (user_id = auth.uid() and exists(select 1 from feed f where f.id = feed_id and public.is_member(f.workspace_id)));
create policy react_del   on public.reactions for delete using (user_id = auth.uid());

-- messages: announcements + team chat for every member; DMs only for the two people in them
-- (managers cannot read DMs); lead threads for managers/office and the rep who owns the lead.
create or replace function public.can_see_lead(lid text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from leads l where l.id = lid
                and (public.can_view_all(l.workspace_id) or l.owner_id = auth.uid()))
$$;
drop policy if exists msg_read  on public.messages;
drop policy if exists msg_write on public.messages;
drop policy if exists msg_del   on public.messages;
create policy msg_read on public.messages for select using (
  public.is_member(workspace_id) and (
    channel in ('announce','team')
    or (channel = 'dm' and auth.uid() = any(participants))
    or (channel = 'lead' and public.can_see_lead(lead_id))));
create policy msg_write on public.messages for insert with check (
  sender_id = auth.uid() and public.is_member(workspace_id) and (
    (channel = 'announce' and thread = 'announce' and public.is_manager(workspace_id))
    or (channel = 'team' and thread = 'team')
    or (channel = 'dm' and auth.uid() = any(participants) and cardinality(participants) = 2
        and participants[1] <> participants[2] and thread like 'dm:%'
        and strpos(thread, participants[1]::text) > 0 and strpos(thread, participants[2]::text) > 0)
    or (channel = 'lead' and thread = 'lead:' || lead_id and public.can_see_lead(lead_id)
        and exists(select 1 from leads l where l.id = lead_id and l.workspace_id = messages.workspace_id))));
create policy msg_del on public.messages for delete using (sender_id = auth.uid() or public.is_manager(workspace_id));

drop policy if exists reads_self on public.message_reads;
drop policy if exists reads_mgr  on public.message_reads;
create policy reads_self on public.message_reads for all using (user_id = auth.uid()) with check (user_id = auth.uid() and public.is_member(workspace_id));
create policy reads_mgr  on public.message_reads for select using (public.is_member(workspace_id) and thread = 'announce');

drop policy if exists rep_write on public.message_reports;
drop policy if exists rep_read  on public.message_reports;
create policy rep_write on public.message_reports for insert with check (reporter_id = auth.uid() and exists(select 1 from messages m where m.id = message_id));
-- managers see every report in their workspace (including reported DMs, whose text they still can't read)
create or replace function public.message_ws(mid uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select workspace_id from messages where id = mid
$$;
create policy rep_read  on public.message_reports for select using (public.is_manager(public.message_ws(message_id)));

drop policy if exists block_self on public.blocks;
create policy block_self on public.blocks for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------
-- Functions the app calls
-- ---------------------------------------------------------------------

-- Create a workspace and make the caller its owner
create or replace function public.create_workspace(p_name text, p_kind text, p_display_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare ws uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  insert into workspaces(name, kind, owner_id, settings)
  values (p_name, p_kind, auth.uid(), jsonb_build_object(
    'rates', jsonb_build_object(
      'self',    jsonb_build_object('Insurance',10,'Retail',10,'Repair',10),
      'company', jsonb_build_object('Insurance',7,'Retail',7,'Repair',7)),
    'claim_deadline_hours', 2, 'claim_cap', 3, 'protect_days', 30,
    'teammate_pins', true, 'leaderboards', true, 'goal', 0, 'team_goal', null,
    'terms', 'By signing, the homeowner agrees to have the contractor perform the work listed above at the stated price, subject to insurance approval where marked Insurance. This agreement may be cancelled in writing within 3 business days.'))
  returning id into ws;
  insert into members(workspace_id, user_id, role, display_name) values (ws, auth.uid(), 'owner', coalesce(p_display_name,''));
  return ws;
end $$;

-- Make an invite code (managers)
create or replace function public.create_invite(ws uuid, p_role text)
returns text language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if not public.is_manager(ws) then raise exception 'Only managers can invite'; end if;
  c := upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  insert into invites(code, workspace_id, role, created_by) values (c, ws, p_role, auth.uid());
  return c;
end $$;

-- Join with an invite code
create or replace function public.join_workspace(p_code text, p_display_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare inv invites;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  select * into inv from invites where code = upper(trim(p_code)) for update;
  if not found or inv.expires_at < now() or inv.uses >= inv.max_uses then raise exception 'That invite code is not valid'; end if;
  insert into members(workspace_id, user_id, role, display_name)
  values (inv.workspace_id, auth.uid(), inv.role, coalesce(p_display_name,''))
  on conflict (workspace_id, user_id) do update
    set role = case when members.active or members.role = 'owner' then members.role else excluded.role end,
        active = true;
  update invites set uses = uses + 1 where code = inv.code;
  return inv.workspace_id;
end $$;

-- Every member's pins, status only — no homeowner name or phone unless it's your own lead or you're a manager.
create or replace function public.team_pins(ws uuid)
returns table(id text, owner_id uuid, created_by uuid, status text, lat double precision, lng double precision,
              num text, street text, protected_until timestamptz, created_at timestamptz, updated_at timestamptz,
              pinned_lat double precision, pinned_lng double precision)
language sql stable security definer set search_path = public as $$
  select l.id, l.owner_id, l.created_by, l.status, l.lat, l.lng,
         case when public.can_view_all(ws) or l.owner_id = auth.uid() then l.num else '' end,
         l.street, l.protected_until, l.created_at, l.updated_at,
         case when public.can_view_all(ws) then (l.data->>'pinned_lat')::double precision end,
         case when public.can_view_all(ws) then (l.data->>'pinned_lng')::double precision end
  from leads l
  where l.workspace_id = ws and l.lat is not null and not l.pool and public.is_member(ws)
    and (coalesce((select (settings->>'teammate_pins')::boolean from workspaces where id = ws), true)
         or public.can_view_all(ws) or l.owner_id = auth.uid())
$$;

-- Status history for one pin (who pinned it and every change), for anyone in the workspace
create or replace function public.pin_history(lid text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('created_by', l.created_by, 'created_at', l.created_at, 'owner_id', l.owner_id,
         'knocks', case when public.can_view_all(l.workspace_id) or l.owner_id = auth.uid()
                        then coalesce(l.data->'knocks','[]'::jsonb)
                        else (select coalesce(jsonb_agg(k - 'gps'), '[]'::jsonb) from jsonb_array_elements(coalesce(l.data->'knocks','[]'::jsonb)) k) end)
  from leads l where l.id = lid and public.is_member(l.workspace_id)
$$;

-- Open Leads board for reps: area only, no name/phone/house number
create or replace function public.open_leads(ws uuid)
returns table(id text, street text, city text, lat double precision, lng double precision, job text, insurance boolean,
              window_text text, source text, notes text, posted_at timestamptz, posted_by uuid)
language sql stable security definer set search_path = public as $$
  select l.id, l.street, l.city,
         round(l.lat::numeric, 3)::double precision, round(l.lng::numeric, 3)::double precision,
         coalesce(l.data->'post'->>'job',''), coalesce((l.data->'post'->>'insurance')::boolean,false),
         coalesce(l.data->'post'->>'window',''), coalesce(l.data->'post'->>'source',''),
         coalesce(l.data->'post'->>'public_notes',''), l.posted_at, l.posted_by
  from leads l where l.workspace_id = ws and l.pool and l.owner_id is null and public.is_member(ws)
  order by l.posted_at desc
$$;

-- Return claimed office leads that nobody contacted in time
create or replace function public.release_stale_leads(ws uuid)
returns int language plpgsql security definer set search_path = public as $$
declare hrs numeric; n int;
begin
  if not public.is_member(ws) then return 0; end if;
  select coalesce((settings->>'claim_deadline_hours')::numeric, 2) into hrs from workspaces where id = ws;
  update leads set owner_id = null, pool = true, claimed_at = null,
         data = jsonb_set(data, '{knocks}', coalesce(data->'knocks','[]'::jsonb) ||
                jsonb_build_array(jsonb_build_object('t', (extract(epoch from now())*1000)::bigint, 'r', 'Returned to board', 'by', owner_id)))
   where workspace_id = ws and origin = 'company' and not pool and owner_id is not null
     and claimed_at is not null and contacted_at is null
     and claimed_at < now() - make_interval(secs => hrs * 3600);
  get diagnostics n = row_count;
  return n;
end $$;

-- Claim an Open Lead (first come, first served, with a cap)
create or replace function public.claim_lead(lid text)
returns text language plpgsql security definer set search_path = public as $$
declare l leads; cap int; held int; hrs numeric;
begin
  select * into l from leads where id = lid for update;
  if not found or not public.is_member(l.workspace_id) then raise exception 'Lead not found'; end if;
  if not l.pool or l.owner_id is not null then return 'taken'; end if;
  select coalesce((settings->>'claim_cap')::int, 3), coalesce((settings->>'claim_deadline_hours')::numeric, 2)
    into cap, hrs from workspaces where id = l.workspace_id;
  select count(*) into held from leads
   where workspace_id = l.workspace_id and owner_id = auth.uid() and origin = 'company' and contacted_at is null and claimed_at is not null;
  if held >= cap then return 'cap'; end if;
  update leads set owner_id = auth.uid(), pool = false, claimed_at = now(), status = 'Inspection Scheduled', updated_at = now(),
         data = jsonb_set(data, '{knocks}', coalesce(data->'knocks','[]'::jsonb) ||
                jsonb_build_array(jsonb_build_object('t', (extract(epoch from now())*1000)::bigint, 'r', 'Claimed', 'by', auth.uid())))
   where id = lid;
  return 'ok';
end $$;

-- Manager hands a lead to a rep (or back to the board with p_user = null)
create or replace function public.assign_lead(lid text, p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
declare l leads;
begin
  select * into l from leads where id = lid for update;
  if not found or not public.is_manager(l.workspace_id) then raise exception 'Not allowed'; end if;
  update leads set owner_id = p_user, pool = (p_user is null), claimed_at = case when p_user is null then null else now() end,
         contacted_at = null, updated_at = now(),
         data = jsonb_set(data, '{knocks}', coalesce(data->'knocks','[]'::jsonb) ||
                jsonb_build_array(jsonb_build_object('t', (extract(epoch from now())*1000)::bigint,
                  'r', case when p_user is null then 'Returned to board' else 'Assigned' end, 'by', auth.uid(), 'to', p_user)))
   where id = lid;
end $$;

-- Rep gives a lead back to the board
create or replace function public.release_lead(lid text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare l leads;
begin
  select * into l from leads where id = lid for update;
  if not found or l.owner_id is distinct from auth.uid() then raise exception 'Not your lead'; end if;
  update leads set owner_id = null, pool = true, claimed_at = null, contacted_at = null, updated_at = now(),
         data = jsonb_set(data, '{knocks}', coalesce(data->'knocks','[]'::jsonb) ||
                jsonb_build_array(jsonb_build_object('t', (extract(epoch from now())*1000)::bigint, 'r', 'Released', 'by', auth.uid(), 'note', p_reason)))
   where id = lid;
end $$;

-- Take over a teammate's door after its protection window runs out
create or replace function public.take_over_door(lid text)
returns text language plpgsql security definer set search_path = public as $$
declare l leads; days int;
begin
  select * into l from leads where id = lid for update;
  if not found or not public.is_member(l.workspace_id) then raise exception 'Lead not found'; end if;
  if l.owner_id = auth.uid() then return 'mine'; end if;
  -- Open Leads go through claim_lead; office leads a rep has claimed stay theirs (managers reassign them)
  if l.pool or l.owner_id is null then return 'taken'; end if;
  if l.origin = 'company' then return 'protected'; end if;
  if l.protected_until is not null and l.protected_until > now() then return 'protected'; end if;
  select coalesce((settings->>'protect_days')::int, 30) into days from workspaces where id = l.workspace_id;
  update leads set owner_id = auth.uid(), protected_until = now() + make_interval(days => days), updated_at = now(),
         data = jsonb_set(data, '{knocks}', coalesce(data->'knocks','[]'::jsonb) ||
                jsonb_build_array(jsonb_build_object('t', (extract(epoch from now())*1000)::bigint, 'r', 'Taken over', 'by', auth.uid(), 'from', l.owner_id)))
   where id = lid;
  return 'ok';
end $$;

-- Text like '14,800', '$1,200.50', '', 'TBD' or null → a number (0 when there is none)
create or replace function public.money_value(v text) returns numeric
language sql immutable as $$
  select coalesce(substring(replace(coalesce(v,''), ',', '') from '-?[0-9]+(?:\.[0-9]+)?')::numeric, 0)
$$;

-- Leaderboard: activity and sales per member for a time window (never commissions)
create or replace function public.leaderboard(ws uuid, p_from timestamptz, p_to timestamptz)
returns table(user_id uuid, display_name text, doors int, contacts int, appts int, inspections int, sales int, volume numeric)
language sql stable security definer set search_path = public as $$
  with k as (
    select l.owner_id as uid, (x->>'r') as r,
           case when x->>'d' in ('1','true') then 1 else 0 end as d,
           case when x->>'t' ~ '^[0-9]+(\.[0-9]+)?$' then to_timestamp(((x->>'t')::numeric)/1000) end as at
    from leads l, jsonb_array_elements(case when jsonb_typeof(l.data->'knocks') = 'array' then l.data->'knocks' else '[]'::jsonb end) x
    where l.workspace_id = ws and jsonb_typeof(x) = 'object'
  ), s as (
    select l.owner_id as uid, count(*) as sales,
           sum(public.money_value(l.data->'sale'->>'value') + public.money_value(l.data->'sale'->>'upgrades')
             + public.money_value(l.data->'sale'->>'supplements')) as volume
    from leads l
    where l.workspace_id = ws and l.status = 'Sold'
      and coalesce(case when l.data->'sale'->>'soldAt' ~ '^\d{4}-\d{2}-\d{2}' then left(l.data->'sale'->>'soldAt', 10)::date end,
                   l.updated_at::date) between p_from::date and p_to::date
    group by l.owner_id
  )
  select m.user_id, m.display_name,
    coalesce((select count(*) from k where k.uid = m.user_id and k.d = 1 and k.at between p_from and p_to),0)::int,
    coalesce((select count(*) from k where k.uid = m.user_id and k.d = 1 and k.r <> 'Not Home' and k.at between p_from and p_to),0)::int,
    coalesce((select count(*) from k where k.uid = m.user_id and k.r = 'Inspection Scheduled' and k.at between p_from and p_to),0)::int,
    coalesce((select count(*) from k where k.uid = m.user_id and k.r = 'Inspected' and k.at between p_from and p_to),0)::int,
    coalesce(s.sales,0)::int, coalesce(s.volume,0)
  from members m left join s on s.uid = m.user_id
  where m.workspace_id = ws and m.active and public.is_member(ws)
$$;

-- Who has read the latest announcement
create or replace function public.announce_reads(ws uuid)
returns table(user_id uuid, last_read_at timestamptz)
language sql stable security definer set search_path = public as $$
  select r.user_id, r.last_read_at from message_reads r where r.workspace_id = ws and r.thread = 'announce' and public.is_member(ws)
$$;

-- Owner-only export of every message (for legal disputes)
create or replace function public.export_messages(ws uuid)
returns setof public.messages language plpgsql stable security definer set search_path = public as $$
begin
  if public.my_role(ws) is distinct from 'owner' then raise exception 'Only the account owner can export messages'; end if;
  return query select * from messages where workspace_id = ws order by created_at;
end $$;

grant execute on all functions in schema public to authenticated;
-- Table access for signed-in users. Row-level security above still decides which rows each person can see or change.
-- (Needed when the project was created with "Automatically expose new tables" turned off.)
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;

-- ---------------------------------------------------------------------
-- Live updates (chat, feed, board) — Supabase Realtime
-- ---------------------------------------------------------------------
do $$ begin
  begin execute 'alter publication supabase_realtime add table public.messages';  exception when others then null; end;
  begin execute 'alter publication supabase_realtime add table public.feed';      exception when others then null; end;
  begin execute 'alter publication supabase_realtime add table public.reactions'; exception when others then null; end;
end $$;

-- ---------------------------------------------------------------------
-- Photo storage: private bucket, files under <workspace_id>/<lead_id>/<file>
-- ---------------------------------------------------------------------
do $$ begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    insert into storage.buckets (id, name, public) values ('photos','photos', false) on conflict (id) do nothing;
    execute 'drop policy if exists photos_read on storage.objects';
    execute 'drop policy if exists photos_write on storage.objects';
    execute 'drop policy if exists photos_delete on storage.objects';
    execute $p$create policy photos_read on storage.objects for select to authenticated
      using (bucket_id = 'photos' and public.is_member((split_part(name,'/',1))::uuid)
             and (public.can_view_all((split_part(name,'/',1))::uuid) or public.can_see_lead(split_part(name,'/',2)) or split_part(name,'/',2) = 'chat'))$p$;
    execute $p$create policy photos_write on storage.objects for insert to authenticated
      with check (bucket_id = 'photos' and public.is_member((split_part(name,'/',1))::uuid))$p$;
    execute $p$create policy photos_delete on storage.objects for delete to authenticated
      using (bucket_id = 'photos' and owner = auth.uid())$p$;
  end if;
end $$;
