-- ZFC SICHERES UPGRADE (OHNE Datenverlust)
-- Für Datenbanken, auf denen bereits Daten vorhanden sind (Rechnungen, Buchungen,
-- Verträge, Anfragen, Fahrer, terminierte Rechnungen der Teamchefs usw.).
-- Im Supabase SQL Editor komplett einfügen und ausführen.
--
-- Was dieses Skript tut:
--   1. Fehlende Strukturen ergänzen (Konzern, Fahrer, Termine, Karten, Details …)
--   2. Terminierte Rechnungen auf das Dauerauftrag-Modell umstellen
--      (send_date/due_date/interval_weeks -> start_date/end_date, Raten bleiben erhalten)
--   3. Funktionen, RLS-Richtlinien, Rechte und Realtime auf den neuesten Stand bringen
-- Es wird NICHTS gelöscht. Bestehende Zeilen bleiben unverändert erhalten.
-- Danach bei Bedarf 02_make_admin.sql ausführen, um ein Konto zum Admin zu machen.

-- ============================================================
-- 1. Typen (neue Werte, ohne bestehende zu löschen)
-- ============================================================

alter type public.app_role add value if not exists 'konzern';
alter type public.contract_type add value if not exists 'driver';
alter type public.contract_type add value if not exists 'team_principal';
alter type public.contract_type add value if not exists 'driver_purchase';
alter type public.contract_status add value if not exists 'in_review';

-- ============================================================
-- 2. Fehlende Spalten an bestehenden Tabellen
-- ============================================================

alter table public.profiles
  add column if not exists email text;
alter table public.profiles drop constraint if exists profiles_team_role_check;
create unique index if not exists profiles_email_lower_unique_idx
  on public.profiles (lower(email)) where email is not null;

alter table public.sponsor_offers
  add column if not exists category text not null default 'sponsoring',
  add column if not exists terms text not null default '',
  add column if not exists logo_path text,
  add column if not exists details jsonb not null default '{}'::jsonb;
alter table public.sponsor_offers drop constraint if exists sponsor_offers_category_check;
alter table public.sponsor_offers
  add constraint sponsor_offers_category_check check (category in ('insurance','sponsoring','hq','marketplace'));

alter table public.sponsor_orders
  add column if not exists category text not null default 'sponsoring',
  add column if not exists offer_terms text not null default '',
  add column if not exists company text not null default '',
  add column if not exists billing_address text not null default '',
  add column if not exists customer_notes text not null default '';
alter table public.sponsor_orders alter column offer_id drop not null;
alter table public.sponsor_orders drop constraint if exists sponsor_orders_offer_id_fkey;
alter table public.sponsor_orders
  add constraint sponsor_orders_offer_id_fkey foreign key (offer_id) references public.sponsor_offers (id) on delete set null;
create index if not exists sponsor_orders_email_created_at_idx on public.sponsor_orders (email, created_at desc);

alter table public.invoices
  add column if not exists bill_to_name text not null default '',
  add column if not exists bill_to_email text not null default '',
  add column if not exists bill_to_company text not null default '',
  add column if not exists bill_to_address text not null default '',
  add column if not exists items jsonb not null default '[]'::jsonb,
  add column if not exists card_id uuid;

alter table public.contracts
  add column if not exists driver_id uuid;

-- ============================================================
-- 3. Konzern (zwei Teams pro Konzern-Chef)
-- ============================================================

create table if not exists public.konzern_teams (
  profile_id uuid not null references public.profiles (id) on delete cascade,
  team_id text not null references public.teams (id) on delete restrict,
  primary key (profile_id, team_id)
);
alter table public.konzern_teams enable row level security;

-- ============================================================
-- 4. Virtuelle Karten (falls noch nicht vorhanden)
-- ============================================================

