-- ============================================================
-- Phase 82 - Part 1 step E (first half): stock-side guards. Run AFTER phase78 (phase72 lives on another branch; this file does not need it).
-- Idempotent (paste twice = no error). Nothing is deleted. EVERY new switch defaults to today's behaviour; the app only RECOMMENDS (guard_recommendations()), never forces.
--   E1 GRN vs purchase page   purchase_grn_guard off|skip|link, grn_bill_link(), grn_pending_report() ("bill-less receive" list)
--   E2 void of a posted bill  purchase_void_guard off|warn|refuse (return / negative stock / live GRN batch), purchase_void_payments void|keep (keep = supplier credit, use supplier_refund)
--   E3 unit conversion        unit_conv_required off|warn|refuse, item editor guard (trigger), unit_unknown_items()
--   E4 negative stock         neg_grant_log, production_negative_reason off|warn|required, never_opened_negative_items()
-- Re-created from their latest definitions (only lines tagged bos82 differ): _post_purchase_p13, _void_purchase_p13, _sale_stock_out, stock_post.
-- ============================================================

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('purchase_grn_guard', 'stock', 'choice', '"off"', null, '["off","skip","link"]'::jsonb, null, null,
  'GRN উৎস হলে ক্রয় bill stock বাড়াবে কি: বন্ধ / বাদ / link লাগবে', 'GRN source হলে purchase bill stock বাড়াবে কি: off / skip / link লাগবে', 'When GRN is the stock source, does the purchase bill add stock: off, skip or link required',
  'বন্ধ = আগের মতো (দুটোই stock বাড়ায়, দুবার গোনা হতে পারে)। বাদ = bill শুধু টাকা/বাকি ধরে, stock GRN থেকে। link = bill-এর সাথে GRN জুড়তে হবে, না হলে পোস্ট হবে না। শুধু "কেনা মালের উৎস = GRN" হলে কাজ করে।',
  'off = আগের মতো (দুটোই stock বাড়ায়)। skip = bill শুধু টাকা/বাকি ধরে, stock আসে GRN থেকে। link = bill-এর সাথে GRN জুড়তে হবে। শুধু "কেনা মালের source = GRN" হলে কাজ করে।',
  'off = as before (both add stock, goods can be counted twice). skip = the bill only records money / dues, stock comes from the GRN. link = the bill must be linked to its GRN before posting. Works only when the bought-goods source is GRN.', 74),
 ('purchase_void_guard', 'stock', 'choice', '"off"', null, '["off","warn","refuse"]'::jsonb, null, null,
  'পোস্ট করা ক্রয় bill বাতিলে সুরক্ষা: বন্ধ / warn / block', 'Posted purchase bill void-এ সুরক্ষা: off / warn / refuse', 'Voiding a posted purchase bill: off, warn or refuse',
  'ফেরত bill থাকলে, মাল ব্যবহার হয়ে stock ঋণাত্মক হলে, বা চালু GRN batch থাকলে বাতিল block (বা red warning)। বন্ধ = আগের মতো।',
  'Return থাকলে, মাল ব্যবহার হয়ে stock negative হলে, বা live GRN batch থাকলে void block (বা red warning)। off = আগের মতো।',
  'Refuse (or flag red) when a posted return refers to the bill, voiding would make stock negative, or a live GRN batch exists. off = as before.', 75),
 ('purchase_void_payments', 'stock', 'choice', '"void"', null, '["void","keep"]'::jsonb, null, null,
  'bill বাতিলে supplierকে দেওয়া টাকা: বাতিল ধরা / রেখে দেওয়া (credit)', 'Bill void-এ supplier payment: void ধরা / রেখে দেওয়া (credit)', 'Supplier payments when a bill is voided: void them or keep them as credit',
  'default = আগের মতো (payment-ও বাতিল, day book-এ টাকা ফিরে আসে)। রেখে দেওয়া = টাকা সত্যিই বেরিয়েছে, তাই payment থাকে এবং supplier-এর কাছে credit হয়; টাকা ফেরত পেলে "supplier refund" লিখুন।',
  'Default = আগের মতো (payment-ও void, day book-এ টাকা ফিরে আসে)। keep = টাকা সত্যিই বেরিয়েছে, তাই payment থাকে আর supplier credit হয়; টাকা ফেরত পেলে "supplier refund" লিখুন।',
  'Default = as before (payments are voided too, the day book shows the cash back). keep = the money really left, so the payment stays and becomes supplier credit; record a supplier refund when the money comes back.', 76),
 ('unit_conv_required', 'stock', 'choice', '"warn"', null, '["off","warn","refuse"]'::jsonb, null, null,
  'stock-tracked পণ্যে unit-এর conversion না থাকলে বিক্রি: বন্ধ / warn / block', 'Tracked item-এ unit conversion না থাকলে sale: off / warn / refuse', 'Sale of a tracked item with no unit conversion: off, warn or refuse',
  'warn = আগের মতো (বিক্রি হয়, stock কমে না, yellow warning)। block = online বিক্রি "unit_unknown" দিয়ে ফেরত; offline থেকে দেরিতে আসা বিক্রি নেওয়া হয় কিন্তু red চিহ্ন; item editorও tracked করতে দেয় না।',
  'warn = আগের মতো (sale হয়, stock কমে না, yellow warning)। refuse = online sale "unit_unknown" দিয়ে ফেরত; offline থেকে দেরিতে আসা sale নেওয়া হয় কিন্তু red flag; item editor-ও tracked করতে দেয় না।',
  'warn = as before (the sale goes through, stock is not reduced, yellow warning). refuse = an online sale is refused with unit_unknown; a late offline sale is accepted but flagged red; the item editor also refuses tracked.', 77),
 ('neg_grant_log', 'stock', 'switch', 'false', null, null, null, null,
  '"stock-এর নিচে বিক্রি" অনুমতি ব্যবহার হলে yellow warning', '"Sell below zero" permission ব্যবহার হলে yellow warning', 'Yellow warning when the sell-below-zero permission is used',
  'চালু = ব্লক মোডে যে অনুমতির জোরে stock-এর নিচে গেলে কে, কোন পণ্য, কত — লেখা থাকে। বন্ধ = আগের মতো।',
  'On = block mode-এ permission-এর জোরে stock-এর নিচে গেলে কে, কোন item, কত — লেখা থাকে। Off = আগের মতো।',
  'On = in block mode, going below zero by that permission logs who, which item and how much. Off = as before.', 78),
 ('production_negative_reason', 'stock', 'choice', '"off"', null, '["off","warn","required"]'::jsonb, null, null,
  'উৎপাদনে কাঁচামাল ঋণাত্মক হলে কারণ: বন্ধ / warn / required', 'Production-এ ingredient negative হলে reason: off / warn / required', 'Production taking an ingredient below zero: off, warn or reason required',
  'বন্ধ = আগের মতো। warn = yellow warning। required = উৎপাদনের নোটে কারণ না লিখলে আটকে যায়।',
  'off = আগের মতো। warn = yellow warning। required = production note-এ reason না লিখলে আটকে যায়।',
  'off = as before. warn = yellow warning. required = refused unless the production note gives a reason.', 79)
 on conflict (key) do nothing;

