\pset pager off
\pset tuples_only on
\pset format unaligned
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
\echo == owner sales_summary cur (expect bills 6 gross 4690 disc 160 net 4530 paid 3950 due 580 void 1/260 avg 755; cogs 2300 gp ...)
select jsonb_pretty(report_run('sales_summary','{"from":"2026-09-08","to":"2026-09-14"}'));
