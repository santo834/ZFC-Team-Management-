-- Neuer Vertragsstatus für von Teams eingereichte Fahrerverträge (Finanzüberprüfung).
-- Muss in einer eigenen Migration vor der ersten Verwendung des Werts laufen.
alter type public.contract_status add value if not exists 'in_review';
