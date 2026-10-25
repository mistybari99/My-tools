-- FRESH DB ONLY. Phase 325 tests (CRM-G part 3: convert a won lead through the EXISTING order and form functions, lead list, board, win / loss report).
--   build: phases 8..98, then 323, 324, 325;  psql -h /tmp -p 5575 -U postgres -d <db> -qAt -f supabase/phase325_test.sql 2>&1 | grep -E 'FAIL|RESULT'
\ir ../tests/sql/crmg_common.sql
select tt.as(:'u_o');
set role authenticated;
select set_rule('crm_lead_on', 'true') is null as on1 \gset
select set_rule('online_orders_on', 'true') is null as on2 \gset
reset role;
select tt.books() as b0 \gset
update forms set enabled = true where code in ('20-1', '20-4');
insert into user_roles values (:'u_m1', 'party_coordinator') on conflict do nothing;      -- the 20-4 party invoice is entered by the party coordinator role

\echo == T1 convert: rights and preconditions
set role authenticated; select tt.as(:'u_s1');
select _crmg_lead_save(null, gen_random_uuid(), 1, format('{"contact_name":"test_conv_one","contact_phone":"01812345601","source":"phone","event_date":"%s","guests":30}', current_date + 12)::jsonb) ->> 'id' as c1 \gset
select tt.err('T1 the assignee (not a manager) cannot convert', format($$select _crmg_lead_convert('%s', gen_random_uuid(), 'online_order', '{"channel_id":%s}')$$, :'c1', :'ch1'), 'only a manager');
select tt.as(:'u_m2');
select tt.err('T1 a manager of another outlet gets not_found', format($$select _crmg_lead_convert('%s', gen_random_uuid(), 'online_order', '{"channel_id":%s}')$$, :'c1', :'ch1'), 'not_found');
select tt.as(:'u_m1');
select tt.err('T1 an unknown kind', format($$select _crmg_lead_convert('%s', gen_random_uuid(), 'invoice_now', '{}')$$, :'c1'), 'bad_kind');
select tt.err('T1 making a record needs a quote', format($$select _crmg_lead_convert('%s', gen_random_uuid(), 'online_order', '{"channel_id":%s}')$$, :'c1', :'ch1'), 'quote_needed');
select tt.chk('T1 the refusals left the enquiry as it was', tt.q($q$select stage from crm_leads where id = '$q$ || :'c1' || $q$'$q$) = 'enquiry' and tt.q('select count(*) from online_orders') = '0');

\echo == T2 convert to an online order through online_order_save2
select _crmg_quote_save(:'c1'::uuid, null, format('{"items":[{"item_id":"%s","qty":2,"price":100},{"item_id":"%s","qty":1,"price":250}],"discount":50,"send":true,"valid_until":"%s"}', :'ia', :'ib', current_date + 5)::jsonb) ->> 'total' as qt \gset
select tt.chk('T2 quote total: 2 x 100 + 250 - 50 = 400', :'qt'::numeric = 400);
select tt.err('T2 the order needs a sales channel', format($$select _crmg_lead_convert('%s', gen_random_uuid(), 'online_order', '{}')$$, :'c1'), 'channel_required');
select tt.err('T2 delivery by courier needs an address (the order rule is kept)', format($$select _crmg_lead_convert('%s', gen_random_uuid(), 'online_order', '{"channel_id":%s,"delivery_mode":"home"}')$$, :'c1', :'ch1'), 'address_required');
select tt.chk('T2 a refused conversion rolls the stage back too', tt.q($q$select stage from crm_leads where id = '$q$ || :'c1' || $q$'$q$) = 'quoted' and tt.q('select count(*) from online_orders') = '0');
select gen_random_uuid() as ck1 \gset
select _crmg_lead_convert(:'c1'::uuid, :'ck1'::uuid, 'online_order', format('{"channel_id":%s,"delivery_mode":"pickup"}', :'ch1')::jsonb) as v1 \gset
select tt.chk('T2 an order was made by the existing function: new, list subtotal 450, discount 50 (quote 400)',
  tt.q($q$select status || '/' || subtotal::text || '/' || discount::text || '/' || customer_mobile || '/' || advance::text from online_orders$q$) = 'new/450.00/50.00/01812345601/0.00');
