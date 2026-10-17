-- ============================================================
-- BOS tool - Phase 318 (CRM package F, label 118): LOYALTY EXTRAS part 3 - COUPONS AND VOUCHERS.
-- Needs phase316 (and phase43; phase40 only for the optional voucher liability). Paste after phase317. Paste twice is safe.
--
-- WHAT IT DOES: a coupon / voucher is a code worth a percent or an amount off a bill, with a validity window, a minimum bill, a total use limit, a per-customer
-- limit and an optional scope (outlets, items, item categories). It can be for anyone or for one customer. Every use is written to a log.
-- V1 does NOT change record_sale2: the cashier asks crmf_coupon_check for the discount, types it through the normal discount control (normal approval
-- rules apply), then calls crmf_coupon_redeem_after_sale(code, sale). That records the use and raises a YELLOW Exceptions row when the discount on the bill
-- differs from what the coupon gives. Hook text: docs/integration/CRM-F.md.
--
-- OWNER RULES KEPT:
--   * crm_voucher_on is OFF: check and redeem refuse ("vouchers_off"). Coupons can be prepared while it is OFF; nothing starts by itself.
--   * crm_voucher_max_percent / crm_voucher_max_amount are blank: a coupon of that kind cannot be created (a blank number blocks, nothing is invented).
--     Above the maximum only the owner may create it, with a reason (audit line).
--   * Exceptions with a reason: the owner or a holder of crm_coupon_override may accept a coupon that is expired, not started, below the minimum bill, at another
--     outlet or past the per-customer limit, WITH a reason (audit line + yellow Exceptions row). A retired coupon, a coupon that is used up, a personal coupon
--     of another customer and a bill with nothing in the coupon's scope can never be overridden.
--   * Accounting figures never change unless the owner switches VOUCHER LIABILITY on (below). A coupon is a discount record; the discount is already inside the sale total.
--
-- VOUCHER LIABILITY (OFF by default; the ONLY thing in this package that writes to the books):
--   crm_voucher_liability_on (OFF)   crm_voucher_liability_from (blank = cannot be switched on)   crm_voucher_liability_account (a liability account code)   crm_voucher_expense_account (an expense account code)
--   Function crmf_voucher_liability_sync(): for each AMOUNT coupon marked "post liability" (max uses set, issued on or after the effective-from date) the books hold
--   (value x max uses) minus the discount already given, as a provision: Dr the chosen expense account, Cr the chosen liability account; it falls (Dr liability, Cr expense) as
--   the coupon is used, and goes to zero when the coupon expires, is retired, or a sale that used it is voided. Every entry has two lines and Dr = Cr (the one journal
--   writer of phase40 refuses anything else), is dated today (never in a closed period), and the sync is self-healing: it posts only the difference between what the
--   books hold and what should be held. crmf_voucher_liability_wind_down() moves everything back to zero (use it before switching the setting off).
--   Gift cards that are SOLD for cash (package F2) are a different thing and are not here. The accounting treatment is a proposal for the owner and the accountant to confirm.
-- GRANTS: crm_voucher_issue (create / edit coupons), crm_coupon_override (accept a coupon outside its limits with a reason). The owner always may.
-- ============================================================

do $g$ begin
  if to_regprocedure('public._crmf_present()') is null then raise exception 'phase318 needs phase316 first'; end if;
  if to_regprocedure('public._acct_write(date,integer,text,text,text,text,text,jsonb,bigint,uuid,text)') is null then raise exception 'phase318 needs phase40 (the books) first'; end if;
end $g$;

-- ---------- grants and settings ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select v.c, 'master', v.s, v.l, v.l, v.l, 'once', null from (values
  ('crm_voucher_issue', 73, 'Create and edit coupons and vouchers'),
  ('crm_coupon_override', 74, 'Accept a coupon outside its limits, with a reason')) v(c, s, l)
