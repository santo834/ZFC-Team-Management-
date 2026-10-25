-- Enable Realtime (postgres_changes) for tables the portal keeps in sync.
do $$
declare t text;
begin
  foreach t in array array['teams','account_entries','sponsor_offers','sponsor_orders','invoices','contracts','support_tickets','profiles']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
