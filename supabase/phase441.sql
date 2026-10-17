-- Phase 441 (bos441) - REPORT HONESTY, part 2 (package RPT-C1, block R1). Paste AFTER phase440. Paste-twice safe. Earlier phase files are not edited.
-- WHY (docs/REPORTS_AUDIT_3.md F5, F9, F10, F14): the staff attendance report reads the paper register only and shows nothing while the app holds the attendance; the compliance report counts every
--      calendar day as a missing form (623 of 624 on a fresh install); the customer segment (RFM) and the lapsed-customer reports use cut-offs typed into the code (3 orders, 30 / 60 days, 180 days);
--      the cash short / over report ignores whether the owner rejected the shortage case.
-- WHAT THIS FILE DOES (every new setting is blank or OFF = today's figures; the only change with all defaults is the extra columns / rows described below - proved by tests/sql/c1_before_after.sh)
--   1. attendance_summary (engine 2): reads BOTH sources, in separate rows: attendance records of the app (attendance_days) and the paper register 02-1. New column "source". The two are never added by name.
--   2. x4_compliance: setting "report_compliance_from" (rollout start date, blank = every calendar day counts as before) and "report_compliance_closed_days" (weekly closed days, e.g. fri; blank = none).
--      With a start date only the days from that date count and closed days (holidays table, weekly closed days) are left out; new column closed_days.
--   3. m1_rfm / d5_lapsed: cut-offs are settings (report_rfm_min_orders, report_rfm_recent_days, report_rfm_atrisk_days, report_lapsed_days). Blank = the number that was in the code (3 / 30 / 60 / 180),
--      so today's output does not change; the report notice says which numbers are built-in values and not set by the owner.
--   4. cash_short_over (engine 2): setting "report_cash_short_by_case_on" (OFF = today's figures). ON leaves out the sheets whose shortage case was rejected or voided. New columns: cases open / approved / rejected / void.
--   5. Notices (report_notes topics, phase 440) for these five reports.
-- !! Re-pasting phase 21, 25, 26 or 76-79 removes the bos441 patches: paste this file again.

do $g$ begin
  if to_regprocedure('public._c1_p440_present()') is null then raise exception 'phase441 needs phase440 first'; end if;
  if to_regprocedure('public.report_run2_core(text,jsonb,text,text,integer)') is null or to_regprocedure('public._r3q_x4_compliance(date,date,integer[],jsonb)') is null
     or to_regprocedure('public._r3q_m1_rfm(date,date,integer[],jsonb)') is null or to_regprocedure('public._r3q_d5_lapsed(date,date,integer[],jsonb)') is null
     or to_regclass('public.attendance_days') is null or to_regclass('public.shortage_cash_cases') is null or to_regclass('public.holidays') is null then
    raise exception 'phase441 needs the report functions and tables of phases 21, 25, 42, 81';
  end if;
end $g$;

create or replace function public._c1_p441_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- settings (rules, module reports). All blank / OFF. ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('report_rfm_min_orders', 'reports', 'number', null, 'orders', null, 1, 1000,
  'সেরা গ্রাহক (Champion): কমপক্ষে কতটি অর্ডার', 'Champion গ্রাহক: কমপক্ষে কতটি order', 'Best customer (Champion): at least this many orders',
  'ফাঁকা থাকলে রিপোর্ট আগের ধরা সংখ্যা (3) ব্যবহার করে এবং সেটি যে মালিকের দেওয়া নয় তা জানায়।', 'ফাঁকা থাকলে report আগের ধরা সংখ্যা (3) ব্যবহার করে এবং সেটি যে মালিকের দেওয়া নয় তা জানায়।',
  'Blank: the report uses the number that was built into it (3) and says it was not set by the owner.', 811),
 ('report_rfm_recent_days', 'reports', 'number', null, 'days', null, 1, 3650,
  'সেরা গ্রাহক: শেষ কেনা কত দিনের মধ্যে', 'Champion: শেষ কেনা কত দিনের মধ্যে', 'Best customer (Champion): last purchase within this many days',
  'ফাঁকা থাকলে আগের ধরা সংখ্যা (30) ব্যবহার হয়।', 'ফাঁকা থাকলে আগের ধরা সংখ্যা (30) ব্যবহার হয়।', 'Blank: the built-in number (30) is used and the report says so.', 812),
 ('report_rfm_atrisk_days', 'reports', 'number', null, 'days', null, 1, 3650,
  'ঝুঁকিতে (At-risk) গ্রাহক: কত দিন কেনেননি', 'At-risk গ্রাহক: কত দিন কেনেননি', 'At-risk customer: no purchase for more than this many days',
  'ফাঁকা থাকলে আগের ধরা সংখ্যা (60) ব্যবহার হয়।', 'ফাঁকা থাকলে আগের ধরা সংখ্যা (60) ব্যবহার হয়।', 'Blank: the built-in number (60) is used and the report says so.', 813),
 ('report_lapsed_days', 'reports', 'number', null, 'days', null, 1, 3650,
  'নিষ্ক্রিয় গ্রাহক: কত দিন আগে পর্যন্ত দেখো', 'Lapsed গ্রাহক: কত দিন আগে পর্যন্ত দেখো', 'Lapsed customers: look back this many days',
  'যে গ্রাহক এই সময়ের আগে এত দিনের মধ্যে কিনেছেন কিন্তু এই সময়ে কেনেননি তিনি নিষ্ক্রিয়। ফাঁকা থাকলে আগের ধরা সংখ্যা (180)।',
  'যে গ্রাহক এই সময়ের আগে এত দিনের মধ্যে কিনেছেন কিন্তু এই সময়ে কেনেননি তিনি lapsed। ফাঁকা থাকলে আগের ধরা সংখ্যা (180)।',
  'A customer who bought within this many days before the period but not in it is lapsed. Blank: the built-in number (180) is used and the report says so.', 814),
 ('report_compliance_from', 'reports', 'text', null, null, null, null, null,
  'ফর্ম জমা বাধ্যতামূলক এই তারিখ থেকে (রোলআউট শুরু)', 'Form জমা বাধ্যতামূলক এই তারিখ থেকে (rollout শুরু)', 'Forms are required from this date (rollout start)',
  'YYYY-MM-DD লিখুন। ফাঁকা থাকলে নিয়ম-পালন রিপোর্ট পিরিয়ডের প্রতিটি দিন ধরে (আগের মতো) এবং কত দিন বাদ গেছে তা বেশি দেখায়।',
  'YYYY-MM-DD লিখুন। ফাঁকা থাকলে compliance report period-এর প্রতিটি দিন ধরে (আগের মতো) এবং missing দিন বেশি দেখায়।',
  'Type a date as YYYY-MM-DD. Blank: the compliance report counts every calendar day of the period as before, so missing days are overstated. With a date: only days from it count and closed days are left out.', 815),
 ('report_compliance_closed_days', 'reports', 'text', null, null, null, null, null,
  'সাপ্তাহিক বন্ধের দিন (নিয়ম-পালন রিপোর্ট)', 'Weekly বন্ধের দিন (compliance report)', 'Weekly closed days for the compliance report',
  'যেমন fri অথবা fri,sat। ফাঁকা থাকলে কোনো সাপ্তাহিক বন্ধ ধরা হয় না। ছুটির তালিকা (holidays) সবসময় ধরা হয়। শুধু ফর্ম জমার শুরুর তারিখ দিলে কাজ করে।',
  'যেমন fri অথবা fri,sat। ফাঁকা থাকলে কোনো weekly বন্ধ ধরা হয় না। ছুটির তালিকা (holidays) সবসময় ধরা হয়। শুধু form জমার শুরুর তারিখ দিলে কাজ করে।',
  'For example fri or fri,sat. Blank: no weekly closed day. The holidays list is always used. Acts only when the rollout start date above is set.', 816),
 ('report_cash_short_by_case_on', 'reports', 'switch', 'false', null, null, null, null,
  'ক্যাশ কম/বেশি রিপোর্ট কেসের অবস্থা মানে', 'Cash কম/বেশি report case-এর অবস্থা মানে', 'Cash short/over report follows the shortage case',
  'বন্ধ থাকলে রিপোর্ট আগের মতো প্রতিটি ১৪-১ শিটের চিহ্ন ধরে। চালু করলে যে শিটের কেস বাতিল (rejected) বা ভয়েড তা বাদ যায়।',
  'Off থাকলে report আগের মতো প্রতিটি ১৪-১ শিটের চিহ্ন ধরে। On করলে যে শিটের case rejected বা void তা বাদ যায়।',
  'Off: the report counts the flag of every daily sheet (14-1) as today. On: sheets whose shortage case was rejected or voided are left out.', 817)
on conflict (key) do nothing;

-- ---------- helpers (closed to browsers) ----------
create or replace function public._c1_rfm(p_k text) returns numeric language sql stable security definer set search_path = public as $$
  select case p_k
    when 'min_orders'  then coalesce(public.rule_num('report_rfm_min_orders'), 3)
    when 'recent_days' then coalesce(public.rule_num('report_rfm_recent_days'), 30)
    when 'atrisk_days' then coalesce(public.rule_num('report_rfm_atrisk_days'), 60) end $$;
create or replace function public._c1_lapsed_days() returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(public.rule_num('report_lapsed_days'), 180) $$;
-- the rollout start date; null when blank or not a date
create or replace function public._c1_compliance_from() returns date language plpgsql stable security definer set search_path = public as $$
declare v text := public.rule_txt('report_compliance_from');
begin
  if v is null or btrim(v) !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  begin return btrim(v)::date; exception when others then return null; end;
end $$;
-- is this place closed on this day? (holidays list: everywhere or this place; weekly closed days rule)
create or replace function public._c1_is_closed(p_loc int, p_day date) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.holidays h where h.active and h.day = p_day and (h.location_id is null or h.location_id = p_loc))
      or (public.rule_txt('report_compliance_closed_days') is not null
          and lower(to_char(p_day, 'dy')) = any (string_to_array(lower(regexp_replace(public.rule_txt('report_compliance_closed_days'), '\s', '', 'g')), ','))) $$;
create or replace function public._c1_case_strict() returns boolean language sql stable security definer set search_path = public as $$
  select public.rule_on('report_cash_short_by_case_on') $$;

-- attendance rows from both sources, one row per person-day (app) or per person-line (paper register). src tells them apart; they are never joined or added by name.
create or replace function public._c1_att_rows(p_from date, p_to date, p_locs int[])
returns table (id uuid, location_id int, person text, src text, present numeric, late numeric, absent numeric, leave_unpaid numeric, leave_paid numeric, ot_hours numeric)
language sql stable security definer set search_path = public as $$
  select e.id, e.location_id, btrim(r ->> 'name'), 'paper'::text, public._r2_num(r -> 'present'), public._r2_num(r -> 'late'), public._r2_num(r -> 'absent'),
         public._r2_num(r -> 'leave_unpaid'), public._r2_num(r -> 'leave_paid'), public._r2_num(r -> 'ot_hours')
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'staff') = 'array' then e.data -> 'staff' else '[]'::jsonb end) r
   where e.form_code = '02-1' and e.status in ('submitted', 'approved') and e.entry_date between p_from and p_to and e.location_id = any (p_locs)
     and btrim(coalesce(r ->> 'name', '')) <> ''
  union all
  select a.employee_id, coalesce(a.location_id, m.primary_location_id), coalesce(nullif(btrim(m.full_name_bn), ''), nullif(btrim(m.full_name_en), ''), m.employee_no, '-'), 'app'::text,
         (case when a.status in ('present', 'late') then 1 when a.status = 'half_day' then 0.5 else 0 end)::numeric,
         (case when a.status = 'late' then 1 else 0 end)::numeric,
         (case when a.status = 'absent' then 1 else 0 end)::numeric,
         (case when a.status = 'unpaid' or (a.status = 'leave' and a.paid_day is false) then 1 else 0 end)::numeric,
         (case when a.status = 'leave' and a.paid_day is not false then 1 else 0 end)::numeric,
         round(a.ot_minutes / 60.0, 2)
    from public.attendance_days a join public.employees m on m.id = a.employee_id
   where a.day between p_from and p_to and coalesce(a.location_id, m.primary_location_id) = any (p_locs) $$;