-- the GRN <-> bill link uses the existing shadow engine, domain 'grn' (primary = the GRN form, shadow = the bill). Only a link: it has no a/b lock.
insert into public.path_domains (domain, a_bn, a_en, b_bn, b_en, default_primary, note_bn, note_en, sort) values
 ('grn', 'ক্রয় bill (টাকা / বাকি)', 'Purchase bill (money / dues)', 'form 04-1 (GRN, মাল গ্রহণ)', 'Form 04-1 (GRN, goods received)', 'a',
  'শুধু bill ও GRN জোড়া লাগানোর link; কোনটা stock বাড়াবে তা "কেনা মালের উৎস" switch-এ ঠিক হয়।', 'Link between a bill and its GRN only; which one adds stock is decided by the bought-goods source switch.', 80)
 on conflict (domain) do nothing;

-- ---------- re-created functions (latest definitions; only lines tagged bos82 differ) ----------
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
  perform 1 from public.suppliers where id = pb.supplier_id for update;      -- one posting / payment / void at a time per supplier
  select * into pb from public.purchase_bills where id = p_id for update;
  if pb.status = 'posted' then return jsonb_build_object('id', pb.id, 'status', 'posted', 'total', pb.total, 'dup', true); end if;
  if pb.status <> 'draft' then raise exception 'not_draft'; end if;
  if public.rule_on('purchase_separate_poster') and pb.created_by = auth.uid() and not public.is_owner() then raise exception 'poster_must_differ'; end if;
  perform public.lock_check(pb.bill_date);
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
end $function$;

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
  perform 1 from public.suppliers where id = pb.supplier_id for update;      -- one posting / payment / void at a time per supplier
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
end $function$;

