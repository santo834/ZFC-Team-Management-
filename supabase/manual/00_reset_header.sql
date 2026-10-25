-- ZFC KOMPLETTES SCHEMA (Neuaufbau)
-- Im Supabase SQL Editor komplett einfügen und ausführen.
-- ACHTUNG: Löscht zuerst alle ZFC-Tabellen, Funktionen und Typen im Schema public (inkl. Daten).
-- Benutzer unter Authentication > Users bleiben erhalten, ihre Profile werden am Ende neu angelegt.

drop trigger if exists on_auth_user_created on auth.users;
drop policy if exists "Portal media is publicly readable" on storage.objects;
drop policy if exists "Admins upload portal media" on storage.objects;
drop policy if exists "Admins update portal media" on storage.objects;
drop policy if exists "Admins delete portal media" on storage.objects;
drop table if exists public.support_tickets, public.contracts, public.account_entries, public.invoices,
  public.sponsor_orders, public.sponsor_offers, public.site_settings, public.profiles, public.teams cascade;
drop function if exists public.handle_new_auth_user() cascade;
drop function if exists public.protect_profile_role() cascade;
drop function if exists public.validate_sponsor_order() cascade;
drop function if exists public.record_invoice_payment() cascade;
drop function if exists public.prevent_overdrawn_account() cascade;
drop function if exists public.set_updated_at() cascade;
drop function if exists public.current_app_role() cascade;
drop function if exists public.current_team_id() cascade;
drop function if exists public.is_admin() cascade;
drop function if exists public.request_invoice_payment(uuid) cascade;
drop function if exists public.respond_to_contract(uuid, boolean) cascade;
drop type if exists public.contract_type, public.contract_status, public.invoice_status, public.support_ticket_status, public.app_role cascade;

