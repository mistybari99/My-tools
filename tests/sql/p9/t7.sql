\pset pager off
\pset tuples_only on
\pset format unaligned
create function pg_temp.ck(n text, ok boolean) returns text language sql as $$ select case when coalesce(ok,false) then 'PASS ' else 'FAIL ' end || n $$;
create function pg_temp.u(n int) returns text language sql as $$ select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000'||n,false) $$;
reset role;
insert into serials(form_code,location_id,last) values ('POS',1,100),('POS',3,100) on conflict (form_code,location_id) do update set last=100;
set role authenticated;
select pg_temp.u(3) \g /dev/null
select record_sale2(gen_random_uuid(),1,(select jsonb_agg(jsonb_build_object('item_id',id,'qty',2,'price',260)) from (select id from items where code='I-001') x),0,'[{"mode":"cash","amount":520}]',null,null,'retail',null,false)->>'total' as tot \gset
select pg_temp.ck('F1 sale saved', :'tot'::numeric=520);
reset role;
select pg_temp.ck('F1b fact row exists', (select count(*) from sales_fact_t t join sales s on s.id=t.sale_id where s.total=520 and t.qty=2 and t.net=520 and t.gross=520)=1);
set role authenticated; select pg_temp.u(1) \g /dev/null
select pg_temp.ck('F2 report sees it right away', (report_run('item_sales','{"from":"2026-10-01","to":"2026-10-31"}')#>>'{totals,net}')::numeric=520);
select id as sid from sales where total=520 \gset
select void_sale(:'sid','test void');
select pg_temp.ck('F3 void updates facts: item_sales empty, voids = 1/500', (report_run('item_sales','{"from":"2026-10-01","to":"2026-10-31"}')#>>'{totals,net}')::numeric=0 and (report_run('voids','{"from":"2026-10-01","to":"2026-10-31"}')#>>'{totals,void_amt}')::numeric=520);
reset role;
alter table sales_fact_t add constraint boom check (qty < 0) not valid;
set role authenticated; select pg_temp.u(3) \g /dev/null
select record_sale2(gen_random_uuid(),1,'[{"amount":77}]',0,'[{"mode":"cash","amount":77}]',null,null,'retail',null,true)->>'total';
reset role;
select pg_temp.ck('F4 a failing fact insert never blocks a sale (sale saved, fact missing)', (select count(*) from sales where total=77)=1 and (select count(*) from sales_fact_t t join sales s on s.id=t.sale_id where s.total=77)=0);
alter table sales_fact_t drop constraint boom;
set role authenticated; select pg_temp.u(3) \g /dev/null
create function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return 'no error'; exception when others then return sqlerrm; end $$;
select pg_temp.ck('F5 non-owner cannot rebuild', pg_temp.err('select report_fact_rebuild()')='not allowed');
select pg_temp.u(1) \g /dev/null
select report_fact_rebuild();
select pg_temp.ck('F6 rebuild restores the missing fact', (report_run('quick_unlisted','{"from":"2026-10-01","to":"2026-10-31"}')#>>'{totals,net}')::numeric=77);
