-- FRESH DB ONLY. Phase 92 tests (Step Inv: invoice on screen after a sale; rule pos_show_invoice_after_sale; append-only invoice_shares; invoice_data92 without cost).
--   ORDER="phase8 ... phase88" bash <copy of tests/sql/build_fresh_db.sh with your worktree paths> a92db ; psql ... -d a92db -f supabase/phase92.sql
--   psql -h /tmp -p 5544 -U postgres -d a92db -qAt -f supabase/phase92_test.sql | grep -E 'FAIL|RESULT'      (run from the repo root: it \i's phase92.sql again)
-- Numbers are hand-computed (comment above each block). Test data only, no person names. Place 1 (main) and place 2.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set v '00000000-0000-0000-0000-000000000003'
\set m '00000000-0000-0000-0000-000000000004'
\set x '00000000-0000-0000-0000-000000000005'
\set y '00000000-0000-0000-0000-000000000006'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','sales2@s.app','{"full_name":"Seller"}'), (:'v','sales3@s.app','{"full_name":"Other Seller"}'),
 (:'m','mgr4@s.app','{"full_name":"Manager"}'), (:'x','norole5@s.app','{"full_name":"No Role"}'), (:'y','sales6@s.app','{"full_name":"Branch Seller"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','salesperson'),(:'v','salesperson'),(:'m','showroom_manager'),(:'y','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1),(:'v',1),(:'m',1),(:'y',2) on conflict do nothing;
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type,vat_applicable) values ('কেক','Cake','pc','pc',100,false,'resale',true) returning id) select id as ia from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type,vat_applicable) values ('আম','Mango','pc','pc',80,false,'resale',false) returning id) select id as ib from i \gset
-- a secret cost exists for the item: it must never show up in the invoice
insert into item_costs (item_id, cost_price) values (:'ia', 63.37) on conflict (item_id) do update set cost_price = excluded.cost_price;

\echo == T0 shape
select tt.chk('T0 rule exists: pos module, choice never|ask|always, default never = today''s behaviour',
  (select kind='choice' and module='pos' and choices='["never","ask","always"]'::jsonb and default_value='"never"'::jsonb from rules where key='pos_show_invoice_after_sale') and rule_txt('pos_show_invoice_after_sale') = 'never');
select tt.chk('T0 rule has all three languages and the recommendation text',
  (select label_bn is not null and label_mix is not null and label_en is not null and hint_en ilike '%recommended: always%' and hint_bn like '%সুপারিশ%' and hint_mix ilike '%Recommended%' from rules where key='pos_show_invoice_after_sale'));
select tt.chk('T0 table closed to the browser (no grant, RLS on); functions open to signed-in only',
  (select relrowsecurity from pg_class where relname='invoice_shares') and not has_table_privilege('authenticated','public.invoice_shares','select') and not has_table_privilege('authenticated','public.invoice_shares','insert')
  and not has_table_privilege('anon','public.invoice_shares','select')
  and has_function_privilege('authenticated','public.invoice_data92(uuid,uuid)','execute') and has_function_privilege('authenticated','public.invoice_share_log92(uuid,text,uuid)','execute')
  and not has_function_privilege('anon','public.invoice_data92(uuid,uuid)','execute') and not has_function_privilege('anon','public.invoice_share_log92(uuid,text,uuid)','execute'));
select tt.chk('T0 invoice_shares has no cost / recipient column', not exists (select 1 from information_schema.columns where table_name='invoice_shares' and (column_name ~* 'cost|mobile|phone|email|number')));

\echo == setup: two sales
set role authenticated; select tt.as(:'o');
select set_rule('pos_discount_manager','false') is null as dm \gset      -- a plain seller may give the small discount of this fixture
select tt.as(:'s');
-- Sale A by Seller (place 1): Cake 2 x 100 = 200, Mango 1 x 80 = 80, subtotal 280, discount 28 (10 pct via amount), total 252, cash 252. Customer with a mobile.
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":100},{"item_id":"%s","qty":1,"price":80}]',:'ia',:'ib')::jsonb,28,'[{"mode":"cash","amount":252}]','01711000001','Test Buyer','retail',null,false)->>'id' as sa \gset
-- Sale B by Seller: quick sale 50 cash, no customer
select record_sale2(gen_random_uuid(),1,'[{"item_id":null,"name":"Quick sale","amount":50}]'::jsonb,0,'[{"mode":"cash","amount":50}]',null,null,'retail',null,true)->>'id' as sb \gset
reset role;
select tt.chk('setup sales exist', :'sa' is not null and :'sb' is not null);

\echo == D1 invoice_data92 content (hand numbers: subtotal 280, discount 28, total 252, paid 252, due 0)
set role authenticated; select tt.as(:'s');
select invoice_data92(:'sa'::uuid) as da \gset
select tt.chk('D1 header + totals', (:'da'::jsonb->>'subtotal')::numeric=280 and (:'da'::jsonb->>'discount')::numeric=28 and (:'da'::jsonb->>'total')::numeric=252 and (:'da'::jsonb->>'paid')::numeric=252
  and (:'da'::jsonb->>'due')::numeric=0 and :'da'::jsonb->>'status'='done' and :'da'::jsonb->>'cashier'<>'' and :'da'::jsonb->>'location_code'='main');
