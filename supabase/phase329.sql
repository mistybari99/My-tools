-- Phase 329 (bos329, package CRM-H, part 2 of 2: label 129) - RATINGS, REPEAT-COMPLAINT LIST, COMPLAINTS AND RATINGS REPORT.
-- Paste AFTER phase328 (it reads the complaint tables and helpers of that file). Paste-twice safe. No earlier file is edited, no shared function is re-created.
-- If phase328 is pasted again later, paste this file again too (it only adds; nothing in it is replaced by phase328).
--
-- WHAT THIS FILE ADDS
--   1. Settings: crm_feedback_on (OFF), crm_feedback_low_max (blank), crm_feedback_window_days (blank).
--   2. crm_feedback: one star rating (1..5) with a comment, linked to ONE sale or online order. One rating per sale and per order.
--   3. API (all _crmh_*): _crmh_feedback_add, _crmh_feedback_followup, _crmh_feedback_to_complaint, _crmh_feedback_list, _crmh_feedback_settings,
--      _crmh_repeat_list, _crmh_report
-- ACCOUNTING: a rating posts nothing and changes no sale. Turning a low rating into a complaint creates a complaint only, never a refund.
-- DEFAULTS: with crm_feedback_on OFF the write functions answer 'feedback_off'. The report and lists are read only and work for people who hold the right.

do $g$ begin
  if to_regprocedure('public._crmh_present()') is null or to_regclass('public.crm_complaints') is null or to_regprocedure('public._crmh_complaint_save(uuid,jsonb)') is null then
    raise exception 'phase329 needs phase328 first';
  end if;
end $g$;