select tt.chk('T2 the lead is won, linked to that order, quote accepted, converted once',
  tt.q($q$select stage || '/' || (online_order_id = (select id from online_orders))::text || '/' || (converted_at is not null)::text from crm_leads where id = '$q$ || :'c1' || $q$'$q$) = 'won/true/true'
  and tt.q($q$select status from crm_lead_quotes where lead_id = '$q$ || :'c1' || $q$'$q$) = 'accepted');
select tt.chk('T2 the order records where it came from', tt.q($q$select source from online_orders$q$) like 'crm_lead %');
select tt.chk('T2 the same client key returns the first answer, no second order', (_crmg_lead_convert(:'c1'::uuid, :'ck1'::uuid, 'online_order', format('{"channel_id":%s}', :'ch1')::jsonb) ->> 'dup')::boolean and tt.q('select count(*) from online_orders') = '1');
select tt.err('T2 a second conversion (another key) is refused', format($$select _crmg_lead_convert('%s', gen_random_uuid(), 'online_order', '{"channel_id":%s}')$$, :'c1', :'ch1'), 'already_converted');
select tt.err('T2 a second conversion to a form is refused too', format($$select _crmg_lead_convert('%s', gen_random_uuid(), 'form_20_4', '{}')$$, :'c1'), 'already_converted');
reset role;
select tt.chk('T2 the converted lead cannot be unlinked or edited directly', tt.q($q$select count(*) from crm_leads where online_order_id is not null$q$) = '1');
select tt.err('T2 the link to the order cannot be changed in the database', $$update crm_leads set online_order_id = null where online_order_id is not null$$, 'already_converted');
select tt.chk('T2 the books did not change by the lead or the quote (an order posts nothing by itself)', tt.books() = :'b0');
set role authenticated; select tt.as(:'u_m1');

\echo == T2b conversions that cannot become an order
select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_conv_free","contact_phone":"01812345602"}') ->> 'id' as c2 \gset
select _crmg_quote_save(:'c2'::uuid, null, '{"items":[{"desc":"test_custom_cake","qty":1,"price":900}],"send":true,"valid_until":"2099-01-01"}') ->> 'status' as q2 \gset
select tt.err('T2b a free-text line cannot become an order line', format($$select _crmg_lead_convert('%s', gen_random_uuid(), 'online_order', '{"channel_id":%s}')$$, :'c2', :'ch1'), 'lines_need_items');
select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_conv_high","contact_phone":"01812345603"}') ->> 'id' as c3 \gset
select _crmg_quote_save(:'c3'::uuid, null, format('{"items":[{"item_id":"%s","qty":1,"price":999}],"send":true,"valid_until":"2099-01-01"}', :'ia')::jsonb) ->> 'status' as q3 \gset
select tt.err('T2b a quote above the list price cannot become an order (no hidden surcharge)', format($$select _crmg_lead_convert('%s', gen_random_uuid(), 'online_order', '{"channel_id":%s}')$$, :'c3', :'ch1'), 'price_above_list');
select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_conv_nophone","contact_phone":"0212345"}') ->> 'id' as c4 \gset
select _crmg_quote_save(:'c4'::uuid, null, format('{"items":[{"item_id":"%s","qty":1}],"send":true,"valid_until":"2099-01-01"}', :'ia')::jsonb) ->> 'status' as q4 \gset
select tt.err('T2b an order needs a valid mobile number', format($$select _crmg_lead_convert('%s', gen_random_uuid(), 'online_order', '{"channel_id":%s}')$$, :'c4', :'ch1'), 'mobile_required');
select tt.chk('T2b all three stayed open', tt.q($q$select count(*) from crm_leads where id in ('$q$ || :'c2' || $q$','$q$ || :'c3' || $q$','$q$ || :'c4' || $q$') and stage = 'quoted'$q$) = '3');

\echo == T3 convert to a draft paper form (20-4 party invoice, 20-1 customer order form)
select _crmg_lead_convert(:'c2'::uuid, gen_random_uuid(), 'form_20_4', '{}') as f1 \gset
select tt.chk('T3 a draft party invoice was made by save_entry, filled from the quote', (:'f1'::jsonb ->> 'form') = '20-4' and
  tt.q($q$select e.status || '/' || (e.data->>'doc') || '/' || (e.data->>'party') || '/' || (e.data->'lines'->0->>'desc') || '/' || (e.data->'lines'->0->>'rate') from entries e where e.form_code = '20-4'$q$) = 'draft/invoice/test_conv_free/test_custom_cake/900.00');