create table if not exists public.team_cards (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.teams (id) on delete restrict,
  kind text not null default 'extra' check (kind in ('basic', 'extra')),
  label text not null default '' check (char_length(label) <= 40),
  design text not null default 'carbon' check (design in ('basic', 'sunset', 'aurora', 'carbon', 'gold', 'ocean')),
  credit_limit_cents bigint not null default 0 check (credit_limit_cents between 0 and 100000000000),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);
create unique index if not exists team_cards_one_basic_idx on public.team_cards (team_id) where kind = 'basic';
create index if not exists team_cards_team_idx on public.team_cards (team_id);

create table if not exists public.card_requests (
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
create unique index if not exists card_requests_one_pending_idx on public.card_requests (team_id) where status = 'pending';

alter table public.account_entries
  add column if not exists card_id uuid,
  add column if not exists transfer_id uuid;

-- Basiskarten für Teams ohne Karte nachziehen (bestehende bleiben erhalten)
insert into public.team_cards (team_id, kind, label, design)
select team.id, 'basic', 'Basiskarte', 'basic'
from public.teams as team
where not exists (select 1 from public.team_cards as card where card.team_id = team.id and card.kind = 'basic');

-- Buchungen ohne Karte auf die Basiskarte legen
update public.account_entries as entry
set card_id = (select card.id from public.team_cards as card where card.team_id = entry.team_id and card.kind = 'basic')
where entry.card_id is null;

do $$
begin
  if exists (select 1 from public.account_entries where card_id is null) then
    raise notice 'Es gibt Buchungen ohne zuordenbare Karte – bitte prüfen.';
  else
    alter table public.account_entries alter column card_id set not null;
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'account_entries_card_id_fkey') then
    alter table public.account_entries
      add constraint account_entries_card_id_fkey foreign key (card_id) references public.team_cards (id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'invoices_card_id_fkey') then
    alter table public.invoices
      add constraint invoices_card_id_fkey foreign key (card_id) references public.team_cards (id) on delete set null;
  end if;
end $$;
create index if not exists account_entries_card_idx on public.account_entries (card_id);

-- ============================================================
-- 5. Fahrer
-- ============================================================

create table if not exists public.drivers (
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
create index if not exists drivers_team_id_idx on public.drivers (team_id);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'contracts_driver_id_fkey') then
    alter table public.contracts
      add constraint contracts_driver_id_fkey foreign key (driver_id) references public.drivers (id) on delete set null;
  end if;
end $$;

-- ============================================================
-- 6. Terminierte Rechnungen -> Dauerauftrag (Daten bleiben erhalten)
-- ============================================================

-- Neue Spalten
alter table public.scheduled_invoices
  add column if not exists start_date date,
  add column if not exists end_date date;

-- Bestehende Zeilen migrieren: send_date -> start_date, due_date -> end_date
-- (nur wenn die alten Spalten noch existieren; macht das Skript mehrfach ausführbar)
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='scheduled_invoices' and column_name='send_date') then
    update public.scheduled_invoices
    set start_date = coalesce(start_date, send_date, current_date),
        end_date = coalesce(end_date, greatest(due_date, send_date), send_date, current_date)
    where start_date is null or end_date is null;
  else
    update public.scheduled_invoices
    set start_date = coalesce(start_date, current_date),
        end_date = coalesce(end_date, start_date, current_date)
    where start_date is null or end_date is null;
  end if;
end $$;

-- total_cents absichern (war optional): aus Rate × Raten ableiten
update public.scheduled_invoices
set total_cents = amount_cents * installments_total
where total_cents is null;

alter table public.scheduled_invoices alter column start_date set not null;
alter table public.scheduled_invoices alter column end_date set not null;
alter table public.scheduled_invoices alter column total_cents set not null;
alter table public.scheduled_invoices alter column total_cents set default 1;
alter table public.scheduled_invoices alter column installments_total set default 16;

-- Alte Spalten und Constraints entfernen (Werte sind bereits übernommen)
alter table public.scheduled_invoices drop constraint if exists scheduled_invoices_date_order_check;
alter table public.scheduled_invoices drop column if exists send_date;
alter table public.scheduled_invoices drop column if exists due_date;
alter table public.scheduled_invoices drop column if exists interval_weeks;

