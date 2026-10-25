\set ON_ERROR_STOP off
\set VERBOSITY terse
select set_config('request.jwt.claim.sub', :'u', false) \gset
set role authenticated;
select pg_advisory_lock_shared(7770001) \gset
select pg_advisory_unlock_shared(7770001) \gset
select 'C|'||coalesce(card_settle(1,(now() at time zone 'Asia/Dhaka')::date,600,12,'batch','0aa35f24-fdc6-4ef7-a5ad-c79f69c7c01e'::uuid)->>'dup','fresh');
