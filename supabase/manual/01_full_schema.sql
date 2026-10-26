-- ZFC KOMPLETTES SCHEMA (Neuaufbau)
-- Im Supabase SQL Editor komplett einfügen und ausführen.
-- OHNE Datenverlust aktualisieren: stattdessen 03_upgrade_virtual_cards.sql ausführen.
-- ACHTUNG: Löscht zuerst alle ZFC-Tabellen, Funktionen und Typen im Schema public (inkl. Daten).
-- Benutzer unter Authentication > Users bleiben erhalten, ihre Profile werden am Ende neu angelegt.

drop trigger if exists on_auth_user_created on auth.users;
drop policy if exists "Portal media is publicly readable" on storage.objects;
drop policy if exists "Admins upload portal media" on storage.objects;
drop policy if exists "Admins update portal media" on storage.objects;
drop policy if exists "Admins delete portal media" on storage.objects;
drop table if exists public.card_requests, public.team_cards, public.support_tickets, public.contracts, public.account_entries, public.invoices,
  public.sponsor_orders, public.sponsor_offers, public.site_settings, public.profiles, public.teams cascade;
drop function if exists public.handle_new_auth_user() cascade;
drop function if exists public.protect_profile_role() cascade;
drop function if exists public.validate_sponsor_order() cascade;
drop function if exists public.record_invoice_payment() cascade;
drop function if exists public.prevent_overdrawn_account() cascade;
drop function if exists public.set_updated_at() cascade;
drop function if exists public.current_app_role() cascade;
drop function if exists public.current_team_id() cascade;
drop function if exists public.is_admin() cascade;
drop function if exists public.request_invoice_payment(uuid) cascade;
drop function if exists public.request_invoice_payment(uuid, uuid) cascade;
drop function if exists public.transfer_between_cards(uuid, uuid, bigint) cascade;
drop function if exists public.approve_card_request(uuid, text, bigint, text) cascade;
drop function if exists public.card_available_cents(uuid) cascade;
drop function if exists public.limit_team_cards() cascade;
drop function if exists public.create_basic_card() cascade;
drop function if exists public.respond_to_contract(uuid, boolean) cascade;
drop type if exists public.contract_type, public.contract_status, public.invoice_status, public.support_ticket_status, public.app_role cascade;

-- ===== 20261022000000_zfc_team_management =====
create type public.app_role as enum ('admin', 'team_chief');
create type public.invoice_status as enum ('open', 'payment_requested', 'paid', 'void');
create type public.contract_type as enum ('sponsoring', 'insurance', 'hq', 'vehicle');
create type public.contract_status as enum ('pending', 'signed', 'declined', 'terminated');
create type public.support_ticket_status as enum ('open', 'in_progress', 'resolved');

create table public.teams (
  id text primary key,
  name text not null unique,
  color text not null default '#c7f36b' check (color ~ '^#[0-9a-fA-F]{6}$'),
  logo_path text,
  initial_balance_cents bigint not null default 0 check (initial_balance_cents >= 0),
  created_at timestamptz not null default now()
);

insert into public.teams (id, name, color) values
  ('scuderia-rosso', 'Scuderia Rosso', '#e51e2a'),
  ('apex-motorsport', 'Apex Motorsport', '#d7dfeb'),
  ('veloce-racing', 'Veloce Racing', '#f0b429'),
  ('northstar-gp', 'Northstar GP', '#60a5fa'),
  ('vector-racing', 'Vector Racing', '#c7f36b'),
  ('ironclad-racing', 'Ironclad Racing', '#a8b6c5'),
  ('pulse-motorsport', 'Pulse Motorsport', '#ea668f'),
  ('cobalt-works', 'Cobalt Works', '#5688ff'),
  ('summit-gp', 'Summit GP', '#a1cb88'),
  ('atlas-competition', 'Atlas Competition', '#ef995d')
on conflict (id) do nothing;

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  role public.app_role not null default 'team_chief',
  team_id text references public.teams (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_team_role_check check (
    role = 'team_chief'
    or (role = 'admin' and team_id is null)
  )
);

create table public.site_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now()
);

