-- Phase 498 (XC-5) - STAFF COACHING BOARD (OWNER ONLY): per person, the figures that already exist, side by side. No rankings, no scores, no public view.
-- Paste AFTER phase497. Paste-twice safe. Earlier phase files are not edited.
-- OFF by default: switch xc_coaching_on (false). Only the owner can read it, even when the switch is on.
-- The figures come from records that already exist: sales (sales, discounts, voids), cash shortage cases, production runs and their losses, attendance days (late minutes),
-- and complaints. A person with no record for a figure shows a blank, never 0. People are matched to a person's record by their staff id (profiles.staff_id) and by the employee link.
-- Shift and role awareness: not built in this phase (noted on the answer). The board does not judge; it lists what happened in the chosen period.
-- Reads personal data: nothing is shown to any other role, and the rows carry no rank field.

do $g$ begin
  if to_regclass('public.attendance_days') is null or to_regclass('public.shortage_cash_cases') is null or to_regclass('public.production_loss') is null then
    raise exception 'phase554 needs phases 404, 412 (attendance) and the shortage cases';
  end if;
  if to_regclass('public.crm_complaints') is null then raise exception 'phase554 needs the complaints table (CRM-H)'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'xc', v.kind, v.dv, v.unit, null, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('xc_coaching_on', 'switch', 'false'::jsonb, null::text, null::numeric, null::numeric,
   'কর্মী পর্যালোচনা বোর্ড (শুধু মালিক) / Staff coaching board (owner only): on', 'Owner-only view of the figures that already exist per person. OFF = nothing is shown to anyone.', 9540)
  ) as v(key, kind, dv, unit, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

create or replace function public.xc_staff_board(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, public._today() - 30); t date := coalesce(p_to, public._today()); rows_ jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not public.rule_on('xc_coaching_on') then return jsonb_build_object('skipped', 'switch_off'); end if;
  if t < f or t - f > 400 then raise exception 'bad_range'; end if;
  with
  emp as (select p.staff_id, p.full_name, e.id as employee_id from public.profiles p left join public.employees e on e.profile_id = p.id where p.staff_id is not null),
  sales_ as (select s.created_staff as sid, count(*) filter (where s.status = 'done') as sales_n, sum(s.total) filter (where s.status = 'done') as sales_amt,
                    count(*) filter (where s.status = 'done' and s.discount > 0) as disc_n, sum(s.discount) filter (where s.status = 'done') as disc_amt
               from public.sales s where s.sale_date between f and t and (p_loc is null or s.location_id = p_loc) and s.created_staff is not null group by 1),
  voids as (select s.void_staff as sid, count(*) as void_n from public.sales s where s.status = 'void' and s.void_staff is not null
              and (s.void_at at time zone 'Asia/Dhaka')::date between f and t and (p_loc is null or s.location_id = p_loc) group by 1),
  cash as (select e.staff_id as sid, sum(c.amount) as short_amt, count(*) as short_n from public.shortage_cash_cases c join emp e on e.employee_id = c.employee_id
            where c.void_at is null and c.case_date between f and t and (p_loc is null or c.location_id = p_loc) group by 1),
  prod as (select pr.created_staff as sid, sum(pr.yield_base) as yield_n from (select r.*, p.staff_id as created_staff from public.production_runs r join public.profiles p on p.id = r.created_by) pr
            where pr.status = 'done' and (pr.made_at at time zone 'Asia/Dhaka')::date between f and t and (p_loc is null or pr.location_id = p_loc) group by 1),
  rej as (select pr.created_staff as sid, sum(l.qty) as reject_q from public.production_loss l join (select r.id, p.staff_id as created_staff, r.location_id, r.made_at from public.production_runs r join public.profiles p on p.id = r.created_by) pr on pr.id = l.run_id
           where l.status = 'active' and l.kind = 'reject' and (pr.made_at at time zone 'Asia/Dhaka')::date between f and t and (p_loc is null or pr.location_id = p_loc) group by 1),
  att as (select e.staff_id as sid, count(*) as days, count(*) filter (where a.late_minutes > 0) as late_days, sum(a.late_minutes) as late_min
            from public.attendance_days a join emp e on e.employee_id = a.employee_id where a.day between f and t and (p_loc is null or a.location_id = p_loc) group by 1),
  cmp as (select c.created_staff as sid, count(*) as complaints from public.crm_complaints c where c.created_at::date between f and t and (p_loc is null or c.location_id = p_loc) and c.created_staff is not null group by 1),
  people as (select sid from sales_ union select sid from voids union select sid from cash union select sid from prod union select sid from rej union select sid from att union select sid from cmp)
  select coalesce(jsonb_agg(jsonb_build_object('staff_id', pe.sid, 'name', coalesce(em.full_name, pe.sid),
      'sales_bills', sa.sales_n, 'sales_amount', round(sa.sales_amt, 2), 'discount_bills', sa.disc_n, 'discount_amount', round(sa.disc_amt, 2),
      'discount_share_pct', case when coalesce(sa.sales_n, 0) > 0 then round(100.0 * sa.disc_n / sa.sales_n, 1) end,
      'voids', v.void_n,
      'cash_shortage_cases', ca.short_n, 'cash_shortage_amount', round(ca.short_amt, 2),
      'production_yield', round(pd.yield_n, 3), 'production_reject', round(rj.reject_q, 3),
      'reject_share_pct', case when coalesce(pd.yield_n, 0) > 0 then round(100 * coalesce(rj.reject_q, 0) / pd.yield_n, 1) end,
      'attendance_days', at.days, 'late_days', at.late_days, 'late_minutes', at.late_min,
      'complaints', cm.complaints)
      order by coalesce(em.full_name, pe.sid)), '[]'::jsonb) into rows_
    from people pe
    left join emp em on em.staff_id = pe.sid
    left join sales_ sa on sa.sid = pe.sid left join voids v on v.sid = pe.sid left join cash ca on ca.sid = pe.sid
    left join prod pd on pd.sid = pe.sid left join rej rj on rj.sid = pe.sid left join att at on at.sid = pe.sid left join cmp cm on cm.sid = pe.sid;
  return jsonb_build_object('from', f, 'to', t, 'location_id', p_loc, 'rows', rows_, 'owner_only', true,
    'notes', jsonb_build_array('Owner only. Figures are for the period shown and are not a score. No ranking is shown.',
      'A blank means no record for that figure; it is not zero.', 'Shift and role are not taken into account in this version.'));
end $$;

revoke all on function public.xc_staff_board(date, date, int) from public, anon;
grant execute on function public.xc_staff_board(date, date, int) to authenticated;

notify pgrst, 'reload schema';
