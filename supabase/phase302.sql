-- Phase 302 (bos302, package CRM-A, local label 102) - CUSTOMER 360: read functions (profile, timeline, favourites, upcoming dates, masked directory).
-- Paste AFTER phase301. Paste-twice safe. READ ONLY: nothing here writes a table. No shared function is patched or re-created.
--
--   crma_state()                         what the caller may see / do and where the three settings stand (one call for the screen)
--   crma_customer_360(customer)          the whole profile in one call: main + extra phones, addresses, dates with the next occurrence, tags, type, credit terms,
--                                        tier, totals, points, favourites, counts. Same people as customer_profile may call it. Phone numbers and addresses are
--                                        masked when the owner switched crm_mask_phone ON and the caller has no right. Notes and the old single note need crm_view.
--   crma_timeline(customer, before, before_key, limit, kinds)   one timeline of every touchpoint, newest first, paged by (time, key):
--                                        sale, return, collection (a due paid), order (online order matched by phone), points, gift, tier, and for crm_view holders
--                                        message (the SMS / WhatsApp queue), note, enquiry (inbox). Sales, returns, collections and orders are limited to the
--                                        places the caller may see (can_loc), like customer_profile.
--   crma_favourites(customer, limit)     what the customer buys most (counted on done sales, not net of returns)
--   crma_dates_upcoming(days, limit)     birthdays, anniversaries and family dates in the next N days (crm_view or owner)
--   crma_customer_directory(limit)       the masked variant of customer_directory: the SAME columns. With crm_mask_phone OFF (default) the rows are identical to
--                                        customer_directory; ON and no right: mobile and WhatsApp masked, address hidden, note only with crm_view.
-- Accounting: nothing here changes a figure; balances come from the existing _cust_bal.

do $g$ begin
  if to_regprocedure('public._crma_present()') is null or to_regclass('public.customer_phones') is null then raise exception 'phase302 needs phase300 and 301 first'; end if;
end $g$;

create or replace function public.crma_state() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object('crm_on', public.rule_on('crm_on'), 'second_phone_on', public.rule_on('crm_second_phone_on'), 'mask_phone', public.rule_on('crm_mask_phone'),
    'is_owner', public.is_owner(), 'can_see_customers', public._cust_pos43(), 'can_write', public._crma_write_ok(), 'can_manage', public._cust_mgr43(),
    'can_view', public._crma_view_ok(), 'contact_ok', public._crma_contact_ok(), 'shows_phone', public._crma_show_phone());
end $$;

create or replace function public.crma_favourites(p_customer uuid, p_limit int default 10) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('item_id', f.item_id, 'name', f.name, 'name_en', (select i.name_en from public.items i where i.id::text = f.item_id), 'unit', f.unit,
                                        'orders', f.orders, 'qty', f.qty, 'amount', f.amount, 'last_date', f.last_date) order by f.orders desc, f.qty desc nulls last, f.last_date desc, f.name)
    from (select coalesce(l.l ->> 'item_id', 'n:' || lower(coalesce(l.l ->> 'name', ''))) k, max(l.l ->> 'item_id') item_id, max(l.l ->> 'name') name, max(l.l ->> 'unit') unit,
                 count(distinct l.sid)::int orders, sum(l.qty) qty, sum(l.amt) amount, max(l.sd) last_date
          from (select s.id sid, s.sale_date sd, x.l,
                       case when x.l ->> 'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (x.l ->> 'qty')::numeric end qty,
                       case when x.l ->> 'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (x.l ->> 'amount')::numeric end amt
                from public.sales s cross join lateral jsonb_array_elements(s.lines) x(l)
                where s.customer_id = p_customer and s.status = 'done' and jsonb_typeof(s.lines) = 'array' and public.can_loc(s.location_id)) l
          group by 1 order by count(distinct l.sid) desc, sum(l.qty) desc nulls last, max(l.sd) desc, max(l.l ->> 'name') limit least(greatest(coalesce(p_limit, 10), 1), 50)) f), '[]'::jsonb);
end $$;

