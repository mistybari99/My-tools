-- ============================================================
-- Phase 87 (bos87) - STEP X: fixes from the independent QA (docs/briefs_p2p3/QA_COVERAGE.md). Additive; paste-twice safe. Defaults = today's behaviour.
-- Paste order: 72 ... 79, 82, 84, then this file LAST. It re-creates functions from their LATEST definition (all bos72..bos84 lines kept); lines it changes carry "-- bos87".
--   1. Owner decision: the OWNER can always approve (recipe_approve, cost_rule_approve). No self_approve_refused for the owner. The approval is kept as an audit_log
--      row (action 'self_approved') and the return value carries a NON-BLOCKING suggestion (suggestion = 'ask_another_approver' + suggestion_bn/mix/en).
--      A non-owner is unchanged: refused unless the switch recipe_self_approve / cost_rule_self_approve is ON (then also logged + suggestion).
--   2. a2-F8  expiry_sale_guard off|warn|refuse (default off). off = today (block_expired_sale decides). warn = sale goes through, the red alert names batch + expiry date.
--             refuse = refuse the sale from an expired batch (same effect as block_expired_sale = on; late offline syncs are still never refused).
--      a2-F9  record_sale2: a client_id already used by ANOTHER user is refused with 'client_id_taken' (was a raw unique violation). Same user = unchanged (the old sale is returned).
--      a4-F11 purchase_backdate_flag off|warn (default off): posting a bill whose bill_date is not today raises a yellow 'purchase_backdated' line (stock is stamped now(), the journal bill_date).
--             The stock timing itself is NOT changed (owner decision, see report).
--      a4-F12 ledger_problem_count(): number of approved forms whose stock-ledger posting failed (for a badge). The failure already becomes a yellow exception line and never blocks approval.
--   3. production_double_issue_guard off|warn (default off): a stock_issue / form out-line and a recipe production run that take the SAME item from the SAME place on the SAME day
--      -> yellow 'production_double_issue' line (never blocks). production_recommendations() (owner) lists key / current / recommended / reason (production_requires_recipe ON ...).
-- Needs phases 72..79, 82, 84. No table, no data change; three new rules (all off).
-- ============================================================

do $g$ begin
  if to_regprocedure('public._acct_inv_split72(text[], text, text[], integer)') is null
     or to_regprocedure('public._recipe_gate73(uuid)') is null
     or to_regprocedure('public._conv_cost(uuid, integer, numeric, numeric, date, text)') is null
     or to_regprocedure('public._cs_alloc(bigint)') is null
     or to_regprocedure('public._inb_audit76()') is null
     or to_regprocedure('public._oo_flag_ro77()') is null
     or to_regprocedure('public._c78_rows(date, date)') is null
     or (select p.prosrc not like '%bos72%' from pg_proc p where p.proname = 'production_post' and p.pronargs = 7 and p.pronamespace = 'public'::regnamespace limit 1) is not false      -- phase79 applied
     or to_regprocedure('public.guard_recommendations()') is null                                                                                                       -- phase82
     or to_regprocedure('public._aud84()') is null then                                                                                                                 -- phase84
    raise exception 'phase87 needs phases 72, 73, 74, 75, 76, 77, 78, 79, 82 and 84 pasted first (in that order)';
  end if;
end $g$;