CREATE OR REPLACE FUNCTION public._sale_stock_out()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ln jsonb; it public.items; q numeric; bq numeric; neg text; um text;   -- bos82
begin
  if new.status <> 'done' or new.lines is null or jsonb_typeof(new.lines) <> 'array' then return new; end if;
  -- a sale that syncs late (an offline phone) has already happened: it is recorded, it never blocks (a yellow line still tells the owner)
  neg := case when new.sold_at < now() - interval '2 minutes' then 'soft' else 'full' end;
  -- items in a fixed order, so two sales that share items can never wait on each other in a circle
  for ln in select x from jsonb_array_elements(new.lines) x where nullif(x->>'item_id', '') is not null order by x->>'item_id' loop
    select * into it from public.items where id = (ln->>'item_id')::uuid;
    if not found or not it.tracked then continue; end if;
    q := nullif(ln->>'qty', '')::numeric;
    if q is null or q <= 0 then continue; end if;
    if not (q <= 999999999) then raise exception 'bad_qty'; end if;                    -- Infinity / NaN / absurd: the sale is refused
    bq := public._base_qty(it.id, q, ln->>'unit');
    if bq is null then
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
    if round(bq, 4) = 0 then continue; end if;                                          -- under 0.00005 of a base unit: nothing to take out
    perform public.stock_post(it.id, new.location_id, -bq, 'sale_out', 'sale', new.id::text, null, null, new.sold_at, null, null, neg, new.id);
  end loop;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.stock_post(p_item uuid, p_loc integer, p_qty numeric, p_reason text, p_ref_type text DEFAULT NULL::text, p_ref_id text DEFAULT NULL::text, p_unit_cost numeric DEFAULT NULL::numeric, p_batch bigint DEFAULT NULL::bigint, p_made_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_note text DEFAULT NULL::text, p_reverses bigint DEFAULT NULL::bigint, p_neg text DEFAULT 'full'::text, p_sale uuid DEFAULT NULL::uuid, p_client uuid DEFAULT NULL::uuid)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare q numeric := round(p_qty, 4); bal public.stock_balance; mode text; cost numeric; lid bigint; first_id bigint; b record; rem numeric; take numeric;
        ic text; nm text; ne text; en text; at_ timestamptz := coalesce(p_made_at, now()); ref text := coalesce(p_ref_type, '') || ':' || coalesce(p_ref_id, '');
        d date := (coalesce(p_made_at, now()) at time zone 'Asia/Dhaka')::date; form text := case when p_sale is not null then 'POS' else 'STOCK' end;
        blk boolean := false; pm text; who text;   -- bos82