-- Neue Constraints
alter table public.scheduled_invoices drop constraint if exists scheduled_invoices_date_order_check;
alter table public.scheduled_invoices
  add constraint scheduled_invoices_date_order_check check (end_date >= start_date);
alter table public.scheduled_invoices drop constraint if exists scheduled_invoices_installments_check;
alter table public.scheduled_invoices
  add constraint scheduled_invoices_installments_check check (installments_total = 1 or end_date > start_date);

drop index if exists public.scheduled_invoices_due_idx;
create index if not exists scheduled_invoices_team_id_idx on public.scheduled_invoices (team_id);
create index if not exists scheduled_invoices_due_idx on public.scheduled_invoices (status, next_send_date);

-- ============================================================
-- 7. Team-Termine (neu)
-- ============================================================

create table if not exists public.team_appointments (
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
create index if not exists team_appointments_team_id_idx on public.team_appointments (team_id, starts_at);

-- ============================================================
-- 8. Funktionen (aktuelle Versionen)
-- ============================================================

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at := pg_catalog.now(); return new; end;
$$;

create or replace function public.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare user_name text;
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
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_auth_user();

create or replace function public.protect_profile_role()
returns trigger language plpgsql set search_path = '' as $$
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

create or replace function public.validate_sponsor_order()
returns trigger language plpgsql security definer set search_path = '' as $$
declare selected_offer public.sponsor_offers%rowtype;
begin
  select offer.* into selected_offer from public.sponsor_offers as offer
  where offer.id = new.offer_id and offer.published;
  if not found then raise exception 'Sponsor offer is not available'; end if;
  new.offer_name := selected_offer.name;
  new.amount_cents := selected_offer.amount_cents;
  return new;
end;
$$;
drop trigger if exists validate_sponsor_order_before_insert on public.sponsor_orders;
create trigger validate_sponsor_order_before_insert before insert on public.sponsor_orders for each row execute function public.validate_sponsor_order();

create or replace function public.current_app_role()
returns public.app_role language sql stable security definer set search_path = '' as $$
  select case when profile.team_id is not null then 'team_chief'::public.app_role else profile.role end
  from public.profiles as profile where profile.id = (select auth.uid())
$$;

create or replace function public.current_team_id()
returns text language sql stable security definer set search_path = '' as $$
  select profile.team_id from public.profiles as profile where profile.id = (select auth.uid())
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select profile.role = 'admin' from public.profiles as profile where profile.id = (select auth.uid())), false)
$$;

create or replace function public.card_available_cents(p_card_id uuid)
returns bigint language sql stable security definer set search_path = '' as $$
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
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.team_cards as card where card.team_id = new.team_id) >= 3 then
    raise exception 'Ein Team kann höchstens drei Karten besitzen';
  end if;
  return new;
end;
$$;
drop trigger if exists limit_team_cards on public.team_cards;
create trigger limit_team_cards before insert on public.team_cards for each row execute function public.limit_team_cards();

create or replace function public.create_basic_card()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.team_cards (team_id, kind, label, design) values (new.id, 'basic', 'Basiskarte', 'basic');
  return new;
end;
$$;
drop trigger if exists create_basic_card on public.teams;
create trigger create_basic_card after insert on public.teams for each row execute function public.create_basic_card();

create or replace function public.prevent_overdrawn_account()
returns trigger language plpgsql security definer set search_path = '' as $$
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
  if new.direction <> 'debit' then return new; end if;
  select case when card.kind = 'basic' then team.initial_balance_cents else 0 end into opening_balance
  from public.teams as team where team.id = new.team_id;
  select opening_balance + coalesce(sum(case when entry.direction = 'credit' then entry.amount_cents else -entry.amount_cents end), 0)
  into current_balance from public.account_entries as entry where entry.card_id = card.id;
  if current_balance + card.credit_limit_cents < new.amount_cents then
    raise exception 'Insufficient card balance';
  end if;
  return new;