-- ---------- new switches (all default to today's behaviour) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('expiry_sale_guard', 'stock', 'choice', '"off"', null, '["off","warn","refuse"]'::jsonb, null, null,
  'মেয়াদোত্তীর্ণ মাল বিক্রি: বন্ধ / warn / block', 'Expired মাল বিক্রি: off / warn / refuse', 'Selling expired stock: off, warn or refuse',
  'বন্ধ = আগের মতো ("মেয়াদোত্তীর্ণ মাল বিক্রি আটকানো" switch যা ঠিক করে)। warn = বিক্রি হয়, red warning-এ batch ও মেয়াদের তারিখ থাকে। block = মেয়াদোত্তীর্ণ batch থেকে বিক্রি ফেরত।',
  'off = আগের মতো ("Expired মাল বিক্রি আটকানো" switch যা ঠিক করে)। warn = sale হয়, red warning-এ batch ও expiry date থাকে। refuse = expired batch থেকে sale ফেরত।',
  'off = as before (the "block expired sale" switch decides). warn = the sale goes through, the red warning names the batch and its expiry date. refuse = a sale that would take expired stock is refused (late offline syncs are still accepted, with the red warning).', 85),
 ('production_double_issue_guard', 'stock', 'choice', '"off"', null, '["off","warn"]'::jsonb, null, null,
  'উৎপাদন ও stock issue-তে একই মাল দুবার: বন্ধ / warn', 'Production আর stock issue-তে একই মাল দুবার: off / warn', 'Same stock taken by production and by an issue: off or warn',
  'warn = একই দিনে একই জায়গায় একই পণ্য উৎপাদন (recipe) এবং stock issue / form-এর out-line দুটোতেই বেরোলে yellow warning (কিছু আটকায় না)। বন্ধ = আগের মতো।',
  'warn = একই দিনে একই জায়গায় একই item production (recipe) আর stock issue / form out-line দুটোতেই বেরোলে yellow warning (কিছু আটকায় না)। off = আগের মতো।',
  'warn = a yellow warning when the same item leaves the same place on the same day both through a recipe production run and through a stock issue / form out-line (nothing is blocked). off = as before.', 86),
 ('purchase_backdate_flag', 'stock', 'choice', '"off"', null, '["off","warn"]'::jsonb, null, null,
  'আগের তারিখের ক্রয় bill পোস্ট হলে warning: বন্ধ / warn', 'Backdated purchase bill post হলে warning: off / warn', 'Posting a purchase bill with a date other than today: off or warn',
  'warn = bill-এর তারিখ আজ না হলে yellow warning: stock আজকের সময়ে ঢোকে, হিসাবের journal bill-এর তারিখে। বন্ধ = আগের মতো।',
  'warn = bill date আজ না হলে yellow warning: stock আজকের time-এ ঢোকে, journal bill date-এ। off = আগের মতো।',
  'warn = a yellow warning when the bill date is not today: the stock is stamped now, the journal uses the bill date. off = as before.', 87)
 on conflict (key) do nothing;

-- ---------- 1. approvals: the owner can always approve (audit row + non-blocking suggestion) ----------
create or replace function public.recipe_approve(p_recipe uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; prev jsonb; selfap boolean := false; sid text;   -- bos87
begin
  if not public.is_active() or not public.has_grant('recipe_approve') then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe for update;
  if not found then raise exception 'recipe_not_found'; end if;
  if r.approved_at is not null then return jsonb_build_object('dup', true, 'recipe_id', r.id, 'approved_at', r.approved_at); end if;
  if not exists (select 1 from public.recipe_lines where recipe_id = r.id and active) then raise exception 'no_lines'; end if;
  if coalesce(r.changed_by, r.created_by) is not distinct from auth.uid() then   -- bos87: the owner is never refused; others as before (switch recipe_self_approve)
    if public.is_owner() or public.rule_on('recipe_self_approve') then selfap := true; else raise exception 'self_approve_refused'; end if;   -- bos87
  end if;   -- bos87
  prev := public._recipe_snapshot(r.id);
  update public.recipes set approved_by = auth.uid(), approved_at = now(), approve_note = left(p_note, 200) where id = r.id;
  perform public._rv_log(r.id, 'approved', prev, left(p_note, 200));
  if selfap then   -- bos87
    select staff_id into sid from public.profiles where id = auth.uid();   -- bos87
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)   -- bos87
      values (auth.uid(), sid, 'self_approved', 'recipes', r.id::text, jsonb_build_object('self_approved', true, 'owner', public.is_owner(), 'note', left(p_note, 200), 'src', 'phase87'));   -- bos87
  end if;   -- bos87
  return jsonb_build_object('recipe_id', r.id, 'approved', true) || public._self_approve_hint87(selfap);   -- bos87
end $$;

-- the non-blocking suggestion that rides on a self-approval (empty object when it was not a self-approval)
create or replace function public._self_approve_hint87(p_self boolean) returns jsonb language sql immutable set search_path = public as $$
  select case when coalesce(p_self, false) then jsonb_build_object('self_approved', true, 'suggestion', 'ask_another_approver',
    'suggestion_bn', 'আপনি নিজের করা পরিবর্তন নিজেই অনুমোদন করেছেন। অন্য একজন অনুমোদনকারীকে দিয়ে দেখিয়ে নিন।',
    'suggestion_mix', 'আপনি নিজের change নিজেই approve করেছেন। আরেকজন approver-কে দিয়ে দেখিয়ে নিন।',
    'suggestion_en', 'You approved your own change. Consider asking another approver to review it.') else '{}'::jsonb end
