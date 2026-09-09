-- Ensure the atomic wallet balance RPC exists in projects that skipped or
-- partially applied the original wallet-fees migration.

create or replace function public.adjust_wallet_balance(
  _user_id uuid,
  _account_type public.account_type,
  _usd_delta numeric,
  _ksh_delta numeric default 0
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  _profile public.profiles;
begin
  if current_setting('role', true) <> 'service_role' and auth.uid() <> _user_id then
    raise exception 'Unauthorized';
  end if;

  select * into _profile
  from public.profiles
  where id = _user_id
  for update;

  if _profile.id is null then
    raise exception 'Profile not found';
  end if;

  if _account_type = 'real' then
    if _profile.balance_usd + _usd_delta < 0 then
      raise exception 'Insufficient balance';
    end if;

    update public.profiles
    set balance_usd = balance_usd + _usd_delta,
        balance_ksh = balance_ksh + _ksh_delta,
        updated_at = now()
    where id = _user_id
    returning * into _profile;
  else
    if _profile.demo_balance_usd + _usd_delta < 0 then
      raise exception 'Insufficient balance';
    end if;

    update public.profiles
    set demo_balance_usd = demo_balance_usd + _usd_delta,
        balance_ksh = balance_ksh + _ksh_delta,
        updated_at = now()
    where id = _user_id
    returning * into _profile;
  end if;

  return _profile;
end;
$$;

revoke all on function public.adjust_wallet_balance(uuid, public.account_type, numeric, numeric) from public;
grant execute on function public.adjust_wallet_balance(uuid, public.account_type, numeric, numeric) to service_role;

notify pgrst, 'reload schema';
