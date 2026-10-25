\set ON_ERROR_STOP off
\set VERBOSITY terse
select set_config('request.jwt.claim.sub', :'u', false) \gset
set role authenticated;
select pg_advisory_lock_shared(7770001) \gset
select pg_advisory_unlock_shared(7770001) \gset
select 'R|'||coalesce(production_post(1,'fc2c41fd-7010-4bd5-a1aa-2055525bc014',1,gen_random_uuid())->>'run_id','null');
