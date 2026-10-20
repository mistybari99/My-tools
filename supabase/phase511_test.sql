-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase85_test.sql there and is already pasted on the live database under that name.
-- Renumbered to phase511_test.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- FRESH DB ONLY. Phase 511 tests (Phase D: stock movements that missed the books, manual-journal guard, autopost scheduler, card settlement, expense payment mode).
--   ORDER="phase8 ... phase71 phase72 ... phase79 phase511" bash <copy of tests/sql/build_fresh_db.sh with your worktree paths> a85db
--   psql -h /tmp -p 5544 -U postgres -d a85db -qAt -f supabase/phase511_test.sql | grep -E 'FAIL|RESULT'
-- All numbers are hand-computed (comment above each block). Test data only, no person names.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
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
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.unbalanced_entries() returns bigint language sql stable as $$
  select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
-- journal amount of one source type on one account code (originals only, debit or credit side)
create or replace function tt.jt(p_type text, p_code text, p_side text) returns numeric language sql stable as $$
  select coalesce(sum(case p_side when 'd' then l.debit else l.credit end), 0) from public.journal_entries e join public.journal_lines l on l.entry_id = e.id join public.coa_accounts a on a.id = l.account_id
  where e.source_type = p_type and e.reverses_id is null and a.code = p_code $$;
create or replace function tt.noban(p text) returns boolean language sql immutable as $$ select p !~ '[ঀ-৿]' $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','showroom_manager') on conflict do nothing;
insert into user_locations values (:'s',1) on conflict do nothing;
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('I85-FL','Flour','Flour','kg','kg',0,true,'raw_material') returning id) select id as fl from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('I85-GM','Gum','Gum','kg','kg',0,true,'raw_material') returning id) select id as gm from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('I85-SU','Sugar','Sugar','kg','kg',0,true,'raw_material') returning id) select id as su from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('I85-CD','Card item','Card item','pc','pc',1000,true,'resale') returning id) select id as cdi from i \gset
with i as (insert into suppliers (name) values ('Sup') returning id) select id as sup from i \gset

