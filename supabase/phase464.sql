-- Phase 464 (RPT-C3, package R8 part 3) - AUDIT AND CONTROL: price-override approver captured (#175), voids / refunds / unusual transactions in one list (#176), per-user activity (#177).
-- Paste AFTER phase463. Paste-twice safe. No earlier phase file is edited; record_sale2 and every shared function stay as they are.
--
--   NEW CAPTURE (additive, never blocks a sale): trigger sales_c3_override_capture on sales (AFTER INSERT). When a bill has lines whose price was changed, it stores who approved:
--       approval 'grant'         the seller holds the price_override right and the owner switched pos_override_manager ON (the same rule record_sale2 uses);
--       approval 'emergency'     a one-off emergency approval was used (the decider is stored);
--       approval 'not_required'  the setting pos_override_manager is OFF, so no approver is asked for (today's behaviour);
--       approval 'unknown'       the bill came in by a path that does not carry the approval (stored as unknown, never guessed).
--     Bills made BEFORE this phase have no row: the report says "not captured", never an approver it does not know. Any error in the capture is swallowed - the sale always succeeds.
--   aud_overrides   discount approvals (already stored on the bill) and price-override approvals side by side, per bill, with counts by approver and the capture coverage.
--   aud_unusual     sale voids, voided payments, returns (and the refund paid), voided returns and the exceptions raised on bills: events of known kinds, NO invented threshold.
--   aud_user_activity  per person: logins (ok / failed), what he did (audit log actions, exports), bills made / voided / discounted, returns, forms created and decided.
--                   Login and audit-log columns come from owner-only tables, so only the owner sees them; everyone else with the control report sees the business-record columns.
-- Access: rpt_access('control') and the caller's places. Test data only (test_*).

do $g$ begin
  if to_regprocedure('public.aud_cost_gaps(integer)') is null or to_regprocedure('public._append_only43()') is null then raise exception 'phase464 needs phases 463 and 43 first'; end if;
end $g$;

create table if not exists public.sale_price_overrides (
  sale_id uuid primary key references public.sales(id),
  override_lines int not null check (override_lines >= 1),
  approval text not null check (approval in ('grant', 'emergency', 'not_required', 'unknown')),
  approver_by uuid, approver_staff text,
  captured_at timestamptz not null default now()
);
drop trigger if exists sale_price_overrides_ro on public.sale_price_overrides;
create trigger sale_price_overrides_ro before update or delete on public.sale_price_overrides for each row execute function public._append_only43();
drop trigger if exists sale_price_overrides_ro_t on public.sale_price_overrides;
create trigger sale_price_overrides_ro_t before truncate on public.sale_price_overrides for each statement execute function public._append_only43();
alter table public.sale_price_overrides enable row level security;
revoke all on public.sale_price_overrides from public, anon, authenticated;
grant select on public.sale_price_overrides to authenticated;
drop policy if exists sale_price_overrides_read on public.sale_price_overrides;
create policy sale_price_overrides_read on public.sale_price_overrides for select to authenticated
  using (public.is_active() and exists (select 1 from public.sales s where s.id = sale_id));

create or replace function public._c3_sale_override_capture() returns trigger language plpgsql security definer set search_path = public as $$
declare n int; em text; rid bigint; r public.emergency_requests; ap text := 'unknown'; who uuid; sid text;
begin
  begin
    select count(*) into n from jsonb_array_elements(case when jsonb_typeof(new.lines) = 'array' then new.lines else '[]'::jsonb end) e where e ->> 'override' = 'true';
    if coalesce(n, 0) = 0 then return new; end if;
    em := current_setting('bos.em_used', true);
    if em is not null and em ~ ':price_override' then
      select (x.m)[1]::bigint into rid from regexp_matches(em, '([0-9]+):price_override', 'g') as x(m) order by (x.m)[1]::bigint desc limit 1;
      select * into r from public.emergency_requests where id = rid;
      if found and r.decided_by is not null then ap := 'emergency'; who := r.decided_by; sid := r.decided_staff; end if;
    elsif not public.rule_on('pos_override_manager') then
      ap := 'not_required';
    elsif public.can_grant('price_override') then
      ap := 'grant'; who := new.created_by; select staff_id into sid from public.profiles where id = new.created_by;
    end if;
    insert into public.sale_price_overrides (sale_id, override_lines, approval, approver_by, approver_staff) values (new.id, n, ap, who, sid) on conflict (sale_id) do nothing;
  exception when others then null;     -- the capture must never stop a sale
  end;
  return new;
end $$;
drop trigger if exists sales_c3_override_capture on public.sales;
create trigger sales_c3_override_capture after insert on public.sales for each row execute function public._c3_sale_override_capture();

-- ---------- #175 discount and price-override approvals ----------
create or replace function public.aud_overrides(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; rows_ jsonb; byappr jsonb; cov jsonb; first_cap timestamptz;
begin
  perform public._c3_need('control'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  select min(captured_at) into first_cap from public.sale_price_overrides;
  with b as (
    select s.id, s.receipt, s.sale_date, s.location_id, s.created_staff, s.total, s.discount, s.discount_kind, s.discount_input, s.discount_approved_staff, s.discount_approval,
           (select count(*) from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e where e ->> 'override' = 'true') as ov_lines, o.approval as ov_approval, o.approver_staff as ov_staff
      from public.sales s left join public.sale_price_overrides o on o.sale_id = s.id
     where s.status = 'done' and s.sale_date between p_from and p_to and s.location_id = any (locs) and (p_loc is null or s.location_id = p_loc))
  select coalesce(jsonb_agg(jsonb_build_object('sale_id', b.id, 'receipt', b.receipt, 'sale_date', b.sale_date, 'location_id', b.location_id, 'seller', b.created_staff, 'total', b.total,
        'discount', nullif(b.discount, 0), 'discount_kind', b.discount_kind, 'discount_input', b.discount_input, 'discount_approver', b.discount_approved_staff, 'discount_approval', b.discount_approval,
        'override_lines', nullif(b.ov_lines, 0), 'override_approval', case when b.ov_lines = 0 then null else coalesce(b.ov_approval, 'not_captured') end, 'override_approver', b.ov_staff)
        order by b.sale_date desc, b.receipt desc), '[]'::jsonb) into rows_ from b where b.discount > 0 or b.ov_lines > 0;
  with b as (
    select s.discount, s.discount_approved_staff, s.discount_approval, (select count(*) from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e where e ->> 'override' = 'true') as ov_lines,
           o.approval as ov_approval, o.approver_staff as ov_staff
      from public.sales s left join public.sale_price_overrides o on o.sale_id = s.id
     where s.status = 'done' and s.sale_date between p_from and p_to and s.location_id = any (locs) and (p_loc is null or s.location_id = p_loc))
  select coalesce(jsonb_agg(jsonb_build_object('approver', z.ap, 'kind', z.k, 'bills', z.n) order by z.k, z.n desc), '[]'::jsonb) into byappr from (
      select coalesce(b.discount_approved_staff, '(none recorded)') as ap, 'discount'::text as k, count(*) as n from b where b.discount > 0 group by 1
      union all select coalesce(b.ov_staff, case when b.ov_approval = 'not_required' then '(not required: switch off)' else '(none recorded)' end), 'price_override', count(*) from b where b.ov_lines > 0 group by 1) z;
  select jsonb_build_object('discount_bills', count(*) filter (where discount > 0), 'discount_with_approver', count(*) filter (where discount > 0 and discount_approved_staff is not null),
         'override_bills', count(*) filter (where ov_lines > 0), 'override_captured', count(*) filter (where ov_lines > 0 and ov_approval is not null),
         'override_captured_pct', case when count(*) filter (where ov_lines > 0) > 0 then round(100.0 * count(*) filter (where ov_lines > 0 and ov_approval is not null) / count(*) filter (where ov_lines > 0), 1) end)
    into cov from (
      select s.discount, s.discount_approved_staff, o.approval as ov_approval,
             (select count(*) from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e where e ->> 'override' = 'true') as ov_lines
        from public.sales s left join public.sale_price_overrides o on o.sale_id = s.id
       where s.status = 'done' and s.sale_date between p_from and p_to and s.location_id = any (locs) and (p_loc is null or s.location_id = p_loc)) q;
  return jsonb_build_object('key', 'aud_overrides', 'from', p_from, 'to', p_to, 'loc', p_loc, 'rows', rows_, 'by_approver', byappr, 'coverage', cov,
    'capture_started', (first_cap at time zone 'Asia/Dhaka')::date,
    'settings', jsonb_build_object('pos_override_manager', public.rule_on('pos_override_manager'), 'pos_discount_manager', public.rule_on('pos_discount_manager')),
    'notes', jsonb_build_array('override_approver_captured_from_phase464', 'older_bills_say_not_captured', 'no_approver_is_asked_for_while_the_switch_is_off', 'a_discount_inside_the_limit_needs_no_approver'),
    'basis', 'Per bill: the approver stored with the discount, and the approver of a price change (stored by this phase onward). "Not captured" = the bill is older than the capture.');
end $$;

-- ---------- #176 voids, refunds and unusual transactions ----------
create or replace function public._c3_unusual(d1 date, d2 date, locs int[])
returns table (type text, on_date date, event_at timestamptz, ref text, amount numeric, who text, reason text, status text, flag text, location_id int, sale_id uuid)
language sql stable security definer set search_path = public as $$
  select 'sale_void'::text, coalesce((s.void_at at time zone 'Asia/Dhaka')::date, s.sale_date), s.void_at, 'Receipt ' || s.receipt, s.total, coalesce(s.void_staff, public._c3_staff(s.void_by)), s.void_note, 'void'::text, null::text, s.location_id, s.id
    from public.sales s where s.status = 'void' and coalesce((s.void_at at time zone 'Asia/Dhaka')::date, s.sale_date) between d1 and d2 and s.location_id = any (locs)
  union all
  select 'payment_void', (p.paid_at at time zone 'Asia/Dhaka')::date, null, 'Payment ' || p.id, p.amount, null, p.void_note, 'void', p.kind, p.location_id, p.sale_id
    from public.sale_payments p where p.voided and (p.paid_at at time zone 'Asia/Dhaka')::date between d1 and d2 and p.location_id = any (locs)
  union all
  select 'return', (r.created_at at time zone 'Asia/Dhaka')::date, r.created_at, 'Return ' || left(r.id::text, 8), r.amount, r.created_staff, r.note, r.status, r.reason_code, r.location_id, r.sale_id
    from public.sale_returns r where r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs)
  union all
  select 'refund_paid', (r.created_at at time zone 'Asia/Dhaka')::date, r.created_at, 'Return ' || left(r.id::text, 8), r.refund_amount, r.created_staff, r.note, r.status, r.refund_mode, r.location_id, r.sale_id
    from public.sale_returns r where r.status = 'done' and coalesce(r.refund_amount, 0) > 0 and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs)
  union all
  select 'return_void', coalesce((r.void_at at time zone 'Asia/Dhaka')::date, (r.created_at at time zone 'Asia/Dhaka')::date), r.void_at, 'Return ' || left(r.id::text, 8), r.amount, public._c3_staff(r.void_by), r.void_note, r.status, r.reason_code, r.location_id, r.sale_id
    from public.sale_returns r where (r.status = 'void' or r.void_at is not null) and coalesce((r.void_at at time zone 'Asia/Dhaka')::date, (r.created_at at time zone 'Asia/Dhaka')::date) between d1 and d2 and r.location_id = any (locs)
  union all
  select 'exception', e.entry_date, e.created_at, 'Receipt ' || (select s.receipt from public.sales s where s.id = e.sale_id), e.amount, e.resolved_staff, e.resolved_note, e.status, e.flag_code, e.location_id, e.sale_id
    from public.exceptions e where e.sale_id is not null and e.entry_date between d1 and d2 and e.location_id = any (locs)
$$;

create or replace function public.aud_unusual(p_from date, p_to date, p_loc int default null, p_type text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; rows_ jsonb; bytype jsonb;
begin
  perform public._c3_need('control'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(to_jsonb(z) order by z.on_date desc, z.type), '[]'::jsonb) into rows_ from (
    select u.type, u.on_date, u.event_at, u.ref, u.amount, u.who, u.reason, u.status, u.flag, u.location_id, u.sale_id
      from public._c3_unusual(p_from, p_to, locs) u where (p_loc is null or u.location_id = p_loc) and (p_type is null or u.type = p_type) order by u.on_date desc, u.type limit 2000) z;
  select coalesce(jsonb_agg(jsonb_build_object('type', z.type, 'n', z.n, 'amount', z.a) order by z.type), '[]'::jsonb) into bytype
    from (select u.type, count(*) as n, round(sum(u.amount), 2) as a from public._c3_unusual(p_from, p_to, locs) u where p_loc is null or u.location_id = p_loc group by u.type) z;
  return jsonb_build_object('key', 'aud_unusual', 'from', p_from, 'to', p_to, 'loc', p_loc, 'rows', rows_, 'by_type', bytype,
    'notes', jsonb_build_array('events_of_known_kinds_not_a_threshold', 'a_refund_is_also_inside_its_return', 'payment_void_time_not_stored'),
    'basis', 'Bill voids, voided payments, returns and the refund paid, voided returns, and the exceptions raised on bills. Nothing here is flagged by an amount limit.');
end $$;

-- ---------- #177 per-user activity ----------
create or replace function public.aud_user_activity(p_from date, p_to date, p_staff text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; own boolean := public.is_owner(); rows_ jsonb; tl jsonb := null; lg jsonb := null;
begin
  perform public._c3_need('control'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(null);
  with ppl as (select p.staff_id, p.full_name, p.status from public.profiles p where p.staff_id is not null and (p_staff is null or p.staff_id = p_staff)),
  sl as (select s.created_staff as st, count(*) as bills, count(*) filter (where s.discount > 0) as disc
           from public.sales s where s.sale_date between p_from and p_to and s.location_id = any (locs) group by 1),
  vd as (select s.void_staff as st, count(*) as voided from public.sales s where s.status = 'void' and (s.void_at at time zone 'Asia/Dhaka')::date between p_from and p_to and s.location_id = any (locs) group by 1),
  rt as (select r.created_staff as st, count(*) as returns from public.sale_returns r where r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to and r.location_id = any (locs) group by 1),
  ec as (select e.created_staff as st, count(*) as made from public.entries e where (e.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to and e.location_id = any (locs) group by 1),
  ed as (select e.checked_staff as st, count(*) as decided from public.entries e where (e.checked_at at time zone 'Asia/Dhaka')::date between p_from and p_to and e.location_id = any (locs) group by 1),
  lo as (select a.staff_id as st, count(*) filter (where a.ok) as ok_, count(*) filter (where not a.ok) as bad_, max(a.at) filter (where a.ok) as last_ok from public.login_attempts a
          where own and (a.at at time zone 'Asia/Dhaka')::date between p_from and p_to group by 1),
  au as (select a.staff_id as st, count(*) as acts, count(*) filter (where a.action = 'export') as exports from public.audit_log a
          where own and (a.at at time zone 'Asia/Dhaka')::date between p_from and p_to group by 1)
  select coalesce(jsonb_agg(jsonb_build_object('staff_id', ppl.staff_id, 'name', ppl.full_name, 'status', ppl.status,
        'bills_made', coalesce(sl.bills, 0), 'bills_with_discount', coalesce(sl.disc, 0), 'bills_voided_by_him', coalesce(vd.voided, 0), 'returns_made', coalesce(rt.returns, 0),
        'forms_created', coalesce(ec.made, 0), 'forms_decided', coalesce(ed.decided, 0),
        'logins_ok', case when own then coalesce(lo.ok_, 0) end, 'logins_failed', case when own then coalesce(lo.bad_, 0) end, 'last_login', lo.last_ok,
        'audit_actions', case when own then coalesce(au.acts, 0) end, 'exports', case when own then coalesce(au.exports, 0) end)
        order by coalesce(sl.bills, 0) desc, ppl.staff_id), '[]'::jsonb) into rows_
    from ppl left join sl on sl.st = ppl.staff_id left join vd on vd.st = ppl.staff_id left join rt on rt.st = ppl.staff_id left join ec on ec.st = ppl.staff_id left join ed on ed.st = ppl.staff_id
         left join lo on lo.st = ppl.staff_id left join au on au.st = ppl.staff_id
   where coalesce(sl.bills, 0) + coalesce(vd.voided, 0) + coalesce(rt.returns, 0) + coalesce(ec.made, 0) + coalesce(ed.decided, 0) + coalesce(lo.ok_, 0) + coalesce(lo.bad_, 0) + coalesce(au.acts, 0) > 0;
  if own and p_staff is not null then
    select coalesce(jsonb_agg(jsonb_build_object('at', a.at, 'action', a.action, 'table', a.table_name, 'record', a.record_id) order by a.at desc), '[]'::jsonb) into tl
      from (select * from public.audit_log x where x.staff_id = p_staff and (x.at at time zone 'Asia/Dhaka')::date between p_from and p_to order by x.at desc limit 100) a;
    select coalesce(jsonb_agg(jsonb_build_object('at', a.at, 'ok', a.ok) order by a.at desc), '[]'::jsonb) into lg
      from (select * from public.login_attempts x where x.staff_id = p_staff and (x.at at time zone 'Asia/Dhaka')::date between p_from and p_to order by x.at desc limit 50) a;
  end if;
  return jsonb_build_object('key', 'aud_users', 'from', p_from, 'to', p_to, 'staff', p_staff, 'rows', rows_, 'timeline', tl, 'logins', lg,
    'notes', jsonb_build_array('business_record_columns', 'places_you_can_see_only') || case when own then '[]'::jsonb else jsonb_build_array('login_and_audit_columns_owner_only') end,
    'basis', 'Counts per person from the business records (bills, voids, returns, forms) and, for the owner, from the login and audit logs. Counts are not a judgement of the person.');
end $$;

revoke all on function public._c3_sale_override_capture(), public._c3_unusual(date, date, int[]) from public, anon, authenticated;
revoke all on function public.aud_overrides(date, date, int), public.aud_unusual(date, date, int, text), public.aud_user_activity(date, date, text) from public, anon;
grant execute on function public.aud_overrides(date, date, int), public.aud_unusual(date, date, int, text), public.aud_user_activity(date, date, text) to authenticated;
notify pgrst, 'reload schema';