insert into public.site_settings (key, value) values (
  'homepage',
  '{"title":"Built to race.","claim":"Made to rise.","intro":"Die Zenith Formula Championship ist der Ort, an dem Teams zusammenwachsen und jeder Zentimeter zählt. Entdecke das Grid, die Fahrer und die Geschichten hinter der Zielflagge."}'::jsonb
)
on conflict (key) do nothing;

create table public.sponsor_offers (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  description text not null check (char_length(description) between 1 and 300),
  amount_cents bigint not null check (amount_cents between 1 and 100000000000),
  target_url text check (target_url is null or target_url ~* '^https?://'),
  image_path text,
  published boolean not null default false,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.sponsor_orders (
  id uuid primary key default gen_random_uuid(),
  offer_id uuid not null references public.sponsor_offers (id) on delete restrict,
  team_id text not null references public.teams (id) on delete restrict,
  offer_name text not null,
  amount_cents bigint not null check (amount_cents between 1 and 100000000000),
  contact_name text not null check (char_length(contact_name) between 1 and 80),
  email text not null check (char_length(email) between 3 and 254),
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined', 'completed')),
  admin_notes text not null default '' check (char_length(admin_notes) <= 2000),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.teams (id) on delete restrict,
  order_id uuid references public.sponsor_orders (id) on delete set null,
  invoice_number text not null unique,
  description text not null check (char_length(description) between 1 and 500),
  amount_cents bigint not null check (amount_cents between 1 and 100000000000),
  due_date date not null,
  status public.invoice_status not null default 'open',
  reference text not null default '' check (char_length(reference) <= 100),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.account_entries (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.teams (id) on delete restrict,
  invoice_id uuid references public.invoices (id) on delete restrict,
  direction text not null check (direction in ('credit', 'debit')),
  amount_cents bigint not null check (amount_cents between 1 and 100000000000),
  description text not null check (char_length(description) between 1 and 500),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.contracts (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.teams (id) on delete restrict,
  type public.contract_type not null,
  title text not null check (char_length(title) between 1 and 120),
  terms text not null check (char_length(terms) between 1 and 10000),
  file_path text,
  starts_on date,
  ends_on date not null,
  status public.contract_status not null default 'pending',
  created_by uuid references auth.users (id) on delete set null,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint contracts_date_order_check check (starts_on is null or ends_on >= starts_on)
);

create table public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.teams (id) on delete restrict,
  category text not null check (char_length(category) between 1 and 60),
  subject text not null check (char_length(subject) between 1 and 120),
  details text not null check (char_length(details) between 1 and 5000),
  status public.support_ticket_status not null default 'open',
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  user_name text;
begin
  user_name := coalesce(
    nullif(pg_catalog.left(new.raw_user_meta_data ->> 'display_name', 80), ''),
    nullif(pg_catalog.split_part(coalesce(new.email, ''), '@', 1), ''),
    'Teamchef'
  );

  insert into public.profiles (id, display_name, role, team_id)
  values (new.id, user_name, 'team_chief', null);

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

create or replace function public.protect_profile_role()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and new.role <> 'team_chief' then
    if auth.role() is distinct from 'service_role'
       and session_user not in ('postgres', 'supabase_admin') then
      raise exception 'Only a trusted administrator can assign the admin role';
    end if;
  elsif tg_op = 'UPDATE' and new.role is distinct from old.role then
    if auth.role() is distinct from 'service_role'
       and session_user not in ('postgres', 'supabase_admin') then
      raise exception 'Only a trusted administrator can change account roles';
    end if;
  end if;

  return new;
end;
$$;

create trigger protect_profile_role_on_insert
  before insert on public.profiles
  for each row execute function public.protect_profile_role();
create trigger protect_profile_role_on_update
  before update of role on public.profiles
  for each row execute function public.protect_profile_role();

create or replace function public.validate_sponsor_order()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  selected_offer public.sponsor_offers%rowtype;
begin
  select offer.*
  into selected_offer
  from public.sponsor_offers as offer
  where offer.id = new.offer_id
    and offer.published;

  if not found then
    raise exception 'Sponsor offer is not available';
  end if;

  new.offer_name := selected_offer.name;
  new.amount_cents := selected_offer.amount_cents;
  return new;
end;
$$;

create trigger validate_sponsor_order_before_insert
  before insert on public.sponsor_orders
  for each row execute function public.validate_sponsor_order();

create or replace function public.current_app_role()
returns public.app_role
language sql
stable
security definer
set search_path = ''
as $$
  select profile.role
  from public.profiles as profile
  where profile.id = (select auth.uid())
$$;

create or replace function public.current_team_id()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select profile.team_id
  from public.profiles as profile
  where profile.id = (select auth.uid())
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select profile.role = 'admin'
     from public.profiles as profile
     where profile.id = (select auth.uid())),
    false
  )
$$;

create or replace function public.request_invoice_payment(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select public.current_app_role()) <> 'team_chief' then
    raise exception 'Team-chief access required';
  end if;

  update public.invoices
  set status = 'payment_requested'
  where id = p_invoice_id
    and team_id = (select public.current_team_id())
    and status = 'open';

  if not found then
    raise exception 'Invoice not found or payment request is not allowed';
  end if;
end;
$$;

create or replace function public.respond_to_contract(
  p_contract_id uuid,
  p_accept boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  requester_role public.app_role;
begin
  requester_role := (select public.current_app_role());

  if requester_role is distinct from 'admin'::public.app_role
     and requester_role is distinct from 'team_chief'::public.app_role then
    raise exception 'Admin or team-chief access required';
  end if;

  update public.contracts
  set status = case when p_accept then 'signed'::public.contract_status
                    else 'declined'::public.contract_status
      end,
      accepted_at = case when p_accept then pg_catalog.now() else null end
  where id = p_contract_id
    and status = 'pending'
    and (
      requester_role = 'admin'::public.app_role
      or team_id = (select public.current_team_id())
    );

  if not found then
    raise exception 'Contract not found or response is not allowed';
  end if;
end;
$$;

create or replace function public.record_invoice_payment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status is distinct from new.status and new.status = 'paid' then
    insert into public.account_entries (
      team_id,
      invoice_id,
      direction,
      amount_cents,
      description,
      created_by
    )
    values (
      new.team_id,
      new.id,
      'debit',
      new.amount_cents,
      'Rechnung ' || new.invoice_number,
      auth.uid()
    );
  end if;

  return new;
end;
$$;

create trigger record_paid_invoice
  after update of status on public.invoices
  for each row execute function public.record_invoice_payment();

create or replace function public.prevent_overdrawn_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  opening_balance bigint;
  current_balance bigint;
begin
  if new.direction <> 'debit' then
    return new;
  end if;

  select team.initial_balance_cents
  into opening_balance
  from public.teams as team
  where team.id = new.team_id
  for update;

  select opening_balance
      + coalesce(sum(case when entry.direction = 'credit'
                          then entry.amount_cents
                          else -entry.amount_cents
                     end), 0)
  into current_balance
  from public.account_entries as entry
  where entry.team_id = new.team_id;

  if current_balance < new.amount_cents then
    raise exception 'Insufficient team-account balance';
  end if;

  return new;
end;
$$;

create trigger prevent_overdrawn_account
  before insert on public.account_entries
  for each row execute function public.prevent_overdrawn_account();

create view public.team_account_balances
with (security_invoker = true)
as
  select
    team.id as team_id,
    team.name as team_name,
    team.initial_balance_cents
      + coalesce(sum(case when entry.direction = 'credit'
                          then entry.amount_cents
                          else -entry.amount_cents
                     end), 0) as balance_cents
  from public.teams as team
  left join public.account_entries as entry on entry.team_id = team.id
  group by team.id, team.name, team.initial_balance_cents;

create trigger set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();
create trigger set_updated_at
  before update on public.site_settings
  for each row execute function public.set_updated_at();
create trigger set_updated_at
  before update on public.sponsor_offers
  for each row execute function public.set_updated_at();
create trigger set_updated_at
  before update on public.sponsor_orders
  for each row execute function public.set_updated_at();
create trigger set_updated_at
  before update on public.invoices
  for each row execute function public.set_updated_at();
create trigger set_updated_at
  before update on public.contracts
  for each row execute function public.set_updated_at();
create trigger set_updated_at
  before update on public.support_tickets
  for each row execute function public.set_updated_at();

alter table public.teams enable row level security;
alter table public.profiles enable row level security;
alter table public.site_settings enable row level security;
alter table public.sponsor_offers enable row level security;
alter table public.sponsor_orders enable row level security;
alter table public.invoices enable row level security;
alter table public.account_entries enable row level security;
alter table public.contracts enable row level security;
alter table public.support_tickets enable row level security;

create policy "Teams are publicly readable"
  on public.teams for select to anon, authenticated
  using (true);
create policy "Admins manage teams"
  on public.teams for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create policy "Users read their own profile"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()));
