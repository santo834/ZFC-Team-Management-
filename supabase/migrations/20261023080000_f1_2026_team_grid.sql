-- Keep existing team IDs so profiles and account records remain linked.
update public.teams
set
  name = case id
    when 'summit-gp' then 'Alpine'
    when 'atlas-competition' then 'Aston Martin'
    when 'cobalt-works' then 'Audi'
    when 'scuderia-rosso' then 'Ferrari'
    when 'ironclad-racing' then 'Haas'
    when 'veloce-racing' then 'McLaren'
    when 'apex-motorsport' then 'Mercedes'
    when 'pulse-motorsport' then 'Racing Bulls'
    when 'northstar-gp' then 'Red Bull Racing'
    when 'vector-racing' then 'Williams'
  end,
  color = case id
    when 'summit-gp' then '#0093cc'
    when 'atlas-competition' then '#00594f'
    when 'cobalt-works' then '#d1001f'
    when 'scuderia-rosso' then '#dc0000'
    when 'ironclad-racing' then '#9da3a8'
    when 'veloce-racing' then '#ff8700'
    when 'apex-motorsport' then '#00d2be'
    when 'pulse-motorsport' then '#6692ff'
    when 'northstar-gp' then '#1e41ff'
    when 'vector-racing' then '#005aff'
  end
where id in (
  'summit-gp', 'atlas-competition', 'cobalt-works', 'scuderia-rosso',
  'ironclad-racing', 'veloce-racing', 'apex-motorsport',
  'pulse-motorsport', 'northstar-gp', 'vector-racing'
);

insert into public.teams (id, name, color)
values ('cadillac', 'Cadillac', '#c8a95b')
on conflict (id) do update
set name = excluded.name, color = excluded.color;
