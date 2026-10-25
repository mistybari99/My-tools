-- FRESH DB ONLY. Phase 458 tests (RPT-C3 R7 part 1): campaign master list, campaign / offer code on a sale or an online order, audited export, helpers.
--   bash tests/sql/rptc3_build.sh t458 ; psql -h /tmp -p 5710 -U postgres -d t458 -qAt -f supabase/phase458_test.sql | grep -E 'FAIL|RESULT'
-- Built through its own phase (phase 458 only). Test data only (test_* names).
\ir ../tests/sql/rptc3_head.sql

-- T1 installed, paste twice keeps everything
select tt.chk('T1 helper present', _p458_present());
\i supabase/phase458.sql
select tt.chk('T1 paste twice: campaigns and tags survive', (select count(*) from option_lists where list_code='marketing_campaigns')=2 and (select count(*) from mkt_sale_tags)=3);
select tt.chk('T1 the list exists and is owner-only to add', (select add_rule from list_defs where list_code='marketing_campaigns')='owner');
select tt.chk('T1 nothing is seeded: the owner entered both campaigns', (select count(*) from option_lists where list_code='marketing_campaigns' and created_by is null)=0);
select tt.chk('T1 anon cannot run the tag or save functions', not has_function_privilege('anon','public.mkt_tag_sale(uuid,text,text)','execute') and not has_function_privilege('anon','public.mkt_campaign_save(text,jsonb)','execute'));
select tt.chk('T1 internal helpers are not callable by a signed-in user', not has_function_privilege('authenticated','public._c3_locs(integer)','execute'));

-- T2 campaign master: who may save, validation
select tt.as(:'u_st');
select tt.err('T2 a salesperson cannot add a campaign', $$select mkt_campaign_save(null, '{"name_bn":"test_gamma_x"}')$$, 'not allowed');
select tt.as(:'u_o');
select tt.err('T2 end before start is refused', $$select mkt_campaign_save(null, '{"name_bn":"test_delta_y","force":true,"start":"2026-12-10","end":"2026-12-01"}')$$, 'end_before_start');
select tt.err('T2 a bad date is refused', $$select mkt_campaign_save(null, '{"name_bn":"test_delta_y","force":true,"start":"2026-13-45"}')$$, 'bad_date');
select tt.err('T2 a bad budget is refused', $$select mkt_campaign_save(null, '{"name_bn":"test_delta_y","force":true,"budget":"-5"}')$$, 'bad_amount');
select tt.err('T2 a name is required', $$select mkt_campaign_save(null, '{"start":"2026-12-01"}')$$, 'name_required');
select mkt_campaign_save(tt.k('cb'), '{"budget":"500","channel":"test_channel"}') ->> 'status' as e1 \gset
select tt.chk('T2 an existing campaign gets its details', :'e1' = 'saved' and (select extra->>'budget' from option_lists where list_code='marketing_campaigns' and value_code=tt.k('cb')) in ('500', '500.0', '500.00'));
select tt.err('T2 an edit that puts the end before the start is refused', format($$select mkt_campaign_save('%s', '{"start":"2026-12-10","end":"2026-12-01"}')$$, tt.k('ca')), 'end_before_start');
select tt.err('T2 an unknown campaign cannot be edited', $$select mkt_campaign_save('no_such', '{"budget":"1"}')$$, 'bad_option');

-- T3 campaigns a till may pick
select mkt_active_campaigns() as act \gset
select tt.chk('T3 both campaigns are offered today', jsonb_array_length(:'act'::jsonb) = 2);
select option_retire('marketing_campaigns', tt.k('cb'), 'test retire') is not null as rt \gset
select tt.chk('T3 a retired campaign is not offered', jsonb_array_length(mkt_active_campaigns()) = 1);
select option_reactivate('marketing_campaigns', tt.k('cb')) is not null as ra \gset
select tt.chk('T3 and is offered again after reactivation', jsonb_array_length(mkt_active_campaigns()) = 2);
select mkt_campaign_save(null, jsonb_build_object('name_bn','test_future_c','force',true,'start',tt.today()+30)) ->> 'value_code' as fut \gset
select tt.chk('T3 a campaign that starts later is not offered yet', not exists (select 1 from jsonb_array_elements(mkt_active_campaigns()) x where x->>'code' = :'fut'));

