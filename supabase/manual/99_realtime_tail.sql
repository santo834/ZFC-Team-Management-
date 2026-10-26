
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
