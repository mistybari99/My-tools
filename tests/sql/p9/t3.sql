\pset pager off
\pset tuples_only on
\pset format unaligned
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false) \g /dev/null
select (select string_agg(e->>'item_code'||'|'||(e->>'qty')||'|'||(e->>'net'),',' order by e->>'item_code') from jsonb_array_elements(j->'rows') e) from (select report_run('item_sales','{"from":"2026-09-08","to":"2026-09-14"}') j) r;
select jsonb_pretty(j->'rows') from (select report_run('pos_day_close','{"from":"2026-09-08","to":"2026-09-14"}') j) r;
select j->'totals' from (select report_run('pos_day_close','{"from":"2026-09-08","to":"2026-09-14"}') j) r;