-- T4 tag a sale
select tt.as(:'u_st');
select tt.chk('T4 the fixture tags are in place (campaign + offer code upper-cased)', (select offer_code from mkt_sale_tags where sale_id = tt.k('s1')::uuid) = 'TESTOFFER10');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',(select id from items where code='W1D-FG'))::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false)->>'id' as s5 \gset
select mkt_tag_sale(:'s5'::uuid, tt.k('ca'), 'summer1') as tg \gset
select tt.chk('T4 the cashier tags his own sale', (:'tg'::jsonb)->>'ok' = 'true' and (:'tg'::jsonb)->>'offer_code' = 'SUMMER1' and (:'tg'::jsonb)->>'crmf_installed' = 'false' and (:'tg'::jsonb)->>'coupon_known' = 'false');
select tt.chk('T4 the same tag again changes nothing', (mkt_tag_sale(:'s5'::uuid, tt.k('ca'), 'summer1'))->>'unchanged' = 'true');
select tt.chk('T4 a sale can be tagged by its client id (offline queue), by the cashier who made it', (mkt_tag_sale_client((select client_id from sales where id = :'s5'::uuid), tt.k('ca'), 'summer1'))->>'unchanged' = 'true');
select tt.err('T4 a cashier cannot change an existing tag', format($$select mkt_tag_sale('%s', '%s', null)$$, :'s5', tt.k('cb')), 'tag_change_needs_approver');
select tt.err('T4 an unknown campaign is refused', format($$select mkt_tag_sale('%s', 'no_such', null)$$, tt.k('s3')), 'unknown_campaign');
select tt.err('T4 a bad offer code is refused', format($$select mkt_tag_sale('%s', null, 'a b!')$$, tt.k('s3')), 'bad_offer_code');
select tt.err('T4 nothing to tag is refused', format($$select mkt_tag_sale('%s', null, null)$$, tt.k('s3')), 'nothing_to_tag');
select tt.err('T4 an unknown sale is refused', $$select mkt_tag_sale(gen_random_uuid(), null, 'X1')$$, 'sale_not_found');
select tt.as(:'u_o');
select mkt_tag_sale(:'s5'::uuid, tt.k('cb'), null) ->> 'ok' as ch \gset
select tt.chk('T4 the owner may change it', :'ch' = 'true' and (select campaign_code from mkt_sale_tags where sale_id = :'s5'::uuid) = tt.k('cb'));
select tt.chk('T4 a tag on a sale outside the campaign dates is allowed but said so', (mkt_tag_sale(tt.k('s3')::uuid, tt.k('ca'), null))->>'outside_campaign_dates' = 'false');
select void_sale(tt.k('s3')::uuid, 'test void') is not null as vs \gset
select tt.err('T4 a voided sale cannot be tagged', format($$select mkt_tag_sale('%s', null, 'ZZ9')$$, tt.k('s3')), 'sale_not_done');
select tt.as('00000000-0000-0000-0000-0000000fffff');
select tt.err('T4 an unknown login cannot tag', format($$select mkt_tag_sale('%s', null, 'ZZ9')$$, :'s5'), 'not allowed');
select tt.as(:'u_o');
select tt.chk('T4 the change is in audit_log', (select count(*) from audit_log where table_name = 'mkt_sale_tags' and record_id = :'s5') >= 2);
select tt.err('T4 a tag is never deleted', $$delete from mkt_sale_tags$$, 'nothing is deleted');
select tt.as(:'u_rm');
select tt.chk('T4 a report_marketing holder can read the tags of his place', (select count(*) from mkt_sale_tags) >= 3);
select tt.as(:'u_o');

-- T5 order tag + the campaign a sale belongs to
insert into online_orders (location_id, customer_name, customer_mobile, lines, subtotal, status, created_by, order_no, channel, delivery_mode)
  select 1, 'test_order_cust', '01800000555', '[{"qty":1,"price":100,"amount":100}]'::jsonb, 100, 'new', :'u_o'::uuid, 99001, 'phone', 'pickup' where not exists (select 1 from online_orders where order_no = 99001);
