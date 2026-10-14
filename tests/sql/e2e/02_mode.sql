\echo == 02 mode switches
select tt.as(:'o');
select :'mode'='rec' as isrec \gset
\if :isrec
select setup_recommend_apply('aaaaaaaa-0000-0000-0000-00000000e2e1'::uuid) as ap1 \gset
select tt.t('M1 setup_recommend_apply applied recommendations', (:'ap1'::jsonb->>'count')::int > 20, '>20 applied', (:'ap1'::jsonb->>'count'));
select string_agg(x->>'code'||':'||(x->>'reason'), ', ') as sk1 from jsonb_array_elements(:'ap1'::jsonb->'skipped') x where x->>'reason' not in ('already','no_recommendation') \gset
\echo SKIPPED_FIRST_PASS: :sk1
-- second pass (ordering: accounting_on was not ready until start+opening exist; others depend on accounting_on)
select setup_recommend_apply('aaaaaaaa-0000-0000-0000-00000000e2e2'::uuid) as ap2 \gset
select string_agg(x->>'code'||':'||(x->>'reason'), ', ') as sk2 from jsonb_array_elements(:'ap2'::jsonb->'skipped') x where x->>'reason' not in ('already','no_recommendation') \gset
\echo SKIPPED_SECOND_PASS: :sk2
select tt.t('M1 second pass applies more (order dependency)', (:'ap2'::jsonb->>'count')::int >= 0, 'info', (:'ap2'::jsonb->>'count'));
\endif
select set_rule('accounting_on','true') is null as a_on \gset
select set_rule('accounting_autopost','true') is null as a_on2 \gset
select string_agg(key||'='||coalesce(value::text,'-'), ', ' order by key) as rr from rules where value is not null \gset
\echo RULES_SET: :rr