revoke all on function public._c1_rfm(text), public._c1_lapsed_days(), public._c1_compliance_from(), public._c1_is_closed(int, date), public._c1_case_strict(),
  public._c1_att_rows(date, date, int[]) from public, anon, authenticated;

-- ---------- 3. RFM and lapsed: the numbers become settings; blank = the number that was in the code ----------
select public._c1_patch('public._r3q_m1_rfm(date,date,integer[],jsonb)'::regprocedure, 'bos441', array[
  $o$'segment', case when c.n >= 3 and d2 - c.last_d <= 30 then 'Champion' when c.n >= 2 and d2 - c.last_d > 60 then 'At-risk' when c.n = 1 then 'One-time' else 'Regular' end,$o$,
  $n$'segment', case when c.n >= public._c1_rfm('min_orders') /* bos441: cut-offs are settings, blank = the old built-in numbers */ and d2 - c.last_d <= public._c1_rfm('recent_days') then 'Champion'
                     when c.n >= 2 and d2 - c.last_d > public._c1_rfm('atrisk_days') then 'At-risk' when c.n = 1 then 'One-time' else 'Regular' end,$n$]);
select public._c1_patch('public._r3q_d5_lapsed(date,date,integer[],jsonb)'::regprocedure, 'bos441', array[
  $o$where c.n_p > 0 or c.last_d >= d1 - 180;$o$,
  $n$where c.n_p > 0 or c.last_d >= d1 - public._c1_lapsed_days()::int;   /* bos441: the 180 days is a setting, blank = 180 */$n$]);

