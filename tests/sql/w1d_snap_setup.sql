-- W1-D before/after: extra records on top of tests/sql/w1d_fixture.sql so that EVERY W1-D setting has something to change when it is switched on.
--   a payroll run of 8000 (paid) AND a 02-2 sheet of 7000 for the same month (the sheet becomes its shadow), a submitted-only 10-2 voucher of 200, a partner agreement for place 1.
\set ON_ERROR_STOP on
\set o '00000000-0000-0000-0000-000000000092'
select set_config('request.jwt.claim.sub', :'o', false);
select (now() at time zone 'Asia/Dhaka')::date as td \gset
select date_trunc('month', :'td'::date - interval '1 month')::date as pm \gset
select extract(month from :'pm'::date)::int as pmm, extract(year from :'pm'::date)::int as pyy \gset
insert into employees (employee_no, full_name_bn, status, primary_location_id) values ('TESTBA_W','test_emp','active',1) returning id as ea \gset
with x as (insert into payroll_runs (month, location_id, status) values (:'pm', 1, 'draft') returning id) select id as run1 from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run1', :'pm', :'ea', 1, 8000, 8000) returning id) select id as l1 from x \gset
select payroll_approve(:'run1'::bigint) ->> 'status' as ap \gset
select payroll_pay(:'run1'::bigint, array[:'l1'::bigint], 'bank', :'td'::date, 'w1d-sal', null, gen_random_uuid(), null) is not null as pp \gset
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
  ('02-2',1,93001,:'pm'::date + 2,'approved',format('{"month":"%s","year":"%s","pay":[{"name":"test_emp","due":"7000","overtime":"0","other":"0"}],"receipts":[]}',:'pmm',:'pyy')::jsonb,'[]',:'o','t');
select save_entry(null,'10-2',1,:'td'::date,'{"lines":[{"head":"transport","amount":"200"}]}'::jsonb,'[]') ->> 'id' as v2 \gset
select submit_entry(:'v2'::uuid) is not null as s2 \gset
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by) values
  (1, 93101, :'pm'::date + 5, now(), '[]', 1000, 0, 1000, 'cash', 'done', :'o');
select partner_party_save(null,'test_p_owner','company',null,null,null,null,null,null,true,gen_random_uuid()) ->> 'id' as pa \gset
select partner_party_save(null,'test_p_inv','individual',null,null,null,null,null,null,true,gen_random_uuid()) ->> 'id' as pb \gset
select partner_venture_save(null,'test venture','test venture','location',1,'own','2020-01-01',null,'draft',null,gen_random_uuid()) ->> 'id' as v1 \gset
select (partner_agreement_save(null, :v1::bigint, 'test deed', '2020-01-01', null, '[]'::jsonb, null, gen_random_uuid()) ->> 'id')::bigint as ag \gset
select partner_agreement_party_set(:ag, :pa::bigint, 'owner', 60, null) is not null as x1 \gset
select partner_agreement_party_set(:ag, :pb::bigint, 'investor', 40, null) is not null as x2 \gset
select partner_rule_save(:ag, null, 'Base', 'base', '{"base":"net_profit_before_fees"}'::jsonb) is not null as r1 \gset
select partner_rule_save(:ag, null, 'Split', 'split', '{"shares":[{"role":"owner","percent":60},{"role":"investor","percent":40}]}'::jsonb) is not null as r2 \gset
select partner_agreement_activate(:ag, true) is not null as act \gset
create table if not exists tt.kv (k text primary key, v text);
insert into tt.kv values ('ag', :'ag'::text) on conflict (k) do update set v = excluded.v;
select acct_post_pending(false) ->> 'posted' as posted \gset
select :'posted' as posted;
