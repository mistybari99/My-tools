-- ============================================================
-- Phase 128 (marker dl128) - DEALER / HARDWARE-PAINT BUSINESS, part 2: principal SCHEME engine (ADDITIVE ONLY).
-- Canonical order: after phase127 (uses its scope helpers _dl_ok127 / _dl_biz127 / _dl_biz_ok127). Paste twice = no change, no error.
-- Rule dealer_scheme_on is OFF by default: while OFF every write function refuses ('feature_off'); previews (dry runs) and reads still work.
--   A "principal" is simply a row of suppliers (owner data - Asian / Berger / Classic or any other name; nothing is hardcoded).
--   Table dealer_schemes        one scheme of one principal for ONE business: kind slab | target | flat_pack, basis purchase | sale, measure value | qty,
--                               valid_from .. valid_to, status draft | active | closed | cancelled. Rules are editable only while draft (an active scheme is frozen).
--   Table dealer_scheme_items   optional item scope (no rows = every line of the principal's bills). A sale-based scheme MUST have an item scope
--                               (sales do not know the principal) - checked when the scheme is activated.
--   Table dealer_scheme_slabs   slab rows (from, to, rate %): used by kind slab. mode whole = the rate of the slab the total falls in applies to the WHOLE
--                               base value (retro); mode marginal = each slice of value earns its own slab rate (value measure only).
--   Table dealer_scheme_accruals  append-only: every accrual run writes delta = earned-to-date - already accrued (can be negative after a purchase return).
--   Table dealer_scheme_claims / dealer_scheme_claim_events  the claim register to the principal: submitted -> part_settled -> settled | rejected | cancelled;
--                               receipts are append-only events. A claim can never exceed the accrued-but-unclaimed amount of its scheme.
--   Base figures (nothing invented): purchase basis = lines of POSTED bills of that supplier at the locations of the business, bill date inside the scheme
--     period and up to the accrual date, returns counted negative; amount = the line amount as entered (before the bill-level discount). Sale basis = lines of
--     DONE sales at the locations of the business, in the item scope; amount = line amount as recorded. Sale returns are NOT netted (not built).
--   Earned amounts: slab (whole / marginal), target (reached when the measure >= target: pct of base value + flat amount, both entered), flat_pack
--     (amount per pack x net pack quantity). Everything is rounded to 2 places once, at the end. Never below 0.
--   scheme_accrue(.., p_dry := true) is the PREVIEW: it writes nothing and returns base, earned-to-date, already accrued and the delta.
--   Nothing is posted to the books or the supplier ledger by this phase (accruals and receipts are a register; the accountant decides the entries).
--   Reports: scheme_reconciliation (accrued vs claimed vs received, unclaimed, outstanding), claim_list, scheme_list / scheme_get.
--   Grants dealer_scheme_view, dealer_scheme_manage. Business scope exactly as phase127 (owner, or explicitly assigned location + grant, inside that business).
-- Rollback: leave dealer_scheme_on OFF. To remove: drop the functions and the six tables (nothing else refers to them).
-- ============================================================
begin;

do $g$
declare miss text := '';
begin
  if to_regclass('public.dealer_cheques') is null or to_regprocedure('public._dl_ok127(integer,text,text)') is null or to_regprocedure('public._dl_biz_ok127(bigint,text,text)') is null
     or to_regprocedure('public._dl_biz127(integer)') is null or to_regclass('public.dl_unit_tree127') is null then miss := miss || ' phase127'; end if;
  if to_regclass('public.purchase_bills') is null or to_regclass('public.purchase_lines') is null or to_regclass('public.sales') is null or to_regclass('public.suppliers') is null
     or to_regclass('public.items') is null then miss := miss || ' tables'; end if;
  if miss <> '' then raise exception 'phase128 needs the base schema and phases up to 127 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select v.c, 'dealer', v.s, v.b, v.m, v.e, 'once' from (values
  ('dealer_scheme_view', 129, 'প্রিন্সিপাল স্কিম, ক্লেইম ও মিলানো রিপোর্ট দেখা', 'Principal scheme, claim ও reconciliation report দেখা', 'View principal schemes, claims and the reconciliation report'),
  ('dealer_scheme_manage', 130, 'প্রিন্সিপাল স্কিম তৈরি, হিসাব তোলা, ক্লেইম', 'Principal scheme তৈরি, accrual, claim', 'Create schemes, accrue, make and settle claims')
) v(c, s, b, m, e) where not exists (select 1 from public.grant_defs g where g.grant_code = v.c);

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('dealer_scheme_on', 'dealer', 'switch', 'false', null, null, null, null,
  'প্রিন্সিপাল স্কিম চালু', 'Principal scheme চালু', 'Principal schemes',
  'চালু করলে স্কিম, হিসাব তোলা (accrual) ও ক্লেইম লেখা যাবে। শুধু আপনার দেওয়া নিয়ম থেকে অঙ্ক হয়; কিছু বাড়িয়ে ধরা হয় না।',
  'চালু করলে scheme, accrual ও claim লেখা যাবে। শুধু আপনার দেওয়া rule থেকে অঙ্ক হয়; কিছু বাড়িয়ে ধরা হয় না।',
  'When on, schemes, accruals and claims can be written. Amounts come only from the rules you enter; nothing is invented.', 1280)
on conflict (key) do nothing;

insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
select 'dealer_scheme_on', 'dealer_scheme_on', '128', 'dealer', null::jsonb, '{}'::text[],
  'যে ব্যবসায় প্রিন্সিপালের স্কিম/রিবেট আছে শুধু সেখানে চালু করুন।', 'যে business এ principal এর scheme/rebate আছে শুধু সেখানে চালু করুন।',
  'Turn on only for a business that earns principal schemes / rebates.', 1280
where not exists (select 1 from public.setup_rec_defs81 where code = 'dealer_scheme_on');

-- ---------- tables ----------
create table if not exists public.dealer_schemes (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null unique,
  business_id bigint not null references public.org_units(id),
  supplier_id uuid not null references public.suppliers(id),
  name text not null check (length(btrim(name)) between 1 and 120),
  kind text not null check (kind in ('slab', 'target', 'flat_pack')),
  basis text not null check (basis in ('purchase', 'sale')),
  measure text not null default 'value' check (measure in ('value', 'qty')),
  slab_mode text not null default 'whole' check (slab_mode in ('whole', 'marginal')),
  valid_from date not null check (valid_from >= date '2000-01-01'),
  valid_to date not null,
  target_amount numeric(18,4) check (target_amount is null or (target_amount > 0 and target_amount <= 1000000000000)),
  rebate_pct numeric(9,4) check (rebate_pct is null or (rebate_pct >= 0 and rebate_pct <= 100)),
  rebate_flat numeric(16,2) check (rebate_flat is null or (rebate_flat >= 0 and rebate_flat <= 1000000000000)),
  per_pack_amount numeric(16,4) check (per_pack_amount is null or (per_pack_amount > 0 and per_pack_amount <= 1000000000)),
  status text not null default 'draft' check (status in ('draft', 'active', 'closed', 'cancelled')),
  note text check (note is null or length(note) <= 300),
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now(),
  check (valid_to >= valid_from and valid_to <= valid_from + 1830),
  check (kind <> 'flat_pack' or (per_pack_amount is not null and measure = 'qty')),
  check (kind <> 'target' or (target_amount is not null and (rebate_pct is not null or rebate_flat is not null))),
  check (kind <> 'slab' or slab_mode = 'whole' or measure = 'value')
);
create index if not exists dealer_schemes_biz128 on public.dealer_schemes (business_id, status);
create index if not exists dealer_schemes_sup128 on public.dealer_schemes (supplier_id);

create table if not exists public.dealer_scheme_items (
  scheme_id uuid not null references public.dealer_schemes(id),
  item_id uuid not null references public.items(id),
  business_id bigint not null references public.org_units(id),
  primary key (scheme_id, item_id)
);
create table if not exists public.dealer_scheme_slabs (
  scheme_id uuid not null references public.dealer_schemes(id),
  seq int not null check (seq >= 1),
  from_amt numeric(18,4) not null check (from_amt >= 0),
  to_amt numeric(18,4) check (to_amt is null or to_amt > from_amt),
  rate_pct numeric(9,4) not null check (rate_pct >= 0 and rate_pct <= 100),
  business_id bigint not null references public.org_units(id),
  primary key (scheme_id, seq)
);
create table if not exists public.dealer_scheme_accruals (
  id bigserial primary key,
  scheme_id uuid not null references public.dealer_schemes(id),
  business_id bigint not null references public.org_units(id),
  upto_date date not null,
  base_value numeric(18,2) not null,
  base_qty numeric(18,4) not null,
  earned_to_date numeric(16,2) not null check (earned_to_date >= 0),
  delta numeric(16,2) not null,
  note text,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now()
);
create index if not exists dealer_scheme_accruals_s128 on public.dealer_scheme_accruals (scheme_id, id);
create table if not exists public.dealer_scheme_claims (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null unique,
  business_id bigint not null references public.org_units(id),
  scheme_id uuid not null references public.dealer_schemes(id),
  supplier_id uuid not null references public.suppliers(id),
  claim_no text check (claim_no is null or length(claim_no) <= 40),
  claim_date date not null,
  amount numeric(16,2) not null check (amount > 0 and amount <= 1000000000000),
  status text not null default 'submitted' check (status in ('submitted', 'part_settled', 'settled', 'rejected', 'cancelled')),
  note text check (note is null or length(note) <= 300),
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now()
);
create unique index if not exists dealer_scheme_claims_no128 on public.dealer_scheme_claims (supplier_id, lower(claim_no)) where claim_no is not null and status <> 'cancelled';
create index if not exists dealer_scheme_claims_s128 on public.dealer_scheme_claims (scheme_id, status);
create table if not exists public.dealer_scheme_claim_events (
  id bigserial primary key,
  claim_id uuid not null references public.dealer_scheme_claims(id),
  business_id bigint not null references public.org_units(id),
  kind text not null check (kind in ('submitted', 'received', 'rejected', 'cancelled')),
  amount numeric(16,2),
  on_date date,
  ref text check (ref is null or length(ref) <= 80),
  note text,
  client_id uuid unique,
  actor uuid, at timestamptz not null default now()
);
create index if not exists dealer_scheme_claim_events_c128 on public.dealer_scheme_claim_events (claim_id, id);

-- append-only records
drop trigger if exists dealer_scheme_accruals_ro on public.dealer_scheme_accruals;
create trigger dealer_scheme_accruals_ro before update or delete on public.dealer_scheme_accruals for each row execute function public._dl_append_only127();
drop trigger if exists dealer_scheme_claim_events_ro on public.dealer_scheme_claim_events;
create trigger dealer_scheme_claim_events_ro before update or delete on public.dealer_scheme_claim_events for each row execute function public._dl_append_only127();
do $t$ declare t text; begin
  foreach t in array array['dealer_schemes', 'dealer_scheme_items', 'dealer_scheme_slabs', 'dealer_scheme_claims'] loop
    -- slabs / items are replaced while a scheme is a draft: a delete there is allowed only through scheme_save (it removes rows of a DRAFT scheme)
    if t in ('dealer_schemes', 'dealer_scheme_claims') then
      execute format('drop trigger if exists %I on public.%I', t || '_no_delete', t);
      execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_no_delete', t);
    end if;
  end loop;
