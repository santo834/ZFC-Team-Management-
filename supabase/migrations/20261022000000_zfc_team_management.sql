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
begin
  if (select public.current_app_role()) <> 'team_chief' then
    raise exception 'Team-chief access required';
  end if;

  update public.contracts
  set status = case when p_accept then 'signed'::public.contract_status
                    else 'declined'::public.contract_status
      end,
      accepted_at = case when p_accept then pg_catalog.now() else null end
  where id = p_contract_id
    and team_id = (select public.current_team_id())
    and status = 'pending';

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
grant execute on function public.is_admin() to authenticated;
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