select tt.chk('D1 two lines in order with qty / price / amount and English names', jsonb_array_length(:'da'::jsonb->'lines')=2
  and (:'da'::jsonb->'lines'->0->>'qty')::numeric=2 and (:'da'::jsonb->'lines'->0->>'price')::numeric=100 and (:'da'::jsonb->'lines'->0->>'amount')::numeric=200 and :'da'::jsonb->'lines'->0->>'name_en'='Cake'
  and (:'da'::jsonb->'lines'->1->>'amount')::numeric=80 and :'da'::jsonb->'lines'->1->>'name_en'='Mango');
select tt.chk('D1 payment: one cash line of 252', jsonb_array_length(:'da'::jsonb->'payments')=1 and :'da'::jsonb->'payments'->0->>'mode'='cash' and (:'da'::jsonb->'payments'->0->>'amount')::numeric=252);
select tt.chk('D1 NO cost anywhere: no key containing cost, the secret 63.37 absent, only whitelisted line keys',
  :'da' !~* 'cost' and :'da' !~ '63\.37' and (select bool_and(k in ('item_id','code','name','name_en','name_mix','unit','qty','price','amount','custom')) from jsonb_array_elements(:'da'::jsonb->'lines') l, jsonb_object_keys(l) k));
select tt.chk('D1 VAT is null while the VAT switch is off', :'da'::jsonb->'vat' = 'null'::jsonb);
select tt.chk('D1 creator sees the customer mobile', :'da'::jsonb->'customer'->>'mobile'='01711000001' and :'da'::jsonb->'customer'->>'name'='Test Buyer' and (:'da'::jsonb->'customer'->>'masked')::boolean = false);
select tt.chk('D1 no-customer sale returns customer null', invoice_data92(:'sb'::uuid)->'customer' = 'null'::jsonb and (invoice_data92(:'sb'::uuid)->>'total')::numeric=50);
select tt.chk('D1 lookup by client id works for the creator', (invoice_data92(null, (select client_id from sales where id=:'sa'::uuid)))->>'id' = :'sa');
select tt.chk('D1 shares list hidden from a plain seller', :'da'::jsonb->'shares' = '[]'::jsonb);
reset role;

\echo == D2 privacy of the customer mobile
set role authenticated; select tt.as(:'v');
select tt.chk('D2 other seller (same place, did not make the sale): name yes, mobile masked', invoice_data92(:'sa'::uuid)->'customer'->>'name'='Test Buyer' and invoice_data92(:'sa'::uuid)->'customer'->>'mobile' is null
  and (invoice_data92(:'sa'::uuid)->'customer'->>'masked')::boolean);
reset role;
set role authenticated; select tt.as(:'v');
select tt.err('D2 client-id lookup of someone else''s sale is not_found', format('select invoice_data92(null, %L::uuid)', (select client_id from sales where id=:'sa'::uuid)), 'not_found');
select tt.as(:'m');
select tt.chk('D2 POS approve (manager) sees the mobile', invoice_data92(:'sa'::uuid)->'customer'->>'mobile'='01711000001');
select tt.as(:'o');
select tt.chk('D2 owner sees the mobile', invoice_data92(:'sa'::uuid)->'customer'->>'mobile'='01711000001');
reset role;

\echo == D3 who may open it
set role authenticated;
select tt.as(:'x'); select tt.err('D3 user without POS rights is refused', format('select invoice_data92(%L::uuid)', :'sa'), 'not allowed');
select tt.err('D3 same for the log call', format('select invoice_share_log92(%L::uuid, %L)', :'sa', 'print'), 'not allowed');
select tt.as(:'y'); select tt.err('D3 seller of another place is refused', format('select invoice_data92(%L::uuid)', :'sa'), 'not allowed for this location');
select tt.as(:'s'); select tt.err('D3 missing id', 'select invoice_data92()', 'no_sale');
select tt.err('D3 unknown id', format('select invoice_data92(%L::uuid)', gen_random_uuid()), 'not_found');
reset role;

\echo == L1 the audited log
set role authenticated; select tt.as(:'s');
select invoice_share_log92(:'sa'::uuid, 'print') as l1 \gset
select invoice_share_log92(:'sa'::uuid, 'whatsapp') as l2 \gset
select invoice_share_log92(null, 'sms', (select client_id from sales where id=:'sa'::uuid)) as l3 \gset
select invoice_share_log92(:'sa'::uuid, 'email') as l4 \gset
select invoice_share_log92(:'sa'::uuid, 'share') as l5 \gset
select tt.err('L1 an unknown channel is refused', format('select invoice_share_log92(%L::uuid, %L)', :'sa', 'fax'), 'bad_channel');
select tt.err('L1 an empty channel is refused', format('select invoice_share_log92(%L::uuid)', :'sa'), 'bad_channel');
select tt.err('L1 plain staff cannot read the table directly', 'select count(*) from public.invoice_shares', 'permission denied');
select tt.err('L1 plain staff cannot insert directly', format('insert into public.invoice_shares (sale_id, channel) values (%L, %L)', :'sa', 'print'), 'permission denied');
reset role;
select tt.chk('L1 five rows, right channels, who and when recorded, place filled', (select count(*)=5 and count(*) filter (where channel='print')=1 and count(*) filter (where channel='whatsapp')=1 and count(*) filter (where channel='sms')=1
  and count(*) filter (where channel='email')=1 and bool_and(by_staff is not null and by_user=:'s'::uuid and at is not null and location_id=1) from invoice_shares where sale_id=:'sa'::uuid));