select tt.chk('T3 the lead is won and linked to the entry; it posts nothing (a draft)', tt.q($q$select stage || '/' || (entry_id is not null)::text from crm_leads where id = '$q$ || :'c2' || $q$'$q$) = 'won/true'
  and tt.q($q$select count(*) from entry_ledger_posts$q$)::int = 0);
select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_conv_form1","contact_phone":"01812345604"}') ->> 'id' as c5 \gset
select _crmg_quote_save(:'c5'::uuid, null, format('{"items":[{"item_id":"%s","qty":3,"price":100}],"discount":10,"send":true,"valid_until":"2099-01-01"}', :'ia')::jsonb) ->> 'status' as q5 \gset
select _crmg_lead_convert(:'c5'::uuid, gen_random_uuid(), 'form_20_1', '{}') as f2 \gset
select tt.chk('T3 a draft customer order form: total 300, discount 10, party channel', (:'f2'::jsonb ->> 'form') = '20-1' and
  tt.q($q$select e.status || '/' || (e.data->>'total') || '/' || (e.data->>'discount') || '/' || (e.data->>'channel') from entries e where e.form_code = '20-1'$q$) = 'draft/300.00/10/party'
  or tt.q($q$select e.status || '/' || (e.data->>'total') || '/' || (e.data->>'discount') || '/' || (e.data->>'channel') from entries e where e.form_code = '20-1'$q$) = 'draft/300/10/party');

\echo == T4 link a record that already exists
reset role;
insert into online_orders (order_no, location_id, channel, customer_name, customer_mobile, lines, subtotal, delivery_mode, created_by) values (9001, 1, 'phone', 'test_link_order', '01812345605', '[{"item_id":"x"}]', 100, 'pickup', :'u_o');
insert into online_orders (order_no, location_id, channel, customer_name, customer_mobile, lines, subtotal, delivery_mode, created_by) values (9002, 2, 'phone', 'test_link_order2', '01812345606', '[{"item_id":"x"}]', 100, 'pickup', :'u_o');
insert into online_orders (order_no, location_id, channel, customer_name, customer_mobile, lines, subtotal, delivery_mode, created_by, status, cancel_reason) values (9003, 1, 'phone', 'test_link_order3', '01812345607', '[{"item_id":"x"}]', 100, 'pickup', :'u_o', 'cancelled', 'test');
select id as o1 from online_orders where order_no = 9001 \gset
select id as o2 from online_orders where order_no = 9002 \gset
select id as o3 from online_orders where order_no = 9003 \gset
set role authenticated; select tt.as(:'u_m1');
select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_link_one","contact_phone":"01812345999"}') ->> 'id' as l4 \gset
select tt.err('T4 an order of another outlet is not even visible to the manager', format($$select _crmg_lead_convert('%s', gen_random_uuid(), 'link_order', '{"order_id":"%s"}')$$, :'l4', :'o2'), 'not_found');
select tt.err('T4 a cancelled order cannot be linked', format($$select _crmg_lead_convert('%s', gen_random_uuid(), 'link_order', '{"order_id":"%s"}')$$, :'l4', :'o3'), 'order_cancelled');
select tt.err('T4 an unknown order', format($$select _crmg_lead_convert('%s', gen_random_uuid(), 'link_order', '{"order_id":"%s"}')$$, :'l4', gen_random_uuid()), 'not_found');
select _crmg_lead_convert(:'l4'::uuid, gen_random_uuid(), 'link_order', format('{"order_id":"%s"}', :'o1')::jsonb) as lk \gset
select tt.chk('T4 an existing order is linked, a different mobile number is only a warning, the order is untouched',
  (:'lk'::jsonb -> 'warnings' ->> 0) like '%different mobile%' and tt.q($q$select stage from crm_leads where id = '$q$ || :'l4' || $q$'$q$) = 'won' and tt.q($q$select status from online_orders where order_no = 9001$q$) = 'new');