$$;
revoke all on function public._self_approve_hint87(boolean) from public, anon, authenticated;

create or replace function public.cost_rule_approve(p_rule bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.cost_source_rules; b record; n int := 0; selfap boolean := false; sid text;   -- bos87
begin
  if not public._cs_approve() then raise exception 'not allowed'; end if;
  select * into r from public.cost_source_rules where id = p_rule for update;
  if not found then raise exception 'not_found'; end if;
  if not public._cs_src_ok(r.source_id) then raise exception 'not allowed'; end if;
  if r.status = 'approved' then return jsonb_build_object('dup', true, 'id', r.id); end if;
  if r.status <> 'draft' then raise exception 'rule_not_draft'; end if;
  if not r.complete then raise exception 'rule_incomplete'; end if;
  if r.created_by is not distinct from auth.uid() then   -- bos87: the owner is never refused; others as before (switch cost_rule_self_approve)
    if public.is_owner() or public.rule_on('cost_rule_self_approve') then selfap := true; else raise exception 'self_approve_refused'; end if;   -- bos87
  end if;   -- bos87
  update public.cost_source_rules set status = 'superseded' where source_id = r.source_id and status = 'approved' and effective_from = r.effective_from;      -- same date: the new one replaces the old (kept)
  update public.cost_source_rules set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_rule;
  -- bills that still wait for a split (no rule / blank) may now be allocated; fully allocated bills are NOT touched
  for b in select distinct bl.id from public.cost_source_bills bl where bl.source_id = r.source_id and bl.status = 'active' and bl.period_month >= date_trunc('month', r.effective_from)::date
      and (not exists (select 1 from public.cost_bill_shares x where x.bill_id = bl.id and x.active) or exists (select 1 from public.cost_bill_shares x where x.bill_id = bl.id and x.active and x.kind = 'unallocated')) loop
    perform public._cs_alloc(b.id); n := n + 1;
  end loop;
  if selfap then   -- bos87
    select staff_id into sid from public.profiles where id = auth.uid();   -- bos87
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)   -- bos87
      values (auth.uid(), sid, 'self_approved', 'cost_source_rules', p_rule::text, jsonb_build_object('self_approved', true, 'owner', public.is_owner(), 'note', left(p_note, 200), 'src', 'phase87'));   -- bos87
  end if;   -- bos87
  return jsonb_build_object('id', p_rule, 'approved', true, 'bills_allocated', n) || public._self_approve_hint87(selfap);   -- bos87
end $$;

-- ---------- 2. a2-F8 expiry_sale_guard: stock_post (latest = phase82; bos10..bos82 lines kept) ----------
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
  if p_reason = 'sale_out' and p_neg = 'full' then blk := public.rule_on('block_expired_sale') or coalesce(public.rule_txt('expiry_sale_guard'), 'off') = 'refuse'; end if;           -- (12) read once; bos87: expiry_sale_guard = refuse acts like the block_expired_sale switch
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
        perform public._stock_exc(p_loc, 'sold_expired', 'red', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): মেয়াদ শেষ হওয়া মাল বিক্রি হয়েছে'
            || case when coalesce(public.rule_txt('expiry_sale_guard'), 'off') <> 'off' then ' — batch ' || b.id::text || ', মেয়াদ ' || (b.expires_at at time zone 'Asia/Dhaka')::date::text else '' end,   -- bos87
          coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): stock past its expiry was sold'
            || case when coalesce(public.rule_txt('expiry_sale_guard'), 'off') <> 'off' then ' — batch ' || b.id::text || ', expired ' || (b.expires_at at time zone 'Asia/Dhaka')::date::text else '' end, p_sale, d, form);   -- bos87
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

