-- phase 478: the small helper functions (_..._present, _w1*_ checks and triggers) may not be called by the signed-out role (anon).
-- They only answer "is that phase pasted?" / "is this status text allowed?" and are harmless, but nothing outside a signed-in session needs them, and they were open to anon only because a new function is open to everybody until revoked.
-- Signed-in people (authenticated), the owner paths, the service role and the database owner keep EXECUTE, so every screen, trigger, _i2_state() and phase 477 work as before.
-- Safe to paste twice. Changes no table, no figure, no setting.
do $$
declare
  f regprocedure;
  n int := 0;
begin
  for f in
    select p.oid::regprocedure
    from pg_proc p join pg_namespace s on s.oid = p.pronamespace
    where s.nspname = 'public'
      and (p.proname ~ '^_[a-z0-9]+_present[0-9]*$' or p.proname ~ '^_w1[a-z]*_')
      and has_function_privilege('anon', p.oid, 'execute')      -- only what anon can still run today; functions an earlier phase already closed to everybody stay closed
  loop
    execute format('revoke execute on function %s from public, anon', f);
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
      execute format('grant execute on function %s to authenticated', f);
    end if;
    if exists (select 1 from pg_roles where rolname = 'service_role') then
      execute format('grant execute on function %s to service_role', f);
    end if;
    n := n + 1;
  end loop;
  raise notice 'phase478: % helper functions closed to anon', n;
end $$;
