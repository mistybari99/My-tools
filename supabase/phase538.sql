-- Phase 538 (UNION-10: the advanced line's logic in 21 shared functions (record_sale2 ... year_close_list) put back where a repaste of the early phases reset it). Paste-twice safe. Earlier phase files are not edited.
-- What: the advanced line changed these functions after phase 79 (rules, scope, audit, templates, cost, ...). Pasting the early phases (8 to 79) again, as the owner's earlier paste of
--   our line did, puts their older text back and the advanced logic is silently gone. A database that was built by pasting the advanced phases and then ONE run of our phases
--   never loses it (this is how the fresh build is ordered), so on a fresh build this file does nothing.
-- What this file does: for every function listed, if its text is a KNOWN older text (the base text of phases 8-79, or the text of the earlier live paste, recognised by md5), it is replaced by the merged
--   text (the advanced text, our line did not change these functions); the old text is saved in public._union_fn_backup first. An unknown text is never overwritten: all such functions are
--   listed in one message and nothing is changed. Nothing here adds a switch or changes a default.
-- Paste AFTER phase534 and after phase 505. Safe to paste twice.

create table if not exists public._union_fn_backup (id bigserial primary key, fn text not null, saved_at timestamptz not null default now(), why text, def text not null);
alter table public._union_fn_backup enable row level security;
revoke all on public._union_fn_backup from anon, authenticated;

drop table if exists _u_plan;
create temp table _u_plan (seq serial primary key, fn text not null, kind text not null, a text not null, b text);
-- record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)
insert into _u_plan (fn, kind, a, b) values
  ('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.record_sale2(p_client uuid, p_loc integer, p_lines jsonb, p_discount numeric, p_payments jsonb, p_customer_mobile text, p_customer_name text, p_sale_type text, p_note text, p_quick boolean, p_sold_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_discount_kind text DEFAULT NULL::text, p_discount_input numeric DEFAULT NULL::numeric)
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
  lt89 jsonb;   -- bos89
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
  if at_ > now() + interval '10 minutes' or at_ < now() - make_interval(hours => coalesce(public.rule_num('pos_offline_hours'), 72)::int) then
    lt89 := public._w1b_late_sale(p_client, p_loc, p_lines, p_discount, p_payments, p_customer_mobile, p_customer_name, p_sale_type, p_note, p_quick, p_sold_at, p_discount_kind, p_discount_input, at_);   -- bos89
    if lt89 is not null and (lt89 ->> 'keep') is null then return lt89; end if;   -- parked for the owner
    if lt89 is null then at_ := now(); end if;                                    -- re-dated, as before
  end if;
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
      where cu.mobile = public.norm_mobile(p_customer_mobile) and cu.active and t.active and t.discount_percent > 0 and public._m132_at(cu.org_unit_id, p_loc) /* m132 */;
    if found then tier_amt43 := least(disc, round(sub * tier_pct43 / 100, 2), coalesce(tier_cap43, disc)); end if;
  end if;
  select value into lim from public.location_settings where location_id = p_loc and key = 'discount_limit';
  if disc > tier_amt43 and public.rule_on('pos_discount_manager') and (lim is null or jsonb_typeof(lim) = 'null' or disc > (lim #>> '{}')::numeric)
     and not public.rule_ok('discount_over_limit', p_loc, disc, null, 'sale') then raise exception 'discount_needs_approval'; end if;   -- no limit written = a granted role is needed
  -- payments
  if p_payments is not null and jsonb_typeof(p_payments) <> 'array' then raise exception 'bad_payments'; end if;
  for pay in select * from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) loop
    pm := pay->>'mode';
    if pm is null or pm <> all (public._w1f_receipt_modes()) /* bos97 */ then raise exception 'bad_mode'; end if;
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
    select * into cust from public.customers where mobile = mob and public._m132_at(org_unit_id, p_loc) /* m132 */ order by (org_unit_id is not distinct from public._m132_biz_of_loc(p_loc)) desc, org_unit_id limit 1 for update;
    if not found then
      if nullif(btrim(p_customer_name), '') is null then raise exception 'customer_name_required'; end if;
      insert into public.customers (mobile, name, type, created_by, org_unit_id) values (mob, left(btrim(p_customer_name), 80), stype, auth.uid(), public._m132_biz_of_loc(p_loc) /* m132 */) returning * into cust;
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
    insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, cheque_no, cheque_date, money_account_id, ref_waiver, amount, paid_at, created_by, created_staff) /* bos97 */
      values (s.id, cust.id, p_loc, 'sale', pay->>'mode', left(nullif(pay->>'wallet', ''), 30), left(nullif(pay->>'ref', ''), 60), public._w1f_pj_text(pay, 'cheque_no', 40), public._w1f_pj_date(pay, 'cheque_date'), public._w1f_pj_acc(pay), public._w1f_pj_text(pay, 'exception_reason', 200), round((pay->>'amount')::numeric, 2), at_, auth.uid(), sid);
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
end $function$$r0_0$, null),
  ('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)', 'known', '08a61db0833cf41e5256f8963ba3a2b5', null),
  ('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)', 'known', '6410e5d47a1109693208da2fbef16701', null),
  ('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)', 'known', 'cdd520542240939b993bca9d8defae1c', null);
