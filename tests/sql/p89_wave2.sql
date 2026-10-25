-- Phase 89 before/after: the second wave of work, run on the install WITH phase 89 + hooks and on the twin WITHOUT them. With every W1-B setting at its default the reports must agree.
-- The books are closed up to 5 days ago by the typed date; the owner (silent today) works in the closed period, back-dates, sends a late offline sale, and the poster runs.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000987',false);
select set_rule('period_closed_until', to_jsonb(((now() at time zone 'Asia/Dhaka')::date - 5)::text)) is null as lk;
select cash_move_add(1,'owner_topup',910,(now() at time zone 'Asia/Dhaka')::date - 8,'cash',null,'w89',null,gen_random_uuid(),false) is not null as c1;
select cash_move_add(1,'owner_draw',420,date '2000-01-02','bank',null,'w89',null,gen_random_uuid(),false) is not null as c2;
select quick_expense_add(1, (now() at time zone 'Asia/Dhaka')::date - 6, 'transport', 'test_rider', 77, 'cash', false, null, gen_random_uuid()) is not null as q1;
select quick_expense_add(1, (now() at time zone 'Asia/Dhaka')::date, 'transport', 'test_rider', 33, 'mobile', false, null, gen_random_uuid()) is not null as q2;
select save_purchase(gen_random_uuid(), null, (select id from suppliers where name='test_supplier_ba'), 1, 'W89-1', (now() at time zone 'Asia/Dhaka')::date - 400, '[{"description":"x","qty":1,"unit_cost":5}]'::jsonb) is not null as p1;
select record_sale2(gen_random_uuid(),1,'[{"amount":333}]',0,'[{"mode":"cash","amount":333}]',null,null,'retail',null,true, now() - interval '80 hours') is not null as s1;
select record_sale2(gen_random_uuid(),1,'[{"amount":222}]',0,'[{"mode":"mobile","amount":222}]',null,null,'retail',null,true, now() - interval '5 hours') is not null as s2;
select acct_post_pending(false) ->> 'posted';