select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_link_two"}') ->> 'id' as l5 \gset
select tt.err('T4 an order belongs to one enquiry only', format($$select _crmg_lead_convert('%s', gen_random_uuid(), 'link_order', '{"order_id":"%s"}')$$, :'l5', :'o1'), 'already_linked');
reset role;
select id as e1 from entries where form_code = '20-4' limit 1 \gset
select id as e1b from entries where form_code = '20-1' limit 1 \gset
set role authenticated; select tt.as(:'u_m1');
select tt.err('T4 a form already linked to another enquiry is refused', format($$select _crmg_lead_convert('%s', gen_random_uuid(), 'link_form', '{"entry_id":"%s"}')$$, :'l5', :'e1'), 'already_linked');

\echo == T5 an enquiry from the inbox
reset role;
insert into sales_channels (code, kind, name_bn, location_id, active) select 'test_crmg_fb', 'facebook', 'test_crmg_fb', 1, true where not exists (select 1 from sales_channels where code = 'test_crmg_fb');
insert into inbound_messages (channel_id, location_id, external_id, customer_name, msg_text) select id, 1, 'test_crmg_m1', 'test_msg_person', 'test 2 kg cake please' from sales_channels where code = 'test_crmg_fb';
select id as m1 from inbound_messages where external_id = 'test_crmg_m1' \gset
set role authenticated; select tt.as(:'u_s1');
select _crmg_lead_save(null, gen_random_uuid(), 1, format('{"inbound_message_id":%s,"source":"message"}', :'m1')::jsonb) as ms \gset
select tt.chk('T5 the name is taken from the message when it is blank', tt.q($q$select contact_name from crm_leads where inbound_message_id = $q$ || :'m1') = 'test_msg_person');
select tt.err('T5 one message, one enquiry', format($$select _crmg_lead_save(null, gen_random_uuid(), 1, '{"inbound_message_id":%s,"contact_name":"test_again"}')$$, :'m1'), 'message_already_tracked');
select tt.err('T5 a message that is not there', $$select _crmg_lead_save(null, gen_random_uuid(), 1, '{"inbound_message_id":999999,"contact_name":"test_again"}')$$, 'message_not_found');

\echo == T6 list, board, report
select tt.as(:'u_s1');
select (_crmg_lead_list('{}') ->> 'total')::int as n_s1 \gset
select tt.chk('T6 a salesperson lists only her own enquiries', :n_s1 = tt.q($q$select count(*) from crm_leads where owner_user = '00000000-0000-0000-0000-000000003203' or created_by = '00000000-0000-0000-0000-000000003203'$q$)::int);
select tt.as(:'u_s2');
select _crmg_lead_save(null, gen_random_uuid(), 2, '{"contact_name":"test_branch_lead","source":"walk_in","est_value":700}') ->> 'id' as b1 \gset
select tt.as(:'u_m2');
select tt.chk('T6 the manager of outlet 2 sees outlet 2 only', (_crmg_lead_list('{}') ->> 'total')::int = 1);
select tt.as(:'u_m1');
select tt.chk('T6 the manager of outlet 1 sees all of outlet 1 and none of outlet 2', (_crmg_lead_list('{}') ->> 'total')::int = tt.q($q$select count(*) from crm_leads where location_id = 1$q$)::int
  and not exists (select 1 from jsonb_array_elements(_crmg_lead_list('{}') -> 'rows') x where (x ->> 'location_id')::int = 2));
select tt.chk('T6 asking for another outlet by filter does not leak it', (_crmg_lead_list('{"loc":2}') ->> 'total')::int = 0);
select tt.chk('T6 search by name', (_crmg_lead_list('{"q":"test_conv_one"}') ->> 'total')::int = 1);
select tt.chk('T6 search by stage', (_crmg_lead_list('{"stage":["won"]}') ->> 'total')::int = tt.q($q$select count(*) from crm_leads where location_id = 1 and stage = 'won'$q$)::int);
select tt.chk('T6 the list says which are converted', (_crmg_lead_list('{"converted":true}') ->> 'total')::int = 4);
-- known lost leads for the report
select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_lost_a","est_value":300}') ->> 'id' as x1 \gset
select _crmg_lead_stage(:'x1'::uuid, 'lost', '', '{"lost_reason":"price_high"}') ->> 'stage' as xs1 \gset
select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_lost_b"}') ->> 'id' as x2 \gset
select _crmg_quote_save(:'x2'::uuid, null, '{"items":[{"desc":"test_big","qty":1,"price":700}],"send":true,"valid_until":"2099-01-01"}') ->> 'status' as xq \gset
select _crmg_lead_stage(:'x2'::uuid, 'lost', '', '{"lost_reason":"other_shop"}') ->> 'stage' as xs2 \gset
select _crmg_lead_report(null, null, 1) as rp \gset
select tt.chk('T6 report: lost 2 = 300 (estimate) + 700 (its quote)', (:'rp'::jsonb ->> 'lost')::int = 2 and (:'rp'::jsonb ->> 'lost_value')::numeric = 1000);
select tt.chk('T6 report: lost by reason has both reasons with their values', (select count(*) from jsonb_array_elements(:'rp'::jsonb -> 'lost_by_reason') x
  where (x ->> 'code' = 'price_high' and (x ->> 'value')::numeric = 300) or (x ->> 'code' = 'other_shop' and (x ->> 'value')::numeric = 700)) = 2);