select tt.chk('L1 every audit row is in audit_log', (select count(*) from audit_log where table_name='invoice_shares')>=5);
select tt.err('L1 append-only: update refused', 'update public.invoice_shares set channel = ''copy'' where id = 1', 'append-only');
select tt.err('L1 append-only: delete refused', 'delete from public.invoice_shares', 'append-only');
select tt.err('L1 append-only: truncate refused', 'truncate public.invoice_shares', 'append-only');
select tt.chk('L1 still five rows after the attempts', (select count(*) from invoice_shares)=5);

\echo == L2 the log is visible to owner and approvers only, inside the invoice
set role authenticated; select tt.as(:'m');
select tt.chk('L2 manager sees 5 share entries, newest first, no recipient field', jsonb_array_length(invoice_data92(:'sa'::uuid)->'shares')=5 and (invoice_data92(:'sa'::uuid)->'shares'->0) ?& array['channel','by','at']
  and (select count(*) from jsonb_object_keys(invoice_data92(:'sa'::uuid)->'shares'->0))=3);
select tt.as(:'o'); select tt.chk('L2 owner too', jsonb_array_length(invoice_data92(:'sa'::uuid)->'shares')=5);
select tt.as(:'s'); select tt.chk('L2 the seller does not', invoice_data92(:'sa'::uuid)->'shares' = '[]'::jsonb);
reset role;

\echo == V1 VAT (Cake 100 VAT-applicable x2 = 200, Mango not; discount share 252/280 = 0.9; taxable 180)
set role authenticated; select tt.as(:'o');
select set_rule('vat_on','true') is null as r1 \gset
select set_rule('vat_rate','5') is null as r2 \gset
select set_rule('vat_prices_include','false') is null as r2b \gset
select tt.chk('V1 VAT on, prices not included: 5 pct of 180 = 9.00', (invoice_data92(:'sa'::uuid)->'vat'->>'amount')::numeric=9 and (invoice_data92(:'sa'::uuid)->'vat'->>'taxable')::numeric=180 and (invoice_data92(:'sa'::uuid)->'vat'->>'included')::boolean=false);
select set_rule('vat_prices_include','true') is null as r3 \gset
select tt.chk('V1 prices included: 180 x 5/105 = 8.57', (invoice_data92(:'sa'::uuid)->'vat'->>'amount')::numeric=8.57 and (invoice_data92(:'sa'::uuid)->'vat'->>'included')::boolean);
select tt.chk('V1 sale with no VAT-applicable line: 0', (invoice_data92(:'sb'::uuid)->'vat'->>'amount')::numeric=0);
select set_rule('vat_on','false') is null as r4 \gset
select tt.chk('V1 switch off again: no VAT block', invoice_data92(:'sa'::uuid)->'vat' = 'null'::jsonb);
reset role;

\echo == R1 the rule values
set role authenticated; select tt.as(:'o');
select set_rule('pos_show_invoice_after_sale','"always"') is null as q1 \gset
select tt.chk('R1 owner can set always', rule_txt('pos_show_invoice_after_sale')='always');
select tt.err('R1 a value outside the choices is refused', 'select set_rule(''pos_show_invoice_after_sale'', ''"sometimes"'')', '');
select tt.as(:'s'); select tt.err('R1 plain staff cannot change it', 'select set_rule(''pos_show_invoice_after_sale'', ''"never"'')', '');
reset role;

\echo == P1 paste-twice and no change to older things
\i supabase/phase92.sql
select tt.chk('P1 second paste: rule value kept (always), one row, log rows kept', rule_txt('pos_show_invoice_after_sale')='always' and (select count(*) from rules where key='pos_show_invoice_after_sale')=1 and (select count(*) from invoice_shares)=5);
select tt.chk('P1 record_sale2 and record_sale_offline definitions untouched (no bos92 tag in them)', position('bos92' in pg_get_functiondef('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamptz,text,numeric)'::regprocedure))=0);
select tt.chk('P1 new functions carry no cost reads', position('item_costs' in pg_get_functiondef('public.invoice_data92(uuid,uuid)'::regprocedure))=0 and position('stock_ledger' in pg_get_functiondef('public.invoice_data92(uuid,uuid)'::regprocedure))=0
  and position('unit_cost' in pg_get_functiondef('public.invoice_data92(uuid,uuid)'::regprocedure))=0);

select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
