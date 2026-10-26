-- Admins may also be team chiefs (dual role): an admin with a team_id acts as chief of that team.
alter table public.profiles drop constraint if exists profiles_team_role_check;

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
  return result;
end;
$$;

-- Wipes all published business data and puts every team account back to zero.
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
  delete from public.invoices where true;
  delete from public.sponsor_orders where true;
  delete from public.contracts where true;
  delete from public.support_tickets where true;
  update public.teams set initial_balance_cents = 0 where true;
end;
$$;

revoke all on function public.admin_set_profile_role(uuid, public.app_role, text) from public, anon;
revoke all on function public.admin_reset_data() from public, anon;
grant execute on function public.admin_set_profile_role(uuid, public.app_role, text) to authenticated;
grant execute on function public.admin_reset_data() to authenticated;

-- Dual role: anyone with a team may act for it, so check the team instead of the role.
create or replace function public.request_invoice_payment(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select public.current_team_id()) is null then
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

drop policy if exists "Admins and owning team read sponsor orders" on public.sponsor_orders;
create policy "Admins and owning team read sponsor orders"
  on public.sponsor_orders for select to authenticated
  using (
    (select public.is_admin())
    or team_id = (select public.current_team_id())
  );

drop policy if exists "Team chiefs submit sponsor orders for their team" on public.sponsor_orders;
create policy "Team chiefs submit sponsor orders for their team"
  on public.sponsor_orders for insert to authenticated
  with check (
    team_id = (select public.current_team_id())
    and created_by = (select auth.uid())
    and status = 'pending'
  );

drop policy if exists "Team chiefs create tickets for their team" on public.support_tickets;
create policy "Team chiefs create tickets for their team"
  on public.support_tickets for insert to authenticated
  with check (
    team_id = (select public.current_team_id())
    and created_by = (select auth.uid())
    and status = 'open'
  );
