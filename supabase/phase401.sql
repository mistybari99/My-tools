-- Phase 401 (bos401) - REPORTS: "DATA NOT CAPTURED" NOTICES (package RPT-B1, item R2). Paste after phase400. Paste-twice safe. Earlier phase files are not edited.
-- WHY (docs/REPORTS_AUDIT_1.md D3, D4, D5, D6): four reports show a number where the app holds no data, or leave a cost out without saying so.
--   D4  f3_raw_vs_recipe "Actually issued" is the recipe itself (production_post issues exactly the recipe), so it always showed 0.00 % difference although nothing was measured.
--   D5  the app never captures the real yield of a batch, so the costing Runs tab showed "Actual" equal to "Standard".
--   D6  with the location method "off" the conversion cost is booked as 0 and called complete: the Runs tab showed a cost of 0 with no word that labour and overhead were not costed.
--   D3  with profit_one_number_on OFF, wastage, count shrinkage, transit loss and cash short are left out of the branch profit and the gaps column said nothing about them.
-- RULE FOLLOWED: never show 0 or an estimate when the source data is missing; show "not captured" and say which form or field is needed. No stored number is changed; only what the reports SHOW.
-- WHAT THIS FILE ADDS (read-only helpers; the reports use them through the hooks in docs/integration/RPT-B1_hooks.sql, section 2):
--   1. _rptb1_loss_gaps(from, to, place): text for the gaps column of l1_pnl / l3_shop_pnl, e.g. "wastage (not in profit)". Only losses that exist in the ledger and are left out of the profit are listed.
--      A loss counts as "in the profit" exactly when phase92 counts it (master switch on, the cause on, the start date reached, not excluded by the owner).
--   2. _rptb1_loss_summary(from, to, places): the same losses as amounts, for the note under the report.
--   3. _rptb1_r3_notes(report, from, to, places, filters): the notes under f3_raw_vs_recipe ("not captured") and under l1_pnl / l3_shop_pnl (losses left out).
--   4. The report f3_raw_vs_recipe gets one more column, actual_status (measured / partly / not captured). With the hooks its "Actually issued" is empty unless a movement was posted for the batch AFTER
--      the automatic recipe issue (a real measurement). Today nothing posts one, so the column says "not captured" until the production capture package exists.
--   5. production_run_costs (costing Runs tab): conversion_cost is empty with conversion_status "not_captured" when the location method is off; actual_cost is empty with actual_status "not_captured"
--      when no actual yield was typed; unit_cost_basis tells whether the unit cost holds material only.
-- With the hooks NOT installed nothing changes. !! Re-pasting phase 26, 27, 24 or 74 / 79 removes the bos401 hooks: run docs/integration/RPT-B1_hooks.sql again.
-- Test data only (test_*).

do $g$ begin
  if to_regprocedure('public._rptb1_p400_present()') is null then raise exception 'phase401 needs phase400 first'; end if;
  if to_regprocedure('public.report_run3(text,jsonb,text,text,integer)') is null or to_regprocedure('public._r3q_f3_raw_vs_recipe(date,date,integer[],jsonb)') is null
     or to_regprocedure('public._r3q_l1_pnl(date,date,integer[],jsonb)') is null or to_regprocedure('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)') is null
     or to_regprocedure('public.production_run_costs(integer,date,date)') is null or to_regclass('public.report_defs3') is null then
    raise exception 'phase401 needs the engine-3 reports (phases 24-27) and costing (phase 74)';
  end if;
end $g$;

create or replace function public._rptb1_p401_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- 1. losses left out of the profit ----------
-- one row per cause with the amount that is NOT counted in the profit of the place and period. Empty when phase92 is not installed.
create or replace function public._rptb1_loss_rows(p_from date, p_to date, p_locs int[]) returns table (cause text, amt numeric)
language plpgsql stable security definer set search_path = public as $$
declare master boolean; f date;
begin
  if to_regprocedure('public._w1d_pl_rows(date,date,integer[])') is null or to_regclass('public.profit_row_exclusions') is null then return; end if;
  master := coalesce(public.rule_on('profit_one_number_on'), false);
  f := public._w1d_losses_from();
  return query
    select r.cause, round(sum(r.amt), 2)
      from public._w1d_pl_rows(p_from, p_to, p_locs) r
     where r.cause in ('wastage', 'count_shrink', 'transit_loss', 'cash_short')
       and not (master and public._w1d_cause_on(r.cause) and (f is null or r.d >= f))                       -- counted: nothing to say
       and not exists (select 1 from public.profit_row_exclusions x where x.cause = r.cause and x.source_id = r.source_id and x.status = 'active')   -- left out on purpose, with a reason
     group by r.cause
    having sum(r.amt) <> 0;
end $$;

create or replace function public._rptb1_loss_gaps(p_from date, p_to date, p_loc int) returns text
language sql stable security definer set search_path = public as $$
  select nullif(string_agg(case l.cause when 'wastage' then 'wastage' when 'count_shrink' then 'count shrink' when 'transit_loss' then 'transit loss' else 'cash short/over' end || ' (not in profit)',
                           ', ' order by l.cause), '')
    from public._rptb1_loss_rows(p_from, p_to, array[p_loc]) l;