where not exists (select 1 from public.grant_defs g where g.grant_code = v.c);

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'crm', v.kind, v.dv, v.unit, null, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('crm_voucher_on', 'switch', 'false'::jsonb, null::text, null::numeric, null::numeric, 'Coupons and vouchers on',
   'OFF (default) = the till cannot use a coupon. Coupons can still be prepared. ON = a coupon can be checked and recorded against a sale. The discount is still typed through the normal discount control.', 9630),
 ('crm_voucher_max_percent', 'number', null, '%', 1, 100, 'Largest percent a coupon may give',
   'Blank = percent coupons cannot be created. Above this only the owner can create one, with a reason.', 9631),
 ('crm_voucher_max_amount', 'number', null, '৳', 1, 1000000000, 'Largest taka amount a coupon may give',
   'Blank = amount coupons cannot be created. Above this only the owner can create one, with a reason.', 9632),
 ('crm_voucher_liability_on', 'switch', 'false', null, null, null, 'Book coupon liability in the accounts',
   'OFF (default) = coupons never touch the accounts. ON = for amount coupons marked "post liability" the accounts hold the unused value as a provision (see the effective-from date). Needs the date and both accounts below first.', 9633),
 ('crm_voucher_liability_from', 'text', null, 'YYYY-MM-DD', null, null, 'Coupon liability counts from this date',
   'Blank = the liability setting cannot be switched on. Only coupons created on or after this date are booked, so the past never changes. Must not be in the past when you switch it on.', 9634),
 ('crm_voucher_liability_account', 'text', null, 'code', null, null, 'Liability account for unused coupon value (chart code)',
   'Blank = cannot switch on. Type the code of an existing active liability account.', 9635),
 ('crm_voucher_expense_account', 'text', null, 'code', null, null, 'Expense account for the coupon provision (chart code)',
   'Blank = cannot switch on. Type the code of an existing active expense account.', 9636)
 ) as v(key, kind, dv, unit, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- (the settings guard _crmf_rules_guard, with the liability switch-on rules, lives in phase316, so re-pasting an earlier phase can never remove a rule)

-- ---------- tables ----------
create table if not exists public.crmf_coupons (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9][A-Z0-9-]{2,19}$'),
  name text not null check (length(btrim(name)) between 1 and 80),
  kind text not null check (kind in ('percent', 'amount')),
  value numeric not null check (value > 0 and value <= 1000000000),
  min_bill numeric check (min_bill is null or min_bill >= 0),
  max_discount numeric check (max_discount is null or max_discount > 0),
  valid_from date not null,
  valid_to date not null,
  max_uses int check (max_uses is null or max_uses >= 1),
  per_customer_uses int not null default 1 check (per_customer_uses >= 1),
  customer_id uuid references public.customers(id),
  campaign_ref text check (campaign_ref is null or length(campaign_ref) <= 60),
  note text check (note is null or length(note) <= 300),
  post_liability boolean not null default false,
  active boolean not null default true,
  client_id uuid unique,
  created_by uuid, created_staff text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (valid_to >= valid_from),
  check (kind <> 'percent' or value <= 100),
  check (not post_liability or (kind = 'amount' and max_uses is not null))
);
create table if not exists public.crmf_coupon_scope (
  coupon_id uuid not null references public.crmf_coupons(id),
  kind text not null check (kind in ('location', 'item', 'category')),
  ref text not null check (length(ref) between 1 and 80),
  primary key (coupon_id, kind, ref)
);
create table if not exists public.crmf_coupon_uses (
  id bigint generated by default as identity primary key,
  coupon_id uuid not null references public.crmf_coupons(id),
  sale_id uuid not null unique references public.sales(id),
  customer_id uuid references public.customers(id),
  location_id int,
  bill_total numeric not null,
  discount_expected numeric not null,
  discount_given numeric not null,
  mismatch boolean not null default false,
  override_reason text,
  client_id uuid unique,
  at timestamptz not null default now(),
  by_user uuid, by_staff text
);
create index if not exists crmf_coupon_uses_coupon on public.crmf_coupon_uses (coupon_id, customer_id);
create table if not exists public.crmf_liab_postings (
  id bigint generated by default as identity primary key,
  coupon_id uuid not null references public.crmf_coupons(id),
  delta numeric not null check (delta <> 0),
  entry_id bigint not null references public.journal_entries(id),
  why text not null,
  at timestamptz not null default now(),
  by_user uuid
);
create index if not exists crmf_liab_postings_coupon on public.crmf_liab_postings (coupon_id);
drop trigger if exists crmf_coupon_uses_ro on public.crmf_coupon_uses;
create trigger crmf_coupon_uses_ro before update or delete on public.crmf_coupon_uses for each row execute function public._append_only43();
drop trigger if exists crmf_coupon_uses_ro_t on public.crmf_coupon_uses;
create trigger crmf_coupon_uses_ro_t before truncate on public.crmf_coupon_uses for each statement execute function public._append_only43();
drop trigger if exists crmf_liab_postings_ro on public.crmf_liab_postings;
create trigger crmf_liab_postings_ro before update or delete on public.crmf_liab_postings for each row execute function public._append_only43();
drop trigger if exists crmf_liab_postings_ro_t on public.crmf_liab_postings;
create trigger crmf_liab_postings_ro_t before truncate on public.crmf_liab_postings for each statement execute function public._append_only43();
drop trigger if exists audit_crmf_coupons on public.crmf_coupons;
create trigger audit_crmf_coupons after insert or update on public.crmf_coupons for each row execute function public.log_change('id');
drop trigger if exists crmf_coupons_no_delete on public.crmf_coupons;
create trigger crmf_coupons_no_delete before delete on public.crmf_coupons for each row execute function public.no_hard_delete();
alter table public.crmf_coupons enable row level security;
alter table public.crmf_coupon_scope enable row level security;
alter table public.crmf_coupon_uses enable row level security;
alter table public.crmf_liab_postings enable row level security;
create or replace function public._crmf_voucher_mgr() returns boolean language sql stable security definer set search_path = public as $$
  select public._crmf_mgr() or (public.is_active() and public.has_grant('crm_voucher_issue'));
