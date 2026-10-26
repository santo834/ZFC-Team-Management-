-- ZFC UPGRADE: Virtuelle Kreditkarten (ohne Datenverlust)
-- Im Supabase SQL Editor einfügen und ausführen. Löscht KEINE Daten und kann mehrfach ausgeführt werden.
-- Bestehende Buchungen werden der Basiskarte des jeweiligen Teams zugeordnet.
-- Enthält außerdem den Fix für die öffentliche Sicht: Besucher ohne Login konnten veröffentlichte
-- Angebote und die Startseite nicht lesen (is_admin() war für anon gesperrt).
-- Bereits eingespielte Funktionen (z. B. admin_reset_data, admin_set_profile_role) bleiben unverändert.

-- ===== virtual_cards =====
-- Jedes Team hat automatisch eine Basiskarte (Startkapital + Auszahlungen landen dort).
-- Bis zu zwei weitere Karten werden per Kredit-Antrag angefragt und von einem Admin erstellt.
-- Der Kreditrahmen (Minus-Limit) wird nur bei der Erstellung festgelegt und ist danach nicht mehr änderbar.
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
drop trigger if exists limit_team_cards on public.team_cards;
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
drop trigger if exists create_basic_card on public.teams;
create trigger create_basic_card
  after insert on public.teams
  for each row execute function public.create_basic_card();

insert into public.team_cards (team_id, kind, label, design)
select team.id, 'basic', 'Basiskarte', 'basic' from public.teams as team
where not exists (select 1 from public.team_cards as c where c.team_id = team.id and c.kind = 'basic');

drop trigger if exists set_updated_at on public.card_requests;
create trigger set_updated_at
  before update on public.card_requests
  for each row execute function public.set_updated_at();

alter table public.account_entries
  add column if not exists card_id uuid references public.team_cards (id) on delete restrict,
  add column if not exists transfer_id uuid;
alter table public.invoices
  add column if not exists card_id uuid references public.team_cards (id) on delete set null;

update public.account_entries as entry
set card_id = (select card.id from public.team_cards as card where card.team_id = entry.team_id and card.kind = 'basic')
where entry.card_id is null;
alter table public.account_entries alter column card_id set not null;
create index if not exists account_entries_card_idx on public.account_entries (card_id);

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

drop policy if exists "Admins and owning team read cards" on public.team_cards;
create policy "Admins and owning team read cards"
  on public.team_cards for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
drop policy if exists "Admins create extra cards" on public.team_cards;
create policy "Admins create extra cards"
  on public.team_cards for insert to authenticated
  with check ((select public.is_admin()) and kind = 'extra');

drop policy if exists "Admins and owning team read card requests" on public.card_requests;
create policy "Admins and owning team read card requests"
  on public.card_requests for select to authenticated
  using ((select public.is_admin()) or team_id = (select public.current_team_id()));
drop policy if exists "Team chiefs request cards for their team" on public.card_requests;
create policy "Team chiefs request cards for their team"
  on public.card_requests for insert to authenticated
  with check (
    (select public.current_app_role()) = 'team_chief'
    and team_id = (select public.current_team_id())
    and created_by = (select auth.uid())
    and status = 'pending'
  );
drop policy if exists "Admins update card requests" on public.card_requests;
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

-- Öffentliche Angebote: die Lese-Policies rufen is_admin() auf, das auch für Besucher ohne Login ausführbar sein muss.
grant execute on function public.is_admin() to anon, authenticated;

-- Realtime für die neuen Tabellen
do $$
declare t text;
begin
  foreach t in array array['team_cards','card_requests','account_entries','invoices']
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
