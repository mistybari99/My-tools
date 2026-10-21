\set ON_ERROR_STOP off
\set VERBOSITY terse
select set_config('request.jwt.claim.sub', :'u', false) \gset
set role authenticated;
select pg_advisory_lock_shared(7770001) \gset
select pg_advisory_unlock_shared(7770001) \gset
select 'A|'||coalesce(setup_recommend_apply('800afb46-959a-485d-8a33-d362c11a8b3f'::uuid)->>'dup','fresh')||'|'||(setup_recommend_apply('800afb46-959a-485d-8a33-d362c11a8b3f'::uuid)->>'count');
