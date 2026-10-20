\echo == 11 extra cross-feature checks (mode-dependent behaviour is printed as MODEDIFF)
select tt.as(:'o');
select (select coalesce(sum(debit-credit),0) from journal_lines l join coa_accounts a on a.id=l.account_id where a.code='5100') as w0, tt.bal('5120') as i0, tt.bal('1330') as p0 \gset
-- E1 void a sale and its books
select id as vs from sales where created_by=:'sp'::uuid order by receipt desc limit 1 \gset
select tt.qty('FG-CAKE') as cq0 \gset
select * from biz_daily(tt.today(), tt.today(), 1) \gset v0_
select void_sale(:'vs'::uuid,'e2e void') is not null as vd \gset
select acct_post_pending(false) as ppv \gset
select * from biz_daily(tt.today(), tt.today(), 1) \gset v1_
select tt.eq('E1 void: cake stock +1', :cq0::numeric + 1, tt.qty('FG-CAKE'));
select tt.eq('E1 void: revenue -300', :v0_revenue::numeric - 300, :v1_revenue::numeric);
select tt.eq('E1 void: COGS -57.734', :v0_cogs::numeric - 57.734, :v1_cogs::numeric, 0.02);
select tt.eq('E1 void: journal COGS equals report COGS', :v1_cogs::numeric, tt.bal_loc('5000',1), 0.02);
select tt.eq('E1 void: trial balance balanced', 0, tt.unbalanced());
-- E2 invoice_own_sales_only
select id as osale from sales where created_by=:'o'::uuid order by receipt desc limit 1 \gset
select tt.as(:'sp');
select case when exists (select 1) then 1 end as one \gset
do $$ begin perform invoice_data92((select id from sales where created_by='00000000-0000-0000-0000-000000000001' order by receipt desc limit 1), gen_random_uuid()); perform set_config('e2e.inv','allowed',false); exception when others then perform set_config('e2e.inv','refused:'||sqlerrm,false); end $$;
select current_setting('e2e.inv') as invres \gset
select rule_on('invoice_own_sales_only') as ios \gset
\echo MODEDIFF E2 seller opening another users invoice: result=:invres invoice_own_sales_only=:ios
select tt.as(:'o');
-- E4 packaging return mode wastage (recommended value)
select set_rule('packaging_return_mode','"wastage"') is null as prm \gset
select id as sd2 from sales where created_by=:'sp'::uuid and lines::text like '%FG-SNK%' order by receipt limit 1 \gset
select tt.qty('PK-SN') as pk0, tt.qty('FG-SNK') as sn0, tt.bal('5000') as cg0 \gset
select sale_return(gen_random_uuid(), :'sd2'::uuid, format('[{"item_id":"%s","qty":1}]',tt.iid('FG-SNK'))::jsonb, 'damaged','e2e snack return 2','cash') as ret2 \gset
select tt.eq('E4 wastage mode: snack +1', :sn0::numeric + 1, tt.qty('FG-SNK'));
select tt.eq('E4 wastage mode: snack box NOT restored', :pk0::numeric, tt.qty('PK-SN'));
select acct_post_pending(false) as ppw \gset
select tt.eq('E4 wastage mode: COGS falls by the snack cost 10 only (the lost box 2 stays in COGS)', -10, tt.bal('5000') - :cg0::numeric);
select tt.eq('E4 wastage mode: a sale_return_packaging80 record of mode wastage', 1, (select count(*) from sale_return_packaging80 where mode='wastage'));
select (inventory_vs_gl(tt.today(),1)->'rows') as ivr \gset
select tt.eq('E4 inventory_vs_gl packaging row diff stays 0', 0, (select (x->>'diff')::numeric from jsonb_array_elements(:'ivr'::jsonb) x where x->>'key'='inv_pack'));
-- E5 acct_issue_out
select rule_on('acct_issue_out') as aio \gset
select stock_issue(tt.iid('RM-F'),1,1,'kg','e2e own use',gen_random_uuid()) is not null as si \gset
select acct_post_pending(false) as ppi \gset
\if :aio
select tt.eq('E5 acct_issue_out ON: Dr 5120 = 1 kg x 42.7333', 42.73, tt.bal('5120') - :i0::numeric, 0.01);
\else
select tt.eq('E5 acct_issue_out OFF (default): own-use issue NOT in the books', 0, tt.bal('5120') - :i0::numeric);
select set_rule('acct_issue_out','true') is null as aio_on \gset
select acct_post_pending(false) as ppi2 \gset
select tt.eq('E5 switch on later: backlog posts once, Dr 5120 42.73', 42.73, tt.bal('5120') - :i0::numeric, 0.01);
\endif
-- E3 online_keep_order_price
select tt.as(:'bt');
select web_order_submit('webform', gen_random_uuid(), 'Web Cust2', '01811000002', 'Dhaka 6', 'home', format('[{"item_id":"%s","qty":1}]', tt.iid('FG-CAKE'))::jsonb, 'price test')->>'subtotal' as sub2 \gset
select tt.as(:'o');
select id as oo2 from online_orders order by order_no desc limit 1 \gset
update items set sell_price = 320 where code='FG-CAKE';
select online_order_status(:'oo2'::uuid,'confirmed') is not null as c2 \gset
select online_order_status(:'oo2'::uuid,'packed') is not null as p2 \gset
select (online_order_deliver(:'oo2'::uuid, '[{"mode":"cash","amount":300}]')) as dv2 \gset
\echo DELIVER2: :dv2
update items set sell_price = 300 where code='FG-CAKE';
select rule_on('online_keep_order_price') as kop \gset
select (select total from sales order by receipt desc limit 1) as e3tot \gset
\echo MODEDIFF E3 order taken at 300, price list changed to 320 before delivery: sale total=:e3tot keep_order_price=:kop
select acct_post_pending(false) as ppz \gset