end;
$$;
drop trigger if exists prevent_overdrawn_account on public.account_entries;
create trigger prevent_overdrawn_account before insert on public.account_entries for each row execute function public.prevent_overdrawn_account();

create or replace function public.record_invoice_payment()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status is distinct from new.status and new.status = 'paid' then
    insert into public.account_entries (team_id, card_id, invoice_id, direction, amount_cents, description, created_by)
    values (new.team_id, new.card_id, new.id, 'debit', new.amount_cents, 'Rechnung ' || new.invoice_number, auth.uid());
  end if;
  return new;
end;
$$;
drop trigger if exists record_paid_invoice on public.invoices;
create trigger record_paid_invoice after update of status on public.invoices for each row execute function public.record_invoice_payment();

drop function if exists public.request_invoice_payment(uuid);
create or replace function public.request_invoice_payment(p_invoice_id uuid, p_card_id uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  chosen_card uuid;
  invoice_amount bigint;
begin
  if (select public.current_app_role()) <> 'team_chief' then raise exception 'Team-chief access required'; end if;
  select card.id into chosen_card from public.team_cards as card
  where card.team_id = (select public.current_team_id())
    and ((p_card_id is null and card.kind = 'basic') or card.id = p_card_id);
  if chosen_card is null then raise exception 'Card not found'; end if;
  select invoice.amount_cents into invoice_amount from public.invoices as invoice
  where invoice.id = p_invoice_id and invoice.team_id = (select public.current_team_id()) and invoice.status = 'open';
  if invoice_amount is null then raise exception 'Invoice not found or payment request is not allowed'; end if;
  if (select public.card_available_cents(chosen_card)) < invoice_amount then raise exception 'Insufficient card balance'; end if;
  update public.invoices set status = 'payment_requested', card_id = chosen_card where id = p_invoice_id;
end;
$$;

create or replace function public.transfer_between_cards(p_from_card uuid, p_to_card uuid, p_amount_cents bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare
  from_card public.team_cards;
  to_card public.team_cards;
  transfer uuid := gen_random_uuid();
begin
  if (select public.current_app_role()) <> 'team_chief' then raise exception 'Team-chief access required'; end if;
  if p_from_card = p_to_card or p_amount_cents is null or p_amount_cents < 1 then raise exception 'Ungültige Umbuchung'; end if;
  select * into from_card from public.team_cards as c where c.id = p_from_card and c.team_id = (select public.current_team_id());
  select * into to_card from public.team_cards as c where c.id = p_to_card and c.team_id = (select public.current_team_id());
  if from_card.id is null or to_card.id is null then raise exception 'Karte nicht gefunden'; end if;
  if (select public.card_available_cents(from_card.id)) < p_amount_cents then raise exception 'Insufficient card balance'; end if;
  insert into public.account_entries (team_id, card_id, direction, amount_cents, description, created_by, transfer_id)
  values (from_card.team_id, from_card.id, 'debit', p_amount_cents, 'Umbuchung auf ' || to_card.label, auth.uid(), transfer),
         (to_card.team_id, to_card.id, 'credit', p_amount_cents, 'Umbuchung von ' || from_card.label, auth.uid(), transfer);
end;
$$;

create or replace function public.approve_card_request(p_request_id uuid, p_design text, p_limit_cents bigint, p_label text default '')
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  request public.card_requests;
  new_card uuid;
begin
  if not (select public.is_admin()) then raise exception 'Admin access required'; end if;
  select * into request from public.card_requests as r where r.id = p_request_id and r.status = 'pending' for update;
  if request.id is null then raise exception 'Antrag nicht gefunden oder bereits bearbeitet'; end if;
  insert into public.team_cards (team_id, kind, label, design, credit_limit_cents, created_by)
  values (request.team_id, 'extra', coalesce(nullif(pg_catalog.left(p_label, 40), ''), 'Kreditkarte'), p_design, p_limit_cents, auth.uid())
  returning id into new_card;
  update public.card_requests set status = 'approved', card_id = new_card where id = request.id;
  return new_card;
end;
$$;

create or replace function public.respond_to_contract(p_contract_id uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare requester_role public.app_role;
begin
  requester_role := (select public.current_app_role());
  if requester_role is null then raise exception 'Admin or team access required'; end if;
  update public.contracts
  set status = case when p_accept then 'signed'::public.contract_status else 'declined'::public.contract_status end,
      accepted_at = case when p_accept then pg_catalog.now() else null end
  where id = p_contract_id and status = 'pending'
    and (requester_role = 'admin'::public.app_role or team_id = (select public.current_team_id()));
  if not found then raise exception 'Contract not found or response is not allowed'; end if;
end;
$$;

-- Dauerauftrag: Raten gleichmässig zwischen Start- und Enddatum, letzte Rate mit Rundungsrest.
create or replace function public.materialize_scheduled_invoices()
returns integer language plpgsql security definer set search_path = '' as $$
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
    select si.* from public.scheduled_invoices as si
    where si.status = 'active'
      and coalesce(si.next_send_date, si.start_date) <= current_date
      and si.installments_sent < si.installments_total
  loop
    rate_index := item.installments_sent + 1;
    rate_amount := pg_catalog.floor(item.total_cents / item.installments_total);
    if rate_index = item.installments_total then
      rate_amount := item.total_cents - rate_amount * (item.installments_total - 1);
    end if;
    rate_description := case when item.installments_total > 1
      then item.description || ' (Rate ' || rate_index || '/' || item.installments_total || ')'
      else item.description end;
    rate_date := coalesce(item.next_send_date, item.start_date);
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
    insert into public.invoices (team_id, invoice_number, description, amount_cents, due_date, reference, created_by)
    values (item.team_id, new_number, rate_description, rate_amount, rate_date + 7,
            'AUTO-' || pg_catalog.substr(item.id::text, 1, 8), item.created_by)
    returning id into item.invoice_id;
    update public.scheduled_invoices
    set installments_sent = rate_index, invoice_id = item.invoice_id, next_send_date = next_date,
        status = case when rate_index >= item.installments_total then 'sent' else 'active' end,
        updated_at = pg_catalog.now()
    where id = item.id;
    created_count := created_count + 1;
  end loop;
  return created_count;
end;
$$;

create or replace function public.admin_reset_data()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not (select public.is_admin()) then raise exception 'Nur Admins können Daten zurücksetzen.'; end if;
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

create or replace function public.admin_set_profile_role(p_profile_id uuid, p_role public.app_role, p_team_id text)
returns public.profiles language plpgsql security definer set search_path = '' as $$
declare result public.profiles;
begin
  if not (select public.is_admin()) then raise exception 'Nur Admins können Rollen ändern.'; end if;
  if p_role = 'konzern' then raise exception 'Für die Rolle Konzern bitte zwei Teams auswählen.'; end if;
  if p_team_id is not null and not exists (select 1 from public.teams where id = p_team_id) then
    raise exception 'Das ausgewählte Team wurde nicht gefunden.';
  end if;
  if p_role = 'team_chief' and p_team_id is null then raise exception 'Ein Teamchef braucht ein Team.'; end if;
  update public.profiles set role = p_role, team_id = p_team_id where id = p_profile_id returning * into result;
  if not found then raise exception 'Profil nicht gefunden.'; end if;
  delete from public.konzern_teams where profile_id = p_profile_id;
  return result;
end;
$$;

create or replace function public.admin_set_konzern(p_profile_id uuid, p_team_a text, p_team_b text)
returns public.profiles language plpgsql security definer set search_path = '' as $$
declare result public.profiles;
begin
  if not (select public.is_admin()) then raise exception 'Nur Admins können Rollen ändern.'; end if;
  if p_team_a is null or p_team_b is null or p_team_a = p_team_b then
    raise exception 'Ein Konzern braucht genau zwei verschiedene Teams.';
  end if;
  if (select count(*) from public.teams where id in (p_team_a, p_team_b)) <> 2 then
    raise exception 'Eines der ausgewählten Teams wurde nicht gefunden.';
  end if;
  update public.profiles
  set role = 'konzern'::public.app_role,
      team_id = case when profiles.team_id in (p_team_a, p_team_b) then profiles.team_id else p_team_a end
  where profiles.id = p_profile_id returning * into result;
  if not found then raise exception 'Profil nicht gefunden.'; end if;
  delete from public.konzern_teams where profile_id = p_profile_id;
  insert into public.konzern_teams (profile_id, team_id) values (p_profile_id, p_team_a), (p_profile_id, p_team_b);
  return result;
end;
$$;

create or replace function public.konzern_switch_team(p_team_id text)
returns public.profiles language plpgsql security definer set search_path = '' as $$
declare result public.profiles;
begin
  if not exists (
    select 1 from public.profiles as profile
    join public.konzern_teams as kt on kt.profile_id = profile.id
    where profile.id = (select auth.uid()) and profile.role = 'konzern' and kt.team_id = p_team_id
  ) then raise exception 'Dieses Team gehört nicht zu deinem Konzern.'; end if;
  update public.profiles set team_id = p_team_id where id = (select auth.uid()) returning * into result;
  return result;
end;
$$;

-- ============================================================
-- 9. Trigger (updated_at) für neue Tabellen
-- ============================================================

drop trigger if exists set_updated_at on public.card_requests;
create trigger set_updated_at before update on public.card_requests for each row execute function public.set_updated_at();
drop trigger if exists set_updated_at on public.drivers;
create trigger set_updated_at before update on public.drivers for each row execute function public.set_updated_at();
drop trigger if exists set_updated_at on public.scheduled_invoices;
create trigger set_updated_at before update on public.scheduled_invoices for each row execute function public.set_updated_at();
drop trigger if exists set_updated_at on public.team_appointments;
create trigger set_updated_at before update on public.team_appointments for each row execute function public.set_updated_at();

-- ============================================================
-- 10. Row-Level-Security (Richtlinien auf neuesten Stand)
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

drop policy if exists "Teams are publicly readable" on public.teams;
create policy "Teams are publicly readable" on public.teams for select to anon, authenticated using (true);
drop policy if exists "Admins manage teams" on public.teams;
create policy "Admins manage teams" on public.teams for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists "Users read their own profile" on public.profiles;
create policy "Users read their own profile" on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()));
drop policy if exists "Admins update profile assignments" on public.profiles;
create policy "Admins update profile assignments" on public.profiles for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists "Konzern reads own teams, admins read all" on public.konzern_teams;
create policy "Konzern reads own teams, admins read all" on public.konzern_teams for select to authenticated
  using (profile_id = (select auth.uid()) or (select public.is_admin()));

drop policy if exists "Public can read homepage settings" on public.site_settings;
create policy "Public can read homepage settings" on public.site_settings for select to anon, authenticated
  using (key = 'homepage' or (select public.is_admin()));
drop policy if exists "Admins manage site settings" on public.site_settings;
create policy "Admins manage site settings" on public.site_settings for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists "Published sponsor offers are public" on public.sponsor_offers;
create policy "Published sponsor offers are public" on public.sponsor_offers for select to anon, authenticated
  using (published or (select public.is_admin()));
drop policy if exists "Admins manage sponsor offers" on public.sponsor_offers;
create policy "Admins manage sponsor offers" on public.sponsor_offers for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists "Admins and owning team read sponsor orders" on public.sponsor_orders;
create policy "Admins and owning team read sponsor orders" on public.sponsor_orders for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
drop policy if exists "Team chiefs submit sponsor orders for their team" on public.sponsor_orders;
create policy "Team chiefs submit sponsor orders for their team" on public.sponsor_orders for insert to authenticated
  with check (team_id = (select public.current_team_id()) and created_by = (select auth.uid()) and status = 'pending');
drop policy if exists "Admins manage sponsor orders" on public.sponsor_orders;
create policy "Admins manage sponsor orders" on public.sponsor_orders for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists "Admins and owning team read invoices" on public.invoices;
create policy "Admins and owning team read invoices" on public.invoices for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
drop policy if exists "Admins create invoices" on public.invoices;
create policy "Admins create invoices" on public.invoices for insert to authenticated with check ((select public.is_admin()));
drop policy if exists "Admins update invoice status" on public.invoices;
create policy "Admins update invoice status" on public.invoices for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists "Admins and owning team read account entries" on public.account_entries;
create policy "Admins and owning team read account entries" on public.account_entries for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
drop policy if exists "Admins record account entries" on public.account_entries;
create policy "Admins record account entries" on public.account_entries for insert to authenticated
  with check ((select public.is_admin()));
drop policy if exists "Admins update account entries" on public.account_entries;
create policy "Admins update account entries" on public.account_entries for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists "Admins and owning team read cards" on public.team_cards;
create policy "Admins and owning team read cards" on public.team_cards for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
drop policy if exists "Admins create extra cards" on public.team_cards;
create policy "Admins create extra cards" on public.team_cards for insert to authenticated
  with check ((select public.is_admin()) and kind = 'extra');

drop policy if exists "Admins and owning team read card requests" on public.card_requests;
create policy "Admins and owning team read card requests" on public.card_requests for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
drop policy if exists "Team chiefs request cards" on public.card_requests;
create policy "Team chiefs request cards" on public.card_requests for insert to authenticated
  with check ((select public.current_app_role()) = 'team_chief' and team_id = (select public.current_team_id())
    and created_by = (select auth.uid()) and status = 'pending');
drop policy if exists "Admins update card requests" on public.card_requests;
create policy "Admins update card requests" on public.card_requests for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists "Admins and owning team read drivers" on public.drivers;
create policy "Admins and owning team read drivers" on public.drivers for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
drop policy if exists "Teams register their own drivers" on public.drivers;
create policy "Teams register their own drivers" on public.drivers for insert to authenticated
  with check ((select public.is_admin()) or team_id = (select public.current_team_id()));
drop policy if exists "Admins and owning team update drivers" on public.drivers;
create policy "Admins and owning team update drivers" on public.drivers for update to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()))
  with check ((select public.is_admin()) or team_id = (select public.current_team_id()));