create or replace function public.crma_customer_360(p_customer uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.customers; st record; t public.customer_tiers; show boolean := public._crma_show_phone(); vw boolean := public._crma_view_ok();
  today date := public._today43(); ph jsonb; ad jsonb; dt jsonb; tg jsonb; xtra_default boolean; ty text; loc jsonb; own jsonb; phs text[];
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  select * into c from public.customers where id = p_customer;
  if not found then raise exception 'customer_not_found'; end if;
  select * into st from public._cust_stats43(p_customer, true);
  select * into t from public.customer_tiers where id = c.tier_id;
  select label_en into ty from public.option_lists where list_code = 'customer_types' and value_code = c.type_code;
  select jsonb_build_object('id', l.id, 'name', coalesce(l.name_en, l.name_bn)) into loc from public.locations l where l.id = c.preferred_location_id;
  select jsonb_build_object('id', p.id, 'name', coalesce(nullif(p.full_name, ''), p.staff_id)) into own from public.profiles p where p.id = c.owner_user;
  phs := public._crma_phones(p_customer);

  ph := jsonb_build_array(jsonb_build_object('id', null, 'kind', 'main', 'phone', public._crma_ph(c.mobile), 'label', 'mobile', 'wa_ok', c.whatsapp is not null and c.whatsapp = c.mobile, 'masked', not show))
     || case when c.whatsapp is not null and c.whatsapp <> c.mobile then jsonb_build_array(jsonb_build_object('id', null, 'kind', 'whatsapp', 'phone', public._crma_ph(c.whatsapp), 'label', 'mobile', 'wa_ok', true, 'masked', not show)) else '[]'::jsonb end
     || coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'kind', 'extra', 'phone', public._crma_ph(x.phone), 'label', x.label, 'wa_ok', x.wa_ok, 'note', x.note, 'masked', not show,
                                                      'shared', exists (select 1 from public.customers o where o.mobile = x.phone and o.id <> c.id)
                                                                or exists (select 1 from public.customer_phones o where o.phone = x.phone and o.active and o.customer_id <> c.id)) order by x.id)
                  from public.customer_phones x where x.customer_id = c.id and x.active), '[]'::jsonb);

  xtra_default := exists (select 1 from public.customer_addresses where customer_id = c.id and active and is_default);
  ad := case when c.address is not null then jsonb_build_array(jsonb_build_object('id', null, 'kind', 'main', 'label', 'home', 'address', case when show then c.address end, 'is_default', not xtra_default, 'hidden', not show)) else '[]'::jsonb end
     || coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'kind', 'extra', 'label', a.label, 'address', case when show then a.address end, 'area', a.area,
                                                      'landmark', case when show then a.landmark end, 'delivery_note', case when show then a.delivery_note end, 'is_default', a.is_default, 'hidden', not show) order by a.id)
                  from public.customer_addresses a where a.customer_id = c.id and a.active), '[]'::jsonb);

  dt := coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'kind', d.kind, 'person', d.person, 'month', d.m, 'day', d.d, 'year', d.y, 'remind_days_before', d.rb, 'own', d.own,
                                                       'next_date', d.nx, 'days_until', d.nx - today, 'turning', case when d.y is not null then extract(year from d.nx)::int - d.y end) order by d.nx, d.person)
                  from (select z.*, public._crma_next_date(z.m, z.d, today) nx
                        from (select null::bigint id, 'birthday' kind, 'Customer'::text person, extract(month from c.birthday)::int m, extract(day from c.birthday)::int d, extract(year from c.birthday)::int y, null::int rb, true own where c.birthday is not null
                              union all select null, 'anniversary', 'Customer', extract(month from c.anniversary)::int, extract(day from c.anniversary)::int, extract(year from c.anniversary)::int, null, true where c.anniversary is not null
                              union all select x.id, x.kind, x.person_label, x.month, x.day, x.year, x.remind_days_before, false from public.customer_dates x where x.customer_id = c.id and x.active) z) d), '[]'::jsonb);

  tg := coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'code', g.code, 'label', g.label) order by g.label) from public.customer_tags ct join public.crm_tags g on g.id = ct.tag_id where ct.customer_id = c.id and ct.active), '[]'::jsonb);

  return jsonb_build_object(
    'customer', jsonb_build_object('id', c.id, 'name', c.name, 'active', c.active, 'type', c.type, 'type_code', c.type_code, 'type_label', ty,
        'tier', case when t.id is null then null else jsonb_build_object('id', t.id, 'name', t.name_en, 'color', t.color, 'badge', t.badge) end, 'tier_locked', c.tier_locked,
        'source', c.source, 'language', c.language, 'preferred_location', loc, 'owner', own, 'credit_limit', c.credit_limit, 'credit_days', c.credit_days, 'customer_since', c.customer_since,
        'created_at', c.created_at, 'note', case when vw then c.note end),
    'stats', jsonb_build_object('spend', st.spend, 'orders', st.orders, 'orders_12m', st.orders_12m, 'first_sale', st.first_sale, 'last_sale', st.last_sale,
        'avg_bill', case when st.orders > 0 then round(st.spend / st.orders, 2) end, 'balance', public._cust_bal(p_customer),
        'points', coalesce((select sum(delta) from public.customer_points_ledger where customer_id = p_customer), 0)),
    'phones', ph, 'addresses', ad, 'dates', dt, 'tags', tg,
    'next_date', (select x from jsonb_array_elements(dt) x order by (x ->> 'days_until')::int limit 1),
    'favourites', public.crma_favourites(p_customer, 5),
    'counts', jsonb_build_object(
        'notes', case when vw then (select count(*) from public.crm_notes where customer_id = c.id and retired_at is null) end,
        'open_orders', (select count(*) from public.online_orders o where public.can_do('POS', 'view') and public.can_loc(o.location_id) and o.status in ('new', 'confirmed', 'packed') and public._crma_norm(o.customer_mobile) = any(phs)),
        'messages_waiting', case when vw then (select count(*) from public.notify_outbox m where m.customer_id = c.id and m.status in ('queued', 'sending')) end),
    'can', jsonb_build_object('crm_on', public.rule_on('crm_on'), 'edit', public._crma_write_ok() and public.rule_on('crm_on'), 'manage', public._cust_mgr43(),
        'view', vw, 'contact', public._crma_contact_ok(), 'shows_phone', show, 'second_phone', public.rule_on('crm_second_phone_on')));