-- ---------- 2. compliance: rollout start date and closed days (a stop if the function is neither the original nor already this version) ----------
do $g$ declare def text := pg_get_functiondef('public._r3q_x4_compliance(date,date,integer[],jsonb)'::regprocedure);
begin
  if position('bos441' in def) = 0 and position('cross join (values (''14-1''), (''10-1'')) f(code)' in def) = 0 then
    raise exception 'bos441 patch site not found in _r3q_x4_compliance: the function is not the original';
  end if;
end $g$;
create or replace function public._r3q_x4_compliance(d1 date, d2 date, locs integer[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  /* bos441: setting report_compliance_from blank = every calendar day of the period counts (as before). With a date only the days from it count and closed days are left out. */
  with today as (select (now() at time zone 'Asia/Dhaka')::date as t),
  hi as (select least(d2, (select t from today)) as h),
  rf as (select public._c1_compliance_from() as fd),
  lo as (select case when (select fd from rf) is null then d1 else greatest(d1, (select fd from rf)) end as v)
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'form', f.code,
      'days', case when (select fd from rf) is null then greatest((select h from hi) - d1 + 1, 0) else dd.req end,
      'submitted_days', case when (select fd from rf) is null then coalesce(s.sd, 0) else dd.sd_req end,
      'missing_days', case when (select fd from rf) is null then greatest(greatest((select h from hi) - d1 + 1, 0) - coalesce(s.sd, 0), 0) else dd.req - dd.sd_req end,
      'compliance_pct', case when (select fd from rf) is null then (case when greatest((select h from hi) - d1 + 1, 0) > 0 then round(100.0 * coalesce(s.sd, 0) / greatest((select h from hi) - d1 + 1, 0), 2) end)
                             else (case when dd.req > 0 then round(100.0 * dd.sd_req / dd.req, 2) end) end,
      'stale_drafts', coalesce(s.stale, 0), 'late_submits', coalesce(s.late, 0),
      'closed_days', case when (select fd from rf) is null then 0 else dd.closed end, 'start_date', (select fd from rf))
    from public.locations l
    cross join (values ('14-1'), ('10-1')) f(code)
    left join lateral (
      select count(distinct e.entry_date) filter (where e.status in ('submitted', 'approved')) as sd,
             count(*) filter (where e.status = 'draft' and e.entry_date < (select t from today) - 1) as stale,
             count(*) filter (where e.status in ('submitted', 'approved') and not e.entered_later and e.submitted_at is not null
                                and (e.submitted_at at time zone 'Asia/Dhaka')::date > e.entry_date) as late
        from public.entries e where e.form_code = f.code and e.location_id = l.id and e.entry_date between d1 and d2) s on true
    left join lateral (
      select count(*) filter (where not q.cl) as req, count(*) filter (where q.cl) as closed, count(*) filter (where not q.cl and q.has_sub) as sd_req
        from (select g.d::date as d, public._c1_is_closed(l.id, g.d::date) as cl,
                     exists (select 1 from public.entries e where e.form_code = f.code and e.location_id = l.id and e.entry_date = g.d::date and e.status in ('submitted', 'approved')) as has_sub
                from generate_series((select v from lo), (select h from hi), interval '1 day') g(d)
               where (select fd from rf) is not null) q) dd on true
   where l.id = any (locs) and l.kind = 'showroom' and l.is_active and l.status = 'live';
$$;
revoke all on function public._r3q_x4_compliance(date, date, integer[], jsonb) from public, anon, authenticated;
update public.report_defs3 set cols = cols || '[["closed_days","বন্ধ দিন (বাদ)","Closed days (left out)","int"]]'::jsonb where key = 'x4_compliance' and position('"closed_days"' in cols::text) = 0;
update public.report_defs3 set tot = array_append(tot, 'closed_days') where key = 'x4_compliance' and not ('closed_days' = any (tot));

-- ---------- 1 and 4. attendance_summary and cash_short_over (engine 2 core, text patch) ----------
select public._c1_patch('public.report_run2_core(text,jsonb,text,text,integer)'::regprocedure, 'bos441a', array[
  -- cash short / over: the case of each sheet
  $o$where f ->> 'code' = 'cash_short_over'), 0) as so$o$,
  $n$where f ->> 'code' = 'cash_short_over'), 0) as so, (select c.status from public.shortage_cash_cases c where c.entry_id = e.id) as cs   /* bos441a: the shortage case of the sheet */$n$,
  $o$from public.entries e where e.form_code = '14-1' and e.status in ('submitted', 'approved') and e.entry_date between %L and %L and e.location_id = any (%L::int[])) x$o$,
  $n$from public.entries e where e.form_code = '14-1' and e.status in ('submitted', 'approved') and e.entry_date between %L and %L and e.location_id = any (%L::int[])
              and (not public._c1_case_strict() or coalesce((select c.status from public.shortage_cash_cases c where c.entry_id = e.id), 'open') not in ('rejected', 'void'))) x$n$,
  $o$coalesce(max(abs(x.so)), 0) as worst$o$,
  $n$coalesce(max(abs(x.so)), 0) as worst,
        count(*) filter (where x.cs = 'open') as cases_open, count(*) filter (where x.cs = 'approved') as cases_approved, count(*) filter (where x.cs = 'rejected') as cases_rejected, count(*) filter (where x.cs = 'void') as cases_void$n$,
  $o$sum(net) as net, max(worst) as worst';$o$,
  $n$sum(net) as net, max(worst) as worst, sum(cases_open) as cases_open, sum(cases_approved) as cases_approved, sum(cases_rejected) as cases_rejected, sum(cases_void) as cases_void';$n$,
  $o$["worst","সবচেয়ে বড় পার্থক্য","Largest gap","money"]]'::jsonb;$o$,
  $n$["worst","সবচেয়ে বড় পার্থক্য","Largest gap","money"],["cases_open","খোলা কেস","Cases open","int"],["cases_approved","অনুমোদিত কেস","Cases approved","int"],["cases_rejected","বাতিল কেস","Cases rejected","int"],["cases_void","ভয়েড কেস","Cases void","int"]]'::jsonb;$n$]);

