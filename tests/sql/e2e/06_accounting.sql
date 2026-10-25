\echo == 06 accounting
select tt.as(:'o');
-- D2 opening stock helper BEFORE anything is posted
select opening_stock_check96() as ck0 \gset
select (select r from jsonb_array_elements(:'ck0'::jsonb->'rows') r where (r->>'location_id')::int=1) as ckr \gset
select tt.eq('D2 opening_value place 1 = flour 4000 + sweet 2000 + snack 500 + snack box 200', 6700, (:'ckr'::jsonb->>'opening_value')::numeric);
select tt.eq('D2 opening rows = 6, uncosted = 2 (water, glaze)', 6, (:'ckr'::jsonb->>'opening_rows')::numeric);
select tt.eq('D2 uncosted rows', 2, (:'ckr'::jsonb->>'uncosted_rows')::numeric);
select tt.eq('D2 opening journal already carries inventory 4000', 4000, (:'ckr'::jsonb->>'opening_journal_inventory')::numeric);
select opening_stock_preview96('difference',1) as pv \gset
select tt.eq('D2 preview difference = 6700-4000 = 2700 (finished 2500 + packaging 200)', 2700, (:'pv'::jsonb->>'amount')::numeric);
select opening_stock_apply96('difference',1,null,null,'opening journal had only the flour','bbbbbbbb-0000-0000-0000-00000000d2d2'::uuid) as apx \gset
select opening_stock_apply96('difference',1,null,null,'opening journal had only the flour','bbbbbbbb-0000-0000-0000-00000000d2d2'::uuid) as apxb \gset
select tt.is('D2 apply twice with same client id = dup', 'true', coalesce(:'apxb'::jsonb->>'dup','false'));
select tt.eq('D2 helper posted 2700 (Cr 3100)', 2700, (select coalesce(sum(l.credit),0) from journal_entries e join journal_lines l on l.entry_id=e.id join coa_accounts a on a.id=l.account_id where e.source_type='opening_stock96' and a.code='3100'));
select tt.eq('D2 inventory GL after helper = 4000 + 2500 + 200 = 6700', 6700, tt.bal('1310')+tt.bal('1320')+tt.bal('1330'));
-- switch ON afterwards must not double-count
select set_rule('acct_stock_opening','true') is null as aso \gset
select acct_post_pending(false) as pp1 \gset
\echo POST_PENDING_1: :pp1
select tt.eq('D2 opening-stock docs posted by the pending run (must be 0: helper already booked them)', 0, coalesce((:'pp1'::jsonb->'by_type'->>'stock_opening')::numeric,0));
select set_rule('acct_stock_opening',null) is null as aso0 \gset
select acct_post_pending(false) as pp2 \gset
select tt.eq('A0 second pending run posts nothing new', 0, (:'pp2'::jsonb->>'posted')::numeric);
select tt.eq('A0 trial balance: unbalanced entries', 0, tt.unbalanced());

\echo -- card settlement
select card_settlement_list(1) as cl0 \gset
select tt.eq('C1 card receivable before settlement (card sale 600)', 600, (:'cl0'::jsonb->>'unsettled')::numeric);
select card_settle(1, tt.today(), 600, 12, 'batch 1', 'aaaaaaaa-0000-0000-0000-0000000000c1'::uuid) as cs \gset
select card_settle(1, tt.today(), 600, 12, 'batch 1', 'aaaaaaaa-0000-0000-0000-0000000000c1'::uuid) ->> 'dup' as csd \gset
select tt.is('C1 settlement same client id = dup', 'true', :'csd');
select acct_post_pending(false) as pp3 \gset
select tt.eq('C1 Dr bank 588 (card settlement)', 588, (select coalesce(sum(l.debit),0) from journal_entries e join journal_lines l on l.entry_id=e.id join coa_accounts a on a.id=l.account_id where e.source_type='card_settlement' and a.code='1120'));
select tt.eq('C1 Dr bank charges 12', 12, (select coalesce(sum(l.debit),0) from journal_entries e join journal_lines l on l.entry_id=e.id join coa_accounts a on a.id=l.account_id where e.source_type='card_settlement' and a.code='5810'));
select tt.eq('C1 card receivable account 1140 balance after settlement (sale 600 - 600)', 0, tt.bal('1140'));