create policy "Admins update profile assignments"
  on public.profiles for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create policy "Public can read homepage settings"
  on public.site_settings for select to anon, authenticated
  using (key = 'homepage' or (select public.is_admin()));
create policy "Admins manage site settings"
  on public.site_settings for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create policy "Published sponsor offers are public"
  on public.sponsor_offers for select to anon, authenticated
  using (published or (select public.is_admin()));
create policy "Admins manage sponsor offers"
  on public.sponsor_offers for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create policy "Admins and owning team read sponsor orders"
  on public.sponsor_orders for select to authenticated
  using (
    (select public.is_admin())
    or (team_id = (select public.current_team_id())
        and (select public.current_app_role()) = 'team_chief')
  );
create policy "Team chiefs submit sponsor orders for their team"
  on public.sponsor_orders for insert to authenticated
  with check (
    (select public.current_app_role()) = 'team_chief'
    and team_id = (select public.current_team_id())
    and created_by = (select auth.uid())
    and status = 'pending'
  );
create policy "Admins manage sponsor orders"
  on public.sponsor_orders for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create policy "Admins and owning team read invoices"
  on public.invoices for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
create policy "Admins create invoices"
  on public.invoices for insert to authenticated
  with check ((select public.is_admin()));
create policy "Admins update invoice status"
  on public.invoices for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create policy "Admins and owning team read account entries"
  on public.account_entries for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
