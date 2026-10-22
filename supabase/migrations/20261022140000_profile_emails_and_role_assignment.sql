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

update public.profiles as profile
set role = 'admin', team_id = null
from auth.users as auth_user
where auth_user.id = profile.id
  and lower(auth_user.email) = 's.barbosa.galaxy@gmail.com';
