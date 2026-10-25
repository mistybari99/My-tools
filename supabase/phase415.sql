-- Phase 415 (bos415) - RPT-B4 / R9a: OWNER SETTING FOR THE VALUE OF GOODS MOVED BETWEEN UNITS (factory -> shops).
-- Paste after phase404 (it uses the helper _rb4_today; phases 405-413 are not needed). Paste-twice safe. No earlier phase file is edited.
-- Requirement: docs/REPORTS_AUDIT_1.md item #7 (factory vs retail): stock_transfers carry no value, so a factory result cannot be told from a retail result. The owner decides the basis:
--
--   transfer_valuation_basis   none (DEFAULT, as today)  the report says "not valued" and shows quantities and the ledger cost only
--                              cost                       goods moved at what they cost the factory (the ledger cost of the transfer-out line): the factory shows no margin on transfers
--                              price_pct                  goods moved at a percentage of the item's selling price (setting transfer_price_pct); a blank percentage or a blank selling price = "not valued", never a guess
--   transfer_price_pct         the percentage for price_pct. BLANK by default (a blank number blocks the basis that needs it, BUILD-RULES 15).
-- The setting changes only the report (phase 416). No stock, no journal and no price changes.

do $g$ begin
  if to_regprocedure('public._rb4_today()') is null then raise exception 'phase415 needs phase404 first'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('transfer_valuation_basis', 'reports', 'choice', '"none"'::jsonb, '["none", "cost", "price_pct"]'::jsonb, null, null,
  'কারখানা থেকে শোরুমে পাঠানো মালের দাম কীভাবে ধরা হবে (শুধু রিপোর্টে)', 'Factory থেকে showroom-এ পাঠানো মালের দাম কীভাবে ধরা হবে (শুধু report-এ)',
  'How goods moved between units are valued (reports only)',
  'none = not valued (default, as today). cost = the factory cost from the stock ledger. price_pct = a percentage of the selling price (set transfer_price_pct). Changes only the factory-vs-retail report; no stock or money moves.', 7010),
 ('transfer_price_pct', 'reports', 'number', null, null, 0, 1000,
  'পাঠানো মালের দাম = বিক্রয়মূল্যের এত শতাংশ (শুধু "price_pct" হলে)', 'পাঠানো মালের দাম = selling price-এর এত % (শুধু "price_pct" হলে)',
  'Moved goods are valued at this % of the selling price (only when the basis is price_pct)',
  'Blank = no value is worked out for that basis; the report says "percentage not set".', 7011)
on conflict (key) do nothing;

-- the value of one transfer line under the owner's basis; the state says why a value is missing
create or replace function public._rb4_transfer_value(p_item uuid, p_qty numeric, p_unit_cost numeric, p_basis text default null, p_pct numeric default null, out value numeric, out state text)
language plpgsql stable security definer set search_path = public as $$
declare b text := coalesce(p_basis, public.rule_txt('transfer_valuation_basis'), 'none'); pct numeric := coalesce(p_pct, public.rule_num('transfer_price_pct')); sp numeric;
begin
  if b = 'cost' then
    if p_unit_cost is null or p_unit_cost <= 0 then value := null; state := 'cost_not_captured'; else value := round(p_qty * p_unit_cost, 2); state := 'at_cost'; end if;
  elsif b = 'price_pct' then
    select sell_price into sp from public.items where id = p_item;
    if pct is null then value := null; state := 'pct_not_set';
    elsif sp is null or sp <= 0 then value := null; state := 'price_not_captured';
    else value := round(p_qty * sp * pct / 100, 2); state := 'pct_of_price'; end if;
  else
    value := null; state := 'not_valued';
  end if;
end $$;

revoke all on function public._rb4_transfer_value(uuid, numeric, numeric, text, numeric) from public, anon, authenticated;

notify pgrst, 'reload schema';
