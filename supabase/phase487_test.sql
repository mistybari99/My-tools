-- FRESH DB ONLY. Phase 487 (X6 foundation): defaults, rights, closed tables, append-only and no-delete guards.
--   bash tests/sql/x6_run.sh 487
\ir ../tests/sql/w1d_fixture.sql
\ir ../tests/sql/x6_head.sql
select mt.as(:'o');

select mt.chk('T1 all six market switches are OFF by default', not exists (select 1 from rules where key like 'mi\_%' and kind = 'switch' and coalesce(value, default_value) is distinct from 'false'::jsonb));
select mt.chk('T1 the three market numbers are BLANK by default', not exists (select 1 from rules where key in ('mi_quote_max_chars', 'mi_elast_min_days', 'mi_watch_threshold_pct') and coalesce(value, default_value) is not null));
select mt.chk('T1 nine market settings are registered', (select count(*) from rules where key like 'mi\_%') = 9);
select mt.chk('T1 market rights are defined', (select count(*) from grant_defs where grant_code in ('market_view', 'market_manage')) = 2);
select mt.chk('T2 nobody but the owner holds the market rights by default', not exists (select 1 from user_grants where grant_code like 'market\_%' and user_id = :'o'));
select mt.chk('T2 adapter catalogue: every adapter is offline by default', not exists (select 1 from mi_adapters where network_allowed));
select mt.chk('T2 the mock adapter exists and is kind mock', (select kind from mi_adapters where code = 'mock_offline') = 'mock');
select mt.chk('T3 anon has no table rights on the market tables', not has_table_privilege('anon', 'public.mi_topics', 'select') and not has_table_privilege('anon', 'public.mi_findings', 'select') and not has_table_privilege('anon', 'public.mi_opportunities', 'select'));
select mt.chk('T3 anon can not run a market function', not has_function_privilege('anon', 'public.mi_finding_add(jsonb, uuid)', 'execute') and not has_function_privilege('anon', 'public.mi_summary()', 'execute'));
select mt.chk('T3 row level security is on for the market tables', (select bool_and(relrowsecurity) from pg_class where relname in ('mi_topics', 'mi_sources', 'mi_findings', 'mi_opportunities', 'mi_opp_decisions')));

-- a finding and a topic exist, so the guards can be proved on real rows (superuser session, bypasses rights but not triggers)
select set_rule('mi_on', 'true');
select mi_topic_save(null, jsonb_build_object('category', 'prices', 'title_bn', 'test_topic_guard', 'business_relevance', 'test relevance for the guard'))->>'id' as tg \gset
select mi_finding_add(jsonb_build_object('source_url', 'https://test-guard.invalid/a', 'publisher', 'test_pub', 'summary', 'test_guard_summary', 'retrieved_on', to_char(mt.today(), 'YYYY-MM-DD'), 'finding_type', 'analysis'))->>'id' as fg \gset
select mt.err('T4 a finding can not be changed (append-only)', format($$update mi_findings set summary = 'x' where id = '%s'$$, :'fg'), 'append_only');
select mt.err('T4 a finding can not be deleted (append-only)', format($$delete from mi_findings where id = '%s'$$, :'fg'), 'append_only');
select mt.err('T4 a topic can not be deleted (no hard delete)', format($$delete from mi_topics where id = '%s'$$, :'tg'), 'nothing is deleted');
select mi_price_add(jsonb_build_object('competitor', 'test_guard_rival', 'item_label', 'test_guard_item', 'price', '10'))->>'id' as pg \gset
select mt.err('T4 a price row can not be changed', format($$update mi_price_obs set price = 1 where id = %s$$, :'pg'), 'append_only');
select mt.as(:'nb');
set role authenticated;
select mt.chk('T3 a person with no market right reads no topic (row rule)', (select count(*) from mi_topics) = 0);
reset role;
select mt.as(:'o');

select mt.chk('T5 the change log records a new topic', exists (select 1 from audit_log where table_name = 'mi_topics' and record_id = :'tg'));
select mt.chk('T5 pass count: all phase 487 checks listed above', (select count(*) from mt.res where ok) >= 16);
select 'x6 phase487: ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' as result from mt.res;
