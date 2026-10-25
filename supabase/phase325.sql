-- Phase 325 (bos325, package CRM-G label 125, part 3 of 5) - CONVERT A WON LEAD TO THE EXISTING ORDER OR PARTY FORM, LEAD LIST, PIPELINE BOARD, WIN / LOSS REPORT.
-- Paste AFTER phase324. Paste-twice safe. Nothing here posts to the books.
--
-- HOW A WON LEAD BECOMES A REAL RECORD (never by copying the accounting of those records):
--   online_order : calls the EXISTING online_order_save2 (phase 76; it calls online_order_save of phase 61). The order is the normal order: stock, advance, delivery,
--                  and the books follow the order's own rules. The quote total becomes the order discount against the list price. No advance is taken here.
--   form_20_1    : calls the EXISTING save_entry to make a DRAFT customer order form (paper form 20-1) filled from the quote. The person completes and submits it as usual.
--   form_20_4    : the same for the party and wholesale invoice (paper form 20-4, "Invoice"). A draft: nothing is posted until the form is approved the usual way.
--   link_order / link_form : link a record that already exists (an order from the Orders screen, a 20-1 or 20-4 entry) instead of making one.
-- One lead converts once. A second conversion is refused (a repeat with the same client key returns the first answer).

do $g$ begin
  if to_regprocedure('public._crmg_lead_stage(uuid,text,text,jsonb)') is null then raise exception 'phase325 needs phase324 first'; end if;
end $g$;

