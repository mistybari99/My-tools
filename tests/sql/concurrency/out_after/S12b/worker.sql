\set ON_ERROR_STOP off
\set VERBOSITY terse
select set_config('request.jwt.claim.sub', :'u', false) \gset
set role authenticated;
select pg_advisory_lock_shared(7770001) \gset
select pg_advisory_unlock_shared(7770001) \gset
select 'B|'||coalesce(setup_recommend_apply(gen_random_uuid())->>'count','?');
