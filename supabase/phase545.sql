-- Phase 545 (STEP 1 freight option) - PURCHASE PRICE CHECK: freight can be counted in "today's price" (switch, OFF by default).
-- Paste AFTER phase544. Paste-twice safe (create or replace, on conflict do nothing, drop trigger if exists, then create).
-- Earlier phase files are NOT edited. No existing function is redefined: the phase adds one rule row, one check function,
--   one trigger-function and one trigger on landed_costs. With the switch OFF the trigger returns at once, so every
--   result of today is unchanged (proved by tests/sql: phase545_test.sql, section F, old chain vs new chain).
-- Source: owner decision (21 Oct 2026, docs/PLAN_NEXT.md item 45): freight MUST be an option in today's purchase price check.
--   The check in purchase_post (phases 508, 513, 515, 535) compares the INVOICE unit cost with the last posted purchase.
--   Freight (landed cost, phases 523 / 524) is not in it. Landed cost is posted after the bill, so the freight of a bill is
--   known only when its landed cost is posted. Therefore the freight-inclusive comparison runs when a landed cost becomes posted.
--
-- One switch, OFF by default:
--   price_check_include_freight (false): OFF = as today (the invoice check at bill posting only; no extra check).
--                                        ON  = when a landed cost is posted, each item it touches is compared with the
--                                              last posted purchase of that item, both with the freight allocated to the
--                                              line (landed_cost_alloc, parts stock + cogs, void rows counted negative).
--                                              A jump above purchase_cost_jump_pct writes a yellow purchase_price_jump exception.
--   The threshold is the existing rule purchase_cost_jump_pct (blank = no check, as today).
-- Business reason: a freight rise is a real cost rise; the owner asked for it as an option, not as a silent change.

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
values (
  'price_check_include_freight', 'purchase', 'switch', 'false'::jsonb, null, null, null, null,
  'ক্রয়মূল্য যাচাইয়ে freight যোগ করা: বন্ধ / চালু',
  'Purchase price check-এ freight যোগ করা: off / on',
  'Include freight in the purchase price check: off / on',
  'চালু করলে landed cost (freight ইত্যাদি) post হওয়ার পর প্রতিটি মালের দাম (বিলের দাম + সেই মালে বরাদ্দ freight) আগের ক্রয়ের দামের সাথে মেলানো হয়। বন্ধ = আজকের মতো, শুধু বিলের দাম দেখা হয়।',
  'চালু করলে landed cost post হওয়ার পর (invoice price + allocated freight) দিয়ে আগের ক্রয়ের সাথে তুলনা হয়। off = আজকের মতো, শুধু invoice price। Threshold = purchase_cost_jump_pct।',
  'On: after a landed cost (freight and other charges) is posted, each item is compared with its last purchase using the invoice price plus the freight allocated to it. Off = as today, the invoice price only. The threshold is purchase_cost_jump_pct.',
  5451
) on conflict (key) do nothing;

-- freight allocated to one purchase line (posted rows minus voided rows; expense and recoverable-tax parts are not in the unit cost)
create or replace function public._pc545_freight(p_bill_line bigint) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(a.amount), 0) from public.landed_cost_alloc a where a.bill_line_id = p_bill_line and a.part in ('stock', 'cogs')
$$;
revoke all on function public._pc545_freight(bigint) from public, anon, authenticated;

-- the variant: run after a landed cost is posted. Off = returns at once, writes nothing.
create or replace function public.purchase_price_check_freight545(p_cost uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pct numeric; r record; lu record; cur_c numeric; last_c numeric; fr numeric; checked int := 0; flagged int := 0; nm text;
begin
  if not public.rule_on('price_check_include_freight') then
    return jsonb_build_object('on', false, 'checked', 0, 'flagged', 0);
  end if;
  pct := public.rule_num('purchase_cost_jump_pct');
  if pct is null then
    return jsonb_build_object('on', true, 'checked', 0, 'flagged', 0, 'why', 'threshold_blank');
  end if;
  for r in
    select pl.id as bill_line_id, pl.bill_id, pl.item_id, pl.unit_cost_base, pl.base_qty, b.location_id, b.bill_no, b.bill_date, b.posted_at, it.name_bn, it.name_en
      from (select distinct a.bill_line_id from public.landed_cost_alloc a
             where a.cost_id = p_cost and a.kind = 'post' and a.part in ('stock', 'cogs') and a.bill_line_id is not null) x
      join public.purchase_lines pl on pl.id = x.bill_line_id
      join public.purchase_bills b on b.id = pl.bill_id
      join public.items it on it.id = pl.item_id
     where b.kind = 'bill' and b.status = 'posted' and pl.unit_cost_base is not null and pl.base_qty > 0
     order by pl.id
  loop
    checked := checked + 1;
    fr := public._pc545_freight(r.bill_line_id);
    cur_c := r.unit_cost_base + fr / r.base_qty;
    -- the last posted purchase of the same item before this bill (same rule as purchase_post: bills only, not returns)
    select pl2.id as bill_line_id, pl2.unit_cost_base, pl2.base_qty into lu
      from public.purchase_lines pl2 join public.purchase_bills x on x.id = pl2.bill_id
     where pl2.item_id = r.item_id and x.status = 'posted' and x.kind = 'bill' and x.id <> r.bill_id
       and x.posted_at < r.posted_at and pl2.unit_cost_base is not null and pl2.base_qty > 0
     order by x.posted_at desc, pl2.id desc limit 1;
    if not found then continue; end if;
    last_c := lu.unit_cost_base + public._pc545_freight(lu.bill_line_id) / lu.base_qty;
    if last_c > 0 and abs(cur_c - last_c) / last_c * 100 > pct then
      flagged := flagged + 1;
      nm := coalesce(r.name_bn, '');
      perform public._stock_exc(r.location_id, 'purchase_price_jump', 'yellow',
        nm || ': ফ্রেইটসহ ক্রয়মূল্য আগের চেয়ে ' || round((cur_c - last_c) / last_c * 100, 1)::text || '% বদলেছে (বিল ' || coalesce(r.bill_no, '-') || ', freight সহ)',
        coalesce(r.name_en, nm) || ': unit cost with freight moved ' || round((cur_c - last_c) / last_c * 100, 1)::text || '% from the last purchase (bill ' || coalesce(r.bill_no, '-') || ')',
        null, r.bill_date, 'PURCHASE', null);
    end if;
  end loop;
  return jsonb_build_object('on', true, 'checked', checked, 'flagged', flagged);
end $$;
revoke all on function public.purchase_price_check_freight545(uuid) from public, anon, authenticated;

-- the trigger: fires only when a landed cost changes to posted (landed_post); nothing else is touched
create or replace function public._pc545_after_landed_post() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'posted' and old.status is distinct from 'posted' then
    perform public.purchase_price_check_freight545(new.id);
  end if;
  return null;
end $$;
revoke all on function public._pc545_after_landed_post() from public, anon, authenticated;

drop trigger if exists landed_costs_price_freight545 on public.landed_costs;
create trigger landed_costs_price_freight545 after update of status on public.landed_costs
  for each row execute function public._pc545_after_landed_post();
