-- Konzern (and dual-role admins) carry a team, which the original check constraint forbids.
alter table public.profiles drop constraint if exists profiles_team_role_check;

-- profiles.team_id stays the *active* team, so every existing RLS policy (current_team_id()) keeps working.
create table if not exists public.konzern_teams (
  profile_id uuid not null references public.profiles (id) on delete cascade,
  team_id text not null references public.teams (id) on delete restrict,
  primary key (profile_id, team_id)
);

alter table public.konzern_teams enable row level security;

drop policy if exists "Konzern reads own teams, admins read all" on public.konzern_teams;
create policy "Konzern reads own teams, admins read all"
  on public.konzern_teams for select to authenticated
  using (profile_id = (select auth.uid()) or (select public.is_admin()));

grant select on public.konzern_teams to authenticated;

-- Admin assigns the Konzern role together with its two teams.
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

-- Konzern switches the active e-banking between its two teams.
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

-- Leaving the Konzern role removes its team links.
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

revoke all on function public.admin_set_konzern(uuid, text, text) from public, anon;
revoke all on function public.konzern_switch_team(text) from public, anon;
grant execute on function public.admin_set_konzern(uuid, text, text) to authenticated;
grant execute on function public.konzern_switch_team(text) to authenticated;

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
