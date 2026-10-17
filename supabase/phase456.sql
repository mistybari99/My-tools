-- Phase 456 (RPT-HUB, part 7): spend explorer ("Ask / Find": how much was spent on what, for whom, where, in which period).
--   rpt_hub_spend_options()          lists for the filter builder (expense heads, utility types, expense accounts, payment sources, places)
--   rpt_hub_spend(filters, limit, offset)   total, count, month-by-month, by head / kind / status, and the source transactions with links
-- READ ONLY. Sources: quick expenses, expense vouchers 10-2 (one row per voucher line), staff advances, salary payments, purchase bills (and returns),
-- supplier payments, customer refunds, utility / cost-source bills (one row per place share), and the journal (expense accounts).
-- Filters: from, to, loc, person {kind: staff|customer|supplier, id}, heads[] (exact head codes), terms[] (words searched in the head CODE / account name AND in the memo / payee / bill text),
--          account_id, pay_mode, money_account_id, kinds[], status[] (posted by default; draft, void, reversed selectable; 'all').
-- Every row says whether it matched by head, by memo, or both. A person filter lists rows linked to that person ("direct": the row stores the person; "text": the
-- person's name appears in the memo - NOT a verified link) and counts, but never guesses, the rows that name no person ("unlinked") and the missing field.
-- Masking: each kind needs its own report right (expense, payroll, purchase, sales, cost, accounts). Staff pay rows (advances, salary, heads staff_meal and labour,
-- any row tied to a staff member) need the payroll right; without it they are omitted and listed by name in "masked".
-- Safe to paste twice. Needs phases 450-452.
do $$ begin if to_regprocedure('public._rh_masked()') is null then raise exception 'rpthub_needs_phase452'; end if; end $$;

create or replace function public.rpt_hub_spend_options() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object('generated_at', now(),
    'heads', coalesce((select jsonb_agg(jsonb_build_object('code', o.value_code, 'list', o.list_code, 'label_en', coalesce(o.label_en, o.label_mix, o.label_bn), 'label_bn', coalesce(o.label_bn, o.label_en)) order by o.list_code, o.sort)
                       from public.option_lists o where o.list_code in ('expense_heads', 'marketing_heads', 'other_income_heads') and o.active), '[]'::jsonb),
    'utility_types', case when public._rh_area_ok('cost') then coalesce((select jsonb_agg(jsonb_build_object('code', t.code, 'label_en', t.label_en, 'label_bn', t.label_bn) order by t.code) from public.cost_source_types t where t.active), '[]'::jsonb) else '[]'::jsonb end,
    'accounts', case when public._rh_area_ok('accounts') then coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'label_en', a.name_en, 'label_bn', a.name_bn) order by a.code) from public.coa_accounts a where a.type = 'expense' and a.active and not a.is_group), '[]'::jsonb) else '[]'::jsonb end,
    'money_accounts', case when public._rh_area_ok('cash') or public._rh_area_ok('accounts') then coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'kind', m.kind, 'label_en', coalesce(m.name_en, m.name_bn), 'label_bn', coalesce(m.name_bn, m.name_en)) order by m.sort, m.id) from public.money_accounts m where m.active), '[]'::jsonb) else '[]'::jsonb end,
    'pay_modes', jsonb_build_array('cash', 'bank', 'mobile', 'card'),
    'locations', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'kind', l.kind, 'label_en', coalesce(l.name_en, l.name_bn), 'label_bn', coalesce(l.name_bn, l.name_en)) order by l.sort, l.id) from public.locations l where public.can_loc(l.id)), '[]'::jsonb));
end $$;