\echo == 12 reconciliation after the extras (relational checks only)
select acct_post_pending(false) as ppq \gset
select * from biz_daily(tt.today(), tt.today(), 1) \gset g_
select tt.eq('G1 report COGS == journal COGS', :g_cogs::numeric, tt.bal_loc('5000',1), 0.02);
select round(sum(-qty_delta * coalesce(unit_cost,0)),2) as gled from stock_ledger where ref_type in ('sale','sale_return','sale_pack') \gset
select tt.eq('G1 report COGS == stock ledger movement', :g_cogs::numeric, :gled::numeric, 0.02);
select profit_source_check(tt.today(), tt.today(), 1) as gpsc \gset
select tt.t('G1 profit_source_check agrees', (:'gpsc'::jsonb->>'agree')::boolean, 'true', :'gpsc'::jsonb->>'agree');
select tt.eq('G2 net revenue: report == journal (4100 - 4110)', :g_revenue::numeric, -(tt.bal_loc('4100',1) + tt.bal_loc('4110',1)), 0.02);
select tt.eq('G2 unbalanced entries', 0, tt.unbalanced());
select (acct_trial_balance(tt.today()-5, tt.today(), null)->>'balanced')::boolean as gtb \gset
select tt.t('G2 trial balance balanced', :'gtb'::boolean);
select tt.eq('G2 balance sheet difference', 0, (acct_balance_sheet(tt.today(), null)->>'difference')::numeric);
select tt.eq('G2 P&L net profit == balance sheet retained earnings', (acct_income_statement(tt.today()-5, tt.today(), null)->>'net_profit')::numeric, (acct_balance_sheet(tt.today(), null)->>'retained_earnings')::numeric, 0.02);
select inventory_vs_gl(tt.today(), 1) as gi \gset
select tt.eq('G3 inventory_vs_gl unexplained (true gap -200 = salt double count)', -200, (:'gi'::jsonb->'total'->>'unexplained')::numeric);
select tt.eq('G4 pending documents still waiting for the books (should be 0 or cost-missing only)', 0, (select count(*) from ledger_post_problems(1)));