select public._c1_patch_span('public.report_run2_core(text,jsonb,text,text,integer)'::regprocedure, 'bos441b',
  $s$t := format($f$select %s count(distinct x.id) as sheets,$s$,
  $e$elsif p_key = 'exceptions_summary' then$e$,
  $n$t := format($f$select %s case x.src when 'app' then 'App attendance' else 'Paper register (02-1)' end as source,
        case when x.src = 'paper' then count(distinct x.id) end as sheets, case when x.src = 'app' then count(*) end as records,
        coalesce(sum(x.present), 0) as present, coalesce(sum(x.late), 0) as late, coalesce(sum(x.absent), 0) as absent,
        coalesce(sum(x.leave_unpaid), 0) as leave_unpaid, coalesce(sum(x.leave_paid), 0) as leave_paid, coalesce(sum(x.ot_hours), 0) as ot_hours
      from public._c1_att_rows(%L, %L, %L::int[]) x   /* bos441b: the app attendance records and the paper register 02-1, in separate rows */
        join public.locations l on l.id = x.location_id
      %s$f$,
      case dgrp when 'person' then 'x.person as person,' when 'location' then 'l.id as location_id, l.name_bn as location_bn, l.name_en as location_en,' else '' end, d1, d2, eff,
      case dgrp when 'person' then 'group by x.person, x.src' when 'location' then 'group by l.id, l.name_bn, l.name_en, x.src' else 'group by x.src' end);
    tot := 'sum(sheets) as sheets, sum(records) as records, sum(present) as present, sum(late) as late, sum(absent) as absent, sum(leave_unpaid) as leave_unpaid, sum(leave_paid) as leave_paid, sum(ot_hours) as ot_hours';
    cols := (case dgrp when 'person' then '[["person","কর্মী","Person","text"]]' when 'location' then '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"]]' else '[]' end)::jsonb
      || '[["source","উৎস","Source","text"],["sheets","শিট (কাগজ ০২-১)","Sheets (paper 02-1)","int"],["records","রেকর্ড (অ্যাপ)","Records (app)","int"],["present","উপস্থিত","Present","num"],["late","দেরি","Late","num"],["absent","অনুপস্থিত","Absent","num"],["leave_unpaid","বিনা বেতনের ছুটি","Unpaid leave","num"],["leave_paid","সবেতন ছুটি","Paid leave","num"],["ot_hours","ওভারটাইম ঘণ্টা","Overtime hours","num"]]'::jsonb;
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'info', 'text_en', 'Two sources in separate rows: attendance records of the app, and the monthly paper registers (02-1) dated inside the period. Do not add the two for the same person.', 'text_bn', 'দুটি উৎস আলাদা সারিতে: অ্যাপের হাজিরা রেকর্ড এবং সময়ের মধ্যে তারিখের মাসিক কাগজের রেজিস্টার (০২-১)। একই ব্যক্তির দুটি যোগ করবেন না।'));

  $n$);