create or replace function public.rpt_hub_spend(p_filters jsonb, p_limit int default 100, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  f jsonb := coalesce(p_filters, '{}'::jsonb);
  lim int := least(greatest(coalesce(p_limit, 100), 1), 500); off int := greatest(coalesce(p_offset, 0), 0);
  d1 date; d2 date; v_loc int; v_heads text[]; v_terms text[]; v_acc bigint; v_pmode text; v_macc bigint; v_kk text[]; v_sts text[]; v_pk text; v_pid text; v_pnames text[] := '{}'::text[]; plabel text; emp uuid; chk text;
  locs int[] := public._rh_locs();
  a_exp boolean := public._rh_area_ok('expense'); a_pay boolean := public._rh_area_ok('payroll'); a_pur boolean := public._rh_area_ok('purchase'); a_sal boolean := public._rh_area_ok('sales');
  a_cost boolean := public._rh_area_ok('cost'); a_acc boolean := public._rh_area_ok('accounts'); own boolean := public.is_owner();
  masked jsonb := '[]'::jsonb; notes jsonb := '[]'::jsonb; res jsonb; allk text[] := array['quick_expense', 'expense_voucher', 'advance', 'salary', 'purchase', 'supplier_payment', 'customer_refund', 'utility_bill', 'journal'];
  j_alone boolean; t0 timestamptz; t1 timestamptz; person_blocked boolean := false; q text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  -- parse (a bad value is an error, never silently ignored)
  begin d1 := (f ->> 'from')::date; d2 := (f ->> 'to')::date; exception when others then raise exception 'bad_date'; end;
  if d1 is null or d2 is null or d2 < d1 or d2 - d1 > 3700 then raise exception 'bad_range'; end if;
  begin v_loc := nullif(f ->> 'loc', '')::int; exception when others then raise exception 'bad_filter'; end;
  if v_loc is not null and not (v_loc = any (locs)) then raise exception 'not allowed'; end if;
  begin v_acc := nullif(f ->> 'account_id', '')::bigint; v_macc := nullif(f ->> 'money_account_id', '')::bigint; exception when others then raise exception 'bad_filter'; end;
  v_pmode := nullif(lower(btrim(coalesce(f ->> 'pay_mode', ''))), '');
  if v_pmode is not null and v_pmode not in ('cash', 'bank', 'mobile', 'card') then raise exception 'bad_filter'; end if;
  v_heads := coalesce((select array_agg(distinct lower(btrim(x))) from jsonb_array_elements_text(case when jsonb_typeof(f -> 'heads') = 'array' then f -> 'heads' else '[]'::jsonb end) x where btrim(x) <> ''), '{}'::text[]);
  v_terms := coalesce((select array_agg(distinct lower(btrim(x))) from (select x from jsonb_array_elements_text(case when jsonb_typeof(f -> 'terms') = 'array' then f -> 'terms' else '[]'::jsonb end) x limit 12) z where length(btrim(x)) between 2 and 40), '{}'::text[]);
  v_kk := coalesce((select array_agg(distinct x) from jsonb_array_elements_text(case when jsonb_typeof(f -> 'kinds') = 'array' then f -> 'kinds' else '[]'::jsonb end) x where x = any (allk)), '{}'::text[]);
  if jsonb_typeof(f -> 'kinds') = 'array' and jsonb_array_length(f -> 'kinds') > 0 and cardinality(v_kk) = 0 then raise exception 'bad_filter'; end if;
  v_sts := coalesce((select array_agg(distinct x) from jsonb_array_elements_text(case when jsonb_typeof(f -> 'status') = 'array' then f -> 'status' when f ->> 'status' = 'all' then '["posted","draft","void","reversed"]'::jsonb else '[]'::jsonb end) x where x in ('posted', 'draft', 'void', 'reversed')), '{}'::text[]);
  if f ->> 'status' = 'all' then v_sts := array['posted', 'draft', 'void', 'reversed']; end if;
  if cardinality(v_sts) = 0 then v_sts := array['posted']; end if;
  if cardinality(v_kk) = 0 then v_kk := array['quick_expense', 'expense_voucher', 'advance', 'salary', 'purchase', 'utility_bill']; end if;       -- costs once: a supplier payment repeats its bill, a refund is not a cost
  if 'purchase' = any (v_kk) and 'supplier_payment' = any (v_kk) then notes := notes || jsonb_build_array('purchase_and_payment_both_selected_count_twice'); end if;
  if v_acc is not null then v_kk := array['journal']; notes := notes || jsonb_build_array('account_filter_reads_the_journal_only'); end if;
  j_alone := v_kk = array['journal'];
  if 'journal' = any (v_kk) and not j_alone then notes := notes || jsonb_build_array('journal_shows_manual_entries_only_when_combined'); end if;
  v_pk := nullif(f #>> '{person,kind}', ''); v_pid := nullif(f #>> '{person,id}', '');
  if (v_pk is null) <> (v_pid is null) or (v_pk is not null and v_pk not in ('staff', 'customer', 'supplier')) then raise exception 'bad_filter'; end if;
  t0 := (d1::timestamp at time zone 'Asia/Dhaka'); t1 := ((d2 + 1)::timestamp at time zone 'Asia/Dhaka');

  -- masking by name (the same list every time, never a count)
  if not a_exp then masked := masked || jsonb_build_array('quick_expense', 'expense_voucher'); end if;
  if not a_pay then masked := masked || jsonb_build_array('advance', 'salary', 'head:staff_meal', 'head:labour', 'person:staff'); end if;
  if not a_pur then masked := masked || jsonb_build_array('purchase', 'supplier_payment', 'person:supplier'); end if;
  if not a_sal then masked := masked || jsonb_build_array('customer_refund', 'person:customer'); end if;
  if not a_cost then masked := masked || jsonb_build_array('utility_bill'); end if;
  if not a_acc then masked := masked || jsonb_build_array('journal'); end if;
  if not own and not (a_acc or a_exp or a_pay or a_pur or a_sal or a_cost) then raise exception 'not allowed'; end if;

  -- resolve the person
  if v_pk = 'staff' then
    if not a_pay then person_blocked := true;
    else
      select e.id, array_remove(array[lower(e.full_name_en), lower(e.full_name_bn), lower(e.nickname), lower(e.employee_no), lower(p.full_name), lower(p.staff_id)], null), coalesce(e.full_name_en, e.full_name_bn, e.employee_no) into emp, v_pnames, plabel
        from public.employees e left join public.profiles p on p.id = e.profile_id where e.id::text = v_pid or e.profile_id::text = v_pid limit 1;
      if emp is null then
        select p.id, array_remove(array[lower(p.full_name), lower(p.staff_id)], null), coalesce(p.full_name, p.staff_id) into emp, v_pnames, plabel from public.profiles p where p.id::text = v_pid;
      end if;
      v_pid := emp::text;
    end if;
  elsif v_pk = 'supplier' then
    if not a_pur then person_blocked := true; else select array_remove(array[lower(s.name), lower(s.mobile)], null), s.name into v_pnames, plabel from public.suppliers s where s.id::text = v_pid; end if;
  elsif v_pk = 'customer' then
    if not a_sal then person_blocked := true; else select array_remove(array[lower(c.name), lower(c.mobile)], null), c.name into v_pnames, plabel from public.customers c where c.id::text = v_pid; end if;
  end if;
  if v_pk is not null and not person_blocked and plabel is null then raise exception 'not_found'; end if;
  v_pnames := coalesce((select array_agg(x) from unnest(v_pnames) x where length(x) >= 3), '{}'::text[]);
  if person_blocked then
    return jsonb_build_object('generated_at', now(), 'filters', f, 'total', 0, 'count', 0, 'rows', '[]'::jsonb, 'by_month', '[]'::jsonb, 'by_head', '[]'::jsonb, 'by_kind', '[]'::jsonb, 'by_status', '[]'::jsonb,
      'matched', jsonb_build_object('head', 0, 'memo', 0, 'both', 0, 'filter', 0), 'unlinked', jsonb_build_object('count', 0, 'amount', 0, 'missing_fields', '[]'::jsonb), 'overlap', jsonb_build_object('count', 0, 'amount', 0),
      'no_source', 0, 'masked', masked, 'notes', notes || jsonb_build_array('person_needs_a_right'), 'person', jsonb_build_object('kind', v_pk, 'allowed', false));
  end if;

  with b as materialized (
    -- quick expenses
    select q0.exp_date dt, public._rh_ts(q0.exp_date, q0.created_at) ts, 'quick_expense'::text kind, case q0.status when 'done' then 'posted' else 'void' end st, q0.amount amt, lower(coalesce(q0.head, '')) head,
           btrim(coalesce(q0.note, '') || ' ' || coalesce(q0.paid_to, '')) memo, null::text ptype, null::text xid, q0.location_id lc, q0.mode mode, q0.money_account_id mac, null::bigint ac, null::text acc_en, null::text acc_bn,
           q0.created_staff who, 'quick_expenses'::text rt, q0.id::text rid, 'quickexp'::text lnk, jsonb_build_object('paid_to', q0.paid_to, 'note', q0.note, 'receipt', q0.receipt) sd, false dup
      from public.quick_expenses q0
     where a_exp and 'quick_expense' = any (v_kk) and q0.exp_date between d1 and d2 and q0.location_id = any (locs) and (v_loc is null or q0.location_id = v_loc)
    union all   -- expense vouchers, one row per line
    select e.entry_date, public._rh_ts(e.entry_date, e.submitted_at), 'expense_voucher', case e.status when 'draft' then 'draft' when 'rejected' then 'void' else 'posted' end, public._r2_num(l.l -> 'amount'),
           lower(coalesce(nullif(btrim(l.l ->> 'head'), ''), 'other')), coalesce(l.l ->> 'to', ''), null, null, e.location_id, 'cash', case when e.data ->> 'money_account_id' ~ '^[0-9]+$' then (e.data ->> 'money_account_id')::bigint end, null, null, null,
           e.created_staff, 'entries', e.id::text, 'forms', jsonb_build_object('serial', e.serial, 'line', l.n, 'receipt', l.l ->> 'receipt', 'to', l.l ->> 'to'), false
      from public.entries e cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) with ordinality l(l, n)
     where a_exp and 'expense_voucher' = any (v_kk) and e.form_code = '10-2' and e.entry_date between d1 and d2 and e.location_id = any (locs) and (v_loc is null or e.location_id = v_loc)
       and public._r2_num(l.l -> 'amount') > 0 and not public.is_shadow('entries', e.id::text)
    union all   -- staff advances
    select a.adv_date, public._rh_ts(a.adv_date, a.created_at), 'advance', case a.status when 'active' then 'posted' else 'void' end, a.amount, 'staff_advance', btrim(coalesce(a.note, '')), 'staff', a.employee_id::text, a.location_id,
           case a.mode when 'none' then null else a.mode end, a.money_account_id, null, null, null, public._rh_staff(a.created_by), 'employee_advances', a.id::text, 'payroll', jsonb_build_object('instalment', a.instalment, 'recover_from', a.recover_from), false
      from public.employee_advances a
     where a_pay and 'advance' = any (v_kk) and a.adv_date between d1 and d2 and (a.location_id is null or a.location_id = any (locs)) and (v_loc is null or a.location_id = v_loc)
    union all   -- salary payments
    select pp.pay_date, public._rh_ts(pp.pay_date, pp.created_at), 'salary', case pp.status when 'done' then 'posted' else 'void' end, pp.amount, 'salary', btrim(coalesce(pp.note, '')), 'staff', pp.employee_id::text, pp.location_id,
           pp.mode, pp.money_account_id, null, null, null, public._rh_staff(pp.created_by), 'payroll_payments', pp.id::text, 'payroll', jsonb_build_object('run_id', pp.run_id, 'ref', pp.ref), false
      from public.payroll_payments pp
     where a_pay and 'salary' = any (v_kk) and pp.pay_date between d1 and d2 and (pp.location_id is null or pp.location_id = any (locs)) and (v_loc is null or pp.location_id = v_loc)
    union all   -- purchase bills and returns
    select pb.bill_date, public._rh_ts(pb.bill_date, coalesce(pb.posted_at, pb.created_at)), 'purchase', pb.status, case when pb.kind = 'return' then -pb.total else pb.total end, case when pb.kind = 'return' then 'purchase_return' else 'purchase' end,
           btrim(coalesce(pb.note, '') || ' ' || coalesce(pb.bill_no, '') || ' ' || coalesce(su.name, '') || ' ' || coalesce((select string_agg(coalesce(pl.description, it.name_en, ''), ' ') from public.purchase_lines pl left join public.items it on it.id = pl.item_id where pl.bill_id = pb.id), '')),
           'supplier', pb.supplier_id::text, pb.location_id, null, null, null, null, null, pb.created_staff, 'purchase_bills', pb.id::text, 'purchase', jsonb_build_object('bill_no', pb.bill_no, 'supplier', su.name, 'paid', pb.paid, 'due', pb.due), false
      from public.purchase_bills pb left join public.suppliers su on su.id = pb.supplier_id
     where a_pur and 'purchase' = any (v_kk) and pb.bill_date between d1 and d2 and pb.location_id = any (locs) and (v_loc is null or pb.location_id = v_loc)
    union all   -- supplier payments
    select (sp.paid_at at time zone 'Asia/Dhaka')::date, sp.paid_at, 'supplier_payment', case when sp.voided then 'void' else 'posted' end, sp.amount, 'supplier_payment', btrim(coalesce(sp.note, '') || ' ' || coalesce(sp.ref, '') || ' ' || coalesce(su.name, '')),
           'supplier', sp.supplier_id::text, sp.location_id, sp.mode, sp.money_account_id, null, null, null, sp.created_staff, 'supplier_payments', sp.id::text, 'payables', jsonb_build_object('supplier', su.name, 'bill_id', sp.bill_id), false
      from public.supplier_payments sp left join public.suppliers su on su.id = sp.supplier_id
     where a_pur and 'supplier_payment' = any (v_kk) and sp.paid_at >= t0 and sp.paid_at < t1 and (sp.location_id is null or sp.location_id = any (locs)) and (v_loc is null or sp.location_id = v_loc)
    union all   -- customer refunds
    select (r.created_at at time zone 'Asia/Dhaka')::date, r.created_at, 'customer_refund', case r.status when 'done' then 'posted' else 'void' end, r.refund_amount, 'customer_refund', btrim(coalesce(r.reason_code, '') || ' ' || coalesce(r.note, '')),
           'customer', r.customer_id::text, r.location_id, r.refund_mode, r.money_account_id, null, null, null, r.created_staff, 'sale_returns', r.id::text, 'salereturn', jsonb_build_object('sale_id', r.sale_id, 'reason', r.reason_code), false
      from public.sale_returns r
     where a_sal and 'customer_refund' = any (v_kk) and r.refund_amount > 0 and r.created_at >= t0 and r.created_at < t1 and r.location_id = any (locs) and (v_loc is null or r.location_id = v_loc)
    union all   -- utility / cost-source bills: one row per place share (the share's amount), or the whole bill when it has no share
    select coalesce(cb.bill_date, cb.period_month), public._rh_ts(coalesce(cb.bill_date, cb.period_month), cb.created_at), 'utility_bill', case cb.status when 'active' then 'posted' else 'void' end, coalesce(sh.amount, cb.amount),
           lower(coalesce(cs.cost_type, '')), btrim(coalesce(cs.provider, '') || ' ' || coalesce(cb.bill_no, '') || ' ' || coalesce(cs.note, '') || ' ' || coalesce(cs.code, '')), null, null,
           case when sh.id is not null then sh.location_id else (select min(cl.location_id) from public.cost_source_locs cl where cl.source_id = cs.id having count(*) = 1) end, cb.pay_mode, null, null, null, null,
           public._rh_staff(cb.created_by), 'cost_source_bills', cb.id::text, 'costsources', jsonb_build_object('source', cs.code, 'provider', cs.provider, 'bill_no', cb.bill_no, 'share_kind', sh.kind, 'dest', sh.dest, 'bill_total', cb.amount),
           (cb.dup_entry_id is not null and exists (select 1 from public.entries de where de.id = cb.dup_entry_id and de.status in ('submitted', 'approved')))
      from public.cost_source_bills cb join public.cost_sources cs on cs.id = cb.source_id left join public.cost_bill_shares sh on sh.bill_id = cb.id and sh.active
     where a_cost and 'utility_bill' = any (v_kk) and coalesce(cb.bill_date, cb.period_month) between d1 and d2
       and (v_loc is null or (case when sh.id is not null then sh.location_id else (select min(cl.location_id) from public.cost_source_locs cl where cl.source_id = cs.id having count(*) = 1) end) = v_loc)
    union all   -- journal lines on expense accounts (or on the chosen account)
    select je.entry_date, je.created_at, 'journal', case when je.status = 'void' then 'void' when je.reverses_id is not null or exists (select 1 from public.journal_entries rv where rv.reverses_id = je.id and rv.status = 'posted') then 'reversed' else 'posted' end,
           jl.debit - jl.credit, lower(ca.code), btrim(coalesce(jl.memo, '') || ' ' || coalesce(je.memo, '')),
           case when jl.party_type in ('employee', 'staff') then 'staff' when jl.party_type in ('supplier', 'customer') then jl.party_type end, jl.party_id, coalesce(jl.location_id, je.location_id), null, null, ca.id, ca.name_en, ca.name_bn,
           coalesce(je.created_staff, public._rh_staff(je.created_by)), 'journal_entries', je.id::text, 'accounts', jsonb_build_object('source_type', je.source_type, 'source_id', je.source_id, 'line', jl.line_no, 'account', ca.code), false
      from public.journal_entries je join public.journal_lines jl on jl.entry_id = je.id join public.coa_accounts ca on ca.id = jl.account_id
     where a_acc and 'journal' = any (v_kk) and je.entry_date between d1 and d2 and (v_acc is null and ca.type = 'expense' or ca.id = v_acc)
       and (j_alone or je.source_type = 'manual') and (coalesce(jl.location_id, je.location_id) is null or coalesce(jl.location_id, je.location_id) = any (locs)) and (v_loc is null or coalesce(jl.location_id, je.location_id) = v_loc)
  ), e as (
    select b.*, o.label_en h_en, o.label_bn h_bn,
           case when pb_.is_staff_pay then true else false end sens
      from b left join lateral (select ol.label_en, ol.label_bn from public.option_lists ol where ol.value_code = b.head and ol.list_code in ('expense_heads', 'marketing_heads', 'other_income_heads') order by (ol.list_code = 'expense_heads') desc limit 1) o on true
      left join lateral (select (b.kind in ('advance', 'salary') or b.head in ('staff_meal', 'labour') or coalesce(b.ptype, '') = 'staff') is_staff_pay) pb_ on true
     where b.st = any (v_sts) and (a_pay or not pb_.is_staff_pay)
       and (v_pmode is null or b.mode = v_pmode) and (v_macc is null or b.mac = v_macc)
  ), m as (
    select e.*,
           (b_.hm) hm, (b_.tm) tm,
           case when v_pk is null then null
                when e.ptype = v_pk and e.xid = v_pid then 'direct'
                when exists (select 1 from unnest(v_pnames) nm where strpos(lower(e.memo), nm) > 0) then 'text' end lh
      from e cross join lateral (select (e.head = any (v_heads) or exists (select 1 from unnest(v_terms) t where strpos(lower(e.head || ' ' || coalesce(e.acc_en, '') || ' ' || coalesce(e.acc_bn, '')), t) > 0)) hm,
                                         exists (select 1 from unnest(v_terms) t where strpos(lower(e.memo), t) > 0) tm) b_
  ), s as (
    select m.*, case when cardinality(v_heads) = 0 and cardinality(v_terms) = 0 then 'filter' when m.hm and m.tm then 'both' when m.hm then 'head' else 'memo' end mb
      from m where (cardinality(v_heads) = 0 and cardinality(v_terms) = 0) or m.hm or m.tm
  ), kept as (    -- person filter: rows linked to the person; rows that name no person are counted apart
    select s.* from s where v_pk is null or s.lh is not null
  ), nolink as (
    select s.* from s where v_pk is not null and s.lh is null and s.ptype is null and s.kind in ('quick_expense', 'expense_voucher', 'journal', 'utility_bill')
  ), good as (select k.* from kept k where not k.dup)
  select jsonb_build_object(
      'total', (select coalesce(sum(amt), 0) from good), 'count', (select count(*) from good),
      'rows', (select coalesce(jsonb_agg(jsonb_build_object('date', x.dt, 'ts', x.ts, 'kind', x.kind, 'status', x.st, 'amount', x.amt, 'head', x.head, 'head_en', coalesce(x.h_en, x.acc_en, case when x.head like 'other:%' then substr(x.head, 7) end), 'head_bn', coalesce(x.h_bn, x.acc_bn),
                 'memo', x.memo, 'loc', x.lc, 'mode', x.mode, 'who', x.who, 'matched_by', x.mb, 'person_link', x.lh, 'person_kind', x.ptype, 'person_id', x.xid, 'ref_table', x.rt, 'ref_id', x.rid, 'link', x.lnk,
                 'detail', x.sd, 'possible_duplicate', x.dup) order by x.dt desc, x.ts desc, x.rid), '[]'::jsonb) from (select * from kept order by dt desc, ts desc, rid limit lim offset off) x),
      'by_month', (select coalesce(jsonb_agg(jsonb_build_object('month', z.mo, 'amount', z.s, 'n', z.n) order by z.mo), '[]'::jsonb) from (select to_char(date_trunc('month', dt), 'YYYY-MM') mo, sum(amt) s, count(*) n from good group by 1) z),
      'by_head', (select coalesce(jsonb_agg(jsonb_build_object('head', z.h, 'label_en', z.le, 'label_bn', z.lb, 'amount', z.s, 'n', z.n) order by z.s desc nulls last), '[]'::jsonb)
                    from (select head h, min(coalesce(h_en, acc_en, case when head like 'other:%' then substr(head, 7) end)) le, min(coalesce(h_bn, acc_bn)) lb, sum(amt) s, count(*) n from good group by 1 order by sum(amt) desc nulls last limit 20) z),
      'by_kind', (select coalesce(jsonb_agg(jsonb_build_object('kind', z.k, 'amount', z.s, 'n', z.n) order by z.s desc nulls last), '[]'::jsonb) from (select kind k, sum(amt) s, count(*) n from good group by 1) z),
      'by_status', (select coalesce(jsonb_agg(jsonb_build_object('status', z.k, 'amount', z.s, 'n', z.n)), '[]'::jsonb) from (select st k, sum(amt) s, count(*) n from kept group by 1) z),
      'matched', jsonb_build_object('head', (select count(*) from good where mb = 'head'), 'memo', (select count(*) from good where mb = 'memo'), 'both', (select count(*) from good where mb = 'both'), 'filter', (select count(*) from good where mb = 'filter')),
      'linked', jsonb_build_object('direct', (select count(*) from good where lh = 'direct'), 'text', (select count(*) from good where lh = 'text')),
      'unlinked', jsonb_build_object('count', (select count(*) from nolink), 'amount', (select coalesce(sum(amt), 0) from nolink),
                  'missing_fields', case when v_pk is not null and (select count(*) from nolink) > 0 then (select jsonb_agg(distinct x) from (select case kind when 'quick_expense' then 'quick_expenses.person_id' when 'expense_voucher' then 'entries.10-2.lines.person_id' when 'utility_bill' then 'cost_source_bills.person_id' else 'journal_lines.party_id' end x from nolink) q2) else '[]'::jsonb end),
      'overlap', jsonb_build_object('count', (select count(*) from kept where dup), 'amount', (select coalesce(sum(amt), 0) from kept where dup)),
      'no_source', case when v_pmode is not null or v_macc is not null then (select count(*) from s where s.mode is null and s.mac is null) else 0 end)
    into res;
  if v_pmode is not null or v_macc is not null then notes := notes || jsonb_build_array('rows_without_a_recorded_payment_source_are_left_out'); end if;
  if exists (select 1 from jsonb_array_elements(res -> 'by_kind') x where x ->> 'kind' = 'utility_bill') and a_exp then notes := notes || jsonb_build_array('utility_bills_may_repeat_a_voucher'); end if;
  return jsonb_build_object('generated_at', now(), 'filters', jsonb_build_object('from', d1, 'to', d2, 'loc', v_loc, 'person', case when v_pk is null then null else jsonb_build_object('kind', v_pk, 'id', v_pid, 'label', plabel) end,
      'heads', to_jsonb(v_heads), 'terms', to_jsonb(v_terms), 'account_id', v_acc, 'pay_mode', v_pmode, 'money_account_id', v_macc, 'kinds', to_jsonb(v_kk), 'status', to_jsonb(v_sts)),
    'limit', lim, 'offset', off) || res || jsonb_build_object('masked', masked, 'notes', notes, 'person', case when v_pk is null then null else jsonb_build_object('kind', v_pk, 'id', v_pid, 'label', plabel, 'allowed', true, 'names_matched_in_memo', to_jsonb(v_pnames)) end);
end $$;

revoke all on function public.rpt_hub_spend_options(), public.rpt_hub_spend(jsonb, int, int) from public, anon;
grant execute on function public.rpt_hub_spend_options(), public.rpt_hub_spend(jsonb, int, int) to authenticated;