drop policy if exists "Admins and owning team delete drivers" on public.drivers;
create policy "Admins and owning team delete drivers" on public.drivers for delete to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));

drop policy if exists "Admins and owning team read contracts" on public.contracts;
create policy "Admins and owning team read contracts" on public.contracts for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
drop policy if exists "Admins create contracts" on public.contracts;
create policy "Admins create contracts" on public.contracts for insert to authenticated with check ((select public.is_admin()));
drop policy if exists "Teams submit driver contracts for review" on public.contracts;
create policy "Teams submit driver contracts for review" on public.contracts for insert to authenticated
  with check ((select public.is_admin()) or (team_id = (select public.current_team_id())
    and type = 'driver'::public.contract_type and status = 'in_review'::public.contract_status
    and created_by = (select auth.uid())));
drop policy if exists "Admins update contracts" on public.contracts;
create policy "Admins update contracts" on public.contracts for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
drop policy if exists "Admins delete contracts" on public.contracts;
create policy "Admins delete contracts" on public.contracts for delete to authenticated using ((select public.is_admin()));

drop policy if exists "Admins and owning team read scheduled invoices" on public.scheduled_invoices;
create policy "Admins and owning team read scheduled invoices" on public.scheduled_invoices for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
drop policy if exists "Teams request scheduled invoices for their team" on public.scheduled_invoices;
create policy "Teams request scheduled invoices for their team" on public.scheduled_invoices for insert to authenticated
  with check ((select public.is_admin()) or (team_id = (select public.current_team_id())
    and status = 'pending' and created_by = (select auth.uid())));