-- ---------- a2-F9 record_sale2 (latest = phase43): a client_id used by another user is refused with client_id_taken ----------
CREATE OR REPLACE FUNCTION public.record_sale2(p_client uuid, p_loc integer, p_lines jsonb, p_discount numeric, p_payments jsonb, p_customer_mobile text, p_customer_name text, p_sale_type text, p_note text, p_quick boolean, p_sold_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_discount_kind text DEFAULT NULL::text, p_discount_input numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  n int; sid text; s public.sales; ln jsonb; it public.items; qty numeric; pr numeric; amt numeric; shown numeric;
  out_lines jsonb := '[]'; sub numeric := 0; disc numeric := coalesce(p_discount, 0); ov boolean;
  any_ov boolean := false; any_drift boolean := false; any_custom boolean := false;
  at_ timestamptz := coalesce(p_sold_at, now()); stype text := coalesce(p_sale_type, 'retail');
  pay jsonb; paid_sum numeric := 0; due numeric; mob text; cust public.customers; tend numeric; modes text[] := '{}'; pm text; lim jsonb; bal numeric;
  needcust boolean; dkind text; dinput numeric; credit_over boolean := false; em text; ov_ok boolean;
  tier_id43 bigint; tier_pct43 numeric; tier_cap43 numeric; tier_amt43 numeric := 0;   -- bos43
begin
  perform set_config('bos.em_used', '', true);
  perform set_config('bos.tier_use', '', true);   -- bos43
  if not public.can_do('POS', 'enter') then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_client is not null then
    select * into s from public.sales where client_id = p_client and created_by = auth.uid();
    if found then return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'paid', s.paid, 'due', s.due_amount, 'dup', true); end if;
    if exists (select 1 from public.sales x where x.client_id = p_client and x.created_by is distinct from auth.uid()) then raise exception 'client_id_taken'; end if;   -- bos87: another user already used this client_id
  end if;
  if at_ > now() + interval '10 minutes' or at_ < now() - make_interval(hours => coalesce(public.rule_num('pos_offline_hours'), 72)::int) then at_ := now(); end if;
  if stype not in ('retail', 'wholesale') then raise exception 'bad_sale_type'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  -- discount given as an AMOUNT (default, also every old call) or as a PERCENT of the subtotal (computed here, 2 decimals)
  dkind := coalesce(nullif(btrim(p_discount_kind), ''), 'amount');
  if dkind not in ('amount', 'percent') then raise exception 'bad_discount_kind'; end if;
  if dkind = 'percent' then
    dinput := p_discount_input;
    if dinput is null or dinput = 'NaN'::numeric or dinput < 0 or dinput > 100 then raise exception 'bad_discount'; end if;
    disc := 0;                                        -- computed after the subtotal is known
  else
    dinput := coalesce(p_discount_input, p_discount, 0);
    if dinput = 'NaN'::numeric then raise exception 'bad_discount'; end if;
    dinput := round(dinput, 2); disc := dinput;
  end if;
  for ln in select * from jsonb_array_elements(p_lines) loop
    ov := false;
    if nullif(ln->>'item_id', '') is not null then
      select * into it from public.items where id = (ln->>'item_id')::uuid;
      if not found then raise exception 'item_not_found'; end if; /* bos22-late */ if not it.is_active and not (at_ < now() - interval '2 minutes' and it.updated_at > at_) then raise exception 'item_not_found'; end if;
      qty := (ln->>'qty')::numeric;
      if qty is null or qty = 'NaN'::numeric or qty <= 0 then raise exception 'bad_qty'; end if;
      pr := it.sell_price;
      if (ln->>'override')::boolean is true then
        if public.rule_on('pos_override_manager') then
          if ov_ok is null then ov_ok := public.rule_ok('price_override', p_loc, null, null, 'sale'); end if;      -- one approval covers every price change in this sale
          if not ov_ok then raise exception 'override_needs_approval'; end if;
        end if;
        pr := (ln->>'price')::numeric;
        if pr is null or pr = 'NaN'::numeric or pr < 0 then raise exception 'bad_price'; end if;
        if pr is distinct from it.sell_price then ov := true; any_ov := true; end if;
      else
        shown := nullif(ln->>'price', '')::numeric;
        if shown is not null and shown is distinct from it.sell_price then any_drift := true; end if;
      end if;
      if pr is null then raise exception 'no_price'; end if;
      amt := round(qty * pr, 2);
      out_lines := out_lines || jsonb_build_object('item_id', it.id, 'code', it.code, 'name', it.name_bn, 'unit', it.unit, 'qty', qty, 'price', pr, 'amount', amt, 'override', ov);
    elsif ln ? 'qty' and ln ? 'price' then            -- an item that is not in the list
      qty := (ln->>'qty')::numeric; pr := (ln->>'price')::numeric;
      if qty is null or qty = 'NaN'::numeric or qty <= 0 then raise exception 'bad_qty'; end if;
      if pr is null or pr = 'NaN'::numeric or pr <= 0 then raise exception 'bad_price'; end if;
      if nullif(btrim(ln->>'name'), '') is null then raise exception 'name_required'; end if;
      if public.rule_txt('pos_unlisted') = 'block' then raise exception 'unlisted_blocked'; end if;
      amt := round(qty * pr, 2); any_custom := coalesce(public.rule_txt('pos_unlisted'), 'flag') = 'flag';
      out_lines := out_lines || jsonb_build_object('item_id', null, 'name', left(btrim(ln->>'name'), 80), 'unit', left(coalesce(ln->>'unit', ''), 20), 'qty', qty, 'price', pr, 'amount', amt, 'override', false, 'custom', true);
    else                                              -- quick sale
      amt := (ln->>'amount')::numeric;
      if amt is null or amt = 'NaN'::numeric or amt <= 0 then raise exception 'bad_amount'; end if;
      out_lines := out_lines || jsonb_build_object('item_id', null, 'name', left(coalesce(nullif(ln->>'name', ''), 'Quick sale'), 80), 'qty', 1, 'price', amt, 'amount', amt, 'override', false);
    end if;
    sub := sub + amt;
  end loop;
  if dkind = 'percent' then
    disc := round(sub * dinput / 100, 2);
    -- the phone shows the discount it computed from the percent; a half-cent case can round the other way here. Within one paisa (0.01) the amount the
    -- customer was shown wins, so the bill never asks for a paisa more or less than the screen said (never beyond 0.01, never outside 0..subtotal).
    if p_discount is not null and abs(p_discount - disc) <= 0.01 and p_discount between 0 and sub then disc := round(p_discount, 2); end if;
  end if;
  if disc < 0 or disc > sub then raise exception 'bad_discount'; end if;
  if disc > 0 and not public.rule_on(case dkind when 'percent' then 'discount_mode_percent_on' else 'discount_mode_amount_on' end) then raise exception 'discount_mode_off'; end if;
  -- bos43: the customer's tier discount is pre-approved (switch tier_discount_on): the part of the discount up to the tier percent (and the tier cap) needs no manager approval
  if disc > 0 and public.rule_on('tier_discount_on') and nullif(btrim(p_customer_mobile), '') is not null then
    select t.id, t.discount_percent, t.discount_cap_amount into tier_id43, tier_pct43, tier_cap43
      from public.customers cu join public.customer_tiers t on t.id = cu.tier_id
      where cu.mobile = public.norm_mobile(p_customer_mobile) and cu.active and t.active and t.discount_percent > 0;
    if found then tier_amt43 := least(disc, round(sub * tier_pct43 / 100, 2), coalesce(tier_cap43, disc)); end if;
  end if;
  select value into lim from public.location_settings where location_id = p_loc and key = 'discount_limit';
  if disc > tier_amt43 and public.rule_on('pos_discount_manager') and (lim is null or jsonb_typeof(lim) = 'null' or disc > (lim #>> '{}')::numeric)
     and not public.rule_ok('discount_over_limit', p_loc, disc, null, 'sale') then raise exception 'discount_needs_approval'; end if;   -- no limit written = a granted role is needed
  -- payments
  if p_payments is not null and jsonb_typeof(p_payments) <> 'array' then raise exception 'bad_payments'; end if;
  for pay in select * from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) loop
    pm := pay->>'mode';
    if pm is null or pm not in ('cash', 'mobile', 'card') then raise exception 'bad_mode'; end if;
    amt := (pay->>'amount')::numeric;
    if amt is null or amt = 'NaN'::numeric or amt <= 0 then raise exception 'bad_amount'; end if;
    amt := round(amt, 2); paid_sum := paid_sum + amt;
    if not pm = any (modes) then modes := modes || pm; end if;
  end loop;
  if paid_sum > sub - disc then raise exception 'overpaid'; end if;
  due := sub - disc - paid_sum;
  -- customer
  mob := case when nullif(btrim(p_customer_mobile), '') is not null then public.norm_mobile(p_customer_mobile) end;
  needcust := (due > 0 and public.rule_on('pos_customer_on_due')) or (stype = 'wholesale' and public.rule_on('pos_customer_on_wholesale')) or (disc > 0 and public.rule_on('pos_customer_on_discount'));
  if needcust and mob is null and not public.rule_ok('sale_without_customer', p_loc, null, null, 'sale') then raise exception 'customer_required'; end if;
  if mob is not null then
    select * into cust from public.customers where mobile = mob for update;
    if not found then
      if nullif(btrim(p_customer_name), '') is null then raise exception 'customer_name_required'; end if;
      insert into public.customers (mobile, name, type, created_by) values (mob, left(btrim(p_customer_name), 80), stype, auth.uid()) returning * into cust;
    elsif stype = 'wholesale' and cust.type <> 'wholesale' then
      update public.customers set type = 'wholesale' where id = cust.id;
    end if;
    if not cust.active then raise exception 'customer_inactive'; end if;
    if due > 0 and cust.credit_limit is not null and coalesce(public.rule_txt('pos_credit_mode'), 'block') <> 'off' then
      bal := coalesce(public.customer_balance(cust.id), 0);
      if bal + due > cust.credit_limit then
        credit_over := true;
        if coalesce(public.rule_txt('pos_credit_mode'), 'block') = 'block' and not public.rule_ok('credit_over_limit', p_loc, due, null, 'sale') then raise exception 'over_credit_limit'; end if;
      end if;
    end if;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if tier_amt43 > 0 then perform set_config('bos.tier_use', tier_id43 || '|' || tier_pct43 || '|' || tier_amt43, true); end if;   -- bos43
  insert into public.serials (form_code, location_id, last) values ('POS', p_loc, 1)
    on conflict (form_code, location_id) do update set last = public.serials.last + 1 returning last into n;
  begin
    insert into public.sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, tendered, customer, note, quick,
        created_by, created_staff, customer_id, sale_type, paid, due_amount, discount_kind, discount_input)
      values (p_client, p_loc, n, at_, (at_ at time zone 'Asia/Dhaka')::date, out_lines, sub, disc, sub - disc,
        case when paid_sum = 0 then 'due' when due = 0 and array_length(modes, 1) = 1 then modes[1] else 'split' end,
        (select nullif(x->>'tendered', '')::numeric from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) x where x->>'mode' = 'cash' limit 1),
        case when cust.id is not null then cust.name end, left(nullif(btrim(p_note), ''), 200), coalesce(p_quick, false),
        auth.uid(), sid, cust.id, stype, paid_sum, due, case when disc > 0 then dkind end, case when disc > 0 then dinput end)
      returning * into s;
  exception when unique_violation then
    select * into s from public.sales where client_id = p_client and created_by = auth.uid();
    if found then return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'paid', s.paid, 'due', s.due_amount, 'dup', true); end if;
    if p_client is not null and exists (select 1 from public.sales x where x.client_id = p_client and x.created_by is distinct from auth.uid()) then raise exception 'client_id_taken'; end if;   -- bos87: a race with another user
    raise;
  end;
  for pay in select * from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) loop
    insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, amount, paid_at, created_by, created_staff)
      values (s.id, cust.id, p_loc, 'sale', pay->>'mode', left(nullif(pay->>'wallet', ''), 30), left(nullif(pay->>'ref', ''), 60), round((pay->>'amount')::numeric, 2), at_, auth.uid(), sid);
  end loop;
  -- exceptions for the owner (nothing is blocked here except the customer / credit rules above)
  if any_ov or any_drift then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, s.id, 'POS', p_loc, s.sale_date, case when any_ov then 'price_override' else 'price_changed' end, 'yellow', s.total,
        case when any_ov then jsonb_build_object('bn', 'রসিদ ' || n || ': নির্ধারিত দামের বদলে অন্য দামে বিক্রি', 'en', 'Receipt ' || n || ': sold at a price different from the list price')
          else jsonb_build_object('bn', 'রসিদ ' || n || ': ফোনে দেখানো দাম আর তালিকার দাম আলাদা ছিল (তালিকার দাম ধরা হয়েছে)', 'en', 'Receipt ' || n || ': the price shown on the phone differed from the list price (list price used)') end);
  end if;
  if any_custom then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, s.id, 'POS', p_loc, s.sale_date, 'unlisted_item', 'yellow', s.total,
        jsonb_build_object('bn', 'রসিদ ' || n || ': তালিকায় নেই এমন আইটেম বিক্রি — আইটেম তালিকায় যোগ করুন', 'en', 'Receipt ' || n || ': an item that is not in the list was sold — add it to the item list'));
  end if;
  if disc > tier_amt43 then   -- bos43 (was: disc > 0)
    if lim is null or jsonb_typeof(lim) = 'null' then
      insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (null, s.id, 'POS', p_loc, s.sale_date, 'discount_no_limit', 'yellow', disc,
          jsonb_build_object('bn', 'রসিদ ' || n || ': ডিসকাউন্ট দেওয়া হয়েছে কিন্তু ডিসকাউন্টের সীমা সেটিংসে নেই', 'en', 'Receipt ' || n || ': a discount was given but no discount limit is set'));
    elsif disc > (lim #>> '{}')::numeric then
      insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (null, s.id, 'POS', p_loc, s.sale_date, 'discount_over_limit', 'red', disc,
          jsonb_build_object('bn', 'রসিদ ' || n || ': ডিসকাউন্ট সীমার উপরে', 'en', 'Receipt ' || n || ': discount above the limit'));
    end if;
  end if;
  if due > 0 and cust.id is null then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, s.id, 'POS', p_loc, s.sale_date, 'unattributed_due', 'yellow', due,
        jsonb_build_object('bn', 'রসিদ ' || n || ': বাকি আছে কিন্তু কোনো গ্রাহক নেই — এই বাকি কোনো গ্রাহকের খাতায় নেই', 'en', 'Receipt ' || n || ': an amount is due but there is no customer — it is on nobody’s ledger'));
  end if;
  if credit_over then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, s.id, 'POS', p_loc, s.sale_date, 'credit_limit_override', 'yellow', due,
        jsonb_build_object('bn', 'রসিদ ' || n || ': গ্রাহকের বাকির সীমা পার হয়েছে (অনুমোদনকারী দিয়েছেন)', 'en', 'Receipt ' || n || ': the customer’s credit limit was exceeded (given by an approver)'));
  end if;
  for em in select unnest(string_to_array(nullif(current_setting('bos.em_used', true), ''), ',')) loop
    if em <> '' then
      insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (null, s.id, 'POS', p_loc, s.sale_date, 'emergency_used', 'yellow', s.total,
          jsonb_build_object('bn', 'রসিদ ' || n || ': জরুরি অনুমোদনে সেল (' || split_part(em, ':', 2) || ')', 'en', 'Receipt ' || n || ': sold on an emergency approval (' || split_part(em, ':', 2) || ')'));
    end if;
  end loop;
  return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'paid', paid_sum, 'due', due, 'customer_id', cust.id, 'discount', disc);