create policy "Admins record account entries"
  on public.account_entries for insert to authenticated
  with check ((select public.is_admin()));

create policy "Admins and owning team read contracts"
  on public.contracts for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
create policy "Admins create contracts"
  on public.contracts for insert to authenticated
  with check ((select public.is_admin()));
create policy "Admins update contracts"
  on public.contracts for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create policy "Admins and owning team read support tickets"
  on public.support_tickets for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
create policy "Team chiefs create tickets for their team"
  on public.support_tickets for insert to authenticated
  with check (
    (select public.current_app_role()) = 'team_chief'
    and team_id = (select public.current_team_id())
    and created_by = (select auth.uid())
    and status = 'open'
  );
create policy "Admins update support tickets"
  on public.support_tickets for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

grant usage on schema public to anon, authenticated;
grant select on public.teams, public.site_settings, public.sponsor_offers to anon, authenticated;
grant select, insert, update, delete on public.teams to authenticated;
grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.site_settings, public.sponsor_offers to authenticated;
grant select, insert, update on public.sponsor_orders to authenticated;
grant select, insert on public.invoices to authenticated;
grant update (status) on public.invoices to authenticated;
grant select, insert on public.account_entries to authenticated;
grant select, insert on public.contracts to authenticated;
grant update (status) on public.contracts to authenticated;
grant select, insert, update on public.support_tickets to authenticated;
grant select on public.team_account_balances to authenticated;

revoke all on function public.current_app_role() from public, anon;
revoke all on function public.current_team_id() from public, anon;
revoke all on function public.is_admin() from public, anon;
revoke all on function public.request_invoice_payment(uuid) from public, anon;
revoke all on function public.respond_to_contract(uuid, boolean) from public, anon;
grant execute on function public.current_app_role() to authenticated;
grant execute on function public.current_team_id() to authenticated;
grant execute on function public.is_admin() to anon, authenticated;
grant execute on function public.request_invoice_payment(uuid) to authenticated;
grant execute on function public.respond_to_contract(uuid, boolean) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'portal-media',
  'portal-media',
  true,
  614400,
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "Portal media is publicly readable"
  on storage.objects for select to anon, authenticated
  using (bucket_id = 'portal-media');
create policy "Admins upload portal media"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'portal-media' and (select public.is_admin()));
create policy "Admins update portal media"
  on storage.objects for update to authenticated
  using (bucket_id = 'portal-media' and (select public.is_admin()))
  with check (bucket_id = 'portal-media' and (select public.is_admin()));
create policy "Admins delete portal media"
  on storage.objects for delete to authenticated
  using (bucket_id = 'portal-media' and (select public.is_admin()));