-- ============================================================================
-- 1. SETTINGS
-- ============================================================================
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'crm', v.kind, v.dv, v.unit, v.ch, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('crm_feedback_on', 'switch', 'false'::jsonb, null::text, null::jsonb, null::numeric, null::numeric,
  'Record customer ratings (1 to 5 stars) for a sale or order',
  'OFF = nothing changes (today). ON = staff can record a star rating and a short comment for a sale or an online order. One rating per sale. A rating posts no money.', 1295),
 ('crm_feedback_low_max', 'number', null, 'stars', null, 1, 4,
  'A rating at or below this many stars needs a follow-up call',
  'Blank = no rating needs a call (today). For example 2 = a 1 or 2 star rating is put on the "needs a call" list until someone records the call.', 1296),
 ('crm_feedback_window_days', 'number', null, 'days', null, 1, 3650,
  'Accept a rating only for a sale made in the last this many days',
  'Blank = any age. A number refuses a rating for a sale or order older than that.', 1297)
 ) v(key, kind, dv, unit, ch, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- ============================================================================
-- 2. TABLE
-- ============================================================================
create table if not exists public.crm_feedback (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  location_id int not null references public.locations(id),
  customer_id uuid references public.customers(id),
  sale_id uuid references public.sales(id),
  order_id uuid references public.online_orders(id),
  rating smallint not null check (rating between 1 and 5),
  comment text check (comment is null or char_length(comment) <= 500),
  channel text not null default 'counter' check (channel in ('counter', 'phone', 'message', 'other')),
  follow_up text not null default 'none' check (follow_up in ('none', 'needed', 'done')),
  follow_up_note text check (follow_up_note is null or char_length(follow_up_note) <= 500), follow_up_by uuid, follow_up_at timestamptz,
  complaint_id uuid references public.crm_complaints(id),
  collected_by uuid not null, collected_staff text, at timestamptz not null default now(),
  check (sale_id is not null or order_id is not null)
);
create unique index if not exists crm_feedback_one_per_sale on public.crm_feedback (sale_id) where sale_id is not null;
create unique index if not exists crm_feedback_one_per_order on public.crm_feedback (order_id) where order_id is not null;
create index if not exists crm_feedback_loc_at on public.crm_feedback (location_id, at desc);
create index if not exists crm_feedback_followup on public.crm_feedback (location_id) where follow_up = 'needed';

drop trigger if exists crm_feedback_nodel on public.crm_feedback;
create trigger crm_feedback_nodel before delete on public.crm_feedback for each row execute function public.no_hard_delete();
alter table public.crm_feedback enable row level security;
revoke all on public.crm_feedback from public, anon, authenticated;
drop trigger if exists audit_crm_feedback on public.crm_feedback;
create trigger audit_crm_feedback after insert or update on public.crm_feedback for each row execute function public.log_change('id');

-- a rating is a record: only the follow-up fields and the complaint link may change, and a follow-up never goes back
create or replace function public._crmh_feedback_guard() returns trigger language plpgsql as $$
begin
  if new.id is distinct from old.id or new.client_id is distinct from old.client_id or new.location_id is distinct from old.location_id or new.customer_id is distinct from old.customer_id
     or new.sale_id is distinct from old.sale_id or new.order_id is distinct from old.order_id or new.rating is distinct from old.rating or new.comment is distinct from old.comment
     or new.channel is distinct from old.channel or new.collected_by is distinct from old.collected_by or new.at is distinct from old.at then
    raise exception 'feedback_immutable';
  end if;
  if old.follow_up = 'done' and new.follow_up is distinct from 'done' then raise exception 'illegal_status_change'; end if;
  if old.follow_up = 'none' and new.follow_up is distinct from 'none' then raise exception 'illegal_status_change'; end if;
  if old.follow_up = 'needed' and new.follow_up = 'none' then raise exception 'illegal_status_change'; end if;
  if old.complaint_id is not null and new.complaint_id is distinct from old.complaint_id then raise exception 'feedback_immutable'; end if;
  return new;
end $$;
drop trigger if exists crm_feedback_guard on public.crm_feedback;
create trigger crm_feedback_guard before update on public.crm_feedback for each row execute function public._crmh_feedback_guard();

-- ============================================================================
-- 3. API
-- ============================================================================
-- 3.1 record a rating. p keys: sale_id and/or order_id, rating (1..5), comment, channel (counter | phone | message | other), customer_id
create or replace function public._crmh_feedback_add(p_client uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare uid uuid := auth.uid(); f public.crm_feedback; s public.sales; o public.online_orders; sale_ uuid; ord_ uuid; cust_ uuid; loc int; rt int; cm text; ch text; low numeric; win numeric; fu text := 'none'; t_when timestamptz;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_input'; end if;
  if not public.rule_on('crm_feedback_on') then raise exception 'feedback_off'; end if;
  if p_client is not null then
    select * into f from public.crm_feedback where client_id = p_client;
    if found then
      if f.collected_by is distinct from uid and not public._crmh_manage_ok(f.location_id) then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', f.id, 'follow_up', f.follow_up);
    end if;
  end if;
  sale_ := public._crmh_j_uuid(p, 'sale_id'); ord_ := public._crmh_j_uuid(p, 'order_id'); cust_ := public._crmh_j_uuid(p, 'customer_id');
  if coalesce(p ->> 'rating', '') !~ '^[1-5]$' then raise exception 'bad_rating'; end if;
  rt := (p ->> 'rating')::int;
  cm := nullif(btrim(coalesce(p ->> 'comment', '')), ''); if cm is not null and char_length(cm) > 500 then raise exception 'bad_comment'; end if;
  ch := coalesce(nullif(btrim(p ->> 'channel'), ''), 'counter'); if ch not in ('counter', 'phone', 'message', 'other') then raise exception 'bad_channel'; end if;
  if sale_ is null and ord_ is null then raise exception 'sale_or_order_required'; end if;
  if ord_ is not null then
    select * into o from public.online_orders where id = ord_;
    if not found then raise exception 'order_not_found'; end if;
    if o.status = 'cancelled' then raise exception 'order_cancelled'; end if;
    if sale_ is not null and o.sale_id is not null and o.sale_id <> sale_ then raise exception 'order_sale_mismatch'; end if;
    if sale_ is null then sale_ := o.sale_id; end if;
    loc := o.location_id; t_when := o.created_at;
  end if;
  if sale_ is not null then
    select * into s from public.sales where id = sale_;
    if not found then raise exception 'sale_not_found'; end if;
    if loc is not null and loc <> s.location_id then raise exception 'sale_other_outlet'; end if;
    if s.status <> 'done' then raise exception 'sale_void'; end if;
    loc := s.location_id; t_when := s.sold_at; if cust_ is null then cust_ := s.customer_id; end if;
  end if;
  if not public._crmh_log_ok(loc) then raise exception 'not allowed'; end if;
  if cust_ is not null and not exists (select 1 from public.customers where id = cust_) then raise exception 'customer_not_found'; end if;
  win := public.rule_num('crm_feedback_window_days');
  if win is not null and t_when < now() - win * interval '1 day' then raise exception 'too_old'; end if;
  if (sale_ is not null and exists (select 1 from public.crm_feedback where sale_id = sale_)) or (ord_ is not null and exists (select 1 from public.crm_feedback where order_id = ord_)) then raise exception 'already_rated'; end if;
  low := public.rule_num('crm_feedback_low_max');
  if low is not null and rt <= low then fu := 'needed'; end if;
  insert into public.crm_feedback (client_id, location_id, customer_id, sale_id, order_id, rating, comment, channel, follow_up, collected_by, collected_staff)
    values (p_client, loc, cust_, sale_, ord_, rt, cm, ch, fu, uid, public._crmh_staff()) returning * into f;
  perform public._crmh_audit('crmh_rating_new', f.id::text, jsonb_build_object('rating', rt, 'follow_up', fu));
  return jsonb_build_object('dup', false, 'id', f.id, 'rating', rt, 'follow_up', fu);
end $function$;

-- 3.2 record that the follow-up call was made (only when one was needed)
create or replace function public._crmh_feedback_followup(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare f public.crm_feedback; b text := btrim(coalesce(p_note, ''));
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into f from public.crm_feedback where id = p_id for update;
  if not found then raise exception 'feedback_not_found'; end if;
  if not public._crmh_manage_ok(f.location_id) then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_feedback_on') then raise exception 'feedback_off'; end if;
  if f.follow_up = 'done' then return jsonb_build_object('dup', true, 'id', f.id, 'follow_up', 'done'); end if;
  if f.follow_up <> 'needed' then raise exception 'no_follow_up_needed'; end if;
  if char_length(b) < 3 or char_length(b) > 500 then raise exception 'note_required'; end if;
  update public.crm_feedback set follow_up = 'done', follow_up_note = b, follow_up_by = auth.uid(), follow_up_at = now() where id = p_id returning * into f;
  perform public._crmh_audit('crmh_rating_followup', f.id::text, jsonb_build_object('note', b));
  return jsonb_build_object('dup', false, 'id', f.id, 'follow_up', f.follow_up);
end $function$;

-- 3.3 open a complaint from a rating (the rating's sale / order and customer carry over). p keys: category, severity, description, item_id, food_safety. A complaint only: no refund.
create or replace function public._crmh_feedback_to_complaint(p_id uuid, p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare f public.crm_feedback; res jsonb; p2 jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into f from public.crm_feedback where id = p_id for update;
  if not found then raise exception 'feedback_not_found'; end if;
  if not public._crmh_manage_ok(f.location_id) then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_feedback_on') then raise exception 'feedback_off'; end if;
  if f.complaint_id is not null then return jsonb_build_object('dup', true, 'complaint_id', f.complaint_id); end if;
  p2 := coalesce(p, '{}'::jsonb) || jsonb_build_object('location_id', f.location_id, 'sale_id', f.sale_id, 'order_id', f.order_id, 'customer_id', f.customer_id);
  p2 := (select jsonb_object_agg(k, v) from jsonb_each(p2) e(k, v) where v <> 'null'::jsonb);
  if nullif(btrim(coalesce(p2 ->> 'description', '')), '') is null then p2 := p2 || jsonb_build_object('description', coalesce(f.comment, 'Rated ' || f.rating || ' of 5 stars')); end if;
  res := public._crmh_complaint_save(f.id, p2);                         -- the rating's own id is the client id: a second press returns the same complaint
  update public.crm_feedback set complaint_id = (res ->> 'id')::uuid,
         follow_up = case when follow_up = 'needed' then 'done' else follow_up end,
         follow_up_note = case when follow_up = 'needed' then 'Complaint opened' else follow_up_note end,
         follow_up_by = case when follow_up = 'needed' then auth.uid() else follow_up_by end,
         follow_up_at = case when follow_up = 'needed' then now() else follow_up_at end
   where id = p_id;
  return res || jsonb_build_object('complaint_id', res ->> 'id');
end $function$;

-- 3.4 the rating list with a small summary. p keys: location_id, rating_max, follow_up (none | needed | done), from, to, limit, offset
create or replace function public._crmh_feedback_list(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $function$
declare uid uuid := auth.uid(); loc int := nullif(p ->> 'location_id', '')::int; rmax int := nullif(p ->> 'rating_max', '')::int; fu text := nullif(p ->> 'follow_up', '');
        d1 date := nullif(p ->> 'from', '')::date; d2 date := nullif(p ->> 'to', '')::date; lim int := least(greatest(coalesce(nullif(p ->> 'limit', '')::int, 30), 1), 100); off_ int := greatest(coalesce(nullif(p ->> 'offset', '')::int, 0), 0);
        rows jsonb; sm record;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if fu is not null and fu not in ('none', 'needed', 'done') then raise exception 'bad_status'; end if;
  with f as (
    select x.* from public.crm_feedback x
     where (public._crmh_view_ok(x.location_id) or x.collected_by = uid)
       and (loc is null or x.location_id = loc) and (rmax is null or x.rating <= rmax) and (fu is null or x.follow_up = fu)
       and (d1 is null or (x.at at time zone 'Asia/Dhaka')::date >= d1) and (d2 is null or (x.at at time zone 'Asia/Dhaka')::date <= d2))
  select count(*) as n, round(avg(rating), 2) as avg_r, count(*) filter (where follow_up = 'needed') as need_n into sm from f;
  select coalesce(jsonb_agg(jsonb_build_object('id', z.id, 'at', z.at, 'location_id', z.location_id, 'location', (select coalesce(l.name_en, l.name_bn) from public.locations l where l.id = z.location_id),
         'rating', z.rating, 'comment', z.comment, 'channel', z.channel, 'sale_id', z.sale_id, 'receipt', (select s.receipt from public.sales s where s.id = z.sale_id),
         'order_id', z.order_id, 'order_no', (select o.order_no from public.online_orders o where o.id = z.order_id),
         'customer_id', z.customer_id, 'customer_name', (select c.name from public.customers c where c.id = z.customer_id),
         'follow_up', z.follow_up, 'follow_up_note', z.follow_up_note, 'complaint_id', z.complaint_id, 'by', z.collected_staff) order by z.at desc), '[]'::jsonb) into rows
    from (select x.* from public.crm_feedback x
           where (public._crmh_view_ok(x.location_id) or x.collected_by = uid)
             and (loc is null or x.location_id = loc) and (rmax is null or x.rating <= rmax) and (fu is null or x.follow_up = fu)
             and (d1 is null or (x.at at time zone 'Asia/Dhaka')::date >= d1) and (d2 is null or (x.at at time zone 'Asia/Dhaka')::date <= d2)
           order by x.at desc limit lim offset off_) z;
  return jsonb_build_object('total', sm.n, 'average', sm.avg_r, 'needs_call', sm.need_n, 'rows', rows, 'limit', lim, 'offset', off_, 'on', public.rule_on('crm_feedback_on'));
end $function$;

create or replace function public._crmh_feedback_settings() returns jsonb
language plpgsql stable security definer set search_path = public as $function$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('crm_feedback_on'), 'low_max', public.rule_num('crm_feedback_low_max'), 'window_days', public.rule_num('crm_feedback_window_days'),
    'may_log', exists (select 1 from public.locations l where l.is_active and public._crmh_log_ok(l.id)),
    'may_manage', exists (select 1 from public.locations l where l.is_active and public._crmh_manage_ok(l.id)));
end $function$;

-- 3.5 repeat complaints: the same customer (and, by scope, the same item) with several complaints inside the window. p keys: days, min, scope, location_id
--     Uses the settings when a key is not given. With no days anywhere it answers 'days_required' (the check is off by default).
create or replace function public._crmh_repeat_list(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $function$
declare uid uuid := auth.uid(); days int := coalesce(nullif(p ->> 'days', '')::int, public.rule_num('crm_repeat_days')::int); mn int := coalesce(nullif(p ->> 'min', '')::int, public.rule_num('crm_repeat_min')::int, 2);
        sc text := coalesce(nullif(p ->> 'scope', ''), public.rule_txt('crm_repeat_scope'), 'customer_item'); loc int := nullif(p ->> 'location_id', '')::int; rows jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if days is null or days < 1 or days > 3650 then raise exception 'days_required'; end if;
  if sc not in ('customer_item', 'customer') then raise exception 'bad_scope'; end if;
  if mn < 2 then raise exception 'bad_min'; end if;
  with c as (
    select x.*, coalesce(x.customer_id::text, 'p:' || nullif(public.norm_mobile(x.customer_phone), '')) as ck
      from public.crm_complaints x
     where x.created_at >= now() - make_interval(days => days) and coalesce(x.close_reason, '') <> 'duplicate'
       and (public._crmh_view_ok(x.location_id) or x.created_by = uid) and (loc is null or x.location_id = loc)),
  g as (
    select ck, case when sc = 'customer_item' then item_id end as gi, count(*) as n, min(created_at) as first_at, max(created_at) as last_at,
           count(*) filter (where status in ('open', 'in_progress')) as open_n, count(distinct location_id) as outlets,
           (array_agg(ticket_no order by created_at desc))[1:10] as tickets, (array_agg(customer_name order by created_at desc))[1] as nm, (array_agg(customer_id order by created_at desc))[1] as cid
      from c where ck is not null and (sc = 'customer' or item_id is not null) group by ck, case when sc = 'customer_item' then item_id end having count(*) >= mn)
  select coalesce(jsonb_agg(jsonb_build_object('customer_id', g.cid, 'customer_name', g.nm, 'item_id', g.gi, 'item_name', (select coalesce(i.name_en, i.name_bn) from public.items i where i.id = g.gi),
         'complaints', g.n, 'open', g.open_n, 'outlets', g.outlets, 'first_at', g.first_at, 'last_at', g.last_at, 'tickets', to_jsonb(g.tickets)) order by g.n desc, g.last_at desc), '[]'::jsonb) into rows from g;
  return jsonb_build_object('days', days, 'min', mn, 'scope', sc, 'rows', rows);
end $function$;

-- 3.6 the report. p keys: from, to (default: the last 30 days), by (outlet | item | category | severity | month | day; default outlet), location_id.
--     complaints: counts by status, overdue now, SLA met or missed, food safety, repeats, average hours to resolve, value of the linked sale returns.
--     ratings: count, average and 1..5 star counts, calls still needed. By item, a rating counts for every item on its sale or order. Only outlets the caller may view.
create or replace function public._crmh_report(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $function$
declare uid uuid := auth.uid(); d2 date := coalesce(nullif(p ->> 'to', '')::date, (now() at time zone 'Asia/Dhaka')::date); d1 date := coalesce(nullif(p ->> 'from', '')::date, (now() at time zone 'Asia/Dhaka')::date - 29);
        by_ text := coalesce(nullif(p ->> 'by', ''), 'outlet'); loc int := nullif(p ->> 'location_id', '')::int; cr jsonb; rr jsonb; tot jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if by_ not in ('outlet', 'item', 'category', 'severity', 'month', 'day') then raise exception 'bad_group'; end if;
  if d1 > d2 then raise exception 'bad_range'; end if;
  if d2 - d1 > 366 then raise exception 'range_too_long'; end if;
  if not exists (select 1 from public.locations l where public._crmh_view_ok(l.id)) then raise exception 'not allowed'; end if;

  with c as (
    select x.*, (x.created_at at time zone 'Asia/Dhaka')::date as dd,
           coalesce((select sum(r.amount) from public.crm_complaint_returns lr join public.sale_returns r on r.id = lr.return_id and r.status = 'done' where lr.complaint_id = x.id), 0) as refund
      from public.crm_complaints x
     where public._crmh_view_ok(x.location_id) and (loc is null or x.location_id = loc) and (x.created_at at time zone 'Asia/Dhaka')::date between d1 and d2),
  k as (
    select c.*, case by_ when 'outlet' then c.location_id::text when 'item' then coalesce(c.item_id::text, 'none') when 'category' then c.category when 'severity' then c.severity
                         when 'month' then to_char(c.dd, 'YYYY-MM') else to_char(c.dd, 'YYYY-MM-DD') end as gk from c),
  g as (
    select gk, count(*) as total,
           count(*) filter (where status in ('open', 'in_progress')) as open_n, count(*) filter (where status in ('resolved', 'closed')) as resolved_n,
           count(*) filter (where status = 'closed_no_resolution') as closed_no_result_n,
           count(*) filter (where status in ('open', 'in_progress') and due_at is not null and now() > due_at) as overdue_now,
           count(*) filter (where breached_at is not null) as breached_n, count(*) filter (where sla_met is true) as sla_met_n, count(*) filter (where sla_met is false) as sla_missed_n,
           count(*) filter (where food_safety) as food_safety_n, count(*) filter (where repeat_flag) as repeat_n,
           round((avg(extract(epoch from (resolved_at - created_at))) filter (where resolved_at is not null) / 3600)::numeric, 1) as avg_resolve_hours,
           round(sum(refund), 2) as refund_total
      from k group by gk)
  select coalesce(jsonb_agg(jsonb_build_object('key', g.gk,
           'label', case by_ when 'outlet' then (select coalesce(l.name_en, l.name_bn) from public.locations l where l.id = g.gk::int)
                             when 'item' then coalesce((select coalesce(i.name_en, i.name_bn) from public.items i where i.id::text = g.gk), 'No item named')
                             when 'category' then coalesce((select o.label_en from public.option_lists o where o.list_code = 'crm_complaint_cats' and o.value_code = g.gk), g.gk) else g.gk end,
           'total', g.total, 'open', g.open_n, 'resolved', g.resolved_n, 'closed_no_result', g.closed_no_result_n, 'overdue_now', g.overdue_now, 'breached', g.breached_n,
           'sla_met', g.sla_met_n, 'sla_missed', g.sla_missed_n, 'food_safety', g.food_safety_n, 'repeat', g.repeat_n, 'avg_resolve_hours', g.avg_resolve_hours, 'refund_total', g.refund_total)
           order by g.total desc, g.gk), '[]'::jsonb) into cr from g;

  if by_ in ('category', 'severity') then
    rr := '[]'::jsonb;
  else
    with fb as (
      select x.*, (x.at at time zone 'Asia/Dhaka')::date as dd from public.crm_feedback x
       where public._crmh_view_ok(x.location_id) and (loc is null or x.location_id = loc) and (x.at at time zone 'Asia/Dhaka')::date between d1 and d2),
    fk as (
      select fb.id, fb.rating, fb.follow_up, case by_ when 'outlet' then fb.location_id::text when 'month' then to_char(fb.dd, 'YYYY-MM') when 'day' then to_char(fb.dd, 'YYYY-MM-DD') else it.item end as gk
        from fb
        left join lateral (
          select distinct e ->> 'item_id' as item
            from jsonb_array_elements(case when jsonb_typeof(coalesce((select s.lines from public.sales s where s.id = fb.sale_id), (select o.lines from public.online_orders o where o.id = fb.order_id))) = 'array'
                                           then coalesce((select s.lines from public.sales s where s.id = fb.sale_id), (select o.lines from public.online_orders o where o.id = fb.order_id)) else '[]'::jsonb end) e
           where by_ = 'item' and (e ->> 'item_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') it on by_ = 'item'),
    rg as (
      select gk, count(*) as n, round(avg(rating), 2) as avg_r, count(*) filter (where rating = 1) as r1, count(*) filter (where rating = 2) as r2, count(*) filter (where rating = 3) as r3,
             count(*) filter (where rating = 4) as r4, count(*) filter (where rating = 5) as r5, count(*) filter (where follow_up = 'needed') as need_n
        from fk where gk is not null group by gk)
    select coalesce(jsonb_agg(jsonb_build_object('key', rg.gk,
             'label', case by_ when 'outlet' then (select coalesce(l.name_en, l.name_bn) from public.locations l where l.id = rg.gk::int)
                               when 'item' then coalesce((select coalesce(i.name_en, i.name_bn) from public.items i where i.id::text = rg.gk), rg.gk) else rg.gk end,
             'n', rg.n, 'average', rg.avg_r, 'stars', jsonb_build_object('1', rg.r1, '2', rg.r2, '3', rg.r3, '4', rg.r4, '5', rg.r5), 'needs_call', rg.need_n) order by rg.n desc, rg.gk), '[]'::jsonb) into rr from rg;
  end if;

  select jsonb_build_object(
    'complaints', (select count(*) from public.crm_complaints x where public._crmh_view_ok(x.location_id) and (loc is null or x.location_id = loc) and (x.created_at at time zone 'Asia/Dhaka')::date between d1 and d2),
    'ratings', (select count(*) from public.crm_feedback x where public._crmh_view_ok(x.location_id) and (loc is null or x.location_id = loc) and (x.at at time zone 'Asia/Dhaka')::date between d1 and d2),
    'average_rating', (select round(avg(x.rating), 2) from public.crm_feedback x where public._crmh_view_ok(x.location_id) and (loc is null or x.location_id = loc) and (x.at at time zone 'Asia/Dhaka')::date between d1 and d2)) into tot;
  return jsonb_build_object('from', d1, 'to', d2, 'by', by_, 'complaints', cr, 'ratings', rr, 'totals', tot,
    'note', case when by_ = 'item' then 'Ratings are counted once for every item on the rated sale or order.' when by_ in ('category', 'severity') then 'Ratings have no category or severity.' else null end);
end $function$;

-- ============================================================================
-- 4. PRIVILEGES
-- ============================================================================
revoke all on function public._crmh_feedback_guard() from public, anon, authenticated;
revoke all on function public._crmh_feedback_add(uuid, jsonb), public._crmh_feedback_followup(uuid, text), public._crmh_feedback_to_complaint(uuid, jsonb), public._crmh_feedback_list(jsonb),
  public._crmh_feedback_settings(), public._crmh_repeat_list(jsonb), public._crmh_report(jsonb) from public, anon, authenticated;
grant execute on function public._crmh_feedback_add(uuid, jsonb), public._crmh_feedback_followup(uuid, text), public._crmh_feedback_to_complaint(uuid, jsonb), public._crmh_feedback_list(jsonb),
  public._crmh_feedback_settings(), public._crmh_repeat_list(jsonb), public._crmh_report(jsonb) to authenticated;
