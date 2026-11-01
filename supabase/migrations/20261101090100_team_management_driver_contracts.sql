-- Team-Verwaltung im E-Banking: Fahrer, Fahrerverträge zur Finanzprüfung
-- und automatisierte (terminierte) Rechnungen mit manueller Admin-Aufschaltung.
-- Bestehende Daten bleiben unverändert; es werden nur neue Strukturen ergänzt.
-- Voraussetzung: 20261101090000_contract_status_in_review.sql (Enum-Wert 'in_review').

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

alter table public.contracts
  add column if not exists driver_id uuid references public.drivers (id) on delete set null;

create table if not exists public.scheduled_invoices (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.teams (id) on delete restrict,
  description text not null check (char_length(description) between 1 and 500),
  amount_cents bigint not null check (amount_cents between 1 and 100000000000),
  send_date date not null,
  due_date date not null,
  status text not null default 'pending' check (status in ('pending', 'active', 'sent', 'cancelled')),
  invoice_id uuid references public.invoices (id) on delete set null,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scheduled_invoices_date_order_check check (due_date >= send_date)
);

create index if not exists drivers_team_id_idx on public.drivers (team_id);
create index if not exists scheduled_invoices_team_id_idx on public.scheduled_invoices (team_id);
create index if not exists scheduled_invoices_due_idx on public.scheduled_invoices (status, send_date);

alter table public.drivers enable row level security;
alter table public.scheduled_invoices enable row level security;

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

-- Erzeugt fällige terminierte Rechnungen im Teamkonto (wird beim Laden aufgerufen).
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
begin
  for item in
    select si.*
    from public.scheduled_invoices as si
    where si.status = 'active'
      and si.send_date <= current_date
      and si.invoice_id is null
  loop
    loop
      new_number := pg_catalog.lpad(pg_catalog.floor(pg_catalog.random() * 9000000000 + 1000000000)::bigint::text, 10, '0');
      exit when not exists (select 1 from public.invoices as inv where inv.invoice_number = new_number);
    end loop;

    insert into public.invoices (
      team_id, invoice_number, description, amount_cents, due_date, reference, created_by
    ) values (
      item.team_id, new_number, item.description, item.amount_cents, item.due_date,
      'AUTO-' || pg_catalog.substr(item.id::text, 1, 8), item.created_by
    )
    returning id into item.invoice_id;

    update public.scheduled_invoices
    set status = 'sent', invoice_id = item.invoice_id, updated_at = pg_catalog.now()
    where id = item.id;

    created_count := created_count + 1;
  end loop;
  return created_count;
end;
$$;

grant select, insert, update, delete on public.drivers to authenticated;
grant select, insert, update, delete on public.scheduled_invoices to authenticated;

revoke all on function public.materialize_scheduled_invoices() from public, anon;
grant execute on function public.materialize_scheduled_invoices() to authenticated;

-- Live-Synchronisation für die neuen Tabellen.
do $$
declare t text;
begin
  foreach t in array array['drivers','scheduled_invoices']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