-- ===== 20261022120000_marketplace_requests_and_roles =====
alter table public.sponsor_offers
  add column if not exists category text not null default 'sponsoring'
  check (category in ('insurance', 'sponsoring', 'hq', 'marketplace')),
  add column if not exists terms text not null default ''
  check (char_length(terms) <= 2000);

alter table public.sponsor_orders
  add column if not exists category text not null default 'sponsoring'
    check (category in ('insurance', 'sponsoring', 'hq', 'marketplace')),
  add column if not exists offer_terms text not null default ''
    check (char_length(offer_terms) <= 2000),
  add column if not exists company text not null default ''
    check (char_length(company) <= 120),
  add column if not exists billing_address text not null default ''
    check (char_length(billing_address) <= 300),
  add column if not exists customer_notes text not null default ''
    check (char_length(customer_notes) <= 1000);

alter table public.invoices
  add column if not exists bill_to_name text not null default '',
  add column if not exists bill_to_email text not null default '',
  add column if not exists bill_to_company text not null default '',
  add column if not exists bill_to_address text not null default '';

create index if not exists sponsor_orders_email_created_at_idx
  on public.sponsor_orders (email, created_at desc);

-- ===== profile_emails_and_role_assignment =====
alter table public.profiles
  add column if not exists email text;

update public.profiles as profile
set email = auth_user.email
from auth.users as auth_user
where auth_user.id = profile.id
  and profile.email is null;

create unique index if not exists profiles_email_lower_unique_idx
  on public.profiles (lower(email))
  where email is not null;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  user_name text;
begin
  user_name := coalesce(
    nullif(pg_catalog.left(new.raw_user_meta_data ->> 'display_name', 80), ''),
    nullif(pg_catalog.split_part(coalesce(new.email, ''), '@', 1), ''),
    'Teamchef'
  );

  insert into public.profiles (id, email, display_name, role, team_id)
  values (new.id, new.email, user_name, 'team_chief', null);

  return new;
end;
$$;

-- ===== 20261023080000_f1_2026_team_grid =====
-- Keep existing team IDs so profiles and account records remain linked.
update public.teams
set
  name = case id
    when 'summit-gp' then 'Alpine'
    when 'atlas-competition' then 'Aston Martin'
    when 'cobalt-works' then 'Audi'
    when 'scuderia-rosso' then 'Ferrari'
    when 'ironclad-racing' then 'Haas'
    when 'veloce-racing' then 'McLaren'
    when 'apex-motorsport' then 'Mercedes'
    when 'pulse-motorsport' then 'Racing Bulls'
    when 'northstar-gp' then 'Red Bull Racing'
    when 'vector-racing' then 'Williams'
  end,
  color = case id
    when 'summit-gp' then '#0093cc'
    when 'atlas-competition' then '#00594f'
    when 'cobalt-works' then '#d1001f'
    when 'scuderia-rosso' then '#dc0000'
    when 'ironclad-racing' then '#9da3a8'
    when 'veloce-racing' then '#ff8700'
    when 'apex-motorsport' then '#00d2be'
    when 'pulse-motorsport' then '#6692ff'
    when 'northstar-gp' then '#1e41ff'
    when 'vector-racing' then '#005aff'
  end
where id in (
  'summit-gp', 'atlas-competition', 'cobalt-works', 'scuderia-rosso',
  'ironclad-racing', 'veloce-racing', 'apex-motorsport',
  'pulse-motorsport', 'northstar-gp', 'vector-racing'
);

insert into public.teams (id, name, color)
values ('cadillac', 'Cadillac', '#c8a95b')
on conflict (id) do update
set name = excluded.name, color = excluded.color;

-- ===== 20261023100000_admin_record_management =====
update public.teams
set name = case id
  when 'summit-gp' then 'BWT Alpine F1 Team'
  when 'atlas-competition' then 'Aston Martin Aramco F1 Team'
  when 'cobalt-works' then 'Audi F1 Team'
  when 'cadillac' then 'Cadillac F1 Team'
  when 'scuderia-rosso' then 'Scuderia Ferrari HP'
  when 'ironclad-racing' then 'TGR Haas F1 Team'
  when 'veloce-racing' then 'McLaren F1 Team'
  when 'apex-motorsport' then 'Mercedes-AMG PETRONAS F1 Team'
  when 'pulse-motorsport' then 'Visa Cash App Racing Bulls F1 Team'
  when 'northstar-gp' then 'Oracle Red Bull Racing'
  when 'vector-racing' then 'Atlassian Williams F1 Team'
