-- FRESH DB ONLY. Phase 490 (X6 research hook OFF, summariser proposals, price alerts, owner digest). No network: the mock adapter only.
--   bash tests/sql/x6_run.sh 490
\ir ../tests/sql/w1d_fixture.sql
\ir ../tests/sql/x6_head.sql
select mt.as(:'o');
select set_rule('mi_on', 'true');

-- T1 the research gate is closed by default, with reasons in words
select mi_source_save(null, jsonb_build_object('name', 'test_src_gate', 'url', 'https://test-gate.invalid/feed', 'publisher', 'test_pub_gate', 'source_type', 'rss', 'reliability', 'C'))->>'id' as src \gset
select mi_research_gate(:'src'::uuid)::text as g0 \gset
select mt.chk('T1 the gate is closed by default', (:'g0'::jsonb)->>'allowed' = 'false');
select mt.chk('T1 the reasons name the switches and the terms flag', (:'g0'::jsonb)->>'reasons' like '%mi_research_job_on%' and (:'g0'::jsonb)->>'reasons' like '%terms flag is NO%');

-- T2 a job can not be turned on while the gate is closed
select mt.err('T2 a job can not be switched on while the gate is closed', format($$select mi_job_save('test_job_gate', '{"label":"test job","source_id":"%s","enabled":true}'::jsonb)$$, :'src'), 'gate_closed');
select mi_job_save('test_job_gate', jsonb_build_object('label', 'test job', 'source_id', :'src', 'enabled', false))->>'enabled' as je \gset
select mt.chk('T2 a job can be stored OFF', :'je' = 'false');

-- T3 adapters: the network is linked by the owner only; the mock never uses the network
select mt.err('T3 the mock adapter can not be linked to the network', $$select mi_adapter_set('mock_offline', true, 'test try mock')$$, 'mock_never_uses_network');
select mt.as(:'mgr');
select mt.err('T3 a manager can not link an adapter', $$select mi_adapter_set('rss_feed', true, 'test manager link')$$, 'not allowed');
select mt.as(:'o');
select mi_adapter_set('rss_feed', true, 'test owner links the feed reader for the check')->>'network_allowed' as na \gset
select mt.chk('T3 the owner can link an adapter', :'na' = 'true');
select mi_adapter_set('rss_feed', false, 'test unlink again')->>'network_allowed' as na2 \gset
select mt.chk('T3 and unlink it', :'na2' = 'false');

-- T4 the gate opens only when every condition holds (mock adapter, switches ON, source allowed)
select set_rule('mi_research_job_on', 'true');
select set_rule('mi_scrape_on', 'true');
select mi_research_gate(:'src'::uuid)::text as g1 \gset
select mt.chk('T4 switches on but the source terms are still NO: closed', (:'g1'::jsonb)->>'allowed' = 'false');
select mi_source_save(:'src', jsonb_build_object('terms_allow_scraping', true, 'terms_checked_on', to_char(mt.today(), 'YYYY-MM-DD'), 'robots_ok', true, 'rate_limit_per_hour', 6))->>'id' as s2 \gset
select mi_research_gate(:'src'::uuid, 'mock_offline')::text as g2 \gset
select mt.chk('T4 every condition holds for the mock adapter: open', (:'g2'::jsonb)->>'allowed' = 'true');
select mi_research_gate(:'src'::uuid, 'rss_feed')::text as g3 \gset
select mt.chk('T4 the real feed reader stays closed until the owner links it', (:'g3'::jsonb)->>'allowed' = 'false' and (:'g3'::jsonb)->>'reasons' like '%owner has not linked%');
select mi_job_save('test_job_gate', jsonb_build_object('label', 'test job', 'source_id', :'src', 'enabled', true))->>'enabled' as je2 \gset
select mt.chk('T4 the job can now be switched on', :'je2' = 'true');
select mt.err('T4 a job must have a source to be on', $$select mi_job_save('test_job_nosrc', '{"label":"test job","enabled":true}')$$, 'source_required');
select mi_job_mark_run('test_job_gate')->>'key' as mk \gset
select mt.chk('T4 the runner can record a run of an enabled job', :'mk' = 'test_job_gate');
select mt.as(:'mgr');
select mt.err('T4 a manager can not schedule research', $$select mi_job_save('test_job_mgr', '{"label":"test job","source_id":"00000000-0000-0000-0000-000000000000"}')$$, 'not allowed');
select mt.as(:'o');
select set_rule('mi_scrape_on', 'false');
select mi_research_gate(:'src'::uuid)::text as g4 \gset
select mt.chk('T4 switching fetching OFF closes the gate again at once', (:'g4'::jsonb)->>'allowed' = 'false');

