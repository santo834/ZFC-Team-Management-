create or replace function public.respond_to_contract(
  p_contract_id uuid,
  p_accept boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  requester_role public.app_role;
begin
  requester_role := (select public.current_app_role());

  if requester_role is distinct from 'admin'::public.app_role
     and requester_role is distinct from 'team_chief'::public.app_role then
    raise exception 'Admin or team-chief access required';
  end if;

  update public.contracts
  set status = case when p_accept then 'signed'::public.contract_status
                    else 'declined'::public.contract_status
      end,
      accepted_at = case when p_accept then pg_catalog.now() else null end
  where id = p_contract_id
    and status = 'pending'
    and (
      requester_role = 'admin'::public.app_role
      or team_id = (select public.current_team_id())
    );

  if not found then
    raise exception 'Contract not found or response is not allowed';
  end if;
end;
$$;
