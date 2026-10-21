-- Phase 140 (bos140) - W1-FIX: a sale void follows the return rules (finding 4 of the independent Wave 1 check). Paste after phase99, paste-twice safe. Earlier phase files are not edited.
--
-- THE GAP: void_sale cancels a whole sale and the stock trigger puts every unit back on the shelf, with no return window, no "never put back" class rule and no
-- expired-batch rule. A person who is refused a return (phase91) could void the sale instead.
--
-- WHAT THIS ADDS: ONE owner setting, void_follows_return_rules (switch, default OFF = exactly today). When ON, void_sale asks the same questions the return
-- code asks (phase91): is the sale inside the return window of each item class, is any item in a class that is never put back (a void puts everything back),
-- and (rule return_expired_restock = writeoff or block) would an expired batch go back on the shelf. If any answer is "no" the void is REFUSED with the
-- same code the return screen already shows (return_window_exceeded, return_restock_not_allowed, return_expired_restock) unless the caller holds the grant
-- return_override (the owner always does; the owner can give it to anyone). That override needs the void note (already required) as its reason and writes one
-- audit_log line (void_override) and one row in the Exceptions list (flag void_outside_return_rules). The receipt rule is not asked: a void is made from the sale itself.
--
-- HOW: one hook line in void_sale, written by the patch helper _w1x_patch (marker bos140), exactly as the Wave 1 packages did it (docs/integration/W1-FIX.md).
-- phase143 (re-patch) puts the line back if an old phase re-creates void_sale. With the setting OFF the hook returns at once: nothing else changes.

do $g$ begin
  if to_regprocedure('public._w1c_present91()') is null then raise exception 'phase140 needs phase91 (and phase99)'; end if;
  if to_regprocedure('public._i1_apply_hooks()') is null then raise exception 'phase140 needs phase99 pasted first'; end if;
  if to_regprocedure('public.void_sale(uuid,text)') is null then raise exception 'phase140 needs void_sale'; end if;
end $g$;

create or replace function public._w1x_present140() returns boolean language sql immutable as $$ select true $$;

-- patch helper of this package (same logic as _w1c_patch; markers bos140 to bos149)
create or replace function public._w1x_patch(p_fn regprocedure, p_pairs text[], p_marker text) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int; n int;
begin
  if p_marker is null or p_marker !~ '^bos14[0-9]$' then raise exception 'w1x_patch: bad marker'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    n := (length(def) - length(replace(def, p_pairs[i], ''))) / greatest(length(p_pairs[i]), 1);
    if n = 0 then raise exception 'w1x_patch: patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    if n > 1 then raise exception 'w1x_patch: patch site is not unique in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'w1x_patch: patch of % carries no marker', p_fn::text; end if;
  execute def;
  return true;
end $$;
revoke all on function public._w1x_patch(regprocedure, text[], text) from public, anon, authenticated;

-- ---------- setting (default OFF) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('void_follows_return_rules', 'pos', 'switch', 'false'::jsonb, null, null, null, null,
  'Voiding a sale follows the return rules', 'Voiding a sale follows the return rules', 'Voiding a sale follows the return rules',
  'Off = today: a sale can be voided at any time by anyone who may void. On = a void is refused when a return of the same sale would be refused (return window, goods that are never put back, expired batch). The owner and anyone with the grant return_override may still void, with the void note as the reason; it is logged in the Exceptions list',
  'Off = today: a sale can be voided at any time by anyone who may void. On = a void is refused when a return of the same sale would be refused (return window, goods that are never put back, expired batch). The owner and anyone with the grant return_override may still void, with the void note as the reason; it is logged in the Exceptions list',
  'Off = today: a sale can be voided at any time by anyone who may void. On = a void is refused when a return of the same sale would be refused (return window, goods that are never put back, expired batch). The owner and anyone with the grant return_override may still void, with the void note as the reason; it is logged in the Exceptions list', 910)
on conflict (key) do nothing;

