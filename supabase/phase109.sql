-- ============================================================
-- Phase 109 (bos109) - STEP Conc: fixes for the concurrency findings F1, F2, F4, F5, F6 of tests/sql/concurrency/CONCURRENCY_REPORT.md. Run AFTER phase103 (docs/PASTE_ORDER.md; 104..108 are reserved by other steps, this file does not need them).
--   Needs phases 72..103 pasted first (guard below). F3 (inbox_unmask) is NOT here: it is fixed by the security step (phase105).
--   Additive, paste-twice safe: every function is re-created from its LATEST body (taken from a build of docs/PASTE_ORDER.md incl. phase103); only lines tagged bos109 differ, every older bosNN tag is kept.
--   No table, column, trigger or privilege of an existing object is changed. One new rule (default OFF = today), one advisor row. Each create runs only if both guards passed (session flag phase109.ok).
--   F1 (high)  production_post: with the default rules (stock_negative_mode warn, production_short_mode refuse) N cooks on the same raw material all passed the shortage check and the balance went negative.
--              The balances of all ingredients / packaging AND the finished good are now row-locked in one item order before the check (select ... order by item_id for update).
--   F2 (high)  scan_confirm(p_post => true) saves a bill (foreign key = FOR KEY SHARE on the supplier row) and posts it in the same transaction (FOR UPDATE on the same row): two bills of one supplier deadlocked.
--              The supplier lock is now FOR NO KEY UPDATE in all 7 places that take it (post / void purchase, bill payment, pay / void supplier payment, supplier refund / void): it still excludes the other
--              posters (it conflicts with itself) but not the key-share lock of an insert.
--   F4 (med)   set_option_view_bulk / set_role_option_view_bulk upsert the keys sorted (by key, then by position): two owners sending the same keys in opposite order no longer deadlock.
--   F5 (low)   setup_recommend_apply: one apply at a time (transaction advisory lock after the client lock): a second tap with another client id sees the rules already set ('already'); each changed rule is applied and audited once.
--   F6 (med)   card_settle: NO change of behaviour by default. New rule card_settle_over_mode off | warn | refuse (default off). warn = the settlement is saved and a yellow exception 'card_settle_over' is logged when
--              gross > unsettled receivable (GL balance minus settlements saved but not yet booked); refuse = error over_settlement. Per-place advisory lock while the check is on. Advisor row recommends warn.
-- Tag: bos109.
-- ============================================================

