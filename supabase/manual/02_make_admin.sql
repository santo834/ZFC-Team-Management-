-- ZFC: ADMIN ANLEGEN / PROFIL AKTUALISIEREN (separat, jederzeit einzeln ausführbar)
-- 1) Benutzer zuerst unter Authentication > Users anlegen (oder sich einmal registrieren/einloggen).
-- 2) Unten die E-Mail-Adresse eintragen und das Skript im SQL Editor ausführen.

do $$
declare
  admin_email text := 'DEINE-EMAIL@BEISPIEL.DE';  -- <- hier ändern
  target_id uuid;
begin
  select id into target_id from auth.users where lower(email) = lower(admin_email);
  if target_id is null then
    raise exception 'Kein Auth-Benutzer mit der E-Mail % gefunden. Bitte zuerst unter Authentication > Users anlegen.', admin_email;
  end if;

  insert into public.profiles (id, email, display_name, role, team_id)
  values (target_id, admin_email, coalesce(nullif(split_part(admin_email, '@', 1), ''), 'Admin'), 'admin', null)
  on conflict (id) do update
    set role = 'admin', team_id = null, email = excluded.email;
end $$;

-- Kontrolle
select p.email, p.role, p.team_id from public.profiles p order by p.role, p.email;

-- Optional: Teamchef einem Team zuweisen
-- update public.profiles set role = 'team_chief', team_id = 'scuderia-rosso' where lower(email) = lower('chef@beispiel.de');