drop policy if exists "Admins manage scheduled invoices" on public.scheduled_invoices;
create policy "Admins manage scheduled invoices" on public.scheduled_invoices for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
drop policy if exists "Admins and owning team delete scheduled invoices" on public.scheduled_invoices;
create policy "Admins and owning team delete scheduled invoices" on public.scheduled_invoices for delete to authenticated
  using ((select public.is_admin()) or (team_id = (select public.current_team_id()) and status in ('pending', 'active')));

drop policy if exists "Admins and owning team read support tickets" on public.support_tickets;
create policy "Admins and owning team read support tickets" on public.support_tickets for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
drop policy if exists "Team chiefs create tickets for their team" on public.support_tickets;
create policy "Team chiefs create tickets for their team" on public.support_tickets for insert to authenticated
  with check (team_id = (select public.current_team_id()) and created_by = (select auth.uid()) and status = 'open');
drop policy if exists "Admins update support tickets" on public.support_tickets;
create policy "Admins update support tickets" on public.support_tickets for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists "Admins and owning team read appointments" on public.team_appointments;
create policy "Admins and owning team read appointments" on public.team_appointments for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
drop policy if exists "Admins create appointments" on public.team_appointments;
create policy "Admins create appointments" on public.team_appointments for insert to authenticated
  with check ((select public.is_admin()));