end $$;

create or replace function public.crma_timeline(p_customer uuid, p_before timestamptz default null, p_before_key text default null, p_limit int default 30, p_kinds text[] default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lim int := least(greatest(coalesce(p_limit, 30), 1), 100); bk text := coalesce(p_before_key, '~~~~'); vw boolean := public._crma_view_ok(); phs text[]; arr jsonb; n int; posv boolean := public.can_do('POS', 'view');
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  perform 1 from public.customers where id = p_customer;
  if not found then raise exception 'customer_not_found'; end if;
  phs := public._crma_phones(p_customer);
  select coalesce(jsonb_agg(jsonb_build_object('at', x.at, 'key', x.ukey, 'kind', x.kind, 'title', x.title, 'amount', x.amount, 'status', x.status, 'location_id', x.loc, 'ref', x.ref, 'detail', x.detail)
                           order by x.at desc, x.ukey desc), '[]'::jsonb)
    into arr from (
      select * from (
        (select s.sold_at at, 's:' || s.id::text ukey, 'sale' kind, 'Sale #' || s.receipt title, s.total amount, s.status, s.location_id loc, s.receipt::text ref,
                jsonb_build_object('paid', s.paid, 'due', s.due_amount, 'discount', s.discount, 'pay_mode', s.pay_mode, 'sale_id', s.id) detail
         from public.sales s where s.customer_id = p_customer and public.can_loc(s.location_id) and (p_kinds is null or 'sale' = any(p_kinds)) and (p_before is null or (s.sold_at, 's:' || s.id::text) < (p_before, bk))
         order by s.sold_at desc, 's:' || s.id::text desc limit lim + 1)
        union all
        (select r.created_at, 'r:' || r.id::text, 'return', 'Return', r.amount, r.status, r.location_id, null,
                jsonb_build_object('credit', r.credit_amount, 'refund', r.refund_amount, 'reason', r.reason_code, 'sale_id', r.sale_id)
         from public.sale_returns r where r.customer_id = p_customer and public.can_loc(r.location_id) and (p_kinds is null or 'return' = any(p_kinds)) and (p_before is null or (r.created_at, 'r:' || r.id::text) < (p_before, bk))
         order by r.created_at desc, 'r:' || r.id::text desc limit lim + 1)
        union all
        (select p.paid_at, 'c:' || lpad(p.id::text, 12, '0'), 'collection', 'Due payment received', p.amount, case when p.voided then 'void' else 'done' end, p.location_id, null,
                jsonb_build_object('mode', p.mode)
         from public.sale_payments p where p.customer_id = p_customer and p.kind = 'collection' and public.can_loc(p.location_id) and (p_kinds is null or 'collection' = any(p_kinds)) and (p_before is null or (p.paid_at, 'c:' || lpad(p.id::text, 12, '0')) < (p_before, bk))
         order by p.paid_at desc, 'c:' || lpad(p.id::text, 12, '0') desc limit lim + 1)
        union all
        (select o.created_at, 'o:' || o.id::text, 'order', 'Order #' || o.order_no, o.subtotal - o.discount + o.delivery_charge, o.status, o.location_id, o.order_no::text,
                jsonb_build_object('channel', o.channel, 'delivery_date', o.delivery_date, 'advance', o.advance, 'delivery_mode', o.delivery_mode)
         from public.online_orders o where posv and public.can_loc(o.location_id) and public._crma_norm(o.customer_mobile) = any(phs) and (p_kinds is null or 'order' = any(p_kinds)) and (p_before is null or (o.created_at, 'o:' || o.id::text) < (p_before, bk))
         order by o.created_at desc, 'o:' || o.id::text desc limit lim + 1)
        union all
        (select l.at, 'p:' || lpad(l.id::text, 12, '0'), 'points', case l.reason when 'sale' then 'Points earned' when 'redeem' then 'Points used' when 'expire' then 'Points expired' else 'Points adjusted' end, null::numeric, 'done', null::int, null,
                jsonb_build_object('points', l.delta, 'note', l.note)
         from public.customer_points_ledger l where l.customer_id = p_customer and (p_kinds is null or 'points' = any(p_kinds)) and (p_before is null or (l.at, 'p:' || lpad(l.id::text, 12, '0')) < (p_before, bk))
         order by l.at desc, 'p:' || lpad(l.id::text, 12, '0') desc limit lim + 1)
        union all
        (select g.issued_at, 'g:' || g.id::text, 'gift', coalesce(g.gift_text_en, g.gift_text_bn), g.value_taka, case when g.claimed_at is not null then 'given' else 'waiting' end, null::int, null,
                jsonb_build_object('valid_until', g.valid_until, 'claimed_at', g.claimed_at)
         from public.customer_gifts g where g.customer_id = p_customer and (p_kinds is null or 'gift' = any(p_kinds)) and (p_before is null or (g.issued_at, 'g:' || g.id::text) < (p_before, bk))
         order by g.issued_at desc, 'g:' || g.id::text desc limit lim + 1)
        union all
        (select h.at, 't:' || lpad(h.id::text, 12, '0'), 'tier', 'Tier: ' || coalesce((select name_en from public.customer_tiers where id = h.from_tier), '-') || ' to ' || coalesce((select name_en from public.customer_tiers where id = h.to_tier), '-'), null::numeric, 'done', null::int, null,
                jsonb_build_object('reason', h.reason, 'note', h.note)
         from public.customer_tier_history h where h.customer_id = p_customer and (p_kinds is null or 'tier' = any(p_kinds)) and (p_before is null or (h.at, 't:' || lpad(h.id::text, 12, '0')) < (p_before, bk))
         order by h.at desc, 't:' || lpad(h.id::text, 12, '0') desc limit lim + 1)
        union all
        (select m.created_at, 'm:' || lpad(m.id::text, 12, '0'), 'message', initcap(m.channel) || ': ' || m.template_code, null::numeric, m.status, null::int, null,
                jsonb_build_object('to', public._crma_ph(case when m.to_phone ~ '^\+8801' then '0' || substr(m.to_phone, 5) else m.to_phone end), 'text', left(m.body, 160), 'sent_at', m.sent_at)
         from public.notify_outbox m where vw and m.customer_id = p_customer and (p_kinds is null or 'message' = any(p_kinds)) and (p_before is null or (m.created_at, 'm:' || lpad(m.id::text, 12, '0')) < (p_before, bk))
         order by m.created_at desc, 'm:' || lpad(m.id::text, 12, '0') desc limit lim + 1)
        union all
        (select nn.created_at, 'n:' || lpad(nn.id::text, 12, '0'), 'note', initcap(nn.kind), null::numeric, 'done', null::int, null,
                jsonb_build_object('text', nn.body, 'by', nn.created_staff, 'note_id', nn.id)
         from public.crm_notes nn where vw and nn.customer_id = p_customer and nn.retired_at is null and (p_kinds is null or 'note' = any(p_kinds)) and (p_before is null or (nn.created_at, 'n:' || lpad(nn.id::text, 12, '0')) < (p_before, bk))
         order by nn.created_at desc, 'n:' || lpad(nn.id::text, 12, '0') desc limit lim + 1)
        union all
        (select im.received_at, 'e:' || lpad(im.id::text, 12, '0'), 'enquiry', 'Enquiry', null::numeric, im.status, im.location_id, null,
                jsonb_build_object('text', left(im.msg_text, 160), 'channel_id', im.channel_id)
         from public.inbound_messages im where vw and posv and public.can_loc(im.location_id) and public._crma_norm(im.customer_handle) = any(phs) and (p_kinds is null or 'enquiry' = any(p_kinds)) and (p_before is null or (im.received_at, 'e:' || lpad(im.id::text, 12, '0')) < (p_before, bk))
         order by im.received_at desc, 'e:' || lpad(im.id::text, 12, '0') desc limit lim + 1)
      ) u order by u.at desc, u.ukey desc limit lim + 1) x;
  n := jsonb_array_length(arr);
  if n > lim then arr := arr - lim; end if;
  return jsonb_build_object('items', arr, 'has_more', n > lim,
    'next', case when n > lim then jsonb_build_object('before', arr -> (lim - 1) ->> 'at', 'key', arr -> (lim - 1) ->> 'key') end);
end $$;

create or replace function public.crma_dates_upcoming(p_days int default 30, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare today date := public._today43(); dys int := least(greatest(coalesce(p_days, 30), 0), 366);
begin
  if not public._crma_view_ok() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('customer_id', r.cid, 'name', r.name, 'phone', public._crma_ph(r.mobile), 'kind', r.kind, 'person', r.person, 'date', r.nx, 'days_until', r.nx - today,
                                                       'turning', case when r.y is not null then extract(year from r.nx)::int - r.y end) order by r.nx, r.name)
    from (select * from (
            select c.id cid, c.name, c.mobile, 'birthday' kind, 'Customer'::text person, extract(year from c.birthday)::int y, public._crma_next_date(extract(month from c.birthday)::int, extract(day from c.birthday)::int, today) nx
              from public.customers c where c.active and c.birthday is not null
            union all select c.id, c.name, c.mobile, 'anniversary', 'Customer', extract(year from c.anniversary)::int, public._crma_next_date(extract(month from c.anniversary)::int, extract(day from c.anniversary)::int, today)
              from public.customers c where c.active and c.anniversary is not null
            union all select c.id, c.name, c.mobile, d.kind, d.person_label, d.year, public._crma_next_date(d.month, d.day, today)
              from public.customer_dates d join public.customers c on c.id = d.customer_id where d.active and c.active) z
          where z.nx - today <= dys order by z.nx, z.name limit least(greatest(coalesce(p_limit, 200), 1), 1000)) r), '[]'::jsonb);