-- ---------- 5. notices ----------
create or replace function public._c1_n_att_sources(p_key text, d1 date, d2 date, eff int[], flt jsonb, cols text[]) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare na int; np int; app_on boolean := coalesce(public.rule_on('attendance_on'), true); out_ jsonb := '[]'::jsonb;
begin
  select count(*) into na from public._c1_att_rows(d1, d2, eff) x where x.src = 'app';
  select count(distinct x.id) into np from public._c1_att_rows(d1, d2, eff) x where x.src = 'paper';
  out_ := out_ || jsonb_build_object('code', 'attendance_sources', 'level', 'info', 'data', jsonb_build_object('app_records', na, 'paper_sheets', np),
    'text_en', 'Attendance comes from two sources, shown in separate rows: ' || na || ' attendance record(s) in the app and ' || np || ' paper register(s) (02-1). A person who is on both appears twice. Look at one source, do not add them.',
    'text_bn', 'হাজিরা দুটি উৎস থেকে, আলাদা সারিতে: অ্যাপে ' || na || 'টি হাজিরা রেকর্ড ও ' || np || 'টি কাগজের রেজিস্টার (০২-১)। দুটিতেই থাকলে একই ব্যক্তি দুইবার আসে। একটি উৎস দেখুন, যোগ করবেন না।');
  if na = 0 then
    out_ := out_ || case when not app_on
      then jsonb_build_object('code', 'module_off', 'level', 'warn', 'text_en', 'Attendance in the app is not switched on - no data captured. Only the paper registers are shown.',
             'text_bn', 'অ্যাপে হাজিরা চালু নেই - কোনো তথ্য সংগ্রহ হয়নি। শুধু কাগজের রেজিস্টার দেখাচ্ছে।')
      else jsonb_build_object('code', 'no_app_data', 'level', 'warn', 'text_en', 'No attendance record in the app for this period and these places - data not captured in the app. Only the paper registers are shown.',
             'text_bn', 'এই সময়ে ও এই জায়গাগুলোতে অ্যাপে কোনো হাজিরা রেকর্ড নেই - অ্যাপে তথ্য সংগ্রহ হয়নি। শুধু কাগজের রেজিস্টার দেখাচ্ছে।') end;
  end if;
  if np = 0 and na > 0 then
    out_ := out_ || jsonb_build_object('code', 'no_paper_data', 'level', 'info', 'text_en', 'No paper register (02-1) in this period.', 'text_bn', 'এই সময়ে কোনো কাগজের রেজিস্টার (০২-১) নেই।');
  end if;
  return out_;
