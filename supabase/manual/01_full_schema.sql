-- ZFC KOMPLETTES SCHEMA (Neuaufbau)
-- Alle bisherigen Migrationen sind hier zusammengeführt; der Ordner supabase/migrations entfällt.
-- Im Supabase SQL Editor komplett einfügen und ausführen.
-- ACHTUNG: Löscht zuerst alle ZFC-Tabellen, Funktionen und Typen im Schema public (inkl. Daten).
-- Benutzer unter Authentication > Users bleiben erhalten, ihre Profile werden am Ende neu angelegt.
-- Danach 02_make_admin.sql ausführen, um das eigene Konto zum Admin zu machen.

-- ============================================================
-- 0. Reset: alle bekannten ZFC-Objekte entfernen
-- ============================================================

drop trigger if exists on_auth_user_created on auth.users;
drop policy if exists "Portal media is publicly readable" on storage.objects;
drop policy if exists "Admins upload portal media" on storage.objects;
drop policy if exists "Admins update portal media" on storage.objects;
drop policy if exists "Admins delete portal media" on storage.objects;
drop view if exists public.team_account_balances;
drop table if exists public.team_appointments, public.scheduled_invoices, public.drivers, public.konzern_teams,
  public.card_requests, public.team_cards, public.support_tickets, public.contracts, public.account_entries,
  public.invoices, public.sponsor_orders, public.sponsor_offers, public.site_settings, public.profiles, public.teams cascade;
-- Typen zuerst: ihr CASCADE entfernt auch Funktionen, die sie in der Signatur verwenden
-- (z. B. current_app_role, admin_set_profile_role, admin_set_konzern, konzern_switch_team).
drop type if exists public.contract_type, public.contract_status, public.invoice_status, public.support_ticket_status, public.app_role cascade;
drop function if exists public.handle_new_auth_user() cascade;
drop function if exists public.protect_profile_role() cascade;
drop function if exists public.validate_sponsor_order() cascade;
drop function if exists public.record_invoice_payment() cascade;
drop function if exists public.prevent_overdrawn_account() cascade;
drop function if exists public.set_updated_at() cascade;
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
drop function if exists public.admin_reset_data() cascade;
drop function if exists public.materialize_scheduled_invoices() cascade;

-- ============================================================
-- 1. Typen
-- ============================================================

create type public.app_role as enum ('admin', 'team_chief', 'konzern');
create type public.invoice_status as enum ('open', 'payment_requested', 'paid', 'void');
create type public.contract_type as enum ('sponsoring', 'insurance', 'hq', 'vehicle', 'driver', 'team_principal', 'driver_purchase');
create type public.contract_status as enum ('pending', 'in_review', 'signed', 'declined', 'terminated');
create type public.support_ticket_status as enum ('open', 'in_progress', 'resolved');

-- ============================================================
-- 2. Tabellen
-- ============================================================

create table public.teams (
  id text primary key,
  name text not null unique,
  color text not null default '#c7f36b' check (color ~ '^#[0-9a-fA-F]{6}$'),
  logo_path text,
  initial_balance_cents bigint not null default 0 check (initial_balance_cents >= 0),
  created_at timestamptz not null default now()
);

-- Doppelrolle erlaubt: ein Admin mit team_id handelt als Teamchef dieses Teams.
-- Ein Konzern (Rolle 'konzern') verwaltet genau zwei Teams; team_id ist das aktuell aktive Team.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  role public.app_role not null default 'team_chief',
  team_id text references public.teams (id) on delete restrict,
  email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index profiles_email_lower_unique_idx
  on public.profiles (lower(email))
  where email is not null;

create table public.konzern_teams (
  profile_id uuid not null references public.profiles (id) on delete cascade,
  team_id text not null references public.teams (id) on delete restrict,
  primary key (profile_id, team_id)
);

create table public.site_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now()
);