end $$;

create or replace function public.crma_customer_directory(p_limit int default 5000)
returns table (id uuid, mobile text, name text, type text, active boolean, tier_id bigint, tier_locked boolean, birthday date, anniversary date, address text, whatsapp text, note text,
               credit_limit numeric, customer_since date, balance numeric, spend numeric, orders int, last_sale date, points int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  if public._crma_show_phone() then
    return query select * from public.customer_directory(p_limit);                               -- guard OFF (today) or the caller has the right: identical rows
    return;
  end if;
  return query
    select d.id, public._crma_mask(d.mobile), d.name, d.type, d.active, d.tier_id, d.tier_locked, d.birthday, d.anniversary, null::text, public._crma_mask(d.whatsapp),
           case when public._crma_view_ok() then d.note end, d.credit_limit, d.customer_since, d.balance, d.spend, d.orders, d.last_sale, d.points
    from public.customer_directory(p_limit) d;
end $$;

revoke all on function public.crma_state(), public.crma_favourites(uuid, int), public.crma_customer_360(uuid), public.crma_timeline(uuid, timestamptz, text, int, text[]),
  public.crma_dates_upcoming(int, int), public.crma_customer_directory(int) from public, anon;
grant execute on function public.crma_state(), public.crma_favourites(uuid, int), public.crma_customer_360(uuid), public.crma_timeline(uuid, timestamptz, text, int, text[]),
  public.crma_dates_upcoming(int, int), public.crma_customer_directory(int) to authenticated;
