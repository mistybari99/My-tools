-- FRESH DB ONLY. Phase 531 (X6 workspace): topics, sources, findings, prices, opportunities, status machine, decisions, tasks, measuring from ERP.
--   bash tests/sql/x6_run.sh 531
\ir ../tests/sql/w1d_fixture.sql
\ir ../tests/sql/x6_head.sql
select mt.as(:'o');
select set_rule('mi_on', 'true');

-- T1 rights
select mt.as(:'nb');
select mt.err('T1 a person with no right can not save a topic', $$select mi_topic_save(null, '{"category":"prices","title_bn":"test_t","business_relevance":"test relevance"}'::jsonb)$$, 'not allowed');
select mt.as(:'vw');
select mt.err('T1 a viewer can not save a topic', $$select mi_topic_save(null, '{"category":"prices","title_bn":"test_t","business_relevance":"test relevance"}'::jsonb)$$, 'not allowed');
select mt.err('T1 a viewer can not add a finding', $$select mi_finding_add('{"source_url":"https://test-v.invalid/a","publisher":"p","summary":"test_v","finding_type":"analysis"}'::jsonb)$$, 'not allowed');
select mt.as(:'mgr');

-- T2 topics: add, check constraint, retire (reason mandatory)
select mi_topic_save(null, jsonb_build_object('category', 'prices', 'title_bn', 'test_price_topic', 'business_relevance', 'test relevance for prices', 'location_id', 1))->>'id' as topic \gset
select mt.chk('T2 a topic is saved active', (select status from mi_topics where id = :'topic') = 'active');
select mt.err('T2 an unknown category is refused', $$select mi_topic_save(null, '{"category":"nonsense","title_bn":"test_t","business_relevance":"test relevance"}'::jsonb)$$, 'mi_topics_category_check');
select mt.err('T2 retiring a topic needs a reason', format($$select mi_topic_retire('%s', '')$$, :'topic'), 'reason_required');
select mi_topic_save(null, jsonb_build_object('category', 'channels', 'title_bn', 'test_idle_topic', 'business_relevance', 'test idle relevance'))->>'id' as topic2 \gset
select mi_topic_retire(:'topic2', 'test retired for the check');
select mt.chk('T2 a retired topic is kept (not deleted) with its reason', (select status || ':' || retired_reason from mi_topics where id = :'topic2') = 'retired:test retired for the check');

-- T3 sources: the manager adds one; only the owner can allow scraping
select mi_source_save(null, jsonb_build_object('name', 'test_source_a', 'url', 'https://test-source.invalid/news/', 'publisher', 'test_publisher', 'source_type', 'website', 'reliability', 'B'))->>'id' as src \gset
select mt.chk('T3 a new source is saved with scraping NO', (select terms_allow_scraping from mi_sources where id = :'src') = false);
select mt.err('T3 the manager can not set the terms flag', format($$select mi_source_save('%s', '{"terms_allow_scraping": true, "terms_checked_on": "2026-01-01"}'::jsonb)$$, :'src'), 'only the owner');
select mt.as(:'o');
select mt.err('T3 scraping ON needs the terms check date', format($$select mi_source_save('%s', '{"terms_allow_scraping": true}'::jsonb)$$, :'src'), 'mi_sources_check');
select mi_source_save(:'src', jsonb_build_object('terms_allow_scraping', true, 'terms_checked_on', to_char(mt.today(), 'YYYY-MM-DD'), 'robots_ok', true, 'rate_limit_per_hour', 10))->>'terms_allow_scraping' as tas \gset
select mt.chk('T3 the owner sets the terms flag with a date', :'tas' = 'true');

-- T4 findings: scores, duplicates, quote limit, required fields (manager)
select mt.as(:'mgr');
select mi_finding_add(jsonb_build_object('source_id', :'src', 'source_url', 'https://test-source.invalid/news/item-1?utm=x', 'summary', 'test_summary one about a price change',
  'published_on', to_char(mt.today() - 10, 'YYYY-MM-DD'), 'retrieved_on', to_char(mt.today(), 'YYYY-MM-DD'), 'finding_type', 'sourced_fact', 'topic_id', :'topic'))::text as f1 \gset
select (:'f1'::jsonb)->>'id' as f1id \gset
select mt.chk('T4 freshness 3 for a publication 10 days old', (:'f1'::jsonb)->>'freshness_score' = '3');
select mt.chk('T4 quality 5 = sourced fact 3 + source B 2', (:'f1'::jsonb)->>'quality_score' = '5');
select mi_finding_add(jsonb_build_object('source_url', 'https://www.test-source.invalid/news/item-1', 'summary', 'test_summary two, a different sentence',
  'retrieved_on', to_char(mt.today(), 'YYYY-MM-DD'), 'finding_type', 'hypothesis', 'source_id', :'src'))::text as f2 \gset