create table public.sponsor_offers (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  description text not null check (char_length(description) between 1 and 300),
  amount_cents bigint not null check (amount_cents between 1 and 100000000000),
  category text not null default 'sponsoring' check (category in ('insurance', 'sponsoring', 'hq', 'marketplace')),
  terms text not null default '' check (char_length(terms) <= 2000),
  target_url text check (target_url is null or target_url ~* '^https?://'),
  image_path text,
  logo_path text,
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  published boolean not null default false,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- offer_id darf leer werden: gelöschte Angebote lassen bestehende Anfragen mit Name und Preis bestehen.
create table public.sponsor_orders (
  id uuid primary key default gen_random_uuid(),
  offer_id uuid references public.sponsor_offers (id) on delete set null,
  team_id text not null references public.teams (id) on delete restrict,
  offer_name text not null,
  amount_cents bigint not null check (amount_cents between 1 and 100000000000),
  category text not null default 'sponsoring' check (category in ('insurance', 'sponsoring', 'hq', 'marketplace')),
  offer_terms text not null default '' check (char_length(offer_terms) <= 2000),
  contact_name text not null check (char_length(contact_name) between 1 and 80),
  email text not null check (char_length(email) between 3 and 254),
  company text not null default '' check (char_length(company) <= 120),
  billing_address text not null default '' check (char_length(billing_address) <= 300),
  customer_notes text not null default '' check (char_length(customer_notes) <= 1000),
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined', 'completed')),
  admin_notes text not null default '' check (char_length(admin_notes) <= 2000),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index sponsor_orders_email_created_at_idx
  on public.sponsor_orders (email, created_at desc);

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

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.teams (id) on delete restrict,
  order_id uuid references public.sponsor_orders (id) on delete set null,
  card_id uuid references public.team_cards (id) on delete set null,
  invoice_number text not null unique,
  description text not null check (char_length(description) between 1 and 500),
  items jsonb not null default '[]'::jsonb,
  amount_cents bigint not null check (amount_cents between 1 and 100000000000),
  due_date date not null,
  status public.invoice_status not null default 'open',
  reference text not null default '' check (char_length(reference) <= 100),
  bill_to_name text not null default '',
  bill_to_email text not null default '',
  bill_to_company text not null default '',
  bill_to_address text not null default '',
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Buchungen ohne Kartenangabe laufen über die Basiskarte (Trigger prevent_overdrawn_account).
create table public.account_entries (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.teams (id) on delete restrict,
  card_id uuid not null references public.team_cards (id) on delete restrict,
  invoice_id uuid references public.invoices (id) on delete restrict,
  transfer_id uuid,
  direction text not null check (direction in ('credit', 'debit')),
  amount_cents bigint not null check (amount_cents between 1 and 100000000000),
  description text not null check (char_length(description) between 1 and 500),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);
create index account_entries_card_idx on public.account_entries (card_id);

create table public.drivers (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.teams (id) on delete restrict,
  name text not null check (char_length(name) between 1 and 80),
  number integer check (number between 0 and 999),
  nationality text not null default '' check (char_length(nationality) <= 80),
  birth_date date,
  license text not null default '' check (char_length(license) <= 80),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index drivers_team_id_idx on public.drivers (team_id);

create table public.contracts (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.teams (id) on delete restrict,
  driver_id uuid references public.drivers (id) on delete set null,
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

-- Terminierte Rechnungen (Dauerauftrag): Teams stellen den Antrag, Admins schalten auf.
-- Der Gesamtbetrag wird auf die Anzahl Raten aufgeteilt (Standard 16 Rennen,
-- 1 Rate = Einmalzahlung). Die Raten erscheinen gleichmässig verteilt zwischen
-- Start- und Enddatum im E-Banking; die letzte Rate kommt am Enddatum.
create table public.scheduled_invoices (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.teams (id) on delete restrict,
  description text not null check (char_length(description) between 1 and 500),
  total_cents bigint not null check (total_cents between 1 and 100000000000),
  amount_cents bigint not null check (amount_cents between 1 and 100000000000),
  start_date date not null,
  end_date date not null,
  installments_total integer not null default 16 check (installments_total between 1 and 52),
  installments_sent integer not null default 0 check (installments_sent >= 0),
  next_send_date date,
  status text not null default 'pending' check (status in ('pending', 'active', 'sent', 'cancelled')),
  invoice_id uuid references public.invoices (id) on delete set null,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scheduled_invoices_date_order_check check (end_date >= start_date),
  constraint scheduled_invoices_installments_check check (installments_total = 1 or end_date > start_date)
);
create index scheduled_invoices_team_id_idx on public.scheduled_invoices (team_id);
create index scheduled_invoices_due_idx on public.scheduled_invoices (status, next_send_date);

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

-- Pflichttermine der Teams (Trainings, Testings, Rennen, Meetings, Sonstiges).
-- Werden von der Verwaltung gesetzt und erscheinen im Team-E-Banking.
create table public.team_appointments (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.teams (id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  category text not null default 'sonstiges' check (category in ('training', 'testing', 'rennen', 'meeting', 'sonstiges')),
  starts_at timestamptz not null,
  location text not null default '' check (char_length(location) <= 120),
  notes text not null default '' check (char_length(notes) <= 1000),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index team_appointments_team_id_idx on public.team_appointments (team_id, starts_at);

-- ============================================================
-- 3. Funktionen
-- ============================================================

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

  insert into public.profiles (id, email, display_name, role, team_id)
  values (new.id, new.email, user_name, 'team_chief', null);

  return new;
end;
$$;

create or replace function public.protect_profile_role()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (tg_op = 'INSERT' and new.role <> 'team_chief')
     or (tg_op = 'UPDATE' and new.role is distinct from old.role) then
    if auth.role() is distinct from 'service_role'
       and session_user not in ('postgres', 'supabase_admin')
       and not (select public.is_admin()) then
      raise exception 'Only a trusted administrator can change account roles';
    end if;
  end if;
  return new;
end;
$$;

-- Serverseitige Preis- und Angebotsprüfung für Anfragen.
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

-- Jeder mit zugewiesenem Team (Teamchef, Konzern, Admin in Doppelrolle) handelt für dieses Team.
create or replace function public.current_app_role()
returns public.app_role
language sql
stable
security definer
set search_path = ''
as $$
  select case when profile.team_id is not null then 'team_chief'::public.app_role else profile.role end
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

-- Vertragsantwort (Annahme/Ablehnung) durch Admin oder das betroffene Team.
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

  if requester_role is null then
    raise exception 'Admin or team access required';
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

-- Erzeugt fällige Raten eines Dauerauftrags im Teamkonto (wird beim Laden aufgerufen).
-- Ratenbetrag = Gesamtbetrag / Anzahl Raten; die letzte Rate erhält den Rundungsrest,
-- damit die Summe exakt dem Gesamtbetrag entspricht. Die Raten werden gleichmässig
-- zwischen Start- und Enddatum verteilt (letzte Rate am Enddatum), Fälligkeit je +7 Tage.
create or replace function public.materialize_scheduled_invoices()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  item public.scheduled_invoices%rowtype;
  new_number text;
  created_count integer := 0;
  rate_amount bigint;
  rate_description text;
  rate_date date;
  next_date date;
  rate_index integer;
  span_days integer;
begin
  for item in
    select si.*
    from public.scheduled_invoices as si
    where si.status = 'active'
      and coalesce(si.next_send_date, si.start_date) <= current_date
      and si.installments_sent < si.installments_total
  loop
    rate_index := item.installments_sent + 1;
    rate_amount := pg_catalog.floor(item.total_cents / item.installments_total);
    if rate_index = item.installments_total then
      rate_amount := item.total_cents - rate_amount * (item.installments_total - 1);
    end if;
    rate_description := case
      when item.installments_total > 1
        then item.description || ' (Rate ' || rate_index || '/' || item.installments_total || ')'
      else item.description
    end;
    rate_date := coalesce(item.next_send_date, item.start_date);

    -- Nächster Termin: gleichmässige Verteilung zwischen Start- und Enddatum.
    if rate_index >= item.installments_total or item.installments_total <= 1 then
      next_date := null;
    else
      span_days := item.end_date - item.start_date;
      next_date := item.start_date + pg_catalog.round(span_days::numeric * rate_index / (item.installments_total - 1))::integer;
      -- Bei migrierten/alt liegenden Reihen nie hinter das Enddatum und nie rückwärts.
      next_date := least(next_date, item.end_date);
      next_date := greatest(next_date, rate_date);
    end if;

    loop
      new_number := pg_catalog.lpad(pg_catalog.floor(pg_catalog.random() * 9000000000 + 1000000000)::bigint::text, 10, '0');
      exit when not exists (select 1 from public.invoices as inv where inv.invoice_number = new_number);
    end loop;

    insert into public.invoices (
      team_id, invoice_number, description, amount_cents, due_date, reference, created_by
    ) values (
      item.team_id, new_number, rate_description, rate_amount, rate_date + 7,
      'AUTO-' || pg_catalog.substr(item.id::text, 1, 8), item.created_by
    )
    returning id into item.invoice_id;

    update public.scheduled_invoices
    set installments_sent = rate_index,
        invoice_id = item.invoice_id,
        next_send_date = next_date,
        status = case when rate_index >= item.installments_total then 'sent' else 'active' end,
        updated_at = pg_catalog.now()
    where id = item.id;

    created_count := created_count + 1;
  end loop;
  return created_count;
end;
$$;

-- Setzt alle Geldbewegungen, Rechnungen, Anfragen, Verträge, Tickets, Kredit-Anträge,
-- terminierten Rechnungen und Termine zurück; Teamkonten stehen danach auf null.
-- Karten und Fahrer bleiben erhalten (Kreditrahmen unverändert).
create or replace function public.admin_reset_data()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (select public.is_admin()) then
    raise exception 'Nur Admins können Daten zurücksetzen.';
  end if;

  delete from public.account_entries where true;
  delete from public.scheduled_invoices where true;
  delete from public.invoices where true;
  delete from public.sponsor_orders where true;
  delete from public.contracts where true;
  delete from public.support_tickets where true;
  delete from public.card_requests where true;
  delete from public.team_appointments where true;
  update public.teams set initial_balance_cents = 0 where true;
end;
$$;

-- Rollen im Webportal ändern (Admin, auch mit eigenem Team = Doppelrolle).
create or replace function public.admin_set_profile_role(
  p_profile_id uuid,
  p_role public.app_role,
  p_team_id text
)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  result public.profiles;
begin
  if not (select public.is_admin()) then
    raise exception 'Nur Admins können Rollen ändern.';
  end if;
  if p_role = 'konzern' then
    raise exception 'Für die Rolle Konzern bitte zwei Teams auswählen.';
  end if;
  if p_team_id is not null and not exists (select 1 from public.teams where id = p_team_id) then
    raise exception 'Das ausgewählte Team wurde nicht gefunden.';
  end if;
  if p_role = 'team_chief' and p_team_id is null then
    raise exception 'Ein Teamchef braucht ein Team.';
  end if;

  update public.profiles
  set role = p_role, team_id = p_team_id
  where id = p_profile_id
  returning * into result;

  if not found then
    raise exception 'Profil nicht gefunden.';
  end if;

  delete from public.konzern_teams where profile_id = p_profile_id;
  return result;
end;
$$;

-- Admin weist die Konzern-Rolle zusammen mit den zwei Teams zu.
create or replace function public.admin_set_konzern(
  p_profile_id uuid,
  p_team_a text,
  p_team_b text
)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  result public.profiles;
begin
  if not (select public.is_admin()) then
    raise exception 'Nur Admins können Rollen ändern.';
  end if;
  if p_team_a is null or p_team_b is null or p_team_a = p_team_b then
    raise exception 'Ein Konzern braucht genau zwei verschiedene Teams.';
  end if;
  if (select count(*) from public.teams where id in (p_team_a, p_team_b)) <> 2 then
    raise exception 'Eines der ausgewählten Teams wurde nicht gefunden.';
  end if;

  update public.profiles
  set role = 'konzern'::public.app_role,
      team_id = case when profiles.team_id in (p_team_a, p_team_b) then profiles.team_id else p_team_a end
  where profiles.id = p_profile_id
  returning * into result;

  if not found then
    raise exception 'Profil nicht gefunden.';
  end if;

  delete from public.konzern_teams where profile_id = p_profile_id;
  insert into public.konzern_teams (profile_id, team_id)
  values (p_profile_id, p_team_a), (p_profile_id, p_team_b);

  return result;
end;
$$;

-- Konzern wechselt das aktive E-Banking zwischen seinen zwei Teams.
create or replace function public.konzern_switch_team(p_team_id text)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  result public.profiles;
begin
  if not exists (
    select 1
    from public.profiles as profile
    join public.konzern_teams as kt on kt.profile_id = profile.id
    where profile.id = (select auth.uid())
      and profile.role = 'konzern'
      and kt.team_id = p_team_id
  ) then
    raise exception 'Dieses Team gehört nicht zu deinem Konzern.';
  end if;

  update public.profiles
  set team_id = p_team_id
  where id = (select auth.uid())
  returning * into result;
  return result;
end;
$$;

-- ============================================================
-- 4. Trigger
-- ============================================================

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

create trigger protect_profile_role_on_insert
  before insert on public.profiles
  for each row execute function public.protect_profile_role();
create trigger protect_profile_role_on_update
  before update of role on public.profiles
  for each row execute function public.protect_profile_role();

create trigger validate_sponsor_order_before_insert
  before insert on public.sponsor_orders
  for each row execute function public.validate_sponsor_order();

create trigger record_paid_invoice
  after update of status on public.invoices
  for each row execute function public.record_invoice_payment();

create trigger prevent_overdrawn_account
  before insert on public.account_entries
  for each row execute function public.prevent_overdrawn_account();

create trigger limit_team_cards
  before insert on public.team_cards
  for each row execute function public.limit_team_cards();

create trigger create_basic_card
  after insert on public.teams
  for each row execute function public.create_basic_card();

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
create trigger set_updated_at
  before update on public.card_requests
  for each row execute function public.set_updated_at();
create trigger set_updated_at
  before update on public.drivers
  for each row execute function public.set_updated_at();
create trigger set_updated_at
  before update on public.scheduled_invoices
  for each row execute function public.set_updated_at();
create trigger set_updated_at
  before update on public.team_appointments
  for each row execute function public.set_updated_at();

-- ============================================================
-- 5. Startdaten (Teams der F1-Saison 2026, Startseite)
--    Basiskarten werden dabei automatisch pro Team angelegt.
-- ============================================================

insert into public.teams (id, name, color) values
  ('summit-gp', 'BWT Alpine F1 Team', '#0093cc'),
  ('atlas-competition', 'Aston Martin Aramco F1 Team', '#00594f'),
  ('cobalt-works', 'Audi F1 Team', '#d1001f'),
  ('cadillac', 'Cadillac F1 Team', '#c8a95b'),
  ('scuderia-rosso', 'Scuderia Ferrari HP', '#dc0000'),
  ('ironclad-racing', 'TGR Haas F1 Team', '#9da3a8'),
  ('veloce-racing', 'McLaren F1 Team', '#ff8700'),
  ('apex-motorsport', 'Mercedes-AMG PETRONAS F1 Team', '#00d2be'),
  ('pulse-motorsport', 'Visa Cash App Racing Bulls F1 Team', '#6692ff'),
  ('northstar-gp', 'Oracle Red Bull Racing', '#1e41ff'),
  ('vector-racing', 'Atlassian Williams F1 Team', '#005aff')
on conflict (id) do nothing;

insert into public.site_settings (key, value) values (
  'homepage',
  '{"title":"Built to race.","claim":"Made to rise.","intro":"Die Zenith Formula Championship ist der Ort, an dem Teams zusammenwachsen und jeder Zentimeter zählt. Entdecke das Grid, die Fahrer und die Geschichten hinter der Zielflagge."}'::jsonb
)
on conflict (key) do nothing;

-- ============================================================
-- 6. Kontostände (View)
-- ============================================================

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

-- ============================================================
-- 7. Row-Level-Security
-- ============================================================

alter table public.teams enable row level security;
alter table public.profiles enable row level security;
alter table public.konzern_teams enable row level security;
alter table public.site_settings enable row level security;
alter table public.sponsor_offers enable row level security;
alter table public.sponsor_orders enable row level security;
alter table public.invoices enable row level security;
alter table public.account_entries enable row level security;
alter table public.team_cards enable row level security;
alter table public.card_requests enable row level security;
alter table public.drivers enable row level security;
alter table public.contracts enable row level security;
alter table public.scheduled_invoices enable row level security;
alter table public.support_tickets enable row level security;
alter table public.team_appointments enable row level security;

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

create policy "Konzern reads own teams, admins read all"
  on public.konzern_teams for select to authenticated
  using (profile_id = (select auth.uid()) or (select public.is_admin()));

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

-- Angebots-Anfragen: Teamchefs (auch Konzern / Admin in Doppelrolle) senden direkt
-- für ihr eigenes Team; die Verwaltung sieht und bearbeitet alle im Admin-Panel.
create policy "Admins and owning team read sponsor orders"
  on public.sponsor_orders for select to authenticated
  using (
    (select public.is_admin())
    or team_id = (select public.current_team_id())
  );
create policy "Team chiefs submit sponsor orders for their team"
  on public.sponsor_orders for insert to authenticated
  with check (
    team_id = (select public.current_team_id())
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
create policy "Admins update account entries"
  on public.account_entries for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create policy "Admins and owning team read cards"
  on public.team_cards for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
create policy "Admins create extra cards"
  on public.team_cards for insert to authenticated
  with check ((select public.is_admin()) and kind = 'extra');

create policy "Admins and owning team read card requests"
  on public.card_requests for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
create policy "Team chiefs request cards"
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

-- Fahrer: Teams verwalten ihre eigenen Fahrer, Admins alle.
create policy "Admins and owning team read drivers"
  on public.drivers for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
create policy "Teams register their own drivers"
  on public.drivers for insert to authenticated
  with check ((select public.is_admin()) or team_id = (select public.current_team_id()));
create policy "Admins and owning team update drivers"
  on public.drivers for update to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()))
  with check ((select public.is_admin()) or team_id = (select public.current_team_id()));
create policy "Admins and owning team delete drivers"
  on public.drivers for delete to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));

create policy "Admins and owning team read contracts"
  on public.contracts for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
create policy "Admins create contracts"
  on public.contracts for insert to authenticated
  with check ((select public.is_admin()));
-- Fahrerverträge: Teamchefs legen sie zur Finanzprüfung an (in_review), Admins prüfen.
create policy "Teams submit driver contracts for review"
  on public.contracts for insert to authenticated
  with check (
    (select public.is_admin())
    or (
      team_id = (select public.current_team_id())
      and type = 'driver'::public.contract_type
      and status = 'in_review'::public.contract_status
      and created_by = (select auth.uid())
    )
  );
create policy "Admins update contracts"
  on public.contracts for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));
create policy "Admins delete contracts"
  on public.contracts for delete to authenticated
  using ((select public.is_admin()));

-- Terminierte Rechnungen: Teams stellen den Antrag, Admins schalten auf.
create policy "Admins and owning team read scheduled invoices"
  on public.scheduled_invoices for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
create policy "Teams request scheduled invoices for their team"
  on public.scheduled_invoices for insert to authenticated
  with check (
    (select public.is_admin())
    or (
      team_id = (select public.current_team_id())
      and status = 'pending'
      and created_by = (select auth.uid())
    )
  );
create policy "Admins manage scheduled invoices"
  on public.scheduled_invoices for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));
