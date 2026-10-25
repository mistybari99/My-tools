-- Phase 533 (UNION-5: stock functions carry both lines (unit conversion, late sale, returns, transit loss, reconcile audit, intermediate ingredients)). Paste-twice safe. Earlier phase files are not edited.
-- What: _sale_stock_out: our switch stock_unit_unknown_block (phase 501) first, then the advanced unit_conv_required (bos82) and the late sale / offline soft stock rules.
--   sale_return: our return_sale_factor_on (phase 501) then the advanced return_uses_sale_rows (bos114). stock_receive_transfer: our partial receipt (phase 499) and the advanced
--   transit_short_mode = loss (bos83) counted on what is still missing. stock_reconcile: our change log (bos420) and the advanced audit line per fixed row (bos84). stock_transfer: both.
--   _recipe_lines_ok: a made product may be an ingredient when EITHER recipe_intermediate_on (phase 504) OR semi_finished_ingredient116 (bos116) is on; both loop checks run.
-- All of these rules default to OFF/as before. Paste AFTER phase532 and after phase 505. Same behaviour on a re-paste as phase530.

create table if not exists public._union_fn_backup (id bigserial primary key, fn text not null, saved_at timestamptz not null default now(), why text, def text not null);
alter table public._union_fn_backup enable row level security;
revoke all on public._union_fn_backup from anon, authenticated;