select mt.chk('T4 same page with another query string is a duplicate of the first', (:'f2'::jsonb)->>'duplicate_of' = :'f1id');
select mi_finding_add(jsonb_build_object('source_url', 'https://test-other.invalid/x', 'publisher', 'test_other', 'summary', 'TEST_SUMMARY  one about a price change',
  'retrieved_on', to_char(mt.today(), 'YYYY-MM-DD'), 'finding_type', 'analysis'))::text as f3 \gset
select mt.chk('T4 the same summary on another page is also a duplicate', (:'f3'::jsonb)->>'duplicate_of' = :'f1id');
select mt.chk('T4 a finding with no publication date gets freshness 0', (:'f2'::jsonb)->>'freshness_score' = '0');
select mt.err('T4 a quote is refused while the owner has not set a limit', $$select mi_finding_add('{"source_url":"https://test-q.invalid/a","publisher":"p","summary":"test_q","quote":"a short quote","finding_type":"analysis"}'::jsonb)$$, 'quote_not_allowed');
select mt.err('T4 a publisher is required when there is no source', $$select mi_finding_add('{"source_url":"https://test-q.invalid/b","summary":"test_q2","finding_type":"analysis"}'::jsonb)$$, 'publisher_required');
select mt.err('T4 an unknown finding type is refused', $$select mi_finding_add('{"source_url":"https://test-q.invalid/c","publisher":"p","summary":"test_q3","finding_type":"rumour"}'::jsonb)$$, 'bad_finding_type');
select mt.err('T4 a finding can not be changed after it is saved', format($$update mi_findings set summary = 'x' where id = '%s'$$, :'f1id'), 'append_only');

-- T5 competitor prices and CSV import (bad rows are reported, the good ones are kept)
select mi_price_add(jsonb_build_object('competitor', 'test_rival_a', 'item_label', 'test_cake_1kg', 'price', '1200', 'observed_on', to_char(mt.today() - 3, 'YYYY-MM-DD')))->>'id' as p1 \gset
select mi_price_import('[{"competitor":"test_rival_a","item_label":"test_cake_1kg","price":"1300"},{"competitor":"test_rival_b","item_label":"test_cake_1kg","price":"abc"},{"competitor":"","item_label":"x","price":"5"}]'::jsonb)::text as imp \gset
select mt.chk('T5 the import keeps the one good row', (:'imp'::jsonb)->>'inserted' = '1');
select mt.chk('T5 the import reports the two bad rows', jsonb_array_length((:'imp'::jsonb)->'rejected') = 2);
select mt.chk('T5 the competitor price log holds 2 rows (1 manual + 1 imported)', (select count(*) from mi_price_obs where competitor like 'test_rival%') = 2);

-- T6 opportunities: evidence, KPI and confidence limits are required; benefit ranges must make sense
select mt.err('T6 an opportunity with no evidence is refused', $$select mi_opportunity_save(null, '{"title":"test_opp_x","category":"prices","evidence_finding_ids":[],"confidence":"low","confidence_limits":"test limits","success_kpi":"units","kpi_target":5}'::jsonb)$$, 'evidence_required');
select mt.err('T6 an opportunity with no KPI is refused', format($$select mi_opportunity_save(null, '{"title":"test_opp_x","category":"prices","evidence_finding_ids":["%s"],"confidence":"low","confidence_limits":"test limits"}'::jsonb)$$, :'f1id'), 'kpi_required');
select mi_opportunity_save(null, jsonb_build_object('title', 'test_raise_price_10pct', 'category', 'prices', 'topic_id', :'topic', 'evidence_finding_ids', jsonb_build_array(:'f1id'),
  'benefit_low', 1000, 'benefit_base', 2000, 'benefit_basis', 'test: 20 units a week at 100 margin', 'cost_estimate', 0, 'assumptions', 'test assumption', 'risks', 'test risk',
  'confidence', 'low', 'confidence_limits', 'one competitor, two weeks of prices; does not prove the rival caused any change', 'success_kpi', 'cake units per week', 'kpi_baseline', 12, 'kpi_target', 20,
  'next_action', 'test next step'))::text as o1 \gset
select (:'o1'::jsonb)->>'id' as opp \gset
select mt.chk('T6 a new opportunity starts as proposed', (:'o1'::jsonb)->>'status' = 'proposed');
select mt.err('T6 low above base is refused', format($$select mi_opportunity_save('%s', '{"benefit_low": 5000}'::jsonb)$$, :'opp'), 'benefit_low_above_base');