begin
  if q is null or not (abs(q) between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;            -- false for NaN and Infinity too
  if p_unit_cost is not null and not (p_unit_cost between 0 and 1000000000000) then raise exception 'bad_cost'; end if;
  if p_neg not in ('full', 'soft', 'none') then raise exception 'bad_neg_mode'; end if;
  if p_reason = 'sale_out' and p_neg = 'full' then blk := public.rule_on('block_expired_sale'); end if;           -- (12) read once
  insert into public.stock_balance (item_id, location_id) values (p_item, p_loc) on conflict do nothing;
  select * into bal from public.stock_balance where item_id = p_item and location_id = p_loc for update;      -- serialises everyone touching this item here
  if p_client is not null then
    select id into lid from public.stock_ledger where client_id = p_client and reason = p_reason order by id limit 1;
    if found then return lid; end if;
  end if;
  -- negative stock
  if q < 0 and p_neg <> 'none' and bal.qty + q < 0 then
    mode := coalesce(public.rule_txt('stock_negative_mode'), 'warn');
    -- bos82: production that takes an ingredient below zero: reason needed (production_negative_reason: off | warn | required)
    if p_reason = 'issue_out' and p_ref_type = 'production' then   -- bos82
      pm := coalesce(public.rule_txt('production_negative_reason'), 'off');   -- bos82
      if pm <> 'off' then   -- bos82
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;   -- bos82
        select coalesce(staff_id, '-') into who from public.profiles where id = auth.uid();   -- bos82
        if pm = 'required' and nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'production_negative_reason_needed' using detail = coalesce(ic, '') || ' ' || coalesce(nm, ''), hint = 'on hand ' || bal.qty::text; end if;   -- bos82
        perform public._stock_exc(p_loc, 'production_negative', 'yellow', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): উৎপাদনে stock-এর চেয়ে বেশি কাঁচামাল নেওয়া হয়েছে, পরিমাণ ' || trim_scale(-q)::text || ', কর্মী ' || coalesce(who, '-') || ', কারণ: ' || coalesce(nullif(btrim(p_note), ''), '-'),
          coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): production took more than the stock on hand, qty ' || trim_scale(-q)::text || ', staff ' || coalesce(who, '-') || ', reason: ' || coalesce(nullif(btrim(p_note), ''), '-'), p_sale, d, form);   -- bos82
      end if;   -- bos82
    end if;   -- bos82
    if mode <> 'allow' then
      select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;
      if mode = 'block' and p_neg = 'full' then
        if p_sale is null or coalesce(current_setting('bos.neg_ok', true), '') <> p_sale::text then
          if not (public.has_grant('sell_below_zero', p_loc)
                  or case when p_sale is not null then public.use_emergency('sell_below_zero', p_loc, ref, null, null) else public._use_em('sell_below_zero', p_loc, ref, null) end) then
            raise exception 'insufficient_stock' using detail = coalesce(ic, '') || ' ' || coalesce(nm, ''), hint = 'on hand ' || bal.qty::text;
          end if;
          if p_sale is not null then perform set_config('bos.neg_ok', p_sale::text, true); end if;
        end if;
      end if;
      if mode = 'block' and p_neg = 'full' and public.rule_on('neg_grant_log') and public.has_grant('sell_below_zero', p_loc) then   -- bos82: the grant was used to go below zero: tell the owner who / what / how much
        select coalesce(staff_id, '-') into who from public.profiles where id = auth.uid();   -- bos82
        perform public._stock_exc(p_loc, 'sell_below_zero_used', 'yellow', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): "stock-এর নিচে বিক্রি" অনুমতি ব্যবহার হয়েছে, পরিমাণ ' || trim_scale(-q)::text || ', কর্মী ' || coalesce(who, '-'),
          coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): the sell-below-zero permission was used, qty ' || trim_scale(-q)::text || ', staff ' || coalesce(who, '-'), p_sale, d, form);   -- bos82
      end if;   -- bos82
      en := coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): more went out than the stock on hand — the stock is now negative';
      if exists (select 1 from public.stock_ledger where item_id = p_item and location_id = p_loc and qty_delta > 0)
         and not exists (select 1 from public.exceptions where flag_code = 'stock_negative' and location_id = p_loc and entry_date = d and text->>'en' = en) then
        perform public._stock_exc(p_loc, 'stock_negative', 'yellow', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): স্টকের চেয়ে বেশি বের হয়েছে — হিসাবে স্টক ঋণাত্মক', en, p_sale, d, form);
      end if;
    end if;
  end if;
  cost := coalesce(p_unit_cost, case when q < 0 then bal.avg_cost end);
  if q < 0 and p_batch is null and p_reason in ('sale_out', 'issue_out', 'wastage', 'transfer_out', 'count_adjust', 'purchase_return') then
    rem := -q;
    for b in select id, qty_remaining, expires_at from public.stock_batches where item_id = p_item and location_id = p_loc and qty_remaining > 0
             order by (expires_at is not null and expires_at <= at_), expires_at nulls last, made_at, id for update loop
      if blk and b.expires_at is not null and b.expires_at <= at_ then          -- (12) the owner switched "block expired sale" on
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;
        raise exception 'expired_stock_blocked' using detail = coalesce(ic, '') || ' ' || coalesce(nm, ''), hint = 'batch ' || b.id::text;
      end if;
      take := least(b.qty_remaining, rem);
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, batch_id, reverses_id, client_id, made_at, note, created_by)
        values (p_item, p_loc, -take, cost, p_reason, p_ref_type, p_ref_id, b.id, p_reverses, case when first_id is null then p_client end, at_, p_note, auth.uid()) returning id into lid;
      update public.stock_batches set qty_remaining = case when qty_remaining - take < 0.0005 then 0 else qty_remaining - take end where id = b.id;
      first_id := coalesce(first_id, lid); rem := rem - take;
      if p_reason = 'sale_out' and b.expires_at is not null and b.expires_at <= at_ then
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;
        perform public._stock_exc(p_loc, 'sold_expired', 'red', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): মেয়াদ শেষ হওয়া মাল বিক্রি হয়েছে',
          coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): stock past its expiry was sold', p_sale, d, form);
      end if;
      exit when rem <= 0;
    end loop;
    if rem > 0 then
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, reverses_id, client_id, made_at, note, created_by)
        values (p_item, p_loc, -rem, cost, p_reason, p_ref_type, p_ref_id, p_reverses, case when first_id is null then p_client end, at_, p_note, auth.uid()) returning id into lid;
      first_id := coalesce(first_id, lid);
    end if;
    return first_id;
  end if;
  insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, batch_id, reverses_id, client_id, made_at, note, created_by)
    values (p_item, p_loc, q, cost, p_reason, p_ref_type, p_ref_id, p_batch, p_reverses, p_client, at_, p_note, auth.uid()) returning id into lid;
  if p_batch is not null then
    if q < 0 then
      update public.stock_batches set qty_remaining = case when qty_remaining + q < 0.0005 then 0 else qty_remaining + q end where id = p_batch and qty_remaining + q >= 0;
      if not found then raise exception 'batch_short'; end if;
    elsif p_reason in ('sale_void_in', 'reversal', 'sale_return') then          -- (11) 'sale_return' added
      update public.stock_batches set qty_remaining = least(qty_made, qty_remaining + q) where id = p_batch;
    end if;
  end if;
  return lid;
