-- report facts for the seeded sales (the seed bypasses triggers)
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) is not null as x \gset
select report_fact_rebuild();
analyze;