-- T5 AI summariser: off by default; a proposal only; the person who asked can not accept it
select mi_finding_add(jsonb_build_object('source_url', 'https://test-ai.invalid/a', 'publisher', 'test_pub_ai', 'summary', 'test_ai_finding', 'finding_type', 'analysis'))->>'id' as fa \gset
select mt.err('T5 the summariser is off by default', format($$select mi_summary_propose(array['%s']::uuid[], 'test summary text')$$, :'fa'), 'module_off');
select set_rule('mi_ai_summary_on', 'true');
select mi_summary_propose(array[:'fa']::uuid[], 'test summary text')->>'status' as ps \gset
select mt.chk('T5 a proposal starts as proposed', :'ps' = 'proposed');
select mt.err('T5 the person who asked can not accept it', format($$select mi_summary_decide(%s, 'accepted', 'test accept')$$, (select id from mi_summary_proposals order by id desc limit 1)), 'own_request');
select mt.as(:'mgr');
select mi_summary_decide((select id from mi_summary_proposals order by id desc limit 1), 'rejected', 'test rejected by manager')->>'status' as pd \gset
select mt.chk('T5 another person can reject it, with a reason', :'pd' = 'rejected');
select mt.as(:'o');
select mt.err('T5 a decision needs a reason', format($$select mi_summary_decide(%s, 'accepted', '')$$, (select id from mi_summary_proposals order by id desc limit 1)), 'reason_required');

-- T6 competitor price alerts: blank threshold = no alert; typed threshold = alert when it moves more
select mi_price_add(jsonb_build_object('competitor', 'test_rival_w', 'item_label', 'test_watch_item', 'price', '100', 'observed_on', to_char(mt.today() - 2, 'YYYY-MM-DD')))->>'id' as w1 \gset
select mi_price_add(jsonb_build_object('competitor', 'test_rival_w', 'item_label', 'test_watch_item', 'price', '150', 'observed_on', to_char(mt.today(), 'YYYY-MM-DD')))->>'id' as w2 \gset
select mi_watch_alerts()::text as wa0 \gset
select mt.chk('T6 blank threshold: no alert produced', jsonb_array_length((:'wa0'::jsonb)->'alerts') = 0 and (:'wa0'::jsonb)->>'threshold' is null);
select set_rule('mi_watch_threshold_pct', '10');
select mi_watch_alerts()::text as wa1 \gset
select mt.chk('T6 a 50% move is listed above a 10% threshold', exists (select 1 from jsonb_array_elements((:'wa1'::jsonb)->'alerts') a where a->>'item_label' = 'test_watch_item' and (a->>'change_pct')::numeric = 50));

-- T7 owner digest and alert notice: off = nothing written; on = one line per day
select mi_alert_notify()::text as an0 \gset
select mt.chk('T7 alerts are not written while their switch is OFF', (:'an0'::jsonb)->>'created' = 'false');
select set_rule('mi_alerts_on', 'true');
select mi_alert_notify()::text as an1 \gset
select mt.chk('T7 the alert line is written once', (:'an1'::jsonb)->>'created' = 'true');
select mi_alert_notify()::text as an2 \gset
select mt.chk('T7 the same day adds no second line', (:'an2'::jsonb)->>'created' = 'false');
select mi_growth_digest(mt.today() - 6, mt.today(), mt.today() - 13, mt.today() - 7)::text as dg0 \gset
select mt.chk('T7 digest is not written while the digest switch is OFF', (:'dg0'::jsonb)->>'created' = 'false' and (:'dg0'::jsonb)->>'digest' like '%Price alerts%');
select set_rule('mi_digest_on', 'true');
select mi_growth_digest(mt.today() - 6, mt.today(), mt.today() - 13, mt.today() - 7)::text as dg1 \gset
select mt.chk('T7 digest is written when the owner switches it on', (:'dg1'::jsonb)->>'created' = 'true');

-- T8 switch everything back OFF and check the module is quiet again
select set_rule('mi_on', 'false');
select mt.err('T8 with the workspace OFF no finding can be added', $$select mi_finding_add('{"source_url":"https://test-off.invalid/a","publisher":"p","summary":"test_off","finding_type":"analysis"}'::jsonb)$$, 'module_off');
select mt.chk('T8 the gate is closed when the workspace is OFF', (select (mi_research_gate(:'src'::uuid)->>'allowed')::boolean = false));

select 'x6 phase490: ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' as result from mt.res;