-- ---------- the check, called from the hook line in void_sale ----------
create or replace function public._w1x_void_guard(p_sale uuid, p_note text default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.sales; lines jsonb; rs jsonb; ev jsonb; v text[] := '{}'; gwin numeric; age numeric; note text := nullif(btrim(coalesce(p_note, '')), ''); lvl text := 'yellow';
        uuid_re constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
begin
  if not coalesce(public.rule_on('void_follows_return_rules'), false) then return jsonb_build_object('skipped', 'setting_off'); end if;
  select * into s from public.sales where id = p_sale;
  if not found then return jsonb_build_object('skipped', 'not_found'); end if;
  -- the item lines of the sale, one line per item: a void puts the whole quantity of every item back on the shelf
  select jsonb_agg(jsonb_build_object('item_id', x.iid, 'qty', x.q) order by x.iid), jsonb_agg(jsonb_build_object('item_id', x.iid, 'restock_qty', x.q) order by x.iid)
    into lines, rs
    from (select e ->> 'item_id' iid, round(sum((e ->> 'qty')::numeric), 6)::text q
            from jsonb_array_elements(s.lines) e
           where jsonb_typeof(e) = 'object' and coalesce(e ->> 'item_id', '') ~ uuid_re and coalesce(e ->> 'qty', '') ~ '^[0-9]{1,9}(\.[0-9]{1,6})?$' and (e ->> 'qty')::numeric > 0
           group by 1) x
   where x.q::numeric > 0;
  if lines is not null then
    ev := public._w1c_return_eval(p_sale, lines, rs, s.receipt::text);        -- the receipt of this very sale is "shown"
    select coalesce(array_agg(z), '{}') into v from jsonb_array_elements_text(ev -> 'violations') z;
  else
    gwin := public.rule_num('return_window_hours');                            -- a sale without item lines (quick sale): only the general window can be asked
    age := round(extract(epoch from (now() - s.sold_at)) / 3600, 2);
    if gwin is not null and age > gwin then v := array['return_window_exceeded']; end if;
  end if;
  -- a void cannot write expired goods off, so in the modes writeoff and block it may not put them back on the shelf
  if coalesce(public.rule_txt('return_expired_restock'), 'allow') in ('writeoff', 'block')
     and exists (select 1 from public.stock_ledger l join public.stock_batches b on b.id = l.batch_id
                  where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out' and b.expires_at is not null and b.expires_at <= now()) then
    v := array_append(v, 'return_expired_restock'::text);
    lvl := 'red';
  end if;
  if array_length(v, 1) is null then return jsonb_build_object('ok', true); end if;
  -- outside the rules: only the owner or a person holding return_override, and only with a reason
  if not public.has_grant('return_override', s.location_id) then raise exception '%', v[1]; end if;
  if note is null or char_length(note) < 3 then raise exception 'return_override_reason_required'; end if;
  perform public._w1c_audit('void_override', 'sales', s.id::text, jsonb_build_object('receipt', s.receipt, 'rules_broken', to_jsonb(v), 'reason', note, 'amount', s.total, 'owner', public.is_owner()));
  perform public._w1c_exc(s.location_id, 'POS', 'void_outside_return_rules', lvl,
    'Receipt ' || s.receipt::text || ' was voided outside the return rules (' || array_to_string(v, ', ') || '). Reason: ' || note, s.id::text, s.total, s.sale_date);
  return jsonb_build_object('ok', true, 'override', true, 'rules_broken', to_jsonb(v));
end $$;
revoke all on function public._w1x_void_guard(uuid, text) from public, anon, authenticated;

-- ---------- the hook (idempotent: nothing happens when marker bos140 is already inside void_sale) ----------
create or replace function public._w1x140_hooks() returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return jsonb_build_object('void_sale', public._w1x_patch('public.void_sale(uuid,text)'::regprocedure, array[
    E'  if s.status = ''void'' then raise exception ''already void''; end if;',
    E'  if s.status = ''void'' then raise exception ''already void''; end if;\n  perform public._w1x_void_guard(s.id, p_note); /* bos140 */'
  ], 'bos140'));
end $$;
revoke all on function public._w1x140_hooks() from public, anon, authenticated;

select public._w1x140_hooks();
