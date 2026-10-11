\pset pager off
\pset tuples_only on
\pset format unaligned
create function pg_temp.ck(n text, ok boolean) returns text language sql as $$ select case when coalesce(ok,false) then 'PASS ' else 'FAIL ' end || n $$;
create function pg_temp.u(n int) returns text language sql as $$ select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000'||n,false) $$;
reset role;
insert into exceptions(entry_id,sale_id,form_code,location_id,entry_date,flag_code,level,amount,text) select null,id,'POS',1,'2026-09-09','discount_over_limit','red',100,'{}' from sales where receipt=3 and location_id=1;
set role authenticated; select pg_temp.u(1) \g /dev/null
with r as (select report_run('discounts','{"from":"2026-09-08","to":"2026-09-14"}') j)
select pg_temp.ck('D1 over-limit bills from exceptions (alice 1)', (select e->>'over_limit_bills' from jsonb_array_elements(j->'rows') e where e->>'staff'='alice')='1' and (j#>>'{totals,over_limit_bills}')='1') from r;
