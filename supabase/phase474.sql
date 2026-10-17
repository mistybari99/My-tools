-- Phase 474 (RPT-HUB, part 5): audit trail overlay for one record.
--   rpt_hub_trail(table, id)   who created / posted / changed / voided / reversed this record, what the books and the stock did about it, which exceptions it raised.
-- READ ONLY. Built only from what the tables really hold (creator and time columns, void columns, the stock ledger reversal rows, journal reversals, exceptions,
-- corrections, change requests, and audit_log for the owner). Whatever the system did not record is listed in "not_recorded"; nothing is guessed.
-- The saved paper-form data (entries.data) is never returned here: counts are blind (BUILD-RULES 9).
-- Safe to paste twice. Needs phases 470-471.
do $$ begin if to_regprocedure('public._rh_events(date,date,int,text[],text,text,boolean)') is null then raise exception 'rpthub_needs_phase471'; end if; end $$;

create or replace function public.rpt_hub_trail(p_table text, p_id text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  tbl text := regexp_replace(coalesce(p_table, ''), '^approval_', ''); area text; r jsonb; loc int; locs int[] := public._rh_locs(); own boolean := public.is_owner();
  trail jsonb := '[]'::jsonb; nr jsonb := '[]'::jsonb; rev jsonb := '[]'::jsonb; jrev jsonb := '[]'::jsonb; seen text[] := '{}'::text[]; k_ text; exc jsonb := '[]'::jsonb; au jsonb := '[]'::jsonb; cor jsonb := '[]'::jsonb; chg jsonb := '[]'::jsonb; notes jsonb := '[]'::jsonb;
  form text; v record; at_ timestamptz; by_id uuid; by_txt text; note_ text; has_creator boolean := false; is_void boolean;
  strip text[] := '{}'::text[]; costok boolean := public._rh_area_ok('cost'); map jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_id is null or length(p_id) > 80 then raise exception 'bad_id'; end if;
  area := case tbl
    when 'sales' then 'sales' when 'sale_returns' then 'sales' when 'sale_payments' then 'customers' when 'quick_expenses' then 'expense'
    when 'purchase_bills' then 'purchase' when 'supplier_payments' then 'purchase' when 'supplier_refunds' then 'purchase'
    when 'production_runs' then 'stock' when 'stock_wastage' then 'stock' when 'stock_transfers' then 'stock' when 'stock_ledger' then 'stock' when 'shortage_transit' then 'stock'
    when 'cash_moves' then 'cash' when 'shortage_cash_cases' then 'cash' when 'other_income' then 'cash' when 'money_transfers' then 'cash'
    when 'exceptions' then 'control' when 'release' then 'control' when 'emergency' then 'control' when 'change' then 'control' when 'wastage' then 'control' when 'item_change' then 'control' when 'party_adjustment' then 'control'
    when 'release_requests' then 'control' when 'emergency_requests' then 'control' when 'entry_change_requests' then 'control' when 'wastage_requests' then 'control' when 'item_changes' then 'control' when 'open_party_adjustments' then 'control'
    when 'employee_status_log' then 'hr' when 'w1c_exit_log' then 'hr' when 'payroll_payments' then 'payroll' when 'employee_advances' then 'payroll'
    when 'c_month_close_log' then 'accounts' when 'year_closes' then 'accounts' when 'period_overrides' then 'accounts'
    when 'entries' then 'entries' else null end;
  if area is null then raise exception 'bad_table'; end if;
  tbl := case tbl when 'release' then 'release_requests' when 'emergency' then 'emergency_requests' when 'change' then 'entry_change_requests' when 'wastage' then 'wastage_requests'
                  when 'item_change' then 'item_changes' when 'party_adjustment' then 'open_party_adjustments' else tbl end;
  -- the row, read generically (a bad id for the table's key type simply finds nothing)
  begin
    execute format('select to_jsonb(t) from public.%I t where t.%I::text = $1', tbl, case tbl when 'sale_returns' then 'id' when 'w1c_exit_log' then 'id' else 'id' end) into r using p_id;
  exception when others then r := null; end;
  if r is null then raise exception 'not_found'; end if;
  if tbl = 'entries' then
    form := r ->> 'form_code';
    area := case form when '10-2' then 'expense' when '10-1' then 'cash' when '14-1' then 'pos' when '04-3' then 'stock' when '05-1' then 'stock' when '04-1' then 'stock' when '03-1' then 'stock' else 'control' end;
    strip := array['data', 'check_data', 'reopen_snap', 'flags'];
  end if;
  if not public._rh_area_ok(area) then raise exception 'not allowed'; end if;
  -- location gate
  loc := coalesce(nullif(r ->> 'location_id', '')::int, nullif(r ->> 'from_location_id', '')::int, nullif(r ->> 'primary_location_id', '')::int);
  if loc is not null and not (loc = any (locs)) then raise exception 'not allowed'; end if;
  if tbl = 'production_runs' and not costok then strip := strip || array['material_cost', 'conversion_cost', 'unit_cost', 'std_cost', 'actual_cost', 'conversion_detail']; end if;
  if tbl = 'stock_ledger' and not costok then strip := strip || array['unit_cost']; end if;
  if tbl = 'shortage_transit' and not costok then strip := strip || array['value', 'claimed_amount', 'recovered_amount', 'written_off_amount']; end if;
  if tbl = 'item_price_history' and not costok then strip := strip || array['cost_price']; end if;
  foreach form in array strip loop r := r - form; end loop;

  -- life-cycle steps from the columns the table really has (event, time key, who-id key, who-name key, note key)
  for v in select * from (values
      ('created', 'created_at', 'created_by', 'created_staff', null), ('created', 'made_at', 'created_by', 'created_staff', null), ('created', 'sold_at', 'created_by', 'created_staff', null), ('created', 'sent_at', 'sent_by', 'sent_staff', 'note'),
      ('requested', 'requested_at', 'requested_by', 'requested_staff', 'reason'), ('requested', 'started_at', 'started_by', null, 'reason'), ('posted', 'posted_at', 'posted_by', null, null),
      ('received', 'received_at', 'received_by', 'received_staff', 'receive_note'), ('submitted', 'submitted_at', 'created_by', 'created_staff', null), ('checked', 'checked_at', 'checked_by', 'checked_staff', 'check_note'),
      ('decided', 'decided_at', 'decided_by', 'decided_staff', 'decision_note'), ('resolved', 'resolved_at', 'resolved_by', 'resolved_staff', 'resolved_note'),
      ('voided', 'void_at', 'void_by', 'void_staff', 'void_note'), ('voided', 'void_at', 'void_by', null, 'void_reason'), ('cancelled', 'cancelled_at', 'cancelled_by', null, null),
      ('closed', 'closed_at', 'closed_by', null, 'note'), ('reopened', 'reopened_at', 'reopened_by', null, 'reopen_note'), ('ended', 'ended_at', 'ended_by', null, 'end_note'), ('logged', 'at', 'by_user', null, 'reason'), ('logged', 'at', 'by', null, 'reason')
    ) t(ev, ak, bk, sk, nk)
  loop
    if r ? v.ak and nullif(r ->> v.ak, '') is not null then
      at_ := (r ->> v.ak)::timestamptz; by_id := case when v.bk is not null and r ? v.bk then nullif(r ->> v.bk, '')::uuid end;
      by_txt := coalesce(case when v.sk is not null and r ? v.sk then nullif(r ->> v.sk, '') end, public._rh_staff(by_id));
      note_ := case when v.nk is not null and r ? v.nk then nullif(r ->> v.nk, '') end;
      if v.ev = 'created' and (by_txt is not null) then has_creator := true; end if;
      k_ := v.ev || '|' || at_::text || '|' || coalesce(by_txt, '');
      if not (k_ = any (seen)) then       -- the same step spelled by two column sets is shown once
        seen := seen || k_;
        trail := trail || jsonb_build_array(jsonb_build_object('event', v.ev, 'at', at_, 'who', by_txt, 'who_id', by_id, 'note', note_, 'source', 'record'));
      end if;
    end if;
  end loop;
  -- date-only columns (no time recorded)
  for v in select * from (values ('created', 'exp_date'), ('created', 'move_date'), ('created', 'bill_date'), ('created', 'case_date'), ('created', 'entry_date'), ('created', 'pay_date'), ('created', 'adv_date'), ('created', 'income_date'), ('created', 'xfer_date')) t(ev, ak) loop
    if r ? v.ak and not exists (select 1 from jsonb_array_elements(trail) x where x ->> 'event' = 'created') and nullif(r ->> v.ak, '') is not null then
      notes := notes || jsonb_build_array('only_the_date_is_recorded:' || v.ak); exit;
    end if;
  end loop;
  if r ? 'voided' and (r ->> 'voided')::boolean and not exists (select 1 from jsonb_array_elements(trail) x where x ->> 'event' = 'voided') then
    trail := trail || jsonb_build_array(jsonb_build_object('event', 'voided', 'at', null, 'who', public._rh_staff(nullif(r ->> 'void_by', '')::uuid), 'note', r ->> 'void_note', 'source', 'record'));
  end if;
  is_void := coalesce(r ->> 'status', '') in ('void', 'cancelled', 'rejected') or coalesce((r ->> 'voided')::boolean, false);
  if not has_creator and not exists (select 1 from jsonb_array_elements(trail) x where x ->> 'event' in ('created', 'requested', 'posted', 'logged') and x ->> 'who' is not null) then nr := nr || jsonb_build_array('who_created'); end if;
  if is_void and not exists (select 1 from jsonb_array_elements(trail) x where x ->> 'event' in ('voided', 'cancelled') and x ->> 'who' is not null) then nr := nr || jsonb_build_array('who_voided'); end if;
  if is_void and not exists (select 1 from jsonb_array_elements(trail) x where x ->> 'event' in ('voided', 'cancelled') and x ->> 'note' is not null) then nr := nr || jsonb_build_array('void_reason'); end if;

  -- stock reversal lines for sales and purchase bills; chain for a ledger row
  if public._rh_area_ok('stock') and tbl in ('sales', 'purchase_bills', 'sale_returns', 'production_runs') then
    select coalesce(jsonb_agg(jsonb_build_object('at', l.made_at, 'reason', l.reason, 'qty', l.qty_delta, 'item', i.name_en, 'who', public._rh_staff(l.created_by), 'ledger_id', l.id) order by l.made_at, l.id), '[]'::jsonb) into rev
      from public.stock_ledger l left join public.items i on i.id = l.item_id
     where l.ref_id = p_id and l.ref_type = case tbl when 'sales' then 'sale' when 'purchase_bills' then 'purchase' when 'sale_returns' then 'sale_return' else 'production' end
       and l.reason in ('reversal', 'sale_void_in') and l.location_id = any (locs);
  elsif public._rh_area_ok('stock') and tbl = 'stock_ledger' then
    select coalesce(jsonb_agg(jsonb_build_object('at', l.made_at, 'reason', l.reason, 'qty', l.qty_delta, 'who', public._rh_staff(l.created_by), 'ledger_id', l.id, 'relation', case when l.id::text = (r ->> 'reverses_id') then 'this_row_reverses' else 'reversed_by' end) order by l.made_at), '[]'::jsonb) into rev
      from public.stock_ledger l where (l.reverses_id::text = p_id or l.id::text = (r ->> 'reverses_id')) and l.location_id = any (locs);
  end if;
  -- journal entries of this record and their reversals
  if public._rh_area_ok('accounts') then
    select coalesce(jsonb_agg(jsonb_build_object('journal_id', j.id, 'at', j.created_at, 'status', j.status, 'source_type', j.source_type, 'reverses_id', j.reverses_id, 'who', coalesce(j.created_staff, public._rh_staff(j.created_by))) order by j.id), '[]'::jsonb) into jrev
      from (select * from public.journal_entries where source_id = p_id or source_id like p_id || ':%' union select * from public.journal_entries where id in (select reverses_id from public.journal_entries where source_id = p_id or source_id like p_id || ':%')) j;
  end if;
  -- exceptions raised by this record
  if public._rh_area_ok('control') and tbl in ('sales', 'entries') then
    select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'flag', e.flag_code, 'level', e.level, 'status', e.status, 'amount', e.amount, 'raised_at', e.created_at, 'resolved_by', e.resolved_staff, 'resolved_at', e.resolved_at, 'note', e.resolved_note) order by e.created_at), '[]'::jsonb) into exc
      from public.exceptions e where (own or public.can_do(e.form_code, 'approve')) and ((tbl = 'sales' and e.sale_id::text = p_id) or (tbl = 'entries' and e.entry_id::text = p_id));
  end if;
  -- paper-form corrections and change requests (who, when, why; not the figures)
  if tbl = 'entries' then
    select coalesce(jsonb_agg(jsonb_build_object('at', c.at, 'who', c.staff_id, 'note', c.note) order by c.at), '[]'::jsonb) into cor from public.corrections c where c.entry_id = p_id;
    select coalesce(jsonb_agg(jsonb_build_object('requested_at', q.created_at, 'requested_by', q.requested_staff, 'reason', q.reason, 'status', q.status, 'decided_by', q.decided_staff, 'decided_at', q.decided_at, 'decision_note', q.decision_note, 'new_rev', q.new_rev) order by q.created_at), '[]'::jsonb) into chg
      from public.entry_change_requests q where q.entry_id::text = p_id;
    if r ? 'rev_no' and coalesce((r ->> 'rev_no')::int, 0) > 0 and jsonb_array_length(chg) = 0 and jsonb_array_length(cor) = 0 then nr := nr || jsonb_build_array('who_changed_the_form_after_approval'); end if;
  end if;
  -- audit_log: the owner reads it; nobody else is allowed to (RLS), so it is not shown to them
  if own then
    select coalesce(jsonb_agg(jsonb_build_object('at', a.at, 'who', a.staff_id, 'user_id', a.user_id, 'action', a.action, 'detail', a.detail) order by a.at, a.id), '[]'::jsonb) into au
      from public.audit_log a where a.table_name = tbl and a.record_id = p_id;
  else
    notes := notes || jsonb_build_array('audit_log_owner_only');
  end if;
  if own and jsonb_array_length(au) = 0 then nr := nr || jsonb_build_array('audit_log_has_no_line_for_this_record'); end if;

  return jsonb_build_object('generated_at', now(), 'table', tbl, 'id', p_id, 'record', r, 'trail', (select coalesce(jsonb_agg(x order by x ->> 'at' nulls last), '[]'::jsonb) from jsonb_array_elements(trail) x),
    'reversals', rev, 'journal', jrev, 'exceptions', exc, 'corrections', cor, 'change_requests', chg, 'audit_log', au, 'not_recorded', nr, 'notes', notes);
end $$;

revoke all on function public.rpt_hub_trail(text, text) from public, anon;
grant execute on function public.rpt_hub_trail(text, text) to authenticated;