end $t$;
drop trigger if exists audit_dealer_schemes on public.dealer_schemes;
create trigger audit_dealer_schemes after insert or update on public.dealer_schemes for each row execute function public.log_change('id');
drop trigger if exists audit_dealer_scheme_claims on public.dealer_scheme_claims;
create trigger audit_dealer_scheme_claims after insert or update on public.dealer_scheme_claims for each row execute function public.log_change('id');

-- a scheme row is frozen once it left draft (rules cannot be rewritten under existing accruals); only status / note / audit columns move
create or replace function public._scheme_frozen128() returns trigger language plpgsql set search_path = public as $$
begin
  if old.status <> 'draft' and (new.business_id, new.supplier_id, new.name, new.kind, new.basis, new.measure, new.slab_mode, new.valid_from, new.valid_to, new.target_amount, new.rebate_pct, new.rebate_flat, new.per_pack_amount)
     is distinct from (old.business_id, old.supplier_id, old.name, old.kind, old.basis, old.measure, old.slab_mode, old.valid_from, old.valid_to, old.target_amount, old.rebate_pct, old.rebate_flat, old.per_pack_amount) then
    raise exception 'scheme_frozen'; end if;
  return new;
end $$;
drop trigger if exists dealer_schemes_frozen on public.dealer_schemes;
create trigger dealer_schemes_frozen before update on public.dealer_schemes for each row execute function public._scheme_frozen128();

