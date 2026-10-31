-- Öffentliche Angebote erhalten ein Marken-Bild (Logo) neben dem freien Bild
-- sowie strukturierte Details für die neue Detailseite (Tagline, Badge, Laufzeit,
-- Deckung, Region, Ziele, Optionen, Partnerschaftstext, Über-Bereich, Vorteile,
-- Statistiken, Produkte, Button-Text).
alter table public.sponsor_offers
  add column if not exists logo_path text,
  add column if not exists details jsonb not null default '{}'::jsonb
    check (jsonb_typeof(details) = 'object');