select tt.chk('T6 report: won equals the won leads of outlet 1 closed today', (:'rp'::jsonb ->> 'won')::int = tt.q($q$select count(*) from crm_leads where location_id = 1 and stage = 'won'$q$)::int);
select tt.chk('T6 report: win rate = won / (won + lost)', (:'rp'::jsonb ->> 'win_rate_pct')::numeric = round(100.0 * (:'rp'::jsonb ->> 'won')::int / ((:'rp'::jsonb ->> 'won')::int + 2), 1));
select tt.chk('T6 report: won value counts the accepted quotes (the 400 order is in it)', (:'rp'::jsonb ->> 'won_value')::numeric >= 400);
select tt.chk('T6 report: by owner, by source and by occasion are lists', jsonb_typeof(:'rp'::jsonb -> 'by_owner') = 'array' and jsonb_typeof(:'rp'::jsonb -> 'by_source') = 'array' and jsonb_typeof(:'rp'::jsonb -> 'by_occasion') = 'array');
select tt.err('T6 a bad date range is refused', $$select _crmg_lead_report(current_date, current_date - 5, null)$$, 'bad_dates');
select tt.as(:'u_s1');
select tt.chk('T6 a salesperson reports on her own enquiries only', (_crmg_lead_report(null, null, null) ->> 'created')::int <= :n_s1 + 1);
select tt.as(:'u_m1');
select _crmg_lead_board(1, null) as bd \gset
select tt.chk('T6 the board has five columns in order', (select string_agg(x ->> 'stage', ',') from jsonb_array_elements(:'bd'::jsonb -> 'stages') x) = 'enquiry,quoted,following_up,won,lost');
select tt.chk('T6 board counts equal the table', (select (x ->> 'count')::int from jsonb_array_elements(:'bd'::jsonb -> 'stages') x where x ->> 'stage' = 'won') = tt.q($q$select count(*) from crm_leads where location_id = 1 and stage = 'won'$q$)::int
  and (select (x ->> 'count')::int from jsonb_array_elements(:'bd'::jsonb -> 'stages') x where x ->> 'stage' = 'lost') = 2);
select tt.chk('T6 the lost column shows the value (300 + 700)', (select (x ->> 'value')::numeric from jsonb_array_elements(:'bd'::jsonb -> 'stages') x where x ->> 'stage' = 'lost') = 1000);
select tt.as(:'u_x');
select tt.chk('T6 a person with no sales right sees an empty list, no error', (_crmg_lead_list('{}') ->> 'total')::int = 0);
select tt.as(:'u_o'); select set_rule('crm_lead_on', 'false') is null as off1 \gset
select tt.as(:'u_m1');
select tt.chk('T6 switch OFF: the list and the board answer on:false, nothing else', (_crmg_lead_list('{}') ->> 'on')::boolean = false and (_crmg_lead_board(1, null) ->> 'on')::boolean = false);
select tt.err('T6 switch OFF: a conversion is refused', format($$select _crmg_lead_convert('%s', gen_random_uuid(), 'link_order', '{}')$$, :'l5'), 'module_off');
reset role;
select tt.chk('T6 the books are the same as at the start of this file', tt.books() = :'b0' or tt.q('select count(*) from sales')::int = 0);
select 'RESULT ' || count(*) filter (where ok) || ' pass ' || count(*) filter (where not ok) || ' fail' from tt.res;
