-- Phase 84 (bos84) - BALANCE CHECK (G11). READ ONLY. Safe for the live project.
-- Paste after phase79 (or after whatever is latest). Additive, paste-twice safe: create or replace function only. No existing function, table or rule is changed.
-- The guarded test-project reset (G13) is NOT in this file: it lives in supabase/phase84_test_project_only.sql, which belongs in TEST projects only.
--
-- _e_balance_check(p_date, p_loc, p_days)   READ ONLY. One jsonb answer, one red/green status:
--   equation       assets = liabilities + equity + earnings (acct_balance_sheet), RED when the difference is not 0
--   trial_balance  total debit = total credit (acct_trial_balance), RED when not equal
--   journal        every journal entry where sum Dr <> sum Cr, and entries with no lines (list, max 200), RED when any
--   stock_identity per place and item: opening + in - out must equal stock_balance.qty (list, max 200), RED when any
--   cross_checks   AMBER only (they have known timing reasons and never turn the whole status red):
--                  day book vs journal (daybook_vs_journal), stock valuation vs journal (inventory_vs_gl),
--                  documents not yet posted and posting errors (acct_status)
--   status         red | green | data_needed (accounting start date not set). Amber cross-checks are listed in "warnings".
-- Hazard (HANDOVER_5): re-pasting an OLD phase never touches this function; it calls existing reports only.