$$;

create or replace function public._rptb1_loss_summary(p_from date, p_to date, p_locs int[]) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(l.cause, l.amt), '{}'::jsonb) from public._rptb1_loss_rows(p_from, p_to, p_locs) l;
$$;

-- ---------- 2. the notes of the engine-3 reports ----------
create or replace function public._rptb1_r3_notes(p_key text, d1 date, d2 date, locs int[], flt jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb := '[]'::jsonb; n_all int; n_bad int; ls jsonb; txt_en text := ''; txt_bn text := ''; k text; v numeric;
begin
  if p_key = 'f3_raw_vs_recipe' then
    select count(*), count(*) filter (where r ->> 'actual_status' is distinct from 'measured') into n_all, n_bad from public._r3q_f3_raw_vs_recipe(d1, d2, locs, flt) r;
    if coalesce(n_bad, 0) > 0 then
      out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'not_captured', 'what', 'actual_issue', 'lines', n_bad, 'of', n_all,
        'text_en', 'Actual raw material use is not captured for ' || n_bad || ' of ' || n_all || ' lines, so no difference is shown. The app issues the recipe quantity automatically when production is posted, so it cannot be compared with itself. '
                   || 'Needed: the real issue of each batch (the issue slip 04-2 linked to the production run, or an actual-use entry when production is posted).',
        'text_bn', n_all || ' লাইনের মধ্যে ' || n_bad || 'টির কাঁচামালের আসল ব্যবহার ধরা হয়নি, তাই পার্থক্য দেখানো হয়নি। উৎপাদন পোস্ট করলে অ্যাপ নিজে রেসিপির পরিমাণ ইস্যু করে, নিজের সাথে নিজেকে মেলানো যায় না। '
                   || 'দরকার: প্রতিটি ব্যাচের আসল ইস্যু (উৎপাদনের সাথে যুক্ত ইস্যু স্লিপ ০৪-২, অথবা উৎপাদন পোস্টের সময় আসল ব্যবহার লেখা)।'));
    end if;
  elsif p_key in ('l1_pnl', 'l3_shop_pnl') then
    ls := public._rptb1_loss_summary(d1, d2, locs);
    if ls <> '{}'::jsonb then
      for k, v in select e.key, e.value::numeric from jsonb_each_text(ls) e order by e.key loop
        txt_en := txt_en || case when txt_en = '' then '' else ', ' end || case k when 'wastage' then 'wastage' when 'count_shrink' then 'count shrink' when 'transit_loss' then 'transit loss' else 'cash short/over' end || ' ' || v::text;
        txt_bn := txt_bn || case when txt_bn = '' then '' else ', ' end || case k when 'wastage' then 'অপচয়' when 'count_shrink' then 'গণনায় ঘাটতি' when 'transit_loss' then 'পথে ক্ষতি' else 'ক্যাশ কম/বেশি' end || ' ' || v::text;
      end loop;
      out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'losses_not_counted', 'amounts', ls,
        'text_en', 'The profit shown does not include: ' || txt_en || '. They are in the stock ledger / cash cases but the setting "One profit number: count losses in the profit" is off (or that loss is switched off). The gaps column marks the rows.',
        'text_bn', 'দেখানো লাভে এগুলো ধরা নেই: ' || txt_bn || '। স্টক-হিসাব/ক্যাশ কেসে আছে, কিন্তু "One profit number: count losses in the profit" নিয়মটি বন্ধ (বা সেই ক্ষতির সুইচ বন্ধ)। gaps কলামে সারিগুলো চিহ্নিত।'));
    end if;
  end if;
  return out_;
end $$;

-- ---------- 3. f3 gets the status column ----------
update public.report_defs3 set cols = cols || '[["actual_status","আসল মাপা?","Actual measured?","text"]]'::jsonb
 where key = 'f3_raw_vs_recipe' and not (cols::text like '%actual_status%');

-- ---------- 4. which hook sites are in place ----------
create or replace function public._rptb1_hooked401() returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object(
    'f3', position('bos401' in pg_get_functiondef('public._r3q_f3_raw_vs_recipe(date,date,integer[],jsonb)'::regprocedure)) > 0,
    'l1', position('bos401' in pg_get_functiondef('public._r3q_l1_pnl(date,date,integer[],jsonb)'::regprocedure)) > 0,
    'l3', position('bos401' in pg_get_functiondef('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)'::regprocedure)) > 0,
    'report_run3', position('bos401' in pg_get_functiondef('public.report_run3(text,jsonb,text,text,integer)'::regprocedure)) > 0,
    'production_run_costs', position('bos401' in pg_get_functiondef('public.production_run_costs(integer,date,date)'::regprocedure)) > 0);
$$;

revoke all on function public._rptb1_p401_present(), public._rptb1_loss_rows(date, date, int[]), public._rptb1_loss_gaps(date, date, int), public._rptb1_loss_summary(date, date, int[]),
  public._rptb1_r3_notes(text, date, date, int[], jsonb), public._rptb1_hooked401() from public, anon, authenticated;