do $g$ begin perform set_config('phase109.ok', 'off', false); end $g$;
do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.get_doc_templates(integer)'), ('94', 'public._intake_proof_ok94(text,text)'),
    ('95', 'public.drawer_settings(integer)'), ('96', 'public._cw_docs96()'), ('97', 'public._landed_jlines97(uuid,text)'),
    ('99', 'public._inb_pii_f99(text,text)'), ('103', 'public._rec_value103(text,jsonb)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regprocedure('public._acct_docs(date)') is null then miss := miss || ' 98'; end if;
  if to_regclass('public.item_categories') is null then miss := miss || ' 100'; end if;
  if to_regclass('public.setup_rec_defs81') is null or not exists (select 1 from public.setup_rec_defs81 where code = 'purchase_grn_guard' and phase = '82') then miss := miss || ' 101'; end if;
  if miss <> '' then
    raise exception 'phase109 needs phases 72..103 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
  perform set_config('phase109.ok', 'guard1', false);
end $g$;

-- BODY GUARD: a live body with a tag this file does not know (a newer phase, e.g. 104..108) is never overwritten: build a newer merge instead
do $g$
declare d text; t text[]; r record;
begin
  if current_setting('phase109.ok', true) is distinct from 'guard1' then return; end if;
  for r in select * from (values    ('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)', array['bos72', 'bos73', 'bos74', 'bos80', 'bos109']::text[]),
    ('public._post_purchase_p13(uuid,jsonb)', array['bos82', 'bos87', 'bos109']::text[]),
    ('public._void_purchase_p13(uuid,text)', array['bos82', 'bos109']::text[]),
    ('public._bp_pay99(text,text,text,numeric,text,uuid,text,boolean)', array['bos105', 'bos109', 'bos111']::text[]),   -- bos105 = phase105 (L4 client_id_reused); that body is NOT overwritten here, phase111 re-asserts the merge (105 + 109)
    ('public.pay_supplier(uuid,integer,jsonb,uuid,text)', array['bos109']::text[]),
    ('public.void_supplier_payment(bigint,text)', array['bos109']::text[]),
    ('public.supplier_refund(uuid,integer,numeric,text,text,text,text,text,uuid)', array['bos109']::text[]),
    ('public.void_supplier_refund(bigint,text)', array['bos109']::text[]),
    ('public.set_option_view_bulk(uuid,jsonb,uuid)', array['bos109']::text[]),
    ('public.set_role_option_view_bulk(text,jsonb,uuid)', array['bos109']::text[]),
    ('public.setup_recommend_apply(uuid,text[],boolean,boolean)', array['bos103', 'bos109']::text[]),
    ('public.card_settle(integer,date,numeric,numeric,text,uuid,text)', array['bos109']::text[])) v(sig, known)
  loop
    d := pg_get_functiondef(r.sig::regprocedure);
    select array_agg(distinct x[1]) into t from regexp_matches(d, 'bos[0-9]+', 'g') x;
    if t is not null and not (t <@ r.known) then
      raise exception 'phase109: % carries tags this file does not know (%); build a newer merge instead of overwriting it', r.sig, t;
    end if;
  end loop;
  perform set_config('phase109.ok', 'on', false);
end $g$;
-- the statements below run only when both guards passed

-- ---------- F6: new rule (default OFF = today's behaviour) + advisor row (recommends warn) ----------
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('card_settle_over_mode', 'books', 'choice', '"off"', null, '["off","warn","refuse"]'::jsonb, null, null,
  'Card settlement larger than the unsettled card receivable: off / warn / refuse', 'Card settlement larger than the unsettled card receivable: off / warn / refuse', 'Card settlement larger than the unsettled card receivable: off, warn or refuse',
  'off = as before (the settlement is saved and only the over flag in the answer shows it, counted on the booked balance). warn = saved, and a yellow exception is logged when it is more than the unsettled receivable, counting settlements saved but not yet booked. refuse = such a settlement is rejected with over_settlement.',
  'off = as before (the settlement is saved and only the over flag in the answer shows it, counted on the booked balance). warn = saved, and a yellow exception is logged when it is more than the unsettled receivable, counting settlements saved but not yet booked. refuse = such a settlement is rejected with over_settlement.', 980)
on conflict (key) do nothing;
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('card_settle_over_mode', 'card_settle_over_mode', '109', 'books', '"warn"', '{}'::text[],
  'Settling more than the card receivable still open makes the card account negative. With warn the settlement is saved and a yellow exception tells the owner; switch to refuse once the card settlements are routine. Nothing is blocked while warn is on.',
  'Settling more than the card receivable still open makes the card account negative. With warn the settlement is saved and a yellow exception tells the owner; switch to refuse once the card settlements are routine. Nothing is blocked while warn is on.',
  'Settling more than the card receivable still open makes the card account negative. With warn the settlement is saved and a yellow exception tells the owner; switch to refuse once the card settlements are routine. Nothing is blocked while warn is on.', 350)
on conflict do nothing;
end if; end $p109$;

-- public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.production_post(p_loc integer, p_recipe uuid, p_batches numeric, p_client uuid, p_made_at timestamp with time zone, p_note text, p_actual_yield numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes; it public.items; at_ timestamptz := coalesce(p_made_at, now()); run public.production_runs; n record; rid uuid := gen_random_uuid();
        mode text; neg text; yb numeric; f numeric; sl jsonb; exp timestamptz; bid bigint; lin bigint; lid bigint; tot numeric := 0; cost_ok boolean := true; av numeric; wm int := 0;
        shorts text := ''; nocost text := ''; used jsonb := '[]'::jsonb; ucb numeric; derived uuid; gate text;
        outq numeric; conv jsonb; conv_amt numeric := 0; cinc boolean; yvp numeric; ythr numeric;   -- bos74
begin
  if at_ is null or at_ = 'infinity'::timestamptz or at_ = '-infinity'::timestamptz then raise exception 'bad_date'; end if;
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  it := public._stock_guard(r.item_id, p_loc, 'stock_production', (at_ at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into run from public.production_runs where client_id = p_client;
    if found then
      if run.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'run_id', run.id, 'ledger_id', run.ledger_in_id, 'batch_id', run.batch_id, 'qty', run.yield_base);
    end if;
  end if;
  if not r.active then raise exception 'recipe_inactive'; end if;
  gate := public._recipe_gate73(r.id);      -- bos73: on = refuse an unapproved recipe; warn = a yellow line below
  if p_batches is null or not (p_batches between 0.0001 and 100000) then raise exception 'bad_qty'; end if;
  if at_ > now() + interval '10 minutes' then raise exception 'bad_date'; end if;
  if not exists (select 1 from public.recipe_lines where recipe_id = r.id and active) then raise exception 'no_lines'; end if;
  f := public._base_qty(r.item_id, r.yield_qty, r.yield_unit);
  if f is null or not (f > 0) then raise exception 'unit_unknown'; end if;
  yb := round(f * p_batches, 4);
  if not (yb between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if p_actual_yield is not null and not (round(p_actual_yield, 4) between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;      -- bos74
  outq := case when p_actual_yield is null then yb else round(p_actual_yield, 4) end;      -- bos74: what is really booked into stock
  -- everything that leaves the stock: checks first, nothing is posted until all are fine
  for n in select * from public._recipe_need(r.id, p_batches, p_loc) loop
    if not n.tracked then raise exception 'ingredient_not_tracked' using detail = coalesce(n.code, ''); end if;
    if not n.unit_ok then raise exception 'unit_unknown' using detail = coalesce(n.code, ''); end if;
    if n.waste_missing then wm := wm + 1; end if;
  end loop;
  if wm > 0 and public.rule_on('recipe_waste_required') then raise exception 'waste_needed'; end if;
  mode := coalesce(public.rule_txt('production_short_mode'), 'refuse');
  -- bos109: lock every ingredient / packaging balance AND the finished-good balance of this place in ONE item order BEFORE the shortage check, so two cooks (or a cook and a sale)
  -- cannot both pass the check on the same stock, and the later stock_post calls never take a lock in another order (no lock-order deadlock between recipes)
  perform 1 from public.stock_balance sbl where sbl.location_id = p_loc and (sbl.item_id = r.item_id or sbl.item_id in (select n2.item_id from public._recipe_need(r.id, p_batches, p_loc) n2)) order by sbl.item_id for update;   -- bos109
  if mode = 'refuse' and coalesce(public.rule_txt('stock_negative_mode'), 'warn') <> 'allow' and not public.has_grant('sell_below_zero', p_loc) then
    for n in select * from public._recipe_need(r.id, p_batches, p_loc) where need > on_hand order by code loop
      shorts := shorts || case when shorts = '' then '' else '; ' end || coalesce(n.code, '') || ' ' || coalesce(n.name_bn, '') || ' (' || round(n.on_hand, 4)::text || ' / ' || n.need::text || ')';
    end loop;
    if shorts <> '' then raise exception 'insufficient_stock' using detail = shorts, hint = 'production'; end if;
  end if;
  -- bos72: rule production_requires_cost = refuse: no ingredient may have an unknown (NULL or 0) cost (default warn = today's behaviour)
  if coalesce(public.rule_txt('production_requires_cost'), 'warn') = 'refuse' then
    for n in select * from public._recipe_need(r.id, p_batches, p_loc) order by code loop
      if n.need >= 0.0001 and coalesce((select b.avg_cost from public.stock_balance b where b.item_id = n.item_id and b.location_id = p_loc), 0) <= 0
         and not public._cost_free80(n.item_id) then      -- bos80: an item marked 'cost really zero' is a known cost
        nocost := nocost || case when nocost = '' then '' else '; ' end || coalesce(n.code, '') || ' ' || coalesce(n.name_bn, '');
      end if;
    end loop;
    if nocost <> '' then raise exception 'cost_missing' using detail = nocost, hint = 'production'; end if;
  end if;
  if not public._may('stock_production', p_loc, 'production:' || r.item_id::text, yb) then raise exception 'not allowed'; end if;
  insert into public.production_runs (id, client_id, location_id, recipe_id, item_id, batches, made_at, yield_base, waste_missing, note, created_by)
    values (rid, p_client, p_loc, r.id, r.item_id, p_batches, at_, outq, wm, left(p_note, 200), auth.uid());      -- bos74: yield_base = the quantity really booked
  -- ingredient (and packaging) OUT at the weighted average cost, fixed item order so two productions can never wait on each other in a circle
  for n in select * from public._recipe_need(r.id, p_batches, p_loc) order by item_id loop
    if n.need < 0.0001 then continue; end if;
    select avg_cost into av from public.stock_balance where item_id = n.item_id and location_id = p_loc;
    if coalesce(av, 0) <= 0 and not public._cost_free80(n.item_id) then cost_ok := false; else tot := tot + n.need * coalesce(av, 0); end if;   -- bos72: cost 0 = unknown; bos80: unless the item is marked 'cost really zero'
    derived := md5(coalesce(p_client::text, rid::text) || ':' || n.item_id::text)::uuid;
    lin := public.stock_post(n.item_id, p_loc, -n.need, 'issue_out', 'production', rid::text, null, null, at_, left(p_note, 200), null, 'full', null, derived);
    used := used || jsonb_build_object('item_id', n.item_id, 'kind', n.kind, 'qty', n.need);
  end loop;
  -- bos74: conversion cost (layer 2) of this run: off = nothing (today's behaviour); recipe = the recipe's rates; pool = monthly pool / NORMAL output
  conv := public._conv_cost(r.id, p_loc, p_batches, outq, (at_ at time zone 'Asia/Dhaka')::date);
  conv_amt := coalesce((conv->>'amount')::numeric, 0); cinc := (conv->>'mode') <> 'off' and not (conv->>'complete')::boolean;
  -- finished good IN: batch + expiry from the owner's shelf-life rules (no rule = no expiry); the cost is material + conversion when every ingredient has a known cost
  sl := public.shelf_life_for(r.item_id, (at_ at time zone 'Asia/Dhaka')::date);
  exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
  insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
    values (r.item_id, p_loc, at_, outq, outq, exp, sl, left(p_note, 200), auth.uid()) returning id into bid;
  ucb := case when cost_ok and outq > 0 then round((tot + conv_amt) / outq, 6) end;      -- bos74: (material + conversion) / actual output
  derived := md5(coalesce(p_client::text, rid::text) || ':in')::uuid;
  lid := public.stock_post(r.item_id, p_loc, outq, 'production_in', 'production', rid::text, ucb, bid, at_, left(p_note, 200), null, 'none', null, derived);
  yvp := case when p_actual_yield is not null and yb > 0 then round((outq - yb) / yb * 100, 2) end;
  update public.production_runs set ledger_in_id = lid, batch_id = bid, cost_complete = cost_ok,
      material_cost = case when cost_ok then round(tot, 4) end, conversion_cost = round(conv_amt, 4), unit_cost = ucb,
      std_cost = case when cost_ok and yb > 0 then round((tot + conv_amt) / yb, 6) end, actual_cost = ucb,
      conversion_mode = conv->>'mode', conversion_complete = not cinc, conversion_detail = conv->'detail', yield_std = yb, yield_actual = p_actual_yield, yield_var_pct = yvp where id = rid;   -- bos74
  update public.recipes set used_at = coalesce(used_at, now()) where id = r.id;
  if wm > 0 then
    perform public._stock_exc(p_loc, 'recipe_waste_missing', 'yellow', it.name_bn || ': রেসিপিতে অপচয় % বসানো নেই — ০ ধরা হয়েছে (' || wm::text || ' লাইন)',
      coalesce(it.name_en, it.name_bn) || ': the recipe has no waste % on ' || wm::text || ' line(s) — counted as 0', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  if gate = 'warn' then      -- bos73
    perform public._stock_exc(p_loc, 'recipe_not_approved', 'yellow', it.name_bn || ': রেসিপি (ভার্সন ' || r.version::text || ') অনুমোদিত নয়',
      coalesce(it.name_en, it.name_bn) || ': recipe version ' || r.version::text || ' is not approved', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  if cinc then      -- bos74
    perform public._stock_exc(p_loc, 'conversion_incomplete', 'yellow', it.name_bn || ': রূপান্তর খরচ অসম্পূর্ণ (খালি ঘর আছে) — যা জানা ছিল শুধু তা ধরা হয়েছে',
      coalesce(it.name_en, it.name_bn) || ': conversion cost incomplete (blank amounts) — only the known part was booked', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  ythr := public.rule_num('yield_variance_warn_pct');      -- bos74
  if yvp is not null and ythr is not null and abs(yvp) > ythr then
    perform public._stock_exc(p_loc, 'yield_variance', 'yellow', it.name_bn || ': আসল উৎপাদন রেসিপির ফলন থেকে ' || yvp::text || '% আলাদা',
      coalesce(it.name_en, it.name_bn) || ': actual yield differs from the recipe yield by ' || yvp::text || '%', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  return jsonb_build_object('run_id', rid, 'ledger_id', lid, 'batch_id', bid, 'qty', outq, 'expires_at', exp, 'consumed', used, 'waste_missing', wm) ||
    case when public._cost_ok(p_loc) then jsonb_build_object('cost_complete', cost_ok, 'conversion_complete', not cinc, 'unit_cost', ucb) else '{}'::jsonb end;
end $function$
$f$; end if; end $p109$;

-- public._post_purchase_p13(uuid,jsonb)
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._post_purchase_p13(p_id uuid, p_payments jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pb public.purchase_bills; ln record; it public.items; gcode text; f numeric; bq numeric; ucb numeric; net numeric; last_c numeric; pct numeric; sid text;
        pay jsonb; pm text; amt numeric; psum numeric := 0; jumped boolean := false; nm text; lid bigint; av numeric; var numeric := 0; norm jsonb; gm text; skipst boolean := false;   -- bos82
begin
  select * into pb from public.purchase_bills where id = p_id;          -- no lock yet: who is asking comes first
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(pb.location_id) then raise exception 'not allowed for this location'; end if;
  gcode := case pb.kind when 'return' then 'purchase_return' else 'purchase_entry' end;
  if pb.status = 'posted' then          -- a re-sent request: answered only to someone who may see purchases (or who posted it)
    if not (public._pur_ok(pb.location_id) or pb.posted_by = auth.uid()) then raise exception 'not allowed'; end if;
    return jsonb_build_object('id', pb.id, 'status', 'posted', 'total', pb.total, 'dup', true);
  end if;
  if not (public.has_grant(gcode, pb.location_id) or public._use_em(gcode, pb.location_id, 'post_purchase:' || p_id::text, pb.total)) then raise exception 'not allowed'; end if;
  if pb.status <> 'draft' then raise exception 'not_draft'; end if;
  perform 1 from public.suppliers where id = pb.supplier_id for no key update;   -- bos109 (was: for update; the row lock must not conflict with the key-share lock of a bill / payment insert in the same transaction)      -- one posting / payment / void at a time per supplier
  select * into pb from public.purchase_bills where id = p_id for update;
  if pb.status = 'posted' then return jsonb_build_object('id', pb.id, 'status', 'posted', 'total', pb.total, 'dup', true); end if;
  if pb.status <> 'draft' then raise exception 'not_draft'; end if;
  if public.rule_on('purchase_separate_poster') and pb.created_by = auth.uid() and not public.is_owner() then raise exception 'poster_must_differ'; end if;
  perform public.lock_check(pb.bill_date);
  if pb.bill_date is distinct from (now() at time zone 'Asia/Dhaka')::date and coalesce(public.rule_txt('purchase_backdate_flag'), 'off') = 'warn' then   -- bos87 (a4-F11): stock is stamped now(), the journal uses bill_date
    perform public._stock_exc(pb.location_id, 'purchase_backdated', 'yellow', 'বিল ' || coalesce(pb.bill_no, '-') || ': তারিখ ' || pb.bill_date::text || ' (আজ নয়) — stock আজকের সময়ে ঢুকেছে, হিসাবের journal বিলের তারিখে',
      'Bill ' || coalesce(pb.bill_no, '-') || ': dated ' || pb.bill_date::text || ' (not today) — the stock is stamped now, the journal uses the bill date', null, pb.bill_date, 'PURCHASE', pb.total);   -- bos87
  end if;   -- bos87
  if pb.subtotal = 0 and pb.total = 0 and not exists (select 1 from public.purchase_lines where bill_id = pb.id) then raise exception 'no_lines'; end if;
  if pb.kind = 'return' then
    if pb.ref_bill_id is null then
      if not public.is_owner() then raise exception 'return_needs_bill'; end if;
      perform public._stock_exc(pb.location_id, 'purchase_return_unreferenced', 'red', 'বিল ছাড়া ক্রয় ফেরত (বিল ' || coalesce(pb.bill_no, '-') || ')',
        'A purchase return was posted without the original bill (return ' || coalesce(pb.bill_no, '-') || ')', null, pb.bill_date, 'PURCHASE', pb.total);
    else
      perform 1 from public.purchase_bills where id = pb.ref_bill_id for update;
      select coalesce(jsonb_agg(jsonb_build_object('item_id', l.item_id, 'description', l.description, 'qty', l.qty, 'unit', l.unit, 'unit_cost', l.unit_cost)), '[]'::jsonb) into norm
        from public.purchase_lines l where l.bill_id = pb.id;
      if not exists (select 1 from public.purchase_bills where id = pb.ref_bill_id and status = 'posted') then raise exception 'bad_ref_bill'; end if;
      perform public._return_check(pb.ref_bill_id, pb.id, norm, true);
    end if;
  end if;
  pct := public.rule_num('purchase_cost_jump_pct');
  -- bos82: GRN exclusivity. Source = GRN and guard on: the bill keeps money / supplier balance, the GRN holds the stock (no second purchase_in)
  gm := coalesce(public.rule_txt('purchase_grn_guard'), 'off');   -- bos82
  if pb.kind = 'bill' and gm in ('skip', 'link') and coalesce(public.rule_txt('grn_receipt_source'), 'purchase') = 'grn' then   -- bos82
    if gm = 'link' and not exists (select 1 from public.shadow_links x where x.domain = 'grn' and x.shadow_type = 'purchase_bills' and x.shadow_id = pb.id::text and x.state <> 'void') then   -- bos82
      raise exception 'grn_link_required' using detail = 'GRN is the stock source: link this bill to its GRN before posting', hint = 'grn_bill_link';   -- bos82
    end if;   -- bos82
    skipst := true;   -- bos82
  end if;   -- bos82
  net := case when pb.subtotal > 0 then (pb.subtotal - pb.discount) / pb.subtotal else 1 end;         -- the bill discount is spread over the lines
  for ln in select * from public.purchase_lines where bill_id = pb.id order by item_id nulls last, line_no loop
    if ln.item_id is null then continue; end if;
    select * into it from public.items where id = ln.item_id;
    f := public._unit_factor_base(ln.item_id, ln.unit);
    if f is null or f <= 0 then
      if it.tracked then raise exception 'unit_unknown'; end if;
      f := 1;
    end if;
    bq := ln.qty * f; ucb := ln.unit_cost / f;
    update public.purchase_lines set base_qty = bq, unit_cost_base = ucb where id = ln.id;
    -- price jump against the last posted bill of this item (before this one); a return is checked the same way
    if pct is not null then
      select pl.unit_cost_base into last_c from public.purchase_lines pl join public.purchase_bills x on x.id = pl.bill_id
        where pl.item_id = ln.item_id and x.status = 'posted' and x.kind = 'bill' and x.id <> pb.id and pl.unit_cost_base is not null order by x.posted_at desc, pl.id desc limit 1;
      if last_c is not null and last_c > 0 and abs(ucb - last_c) / last_c * 100 > pct and not jumped then
        jumped := true; nm := it.name_bn;
        perform public._stock_exc(pb.location_id, 'purchase_price_jump', 'yellow',
          nm || ': ' || case when pb.kind = 'return' then 'ফেরতের' else 'ক্রয়' end || 'মূল্য আগের চেয়ে ' || round((ucb - last_c) / last_c * 100, 1)::text || '% বদলেছে (বিল ' || coalesce(pb.bill_no, '-') || ')',
          coalesce(it.name_en, nm) || ': ' || case when pb.kind = 'return' then 'return ' else '' end || 'unit cost moved ' || round((ucb - last_c) / last_c * 100, 1)::text || '% from the last purchase (bill ' || coalesce(pb.bill_no, '-') || ')', null, pb.bill_date, 'PURCHASE');
      end if;
    end if;
    if it.tracked and not (skipst and pb.kind = 'bill') then   -- bos82: stock comes from the GRN
      if pb.kind = 'bill' then
        perform public.stock_post(ln.item_id, pb.location_id, bq, 'purchase_in', 'purchase', pb.id::text, round(ucb * net, 6), null, now(), null, null, 'none');
      else
        -- out at the current average cost (cost null = the average); what the supplier credits beyond / below that is the variance of this return
        lid := public.stock_post(ln.item_id, pb.location_id, -bq, 'purchase_return', 'purchase', pb.id::text, null, null, now(), null, null, 'full');
        select unit_cost into av from public.stock_ledger where id = lid;
        var := var + round(bq * (round(ucb * net, 6) - coalesce(av, round(ucb * net, 6))), 2);
      end if;
    end if;
  end loop;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_payments is not null and jsonb_typeof(p_payments) = 'array' and jsonb_array_length(p_payments) > 0 then
    if pb.kind <> 'bill' then raise exception 'no_payment_on_return'; end if;
    if not (public.has_grant('supplier_pay', pb.location_id) or public._use_em('supplier_pay', pb.location_id, 'post_purchase:' || p_id::text, null)) then raise exception 'not allowed'; end if;
    for pay in select * from jsonb_array_elements(p_payments) loop
      pm := pay->>'mode'; amt := nullif(pay->>'amount', '')::numeric;
      if pm is null or pm not in ('cash', 'mobile', 'card', 'bank') then raise exception 'bad_mode'; end if;
      if amt is null or not (amt between 0.01 and 999999999999) or round(amt, 2) <= 0 then raise exception 'bad_amount'; end if;
      amt := round(amt, 2); psum := psum + amt;
      insert into public.supplier_payments (supplier_id, location_id, bill_id, mode, wallet, ref, amount, created_by, created_staff)
        values (pb.supplier_id, pb.location_id, pb.id, pm, left(nullif(pay->>'wallet', ''), 30), left(nullif(pay->>'ref', ''), 60), amt, auth.uid(), sid);
    end loop;
    if psum > pb.total then raise exception 'overpaid'; end if;
  end if;
  update public.purchase_bills set status = 'posted', paid = psum, posted_by = auth.uid(), posted_at = now(), variance = case when pb.kind = 'return' then var end where id = pb.id;
  return jsonb_build_object('id', pb.id, 'status', 'posted', 'total', pb.total, 'paid', psum, 'due', pb.total - psum) || case when skipst then jsonb_build_object('stock_from_grn', true) else '{}'::jsonb end;   -- bos82
end $function$
$f$; end if; end $p109$;

-- public._void_purchase_p13(uuid,text)
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._void_purchase_p13(p_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pb public.purchase_bills; r public.stock_ledger; gmode text; why text; shorts text := ''; kept numeric := 0; z record;   -- bos82
begin
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into pb from public.purchase_bills where id = p_id;          -- no lock yet: who is asking comes first
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(pb.location_id) then raise exception 'not allowed for this location'; end if;
  if pb.status = 'void' then          -- a re-sent request: answered only to someone who may see purchases (or who voided it)
    if not (public._pur_ok(pb.location_id) or pb.void_by = auth.uid()) then raise exception 'not allowed'; end if;
    return jsonb_build_object('id', pb.id, 'status', 'void', 'dup', true);
  end if;
  if pb.status = 'draft' then
    if not (public.has_grant(case pb.kind when 'return' then 'purchase_return' else 'purchase_entry' end, pb.location_id)) then raise exception 'not allowed'; end if;
  elsif not (public.has_grant('purchase_void', pb.location_id) or public._use_em('purchase_void', pb.location_id, 'void_purchase:' || p_id::text, pb.total)) then raise exception 'not allowed';
  end if;
  perform 1 from public.suppliers where id = pb.supplier_id for no key update;   -- bos109 (was: for update; the row lock must not conflict with the key-share lock of a bill / payment insert in the same transaction)      -- one posting / payment / void at a time per supplier
  select * into pb from public.purchase_bills where id = p_id for update;
  if pb.status = 'void' then return jsonb_build_object('id', pb.id, 'status', 'void', 'dup', true); end if;
  if pb.status = 'draft' then
    update public.purchase_bills set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = pb.id;
    return jsonb_build_object('id', pb.id, 'status', 'void');
  end if;
  perform public.lock_check(pb.bill_date);
  -- bos82: a posted bill that others depend on cannot simply disappear (switch purchase_void_guard: off | warn | refuse)
  gmode := coalesce(public.rule_txt('purchase_void_guard'), 'off');   -- bos82
  if gmode <> 'off' and pb.kind = 'bill' then   -- bos82
    if exists (select 1 from public.purchase_bills x where x.ref_bill_id = pb.id and x.kind = 'return' and x.status = 'posted') then why := 'void_has_return';   -- bos82
    elsif exists (select 1 from public.grn_batch_links gl join public.stock_batches b on b.id = gl.batch_id where gl.source_type = 'purchase' and gl.source_id = pb.id and b.qty_remaining > 0) then why := 'void_has_grn_batch';   -- bos82
    else   -- bos82
      for z in select o.item_id, o.location_id, sum(o.qty_delta) q from public.stock_ledger o where o.ref_type = 'purchase' and o.ref_id = pb.id::text and o.reason = 'purchase_in'   -- bos82
               and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id) group by 1, 2 order by 1, 2 loop   -- bos82
        perform 1 from public.stock_balance sb where sb.item_id = z.item_id and sb.location_id = z.location_id for update;   -- bos82
        if coalesce((select sb.qty from public.stock_balance sb where sb.item_id = z.item_id and sb.location_id = z.location_id), 0) - z.q < 0 then   -- bos82
          why := 'void_would_go_negative'; shorts := shorts || case when shorts = '' then '' else ', ' end || coalesce((select code from public.items where id = z.item_id), '?');   -- bos82
        end if;   -- bos82
      end loop;   -- bos82
    end if;   -- bos82
    if why is not null then   -- bos82
      if gmode = 'refuse' then raise exception '%', why using detail = case why when 'void_has_return' then 'A posted purchase return refers to this bill: void the return first' when 'void_has_grn_batch' then 'GRN batches with stock left exist for this bill' else 'Stock used or sold already: voiding would make it negative: ' || shorts end, hint = 'purchase_void_guard'; end if;   -- bos82
      perform public._stock_exc(pb.location_id, 'purchase_void_unsafe', 'red', 'ক্রয় bill বাতিল (ঝুঁকিপূর্ণ): ' || why || ' ' || shorts, 'Purchase bill voided although: ' || why || ' ' || shorts, null, pb.bill_date, 'PURCHASE', pb.total);   -- bos82
    end if;   -- bos82
  end if;   -- bos82
  for r in select * from public.stock_ledger o where o.ref_type = 'purchase' and o.ref_id = pb.id::text and o.reason in ('purchase_in', 'purchase_return')
           and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id) order by o.item_id, o.id loop
    perform public.stock_post(r.item_id, r.location_id, -r.qty_delta, 'reversal', 'purchase', pb.id::text, r.unit_cost, r.batch_id, now(), left('void: ' || btrim(p_note), 200), r.id, 'soft');
  end loop;
  if coalesce(public.rule_txt('purchase_void_payments'), 'void') = 'keep' then   -- bos82: cash really left; the payment stays and becomes supplier credit (use supplier_refund to take the money back)
    select coalesce(sum(amount), 0) into kept from public.supplier_payments where bill_id = pb.id and not voided;   -- bos82
    if kept > 0 then perform public._stock_exc(pb.location_id, 'purchase_void_credit', 'yellow', 'বাতিল bill-এর পরিশোধ রাখা হয়েছে, supplier-এর কাছে credit: ' || kept::text, 'Voided bill payment kept as supplier credit: ' || kept::text, null, pb.bill_date, 'PURCHASE', kept); end if;   -- bos82
  else   -- bos82
  update public.supplier_payments set voided = true, void_note = left(btrim(p_note), 200), void_by = auth.uid() where bill_id = pb.id and not voided;
  end if;   -- bos82
  update public.purchase_bills set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = pb.id;
  perform public._stock_exc(pb.location_id, 'purchase_void', 'yellow', 'ক্রয় বিল বাতিল: ' || left(btrim(p_note), 100), 'A posted purchase was voided: ' || left(btrim(p_note), 100), null, pb.bill_date, 'PURCHASE', pb.total);
  return jsonb_build_object('id', pb.id, 'status', 'void') || case when kept > 0 then jsonb_build_object('payments_kept', kept) else '{}'::jsonb end;   -- bos82
end $function$
$f$; end if; end $p109$;

-- public._bp_pay99(text,text,text,numeric,text,uuid,text,boolean)
-- (INT4) skipped when phase105 is already on it (tag bos105): this text was built before phase105 and would erase the L4 line. phase111 creates the merged body (bos105 + bos109).
do $p109$ begin if current_setting('phase109.ok', true) = 'on' and position('bos105' in pg_get_functiondef('public._bp_pay99(text,text,text,numeric,text,uuid,text,boolean)'::regprocedure)) = 0 then execute $f$
CREATE OR REPLACE FUNCTION public._bp_pay99(p_kind text, p_ref text, p_mode text, p_amount numeric, p_origin text, p_client uuid, p_note text, p_confirm boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cb public.cost_source_bills; cs public.cost_sources; pb public.purchase_bills; q public.quick_expenses; loc int; rem numeric; paid_sum numeric; amt numeric; warns text[];
        sid text; mtype text; mref text; today date := public._bp_today99(); open_amt numeric; bid bigint; ex public.bill_payments99;
begin
  if p_kind not in ('cost', 'purchase') then raise exception 'bad_kind'; end if;
  if p_origin not in ('auto', 'ask') then raise exception 'bad_value'; end if;
  if p_ref is null or (p_kind = 'cost' and p_ref !~ '^[0-9]{1,18}$') or (p_kind = 'purchase' and p_ref !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then raise exception 'bad_ref'; end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into ex from public.bill_payments99 where client_id = p_client;
    if found then return jsonb_build_object('ok', true, 'dup', true, 'id', ex.id, 'amount', ex.amount); end if;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_kind = 'cost' then
    select * into cb from public.cost_source_bills where id = p_ref::bigint for update;
    if not found then raise exception 'not_found'; end if;
    if cb.status <> 'active' then raise exception 'bill_void'; end if;
    select * into cs from public.cost_sources where id = cb.source_id;
    select min(location_id) into loc from public.cost_source_locs where source_id = cb.source_id;
    if loc is null then raise exception 'no_location'; end if;
    if p_mode is null or p_mode not in ('cash', 'bank', 'mobile', 'other') then raise exception 'bad_mode'; end if;
    select coalesce(sum(amount), 0) into paid_sum from public.bill_payments99 where bill_kind = 'cost' and bill_ref = p_ref and status in ('active', 'kept_credit');
    rem := cb.amount - paid_sum;
  else
    select * into pb from public.purchase_bills where id = p_ref::uuid;
    if not found then raise exception 'not_found'; end if;
    perform 1 from public.suppliers where id = pb.supplier_id for no key update;   -- bos109 (was: for update; the row lock must not conflict with the key-share lock of a bill / payment insert in the same transaction)                 -- one posting / payment / void at a time per supplier
    select * into pb from public.purchase_bills where id = p_ref::uuid for update;
    if pb.status <> 'posted' or pb.kind <> 'bill' then raise exception 'bill_not_posted'; end if;
    loc := pb.location_id;
    if p_mode is null or p_mode not in ('cash', 'bank', 'mobile', 'card') then raise exception 'bad_mode'; end if;
    select o.open_amt into open_amt from public._sup_open(pb.supplier_id) o where o.bill_id = pb.id;
    rem := least(coalesce(open_amt, 0), pb.total - pb.paid);
  end if;
  if rem <= 0.004 then raise exception 'nothing_due'; end if;
  amt := round(coalesce(p_amount, rem), 2);
  if amt is null or amt <= 0 or amt > 1000000000000 then raise exception 'bad_amount'; end if;
  if amt > rem + 0.004 then raise exception 'overpaid'; end if;
  warns := public._bp_dup99(p_kind, p_ref, amt);
  if coalesce(array_length(warns, 1), 0) > 0 and not coalesce(p_confirm, false) then
    return jsonb_build_object('ok', false, 'needs_confirm', true, 'warnings', to_jsonb(warns), 'remaining', rem);
  end if;
  if p_kind = 'cost' then
    if p_mode = 'other' then
      mtype := 'note_only';                                                              -- no cash / bank / mobile movement: not in the cash book, not in the journal
    else
      perform public.path_guard('expense', loc, 'a');                                    -- the owner may have made the 10-2 form the record here
      perform public.lock_check(today);
      insert into public.quick_expenses (client_id, location_id, exp_date, head, paid_to, amount, mode, receipt, note, created_by, created_staff)
        values (p_client, loc, today, public._bp_head99(cs.cost_type), left(nullif(btrim(coalesce(cs.provider, '')), ''), 120), amt, p_mode, cb.bill_no is not null,
                left('cost bill #' || cb.id::text || coalesce(' ' || cb.bill_no, ''), 300), auth.uid(), sid) returning * into q;
      perform public.shadow_link_add('expense', loc, 'quick_expenses', q.id::text, 'entries', null, 'form 10-2 owed at day end');
      mtype := 'quick_expense'; mref := q.id::text;
    end if;
  else
    perform public.lock_check(today);
    insert into public.supplier_payments (supplier_id, location_id, bill_id, mode, wallet, ref, amount, note, created_by, created_staff, client_id)
      values (pb.supplier_id, pb.location_id, pb.id, p_mode, null, null, amt, left(coalesce(nullif(btrim(p_note), ''), 'bill payment (option)'), 200), auth.uid(), sid, p_client)
      returning id::text into mref;
    update public.purchase_bills set paid = paid + amt where id = pb.id;
    mtype := 'supplier_payment';
  end if;
  insert into public.bill_payments99 (bill_kind, bill_ref, location_id, mode, amount, origin, money_type, money_ref, note, client_id, created_by, created_staff)
    values (p_kind, p_ref, loc, p_mode, amt, p_origin, mtype, mref, left(nullif(btrim(p_note), ''), 300), p_client, auth.uid(), sid) returning id into bid;
  return jsonb_build_object('ok', true, 'id', bid, 'amount', amt, 'remaining', rem - amt, 'money_type', mtype, 'money_ref', mref,
                            'counted', mtype <> 'note_only', 'warnings', to_jsonb(warns));
end $function$
$f$; end if; end $p109$;

-- public.pay_supplier(uuid,integer,jsonb,uuid,text)
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.pay_supplier(p_supplier uuid, p_loc integer, p_payments jsonb, p_client uuid DEFAULT NULL::uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pay jsonb; pm text; amt numeric; tot numeric := 0; bal numeric; sid text; dupby uuid;
begin
  if not public.is_active() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if p_payments is null or jsonb_typeof(p_payments) <> 'array' or jsonb_array_length(p_payments) = 0 then raise exception 'no_payments'; end if;
  for pay in select * from jsonb_array_elements(p_payments) loop
    pm := pay->>'mode'; amt := nullif(pay->>'amount', '')::numeric;
    if pm is null or pm not in ('cash', 'mobile', 'card', 'bank') then raise exception 'bad_mode'; end if;
    if amt is null or not (amt between 0.01 and 999999999999) or round(amt, 2) <= 0 then raise exception 'bad_amount'; end if;
    tot := tot + round(amt, 2);
  end loop;
  if not (tot between 0.01 and 999999999999) then raise exception 'bad_amount'; end if;
  -- a re-sent request is answered before anything is locked or consumed, but only to someone who may see supplier money (or who made it)
  if p_client is not null then
    select created_by into dupby from public.supplier_payments where client_id = p_client order by id limit 1;
    if found then
      if not (public.has_grant('supplier_pay', p_loc) or public._pur_ok(p_loc) or dupby = auth.uid()) then raise exception 'not allowed'; end if;
      return jsonb_build_object('dup', true, 'balance', public._sup_balance(p_supplier));
    end if;
  end if;
  if not (public.has_grant('supplier_pay', p_loc) or public._use_em('supplier_pay', p_loc, 'pay_supplier:' || p_supplier::text, tot)) then raise exception 'not allowed'; end if;
  perform 1 from public.suppliers where id = p_supplier for no key update;   -- bos109 (was: for update; the row lock must not conflict with the key-share lock of a bill / payment insert in the same transaction)           -- one payment at a time per supplier
  if not found then raise exception 'supplier_not_found'; end if;
  if p_client is not null and exists (select 1 from public.supplier_payments where client_id = p_client) then
    return jsonb_build_object('dup', true, 'balance', public._sup_balance(p_supplier));
  end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  bal := public._sup_balance(p_supplier);
  if tot > bal then raise exception 'overpaid'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  for pay in select * from jsonb_array_elements(p_payments) loop
    insert into public.supplier_payments (supplier_id, location_id, bill_id, mode, wallet, ref, amount, note, created_by, created_staff, client_id)
      values (p_supplier, p_loc, null, pay->>'mode', left(nullif(pay->>'wallet', ''), 30), left(nullif(pay->>'ref', ''), 60), round((pay->>'amount')::numeric, 2), left(nullif(btrim(p_note), ''), 200), auth.uid(), sid, p_client);
  end loop;
  return jsonb_build_object('paid', tot, 'balance', bal - tot);
end $function$
$f$; end if; end $p109$;

-- public.void_supplier_payment(bigint,text)
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.void_supplier_payment(p_id bigint, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.supplier_payments;
begin
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into p from public.supplier_payments where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(p.location_id) then raise exception 'not allowed for this location'; end if;
  if not (public.has_grant('purchase_void', p.location_id) or public._use_em('purchase_void', p.location_id, 'void_payment:' || p_id::text, p.amount)) then raise exception 'not allowed'; end if;
  perform 1 from public.suppliers where id = p.supplier_id for no key update;   -- bos109 (was: for update; the row lock must not conflict with the key-share lock of a bill / payment insert in the same transaction)       -- one posting / payment / void at a time per supplier
  select * into p from public.supplier_payments where id = p_id for update;
  if p.voided then raise exception 'already void'; end if;
  if p.bill_id is not null then raise exception 'void_the_bill'; end if;     -- a payment made with a bill goes with the bill
  perform public.lock_check((p.paid_at at time zone 'Asia/Dhaka')::date);
  update public.supplier_payments set voided = true, void_note = left(btrim(p_note), 200), void_by = auth.uid() where id = p_id;
  perform public._stock_exc(p.location_id, 'supplier_payment_void', 'yellow', 'সাপ্লায়ার পেমেন্ট বাতিল: ' || left(btrim(p_note), 100), 'A supplier payment was reversed: ' || left(btrim(p_note), 100), null, null, 'PURCHASE', p.amount);
end $function$
$f$; end if; end $p109$;

-- public.supplier_refund(uuid,integer,numeric,text,text,text,text,text,uuid)
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.supplier_refund(p_supplier uuid, p_loc integer, p_amount numeric, p_mode text, p_wallet text DEFAULT NULL::text, p_ref text DEFAULT NULL::text, p_reason text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare amt numeric; bal numeric; sid text; dupby uuid;
begin
  if not public.is_active() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if p_mode is null or p_mode not in ('cash', 'mobile', 'card', 'bank') then raise exception 'bad_mode'; end if;
  if p_amount is null or not (p_amount between 0.01 and 999999999999) or round(p_amount, 2) <= 0 then raise exception 'bad_amount'; end if;
  amt := round(p_amount, 2);
  if p_reason is not null and not exists (select 1 from public.option_lists where list_code = 'return_reasons' and value_code = p_reason and active) then raise exception 'bad_reason'; end if;
  if p_client is not null then
    select created_by into dupby from public.supplier_refunds where client_id = p_client;
    if found then
      if not (public.has_grant('supplier_pay', p_loc) or public._pur_ok(p_loc) or dupby = auth.uid()) then raise exception 'not allowed'; end if;
      return jsonb_build_object('dup', true, 'balance', public._sup_balance(p_supplier));
    end if;
  end if;
  if not (public.has_grant('supplier_pay', p_loc) or public._use_em('supplier_pay', p_loc, 'supplier_refund:' || p_supplier::text, amt)) then raise exception 'not allowed'; end if;
  perform 1 from public.suppliers where id = p_supplier for no key update;   -- bos109 (was: for update; the row lock must not conflict with the key-share lock of a bill / payment insert in the same transaction)
  if not found then raise exception 'supplier_not_found'; end if;
  if p_client is not null and exists (select 1 from public.supplier_refunds where client_id = p_client) then return jsonb_build_object('dup', true, 'balance', public._sup_balance(p_supplier)); end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  bal := public._sup_balance(p_supplier);
  if bal >= 0 or amt > -bal then raise exception 'refund_exceeds_credit'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.supplier_refunds (supplier_id, location_id, mode, wallet, ref, amount, reason_code, note, created_by, created_staff, client_id)
    values (p_supplier, p_loc, p_mode, left(nullif(p_wallet, ''), 30), left(nullif(p_ref, ''), 60), amt, p_reason, left(nullif(btrim(p_note), ''), 200), auth.uid(), sid, p_client);
  return jsonb_build_object('refunded', amt, 'balance', bal + amt);
end $function$
$f$; end if; end $p109$;

-- public.void_supplier_refund(bigint,text)
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.void_supplier_refund(p_id bigint, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.supplier_refunds;
begin
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into r from public.supplier_refunds where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(r.location_id) then raise exception 'not allowed for this location'; end if;
  if not (public.has_grant('purchase_void', r.location_id) or public._use_em('purchase_void', r.location_id, 'void_refund:' || p_id::text, r.amount)) then raise exception 'not allowed'; end if;
  perform 1 from public.suppliers where id = r.supplier_id for no key update;   -- bos109 (was: for update; the row lock must not conflict with the key-share lock of a bill / payment insert in the same transaction)
  select * into r from public.supplier_refunds where id = p_id for update;
  if r.voided then raise exception 'already void'; end if;
  perform public.lock_check((r.refunded_at at time zone 'Asia/Dhaka')::date);
  update public.supplier_refunds set voided = true, void_note = left(btrim(p_note), 200), void_by = auth.uid() where id = p_id;
  perform public._stock_exc(r.location_id, 'supplier_refund_void', 'yellow', 'সাপ্লায়ার রিফান্ড বাতিল: ' || left(btrim(p_note), 100), 'A supplier refund was reversed: ' || left(btrim(p_note), 100), null, null, 'PURCHASE', r.amount);
end $function$
$f$; end if; end $p109$;

-- public.set_option_view_bulk(uuid,jsonb,uuid)
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.set_option_view_bulk(p_user uuid, p_items jsonb, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rp jsonb; it jsonb; r jsonb; ch jsonb := '[]'::jsonb; n int := 0; res jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  rp := public._ov_replay(p_client, 'user_bulk'); if rp is not null then return rp; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception 'bad_items'; end if;
  if jsonb_array_length(p_items) > 500 then raise exception 'too_many_items'; end if;
  for it in select e.value from jsonb_array_elements(p_items) with ordinality e(value, ord) order by e.value->>'key', e.ord loop   -- bos109: one key order for every caller, so two bulk sets can never wait on each other in a circle
    r := public._ov_put_user(p_user, it->>'key', it->>'mode'); n := n + 1;
    if (r->>'changed')::boolean then ch := ch || jsonb_build_array(r); end if;
  end loop;
  perform public._ov_audit('user_option_view', p_user::text, ch);
  res := jsonb_build_object('user_id', p_user, 'count', n, 'changed', jsonb_array_length(ch));
  perform public._ov_remember(p_client, 'user_bulk', res);
  return res;
end $function$
$f$; end if; end $p109$;

-- public.set_role_option_view_bulk(text,jsonb,uuid)
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.set_role_option_view_bulk(p_role text, p_items jsonb, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rp jsonb; it jsonb; r jsonb; ch jsonb := '[]'::jsonb; n int := 0; res jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  rp := public._ov_replay(p_client, 'role_bulk'); if rp is not null then return rp; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception 'bad_items'; end if;
  if jsonb_array_length(p_items) > 500 then raise exception 'too_many_items'; end if;
  for it in select e.value from jsonb_array_elements(p_items) with ordinality e(value, ord) order by e.value->>'key', e.ord loop   -- bos109: one key order for every caller, so two bulk sets can never wait on each other in a circle
    r := public._ov_put_role(p_role, it->>'key', it->>'mode'); n := n + 1;
    if (r->>'changed')::boolean then ch := ch || jsonb_build_array(r); end if;
  end loop;
  perform public._ov_audit('role_option_view', p_role, ch);
  res := jsonb_build_object('role_code', p_role, 'count', n, 'changed', jsonb_array_length(ch));
  perform public._ov_remember(p_client, 'role_bulk', res);
  return res;
end $function$
$f$; end if; end $p109$;

-- public.setup_recommend_apply(uuid,text[],boolean,boolean)
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.setup_recommend_apply(p_client uuid, p_codes text[] DEFAULT NULL::text[], p_overwrite boolean DEFAULT false, p_ignore_ready boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d record; r public.rules; eff jsonb; applied jsonb := '[]'::jsonb; skipped jsonb := '[]'::jsonb; old_ jsonb; ex public.setup_apply_batches81; res jsonb; sid text;
        c record; cj jsonb; ready boolean; owr boolean; rv jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_client is null then raise exception 'client_id_required'; end if;
  perform public._client_lock(p_client);
  perform pg_advisory_xact_lock(hashtextextended('setup_recommend_apply', 0));   -- bos109: one apply at a time; a second tap with another client id waits, then reads the rules already set ('already') - no rule is applied or audited twice
  select * into ex from public.setup_apply_batches81 where client_id = p_client;
  if found then return ex.result || jsonb_build_object('dup', true); end if;
  for d in select * from public.setup_rec_defs81 where active and (p_codes is null or code = any (p_codes)) order by sort, code loop
    rv := public._rec_value103(d.rule_key, d.rec_value);   -- bos103: purchase_grn_guard = skip when GRN is the stock source
    select * into r from public.rules where key = d.rule_key;
    if not found then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'not_installed'); continue; end if;
    if rv is null then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'no_recommendation'); continue; end if;
    eff := coalesce(r.value, r.default_value);
    if eff is not distinct from rv then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'already'); continue; end if;
    owr := r.value is not null;                       -- the owner already chose another value
    if owr and not (p_overwrite and p_codes is not null) then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'owner_chosen'); continue; end if;
    ready := true;
    if not p_ignore_ready then
      for c in select x.code from public.setup_check_defs81 x where x.code = any (d.ready_checks) and x.active loop
        cj := public._setup_chk81(c.code);
        if coalesce((cj->>'applies')::boolean, false) and coalesce((cj->>'n')::bigint, 0) > 0 then ready := false; end if;
      end loop;
    end if;
    if not ready then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'not_ready'); continue; end if;
    begin
      perform public.set_rule(d.rule_key, rv);      -- validates the value by the rule's kind; the rules audit trigger logs it too
    exception when others then
      skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'rejected', 'error', left(sqlerrm, 120)); continue;
    end;
    old_ := r.value;
    applied := applied || jsonb_build_object('code', d.code, 'rule_key', d.rule_key, 'old', old_, 'new', rv, 'overwrote', owr);
  end loop;
  res := jsonb_build_object('applied', applied, 'skipped', skipped, 'count', jsonb_array_length(applied));
  insert into public.setup_apply_batches81 (client_id, applied_by, overwrite, ignore_ready, result) values (p_client, auth.uid(), coalesce(p_overwrite, false), coalesce(p_ignore_ready, false), res);
  insert into public.setup_apply_lines81 (batch_id, code, rule_key, old_value, new_value, overwrote)
    select p_client, x->>'code', x->>'rule_key', case when jsonb_typeof(x->'old') = 'null' then null else x->'old' end, x->'new', (x->>'overwrote')::boolean from jsonb_array_elements(applied) x;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'setup_apply', 'setup_apply_batches81', p_client::text, jsonb_build_object('applied', applied, 'skipped_count', jsonb_array_length(skipped), 'overwrite', coalesce(p_overwrite, false), 'ignore_ready', coalesce(p_ignore_ready, false)));
  return res;
end $function$
$f$; end if; end $p109$;

-- public.card_settle(integer,date,numeric,numeric,text,uuid,text)
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.card_settle(p_loc integer, p_date date, p_gross numeric, p_fee numeric DEFAULT 0, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid, p_bank_mode text DEFAULT 'bank'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.card_settlements85; sid text; t date := public._acct_today(); d date := coalesce(p_date, public._acct_today()); fee numeric := coalesce(p_fee, 0); bal numeric; omode text := coalesce(public.rule_txt('card_settle_over_mode'), 'off');   -- bos109
begin
  if not (public._acct_manage() and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into c from public.card_settlements85 where client_id = p_client;
    if found then
      if c.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('id', c.id, 'dup', true);
    end if;
  end if;
  if p_gross is null or not (p_gross > 0 and p_gross <= 1000000000000) then raise exception 'bad_amount'; end if;
  if not (fee >= 0 and fee < p_gross) then raise exception 'bad_fee'; end if;
  if coalesce(p_bank_mode, 'bank') not in ('bank', 'mobile') then raise exception 'bad_mode'; end if;
  if d > t then raise exception 'bad_date'; end if;
  perform public.lock_check(d);
  select staff_id into sid from public.profiles where id = auth.uid();
  if omode in ('warn', 'refuse') then perform pg_advisory_xact_lock(hashtextextended('card_settle:' || p_loc::text, 0)); end if;   -- bos109: one settlement per place at a time while the check is on
  select coalesce(sum(jl.debit - jl.credit), 0) into bal from public.journal_lines jl join public.acct_mappings m on m.account_id = jl.account_id and m.key = 'pay_card' where jl.location_id = p_loc;
  if omode in ('warn', 'refuse') then      -- bos109: rule card_settle_over_mode (default off = exactly the old behaviour above). The GL balance lags the books, so settlements saved but not yet booked are taken off it.
    bal := bal - coalesce((select sum(c2.gross) from public.card_settlements85 c2 where c2.location_id = p_loc and c2.status = 'done'
                            and not exists (select 1 from public.journal_entries e where e.source_type = 'card_settlement' and e.source_id = c2.id::text and e.reverses_id is null)), 0);
    if round(p_gross, 2) > bal then
      if omode = 'refuse' then raise exception 'over_settlement' using detail = 'unsettled ' || bal::text, hint = 'card_settle_over_mode'; end if;
      perform public._stock_exc(p_loc, 'card_settle_over', 'yellow', 'Card settlement ' || round(p_gross, 2)::text || ' is more than the unsettled card receivable ' || bal::text,
        'Card settlement ' || round(p_gross, 2)::text || ' is more than the unsettled card receivable ' || bal::text, null, d, 'ACCOUNTS', round(p_gross, 2));
    end if;
  end if;
  insert into public.card_settlements85 (client_id, location_id, settle_date, gross, fee, bank_mode, note, created_by, created_staff)
    values (p_client, p_loc, d, round(p_gross, 2), round(fee, 2), coalesce(p_bank_mode, 'bank'), left(nullif(btrim(p_note), ''), 300), auth.uid(), sid) returning * into c;
  return jsonb_build_object('id', c.id, 'unsettled', bal, 'over', round(p_gross, 2) > bal);
end $function$
$f$; end if; end $p109$;
