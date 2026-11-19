-- =====================================================================
-- RidgeMate Teams — database schema for Supabase (Postgres)
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
-- RUVA support staff, only while the owner has allowed support access
alter table public.members add column if not exists support boolean not null default false;
create table if not exists public.support_grants (
  workspace_id uuid primary key references public.workspaces(id) on delete cascade,
  granted_by   uuid,
  expires_at   timestamptz not null,
  created_at   timestamptz not null default now()
);

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
-- Personal invites (from an imported roster) carry the person's details
alter table public.invites add column if not exists name  text not null default '';
alter table public.invites add column if not exists phone text not null default '';
alter table public.invites add column if not exists email text not null default '';

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
  select role from members m where m.workspace_id = ws and m.user_id = auth.uid() and m.active
    and (not m.support or exists(select 1 from support_grants g where g.workspace_id = ws and g.expires_at > now()))
$$;
create or replace function public.is_member(ws uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from members m where m.workspace_id = ws and m.user_id = auth.uid() and m.active
    and (not m.support or exists(select 1 from support_grants g where g.workspace_id = ws and g.expires_at > now())))
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
-- Owners/managers and office staff can edit any lead's details (office attaches measurement reports, fixes info);
-- only owners/managers can change who owns a lead or its board status (leads_guard below).
create policy lead_update on public.leads for update
  using (public.can_view_all(workspace_id) or (public.is_member(workspace_id) and owner_id = auth.uid()))
  with check (public.can_view_all(workspace_id) or (public.is_member(workspace_id) and owner_id = auth.uid() and not pool));

-- Reps editing their own lead can't touch board/claim bookkeeping (owner, origin, pool, claim time…);
-- those change only through claim_lead / release_lead / assign_lead / take_over_door, or by a manager.
create or replace function public.leads_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user not in ('authenticated','anon') then return new; end if;
  -- Reports the owner, a manager or the office attached can only be removed by them, not by the rep
  if not public.can_view_all(old.workspace_id) and exists (
       select 1 from jsonb_array_elements(case when jsonb_typeof(old.data->'docs') = 'array' then old.data->'docs' else '[]'::jsonb end) d
       where coalesce(d->>'staff','') = 'true'
         and not (case when jsonb_typeof(new.data->'docs') = 'array' then new.data->'docs' else '[]'::jsonb end) @> jsonb_build_array(jsonb_build_object('id', d->'id'))) then
    raise exception 'Only the office can remove a report it attached';
  end if;
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

-- Personal invite for one person from a roster: single use, good for 30 days
create or replace function public.create_invite_for(ws uuid, p_role text, p_name text, p_phone text, p_email text)
returns text language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if not public.is_manager(ws) then raise exception 'Only managers can invite'; end if;
  if p_role not in ('manager','rep','office') then raise exception 'Unknown role'; end if;
  c := upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  insert into invites(code, workspace_id, role, created_by, max_uses, expires_at, name, phone, email)
  values (c, ws, p_role, auth.uid(), 1, now() + interval '30 days', coalesce(trim(p_name),''), coalesce(trim(p_phone),''), coalesce(lower(trim(p_email)),''));
  return c;
end $$;

-- What an invite is for (shown on the welcome screen before joining)
create or replace function public.invite_info(p_code text)
returns table(company text, role text, name text)
language sql stable security definer set search_path = public as $$
  select w.name, i.role, i.name from invites i join workspaces w on w.id = i.workspace_id
  where auth.uid() is not null and i.code = upper(trim(p_code)) and i.expires_at >= now() and i.uses < i.max_uses
$$;

