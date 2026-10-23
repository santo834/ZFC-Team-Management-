update public.teams
set name = case id
  when 'summit-gp' then 'BWT Alpine F1 Team'
  when 'atlas-competition' then 'Aston Martin Aramco F1 Team'
  when 'cobalt-works' then 'Audi F1 Team'
  when 'cadillac' then 'Cadillac F1 Team'
  when 'scuderia-rosso' then 'Scuderia Ferrari HP'
  when 'ironclad-racing' then 'TGR Haas F1 Team'
  when 'veloce-racing' then 'McLaren F1 Team'
  when 'apex-motorsport' then 'Mercedes-AMG PETRONAS F1 Team'
  when 'pulse-motorsport' then 'Visa Cash App Racing Bulls F1 Team'
  when 'northstar-gp' then 'Oracle Red Bull Racing'
  when 'vector-racing' then 'Atlassian Williams F1 Team'
end
where id in (
  'summit-gp', 'atlas-competition', 'cobalt-works', 'cadillac',
  'scuderia-rosso', 'ironclad-racing', 'veloce-racing', 'apex-motorsport',
  'pulse-motorsport', 'northstar-gp', 'vector-racing'
);

drop policy if exists "Admins update account entries" on public.account_entries;
create policy "Admins update account entries"
  on public.account_entries for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

grant update (
  team_id, invoice_number, description, amount_cents, due_date, status,
  reference, bill_to_name, bill_to_email, bill_to_company, bill_to_address
) on public.invoices to authenticated;
grant update (team_id, direction, amount_cents, description)
  on public.account_entries to authenticated;
grant update (
  team_id, type, title, terms, starts_on, ends_on, status
) on public.contracts to authenticated;