create policy "Admins and owning team delete scheduled invoices"
  on public.scheduled_invoices for delete to authenticated
  using (
    (select public.is_admin())
    or (team_id = (select public.current_team_id()) and status in ('pending', 'active'))
  );

create policy "Admins and owning team read support tickets"
  on public.support_tickets for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
create policy "Team chiefs create tickets for their team"
  on public.support_tickets for insert to authenticated
  with check (
    team_id = (select public.current_team_id())
    and created_by = (select auth.uid())
    and status = 'open'
  );
create policy "Admins update support tickets"
  on public.support_tickets for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- Termine: die Verwaltung setzt sie, Teams lesen nur ihre eigenen.
create policy "Admins and owning team read appointments"
  on public.team_appointments for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
create policy "Admins create appointments"
  on public.team_appointments for insert to authenticated
  with check ((select public.is_admin()));
create policy "Admins update appointments"
  on public.team_appointments for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));
create policy "Admins delete appointments"
  on public.team_appointments for delete to authenticated
  using ((select public.is_admin()));

-- ============================================================
-- 8. Rechte (Grants)
-- ============================================================

grant usage on schema public to anon, authenticated;
grant select on public.teams, public.site_settings, public.sponsor_offers to anon, authenticated;
grant select, insert, update, delete on public.teams to authenticated;
grant select, update on public.profiles to authenticated;
grant select on public.konzern_teams to authenticated;
grant select, insert, update, delete on public.site_settings, public.sponsor_offers to authenticated;
grant select, insert, update on public.sponsor_orders to authenticated;
grant select, insert on public.invoices to authenticated;
grant update (
  team_id, invoice_number, description, amount_cents, due_date, status,
  reference, bill_to_name, bill_to_email, bill_to_company, bill_to_address
) on public.invoices to authenticated;
grant select, insert on public.account_entries to authenticated;
grant update (team_id, direction, amount_cents, description)
  on public.account_entries to authenticated;