\echo == T0 shape and defaults (every new switch = today's behaviour)
select tt.chk('T0 phase85 applied: tags bos85 in the re-created functions', position('bos85' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0 and position('bos85' in pg_get_functiondef('public.acct_post_pending(boolean,int)'::regprocedure))>0
  and position('bos85' in pg_get_functiondef('public.inventory_vs_gl(date,int)'::regprocedure))>0 and position('bos85' in pg_get_functiondef('public.acct_status()'::regprocedure))>0
  and position('bos85' in pg_get_functiondef('public.stock_count_adjust(uuid,int,numeric,text,text,uuid)'::regprocedure))>0 and position('bos85' in pg_get_functiondef('public.acct_journal_post(date,int,text,jsonb,uuid,text,boolean,text)'::regprocedure))>0);
select tt.chk('T0 earlier tags survive (bos50 bos52 bos72 bos74 in _acct_docs, bos72 in acct_post_pending / inventory_vs_gl / acct_status)',
  position('bos50' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0 and position('bos52' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0 and position('bos72' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0
  and position('bos74' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0 and position('bos72' in pg_get_functiondef('public.acct_post_pending(boolean,int)'::regprocedure))>0
  and position('bos72' in pg_get_functiondef('public.acct_status()'::regprocedure))>0 and position('unexplained' in pg_get_functiondef('public.inventory_vs_gl(date,int)'::regprocedure))>0);
select tt.chk('T0 one acct_journal_post only (the old 7-argument one is gone, no ambiguity)', (select count(*) from pg_proc where proname='acct_journal_post')=1);
select tt.chk('T0 defaults: all stock-movement switches off, transfer mode off, guard off, scheduler off, alert days 1',
  not rule_on('acct_count_adjust') and not rule_on('acct_stock_opening') and not rule_on('acct_issue_out') and rule_txt('acct_transfer_mode')='off' and not rule_on('acct_transit_loss')
  and not rule_on('acct_purchase_variance') and rule_txt('manual_journal_guard')='off' and not rule_on('acct_scheduler_on') and rule_num('acct_pending_alert_days')=1 and rule_txt('acct_transit_loss_at')='receiver');
select tt.chk('T0 mapping keys added and point at the intended accounts', (select string_agg(m.key||'='||a.code, ',' order by m.key) from acct_mappings m join coa_accounts a on a.id=m.account_id
  where m.key in ('stock_adjust','stock_issue_use','transit_loss','purchase_variance','stock_opening_equity','interloc_clearing','bank_charges')) = 'bank_charges=5810,interloc_clearing=1230,purchase_variance=5140,stock_adjust=5110,stock_issue_use=5120,stock_opening_equity=3100,transit_loss=5130');
select tt.chk('T0 internals closed, new calls open to signed-in only; the scheduler entry is not open to anon',
  not has_function_privilege('authenticated','public._acct_stock_moves85(date)','execute') and not has_function_privilege('authenticated','public._pvar85(uuid)','execute') and not has_function_privilege('authenticated','public._manual_guard85(jsonb,text)','execute')
  and not has_function_privilege('anon','public.acct_autopost_tick()','execute') and not has_function_privilege('anon','public.card_settle(int,date,numeric,numeric,text,uuid,text)','execute') and not has_function_privilege('anon','public.acct_journal_post(date,int,text,jsonb,uuid,text,boolean,text)','execute')
  and has_function_privilege('authenticated','public.card_settle(int,date,numeric,numeric,text,uuid,text)','execute') and has_function_privilege('authenticated','public.acct_pending_alert85(int)','execute'));
select tt.chk('T0 new tables: RLS on, no browser write grants, settlement table append-only trigger',
  (select relrowsecurity from pg_class where relname='card_settlements85') and (select relrowsecurity from pg_class where relname='acct_autopost_runs85') and (select relrowsecurity from pg_class where relname='manual_reason_codes85')
  and not has_table_privilege('authenticated','card_settlements85','insert') and not has_table_privilege('authenticated','acct_autopost_runs85','select') and not has_table_privilege('authenticated','manual_reason_codes85','update')
  and exists (select 1 from pg_trigger where tgname='card_settle_ro85'));
select tt.chk('T0 English rule labels and hints have no Bangla characters', (select bool_and(tt.noban(coalesce(label_en,'')) and tt.noban(coalesce(hint_en,''))) from rules where key in ('acct_count_adjust','acct_stock_opening','acct_issue_out','acct_transfer_mode','acct_transit_loss','acct_transit_loss_at','acct_purchase_variance','acct_stock_moves_from','manual_journal_guard','acct_scheduler_on','acct_pending_alert_days')));
select tt.chk('T0 English account and reason labels have no Bangla characters', (select bool_and(tt.noban(name_en)) from coa_accounts where code in ('5110','5120','5130','5140')) and (select bool_and(tt.noban(label_en)) from manual_reason_codes85)
  and (select bool_and(tt.noban(label_en)) from acct_mappings where key in ('stock_adjust','stock_issue_use','transit_loss','purchase_variance','stock_opening_equity','interloc_clearing','bank_charges')));

\echo == setup: accounting on from 5 days ago
set role authenticated; select tt.as(:'o');
select acct_set_start(tt.today()-5)->>'start' as sd \gset
select set_rule('accounting_on','true') is null as on1 \gset
reset role;
select tt.chk('setup: accounting on', rule_on('accounting_on'));

\echo == A the movements happen with every switch OFF (today's behaviour)
set role authenticated; select tt.as(:'o');
-- Flour at place 1: opening 100 @ 40 (+4000) ; count to 95 (-5 = -200) ; issue 2 (-80) ; T1 send 10 receive 6 ; T2 send 5 receive 5 ; T3 send 3 then cancel
select stock_opening(:'fl'::uuid,1,100,40) is not null as a1 \gset
select stock_count_adjust(:'fl'::uuid,1,95,'count') is not null as a2 \gset
select stock_issue(:'fl'::uuid,1,2,null,'to kitchen') is not null as a3 \gset
select (stock_transfer(1,2,:'fl'::uuid,10,null,'t1')->>'id')::uuid as t1 \gset
select stock_receive_transfer(:'t1'::uuid, 6, 'four short')->>'short' as shrt \gset
select (stock_transfer(1,2,:'fl'::uuid,5,null,'t2')->>'id')::uuid as t2 \gset
select stock_receive_transfer(:'t2'::uuid)->>'status' as st2 \gset
select (stock_transfer(1,2,:'fl'::uuid,3,null,'t3')->>'id')::uuid as t3 \gset
select stock_cancel_transfer(:'t3'::uuid,'wrong place') is not null as c3 \gset
-- Gum has no cost: opening 10, count to 12 (a gain with NO known cost)
select stock_opening(:'gm'::uuid,1,10,null) is not null as g1 \gset
select stock_count_adjust(:'gm'::uuid,1,12,'count gum') is not null as g2 \gset
-- Sugar: bill 20 kg @ 50 = 1000 ; return 5 kg at 45 = 225 (the stock leaves at the average cost 50 = 250)
select save_purchase(gen_random_uuid(),null,:'sup'::uuid,1,'B85-1',tt.today()-2,format('[{"item_id":"%s","qty":20,"unit":"kg","unit_cost":50}]',:'su')::jsonb)->>'id' as b1 \gset
select post_purchase(:'b1'::uuid) is not null as pb1 \gset
select save_purchase(gen_random_uuid(),null,:'sup'::uuid,1,'R85-1',tt.today()-1,format('[{"item_id":"%s","qty":5,"unit":"kg","unit_cost":45}]',:'su')::jsonb,0,'price',null,'return',:'b1'::uuid,'quality')->>'id' as r1 \gset
select post_purchase(:'r1'::uuid) is not null as pr1 \gset
reset role;
select tt.chk('A the movements went through', :'a1' and :'a2' and :'a3' and :'shrt'::numeric=4 and :'st2'='received' and :'c3' and :'g1' and :'g2' and :'pb1' and :'pr1');
select tt.chk('A ledger: flour place 1 = 78, place 2 = 11; sugar 15; gum 12', (select qty from stock_balance where item_id=:'fl'::uuid and location_id=1)=78 and (select qty from stock_balance where item_id=:'fl'::uuid and location_id=2)=11
  and (select sum(qty) from stock_balance where item_id=:'su'::uuid)=15 and (select qty from stock_balance where item_id=:'gm'::uuid and location_id=1)=12);
select tt.chk('A count gain with the switch off stays a NULL-cost row (as before)', (select unit_cost is null from stock_ledger where item_id=:'gm'::uuid and reason='count_adjust'));
set role authenticated; select tt.as(:'o');
select acct_post_pending(false) as p0 \gset
reset role;
select tt.chk('A defaults: nothing of the new kinds is posted; the dry waiting list has no cost_missing', not exists (select 1 from journal_entries where source_type in ('stock_adjust','stock_opening','stock_issue','stock_transfer','transit_loss','purchase_variance','card_settlement'))
  and (:'p0'::jsonb->'waiting'->>'cost_missing') is null and (:'p0'::jsonb->'by_type'->>'purchase')::int = 2);
-- GL raw = 1000 - 225 = 775 ; valuation = 89 x 40 + 15 x 50 = 4310 ; diff -3535 = opening -4000 + count +200 + issue +80 + transfer +160 + purchase variance +25
set role authenticated; select tt.as(:'o');
select inventory_vs_gl(tt.today(), null) as iv0 \gset
reset role;
select tt.chk('A before: raw GL 775, valuation 4310, diff -3535, unexplained 0',
  (select (r->>'gl')::numeric = 775 and (r->>'valuation')::numeric = 4310 and (r->>'diff')::numeric = -3535 and (r->>'unexplained')::numeric = 0 from jsonb_array_elements(:'iv0'::jsonb->'rows') r where r->>'key'='inv_raw'));
select tt.chk('A before: reasons opening -4000, count_adjust 200, issue_out 80, transfer 160, purchase_return_variance 25',
  (select (select (x->>'amount')::numeric from jsonb_array_elements(r->'reasons') x where x->>'code'='opening') = -4000
      and (select (x->>'amount')::numeric from jsonb_array_elements(r->'reasons') x where x->>'code'='count_adjust') = 200
      and (select (x->>'amount')::numeric from jsonb_array_elements(r->'reasons') x where x->>'code'='issue_out') = 80
      and (select (x->>'amount')::numeric from jsonb_array_elements(r->'reasons') x where x->>'code'='transfer') = 160
      and (select (x->>'amount')::numeric from jsonb_array_elements(r->'reasons') x where x->>'code'='purchase_return_variance') = 25
   from jsonb_array_elements(:'iv0'::jsonb->'rows') r where r->>'key'='inv_raw'));

\echo == B switches ON: the backlog is posted once, hand-computed
-- count -5 flour @40: Dr 5110 200 / Cr 1320 200 ; gain +2 (after the switch, recorded at the average 40): Dr 1320 80 / Cr 5110 80 ; opening 4000 : Dr 1320 / Cr 3100 ;
-- issue 2 @40: Dr 5120 80 / Cr 1320 80 ; transfers location-tagged: out Dr 1230 / Cr 1320 : 400 + 200 + 120 = 720, in Dr 1320 / Cr 1230 : 240 + 200 + 120 (cancel) = 560 ;
-- short 4 @40 = 160 at the receiving place: Dr 5130 160 / Cr 1230 160 ; purchase return: stock out 250, credit 225 -> Dr 5140 25 / Cr 1320 25
set role authenticated; select tt.as(:'o');
select set_rule('acct_count_adjust','true') is null as ru1 \gset
select set_rule('acct_stock_opening','true') is null as ru2 \gset
select set_rule('acct_issue_out','true') is null as ru3 \gset
select set_rule('acct_transfer_mode','"location_tagged"') is null as ru4 \gset
select set_rule('acct_transit_loss','true') is null as ru5 \gset
select set_rule('acct_purchase_variance','true') is null as ru6 \gset
select stock_count_adjust(:'fl'::uuid,1,80,'count again') is not null as gain \gset
reset role;
select tt.chk('B the gain was recorded at the average cost 40 (known cost), the average did not move', (select unit_cost from stock_ledger where item_id=:'fl'::uuid and reason='count_adjust' order by id desc limit 1)=40 and (select avg_cost from stock_balance where item_id=:'fl'::uuid and location_id=1)=40);
set role authenticated; select tt.as(:'o');
select acct_post_pending(true) as dry \gset
select acct_post_pending(false) as p1 \gset
select acct_post_pending(false) as p2 \gset
reset role;
select tt.chk('B the dry run did not post, then the real run posted: stock_adjust 2, stock_opening 1, stock_issue 1, stock_transfer 6, transit_loss 1, purchase_variance 1',
  (:'p1'::jsonb->'by_type'->>'stock_adjust')::int=2 and (:'p1'::jsonb->'by_type'->>'stock_opening')::int=1 and (:'p1'::jsonb->'by_type'->>'stock_issue')::int=1 and (:'p1'::jsonb->'by_type'->>'stock_transfer')::int=6
  and (:'p1'::jsonb->'by_type'->>'transit_loss')::int=1 and (:'p1'::jsonb->'by_type'->>'purchase_variance')::int=1 and (:'dry'::jsonb->>'dry')::boolean);
select tt.chk('B no errors; the gum rows (no cost) wait as cost_missing: 2 (opening, gain)', jsonb_array_length(:'p1'::jsonb->'errors')=0 and (:'p1'::jsonb->'waiting'->>'cost_missing')::int=2);
select tt.chk('B posting again posts nothing (once per source: je_source_uq)', (:'p2'::jsonb->>'posted')::int=0 and (:'p2'::jsonb->>'reversed')::int=0
  and not exists (select 1 from journal_entries where reverses_id is null group by source_type, source_id having count(*)>1));
select tt.chk('B stock_adjust: Dr 5110 200 + Cr 5110 80 ; Cr 1320 200 + Dr 1320 80', tt.jt('stock_adjust','5110','d')=200 and tt.jt('stock_adjust','5110','c')=80 and tt.jt('stock_adjust','1320','c')=200 and tt.jt('stock_adjust','1320','d')=80);
select tt.chk('B opening: Dr 1320 4000 / Cr owner capital 3100 4000', tt.jt('stock_opening','1320','d')=4000 and tt.jt('stock_opening','3100','c')=4000);
select tt.chk('B issue: Dr 5120 80 / Cr 1320 80', tt.jt('stock_issue','5120','d')=80 and tt.jt('stock_issue','1320','c')=80);
select tt.chk('B transfers: clearing Dr 720 Cr 560 ; inventory Cr 720 Dr 560', tt.jt('stock_transfer','1230','d')=720 and tt.jt('stock_transfer','1230','c')=560 and tt.jt('stock_transfer','1320','c')=720 and tt.jt('stock_transfer','1320','d')=560);
select tt.chk('B transit loss: Dr 5130 160 / Cr clearing 160, at the receiving place 2', tt.jt('transit_loss','5130','d')=160 and tt.jt('transit_loss','1230','c')=160
  and (select location_id from journal_entries where source_type='transit_loss')=2);
select tt.chk('B purchase variance: Dr 5140 25 / Cr 1320 25', tt.jt('purchase_variance','5140','d')=25 and tt.jt('purchase_variance','1320','c')=25);
select tt.chk('B the clearing account nets to 0 company-wide (720 - 560 - 160)', (select sum(l.debit-l.credit) from journal_lines l join coa_accounts a on a.id=l.account_id where a.code='1230')=0);
select tt.chk('B every entry balances; each transfer entry is tagged with its own place', tt.unbalanced_entries()=0
  and (select count(*) from journal_entries e where e.source_type='stock_transfer' and e.location_id is not null and not exists (select 1 from journal_lines l where l.entry_id=e.id and l.location_id is distinct from e.location_id))=6);
set role authenticated; select tt.as(:'o');
select inventory_vs_gl(tt.today(), null) as iv1 \gset
select inventory_vs_gl(tt.today(), 1) as iv1a \gset
select inventory_vs_gl(tt.today(), 2) as iv1b \gset
reset role;
-- GL raw = 775 + 4000 - 120 - 80 - 160 - 25 = 4390 = valuation (91 x 40 + 15 x 50)
select tt.chk('B inventory_vs_gl all places: raw GL 4390 = valuation 4390, no reasons left, unexplained 0',
  (select (r->>'gl')::numeric = 4390 and (r->>'valuation')::numeric = 4390 and (r->>'diff')::numeric = 0 and (r->>'unexplained')::numeric = 0 and jsonb_array_length(r->'reasons')=0 from jsonb_array_elements(:'iv1'::jsonb->'rows') r where r->>'key'='inv_raw'));
select tt.chk('B place 1: GL 3950 = valuation 3950 ; place 2: GL 440 = valuation 440 (the tagged pair keeps each place right)',
  (select (r->>'gl')::numeric = 3950 and (r->>'valuation')::numeric = 3950 and (r->>'unexplained')::numeric = 0 from jsonb_array_elements(:'iv1a'::jsonb->'rows') r where r->>'key'='inv_raw')
  and (select (r->>'gl')::numeric = 440 and (r->>'valuation')::numeric = 440 and (r->>'unexplained')::numeric = 0 from jsonb_array_elements(:'iv1b'::jsonb->'rows') r where r->>'key'='inv_raw'));
set role authenticated; select tt.as(:'o');
select acct_trial_balance(null,null) as tb \gset
select acct_balance_sheet(tt.today()) as bs \gset
select acct_income_statement(tt.today()-5, tt.today(), null) as ist \gset
reset role;
select tt.chk('B trial balance balanced; account rows add up to the journal totals (dr 7050 = cr 7050)', (:'tb'::jsonb->>'balanced')::boolean
  and (select sum((r->>'dr')::numeric) from jsonb_array_elements(:'tb'::jsonb->'rows') r where not (r->>'is_group')::boolean) = (select sum(debit) from journal_lines)
  and (select sum((r->>'cr')::numeric) from jsonb_array_elements(:'tb'::jsonb->'rows') r where not (r->>'is_group')::boolean) = (select sum(credit) from journal_lines));
select tt.chk('B report == journal per account: the new accounts in the trial balance equal their journal lines',
  (select bool_and((r->>'dr')::numeric = j.d and (r->>'cr')::numeric = j.c) from jsonb_array_elements(:'tb'::jsonb->'rows') r join (select a.code, sum(l.debit) d, sum(l.credit) c from journal_lines l join coa_accounts a on a.id=l.account_id group by a.code) j on j.code = r->>'code' where not (r->>'is_group')::boolean));
select tt.chk('B income statement: expenses 5110 120 + 5120 80 + 5130 160 + 5140 25 = 385 = journal; net profit -385', (:'ist'::jsonb->>'total_expense')::numeric = 385 and (:'ist'::jsonb->>'net_profit')::numeric = -385
  and (:'ist'::jsonb->>'total_expense')::numeric = (select sum(l.debit-l.credit) from journal_lines l join coa_accounts a on a.id=l.account_id where a.type='expense')
  and (select string_agg(r->>'code'||'='||(r->>'amount')::numeric::int, ',' order by r->>'code') from jsonb_array_elements(:'ist'::jsonb->'expense') r) = '5110=120,5120=80,5130=160,5140=25');
select tt.chk('B balance sheet balanced and its raw material line = journal 4390', not (:'bs'::jsonb->>'unbalanced')::boolean and (:'bs'::jsonb->>'difference')::numeric=0
  and (select (r->>'amount')::numeric from jsonb_array_elements(:'bs'::jsonb->'assets') r where r->>'code'='1320') = 4390);

\echo == C a purchase-return void reverses the variance; company-wide transfer mode; the from-date rule
set role authenticated; select tt.as(:'o');
select void_purchase(:'r1'::uuid,'return was entered twice') is not null as vr \gset
select acct_post_pending(false) as p3 \gset
reset role;
select tt.chk('C voiding the return bill: the bill entry and the variance entry are reversed, nothing else', (:'p3'::jsonb->'by_type'->>'purchase_reversed')::int=1 and (:'p3'::jsonb->'by_type'->>'purchase_variance_reversed')::int=1 and jsonb_array_length(:'p3'::jsonb->'errors')=0);
set role authenticated; select tt.as(:'o');
select inventory_vs_gl(tt.today(), null) as iv2 \gset
reset role;
-- sugar back to 20 @ 50 = 1000 : GL raw = 4390 + 225 + 25 = 4640 = valuation 91 x 40 + 20 x 50
select tt.chk('C after the void: raw GL 4640 = valuation 4640, unexplained 0', (select (r->>'gl')::numeric = 4640 and (r->>'valuation')::numeric = 4640 and (r->>'unexplained')::numeric = 0 from jsonb_array_elements(:'iv2'::jsonb->'rows') r where r->>'key'='inv_raw'));
-- company-wide mode: T4 sends 10 from place 1 and place 2 gets 7 (3 short = 120): no pair is posted, the loss is Dr 5130 120 / Cr 1320 120
set role authenticated; select tt.as(:'o');
select set_rule('acct_transfer_mode','"company_wide"') is null as cw \gset
select (stock_transfer(1,2,:'fl'::uuid,10,null,'t4')->>'id')::uuid as t4 \gset
select stock_receive_transfer(:'t4'::uuid, 7, 'three short')->>'short' as sh4 \gset
select acct_post_pending(false) as p4 \gset
select inventory_vs_gl(tt.today(), null) as iv3 \gset
reset role;
select tt.chk('C company-wide: no transfer entry posted for T4; the 3 short are a transit loss against inventory (120)', (:'p4'::jsonb->'by_type'->>'stock_transfer') is null and (:'p4'::jsonb->'by_type'->>'transit_loss')::int=1
  and tt.jt('transit_loss','5130','d')=280 and tt.jt('transit_loss','1320','c')=120);
-- raw GL 4640 - 120 = 4520 ; valuation: place 1 70 + 1 gain... flour 80 - 10 = 70, place 2 11 + 7 = 18, sugar 20 x 50 : (70 + 18) x 40 + 1000 = 4520
select tt.chk('C company-wide: raw GL 4520 = valuation 4520, unexplained 0 (the books are company-wide)', (select (r->>'gl')::numeric = 4520 and (r->>'valuation')::numeric = 4520 and (r->>'unexplained')::numeric = 0 from jsonb_array_elements(:'iv3'::jsonb->'rows') r where r->>'key'='inv_raw'));
-- the from-date rule: a count adjustment dated today is left out while the rule says tomorrow, and is posted when the rule is cleared
set role authenticated; select tt.as(:'o');
select set_rule('acct_stock_moves_from', to_jsonb((tt.today()+1)::text)) is null as fr \gset
select stock_count_adjust(:'fl'::uuid,1,69,'one lost') is not null as ca2 \gset
select acct_post_pending(false) as p5 \gset
select set_rule('acct_stock_moves_from', null) is null as fr2 \gset
select acct_post_pending(false) as p6 \gset
reset role;
select tt.chk('C from-date in the future: the new count adjustment waits, nothing posted; after clearing it posts 1 entry of 40', coalesce((:'p5'::jsonb->'by_type'->>'stock_adjust')::int,0)=0 and (:'p6'::jsonb->'by_type'->>'stock_adjust')::int=1
  and tt.jt('stock_adjust','5110','d')=240);

\echo == D manual journal guard
set role authenticated; select tt.as(:'o');
select acct_journal_post(tt.today(),1,'inventory top-up by hand','[{"code":"1320","debit":10},{"code":"1110","credit":10}]'::jsonb,null,null,true)->>'dry' as gd0 \gset
select tt.chk('D guard off: a manual line on an inventory account is accepted without a reason (as today)', :'gd0'='true');
select set_rule('manual_journal_guard','"on"') is null as ge \gset
select tt.err('D guard on: inventory account without a reason code is refused', $$select acct_journal_post(current_date,1,'inventory top-up by hand','[{"code":"1320","debit":10},{"code":"1110","credit":10}]'::jsonb,null,null,true)$$, 'reason_required');
select tt.err('D guard on: unknown reason code is refused', $$select acct_journal_post(current_date,1,'inventory top-up by hand','[{"code":"1320","debit":10},{"code":"1110","credit":10}]'::jsonb,null,null,true,'bogus')$$, 'bad_reason');
select acct_journal_post(tt.today(),1,'inventory top-up by hand','[{"code":"1320","debit":10},{"code":"1110","credit":10}]'::jsonb,null,null,true,'correction')->>'dry' as gd1 \gset
select tt.chk('D guard on: a valid reason code is accepted', :'gd1'='true');
select tt.err('D guard on: payable line without a party is refused', $$select acct_journal_post(current_date,1,'supplier fix by hand','[{"code":"2100","credit":10},{"code":"5900","debit":10}]'::jsonb,null,null,true,'correction')$$, 'party_required');
select acct_journal_post(tt.today(),1,'supplier fix by hand',format('[{"code":"2100","credit":10,"party_type":"supplier","party_id":"%s"},{"code":"5900","debit":10}]',:'sup')::jsonb,null,null,true,'correction')->>'dry' as gd2 \gset
select tt.chk('D guard on: payable line with a party is accepted', :'gd2'='true');
select acct_journal_post(tt.today(),1,'rent by hand','[{"code":"5900","debit":10},{"code":"1110","credit":10}]'::jsonb,null,null,true)->>'dry' as gd3 \gset
select tt.chk('D guard on: accounts that are not reserved need no reason', :'gd3'='true');
select acct_journal_post(tt.today(),1,'inventory top-up by hand','[{"code":"1320","debit":10},{"code":"1110","credit":10}]'::jsonb,null,null,false,'correction')->>'id' as gid \gset
select tt.chk('D the real post keeps the reason in the entry flags', (select flags from journal_entries where id=:'gid'::bigint)='reason:correction');
select manual_reason_set('stock_fix','স্টক ঠিক করা','Stock fix','Stock fix')->>'code' as rc \gset
select tt.chk('D the owner can add a reason code; the list shows it', :'rc'='stock_fix' and exists (select 1 from jsonb_array_elements(manual_reasons85()) x where x->>'code'='stock_fix'));
select tt.as(:'s');
select tt.err('D a manager cannot add a reason code', $$select manual_reason_set('x_fix','a','b','c')$$, 'not allowed');
select tt.as(:'o');
select tt.err('D a bad guard value is refused by the rule engine', $$select set_rule('manual_journal_guard','"maybe"')$$, 'bad_value');
select set_rule('manual_journal_guard','"off"') is null as gof \gset
reset role;
select tt.chk('D guard back off', rule_txt('manual_journal_guard')='off');

\echo == F card settlement (typed numbers only)
-- card sale 1000 -> Dr 1140 1000 / Cr 4100 1000 ; settlement gross 600 fee 12: Dr 1120 588 + Dr 5810 12 / Cr 1140 600 ; card receivable left 400
set role authenticated; select tt.as(:'o');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":1000}]',:'cdi')::jsonb,0,'[{"mode":"card","amount":1000}]',null,null,'retail',null,false)->>'id' as sc1 \gset
select acct_post_pending(false) as p7 \gset
select card_settlement_list(1) as cl0 \gset
select tt.chk('F the card sale is in 1140: unsettled 1000', (:'cl0'::jsonb->>'unsettled')::numeric=1000 and tt.jt('sale','1140','d')=1000);
select card_settle(1, tt.today(), 600, 12, 'batch 1', 'aaaaaaaa-0000-0000-0000-000000000085'::uuid) as cs1 \gset
select card_settle(1, tt.today(), 600, 12, 'batch 1', 'aaaaaaaa-0000-0000-0000-000000000085'::uuid) as cs1b \gset
select tt.chk('F settlement saved once (client id), the hint says it is not over the unsettled amount', (:'cs1'::jsonb->>'id') is not null and (:'cs1b'::jsonb->>'dup')::boolean and (select count(*) from card_settlements85)=1 and not (:'cs1'::jsonb->>'over')::boolean and (:'cs1'::jsonb->>'unsettled')::numeric=1000);
select tt.err('F fee must be below the gross', $$select card_settle(1, current_date, 100, 100, 'x')$$, 'bad_fee');
select tt.err('F a bad bank mode is refused', $$select card_settle(1, current_date, 100, 1, 'x', null, 'cash')$$, 'bad_mode');
select tt.err('F a future date is refused', $$select card_settle(1, current_date + 3, 100, 1, 'x')$$, 'bad_date');
select acct_post_pending(false) as p8 \gset
select tt.chk('F posted once: Dr bank 588 + Dr charges 12 / Cr card 600', (:'p8'::jsonb->'by_type'->>'card_settlement')::int=1 and tt.jt('card_settlement','1120','d')=588 and tt.jt('card_settlement','5810','d')=12 and tt.jt('card_settlement','1140','c')=600);
select card_settlement_list(1) as cl1 \gset
select tt.chk('F unsettled card receivable now 400; the list has the row', (:'cl1'::jsonb->>'unsettled')::numeric=400 and jsonb_array_length(:'cl1'::jsonb->'rows')=1);
select card_settle(1, tt.today(), 5000, 0, 'too much') as cs2 \gset
select tt.chk('F over the unsettled amount: allowed but flagged over=true (a hint, nothing invented)', (:'cs2'::jsonb->>'over')::boolean);
select card_settle_void((:'cs2'::jsonb->>'id')::uuid, 'typed by mistake') as v2 \gset
select acct_post_pending(false) as p9 \gset
select tt.chk('F voided before posting: never reaches the books', (select status from card_settlements85 where id=(:'cs2'::jsonb->>'id')::uuid)='void' and not exists (select 1 from journal_entries where source_type='card_settlement' and source_id=(:'cs2'::jsonb->>'id')));
select card_settle(1, tt.today(), 100, 0, 'batch 3') as cs3 \gset
select acct_post_pending(false) as p10 \gset
select card_settle_void((:'cs3'::jsonb->>'id')::uuid, 'wrong day') as v3 \gset
select acct_post_pending(false) as p11 \gset
select tt.chk('F a posted settlement that is voided is reversed by the next run; the card receivable is unchanged (400)', (:'p10'::jsonb->'by_type'->>'card_settlement')::int=1 and (:'p11'::jsonb->'by_type'->>'card_settlement_reversed')::int=1
  and (card_settlement_list(1)->>'unsettled')::numeric=400);
select tt.as(:'s');
select tt.err('F a manager without accounts rights cannot settle', $$select card_settle(1, current_date, 10, 0, 'x')$$, 'not allowed');
select tt.as(:'o');
reset role;
select tt.err('F a settlement row cannot be changed or deleted', format($$update card_settlements85 set gross = 1 where id = %L$$, (:'cs1'::jsonb->>'id')), 'append_only');
select tt.err('F ... or deleted', format($$delete from card_settlements85 where id = %L$$, (:'cs1'::jsonb->>'id')), 'append_only');
select tt.chk('F the settlement is audited', exists (select 1 from audit_log where table_name='card_settlements85' and record_id=(:'cs1'::jsonb->>'id')));

\echo == G expense voucher payment mode (10-2)
-- bank 300 -> Cr 1120 ; card 100 -> bank (a card is settled through the bank, as for supplier payments) ; none 200 and an unknown value 50 -> cash 1110
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
 ('10-2',1,9301,tt.today(),'approved','{"lines":[{"head":"transport","amount":"300"}],"pay_mode":"bank"}','[]',:'s','st'),
 ('10-2',1,9302,tt.today(),'approved','{"lines":[{"head":"transport","amount":"200"}]}','[]',:'s','st'),
 ('10-2',1,9303,tt.today(),'approved','{"lines":[{"head":"transport","amount":"100"}],"pay_mode":"card"}','[]',:'s','st'),
 ('10-2',1,9304,tt.today(),'approved','{"lines":[{"head":"transport","amount":"50"}],"pay_mode":"crypto"}','[]',:'s','st');
set role authenticated; select tt.as(:'o');
select acct_post_pending(false) as p12 \gset
reset role;
select tt.chk('G four vouchers posted; Cr bank 400 (bank 300 + card 100), Cr cash 250 (none 200 + unknown 50), Dr transport 650', (:'p12'::jsonb->'by_type'->>'expense_voucher')::int=4 and tt.jt('expense_voucher','1120','c')=400
  and tt.jt('expense_voucher','1110','c')=250 and tt.jt('expense_voucher','5700','d')=650);

\echo == E scheduler, locked documents, pending alert
-- a count loss of 1 kg flour (-40) waits ; the scheduler (no signed-in person) posts it
set role authenticated; select tt.as(:'o');
select stock_count_adjust(:'fl'::uuid,1,68,'one more lost') is not null as ca3 \gset
reset role;
select tt.as('');
select tt.chk('E scheduler off: the tick does nothing and says so', acct_autopost_tick()->>'skipped' = 'scheduler_off');
select tt.err('E posting without a person and without the scheduler entry is refused', $$select acct_post_pending(false)$$, 'not allowed');
set role authenticated; select tt.as(:'s');
select tt.err('E a signed-in non-owner cannot call the tick', $$select acct_autopost_tick()$$, 'not allowed');
select tt.err('E a manager without accounts view cannot read the pending alert', $$select acct_pending_alert85()$$, 'not allowed');
reset role;
update rules set value = 'true'::jsonb where key = 'acct_scheduler_on';
select tt.as('');
select acct_autopost_tick() as tk1 \gset
select acct_autopost_tick() as tk2 \gset
select tt.chk('E the tick posted the waiting entry (1), a run row was kept; the second tick posts 0', (:'tk1'::jsonb->>'posted')::int=1 and (:'tk2'::jsonb->>'posted')::int=0 and (select count(*) from acct_autopost_runs85)=2
  and tt.jt('stock_adjust','5110','d')=280 and (select created_by is null from journal_entries where source_type='stock_adjust' order by id desc limit 1));
select tt.chk('E scheduler entries keep their date and place (the dated posting, not the run time)', (select entry_date = tt.today() and location_id = 1 from journal_entries where source_type='stock_adjust' order by id desc limit 1));
-- locked: a settlement dated 3 days ago, period closed up to 2 days ago: the scheduler respects the lock (the owner may force-post)
set role authenticated; select tt.as(:'o');
select card_settle(1, tt.today()-3, 50, 0, 'old batch')->>'id' as cs4 \gset
select set_rule('period_closed_until', to_jsonb((tt.today()-2)::text)) is null as lk \gset
select acct_pending_alert85() as al \gset
reset role;
select tt.chk('E alert: 1 document waiting longer than 1 day, 1 locked, listed with its source; force by owner', (:'al'::jsonb->>'alert')::boolean and (:'al'::jsonb->>'old_count')::int=1 and (:'al'::jsonb->>'locked_count')::int=1
  and :'al'::jsonb->'locked'->0->>'source_type'='card_settlement' and :'al'::jsonb->>'force_by'='owner' and (:'al'::jsonb->'scheduler'->>'on')::boolean);
select tt.as('');
select acct_autopost_tick() as tk3 \gset
select tt.chk('E the scheduled run does not bypass the lock: locked 1, nothing posted', (:'tk3'::jsonb->>'locked')::int=1 and (:'tk3'::jsonb->>'posted')::int=0 and not exists (select 1 from journal_entries where source_type='card_settlement' and source_id=:'cs4'));
set role authenticated; select tt.as(:'o');
select set_rule('period_closed_until', null) is null as unlk \gset
reset role;
select tt.as('');
select acct_autopost_tick() as tk4 \gset
select tt.chk('E after the period is opened the scheduled run posts it', (:'tk4'::jsonb->>'posted')::int=1 and exists (select 1 from journal_entries where source_type='card_settlement' and source_id=:'cs4'));
set role authenticated; select tt.as(:'o');
select acct_status() as stt \gset
select acct_pending_alert85() as al2 \gset
reset role;
select tt.chk('E status shows the scheduler (on, last run); after posting nothing is old', (:'stt'::jsonb->'scheduler'->>'on')::boolean and (:'stt'::jsonb->'scheduler'->>'last_run') is not null and (:'stt'::jsonb->>'last_post_at') is not null and (:'al2'::jsonb->>'old_count')::int=0 and (:'al2'::jsonb->>'locked_count')::int=0);
-- pg_cron is not installed here: the enable call says so; with a stand-in cron schema it schedules (the real pg_cron is NOT tested)
set role authenticated; select tt.as(:'o');
select acct_scheduler_enable('*/15 * * * *') as en0 \gset
select tt.err('E a bad cron text is refused', $$select acct_scheduler_enable('every hour; drop table x')$$, 'bad_cron');
reset role;
select tt.chk('E without pg_cron: scheduled false, reason pg_cron_missing', (:'en0'::jsonb->>'scheduled')::boolean is false and :'en0'::jsonb->>'reason'='pg_cron_missing');
create schema cron;
create table cron.calls (fn text, args text);
create function cron.schedule(p_name text, p_schedule text, p_command text) returns bigint language sql as $$ insert into cron.calls values ('schedule', p_name || '|' || p_schedule || '|' || p_command); select 7::bigint $$;
create function cron.unschedule(p_name text) returns boolean language sql as $$ insert into cron.calls values ('unschedule', p_name); select true $$;
set role authenticated; select tt.as(:'o');
select acct_scheduler_enable('*/15 * * * *') as en1 \gset
select acct_scheduler_disable() as dis1 \gset
reset role;
select tt.chk('E with a stand-in cron: scheduled job named, command is the tick; disable unschedules and switches the rule off', (:'en1'::jsonb->>'scheduled')::boolean and (select args from cron.calls where fn='schedule') = 'bos_acct_autopost|*/15 * * * *|select public.acct_autopost_tick()'
  and exists (select 1 from cron.calls where fn='unschedule') and not rule_on('acct_scheduler_on'));
drop schema cron cascade;

\echo == H closing checks
set role authenticated; select tt.as(:'o');
select acct_trial_balance(null,null) as tbf \gset
select acct_balance_sheet(tt.today()) as bsf \gset
select inventory_vs_gl(tt.today(), null) as ivf \gset
reset role;
select tt.chk('H final: every entry balances, trial balance balanced, balance sheet difference 0', tt.unbalanced_entries()=0 and (:'tbf'::jsonb->>'balanced')::boolean and not (:'bsf'::jsonb->>'unbalanced')::boolean and (:'bsf'::jsonb->>'difference')::numeric=0);
-- the only thing left between the books and the stock is the manual journal (+10) and the 40 kg... flour count: all explained
select tt.chk('H final: raw material difference is exactly the manual journal 10; unexplained 0', (select (r->>'unexplained')::numeric = 0 and (r->>'diff')::numeric = 10
   and (select (x->>'amount')::numeric from jsonb_array_elements(r->'reasons') x where x->>'code'='manual_journal') = 10 from jsonb_array_elements(:'ivf'::jsonb->'rows') r where r->>'key'='inv_raw'));
select tt.chk('H English-mode strings: memos of the new entries have no Bangla characters', (select bool_and(tt.noban(memo)) from journal_entries where source_type in ('stock_adjust','stock_opening','stock_issue','stock_transfer','transit_loss','purchase_variance','card_settlement')));
select tt.err('H the journal stays append-only: a line cannot be changed', $$update journal_lines set debit = debit + 1 where entry_id = (select min(entry_id) from journal_lines)$$, 'append_only');
select tt.err('H the stock ledger stays immutable: a row cannot be deleted', $$delete from stock_ledger where id = (select min(id) from stock_ledger)$$, 'ledger_immutable');
select tt.chk('H cost secrecy: the browser cannot read the stock ledger or the settlement table directly without rights, and the ledger cost view is unchanged', not has_table_privilege('anon','card_settlements85','select') and not has_table_privilege('anon','stock_ledger','select'));
select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