-- T7 status machine: own request can not be approved by the same person; reason mandatory; illegal moves refused
select mt.err('T7 the person who asked can not approve it', format($$select mi_opportunity_move('%s', 'approved', 'test self approve')$$, :'opp'), 'own_request');
select mt.err('T7 a move needs a reason', format($$select mi_opportunity_move('%s', 'saved', '')$$, :'opp'), 'reason_required');
select mt.err('T7 proposed can not jump to done', format($$select mi_opportunity_move('%s', 'done', 'test jump')$$, :'opp'), 'bad_move');
select mt.err('T7 measured can not be set by hand', format($$select mi_opportunity_move('%s', 'measured', 'test by hand')$$, :'opp'), 'use_measure');
select mi_opportunity_move(:'opp', 'saved', 'test saved while we wait for approval');
select mt.chk('T7 saved is a valid move', (select status from mi_opportunities where id = :'opp') = 'saved');
select mt.as(:'o');
select mi_opportunity_move(:'opp', 'approved', 'test approved by owner, the evidence is one page')->>'to' as ap \gset
select mt.chk('T7 the owner approves the request', :'ap' = 'approved');
select mt.as(:'mgr');
select mt.err('T7 an approved record can not be edited (locked)', format($$select mi_opportunity_save('%s', '{"next_action":"test edit"}'::jsonb)$$, :'opp'), 'locked_after_decision');
select mt.err('T7 tasks need the task list switched on', format($$select mi_opportunity_task('%s', 'test_task', now() + interval '1 day')$$, :'opp'), 'module_off');
select mt.as(:'o');
select set_rule('crm_task_on', 'true');
select mt.as(:'mgr');
select mi_opportunity_task(:'opp', 'test_follow_up_task', now() + interval '1 day')->>'task_id' as tk \gset
select mt.chk('T8 the task is in the task list, linked, and from this record', exists (select 1 from crm_tasks t join mi_opp_links l on l.task_id = t.id where l.opp_id = :'opp' and t.id = :'tk'::uuid and t.source = 'manual'));
select mi_opportunity_move(:'opp', 'in_progress', 'test work started')->>'to' as ip \gset
select mi_opportunity_move(:'opp', 'done', 'test work finished')->>'to' as dn \gset
select mt.chk('T7 approved -> in progress -> done', :'ip' = 'in_progress' and :'dn' = 'done');

-- T9 measuring: from ERP sales only; nothing typed in
select mi_opportunity_save(null, jsonb_build_object('title', 'test_opp_second', 'category', 'prices', 'evidence_finding_ids', jsonb_build_array(:'f1id'),
  'confidence', 'low', 'confidence_limits', 'test limits for the second record', 'success_kpi', 'units', 'kpi_target', 3))->>'id' as opp2 \gset
select mt.err('T9 an opportunity that is not done can not be measured', format($$select mi_opportunity_measure('%s', current_date, current_date, current_date - 7, current_date - 1)$$, :'opp2'), 'not_done');
select mi_opportunity_measure(:'opp'::uuid, mt.today(), mt.today(), mt.today() - 7, mt.today() - 1)::text as ms \gset
select mt.chk('T9 the record is measured', (select status from mi_opportunities where id = :'opp') = 'measured');
select mt.chk('T9 the outcome carries the coverage and the correlation warning', (:'ms'::jsonb)->>'warning' like '%does not prove%' and (:'ms'::jsonb)->>'actual_days' is not null);
select mt.chk('T9 the actual equals the ERP net sales of today (place 1)', ((:'ms'::jsonb)->>'actual')::numeric = (select coalesce(sum(net), 0) from sales_fact where status = 'done' and day = mt.today() and location_id = 1));
select mt.chk('T9 the outcome row is kept (append-only)', (select count(*) from mi_opp_outcomes where opp_id = :'opp') = 1);

-- T10 decisions: every move has a reason, kept for ever
select mt.chk('T10 five decisions (saved, approved, in progress, done, measured), each with a reason', (select count(*) = 5 and bool_and(length(reason) >= 3) from mi_opp_decisions where opp_id = :'opp'));
select mt.err('T10 a decision can not be changed', format($$update mi_opp_decisions set reason = 'xx' where opp_id = '%s'$$, :'opp'), 'append_only');
select mt.err('T10 a decision can not be deleted', format($$delete from mi_opp_decisions where opp_id = '%s'$$, :'opp'), 'append_only');

-- T11 summary for the page
select mt.as(:'vw');
select mi_summary()->'opportunities'->>'measured' as ms2 \gset
select mt.chk('T11 the viewer sees the measured count', :'ms2' = '1');
select mt.as(:'nb');
select mt.err('T11 a person with no right can not read the summary', $$select mi_summary()$$, 'not allowed');

select 'x6 phase531: ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' as result from mt.res;
