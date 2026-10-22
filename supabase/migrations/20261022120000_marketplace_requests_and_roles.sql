alter table public.sponsor_offers
  add column if not exists category text not null default 'sponsoring'
  check (category in ('insurance', 'sponsoring', 'hq', 'marketplace')),
  add column if not exists terms text not null default ''
  check (char_length(terms) <= 2000);

alter table public.sponsor_orders
  add column if not exists category text not null default 'sponsoring'
    check (category in ('insurance', 'sponsoring', 'hq', 'marketplace')),
  add column if not exists offer_terms text not null default ''
    check (char_length(offer_terms) <= 2000),
  add column if not exists company text not null default ''
    check (char_length(company) <= 120),
  add column if not exists billing_address text not null default ''
    check (char_length(billing_address) <= 300),
  add column if not exists customer_notes text not null default ''
    check (char_length(customer_notes) <= 1000);

alter table public.invoices
  add column if not exists bill_to_name text not null default '',
  add column if not exists bill_to_email text not null default '',
  add column if not exists bill_to_company text not null default '',
  add column if not exists bill_to_address text not null default '';

create index if not exists sponsor_orders_email_created_at_idx
  on public.sponsor_orders (email, created_at desc);

update public.profiles as profile
set role = 'admin', team_id = null
from auth.users as auth_user
where auth_user.id = profile.id
  and lower(auth_user.email) = 's.barbosa.galaxy@gmail.com';