end
where id in (
  'summit-gp', 'atlas-competition', 'cobalt-works', 'cadillac',
  'scuderia-rosso', 'ironclad-racing', 'veloce-racing', 'apex-motorsport',
  'pulse-motorsport', 'northstar-gp', 'vector-racing'
);

drop policy if exists "Admins update account entries" on public.account_entries;
create policy "Admins update account entries"
  on public.account_entries for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

grant update (
  team_id, invoice_number, description, amount_cents, due_date, status,
  reference, bill_to_name, bill_to_email, bill_to_company, bill_to_address
) on public.invoices to authenticated;
grant update (team_id, direction, amount_cents, description)
  on public.account_entries to authenticated;
grant update (
  team_id, type, title, terms, starts_on, ends_on, status
) on public.contracts to authenticated;

-- ===== 20261024080000_contract_types_and_offer_cleanup =====
alter type public.contract_type add value if not exists 'driver';
alter type public.contract_type add value if not exists 'team_principal';
alter type public.contract_type add value if not exists 'driver_purchase';

-- Allow offers to be deleted for good; existing requests keep their offer name and price.
alter table public.sponsor_orders alter column offer_id drop not null;
alter table public.sponsor_orders drop constraint if exists sponsor_orders_offer_id_fkey;
alter table public.sponsor_orders
  add constraint sponsor_orders_offer_id_fkey
  foreign key (offer_id) references public.sponsor_offers (id) on delete set null;

-- ===== virtual_cards =====
-- Jedes Team hat automatisch eine Basiskarte (Startkapital + Auszahlungen landen dort).
-- Bis zu zwei weitere Karten werden per Kredit-Antrag angefragt und von einem Admin erstellt.
-- Der Kreditrahmen (Minus-Limit) wird nur bei der Erstellung festgelegt und ist danach nicht mehr änderbar.
create table public.team_cards (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.teams (id) on delete restrict,
  kind text not null default 'extra' check (kind in ('basic', 'extra')),
  label text not null default '' check (char_length(label) <= 40),
  design text not null default 'carbon' check (design in ('basic', 'sunset', 'aurora', 'carbon', 'gold', 'ocean')),
  credit_limit_cents bigint not null default 0 check (credit_limit_cents between 0 and 100000000000),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);
create unique index team_cards_one_basic_idx on public.team_cards (team_id) where kind = 'basic';
create index team_cards_team_idx on public.team_cards (team_id);

create table public.card_requests (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.teams (id) on delete restrict,
  design text not null default 'sunset' check (design in ('basic', 'sunset', 'aurora', 'carbon', 'gold', 'ocean')),
  requested_limit_cents bigint not null default 0 check (requested_limit_cents between 0 and 100000000000),
  reason text not null default '' check (char_length(reason) <= 500),
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined')),
  card_id uuid references public.team_cards (id) on delete set null,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index card_requests_one_pending_idx on public.card_requests (team_id) where status = 'pending';

create or replace function public.limit_team_cards()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select count(*) from public.team_cards as card where card.team_id = new.team_id) >= 3 then
    raise exception 'Ein Team kann höchstens drei Karten besitzen';
  end if;
  return new;
end;
$$;
create trigger limit_team_cards
  before insert on public.team_cards
  for each row execute function public.limit_team_cards();

create or replace function public.create_basic_card()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.team_cards (team_id, kind, label, design)
  values (new.id, 'basic', 'Basiskarte', 'basic');
  return new;
end;
$$;
create trigger create_basic_card
  after insert on public.teams
  for each row execute function public.create_basic_card();

insert into public.team_cards (team_id, kind, label, design)
select team.id, 'basic', 'Basiskarte', 'basic' from public.teams as team;

create trigger set_updated_at
  before update on public.card_requests
  for each row execute function public.set_updated_at();

alter table public.account_entries
  add column card_id uuid references public.team_cards (id) on delete restrict,
  add column transfer_id uuid;
alter table public.invoices
  add column card_id uuid references public.team_cards (id) on delete set null;