end $function$;

-- ---------- E3: item editor refuses tracked while the unit has no conversion (only when unit_conv_required = refuse) ----------
create or replace function public._items_unit_conv82() returns trigger
language plpgsql security definer set search_path = public as $$
declare b text;
begin
  if not new.tracked or coalesce(public.rule_txt('unit_conv_required'), 'warn') <> 'refuse' then return new; end if;
  if tg_op = 'UPDATE' and old.tracked and old.unit is not distinct from new.unit and old.base_unit is not distinct from new.base_unit then return new; end if;
  b := coalesce(nullif(btrim(new.base_unit), ''), nullif(btrim(new.unit), ''));
  if nullif(btrim(coalesce(new.unit, '')), '') is not null and b is not null and new.unit <> b and public.unit_factor(new.id, new.unit, b) is null then
    raise exception 'unit_unknown' using detail = 'Cannot track ' || new.code || ': add the conversion from ' || new.unit || ' to ' || b || ' first', hint = new.code;
  end if;
  return new;
end $$;
drop trigger if exists items_unit_conv82 on public.items;
create trigger items_unit_conv82 after insert or update of tracked, unit, base_unit on public.items for each row execute function public._items_unit_conv82();
revoke all on function public._items_unit_conv82() from public, anon, authenticated;

-- ---------- E3: owner board count ----------
create or replace function public.unit_unknown_items() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', i.id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'unit', i.unit, 'base_unit', coalesce(nullif(btrim(i.base_unit), ''), i.unit)) order by i.code), '[]'::jsonb) into r
    from public.items i
   where i.tracked and i.is_active and nullif(btrim(coalesce(i.unit, '')), '') is not null
     and i.unit <> coalesce(nullif(btrim(i.base_unit), ''), nullif(btrim(i.unit), ''))
     and public.unit_factor(i.id, i.unit, coalesce(nullif(btrim(i.base_unit), ''), nullif(btrim(i.unit), ''))) is null;
  return jsonb_build_object('count', jsonb_array_length(r), 'items', r);
end $$;

-- ---------- E4: tracked stock that went negative with no opening / receipt ever ----------
create or replace function public.never_opened_negative_items() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', i.id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'location_id', b.location_id, 'qty', b.qty) order by i.code, b.location_id), '[]'::jsonb) into r
    from public.stock_balance b join public.items i on i.id = b.item_id
   where b.qty < 0 and i.tracked
     and not exists (select 1 from public.stock_ledger l where l.item_id = b.item_id and l.location_id = b.location_id and l.qty_delta > 0
                        and l.reverses_id is null and l.reason not in ('sale_void_in', 'sale_return', 'reversal'));
  return jsonb_build_object('count', jsonb_array_length(r), 'items', r);
end $$;