end $$;

create or replace function public._c1_n_case_status(p_key text, d1 date, d2 date, eff int[], flt jsonb, cols text[]) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare strict_on boolean := public._c1_case_strict(); n_open int; na int; nr int; nv int; en text; bn text;
begin
  select count(*) filter (where c.status = 'open'), count(*) filter (where c.status = 'approved'), count(*) filter (where c.status = 'rejected'), count(*) filter (where c.status = 'void')
    into n_open, na, nr, nv from public.shortage_cash_cases c where c.case_date between d1 and d2 and c.location_id = any (eff);
  en := 'Short and over come from the flag of each daily sheet (14-1). ' || case when strict_on then 'Setting ON: sheets whose shortage case was rejected or voided are left out.'
        else 'Setting OFF: every flagged sheet counts, even if the owner rejected its shortage case.' end
        || ' Shortage cases in this period: ' || n_open || ' open, ' || na || ' approved, ' || nr || ' rejected, ' || nv || ' void.';
  bn := 'কম/বেশি প্রতিটি দৈনিক শিটের (১৪-১) চিহ্ন থেকে। ' || case when strict_on then 'সেটিং চালু: যে শিটের কেস বাতিল (rejected) বা ভয়েড তা বাদ।'
        else 'সেটিং বন্ধ: মালিক কেস বাতিল করলেও চিহ্নিত প্রতিটি শিট ধরা হয়।' end
        || ' এই সময়ের কেস: ' || n_open || 'টি খোলা, ' || na || 'টি অনুমোদিত, ' || nr || 'টি বাতিল, ' || nv || 'টি ভয়েড।';
  return jsonb_build_array(jsonb_build_object('code', 'cash_short_basis', 'level', case when nr + nv > 0 and not strict_on then 'warn' else 'info' end,
    'data', jsonb_build_object('open', n_open, 'approved', na, 'rejected', nr, 'void', nv, 'strict', strict_on), 'text_en', en, 'text_bn', bn,
    'link', jsonb_build_object('route', 'shortages', 'label_en', 'Shortages', 'label_bn', 'কম / বেশি')));