\echo -- stock count adjustment (flour 280.2 -> counted 279): -1.2 x 42.7333 = 51.28
select tt.eq('K0 flour book qty before count', 280.2, tt.qty('RM-F'));
select rule_on('acct_count_adjust') as aca0 \gset
\echo ACCT_COUNT_ADJUST_AT_START=:aca0
select stock_count_adjust(tt.iid('RM-F'),1,279,'e2e count') is not null as sca \gset
select tt.eq('K1 flour qty after count', 279, tt.qty('RM-F'));
select acct_post_pending(false) as pp4 \gset
\if :aca0
select tt.eq('K1 switch ON: count loss booked at once: Dr 5110 51.28', 51.28, tt.bal('5110'), 0.01);
\else
select tt.eq('K1 switch OFF (default): the count loss is NOT in the books yet (5110 = 0)', 0, tt.bal('5110'));
select set_rule('acct_count_adjust','true') is null as acaon \gset
select acct_post_pending(false) as pp5 \gset
select tt.eq('K1 switch turned ON later: backlog posted once: Dr 5110 51.28', 51.28, tt.bal('5110'), 0.01);
select acct_post_pending(false) as pp6 \gset
select tt.eq('K1 posting again changes nothing (still 51.28)', 51.28, tt.bal('5110'), 0.01);
\endif

\echo -- D3 cost-waiting list and supplying a cost
select stock_wastage(tt.iid('RM-X'),1,1,'spoiled','e2e glaze') is not null as wg \gset
select acct_post_pending(false) as pp7 \gset
\echo POST_PENDING_7: :pp7
select cost_wait_list96() as cwl \gset
select (select string_agg(x->>'kind'||':'||coalesce(x->'items'->0->>'code','?'), ', ' order by x->>'kind', x->'items'->0->>'code') from jsonb_array_elements(:'cwl'::jsonb->'items') x) as cwitems \gset
\echo COST_WAIT_ITEMS: :cwitems
select tt.t('D3 cost-wait list shows: cookie production-in, glaze opening, glaze wastage (3), water is free so not waiting', (:'cwl'::jsonb->>'total')::int = 3, '3', (:'cwl'::jsonb->>'total'));
select (select x->>'ref' from jsonb_array_elements(:'cwl'::jsonb->'items') x where x->>'kind'='wastage') as wref \gset
select cost_wait_supply96('wastage', :'wref', 'manual', format('[{"item_id":"%s","cost":12}]', tt.iid('RM-X'))::jsonb, 'supplier quote', 'cccccccc-0000-0000-0000-0000000000d3'::uuid) as sp1 \gset
select tt.eq('D3 glaze wastage posted at 12: Dr 5100 12', 12, tt.bal('5100'));
select (select x->>'ref' from jsonb_array_elements(cost_wait_list96()->'items') x where x->>'kind'='ledger' and x->>'move'='opening') as cref \gset
select tt.bal('1310')+tt.bal('1320')+tt.bal('1330') as inv0 \gset
select cost_wait_supply96('ledger', :'cref', 'manual', format('[{"item_id":"%s","cost":12}]', tt.iid('RM-X'))::jsonb, 'supplier quote', 'cccccccc-0000-0000-0000-0000000000d4'::uuid) as sp2 \gset
-- phase103 (D-3): the cost came after the opening-stock helper, so the helper books exactly the later rows, once (5 x 12 = 60)
select opening_stock_apply96('difference',1,null,null,'glaze cost supplied later','bbbbbbbb-0000-0000-0000-00000000d2d3'::uuid) as apy \gset
select tt.eq('D3 follow-up decision amount = 5 x 12', 60, (:'apy'::jsonb->>'amount')::numeric);
select tt.err('D3 a second follow-up has nothing left to book', $$select opening_stock_apply96('difference',1,null,null,'again','bbbbbbbb-0000-0000-0000-00000000d2d4'::uuid)$$, 'already_applied');
select acct_post_pending(false) as pp8 \gset
select tt.eq('D3 glaze opening 5 x 12 supplied later: inventory GL moves by +60 (Dr 1320) [or a warning says it is not booked]', 60, tt.bal('1310')+tt.bal('1320')+tt.bal('1330') - :inv0::numeric);
select opening_stock_check96() as ck9 \gset
\echo OPENING_CHECK_AFTER_SUPPLY: :ck9
-- phase103 (D-2): the cookie production-in (no recipe, no cost) is in the list; supply its cost too (5 kg x 50)
select (select x->>'ref' from jsonb_array_elements(cost_wait_list96()->'items') x where x->>'kind'='ledger' and x->>'move'='production_in') as pref \gset
select (select x->'items'->0->>'item_id' from jsonb_array_elements(cost_wait_list96()->'items') x where x->>'kind'='ledger' and x->>'move'='production_in') as pitem \gset
select cost_wait_supply96('ledger', :'pref', 'manual', format('[{"item_id":"%s","cost":50}]', :'pitem')::jsonb, 'typed cost', 'cccccccc-0000-0000-0000-0000000000d5'::uuid) as sp3 \gset
select tt.eq('D3 cost waiting list after supplying all three = 0', 0, (cost_wait_list96()->>'total')::numeric);
select tt.eq('A9 unbalanced entries', 0, tt.unbalanced());
