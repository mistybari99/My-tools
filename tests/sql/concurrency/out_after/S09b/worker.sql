\set ON_ERROR_STOP off
\set VERBOSITY terse
select set_config('request.jwt.claim.sub', :'u', false) \gset
set role authenticated;
select pg_advisory_lock_shared(7770001) \gset
select pg_advisory_unlock_shared(7770001) \gset
select 'S|'||coalesce(scan_confirm(('00000000-0000-0000-0000-0000000000'||lpad(:i::text,2,'0'))::uuid, ('00000000-0000-0000-0000-0000000001'||lpad(:i::text,2,'0'))::uuid, true, true)->'result'->'posted'->>'status','?');