end $function$;

-- ---------- a4-F11 _post_purchase_p13 (latest = phase82; bos82 lines kept): optional backdate flag ----------
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
end $function$;

-- ---------- a4-F12: how many approved forms have a failed / skipped stock-ledger posting (for a badge). The failure itself already never blocks the approval
--            (trigger _entries_post_ledger swallows it into a yellow exception line); this only counts what ledger_post_problems() lists, for the people allowed to see it ----------
create or replace function public.ledger_problem_count(p_loc int default null) returns int
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return (select count(*)::int from public.ledger_post_problems(p_loc));
end $$;
revoke all on function public.ledger_problem_count(int) from public, anon;
grant execute on function public.ledger_problem_count(int) to authenticated;

-- ---------- 3. production double-deduction guard (never blocks: any error inside is swallowed) ----------
-- fires for every issue_out ledger row (stock_issue 'issue', form out-line 'entry', recipe production 'production') when the switch is not off
create or replace function public._prod_double_issue87() returns trigger
language plpgsql security definer set search_path = public as $$
declare d date; t0 timestamptz; t1 timestamptz; other bigint; ic text; nm text; ne text; en text; bn text;
begin
  if coalesce(public.rule_txt('production_double_issue_guard'), 'off') = 'off' then return null; end if;
  if new.ref_type not in ('production', 'issue', 'entry') then return null; end if;
  begin
    d := (new.made_at at time zone 'Asia/Dhaka')::date;
    t0 := d::timestamp at time zone 'Asia/Dhaka'; t1 := (d + 1)::timestamp at time zone 'Asia/Dhaka';
    select x.id into other from public.stock_ledger x
     where x.item_id = new.item_id and x.location_id = new.location_id and x.reason = 'issue_out' and x.id <> new.id
       and x.made_at >= t0 and x.made_at < t1
       and ((new.ref_type = 'production' and x.ref_type in ('issue', 'entry')) or (new.ref_type in ('issue', 'entry') and x.ref_type = 'production'))
       and not exists (select 1 from public.stock_ledger y where y.reverses_id = x.id)
     order by x.id limit 1;
    if other is null then return null; end if;
    select code, name_bn, name_en into ic, nm, ne from public.items where id = new.item_id;
    en := coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): taken out by a recipe production run and also by a stock issue / form out-line on the same day — it may be deducted twice';
    bn := coalesce(nm, '') || ' (' || coalesce(ic, '') || '): একই দিনে recipe উৎপাদন আর stock issue / form-এর out-line দুটোতেই বেরিয়েছে — দুবার কাটা হয়ে থাকতে পারে';
    if not exists (select 1 from public.exceptions e where e.flag_code = 'production_double_issue' and e.location_id = new.location_id and e.entry_date = d and e.text->>'en' = en) then
      perform public._stock_exc(new.location_id, 'production_double_issue', 'yellow', bn, en, null, d, 'STOCK');
    end if;
  exception when others then null;
  end;
  return null;