-- ---------- E1: link a GRN (04-1) to the bill that pays for it ----------
create or replace function public.grn_bill_link(p_entry uuid, p_bill uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; b public.purchase_bills; lk bigint;
begin
  select * into e from public.entries where id = p_entry;
  if not found or e.form_code <> '04-1' or e.status not in ('submitted', 'approved') then raise exception 'grn_not_found'; end if;
  select * into b from public.purchase_bills where id = p_bill;
  if not found or b.kind <> 'bill' or b.status = 'void' then raise exception 'bill_not_found'; end if;
  if b.location_id <> e.location_id then raise exception 'location_mismatch'; end if;
  if not (public.is_owner() or (public.can_loc(b.location_id) and (public.has_grant('purchase_entry', b.location_id) or public._pur_ok(b.location_id)))) then raise exception 'not allowed'; end if;
  lk := public.shadow_link_add('grn', b.location_id, 'entries', e.id::text, 'purchase_bills', b.id::text, coalesce(left(btrim(p_note), 200), 'GRN linked to bill'));
  return jsonb_build_object('link', lk, 'entry', e.id, 'bill', b.id);
end $$;

-- ---------- E1: pending lists ("bill-বিহীন রিসিভ" / receives with no bill, and bills with no GRN when GRN is the source) ----------
create or replace function public.grn_pending_report(p_days int default 60) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare src text := coalesce(public.rule_txt('grn_receipt_source'), 'purchase'); a jsonb; c jsonb; d0 date := (now() at time zone 'Asia/Dhaka')::date - greatest(coalesce(p_days, 60), 1);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('entry_id', e.id, 'date', e.entry_date, 'location_id', e.location_id, 'supplier', e.data->>'supplier',
           'stock_from', case when src = 'grn' then 'grn' else 'purchase_page' end) order by e.entry_date desc), '[]'::jsonb) into a
    from public.entries e
   where e.form_code = '04-1' and e.status = 'approved' and e.entry_date >= d0 and (public.is_owner() or public.can_loc(e.location_id))
     and not exists (select 1 from public.shadow_links x where x.domain = 'grn' and x.primary_type = 'entries' and x.primary_id = e.id::text and x.state <> 'void');
  select coalesce(jsonb_agg(jsonb_build_object('bill_id', pb.id, 'bill_no', pb.bill_no, 'date', pb.bill_date, 'location_id', pb.location_id, 'supplier_id', pb.supplier_id) order by pb.bill_date desc), '[]'::jsonb) into c
    from public.purchase_bills pb
   where src = 'grn' and pb.kind = 'bill' and pb.status = 'posted' and pb.bill_date >= d0 and public._pur_ok(pb.location_id)
     and exists (select 1 from public.purchase_lines l join public.items i on i.id = l.item_id where l.bill_id = pb.id and i.tracked)
     and not exists (select 1 from public.shadow_links x where x.domain = 'grn' and x.shadow_type = 'purchase_bills' and x.shadow_id = pb.id::text and x.state <> 'void');
  return jsonb_build_object('source', src, 'guard', coalesce(public.rule_txt('purchase_grn_guard'), 'off'),
    'receipts_without_bill', a, 'bills_without_receipt', c);
end $$;