-- RLS
do $r$ declare t text; begin
  foreach t in array array['dealer_schemes', 'dealer_scheme_items', 'dealer_scheme_slabs', 'dealer_scheme_accruals', 'dealer_scheme_claims', 'dealer_scheme_claim_events'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read128', t);
    execute format($p$create policy %I on public.%I for select to authenticated using (public._dl_biz_ok127(business_id, 'dealer_scheme_view', 'dealer_scheme_manage'))$p$, t || '_read128', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $r$;
revoke all on sequence public.dealer_scheme_accruals_id_seq, public.dealer_scheme_claim_events_id_seq from public, anon, authenticated;
grant execute on function public._dl_biz_ok127(bigint, text, text) to authenticated;     -- used by the row policies above (answers only about the caller)

-- ---------- helpers ----------
create or replace function public._scheme_gate128(p_biz bigint, p_manage boolean) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_manage then
    if not public._dl_biz_ok127(p_biz, 'dealer_scheme_manage') then raise exception 'not allowed'; end if;
    if not public.rule_on('dealer_scheme_on') then raise exception 'feature_off'; end if;
  else
    if not public._dl_biz_ok127(p_biz, 'dealer_scheme_view', 'dealer_scheme_manage') then raise exception 'not allowed'; end if;
  end if;
end $$;

-- the calculation: base figures and earned-to-date of one scheme up to a date. Reads only; used by the preview and by the accrual.
create or replace function public._scheme_calc128(p_id uuid, p_upto date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.dealer_schemes; d1 date; d2 date; locs int[]; items text[]; bv numeric := 0; bq numeric := 0; x numeric; e numeric := 0; r record; lo numeric; hi numeric; hit boolean := false;
begin
  select * into s from public.dealer_schemes where id = p_id;
  if not found then raise exception 'scheme_not_found'; end if;
  d1 := s.valid_from; d2 := least(s.valid_to, p_upto);
  locs := array(select l.id from public.locations l where public._dl_biz127(l.id) = s.business_id);
  items := array(select i.item_id::text from public.dealer_scheme_items i where i.scheme_id = p_id);
  if d2 >= d1 and coalesce(array_length(locs, 1), 0) > 0 then
    if s.basis = 'purchase' then
      select coalesce(sum(case b.kind when 'bill' then pl.amount else -pl.amount end), 0), coalesce(sum(case b.kind when 'bill' then pl.qty else -pl.qty end), 0)
        into bv, bq
        from public.purchase_bills b join public.purchase_lines pl on pl.bill_id = b.id
        where b.supplier_id = s.supplier_id and b.status = 'posted' and b.location_id = any (locs) and b.bill_date between d1 and d2
          and (coalesce(array_length(items, 1), 0) = 0 or pl.item_id::text = any (items));
    else
      select coalesce(sum(coalesce((e2->>'amount')::numeric, (e2->>'qty')::numeric * (e2->>'price')::numeric)), 0), coalesce(sum((e2->>'qty')::numeric), 0)
        into bv, bq
        from public.sales sa cross join lateral jsonb_array_elements(sa.lines) e2
        where sa.status = 'done' and sa.location_id = any (locs) and sa.sale_date between d1 and d2 and (e2->>'item_id') = any (items);
    end if;
  end if;
  x := case s.measure when 'qty' then bq else bv end;
  if s.kind = 'slab' then
    if s.slab_mode = 'whole' then
      select sl.rate_pct into e from public.dealer_scheme_slabs sl where sl.scheme_id = p_id and sl.from_amt <= x and (sl.to_amt is null or x < sl.to_amt) order by sl.seq limit 1;
      e := coalesce(bv * coalesce(e, 0) / 100, 0);
    else
      e := 0;
      for r in select * from public.dealer_scheme_slabs sl where sl.scheme_id = p_id order by sl.seq loop
        lo := r.from_amt; hi := coalesce(r.to_amt, x);
        if x > lo then e := e + (least(x, hi) - lo) * r.rate_pct / 100; end if;
      end loop;
    end if;
  elsif s.kind = 'target' then
    if x >= s.target_amount then e := bv * coalesce(s.rebate_pct, 0) / 100 + coalesce(s.rebate_flat, 0); end if;
  else
    e := bq * s.per_pack_amount;
  end if;
  return jsonb_build_object('from', d1, 'to', d2, 'base_value', round(bv, 2), 'base_qty', round(bq, 4), 'measure_value', round(x, 4), 'earned', greatest(round(e, 2), 0));
end $$;

-- ---------- scheme set-up (draft only) ----------
-- p_params: {"target_amount","rebate_pct","rebate_flat","per_pack_amount","slab_mode"}; p_slabs: [{"from","to","rate"}]; p_items: item ids (empty = all lines)
create or replace function public.scheme_save(p_id uuid, p_client uuid, p_business bigint, p_supplier uuid, p_name text, p_kind text, p_basis text, p_measure text,
  p_from date, p_to date, p_params jsonb default '{}'::jsonb, p_items uuid[] default '{}', p_slabs jsonb default '[]'::jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.dealer_schemes; sid uuid; sl jsonb; n int := 0; prev_to numeric; f numeric; t numeric; rt numeric; it uuid; pr jsonb := coalesce(p_params, '{}'::jsonb); mode text;
begin
  perform public._scheme_gate128(p_business, true);
  if p_kind is null or p_kind not in ('slab', 'target', 'flat_pack') then raise exception 'bad_kind'; end if;
  if p_basis is null or p_basis not in ('purchase', 'sale') then raise exception 'bad_basis'; end if;
  if p_measure is null or p_measure not in ('value', 'qty') then raise exception 'bad_measure'; end if;
  if p_name is null or length(btrim(p_name)) not between 1 and 120 then raise exception 'name_required'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to > p_from + 1830 then raise exception 'bad_period'; end if;
  if jsonb_typeof(pr) <> 'object' then raise exception 'bad_params'; end if;
  if not exists (select 1 from public.dl_unit_tree127 u where u.id = p_business and u.kind = 'business') then raise exception 'bad_business'; end if;
  if not exists (select 1 from public.suppliers x where x.id = p_supplier and x.active) then raise exception 'supplier_not_found'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'note_too_long'; end if;
  mode := coalesce(pr->>'slab_mode', 'whole');
  if mode not in ('whole', 'marginal') then raise exception 'bad_params'; end if;
  if p_kind = 'flat_pack' and p_measure <> 'qty' then raise exception 'bad_measure'; end if;
  if p_kind = 'slab' and mode = 'marginal' and p_measure <> 'value' then raise exception 'bad_measure'; end if;
  if p_kind = 'target' and (nullif(pr->>'target_amount', '') is null or (nullif(pr->>'rebate_pct', '') is null and nullif(pr->>'rebate_flat', '') is null)) then raise exception 'target_needs_amount_and_rebate'; end if;
  if p_kind = 'flat_pack' and nullif(pr->>'per_pack_amount', '') is null then raise exception 'per_pack_amount_required'; end if;
  if p_kind = 'slab' and (p_slabs is null or jsonb_typeof(p_slabs) <> 'array' or jsonb_array_length(p_slabs) = 0) then raise exception 'slabs_required'; end if;
  if p_id is null then
    if p_client is null then raise exception 'client_required'; end if;
    perform public._client_lock(p_client);
    select * into s from public.dealer_schemes where client_id = p_client;
    if found then
      if s.business_id <> p_business then raise exception 'client_key_used'; end if;
      return jsonb_build_object('id', s.id, 'status', s.status, 'dup', true);
    end if;
    begin
      insert into public.dealer_schemes (client_id, business_id, supplier_id, name, kind, basis, measure, slab_mode, valid_from, valid_to, target_amount, rebate_pct, rebate_flat, per_pack_amount, note, created_by, updated_by)
        values (p_client, p_business, p_supplier, btrim(p_name), p_kind, p_basis, p_measure, mode, p_from, p_to, nullif(pr->>'target_amount', '')::numeric, nullif(pr->>'rebate_pct', '')::numeric,
          round(nullif(pr->>'rebate_flat', '')::numeric, 2), nullif(pr->>'per_pack_amount', '')::numeric, nullif(btrim(coalesce(p_note, '')), ''), auth.uid(), auth.uid()) returning id into sid;
    exception when check_violation or numeric_value_out_of_range then raise exception 'bad_params';
    end;
  else
    select * into s from public.dealer_schemes where id = p_id for update;
    if not found then raise exception 'scheme_not_found'; end if;
    if s.business_id <> p_business then raise exception 'not allowed'; end if;
    if s.status <> 'draft' then raise exception 'scheme_frozen'; end if;
    begin
      update public.dealer_schemes set supplier_id = p_supplier, name = btrim(p_name), kind = p_kind, basis = p_basis, measure = p_measure, slab_mode = mode, valid_from = p_from, valid_to = p_to,
        target_amount = nullif(pr->>'target_amount', '')::numeric, rebate_pct = nullif(pr->>'rebate_pct', '')::numeric, rebate_flat = round(nullif(pr->>'rebate_flat', '')::numeric, 2),
        per_pack_amount = nullif(pr->>'per_pack_amount', '')::numeric, note = nullif(btrim(coalesce(p_note, '')), ''), updated_by = auth.uid(), updated_at = now() where id = p_id;
    exception when check_violation or numeric_value_out_of_range then raise exception 'bad_params';
    end;
    sid := p_id;
    delete from public.dealer_scheme_items where scheme_id = sid;
    delete from public.dealer_scheme_slabs where scheme_id = sid;
  end if;
  -- item scope
  foreach it in array coalesce(p_items, '{}'::uuid[]) loop
    if not exists (select 1 from public.items i where i.id = it) then raise exception 'item_not_found'; end if;
    insert into public.dealer_scheme_items (scheme_id, item_id, business_id) values (sid, it, p_business) on conflict do nothing;
  end loop;
  -- slabs: ascending, no overlap
  if p_kind = 'slab' then
    for sl in select * from jsonb_array_elements(p_slabs) loop
      n := n + 1;
      begin f := (sl->>'from')::numeric; t := nullif(sl->>'to', '')::numeric; rt := (sl->>'rate')::numeric;
      exception when others then raise exception 'bad_slab'; end;
      if f is null or rt is null or f < 0 or rt < 0 or rt > 100 or (t is not null and t <= f) then raise exception 'bad_slab'; end if;
      if n = 1 and f is null then raise exception 'bad_slab'; end if;
      if n > 1 and (prev_to is null or f < prev_to) then raise exception 'slab_overlap'; end if;
      insert into public.dealer_scheme_slabs (scheme_id, seq, from_amt, to_amt, rate_pct, business_id) values (sid, n, f, t, rt, p_business);
      prev_to := t;
    end loop;
  end if;
  return jsonb_build_object('id', sid, 'status', 'draft');
end $$;

create or replace function public.scheme_activate(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.dealer_schemes;
begin
  select * into s from public.dealer_schemes where id = p_id;
  if not found then raise exception 'scheme_not_found'; end if;
  perform public._scheme_gate128(s.business_id, true);
  select * into s from public.dealer_schemes where id = p_id for update;
  if s.status = 'active' then return jsonb_build_object('id', s.id, 'status', 'active', 'dup', true); end if;
  if s.status <> 'draft' then raise exception 'bad_status'; end if;
  if s.basis = 'sale' and not exists (select 1 from public.dealer_scheme_items where scheme_id = s.id) then raise exception 'sale_scheme_needs_items'; end if;
  if s.kind = 'slab' and not exists (select 1 from public.dealer_scheme_slabs where scheme_id = s.id) then raise exception 'slabs_required'; end if;
  update public.dealer_schemes set status = 'active', updated_by = auth.uid(), updated_at = now() where id = s.id;
  return jsonb_build_object('id', s.id, 'status', 'active');
end $$;

-- ---------- accrual (preview or real) ----------
create or replace function public.scheme_accrue(p_id uuid, p_upto date default null, p_dry boolean default true, p_client uuid default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.dealer_schemes; today date := public._dl_today127(); up date; c jsonb; prev numeric; earned numeric; dl numeric; ev public.dealer_scheme_accruals;
begin
  select * into s from public.dealer_schemes where id = p_id;
  if not found then raise exception 'scheme_not_found'; end if;
  perform public._scheme_gate128(s.business_id, not coalesce(p_dry, true));
  up := coalesce(p_upto, today);
  if up > today or up < s.valid_from then raise exception 'bad_date'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'note_too_long'; end if;
  if not coalesce(p_dry, true) then
    if p_client is null then raise exception 'client_required'; end if;
    perform public._client_lock(p_client);
    select * into ev from public.dealer_scheme_accruals where client_id = p_client;
    if found then
      if ev.scheme_id <> p_id then raise exception 'client_key_used'; end if;
      return jsonb_build_object('id', ev.id, 'delta', ev.delta, 'earned_to_date', ev.earned_to_date, 'dup', true);
    end if;
    select * into s from public.dealer_schemes where id = p_id for update;      -- one accrual at a time per scheme
    if s.status <> 'active' then raise exception 'bad_status'; end if;
    perform public.lock_check(up);
  end if;
  c := public._scheme_calc128(p_id, up);
  earned := (c->>'earned')::numeric;
  select coalesce(sum(a.delta), 0) into prev from public.dealer_scheme_accruals a where a.scheme_id = p_id;
  dl := round(earned - prev, 2);
  if coalesce(p_dry, true) then
    return c || jsonb_build_object('dry', true, 'already_accrued', prev, 'delta', dl, 'status', s.status);
  end if;
  if dl = 0 then return c || jsonb_build_object('nothing_new', true, 'already_accrued', prev, 'delta', 0); end if;
  insert into public.dealer_scheme_accruals (scheme_id, business_id, upto_date, base_value, base_qty, earned_to_date, delta, note, client_id, created_by)
    values (p_id, s.business_id, up, (c->>'base_value')::numeric, (c->>'base_qty')::numeric, earned, dl, left(p_note, 300), p_client, auth.uid());
  return c || jsonb_build_object('already_accrued', prev, 'delta', dl, 'accrued_total', prev + dl);
end $$;

-- close a scheme: final accrual up to the end of its period (or today if earlier), then no more accruals
create or replace function public.scheme_close(p_id uuid, p_client uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.dealer_schemes; r jsonb;
begin
  select * into s from public.dealer_schemes where id = p_id;
  if not found then raise exception 'scheme_not_found'; end if;
  perform public._scheme_gate128(s.business_id, true);
  if p_client is null then raise exception 'client_required'; end if;
  if s.status = 'closed' then return jsonb_build_object('id', s.id, 'status', 'closed', 'dup', true); end if;
  if s.status <> 'active' then raise exception 'bad_status'; end if;
  r := public.scheme_accrue(p_id, least(s.valid_to, public._dl_today127()), false, p_client, 'final accrual at close');
  update public.dealer_schemes set status = 'closed', updated_by = auth.uid(), updated_at = now() where id = p_id;
  return jsonb_build_object('id', p_id, 'status', 'closed', 'final', r);
end $$;

create or replace function public.scheme_cancel(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.dealer_schemes;
begin
  select * into s from public.dealer_schemes where id = p_id;
  if not found then raise exception 'scheme_not_found'; end if;
  perform public._scheme_gate128(s.business_id, true);
  select * into s from public.dealer_schemes where id = p_id for update;
  if s.status = 'cancelled' then return jsonb_build_object('id', s.id, 'status', 'cancelled', 'dup', true); end if;
  if s.status not in ('draft', 'active') then raise exception 'bad_status'; end if;
  if p_reason is null or length(btrim(p_reason)) not between 1 and 200 then raise exception 'reason_required'; end if;
  if exists (select 1 from public.dealer_scheme_claims c where c.scheme_id = s.id and c.status in ('submitted', 'part_settled', 'settled')) then raise exception 'has_open_claims'; end if;
  update public.dealer_schemes set status = 'cancelled', note = left(coalesce(s.note || ' / ', '') || 'cancelled: ' || btrim(p_reason), 300), updated_by = auth.uid(), updated_at = now() where id = s.id;
  return jsonb_build_object('id', s.id, 'status', 'cancelled');
end $$;

-- ---------- claims to the principal ----------
create or replace function public.claim_create(p_client uuid, p_scheme uuid, p_claim_no text, p_date date, p_amount numeric, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.dealer_schemes; c public.dealer_scheme_claims; amt numeric; acc numeric; clm numeric; cid uuid;
begin
  select * into s from public.dealer_schemes where id = p_scheme;
  if not found then raise exception 'scheme_not_found'; end if;
  perform public._scheme_gate128(s.business_id, true);
  if p_client is null then raise exception 'client_required'; end if;
  perform public._client_lock(p_client);
  select * into c from public.dealer_scheme_claims where client_id = p_client;
  if found then
    if c.scheme_id <> p_scheme then raise exception 'client_key_used'; end if;
    return jsonb_build_object('id', c.id, 'status', c.status, 'dup', true);
  end if;
  if p_amount is null or p_amount = 'NaN'::numeric or not (abs(p_amount) <= 1000000000000) then raise exception 'bad_amount'; end if;
  amt := round(p_amount, 2);
  if amt <= 0 then raise exception 'bad_amount'; end if;
  if p_date is null or p_date > public._dl_today127() or p_date < s.valid_from then raise exception 'bad_date'; end if;
  if p_claim_no is not null and length(p_claim_no) > 40 then raise exception 'claim_no_too_long'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'note_too_long'; end if;
  select * into s from public.dealer_schemes where id = p_scheme for update;      -- one claim at a time per scheme
  if s.status not in ('active', 'closed') then raise exception 'bad_status'; end if;
  perform public.lock_check(p_date);
  select coalesce(sum(delta), 0) into acc from public.dealer_scheme_accruals where scheme_id = p_scheme;
  select coalesce(sum(amount), 0) into clm from public.dealer_scheme_claims where scheme_id = p_scheme and status in ('submitted', 'part_settled', 'settled');
  if amt > acc - clm then raise exception 'exceeds_accrual'; end if;
  begin
    insert into public.dealer_scheme_claims (client_id, business_id, scheme_id, supplier_id, claim_no, claim_date, amount, note, created_by, updated_by)
      values (p_client, s.business_id, s.id, s.supplier_id, nullif(btrim(coalesce(p_claim_no, '')), ''), p_date, amt, nullif(btrim(coalesce(p_note, '')), ''), auth.uid(), auth.uid()) returning id into cid;
  exception when unique_violation then raise exception 'duplicate_claim_no';
  end;
  insert into public.dealer_scheme_claim_events (claim_id, business_id, kind, amount, on_date, ref, note, client_id, actor)
    values (cid, s.business_id, 'submitted', amt, p_date, p_claim_no, left(p_note, 300), null, auth.uid());
  return jsonb_build_object('id', cid, 'status', 'submitted', 'amount', amt, 'unclaimed_after', acc - clm - amt);
end $$;

create or replace function public.claim_receive(p_claim uuid, p_client uuid, p_amount numeric, p_date date, p_ref text default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.dealer_scheme_claims; amt numeric; got numeric; st text;
begin
  select * into c from public.dealer_scheme_claims where id = p_claim;
  if not found then raise exception 'claim_not_found'; end if;
  perform public._scheme_gate128(c.business_id, true);
  if p_client is null then raise exception 'client_required'; end if;
  perform public._client_lock(p_client);
  if exists (select 1 from public.dealer_scheme_claim_events e where e.client_id = p_client) then
    if not exists (select 1 from public.dealer_scheme_claim_events e where e.client_id = p_client and e.claim_id = p_claim) then raise exception 'client_key_used'; end if;
    select * into c from public.dealer_scheme_claims where id = p_claim;
    return jsonb_build_object('id', c.id, 'status', c.status, 'dup', true);
  end if;
  select * into c from public.dealer_scheme_claims where id = p_claim for update;
  if c.status not in ('submitted', 'part_settled') then raise exception 'bad_status'; end if;
  if p_amount is null or p_amount = 'NaN'::numeric or not (abs(p_amount) <= 1000000000000) then raise exception 'bad_amount'; end if;
  amt := round(p_amount, 2);
  if amt <= 0 then raise exception 'bad_amount'; end if;
  if p_date is null or p_date > public._dl_today127() or p_date < c.claim_date then raise exception 'bad_date'; end if;
  if (p_ref is not null and length(p_ref) > 80) or (p_note is not null and length(p_note) > 300) then raise exception 'text_too_long'; end if;
  perform public.lock_check(p_date);
  select coalesce(sum(amount), 0) into got from public.dealer_scheme_claim_events where claim_id = p_claim and kind = 'received';
  if got + amt > c.amount then raise exception 'overpaid'; end if;
  st := case when got + amt = c.amount then 'settled' else 'part_settled' end;
  insert into public.dealer_scheme_claim_events (claim_id, business_id, kind, amount, on_date, ref, note, client_id, actor)
    values (p_claim, c.business_id, 'received', amt, p_date, left(p_ref, 80), left(p_note, 300), p_client, auth.uid());
  update public.dealer_scheme_claims set status = st, updated_by = auth.uid(), updated_at = now() where id = p_claim;
  return jsonb_build_object('id', p_claim, 'status', st, 'received_total', got + amt, 'outstanding', c.amount - got - amt);
end $$;

create or replace function public.claim_reject(p_claim uuid, p_client uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.dealer_scheme_claims;
begin
  select * into c from public.dealer_scheme_claims where id = p_claim;
  if not found then raise exception 'claim_not_found'; end if;
  perform public._scheme_gate128(c.business_id, true);
  if p_client is null then raise exception 'client_required'; end if;
  perform public._client_lock(p_client);
  if exists (select 1 from public.dealer_scheme_claim_events e where e.client_id = p_client) then
    if not exists (select 1 from public.dealer_scheme_claim_events e where e.client_id = p_client and e.claim_id = p_claim) then raise exception 'client_key_used'; end if;
    select * into c from public.dealer_scheme_claims where id = p_claim;
    return jsonb_build_object('id', c.id, 'status', c.status, 'dup', true);
  end if;
  select * into c from public.dealer_scheme_claims where id = p_claim for update;
  if c.status <> 'submitted' then raise exception 'bad_status'; end if;             -- nothing received yet
  if p_reason is null or length(btrim(p_reason)) not between 1 and 200 then raise exception 'reason_required'; end if;
  update public.dealer_scheme_claims set status = 'rejected', updated_by = auth.uid(), updated_at = now() where id = p_claim;
  insert into public.dealer_scheme_claim_events (claim_id, business_id, kind, amount, on_date, note, client_id, actor)
    values (p_claim, c.business_id, 'rejected', c.amount, public._dl_today127(), btrim(p_reason), p_client, auth.uid());
  return jsonb_build_object('id', p_claim, 'status', 'rejected');
end $$;

create or replace function public.claim_cancel(p_claim uuid, p_client uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.dealer_scheme_claims;
begin
  select * into c from public.dealer_scheme_claims where id = p_claim;
  if not found then raise exception 'claim_not_found'; end if;
  perform public._scheme_gate128(c.business_id, true);
  if p_client is null then raise exception 'client_required'; end if;
  perform public._client_lock(p_client);
  if exists (select 1 from public.dealer_scheme_claim_events e where e.client_id = p_client) then
    if not exists (select 1 from public.dealer_scheme_claim_events e where e.client_id = p_client and e.claim_id = p_claim) then raise exception 'client_key_used'; end if;
    select * into c from public.dealer_scheme_claims where id = p_claim;
    return jsonb_build_object('id', c.id, 'status', c.status, 'dup', true);
  end if;
  select * into c from public.dealer_scheme_claims where id = p_claim for update;
  if c.status <> 'submitted' then raise exception 'bad_status'; end if;
  if p_reason is null or length(btrim(p_reason)) not between 1 and 200 then raise exception 'reason_required'; end if;
  update public.dealer_scheme_claims set status = 'cancelled', updated_by = auth.uid(), updated_at = now() where id = p_claim;
  insert into public.dealer_scheme_claim_events (claim_id, business_id, kind, amount, on_date, note, client_id, actor)
    values (p_claim, c.business_id, 'cancelled', c.amount, public._dl_today127(), btrim(p_reason), p_client, auth.uid());
  return jsonb_build_object('id', p_claim, 'status', 'cancelled');
end $$;

-- ---------- reads ----------
create or replace function public.scheme_list(p_business bigint, p_status text default null)
returns table (id uuid, supplier_id uuid, supplier_name text, name text, kind text, basis text, measure text, valid_from date, valid_to date, status text, accrued numeric, claimed numeric, received numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._scheme_gate128(p_business, false);
  return query
    select s.id, s.supplier_id, (select x.name from public.suppliers x where x.id = s.supplier_id), s.name, s.kind, s.basis, s.measure, s.valid_from, s.valid_to, s.status,
      (select coalesce(sum(a.delta), 0) from public.dealer_scheme_accruals a where a.scheme_id = s.id),
      (select coalesce(sum(c.amount), 0) from public.dealer_scheme_claims c where c.scheme_id = s.id and c.status in ('submitted', 'part_settled', 'settled')),
      (select coalesce(sum(e.amount), 0) from public.dealer_scheme_claim_events e join public.dealer_scheme_claims c on c.id = e.claim_id where c.scheme_id = s.id and e.kind = 'received')
    from public.dealer_schemes s where s.business_id = p_business and (p_status is null or s.status = p_status) order by s.valid_from desc, s.name;
end $$;

create or replace function public.scheme_get(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.dealer_schemes;
begin
  select * into s from public.dealer_schemes where id = p_id;
  if not found then raise exception 'scheme_not_found'; end if;
  perform public._scheme_gate128(s.business_id, false);
  return to_jsonb(s) - 'client_id' || jsonb_build_object(
    'items', coalesce((select jsonb_agg(i.item_id order by i.item_id) from public.dealer_scheme_items i where i.scheme_id = p_id), '[]'::jsonb),
    'slabs', coalesce((select jsonb_agg(jsonb_build_object('seq', l.seq, 'from', l.from_amt, 'to', l.to_amt, 'rate', l.rate_pct) order by l.seq) from public.dealer_scheme_slabs l where l.scheme_id = p_id), '[]'::jsonb));
end $$;

create or replace function public.claim_list(p_business bigint, p_supplier uuid default null, p_status text default null)
returns table (id uuid, scheme_id uuid, scheme_name text, supplier_id uuid, supplier_name text, claim_no text, claim_date date, amount numeric, status text, received numeric, outstanding numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._scheme_gate128(p_business, false);
  return query
    select c.id, c.scheme_id, s.name, c.supplier_id, (select x.name from public.suppliers x where x.id = c.supplier_id), c.claim_no, c.claim_date, c.amount, c.status,
      r.got, case when c.status in ('submitted', 'part_settled') then c.amount - r.got else 0::numeric end
    from public.dealer_scheme_claims c join public.dealer_schemes s on s.id = c.scheme_id
      cross join lateral (select coalesce(sum(e.amount), 0) got from public.dealer_scheme_claim_events e where e.claim_id = c.id and e.kind = 'received') r
    where c.business_id = p_business and (p_supplier is null or c.supplier_id = p_supplier) and (p_status is null or c.status = p_status)
    order by c.claim_date desc, c.created_at desc;
end $$;

-- accrual vs claim vs receipt, per scheme (and per principal): what is earned, what was claimed, what came in, what is still unclaimed / outstanding
create or replace function public.scheme_reconciliation(p_business bigint, p_supplier uuid default null)
returns table (scheme_id uuid, supplier_id uuid, supplier_name text, scheme_name text, status text, accrued numeric, claimed numeric, received numeric, rejected numeric,
  unclaimed numeric, outstanding numeric, over_claimed numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._scheme_gate128(p_business, false);
  return query
    select z.id, z.supplier_id, z.sname, z.name, z.status, z.acc, z.clm, z.rec, z.rej, greatest(z.acc - z.clm, 0), z.clm - z.rec, greatest(z.clm - z.acc, 0)
    from (
      select s.id, s.supplier_id, (select x.name from public.suppliers x where x.id = s.supplier_id) sname, s.name, s.status,
        (select coalesce(sum(a.delta), 0) from public.dealer_scheme_accruals a where a.scheme_id = s.id) acc,
        (select coalesce(sum(c.amount), 0) from public.dealer_scheme_claims c where c.scheme_id = s.id and c.status in ('submitted', 'part_settled', 'settled')) clm,
        (select coalesce(sum(e.amount), 0) from public.dealer_scheme_claim_events e join public.dealer_scheme_claims c on c.id = e.claim_id where c.scheme_id = s.id and e.kind = 'received') rec,
        (select coalesce(sum(c.amount), 0) from public.dealer_scheme_claims c where c.scheme_id = s.id and c.status = 'rejected') rej
      from public.dealer_schemes s where s.business_id = p_business and s.status <> 'cancelled' and (p_supplier is null or s.supplier_id = p_supplier)) z
    order by z.sname, z.name;
end $$;

-- ---------- function grants ----------
revoke all on function public._scheme_gate128(bigint, boolean), public._scheme_calc128(uuid, date), public._scheme_frozen128() from public, anon, authenticated;
revoke all on function public.scheme_save(uuid, uuid, bigint, uuid, text, text, text, text, date, date, jsonb, uuid[], jsonb, text), public.scheme_activate(uuid),
  public.scheme_accrue(uuid, date, boolean, uuid, text), public.scheme_close(uuid, uuid), public.scheme_cancel(uuid, text),
  public.claim_create(uuid, uuid, text, date, numeric, text), public.claim_receive(uuid, uuid, numeric, date, text, text), public.claim_reject(uuid, uuid, text), public.claim_cancel(uuid, uuid, text),
  public.scheme_list(bigint, text), public.scheme_get(uuid), public.claim_list(bigint, uuid, text), public.scheme_reconciliation(bigint, uuid) from public, anon;
grant execute on function public.scheme_save(uuid, uuid, bigint, uuid, text, text, text, text, date, date, jsonb, uuid[], jsonb, text), public.scheme_activate(uuid),
  public.scheme_accrue(uuid, date, boolean, uuid, text), public.scheme_close(uuid, uuid), public.scheme_cancel(uuid, text),
  public.claim_create(uuid, uuid, text, date, numeric, text), public.claim_receive(uuid, uuid, numeric, date, text, text), public.claim_reject(uuid, uuid, text), public.claim_cancel(uuid, uuid, text),
  public.scheme_list(bigint, text), public.scheme_get(uuid), public.claim_list(bigint, uuid, text), public.scheme_reconciliation(bigint, uuid) to authenticated;

commit;
