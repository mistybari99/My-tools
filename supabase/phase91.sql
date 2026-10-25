-- Phase 91 (bos91) - U-04 SALE RETURN CONTROL. Paste after phase90, paste-twice safe. Earlier phase files are not edited.
-- Package W1-C (Wave 1). New functions all carry the prefix _w1c_. sale_return and void_sale_return are integrator-owned and are NOT changed here:
-- the two hook lines they need are written in docs/integration/W1-C.md and proved on a scratch copy in phase91_test.sql.
--
-- WHAT THIS ADDS (everything is a setting, the owner edits it at any time, every change is an audit_log line)
--   Per item class (items.category) in w1c_return_class_rules: restock = restock | no_restock, window_hours (blank = no limit), receipt_required (blank = follow the global switch),
--   effective_from. A class without a row behaves exactly as today (goods go back on the shelf, any age, no receipt).
--   Global rules: return_needs_receipt (off), return_window_hours (blank = off, used by classes without their own window), return_expired_restock (allow [today] | writeoff | block).
--   At the moment a return is saved:
--     * the quantity that may not go back on the shelf is written off at once: the goods are put back by the existing return code, then written off through the
--       existing wastage source (stock_wastage, reason customer_return) at the SAME cost, so the books show Dr 5100 wastage / Cr inventory and balance;
--     * the cashier may choose to write off more (restock_qty per item), never to restock a no_restock class without an override;
--     * a return past its window, without the receipt number, or restocking an expired batch (mode block) is refused unless an override with a reason is given
--       by a person who holds the grant return_override (the owner always does; the owner can give it to anyone, also through an emergency request);
--       each override writes one audit_log line and one row in the Exceptions list.
--   Disposition of every return is kept (w1c_returns, w1c_return_lines, append-only) for the report "returns by reason: restocked or written off".
--   _w1c_sale_return(...) is the call for the screen. It works with or without the hook line; the hook makes a direct sale_return call obey the same rules.
-- NOTHING CHANGES until the owner adds a class rule or switches a global rule (defaults: no rows, receipt off, window blank, expired = allow).

do $g$ begin
  if to_regprocedure('public._w1c_present90()') is null then raise exception 'phase91 needs phase90'; end if;
  if to_regprocedure('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)') is null or to_regprocedure('public.void_sale_return(uuid,text)') is null
     or to_regprocedure('public.stock_post(uuid,integer,numeric,text,text,text,numeric,bigint,timestamp with time zone,text,bigint,text,uuid,uuid)') is null then
    raise exception 'phase91 needs the sale return and stock functions (phase12)';
  end if;
end $g$;

create or replace function public._w1c_present91() returns boolean language sql immutable as $$ select true $$;

-- same patch helper as phase90 (create or replace: harmless to repeat)
create or replace function public._w1c_patch(p_fn regprocedure, p_pairs text[], p_marker text) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int; n int;
begin
  if p_marker is null or p_marker !~ '^bos[0-9]{2,3}$' then raise exception 'w1c_patch: bad marker'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    n := (length(def) - length(replace(def, p_pairs[i], ''))) / greatest(length(p_pairs[i]), 1);
    if n = 0 then raise exception 'w1c_patch: patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    if n > 1 then raise exception 'w1c_patch: patch site is not unique in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'w1c_patch: patch of % carries no marker', p_fn::text; end if;
  execute def;
  return true;
end $$;
revoke all on function public._w1c_patch(regprocedure, text[], text) from public, anon, authenticated;

-- ---------- tables ----------
create table if not exists public.w1c_return_class_rules (
  class_code text primary key check (char_length(btrim(class_code)) between 1 and 60),
  restock text not null default 'restock' check (restock in ('restock', 'no_restock')),
  window_hours numeric check (window_hours is null or (window_hours > 0 and window_hours <= 100000)),
  receipt_required boolean,
  effective_from date not null default ((now() at time zone 'Asia/Dhaka')::date),
  active boolean not null default true,
  note text check (note is null or char_length(note) <= 300),
  updated_by uuid, updated_at timestamptz not null default now()
);
drop trigger if exists audit_w1c_return_class_rules on public.w1c_return_class_rules;
create trigger audit_w1c_return_class_rules after insert or update on public.w1c_return_class_rules for each row execute function public.log_change('class_code');
drop trigger if exists w1c_return_class_rules_nodel on public.w1c_return_class_rules;
create trigger w1c_return_class_rules_nodel before delete on public.w1c_return_class_rules for each row execute function public.no_hard_delete();
alter table public.w1c_return_class_rules enable row level security;
drop policy if exists w1c_return_class_rules_read on public.w1c_return_class_rules;
create policy w1c_return_class_rules_read on public.w1c_return_class_rules for select to authenticated using (public.is_owner());
revoke all on table public.w1c_return_class_rules from anon, authenticated; grant select on table public.w1c_return_class_rules to authenticated;

