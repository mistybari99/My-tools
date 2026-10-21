-- Phase 141 (bos141) - W1-FIX: the supplier payment limit can count over several days (finding 5 of the independent Wave 1 check). Paste after phase99, paste-twice safe.
-- Earlier phase files are not edited.
--
-- THE GAP: supplier_pay_over (phase94) is compared with the total of ONE pay_supplier call. A person who is not the owner can pay the same supplier in several
-- smaller calls and stay under the limit every time.
--
-- WHAT THIS ADDS: ONE owner setting, supplier_pay_over_cumulative_days (number of days, default 0 = exactly today: the limit is per call). When N is more than 0
-- the limit is compared with THIS payment PLUS what the SAME person has already paid to the SAME supplier in the last N days (payments not voided, plus that
-- person's requests still waiting for the approver). Approved requests are already payments (the payment keeps the maker's login), so nothing is counted twice.
-- The owner is still never held. The approver sees the reason in the request text ("plus Tk ... already paid or waiting by this person in the last N days").
--
-- HOW: two exact-text lines in _w1e_pay_gate (marker bos141), patched with _w1x_patch (docs/integration/W1-FIX.md). With the setting at 0 both helpers return
-- 0 / empty text and the gate behaves exactly as before. phase143 puts the lines back if phase94 is pasted again.

do $g$ begin
  if to_regprocedure('public._w1e_pay_gate(uuid,integer,jsonb,uuid,text,numeric)') is null then raise exception 'phase141 needs phase94 (and phase99)'; end if;
  if to_regprocedure('public._i1_apply_hooks()') is null then raise exception 'phase141 needs phase99 pasted first'; end if;
end $g$;

create or replace function public._w1x_present141() returns boolean language sql immutable as $$ select true $$;

-- patch helper of this package (same text as in phase140; create or replace is harmless to repeat)
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

-- ---------- setting (default 0 = per call, as today) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('supplier_pay_over_cumulative_days', 'books', 'number', '0'::jsonb, 'days', null, 0, 365,
  'Supplier payment limit counts payments of the last days', 'Supplier payment limit counts payments of the last days', 'Supplier payment limit counts payments of the last days',
  'Number of days. 0 = today: the limit above is compared with each payment on its own, so paying in smaller parts avoids it. A number of days (for example 7) = the limit is compared with this payment plus what the same person already paid to the same supplier in those days. The owner is not held. Only used when "A supplier payment above this amount waits for the approver" has a number',
  'Number of days. 0 = today: the limit above is compared with each payment on its own, so paying in smaller parts avoids it. A number of days (for example 7) = the limit is compared with this payment plus what the same person already paid to the same supplier in those days. The owner is not held. Only used when "A supplier payment above this amount waits for the approver" has a number',
  'Number of days. 0 = today: the limit above is compared with each payment on its own, so paying in smaller parts avoids it. A number of days (for example 7) = the limit is compared with this payment plus what the same person already paid to the same supplier in those days. The owner is not held. Only used when "A supplier payment above this amount waits for the approver" has a number', 750)
on conflict (key) do nothing;

-- ---------- what this person already paid or has waiting for this supplier in the last N days (0 when the setting is 0) ----------
create or replace function public._w1x_pay_prior(p_supplier uuid) returns numeric language plpgsql stable security definer set search_path = public as $$
declare n numeric := coalesce(public.rule_num('supplier_pay_over_cumulative_days'), 0); since timestamptz; paid numeric; waiting numeric;
begin
  if n <= 0 or auth.uid() is null then return 0; end if;
  since := now() - make_interval(secs => (n * 86400)::double precision);
  select coalesce(sum(amount), 0) into paid from public.supplier_payments where supplier_id = p_supplier and not voided and created_by = auth.uid() and paid_at >= since;
  select coalesce(sum((q.payload ->> 'total')::numeric), 0) into waiting from public.w1e_requests q
   where q.kind = 'supplier_pay' and q.status = 'pending' and q.requested_by = auth.uid() and q.payload ->> 'supplier' = p_supplier::text and q.requested_at >= since;
  return paid + waiting;
end $$;
revoke all on function public._w1x_pay_prior(uuid) from public, anon, authenticated;

-- the sentence added to the request text when earlier payments were counted
create or replace function public._w1x_pay_note(p_supplier uuid) returns text language plpgsql stable security definer set search_path = public as $$
declare pr numeric := public._w1x_pay_prior(p_supplier); n numeric := coalesce(public.rule_num('supplier_pay_over_cumulative_days'), 0);
begin
  if pr <= 0 then return ''; end if;
  return ', plus ' || trim_scale(pr)::text || ' already paid or waiting by this person in the last ' || trim_scale(n)::text || ' day(s)';
end $$;
revoke all on function public._w1x_pay_note(uuid) from public, anon, authenticated;

-- ---------- the hooks (idempotent: nothing happens when marker bos141 is already inside _w1e_pay_gate) ----------
create or replace function public._w1x141_hooks() returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return jsonb_build_object('_w1e_pay_gate', public._w1x_patch('public._w1e_pay_gate(uuid,integer,jsonb,uuid,text,numeric)'::regprocedure, array[
    E'  if ov is not null and p_tot > ov and not public.is_owner() then',
    E'  if ov is not null and p_tot + public._w1x_pay_prior(p_supplier) > ov and not public.is_owner() then   /* bos141 */',
    E'|| '' (limit '' || ov::text || '')'', 300)',
    E'|| '' (limit '' || ov::text || public._w1x_pay_note(p_supplier) || '')'', 300)'
  ], 'bos141'));
end $$;
revoke all on function public._w1x141_hooks() from public, anon, authenticated;

select public._w1x141_hooks();