drop table if exists _u_plan;
create temp table _u_plan (seq serial primary key, fn text not null, kind text not null, a text not null, b text);
-- _sale_stock_out()
insert into _u_plan (fn, kind, a, b) values
  ('public._sale_stock_out()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._sale_stock_out()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- bos89: merge of phase508 (unit_conv_required) and phase509 (offline soft stock); the original Bangla wording of the unit message is kept
declare ln jsonb; it public.items; q numeric; bq numeric; neg text; um text; soft83 boolean := false; bal83 numeric;   -- bos82 bos83
begin
  if new.status <> 'done' or new.lines is null or jsonb_typeof(new.lines) <> 'array' then return new; end if;
  -- a sale that syncs late (an offline phone) has already happened: it is recorded, it never blocks (a yellow line still tells the owner). See phase 501, L1.
  neg := case when new.sold_at < now() - interval '2 minutes' then 'soft' else 'full' end;
  -- bos94: owner can limit how old a sale may be and still count as a late sync (rule offline_sale_max_age, hours; empty = no limit = as before). A manager replay override stays soft.
  if neg = 'soft' and public.rule_num('offline_sale_max_age') is not null and new.sold_at < now() - make_interval(hours => public.rule_num('offline_sale_max_age')::int)
     and coalesce(current_setting('bos.replay_override', true), '') <> '1' then neg := 'full'; end if;   -- bos94
  -- bos83: a sale replayed from the offline queue (record_sale_offline / manager override) is soft too when the owner switch offline_soft_stock is on (override: always) - flagged below
  if neg = 'soft' and public.rule_on('late_sale_follows_block') and coalesce(current_setting('bos.offline_replay', true), '') <> '1' and coalesce(current_setting('bos.replay_override', true), '') <> '1' then neg := 'full'; end if;   -- bos114:late-sale (an online sale with an old p_sold_at is not an offline sync)
  if neg = 'full' and coalesce(current_setting('bos.offline_replay', true), '') = '1'
     and (public.rule_on('offline_soft_stock') or coalesce(current_setting('bos.replay_override', true), '') = '1') then neg := 'soft'; soft83 := true; end if;
  -- items in a fixed order, so two sales that share items can never wait on each other in a circle
  for ln in select x from jsonb_array_elements(new.lines) x where nullif(x->>'item_id', '') is not null order by x->>'item_id' loop
    select * into it from public.items where id = (ln->>'item_id')::uuid;
    if not found or not it.tracked then continue; end if;
    q := nullif(ln->>'qty', '')::numeric;
    if q is null or q <= 0 then continue; end if;
    if not (q <= 999999999) then raise exception 'bad_qty'; end if;                    -- Infinity / NaN / absurd: the sale is refused
    bq := public._base_qty(it.id, q, ln->>'unit');
    if bq is null then
      if public.rule_on('stock_unit_unknown_block') then
        raise exception 'stock_unit_unknown' using detail = coalesce(it.code, ''), hint = 'unit ' || coalesce(ln->>'unit', '') || ' has no conversion to ' || coalesce(nullif(it.base_unit, ''), it.unit);
      end if;
      um := coalesce(public.rule_txt('unit_conv_required'), 'warn');   -- bos82: off | warn (today) | refuse
      if um = 'refuse' and neg = 'full' then raise exception 'unit_unknown' using detail = 'Unit conversion unknown for ' || it.code || ': set the conversion or sell in the base unit', hint = it.code; end if;   -- bos82
      if um = 'refuse' then   -- bos82: a sale that already happened (offline) is recorded, never lost, but flagged red
        perform public._stock_exc(new.location_id, 'stock_unit_unknown_late', 'red',
          'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — offline বিক্রি নেওয়া হয়েছে কিন্তু unit-এর conversion জানা নেই, stock কমেনি',
          'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.code) || ' — offline sale accepted but the unit conversion is unknown, stock was NOT reduced', new.id, new.sale_date, 'POS');   -- bos82
      elsif um <> 'off' then   -- bos82
      perform public._stock_exc(new.location_id, 'stock_unit_unknown', 'yellow',
        'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — এককের রূপান্তর জানা নেই, স্টক কমানো হয়নি',
        'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — the unit conversion is unknown, stock was NOT reduced', new.id, new.sale_date, 'POS');
      end if;   -- bos82
      continue;
    end if;
    if not (bq <= 999999999) then raise exception 'bad_qty'; end if;
    insert into public.sale_base_factor (sale_id, item_id, unit, factor) values (new.id, it.id, coalesce(ln->>'unit', ''), round(bq / q, 12)) on conflict do nothing;
    if round(bq, 4) = 0 then continue; end if;                                          -- under 0.00005 of a base unit: nothing to take out
    if soft83 then      -- bos83
      select b.qty into bal83 from public.stock_balance b where b.item_id = it.id and b.location_id = new.location_id;
      if coalesce(bal83, 0) < bq then
        perform public._stock_exc(new.location_id, 'offline_soft_stock', 'yellow',
          'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — offline sale, stock-এর চেয়ে বেশি; sale গ্রহণ হয়েছে, stock ঋণাত্মক হতে পারে',
          'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — offline sale above the stock on hand; accepted, stock may go negative', new.id, new.sale_date, 'POS');
      end if;
    end if;
    perform public.stock_post(it.id, new.location_id, -bq, 'sale_out', 'sale', new.id::text, null, null, new.sold_at, null, null, neg, new.id);
  end loop;
  return new;
end $function$$r0_0$, null),
  ('public._sale_stock_out()', 'known', '6d154ba33575afcbed1c3e41aa767a0a', null),
  ('public._sale_stock_out()', 'known', '85cb2f162c0cf934e637824e4de000aa', null),
  ('public._sale_stock_out()', 'known', 'c67d14180692b7b19b114e01052a0e9b', null),
  ('public._sale_stock_out()', 'old', $o0_0$AS $function$
declare ln jsonb; it public.items; q numeric; bq numeric; neg text;
begin$o0_0$, $n0_0$AS $function$
-- bos89: merge of phase508 (unit_conv_required) and phase509 (offline soft stock); the original Bangla wording of the unit message is kept
declare ln jsonb; it public.items; q numeric; bq numeric; neg text; um text; soft83 boolean := false; bal83 numeric;   -- bos82 bos83
begin$n0_0$),
  ('public._sale_stock_out()', 'old', $o1_0$  neg := case when new.sold_at < now() - interval '2 minutes' then 'soft' else 'full' end;
  -- items in a fixed order, so two sales that share items can never wait on each other in a circle$o1_0$, $n1_0$  neg := case when new.sold_at < now() - interval '2 minutes' then 'soft' else 'full' end;
  -- bos94: owner can limit how old a sale may be and still count as a late sync (rule offline_sale_max_age, hours; empty = no limit = as before). A manager replay override stays soft.
  if neg = 'soft' and public.rule_num('offline_sale_max_age') is not null and new.sold_at < now() - make_interval(hours => public.rule_num('offline_sale_max_age')::int)
     and coalesce(current_setting('bos.replay_override', true), '') <> '1' then neg := 'full'; end if;   -- bos94
  -- bos83: a sale replayed from the offline queue (record_sale_offline / manager override) is soft too when the owner switch offline_soft_stock is on (override: always) - flagged below
  if neg = 'soft' and public.rule_on('late_sale_follows_block') and coalesce(current_setting('bos.offline_replay', true), '') <> '1' and coalesce(current_setting('bos.replay_override', true), '') <> '1' then neg := 'full'; end if;   -- bos114:late-sale (an online sale with an old p_sold_at is not an offline sync)
  if neg = 'full' and coalesce(current_setting('bos.offline_replay', true), '') = '1'
     and (public.rule_on('offline_soft_stock') or coalesce(current_setting('bos.replay_override', true), '') = '1') then neg := 'soft'; soft83 := true; end if;
  -- items in a fixed order, so two sales that share items can never wait on each other in a circle$n1_0$),
  ('public._sale_stock_out()', 'old', $o2_0$      end if;
      perform public._stock_exc(new.location_id, 'stock_unit_unknown', 'yellow',$o2_0$, $n2_0$      end if;
      um := coalesce(public.rule_txt('unit_conv_required'), 'warn');   -- bos82: off | warn (today) | refuse
      if um = 'refuse' and neg = 'full' then raise exception 'unit_unknown' using detail = 'Unit conversion unknown for ' || it.code || ': set the conversion or sell in the base unit', hint = it.code; end if;   -- bos82
      if um = 'refuse' then   -- bos82: a sale that already happened (offline) is recorded, never lost, but flagged red
        perform public._stock_exc(new.location_id, 'stock_unit_unknown_late', 'red',
          'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — offline বিক্রি নেওয়া হয়েছে কিন্তু unit-এর conversion জানা নেই, stock কমেনি',
          'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.code) || ' — offline sale accepted but the unit conversion is unknown, stock was NOT reduced', new.id, new.sale_date, 'POS');   -- bos82
      elsif um <> 'off' then   -- bos82
      perform public._stock_exc(new.location_id, 'stock_unit_unknown', 'yellow',$n2_0$),
  ('public._sale_stock_out()', 'old', $o3_0$        'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — the unit conversion is unknown, stock was NOT reduced', new.id, new.sale_date, 'POS');
      continue;$o3_0$, $n3_0$        'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — the unit conversion is unknown, stock was NOT reduced', new.id, new.sale_date, 'POS');
      end if;   -- bos82
      continue;$n3_0$),
  ('public._sale_stock_out()', 'old', $o4_0$    if round(bq, 4) = 0 then continue; end if;                                          -- under 0.00005 of a base unit: nothing to take out
    perform public.stock_post(it.id, new.location_id, -bq, 'sale_out', 'sale', new.id::text, null, null, new.sold_at, null, null, neg, new.id);$o4_0$, $n4_0$    if round(bq, 4) = 0 then continue; end if;                                          -- under 0.00005 of a base unit: nothing to take out
    if soft83 then      -- bos83
      select b.qty into bal83 from public.stock_balance b where b.item_id = it.id and b.location_id = new.location_id;
      if coalesce(bal83, 0) < bq then
        perform public._stock_exc(new.location_id, 'offline_soft_stock', 'yellow',
          'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — offline sale, stock-এর চেয়ে বেশি; sale গ্রহণ হয়েছে, stock ঋণাত্মক হতে পারে',
          'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — offline sale above the stock on hand; accepted, stock may go negative', new.id, new.sale_date, 'POS');
      end if;
    end if;
    perform public.stock_post(it.id, new.location_id, -bq, 'sale_out', 'sale', new.id::text, null, null, new.sold_at, null, null, neg, new.id);$n4_0$);
-- sale_return(uuid,uuid,jsonb,text,text,text,text,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.sale_return(p_client uuid, p_sale uuid, p_lines jsonb, p_reason text, p_note text DEFAULT NULL::text, p_refund_mode text DEFAULT NULL::text, p_wallet text DEFAULT NULL::text, p_ref text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.sales; r public.sale_returns; it public.items; ln record; rid uuid := gen_random_uuid(); pamt numeric; sq numeric; samt numeric; su text; pq numeric; price numeric; lamt numeric;
        gross numeric := 0; amt numeric; credit numeric := 0; refund numeric; bal numeric; fac numeric; out_lines jsonb := '[]'::jsonb; sid text;
        bq numeric; prior numeric; skip numeric; rem numeric; take numeric; o record; avail numeric; lid bigint;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into s from public.sales where id = p_sale;
  if not found then raise exception 'sale_not_found'; end if;
  if not public.can_loc(s.location_id) then raise exception 'not allowed for this location'; end if;
  if p_client is not null then
    select * into r from public.sale_returns where client_id = p_client;
    if found then
      if r.created_by is distinct from auth.uid() and not public.has_grant('sale_return', r.location_id) then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', r.id, 'amount', r.amount, 'credit', r.credit_amount, 'refund', r.refund_amount);
    end if;
  end if;
  if p_reason is null or not exists (select 1 from public.option_lists where list_code = 'return_reasons' and value_code = p_reason and active) then raise exception 'reason_required'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  if not (public.has_grant('sale_return', s.location_id) or public._use_em('sale_return', s.location_id, 'sale_return:' || p_sale::text, null)) then raise exception 'not allowed'; end if;
  -- every line is checked before anything is cast: a malformed uuid / quantity is bad_item / bad_qty, never a raw cast error
  for ln in select e from jsonb_array_elements(p_lines) e loop
    if jsonb_typeof(ln.e) <> 'object' or coalesce(ln.e->>'item_id', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then raise exception 'bad_item'; end if;
    if coalesce(ln.e->>'qty', '') !~ '^[0-9]{1,9}(\.[0-9]{1,6})?$' then raise exception 'bad_qty'; end if;
  end loop;
  perform 1 from public.sales where id = p_sale for update;                  -- one return at a time per sale
  select * into s from public.sales where id = p_sale;
  if s.status <> 'done' then raise exception 'sale_not_done'; end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  -- same item twice in p_lines is added up
  for ln in select e->>'item_id' iid, sum((e->>'qty')::numeric) q from jsonb_array_elements(p_lines) e group by 1 loop
    if ln.iid is null or ln.q is null or not (ln.q between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
    select coalesce(sum((e->>'qty')::numeric), 0), coalesce(sum((e->>'amount')::numeric), 0), max(e->>'unit')
      into sq, samt, su from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e where e->>'item_id' = ln.iid;
    if sq <= 0 then raise exception 'line_not_in_sale'; end if;
    select coalesce(sum((e->>'qty')::numeric), 0) into pq from public.sale_returns x, jsonb_array_elements(x.lines) e where x.sale_id = s.id and x.status = 'done' and e->>'item_id' = ln.iid;
    if ln.q > sq - pq + 0.00005 then raise exception 'return_exceeds_sale'; end if;
    select coalesce(sum((e->>'amount')::numeric), 0) into pamt from public.sale_returns x, jsonb_array_elements(x.lines) e where x.sale_id = s.id and x.status = 'done' and e->>'item_id' = ln.iid;
    price := samt / sq;
    -- the last unit takes what is left of the line's money, so partial returns add up to the line exactly
    lamt := case when ln.q >= sq - pq - 0.00005 then greatest(samt - pamt, 0) else round(ln.q * price, 2) end; gross := gross + lamt;
    select * into it from public.items where id = ln.iid::uuid and public._m132_own(items.org_unit_id) /* m132b:items */;
    out_lines := out_lines || jsonb_build_object('item_id', ln.iid, 'name', coalesce(it.name_bn, ''), 'unit', su, 'qty', ln.q, 'price', round(price, 4), 'amount', lamt);
  end loop;
  if not (gross between 0.01 and 999999999999) then raise exception 'bad_amount'; end if;
  fac := case when s.subtotal > 0 then s.total / s.subtotal else 1 end;               -- the sale's discount is shared in proportion
  amt := round(gross * fac, 2);
  if not (amt between 0.01 and 999999999999) then raise exception 'bad_amount'; end if;
  if s.customer_id is not null then perform pg_advisory_xact_lock(hashtextextended('bos12c:' || s.customer_id::text, 0)); end if;
  if s.customer_id is not null and public.rule_on('sale_return_due_first') then
    bal := coalesce(public._cust_bal(s.customer_id), 0);
    credit := least(amt, greatest(bal, 0));
  end if;
  refund := amt - credit;
  if refund > 0 and (p_refund_mode is null or p_refund_mode not in ('cash', 'mobile', 'card')) then raise exception 'refund_mode_required'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  begin
    insert into public.sale_returns (id, client_id, sale_id, location_id, customer_id, lines, amount, credit_amount, refund_amount, refund_mode, wallet, ref, reason_code, note, created_by, created_staff)
      values (rid, p_client, s.id, s.location_id, s.customer_id, out_lines, amt, credit, refund, case when refund > 0 then p_refund_mode end, left(nullif(p_wallet, ''), 30), left(nullif(p_ref, ''), 60), p_reason, left(nullif(btrim(p_note), ''), 300), auth.uid(), sid);
  exception when unique_violation then
    select * into r from public.sale_returns where p_client is not null and client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id, 'amount', r.amount, 'credit', r.credit_amount, 'refund', r.refund_amount); end if;
    raise;
  end;
  -- stock back (tracked items), batch aware
  for ln in select e->>'item_id' iid, (e->>'qty')::numeric q, e->>'unit' u from jsonb_array_elements(out_lines) e order by 1 loop
    select * into it from public.items where id = ln.iid::uuid and public._m132_own(items.org_unit_id) /* m132b:items */;
    if it.tracked is not true then continue; end if;
    bq := null;
    if public.rule_on('return_sale_factor_on') then                  -- the factor saved at the sale (sale_base_factor); older sales have none and use today's factor
      select f.factor * ln.q into bq from public.sale_base_factor f where f.sale_id = s.id and f.item_id = it.id and f.unit = coalesce(ln.u, '');
    end if;
    if bq is null then bq := public._base_qty(it.id, ln.q, ln.u); end if;
    if public.rule_on('return_uses_sale_rows') then   -- bos114:return-rows: base quantity the sale itself took out x returned part of the line (not today's factor)
      bq := coalesce((select z.sold_base * bq / z.sold_line from (select
          (select sum(-x.qty_delta) from public.stock_ledger x where x.ref_type = 'sale' and x.ref_id = s.id::text and x.reason = 'sale_out' and x.item_id = it.id
              and not exists (select 1 from public.stock_ledger v where v.reverses_id = x.id)) sold_base,
          (select case when count(*) filter (where q.b is null) > 0 then null else sum(q.b) end from (select public._base_qty(it.id, nullif(e->>'qty', '')::numeric, e->>'unit') b      -- sec121: all lines of the item, in base units
              from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e where e->>'item_id' = it.id::text) q) sold_line) z
        where z.sold_base > 0 and z.sold_line > 0), bq);
    end if;
    if bq is null then
      perform public._stock_exc(s.location_id, 'stock_unit_unknown', 'yellow', 'রসিদ ' || s.receipt || ': ' || it.name_bn || ' — এককের রূপান্তর জানা নেই, ফেরত মাল স্টকে ওঠেনি',
        'Receipt ' || s.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — the unit conversion is unknown, the returned goods were NOT put back', s.id, s.sale_date, 'POS');
      continue;
    end if;
    rem := round(bq, 4);
    -- what earlier (live) returns of this sale already put back for this item
    select coalesce(sum(l.qty_delta), 0) into prior from public.stock_ledger l
      where l.item_id = it.id and l.ref_type = 'sale_return' and l.ref_id in (select x.id::text from public.sale_returns x where x.sale_id = s.id and x.id <> rid);
    skip := prior;
    for o in select * from public.stock_ledger x where x.ref_type = 'sale' and x.ref_id = s.id::text and x.reason = 'sale_out' and x.item_id = it.id
             and not exists (select 1 from public.stock_ledger v where v.reverses_id = x.id) order by x.id loop
      exit when rem <= 0;
      avail := -o.qty_delta;
      if skip >= avail then skip := skip - avail; continue; end if;
      avail := avail - skip; skip := 0;
      take := least(avail, rem);
      perform public.stock_post(it.id, s.location_id, take, 'sale_return', 'sale_return', rid::text, o.unit_cost, o.batch_id, now(), left('return of receipt ' || s.receipt, 200), null, 'none');
      rem := rem - take;
    end loop;
    if rem >= 0.0005 then            -- no sale_out ledger row covers this (stock tracking was switched on after the sale): nothing is invented, the owner is told
      perform public._stock_exc(s.location_id, 'return_no_stock_trace', 'yellow', 'রসিদ ' || s.receipt || ': ' || it.name_bn || ' — বিক্রির স্টক-হিসাব নেই, ফেরত মাল স্টকে ওঠেনি (টাকা ফেরত/বাকি কমা হয়েছে)',
        'Receipt ' || s.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — the sale has no stock ledger trace, the returned goods were NOT put back (money / due credit was still given)', s.id, s.sale_date, 'POS');
    end if;
  end loop;
  if coalesce(public.rule_txt('packaging_return_mode'), 'none') <> 'none' then      -- bos80: packaging of a returned product (none = today)
    perform public._ret_pack80(rid, s.id, out_lines);
  end if;
  perform public._stock_exc(s.location_id, 'sale_return', 'yellow', 'রসিদ ' || s.receipt || ': বিক্রি ফেরত ' || amt::text, 'Receipt ' || s.receipt || ': a sale return of ' || amt::text, s.id, s.sale_date, 'POS', amt);
  perform public._w1c_return_hook(rid); /* bos91 */
  return jsonb_build_object('id', rid, 'amount', amt, 'credit', credit, 'refund', refund);
end $function$$r0_0$, null),
  ('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'known', '7e2e09f0185df9ee356ad36f76070fe6', null),
  ('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'known', '8532e9849c8b6233ee40d2699cfd538a', null),
  ('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'known', '98732425d858f6bd190aeac139f92b1e', null),
  ('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'known', 'c3298aa49ef8be2c624eef0638bd6dba', null),
  ('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'old', $o0_0$    lamt := case when ln.q >= sq - pq - 0.00005 then greatest(samt - pamt, 0) else round(ln.q * price, 2) end; gross := gross + lamt;
    select * into it from public.items where id = ln.iid::uuid;
    out_lines := out_lines || jsonb_build_object('item_id', ln.iid, 'name', coalesce(it.name_bn, ''), 'unit', su, 'qty', ln.q, 'price', round(price, 4), 'amount', lamt);$o0_0$, $n0_0$    lamt := case when ln.q >= sq - pq - 0.00005 then greatest(samt - pamt, 0) else round(ln.q * price, 2) end; gross := gross + lamt;
    select * into it from public.items where id = ln.iid::uuid and public._m132_own(items.org_unit_id) /* m132b:items */;
    out_lines := out_lines || jsonb_build_object('item_id', ln.iid, 'name', coalesce(it.name_bn, ''), 'unit', su, 'qty', ln.q, 'price', round(price, 4), 'amount', lamt);$n0_0$),
  ('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'old', $o1_0$  for ln in select e->>'item_id' iid, (e->>'qty')::numeric q, e->>'unit' u from jsonb_array_elements(out_lines) e order by 1 loop
    select * into it from public.items where id = ln.iid::uuid;
    if it.tracked is not true then continue; end if;$o1_0$, $n1_0$  for ln in select e->>'item_id' iid, (e->>'qty')::numeric q, e->>'unit' u from jsonb_array_elements(out_lines) e order by 1 loop
    select * into it from public.items where id = ln.iid::uuid and public._m132_own(items.org_unit_id) /* m132b:items */;
    if it.tracked is not true then continue; end if;$n1_0$),
  ('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'old', $o2_0$    if bq is null then bq := public._base_qty(it.id, ln.q, ln.u); end if;
    if bq is null then$o2_0$, $n2_0$    if bq is null then bq := public._base_qty(it.id, ln.q, ln.u); end if;
    if public.rule_on('return_uses_sale_rows') then   -- bos114:return-rows: base quantity the sale itself took out x returned part of the line (not today's factor)
      bq := coalesce((select z.sold_base * bq / z.sold_line from (select
          (select sum(-x.qty_delta) from public.stock_ledger x where x.ref_type = 'sale' and x.ref_id = s.id::text and x.reason = 'sale_out' and x.item_id = it.id
              and not exists (select 1 from public.stock_ledger v where v.reverses_id = x.id)) sold_base,
          (select case when count(*) filter (where q.b is null) > 0 then null else sum(q.b) end from (select public._base_qty(it.id, nullif(e->>'qty', '')::numeric, e->>'unit') b      -- sec121: all lines of the item, in base units
              from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e where e->>'item_id' = it.id::text) q) sold_line) z
        where z.sold_base > 0 and z.sold_line > 0), bq);
    end if;
    if bq is null then$n2_0$),
  ('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'old', $o3_0$  end loop;
  perform public._stock_exc(s.location_id, 'sale_return', 'yellow', 'রসিদ ' || s.receipt || ': বিক্রি ফেরত ' || amt::text, 'Receipt ' || s.receipt || ': a sale return of ' || amt::text, s.id, s.sale_date, 'POS', amt);$o3_0$, $n3_0$  end loop;
  if coalesce(public.rule_txt('packaging_return_mode'), 'none') <> 'none' then      -- bos80: packaging of a returned product (none = today)
    perform public._ret_pack80(rid, s.id, out_lines);
  end if;
  perform public._stock_exc(s.location_id, 'sale_return', 'yellow', 'রসিদ ' || s.receipt || ': বিক্রি ফেরত ' || amt::text, 'Receipt ' || s.receipt || ': a sale return of ' || amt::text, s.id, s.sale_date, 'POS', amt);$n3_0$);
-- stock_receive_transfer(uuid,numeric,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.stock_receive_transfer(uuid,numeric,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.stock_receive_transfer(p_id uuid, p_received_qty numeric DEFAULT NULL::numeric, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t public.stock_transfers; it public.items; rq numeric; sid text; o record; rem numeric; take numeric; nb bigint; ob public.stock_batches;
  lid bigint; got numeric; skip numeric; avail numeric; left_qty numeric; partial boolean;
begin
  select * into t from public.stock_transfers where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if t.status = 'received' then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
  if t.status <> 'sent' then raise exception 'not_in_transit'; end if;
  it := public._stock_guard(t.item_id, t.to_location_id, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);
  if not public._may('stock_transfer', t.to_location_id, 'receive:' || p_id::text, t.qty) then raise exception 'not allowed'; end if;
  -- what has already arrived in earlier steps of this delivery (always 0 when the switch is off: one receipt closes the transfer)
  got := coalesce((select sum(l.qty_delta) from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = t.id::text and l.reason = 'transfer_in'), 0);
  left_qty := t.qty - got;
  rq := coalesce(p_received_qty, left_qty);
  if not (rq between 0 and 999999999) then raise exception 'bad_qty'; end if;
  if rq > left_qty then raise exception 'over_received'; end if;
  partial := public.rule_on('transfer_partial_on') and rq < left_qty;
  rem := rq;
  skip := got;
  for o in select * from public.stock_ledger where ref_type = 'transfer' and ref_id = t.id::text and reason = 'transfer_out' order by id loop
    exit when rem <= 0;
    avail := -o.qty_delta;
    if skip >= avail then skip := skip - avail; continue; end if;      -- this line already arrived in an earlier step
    avail := avail - skip;
    skip := 0;
    take := least(avail, rem);
    nb := null;
    if o.batch_id is not null then       -- the batch travels with the goods: same made-at and expiry at the destination
      select * into ob from public.stock_batches where id = o.batch_id;
      insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
        values (t.item_id, t.to_location_id, ob.made_at, take, take, ob.expires_at, ob.shelf_rule, 'transfer', auth.uid()) returning id into nb;
    end if;
    lid := public.stock_post(t.item_id, t.to_location_id, take, 'transfer_in', 'transfer', t.id::text, o.unit_cost, nb, now(), left(p_note, 200), null, 'none');
    rem := rem - take;
  end loop;
  select staff_id into sid from public.profiles where id = auth.uid();
  if partial then
    update public.stock_transfers set received_qty = got + rq, receive_note = left(p_note, 200), received_by = auth.uid(), received_staff = sid, received_at = now() where id = t.id;
    return jsonb_build_object('id', t.id, 'status', 'sent', 'partial', true, 'received_qty', got + rq, 'remaining', left_qty - rq);
  end if;
  update public.stock_transfers set status = 'received', received_qty = got + rq, receive_note = left(p_note, 200), received_by = auth.uid(), received_staff = sid, received_at = now() where id = t.id;
  if got + rq < t.qty then
    perform public._stock_exc(t.to_location_id, 'transit_short', 'yellow',
      it.name_bn || ': পাঠানো ' || t.qty::text || ', গ্রহণ ' || (got + rq)::text || ' — পথে কম', coalesce(it.name_en, it.name_bn) || ': sent ' || t.qty::text || ', received ' || (got + rq)::text || ' — short in transit');
  end if;
  if t.qty - got - rq > 0 and coalesce(public.rule_txt('transit_short_mode'), 'keep_in_transit') = 'loss' then      -- bos83: the owner chose to book the shortfall as a loss (shortfall counted after earlier partial receipts)
    perform public._transit_loss83(t.id, t.qty - got - rq, p_note);
  end if;
  return jsonb_build_object('id', t.id, 'status', 'received', 'received_qty', got + rq, 'short', t.qty - got - rq);
end $function$$r0_0$, null),
  ('public.stock_receive_transfer(uuid,numeric,text)', 'known', '24c310ed8a630b1753efa4a047e2d5de', null),
  ('public.stock_receive_transfer(uuid,numeric,text)', 'known', '81118bd620e74142e39274c833cfa284', null),
  ('public.stock_receive_transfer(uuid,numeric,text)', 'known', 'e1e47c4f94c94390d19e18abec8494fd', null),
  ('public.stock_receive_transfer(uuid,numeric,text)', 'old', $o0_0$  end if;
  return jsonb_build_object('id', t.id, 'status', 'received', 'received_qty', got + rq, 'short', t.qty - got - rq);$o0_0$, $n0_0$  end if;
  if t.qty - got - rq > 0 and coalesce(public.rule_txt('transit_short_mode'), 'keep_in_transit') = 'loss' then      -- bos83: the owner chose to book the shortfall as a loss (shortfall counted after earlier partial receipts)
    perform public._transit_loss83(t.id, t.qty - got - rq, p_note);
  end if;
  return jsonb_build_object('id', t.id, 'status', 'received', 'received_qty', got + rq, 'short', t.qty - got - rq);$n0_0$);
-- stock_reconcile(boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.stock_reconcile(boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.stock_reconcile(p_fix boolean DEFAULT false)
 RETURNS TABLE(item_id uuid, location_id integer, ledger_qty numeric, cached_qty numeric, qty_diff numeric, cached_avg numeric, replay_avg numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare r record; l record; q numeric; a numeric; bq numeric; bavg numeric; n int := 0; sid text; log_ jsonb := '[]'::jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select p.staff_id into sid from public.profiles p where p.id = auth.uid();                                  -- bos84
  for r in
    select k.iid, k.lid from (select x.item_id iid, x.location_id lid from public.stock_ledger x group by 1, 2
                              union select y.item_id, y.location_id from public.stock_balance y) k order by 1, 2 loop
    if p_fix then
      insert into public.stock_balance (item_id, location_id) values (r.iid, r.lid) on conflict do nothing;
      perform 1 from public.stock_balance z where z.item_id = r.iid and z.location_id = r.lid for update;     -- nobody can post to this pair until we are done
    end if;
    select z.qty, z.avg_cost into bq, bavg from public.stock_balance z where z.item_id = r.iid and z.location_id = r.lid;
    bq := coalesce(bq, 0);
    q := 0; a := null;
    for l in select x.qty_delta, x.unit_cost, x.reason from public.stock_ledger x where x.item_id = r.iid and x.location_id = r.lid order by x.id loop
      a := public._avg_next(q, a, l.qty_delta, l.unit_cost, l.reason); q := q + l.qty_delta;
    end loop;
    if q <> bq or bavg is distinct from a then
      item_id := r.iid; location_id := r.lid; ledger_qty := q; cached_qty := bq; qty_diff := bq - q; cached_avg := bavg; replay_avg := a;
      if p_fix then
        perform set_config('bos.audit_skip84', '1', true);                                                    -- bos84 (this function writes its own, single row)
        update public.stock_balance z set qty = q, avg_cost = a, updated_at = now() where z.item_id = r.iid and z.location_id = r.lid;
        n := n + 1; if n <= 50 then log_ := log_ || jsonb_build_array(jsonb_build_object('item_id', r.iid, 'location_id', r.lid, 'old_qty', bq, 'new_qty', q, 'old_avg', bavg, 'new_avg', a)); end if;   -- bos420
        perform set_config('bos.audit_skip84', '', true);                                                     -- bos84
        insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)               -- bos84
          values (auth.uid(), sid, 'reconcile_fix', 'stock_balance', r.iid::text || ':' || r.lid::text,
                  jsonb_build_object('old', jsonb_build_object('qty', bq, 'avg_cost', bavg), 'new', jsonb_build_object('qty', q, 'avg_cost', a),
                                     'source', 'stock_reconcile', 'src', 'phase84'));                          -- bos84
      end if;
      return next;
    end if;
  end loop;
  if p_fix and n > 0 then                                                                                                   -- bos420: the cache was rewritten, say who and what
    select p.staff_id into sid from public.profiles p where p.id = auth.uid();
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), sid, 'stock_reconcile_fix', 'stock_balance', null, jsonb_build_object('rows_fixed', n, 'confirmed', coalesce(current_setting('bos.reconcile_confirm', true), '') = 'yes', 'first_rows', log_));
  end if;
end $function$$r0_0$, null),
  ('public.stock_reconcile(boolean)', 'known', '493eac1f54ca49daf250160bc220ecbb', null),
  ('public.stock_reconcile(boolean)', 'known', 'a3c49535852e3e2db835a74dcee58a2d', null),
  ('public.stock_reconcile(boolean)', 'known', 'cbcb93c7f000f71974e4e86cf4162ded', null),
  ('public.stock_reconcile(boolean)', 'old', $o0_0$  if not public.is_owner() then raise exception 'not allowed'; end if;
  for r in$o0_0$, $n0_0$  if not public.is_owner() then raise exception 'not allowed'; end if;
  select p.staff_id into sid from public.profiles p where p.id = auth.uid();                                  -- bos84
  for r in$n0_0$),
  ('public.stock_reconcile(boolean)', 'old', $o1_0$      if p_fix then
        update public.stock_balance z set qty = q, avg_cost = a, updated_at = now() where z.item_id = r.iid and z.location_id = r.lid;
        n := n + 1; if n <= 50 then log_ := log_ || jsonb_build_array(jsonb_build_object('item_id', r.iid, 'location_id', r.lid, 'old_qty', bq, 'new_qty', q, 'old_avg', bavg, 'new_avg', a)); end if;   -- bos420
      end if;$o1_0$, $n1_0$      if p_fix then
        perform set_config('bos.audit_skip84', '1', true);                                                    -- bos84 (this function writes its own, single row)
        update public.stock_balance z set qty = q, avg_cost = a, updated_at = now() where z.item_id = r.iid and z.location_id = r.lid;
        n := n + 1; if n <= 50 then log_ := log_ || jsonb_build_array(jsonb_build_object('item_id', r.iid, 'location_id', r.lid, 'old_qty', bq, 'new_qty', q, 'old_avg', bavg, 'new_avg', a)); end if;   -- bos420
        perform set_config('bos.audit_skip84', '', true);                                                     -- bos84
        insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)               -- bos84
          values (auth.uid(), sid, 'reconcile_fix', 'stock_balance', r.iid::text || ':' || r.lid::text,
                  jsonb_build_object('old', jsonb_build_object('qty', bq, 'avg_cost', bavg), 'new', jsonb_build_object('qty', q, 'avg_cost', a),
                                     'source', 'stock_reconcile', 'src', 'phase84'));                          -- bos84
      end if;$n1_0$);
-- stock_transfer(integer,integer,uuid,numeric,text,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.stock_transfer(integer,integer,uuid,numeric,text,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.stock_transfer(p_from integer, p_to integer, p_item uuid, p_qty numeric, p_unit text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items; bq numeric; tid uuid := gen_random_uuid(); sid text; t public.stock_transfers; lid bigint;
begin
  it := public._stock_guard(p_item, p_from, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into t from public.stock_transfers where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
  end if;
  if p_to is null or p_to = p_from or not exists (select 1 from public.locations where id = p_to) then raise exception 'bad_location'; end if;
  if public.rule_on('transfer_paused_block') and coalesce((select l.status from public.locations l where l.id = p_to), '') <> 'live' then
    raise exception 'destination_paused';
  end if;
  if p_qty is null or not (p_qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not (bq between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if not public._may('stock_transfer', p_from, 'transfer:' || p_item::text, bq) then raise exception 'not allowed'; end if;
  if public.rule_on('transfer_overdraw_block') and coalesce((select sb.qty from public.stock_balance sb where sb.item_id = p_item and sb.location_id = p_from), 0) < bq then
    raise exception 'insufficient_stock';
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  begin
    insert into public.stock_transfers (id, client_id, from_location_id, to_location_id, item_id, qty, note, sent_by, sent_staff)
      values (tid, p_client, p_from, p_to, p_item, bq, left(p_note, 200), auth.uid(), sid);
  exception when unique_violation then          -- the same client id arrived twice at once: the first one wins
    select * into t from public.stock_transfers where p_client is not null and client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
    raise;
  end;
  if public.rule_on('transfer_needs_stock') then   -- bos114:xfer-stock (the balance row is locked, so two phones cannot both pass)
    insert into public.stock_balance (item_id, location_id) values (p_item, p_from) on conflict do nothing;
    perform 1 from public.stock_balance b where b.item_id = p_item and b.location_id = p_from for update;
    if coalesce((select b.qty from public.stock_balance b where b.item_id = p_item and b.location_id = p_from), 0) < bq
       and not (public.has_grant('sell_below_zero', p_from) or public._use_em('sell_below_zero', p_from, 'transfer:' || tid::text, null)) then
      raise exception 'insufficient_stock' using detail = coalesce(it.code, '') || ' ' || coalesce(it.name_bn, ''), hint = 'on hand ' || coalesce((select b.qty from public.stock_balance b where b.item_id = p_item and b.location_id = p_from), 0)::text;
    end if;
  end if;
  lid := public.stock_post(p_item, p_from, -bq, 'transfer_out', 'transfer', tid::text, null, null, now(), left(p_note, 200), null, 'full');
  if public.rule_on('transfer_notify_receiver') then   -- bos115:xfer-notify
    perform public._notif_add('transfer_sent', 'info', 'মাল পথে: ' || coalesce(it.name_bn, ''), 'Goods on the way: ' || coalesce(it.name_en, it.name_bn, ''),
      'পরিমাণ ' || trim_scale(bq)::text || ' — গ্রহণ করতে স্টক পাতার "পথে" ট্যাব দেখুন।', 'Quantity ' || trim_scale(bq)::text || ' — open the Stock page, tab "In transit", to receive.', 'stock', tid::text, 'manager', p_to);
  end if;
  return jsonb_build_object('id', tid, 'status', 'sent', 'qty', bq);
end $function$$r0_0$, null),
  ('public.stock_transfer(integer,integer,uuid,numeric,text,text,uuid)', 'known', '36ef875eee267f280ec4b9c29dfa7250', null),
  ('public.stock_transfer(integer,integer,uuid,numeric,text,text,uuid)', 'known', '5ffe72be40375c722d7b753d4e7f7533', null),
  ('public.stock_transfer(integer,integer,uuid,numeric,text,text,uuid)', 'known', 'ae3bb09a26d249c2c2e094d503cbcef3', null),
  ('public.stock_transfer(integer,integer,uuid,numeric,text,text,uuid)', 'old', $o0_0$  end;
  lid := public.stock_post(p_item, p_from, -bq, 'transfer_out', 'transfer', tid::text, null, null, now(), left(p_note, 200), null, 'full');
  return jsonb_build_object('id', tid, 'status', 'sent', 'qty', bq);$o0_0$, $n0_0$  end;
  if public.rule_on('transfer_needs_stock') then   -- bos114:xfer-stock (the balance row is locked, so two phones cannot both pass)
    insert into public.stock_balance (item_id, location_id) values (p_item, p_from) on conflict do nothing;
    perform 1 from public.stock_balance b where b.item_id = p_item and b.location_id = p_from for update;
    if coalesce((select b.qty from public.stock_balance b where b.item_id = p_item and b.location_id = p_from), 0) < bq
       and not (public.has_grant('sell_below_zero', p_from) or public._use_em('sell_below_zero', p_from, 'transfer:' || tid::text, null)) then
      raise exception 'insufficient_stock' using detail = coalesce(it.code, '') || ' ' || coalesce(it.name_bn, ''), hint = 'on hand ' || coalesce((select b.qty from public.stock_balance b where b.item_id = p_item and b.location_id = p_from), 0)::text;
    end if;
  end if;
  lid := public.stock_post(p_item, p_from, -bq, 'transfer_out', 'transfer', tid::text, null, null, now(), left(p_note, 200), null, 'full');
  if public.rule_on('transfer_notify_receiver') then   -- bos115:xfer-notify
    perform public._notif_add('transfer_sent', 'info', 'মাল পথে: ' || coalesce(it.name_bn, ''), 'Goods on the way: ' || coalesce(it.name_en, it.name_bn, ''),
      'পরিমাণ ' || trim_scale(bq)::text || ' — গ্রহণ করতে স্টক পাতার "পথে" ট্যাব দেখুন।', 'Quantity ' || trim_scale(bq)::text || ' — open the Stock page, tab "In transit", to receive.', 'stock', tid::text, 'manager', p_to);
  end if;
  return jsonb_build_object('id', tid, 'status', 'sent', 'qty', bq);$n0_0$);
-- _recipe_lines_ok(uuid,jsonb)
insert into _u_plan (fn, kind, a, b) values
  ('public._recipe_lines_ok(uuid,jsonb)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._recipe_lines_ok(p_item uuid, p_lines jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ln jsonb; ing public.items; q numeric; w numeric; seen uuid[] := '{}'; iid uuid;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  if jsonb_array_length(p_lines) > 100 then raise exception 'too_many_lines'; end if;
  for ln in select x from jsonb_array_elements(p_lines) x loop
    iid := nullif(ln->>'ingredient_item_id', '')::uuid;
    select * into ing from public.items where id = iid and public._m132_own(items.org_unit_id) /* m132b:items */;
    if not found then raise exception 'item_not_found'; end if;
    if iid = p_item then raise exception 'ingredient_is_product'; end if;
    if ing.item_type not in ('raw_material', 'packaging', 'resale') then
      -- a made product (finished good) may be an ingredient only behind a switch: phase 504 recipe_intermediate_on (navstack line) or bos116 semi_finished_ingredient116 (advanced line); never in a loop
      if not (ing.item_type = 'finished_good' and (public.rule_on('recipe_intermediate_on') or public.rule_on('semi_finished_ingredient116'))) then raise exception 'bad_ingredient_type' using detail = ing.code; end if;
      if public.rule_on('recipe_intermediate_on') and public._recipe_reaches(iid, p_item) then raise exception 'recipe_loop' using detail = ing.code; end if;   -- phase 504
      if public.rule_on('semi_finished_ingredient116') and public._recipe_reaches116(iid, p_item) then raise exception 'recipe_cycle' using detail = ing.code; end if;   -- bos116
    end if;
    if iid = any(seen) then raise exception 'dup_ingredient'; end if;
    seen := seen || iid;
    q := nullif(ln->>'qty', '')::numeric;
    if q is null or not (q > 0 and q < 1000000000) then raise exception 'bad_qty'; end if;
    w := nullif(ln->>'waste_pct', '')::numeric;
    if w is not null and not (w between 0 and 100) then raise exception 'bad_waste'; end if;
    if public._base_qty(iid, q, nullif(btrim(ln->>'unit'), '')) is null then raise exception 'unit_unknown' using detail = ing.code; end if;
  end loop;
end $function$$r0_0$, null),
  ('public._recipe_lines_ok(uuid,jsonb)', 'known', '5cebadbf52950d50546715a034c3f7a2', null),
  ('public._recipe_lines_ok(uuid,jsonb)', 'known', 'dfa3141d8708ae0dafea55bb9ce7b690', null),
  ('public._recipe_lines_ok(uuid,jsonb)', 'known', 'fe83e9b62649c3d38e780399c6d72219', null),
  ('public._recipe_lines_ok(uuid,jsonb)', 'old', $o0_0$    iid := nullif(ln->>'ingredient_item_id', '')::uuid;
    select * into ing from public.items where id = iid;
    if not found then raise exception 'item_not_found'; end if;$o0_0$, $n0_0$    iid := nullif(ln->>'ingredient_item_id', '')::uuid;
    select * into ing from public.items where id = iid and public._m132_own(items.org_unit_id) /* m132b:items */;
    if not found then raise exception 'item_not_found'; end if;$n0_0$),
  ('public._recipe_lines_ok(uuid,jsonb)', 'old', $o1_0$    if ing.item_type not in ('raw_material', 'packaging', 'resale') then
      -- phase 504: a made product (finished good) may be an ingredient only when recipe_intermediate_on is on, and never in a loop
      if not (ing.item_type = 'finished_good' and public.rule_on('recipe_intermediate_on')) then raise exception 'bad_ingredient_type' using detail = ing.code; end if;
      if public._recipe_reaches(iid, p_item) then raise exception 'recipe_loop' using detail = ing.code; end if;
    end if;$o1_0$, $n1_0$    if ing.item_type not in ('raw_material', 'packaging', 'resale') then
      -- a made product (finished good) may be an ingredient only behind a switch: phase 504 recipe_intermediate_on (navstack line) or bos116 semi_finished_ingredient116 (advanced line); never in a loop
      if not (ing.item_type = 'finished_good' and (public.rule_on('recipe_intermediate_on') or public.rule_on('semi_finished_ingredient116'))) then raise exception 'bad_ingredient_type' using detail = ing.code; end if;
      if public.rule_on('recipe_intermediate_on') and public._recipe_reaches(iid, p_item) then raise exception 'recipe_loop' using detail = ing.code; end if;   -- phase 504
      if public.rule_on('semi_finished_ingredient116') and public._recipe_reaches116(iid, p_item) then raise exception 'recipe_cycle' using detail = ing.code; end if;   -- bos116
    end if;$n1_0$);
do $u533$
declare f record; r record; cur text; body text; rbody text; miss text := ''; st text; nfix int := 0; ok boolean;
begin
  -- Every function of this file is looked at first. A function is in one of these states: DONE (already the merged text), KNOWN (a known older text of one of the two lines: it is replaced by the
  -- merged text), PATCH (not a known text, but every patch site of the fallback is found), MISSING (nothing fits). ALL missing ones are listed in ONE message and nothing is changed.
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then continue; end if;     -- the function does not exist yet: it is created below
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then continue; end if;
    ok := exists (select 1 from _u_plan where fn = f.fn and kind = 'old');
    body := cur;
    for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
      if position(r.b in body) > 0 then continue; end if;
      if position(r.a in body) = 0 then ok := false; exit; end if;
      body := overlay(body placing r.b from position(r.a in body) for length(r.a));
    end loop;
    if not ok then miss := miss || E'\n  ' || f.fn || ' (the text in this database is not one of the known texts and the patch sites are not all there; md5 ' || md5(cur) || ')'; end if;
  end loop;
  if miss <> '' then raise exception 'phase533: these functions have an unknown text, nothing was changed. Send this message to the agent:%', miss; end if;
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then
      execute rbody; nfix := nfix + 1; continue;
    end if;
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    insert into public._union_fn_backup (fn, why, def) values (f.fn, 'phase533: merged text of the two lines', cur);
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then
      execute rbody;
    else
      body := cur;
      for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
        if position(r.b in body) > 0 then continue; end if;
        body := overlay(body placing r.b from position(r.a in body) for length(r.a));
      end loop;
      execute body;
    end if;
    nfix := nfix + 1;
  end loop;
  raise notice 'phase533: % function(s) changed', nfix;
end $u533$;
drop table if exists _u_plan;