create table if not exists public.w1c_returns (
  return_id uuid primary key references public.sale_returns(id),
  sale_id uuid not null references public.sales(id),
  location_id int not null,
  age_hours numeric, receipt_shown text,
  override boolean not null default false, override_kinds text[], override_reason text,
  created_by uuid, created_at timestamptz not null default now()
);
create table if not exists public.w1c_return_lines (
  id bigserial primary key,
  return_id uuid not null references public.w1c_returns(return_id),
  item_id uuid not null, class_code text, unit text,
  qty numeric not null, restock_qty numeric not null, writeoff_qty numeric not null,
  restock_base numeric not null default 0, writeoff_base numeric not null default 0, writeoff_value numeric not null default 0,
  decision text not null check (decision in ('restocked', 'written_off', 'split', 'not_tracked')),
  basis text not null check (basis in ('default', 'class_rule', 'cashier_choice', 'expired_batch', 'override')),
  wastage_ids uuid[] not null default '{}'
);
create index if not exists w1c_return_lines_ret on public.w1c_return_lines (return_id);
drop trigger if exists w1c_returns_ro on public.w1c_returns;
create trigger w1c_returns_ro before update or delete on public.w1c_returns for each row execute function public._w1c_append_only();
drop trigger if exists w1c_return_lines_ro on public.w1c_return_lines;
create trigger w1c_return_lines_ro before update or delete on public.w1c_return_lines for each row execute function public._w1c_append_only();
alter table public.w1c_returns enable row level security;
alter table public.w1c_return_lines enable row level security;
drop policy if exists w1c_returns_read on public.w1c_returns;
create policy w1c_returns_read on public.w1c_returns for select to authenticated using (public.can_loc(location_id) and (public.is_owner() or public.has_grant('sale_return', location_id)));
drop policy if exists w1c_return_lines_read on public.w1c_return_lines;
create policy w1c_return_lines_read on public.w1c_return_lines for select to authenticated
  using (exists (select 1 from public.w1c_returns h where h.return_id = w1c_return_lines.return_id and public.can_loc(h.location_id) and (public.is_owner() or public.has_grant('sale_return', h.location_id))));
revoke all on table public.w1c_returns, public.w1c_return_lines from anon, authenticated; grant select on table public.w1c_returns, public.w1c_return_lines to authenticated;
revoke all on sequence public.w1c_return_lines_id_seq from anon, authenticated;

-- ---------- settings, grant, wastage reason (own keys only, on conflict do nothing) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('return_needs_receipt', 'pos', 'switch', 'false'::jsonb, null, null, null, null,
  'A sale return must show the receipt number', 'A sale return must show the receipt number', 'A sale return must show the receipt number',
  'Off = today: any return of a recorded sale is accepted. On = the receipt number must be typed and match the sale. A class can override this',
  'Off = today: any return of a recorded sale is accepted. On = the receipt number must be typed and match the sale. A class can override this',
  'Off = today: any return of a recorded sale is accepted. On = the receipt number must be typed and match the sale. A class can override this', 905),
 ('return_window_hours', 'pos', 'number', null, 'hours', null, 1, 87600,
  'Return window (hours after the sale)', 'Return window (hours after the sale)', 'Return window (hours after the sale)',
  'Blank = no limit (today). Used for every item class that has no window of its own. Past the window a return needs an override with a reason',
  'Blank = no limit (today). Used for every item class that has no window of its own. Past the window a return needs an override with a reason',
  'Blank = no limit (today). Used for every item class that has no window of its own. Past the window a return needs an override with a reason', 906),
 ('return_expired_restock', 'pos', 'choice', '"allow"'::jsonb, null, '["allow","writeoff","block"]'::jsonb, null, null,
  'Returned goods from an expired batch', 'Returned goods from an expired batch', 'Returned goods from an expired batch',
  'allow = back on the shelf (today); writeoff = written off automatically; block = refused unless an override with a reason',
  'allow = back on the shelf (today); writeoff = written off automatically; block = refused unless an override with a reason',
  'allow = back on the shelf (today); writeoff = written off automatically; block = refused unless an override with a reason', 907)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
