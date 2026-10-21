-- Discovery run of the C3 differential probe (by hand; the permanent version is inside phase133_test). Fresh DB only.
-- psql -h /tmp -p 5544 -U postgres -d <db> -v mode=def -qAt -f tests/sql/c3_discover.sql
\i tests/sql/e2e/00_common.sql
\i tests/sql/c3_probe.sql
\i tests/sql/c3_seed.sql
\echo == seed A
select c3.seed_data(1, 2, :'ao', 'A', :'sbz'::bigint)::text as ja \gset
insert into c3.ids values ('persona_a_staff', :'ao'), ('persona_a_mgr', :'am'), ('persona_a_super', :'as'), ('persona_a_ops', :'aop'), ('loc_a', '1'), ('biz_a', :'sbz');
select tt.as(:'o');
update rules set value = 'true'::jsonb where key = 'org_scope_on';
\echo == probe S1 (only A has data)
set role authenticated;
select c3.probe('S1');
reset role;
\echo == seed B
select c3.seed_data(:'hw1'::int, :'hw2'::int, :'bo', 'B', :'hbz'::bigint)::text as jb \gset
insert into c3.ids select regexp_replace(k, '^(.*)_B$', '\1_b'), v from jsonb_each_text(:'jb'::jsonb) e(k, v);
insert into c3.ids values ('loc_b', :'hw1'), ('biz_b', :'hbz'), ('int_b', :'hw1'), ('cheque_b', '00000000-0000-0000-0000-00000000dead'), ('ship_b', '1');
\echo == probe S2 (B has data)
set role authenticated;
select c3.probe('S2');
reset role;
\echo == RESULT: v0 differences between S1 and S2
select 'DIFF', fn, persona, a.out, b.out from c3.probe_out a join c3.probe_out b using (fn, persona, variant) where a.snap = 'S1' and b.snap = 'S2' and variant in ('v0', 'vA') and a.out <> b.out order by fn, persona;
