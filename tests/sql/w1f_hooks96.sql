-- W1-F hooks for phase 96 (marker bos96). THESE ARE NOT PART OF phase96.sql: the wave integrator pastes them (docs/integration/W1-F.md section 2).
-- phase96_test.sql runs this file inside a transaction that is rolled back, so the patched shared functions only ever exist on a scratch copy.
-- Every pair is [old exact text, new exact text]. A missing site stops the paste (nothing half changed). Paste twice = no-op (marker bos96).

-- H96-1 _acct_docs: the journal source of other income
select public._w1f_patch('public._acct_docs(date)'::regprocedure, array[
  $a$return query select * from public._m_docs(p_start); /* bos87: transfers and charges between money accounts */$a$,
  $a$return query select * from public._m_docs(p_start); /* bos87: transfers and charges between money accounts */
  return query select * from public._w1f_docs(p_start); /* bos96: other income */$a$], 'bos96');

-- H96-2 _daybook_lines: other income rows in the day book
select public._w1f_patch('public._daybook_lines(integer[],integer[],date,date)'::regprocedure, array[
  $a$union all select * from public._m_daybook_rows(p_locs, p_from, p_to) /* bos87 */;$a$,
  $a$union all select * from public._m_daybook_rows(p_locs, p_from, p_to) /* bos87 */
  union all select * from public._w1f_daybook_rows(p_locs, p_from, p_to) /* bos96 */;$a$], 'bos96');

-- H96-3 _e_balance_check: the mapping coverage line (amber, never red)
select public._w1f_patch('public._e_balance_check(date,integer,integer)'::regprocedure, array[
  $a$  red := not (eq ->> 'ok')::boolean or not (trial ->> 'ok')::boolean or jr_n > 0 or st_n > 0 or coalesce((mnc ->> 'red')::boolean, false);$a$,
  $a$  begin   -- bos96: mapping coverage (amber): every key the posting needs points to an active account
    xc := xc || jsonb_build_object('mapping_coverage', public._w1f_mapping_coverage());
    if not coalesce((xc #>> '{mapping_coverage,ok}')::boolean, true) then warn := warn || to_jsonb('mapping_coverage'::text); end if;
  exception when others then xc := xc || jsonb_build_object('mapping_coverage', jsonb_build_object('ran', false, 'skipped', sqlerrm));
  end;
  red := not (eq ->> 'ok')::boolean or not (trial ->> 'ok')::boolean or jr_n > 0 or st_n > 0 or coalesce((mnc ->> 'red')::boolean, false);$a$], 'bos96');

-- H96-4 acct_cash_flow: the legacy wallets 1131-1134 (keys d_wallet_*) are cash too
select public._w1f_patch('public.acct_cash_flow(date,date,integer)'::regprocedure, array[
  $a$union select coa_account_id from public.money_accounts) z; /* bos87 */$a$,
  $a$union select coa_account_id from public.money_accounts union select account_id from public.acct_mappings where key like 'd\_wallet\_%' /* bos96: legacy wallets */) z; /* bos87 */$a$], 'bos96');

-- H96-5 daybook_vs_journal: the same legacy wallets, so a wallet split does not show as a difference
select public._w1f_patch('public.daybook_vs_journal(date,date,integer)'::regprocedure, array[
  $a$from public.acct_mappings m0 union select ma.coa_account_id$a$,
  $a$from public.acct_mappings m0 union select w0.account_id, 'pay_mobile' from public.acct_mappings w0 where w0.key like 'd\_wallet\_%' /* bos96: legacy wallets */ union select ma.coa_account_id$a$], 'bos96');
