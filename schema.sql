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
delete from public.platform_admin_emails where lower(email) <> 'support@ridgemate.app';
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
