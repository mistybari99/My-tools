\set ON_ERROR_STOP off
\set VERBOSITY terse
select set_config('request.jwt.claim.sub', :'u', false) \gset
set role authenticated;
select pg_advisory_lock_shared(7770001) \gset
select pg_advisory_unlock_shared(7770001) \gset
select 'A|'||coalesce(setup_recommend_apply('a4ae4e4b-4fe9-4b2b-8a7d-ad030542e523'::uuid)->>'dup','fresh')||'|'||(setup_recommend_apply('a4ae4e4b-4fe9-4b2b-8a7d-ad030542e523'::uuid)->>'count');