end $$;
revoke all on function public._prod_double_issue87() from public, anon, authenticated;
drop trigger if exists stock_ledger_dbl87 on public.stock_ledger;
create trigger stock_ledger_dbl87 after insert on public.stock_ledger for each row when (new.reason = 'issue_out') execute function public._prod_double_issue87();

-- recommendations only (the owner decides; nothing is changed here). Same row shape as guard_recommendations().
create or replace function public.production_recommendations() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return jsonb_build_array(
   jsonb_build_object('key', 'production_requires_recipe', 'current', to_jsonb(public.rule_on('production_requires_recipe')), 'recommended', to_jsonb(true),
     'reason_bn', 'recipe ছাড়া হাতে-লেখা উৎপাদন কাঁচামাল না কেটে তৈরি মাল যোগ করে; recipe বাধ্যতামূলক হলে কাঁচামাল একবারই কাটে ও খরচ ধরা পড়ে।',
     'reason_mix', 'Recipe ছাড়া manual production কাঁচামাল না কেটে finished মাল যোগ করে; recipe বাধ্যতামূলক হলে কাঁচামাল একবারই কাটে ও cost ধরা পড়ে।',
     'reason_en', 'A manual production entry adds finished goods without deducting ingredients; requiring a recipe deducts the ingredients once and captures the cost.'),
   jsonb_build_object('key', 'production_double_issue_guard', 'current', public.rule_txt('production_double_issue_guard'), 'recommended', 'warn',
     'reason_bn', 'একই দিনে একই মাল উৎপাদন (recipe) আর stock issue/form দুটোতেই কাটলে দুবার কাটা হতে পারে; warn দিলে সতর্কবার্তা আসে, কিছু আটকায় না।',
     'reason_mix', 'একই দিনে একই মাল production (recipe) আর stock issue/form দুটোতেই কাটলে দুবার কাটা হতে পারে; warn দিলে warning আসে, কিছু আটকায় না।',
     'reason_en', 'If the same goods are deducted by a recipe production run and by a stock issue or form on the same day, they may be deducted twice; warn flags it and blocks nothing.'),
   jsonb_build_object('key', 'production_requires_cost', 'current', public.rule_txt('production_requires_cost'), 'recommended', 'refuse',
     'reason_bn', 'কাঁচামালের দাম অজানা থাকলে উৎপাদনের খরচ ভুল/ফাঁকা থাকে; refuse দিলে আগে দাম বসাতে হয় (আগে সব কাঁচামালের দাম দিয়ে নিন)।',
     'reason_mix', 'Ingredient-এর cost অজানা থাকলে production cost ভুল/ফাঁকা থাকে; refuse দিলে আগে cost বসাতে হয় (আগে সব ingredient-এর cost দিয়ে নিন)।',
     'reason_en', 'With an unknown ingredient cost the production cost is wrong or blank; refuse forces the cost to be entered first (fill in every ingredient cost before switching it on).'));
end $$;
revoke all on function public.production_recommendations() from public, anon;
grant execute on function public.production_recommendations() to authenticated;