select id as oid from online_orders where order_no = 99001 \gset
select mkt_tag_order(:'oid'::uuid, tt.k('ca'), 'ORD5') ->> 'ok' as to1 \gset
select tt.chk('T5 an online order can carry a campaign and a code', :'to1' = 'true' and (select offer_code from mkt_order_tags where order_id = :'oid'::uuid) = 'ORD5');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',(select id from items where code='W1D-FG'))::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false)->>'id' as s6 \gset
update online_orders set sale_id = :'s6'::uuid where id = :'oid'::uuid;
select tt.chk('T5 a sale with no tag of its own takes the tag of the order it came from', (select campaign_code || '/' || offer_code || '/' || via from public._c3_sale_campaign(tt.today()-1, tt.today()+1, array[1]) where sale_id = :'s6'::uuid) = tt.k('ca') || '/ORD5/order');
select tt.chk('T5 a sale with its own tag keeps it', (select via from public._c3_sale_campaign(tt.today()-1, tt.today()+1, array[1]) where sale_id = tt.k('s1')::uuid) = 'sale');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',(select id from items where code='W1D-FG'))::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false)->>'id' as s7 \gset
select tt.chk('T5 an untagged sale is not in the list', not exists (select 1 from public._c3_sale_campaign(tt.today()-1, tt.today()+1, array[1]) where sale_id = :'s7'::uuid));
select tt.err('T5 an unknown order is refused', $$select mkt_tag_order(gen_random_uuid(), null, 'X1')$$, 'order_not_found');

-- T6 audited export
select tt.as(:'u_nb');
select tt.err('T6 nobody cannot export a marketing report', $$select rptc3_export_log('mkt_spend','csv','{}',3)$$, 'not allowed');
select tt.as(:'u_rm');
select tt.err('T6 a report reader without export_data cannot export', $$select rptc3_export_log('mkt_spend','csv','{}',3)$$, 'not allowed');
select tt.as(:'u_ex');
select rptc3_export_log('mkt_spend','csv','{"from":"2026-01-01"}',3) is not null as xl \gset
select tt.chk('T6 export_data + report_marketing may export, and it is audited', (select count(*) from audit_log where action='export' and table_name='report' and record_id='mkt_spend') = 1);
select tt.err('T6 an unknown report key is refused', $$select rptc3_export_log('nope','csv','{}',1)$$, 'unknown_report');
select tt.err('T6 the raw audit log export is owner only', $$select rptc3_export_log('aud_log','csv','{}',1)$$, 'not allowed');
select tt.err('T6 a marketing exporter cannot export a planning report of a group he cannot read', $$select rptc3_export_log('fc_scenario','csv','{}',1)$$, 'not allowed');
select tt.as(:'u_o');
select rptc3_export_log('aud_log','csv','{}',1) is not null as xo \gset
select tt.chk('T6 the owner may export the audit log', :'xo');
select tt.err('T6 a bad kind is refused', $$select rptc3_export_log('mkt_spend','c s v','{}',1)$$, 'bad_kind');

-- T7 helpers
select tt.chk('T7 range check', (select count(*) from (select public._c3_range(tt.today()-5, tt.today())) z) = 1);
select tt.err('T7 a reversed range is refused', $$select public._c3_range(current_date, current_date - 1)$$, 'bad_range');
select tt.err('T7 an empty range is refused', $$select public._c3_range(null, current_date)$$, 'bad_range');
select tt.chk('T7 an extra number that is text is read; junk is not captured', public._c3_xnum('{"a":"12.5","b":"x"}','a') = 12.5 and public._c3_xnum('{"a":"12.5","b":"x"}','b') is null);
select tt.chk('T7 a bad date inside extra is not captured', public._c3_xdate('{"d":"2026-99-99"}','d') is null and public._c3_xdate('{"d":"2026-10-05"}','d') = date '2026-10-05');
select tt.chk('T7 no journal entry is unbalanced', tt.unbalanced() = 0);

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
select name from tt.res where not ok;
