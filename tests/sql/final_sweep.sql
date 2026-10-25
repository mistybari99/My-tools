-- Post-test sweep: negative stock, stock cache vs ledger, unbalanced entries, trial balance vs journal lines, profit_source_check. Run on the DB a test suite just used: psql -d <db> -f tests/sql/final_sweep.sql | grep SWEEP
\set ON_ERROR_STOP off
\pset tuples_only on
do $$
declare uid uuid; negb int; negl int; mis int; unb int; nje int; tb jsonb; d1 date; d2 date; tbm int := null; tbdiff numeric := null; ps jsonb; psd text := null; nsale int; dupl int;
begin
  select user_id into uid from public.user_roles where role_code='owner' limit 1;
  if uid is not null then perform set_config('request.jwt.claim.sub', uid::text, false); end if;
  select count(*) into negb from public.stock_balance where qty < 0;
  select count(*) into mis from (select b.item_id, b.location_id from public.stock_balance b left join (select item_id, location_id, sum(qty_delta) q from public.stock_ledger group by 1,2) l on l.item_id=b.item_id and l.location_id=b.location_id where abs(coalesce(l.q,0) - b.qty) > 0.0001) z;
  select count(*) into unb from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z;
  select count(*), min(entry_date), max(entry_date) into nje, d1, d2 from public.journal_entries;
  if nje > 0 then
    begin
      tb := public.acct_trial_balance(d1, d2);
      tbdiff := (tb->>'diff')::numeric;
      select count(*) into tbm from jsonb_array_elements(tb->'rows') r
        where not (r->>'is_group')::boolean and (
          abs((r->>'dr')::numeric - coalesce((select sum(l.debit) from public.journal_lines l join public.journal_entries e on e.id=l.entry_id join public.coa_accounts a on a.id=l.account_id where a.code = r->>'code' and e.entry_date between d1 and d2),0)) > 0.005
       or abs((r->>'cr')::numeric - coalesce((select sum(l.credit) from public.journal_lines l join public.journal_entries e on e.id=l.entry_id join public.coa_accounts a on a.id=l.account_id where a.code = r->>'code' and e.entry_date between d1 and d2),0)) > 0.005);
    exception when others then tbm := -1; end;
    begin
      ps := public.profit_source_check(d1, d2, null);
      psd := (ps->>'difference') || '/' || (ps->>'agree');
    exception when others then psd := 'err:' || sqlerrm; end;
  end if;
  raise notice 'SWEEP negbal=% cache_mismatch=% unbalanced_entries=% journal_entries=% tb_diff=% tb_rows_vs_journal_mismatch=% profit_check(diff/agree)=%', negb, mis, unb, nje, coalesce(tbdiff::text,'-'), coalesce(tbm::text,'-'), coalesce(psd,'-');
end $$;