drop policy if exists "Admins update appointments" on public.team_appointments;
create policy "Admins update appointments" on public.team_appointments for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
drop policy if exists "Admins delete appointments" on public.team_appointments;
create policy "Admins delete appointments" on public.team_appointments for delete to authenticated
  using ((select public.is_admin()));

-- ============================================================
-- 11. Rechte (Grants)
-- ============================================================

grant usage on schema public to anon, authenticated;
grant select on public.teams, public.site_settings, public.sponsor_offers to anon, authenticated;
grant select, insert, update, delete on public.teams to authenticated;
grant select, update on public.profiles to authenticated;
grant select on public.konzern_teams to authenticated;
grant select, insert, update, delete on public.site_settings, public.sponsor_offers to authenticated;
grant select, insert, update on public.sponsor_orders to authenticated;
grant select, insert on public.invoices to authenticated;
grant update (team_id, invoice_number, description, amount_cents, due_date, status, reference,
  bill_to_name, bill_to_email, bill_to_company, bill_to_address) on public.invoices to authenticated;
grant select, insert on public.account_entries to authenticated;
grant update (team_id, direction, amount_cents, description) on public.account_entries to authenticated;
grant select, insert on public.team_cards to authenticated;
grant select, insert on public.card_requests to authenticated;
grant update (status) on public.card_requests to authenticated;
grant select, insert, update, delete on public.drivers to authenticated;
grant select, insert on public.contracts to authenticated;
grant update (status) on public.contracts to authenticated;
grant update (team_id, type, title, terms, starts_on, ends_on, status) on public.contracts to authenticated;
grant delete on public.contracts to authenticated;
grant select, insert, update, delete on public.scheduled_invoices to authenticated;
grant select, insert, update on public.support_tickets to authenticated;
grant select, insert, update, delete on public.team_appointments to authenticated;

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
-- 12. Profile für Auth-Benutzer ohne Profil nachziehen
-- ============================================================

insert into public.profiles (id, email, display_name, role, team_id)
select u.id, u.email, coalesce(nullif(split_part(coalesce(u.email, ''), '@', 1), ''), 'Teamchef'), 'team_chief', null
from auth.users u
on conflict (id) do nothing;

-- ============================================================
-- 13. Realtime
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