-- ============================================================================
-- 1. CONVERT
--    p_kind: online_order | form_20_1 | form_20_4 | link_order | link_form
--    p_args: quote_id (default: the latest sent or accepted quote), reason (only to win without a quote when that setting is ON),
--            online_order: channel_id (required), delivery_mode (pickup|home|courier, default pickup), delivery_by, delivery_date, address, charge, note
--            link_order: order_id          link_form: entry_id
-- ============================================================================
create or replace function public._crmg_lead_convert(p_lead uuid, p_client uuid, p_kind text, p_args jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := coalesce(p_args, '{}'::jsonb); l public.crm_leads; qq public.crm_lead_quotes; qid uuid; res jsonb := '{}'::jsonb; oid uuid; eid uuid; mob text; lines jsonb := '[]'; rows jsonb := '[]'; e jsonb;
        list_sub numeric := 0; disc numeric; it public.items; ch int; dm text; dd date; addr text; oo public.online_orders; en public.entries; msg bigint; task_days numeric; task_id uuid; cc text;
        form text; dat jsonb; st jsonb; warn text[] := '{}'; n int := 0;
begin
  l := public._crmg_lead_load(p_lead, true);
  if not public._crmg_lead_mgr(l.location_id) then raise exception 'not allowed: only a manager can turn an enquiry into an order'; end if;
  if p_kind not in ('online_order', 'form_20_1', 'form_20_4', 'link_order', 'link_form') then raise exception 'bad_kind'; end if;
  perform public._client_lock(p_client);
  if l.converted_at is not null then
    if p_client is not null and l.convert_client = p_client then
      return jsonb_build_object('id', l.id, 'online_order_id', l.online_order_id, 'entry_id', l.entry_id, 'dup', true);
    end if;
    raise exception 'already_converted: this enquiry already has its order or form';
  end if;
  if l.stage = 'lost' then raise exception 'lead_lost: reopen the enquiry first'; end if;

  -- the quote the record is made from
  qid := nullif(a->>'quote_id', '')::uuid;
  if qid is not null then
    select * into qq from public.crm_lead_quotes where id = qid and lead_id = l.id;
    if not found then raise exception 'not_found: that quote is not on this enquiry'; end if;
  else
    select * into qq from public.crm_lead_quotes where lead_id = l.id and status in ('accepted', 'sent') order by version desc limit 1;
  end if;
  if p_kind in ('online_order', 'form_20_1', 'form_20_4') and qq.id is null then raise exception 'quote_needed: send a quote first - the record is made from its lines'; end if;

  -- the enquiry becomes Won first (the normal stage rules apply, including the setting that asks for a quote)
  if l.stage <> 'won' then
    perform public._crmg_lead_stage(l.id, 'won', 'turned into an order', a);
    select * into l from public.crm_leads where id = l.id;
  end if;

  if p_kind = 'online_order' then
    if nullif(a->>'channel_id', '') is null then raise exception 'channel_required: choose the sales channel of the order'; end if;
    ch := (a->>'channel_id')::int;
    begin mob := public.norm_mobile(l.contact_phone); exception when others then mob := null; end;
    if mob is null then raise exception 'mobile_required: an order needs a valid mobile number on the enquiry'; end if;
    for e in select * from jsonb_array_elements(qq.items) loop
      n := n + 1;
      if nullif(e->>'item_id', '') is null then raise exception 'lines_need_items: line % has no item from the item list - use the party invoice form or link an order', n; end if;
      select * into it from public.items where id = (e->>'item_id')::uuid and is_active;
      if not found or it.sell_price is null then raise exception 'item_not_found: line % has no active item with a list price', n; end if;
      lines := lines || jsonb_build_object('item_id', it.id, 'qty', (e->>'qty')::numeric);
      list_sub := list_sub + round((e->>'qty')::numeric * it.sell_price, 2);
    end loop;
    disc := list_sub - qq.total;
    if disc < 0 then raise exception 'price_above_list: the quote total is above the list price - use the party invoice form or link an order'; end if;
    dm := coalesce(nullif(btrim(a->>'delivery_mode'), ''), 'pickup');
    begin dd := nullif(a->>'delivery_date', '')::date; exception when others then raise exception 'bad_date'; end;
    if dd is null and l.event_date between public._crmg_today() - 1 and public._crmg_today() + 365 then dd := l.event_date; end if;
    addr := nullif(btrim(a->>'address'), '');
    select inbound_message_id into msg from public.crm_leads where id = l.id;
    if msg is not null and not exists (select 1 from public.inbound_messages where id = msg and status in ('new', 'seen')) then msg := null; end if;
    st := public.online_order_save2(null, coalesce(p_client, gen_random_uuid()), l.location_id, ch, l.contact_name, mob, addr, lines, dm, nullif(btrim(a->>'delivery_by'), ''), dd,
            coalesce(nullif(a->>'charge', '')::numeric, 0), round(disc, 2), 0, null, null, coalesce(nullif(btrim(a->>'note'), ''), 'from enquiry ' || l.lead_no),
            null, 'crm_lead ' || l.lead_no, null, null, null, msg, false);
    oid := (st->>'id')::uuid;
    res := res || jsonb_build_object('order_no', st->>'order_no', 'order_status', st->>'status');
    -- optional delivery task for the assigned person (setting crm_order_task_days, tasks must be ON)
    task_days := public.rule_num('crm_order_task_days');
    if task_days is not null and public._crmg_task_on() and dd is not null then
      insert into public.crm_tasks (location_id, customer_id, lead_id, order_id, kind, title, due_at, assigned_to, source, created_by)
        values (l.location_id, l.customer_id, l.id, oid, 'follow_up', left('Delivery of order ' || (st->>'order_no') || ' for ' || l.contact_name, 120),
                ((dd - task_days::int)::text || ' 09:00 Asia/Dhaka')::timestamptz, l.owner_user, 'order', auth.uid()) returning id into task_id;
      insert into public.crm_task_events (task_id, by_user, by_staff, kind, note) values (task_id, auth.uid(), public._crmg_staff(), 'created', 'made when the enquiry became an order');
      res := res || jsonb_build_object('task_id', task_id);
    end if;

  elsif p_kind in ('form_20_1', 'form_20_4') then
    form := case p_kind when 'form_20_1' then '20-1' else '20-4' end;
    if not public.can_do(form, 'enter') then raise exception 'form_not_allowed: you do not hold the right to enter form %', form; end if;
    for e in select * from jsonb_array_elements(qq.items) loop
      if form = '20-4' then
        rows := rows || jsonb_build_object('item', coalesce(e->>'code', ''), 'desc', e->>'desc', 'unit', coalesce(e->>'unit', ''), 'qty', e->>'qty', 'rate', e->>'price');
      else
        rows := rows || jsonb_build_object('item', coalesce(e->>'code', ''), 'desc', e->>'desc', 'qty', e->>'qty');
      end if;
    end loop;
    if form = '20-4' then
      dat := jsonb_build_object('doc', 'invoice', 'party', l.contact_name, 'phone', coalesce(l.contact_phone, ''), 'order_no', 'ENQ-' || l.lead_no, 'lines', rows, 'discount', qq.discount::text);
    else
      dat := jsonb_build_object('order_type', 'custom', 'channel', 'party', 'cust_name', l.contact_name, 'cust_phone', coalesce(l.contact_phone, ''), 'deliv_mode', 'pickup',
        'items', rows, 'total', qq.subtotal::text, 'discount', qq.discount::text);
      if l.event_date is not null then dat := dat || jsonb_build_object('deliv_date', l.event_date::text); end if;
    end if;
    st := public.save_entry(null, form, l.location_id, public._crmg_today(), dat, '[]'::jsonb, 'from enquiry ' || l.lead_no, jsonb_build_object('client_id', coalesce(p_client, gen_random_uuid())));
    eid := (st->>'id')::uuid;
    res := res || jsonb_build_object('form', form, 'serial', st->>'serial', 'draft', true);

  elsif p_kind = 'link_order' then
    begin oid := nullif(a->>'order_id', '')::uuid; exception when others then raise exception 'not_found'; end;
    select * into oo from public.online_orders where id = oid;
    if not found or not public.can_loc(oo.location_id) then raise exception 'not_found'; end if;
    if oo.location_id <> l.location_id then raise exception 'other_outlet: the order belongs to another outlet'; end if;
    if oo.status = 'cancelled' then raise exception 'order_cancelled: a cancelled order cannot be linked'; end if;
    if exists (select 1 from public.crm_leads x where x.online_order_id = oid) then raise exception 'already_linked: this order belongs to another enquiry'; end if;
    begin if public.norm_mobile(l.contact_phone) is distinct from oo.customer_mobile then warn := warn || 'the order has a different mobile number'::text; end if; exception when others then null; end;
    res := res || jsonb_build_object('order_no', oo.order_no, 'order_status', oo.status);

  else   -- link_form
    begin eid := nullif(a->>'entry_id', '')::uuid; exception when others then raise exception 'not_found'; end;
    select * into en from public.entries where id = eid;
    if not found or en.form_code not in ('20-1', '20-4') or not public.can_loc(en.location_id) or not public.can_do(en.form_code, 'view') then raise exception 'not_found'; end if;
    if en.location_id <> l.location_id then raise exception 'other_outlet: the form belongs to another outlet'; end if;
    if exists (select 1 from public.crm_leads x where x.entry_id = eid) then raise exception 'already_linked: this form belongs to another enquiry'; end if;
    res := res || jsonb_build_object('form', en.form_code, 'serial', en.serial, 'form_status', en.status);
  end if;

  begin
    update public.crm_leads set online_order_id = oid, entry_id = eid, converted_at = now(), converted_by = auth.uid(), convert_client = p_client where id = l.id;
  exception when unique_violation then raise exception 'already_linked: this record belongs to another enquiry'; end;
  perform public._crmg_ev(l.id, 'convert', 'won', 'won', null, jsonb_build_object('kind', p_kind, 'order_id', oid, 'entry_id', eid, 'quote_id', qq.id));
  perform public._crmg_audit('convert', 'crm_leads', l.id::text, jsonb_build_object('kind', p_kind, 'order_id', oid, 'entry_id', eid));
  return jsonb_build_object('id', l.id, 'kind', p_kind, 'online_order_id', oid, 'entry_id', eid, 'warnings', to_jsonb(warn)) || res;
end $$;

-- ============================================================================
-- 2. LEAD LIST   p_filter: stage (text or array), loc, owner ('me' or a user id), q (name, phone or number), overdue, stale, converted, from, to (created date), limit (max 300), offset
-- ============================================================================
create or replace function public._crmg_lead_rows(p_filter jsonb) returns table (r jsonb, stage text, loc int)
language plpgsql stable security definer set search_path = public as $$
declare f jsonb := coalesce(p_filter, '{}'::jsonb); stages text[]; own uuid; qtxt text := lower(btrim(coalesce(f->>'q', ''))); stale numeric := public.rule_num('crm_lead_stale_days');
begin
  if jsonb_typeof(f->'stage') = 'array' then select array_agg(x) into stages from jsonb_array_elements_text(f->'stage') x;
  elsif nullif(f->>'stage', '') is not null then stages := array[f->>'stage']; end if;
  own := case when f->>'owner' = 'me' then auth.uid() when nullif(f->>'owner', '') is not null then (f->>'owner')::uuid end;
  return query
    select jsonb_build_object('id', l.id, 'lead_no', l.lead_no, 'location_id', l.location_id, 'contact_name', l.contact_name, 'contact_phone', public._crmg_phone(l.contact_phone, l.owner_user),
        'stage', l.stage, 'source', l.source, 'occasion', l.occasion, 'event_date', l.event_date, 'guests', l.guests, 'est_value', l.est_value, 'owner_user', l.owner_user,
        'owner_staff', (select pr.staff_id from public.profiles pr where pr.id = l.owner_user), 'next_follow_up', l.next_follow_up,
        'overdue', l.stage not in ('won', 'lost') and l.next_follow_up is not null and l.next_follow_up < now(),
        'stale', l.stage not in ('won', 'lost') and stale is not null and l.last_activity_at < now() - (stale || ' days')::interval,
        'quote_total', qt.total, 'quote_status', qt.status, 'quote_valid_until', qt.valid_until, 'quote_expired', qt.status = 'sent' and qt.valid_until < public._crmg_today(),
        'converted', l.converted_at is not null, 'lost_reason', l.lost_reason, 'created_at', l.created_at, 'stage_at', l.stage_at, 'last_activity_at', l.last_activity_at),
      l.stage, l.location_id
    from public.crm_leads l
    left join lateral (select q.total, q.status, q.valid_until from public.crm_lead_quotes q where q.lead_id = l.id and q.status in ('accepted', 'sent', 'draft') order by q.version desc limit 1) qt on true
    where public._crmg_lead_vis(l.location_id, l.owner_user, l.created_by)
      and (stages is null or l.stage = any (stages))
      and (nullif(f->>'loc', '') is null or l.location_id = (f->>'loc')::int)
      and (own is null or l.owner_user = own)
      and (qtxt = '' or lower(l.contact_name) like '%' || qtxt || '%' or coalesce(l.contact_phone, '') like '%' || qtxt || '%' or l.lead_no::text = qtxt)
      and (not coalesce((f->>'overdue')::boolean, false) or (l.stage not in ('won', 'lost') and l.next_follow_up is not null and l.next_follow_up < now()))
      and (not coalesce((f->>'stale')::boolean, false) or (l.stage not in ('won', 'lost') and stale is not null and l.last_activity_at < now() - (stale || ' days')::interval))
      and (nullif(f->>'converted', '') is null or (l.converted_at is not null) = (f->>'converted')::boolean)
      and (nullif(f->>'from', '') is null or (l.created_at at time zone 'Asia/Dhaka')::date >= (f->>'from')::date)
      and (nullif(f->>'to', '') is null or (l.created_at at time zone 'Asia/Dhaka')::date <= (f->>'to')::date)
    order by (l.stage in ('won', 'lost')), coalesce(l.next_follow_up, l.event_date::timestamptz, l.created_at), l.lead_no desc;
end $$;

create or replace function public._crmg_lead_list(p_filter jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lim int := least(greatest(coalesce(nullif(p_filter->>'limit', '')::int, 100), 1), 300); off int := greatest(coalesce(nullif(p_filter->>'offset', '')::int, 0), 0);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._crmg_lead_on() then return jsonb_build_object('on', false, 'rows', '[]'::jsonb, 'total', 0); end if;
  return jsonb_build_object('on', true,
    'total', (select count(*) from public._crmg_lead_rows(p_filter)),
    'by_stage', coalesce((select jsonb_object_agg(s, c) from (select stage as s, count(*) as c from public._crmg_lead_rows(p_filter - 'stage') group by stage) z), '{}'::jsonb),
    'rows', coalesce((select jsonb_agg(z.r) from (select r from public._crmg_lead_rows(p_filter) offset off limit lim) z), '[]'::jsonb));
end $$;

-- ============================================================================
-- 3. PIPELINE BOARD: five columns with count, value and the cards. Won and lost show the last 30 days only.
-- ============================================================================
create or replace function public._crmg_lead_board(p_loc int default null, p_owner uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f jsonb := jsonb_build_object('loc', p_loc, 'owner', p_owner); out jsonb := '[]'::jsonb; s text; rows jsonb; cnt int; val numeric; since timestamptz := now() - interval '30 days';
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._crmg_lead_on() then return jsonb_build_object('on', false, 'stages', '[]'::jsonb); end if;
  foreach s in array array['enquiry', 'quoted', 'following_up', 'won', 'lost'] loop
    select coalesce(jsonb_agg(z.r), '[]'::jsonb), count(*), coalesce(sum(coalesce((z.r->>'quote_total')::numeric, (z.r->>'est_value')::numeric, 0)), 0) into rows, cnt, val
      from (select r from public._crmg_lead_rows(f || jsonb_build_object('stage', s)) x
            where s not in ('won', 'lost') or (x.r->>'stage_at')::timestamptz >= since limit 60) z;
    out := out || jsonb_build_object('stage', s, 'count', cnt, 'value', val, 'cards', rows);
  end loop;
  return jsonb_build_object('on', true, 'today', public._crmg_today(),
    'overdue', (select count(*) from public._crmg_lead_rows(f || '{"overdue":true}'::jsonb)),
    'stale', (select count(*) from public._crmg_lead_rows(f || '{"stale":true}'::jsonb)),
    'stages', out);
end $$;

-- ============================================================================
-- 4. WIN / LOSS REPORT (leads the caller may see). Read only; no figure of the books is touched.
--    created = enquiries made in the dates; won / lost = enquiries closed in the dates; win rate = won / (won + lost); value of a won lead = its accepted quote or estimate
-- ============================================================================
create or replace function public._crmg_lead_report(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d1 date := coalesce(p_from, public._crmg_today() - 30); d2 date := coalesce(p_to, public._crmg_today()); res jsonb; stale numeric := public.rule_num('crm_lead_stale_days');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._crmg_lead_on() then return jsonb_build_object('on', false); end if;
  if d2 < d1 or d2 - d1 > 800 then raise exception 'bad_dates'; end if;
  with base as (
    select l.*, coalesce((select q.total from public.crm_lead_quotes q where q.lead_id = l.id and q.status in ('accepted', 'sent') order by q.version desc limit 1), l.est_value, 0) as val,
           (select pr.staff_id from public.profiles pr where pr.id = l.owner_user) as owner_staff
      from public.crm_leads l
     where public._crmg_lead_vis(l.location_id, l.owner_user, l.created_by) and (p_loc is null or l.location_id = p_loc)),
  made as (select * from base where (created_at at time zone 'Asia/Dhaka')::date between d1 and d2),
  closed as (select * from base where closed_at is not null and (closed_at at time zone 'Asia/Dhaka')::date between d1 and d2),
  w as (select * from closed where stage = 'won'), x as (select * from closed where stage = 'lost')
  select jsonb_build_object('on', true, 'from', d1, 'to', d2,
    'created', (select count(*) from made),
    'created_still_open', (select count(*) from made where stage not in ('won', 'lost')),
    'won', (select count(*) from w), 'lost', (select count(*) from x),
    'won_value', (select coalesce(sum(val), 0) from w), 'lost_value', (select coalesce(sum(val), 0) from x),
    'win_rate_pct', (select case when (select count(*) from closed) = 0 then null else round(100.0 * (select count(*) from w) / (select count(*) from closed), 1) end),
    'avg_days_to_close', (select round(avg(extract(epoch from closed_at - created_at) / 86400)::numeric, 1) from closed),
    'open_now', (select count(*) from base where stage not in ('won', 'lost')),
    'open_value', (select coalesce(sum(val), 0) from base where stage not in ('won', 'lost')),
    'overdue_open', (select count(*) from base where stage not in ('won', 'lost') and next_follow_up is not null and next_follow_up < now()),
    'stale_open', (select case when stale is null then null else count(*) end from base where stage not in ('won', 'lost') and stale is not null and last_activity_at < now() - (stale || ' days')::interval),
    'reopened', (select count(*) from base where reopened_count > 0),
    'lost_by_reason', coalesce((select jsonb_agg(jsonb_build_object('code', z.lost_reason, 'label', coalesce(li.label, z.lost_reason), 'count', z.c, 'value', z.v) order by z.c desc, z.lost_reason)
        from (select lost_reason, count(*) c, sum(val) v from x group by lost_reason) z left join public.crm_lead_lists li on li.kind = 'lost_reason' and li.code = z.lost_reason), '[]'::jsonb),
    'by_owner', coalesce((select jsonb_agg(jsonb_build_object('owner_staff', z.o, 'created', z.cr, 'won', z.wn, 'lost', z.ls, 'won_value', z.wv) order by z.wv desc nulls last, z.o)
        from (select o.owner_staff as o, (select count(*) from made m where m.owner_user = o.owner_user) cr, (select count(*) from w where w.owner_user = o.owner_user) wn,
                     (select count(*) from x where x.owner_user = o.owner_user) ls, (select coalesce(sum(val), 0) from w where w.owner_user = o.owner_user) wv
                from (select distinct owner_user, owner_staff from base) o) z where z.cr + z.wn + z.ls > 0), '[]'::jsonb),
    'by_source', coalesce((select jsonb_agg(jsonb_build_object('code', z.k, 'label', coalesce(li.label, z.k, 'Not written'), 'created', z.cr, 'won', z.wn, 'lost', z.ls) order by z.cr desc, z.k)
        from (select s.k, (select count(*) from made m where m.source is not distinct from s.k) cr, (select count(*) from w where w.source is not distinct from s.k) wn, (select count(*) from x where x.source is not distinct from s.k) ls
                from (select distinct source as k from base) s) z left join public.crm_lead_lists li on li.kind = 'source' and li.code = z.k where z.cr + z.wn + z.ls > 0), '[]'::jsonb),
    'by_occasion', coalesce((select jsonb_agg(jsonb_build_object('code', z.k, 'label', coalesce(li.label, z.k, 'Not written'), 'created', z.cr, 'won', z.wn, 'lost', z.ls) order by z.cr desc, z.k)
        from (select s.k, (select count(*) from made m where m.occasion is not distinct from s.k) cr, (select count(*) from w where w.occasion is not distinct from s.k) wn, (select count(*) from x where x.occasion is not distinct from s.k) ls
                from (select distinct occasion as k from base) s) z left join public.crm_lead_lists li on li.kind = 'occasion' and li.code = z.k where z.cr + z.wn + z.ls > 0), '[]'::jsonb))
  into res;
  return res;
end $$;

-- ============================================================================
-- 5. PRIVILEGES
-- ============================================================================
select public._crmg_lock(array['_crmg_lead_convert', '_crmg_lead_rows', '_crmg_lead_list', '_crmg_lead_board', '_crmg_lead_report'],
  array['_crmg_lead_convert', '_crmg_lead_list', '_crmg_lead_board', '_crmg_lead_report']);