$$;
create or replace function public._crmf_override_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_coupon_override'));
$$;
drop policy if exists crmf_coupons_read on public.crmf_coupons;
create policy crmf_coupons_read on public.crmf_coupons for select to authenticated using (public._crmf_voucher_mgr());
drop policy if exists crmf_coupon_scope_read on public.crmf_coupon_scope;
create policy crmf_coupon_scope_read on public.crmf_coupon_scope for select to authenticated using (public._crmf_voucher_mgr());
drop policy if exists crmf_coupon_uses_read on public.crmf_coupon_uses;
create policy crmf_coupon_uses_read on public.crmf_coupon_uses for select to authenticated using (public._crmf_voucher_mgr());
drop policy if exists crmf_liab_postings_read on public.crmf_liab_postings;
create policy crmf_liab_postings_read on public.crmf_liab_postings for select to authenticated using (public._crmf_voucher_mgr() or public._acct_manage());
revoke all on public.crmf_coupons, public.crmf_coupon_scope, public.crmf_coupon_uses, public.crmf_liab_postings from public, anon, authenticated;
grant select on public.crmf_coupons, public.crmf_coupon_scope, public.crmf_coupon_uses, public.crmf_liab_postings to authenticated;

-- ---------- the rule check, in one place (used by the till check, the redemption and the report) ----------
-- Returns {ok, reason, overridden[], discount, eligible}. Business refusals are answers, not errors. p_override = the caller may and did give a reason.
create or replace function public._crmf_coupon_eval(c public.crmf_coupons, p_loc int, p_customer uuid, p_lines jsonb, p_subtotal numeric, p_date date, p_exclude uuid, p_override boolean)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare soft text[] := '{}'; hard text; elig numeric; disc numeric; live int; cl int; sc_loc boolean; sc_item boolean; ln jsonb; amt numeric; iid uuid; icat text; hit boolean;
begin
  if p_subtotal is null or p_subtotal < 0 then raise exception 'bad_number'; end if;
  if not c.active then return jsonb_build_object('ok', false, 'reason', 'retired', 'overridden', '[]'::jsonb); end if;
  if p_date < c.valid_from then soft := soft || 'not_started'::text; end if;
  if p_date > c.valid_to then soft := soft || 'expired'::text; end if;
  if c.customer_id is not null and p_customer is distinct from c.customer_id then hard := 'wrong_customer'; end if;
  if p_customer is null then soft := soft || 'customer_needed'::text; end if;
  select exists (select 1 from public.crmf_coupon_scope where coupon_id = c.id and kind = 'location') into sc_loc;
  if sc_loc and not exists (select 1 from public.crmf_coupon_scope where coupon_id = c.id and kind = 'location' and ref = p_loc::text) then soft := soft || 'wrong_outlet'::text; end if;
  select exists (select 1 from public.crmf_coupon_scope where coupon_id = c.id and kind in ('item', 'category')) into sc_item;
  if sc_item then
    elig := 0;
    for ln in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
      begin
        iid := nullif(ln->>'item_id', '')::uuid;
        amt := coalesce(nullif(ln->>'amount', '')::numeric, nullif(ln->>'qty', '')::numeric * nullif(ln->>'price', '')::numeric, 0);
      exception when others then raise exception 'bad_lines'; end;
      continue when iid is null or amt <= 0;
      select category into icat from public.items where id = iid;
      select exists (select 1 from public.crmf_coupon_scope s where s.coupon_id = c.id and ((s.kind = 'item' and s.ref = iid::text) or (s.kind = 'category' and icat is not null and s.ref = icat))) into hit;
      if hit then elig := elig + amt; end if;
    end loop;
    elig := least(elig, p_subtotal);
    if elig <= 0 and hard is null then hard := 'nothing_in_scope'; end if;
  else
    elig := p_subtotal;
  end if;
  if c.min_bill is not null and p_subtotal < c.min_bill then soft := soft || 'min_bill'::text; end if;
  select count(*)::int into live from public.crmf_coupon_uses u join public.sales s on s.id = u.sale_id
    where u.coupon_id = c.id and s.status = 'done' and u.sale_id is distinct from p_exclude;
  if c.max_uses is not null and live >= c.max_uses and hard is null then hard := 'used_up'; end if;
  if p_customer is not null then
    select count(*)::int into cl from public.crmf_coupon_uses u join public.sales s on s.id = u.sale_id
      where u.coupon_id = c.id and u.customer_id = p_customer and s.status = 'done' and u.sale_id is distinct from p_exclude;
    if cl >= c.per_customer_uses then soft := soft || 'customer_limit'::text; end if;
  end if;
  disc := case c.kind when 'percent' then round(elig * c.value / 100, 2) else least(c.value, elig) end;
  if c.kind = 'percent' and c.max_discount is not null then disc := least(disc, c.max_discount); end if;
  disc := greatest(least(disc, p_subtotal), 0);
  if hard is not null then return jsonb_build_object('ok', false, 'reason', hard, 'overridden', '[]'::jsonb, 'discount', 0, 'eligible', coalesce(elig, 0)); end if;
  if array_length(soft, 1) > 0 and not p_override then
    return jsonb_build_object('ok', false, 'reason', soft[1], 'reasons', to_jsonb(soft), 'overridable', true, 'overridden', '[]'::jsonb, 'discount', 0, 'eligible', elig);
  end if;
  return jsonb_build_object('ok', true, 'reason', null, 'overridden', to_jsonb(soft), 'discount', disc, 'eligible', elig, 'left_uses', case when c.max_uses is null then null else greatest(c.max_uses - live, 0) end);
end $$;

create or replace function public._crmf_code(p_code text) returns text language sql immutable as $$ select upper(btrim(coalesce(p_code, ''))) $$;

