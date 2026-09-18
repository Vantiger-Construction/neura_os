-- The Supabase-managed helper is an administrative event trigger, not a client API.
-- Some local/self-hosted environments do not install it; keep fresh setups portable.
do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
  end if;
end;
$$;