values ('return_override', 'pos', 905, 'Approve a sale return outside the return rules', 'Approve a sale return outside the return rules', 'Approve a sale return outside the return rules', 'window')
on conflict (grant_code) do nothing;

do $o$ begin
  insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort, active)
    values ('wastage_reasons', 'customer_return', 'Customer return, not for resale', 'Customer return, not for resale', 'Customer return, not for resale', 905, true)
    on conflict (list_code, value_code) do nothing;
exception when others then
  raise notice 'phase91: the wastage reason customer_return could not be added (%): add it by hand in Lists', sqlerrm;
end $o$;

-- ---------- helpers ----------
create or replace function public._w1c_class_of(p_item uuid) returns text language sql stable security definer set search_path = public as $$
  select coalesce(nullif(btrim(i.category), ''), '-') from public.items i where i.id = p_item $$;
revoke all on function public._w1c_class_of(uuid) from public, anon, authenticated;

-- ---------- the check (read only): what does the rule say about this return? ----------
-- p_lines = [{item_id, qty}], p_restock = [{item_id, restock_qty}] or null (null = the class default for every item)
create or replace function public._w1c_return_eval(p_sale uuid, p_lines jsonb, p_restock jsonb, p_receipt text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.sales; ln record; rl record; cr public.w1c_return_class_rules; has_cr boolean; cls text; q numeric; dflt numeric; arg numeric; given boolean; rq numeric; win numeric; need boolean; rec_ok boolean;
        age numeric; lines_out jsonb := '[]'::jsonb; allv text[] := '{}'; lv text[]; today date := (now() at time zone 'Asia/Dhaka')::date;
        gwin numeric := public.rule_num('return_window_hours'); gneed boolean := public.rule_on('return_needs_receipt');
        uuid_re constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'; qty_re constant text := '^[0-9]{1,9}(\.[0-9]{1,6})?$';
begin
  select * into s from public.sales where id = p_sale;
  if not found then raise exception 'sale_not_found'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  age := round(extract(epoch from (now() - s.sold_at)) / 3600, 2);
  rec_ok := regexp_replace(coalesce(p_receipt, ''), '[^0-9]', '', 'g') = s.receipt::text;
  if p_restock is not null and jsonb_typeof(p_restock) not in ('array', 'null') then raise exception 'return_bad_restock_qty'; end if;
  if p_restock is not null and jsonb_typeof(p_restock) = 'array' then
    for rl in select e from jsonb_array_elements(p_restock) e loop
      if jsonb_typeof(rl.e) <> 'object' or coalesce(rl.e ->> 'item_id', '') !~ uuid_re or coalesce(rl.e ->> 'restock_qty', '') !~ qty_re then raise exception 'return_bad_restock_qty'; end if;
      if not exists (select 1 from jsonb_array_elements(p_lines) x where x ->> 'item_id' = rl.e ->> 'item_id') then raise exception 'return_bad_restock_qty'; end if;
    end loop;
  end if;
  for ln in select e ->> 'item_id' iid, sum((e ->> 'qty')::numeric) q from jsonb_array_elements(p_lines) e
             where jsonb_typeof(e) = 'object' and coalesce(e ->> 'item_id', '') ~ uuid_re and coalesce(e ->> 'qty', '') ~ qty_re group by 1 order by 1 loop
    q := ln.q;
    cls := public._w1c_class_of(ln.iid::uuid);
    select * into cr from public.w1c_return_class_rules where class_code = cls and active and effective_from <= today;
    has_cr := found;
    dflt := case when has_cr and cr.restock = 'no_restock' then 0 else q end;
    arg := null;
    if p_restock is not null and jsonb_typeof(p_restock) = 'array' then
      select (x ->> 'restock_qty')::numeric into arg from jsonb_array_elements(p_restock) x where x ->> 'item_id' = ln.iid limit 1;
    end if;
    given := arg is not null;
    if given and arg > q + 0.00005 then raise exception 'return_bad_restock_qty'; end if;
    rq := coalesce(arg, dflt);
    lv := '{}';
    if has_cr and cr.restock = 'no_restock' and rq > 0.00005 then lv := array_append(lv, 'return_restock_not_allowed'::text); end if;
    win := case when has_cr and cr.window_hours is not null then cr.window_hours else gwin end;
    if win is not null and age > win then lv := array_append(lv, 'return_window_exceeded'::text); end if;
    need := coalesce(case when has_cr then cr.receipt_required end, gneed);
    if need and not rec_ok then lv := array_append(lv, 'return_receipt_required'::text); end if;
    allv := allv || lv;
    lines_out := lines_out || jsonb_build_object('item_id', ln.iid, 'class', cls, 'qty', q, 'default_restock_qty', dflt, 'restock_qty', rq, 'given', given,
      'restock_rule', case when has_cr then cr.restock else 'restock' end, 'window_hours', win, 'receipt_needed', need, 'violations', to_jsonb(lv));
  end loop;
  return jsonb_build_object('age_hours', age, 'receipt_ok', rec_ok, 'lines', lines_out,
    'violations', coalesce((select jsonb_agg(distinct v) from unnest(allv) v), '[]'::jsonb));
end $$;
revoke all on function public._w1c_return_eval(uuid, jsonb, jsonb, text) from public, anon, authenticated;

-- write off a quantity of returned goods through the existing wastage source, at the cost of the return row (so the books net to the loss)
create or replace function public._w1c_writeoff(p_item uuid, p_loc int, p_bq numeric, p_batch bigint, p_cost numeric, p_note text) returns uuid
language plpgsql security definer set search_path = public as $$
declare wid uuid := gen_random_uuid(); lid bigint;
begin
  lid := public.stock_post(p_item, p_loc, -p_bq, 'wastage', 'wastage', wid::text, p_cost, p_batch, now(), left(p_note, 200), null, 'none');
  insert into public.stock_wastage (id, item_id, location_id, qty, reason_code, note, batch_id, ledger_id, created_by, created_staff)
    values (wid, p_item, p_loc, p_bq, 'customer_return', left(p_note, 200), p_batch, lid, auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
  return wid;
end $$;
revoke all on function public._w1c_writeoff(uuid, int, numeric, bigint, numeric, text) from public, anon, authenticated;

-- ---------- the step that runs when a return is saved (hook in sale_return, or the wrapper below) ----------
create or replace function public._w1c_return_finish(p_return uuid, p_restock jsonb default null, p_receipt text default null, p_override text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.sale_returns; s public.sales; ev jsonb; v text[]; ov_reason text := nullif(left(btrim(coalesce(p_override, '')), 300), ''); ov boolean := false;
        mode text := coalesce(public.rule_txt('return_expired_restock'), 'allow'); ln jsonb; it public.items; plan jsonb := '[]'::jsonb; pl jsonb; rw record;
        total_back numeric; wo numeric; exp_tot numeric; remaining numeric; chunk numeric; basis text; bad_exp boolean := false; wids uuid[]; wid uuid; wval numeric; rq_final numeric; rbase numeric;
        n_wo int := 0; n_rs int := 0; dec text; lvl text := 'yellow';
begin
  select * into r from public.sale_returns where id = p_return;
  if not found then raise exception 'not_found'; end if;
  if exists (select 1 from public.w1c_returns h where h.return_id = p_return) then return jsonb_build_object('skipped', 'done'); end if;
  select * into s from public.sales where id = r.sale_id;
  ev := public._w1c_return_eval(r.sale_id, r.lines, p_restock, p_receipt);
  select coalesce(array_agg(x), '{}') into v from jsonb_array_elements_text(ev -> 'violations') x;

  -- plan: how much of each item goes back on the shelf, how much is written off
  for ln in select e from jsonb_array_elements(ev -> 'lines') e loop
    select * into it from public.items where id = (ln ->> 'item_id')::uuid;
    if it.tracked is not true then
      plan := plan || jsonb_build_object('item_id', it.id, 'class', ln ->> 'class', 'qty', (ln ->> 'qty')::numeric, 'restock_qty', (ln ->> 'restock_qty')::numeric, 'wo', 0, 'total_back', 0, 'basis', 'default', 'decision', 'not_tracked');
      continue;
    end if;
    select coalesce(sum(l.qty_delta), 0) into total_back from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.item_id = it.id;
    wo := round(total_back * (1 - least(1, (ln ->> 'restock_qty')::numeric / nullif((ln ->> 'qty')::numeric, 0))), 4);
    basis := case when (ln ->> 'given')::boolean then 'cashier_choice' when ln ->> 'restock_rule' = 'no_restock' then 'class_rule' else 'default' end;
    select coalesce(sum(l.qty_delta), 0) into exp_tot from public.stock_ledger l join public.stock_batches b on b.id = l.batch_id
      where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.item_id = it.id and b.expires_at is not null and b.expires_at <= now();
    if exp_tot > 0.0005 and mode = 'writeoff' and wo < exp_tot then wo := exp_tot; basis := 'expired_batch'; end if;
    if exp_tot > 0.0005 and mode = 'block' and exp_tot - least(wo, exp_tot) > 0.0005 then bad_exp := true; end if;
    plan := plan || jsonb_build_object('item_id', it.id, 'class', ln ->> 'class', 'qty', (ln ->> 'qty')::numeric, 'restock_qty', (ln ->> 'restock_qty')::numeric, 'wo', wo, 'total_back', total_back, 'basis', basis, 'decision', null, 'rs_viol', ln -> 'violations' @> '"return_restock_not_allowed"');
  end loop;
  if bad_exp then v := array_append(v, 'return_expired_restock'::text); end if;

  -- rule check: a violation needs an override (reason + grant), otherwise the whole return is refused
  if array_length(v, 1) is not null then
    if ov_reason is null or char_length(ov_reason) < 3 then raise exception '%', v[1]; end if;
    if not public.has_grant('return_override', s.location_id) then raise exception 'return_override_not_allowed'; end if;
    ov := true;
    if 'return_expired_restock' = any (v) then lvl := 'red'; end if;
  end if;

  insert into public.w1c_returns (return_id, sale_id, location_id, age_hours, receipt_shown, override, override_kinds, override_reason, created_by)
    values (r.id, r.sale_id, r.location_id, (ev ->> 'age_hours')::numeric, left(nullif(btrim(coalesce(p_receipt, '')), ''), 30), ov, case when ov then v end, case when ov then ov_reason end, auth.uid());

  for pl in select e from jsonb_array_elements(plan) e loop
    wo := (pl ->> 'wo')::numeric; wids := '{}'; wval := 0; remaining := wo; total_back := (pl ->> 'total_back')::numeric;
    if remaining > 0.00005 then
      for rw in select l.id, l.batch_id, l.qty_delta, l.unit_cost, coalesce(b.expires_at <= now(), false) as expd
                   from public.stock_ledger l left join public.stock_batches b on b.id = l.batch_id
                  where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.item_id = (pl ->> 'item_id')::uuid
                  order by coalesce(b.expires_at <= now(), false) desc, l.id loop
        exit when remaining <= 0.00005;
        chunk := least(rw.qty_delta, remaining);
        wid := public._w1c_writeoff((pl ->> 'item_id')::uuid, r.location_id, chunk, rw.batch_id, rw.unit_cost, 'customer return, receipt ' || s.receipt::text);
        wids := wids || wid; remaining := remaining - chunk; wval := wval + round(chunk * coalesce(rw.unit_cost, 0), 2);
      end loop;
    end if;
    rbase := total_back - (wo - greatest(remaining, 0));
    rq_final := case when total_back > 0 then round((pl ->> 'qty')::numeric * rbase / total_back, 6) else (pl ->> 'restock_qty')::numeric end;
    dec := case when pl ->> 'decision' = 'not_tracked' or total_back <= 0.00005 then 'not_tracked' when (wo - greatest(remaining, 0)) <= 0.00005 then 'restocked' when rbase <= 0.00005 then 'written_off' else 'split' end;
    if dec in ('written_off', 'split') then n_wo := n_wo + 1; end if;
    if dec in ('restocked', 'split') then n_rs := n_rs + 1; end if;
    insert into public.w1c_return_lines (return_id, item_id, class_code, unit, qty, restock_qty, writeoff_qty, restock_base, writeoff_base, writeoff_value, decision, basis, wastage_ids)
      values (r.id, (pl ->> 'item_id')::uuid, pl ->> 'class', (select e ->> 'unit' from jsonb_array_elements(r.lines) e where e ->> 'item_id' = pl ->> 'item_id' limit 1),
              (pl ->> 'qty')::numeric, rq_final, greatest((pl ->> 'qty')::numeric - rq_final, 0), greatest(rbase, 0), wo - greatest(remaining, 0), wval, dec,
              case when ov and coalesce((pl ->> 'rs_viol')::boolean, false) then 'override' else pl ->> 'basis' end, wids);
  end loop;

  if n_wo > 0 then
    perform public._w1c_audit('return_writeoff', 'sale_returns', r.id::text, jsonb_build_object('sale', r.sale_id, 'receipt', s.receipt, 'lines', (select jsonb_agg(jsonb_build_object('item', x.item_id, 'class', x.class_code,
      'writeoff_qty', x.writeoff_qty, 'value', x.writeoff_value, 'basis', x.basis)) from public.w1c_return_lines x where x.return_id = r.id and x.writeoff_base > 0)));
  end if;
  if ov then
    perform public._w1c_audit('return_override', 'sale_returns', r.id::text, jsonb_build_object('sale', r.sale_id, 'receipt', s.receipt, 'rules_broken', to_jsonb(v), 'reason', ov_reason, 'amount', r.amount, 'age_hours', ev -> 'age_hours'));
    perform public._w1c_exc(r.location_id, 'POS', 'return_override', lvl, 'Receipt ' || s.receipt::text || ': a return was accepted outside the return rules (' || array_to_string(v, ', ') || '). Reason: ' || ov_reason, r.id::text, r.amount, s.sale_date);
  end if;
  return jsonb_build_object('return', r.id, 'written_off_items', n_wo, 'restocked_items', n_rs, 'override', ov, 'rules_broken', to_jsonb(v));
end $$;
revoke all on function public._w1c_return_finish(uuid, jsonb, text, text) from public, anon, authenticated;

-- the line sale_return calls (reads what the wrapper stored for this transaction; a direct call has nothing stored and gets the defaults)
create or replace function public._w1c_return_hook(p_return uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare a jsonb := nullif(current_setting('w1c.return_args', true), '')::jsonb;
begin
  return public._w1c_return_finish(p_return, case when jsonb_typeof(a -> 'restock') = 'array' then a -> 'restock' end, a ->> 'receipt', a ->> 'override');
end $$;
revoke all on function public._w1c_return_hook(uuid) from public, anon, authenticated;

-- the line void_sale_return calls: a return that wrote goods off cannot be voided (the write-off cannot be undone in the books; correct it with a stock adjustment)
create or replace function public._w1c_return_void_guard(p_return uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.w1c_return_lines x where x.return_id = p_return and x.writeoff_base > 0.00005) then raise exception 'return_written_off' using hint = 'Goods of this return were written off; fix with a stock adjustment'; end if;
end $$;
revoke all on function public._w1c_return_void_guard(uuid) from public, anon, authenticated;

-- ---------- the call for the screen ----------
create or replace function public._w1c_sale_return(p_client uuid, p_sale uuid, p_lines jsonb, p_reason text, p_note text default null, p_refund_mode text default null, p_wallet text default null, p_ref text default null,
                                                   p_restock_lines jsonb default null, p_receipt_no text default null, p_override_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare res jsonb; fin jsonb; rid uuid;
begin
  perform set_config('w1c.return_args', jsonb_build_object('restock', p_restock_lines, 'receipt', p_receipt_no, 'override', p_override_reason)::text, true);
  res := public.sale_return(p_client, p_sale, p_lines, p_reason, p_note, p_refund_mode, p_wallet, p_ref);
  if coalesce((res ->> 'dup')::boolean, false) then perform set_config('w1c.return_args', '', true); return res; end if;
  rid := (res ->> 'id')::uuid;
  fin := public._w1c_return_finish(rid, case when jsonb_typeof(p_restock_lines) = 'array' then p_restock_lines end, p_receipt_no, p_override_reason);   -- skipped when the hook already did it
  if fin ? 'skipped' then
    fin := (select jsonb_build_object('return', h.return_id, 'override', h.override, 'rules_broken', coalesce(to_jsonb(h.override_kinds), '[]'::jsonb),
              'written_off_items', (select count(*) from public.w1c_return_lines x where x.return_id = h.return_id and x.writeoff_base > 0.00005),
              'restocked_items', (select count(*) from public.w1c_return_lines x where x.return_id = h.return_id and x.restock_base > 0.00005)) from public.w1c_returns h where h.return_id = rid);
  end if;
  perform set_config('w1c.return_args', '', true);
  return res || jsonb_build_object('w1c', fin);
end $$;
revoke all on function public._w1c_sale_return(uuid, uuid, jsonb, text, text, text, text, text, jsonb, text, text) from public, anon;
grant execute on function public._w1c_sale_return(uuid, uuid, jsonb, text, text, text, text, text, jsonb, text, text) to authenticated;

-- preview for the picker: defaults and rule hits before the cashier saves (read only)
create or replace function public._w1c_return_preview(p_sale uuid, p_lines jsonb, p_restock jsonb default null, p_receipt text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.sales; ev jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into s from public.sales where id = p_sale;
  if not found then raise exception 'sale_not_found'; end if;
  if not public.can_loc(s.location_id) or not (public.has_grant('sale_return', s.location_id) or public.has_grant('return_override', s.location_id)) then raise exception 'not allowed'; end if;
  ev := public._w1c_return_eval(p_sale, p_lines, p_restock, p_receipt);
  return ev || jsonb_build_object('can_override', public.has_grant('return_override', s.location_id), 'expired_mode', coalesce(public.rule_txt('return_expired_restock'), 'allow'));
end $$;
revoke all on function public._w1c_return_preview(uuid, jsonb, jsonb, text) from public, anon; grant execute on function public._w1c_return_preview(uuid, jsonb, jsonb, text) to authenticated;

-- ---------- settings screen ----------
create or replace function public._w1c_return_settings() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'needs_receipt', public.rule_on('return_needs_receipt'), 'window_hours', public.rule_num('return_window_hours'), 'expired_mode', coalesce(public.rule_txt('return_expired_restock'), 'allow'),
    'classes', coalesce((select jsonb_agg(jsonb_build_object('class_code', c.cls, 'items', c.n, 'sample_en', c.sample_en, 'sample_bn', c.sample_bn,
         'configured', cr.class_code is not null and cr.active, 'restock', coalesce(cr.restock, 'restock'), 'window_hours', cr.window_hours, 'receipt_required', cr.receipt_required,
         'effective_from', cr.effective_from, 'active', coalesce(cr.active, false), 'note', cr.note,
         'perishable', exists (select 1 from public.shelf_life_rules z where z.active and (z.category = c.cls or z.item_id in (select i.id from public.items i where coalesce(nullif(btrim(i.category), ''), '-') = c.cls)))
                       or exists (select 1 from public.stock_batches b join public.items i on i.id = b.item_id where coalesce(nullif(btrim(i.category), ''), '-') = c.cls and b.expires_at is not null)) order by c.cls)
       from (select coalesce(nullif(btrim(i.category), ''), '-') cls, count(*) n, min(i.name_en) sample_en, min(i.name_bn) sample_bn from public.items i where i.is_active group by 1) c
       left join public.w1c_return_class_rules cr on cr.class_code = c.cls), '[]'::jsonb));
end $$;
revoke all on function public._w1c_return_settings() from public, anon; grant execute on function public._w1c_return_settings() to authenticated;

create or replace function public._w1c_return_class_set(p_class text, p_restock text, p_window numeric, p_receipt boolean, p_effective date default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old public.w1c_return_class_rules; cls text := nullif(btrim(coalesce(p_class, '')), ''); eff date := coalesce(p_effective, public._dhaka_today());
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if cls is null or char_length(cls) > 60 then raise exception 'bad_class'; end if;
  if not exists (select 1 from public.items i where coalesce(nullif(btrim(i.category), ''), '-') = cls) then raise exception 'unknown_class'; end if;
  if p_restock is null or p_restock not in ('restock', 'no_restock') then raise exception 'bad_restock'; end if;
  if p_window is not null and not (p_window > 0 and p_window <= 100000) then raise exception 'bad_window'; end if;
  if char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long: note'; end if;
  select * into old from public.w1c_return_class_rules where class_code = cls;
  insert into public.w1c_return_class_rules (class_code, restock, window_hours, receipt_required, effective_from, active, note, updated_by, updated_at)
    values (cls, p_restock, p_window, p_receipt, eff, true, nullif(btrim(p_note), ''), auth.uid(), now())
    on conflict (class_code) do update set restock = excluded.restock, window_hours = excluded.window_hours, receipt_required = excluded.receipt_required,
      effective_from = excluded.effective_from, active = true, note = excluded.note, updated_by = auth.uid(), updated_at = now();
  perform public._w1c_audit('return_rule_changed', 'w1c_return_class_rules', cls, jsonb_build_object('old', case when old.class_code is null then null else to_jsonb(old) end,
    'new', jsonb_build_object('restock', p_restock, 'window_hours', p_window, 'receipt_required', p_receipt, 'effective_from', eff, 'note', p_note)));
  return jsonb_build_object('class', cls, 'saved', true);
end $$;
revoke all on function public._w1c_return_class_set(text, text, numeric, boolean, date, text) from public, anon; grant execute on function public._w1c_return_class_set(text, text, numeric, boolean, date, text) to authenticated;

-- switch a class rule off (the row stays; nothing is deleted)
create or replace function public._w1c_return_class_off(p_class text, p_reason text) returns jsonb language plpgsql security definer set search_path = public as $$
declare n int; v_reason text := nullif(left(btrim(coalesce(p_reason, '')), 300), '');
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if v_reason is null or char_length(v_reason) < 3 then raise exception 'reason_required'; end if;
  update public.w1c_return_class_rules set active = false, updated_by = auth.uid(), updated_at = now() where class_code = p_class and active;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'not_found'; end if;
  perform public._w1c_audit('return_rule_off', 'w1c_return_class_rules', p_class, jsonb_build_object('reason', v_reason));
  return jsonb_build_object('class', p_class, 'active', false);
end $$;
revoke all on function public._w1c_return_class_off(text, text) from public, anon; grant execute on function public._w1c_return_class_off(text, text) to authenticated;

create or replace function public._w1c_return_global_set(p_needs_receipt boolean, p_window numeric, p_expired text) returns jsonb language plpgsql security definer set search_path = public as $$
declare old jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_expired is null or p_expired not in ('allow', 'writeoff', 'block') then raise exception 'bad_mode'; end if;
  if p_window is not null and not (p_window between 1 and 87600) then raise exception 'bad_window'; end if;
  old := jsonb_build_object('needs_receipt', public.rule_on('return_needs_receipt'), 'window_hours', public.rule_num('return_window_hours'), 'expired_mode', coalesce(public.rule_txt('return_expired_restock'), 'allow'));
  perform public.set_rule('return_needs_receipt', to_jsonb(coalesce(p_needs_receipt, false)));
  perform public.set_rule('return_window_hours', case when p_window is null then 'null'::jsonb else to_jsonb(p_window) end);
  perform public.set_rule('return_expired_restock', to_jsonb(p_expired));
  perform public._w1c_audit('return_rules_changed', 'rules', 'return_*', jsonb_build_object('old', old, 'new', jsonb_build_object('needs_receipt', coalesce(p_needs_receipt, false), 'window_hours', p_window, 'expired_mode', p_expired)));
  return public._w1c_return_settings();
end $$;
revoke all on function public._w1c_return_global_set(boolean, numeric, text) from public, anon; grant execute on function public._w1c_return_global_set(boolean, numeric, text) to authenticated;

-- ---------- report: returns by reason, restocked or written off ----------
create or replace function public._w1c_return_report(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, public._dhaka_today() - 30); t date := coalesce(p_to, public._dhaka_today());
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not (public.is_owner() or public.has_grant('sale_return', p_loc) or public.has_grant('return_override', p_loc)) then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return jsonb_build_object('from', f, 'to', t,
    'by_reason', coalesce((select jsonb_agg(z order by (z ->> 'reason')) from (
        select jsonb_build_object('reason', sr.reason_code, 'class', l.class_code, 'returns', count(distinct sr.id), 'lines', count(*),
               'restocked_qty', coalesce(sum(l.restock_qty), 0), 'written_off_qty', coalesce(sum(l.writeoff_qty), 0), 'written_off_value', coalesce(sum(l.writeoff_value), 0)) z
          from public.sale_returns sr join public.w1c_returns h on h.return_id = sr.id join public.w1c_return_lines l on l.return_id = h.return_id
         where sr.status = 'done' and (sr.created_at at time zone 'Asia/Dhaka')::date between f and t and (p_loc is null or sr.location_id = p_loc) and public.can_loc(sr.location_id)
         group by sr.reason_code, l.class_code) q), '[]'::jsonb),
    'overrides', coalesce((select jsonb_agg(jsonb_build_object('return_id', h.return_id, 'at', h.created_at, 'kinds', h.override_kinds, 'reason', h.override_reason, 'by', h.created_by))
        from public.w1c_returns h join public.sale_returns sr on sr.id = h.return_id
       where h.override and (sr.created_at at time zone 'Asia/Dhaka')::date between f and t and (p_loc is null or sr.location_id = p_loc) and public.can_loc(sr.location_id)), '[]'::jsonb),
    'not_covered', (select count(*) from public.sale_returns sr where sr.status = 'done' and (sr.created_at at time zone 'Asia/Dhaka')::date between f and t and (p_loc is null or sr.location_id = p_loc)
                      and public.can_loc(sr.location_id) and not exists (select 1 from public.w1c_returns h where h.return_id = sr.id)));
end $$;
revoke all on function public._w1c_return_report(date, date, int) from public, anon; grant execute on function public._w1c_return_report(date, date, int) to authenticated;