end $$;

create or replace function public._c1_n_rfm_cutoffs(p_key text, d1 date, d2 date, eff int[], flt jsonb, cols text[]) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare b text[] := '{}'; bb text[] := '{}'; en text; bn text;
begin
  if public.rule_num('report_rfm_min_orders') is null then b := b || 'at least 3 orders'::text; bb := bb || 'কমপক্ষে ৩টি অর্ডার'::text; end if;
  if public.rule_num('report_rfm_recent_days') is null then b := b || 'last purchase within 30 days'::text; bb := bb || 'শেষ কেনা ৩০ দিনের মধ্যে'::text; end if;
  if public.rule_num('report_rfm_atrisk_days') is null then b := b || 'no purchase for more than 60 days'::text; bb := bb || '৬০ দিনের বেশি কেনেননি'::text; end if;
  en := 'Champion = at least ' || public._c1_rfm('min_orders')::int || ' orders and a purchase within ' || public._c1_rfm('recent_days')::int || ' days; At-risk = 2 or more orders and no purchase for more than '
        || public._c1_rfm('atrisk_days')::int || ' days; One-time = 1 order; the rest are Regular.';
  bn := 'Champion = কমপক্ষে ' || public._c1_rfm('min_orders')::int || 'টি অর্ডার ও ' || public._c1_rfm('recent_days')::int || ' দিনের মধ্যে কেনা; At-risk = ২ বা বেশি অর্ডার ও ' || public._c1_rfm('atrisk_days')::int
        || ' দিনের বেশি কেনেননি; One-time = ১টি অর্ডার; বাকিরা Regular।';
  if cardinality(b) > 0 then
    en := en || ' NOT SET BY THE OWNER (built-in numbers): ' || array_to_string(b, '; ') || '. Set them in the settings of the reports.';
    bn := bn || ' মালিকের দেওয়া নয় (কোডে ধরা সংখ্যা): ' || array_to_string(bb, '; ') || '। রিপোর্টের সেটিংয়ে দিন।';
  end if;
  return jsonb_build_array(jsonb_build_object('code', 'rfm_cutoffs', 'level', case when cardinality(b) > 0 then 'warn' else 'info' end, 'data', jsonb_build_object('built_in', to_jsonb(b)), 'text_en', en, 'text_bn', bn));
end $$;

create or replace function public._c1_n_lapse_days(p_key text, d1 date, d2 date, eff int[], flt jsonb, cols text[]) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare setv boolean := public.rule_num('report_lapsed_days') is not null; n int := public._c1_lapsed_days()::int;
begin
  return jsonb_build_array(jsonb_build_object('code', 'lapse_days', 'level', case when setv then 'info' else 'warn' end, 'data', jsonb_build_object('days', n, 'set_by_owner', setv),
    'text_en', 'Lapsed = bought within ' || n || ' days before the period but not in it. ' || case when setv then 'The number is set by the owner.' else 'NOT SET BY THE OWNER: ' || n || ' is the built-in number. Set it in the settings of the reports.' end,
    'text_bn', 'Lapsed = এই সময়ের আগের ' || n || ' দিনের মধ্যে কিনেছেন কিন্তু এই সময়ে কেনেননি। ' || case when setv then 'সংখ্যাটি মালিকের দেওয়া।' else 'মালিকের দেওয়া নয়: ' || n || ' কোডে ধরা সংখ্যা। রিপোর্টের সেটিংয়ে দিন।' end));