update public.account_entries as entry
set card_id = (select card.id from public.team_cards as card where card.team_id = entry.team_id and card.kind = 'basic');
alter table public.account_entries alter column card_id set not null;
create index account_entries_card_idx on public.account_entries (card_id);

-- Verfügbar = Kartensaldo + Kreditrahmen - Beträge aus Zahlungen, die auf Freigabe warten.
create or replace function public.card_available_cents(p_card_id uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select (case when card.kind = 'basic' then team.initial_balance_cents else 0 end)
    + coalesce((select sum(case when entry.direction = 'credit' then entry.amount_cents else -entry.amount_cents end)
                from public.account_entries as entry where entry.card_id = card.id), 0)
    + card.credit_limit_cents
    - coalesce((select sum(invoice.amount_cents) from public.invoices as invoice
                where invoice.card_id = card.id and invoice.status = 'payment_requested'), 0)
  from public.team_cards as card
  join public.teams as team on team.id = card.team_id
  where card.id = p_card_id
$$;

-- Ohne Kartenangabe wird immer die Basiskarte gebucht; jede Belastung darf den Kreditrahmen der Karte nicht überschreiten.
create or replace function public.prevent_overdrawn_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  card public.team_cards;
  opening_balance bigint;
  current_balance bigint;
begin
  if new.card_id is null then
    select * into card from public.team_cards as c where c.team_id = new.team_id and c.kind = 'basic' for update;
  else
    select * into card from public.team_cards as c where c.id = new.card_id for update;
  end if;
  if card.id is null or card.team_id <> new.team_id then
    raise exception 'Karte nicht gefunden oder gehört nicht zu diesem Team';
  end if;
  new.card_id := card.id;

  if new.direction <> 'debit' then
    return new;
  end if;

  select case when card.kind = 'basic' then team.initial_balance_cents else 0 end
  into opening_balance
  from public.teams as team
  where team.id = new.team_id;

  select opening_balance
      + coalesce(sum(case when entry.direction = 'credit'
                          then entry.amount_cents
                          else -entry.amount_cents
                     end), 0)
  into current_balance
  from public.account_entries as entry
  where entry.card_id = card.id;

  if current_balance + card.credit_limit_cents < new.amount_cents then
    raise exception 'Insufficient card balance';
  end if;

  return new;
end;
$$;

create or replace function public.record_invoice_payment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status is distinct from new.status and new.status = 'paid' then
    insert into public.account_entries (team_id, card_id, invoice_id, direction, amount_cents, description, created_by)
    values (new.team_id, new.card_id, new.id, 'debit', new.amount_cents, 'Rechnung ' || new.invoice_number, auth.uid());
  end if;
  return new;
end;
$$;

drop function if exists public.request_invoice_payment(uuid);
create or replace function public.request_invoice_payment(p_invoice_id uuid, p_card_id uuid default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  chosen_card uuid;
  invoice_amount bigint;
begin
  if (select public.current_app_role()) <> 'team_chief' then
    raise exception 'Team-chief access required';
  end if;

  select card.id into chosen_card
  from public.team_cards as card
  where card.team_id = (select public.current_team_id())
    and ((p_card_id is null and card.kind = 'basic') or card.id = p_card_id);
  if chosen_card is null then
    raise exception 'Card not found';
  end if;

  select invoice.amount_cents into invoice_amount
  from public.invoices as invoice
  where invoice.id = p_invoice_id
    and invoice.team_id = (select public.current_team_id())
    and invoice.status = 'open';
  if invoice_amount is null then
    raise exception 'Invoice not found or payment request is not allowed';
  end if;
  if (select public.card_available_cents(chosen_card)) < invoice_amount then
    raise exception 'Insufficient card balance';
  end if;

  update public.invoices
  set status = 'payment_requested', card_id = chosen_card
  where id = p_invoice_id;
end;
$$;

-- Der Teamchef verschiebt Guthaben beliebig oft zwischen den Karten seines Teams.
create or replace function public.transfer_between_cards(p_from_card uuid, p_to_card uuid, p_amount_cents bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  from_card public.team_cards;
  to_card public.team_cards;
  transfer uuid := gen_random_uuid();
begin
  if (select public.current_app_role()) <> 'team_chief' then
    raise exception 'Team-chief access required';
  end if;
  if p_from_card = p_to_card or p_amount_cents is null or p_amount_cents < 1 then
    raise exception 'Ungültige Umbuchung';
  end if;

  select * into from_card from public.team_cards as c where c.id = p_from_card and c.team_id = (select public.current_team_id());
  select * into to_card from public.team_cards as c where c.id = p_to_card and c.team_id = (select public.current_team_id());
  if from_card.id is null or to_card.id is null then
    raise exception 'Karte nicht gefunden';
  end if;
  if (select public.card_available_cents(from_card.id)) < p_amount_cents then
    raise exception 'Insufficient card balance';
  end if;

  insert into public.account_entries (team_id, card_id, direction, amount_cents, description, created_by, transfer_id)
  values (from_card.team_id, from_card.id, 'debit', p_amount_cents, 'Umbuchung auf ' || to_card.label, auth.uid(), transfer),
         (to_card.team_id, to_card.id, 'credit', p_amount_cents, 'Umbuchung von ' || from_card.label, auth.uid(), transfer);
end;
$$;

-- Ein Admin genehmigt einen Kredit-Antrag und legt dabei Design und (unveränderlichen) Kreditrahmen fest.
create or replace function public.approve_card_request(
  p_request_id uuid, p_design text, p_limit_cents bigint, p_label text default ''
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  request public.card_requests;
  new_card uuid;
begin
  if not (select public.is_admin()) then
    raise exception 'Admin access required';
  end if;
  select * into request from public.card_requests as r where r.id = p_request_id and r.status = 'pending' for update;
  if request.id is null then
    raise exception 'Antrag nicht gefunden oder bereits bearbeitet';
  end if;

  insert into public.team_cards (team_id, kind, label, design, credit_limit_cents, created_by)
  values (request.team_id, 'extra', coalesce(nullif(pg_catalog.left(p_label, 40), ''), 'Kreditkarte'), p_design, p_limit_cents, auth.uid())
  returning id into new_card;

  update public.card_requests set status = 'approved', card_id = new_card where id = request.id;
  return new_card;
end;
$$;

alter table public.team_cards enable row level security;
alter table public.card_requests enable row level security;

create policy "Admins and owning team read cards"
  on public.team_cards for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
create policy "Admins create extra cards"
  on public.team_cards for insert to authenticated
  with check ((select public.is_admin()) and kind = 'extra');

create policy "Admins and owning team read card requests"
  on public.card_requests for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
create policy "Team chiefs request cards for their team"
  on public.card_requests for insert to authenticated
  with check (
    (select public.current_app_role()) = 'team_chief'
    and team_id = (select public.current_team_id())
    and created_by = (select auth.uid())
    and status = 'pending'
  );
create policy "Admins update card requests"
  on public.card_requests for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- Kein UPDATE auf team_cards: Kreditrahmen und Design bleiben nach der Erstellung fix.
grant select, insert on public.team_cards to authenticated;
grant select, insert on public.card_requests to authenticated;
grant update (status) on public.card_requests to authenticated;

revoke all on function public.card_available_cents(uuid) from public, anon, authenticated;
revoke all on function public.request_invoice_payment(uuid, uuid) from public, anon;
revoke all on function public.transfer_between_cards(uuid, uuid, bigint) from public, anon;
revoke all on function public.approve_card_request(uuid, text, bigint, text) from public, anon;
grant execute on function public.request_invoice_payment(uuid, uuid) to authenticated;
grant execute on function public.transfer_between_cards(uuid, uuid, bigint) to authenticated;
grant execute on function public.approve_card_request(uuid, text, bigint, text) to authenticated;

-- ===== Profile für bereits vorhandene Auth-Benutzer neu anlegen =====
insert into public.profiles (id, email, display_name, role, team_id)
select u.id, u.email, coalesce(nullif(split_part(coalesce(u.email, ''), '@', 1), ''), 'Teamchef'), 'team_chief', null
from auth.users u
on conflict (id) do nothing;

-- ===== Realtime =====
do $$
declare t text;
begin
  foreach t in array array['teams','account_entries','sponsor_offers','sponsor_orders','invoices','contracts','support_tickets','profiles','site_settings','team_cards','card_requests']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
    execute format('alter table public.%I replica identity full', t);
  end loop;
end $$;

-- Kontrolle: muss alle 11 Tabellen anzeigen
select tablename from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' order by 1;