-- rollout_mode(text,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.rollout_mode(text,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.rollout_mode(p_form text, p_loc integer)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select mode from public.form_rollout where form_code = p_form and location_id = p_loc and public._cfgvis133(p_loc)), 'app');   /* scope133 */
$function$$r0_0$, null),
  ('public.rollout_mode(text,integer)', 'known', '7d9d84b171012c1649e2ce643476b177', null);
-- sales_channel_save(integer,text,text,text,text,integer,text,text,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.sales_channel_save(integer,text,text,text,text,integer,text,text,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.sales_channel_save(p_id integer, p_code text, p_kind text, p_other text, p_name text, p_loc integer, p_role text, p_account_ref text, p_active boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.sales_channels;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_kind not in ('web_form', 'facebook', 'instagram', 'whatsapp', 'telegram', 'phone', 'walkin', 'other') then raise exception 'bad_kind'; end if;   -- bos86: + telegram
  if p_kind = 'telegram' and nullif(btrim(p_account_ref), '') is null then raise exception 'account_ref_required'; end if;                           -- bos86
  if p_kind = 'other' and nullif(btrim(p_other), '') is null then raise exception 'other_text_required'; end if;
  if nullif(btrim(p_name), '') is null or char_length(btrim(p_name)) > 60 then raise exception 'name_required'; end if;
  if p_code is null or p_code !~ '^[a-z0-9_]{2,30}$' then raise exception 'bad_code'; end if;
  if p_loc is not null and not exists (select 1 from public.locations where id = p_loc) then raise exception 'location_not_found'; end if;
  if p_role is not null and not exists (select 1 from public.roles where code = p_role) then raise exception 'role_not_found'; end if;
  if p_id is null then
    insert into public.sales_channels (code, kind, other_text, name_bn, location_id, role_code, account_ref, active, created_by)
      values (p_code, p_kind, case when p_kind = 'other' then left(btrim(p_other), 60) end, btrim(p_name), p_loc, p_role, nullif(btrim(p_account_ref), ''), coalesce(p_active, true), auth.uid()) returning * into c;
  else
    update public.sales_channels set code = p_code, kind = p_kind, other_text = case when p_kind = 'other' then left(btrim(p_other), 60) end, name_bn = btrim(p_name), location_id = p_loc,
        role_code = p_role, account_ref = nullif(btrim(p_account_ref), ''), active = coalesce(p_active, true), updated_at = now() where id = p_id returning * into c;
    if not found then raise exception 'not_found'; end if;
  end if;
  return jsonb_build_object('id', c.id, 'code', c.code, 'active', c.active);
end $function$$r0_0$, null),
  ('public.sales_channel_save(integer,text,text,text,text,integer,text,text,boolean)', 'known', '76028050e90cf1a269dc4f5affec9a73', null);
-- save_purchase(uuid,uuid,uuid,integer,text,date,jsonb,numeric,text,text,text,uuid,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.save_purchase(uuid,uuid,uuid,integer,text,date,jsonb,numeric,text,text,text,uuid,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.save_purchase(p_client uuid, p_id uuid, p_supplier uuid, p_loc integer, p_bill_no text, p_bill_date date, p_lines jsonb, p_discount numeric DEFAULT 0, p_note text DEFAULT NULL::text, p_photo text DEFAULT NULL::text, p_kind text DEFAULT 'bill'::text, p_ref_bill uuid DEFAULT NULL::uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pb public.purchase_bills; ln jsonb; it public.items; n int := 0; qty numeric; uc numeric; amt numeric; sub numeric := 0; disc numeric := coalesce(p_discount, 0);
        un text; bid uuid := p_id; sid text; ref public.purchase_bills; gcode text; norm jsonb := '[]'::jsonb;
begin
  if p_kind not in ('bill', 'return') then raise exception 'bad_kind'; end if;
  gcode := case p_kind when 'return' then 'purchase_return' else 'purchase_entry' end;
  if not public.is_active() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if p_client is not null and p_id is null then          -- editing a draft (p_id) is never a "duplicate"
    select * into pb from public.purchase_bills where client_id = p_client;
    if found then
      if pb.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('id', pb.id, 'status', pb.status, 'total', pb.total, 'dup', true);
    end if;
  end if;
  if bid is not null then
    select * into pb from public.purchase_bills where id = bid for update;
    if not found then raise exception 'not found'; end if;
    if pb.status <> 'draft' then raise exception 'not_draft'; end if;
    if pb.kind <> p_kind or pb.location_id <> p_loc then raise exception 'cannot_change_kind_or_location'; end if;
  end if;
  if not (public.has_grant(gcode, p_loc) or public._use_em(gcode, p_loc, 'save_purchase', null)) then raise exception 'not allowed'; end if;
  if p_bill_date is null or not (p_bill_date <= (now() at time zone 'Asia/Dhaka')::date + 1) then raise exception 'bad_date'; end if;
  if bid is null then perform public._w1b_backdate_check('purchase', p_bill_date, p_client, 'purchase_bills');   -- bos89
  elsif pb.bill_date is distinct from p_bill_date then perform public._w1b_backdate_check('purchase', p_bill_date, p_client, 'purchase_bills'); end if;
  if not exists (select 1 from public.suppliers where id = p_supplier and public._m132_vis('suppliers', suppliers.org_unit_id, suppliers.id::text, false) /* m132b:suppliers */ and active) then raise exception 'supplier_not_found'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  if not (disc between 0 and 999999999999) then raise exception 'bad_discount'; end if;      -- false for NaN / Infinity
  if length(coalesce(p_photo, '')) > 300 then raise exception 'bad_photo'; end if;
  if p_kind = 'return' then
    if p_reason is null or not exists (select 1 from public.option_lists where list_code = 'return_reasons' and value_code = p_reason and active) then raise exception 'reason_required'; end if;
    if p_ref_bill is null then
      if not public.is_owner() then raise exception 'return_needs_bill'; end if;
    else
      select * into ref from public.purchase_bills where id = p_ref_bill;
      if not found or ref.supplier_id <> p_supplier or ref.kind <> 'bill' or ref.status <> 'posted' then raise exception 'bad_ref_bill'; end if;
    end if;
  elsif p_ref_bill is not null then raise exception 'bad_ref_bill';
  end if;
  if nullif(btrim(p_bill_no), '') is not null and exists (select 1 from public.purchase_bills where supplier_id = p_supplier and lower(bill_no) = lower(btrim(p_bill_no)) and kind = p_kind and status <> 'void'
       and id is distinct from bid and (p_client is null or client_id is distinct from p_client)) then
    raise exception 'duplicate_bill';
  end if;
  -- validate lines first (nothing is written if one is wrong)
  for ln in select * from jsonb_array_elements(p_lines) loop
    qty := nullif(ln->>'qty', '')::numeric; uc := nullif(ln->>'unit_cost', '')::numeric;
    if qty is null or not (qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
    if uc is null or not (uc between 0 and 999999999) then raise exception 'bad_cost'; end if;
    it := null; un := nullif(ln->>'unit', '');
    if nullif(ln->>'item_id', '') is not null then
      select * into it from public.items where id = (ln->>'item_id')::uuid;
      if not found or not it.is_active then raise exception 'item_not_found'; end if;
      un := coalesce(un, it.unit);
      if it.tracked and public._base_qty(it.id, 1, un) is null then raise exception 'unit_unknown'; end if;
    elsif nullif(btrim(ln->>'description'), '') is null then raise exception 'description_required';
    end if;
    sub := sub + round(qty * uc, 2);
    if not (sub <= 999999999999) then raise exception 'bad_amount'; end if;
    norm := norm || jsonb_build_array(jsonb_build_object('item_id', it.id, 'description', nullif(btrim(ln->>'description'), ''), 'qty', qty, 'unit', un, 'unit_cost', uc));
  end loop;
  if disc > sub then raise exception 'bad_discount'; end if;
  if p_kind = 'return' and p_ref_bill is not null then perform public._return_check(p_ref_bill, bid, norm); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if bid is null then
    begin
      insert into public.purchase_bills (client_id, kind, supplier_id, bill_no, bill_date, location_id, status, subtotal, discount, total, note, photo, reason_code, ref_bill_id, created_by, created_staff)
        values (p_client, p_kind, p_supplier, nullif(btrim(p_bill_no), ''), p_bill_date, p_loc, 'draft', sub, round(disc, 2), sub - round(disc, 2), left(p_note, 300), nullif(btrim(p_photo), ''), p_reason, p_ref_bill, auth.uid(), sid)
        returning id into bid;
    exception when unique_violation then
      select * into pb from public.purchase_bills where p_client is not null and client_id = p_client;
      if found and pb.created_by = auth.uid() then return jsonb_build_object('id', pb.id, 'status', pb.status, 'total', pb.total, 'dup', true); end if;
      raise exception 'duplicate_bill';
    end;
  else
    update public.purchase_bills set supplier_id = p_supplier, bill_no = nullif(btrim(p_bill_no), ''), bill_date = p_bill_date, subtotal = sub, discount = round(disc, 2), total = sub - round(disc, 2),
      note = left(p_note, 300), photo = nullif(btrim(p_photo), ''), reason_code = p_reason, ref_bill_id = p_ref_bill where id = bid;
    delete from public.purchase_lines where bill_id = bid;
  end if;
  for ln in select * from jsonb_array_elements(norm) loop
    n := n + 1; qty := (ln->>'qty')::numeric; uc := (ln->>'unit_cost')::numeric; amt := round(qty * uc, 2);
    insert into public.purchase_lines (bill_id, line_no, item_id, description, qty, unit, unit_cost, amount)
      values (bid, n, nullif(ln->>'item_id', '')::uuid, left(nullif(btrim(ln->>'description'), ''), 120), qty, left(nullif(ln->>'unit', ''), 20), uc, amt);
  end loop;
  return jsonb_build_object('id', bid, 'status', 'draft', 'total', sub - round(disc, 2), 'lines', n);
end $function$$r0_0$, null),
  ('public.save_purchase(uuid,uuid,uuid,integer,text,date,jsonb,numeric,text,text,text,uuid,text)', 'known', '4cc5b1117196648e04a15127eb685154', null),
  ('public.save_purchase(uuid,uuid,uuid,integer,text,date,jsonb,numeric,text,text,text,uuid,text)', 'known', '679a8ce09e2b97fccad841cadace5562', null),
  ('public.save_purchase(uuid,uuid,uuid,integer,text,date,jsonb,numeric,text,text,text,uuid,text)', 'known', 'df1e1dc7039f37cc61b6e18551330bd0', null);
-- save_supplier(uuid,jsonb)
insert into _u_plan (fn, kind, a, b) values
  ('public.save_supplier(uuid,jsonb)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.save_supplier(p_id uuid, p_patch jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sid uuid := p_id; p jsonb := coalesce(p_patch, '{}');
begin
  if not public.has_grant('supplier_manage') then raise exception 'not allowed'; end if;
  if sid is null then
    if nullif(btrim(p->>'name'), '') is null then raise exception 'name_required'; end if;
    insert into public.suppliers (name, created_by) values (left(btrim(p->>'name'), 120), auth.uid()) returning id into sid;
  elsif not exists (select 1 from public.suppliers where id = sid and public._m132_vis('suppliers', suppliers.org_unit_id, suppliers.id::text, false) /* m132b:suppliers */) then raise exception 'not found';
  end if;
  update public.suppliers set
    name = case when p ? 'name' and nullif(btrim(p->>'name'), '') is not null then left(btrim(p->>'name'), 120) else name end,
    mobile = case when p ? 'mobile' then nullif(public.norm_mobile(p->>'mobile'), '') else mobile end,
    type_code = case when p ? 'type_code' then nullif(p->>'type_code', '') else type_code end,
    address = case when p ? 'address' then left(nullif(p->>'address', ''), 300) else address end,
    credit_days = case when p ? 'credit_days' then nullif(p->>'credit_days', '')::int else credit_days end,
    opening_balance = case when p ? 'opening_balance' then nullif(p->>'opening_balance', '')::numeric else opening_balance end,
    nid = case when p ? 'nid' then left(nullif(p->>'nid', ''), 40) else nid end,
    tin = case when p ? 'tin' then left(nullif(p->>'tin', ''), 40) else tin end,
    note = case when p ? 'note' then left(nullif(p->>'note', ''), 300) else note end,
    active = case when p ? 'active' then (p->>'active')::boolean else active end,
    updated_at = now()
  where id = sid;
  return sid;
end $function$$r0_0$, null),
  ('public.save_supplier(uuid,jsonb)', 'known', '86e38f6aacde788adc0a6eb601364f83', null);
-- sheet_sync_all()
insert into _u_plan (fn, kind, a, b) values
  ('public.sheet_sync_all()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.sheet_sync_all()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l record; n int := 0;
begin
  if not public._sheet_viewer() then raise exception 'not allowed'; end if;
  for l in select id from public.locations where ((select not public._org_on123()) or public.is_owner() or public._biz_ok123(id)) loop   /* scope133 */ perform public._sheet_writethrough(l.id); n := n + 1; end loop;
  return n;
end $function$$r0_0$, null),
  ('public.sheet_sync_all()', 'known', 'c2b22049a8f5d33ca08eb40ab0c8ac05', null);
-- shelf_life_for(uuid,date)
insert into _u_plan (fn, kind, a, b) values
  ('public.shelf_life_for(uuid,date)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.shelf_life_for(p_item uuid, p_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d date := coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date); md int := extract(month from d)::int * 100 + extract(day from d)::int;
        it public.items; r public.shelf_life_rules;
begin
  select * into it from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;
  if not found then return null; end if;
  select * into r from public.shelf_life_rules s
  where s.active
    and (s.item_id = p_item or (s.item_id is null and s.category is not null and s.category = it.category) or (s.item_id is null and s.category is null))
    and (s.start_month is null
         or (case when s.start_month * 100 + s.start_day <= s.end_month * 100 + s.end_day
                  then md between s.start_month * 100 + s.start_day and s.end_month * 100 + s.end_day
                  else md >= s.start_month * 100 + s.start_day or md <= s.end_month * 100 + s.end_day end))
  order by (case when s.item_id is not null then 3 when s.category is not null then 2 else 1 end) desc,
           (s.start_month is not null) desc,
           (case when s.start_month is null then 0
                 when s.start_month * 31 + s.start_day <= s.end_month * 31 + s.end_day then (s.end_month * 31 + s.end_day) - (s.start_month * 31 + s.start_day)
                 else 372 - ((s.start_month * 31 + s.start_day) - (s.end_month * 31 + s.end_day)) end) asc,
           s.id desc
  limit 1;
  if not found then return null; end if;
  return jsonb_build_object('rule_id', r.id, 'scope', case when r.item_id is not null then 'item' when r.category is not null then 'category' else 'all' end,
    'season', r.season_label, 'value', r.value, 'unit', r.unit, 'hours', case r.unit when 'days' then r.value * 24 else r.value end, 'date', d);
end $function$$r0_0$, null),
  ('public.shelf_life_for(uuid,date)', 'known', '335903b6a88e3632c9f237543a08c536', null);
-- stock_blind_active(text,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.stock_blind_active(text,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.stock_blind_active(p_form text, p_loc integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p_form in ('04-1', '04-3') and public.rule_on('blind_count_on')
     and coalesce((select enabled from public.blind_count_cfg where form_code = p_form and location_id = p_loc and public._cfgvis133(p_loc)), true);   /* scope133 */
$function$$r0_0$, null),
  ('public.stock_blind_active(text,integer)', 'known', 'b9502bbe82a04d90f98a17e4353c9434', null);
-- stock_count_adjust(uuid,integer,numeric,text,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.stock_count_adjust(uuid,integer,numeric,text,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.stock_count_adjust(p_item uuid, p_loc integer, p_counted numeric, p_note text, p_unit text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items; bq numeric; bal public.stock_balance; d numeric; lid bigint; tol numeric;
begin
  it := public._stock_guard(p_item, p_loc, 'stock_count_adjust', (now() at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then select id into lid from public.stock_ledger where client_id = p_client and reason = 'count_adjust' order by id limit 1; if found then return jsonb_build_object('dup', true, 'ledger_id', lid); end if; end if;
  if p_counted is null or not (p_counted between 0 and 999999999) then raise exception 'bad_qty'; end if;
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  bq := public._base_qty(p_item, p_counted, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not (bq between 0 and 999999999) then raise exception 'bad_qty'; end if;
  if not public._may('stock_count_adjust', p_loc, 'count:' || p_item::text) then raise exception 'not allowed'; end if;
  insert into public.stock_balance (item_id, location_id) values (p_item, p_loc) on conflict do nothing;
  select * into bal from public.stock_balance where item_id = p_item and location_id = p_loc for update;
  d := round(bq - bal.qty, 4);
  if d = 0 then return jsonb_build_object('ledger_id', null, 'delta', 0, 'qty', bal.qty); end if;
  lid := public.stock_post(p_item, p_loc, d, 'count_adjust', 'count', null, case when d > 0 and public.rule_on('acct_count_adjust') then bal.avg_cost end /* bos85: a gain is recorded at the average cost so it has a known cost; the average does not move */, public._adj_batch114(p_item, p_loc, d, 'count gain'), now(), left(p_note, 200), null, 'none', null, p_client);   -- bos114:count-batch
  tol := public.rule_num('count_tolerance_pct');
  if tol is not null and (bal.qty = 0 or abs(d) / abs(bal.qty) * 100 > tol) then
    perform public._stock_exc(p_loc, 'stock_count_variance', 'yellow', it.name_bn || ': গণনায় ' || d::text || ' পার্থক্য', coalesce(it.name_en, it.name_bn) || ': the count differs from the book by ' || d::text);
  end if;
  return jsonb_build_object('ledger_id', lid, 'delta', d, 'qty', bq);
end $function$$r0_0$, null),
  ('public.stock_count_adjust(uuid,integer,numeric,text,text,uuid)', 'known', '282a9df482f28749d5e730abc87c2eff', null);
-- stock_opening(uuid,integer,numeric,numeric,text,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.stock_opening(uuid,integer,numeric,numeric,text,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.stock_opening(p_item uuid, p_loc integer, p_qty numeric, p_unit_cost numeric DEFAULT NULL::numeric, p_unit text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items; bq numeric; f numeric; cost numeric; lid bigint;
begin
  it := public._stock_guard(p_item, p_loc, 'stock_opening', (now() at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then select id into lid from public.stock_ledger where client_id = p_client and reason = 'opening'; if found then return jsonb_build_object('dup', true, 'ledger_id', lid); end if; end if;
  if p_qty is null or not (p_qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if p_unit_cost is not null and not (p_unit_cost between 0 and 999999999) then raise exception 'bad_cost'; end if;
  if p_unit_cost is not null and not public._cost_ok(p_loc) then raise exception 'not allowed'; end if;      -- cost is secret: only who may see it may write it
  if not public._may('stock_opening', p_loc, 'opening:' || p_item::text) then raise exception 'not allowed'; end if;
  perform 1 from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */ for no key update;                -- two people entering the same opening wait here (NO KEY UPDATE: ledger inserts take a KEY SHARE lock on the item, so this can never deadlock with them)
  if exists (select 1 from public.stock_ledger where item_id = p_item and location_id = p_loc and reason = 'opening') then raise exception 'opening_exists'; end if;
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  f := public._unit_factor_base(p_item, p_unit);
  if f is null or not (f > 0) then raise exception 'unit_unknown'; end if;
  cost := case when p_unit_cost is null then null else p_unit_cost / f end;       -- cost given per p_unit -> per base unit
  lid := public.stock_post(p_item, p_loc, bq, 'opening', 'opening', null, cost, public._adj_batch114(p_item, p_loc, bq, 'opening stock'), now(), left(p_note, 200), null, 'none', null, p_client);   -- bos114:opening-batch
  return jsonb_build_object('ledger_id', lid, 'qty', bq);
end $function$$r0_0$, null),
  ('public.stock_opening(uuid,integer,numeric,numeric,text,text,uuid)', 'known', 'fbf8d3ca185642152ceda9ee93608714', null);
-- stock_post(uuid,integer,numeric,text,text,text,numeric,bigint,timestamp with time zone,text,bigint,text,uuid,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.stock_post(uuid,integer,numeric,text,text,text,numeric,bigint,timestamp with time zone,text,bigint,text,uuid,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.stock_post(p_item uuid, p_loc integer, p_qty numeric, p_reason text, p_ref_type text DEFAULT NULL::text, p_ref_id text DEFAULT NULL::text, p_unit_cost numeric DEFAULT NULL::numeric, p_batch bigint DEFAULT NULL::bigint, p_made_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_note text DEFAULT NULL::text, p_reverses bigint DEFAULT NULL::bigint, p_neg text DEFAULT 'full'::text, p_sale uuid DEFAULT NULL::uuid, p_client uuid DEFAULT NULL::uuid)
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
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;   -- bos82
        select coalesce(staff_id, '-') into who from public.profiles where id = auth.uid();   -- bos82
        if pm = 'required' and nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'production_negative_reason_needed' using detail = coalesce(ic, '') || ' ' || coalesce(nm, ''), hint = 'on hand ' || bal.qty::text; end if;   -- bos82
        perform public._stock_exc(p_loc, 'production_negative', 'yellow', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): উৎপাদনে stock-এর চেয়ে বেশি কাঁচামাল নেওয়া হয়েছে, পরিমাণ ' || trim_scale(-q)::text || ', কর্মী ' || coalesce(who, '-') || ', কারণ: ' || coalesce(nullif(btrim(p_note), ''), '-'),
          coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): production took more than the stock on hand, qty ' || trim_scale(-q)::text || ', staff ' || coalesce(who, '-') || ', reason: ' || coalesce(nullif(btrim(p_note), ''), '-'), p_sale, d, form);   -- bos82
      end if;   -- bos82
    end if;   -- bos82
    if mode <> 'allow' then
      select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;
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
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;
        raise exception 'expired_stock_blocked' using detail = coalesce(ic, '') || ' ' || coalesce(nm, ''), hint = 'batch ' || b.id::text;
      end if;
      take := least(b.qty_remaining, rem);
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, batch_id, reverses_id, client_id, made_at, note, created_by)
        values (p_item, p_loc, -take, cost, p_reason, p_ref_type, p_ref_id, b.id, p_reverses, case when first_id is null then p_client end, at_, p_note, auth.uid()) returning id into lid;
      update public.stock_batches set qty_remaining = case when qty_remaining - take < 0.0005 then 0 else qty_remaining - take end where id = b.id;
      first_id := coalesce(first_id, lid); rem := rem - take;
      if p_reason = 'sale_out' and b.expires_at is not null and b.expires_at <= at_ then
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;
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
end $function$$r0_0$, null),
  ('public.stock_post(uuid,integer,numeric,text,text,text,numeric,bigint,timestamp with time zone,text,bigint,text,uuid,uuid)', 'known', '6499d1b362cae0242a2ad430f4621e7f', null);
-- stock_receive_transfer(uuid,numeric,text,numeric,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.stock_receive_transfer(uuid,numeric,text,numeric,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.stock_receive_transfer(p_id uuid, p_received_qty numeric, p_note text, p_damaged_qty numeric, p_damaged_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t public.stock_transfers; rq numeric; res jsonb; dq numeric := p_damaged_qty; rs text := nullif(btrim(p_damaged_reason), ''); it public.items; got numeric;
begin
  select * into t from public.stock_transfers where id = p_id;
  if not found then raise exception 'not found'; end if;
  got := coalesce((select sum(l.qty_delta) from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = t.id::text and l.reason = 'transfer_in'), 0);
  rq := coalesce(p_received_qty, t.qty - got);
  if dq is not null then
    if not (dq between 0 and 999999999) then raise exception 'bad_qty'; end if;
    if dq > rq then raise exception 'damaged_over_received'; end if;
    if dq > 0 and (rs is null or not exists (select 1 from public.option_lists where list_code = 'transfer_damage_reasons' and value_code = rs and active)) then raise exception 'damage_reason_required'; end if;
    if dq = 0 then rs := null; end if;
  end if;
  res := public.stock_receive_transfer(p_id, p_received_qty, p_note);          -- the 3-argument function: every rule (grant, short quantity, batches, exception, parts)
  if coalesce((res ->> 'dup')::boolean, false) then return res; end if;
  if dq is not null then
    update public.stock_transfers set received_damaged_qty = coalesce(received_damaged_qty, 0) + dq, damaged_reason = coalesce(rs, damaged_reason) where id = p_id;
    if dq > 0 then
      select * into it from public.items where id = t.item_id;
      perform public._stock_exc(t.to_location_id, 'transit_damaged', 'yellow', it.name_bn || ': গ্রহণ ' || rq::text || ', তার মধ্যে ' || dq::text || ' ক্ষতিগ্রস্ত',
        coalesce(it.name_en, it.name_bn) || ': received ' || rq::text || ', of which ' || dq::text || ' damaged');
    end if;
  end if;
  return res || jsonb_build_object('damaged', dq);
end $function$$r0_0$, null),
  ('public.stock_receive_transfer(uuid,numeric,text,numeric,text)', 'known', 'b8d20930741592905fa5bc7677021df4', null);
-- supplier_pick()
insert into _u_plan (fn, kind, a, b) values
  ('public.supplier_pick()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.supplier_pick()
 RETURNS TABLE(id uuid, name text, type_code text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select s.id, s.name, s.type_code from public.suppliers s where public.is_active() and s.active and public._m132_vis('suppliers', s.org_unit_id, s.id::text, false) /* m132 */ order by lower(s.name);
$function$$r0_0$, null),
  ('public.supplier_pick()', 'known', '9a956f85fe391e26dc6ebc1e87ef545e', null);
-- supplier_refund(uuid,integer,numeric,text,text,text,text,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.supplier_refund(uuid,integer,numeric,text,text,text,text,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.supplier_refund(p_supplier uuid, p_loc integer, p_amount numeric, p_mode text, p_wallet text DEFAULT NULL::text, p_ref text DEFAULT NULL::text, p_reason text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
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
end $function$$r0_0$, null),
  ('public.supplier_refund(uuid,integer,numeric,text,text,text,text,text,uuid)', 'known', '529288c03769fa61a9d7d01e68a73985', null);
-- template_for(text,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.template_for(text,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.template_for(p_kind text, p_loc integer)
 RETURNS invoice_templates
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select t.* from public.invoice_templates t
  where public.is_active() and t.active and t.is_default and t.kind = p_kind and (t.location_id = p_loc or t.location_id is null) and (t.location_id is null or public._cfgvis133(t.location_id)) /* scope133 */
  order by (t.location_id is null) limit 1;
$function$$r0_0$, null),
  ('public.template_for(text,integer)', 'known', 'dacd83149625cd03edaf46eaa298fa31', null);
-- unit_factor(uuid,text,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.unit_factor(uuid,text,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.unit_factor(p_item uuid, p_from text, p_to text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f numeric; b text; x numeric; y numeric;
begin
  if p_from is null or p_to is null then return null; end if;
  if p_from = p_to then return 1; end if;
  f := public._unit_hop(p_item, p_from, p_to);
  if f is not null then return f; end if;
  select base_unit into b from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;
  if b is not null and b <> p_from and b <> p_to then
    x := public._unit_hop(p_item, p_from, b); y := public._unit_hop(p_item, b, p_to);
    if x is not null and y is not null then return x * y; end if;
  end if;
  return null;
end $function$$r0_0$, null),
  ('public.unit_factor(uuid,text,text)', 'known', '9a3e3b20fcaf59910f1362aba2445b5a', null);
-- urgent_alerts(timestamp with time zone)
insert into _u_plan (fn, kind, a, b) values
  ('public.urgent_alerts(timestamp with time zone)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.urgent_alerts(p_since timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  perform public._transit_open_scan83();      -- bos83: open transit older than the owner's limit becomes an urgent notification (blank limit = nothing)
  return coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'kind', n.kind, 'title_bn', n.title_bn, 'title_en', n.title_en, 'body_bn', n.body_bn, 'body_en', n.body_en, 'route', n.route, 'created_at', n.created_at) order by n.id)
                     from public.notifications n
                    where n.level = 'bad' and n.emailed_at is null and n.user_id is null and n.audience in ('owner', 'all')
                      and n.created_at >= coalesce(p_since, now() - interval '2 days')), '[]'::jsonb);
end $function$$r0_0$, null),
  ('public.urgent_alerts(timestamp with time zone)', 'known', 'f419b0c6d38fce523d63daa9ad675367', null);
-- void_supplier_payment(bigint,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.void_supplier_payment(bigint,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.void_supplier_payment(p_id bigint, p_note text)
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
end $function$$r0_0$, null),
  ('public.void_supplier_payment(bigint,text)', 'known', 'a7d5acd40df1bcff77e04e28c9dcfc43', null);
-- void_supplier_refund(bigint,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.void_supplier_refund(bigint,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.void_supplier_refund(p_id bigint, p_note text)
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
end $function$$r0_0$, null),
  ('public.void_supplier_refund(bigint,text)', 'known', '97a57b13f10cf99da5f5fc7b3e9581f5', null);
-- wastage_decide(uuid,boolean,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.wastage_decide(uuid,boolean,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.wastage_decide(p_id uuid, p_approve boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.wastage_requests; sid text; res jsonb; it public.items;
begin
  select * into r from public.wastage_requests where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(r.location_id) or not public.has_grant('wastage_approve', r.location_id) then raise exception 'not allowed'; end if;
  perform 1 from public.wastage_requests where id = p_id for update;
  select * into r from public.wastage_requests where id = p_id;
  if r.status <> 'pending' then
    if r.status = (case when p_approve then 'approved' else 'rejected' end) then return jsonb_build_object('dup', true, 'status', r.status); end if;
    raise exception 'already_decided';
  end if;
  if r.requested_by = auth.uid() then raise exception 'own_request'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_approve then
    res := public._wastage_post(r.item_id, r.location_id, r.qty, r.reason_code, coalesce(r.note, '') || case when r.note is null then '' else ' · ' end || 'approved by ' || coalesce(sid, '?'),
                                r.photo, r.batch_id, r.client_id, r.requested_by, r.requested_staff);
    update public.wastage_requests set status = 'approved', decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = left(nullif(btrim(p_note), ''), 300),
      wastage_id = nullif(res->>'id', '')::uuid where id = p_id;
    return jsonb_build_object('status', 'approved') || res;
  end if;
  update public.wastage_requests set status = 'rejected', decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = left(btrim(p_note), 300) where id = p_id;
  select * into it from public.items where id = r.item_id and public._m132_own(items.org_unit_id) /* m132b:items */;
  perform public._stock_exc(r.location_id, 'wastage_rejected', 'yellow', it.name_bn || ': বড় নষ্ট মাল বাদ নামঞ্জুর — ' || left(btrim(p_note), 100),
    coalesce(it.name_en, it.name_bn) || ': a large wastage write-off was rejected — ' || left(btrim(p_note), 100));
  return jsonb_build_object('status', 'rejected');
end $function$$r0_0$, null),
  ('public.wastage_decide(uuid,boolean,text)', 'known', '1c262451ed469888e610a4e0dad6a74f', null);
-- year_close_list()
insert into _u_plan (fn, kind, a, b) values
  ('public.year_close_list()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.year_close_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if public._org_on123() and not public._acct_all() then raise exception 'not allowed'; end if;   -- scope123: year closes are company-level records (owner only until the per-entity books of Stage C2)
  return jsonb_build_object('on', public.rule_on('year_close_on'), 'period_closed_until', public.rule_txt('period_closed_until'), 'owner', public.is_owner(),
    'rows', coalesce((select jsonb_agg(to_jsonb(y) - 'client_id' order by y.fiscal_to desc, y.id desc) from public.year_closes y), '[]'::jsonb));
end $function$$r0_0$, null),
  ('public.year_close_list()', 'known', '90e8d1a776fda4d13dc90fe6d13e54be', null);
do $u538$
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
  if miss <> '' then raise exception 'phase538: these functions have an unknown text, nothing was changed. Send this message to the agent:%', miss; end if;
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then
      execute rbody; nfix := nfix + 1; continue;
    end if;
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    insert into public._union_fn_backup (fn, why, def) values (f.fn, 'phase538: merged text of the two lines', cur);
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
  raise notice 'phase538: % function(s) changed', nfix;
end $u538$;
drop table if exists _u_plan;