end $$;

create or replace function public._c1_n_compliance_basis(p_key text, d1 date, d2 date, eff int[], flt jsonb, cols text[]) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare f date := public._c1_compliance_from(); raw text := public.rule_txt('report_compliance_from'); nh int; en text; bn text; lv text := 'info';
begin
  if f is null then
    lv := 'warn';
    en := case when raw is not null then 'The rollout start date in the settings is not a valid date (YYYY-MM-DD), so it is ignored. ' else 'No rollout start date is set. ' end
          || 'Every calendar day of the period counts as a day a form is required, and closed days are not left out, so the missing days are overstated (most of all on a new install). Set "Forms are required from this date" in the settings of the reports.';
    bn := case when raw is not null then 'সেটিংয়ে রোলআউট শুরুর তারিখ সঠিক নয় (YYYY-MM-DD), তাই ধরা হয়নি। ' else 'রোলআউট শুরুর তারিখ দেওয়া নেই। ' end
          || 'পিরিয়ডের প্রতিটি দিন ফর্ম জমার দিন ধরা হচ্ছে, বন্ধের দিন বাদ যাচ্ছে না, তাই বাদ-পড়া দিন বেশি দেখাচ্ছে (নতুন ইনস্টলে সবচেয়ে বেশি)। রিপোর্টের সেটিংয়ে "ফর্ম জমা বাধ্যতামূলক এই তারিখ থেকে" দিন।';
  else
    select count(distinct h.day) into nh from public.holidays h where h.active and h.day between greatest(d1, f) and d2 and (h.location_id is null or h.location_id = any (eff));
    en := 'Days count from ' || to_char(f, 'YYYY-MM-DD') || '. Closed days are left out (holidays list: ' || nh || ' day(s) in this period' || case when public.rule_txt('report_compliance_closed_days') is not null then ', plus the weekly closed days ' || public.rule_txt('report_compliance_closed_days') else '' end
          || '). Only forms 14-1 and 10-1 are checked.' || case when f > d2 then ' The start date is after this period, so no day is required yet.' else '' end;
    bn := 'দিন গণনা ' || to_char(f, 'YYYY-MM-DD') || ' থেকে। বন্ধের দিন বাদ (ছুটির তালিকা: এই সময়ে ' || nh || ' দিন' || case when public.rule_txt('report_compliance_closed_days') is not null then ', সাথে সাপ্তাহিক বন্ধ ' || public.rule_txt('report_compliance_closed_days') else '' end
          || ')। শুধু ১৪-১ ও ১০-১ ফর্ম দেখা হয়।' || case when f > d2 then ' শুরুর তারিখ এই সময়ের পরে, তাই এখনও কোনো দিন বাধ্যতামূলক নয়।' else '' end;
  end if;
  return jsonb_build_array(jsonb_build_object('code', 'compliance_basis', 'level', lv, 'data', jsonb_build_object('start_date', f, 'holiday_days', nh), 'text_en', en, 'text_bn', bn));
end $$;

revoke all on function public._c1_n_att_sources(text, date, date, integer[], jsonb, text[]), public._c1_n_case_status(text, date, date, integer[], jsonb, text[]),
  public._c1_n_rfm_cutoffs(text, date, date, integer[], jsonb, text[]), public._c1_n_lapse_days(text, date, date, integer[], jsonb, text[]),
  public._c1_n_compliance_basis(text, date, date, integer[], jsonb, text[]) from public, anon, authenticated;

insert into public.report_notice_topics (report_key, topic, sort) values
 ('attendance_summary', 'att_sources', 10), ('cash_short_over', 'case_status', 10), ('m1_rfm', 'rfm_cutoffs', 10), ('d5_lapsed', 'lapse_days', 10), ('x4_compliance', 'compliance_basis', 10)
on conflict do nothing;
notify pgrst, 'reload schema';