-- ---------- coupon master: create / edit ----------
-- p keys: code (new only), name, kind (percent|amount), value, min_bill, max_discount, valid_from, valid_to, max_uses, per_customer_uses, customer_id, campaign_ref, note,
--         post_liability, active, scope {"locations":[1,2],"items":["<uuid>"],"categories":["<text>"]}. A missing key is not changed; an empty value clears an optional field.
-- After the first use the money terms (kind, value, minimum, cap, customer, scope) are locked: retire the coupon and make a new one.
create or replace function public.crmf_coupon_save(p_id uuid, p jsonb, p_client uuid default null, p_override text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.crmf_coupons; n public.crmf_coupons; k text; v numeric; mx numeric; ov text := nullif(btrim(p_override), ''); sc jsonb; x jsonb; used int; kind_ text; val_ numeric; over_ boolean := false;
begin
  if not public._crmf_voucher_mgr() then raise exception 'not allowed'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_value'; end if;
  perform public._client_lock(p_client);
  if p_id is null then
    if p_client is not null then
      select * into c from public.crmf_coupons where client_id = p_client;
      if found then return jsonb_build_object('dup', true, 'id', c.id, 'code', c.code); end if;
    end if;
    k := public._crmf_code(p->>'code');
    if k !~ '^[A-Z0-9][A-Z0-9-]{2,19}$' then raise exception 'bad_code'; end if;
    if exists (select 1 from public.crmf_coupons where code = k) then raise exception 'code_exists'; end if;
    kind_ := p->>'kind'; if kind_ is null or kind_ not in ('percent', 'amount') then raise exception 'bad_kind'; end if;
    val_ := public._n43(p, 'value', 0.01, 1000000000); if val_ is null then raise exception 'value_required'; end if;
    if nullif(btrim(p->>'name'), '') is null then raise exception 'name_required'; end if;
    if nullif(btrim(p->>'valid_from'), '') is null or nullif(btrim(p->>'valid_to'), '') is null then raise exception 'validity_required'; end if;
  else
    select * into c from public.crmf_coupons where id = p_id for update;
    if not found then raise exception 'not found'; end if;
    kind_ := coalesce(p->>'kind', c.kind);
    val_ := coalesce(public._n43(p, 'value', 0.01, 1000000000), c.value);
    select count(*)::int into used from public.crmf_coupon_uses where coupon_id = c.id;
    if used > 0 and (kind_ is distinct from c.kind or val_ is distinct from c.value or p ? 'min_bill' or p ? 'max_discount' or p ? 'customer_id' or p ? 'scope' or p ? 'post_liability') then raise exception 'locked_after_use'; end if;
  end if;
  if kind_ = 'percent' then
    if val_ > 100 then raise exception 'bad_number'; end if;
    mx := public.rule_num('crm_voucher_max_percent'); if mx is null then raise exception 'max_percent_not_set'; end if;
  else
    mx := public.rule_num('crm_voucher_max_amount'); if mx is null then raise exception 'max_amount_not_set'; end if;
  end if;
  if val_ > mx and (p_id is null or val_ is distinct from c.value or kind_ is distinct from c.kind) then
    if not public.is_owner() then raise exception 'over_maximum'; end if;
    ov := public._crmf_reason(ov); over_ := true;
  end if;
  -- friendly messages before the table checks would speak
  if p_id is null then
    if public._d43(p, 'valid_to') < public._d43(p, 'valid_from') then raise exception 'bad_date'; end if;
    if coalesce((p->>'post_liability')::boolean, false) and (kind_ <> 'amount' or public._n43(p, 'max_uses', 1, 100000000) is null) then raise exception 'liability_needs_amount_and_max_uses'; end if;
  else
    if coalesce(public._d43(p, 'valid_to'), c.valid_to) < coalesce(public._d43(p, 'valid_from'), c.valid_from) then raise exception 'bad_date'; end if;
    if (case when p ? 'post_liability' then coalesce((p->>'post_liability')::boolean, false) else c.post_liability end)
       and (kind_ <> 'amount' or (case when p ? 'max_uses' then public._n43(p, 'max_uses', 1, 100000000) else c.max_uses end) is null) then raise exception 'liability_needs_amount_and_max_uses'; end if;
  end if;
  if p_id is null then
    insert into public.crmf_coupons (code, name, kind, value, min_bill, max_discount, valid_from, valid_to, max_uses, per_customer_uses, customer_id, campaign_ref, note, post_liability, client_id, created_by, created_staff)
      values (k, left(btrim(p->>'name'), 80), kind_, val_, public._n43(p, 'min_bill', 0, 1000000000), public._n43(p, 'max_discount', 0.01, 1000000000), public._d43(p, 'valid_from'), public._d43(p, 'valid_to'),
              public._n43(p, 'max_uses', 1, 100000000)::int, coalesce(public._n43(p, 'per_customer_uses', 1, 100000)::int, 1), nullif(p->>'customer_id', '')::uuid, left(nullif(btrim(p->>'campaign_ref'), ''), 60),
              left(nullif(btrim(p->>'note'), ''), 300), coalesce((p->>'post_liability')::boolean, false), p_client, auth.uid(), public._crmf_staff())
      returning * into n;
  else
    update public.crmf_coupons set
      name = case when p ? 'name' then coalesce(left(nullif(btrim(p->>'name'), ''), 80), name) else name end,
      kind = kind_, value = val_,
      min_bill = case when p ? 'min_bill' then public._n43(p, 'min_bill', 0, 1000000000) else min_bill end,
      max_discount = case when p ? 'max_discount' then public._n43(p, 'max_discount', 0.01, 1000000000) else max_discount end,
      valid_from = case when p ? 'valid_from' then coalesce(public._d43(p, 'valid_from'), valid_from) else valid_from end,
      valid_to = case when p ? 'valid_to' then coalesce(public._d43(p, 'valid_to'), valid_to) else valid_to end,
      max_uses = case when p ? 'max_uses' then public._n43(p, 'max_uses', 1, 100000000)::int else max_uses end,
      per_customer_uses = case when p ? 'per_customer_uses' then coalesce(public._n43(p, 'per_customer_uses', 1, 100000)::int, per_customer_uses) else per_customer_uses end,
      customer_id = case when p ? 'customer_id' then nullif(p->>'customer_id', '')::uuid else customer_id end,
      campaign_ref = case when p ? 'campaign_ref' then left(nullif(btrim(p->>'campaign_ref'), ''), 60) else campaign_ref end,
      note = case when p ? 'note' then left(nullif(btrim(p->>'note'), ''), 300) else note end,
      post_liability = case when p ? 'post_liability' then coalesce((p->>'post_liability')::boolean, false) else post_liability end,
      active = case when p ? 'active' then coalesce((p->>'active')::boolean, active) else active end,
      updated_at = now()
    where id = p_id returning * into n;
  end if;
  if p ? 'scope' and (p_id is null or used = 0) then
    sc := p->'scope';
    if sc is not null and jsonb_typeof(sc) = 'object' then
      delete from public.crmf_coupon_scope where coupon_id = n.id;
      for x in select * from jsonb_array_elements(coalesce(sc->'locations', '[]'::jsonb)) loop
        if not exists (select 1 from public.locations where id = (x #>> '{}')::int) then raise exception 'bad_location'; end if;
        insert into public.crmf_coupon_scope (coupon_id, kind, ref) values (n.id, 'location', x #>> '{}') on conflict do nothing;
      end loop;
      for x in select * from jsonb_array_elements(coalesce(sc->'items', '[]'::jsonb)) loop
        if not exists (select 1 from public.items where id = (x #>> '{}')::uuid) then raise exception 'bad_item'; end if;
        insert into public.crmf_coupon_scope (coupon_id, kind, ref) values (n.id, 'item', x #>> '{}') on conflict do nothing;
      end loop;
      for x in select * from jsonb_array_elements(coalesce(sc->'categories', '[]'::jsonb)) loop
        if length(btrim(x #>> '{}')) = 0 then raise exception 'bad_value'; end if;
        insert into public.crmf_coupon_scope (coupon_id, kind, ref) values (n.id, 'category', left(btrim(x #>> '{}'), 80)) on conflict do nothing;
      end loop;
    end if;
  end if;
  if n.valid_to < n.valid_from then raise exception 'bad_date'; end if;
  if n.post_liability and (n.kind <> 'amount' or n.max_uses is null) then raise exception 'liability_needs_amount_and_max_uses'; end if;
  if over_ then perform public._crmf_audit('crmf_coupon_over_maximum', 'crmf_coupons', n.id::text, jsonb_build_object('code', n.code, 'kind', n.kind, 'value', n.value, 'max', mx, 'reason', ov)); end if;
  if public.rule_on('crm_voucher_liability_on') and n.post_liability then perform public._crmf_liab_sync_one(n.id); end if;
  return jsonb_build_object('dup', false, 'id', n.id, 'code', n.code);
end $$;

create or replace function public.crmf_coupon_list(p_active boolean default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._crmf_voucher_mgr() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.created_at desc) from (
    select c.id, c.code, c.name, c.kind, c.value, c.min_bill, c.max_discount, c.valid_from, c.valid_to, c.max_uses, c.per_customer_uses, c.customer_id, c.campaign_ref, c.note, c.post_liability, c.active, c.created_at,
           (select count(*) from public.crmf_coupon_uses u join public.sales s on s.id = u.sale_id where u.coupon_id = c.id and s.status = 'done')::int as uses,
           coalesce((select sum(u.discount_given) from public.crmf_coupon_uses u join public.sales s on s.id = u.sale_id where u.coupon_id = c.id and s.status = 'done'), 0) as discount_total,
           coalesce((select jsonb_agg(jsonb_build_object('kind', sc.kind, 'ref', sc.ref) order by sc.kind, sc.ref) from public.crmf_coupon_scope sc where sc.coupon_id = c.id), '[]'::jsonb) as scope
      from public.crmf_coupons c where p_active is null or c.active = p_active) z), '[]'::jsonb);
end $$;

-- ---------- the till: check (writes nothing) ----------
create or replace function public.crmf_coupon_check(p_code text, p_loc int, p_customer uuid, p_lines jsonb, p_subtotal numeric, p_override text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.crmf_coupons; ov boolean := false; ev jsonb;
begin
  if not (public._crmf_voucher_mgr() or (public.is_active() and public.can_do('POS', 'enter'))) then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_voucher_on') then raise exception 'vouchers_off'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_loc is null then raise exception 'location_required'; end if;
  if nullif(btrim(p_override), '') is not null then
    if not public._crmf_override_ok() then raise exception 'not allowed'; end if;
    perform public._crmf_reason(p_override); ov := true;
  end if;
  select * into c from public.crmf_coupons where code = public._crmf_code(p_code);
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  ev := public._crmf_coupon_eval(c, p_loc, p_customer, p_lines, p_subtotal, public._crmf_today(), null, ov);
  return ev || jsonb_build_object('code', c.code, 'name', c.name, 'kind', c.kind, 'value', c.value);
end $$;

-- ---------- after the sale: record the use ----------
create or replace function public.crmf_coupon_redeem_after_sale(p_code text, p_sale uuid, p_override text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.crmf_coupons; s public.sales; u public.crmf_coupon_uses; ev jsonb; ov boolean := false; ovt text := nullif(btrim(p_override), ''); exp_ numeric; mism boolean; k text := public._crmf_code(p_code); mgr boolean;
begin
  mgr := public._crmf_voucher_mgr() or public._crmf_override_ok();       -- the owner, coupon managers and override holders may act on any sale; a cashier only on their own
  if not (mgr or (public.is_active() and public.can_do('POS', 'enter'))) then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_voucher_on') then raise exception 'vouchers_off'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into u from public.crmf_coupon_uses where client_id = p_client;
    if found then return jsonb_build_object('ok', true, 'dup', true, 'use_id', u.id); end if;
  end if;
  select * into s from public.sales where id = p_sale;
  if not found then raise exception 'sale_not_found'; end if;
  if s.status <> 'done' then raise exception 'sale_not_done'; end if;
  if not public.can_loc(s.location_id) then raise exception 'not allowed for this location'; end if;
  if s.created_by is distinct from auth.uid() and not mgr then raise exception 'not allowed'; end if;
  if ovt is not null then
    if not public._crmf_override_ok() then raise exception 'not allowed'; end if;
    ovt := public._crmf_reason(ovt); ov := true;
  end if;
  select * into u from public.crmf_coupon_uses where sale_id = p_sale;
  if found then
    if u.coupon_id = (select id from public.crmf_coupons where code = k) then return jsonb_build_object('ok', true, 'dup', true, 'use_id', u.id); end if;
    return jsonb_build_object('ok', false, 'reason', 'sale_has_coupon');
  end if;
  select * into c from public.crmf_coupons where code = k for update;                          -- one redemption at a time per coupon: the race is decided here
  if not found then
    if s.discount > 0 then perform public._crmf_exception('coupon_refused', s.location_id, s.sale_date, s.discount, 'Receipt ' || s.receipt || ': coupon ' || left(k, 20) || ' not found but the bill carries a discount', s.id); end if;
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  ev := public._crmf_coupon_eval(c, s.location_id, s.customer_id, s.lines, s.subtotal, s.sale_date, s.id, ov);
  if not (ev->>'ok')::boolean then
    if s.discount > 0 then
      perform public._crmf_exception('coupon_refused', s.location_id, s.sale_date, s.discount, 'Receipt ' || s.receipt || ': coupon ' || c.code || ' refused (' || (ev->>'reason') || ') but the bill carries a discount', s.id);
    end if;
    return jsonb_build_object('ok', false, 'reason', ev->>'reason', 'overridable', coalesce((ev->>'overridable')::boolean, false));
  end if;
  exp_ := (ev->>'discount')::numeric;
  mism := abs(s.discount - exp_) > 0.01;
  insert into public.crmf_coupon_uses (coupon_id, sale_id, customer_id, location_id, bill_total, discount_expected, discount_given, mismatch, override_reason, client_id, by_user, by_staff)
    values (c.id, s.id, s.customer_id, s.location_id, s.total, exp_, s.discount, mism, case when jsonb_array_length(ev->'overridden') > 0 then ovt end, p_client, auth.uid(), public._crmf_staff()) returning * into u;
  if jsonb_array_length(ev->'overridden') > 0 then
    perform public._crmf_audit('crmf_coupon_override', 'crmf_coupon_uses', u.id::text, jsonb_build_object('code', c.code, 'sale', s.id, 'rules', ev->'overridden', 'reason', ovt));
    perform public._crmf_exception('coupon_override', s.location_id, s.sale_date, s.discount, 'Receipt ' || s.receipt || ': coupon ' || c.code || ' accepted past ' || (ev->>'overridden') || ': ' || ovt, s.id);
  end if;
  if mism then
    perform public._crmf_exception('coupon_discount_mismatch', s.location_id, s.sale_date, abs(s.discount - exp_), 'Receipt ' || s.receipt || ': coupon ' || c.code || ' gives ' || exp_ || ' but the bill discount is ' || s.discount, s.id);
  end if;
  if c.post_liability and public.rule_on('crm_voucher_liability_on') then perform public._crmf_liab_sync_one(c.id); end if;
  return jsonb_build_object('ok', true, 'dup', false, 'use_id', u.id, 'discount_expected', exp_, 'discount_given', s.discount, 'mismatch', mism);
end $$;

create or replace function public.crmf_coupon_uses_list(p_coupon uuid default null, p_from date default null, p_to date default null, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._crmf_voucher_mgr() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
    select u.id, u.coupon_id, c.code, u.sale_id, s.receipt, s.sale_date, s.status as sale_status, u.location_id, u.customer_id, cu.name as customer_name, u.bill_total,
           u.discount_expected, u.discount_given, u.mismatch, u.override_reason, u.at, u.by_staff
      from public.crmf_coupon_uses u join public.crmf_coupons c on c.id = u.coupon_id join public.sales s on s.id = u.sale_id left join public.customers cu on cu.id = u.customer_id
     where (p_coupon is null or u.coupon_id = p_coupon) and (p_from is null or s.sale_date >= p_from) and (p_to is null or s.sale_date <= p_to)
     order by u.id desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) z), '[]'::jsonb);
end $$;

-- ---------- voucher liability (OFF; the only writer to the books in this package) ----------
-- what the books should hold for one coupon right now
create or replace function public._crmf_liab_target(c public.crmf_coupons) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare used numeric;
begin
  if not c.post_liability or c.kind <> 'amount' or c.max_uses is null then return 0; end if;
  if not c.active or c.valid_to < public._crmf_today() then return 0; end if;
  select coalesce(sum(u.discount_given), 0) into used from public.crmf_coupon_uses u join public.sales s on s.id = u.sale_id where u.coupon_id = c.id and s.status = 'done';
  return greatest(c.value * c.max_uses - used, 0);
end $$;

-- brings the books to the target for ONE coupon: posts only the difference, two lines, Dr = Cr. p_force_zero = wind down (target 0, even when the setting is OFF)
create or replace function public._crmf_liab_post(p_coupon uuid, p_force_zero boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.crmf_coupons; tgt numeric; posted numeric; d numeric; liab bigint; expn bigint; n int; eid bigint; lines jsonb; today date := public._crmf_today(); from_ date := public.rule_txt('crm_voucher_liability_from')::date;
begin
  select * into c from public.crmf_coupons where id = p_coupon for update;
  if not found then raise exception 'not found'; end if;
  select coalesce(sum(delta), 0), count(*)::int into posted, n from public.crmf_liab_postings where coupon_id = c.id;
  if p_force_zero then tgt := 0;
  else
    if from_ is null or (c.created_at at time zone 'Asia/Dhaka')::date < from_ then return jsonb_build_object('skipped', 'before_effective_date'); end if;
    tgt := public._crmf_liab_target(c);
  end if;
  d := round(tgt - posted, 2);
  if d = 0 then return jsonb_build_object('posted', 0, 'target', tgt, 'held', posted); end if;
  if not public.rule_on('accounting_on') then raise exception 'accounting_off'; end if;
  select id into liab from public.coa_accounts where code = public.rule_txt('crm_voucher_liability_account') and type = 'liability' and active and not is_group;
  select id into expn from public.coa_accounts where code = public.rule_txt('crm_voucher_expense_account') and type = 'expense' and active and not is_group;
  if liab is null or expn is null then raise exception 'liability_accounts_needed'; end if;
  if public._acct_locked(today) then raise exception 'period_closed'; end if;
  lines := case when d > 0
    then jsonb_build_array(jsonb_build_object('account_id', expn, 'debit', d, 'credit', 0, 'memo', 'Coupon ' || c.code), jsonb_build_object('account_id', liab, 'debit', 0, 'credit', d, 'memo', 'Coupon ' || c.code))
    else jsonb_build_array(jsonb_build_object('account_id', liab, 'debit', -d, 'credit', 0, 'memo', 'Coupon ' || c.code), jsonb_build_object('account_id', expn, 'debit', 0, 'credit', -d, 'memo', 'Coupon ' || c.code)) end;
  eid := public._acct_write(today, null, 'crmf_voucher', 'cp:' || c.id || ':' || (n + 1), 'voucher_liability',
           'Coupon ' || c.code || case when d > 0 then ': unused value held' else ': unused value released' end, null, lines);
  insert into public.crmf_liab_postings (coupon_id, delta, entry_id, why, by_user) values (c.id, d, eid, case when p_force_zero then 'wind_down' when d > 0 then 'issue' else 'use_or_expiry' end, auth.uid());
  return jsonb_build_object('posted', d, 'target', tgt, 'held', tgt, 'entry_id', eid);
end $$;

-- the automatic callers (after a save, a redemption, a void) must never stop the main action: an error is a warning, and the next sync repairs it
create or replace function public._crmf_liab_sync_one(p_coupon uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.rule_on('crm_voucher_liability_on') then return; end if;
  begin perform pg_advisory_xact_lock(hashtextextended('crmf_liab', 0)); perform public._crmf_liab_post(p_coupon, false);
  exception when others then raise warning 'crmf voucher liability sync failed for coupon %: %', p_coupon, sqlerrm; end;
end $$;

-- the named, owner-visible function: sync every marked coupon (or one). Owner or accounts manager. Self-healing: run it again any time.
create or replace function public.crmf_voucher_liability_sync(p_coupon uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; res jsonb; out_ jsonb := '[]'::jsonb; errs jsonb := '[]'::jsonb; n int := 0;
begin
  if not (public.is_owner() or public._acct_manage()) then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_voucher_liability_on') then return jsonb_build_object('off', true); end if;
  perform pg_advisory_xact_lock(hashtextextended('crmf_liab', 0));
  for r in select id, code from public.crmf_coupons where (p_coupon is null or id = p_coupon)
            and (post_liability or exists (select 1 from public.crmf_liab_postings x where x.coupon_id = crmf_coupons.id)) order by created_at loop
    begin res := public._crmf_liab_post(r.id, false);
      if coalesce((res->>'posted')::numeric, 0) <> 0 then n := n + 1; out_ := out_ || jsonb_build_object('code', r.code, 'posted', res->'posted'); end if;
    exception when others then errs := errs || jsonb_build_object('code', r.code, 'error', sqlerrm); end;
  end loop;
  return jsonb_build_object('off', false, 'entries', n, 'rows', out_, 'errors', errs);
end $$;

-- move every held amount back to zero (use before switching the setting off). Owner or accounts manager; a reason is required.
create or replace function public.crmf_voucher_liability_wind_down(p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; res jsonb; n int := 0; tot numeric := 0; why text;
begin
  if not (public.is_owner() or public._acct_manage()) then raise exception 'not allowed'; end if;
  why := public._crmf_reason(p_reason);
  perform pg_advisory_xact_lock(hashtextextended('crmf_liab', 0));
  for r in select coupon_id from public.crmf_liab_postings group by coupon_id having sum(delta) <> 0 loop
    res := public._crmf_liab_post(r.coupon_id, true);
    n := n + 1; tot := tot + coalesce((res->>'posted')::numeric, 0);
  end loop;
  perform public._crmf_audit('crmf_voucher_liability_wind_down', 'crmf_liab_postings', null, jsonb_build_object('coupons', n, 'released', -tot, 'reason', why));
  return jsonb_build_object('coupons', n, 'released', -tot);
end $$;

create or replace function public.crmf_voucher_liability_report() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_owner() or public._acct_manage() or public._acct_view()) then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('crm_voucher_liability_on'), 'from', public.rule_txt('crm_voucher_liability_from'),
    'liability_account', public.rule_txt('crm_voucher_liability_account'), 'expense_account', public.rule_txt('crm_voucher_expense_account'),
    'held_total', coalesce((select sum(delta) from public.crmf_liab_postings), 0),
    'rows', coalesce((select jsonb_agg(to_jsonb(z) order by z.code) from (
      select c.code, c.name, c.value, c.max_uses, c.valid_to, c.active, public._crmf_liab_target(c) as should_hold, coalesce((select sum(delta) from public.crmf_liab_postings p where p.coupon_id = c.id), 0) as held
        from public.crmf_coupons c where c.post_liability or exists (select 1 from public.crmf_liab_postings p where p.coupon_id = c.id)) z), '[]'::jsonb));
end $$;

-- a voided sale gives its coupon use back: the liability follows (only while the setting is ON; an error never stops the void)
create or replace function public._crmf_sale_void_coupon() returns trigger language plpgsql security definer set search_path = public as $$
declare u public.crmf_coupon_uses;
begin
  if new.status <> 'void' or old.status is not distinct from 'void' or not public.rule_on('crm_voucher_liability_on') then return new; end if;
  begin
    select * into u from public.crmf_coupon_uses where sale_id = new.id;
    if found then perform public._crmf_liab_sync_one(u.coupon_id); end if;
  exception when others then raise warning 'crmf coupon void sync failed for sale %: %', new.id, sqlerrm; end;
  return new;
end $$;
revoke all on function public._crmf_sale_void_coupon() from public, anon, authenticated;
drop trigger if exists sales_void_coupon_crmf on public.sales;
create trigger sales_void_coupon_crmf after update of status on public.sales for each row execute function public._crmf_sale_void_coupon();

-- ---------- privileges ----------
revoke all on function public._crmf_voucher_mgr(), public._crmf_override_ok(), public._crmf_coupon_eval(public.crmf_coupons, int, uuid, jsonb, numeric, date, uuid, boolean), public._crmf_code(text),
  public._crmf_liab_target(public.crmf_coupons), public._crmf_liab_post(uuid, boolean), public._crmf_liab_sync_one(uuid) from public, anon, authenticated;
grant execute on function public._crmf_voucher_mgr() to authenticated;                 -- the table policies call it (answers true / false only)
revoke all on function public.crmf_coupon_save(uuid, jsonb, uuid, text), public.crmf_coupon_list(boolean), public.crmf_coupon_check(text, int, uuid, jsonb, numeric, text),
  public.crmf_coupon_redeem_after_sale(text, uuid, text, uuid), public.crmf_coupon_uses_list(uuid, date, date, int), public.crmf_voucher_liability_sync(uuid),
  public.crmf_voucher_liability_wind_down(text), public.crmf_voucher_liability_report() from public, anon;
grant execute on function public.crmf_coupon_save(uuid, jsonb, uuid, text), public.crmf_coupon_list(boolean), public.crmf_coupon_check(text, int, uuid, jsonb, numeric, text),
  public.crmf_coupon_redeem_after_sale(text, uuid, text, uuid), public.crmf_coupon_uses_list(uuid, date, date, int), public.crmf_voucher_liability_sync(uuid),
  public.crmf_voucher_liability_wind_down(text), public.crmf_voucher_liability_report() to authenticated;