-- ---------- PART 1: balance check (read only) ----------
create or replace function public._e_balance_check(p_date date default null, p_loc int default null, p_days int default 31)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  st date := public._acct_start(); d date := coalesce(p_date, public._acct_today()); bs jsonb; tb jsonb; days int := least(greatest(coalesce(p_days, 31), 1), 366);
  eq jsonb; trial jsonb; jr jsonb; stk jsonb; dbk jsonb; invg jsonb; sts jsonb; xc jsonb := '{}'::jsonb; warn jsonb := '[]'::jsonb;
  jr_n bigint; jr_list jsonb; st_n bigint; st_list jsonb; red boolean := false; v_all boolean := public._acct_all();
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if p_loc is null and not v_all then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if st is null then return jsonb_build_object('status', 'data_needed', 'why', 'accounting_start_date', 'as_of', d, 'location_id', p_loc); end if;

  -- 1 the equation
  bs := public.acct_balance_sheet(d, p_loc);
  eq := jsonb_build_object('assets', bs -> 'total_assets', 'liabilities', bs -> 'total_liabilities', 'equity', bs -> 'total_equity', 'earnings', bs -> 'retained_earnings',
          'liabilities_equity_earnings', bs -> 'total_liabilities_and_equity', 'difference', bs -> 'difference', 'ok', not coalesce((bs ->> 'unbalanced')::boolean, true));
  -- 2 the trial balance
  tb := public.acct_trial_balance(st, d, p_loc);
  trial := jsonb_build_object('total_debit', tb -> 'total_debit', 'total_credit', tb -> 'total_credit', 'difference', tb -> 'diff', 'ok', coalesce((tb ->> 'balanced')::boolean, false));
  -- 3 journal entries where Dr <> Cr (or no lines at all)
  with z as (
    select e.id, e.entry_date, e.source_type, e.source_id, coalesce(sum(l.debit), 0) dr, coalesce(sum(l.credit), 0) cr, count(l.entry_id) n
      from public.journal_entries e left join public.journal_lines l on l.entry_id = e.id
     where e.entry_date <= d and (p_loc is null or exists (select 1 from public.journal_lines x where x.entry_id = e.id and x.location_id = p_loc))
     group by e.id, e.entry_date, e.source_type, e.source_id
    having coalesce(sum(l.debit), 0) <> coalesce(sum(l.credit), 0) or count(l.entry_id) = 0)
  select count(*), coalesce(jsonb_agg(jsonb_build_object('entry_id', id, 'date', entry_date, 'source_type', source_type, 'source_id', source_id, 'debit', dr, 'credit', cr, 'diff', dr - cr, 'lines', n)
         order by id) filter (where rn <= 200), '[]'::jsonb)
    into jr_n, jr_list from (select z.*, row_number() over (order by z.id) rn from z) z;
  jr := jsonb_build_object('broken', jr_n, 'rows', jr_list, 'truncated', jr_n > 200, 'ok', jr_n = 0);
  -- 4 stock identity per place and item: opening + in - out = closing (stock_balance), as of now
  with l as (
    select item_id, location_id,
           coalesce(sum(qty_delta) filter (where reason = 'opening'), 0) op,
           coalesce(sum(qty_delta) filter (where reason <> 'opening' and qty_delta > 0), 0) qin,
           -coalesce(sum(qty_delta) filter (where reason <> 'opening' and qty_delta < 0), 0) qout
      from public.stock_ledger where p_loc is null or location_id = p_loc group by item_id, location_id),
  j as (
    select coalesce(l.item_id, b.item_id) item_id, coalesce(l.location_id, b.location_id) location_id, coalesce(l.op, 0) op, coalesce(l.qin, 0) qin, coalesce(l.qout, 0) qout,
           coalesce(b.qty, 0) closing, coalesce(l.op, 0) + coalesce(l.qin, 0) - coalesce(l.qout, 0) expected
      from l full join (select * from public.stock_balance where p_loc is null or location_id = p_loc) b on b.item_id = l.item_id and b.location_id = l.location_id),
  br as (select j.*, row_number() over (order by j.location_id, j.item_id) rn from j where j.expected <> j.closing)
  select count(*), coalesce(jsonb_agg(jsonb_build_object('item_id', item_id, 'location_id', location_id, 'opening', op, 'in', qin, 'out', qout, 'expected_closing', expected,
         'stock_balance', closing, 'diff', closing - expected) order by rn) filter (where rn <= 200), '[]'::jsonb)
    into st_n, st_list from br;
  stk := jsonb_build_object('broken', st_n, 'rows', st_list, 'truncated', st_n > 200, 'ok', st_n = 0, 'as_of', 'now');

  -- 5 cross-checks (amber). Each is skipped, not failed, when the caller may not run the report.
  begin
    dbk := public.daybook_vs_journal(greatest(d - days, st), d, p_loc);
    xc := xc || jsonb_build_object('daybook_vs_journal', jsonb_build_object('ran', coalesce(dbk -> 'total' is not null, false), 'kinds_differing', dbk #> '{total,kinds_differing}',
            'diff', dbk #> '{total,diff}', 'rows', coalesce(dbk -> 'rows', '[]'::jsonb), 'from', dbk -> 'from', 'to', dbk -> 'to', 'ok', coalesce((dbk #>> '{total,kinds_differing}')::int, 0) = 0));
    if coalesce((dbk #>> '{total,kinds_differing}')::int, 0) > 0 then warn := warn || to_jsonb('daybook_vs_journal'::text); end if;
  exception when others then xc := xc || jsonb_build_object('daybook_vs_journal', jsonb_build_object('ran', false, 'skipped', sqlerrm));
  end;
  begin
    invg := public.inventory_vs_gl(d, p_loc);
    xc := xc || jsonb_build_object('inventory_vs_gl', jsonb_build_object('ran', coalesce(invg -> 'total' is not null, false), 'gl', invg #> '{total,gl}', 'valuation', invg #> '{total,valuation}',
            'diff', invg #> '{total,diff}', 'unexplained', invg #> '{total,unexplained}', 'ok', coalesce((invg ->> 'agree')::boolean, true)));
    if not coalesce((invg ->> 'agree')::boolean, true) then warn := warn || to_jsonb('inventory_vs_gl'::text); end if;
  exception when others then xc := xc || jsonb_build_object('inventory_vs_gl', jsonb_build_object('ran', false, 'skipped', sqlerrm));
  end;
  begin
    sts := public.acct_status();
    xc := xc || jsonb_build_object('unposted_sources', jsonb_build_object('ran', true, 'pending', sts -> 'pending', 'errors', sts -> 'errors', 'waiting', sts -> 'waiting',
            'ok', coalesce((sts ->> 'pending')::int, 0) = 0 and coalesce((sts ->> 'errors')::int, 0) = 0));
    if coalesce((sts ->> 'pending')::int, 0) > 0 or coalesce((sts ->> 'errors')::int, 0) > 0 then warn := warn || to_jsonb('unposted_sources'::text); end if;
  exception when others then xc := xc || jsonb_build_object('unposted_sources', jsonb_build_object('ran', false, 'skipped', sqlerrm));
  end;

  red := not (eq ->> 'ok')::boolean or not (trial ->> 'ok')::boolean or jr_n > 0 or st_n > 0;
  return jsonb_build_object('status', case when red then 'red' else 'green' end, 'as_of', d, 'location_id', p_loc, 'start', st,
    'equation', eq, 'trial_balance', trial, 'journal', jr, 'stock_identity', stk, 'cross_checks', xc, 'warnings', warn,
    'reds', (select coalesce(jsonb_agg(k), '[]'::jsonb) from (values ('equation', not (eq ->> 'ok')::boolean), ('trial_balance', not (trial ->> 'ok')::boolean),
                ('journal', jr_n > 0), ('stock_identity', st_n > 0)) v(k, bad) where bad),
    'note', 'Read only: nothing is posted or changed. Red = a book rule is broken. Amber (warnings) = two reports disagree and need a look (timing or an unposted document is the usual reason); amber never turns the status red. Stock identity is checked as of now.');
end $$;
revoke all on function public._e_balance_check(date, int, int) from public, anon;
grant execute on function public._e_balance_check(date, int, int) to authenticated;