grant select, insert on public.team_cards to authenticated;
grant select, insert on public.card_requests to authenticated;
grant update (status) on public.card_requests to authenticated;
grant select, insert, update, delete on public.drivers to authenticated;
grant select, insert on public.contracts to authenticated;
grant update (status) on public.contracts to authenticated;
grant update (
  team_id, type, title, terms, starts_on, ends_on, status
) on public.contracts to authenticated;
grant delete on public.contracts to authenticated;
grant select, insert, update, delete on public.scheduled_invoices to authenticated;
grant select, insert, update on public.support_tickets to authenticated;
grant select, insert, update, delete on public.team_appointments to authenticated;
grant select on public.team_account_balances to authenticated;

revoke all on function public.current_app_role() from public, anon;
revoke all on function public.current_team_id() from public, anon;
revoke all on function public.is_admin() from public, anon;
revoke all on function public.card_available_cents(uuid) from public, anon, authenticated;
revoke all on function public.request_invoice_payment(uuid, uuid) from public, anon;
revoke all on function public.transfer_between_cards(uuid, uuid, bigint) from public, anon;
revoke all on function public.approve_card_request(uuid, text, bigint, text) from public, anon;
revoke all on function public.respond_to_contract(uuid, boolean) from public, anon;
revoke all on function public.materialize_scheduled_invoices() from public, anon;
revoke all on function public.admin_reset_data() from public, anon;
revoke all on function public.admin_set_profile_role(uuid, public.app_role, text) from public, anon;
revoke all on function public.admin_set_konzern(uuid, text, text) from public, anon;
revoke all on function public.konzern_switch_team(text) from public, anon;
grant execute on function public.current_app_role() to authenticated;
grant execute on function public.current_team_id() to authenticated;
grant execute on function public.is_admin() to anon, authenticated;
grant execute on function public.request_invoice_payment(uuid, uuid) to authenticated;
grant execute on function public.transfer_between_cards(uuid, uuid, bigint) to authenticated;
grant execute on function public.approve_card_request(uuid, text, bigint, text) to authenticated;
grant execute on function public.respond_to_contract(uuid, boolean) to authenticated;
grant execute on function public.materialize_scheduled_invoices() to authenticated;
grant execute on function public.admin_reset_data() to authenticated;
grant execute on function public.admin_set_profile_role(uuid, public.app_role, text) to authenticated;
grant execute on function public.admin_set_konzern(uuid, text, text) to authenticated;
grant execute on function public.konzern_switch_team(text) to authenticated;

-- ============================================================
-- 9. Storage (Website-Bilder)
-- ============================================================

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

-- ============================================================
-- 10. Profile für bereits vorhandene Auth-Benutzer neu anlegen
-- ============================================================

insert into public.profiles (id, email, display_name, role, team_id)
select u.id, u.email, coalesce(nullif(split_part(coalesce(u.email, ''), '@', 1), ''), 'Teamchef'), 'team_chief', null
from auth.users u
on conflict (id) do nothing;

-- ============================================================
-- 11. Realtime (Live-Synchronisation des Portals)
-- ============================================================

do $$
declare t text;
begin
  foreach t in array array['teams','account_entries','sponsor_offers','sponsor_orders','invoices','contracts','support_tickets','profiles','site_settings','team_cards','card_requests','drivers','scheduled_invoices','team_appointments']
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

-- Kontrolle: muss alle 14 Tabellen anzeigen
select tablename from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' order by 1;