-- Join with an invite code
create or replace function public.join_workspace(p_code text, p_display_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare inv invites;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  select * into inv from invites where code = upper(trim(p_code)) for update;
  if not found or inv.expires_at < now() or inv.uses >= inv.max_uses then raise exception 'That invite code is not valid'; end if;
  insert into members(workspace_id, user_id, role, display_name, phone)
  values (inv.workspace_id, auth.uid(), inv.role, coalesce(nullif(trim(p_display_name),''), inv.name, ''), coalesce(inv.phone,''))
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
  where m.workspace_id = ws and m.active and not m.support and public.is_member(ws)
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

-- Internal: take one person out of a workspace. Their open leads and pins go to the Open Leads
-- board; sold or closed jobs go to p_actor; their messages, posts, reactions, sessions and invites
-- are deleted; their skip zones are kept under p_actor; they come off every territory.
-- Not callable from the app directly (see the revoke near the end).
create or replace function public._remove_member(ws uuid, p_user uuid, p_actor uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare nm text; nb int := 0; nk int := 0; ms bigint := (extract(epoch from now())*1000)::bigint;
begin
  select coalesce(nullif(display_name,''),'a teammate') into nm from members where workspace_id = ws and user_id = p_user;
  nm := coalesce(nm, 'a teammate');
  update leads set owner_id = p_actor, updated_at = now(),
         data = jsonb_set(data, '{knocks}', coalesce(data->'knocks','[]'::jsonb) || jsonb_build_array(
                jsonb_build_object('t', ms, 'r', 'Reassigned', 'by', p_actor, 'from', p_user, 'note', nm || ' was removed')))
   where workspace_id = ws and owner_id = p_user and status in ('Sold','Cancelled','Finance Denied');
  get diagnostics nk = row_count;
  update leads set owner_id = null, pool = true, origin = 'company', posted_by = p_actor, posted_at = now(),
         claimed_at = null, contacted_at = null, protected_until = null, updated_at = now(),
         data = jsonb_set(jsonb_set(data, '{post}', jsonb_build_object(
                  'job', 'Follow up', 'insurance', coalesce(data->'sale'->>'type','') = 'Insurance', 'window', '',
                  'source', 'Was ' || nm || '''s', 'public_notes', 'Last status: ' || status)),
                '{knocks}', coalesce(data->'knocks','[]'::jsonb) || jsonb_build_array(
                  jsonb_build_object('t', ms, 'r', 'Returned to board', 'by', p_actor, 'from', p_user, 'note', nm || ' was removed')))
   where workspace_id = ws and owner_id = p_user;
  get diagnostics nb = row_count;
  delete from reactions r using feed f where f.id = r.feed_id and f.workspace_id = ws and r.user_id = p_user;
  delete from feed where workspace_id = ws and user_id = p_user;
  delete from messages where workspace_id = ws and (sender_id = p_user or (channel = 'dm' and p_user = any(participants)));
  delete from message_reads where workspace_id = ws and user_id = p_user;
  delete from knock_sessions where workspace_id = ws and user_id = p_user;
  delete from invites where workspace_id = ws and created_by = p_user;
  update skip_zones set created_by = p_actor where workspace_id = ws and created_by = p_user;
  update territories set rep_ids = array_remove(rep_ids, p_user) where workspace_id = ws;
  delete from members where workspace_id = ws and user_id = p_user;
  return jsonb_build_object('board', nb, 'kept', nk);
end $$;

-- Managers: permanently remove a person from the company (they must type the person's name).
create or replace function public.delete_member(ws uuid, p_user uuid, p_confirm text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare m members;
begin
  if not public.is_manager(ws) then raise exception 'Only managers can delete people'; end if;
  select * into m from members where workspace_id = ws and user_id = p_user for update;
  if not found then raise exception 'Person not found'; end if;
  if m.role = 'owner' then raise exception 'The account owner can''t be deleted'; end if;
  if p_user = auth.uid() then raise exception 'You can''t delete yourself here — use Delete my account'; end if;
  if lower(trim(coalesce(p_confirm,''))) <> lower(trim(coalesce(nullif(m.display_name,''),'delete'))) then
    raise exception 'Type their exact name to confirm';
  end if;
  return public._remove_member(ws, p_user, auth.uid());
end $$;

-- Anyone: delete your own RidgeMate account. Solo accounts (and companies where you're the only
-- person) are deleted; in other companies you're removed like a deleted rep, with your open leads
-- going to that company's Open Leads board. If you own a company that still has a team, you must
-- delete that company first. Finally the sign-in itself is removed.
create or replace function public.delete_my_account(p_confirm text)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); w record;
begin
  if me is null then raise exception 'Sign in first'; end if;
  if upper(trim(coalesce(p_confirm,''))) <> 'DELETE' then raise exception 'Type DELETE to confirm'; end if;
  for w in select ws.id, ws.name from workspaces ws join members m on m.workspace_id = ws.id and m.user_id = me where m.role = 'owner' loop
    if exists(select 1 from members where workspace_id = w.id and user_id <> me and not support) then
      raise exception 'You own % — delete that company first (Settings → Delete this company)', w.name;
    end if;
  end loop;
  delete from workspaces where id in (select workspace_id from members where user_id = me and role = 'owner');
  for w in select m.workspace_id, ws.owner_id from members m join workspaces ws on ws.id = m.workspace_id where m.user_id = me loop
    perform public._remove_member(w.workspace_id, me, w.owner_id);
  end loop;
  delete from blocks where user_id = me or blocked_id = me;
  delete from message_reports where reporter_id = me;
  delete from push_subs where user_id = me;
  delete from push_outbox where user_id = me;
  begin
    execute 'delete from auth.users where id = $1' using me;
  exception when others then null;  -- if the project doesn't allow it, the account is still emptied and has no access
  end;
end $$;

-- Owner-only: permanently delete a company (or solo) account and everything in it.
-- The caller must type the account's exact name. Leads, members, invites, messages, feed,
-- territories, skip zones and sessions are removed with it (on delete cascade).
create or replace function public.delete_workspace(ws uuid, p_confirm text)
returns void language plpgsql security definer set search_path = public as $$
declare w workspaces;
begin
  select * into w from workspaces where id = ws for update;
  if not found then raise exception 'Account not found'; end if;
  if w.owner_id is distinct from auth.uid() or public.my_role(ws) is distinct from 'owner' then
    raise exception 'Only the account owner can delete it';
  end if;
  if lower(trim(coalesce(p_confirm,''))) <> lower(trim(w.name)) then
    raise exception 'Type the exact account name to confirm';
  end if;
  delete from workspaces where id = ws;
end $$;

grant execute on all functions in schema public to authenticated;
-- Table access for signed-in users. Row-level security above still decides which rows each person can see or change.
-- (Needed when the project was created with "Automatically expose new tables" turned off.)
grant usage on schema public to authenticated;
revoke execute on function public._remove_member(uuid, uuid, uuid) from public, anon, authenticated;
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
      using (bucket_id = 'photos' and (owner = auth.uid() or public.can_view_all((split_part(name,'/',1))::uuid)))$p$;
  end if;
end $$;

-- =====================================================================
-- Push notifications (phone / tablet / computer)
-- Events below drop a row in push_outbox; the "push" Edge Function sends them.
-- The function makes its own keys the first time it runs — nothing to paste.
-- =====================================================================
do $$ begin
  begin create extension if not exists pg_net; exception when others then null; end;
  begin create extension if not exists pg_cron; exception when others then
    begin create extension if not exists pg_cron with schema pg_catalog; exception when others then null; end;
  end;
end $$;

-- One row per device that turned notifications on. prefs: {"messages":false,…} turns a kind off.
create table if not exists public.push_subs (
  endpoint   text primary key,
  user_id    uuid not null,
  p256dh     text not null,
  auth       text not null,
  prefs      jsonb not null default '{}'::jsonb,
  ua         text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists push_subs_user_idx on public.push_subs(user_id);

create table if not exists public.push_outbox (
  id         bigserial primary key,
  user_id    uuid not null,
  kind       text not null,          -- messages | announce | board | assigned | jobs | followups | test
  title      text not null,
  body       text not null default '',
  url        text not null default './',
  tag        text not null default '',
  created_at timestamptz not null default now(),
  sent_at    timestamptz
);
create index if not exists push_outbox_todo_idx on public.push_outbox(id) where sent_at is null;

-- The sending keys (VAPID) and the function's address. Only the server can read this.
create table if not exists public.push_keys (
  id          int primary key default 1 check (id = 1),
  public_key  text not null,
  private_jwk jsonb not null,
  fn_url      text not null default '',
  created_at  timestamptz not null default now()
);

alter table public.push_subs   enable row level security;
alter table public.push_outbox enable row level security;
alter table public.push_keys   enable row level security;
revoke all on public.push_subs, public.push_outbox, public.push_keys from anon, authenticated;
do $$ begin
  execute 'grant all on public.push_subs, public.push_outbox, public.push_keys to service_role';
  execute 'grant usage, select on sequence public.push_outbox_id_seq to service_role';
exception when others then null; end $$;

-- ---- for the app (signed-in people) ---------------------------------
create or replace function public.push_public_key() returns text
language sql stable security definer set search_path = public as $$
  select public_key from push_keys where id = 1
$$;

create or replace function public.push_register(p_endpoint text, p_p256dh text, p_auth text, p_prefs jsonb default null, p_ua text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare r push_subs;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if coalesce(p_endpoint,'') !~ '^https://' or coalesce(p_p256dh,'') = '' or coalesce(p_auth,'') = '' then
    raise exception 'That device didn''t give a usable notification address';
  end if;
  insert into push_subs(endpoint, user_id, p256dh, auth, prefs, ua)
  values (p_endpoint, auth.uid(), p_p256dh, p_auth, coalesce(p_prefs, '{}'::jsonb), left(coalesce(p_ua,''), 300))
  on conflict (endpoint) do update set
    user_id = auth.uid(), p256dh = excluded.p256dh, auth = excluded.auth, ua = excluded.ua,
    prefs = case when p_prefs is null then push_subs.prefs else excluded.prefs end
  returning * into r;
  return jsonb_build_object('prefs', r.prefs);
end $$;

create or replace function public.push_status(p_endpoint text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('registered', true, 'prefs', prefs) from push_subs where endpoint = p_endpoint and user_id = auth.uid()
$$;

create or replace function public.push_set_prefs(p_endpoint text, p_prefs jsonb) returns void
language sql security definer set search_path = public as $$
  update push_subs set prefs = coalesce(p_prefs, '{}'::jsonb) where endpoint = p_endpoint and user_id = auth.uid()
$$;

create or replace function public.push_unregister(p_endpoint text) returns void
language sql security definer set search_path = public as $$
  delete from push_subs where endpoint = p_endpoint and user_id = auth.uid()
$$;

-- ---- internal --------------------------------------------------------
-- Queue a notification for each person who has it turned on somewhere.
create or replace function public._push(p_users uuid[], p_kind text, p_title text, p_body text, p_url text, p_tag text)
returns void language sql security definer set search_path = public as $$
  insert into push_outbox(user_id, kind, title, body, url, tag)
  select distinct u, p_kind, left(coalesce(p_title,'RUVA'), 120), left(coalesce(p_body,''), 240), coalesce(p_url,'./'), coalesce(p_tag,'')
  from unnest(coalesce(p_users, '{}'::uuid[])) u
  where u is not null and exists (select 1 from push_subs s where s.user_id = u and coalesce(s.prefs->>p_kind,'true') <> 'false')
$$;

-- Wake the Edge Function (after the transaction commits). Quietly does nothing until it's set up.
create or replace function public._push_wake() returns void
language plpgsql security definer set search_path = public as $$
declare u text;
begin
  select fn_url into u from push_keys where id = 1;
  if coalesce(u,'') = '' then return; end if;
  begin
    perform net.http_post(url := u, body := '{}'::jsonb, headers := '{"Content-Type":"application/json"}'::jsonb);
  exception when others then null;
  end;
end $$;

create or replace function public._push_outbox_trg() returns trigger
language plpgsql security definer set search_path = public as $$
begin perform public._push_wake(); return null; end $$;
drop trigger if exists push_outbox_wake on public.push_outbox;
create trigger push_outbox_wake after insert on public.push_outbox for each statement execute function public._push_outbox_trg();

create or replace function public._push_name(ws uuid, u uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select nullif(display_name,'') from members where workspace_id = ws and user_id = u), 'Someone')
$$;

create or replace function public._push_addr(l leads) returns text
language sql immutable as $$
  select coalesce(nullif(trim(l.num || ' ' || l.street), ''), nullif(l.name, ''), 'a lead')
$$;

-- New chat messages
create or replace function public._push_on_message() returns trigger
language plpgsql security definer set search_path = public as $$
declare who text := public._push_name(new.workspace_id, new.sender_id); rcpt uuid[]; ttl text; b text; u text := './#team'; k text := 'messages'; l leads;
begin
  b := case when coalesce(new.body,'') <> '' then left(new.body, 200) when new.image_path is not null then '📷 Photo' else '' end;
  if new.channel = 'dm' then
    rcpt := array(select x from unnest(new.participants) x where x <> new.sender_id);
    ttl := who;
  elsif new.channel = 'lead' then
    select * into l from leads where id = new.lead_id and workspace_id = new.workspace_id;
    rcpt := array(select distinct x from (
              select l.owner_id as x
              union select sender_id from messages where workspace_id = new.workspace_id and thread = new.thread) s
            where x is not null and x <> new.sender_id);
    ttl := who || ' · ' || coalesce(public._push_addr(l), 'a lead');
    u := './?lead=' || coalesce(new.lead_id,'') || '#leads';
  else
    rcpt := array(select user_id from members where workspace_id = new.workspace_id and active and not support and user_id <> new.sender_id);
    if new.channel = 'announce' then ttl := '📣 ' || who; k := 'announce'; else ttl := who || ' · Team chat'; end if;
  end if;
  rcpt := array(select x from unnest(rcpt) x
                where exists (select 1 from members where workspace_id = new.workspace_id and user_id = x and active and not support)
                  and not exists (select 1 from blocks where user_id = x and blocked_id = new.sender_id));
  perform public._push(rcpt, k, ttl, b, u, 'msg:' || new.thread);
  return null;
end $$;
drop trigger if exists push_on_message on public.messages;
create trigger push_on_message after insert on public.messages for each row execute function public._push_on_message();

-- Leads: posted to the board, handed to a rep, or changed by someone else
create or replace function public._push_on_lead() returns trigger
language plpgsql security definer set search_path = public as $$
declare actor uuid := auth.uid(); a text := public._push_addr(new); who text; u text := './?lead=' || new.id || '#leads';
        nlog int; olog int; last jsonb; job text := nullif(new.data->'post'->>'job','');
begin
  if new.city <> '' then a := a || ', ' || new.city; end if;
  if new.pool and (tg_op = 'INSERT' or not old.pool) then
    perform public._push(array(select user_id from members where workspace_id = new.workspace_id and active and not support
                                 and role in ('owner','manager','rep') and user_id is distinct from coalesce(actor, new.posted_by)),
                         'board', 'New open lead', a || coalesce(' · ' || job, ''), './#board', 'board:' || new.id);
  end if;
  -- A rep asked the office to order measurements
  if tg_op = 'UPDATE' and coalesce(new.data->'meas'->>'st','') = 'requested'
     and coalesce(old.data->'meas'->>'st','') <> 'requested' then
    perform public._push(array(select user_id from members where workspace_id = new.workspace_id and active and not support
                                 and role in ('owner','manager','office') and user_id is distinct from actor),
                         'meas', 'Measurements requested', a || ' · from ' || public._push_name(new.workspace_id, actor), u, 'meas:' || new.id);
  end if;
  -- A rep asked the office for a contract
  if tg_op = 'UPDATE' and coalesce(new.data->'sale'->'er'->>'st','') = 'requested'
     and coalesce(old.data->'sale'->'er'->>'st','') <> 'requested' then
    perform public._push(array(select user_id from members where workspace_id = new.workspace_id and active and not support
                                 and role in ('owner','manager','office') and user_id is distinct from actor),
                         'jobs', 'Contract requested', a || ' · from ' || public._push_name(new.workspace_id, actor), u, 'contract:' || new.id);
    return null;
  end if;
  -- The office sent the contract: tell the rep(s) on the job
  if tg_op = 'UPDATE' and new.owner_id is not null and actor is distinct from new.owner_id
     and coalesce(new.data->'sale'->'er'->>'st','') = 'ready'
     and coalesce(new.data->'sale'->'er'->>'readyAt','') <> coalesce(old.data->'sale'->'er'->>'readyAt','') then
    perform public._push(array_remove(array[new.owner_id,
                           case when coalesce(new.data->'sale'->>'splitWith','') ~ '^[0-9a-f-]{36}$' then (new.data->'sale'->>'splitWith')::uuid end], null),
      'jobs', 'Contract ready', a || ' · have the homeowner sign it', u, 'contract:' || new.id);
    return null;
  end if;
  -- The homeowner signed: tell the owner, managers and office
  if tg_op = 'UPDATE' and coalesce(new.data->'est'->>'sigAt','') <> '' and coalesce(old.data->'est'->>'sigAt','') = '' then
    perform public._push(array(select user_id from members where workspace_id = new.workspace_id and active and not support
                                 and role in ('owner','manager','office') and user_id is distinct from actor),
      'jobs', 'Contract signed', a || coalesce(' · ' || nullif(new.data->'est'->>'sigName',''), ''), u, 'contract:' || new.id);
    return null;
  end if;
  -- Insurance approved an amount: tell whoever didn't enter it
  if tg_op = 'UPDATE' and coalesce(new.data->'ins'->>'rcv','') <> '' and coalesce(old.data->'ins'->>'rcv','') = '' then
    perform public._push(array(select user_id from members where workspace_id = new.workspace_id and active and not support
                                 and (role in ('owner','manager','office') or user_id = new.owner_id) and user_id is distinct from actor),
      'jobs', 'Insurance approved', a || ' · $' || (new.data->'ins'->>'rcv'), u, 'ins:' || new.id);
    return null;
  end if;
  -- The office approved, denied or delivered a measurement request: tell the rep(s) on the job
  if tg_op = 'UPDATE' and new.owner_id is not null and actor is distinct from new.owner_id
     and coalesce(new.data->'meas'->>'st','') in ('approved','denied','ready')
     and coalesce(new.data->'meas'->>'st','') <> coalesce(old.data->'meas'->>'st','') then
    who := case when actor is null then 'the office' else public._push_name(new.workspace_id, actor) end;
    perform public._push(array_remove(array[new.owner_id,
                           case when coalesce(new.data->'sale'->>'splitWith','') ~ '^[0-9a-f-]{36}$' then (new.data->'sale'->>'splitWith')::uuid end], null),
      'jobs',
      case new.data->'meas'->>'st' when 'approved' then 'Measurements approved'
                                   when 'denied' then 'Measurement request denied'
                                   else 'Measurements ready' end,
      a || case new.data->'meas'->>'st' when 'approved' then ' · ' || who || ' is ordering them'
                                        when 'denied' then coalesce(' · ' || nullif(new.data->'meas'->>'reason',''), ' · by ' || who)
                                        else ' · tap to view the report' end,
      u, 'meas:' || new.id);
    return null;
  end if;
  if new.owner_id is null or not exists (select 1 from members where workspace_id = new.workspace_id and user_id = new.owner_id and active) then
    return null;
  end if;
  if new.owner_id is distinct from actor and (tg_op = 'INSERT' or old.owner_id is distinct from new.owner_id) then
    who := case when actor is null then 'the office' else public._push_name(new.workspace_id, actor) end;
    perform public._push(array[new.owner_id], 'assigned', 'Lead assigned to you', a || ' · from ' || who, u, 'lead:' || new.id);
  elsif tg_op = 'UPDATE' and actor is not null and actor <> new.owner_id and old.owner_id is not distinct from new.owner_id then
    who := public._push_name(new.workspace_id, actor);
    if new.status is distinct from old.status then
      perform public._push(array[new.owner_id], 'jobs', who || ' updated ' || a, 'Status: ' || new.status, u, 'lead:' || new.id);
    else
      nlog := case when jsonb_typeof(new.data->'log') = 'array' then jsonb_array_length(new.data->'log') else 0 end;
      olog := case when jsonb_typeof(old.data->'log') = 'array' then jsonb_array_length(old.data->'log') else 0 end;
      if nlog > olog then
        last := new.data->'log'->(nlog - 1);
        if coalesce(last->>'text','') <> '' then
          perform public._push(array[new.owner_id], 'jobs', 'Note from ' || who || ' · ' || a, left(last->>'text', 200), u, 'lead:' || new.id);
        end if;
      end if;
    end if;
  end if;
  return null;
end $$;
drop trigger if exists push_on_lead on public.leads;
create trigger push_on_lead after insert or update on public.leads for each row execute function public._push_on_lead();

-- Morning reminder: follow-ups due today (and any overdue) for each rep
create or replace function public.push_followups() returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in
    select l.owner_id, count(*) as c,
           count(*) filter (where left(l.follow_at,10) < to_char(now() at time zone coalesce(nullif(w.settings->>'tz',''),'America/New_York'),'YYYY-MM-DD')) as late,
           (array_agg(public._push_addr(l) order by l.follow_at))[1] as first
      from leads l
      join workspaces w on w.id = l.workspace_id
      join members m on m.workspace_id = l.workspace_id and m.user_id = l.owner_id and m.active
     where l.owner_id is not null and l.follow_at <> ''
       and l.status not in ('Not Interested','No Damage','Cancelled','Finance Denied')
       and left(l.follow_at,10) <= to_char(now() at time zone coalesce(nullif(w.settings->>'tz',''),'America/New_York'),'YYYY-MM-DD')
     group by l.owner_id
  loop
    perform public._push(array[r.owner_id], 'followups',
      case when r.c = 1 then '1 follow-up due today' else r.c || ' follow-ups due today' end,
      r.first || case when r.c > 1 then ' and ' || (r.c - 1) || ' more' else '' end || case when r.late > 0 then ' (' || r.late || ' overdue)' else '' end,
      './#followups', 'followups');
    n := n + 1;
  end loop;
  return n;
end $$;

-- Safety net: if anything is still waiting, wake the function again.
create or replace function public.push_retry() returns void
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from push_outbox where sent_at is null and created_at > now() - interval '1 day') then perform public._push_wake(); end if;
end $$;

-- Send yourself a test
create or replace function public.push_test() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  select count(*) into n from push_subs where user_id = auth.uid();
  if n = 0 then raise exception 'Turn on notifications on this device first'; end if;
  insert into push_outbox(user_id, kind, title, body, url, tag)
  values (auth.uid(), 'test', 'RUVA notifications are on', 'This is what a notification looks like.', './#home', 'test');
  return n;
end $$;

-- ---- for the Edge Function only (service role) ----------------------
create or replace function public.push_init(p_public text, p_private jsonb, p_url text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k push_keys;
begin
  select * into k from push_keys where id = 1;
  if not found then
    if p_public is null then raise exception 'no keys'; end if;
    insert into push_keys(id, public_key, private_jwk, fn_url) values (1, p_public, p_private, coalesce(p_url,''))
    on conflict (id) do nothing;
    select * into k from push_keys where id = 1;
  end if;
  if coalesce(p_url,'') <> '' and k.fn_url is distinct from p_url then
    update push_keys set fn_url = p_url where id = 1 returning * into k;
  end if;
  return jsonb_build_object('public_key', k.public_key, 'private_jwk', k.private_jwk, 'fn_url', k.fn_url);
end $$;

create or replace function public.push_claim(p_limit int default 200) returns setof public.push_outbox
language plpgsql security definer set search_path = public as $$
begin
  delete from push_outbox where created_at < now() - interval '7 days';
  return query
    update push_outbox o set sent_at = now()
     where o.id in (select id from push_outbox where sent_at is null and created_at > now() - interval '1 day'
                     order by id limit greatest(1, least(coalesce(p_limit,200), 500)) for update skip locked)
    returning o.*;
end $$;

create or replace function public.push_targets(p_users uuid[]) returns setof public.push_subs
language sql stable security definer set search_path = public as $$
  select * from push_subs where user_id = any(p_users)
$$;

create or replace function public.push_drop(p_endpoints text[]) returns void
language sql security definer set search_path = public as $$
  delete from push_subs where endpoint = any(p_endpoints)
$$;

revoke execute on function public._push(uuid[], text, text, text, text, text) from public, anon, authenticated;
revoke execute on function public._push_wake() from public, anon, authenticated;
revoke execute on function public._push_name(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.push_followups() from public, anon, authenticated;
revoke execute on function public.push_retry() from public, anon, authenticated;
revoke execute on function public.push_init(text, jsonb, text) from public, anon, authenticated;
revoke execute on function public.push_claim(int) from public, anon, authenticated;
revoke execute on function public.push_targets(uuid[]) from public, anon, authenticated;
revoke execute on function public.push_drop(text[]) from public, anon, authenticated;
do $$ begin
  execute 'grant execute on function public.push_init(text, jsonb, text), public.push_claim(int), public.push_targets(uuid[]), public.push_drop(text[]) to service_role';
exception when others then null; end $$;

-- Schedules: follow-up reminders every morning at 8 AM Eastern (1 PM UTC), and a retry every 10 minutes.
do $$ begin
  begin perform cron.unschedule('ridgeline-followups'); exception when others then null; end;
  begin perform cron.unschedule('ridgeline-push-retry'); exception when others then null; end;
  begin
    perform cron.schedule('ridgeline-followups', '0 13 * * *', 'select public.push_followups()');
    perform cron.schedule('ridgeline-push-retry', '*/10 * * * *', 'select public.push_retry()');
  exception when others then null; end;
end $$;

-- =====================================================================
-- Delete a whole chat. Direct messages: either person in the conversation (gone for both).
-- Team chat, announcements, lead chats: managers only. Returns the photo paths that were in it.
-- =====================================================================
create or replace function public.delete_thread(ws uuid, p_thread text) returns text[]
language plpgsql security definer set search_path = public as $$
declare paths text[]; parts text[];
begin
  if auth.uid() is null or not public.is_member(ws) then raise exception 'Not allowed'; end if;
  if p_thread like 'dm:%' then
    parts := string_to_array(substr(p_thread, 4), ':');
    if not (auth.uid()::text = any(parts)) then raise exception 'You can only delete your own conversations'; end if;
  elsif not public.is_manager(ws) then
    raise exception 'Only managers can clear this chat';
  end if;
  select coalesce(array_agg(image_path) filter (where image_path is not null), '{}') into paths
    from messages where workspace_id = ws and thread = p_thread;
  delete from messages where workspace_id = ws and thread = p_thread;
  delete from message_reads where workspace_id = ws and thread = p_thread;
  delete from push_outbox where tag = 'msg:' || p_thread and sent_at is null;
  if cardinality(paths) > 0 and exists (select 1 from pg_namespace where nspname = 'storage') then
    begin execute 'delete from storage.objects where bucket_id = ''photos'' and name = any($1)' using paths;
    exception when others then null; end;
  end if;
  return paths;
end $$;

-- =====================================================================
-- Billing (Stripe). 14-day free trial, then Solo $19/mo or Team $39 per person/mo.
-- The "billing" Edge Function talks to Stripe; the app only reads these columns.
-- Accounts that existed before billing launched are free (billing_exempt).
-- =====================================================================
alter table public.workspaces add column if not exists trial_ends_at      timestamptz not null default now() + interval '14 days';
alter table public.workspaces add column if not exists sub_status         text not null default 'none';  -- none | trialing | active | past_due | unpaid | canceled | incomplete…
alter table public.workspaces add column if not exists billing_exempt     boolean not null default false;
alter table public.workspaces add column if not exists stripe_customer    text;
alter table public.workspaces add column if not exists stripe_sub         text;
alter table public.workspaces add column if not exists stripe_mode        text;                          -- test | live
alter table public.workspaces add column if not exists seats              int;
alter table public.workspaces add column if not exists period_end         timestamptz;
alter table public.workspaces add column if not exists cancel_at_period_end boolean not null default false;
-- Everything created before billing launched stays free.
update public.workspaces set billing_exempt = true where created_at < '2026-11-06' and not billing_exempt;

-- Is this account allowed to add and change things right now?
create or replace function public.ws_active(ws uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select billing_exempt or sub_status in ('active','trialing','past_due') or trial_ends_at > now()
                   from workspaces where id = ws), false)
$$;

-- Owners and managers edit settings, but billing fields only change through Stripe.
create or replace function public.workspaces_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user not in ('authenticated','anon') then return new; end if;
  if new.owner_id is distinct from old.owner_id or new.id is distinct from old.id then
    raise exception 'The account owner cannot be changed here';
  end if;
  new.trial_ends_at := old.trial_ends_at; new.sub_status := old.sub_status; new.billing_exempt := old.billing_exempt;
  new.stripe_customer := old.stripe_customer; new.stripe_sub := old.stripe_sub; new.stripe_mode := old.stripe_mode;
  new.seats := old.seats; new.period_end := old.period_end; new.cancel_at_period_end := old.cancel_at_period_end;
  return new;
end $$;

-- When the trial is over and nobody has paid, the account is read-only:
-- people can still sign in, look at everything and export it, but not add or change things.
create or replace function public.billing_write_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user not in ('authenticated','anon') then return new; end if;
  if not public.ws_active(new.workspace_id) then
    raise exception 'RIDGEMATE_INACTIVE: This RUVA account needs a plan. The owner can choose one in Settings → Plan & billing.';
  end if;
  return new;
end $$;
do $$ declare t text; begin
  foreach t in array array['leads','messages','feed','knock_sessions','territories','skip_zones'] loop
    execute format('drop trigger if exists billing_guard on public.%I', t);
    execute format('create trigger billing_guard before insert or update on public.%I for each row execute function public.billing_write_guard()', t);
  end loop;
end $$;

-- Stripe settings the function keeps for itself (prices, webhook secret, seat-sync token). Server only.
create table if not exists public.billing_cfg (
  mode        text primary key,           -- test | live
  price_solo  text,
  price_team  text,
  webhook_id  text,
  webhook_secret text,
  fn_url      text not null default '',
  wake_token  text not null default '',
  updated_at  timestamptz not null default now()
);
alter table public.billing_cfg enable row level security;
revoke all on public.billing_cfg from anon, authenticated;
do $$ begin execute 'grant all on public.billing_cfg to service_role'; exception when others then null; end $$;

-- Billing summary for the app (owner sees the Stripe bits; everyone sees whether it's active)
create or replace function public.billing_info(ws uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare w workspaces; n int;
begin
  if not public.is_member(ws) then raise exception 'Not allowed'; end if;
  select * into w from workspaces where id = ws;
  select count(*) into n from members where workspace_id = ws and active and not support;
  return jsonb_build_object('kind', w.kind, 'active', public.ws_active(ws), 'exempt', w.billing_exempt,
    'status', w.sub_status, 'trial_ends_at', w.trial_ends_at, 'period_end', w.period_end,
    'cancel_at_period_end', w.cancel_at_period_end, 'seats', coalesce(w.seats, 0), 'people', n,
    'subscribed', w.stripe_sub is not null and w.sub_status not in ('canceled','incomplete_expired'),
    'is_owner', w.owner_id = auth.uid());
end $$;

-- ---- for the billing Edge Function only (service role) -----------------
create or replace function public.billing_cfg_get(p_mode text) returns jsonb
language sql stable security definer set search_path = public as $$
  select to_jsonb(c) from billing_cfg c where mode = p_mode
$$;
create or replace function public.billing_cfg_set(p_mode text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r billing_cfg;
begin
  insert into billing_cfg(mode) values (p_mode) on conflict (mode) do nothing;
  update billing_cfg set
    price_solo     = coalesce(p->>'price_solo', price_solo),
    price_team     = coalesce(p->>'price_team', price_team),
    webhook_id     = coalesce(p->>'webhook_id', webhook_id),
    webhook_secret = coalesce(p->>'webhook_secret', webhook_secret),
    fn_url         = coalesce(p->>'fn_url', fn_url),
    wake_token     = coalesce(p->>'wake_token', wake_token),
    updated_at     = now()
  where mode = p_mode returning * into r;
  return to_jsonb(r);
end $$;
-- Who is asking, and may they manage billing for this account?
create or replace function public.billing_ws(ws uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb; em text;
begin
  select to_jsonb(w) || jsonb_build_object('people', (select count(*) from members m where m.workspace_id = w.id and m.active and not m.support))
    into r from workspaces w where w.id = ws;
  if r is null then return null; end if;
  begin execute 'select email from auth.users where id = $1' into em using (r->>'owner_id')::uuid; exception when others then em := null; end;
  return r || jsonb_build_object('owner_email', em);
end $$;
create or replace function public.billing_set(ws uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  update workspaces set
    stripe_customer = case when p ? 'stripe_customer' then p->>'stripe_customer' else stripe_customer end,
    stripe_sub      = case when p ? 'stripe_sub' then p->>'stripe_sub' else stripe_sub end,
    stripe_mode     = case when p ? 'stripe_mode' then p->>'stripe_mode' else stripe_mode end,
    sub_status      = coalesce(p->>'sub_status', sub_status),
    seats           = case when p ? 'seats' then (p->>'seats')::int else seats end,
    period_end      = case when p ? 'period_end' then (p->>'period_end')::timestamptz else period_end end,
    cancel_at_period_end = coalesce((p->>'cancel_at_period_end')::boolean, cancel_at_period_end)
  where id = ws;
end $$;

-- Team seat count follows the people in the company: wake the function when someone joins or leaves.
create or replace function public._billing_wake() returns trigger
language plpgsql security definer set search_path = public as $$
declare ws uuid := coalesce(new.workspace_id, old.workspace_id); w workspaces; c billing_cfg;
begin
  select * into w from workspaces where id = ws;
  if w.id is null or w.stripe_sub is null or w.kind <> 'company' then return null; end if;
  select * into c from billing_cfg where mode = coalesce(w.stripe_mode, 'test');
  if c.fn_url is null or c.fn_url = '' then return null; end if;
  begin
    perform net.http_post(url := c.fn_url, body := jsonb_build_object('action','sync','ws',ws,'token',c.wake_token),
                          headers := '{"Content-Type":"application/json"}'::jsonb);
  exception when others then null;
  end;
  return null;
end $$;
drop trigger if exists billing_seats on public.members;
create trigger billing_seats after insert or delete or update of active on public.members for each row execute function public._billing_wake();

revoke execute on function public.billing_cfg_get(text) from public, anon, authenticated;
revoke execute on function public.billing_cfg_set(text, jsonb) from public, anon, authenticated;
revoke execute on function public.billing_ws(uuid) from public, anon, authenticated;
revoke execute on function public.billing_set(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public._billing_wake() from public, anon, authenticated;
do $$ begin
  execute 'grant execute on function public.billing_cfg_get(text), public.billing_cfg_set(text, jsonb), public.billing_ws(uuid), public.billing_set(uuid, jsonb) to service_role';
exception when others then null; end $$;

-- =====================================================================
-- Comp codes: give an account free use (forever, or for some months).
-- You (platform admins) make codes in the app: Settings → Comp codes.
-- An owner types the code in Settings → Plan & billing → Have a code?
-- =====================================================================
alter table public.workspaces add column if not exists comp_until timestamptz;
alter table public.workspaces add column if not exists comp_code  text;

create table if not exists public.platform_admins (user_id uuid primary key);
create table if not exists public.comp_codes (
  code       text primary key,
  note       text not null default '',
  months     int,                       -- null = free forever
  max_uses   int not null default 1,
  uses       int not null default 0,
  expires_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now()
);
alter table public.platform_admins enable row level security;
alter table public.comp_codes enable row level security;
revoke all on public.platform_admins, public.comp_codes from anon, authenticated;

-- You are the platform admin (matched by your sign-in email).
do $$ begin
  execute $q$insert into public.platform_admins(user_id)
             select id from auth.users where lower(email) in ('support@ridgemate.app')
             on conflict do nothing$q$;
exception when others then null; end $$;

-- Admin emails: whoever signs in with one of these is a RidgeMate admin (no need to exist first)
create table if not exists public.platform_admin_emails (email text primary key);
alter table public.platform_admin_emails enable row level security;
revoke all on public.platform_admin_emails from anon, authenticated;
insert into public.platform_admin_emails values ('support@ridgemate.app') on conflict do nothing;
delete from public.platform_admin_emails where lower(email) not in ('support@ridgemate.app','support@useruva.com','thadjacobs@useruva.com');
create or replace function public.is_platform_admin() returns boolean
language plpgsql stable security definer set search_path = public as $$
declare e text;
begin
  if auth.uid() is null then return false; end if;
  if exists(select 1 from platform_admins where user_id = auth.uid()) then return true; end if;
  begin execute 'select lower(email) from auth.users where id = $1' into e using auth.uid(); exception when others then e := null; end;
  return e is not null and exists(select 1 from platform_admin_emails where lower(email) = e);
end $$;

create or replace function public.ws_active(ws uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select billing_exempt or coalesce(comp_until > now(), false) or sub_status in ('active','trialing','past_due') or trial_ends_at > now()
                   from workspaces where id = ws), false)
$$;

create or replace function public.workspaces_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user not in ('authenticated','anon') then return new; end if;
  if new.owner_id is distinct from old.owner_id or new.id is distinct from old.id then
    raise exception 'The account owner cannot be changed here';
  end if;
  new.trial_ends_at := old.trial_ends_at; new.sub_status := old.sub_status; new.billing_exempt := old.billing_exempt;
  new.stripe_customer := old.stripe_customer; new.stripe_sub := old.stripe_sub; new.stripe_mode := old.stripe_mode;
  new.seats := old.seats; new.period_end := old.period_end; new.cancel_at_period_end := old.cancel_at_period_end;
  new.comp_until := old.comp_until; new.comp_code := old.comp_code;
  return new;
end $$;

create or replace function public.billing_info(ws uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare w workspaces; n int;
begin
  if not public.is_member(ws) then raise exception 'Not allowed'; end if;
  select * into w from workspaces where id = ws;
  select count(*) into n from members where workspace_id = ws and active and not support;
  return jsonb_build_object('kind', w.kind, 'active', public.ws_active(ws), 'exempt', w.billing_exempt,
    'comp_until', case when w.comp_until > now() then w.comp_until end, 'comp_code', w.comp_code,
    'status', w.sub_status, 'trial_ends_at', w.trial_ends_at, 'period_end', w.period_end,
    'cancel_at_period_end', w.cancel_at_period_end, 'seats', coalesce(w.seats, 0), 'people', n,
    'subscribed', w.stripe_sub is not null and w.sub_status not in ('canceled','incomplete_expired'),
    'is_owner', w.owner_id = auth.uid(), 'platform_admin', public.is_platform_admin());
end $$;

-- Owner: redeem a code
create or replace function public.redeem_comp_code(ws uuid, p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare w workspaces; c comp_codes; k text := upper(regexp_replace(coalesce(p_code,''), '[^A-Za-z0-9]', '', 'g'));
begin
  select * into w from workspaces where id = ws;
  if w.id is null or w.owner_id <> auth.uid() then raise exception 'Only the account owner can use a code'; end if;
  if w.billing_exempt then raise exception 'This account is already free'; end if;
  if w.stripe_sub is not null and w.sub_status in ('active','trialing','past_due') then
    raise exception 'You have a paid plan — cancel it in Manage billing first, then enter the code';
  end if;
  select * into c from comp_codes where upper(regexp_replace(code, '[^A-Za-z0-9]', '', 'g')) = k for update;
  if c.code is null or k = '' then raise exception 'That code isn''t valid'; end if;
  if c.expires_at is not null and c.expires_at < now() then raise exception 'That code has expired'; end if;
  if c.uses >= c.max_uses then raise exception 'That code has already been used'; end if;
  update comp_codes set uses = uses + 1 where code = c.code;
  if c.months is null then
    update workspaces set billing_exempt = true, comp_code = c.code where id = ws;
  else
    update workspaces set comp_until = greatest(coalesce(comp_until, now()), now()) + make_interval(months => c.months), comp_code = c.code where id = ws;
  end if;
  return public.billing_info(ws);
end $$;

-- Platform admin: make, list and turn off codes
create or replace function public.comp_code_create(p_code text, p_note text, p_months int, p_max_uses int, p_expires_days int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k text := upper(regexp_replace(coalesce(p_code,''), '[^A-Za-z0-9-]', '', 'g')); r comp_codes;
begin
  if not public.is_platform_admin() then raise exception 'Not allowed'; end if;
  if k = '' then k := 'RM-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6)); end if;
  if length(k) < 4 then raise exception 'Make the code at least 4 letters or numbers'; end if;
  insert into comp_codes(code, note, months, max_uses, expires_at, created_by)
  values (k, coalesce(p_note,''), case when p_months > 0 then p_months end, greatest(1, coalesce(p_max_uses,1)),
          case when p_expires_days > 0 then now() + make_interval(days => p_expires_days) end, auth.uid())
  returning * into r;
  return to_jsonb(r);
exception when unique_violation then raise exception 'That code already exists — pick another';
end $$;
create or replace function public.comp_codes_list() returns setof public.comp_codes
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'Not allowed'; end if;
  return query select * from comp_codes order by created_at desc limit 200;
end $$;
create or replace function public.comp_code_disable(p_code text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'Not allowed'; end if;
  update comp_codes set max_uses = uses where code = p_code;
end $$;

-- =====================================================================
-- RUVA support console (admin.ridgemate.app)
-- Platform admins can look up accounts and fix things. They never see private messages.
-- Homeowner details are visible only while the owner has turned on support access.
-- Everything an admin does is written to admin_log, which the account's owner can read.
-- =====================================================================
alter table public.support_grants enable row level security;
revoke all on public.support_grants from anon, authenticated;

create table if not exists public.admin_log (
  id           bigserial primary key,
  workspace_id uuid,
  actor        uuid,
  by_support   boolean not null default true,
  action       text not null,
  created_at   timestamptz not null default now()
);
create index if not exists admin_log_ws_idx on public.admin_log(workspace_id, created_at desc);
alter table public.admin_log enable row level security;
revoke all on public.admin_log from anon, authenticated;

-- Deleted leads are kept 30 days so support can bring one back
create table if not exists public.leads_trash (
  id           bigserial primary key,
  workspace_id uuid not null,
  lead         jsonb not null,
  deleted_by   uuid,
  deleted_at   timestamptz not null default now()
);
create index if not exists leads_trash_ws_idx on public.leads_trash(workspace_id, deleted_at desc);
alter table public.leads_trash enable row level security;
revoke all on public.leads_trash from anon, authenticated;
create or replace function public._lead_to_trash() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- only leads deleted one at a time; deleting a whole company or account (a cascade) keeps nothing
  if pg_trigger_depth() <= 1 and auth.uid() is not null then
    insert into leads_trash(workspace_id, lead, deleted_by) values (old.workspace_id, to_jsonb(old), auth.uid());
  end if;
  return old;
end $$;
drop trigger if exists lead_to_trash on public.leads;
create trigger lead_to_trash before delete on public.leads for each row execute function public._lead_to_trash();
do $$ begin
  begin perform cron.unschedule('ridgemate-trash-purge'); exception when others then null; end;
  begin perform cron.schedule('ridgemate-trash-purge', '30 7 * * *', $c$delete from public.leads_trash where deleted_at < now() - interval '30 days'; delete from public.admin_log where created_at < now() - interval '2 years'$c$);
  exception when others then null; end;
end $$;

create or replace function public._alog(ws uuid, p_action text, p_support boolean default true) returns void
language sql security definer set search_path = public as $$
  insert into admin_log(workspace_id, actor, by_support, action) values (ws, auth.uid(), p_support, left(p_action, 400))
$$;
create or replace function public._need_admin() returns void
language plpgsql stable security definer set search_path = public as $$
begin if not public.is_platform_admin() then raise exception 'Not allowed'; end if; end $$;
create or replace function public._email_of(u uuid) returns text
language plpgsql stable security definer set search_path = public as $$
declare e text;
begin
  begin execute 'select email from auth.users where id = $1' into e using u; exception when others then e := null; end;
  return e;
end $$;
create or replace function public._grant_live(ws uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from support_grants where workspace_id = ws and expires_at > now())
$$;

-- ---- for owners, in the app ----------------------------------------------
create or replace function public.support_grant(ws uuid, p_hours int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h int := greatest(1, least(coalesce(p_hours, 24), 24 * 14));
begin
  if public.my_role(ws) is distinct from 'owner' then raise exception 'Only the account owner can allow support access'; end if;
  insert into support_grants(workspace_id, granted_by, expires_at) values (ws, auth.uid(), now() + make_interval(hours => h))
  on conflict (workspace_id) do update set granted_by = excluded.granted_by, expires_at = excluded.expires_at, created_at = now();
  perform public._alog(ws, 'Support access turned on for ' || case when h % 24 = 0 then (h/24) || ' day' || case when h/24 > 1 then 's' else '' end else h || ' hours' end, false);
  return public.support_info(ws);
end $$;
create or replace function public.support_revoke(ws uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if public.my_role(ws) is distinct from 'owner' then raise exception 'Only the account owner can change support access'; end if;
  delete from support_grants where workspace_id = ws;
  delete from members where workspace_id = ws and support;
  perform public._alog(ws, 'Support access turned off', false);
  return public.support_info(ws);
end $$;
create or replace function public.support_info(ws uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_manager(ws) then raise exception 'Only owners and managers can see this'; end if;
  return jsonb_build_object(
    'expires_at', (select expires_at from support_grants where workspace_id = ws and expires_at > now()),
    'log', coalesce((select jsonb_agg(jsonb_build_object('at', a.created_at, 'action', a.action, 'support', a.by_support,
              'by', case when a.by_support then 'RUVA support' else coalesce((select nullif(display_name,'') from members where workspace_id = ws and user_id = a.actor), 'Owner') end)
              order by a.created_at desc)
            from (select * from admin_log where workspace_id = ws order by created_at desc limit 100) a), '[]'::jsonb));
end $$;

-- ---- for platform admins (support console) -------------------------------
create or replace function public.admin_whoami() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  return jsonb_build_object('admin', public.is_platform_admin(), 'email', public._email_of(auth.uid()));
end $$;

create or replace function public.admin_search(p_q text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare q text := '%' || lower(trim(coalesce(p_q,''))) || '%'; r jsonb;
begin
  perform public._need_admin();
  with hits as (
    select w.id from workspaces w where lower(w.name) like q
    union
    select m.workspace_id from members m where not m.support and (lower(m.display_name) like q or lower(coalesce(public._email_of(m.user_id),'')) like q)
  )
  select coalesce(jsonb_agg(x order by x->>'created_at' desc), '[]'::jsonb) into r from (
    select jsonb_build_object('id', w.id, 'name', w.name, 'kind', w.kind, 'created_at', w.created_at,
      'owner', (select nullif(display_name,'') from members where workspace_id = w.id and user_id = w.owner_id),
      'owner_email', public._email_of(w.owner_id),
      'people', (select count(*) from members where workspace_id = w.id and active and not support),
      'active', public.ws_active(w.id), 'exempt', w.billing_exempt, 'comp_until', w.comp_until,
      'status', w.sub_status, 'trial_ends_at', w.trial_ends_at, 'grant', public._grant_live(w.id)) x
    from workspaces w where w.id in (select id from hits) limit 60) t;
  return r;
end $$;

create or replace function public.admin_account(ws uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare w workspaces; r jsonb;
begin
  perform public._need_admin();
  select * into w from workspaces where id = ws;
  if w.id is null then raise exception 'Account not found'; end if;
  r := jsonb_build_object(
    'id', w.id, 'name', w.name, 'kind', w.kind, 'created_at', w.created_at, 'owner_id', w.owner_id, 'owner_email', public._email_of(w.owner_id),
    'active', public.ws_active(ws), 'exempt', w.billing_exempt, 'comp_until', w.comp_until, 'comp_code', w.comp_code,
    'status', w.sub_status, 'trial_ends_at', w.trial_ends_at, 'period_end', w.period_end, 'cancel_at_period_end', w.cancel_at_period_end,
    'seats', w.seats, 'stripe_customer', w.stripe_customer, 'stripe_mode', w.stripe_mode,
    'grant_until', (select expires_at from support_grants where workspace_id = ws and expires_at > now()),
    'members', coalesce((select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'name', m.display_name, 'role', m.role, 'active', m.active,
                  'email', public._email_of(m.user_id), 'joined_at', m.joined_at, 'support', m.support,
                  'leads', (select count(*) from leads l where l.workspace_id = ws and l.owner_id = m.user_id)) order by m.support, m.joined_at)
                from members m where m.workspace_id = ws), '[]'::jsonb),
    'counts', jsonb_build_object(
      'leads', (select count(*) from leads where workspace_id = ws),
      'board', (select count(*) from leads where workspace_id = ws and pool),
      'sold', (select count(*) from leads where workspace_id = ws and status = 'Sold'),
      'photos', (select coalesce(sum(case when jsonb_typeof(data->'photos') = 'array' then jsonb_array_length(data->'photos') else 0 end),0) from leads where workspace_id = ws),
      'messages', (select count(*) from messages where workspace_id = ws),
      'trash', (select count(*) from leads_trash where workspace_id = ws and deleted_at > now() - interval '30 days')),
    'log', coalesce((select jsonb_agg(jsonb_build_object('at', a.created_at, 'action', a.action, 'support', a.by_support,
              'by', case when a.by_support then coalesce(public._email_of(a.actor), 'Support') else 'Owner' end) order by a.created_at desc)
            from (select * from admin_log where workspace_id = ws order by created_at desc limit 60) a), '[]'::jsonb));
  return r;
end $$;

create or replace function public.admin_extend_trial(ws uuid, p_days int) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public._need_admin();
  if coalesce(p_days,0) < 1 or p_days > 365 then raise exception 'Pick 1 to 365 days'; end if;
  update workspaces set trial_ends_at = greatest(trial_ends_at, now()) + make_interval(days => p_days) where id = ws;
  perform public._alog(ws, 'Free trial extended ' || p_days || ' day' || case when p_days > 1 then 's' else '' end);
end $$;

create or replace function public.admin_comp(ws uuid, p_months int) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public._need_admin();
  if coalesce(p_months,0) <= 0 then
    update workspaces set billing_exempt = true, comp_code = 'SUPPORT' where id = ws;
    perform public._alog(ws, 'Account made free (comped) by support');
  else
    update workspaces set comp_until = greatest(coalesce(comp_until, now()), now()) + make_interval(months => p_months), comp_code = 'SUPPORT' where id = ws;
    perform public._alog(ws, 'Comped ' || p_months || ' month' || case when p_months > 1 then 's' else '' end || ' by support');
  end if;
end $$;
create or replace function public.admin_uncomp(ws uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public._need_admin();
  update workspaces set billing_exempt = false, comp_until = null, comp_code = null where id = ws;
  perform public._alog(ws, 'Comp removed — back to normal billing');
end $$;

create or replace function public.admin_set_member(ws uuid, p_user uuid, p_role text, p_active boolean) returns void
language plpgsql security definer set search_path = public as $$
declare m members; nm text;
begin
  perform public._need_admin();
  select * into m from members where workspace_id = ws and user_id = p_user;
  if m.user_id is null then raise exception 'Person not found'; end if;
  if m.role = 'owner' then raise exception 'Use Transfer ownership to change the owner'; end if;
  if p_role is not null and p_role not in ('manager','rep','office') then raise exception 'Unknown role'; end if;
  nm := coalesce(nullif(m.display_name,''), 'a teammate');
  update members set role = coalesce(p_role, role), active = coalesce(p_active, active) where workspace_id = ws and user_id = p_user;
  if p_role is not null and p_role <> m.role then perform public._alog(ws, nm || ' changed from ' || m.role || ' to ' || p_role); end if;
  if p_active is not null and p_active <> m.active then perform public._alog(ws, nm || case when p_active then ' reactivated' else ' deactivated' end); end if;
end $$;

create or replace function public.admin_remove_member(ws uuid, p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m members; w workspaces; r jsonb;
begin
  perform public._need_admin();
  select * into m from members where workspace_id = ws and user_id = p_user;
  select * into w from workspaces where id = ws;
  if m.user_id is null then raise exception 'Person not found'; end if;
  if m.role = 'owner' then raise exception 'Transfer ownership first'; end if;
  r := public._remove_member(ws, p_user, w.owner_id);
  perform public._alog(ws, coalesce(nullif(m.display_name,''),'A teammate') || ' removed — ' || (r->>'board') || ' open lead(s) to the board');
  return r;
end $$;

create or replace function public.admin_transfer_owner(ws uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare w workspaces; m members;
begin
  perform public._need_admin();
  select * into w from workspaces where id = ws;
  select * into m from members where workspace_id = ws and user_id = p_user and active and not support;
  if m.user_id is null then raise exception 'That person isn''t an active member of this account'; end if;
  if p_user = w.owner_id then return; end if;
  update members set role = 'manager' where workspace_id = ws and user_id = w.owner_id;
  update members set role = 'owner' where workspace_id = ws and user_id = p_user;
  update workspaces set owner_id = p_user where id = ws;
  perform public._alog(ws, 'Ownership transferred to ' || coalesce(nullif(m.display_name,''), public._email_of(p_user), 'a member') || ' (previous owner is now a manager)');
end $$;

create or replace function public.admin_invite(ws uuid, p_role text) returns text
language plpgsql security definer set search_path = public as $$
declare c text; w workspaces;
begin
  perform public._need_admin();
  if p_role not in ('manager','rep','office') then raise exception 'Unknown role'; end if;
  select * into w from workspaces where id = ws;
  c := upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  insert into invites(code, workspace_id, role, created_by) values (c, ws, p_role, w.owner_id);
  perform public._alog(ws, 'Support made a ' || p_role || ' invite code');
  return c;
end $$;

create or replace function public.admin_change_email(p_user uuid, p_email text) returns void
language plpgsql security definer set search_path = public as $$
declare e text := lower(trim(coalesce(p_email,''))); old text := public._email_of(p_user); n int; ws uuid;
begin
  perform public._need_admin();
  if e !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'That doesn''t look like an email address'; end if;
  begin
    execute 'select count(*) from auth.users where lower(email) = $1 and id <> $2' into n using e, p_user;
    if n > 0 then raise exception 'EMAIL_TAKEN'; end if;
    execute 'update auth.users set email = $1, email_change = '''', email_change_token_new = '''', email_change_token_current = '''', updated_at = now() where id = $2' using e, p_user;
    begin
      execute 'update auth.identities set identity_data = identity_data || jsonb_build_object(''email'', $1::text), updated_at = now() where user_id = $2 and provider = ''email''' using e, p_user;
    exception when others then null; end;
  exception
    when raise_exception then
      if sqlerrm = 'EMAIL_TAKEN' then raise exception 'Another RUVA login already uses %', e; end if; raise;
    when others then
      raise exception 'Couldn''t change it from here (%). Change it in Supabase → Authentication → Users instead.', sqlerrm;
  end;
  for ws in select workspace_id from members where user_id = p_user and not support loop
    perform public._alog(ws, 'Sign-in email changed from ' || coalesce(old,'?') || ' to ' || e);
  end loop;
end $$;

create or replace function public.admin_move_leads(ws uuid, p_from uuid, p_to uuid) returns int
language plpgsql security definer set search_path = public as $$
declare n int; w workspaces; nm text; ms bigint := (extract(epoch from now())*1000)::bigint;
begin
  perform public._need_admin();
  select * into w from workspaces where id = ws;
  nm := coalesce((select nullif(display_name,'') from members where workspace_id = ws and user_id = p_from), 'a teammate');
  if p_to is null then
    update leads set owner_id = null, pool = true, origin = 'company', posted_by = w.owner_id, posted_at = now(),
           claimed_at = null, contacted_at = null, protected_until = null, updated_at = now(),
           data = jsonb_set(data, '{post}', jsonb_build_object('job','Follow up','insurance', coalesce(data->'sale'->>'type','') = 'Insurance','window','',
                    'source','Was ' || nm || '''s','public_notes','Last status: ' || status))
     where workspace_id = ws and owner_id = p_from and status not in ('Sold','Cancelled','Finance Denied');
    get diagnostics n = row_count;
    perform public._alog(ws, n || ' open lead(s) from ' || nm || ' moved to the Open Leads board');
  else
    if not exists(select 1 from members where workspace_id = ws and user_id = p_to and active and not support) then raise exception 'Pick an active member'; end if;
    update leads set owner_id = p_to, updated_at = now(),
           data = jsonb_set(data, '{knocks}', coalesce(data->'knocks','[]'::jsonb) || jsonb_build_array(
                  jsonb_build_object('t', ms, 'r', 'Reassigned', 'by', w.owner_id, 'from', p_from, 'note', 'Moved by support')))
     where workspace_id = ws and owner_id = p_from and status not in ('Sold','Cancelled','Finance Denied');
    get diagnostics n = row_count;
    perform public._alog(ws, n || ' open lead(s) moved from ' || nm || ' to ' || coalesce((select nullif(display_name,'') from members where workspace_id = ws and user_id = p_to), 'a teammate'));
  end if;
  return n;
end $$;

-- Trash shows only the street address (to identify the lead), not homeowner names or phones
create or replace function public.admin_trash(ws uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._need_admin();
  return coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'deleted_at', t.deleted_at,
      'address', nullif(trim(coalesce(t.lead->>'num','') || ' ' || coalesce(t.lead->>'street','') || case when coalesce(t.lead->>'city','') <> '' then ', ' || (t.lead->>'city') else '' end), ''),
      'status', t.lead->>'status',
      'by', coalesce((select nullif(display_name,'') from members where workspace_id = ws and user_id = t.deleted_by), 'someone')) order by t.deleted_at desc)
    from leads_trash t where t.workspace_id = ws and t.deleted_at > now() - interval '30 days'), '[]'::jsonb);
end $$;
create or replace function public.admin_restore_lead(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare t leads_trash; l leads;
begin
  perform public._need_admin();
  select * into t from leads_trash where id = p_id;
  if t.id is null then raise exception 'Not found'; end if;
  l := jsonb_populate_record(null::leads, t.lead);
  if exists(select 1 from leads where id = l.id) then raise exception 'That lead is already back'; end if;
  if l.owner_id is not null and not exists(select 1 from members where workspace_id = l.workspace_id and user_id = l.owner_id and active) then
    l.owner_id := null; l.pool := true;
  end if;
  l.updated_at := now();
  insert into leads select l.*;
  delete from leads_trash where id = p_id;
  perform public._alog(t.workspace_id, 'Deleted lead restored: ' || coalesce(nullif(trim(coalesce(l.num,'') || ' ' || coalesce(l.street,'')),''), 'a lead'));
end $$;

-- Open the account in the app as "RidgeMate Support" (only while the owner allows it)
create or replace function public.admin_open(ws uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g support_grants;
begin
  perform public._need_admin();
  select * into g from support_grants where workspace_id = ws and expires_at > now();
  if g.workspace_id is null then raise exception 'The owner hasn''t turned on support access. Ask them: Settings → Support access → Allow.'; end if;
  if exists(select 1 from members where workspace_id = ws and user_id = auth.uid() and not support) then return; end if;
  insert into members(workspace_id, user_id, role, display_name, support, active)
  values (ws, auth.uid(), 'manager', 'RUVA Support', true, true)
  on conflict (workspace_id, user_id) do update set role = 'manager', active = true, support = true, display_name = 'RUVA Support';
  perform public._alog(ws, 'Support opened the account in the app (access until ' || to_char(g.expires_at at time zone 'America/New_York', 'Mon DD, HH12:MI AM') || ')');
end $$;
create or replace function public.admin_close(ws uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public._need_admin();
  delete from members where workspace_id = ws and user_id = auth.uid() and support;
  perform public._alog(ws, 'Support closed the account');
end $$;

create or replace function public.admin_recent() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._need_admin();
  return jsonb_build_object(
    'accounts', (select count(*) from workspaces),
    'paying', (select count(*) from workspaces where sub_status in ('active','past_due') and stripe_mode = 'live'),
    'trialing', (select count(*) from workspaces where not billing_exempt and trial_ends_at > now() and stripe_sub is null),
    'grants', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'name', w.name, 'until', g.expires_at)) from support_grants g join workspaces w on w.id = g.workspace_id where g.expires_at > now()), '[]'::jsonb));
end $$;

revoke execute on function public._alog(uuid, text, boolean) from public, anon, authenticated;
revoke execute on function public._email_of(uuid) from public, anon, authenticated;
revoke execute on function public._need_admin() from public, anon, authenticated;
revoke execute on function public._lead_to_trash() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Job profit & commission (owners and managers only)
-- The owner enters materials and labor on a sold job; profit = contract − costs
-- (or his own number). Each rep on the job gets a share of profit (10–50%,
-- 50% combined at most). Reps never see the cost breakdown: they read their
-- own line through my_comms(), which returns contract, total job cost,
-- profit, their share and amount.
-- ---------------------------------------------------------------------
create table if not exists public.job_comm (
  lead_id      text primary key references public.leads(id) on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  materials    numeric not null default 0,
  labor        numeric not null default 0,
  profit       numeric,                         -- null = contract − materials − labor
  contract     numeric not null default 0,      -- snapshot at approval
  shares       jsonb not null default '[]'::jsonb, -- [{user_id, pct, amount}]
  status       text not null default 'approved' check (status in ('approved','paid')),
  approved_by  uuid,
  approved_at  timestamptz,
  paid_at      timestamptz,
  updated_at   timestamptz not null default now()
);
create index if not exists job_comm_ws_idx on public.job_comm(workspace_id);
alter table public.job_comm enable row level security;
drop policy if exists job_comm_mgr on public.job_comm;
create policy job_comm_mgr on public.job_comm for select using (public.is_manager(workspace_id));
revoke insert, update, delete on public.job_comm from anon, authenticated;

create or replace function public._money(t text) returns numeric
language sql immutable as $$ select coalesce(nullif(regexp_replace(coalesce(t,''),'[^0-9.]','','g'),'')::numeric, 0) $$;

create or replace function public.comm_approve(p_lead text, p_materials numeric, p_labor numeric, p_profit numeric, p_shares jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare l leads; ct numeric; pr numeric; tot numeric := 0; s jsonb; out jsonb := '[]'::jsonb; who uuid[] := '{}'; amt numeric; pc numeric;
begin
  select * into l from leads where id = p_lead;
  if l.id is null then raise exception 'Lead not found'; end if;
  if not public.is_manager(l.workspace_id) then raise exception 'Only the owner or a manager can approve commission'; end if;
  if not public.ws_active(l.workspace_id) then raise exception 'RIDGEMATE_INACTIVE: This RUVA account needs a plan.'; end if;
  if jsonb_typeof(p_shares) <> 'array' or jsonb_array_length(p_shares) = 0 or jsonb_array_length(p_shares) > 2 then
    raise exception 'Pick one or two reps'; end if;
  ct := public._money(l.data->'sale'->>'value') + public._money(l.data->'sale'->>'upgrades') + public._money(l.data->'sale'->>'supplements');
  pr := coalesce(p_profit, ct - coalesce(p_materials,0) - coalesce(p_labor,0));
  for s in select * from jsonb_array_elements(p_shares) loop
    pc := (s->>'pct')::numeric;
    if pc not in (10,20,25,30,50) then raise exception 'Rep share must be 10, 20, 25, 30 or 50%%'; end if;
    if not exists (select 1 from members where workspace_id = l.workspace_id and user_id = (s->>'user_id')::uuid and active and not coalesce(support,false)) then
      raise exception 'That rep isn''t on this team'; end if;
    if (s->>'user_id')::uuid = any(who) then raise exception 'Pick two different reps'; end if;
    tot := tot + pc; who := who || (s->>'user_id')::uuid;
    amt := round(greatest(pr,0) * pc / 100, 2);
    out := out || jsonb_build_object('user_id', s->>'user_id', 'pct', pc, 'amount', amt);
  end loop;
  if tot > 50 then raise exception 'Shares can''t add up to more than 50%%'; end if;
  insert into job_comm(lead_id, workspace_id, materials, labor, profit, contract, shares, status, approved_by, approved_at, paid_at, updated_at)
  values (l.id, l.workspace_id, coalesce(p_materials,0), coalesce(p_labor,0), p_profit, ct, out, 'approved', auth.uid(), now(), null, now())
  on conflict (lead_id) do update set materials = excluded.materials, labor = excluded.labor, profit = excluded.profit,
    contract = excluded.contract, shares = excluded.shares, status = 'approved', approved_by = excluded.approved_by,
    approved_at = excluded.approved_at, paid_at = null, updated_at = now();
  for s in select * from jsonb_array_elements(out) loop
    perform public._push(array[(s->>'user_id')::uuid], 'comm', 'Commission approved',
      '$' || to_char((s->>'amount')::numeric, 'FM999,999,990') || ' on ' || trim(l.num || ' ' || l.street), './#money', 'comm:' || l.id);
  end loop;
  return out;
end $$;

create or replace function public.comm_paid(p_lead text, p_paid boolean default true) returns void
language plpgsql security definer set search_path = public as $$
declare c job_comm; s jsonb; l leads;
begin
  select * into c from job_comm where lead_id = p_lead;
  if c.lead_id is null then raise exception 'Approve the commission first'; end if;
  if not public.is_manager(c.workspace_id) then raise exception 'Only the owner or a manager can mark commission paid'; end if;
  update job_comm set status = case when p_paid then 'paid' else 'approved' end, paid_at = case when p_paid then now() end, updated_at = now() where lead_id = p_lead;
  if p_paid then
    select * into l from leads where id = p_lead;
    for s in select * from jsonb_array_elements(c.shares) loop
      perform public._push(array[(s->>'user_id')::uuid], 'comm', 'Commission paid',
        '$' || to_char((s->>'amount')::numeric, 'FM999,999,990') || ' on ' || trim(coalesce(l.num,'') || ' ' || coalesce(l.street,'')), './#money', 'comm:' || p_lead);
    end loop;
  end if;
end $$;

create or replace function public.comm_clear(p_lead text) returns void
language plpgsql security definer set search_path = public as $$
declare w uuid;
begin
  select workspace_id into w from job_comm where lead_id = p_lead;
  if w is null then return; end if;
  if not public.is_manager(w) then raise exception 'Not allowed'; end if;
  delete from job_comm where lead_id = p_lead;
end $$;

-- A rep's own commission lines: totals only, never the cost breakdown.
create or replace function public.my_comms(ws uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'lead_id', c.lead_id, 'status', c.status, 'contract', c.contract,
      'job_cost', c.materials + c.labor,
      'profit', coalesce(c.profit, c.contract - c.materials - c.labor),
      'pct', (s->>'pct')::numeric, 'amount', (s->>'amount')::numeric,
      'split', jsonb_array_length(c.shares) > 1,
      'approved_by', public._push_name(c.workspace_id, c.approved_by),
      'approved_at', c.approved_at, 'paid_at', c.paid_at,
      'num', l.num, 'street', l.street, 'name', l.name) order by c.approved_at desc), '[]'::jsonb)
  from job_comm c join leads l on l.id = c.lead_id
  cross join lateral jsonb_array_elements(c.shares) s
  where c.workspace_id = ws and public.is_member(ws) and (s->>'user_id')::uuid = auth.uid()
$$;
grant execute on function public.comm_approve(text, numeric, numeric, numeric, jsonb), public.comm_paid(text, boolean), public.comm_clear(text), public.my_comms(uuid) to authenticated;
grant select on public.job_comm to authenticated;


-- =====================================================================
-- Share links: a photo page for the homeowner or adjuster, no login needed
create table if not exists public.shares (
  token        text primary key check (length(token) >= 20),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  lead_id      text not null,
  created_by   uuid not null default auth.uid(),
  payload      jsonb not null,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default now() + interval '60 days'
);
alter table public.shares enable row level security;
drop policy if exists shares_rw on public.shares;
create policy shares_rw on public.shares for all to authenticated
  using (public.is_member(workspace_id) and public.can_see_lead(lead_id))
  with check (public.is_member(workspace_id) and public.can_see_lead(lead_id));
grant select, insert, update, delete on public.shares to authenticated;
revoke all on public.shares from anon;
create or replace function public.get_share(p_token text) returns jsonb
language sql stable security definer set search_path = public as $$
  select payload from shares where token = p_token and length(p_token) >= 20 and expires_at > now()
$$;
revoke execute on function public.get_share(text) from public;
grant execute on function public.get_share(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Office data kept safe from older phone apps.
-- The office dashboard stores tasks, emails, documents, job numbers, closed jobs,
-- locations and automatic-task history inside leads.data. A phone still running
-- an older app version doesn't know those keys and would save the lead without
-- them. This puts them back whenever an update leaves one out.
-- ---------------------------------------------------------------------------
create or replace function public._keep_office_keys() returns trigger
language plpgsql as $$
declare k text;
begin
  foreach k in array array['tasks','emails','gdocs','jobNo','closed','branch','fired'] loop
    if (old.data ? k) and not (new.data ? k) then
      new.data := new.data || jsonb_build_object(k, old.data -> k);
    end if;
  end loop;
  return new;
end $$;
drop trigger if exists keep_office_keys on public.leads;
create trigger keep_office_keys before update on public.leads for each row execute function public._keep_office_keys();
-- RUVA: customer feedback form on useruva.com/feedback. Safe to run more than once.
create table if not exists public.feedback (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  name text, company text, answers jsonb not null default '{}'::jsonb
);
alter table public.feedback enable row level security;
revoke all on public.feedback from anon, authenticated;

create or replace function public.submit_feedback(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p is null or jsonb_typeof(p) <> 'object' or pg_column_size(p) > 20000 then raise exception 'Bad form'; end if;
  insert into feedback(name, company, answers)
  values (left(p->>'name', 80), left(p->>'company', 120), p - 'name' - 'company');
end $$;
revoke all on function public.submit_feedback(jsonb) from public;
grant execute on function public.submit_feedback(jsonb) to anon, authenticated;
-- RUVA: private link to read feedback answers, plus a phone notification when someone answers.
create table if not exists public.feedback_key (id int primary key default 1 check (id = 1), k text not null);
alter table public.feedback_key enable row level security;
revoke all on public.feedback_key from anon, authenticated;

create or replace function public.list_feedback(p_k text) returns setof public.feedback
language plpgsql stable security definer set search_path = public as $$
begin
  if p_k is null or not exists (select 1 from feedback_key where k = p_k) then raise exception 'Not allowed'; end if;
  return query select * from feedback order by created_at desc limit 500;
end $$;
revoke all on function public.list_feedback(text) from public;
grant execute on function public.list_feedback(text) to anon, authenticated;

create or replace function public._feedback_notify() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public._push(array(select id from auth.users where lower(email) = 'thaddeusjreugene@icloud.com'), 'feedback',
    'New feedback' || coalesce(' from ' || nullif(new.name, ''), ''), coalesce(nullif(new.company, ''), 'Someone answered your questions'),
    'https://useruva.com/feedback/answers.html', 'feedback');
  return new;
exception when others then return new;
end $$;
drop trigger if exists feedback_notify on public.feedback;
create trigger feedback_notify after insert on public.feedback for each row execute function public._feedback_notify();

-- RUVA HQ: the company's own back office (prospects, founding-spot requests, feedback, launch checklist).
-- Safe to run more than once.

-- Who can sign in to RUVA HQ
insert into public.platform_admin_emails(email) values ('support@ridgemate.app'), ('support@useruva.com'), ('thadjacobs@useruva.com') on conflict do nothing;

-- Prospects: roofing companies you're talking to
create table if not exists public.hq_prospects (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  company text not null default '',
  contact text not null default '',
  phone text not null default '',
  email text not null default '',
  town text not null default '',
  stage text not null default 'To call',
  source text not null default '',
  current_tool text not null default '',
  current_cost text not null default '',
  users text not null default '',
  next_step text not null default '',
  next_date date,
  notes text not null default '',
  log jsonb not null default '[]'::jsonb
);
alter table public.hq_prospects enable row level security;
revoke all on public.hq_prospects from anon, authenticated;

-- Launch checklist
create table if not exists public.hq_tasks (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  title text not null,
  area text not null default 'Launch',
  done boolean not null default false,
  due date,
  note text not null default '',
  sort int not null default 0
);
alter table public.hq_tasks enable row level security;
revoke all on public.hq_tasks from anon, authenticated;

create or replace function public._hq_guard() returns void language plpgsql stable security definer set search_path = public as $$
begin if not public.is_platform_admin() then raise exception 'Not allowed'; end if; end $$;

create or replace function public.hq_prospects() returns setof public.hq_prospects
language plpgsql stable security definer set search_path = public as $$
begin perform _hq_guard(); return query select * from hq_prospects order by updated_at desc; end $$;

create or replace function public.hq_prospect_save(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint := nullif(p->>'id','')::bigint;
begin
  perform _hq_guard();
  if v_id is null then
    insert into hq_prospects(company) values (coalesce(p->>'company','')) returning id into v_id;
  end if;
  update hq_prospects set
    company = coalesce(p->>'company', company), contact = coalesce(p->>'contact', contact),
    phone = coalesce(p->>'phone', phone), email = coalesce(p->>'email', email), town = coalesce(p->>'town', town),
    stage = coalesce(p->>'stage', stage), source = coalesce(p->>'source', source),
    current_tool = coalesce(p->>'current_tool', current_tool), current_cost = coalesce(p->>'current_cost', current_cost),
    users = coalesce(p->>'users', users), next_step = coalesce(p->>'next_step', next_step),
    next_date = case when p ? 'next_date' then nullif(p->>'next_date','')::date else next_date end,
    notes = coalesce(p->>'notes', notes),
    log = case when p ? 'log_add' then log || jsonb_build_array(jsonb_build_object('t', now(), 'text', p->>'log_add')) else log end,
    updated_at = now()
  where id = v_id;
  return v_id;
end $$;

create or replace function public.hq_prospect_delete(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin perform _hq_guard(); delete from hq_prospects where id = p_id; end $$;

create or replace function public.hq_feedback() returns setof public.feedback
language plpgsql stable security definer set search_path = public as $$
begin perform _hq_guard(); return query select * from feedback order by created_at desc limit 500; end $$;

create or replace function public.hq_tasks() returns setof public.hq_tasks
language plpgsql stable security definer set search_path = public as $$
begin perform _hq_guard(); return query select * from hq_tasks order by done, sort, id; end $$;

create or replace function public.hq_task_save(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint := nullif(p->>'id','')::bigint;
begin
  perform _hq_guard();
  if v_id is null then insert into hq_tasks(title, area, sort) values (coalesce(nullif(p->>'title',''),'New task'), coalesce(nullif(p->>'area',''),'Launch'), 999) returning id into v_id; end if;
  update hq_tasks set title = coalesce(nullif(p->>'title',''), title), area = coalesce(nullif(p->>'area',''), area),
    done = coalesce((p->>'done')::boolean, done), note = coalesce(p->>'note', note),
    due = case when p ? 'due' then nullif(p->>'due','')::date else due end
  where id = v_id;
  return v_id;
end $$;

create or replace function public.hq_task_delete(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin perform _hq_guard(); delete from hq_tasks where id = p_id; end $$;

-- Website "Save a founding spot" form
create or replace function public.request_founding(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare v_co text := left(coalesce(p->>'company',''), 120);
begin
  if p is null or jsonb_typeof(p) <> 'object' or pg_column_size(p) > 8000 then raise exception 'Bad form'; end if;
  if v_co = '' or coalesce(p->>'contact','') = '' then raise exception 'Add your name and company'; end if;
  insert into hq_prospects(company, contact, phone, email, town, users, current_tool, stage, source, notes, log)
  values (v_co, left(p->>'contact',80), left(coalesce(p->>'phone',''),40), left(coalesce(p->>'email',''),120), left(coalesce(p->>'town',''),80),
    left(coalesce(p->>'users',''),20), left(coalesce(p->>'current_tool',''),80), 'New request', 'Website', left(coalesce(p->>'notes',''),2000),
    jsonb_build_array(jsonb_build_object('t', now(), 'text', 'Asked for a founding spot on useruva.com')));
  begin
    perform public._push(array(select u.id from auth.users u where lower(u.email) in (select lower(email) from platform_admin_emails) or lower(u.email) = 'thaddeusjreugene@icloud.com'),
      'feedback', 'Founding spot request', v_co || ' · ' || left(p->>'contact',60), './', 'founding');
  exception when others then null; end;
end $$;
revoke all on function public.request_founding(jsonb) from public;
grant execute on function public.request_founding(jsonb) to anon, authenticated;
revoke all on function public.hq_prospects(), public.hq_prospect_save(jsonb), public.hq_prospect_delete(bigint), public.hq_feedback(), public.hq_tasks(), public.hq_task_save(jsonb), public.hq_task_delete(bigint), public._hq_guard() from public;
grant execute on function public.hq_prospects(), public.hq_prospect_save(jsonb), public.hq_prospect_delete(bigint), public.hq_feedback(), public.hq_tasks(), public.hq_task_save(jsonb), public.hq_task_delete(bigint), public._hq_guard() to authenticated;

-- Starting data (only the first time)
do $$ begin
  if not exists (select 1 from hq_prospects) then
    insert into hq_prospects(company, contact, town, stage, source, current_tool, current_cost, next_step, notes, log) values
      ('Response Roofing', 'Gavin Flynn', 'Lancaster, SC', 'Demo done', 'Family', 'AccuLynx', '$490/mo, no add-ons',
       'Send feedback form. Schedule follow-up in person.',
       'Met 11/10. 60% insurance / 40% retail. GAF HDZ. Liked: rep app, Today screen, scope import and supplements, homeowner view. Biggest AccuLynx complaint: how material orders work. Builds orders from templates. Uses QuickBooks and EagleView, won''t switch without both. Said $299 for up to 5 users would still be worth it.',
       jsonb_build_array(jsonb_build_object('t', '2026-11-10', 'text', 'First meeting and demo'))),
      ('Ben Ross Roofing', '', 'Rock Hill, SC', 'To call', 'Cold call', '', '', 'Call (803) 327-7677', '', '[]'),
      ('Rodríguez Roofing', '', '', 'To call', 'Cold call', '', '', 'Find the owner and call', '', '[]'),
      ('Innovation Restoration', '', '', 'To call', 'Cold call', '', '', 'Find the owner and call', '', '[]');
  end if;
  if not exists (select 1 from hq_tasks) then
    insert into hq_tasks(title, area, sort, note) values
      ('Apply for the QuickBooks Online app (Intuit developer)', 'Partners', 1, 'Gavin won''t switch without it.'),
      ('Apply for EagleView ordering access', 'Partners', 2, 'Gavin won''t switch without it.'),
      ('Apply to Hover and GAF QuickMeasure partner programs', 'Partners', 3, ''),
      ('Supplier ordering: ABC Supply, SRS, Beacon', 'Partners', 4, ''),
      ('Lawyer review: terms, privacy, customer agreement', 'Legal', 10, ''),
      ('Form RUVA Inc. or LLC and get an EIN', 'Legal', 11, ''),
      ('Register for SC sales tax on software (SaaS is taxable in SC)', 'Legal', 12, ''),
      ('Turn on live Stripe billing at the RUVA price', 'Money', 20, 'App still shows the old Solo/Team prices.'),
      ('Email sending service for vendor orders and job emails', 'Product', 30, 'About $20/mo.'),
      ('Saved material order templates', 'Product', 31, 'Promised to Gavin.'),
      ('Switch the office to the new dashboard', 'Product', 32, 'After Gavin tests dashboard-new.'),
      ('Get useruva.com categorized by web filters', 'Product', 33, 'Blocked on the Nutramax network as a new domain.'),
      ('Demo login for showing RUVA', 'Sales', 40, ''),
      ('Line up 2–3 more small roofers to pitch', 'Sales', 41, '');
  end if;
end $$;

-- RUVA beta: "Report a problem" from the app and dashboard, read in RUVA HQ.
-- Safe to run more than once.

create table if not exists public.beta_reports (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  user_id uuid,
  email text not null default '',
  workspace text not null default '',
  kind text not null default 'Bug',
  body text not null,
  where_at text not null default '',
  device text not null default '',
  status text not null default 'New',
  note text not null default ''
);
alter table public.beta_reports enable row level security;
revoke all on public.beta_reports from anon, authenticated;

-- Anyone signed in can send a report. They can't read anyone else's.
create or replace function public.report_problem(p_kind text, p_body text, p_where text, p_device text, p_ws uuid default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_email text; v_ws text;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if coalesce(trim(p_body), '') = '' then raise exception 'Tell us what happened'; end if;
  select email into v_email from auth.users where id = auth.uid();
  select name into v_ws from workspaces where id = p_ws and exists (select 1 from members m where m.workspace_id = p_ws and m.user_id = auth.uid());
  insert into beta_reports(user_id, email, workspace, kind, body, where_at, device)
  values (auth.uid(), coalesce(v_email, ''), coalesce(v_ws, ''), left(coalesce(nullif(p_kind, ''), 'Bug'), 20), left(p_body, 4000), left(coalesce(p_where, ''), 300), left(coalesce(p_device, ''), 300))
  returning id into v_id;
  return v_id;
end $$;
grant execute on function public.report_problem(text, text, text, text, uuid) to authenticated;

create or replace function public._beta_notify() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public._push(array(select id from auth.users where lower(email) in ('thaddeusjreugene@icloud.com', 'thadjacobsjr@icloud.com', 'thadjacobs@useruva.com')), 'beta',
    'Beta ' || lower(new.kind) || coalesce(' from ' || nullif(new.workspace, ''), ''), left(new.body, 140), 'https://useruva.com/admin/#beta', 'beta');
  return new;
exception when others then return new;
end $$;
drop trigger if exists beta_notify on public.beta_reports;
create trigger beta_notify after insert on public.beta_reports for each row execute function public._beta_notify();

-- RUVA HQ
create or replace function public.hq_beta() returns setof public.beta_reports
language plpgsql stable security definer set search_path = public as $$
begin perform _hq_guard(); return query select * from beta_reports order by (status = 'Fixed'), created_at desc limit 500; end $$;

create or replace function public.hq_beta_save(p_id bigint, p_status text, p_note text) returns void
language plpgsql security definer set search_path = public as $$
begin perform _hq_guard(); update beta_reports set status = coalesce(nullif(p_status, ''), status), note = coalesce(p_note, note) where id = p_id; end $$;

grant execute on function public.hq_beta() to authenticated;
grant execute on function public.hq_beta_save(bigint, text, text) to authenticated;

-- 7. Homeowner link: a private page per job. No login. View progress, pick Good/Better/Best, review and sign.

-- One private link per job. Turning it off kills the link.
create table if not exists public.ho_links (
  token        text primary key check (length(token) >= 24),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  lead_id      text not null unique,
  created_by   uuid not null default auth.uid(),
  created_at   timestamptz not null default now(),
  revoked_at   timestamptz
);
alter table public.ho_links enable row level security;
drop policy if exists ho_links_rw on public.ho_links;
create policy ho_links_rw on public.ho_links for select to authenticated
  using (public.is_member(workspace_id) and public.can_see_lead(lead_id));
revoke all on public.ho_links from anon;

-- Rep or office: make (or reuse) the job's link, and save the three options the homeowner will see.
-- p_offer = {sq, tiers:[{n, name, per, inc}]} built by the app from the job's own prices.
create or replace function public.ho_link(p_lead text, p_offer jsonb default null) returns text
language plpgsql security definer set search_path = public as $$
declare l leads; t text;
begin
  select * into l from leads where id = p_lead;
  if l.id is null or not public.is_member(l.workspace_id) or not public.can_see_lead(p_lead) then raise exception 'not allowed'; end if;
  select token into t from ho_links where lead_id = p_lead and revoked_at is null;
  if t is null then
    t := replace(gen_random_uuid()::text, '-', '');
    insert into ho_links(token, workspace_id, lead_id) values (t, l.workspace_id, p_lead)
      on conflict (lead_id) do update set token = excluded.token, revoked_at = null, created_at = now(), created_by = auth.uid();
  end if;
  if p_offer is not null and jsonb_typeof(p_offer->'tiers') = 'array' then
    update leads set data = jsonb_set(data, '{ho}', coalesce(data->'ho','{}'::jsonb) || jsonb_build_object('offer', p_offer, 'offerAt', (extract(epoch from now())*1000)::bigint)) where id = p_lead;
  end if;
  return t;
end $$;

create or replace function public.ho_unlink(p_lead text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from leads where id = p_lead and public.is_member(workspace_id) and public.can_see_lead(p_lead)) then raise exception 'not allowed'; end if;
  update ho_links set revoked_at = now() where lead_id = p_lead;
end $$;

-- What the homeowner sees. Only these fields leave the database: never costs, crew pay, commission, notes or other jobs.
create or replace function public.ho_view(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare k ho_links; l leads; w workspaces; e jsonb; tot numeric := 0; rep text;
begin
  select * into k from ho_links where token = p_token and length(p_token) >= 24 and revoked_at is null;
  if k.token is null then return null; end if;
  select * into l from leads where id = k.lead_id;
  if l.id is null then return null; end if;
  select * into w from workspaces where id = l.workspace_id;
  e := coalesce(l.data->'est', '{}'::jsonb);
  select coalesce(sum(coalesce(nullif(regexp_replace(x->>'q','[^0-9.]','','g'),'')::numeric,0) * coalesce(nullif(regexp_replace(x->>'p','[^0-9.-]','','g'),'')::numeric,0)),0)
    into tot from jsonb_array_elements(coalesce(e->'lines','[]'::jsonb)) x;
  rep := case when l.owner_id is not null then split_part(public._push_name(l.workspace_id, l.owner_id), ' ', 1) end;
  return jsonb_build_object(
    'company', jsonb_build_object('name', w.name, 'phone', w.settings->'profile'->>'phone', 'logo', w.settings->'profile'->>'logo', 'license', w.settings->'profile'->>'license'),
    'rep', rep,
    'name', l.name, 'address', trim(concat_ws(' ', l.num, l.street)), 'city', l.city,
    'type', coalesce(l.data->'sale'->>'type', 'Insurance'),
    'status', l.status, 'stage', l.data->'sale'->>'stage',
    'install', l.data->'sale'->'install'->>'at',
    'offer', l.data->'ho'->'offer',
    'pick', e->'pick',
    'contract', case when coalesce(l.data->'sale'->'er'->>'st','') = 'ready' and tot > 0 then jsonb_build_object(
        'total', round(tot, 2),
        'lines', (select jsonb_agg(x->>'d') from jsonb_array_elements(coalesce(e->'lines','[]'::jsonb)) x where coalesce(x->>'d','') <> ''),
        'terms', w.settings->>'terms') end,
    'signed', case when coalesce(e->>'sigAt','') <> '' then jsonb_build_object('name', e->>'sigName', 'at', e->>'sigAt') end
  );
end $$;

-- Homeowner picks an option. Fills the contract's main line, logs it, and tells the rep and office.
create or replace function public.ho_pick(p_token text, p_i int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k ho_links; l leads; t jsonb; sq numeric; ln jsonb; who uuid[];
begin
  select * into k from ho_links where token = p_token and revoked_at is null;
  if k.token is null then raise exception 'link not found'; end if;
  select * into l from leads where id = k.lead_id for update;
  if coalesce(l.data->'est'->>'sigAt','') <> '' then raise exception 'already signed'; end if;
  t := l.data->'ho'->'offer'->'tiers'->p_i;
  if t is null then raise exception 'no such option'; end if;
  sq := coalesce(nullif(l.data->'ho'->'offer'->>'sq','')::numeric, 0);
  ln := jsonb_build_object('d', 'Tear off and replace · ' || coalesce(t->>'name','') || ' (' || (t->>'n') || ')', 'q', sq::text, 'u', 'SQ', 'p', t->>'per', 'tier', 1);
  update leads set data = jsonb_set(jsonb_set(jsonb_set(data,
      '{est,lines}', jsonb_build_array(ln) || coalesce((select jsonb_agg(x) from jsonb_array_elements(coalesce(data->'est'->'lines','[]'::jsonb)) x where coalesce((x->>'tier')::int,0) <> 1), '[]'::jsonb)),
      '{est,pick}', to_jsonb(p_i)),
      '{log}', coalesce(data->'log','[]'::jsonb) || jsonb_build_array(jsonb_build_object('t', (extract(epoch from now())*1000)::bigint, 'text', 'Homeowner picked ' || (t->>'n') || ' from their link · $' || to_char(sq * (t->>'per')::numeric, 'FM999,999,990'))))
    where id = l.id;
  who := array(select user_id from members where workspace_id = l.workspace_id and active and not support and (role in ('owner','manager','office') or user_id = l.owner_id));
  perform public._push(who, 'jobs', 'Homeowner picked ' || (t->>'n'), public._push_addr(l) || ' · $' || to_char(sq * (t->>'per')::numeric, 'FM999,999,990'), './?lead=' || l.id || '#leads', 'ho:' || l.id);
  return public.ho_view(p_token);
end $$;

-- Homeowner signs. Only when the office has sent the contract. Stores the drawn signature; the existing
-- "Contract signed" alert fires on its own.
create or replace function public.ho_sign(p_token text, p_name text, p_img text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k ho_links; l leads; now_ms bigint := (extract(epoch from now())*1000)::bigint;
begin
  select * into k from ho_links where token = p_token and revoked_at is null;
  if k.token is null then raise exception 'link not found'; end if;
  select * into l from leads where id = k.lead_id for update;
  if coalesce(l.data->'sale'->'er'->>'st','') <> 'ready' then raise exception 'contract not ready'; end if;
  if coalesce(l.data->'est'->>'sigAt','') <> '' then raise exception 'already signed'; end if;
  if length(trim(coalesce(p_name,''))) < 2 then raise exception 'name required'; end if;
  if p_img is null or p_img not like 'data:image/png;base64,%' or length(p_img) > 300000 then raise exception 'bad signature'; end if;
  update leads set data = jsonb_set(jsonb_set(jsonb_set(jsonb_set(data,
      '{est,hoSig}', jsonb_build_object('img', p_img, 'name', trim(p_name), 'at', now_ms)),
      '{est,sigName}', to_jsonb(trim(p_name))),
      '{est,sigAt}', to_jsonb(to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))),
      '{log}', coalesce(data->'log','[]'::jsonb) || jsonb_build_array(jsonb_build_object('t', now_ms, 'text', 'Homeowner signed the contract from their link')))
    where id = l.id;
  return public.ho_view(p_token);
end $$;

revoke execute on function public.ho_link(text, jsonb), public.ho_unlink(text) from public, anon;
grant execute on function public.ho_link(text, jsonb), public.ho_unlink(text) to authenticated;
revoke execute on function public.ho_view(text), public.ho_pick(text, int), public.ho_sign(text, text, text) from public;
grant execute on function public.ho_view(text), public.ho_pick(text, int), public.ho_sign(text, text, text) to anon, authenticated;
-- 8. Homeowner page: name the roof they're getting, and keep showing the contract after it's signed.
create or replace function public.ho_view(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare k ho_links; l leads; w workspaces; e jsonb; tot numeric := 0; rep text; pid text; roof text;
begin
  select * into k from ho_links where token = p_token and length(p_token) >= 24 and revoked_at is null;
  if k.token is null then return null; end if;
  select * into l from leads where id = k.lead_id;
  if l.id is null then return null; end if;
  select * into w from workspaces where id = l.workspace_id;
  e := coalesce(l.data->'est', '{}'::jsonb);
  select coalesce(sum(coalesce(nullif(regexp_replace(x->>'q','[^0-9.]','','g'),'')::numeric,0) * coalesce(nullif(regexp_replace(x->>'p','[^0-9.-]','','g'),'')::numeric,0)),0)
    into tot from jsonb_array_elements(coalesce(e->'lines','[]'::jsonb)) x;
  rep := case when l.owner_id is not null then split_part(public._push_name(l.workspace_id, l.owner_id), ' ', 1) end;
  -- The roof system on the contract: product name from the company's catalog (Atlas built-ins as a fallback) plus the color.
  pid := e->'sys'->>'pid';
  if pid is not null then
    select trim(concat_ws(' ', nullif(nullif(c->>'brand',''),'Any'), c->>'name')) into roof from jsonb_array_elements(coalesce(w.settings->'catalog','[]'::jsonb)) c where c->>'id' = pid limit 1;
    if roof is null then roof := case pid when 'a1' then 'Atlas Pinnacle Pristine' end; end if;
  end if;
  if roof is not null and coalesce(e->'sys'->>'color', e->>'color', '') <> '' then roof := roof || ' · ' || coalesce(nullif(e->'sys'->>'color',''), e->>'color'); end if;
  return jsonb_build_object(
    'company', jsonb_build_object('name', w.name, 'phone', w.settings->'profile'->>'phone', 'logo', w.settings->'profile'->>'logo', 'license', w.settings->'profile'->>'license'),
    'rep', rep,
    'name', l.name, 'address', trim(concat_ws(' ', l.num, l.street)), 'city', l.city,
    'type', coalesce(l.data->'sale'->>'type', 'Insurance'),
    'status', l.status, 'stage', l.data->'sale'->>'stage',
    'install', l.data->'sale'->'install'->>'at',
    'offer', l.data->'ho'->'offer',
    'pick', e->'pick',
    'roof', roof,
    'contract', case when (coalesce(l.data->'sale'->'er'->>'st','') = 'ready' or coalesce(e->>'sigAt','') <> '') and tot > 0 then jsonb_build_object(
        'total', round(tot, 2),
        'lines', (select jsonb_agg(x->>'d') from jsonb_array_elements(coalesce(e->'lines','[]'::jsonb)) x where coalesce(x->>'d','') <> ''),
        'terms', w.settings->>'terms') end,
    'signed', case when coalesce(e->>'sigAt','') <> '' then jsonb_build_object('name', e->>'sigName', 'at', e->>'sigAt') end
  );
end $$;


-- 9. QuickBooks Online connection.
-- Tokens are encrypted by the "qbo" Edge Function before they get here (AES-GCM; the key lives in the
-- function's secrets, never in the database). Nobody signed in to RUVA can read these tables directly:
-- only the Edge Function (service role) can. The dashboard reads a safe summary through qbo_status().

create table if not exists public.qbo_conn (
  workspace_id  uuid primary key references public.workspaces(id) on delete cascade,
  env           text not null default 'sandbox' check (env in ('sandbox','production')),
  realm_hash    text not null,                 -- sha-256 of the QuickBooks company id (to match without decrypting)
  realm_enc     text not null,                 -- QuickBooks company id, encrypted
  access_enc    text not null,                 -- access token, encrypted (lasts 1 hour)
  refresh_enc   text not null,                 -- refresh token, encrypted
  access_exp    timestamptz not null,
  refresh_exp   timestamptz,
  company       text not null default '',      -- QuickBooks company name, shown in Settings
  connected_by  uuid,
  connected_at  timestamptz not null default now(),
  status        text not null default 'connected' check (status in ('connected','reconnect')),
  last_error    text not null default '',
  last_sync_at  timestamptz,
  pull_cursor   timestamptz,                   -- payments and expenses changed in QuickBooks after this come back
  sync_lock     timestamptz                    -- one sync at a time per company
);

-- Sign-in handshakes. Each one is single-use and good for 10 minutes (stops forged callbacks).
create table if not exists public.qbo_state (
  state        text primary key check (length(state) >= 32),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id      uuid not null,
  return_url   text not null default '',
  created_at   timestamptz not null default now()
);

-- Which QuickBooks record each RUVA thing became, so nothing is sent twice.
-- kind: cust, job, inv, pay, bill, vend, item, acct
create table if not exists public.qbo_map (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  realm_hash   text not null,
  kind         text not null,
  ruva_key     text not null,
  qbo_id       text not null,
  sync_token   text not null default '',
  hash         text not null default '',
  synced_at    timestamptz not null default now(),
  gone_at      timestamptz,                    -- set on disconnect; erased 30 days later (Intuit rule)
  primary key (workspace_id, realm_hash, kind, ruva_key)
);
create index if not exists qbo_map_qid on public.qbo_map(workspace_id, realm_hash, kind, qbo_id);

-- Short activity list for Settings → Integrations.
create table if not exists public.qbo_log (
  id           bigserial primary key,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  at           timestamptz not null default now(),
  ok           boolean not null default true,
  msg          text not null,
  lead_id      text
);
create index if not exists qbo_log_ws on public.qbo_log(workspace_id, at desc);

alter table public.qbo_conn  enable row level security;
alter table public.qbo_state enable row level security;
alter table public.qbo_map   enable row level security;
alter table public.qbo_log   enable row level security;
revoke all on public.qbo_conn, public.qbo_state, public.qbo_map, public.qbo_log from anon, authenticated;
do $$ begin
  execute 'grant all on public.qbo_conn, public.qbo_state, public.qbo_map, public.qbo_log to service_role';
  execute 'grant usage, select on sequence public.qbo_log_id_seq to service_role';
exception when others then null; end $$;

-- One secret the daily check sends, so nobody else can trigger it.
create table if not exists public.qbo_cfg (id int primary key default 1 check (id = 1), cron_token text not null);
alter table public.qbo_cfg enable row level security;
revoke all on public.qbo_cfg from anon, authenticated;
do $$ begin execute 'grant all on public.qbo_cfg to service_role'; exception when others then null; end $$;
insert into public.qbo_cfg(id, cron_token) values (1, encode(gen_random_bytes(32), 'hex')) on conflict (id) do nothing;

-- What the office sees. Never tokens or the company id.
create or replace function public.qbo_status(ws uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c qbo_conn;
begin
  if not public.can_view_all(ws) then raise exception 'not allowed'; end if;
  select * into c from qbo_conn where workspace_id = ws;
  return jsonb_build_object(
    'connected', c.workspace_id is not null,
    'can_connect', public.is_manager(ws),
    'status', c.status, 'env', c.env, 'company', c.company,
    'connected_at', c.connected_at, 'connected_by', c.connected_by,
    'last_sync_at', c.last_sync_at, 'refresh_exp', c.refresh_exp, 'last_error', c.last_error,
    'jobs', (select count(*) from qbo_map m where m.workspace_id = ws and m.kind = 'job' and m.gone_at is null),
    'log', coalesce((select jsonb_agg(jsonb_build_object('at', l.at, 'ok', l.ok, 'msg', l.msg, 'lead', l.lead_id) order by l.at desc)
                     from (select * from qbo_log where workspace_id = ws order by at desc limit 12) l), '[]'::jsonb),
    'synced', coalesce((select jsonb_object_agg(m.ruva_key, m.qbo_id) from qbo_map m
                        where m.workspace_id = ws and m.kind = 'inv' and m.gone_at is null), '{}'::jsonb));
end $$;
revoke execute on function public.qbo_status(uuid) from public, anon;
grant execute on function public.qbo_status(uuid) to authenticated;

-- Daily clean-up: QuickBooks ids from a disconnected company are erased after 30 days,
-- expired handshakes after a day, activity older than 90 days.
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('ruva-qbo-purge', '45 7 * * *', $c$
      delete from public.qbo_map   where gone_at < now() - interval '30 days';
      delete from public.qbo_state where created_at < now() - interval '1 day';
      delete from public.qbo_log   where at < now() - interval '90 days';$c$);
  end if;
exception when others then null; end $$;

-- Daily check of every connection (keeps sign-ins from expiring; catches a disconnect made inside QuickBooks).
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') and exists (select 1 from pg_extension where extname = 'pg_net') then
    perform cron.schedule('ruva-qbo-check', '20 8 * * *', $c$
      select net.http_post(
        url := 'https://fixqhaewtyddieoimmrv.supabase.co/functions/v1/qbo',
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body := jsonb_build_object('action', 'cron', 'token', (select cron_token from public.qbo_cfg where id = 1)));$c$);
  end if;
exception when others then null; end $$;


-- 11. AccuLynx connection: leads set in RUVA show up in the company's AccuLynx as a contact + job,
-- with the rep as sales owner, notes as job messages, and photos in the job's Photos folder.
-- The API key is encrypted by the "acculynx" Edge Function before it gets here. Nobody signed in to RUVA
-- can read these tables; the dashboard and app read safe summaries through acx_status() and acx_lead().

create table if not exists public.acx_conn (
  workspace_id uuid primary key references public.workspaces(id) on delete cascade,
  key_enc      text not null,                 -- AccuLynx API key, encrypted
  company      text not null default '',      -- AccuLynx company/location name
  connected_by uuid,
  connected_at timestamptz not null default now(),
  status       text not null default 'connected' check (status in ('connected','reconnect')),
  last_error   text not null default '',
  last_sync_at timestamptz,
  settings     jsonb not null default '{}'::jsonb,   -- leadSourceId, statuses[], contactTypeId
  lists        jsonb not null default '{}'::jsonb    -- lead sources and users from AccuLynx, for the settings screen
);

-- Which AccuLynx contact and job each RUVA lead became, and what has been sent since.
create table if not exists public.acx_map (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  lead_id      text not null,
  contact_id   text,
  job_id       text,
  job_number   text not null default '',
  sent         jsonb not null default '{}'::jsonb,   -- {status, logT, photos:[ids]}
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (workspace_id, lead_id)
);

-- Leads waiting to go over. A change to a lead lands here; a job every minute sends them.
create table if not exists public.acx_queue (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  lead_id      text not null,
  queued_at    timestamptz not null default now(),
  next_at      timestamptz not null default now(),
  tries        int not null default 0,
  primary key (workspace_id, lead_id)
);
create index if not exists acx_queue_due on public.acx_queue(next_at);

create table if not exists public.acx_log (
  id           bigserial primary key,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  at           timestamptz not null default now(),
  ok           boolean not null default true,
  msg          text not null,
  lead_id      text
);
create index if not exists acx_log_ws on public.acx_log(workspace_id, at desc);

create table if not exists public.acx_cfg (id int primary key default 1 check (id = 1), cron_token text not null);
insert into public.acx_cfg(id, cron_token) values (1, encode(gen_random_bytes(32), 'hex')) on conflict (id) do nothing;

alter table public.acx_conn  enable row level security;
alter table public.acx_map   enable row level security;
alter table public.acx_queue enable row level security;
alter table public.acx_log   enable row level security;
alter table public.acx_cfg   enable row level security;
revoke all on public.acx_conn, public.acx_map, public.acx_queue, public.acx_log, public.acx_cfg from anon, authenticated;
do $$ begin
  execute 'grant all on public.acx_conn, public.acx_map, public.acx_queue, public.acx_log, public.acx_cfg to service_role';
  execute 'grant usage, select on sequence public.acx_log_id_seq to service_role';
exception when others then null; end $$;

-- A lead changed: if the company is connected and the lead is at a status that goes to AccuLynx
-- (or already went), put it in line. Waits 30 seconds so a rep's burst of edits goes as one send.
create or replace function public._acx_on_lead() returns trigger
language plpgsql security definer set search_path = public as $$
declare st jsonb;
begin
  select settings->'statuses' into st from acx_conn where workspace_id = new.workspace_id and status = 'connected';
  if not found then return new; end if;
  if tg_op = 'UPDATE' and new.status is not distinct from old.status and new.data is not distinct from old.data
     and new.name is not distinct from old.name and new.phone is not distinct from old.phone then return new; end if;
  if coalesce(st, '["Inspection Scheduled","Inspected","Claim Pending","Sold"]'::jsonb) ? new.status
     or exists (select 1 from acx_map where workspace_id = new.workspace_id and lead_id = new.id and job_id is not null) then
    insert into acx_queue(workspace_id, lead_id, next_at) values (new.workspace_id, new.id, now() + interval '30 seconds')
      on conflict (workspace_id, lead_id) do update set next_at = greatest(acx_queue.next_at, now() + interval '30 seconds'), tries = 0;
  end if;
  return new;
end $$;
drop trigger if exists acx_on_lead on public.leads;
create trigger acx_on_lead after insert or update on public.leads for each row execute function public._acx_on_lead();

-- Office: connection status, settings and recent activity. Never the key.
create or replace function public.acx_status(ws uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c acx_conn;
begin
  if not public.can_view_all(ws) then raise exception 'not allowed'; end if;
  select * into c from acx_conn where workspace_id = ws;
  return jsonb_build_object(
    'connected', c.workspace_id is not null, 'can_connect', public.is_manager(ws),
    'status', c.status, 'company', c.company, 'connected_at', c.connected_at, 'connected_by', c.connected_by,
    'last_sync_at', c.last_sync_at, 'last_error', c.last_error, 'settings', c.settings,
    'sources', coalesce(c.lists->'sources', '[]'::jsonb),
    'reps', coalesce((select jsonb_agg(jsonb_build_object('id', m.user_id, 'name', m.display_name,
        'matched', exists (select 1 from jsonb_array_elements(coalesce(c.lists->'users','[]'::jsonb)) u where lower(u->>'email') = lower(au.email))))
      from members m join auth.users au on au.id = m.user_id where m.workspace_id = ws and m.active and not m.support), '[]'::jsonb),
    'sent', (select count(*) from acx_map x where x.workspace_id = ws and x.job_id is not null),
    'waiting', (select count(*) from acx_queue q where q.workspace_id = ws),
    'log', coalesce((select jsonb_agg(jsonb_build_object('at', l.at, 'ok', l.ok, 'msg', l.msg, 'lead', l.lead_id) order by l.at desc)
                     from (select * from acx_log where workspace_id = ws order by at desc limit 15) l), '[]'::jsonb));
end $$;

-- Rep or office: is this lead in AccuLynx yet?
create or replace function public.acx_lead(p_lead text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l leads; x acx_map;
begin
  select * into l from leads where id = p_lead;
  if l.id is null or not public.is_member(l.workspace_id) or not public.can_see_lead(p_lead) then return null; end if;
  if not exists (select 1 from acx_conn where workspace_id = l.workspace_id) then return null; end if;
  select * into x from acx_map where workspace_id = l.workspace_id and lead_id = p_lead;
  return jsonb_build_object('job', x.job_id is not null, 'number', x.job_number, 'at', x.created_at,
    'waiting', exists (select 1 from acx_queue q where q.workspace_id = l.workspace_id and q.lead_id = p_lead));
end $$;

revoke execute on function public.acx_status(uuid), public.acx_lead(text) from public, anon;
grant execute on function public.acx_status(uuid), public.acx_lead(text) to authenticated;
revoke execute on function public._acx_on_lead() from public, anon, authenticated;

-- Every minute: send waiting leads (only calls the function when something is due).
-- Daily: drop activity older than 90 days.
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') and exists (select 1 from pg_extension where extname = 'pg_net') then
    perform cron.schedule('ruva-acx-send', '* * * * *', $c$
      select net.http_post(
        url := 'https://fixqhaewtyddieoimmrv.supabase.co/functions/v1/acculynx',
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body := jsonb_build_object('action', 'drain', 'token', (select cron_token from public.acx_cfg where id = 1)))
      where exists (select 1 from public.acx_queue where next_at <= now());$c$);
    perform cron.schedule('ruva-acx-purge', '50 7 * * *', $c$ delete from public.acx_log where at < now() - interval '90 days';$c$);
  end if;
exception when others then null; end $$;
-- 12. Plans: "full" (everything) or "field" (rep app + manager screens; office tools locked).
-- Only RUVA sets the plan, from RUVA HQ. A company owner can't change it, even by editing the database directly.

alter table public.workspaces add column if not exists plan text not null default 'full';
do $$ begin
  alter table public.workspaces add constraint workspaces_plan_ck check (plan in ('full','field'));
exception when duplicate_object then null; end $$;

create or replace function public._plan_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  -- runs as the caller: a signed-in user (authenticated) can never change it; RUVA's HQ function runs as the owner role and can
  if new.plan is distinct from old.plan and current_user in ('authenticated', 'anon') then
    raise exception 'Only RUVA can change the plan';
  end if;
  return new;
end $$;
drop trigger if exists plan_guard on public.workspaces;
create trigger plan_guard before update of plan on public.workspaces for each row execute function public._plan_guard();

-- RUVA HQ: set a company's plan.
create or replace function public.admin_set_plan(ws uuid, p_plan text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public._need_admin();
  if p_plan not in ('full','field') then raise exception 'Pick Full or Field'; end if;
  update workspaces set plan = p_plan where id = ws;
  perform public._alog(ws, 'Plan set to ' || case when p_plan = 'field' then 'Field app' else 'Full RUVA' end);
end $$;
revoke execute on function public.admin_set_plan(uuid, text) from public, anon;
grant execute on function public.admin_set_plan(uuid, text) to authenticated;

-- HQ account card now shows the plan.
create or replace function public.admin_account(ws uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare w workspaces; r jsonb;
begin
  perform public._need_admin();
  select * into w from workspaces where id = ws;
  if w.id is null then raise exception 'Account not found'; end if;
  r := jsonb_build_object(
    'id', w.id, 'name', w.name, 'kind', w.kind, 'plan', w.plan, 'created_at', w.created_at, 'owner_id', w.owner_id, 'owner_email', public._email_of(w.owner_id),
    'active', public.ws_active(ws), 'exempt', w.billing_exempt, 'comp_until', w.comp_until, 'comp_code', w.comp_code,
    'status', w.sub_status, 'trial_ends_at', w.trial_ends_at, 'period_end', w.period_end, 'cancel_at_period_end', w.cancel_at_period_end,
    'seats', w.seats, 'stripe_customer', w.stripe_customer, 'stripe_mode', w.stripe_mode,
    'grant_until', (select expires_at from support_grants where workspace_id = ws and expires_at > now()),
    'members', coalesce((select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'name', m.display_name, 'role', m.role, 'active', m.active,
                  'email', public._email_of(m.user_id), 'joined_at', m.joined_at, 'support', m.support,
                  'leads', (select count(*) from leads l where l.workspace_id = ws and l.owner_id = m.user_id)) order by m.support, m.joined_at)
                from members m where m.workspace_id = ws), '[]'::jsonb),
    'counts', jsonb_build_object(
      'leads', (select count(*) from leads where workspace_id = ws),
      'board', (select count(*) from leads where workspace_id = ws and pool),
      'sold', (select count(*) from leads where workspace_id = ws and status = 'Sold'),
      'photos', (select coalesce(sum(case when jsonb_typeof(data->'photos') = 'array' then jsonb_array_length(data->'photos') else 0 end),0) from leads where workspace_id = ws),
      'messages', (select count(*) from messages where workspace_id = ws),
      'trash', (select count(*) from leads_trash where workspace_id = ws and deleted_at > now() - interval '30 days')),
    'log', coalesce((select jsonb_agg(jsonb_build_object('at', a.created_at, 'action', a.action, 'support', a.by_support,
              'by', case when a.by_support then coalesce(public._email_of(a.actor), 'Support') else 'Owner' end) order by a.created_at desc)
            from (select * from admin_log where workspace_id = ws order by created_at desc limit 60) a), '[]'::jsonb));
  return r;
end $$;

-- Field plan: no homeowner pick-and-sign page.
create or replace function public.ho_link(p_lead text, p_offer jsonb default null) returns text
language plpgsql security definer set search_path = public as $$
declare l leads; t text;
begin
  select * into l from leads where id = p_lead;
  if l.id is null or not public.is_member(l.workspace_id) or not public.can_see_lead(p_lead) then raise exception 'not allowed'; end if;
  if (select plan from workspaces where id = l.workspace_id) = 'field' then raise exception 'The homeowner page comes with the full RUVA plan'; end if;
  select token into t from ho_links where lead_id = p_lead and revoked_at is null;
  if t is null then
    t := replace(gen_random_uuid()::text, '-', '');
    insert into ho_links(token, workspace_id, lead_id) values (t, l.workspace_id, p_lead)
      on conflict (lead_id) do update set token = excluded.token, revoked_at = null, created_at = now(), created_by = auth.uid();
  end if;
  if p_offer is not null and jsonb_typeof(p_offer->'tiers') = 'array' then
    update leads set data = jsonb_set(data, '{ho}', coalesce(data->'ho','{}'::jsonb) || jsonb_build_object('offer', p_offer, 'offerAt', (extract(epoch from now())*1000)::bigint)) where id = p_lead;
  end if;
  return t;
end $$;

-- Field plan: QuickBooks can't be connected.
create or replace function public._qbo_plan_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select plan from workspaces where id = new.workspace_id) = 'field' then
    raise exception 'QuickBooks comes with the full RUVA plan';
  end if;
  return new;
end $$;
drop trigger if exists qbo_state_plan on public.qbo_state;
create trigger qbo_state_plan before insert on public.qbo_state for each row execute function public._qbo_plan_guard();
drop trigger if exists qbo_conn_plan on public.qbo_conn;
create trigger qbo_conn_plan before insert on public.qbo_conn for each row execute function public._qbo_plan_guard();

-- 13. Security fixes from the November 18 code review.
--  a. A company can switch to a one-person account (cheaper plan) only once the owner is the only member left,
--     and nobody can join a one-person account with an invite code.
--  b. Support staff can't remove their own "support" flag (so the owner's "turn off support access" always works).
--  c. Only managers change a member's commission override (members.prefs); reps can't set their own.
--  d. Chat photos can only be opened by people who can read the message they were sent in (so DM photos stay private).
--  e. When the trial is over and nobody has paid, claiming, assigning, releasing and taking over leads and
--     sending a homeowner link are blocked too (they skipped the read-only check before).
--  f. The old feedback-viewer key was in this repo, so it is replaced with a random one nobody has.
--     RUVA HQ shows feedback through the admin sign-in and doesn't use this key.
-- Nothing here changes or deletes customer data.

create or replace function public._need_active(ws uuid) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.ws_active(ws) then
    raise exception 'RIDGEMATE_INACTIVE: This RUVA account needs a plan. The owner can choose one in Settings → Plan & billing.';
  end if;
end $$;
revoke all on function public._need_active(uuid) from public;

create or replace function public.workspaces_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user not in ('authenticated','anon') then return new; end if;
  if new.owner_id is distinct from old.owner_id or new.id is distinct from old.id then
    raise exception 'The account owner cannot be changed here';
  end if;
  new.trial_ends_at := old.trial_ends_at; new.sub_status := old.sub_status; new.billing_exempt := old.billing_exempt;
  new.stripe_customer := old.stripe_customer; new.stripe_sub := old.stripe_sub; new.stripe_mode := old.stripe_mode;
  new.seats := old.seats; new.period_end := old.period_end; new.cancel_at_period_end := old.cancel_at_period_end;
  new.comp_until := old.comp_until; new.comp_code := old.comp_code;
  -- A company can become a one-person account only once the owner is the only one left on it.
  if new.kind is distinct from old.kind and new.kind = 'individual' and exists(
       select 1 from members m where m.workspace_id = old.id and m.active and not m.support and m.user_id <> old.owner_id) then
    raise exception 'Remove everyone else from the team first, then switch to a one-person account.';
  end if;
  return new;
end $$;

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
  if new.support is distinct from old.support then raise exception 'Support access is changed by the account owner'; end if;
  if new.prefs is distinct from old.prefs and not public.is_manager(old.workspace_id) then
    raise exception 'Only managers can change commission overrides';
  end if;
  return new;
end $$;

create or replace function public.join_workspace(p_code text, p_display_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare inv invites;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  select * into inv from invites where code = upper(trim(p_code)) for update;
  if not found or inv.expires_at < now() or inv.uses >= inv.max_uses then raise exception 'That invite code is not valid'; end if;
  if (select kind from workspaces where id = inv.workspace_id) <> 'company' then
    raise exception 'This is a one-person account. The owner can switch it to a company account first.';
  end if;
  insert into members(workspace_id, user_id, role, display_name, phone)
  values (inv.workspace_id, auth.uid(), inv.role, coalesce(nullif(trim(p_display_name),''), inv.name, ''), coalesce(inv.phone,''))
  on conflict (workspace_id, user_id) do update
    set role = case when members.active or members.role = 'owner' then members.role else excluded.role end,
        active = true;
  update invites set uses = uses + 1 where code = inv.code;
  return inv.workspace_id;
end $$;

create or replace function public.claim_lead(lid text)
returns text language plpgsql security definer set search_path = public as $$
declare l leads; cap int; held int; hrs numeric;
begin
  select * into l from leads where id = lid for update;
  if not found or not public.is_member(l.workspace_id) then raise exception 'Lead not found'; end if;
  perform public._need_active(l.workspace_id);
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

create or replace function public.assign_lead(lid text, p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
declare l leads;
begin
  select * into l from leads where id = lid for update;
  if not found or not public.is_manager(l.workspace_id) then raise exception 'Not allowed'; end if;
  perform public._need_active(l.workspace_id);
  update leads set owner_id = p_user, pool = (p_user is null), claimed_at = case when p_user is null then null else now() end,
         contacted_at = null, updated_at = now(),
         data = jsonb_set(data, '{knocks}', coalesce(data->'knocks','[]'::jsonb) ||
                jsonb_build_array(jsonb_build_object('t', (extract(epoch from now())*1000)::bigint,
                  'r', case when p_user is null then 'Returned to board' else 'Assigned' end, 'by', auth.uid(), 'to', p_user)))
   where id = lid;
end $$;

create or replace function public.release_lead(lid text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare l leads;
begin
  select * into l from leads where id = lid for update;
  if not found or l.owner_id is distinct from auth.uid() then raise exception 'Not your lead'; end if;
  perform public._need_active(l.workspace_id);
  update leads set owner_id = null, pool = true, claimed_at = null, contacted_at = null, updated_at = now(),
         data = jsonb_set(data, '{knocks}', coalesce(data->'knocks','[]'::jsonb) ||
                jsonb_build_array(jsonb_build_object('t', (extract(epoch from now())*1000)::bigint, 'r', 'Released', 'by', auth.uid(), 'note', p_reason)))
   where id = lid;
end $$;

create or replace function public.take_over_door(lid text)
returns text language plpgsql security definer set search_path = public as $$
declare l leads; days int;
begin
  select * into l from leads where id = lid for update;
  if not found or not public.is_member(l.workspace_id) then raise exception 'Lead not found'; end if;
  perform public._need_active(l.workspace_id);
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

create or replace function public.ho_link(p_lead text, p_offer jsonb default null) returns text
language plpgsql security definer set search_path = public as $$
declare l leads; t text;
begin
  select * into l from leads where id = p_lead;
  if l.id is null or not public.is_member(l.workspace_id) or not public.can_see_lead(p_lead) then raise exception 'not allowed'; end if;
  perform public._need_active(l.workspace_id);
  if (select plan from workspaces where id = l.workspace_id) = 'field' then raise exception 'The homeowner page comes with the full RUVA plan'; end if;
  select token into t from ho_links where lead_id = p_lead and revoked_at is null;
  if t is null then
    t := replace(gen_random_uuid()::text, '-', '');
    insert into ho_links(token, workspace_id, lead_id) values (t, l.workspace_id, p_lead)
      on conflict (lead_id) do update set token = excluded.token, revoked_at = null, created_at = now(), created_by = auth.uid();
  end if;
  if p_offer is not null and jsonb_typeof(p_offer->'tiers') = 'array' then
    update leads set data = jsonb_set(data, '{ho}', coalesce(data->'ho','{}'::jsonb) || jsonb_build_object('offer', p_offer, 'offerAt', (extract(epoch from now())*1000)::bigint)) where id = p_lead;
  end if;
  return t;
end $$;

create index if not exists messages_image_idx on public.messages(image_path) where image_path is not null;
do $$ begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    execute 'drop policy if exists photos_read on storage.objects';
    execute $p$create policy photos_read on storage.objects for select to authenticated
      using (bucket_id = 'photos' and public.is_member((split_part(name,'/',1))::uuid)
             and case when split_part(name,'/',2) = 'chat'
                      then owner = auth.uid() or exists(select 1 from public.messages m where m.image_path = storage.objects.name)
                      else public.can_view_all((split_part(name,'/',1))::uuid) or public.can_see_lead(split_part(name,'/',2)) end)$p$;
  end if;
end $$;

do $$ begin
  if to_regclass('public.feedback_key') is not null then
    execute $q$update public.feedback_key set k = encode(gen_random_bytes(24), 'hex')$q$;
  end if;
end $$;

-- 14. Data-loss and security fixes from the November 18 code review (part 2).
--  a. AccuLynx: one sender per lead at a time. The every-minute sender and "Send now" take a lease on a waiting
--     lead (acx_claim), so overlapping runs can't send the same lead twice. A lead changed again while it is
--     being sent now gets a new queued_at (so it stays in line), and an edit no longer resets the try count.
--  b. Push notifications: a send that failed because the push service had trouble goes back in line
--     (up to 3 more tries, a few minutes apart). The push function now only sends when the database wakes it
--     with a secret token (kept in push_keys, like the QuickBooks and AccuLynx tokens).
--  c. QuickBooks: room to hold a new sign-in until the person who started connecting confirms it.
--  d. Homeowner page: on the Field plan the homeowner can't pick or sign (the page still shows). Picking the
--     same option again does nothing, and the office gets at most one "Homeowner picked" alert a minute per job.
--     Once the office marks the contract ready the homeowner's pick is locked (the page says to call or text the rep,
--     with the rep's number); the office can reopen it (data.ho.pickOpen), and a new pick locks it again.
-- Safe to run more than once. Nothing here changes or deletes customer data.

-- a. AccuLynx queue lease -----------------------------------------------------------------------------
alter table public.acx_queue add column if not exists leased_until timestamptz;

create or replace function public.acx_claim(p_limit int default 60, p_lease_sec int default 300, p_ws uuid default null, p_lead text default null)
returns table(workspace_id uuid, lead_id text, tries int, queued_at timestamptz)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare lease interval := make_interval(secs => greatest(30, least(coalesce(p_lease_sec, 300), 3600)));
begin
  -- due rows (or the one lead "Send now" asked for) that nobody else holds right now
  return query
    update acx_queue q set leased_until = now() + lease, next_at = greatest(q.next_at, now() + lease)
     where (q.workspace_id, q.lead_id) in (
       select x.workspace_id, x.lead_id from acx_queue x
        where (x.leased_until is null or x.leased_until <= now())
          and (case when p_lead is null then x.next_at <= now() else x.lead_id = p_lead end)
          and (p_ws is null or x.workspace_id = p_ws)
        order by x.next_at
        limit greatest(1, least(coalesce(p_limit, 60), 200))
        for update skip locked)
    returning q.workspace_id, q.lead_id, q.tries, q.queued_at;
end $$;
revoke execute on function public.acx_claim(int, int, uuid, text) from public, anon, authenticated;
do $$ begin execute 'grant execute on function public.acx_claim(int, int, uuid, text) to service_role'; exception when others then null; end $$;

create or replace function public._acx_on_lead() returns trigger
language plpgsql security definer set search_path = public as $$
declare st jsonb;
begin
  select settings->'statuses' into st from acx_conn where workspace_id = new.workspace_id and status = 'connected';
  if not found then return new; end if;
  if tg_op = 'UPDATE' and new.status is not distinct from old.status and new.data is not distinct from old.data
     and new.name is not distinct from old.name and new.phone is not distinct from old.phone then return new; end if;
  if coalesce(st, '["Inspection Scheduled","Inspected","Claim Pending","Sold"]'::jsonb) ? new.status
     or exists (select 1 from acx_map where workspace_id = new.workspace_id and lead_id = new.id and job_id is not null) then
    insert into acx_queue(workspace_id, lead_id, next_at) values (new.workspace_id, new.id, now() + interval '30 seconds')
      on conflict (workspace_id, lead_id) do update set next_at = greatest(acx_queue.next_at, now() + interval '30 seconds'), queued_at = clock_timestamp();
  end if;
  return new;
end $$;
revoke execute on function public._acx_on_lead() from public, anon, authenticated;

-- b. Push: retries and a wake-up token ---------------------------------------------------------------
alter table public.push_outbox add column if not exists tries int not null default 0;
alter table public.push_outbox add column if not exists next_at timestamptz;
alter table public.push_keys add column if not exists cron_token text not null default encode(gen_random_bytes(32), 'hex');

create or replace function public._push_wake() returns void
language plpgsql security definer set search_path = public as $$
declare k push_keys;
begin
  select * into k from push_keys where id = 1;
  if coalesce(k.fn_url,'') = '' then return; end if;
  begin
    perform net.http_post(url := k.fn_url, body := jsonb_build_object('token', k.cron_token), headers := '{"Content-Type":"application/json"}'::jsonb);
  exception when others then null;
  end;
end $$;

create or replace function public.push_retry() returns void
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from push_outbox where sent_at is null and created_at > now() - interval '1 day' and (next_at is null or next_at <= now())) then
    perform public._push_wake();
  end if;
end $$;

create or replace function public.push_init(p_public text, p_private jsonb, p_url text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k push_keys;
begin
  select * into k from push_keys where id = 1;
  if not found then
    if p_public is null then raise exception 'no keys'; end if;
    insert into push_keys(id, public_key, private_jwk, fn_url) values (1, p_public, p_private, coalesce(p_url,''))
    on conflict (id) do nothing;
    select * into k from push_keys where id = 1;
  end if;
  if coalesce(p_url,'') <> '' and k.fn_url is distinct from p_url then
    update push_keys set fn_url = p_url where id = 1 returning * into k;
  end if;
  return jsonb_build_object('public_key', k.public_key, 'private_jwk', k.private_jwk, 'fn_url', k.fn_url, 'cron_token', k.cron_token);
end $$;

create or replace function public.push_claim(p_limit int default 200) returns setof public.push_outbox
language plpgsql security definer set search_path = public as $$
begin
  delete from push_outbox where created_at < now() - interval '7 days';
  return query
    update push_outbox o set sent_at = now()
     where o.id in (select id from push_outbox where sent_at is null and created_at > now() - interval '1 day'
                     and (next_at is null or next_at <= now())
                     order by id limit greatest(1, least(coalesce(p_limit,200), 500)) for update skip locked)
    returning o.*;
end $$;

-- A message no device got because the push service had trouble: try again in 2, 4, then 6 minutes, then give up.
create or replace function public.push_fail(p_ids bigint[]) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update push_outbox set sent_at = null, tries = tries + 1, next_at = now() + make_interval(mins => 2 * (tries + 1))
   where id = any(coalesce(p_ids, '{}'::bigint[])) and sent_at is not null and tries < 3;
  get diagnostics n = row_count;
  return n;
end $$;

revoke execute on function public._push_wake() from public, anon, authenticated;
revoke execute on function public.push_retry() from public, anon, authenticated;
revoke execute on function public.push_init(text, jsonb, text) from public, anon, authenticated;
revoke execute on function public.push_claim(int) from public, anon, authenticated;
revoke execute on function public.push_fail(bigint[]) from public, anon, authenticated;
do $$ begin
  execute 'grant execute on function public.push_init(text, jsonb, text), public.push_claim(int), public.push_fail(bigint[]) to service_role';
exception when others then null; end $$;

-- c. QuickBooks: a sign-in waiting for the person who started it (encrypted by the qbo function) -------
alter table public.qbo_state add column if not exists pending text;

-- d. Homeowner page ----------------------------------------------------------------------------------
create or replace function public.ho_pick(p_token text, p_i int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k ho_links; l leads; t jsonb; sq numeric; ln jsonb; who uuid[];
begin
  select * into k from ho_links where token = p_token and revoked_at is null;
  if k.token is null then raise exception 'link not found'; end if;
  select * into l from leads where id = k.lead_id for update;
  if (select plan from workspaces where id = l.workspace_id) = 'field' then raise exception 'The homeowner page comes with the full RUVA plan'; end if;
  if coalesce(l.data->'est'->>'sigAt','') <> '' then raise exception 'already signed'; end if;
  -- once the office marks the contract ready, the pick is locked until the office reopens it
  if coalesce(l.data->'sale'->'er'->>'st','') = 'ready' and l.data->'est'->'pick' is not null
     and not coalesce((l.data->'ho'->>'pickOpen')::boolean, false) then raise exception 'pick locked'; end if;
  t := l.data->'ho'->'offer'->'tiers'->p_i;
  if t is null then raise exception 'no such option'; end if;
  sq := coalesce(nullif(l.data->'ho'->'offer'->>'sq','')::numeric, 0);
  ln := jsonb_build_object('d', 'Tear off and replace · ' || coalesce(t->>'name','') || ' (' || (t->>'n') || ')', 'q', sq::text, 'u', 'SQ', 'p', t->>'per', 'tier', 1);
  -- the same option again, with the same price: nothing to change, nobody to tell
  if l.data->'est'->'pick' = to_jsonb(p_i)
     and exists (select 1 from jsonb_array_elements(coalesce(l.data->'est'->'lines','[]'::jsonb)) x where x = ln) then
    return public.ho_view(p_token);
  end if;
  update leads set data = jsonb_set(jsonb_set(jsonb_set(jsonb_set(data,
      '{ho}', coalesce(data->'ho','{}'::jsonb) - 'pickOpen'),
      '{est,lines}', jsonb_build_array(ln) || coalesce((select jsonb_agg(x) from jsonb_array_elements(coalesce(data->'est'->'lines','[]'::jsonb)) x where coalesce((x->>'tier')::int,0) <> 1), '[]'::jsonb)),
      '{est,pick}', to_jsonb(p_i)),
      '{log}', coalesce(data->'log','[]'::jsonb) || jsonb_build_array(jsonb_build_object('t', (extract(epoch from now())*1000)::bigint, 'text', 'Homeowner picked ' || (t->>'n') || ' from their link · $' || to_char(sq * (t->>'per')::numeric, 'FM999,999,990'))))
    where id = l.id;
  -- at most one alert a minute per job, so clicking back and forth doesn't buzz the office every time
  if not exists (select 1 from push_outbox where tag = 'ho:' || l.id and created_at > now() - interval '1 minute') then
    who := array(select user_id from members where workspace_id = l.workspace_id and active and not support and (role in ('owner','manager','office') or user_id = l.owner_id));
    perform public._push(who, 'jobs', 'Homeowner picked ' || (t->>'n'), public._push_addr(l) || ' · $' || to_char(sq * (t->>'per')::numeric, 'FM999,999,990'), './?lead=' || l.id || '#leads', 'ho:' || l.id);
  end if;
  return public.ho_view(p_token);
end $$;

create or replace function public.ho_sign(p_token text, p_name text, p_img text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k ho_links; l leads; now_ms bigint := (extract(epoch from now())*1000)::bigint;
begin
  select * into k from ho_links where token = p_token and revoked_at is null;
  if k.token is null then raise exception 'link not found'; end if;
  select * into l from leads where id = k.lead_id for update;
  if (select plan from workspaces where id = l.workspace_id) = 'field' then raise exception 'The homeowner page comes with the full RUVA plan'; end if;
  if coalesce(l.data->'sale'->'er'->>'st','') <> 'ready' then raise exception 'contract not ready'; end if;
  if coalesce(l.data->'est'->>'sigAt','') <> '' then raise exception 'already signed'; end if;
  if length(trim(coalesce(p_name,''))) < 2 then raise exception 'name required'; end if;
  if p_img is null or p_img not like 'data:image/png;base64,%' or length(p_img) > 300000 then raise exception 'bad signature'; end if;
  update leads set data = jsonb_set(jsonb_set(jsonb_set(jsonb_set(data,
      '{est,hoSig}', jsonb_build_object('img', p_img, 'name', trim(p_name), 'at', now_ms)),
      '{est,sigName}', to_jsonb(trim(p_name))),
      '{est,sigAt}', to_jsonb(to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))),
      '{log}', coalesce(data->'log','[]'::jsonb) || jsonb_build_array(jsonb_build_object('t', now_ms, 'text', 'Homeowner signed the contract from their link')))
    where id = l.id;
  return public.ho_view(p_token);
end $$;

-- The homeowner page gets pick_locked and the rep's phone (based on the live ho_view, Nov 18).
create or replace function public.ho_view(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare k ho_links; l leads; w workspaces; e jsonb; tot numeric := 0; rep text; pid text; roof text; rph text;
begin
  select * into k from ho_links where token = p_token and length(p_token) >= 24 and revoked_at is null;
  if k.token is null then return null; end if;
  select * into l from leads where id = k.lead_id;
  if l.id is null then return null; end if;
  select * into w from workspaces where id = l.workspace_id;
  e := coalesce(l.data->'est', '{}'::jsonb);
  select coalesce(sum(coalesce(nullif(regexp_replace(x->>'q','[^0-9.]','','g'),'')::numeric,0) * coalesce(nullif(regexp_replace(x->>'p','[^0-9.-]','','g'),'')::numeric,0)),0)
    into tot from jsonb_array_elements(coalesce(e->'lines','[]'::jsonb)) x;
  rep := case when l.owner_id is not null then split_part(public._push_name(l.workspace_id, l.owner_id), ' ', 1) end;
  if l.owner_id is not null then select nullif(trim(phone),'') into rph from members where workspace_id = l.workspace_id and user_id = l.owner_id and active; end if;
  pid := e->'sys'->>'pid';
  if pid is not null then
    select trim(concat_ws(' ', nullif(nullif(c->>'brand',''),'Any'), c->>'name')) into roof from jsonb_array_elements(coalesce(w.settings->'catalog','[]'::jsonb)) c where c->>'id' = pid limit 1;
    if roof is null then roof := case pid when 'a1' then 'Atlas Pinnacle Pristine' end; end if;
  end if;
  if roof is not null and coalesce(e->'sys'->>'color', e->>'color', '') <> '' then roof := roof || ' · ' || coalesce(nullif(e->'sys'->>'color',''), e->>'color'); end if;
  return jsonb_build_object(
    'company', jsonb_build_object('name', w.name, 'phone', w.settings->'profile'->>'phone', 'logo', w.settings->'profile'->>'logo', 'license', w.settings->'profile'->>'license'),
    'rep', rep, 'rep_phone', rph,
    'name', l.name, 'address', trim(concat_ws(' ', l.num, l.street)), 'city', l.city,
    'type', coalesce(l.data->'sale'->>'type', 'Insurance'),
    'status', l.status, 'stage', l.data->'sale'->>'stage',
    'install', l.data->'sale'->'install'->>'at',
    'offer', l.data->'ho'->'offer',
    'pick', e->'pick',
    'pick_locked', coalesce(l.data->'sale'->'er'->>'st','') = 'ready' and e->'pick' is not null and not coalesce((l.data->'ho'->>'pickOpen')::boolean, false),
    'roof', roof,
    'contract', case when (coalesce(l.data->'sale'->'er'->>'st','') = 'ready' or coalesce(e->>'sigAt','') <> '') and tot > 0 then jsonb_build_object(
        'total', round(tot, 2),
        'lines', (select jsonb_agg(x->>'d') from jsonb_array_elements(coalesce(e->'lines','[]'::jsonb)) x where coalesce(x->>'d','') <> ''),
        'terms', w.settings->>'terms') end,
    'signed', case when coalesce(e->>'sigAt','') <> '' then jsonb_build_object('name', e->>'sigName', 'at', e->>'sigAt') end
  );
end $$;

revoke execute on function public.ho_pick(text, int), public.ho_sign(text, text, text), public.ho_view(text) from public;
grant execute on function public.ho_pick(text, int), public.ho_sign(text, text, text), public.ho_view(text) to anon, authenticated;

-- 15. Review fixes (3): longer invite codes, pin history follows "hide teammates' pins", protection dates
-- capped at the company's window, job numbers handed out by the server, and the one-time Stripe setup
-- race. Safe to run more than once. No table or column changes; existing data is not touched.

-- ---------------------------------------------------------------------------------------------
-- Invite codes: 10 characters from 32 easy-to-read letters and digits (no 0, O, 1 or I), about
-- 1 in a quadrillion per guess instead of 1 in 16 million. Old 6-character codes keep working.
-- Randomness comes from gen_random_uuid(), which is built in (pgcrypto lives in another schema).
-- ---------------------------------------------------------------------------------------------
create or replace function public._invite_code() returns text
language plpgsql volatile set search_path = public as $$
declare a text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; b bytea; c text; i int;  -- 32 characters, so each byte maps evenly
begin
  loop
    b := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
    c := '';
    -- skip bytes 6 and 8: they carry the UUID version and variant bits
    foreach i in array array[0,1,2,3,4,5,9,10,11,12] loop
      c := c || substr(a, (get_byte(b, i) % 32) + 1, 1);
    end loop;
    exit when not exists (select 1 from invites where code = c);
  end loop;
  return c;
end $$;
revoke execute on function public._invite_code() from public, anon, authenticated;

create or replace function public.create_invite(ws uuid, p_role text)
returns text language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if not public.is_manager(ws) then raise exception 'Only managers can invite'; end if;
  c := public._invite_code();
  insert into invites(code, workspace_id, role, created_by) values (c, ws, p_role, auth.uid());
  return c;
end $$;

create or replace function public.create_invite_for(ws uuid, p_role text, p_name text, p_phone text, p_email text)
returns text language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if not public.is_manager(ws) then raise exception 'Only managers can invite'; end if;
  if p_role not in ('manager','rep','office') then raise exception 'Unknown role'; end if;
  c := public._invite_code();
  insert into invites(code, workspace_id, role, created_by, max_uses, expires_at, name, phone, email)
  values (c, ws, p_role, auth.uid(), 1, now() + interval '30 days', coalesce(trim(p_name),''), coalesce(trim(p_phone),''), coalesce(lower(trim(p_email)),''));
  return c;
end $$;

create or replace function public.admin_invite(ws uuid, p_role text) returns text
language plpgsql security definer set search_path = public as $$
declare c text; w workspaces;
begin
  perform public._need_admin();
  if p_role not in ('manager','rep','office') then raise exception 'Unknown role'; end if;
  select * into w from workspaces where id = ws;
  c := public._invite_code();
  insert into invites(code, workspace_id, role, created_by) values (c, ws, p_role, w.owner_id);
  perform public._alog(ws, 'Support made a ' || p_role || ' invite code');
  return c;
end $$;

-- ---------------------------------------------------------------------------------------------
-- Pin history: when "Teammates' pins on the map" is off, a rep gets nothing back for a
-- teammate's door, the same as team_pins. Owners, managers, office and the lead's own rep
-- still see it.
-- ---------------------------------------------------------------------------------------------
create or replace function public.pin_history(lid text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('created_by', l.created_by, 'created_at', l.created_at, 'owner_id', l.owner_id,
         'knocks', case when public.can_view_all(l.workspace_id) or l.owner_id = auth.uid()
                        then coalesce(l.data->'knocks','[]'::jsonb)
                        else (select coalesce(jsonb_agg(k - 'gps'), '[]'::jsonb) from jsonb_array_elements(coalesce(l.data->'knocks','[]'::jsonb)) k) end)
  from leads l join workspaces w on w.id = l.workspace_id
  where l.id = lid and public.is_member(l.workspace_id)
    and (coalesce((w.settings->>'teammate_pins')::boolean, true)
         or public.can_view_all(l.workspace_id) or l.owner_id = auth.uid())
$$;

-- ---------------------------------------------------------------------------------------------
-- Door protection: a rep's app still renews protection each time they work the door, but the
-- date can never be set past today + the company's protection window (protect_days, default 30).
-- Owners and managers can still set any date.
-- ---------------------------------------------------------------------------------------------
create or replace function public._protect_cap(ws uuid) returns timestamptz
language sql stable security definer set search_path = public as $$
  select now() + make_interval(days => greatest(1, coalesce((select (settings->>'protect_days')::int from workspaces where id = ws), 30)))
$$;

create or replace function public.leads_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user not in ('authenticated','anon') then return new; end if;
  -- Reports the owner, a manager or the office attached can only be removed by them, not by the rep
  if not public.can_view_all(old.workspace_id) and exists (
       select 1 from jsonb_array_elements(case when jsonb_typeof(old.data->'docs') = 'array' then old.data->'docs' else '[]'::jsonb end) d
       where coalesce(d->>'staff','') = 'true'
         and not (case when jsonb_typeof(new.data->'docs') = 'array' then new.data->'docs' else '[]'::jsonb end) @> jsonb_build_array(jsonb_build_object('id', d->'id'))) then
    raise exception 'Only the office can remove a report it attached';
  end if;
  if public.is_manager(old.workspace_id) and public.is_manager(new.workspace_id) then return new; end if;
  if new.workspace_id is distinct from old.workspace_id or new.owner_id is distinct from old.owner_id
     or new.created_by is distinct from old.created_by or new.origin is distinct from old.origin
     or new.pool is distinct from old.pool or new.posted_by is distinct from old.posted_by
     or new.posted_at is distinct from old.posted_at or new.claimed_at is distinct from old.claimed_at then
    raise exception 'Only a manager can change who owns a lead or its board status';
  end if;
  if new.protected_until is distinct from old.protected_until and new.protected_until is not null then
    new.protected_until := least(new.protected_until, public._protect_cap(new.workspace_id));
  end if;
  return new;
end $$;

create or replace function public.leads_insert_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user not in ('authenticated','anon') or public.is_manager(new.workspace_id) then return new; end if;
  if new.protected_until is not null then
    new.protected_until := least(new.protected_until, public._protect_cap(new.workspace_id));
  end if;
  return new;
end $$;
drop trigger if exists leads_insert_guard on public.leads;
create trigger leads_insert_guard before insert on public.leads for each row execute function public.leads_insert_guard();

-- ---------------------------------------------------------------------------------------------
-- Job numbers: the dashboard used to pick the next number itself, so two office computers
-- refreshing at the same moment could hand out the same number. Now the server hands them out
-- one company at a time. A lead that already has a number keeps it.
-- p_ids: leads that need a number, oldest first. Returns {lead_id: job number}.
-- ---------------------------------------------------------------------------------------------
create or replace function public.assign_job_nos(ws uuid, p_prefix text, p_ids text[])
returns jsonb language plpgsql security definer set search_path = public as $$
declare pre text := left(upper(regexp_replace(coalesce(p_prefix,''), '[^A-Za-z]', '', 'g')), 4);
        n int; lid text; cur text; ok boolean; res jsonb := '{}'::jsonb;
begin
  if not public.can_view_all(ws) then raise exception 'Not allowed'; end if;
  if pre = '' then pre := 'RR'; end if;
  perform pg_advisory_xact_lock(hashtext('ruva-jobno:' || ws::text));
  select greatest(99, coalesce(max(split_part(data->>'jobNo', '-', 2)::int), 99)) into n
    from leads where workspace_id = ws and split_part(coalesce(data->>'jobNo',''), '-', 2) ~ '^[0-9]{1,9}$';
  foreach lid in array coalesce(p_ids[1:1000], '{}') loop
    select true, data->>'jobNo' into ok, cur from leads where id = lid and workspace_id = ws for update;
    continue when ok is null;
    if coalesce(cur, '') = '' then
      n := n + 1; cur := pre || '-' || n;
      update leads set data = jsonb_set(data, '{jobNo}', to_jsonb(cur)) where id = lid;
    end if;
    res := res || jsonb_build_object(lid, cur);
    ok := null;
  end loop;
  return res;
end $$;
revoke execute on function public.assign_job_nos(uuid, text, text[]) from public, anon;
grant execute on function public.assign_job_nos(uuid, text, text[]) to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Stripe setup: the first save of the prices, the webhook and the seat-sync token wins. If two
-- requests set billing up at the same moment, the second keeps the first one's values (and the
-- billing function deletes the extra webhook it made). To replace a value, clear it in the table first.
-- ---------------------------------------------------------------------------------------------
create or replace function public.billing_cfg_set(p_mode text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r billing_cfg;
begin
  insert into billing_cfg(mode) values (p_mode) on conflict (mode) do nothing;
  update billing_cfg set
    price_solo     = coalesce(price_solo, p->>'price_solo'),
    price_team     = coalesce(price_team, p->>'price_team'),
    webhook_id     = case when webhook_id is null or webhook_secret is null then coalesce(p->>'webhook_id', webhook_id) else webhook_id end,
    webhook_secret = case when webhook_id is null or webhook_secret is null then coalesce(p->>'webhook_secret', webhook_secret) else webhook_secret end,
    fn_url         = coalesce(p->>'fn_url', fn_url),
    wake_token     = coalesce(nullif(wake_token, ''), p->>'wake_token', wake_token),
    updated_at     = now()
  where mode = p_mode returning * into r;
  return to_jsonb(r);
end $$;
revoke execute on function public.billing_cfg_set(text, jsonb) from public, anon, authenticated;

-- =====================================================================
-- 16. Email campaigns. Follow-ups to leads (by temperature), past-customer emails, unsubscribes.
-- Both plans (Full and Field). Nothing sends until a company turns a campaign on, and nothing reaches a
-- homeowner until the "email" Edge Function's EMAIL_LIVE secret is set. No existing table changes:
-- temperature, "pause emails" and the Keep Warm snooze live in leads.data (temp, tempAt, emailsPaused).

create table if not exists public.email_settings (
  workspace_id     uuid primary key references public.workspaces(id) on delete cascade,
  enabled          boolean not null default false,
  from_name        text not null default '',
  from_local       text not null default 'team',
  office_reply_to  text not null default '',
  mailing_address  text not null default '',
  review_url       text not null default '',
  timezone         text not null default 'America/New_York',
  domain           text not null default '',
  domain_status    text not null default 'none' check (domain_status in ('none','pending','verified','failed')),
  provider_domain_id text not null default '',
  dns              jsonb not null default '[]'::jsonb,
  campaigns        jsonb not null default '{}'::jsonb,   -- {inspected_no_answer:true, ...}
  field_days       jsonb not null default '{"review":30,"referral":60}'::jsonb,
  test_to          text not null default '',              -- while EMAIL_LIVE is off, everything goes here
  updated_by       uuid,
  updated_at       timestamptz not null default now()
);

create table if not exists public.email_templates (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  campaign     text not null,
  step         text not null,
  subject      text not null,
  body         text not null,
  updated_at   timestamptz not null default now(),
  primary key (workspace_id, campaign, step)
);

create table if not exists public.email_sends (
  id           bigserial primary key,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  lead_id      text not null,
  campaign     text not null,
  step         text not null,
  to_email     text not null,
  status       text not null default 'queued' check (status in ('queued','sending','sent','failed','bounced','complained','skipped')),
  claimed_at   timestamptz,
  provider_id  text,
  error        text not null default '',
  test         boolean not null default false,
  created_at   timestamptz not null default now(),
  sent_at      timestamptz,
  unique (workspace_id, lead_id, campaign, step)
);
create index if not exists email_sends_ws on public.email_sends(workspace_id, created_at desc);
create index if not exists email_sends_queued on public.email_sends(created_at) where status = 'queued';
create index if not exists email_sends_provider on public.email_sends(provider_id) where provider_id is not null;

create table if not exists public.email_unsubs (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  email        text not null,
  reason       text not null default 'unsubscribed' check (reason in ('unsubscribed','bounced','complained')),
  created_at   timestamptz not null default now(),
  primary key (workspace_id, email)
);

create table if not exists public.email_cfg (id int primary key default 1 check (id = 1), cron_token text not null, daily_cap int not null default 100);
insert into public.email_cfg(id, cron_token) values (1, encode(gen_random_bytes(32), 'hex')) on conflict (id) do nothing;

alter table public.email_settings  enable row level security;
alter table public.email_templates enable row level security;
alter table public.email_sends     enable row level security;
alter table public.email_unsubs    enable row level security;
alter table public.email_cfg       enable row level security;
revoke all on public.email_settings, public.email_templates, public.email_sends, public.email_unsubs, public.email_cfg from anon, authenticated;
do $$ begin
  execute 'grant all on public.email_settings, public.email_templates, public.email_sends, public.email_unsubs, public.email_cfg to service_role';
  execute 'grant usage, select on sequence public.email_sends_id_seq to service_role';
exception when others then null; end $$;

-- Default wording. A company's own edits (email_templates) win.
create or replace function public.email_defaults() returns jsonb language sql immutable as $$
select '{
 "inspected_no_answer": {
  "d3":  {"subject":"Your roof inspection at {address}","body":"Hi {first_name}, it''s {rep_name} with {company}. Thanks again for letting me look at your roof. If you have any questions about what I found or the estimate, just reply here or call me at {rep_phone}."},
  "d7":  {"subject":"Checking in on your roof","body":"Hi {first_name}, I wanted to check back in. Small roof problems usually get bigger, and it''s easier to deal with them now. I''m glad to walk through the estimate with you, no pressure. {rep_phone}"},
  "d14": {"subject":"Last note from me","body":"Hi {first_name}, this is my last follow-up so I don''t crowd your inbox. If you ever want to pick this back up, reply here and I''ll take care of you.\n\n{rep_name}, {company}"}},
 "not_inspected": {
  "d2":  {"subject":"Free roof inspection","body":"Hi {first_name}, it''s {rep_name} with {company}. I can come out and inspect your roof for free. It takes about 30 minutes, and you''ll get photos of everything I see. Reply with a day that works, or call {rep_phone}."},
  "d7":  {"subject":"Still want that roof check?","body":"Hi {first_name}, just following up. If now isn''t a good time, no problem. If you''d like the inspection, reply and I''ll get you on the schedule.\n\n{rep_name}"}},
 "cold_checkin": {
  "m":   {"subject":"Still here if you need us","body":"Hi {first_name}, it''s {rep_name} with {company}. Just checking in. If your roof took a hit or you''re ready to talk about it, reply here or call {rep_phone}."}},
 "pc_review": {
  "r":   {"subject":"How did we do?","body":"Hi {first_name}, thanks for trusting {company} with your roof. If we did right by you, a quick review helps us a lot: {review_url}\n\nIf anything isn''t right, reply here and we''ll fix it."}},
 "pc_referral": {
  "f":   {"subject":"Know someone who needs a roof?","body":"Hi {first_name}, our best work comes from neighbors telling neighbors. If you know someone with roof damage or an old roof, reply with their name or pass along our number. We''ll treat them the way we treated you."}},
 "pc_yearly": {
  "y":   {"subject":"Your yearly roof check","body":"Hi {first_name}, it''s been a year since we put the roof on at {address}. We''ll come check it over for free. Reply and we''ll set up a time."}}
}'::jsonb $$;

-- Where a lead sits: door, lost, N (new), I (inspected), S (sold) — same rules as the app's pstage().
create or replace function public._email_stage(l public.leads) returns text language sql immutable as $$
  select case
    when coalesce(l.status,'') in ('','Not Home','Not Interested') then 'door'
    when l.status in ('No Damage','Finance Denied','Cancelled') then 'lost'
    when l.status = 'Sold' then 'S'
    when l.status in ('Inspected','Claim Pending') or jsonb_array_length(coalesce(l.data->'est'->'lines','[]'::jsonb)) > 0 then 'I'
    else 'N' end $$;

create or replace function public._email_ms(v text) returns timestamptz language sql immutable as $$
  select case when v ~ '^\d{10,14}$' then to_timestamp(v::numeric / 1000)
              when v ~ '^\d{4}-\d{2}-\d{2}' then (left(v, 10))::date::timestamptz
              else null end $$;

-- Every step a lead could get, with when it's due. Sent steps are filtered by the callers.
create or replace function public._email_steps(l public.leads, plan text, fdays jsonb)
returns table(campaign text, step text, due timestamptz)
language plpgsql stable set search_path = public as $$
declare st text := _email_stage(l); t text := coalesce(nullif(l.data->>'temp',''),'warm');
  t_at timestamptz := _email_ms(l.data->>'tempAt'); insp timestamptz; a timestamptz; n int;
begin
  if st in ('N','I') then
    if t = 'hot' or l.owner_id is null or l.pool then return; end if;
    if t = 'cold' then
      a := coalesce(t_at, l.updated_at);
      for n in 1..36 loop campaign := 'cold_checkin'; step := 'm' || n || '@' || to_char(a, 'YYYY-MM-DD'); due := a + make_interval(months => n); return next; end loop;
      return;
    end if;
    if st = 'I' then
      select max(_email_ms(k->>'t')) into insp from jsonb_array_elements(coalesce(l.data->'knocks','[]'::jsonb)) k
        where k->>'r' in ('Inspected','Claim Pending');
      a := greatest(coalesce(insp, l.created_at), coalesce(t_at, '-infinity'::timestamptz));
      campaign := 'inspected_no_answer';
      step := 'd3';  due := a + interval '3 days';  return next;
      step := 'd7';  due := a + interval '7 days';  return next;
      step := 'd14'; due := a + interval '14 days'; return next;
    elsif l.status <> 'Inspection Scheduled' then
      a := greatest(l.created_at, coalesce(t_at, '-infinity'::timestamptz));
      campaign := 'not_inspected';
      step := 'd2'; due := a + interval '2 days'; return next;
      step := 'd7'; due := a + interval '7 days'; return next;
    end if;
  elsif st = 'S' then
    if plan = 'field' then
      a := _email_ms(l.data->'sale'->>'soldAt');
      if a is null then return; end if;
      campaign := 'pc_review';   step := 'r'; due := a + make_interval(days => coalesce((fdays->>'review')::int, 30));   return next;
      campaign := 'pc_referral'; step := 'f'; due := a + make_interval(days => coalesce((fdays->>'referral')::int, 60)); return next;
    else
      -- Full: count from the install date once the job is built (Installed, Final check paid or invoiced).
      if not (coalesce(l.data->'sale'->>'stage','') in ('Installed','Final check paid') or coalesce(l.data->'sale'->'inv'->>'sentAt','') <> '') then return; end if;
      a := _email_ms(l.data->'sale'->'install'->>'at');
      if a is null or a > now() then return; end if;
      campaign := 'pc_review';   step := 'r'; due := a + interval '7 days';  return next;
      campaign := 'pc_referral'; step := 'f'; due := a + interval '30 days'; return next;
    end if;
    for n in 1..10 loop campaign := 'pc_yearly'; step := 'y' || n; due := a + make_interval(years => n); return next; end loop;
  end if;
end $$;

-- Who's due right now. Called every 15 minutes. Only steps that came due in the last 2 days, so turning a
-- campaign on never sends a pile of old emails. Mon–Sat, 9am–6pm in the company's time zone.
create or replace function public.email_enqueue() returns int
language plpgsql security definer set search_path = public as $$
declare cap int; used int; added int := 0; r record;
begin
  select daily_cap into cap from email_cfg where id = 1;
  select count(*) into used from email_sends where created_at > now() - interval '1 day' and status in ('queued','sending','sent');
  if used >= coalesce(cap, 100) then return 0; end if;
  for r in
    select l.workspace_id, l.id, lower(trim(l.data->>'email')) as em, x.campaign, x.step, x.due
    from email_settings s
    join workspaces w on w.id = s.workspace_id
    join leads l on l.workspace_id = s.workspace_id
    cross join lateral _email_steps(l, w.plan, s.field_days) x
    where s.enabled
      and extract(isodow from now() at time zone s.timezone) between 1 and 6
      and extract(hour from now() at time zone s.timezone) between 9 and 17
      and coalesce(s.campaigns->>x.campaign, 'false') = 'true'
      and coalesce(l.data->>'emailsPaused', 'false') <> 'true'
      and coalesce(l.data->>'email', '') ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'
      and x.due <= now() and x.due > now() - interval '2 days'
      and not exists (select 1 from email_unsubs u where u.workspace_id = l.workspace_id and u.email = lower(trim(l.data->>'email')))
      and not exists (select 1 from email_sends e where e.workspace_id = l.workspace_id and e.lead_id = l.id and e.campaign = x.campaign and e.step = x.step)
      -- one email per lead per day at most
      and not exists (select 1 from email_sends e where e.workspace_id = l.workspace_id and e.lead_id = l.id and e.created_at > now() - interval '20 hours' and e.status <> 'skipped')
    order by x.due
  loop
    exit when used + added >= coalesce(cap, 100);
    insert into email_sends(workspace_id, lead_id, campaign, step, to_email)
      values (r.workspace_id, r.id, r.campaign, r.step, r.em) on conflict do nothing;
    if found then added := added + 1; end if;
  end loop;
  return added;
end $$;

-- Office (owner/manager): settings, templates, counts and recent sends.
create or replace function public.email_status(ws uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s email_settings;
begin
  if not public.can_view_all(ws) then raise exception 'not allowed'; end if;
  select * into s from email_settings where workspace_id = ws;
  return jsonb_build_object(
    'can_edit', public.is_manager(ws),
    'plan', (select plan from workspaces where id = ws),
    'company', (select name from workspaces where id = ws),
    'settings', case when s.workspace_id is null then jsonb_build_object('enabled', false, 'from_local', 'team', 'timezone', 'America/New_York',
                     'domain_status', 'none', 'campaigns', '{}'::jsonb, 'field_days', '{"review":30,"referral":60}'::jsonb, 'dns', '[]'::jsonb)
                else to_jsonb(s) - 'workspace_id' - 'provider_domain_id' - 'updated_by' end,
    'defaults', email_defaults(),
    'templates', coalesce((select jsonb_object_agg(t.campaign || '.' || t.step, jsonb_build_object('subject', t.subject, 'body', t.body))
                           from email_templates t where t.workspace_id = ws), '{}'::jsonb),
    'sent_30d', (select count(*) from email_sends e where e.workspace_id = ws and e.status = 'sent' and e.sent_at > now() - interval '30 days'),
    'unsubs', (select count(*) from email_unsubs u where u.workspace_id = ws),
    'log', coalesce((select jsonb_agg(jsonb_build_object('at', coalesce(e.sent_at, e.created_at), 'lead', e.lead_id, 'name', l.name,
                       'campaign', e.campaign, 'step', e.step, 'to', e.to_email, 'status', e.status, 'error', e.error, 'test', e.test) order by e.created_at desc)
                     from (select * from email_sends where workspace_id = ws order by created_at desc limit 100) e
                     left join leads l on l.id = e.lead_id), '[]'::jsonb));
end $$;

-- Owner/manager: save settings. Turning email on needs a mailing address (the law requires it in every email).
create or replace function public.email_save(ws uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare s email_settings; okc text[] := array['inspected_no_answer','not_inspected','cold_checkin','pc_review','pc_referral','pc_yearly'];
  c jsonb := '{}'::jsonb; k text;
begin
  if not public.is_manager(ws) then raise exception 'Only an owner or manager can change email settings'; end if;
  insert into email_settings(workspace_id) values (ws) on conflict do nothing;
  select * into s from email_settings where workspace_id = ws;
  if p ? 'campaigns' then
    foreach k in array okc loop if p->'campaigns' ? k then c := c || jsonb_build_object(k, (p->'campaigns'->>k)::boolean); end if; end loop;
    s.campaigns := s.campaigns || c;
  end if;
  if p ? 'from_name'       then s.from_name := left(trim(p->>'from_name'), 80); end if;
  if p ? 'from_local'      then
    if coalesce(p->>'from_local','') !~ '^[a-z0-9][a-z0-9._-]{0,40}$' then raise exception 'The from address can use letters, numbers, dots and dashes'; end if;
    s.from_local := p->>'from_local'; end if;
  if p ? 'office_reply_to' then
    if coalesce(p->>'office_reply_to','') <> '' and p->>'office_reply_to' !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Check the reply-to email'; end if;
    s.office_reply_to := lower(trim(p->>'office_reply_to')); end if;
  if p ? 'mailing_address' then s.mailing_address := left(trim(p->>'mailing_address'), 200); end if;
  if p ? 'review_url'      then
    if coalesce(p->>'review_url','') <> '' and p->>'review_url' !~* '^https://' then raise exception 'The review link should start with https://'; end if;
    s.review_url := left(trim(p->>'review_url'), 500); end if;
  if p ? 'timezone'        then
    if not exists (select 1 from pg_timezone_names where name = p->>'timezone') then raise exception 'Unknown time zone'; end if;
    s.timezone := p->>'timezone'; end if;
  if p ? 'field_days'      then s.field_days := jsonb_build_object(
      'review',   least(greatest(coalesce((p->'field_days'->>'review')::int, 30), 1), 365),
      'referral', least(greatest(coalesce((p->'field_days'->>'referral')::int, 60), 1), 365)); end if;
  if p ? 'test_to'         then
    if coalesce(p->>'test_to','') <> '' and p->>'test_to' !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Check the test email'; end if;
    s.test_to := lower(trim(p->>'test_to')); end if;
  if p ? 'enabled'         then s.enabled := (p->>'enabled')::boolean; end if;
  if s.enabled and s.mailing_address = '' then raise exception 'Add your mailing address first. Every email has to show it.'; end if;
  update email_settings set enabled = s.enabled, from_name = s.from_name, from_local = s.from_local, office_reply_to = s.office_reply_to,
    mailing_address = s.mailing_address, review_url = s.review_url, timezone = s.timezone, campaigns = s.campaigns,
    field_days = s.field_days, test_to = s.test_to, updated_by = auth.uid(), updated_at = now()
  where workspace_id = ws;
end $$;

-- Owner/manager: rewrite one email, or put it back to the default (empty subject and body).
create or replace function public.email_template_save(ws uuid, p_campaign text, p_step text, p_subject text, p_body text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_manager(ws) then raise exception 'Only an owner or manager can change email wording'; end if;
  if email_defaults()->p_campaign->p_step is null then raise exception 'Unknown email'; end if;
  if coalesce(trim(p_subject),'') = '' and coalesce(trim(p_body),'') = '' then
    delete from email_templates where workspace_id = ws and campaign = p_campaign and step = p_step; return;
  end if;
  if coalesce(trim(p_subject),'') = '' or coalesce(trim(p_body),'') = '' then raise exception 'Fill in both the subject and the email'; end if;
  insert into email_templates(workspace_id, campaign, step, subject, body) values (ws, p_campaign, p_step, left(trim(p_subject), 150), left(p_body, 4000))
    on conflict (workspace_id, campaign, step) do update set subject = excluded.subject, body = excluded.body, updated_at = now();
end $$;

-- Rep app: what's next for this lead's emails.
create or replace function public.email_lead(p_lead text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l leads; s email_settings; pl text; nx record; last record;
begin
  select * into l from leads where id = p_lead;
  if l.id is null or not public.is_member(l.workspace_id) or not public.can_see_lead(p_lead) then return null; end if;
  select * into s from email_settings where workspace_id = l.workspace_id;
  if s.workspace_id is null or not s.enabled then return jsonb_build_object('on', false); end if;
  select plan into pl from workspaces where id = l.workspace_id;
  select x.campaign, x.step, x.due into nx from _email_steps(l, pl, s.field_days) x
    where coalesce(s.campaigns->>x.campaign, 'false') = 'true' and x.due > now() - interval '2 days'
      and not exists (select 1 from email_sends e where e.workspace_id = l.workspace_id and e.lead_id = l.id and e.campaign = x.campaign and e.step = x.step)
    order by x.due limit 1;
  select e.campaign, coalesce(e.sent_at, e.created_at) as at, e.status into last from email_sends e
    where e.workspace_id = l.workspace_id and e.lead_id = l.id and e.status <> 'skipped' order by e.created_at desc limit 1;
  return jsonb_build_object('on', true,
    'email', coalesce(l.data->>'email','') <> '',
    'unsub', exists (select 1 from email_unsubs u where u.workspace_id = l.workspace_id and u.email = lower(trim(coalesce(l.data->>'email','')))),
    'next', case when nx.campaign is null then null else jsonb_build_object('campaign', nx.campaign, 'at', greatest(nx.due, now())) end,
    'last', case when last.campaign is null then null else jsonb_build_object('campaign', last.campaign, 'at', last.at, 'status', last.status) end);
end $$;

revoke execute on function public.email_status(uuid), public.email_save(uuid, jsonb), public.email_template_save(uuid, text, text, text, text), public.email_lead(text) from public, anon;
grant execute on function public.email_status(uuid), public.email_save(uuid, jsonb), public.email_template_save(uuid, text, text, text, text), public.email_lead(text) to authenticated;
-- The sender takes a batch so two runs can never send the same email. Anything stuck mid-send for 15 minutes
-- is marked failed, never retried (better a missed email than a double one).
create or replace function public.email_claim(p_limit int) returns setof public.email_sends
language plpgsql security definer set search_path = public as $$
begin
  update email_sends set status = 'failed', error = 'Stopped mid-send' where status = 'sending' and claimed_at < now() - interval '15 minutes';
  return query
    update email_sends e set status = 'sending', claimed_at = now()
    where e.id in (select id from email_sends where status = 'queued' order by created_at limit greatest(p_limit, 1) for update skip locked)
    returning e.*;
end $$;

revoke execute on function public.email_enqueue(), public.email_claim(int), public._email_steps(public.leads, text, jsonb) from public, anon, authenticated;
do $$ begin execute 'grant execute on function public.email_enqueue(), public.email_claim(int) to service_role'; exception when others then null; end $$;

-- Every 15 minutes: queue who's due, then wake the sender if anything is waiting.
-- Daily: keep a year of send history.
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') and exists (select 1 from pg_extension where extname = 'pg_net') then
    perform cron.schedule('ruva-email-queue', '*/15 * * * *', $c$ select public.email_enqueue(); $c$);
    perform cron.schedule('ruva-email-send', '1-59/5 * * * *', $c$
      select net.http_post(
        url := 'https://fixqhaewtyddieoimmrv.supabase.co/functions/v1/email',
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body := jsonb_build_object('action', 'run', 'token', (select cron_token from public.email_cfg where id = 1)))
      where exists (select 1 from public.email_sends where status = 'queued');$c$);
    perform cron.schedule('ruva-email-purge', '55 7 * * *', $c$ delete from public.email_sends where created_at < now() - interval '400 days';$c$);
  end if;
exception when others then null; end $$;

-- Pin the search path on the small helpers (Supabase advisor).
alter function public.email_defaults() set search_path = public;
alter function public._email_stage(public.leads) set search_path = public;
alter function public._email_ms(text) set search_path = public;

-- RUVA migration 17: Completed jobs (Nov 18, 2026). Safe to run more than once.
-- No new tables or columns, and no existing lead data changes. Two function updates:
--
-- 1. leads_guard: only an owner or a manager can mark a job completed or move it back.
--    A completed job is a Sold lead with data.closed set (a time), and data.closedBy (who did it).
--    If anyone else's save would change those two keys, the old values are kept; the rest of
--    the save goes through as before.
--
-- 2. _email_steps: past-customer emails (review +7 days, referral +30, yearly) count from the
--    day the job was marked completed, on both plans. Jobs never marked completed keep the
--    old rule (Full: the install date once built; Field: the Sold date with the Field days).
--    Moving a job back to active puts it back on the old rule, so unsent steps follow.

create or replace function public.leads_guard() returns trigger
language plpgsql set search_path = public as $$
declare k text;
begin
  if current_user not in ('authenticated','anon') then return new; end if;
  -- Reports the owner, a manager or the office attached can only be removed by them, not by the rep
  if not public.can_view_all(old.workspace_id) and exists (
       select 1 from jsonb_array_elements(case when jsonb_typeof(old.data->'docs') = 'array' then old.data->'docs' else '[]'::jsonb end) d
       where coalesce(d->>'staff','') = 'true'
         and not (case when jsonb_typeof(new.data->'docs') = 'array' then new.data->'docs' else '[]'::jsonb end) @> jsonb_build_array(jsonb_build_object('id', d->'id'))) then
    raise exception 'Only the office can remove a report it attached';
  end if;
  -- Job completed: owners and managers only. Anyone else's change to these keys is quietly undone.
  if not public.is_manager(old.workspace_id) then
    foreach k in array array['closed','closedBy'] loop
      if (old.data -> k) is distinct from (new.data -> k) then
        if old.data ? k then new.data := new.data || jsonb_build_object(k, old.data -> k);
        else new.data := new.data - k; end if;
      end if;
    end loop;
  end if;
  if public.is_manager(old.workspace_id) and public.is_manager(new.workspace_id) then return new; end if;
  if new.workspace_id is distinct from old.workspace_id or new.owner_id is distinct from old.owner_id
     or new.created_by is distinct from old.created_by or new.origin is distinct from old.origin
     or new.pool is distinct from old.pool or new.posted_by is distinct from old.posted_by
     or new.posted_at is distinct from old.posted_at or new.claimed_at is distinct from old.claimed_at then
    raise exception 'Only a manager can change who owns a lead or its board status';
  end if;
  if new.protected_until is distinct from old.protected_until and new.protected_until is not null then
    new.protected_until := least(new.protected_until, public._protect_cap(new.workspace_id));
  end if;
  return new;
end $$;

-- Keep closedBy safe from older phone apps too, the same way closed already is.
create or replace function public._keep_office_keys() returns trigger
language plpgsql as $$
declare k text;
begin
  foreach k in array array['tasks','emails','gdocs','jobNo','closed','closedBy','branch','fired'] loop
    if (old.data ? k) and not (new.data ? k) then
      new.data := new.data || jsonb_build_object(k, old.data -> k);
    end if;
  end loop;
  return new;
end $$;

create or replace function public._email_steps(l public.leads, plan text, fdays jsonb)
returns table(campaign text, step text, due timestamptz)
language plpgsql stable set search_path = public as $$
declare st text := _email_stage(l); t text := coalesce(nullif(l.data->>'temp',''),'warm');
  t_at timestamptz := _email_ms(l.data->>'tempAt'); insp timestamptz; a timestamptz; n int;
  done timestamptz := _email_ms(l.data->>'closed');
begin
  if st in ('N','I') then
    if t = 'hot' or l.owner_id is null or l.pool then return; end if;
    if t = 'cold' then
      a := coalesce(t_at, l.updated_at);
      for n in 1..36 loop campaign := 'cold_checkin'; step := 'm' || n || '@' || to_char(a, 'YYYY-MM-DD'); due := a + make_interval(months => n); return next; end loop;
      return;
    end if;
    if st = 'I' then
      select max(_email_ms(k->>'t')) into insp from jsonb_array_elements(coalesce(l.data->'knocks','[]'::jsonb)) k
        where k->>'r' in ('Inspected','Claim Pending');
      a := greatest(coalesce(insp, l.created_at), coalesce(t_at, '-infinity'::timestamptz));
      campaign := 'inspected_no_answer';
      step := 'd3';  due := a + interval '3 days';  return next;
      step := 'd7';  due := a + interval '7 days';  return next;
      step := 'd14'; due := a + interval '14 days'; return next;
    elsif l.status <> 'Inspection Scheduled' then
      a := greatest(l.created_at, coalesce(t_at, '-infinity'::timestamptz));
      campaign := 'not_inspected';
      step := 'd2'; due := a + interval '2 days'; return next;
      step := 'd7'; due := a + interval '7 days'; return next;
    end if;
  elsif st = 'S' then
    if done is not null and done <= now() then
      -- Marked completed (either plan): count from that day.
      a := done;
      campaign := 'pc_review';   step := 'r'; due := a + interval '7 days';  return next;
      campaign := 'pc_referral'; step := 'f'; due := a + interval '30 days'; return next;
    elsif plan = 'field' then
      a := _email_ms(l.data->'sale'->>'soldAt');
      if a is null then return; end if;
      campaign := 'pc_review';   step := 'r'; due := a + make_interval(days => coalesce((fdays->>'review')::int, 30));   return next;
      campaign := 'pc_referral'; step := 'f'; due := a + make_interval(days => coalesce((fdays->>'referral')::int, 60)); return next;
    else
      -- Full: count from the install date once the job is built (Installed, Final check paid or invoiced).
      if not (coalesce(l.data->'sale'->>'stage','') in ('Installed','Final check paid') or coalesce(l.data->'sale'->'inv'->>'sentAt','') <> '') then return; end if;
      a := _email_ms(l.data->'sale'->'install'->>'at');
      if a is null or a > now() then return; end if;
      campaign := 'pc_review';   step := 'r'; due := a + interval '7 days';  return next;
      campaign := 'pc_referral'; step := 'f'; due := a + interval '30 days'; return next;
    end if;
    for n in 1..10 loop campaign := 'pc_yearly'; step := 'y' || n; due := a + make_interval(years => n); return next; end loop;
  end if;
end $$;
alter function public._email_steps(public.leads, text, jsonb) set search_path = public;

-- RUVA migration 18: Storm watch and storm alert emails (Nov 19, 2026). Safe to run more than once.
-- Two new tables, one new column, no existing lead data changes when it runs.
--
-- 1. storm_reports: hail and wind reports the "email" Edge Function pulls from the National Weather Service
--    (Local Storm Reports via the Iowa Environmental Mesonet, the same feed the rep app uses). Only reports
--    within 10 miles of a lead that could get a storm email are kept. Kept one year.
-- 2. storm_hits: a report within the company's miles (3) of a lead, hail >= 1" or wind >= 60 mph.
--    Storm watch leads (No Damage / Not Interested with Storm watch on) → campaign storm_watch.
--    Past customers (completed jobs; Sold on Field) → campaign pc_storm.
--    At most one hit per lead every 30 days (this also limits the Today cards). Only made for a company
--    that has that campaign switched on.
-- 3. email_settings.storm: {"miles":3,"hail":1,"wind":60}.
-- 4. _email_steps: a storm hit becomes a "s<hit id>" step for that lead, due when the hit was made, so
--    email_enqueue's rules (Mon–Sat 9–6, 2-day window, one a day, cap, unsubscribes, paused) apply.
-- 5. email_defaults: wording for storm_watch.s and pc_storm.s. email_save: the two campaigns and storm settings.
-- 6. storm_hits_list / storm_hit_dismiss: the rep app's Today cards.
-- 7. Unsubscribe, bounce or spam report turns Storm watch off on that person's leads, with a note.
-- 8. Cron: ruva-storm-fetch every 30 minutes (only while some company has a storm campaign on),
--    ruva-storm-purge daily.

create table if not exists public.storm_reports (
  id         text primary key,                        -- valid|lat|lng|type, the same id the rep app uses
  kind       text not null check (kind in ('hail','wind')),
  mag        numeric not null default 0,              -- hail: inches; wind: mph
  at         timestamptz not null,
  lat        double precision not null,
  lng        double precision not null,
  place      text not null default '',
  src        text not null default '',
  remark     text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists storm_reports_at on public.storm_reports(at);

create table if not exists public.storm_hits (
  id           bigserial primary key,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  lead_id      text not null,
  report_id    text not null references public.storm_reports(id) on delete cascade,
  campaign     text not null check (campaign in ('storm_watch','pc_storm')),
  kind         text not null,
  mag          numeric not null default 0,
  at           timestamptz not null,                  -- when the storm hit
  miles        numeric not null,
  what         text not null default '',              -- 1.25" hail · 65 mph wind
  place        text not null default '',
  dismissed_at timestamptz,
  dismissed_by uuid,
  created_at   timestamptz not null default now(),
  unique (workspace_id, lead_id, report_id)
);
create index if not exists storm_hits_lead on public.storm_hits(workspace_id, lead_id, at desc);
create index if not exists storm_hits_recent on public.storm_hits(workspace_id, created_at desc);

alter table public.storm_reports enable row level security;
alter table public.storm_hits    enable row level security;
revoke all on public.storm_reports, public.storm_hits from anon, authenticated;
do $$ begin
  execute 'grant all on public.storm_reports, public.storm_hits to service_role';
  execute 'grant usage, select on sequence public.storm_hits_id_seq to service_role';
exception when others then null; end $$;

alter table public.email_settings add column if not exists storm jsonb not null default '{"miles":3,"hail":1,"wind":60}'::jsonb;

-- Miles between two points.
create or replace function public._miles(a_lat double precision, a_lng double precision, b_lat double precision, b_lng double precision)
returns double precision language sql immutable set search_path = public as $$
  select 3958.8 * 2 * asin(least(1, sqrt(power(sin(radians(b_lat - a_lat) / 2), 2)
       + cos(radians(a_lat)) * cos(radians(b_lat)) * power(sin(radians(b_lng - a_lng) / 2), 2)))) $$;

-- The house: the lead's map spot, else where the rep stood when logging it.
create or replace function public._lead_lat(l public.leads) returns double precision language sql immutable set search_path = public as $$
  select coalesce(l.lat, case when l.data->>'pinned_lat' ~ '^-?\d+(\.\d+)?$' then (l.data->>'pinned_lat')::double precision end) $$;
create or replace function public._lead_lng(l public.leads) returns double precision language sql immutable set search_path = public as $$
  select coalesce(l.lng, case when l.data->>'pinned_lng' ~ '^-?\d+(\.\d+)?$' then (l.data->>'pinned_lng')::double precision end) $$;

-- Which storm email a lead could get: storm_watch, pc_storm or nothing.
-- Past customers use the past-customer rule: a completed job; on Field, any Sold lead.
create or replace function public._storm_campaign(l public.leads, plan text) returns text
language sql stable set search_path = public as $$
  select case
    when not coalesce(l.pool, false) and l.status in ('No Damage','Not Interested') and coalesce(l.data->>'stormWatch','') = 'true' then 'storm_watch'
    when l.status = 'Sold' and (plan = 'field' or coalesce(public._email_ms(l.data->>'closed'), 'infinity'::timestamptz) <= now()) then 'pc_storm'
  end $$;

-- Storm settings with limits.
create or replace function public._storm_cfg(s jsonb) returns jsonb language sql immutable set search_path = public as $$
  select jsonb_build_object(
    'miles', least(greatest(coalesce(case when s->>'miles' ~ '^\d+(\.\d+)?$' then (s->>'miles')::numeric end, 3), 1), 10),
    'hail',  least(greatest(coalesce(case when s->>'hail'  ~ '^\d+(\.\d+)?$' then (s->>'hail')::numeric  end, 1), 0.75), 3),
    'wind',  least(greatest(coalesce(case when s->>'wind'  ~ '^\d+(\.\d+)?$' then (s->>'wind')::numeric  end, 60), 50), 100)) $$;

-- Where the server should look: one box per company that has a storm campaign on, around the leads that qualify.
create or replace function public.storm_areas() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('ws', b.ws,
           'w', floor((b.w - b.pad / cos(radians(b.n))) * 2) / 2, 'e', ceil((b.e + b.pad / cos(radians(b.n))) * 2) / 2,
           's', floor((b.s - b.pad) * 2) / 2, 'n', ceil((b.n + b.pad) * 2) / 2)), '[]'::jsonb)
  from (
    select s.workspace_id ws, min(_lead_lng(l)) w, max(_lead_lng(l)) e, min(_lead_lat(l)) s, max(_lead_lat(l)) n,
           ((_storm_cfg(s.storm)->>'miles')::numeric + 1) / 69.0 pad
    from email_settings s join workspaces w on w.id = s.workspace_id join leads l on l.workspace_id = s.workspace_id
    where _lead_lat(l) between -90 and 90 and _lead_lng(l) between -180 and 180
      and coalesce(s.campaigns->>_storm_campaign(l, w.plan), 'false') = 'true'
    group by s.workspace_id, s.storm) b $$;

-- Find hits: reports from the last 3 days near leads that qualify. Earliest storm wins; then 30 days quiet.
create or replace function public.storm_match() returns int
language plpgsql security definer set search_path = public as $$
declare r record; added int := 0;
begin
  for r in
    select distinct on (l.workspace_id, l.id) l.workspace_id ws, l.id lid, c.camp, sr.id rid, sr.kind, sr.mag, sr.at, sr.place, m.mi
    from email_settings s
    join workspaces w on w.id = s.workspace_id
    cross join lateral (select _storm_cfg(s.storm) cfg) g
    join leads l on l.workspace_id = s.workspace_id
    cross join lateral (select _storm_campaign(l, w.plan) camp, _lead_lat(l) la, _lead_lng(l) lo) c
    join storm_reports sr on sr.at > now() - interval '3 days'
      and sr.lat between c.la - 0.2 and c.la + 0.2 and sr.lng between c.lo - 0.3 and c.lo + 0.3
    cross join lateral (select _miles(c.la, c.lo, sr.lat, sr.lng) mi) m
    where c.camp is not null and coalesce(s.campaigns->>c.camp, 'false') = 'true'
      and m.mi <= (g.cfg->>'miles')::numeric
      and ((sr.kind = 'hail' and sr.mag >= (g.cfg->>'hail')::numeric) or (sr.kind = 'wind' and sr.mag >= (g.cfg->>'wind')::numeric))
      and not exists (select 1 from storm_hits h where h.workspace_id = l.workspace_id and h.lead_id = l.id
                        and h.at > sr.at - interval '30 days' and h.at < sr.at + interval '30 days')
    order by l.workspace_id, l.id, sr.at, sr.mag desc
  loop
    insert into storm_hits(workspace_id, lead_id, report_id, campaign, kind, mag, at, miles, what, place)
    values (r.ws, r.lid, r.rid, r.camp, r.kind, r.mag, r.at, round(r.mi::numeric, 1),
            case when r.kind = 'hail' then rtrim(rtrim(round(r.mag, 2)::text, '0'), '.') || '" hail' else round(r.mag)::text || ' mph wind' end,
            r.place)
    on conflict do nothing;
    if found then added := added + 1; end if;
  end loop;
  return added;
end $$;

-- The Edge Function hands over what it fetched. Keeps only hail/wind reports within 10 miles of a lead
-- that could get a storm email, then looks for hits.
create or replace function public.storm_ingest(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare kept int := 0; hits int;
begin
  with x as (
    select left(e->>'id', 120) id, e->>'kind' kind,
           case when e->>'mag' ~ '^\d+(\.\d+)?$' then (e->>'mag')::numeric else 0 end mag,
           case when e->>'at' ~ '^\d{10,14}$' then to_timestamp((e->>'at')::numeric / 1000) else (e->>'at')::timestamptz end at,
           (e->>'lat')::double precision lat, (e->>'lng')::double precision lng,
           left(coalesce(e->>'place',''), 120) place, left(coalesce(e->>'src',''), 80) src, left(coalesce(e->>'remark',''), 400) remark
    from jsonb_array_elements(case when jsonb_typeof(p) = 'array' then p else '[]'::jsonb end) e
    where e->>'kind' in ('hail','wind') and coalesce(e->>'id','') <> ''
      and e->>'lat' ~ '^-?\d+(\.\d+)?$' and e->>'lng' ~ '^-?\d+(\.\d+)?$'),
  ins as (
    insert into storm_reports(id, kind, mag, at, lat, lng, place, src, remark)
    select x.id, x.kind, x.mag, x.at, x.lat, x.lng, x.place, x.src, x.remark from x
    where x.at > now() - interval '3 days' and x.at < now() + interval '1 hour'
      and exists (select 1 from email_settings s join workspaces w on w.id = s.workspace_id join leads l on l.workspace_id = s.workspace_id
                  where coalesce(s.campaigns->>_storm_campaign(l, w.plan), 'false') = 'true'
                    and _lead_lat(l) between x.lat - 0.2 and x.lat + 0.2 and _lead_lng(l) between x.lng - 0.3 and x.lng + 0.3
                    and _miles(_lead_lat(l), _lead_lng(l), x.lat, x.lng) <= 10)
    on conflict (id) do update set mag = greatest(storm_reports.mag, excluded.mag)
    returning 1)
  select count(*) into kept from ins;
  hits := storm_match();
  return jsonb_build_object('reports', kept, 'hits', hits);
end $$;

revoke execute on function public.storm_areas(), public.storm_match(), public.storm_ingest(jsonb) from public, anon, authenticated;
do $$ begin execute 'grant execute on function public.storm_areas(), public.storm_match(), public.storm_ingest(jsonb) to service_role'; exception when others then null; end $$;

-- Rep app Today: storm hits from the last 14 days that nobody dismissed. Reps see their own leads;
-- owners, managers and office see the company's.
create or replace function public.storm_hits_list(ws uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', h.id, 'lead_id', h.lead_id, 'campaign', h.campaign, 'what', h.what,
           'at', h.at, 'miles', h.miles, 'place', h.place,
           'emailed', exists (select 1 from email_sends e where e.workspace_id = h.workspace_id and e.lead_id = h.lead_id
                                and e.campaign = h.campaign and e.step = 's' || h.id and e.status = 'sent'))
         order by h.at desc), '[]'::jsonb)
  from storm_hits h join leads l on l.id = h.lead_id and l.workspace_id = h.workspace_id
  where public.is_member(ws) and h.workspace_id = ws and h.dismissed_at is null and h.created_at > now() - interval '14 days'
    and (public.can_view_all(ws) or l.owner_id = auth.uid()) $$;

create or replace function public.storm_hit_dismiss(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare h storm_hits;
begin
  select * into h from storm_hits where id = p_id;
  if h.id is null or not public.is_member(h.workspace_id) or not public.can_see_lead(h.lead_id) then raise exception 'not allowed'; end if;
  update storm_hits set dismissed_at = now(), dismissed_by = auth.uid() where id = p_id and dismissed_at is null;
end $$;

revoke execute on function public.storm_hits_list(uuid), public.storm_hit_dismiss(bigint) from public, anon;
grant execute on function public.storm_hits_list(uuid), public.storm_hit_dismiss(bigint) to authenticated;

-- Unsubscribed, bounced or marked as spam: Storm watch goes off on that person's leads in that company.
create or replace function public._storm_watch_off() returns trigger
language plpgsql security definer set search_path = public as $$
declare ms bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  why text := case new.reason when 'bounced' then 'email bounced' when 'complained' then 'marked as spam' else 'unsubscribed' end;
begin
  update leads set data = data || jsonb_build_object('stormWatch', false, 'stormWatchAt', ms,
      'log', (case when jsonb_typeof(data->'log') = 'array' then data->'log' else '[]'::jsonb end)
             || jsonb_build_array(jsonb_build_object('t', ms, 'text', 'Storm watch off (' || why || ')')))
  where workspace_id = new.workspace_id and lower(trim(coalesce(data->>'email',''))) = new.email
    and coalesce(data->>'stormWatch','') = 'true';
  return null;
end $$;
revoke execute on function public._storm_watch_off() from public, anon, authenticated;
drop trigger if exists storm_watch_off on public.email_unsubs;
create trigger storm_watch_off after insert or update on public.email_unsubs for each row execute function public._storm_watch_off();

-- Default wording (now with the two storm emails). A company's own edits (email_templates) win.
create or replace function public.email_defaults() returns jsonb language sql immutable as $$
select '{
 "inspected_no_answer": {
  "d3":  {"subject":"Your roof inspection at {address}","body":"Hi {first_name}, it''s {rep_name} with {company}. Thanks again for letting me look at your roof. If you have any questions about what I found or the estimate, just reply here or call me at {rep_phone}."},
  "d7":  {"subject":"Checking in on your roof","body":"Hi {first_name}, I wanted to check back in. Small roof problems usually get bigger, and it''s easier to deal with them now. I''m glad to walk through the estimate with you, no pressure. {rep_phone}"},
  "d14": {"subject":"Last note from me","body":"Hi {first_name}, this is my last follow-up so I don''t crowd your inbox. If you ever want to pick this back up, reply here and I''ll take care of you.\n\n{rep_name}, {company}"}},
 "not_inspected": {
  "d2":  {"subject":"Free roof inspection","body":"Hi {first_name}, it''s {rep_name} with {company}. I can come out and inspect your roof for free. It takes about 30 minutes, and you''ll get photos of everything I see. Reply with a day that works, or call {rep_phone}."},
  "d7":  {"subject":"Still want that roof check?","body":"Hi {first_name}, just following up. If now isn''t a good time, no problem. If you''d like the inspection, reply and I''ll get you on the schedule.\n\n{rep_name}"}},
 "cold_checkin": {
  "m":   {"subject":"Still here if you need us","body":"Hi {first_name}, it''s {rep_name} with {company}. Just checking in. If your roof took a hit or you''re ready to talk about it, reply here or call {rep_phone}."}},
 "storm_watch": {
  "s":   {"subject":"Storm near {address}","body":"Hi {first_name}, it''s {rep_name} with {company}. The weather service reported {storm} near your home on {storm_date}. Damage from a storm like that isn''t always easy to see from the ground. If you''d like, I''ll take a free look. Reply here or call me at {rep_phone}."}},
 "pc_storm": {
  "s":   {"subject":"Storm near your home","body":"Hi {first_name}, the weather service reported {storm} near {address} on {storm_date}. Your roof should hold up well, but if you see shingles in the yard, dents or a leak, reply here and {company} will come check it for free."}},
 "pc_review": {
  "r":   {"subject":"How did we do?","body":"Hi {first_name}, thanks for trusting {company} with your roof. If we did right by you, a quick review helps us a lot: {review_url}\n\nIf anything isn''t right, reply here and we''ll fix it."}},
 "pc_referral": {
  "f":   {"subject":"Know someone who needs a roof?","body":"Hi {first_name}, our best work comes from neighbors telling neighbors. If you know someone with roof damage or an old roof, reply with their name or pass along our number. We''ll treat them the way we treated you."}},
 "pc_yearly": {
  "y":   {"subject":"Your yearly roof check","body":"Hi {first_name}, it''s been a year since we put the roof on at {address}. We''ll come check it over for free. Reply and we''ll set up a time."}}
}'::jsonb $$;

-- Every step a lead could get, now with storm emails first. The rest is migration 17's rule.
create or replace function public._email_steps(l public.leads, plan text, fdays jsonb)
returns table(campaign text, step text, due timestamptz)
language plpgsql stable set search_path = public as $$
declare st text := _email_stage(l); t text := coalesce(nullif(l.data->>'temp',''),'warm');
  t_at timestamptz := _email_ms(l.data->>'tempAt'); insp timestamptz; a timestamptz; n int;
  done timestamptz := _email_ms(l.data->>'closed'); sc text := _storm_campaign(l, plan); h record;
begin
  -- Storm hits (migration 18): one step per hit, due when the hit was made.
  if sc is not null then
    for h in select x.id, x.created_at from storm_hits x where x.workspace_id = l.workspace_id and x.lead_id = l.id
               and x.campaign = sc and x.created_at > now() - interval '30 days' loop
      campaign := sc; step := 's' || h.id; due := h.created_at; return next;
    end loop;
  end if;
  if st in ('N','I') then
    if t = 'hot' or l.owner_id is null or l.pool then return; end if;
    if t = 'cold' then
      a := coalesce(t_at, l.updated_at);
      for n in 1..36 loop campaign := 'cold_checkin'; step := 'm' || n || '@' || to_char(a, 'YYYY-MM-DD'); due := a + make_interval(months => n); return next; end loop;
      return;
    end if;
    if st = 'I' then
      select max(_email_ms(k->>'t')) into insp from jsonb_array_elements(coalesce(l.data->'knocks','[]'::jsonb)) k
        where k->>'r' in ('Inspected','Claim Pending');
      a := greatest(coalesce(insp, l.created_at), coalesce(t_at, '-infinity'::timestamptz));
      campaign := 'inspected_no_answer';
      step := 'd3';  due := a + interval '3 days';  return next;
      step := 'd7';  due := a + interval '7 days';  return next;
      step := 'd14'; due := a + interval '14 days'; return next;
    elsif l.status <> 'Inspection Scheduled' then
      a := greatest(l.created_at, coalesce(t_at, '-infinity'::timestamptz));
      campaign := 'not_inspected';
      step := 'd2'; due := a + interval '2 days'; return next;
      step := 'd7'; due := a + interval '7 days'; return next;
    end if;
  elsif st = 'S' then
    if done is not null and done <= now() then
      -- Marked completed (either plan): count from that day.
      a := done;
      campaign := 'pc_review';   step := 'r'; due := a + interval '7 days';  return next;
      campaign := 'pc_referral'; step := 'f'; due := a + interval '30 days'; return next;
    elsif plan = 'field' then
      a := _email_ms(l.data->'sale'->>'soldAt');
      if a is null then return; end if;
      campaign := 'pc_review';   step := 'r'; due := a + make_interval(days => coalesce((fdays->>'review')::int, 30));   return next;
      campaign := 'pc_referral'; step := 'f'; due := a + make_interval(days => coalesce((fdays->>'referral')::int, 60)); return next;
    else
      -- Full: count from the install date once the job is built (Installed, Final check paid or invoiced).
      if not (coalesce(l.data->'sale'->>'stage','') in ('Installed','Final check paid') or coalesce(l.data->'sale'->'inv'->>'sentAt','') <> '') then return; end if;
      a := _email_ms(l.data->'sale'->'install'->>'at');
      if a is null or a > now() then return; end if;
      campaign := 'pc_review';   step := 'r'; due := a + interval '7 days';  return next;
      campaign := 'pc_referral'; step := 'f'; due := a + interval '30 days'; return next;
    end if;
    for n in 1..10 loop campaign := 'pc_yearly'; step := 'y' || n; due := a + make_interval(years => n); return next; end loop;
  end if;
end $$;
alter function public._email_steps(public.leads, text, jsonb) set search_path = public;
revoke execute on function public._email_steps(public.leads, text, jsonb) from public, anon, authenticated;

-- Owner/manager: save settings (now with storm_watch, pc_storm and storm settings). Turning email on needs a mailing address (the law requires it in every email).
create or replace function public.email_save(ws uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare s email_settings; okc text[] := array['inspected_no_answer','not_inspected','cold_checkin','pc_review','pc_referral','pc_yearly','storm_watch','pc_storm'];
  c jsonb := '{}'::jsonb; k text;
begin
  if not public.is_manager(ws) then raise exception 'Only an owner or manager can change email settings'; end if;
  insert into email_settings(workspace_id) values (ws) on conflict do nothing;
  select * into s from email_settings where workspace_id = ws;
  if p ? 'campaigns' then
    foreach k in array okc loop if p->'campaigns' ? k then c := c || jsonb_build_object(k, (p->'campaigns'->>k)::boolean); end if; end loop;
    s.campaigns := s.campaigns || c;
  end if;
  if p ? 'from_name'       then s.from_name := left(trim(p->>'from_name'), 80); end if;
  if p ? 'from_local'      then
    if coalesce(p->>'from_local','') !~ '^[a-z0-9][a-z0-9._-]{0,40}$' then raise exception 'The from address can use letters, numbers, dots and dashes'; end if;
    s.from_local := p->>'from_local'; end if;
  if p ? 'office_reply_to' then
    if coalesce(p->>'office_reply_to','') <> '' and p->>'office_reply_to' !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Check the reply-to email'; end if;
    s.office_reply_to := lower(trim(p->>'office_reply_to')); end if;
  if p ? 'mailing_address' then s.mailing_address := left(trim(p->>'mailing_address'), 200); end if;
  if p ? 'review_url'      then
    if coalesce(p->>'review_url','') <> '' and p->>'review_url' !~* '^https://' then raise exception 'The review link should start with https://'; end if;
    s.review_url := left(trim(p->>'review_url'), 500); end if;
  if p ? 'timezone'        then
    if not exists (select 1 from pg_timezone_names where name = p->>'timezone') then raise exception 'Unknown time zone'; end if;
    s.timezone := p->>'timezone'; end if;
  if p ? 'field_days'      then s.field_days := jsonb_build_object(
      'review',   least(greatest(coalesce((p->'field_days'->>'review')::int, 30), 1), 365),
      'referral', least(greatest(coalesce((p->'field_days'->>'referral')::int, 60), 1), 365)); end if;
  if p ? 'test_to'         then
    if coalesce(p->>'test_to','') <> '' and p->>'test_to' !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Check the test email'; end if;
    s.test_to := lower(trim(p->>'test_to')); end if;
  if p ? 'storm'           then s.storm := _storm_cfg(s.storm || coalesce(p->'storm', '{}'::jsonb)); end if;
  if p ? 'enabled'         then s.enabled := (p->>'enabled')::boolean; end if;
  if s.enabled and s.mailing_address = '' then raise exception 'Add your mailing address first. Every email has to show it.'; end if;
  update email_settings set enabled = s.enabled, from_name = s.from_name, from_local = s.from_local, office_reply_to = s.office_reply_to,
    mailing_address = s.mailing_address, review_url = s.review_url, timezone = s.timezone, campaigns = s.campaigns,
    field_days = s.field_days, storm = s.storm, test_to = s.test_to, updated_by = auth.uid(), updated_at = now()
  where workspace_id = ws;
end $$;

-- Every 30 minutes, only while some company has a storm campaign on: fetch storm reports and find hits.
-- Daily: keep a year of storm reports (their hits go with them).
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') and exists (select 1 from pg_extension where extname = 'pg_net') then
    perform cron.schedule('ruva-storm-fetch', '7,37 * * * *', $c$
      select net.http_post(
        url := 'https://fixqhaewtyddieoimmrv.supabase.co/functions/v1/email',
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body := jsonb_build_object('action', 'storms', 'token', (select cron_token from public.email_cfg where id = 1)))
      where exists (select 1 from public.email_settings where campaigns->>'storm_watch' = 'true' or campaigns->>'pc_storm' = 'true');$c$);
    perform cron.schedule('ruva-storm-purge', '57 7 * * *', $c$ delete from public.storm_reports where at < now() - interval '1 year';$c$);
  end if;
exception when others then null; end $$;