-- ---------- recommendations: key, current, recommended, reason in 3 languages. Read-only. The owner may choose anything. ----------
create or replace function public.guard_recommendations() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb := '[]'::jsonb; nu int; counted boolean;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  nu := (public.unit_unknown_items() ->> 'count')::int;
  counted := exists (select 1 from public.stock_ledger where reason in ('count_adjust', 'opening'));
  out_ := out_ || jsonb_build_array(
   jsonb_build_object('key', 'purchase_grn_guard', 'current', public.rule_txt('purchase_grn_guard'),
     'recommended', case when coalesce(public.rule_txt('grn_receipt_source'), 'purchase') = 'grn' then 'skip' else 'off' end,
     'reason_bn', 'GRN-কে উৎস করলে bill stock বাড়ালে একই মাল দুবার গোনা হয়; "বাদ" দিলে bill শুধু টাকা ধরে।',
     'reason_mix', 'GRN source হলে bill-ও stock বাড়ালে একই মাল দুবার গোনা হয়; skip দিলে bill শুধু টাকা ধরে।',
     'reason_en', 'If GRN is the source and the bill also adds stock, the same goods are counted twice; skip makes the bill record money only.'),
   jsonb_build_object('key', 'purchase_void_guard', 'current', public.rule_txt('purchase_void_guard'), 'recommended', 'refuse',
     'reason_bn', 'ফেরত দেওয়া বা ব্যবহার হয়ে যাওয়া মালের bill বাতিল করলে stock ঋণাত্মক ও হিসাব ভুল হয়।',
     'reason_mix', 'Return হয়ে যাওয়া বা use হয়ে যাওয়া মালের bill void করলে stock negative ও হিসাব ভুল হয়।',
     'reason_en', 'Voiding a bill whose goods were returned or used makes stock negative and the books wrong.'),
   jsonb_build_object('key', 'purchase_void_payments', 'current', public.rule_txt('purchase_void_payments'), 'recommended', 'keep',
     'reason_bn', 'টাকা সত্যিই বেরিয়ে গেছে; payment বাতিল করলে day book-এ টাকা ফিরে আসার ভুল দেখায়।',
     'reason_mix', 'টাকা সত্যিই বেরিয়ে গেছে; payment void করলে day book-এ টাকা ফিরে আসার ভুল দেখায়।',
     'reason_en', 'The money really left; voiding the payment makes the day book show cash that never came back.'),
   jsonb_build_object('key', 'unit_conv_required', 'current', public.rule_txt('unit_conv_required'),
     'recommended', case when nu = 0 then 'refuse' else 'warn' end, 'unknown_unit_items', nu,
     'reason_bn', case when nu = 0 then 'সব stock-tracked পণ্যের conversion আছে, তাই block নিরাপদ।' else nu::text || 'টি পণ্যের conversion নেই; আগে সেগুলো ঠিক করুন, তারপর block চালু করুন।' end,
     'reason_mix', case when nu = 0 then 'সব tracked item-এর conversion আছে, তাই refuse করা নিরাপদ।' else nu::text || 'টি item-এর conversion নেই; আগে ঠিক করুন, তারপর refuse চালু করুন।' end,
     'reason_en', case when nu = 0 then 'Every tracked item has its conversion, so refusing is safe.' else nu::text || ' item(s) have no conversion; fix them first, then switch refuse on.' end),
   jsonb_build_object('key', 'neg_grant_log', 'current', to_jsonb(public.rule_on('neg_grant_log')), 'recommended', to_jsonb(true),
     'reason_bn', 'যার অনুমতি আছে সে stock-এর নিচে বিক্রি করলে মালিক যেন জানতে পারেন।',
     'reason_mix', 'যার permission আছে সে stock-এর নিচে sell করলে owner যেন জানতে পারেন।',
     'reason_en', 'The owner should know whenever someone with the permission sells below zero.'),
   jsonb_build_object('key', 'production_negative_reason', 'current', public.rule_txt('production_negative_reason'), 'recommended', 'required',
     'reason_bn', 'কাঁচামাল না থাকা অবস্থায় উৎপাদন করলে খরচ ভুল হয়; কারণ লিখে রাখা ভালো।',
     'reason_mix', 'Ingredient না থাকা অবস্থায় production করলে cost ভুল হয়; reason লিখে রাখা ভালো।',
     'reason_en', 'Producing without enough ingredient stock gives wrong costs; a written reason keeps a trace.'),
   jsonb_build_object('key', 'stock_negative_mode', 'current', public.rule_txt('stock_negative_mode'),
     'recommended', case when counted then 'block' else coalesce(public.rule_txt('stock_negative_mode'), 'warn') end,
     'reason_bn', case when counted then 'প্রথম stock count/opening হয়ে গেছে, তাই stock-এর চেয়ে বেশি বিক্রি block যুক্তিসঙ্গত।' else 'প্রথম stock count বা opening stock এখনো হয়নি; তার পরে "block" বেছে নিন।' end,
     'reason_mix', case when counted then 'প্রথম stock count/opening হয়ে গেছে, তাই stock-এর বেশি sale block করা যুক্তিসঙ্গত।' else 'প্রথম stock count বা opening এখনো হয়নি; তার পরে block বেছে নিন।' end,
     'reason_en', case when counted then 'The first stock count / opening is done, so blocking sales above stock is reasonable.' else 'No stock count or opening yet; choose block after the first one.' end));
  return out_;
end $$;

revoke all on function public.unit_unknown_items(), public.never_opened_negative_items(), public.grn_bill_link(uuid, uuid, text), public.grn_pending_report(int), public.guard_recommendations() from public, anon;
grant execute on function public.unit_unknown_items(), public.never_opened_negative_items(), public.grn_bill_link(uuid, uuid, text), public.grn_pending_report(int), public.guard_recommendations() to authenticated;
