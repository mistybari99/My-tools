\set ON_ERROR_STOP off
\set VERBOSITY terse
select set_config('request.jwt.claim.sub', :'u', false) \gset
set role authenticated;
select pg_advisory_lock_shared(7770001) \gset
select pg_advisory_unlock_shared(7770001) \gset
select 'R|'||coalesce(production_post(1,'d26271a8-73bf-4299-8670-f24e369f8af2',1,gen_random_uuid())->>'run_id','null');
