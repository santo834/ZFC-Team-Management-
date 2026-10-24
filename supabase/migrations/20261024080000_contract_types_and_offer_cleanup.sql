alter type public.contract_type add value if not exists 'driver';
alter type public.contract_type add value if not exists 'team_principal';
alter type public.contract_type add value if not exists 'driver_purchase';

-- Allow offers to be deleted for good; existing requests keep their offer name and price.
alter table public.sponsor_orders alter column offer_id drop not null;
alter table public.sponsor_orders drop constraint if exists sponsor_orders_offer_id_fkey;
alter table public.sponsor_orders
  add constraint sponsor_orders_offer_id_fkey
  foreign key (offer_id) references public.sponsor_offers (id) on delete set null;
