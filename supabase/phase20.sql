-- ============================================================
-- Phase 20: FORMS <-> STOCK LEDGER LINKS, discount approver on sales, brand-level P&L.
--   Additive and safe to run twice; paste the whole file into the Supabase SQL editor.  Needs phase8..phase17 (phase18 / 19 are not required).
--   (1) rule forms_post_to_ledger (default OFF) + per-form switches forms_ledger_cfg(form_code, is_on).
--       When an entry of 04-1 GRN / 04-2 issue / 04-3 count / 03-1 transfer / 05-1 factory sheet is APPROVED, an AFTER UPDATE trigger on entries
--       calls entry_post_ledger(entry), which posts into the existing stock ledger through stock_post.  decide_entry is NOT edited.
--       - one log row per form line in entry_ledger_posts (entry, generation, line): the same approval twice posts nothing twice;
--       - reopen + re-approve (or an approved change request) with different content: reverse the earlier generation (reversal rows) and post the new one;
--       - lines whose item is not tracked / not counted in the business, held / returned GRN lines, lines without a quantity: skipped, yellow exception ledger_skip;
--       - any failure (unknown item, not enough stock, unknown unit ...): yellow exception ledger_post_failed with the reason, approval is never blocked;
--         entry_post_ledger_retry(entry) posts the failed lines again (and also posts an entry approved while the switch was off).
--   (2) the 04-4 store ledger and 06-5 supplier ledger need no new data: they become read views over stock_ledger_rows / supplier_ledger (web).
--   (3) sales.discount_approved_by / _staff / discount_approval: filled by a BEFORE INSERT trigger from the approval that record_sale2 used
--       (a granted role = the seller, an emergency approval = the person who approved the request).  record_sale2 is NOT edited.  RPC discounts_report.
--   (4) brand_pnl(from, to): the existing gross-profit figures (biz_daily) grouped by brand through report_brand_map. Costs only for cost-grant holders.
-- ============================================================

-- ---------- (1) switches ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('forms_post_to_ledger', 'stock', 'switch', 'false', null, null, null, null,
  'ফর্ম অনুমোদন হলে স্টক লেজারে নিজে থেকে পোস্ট', 'Form approve হলে stock ledger এ নিজে পোস্ট', 'Approved forms post to the stock ledger',
  'চালু করলে GRN, ইস্যু স্লিপ, কাউন্ট শিট, ট্রান্সফার চালান ও কারখানা শিট অনুমোদনের সময় স্টক লেজারে লাইন যোগ করে। বন্ধ থাকলে কিছুই বদলায় না।',
  null,
  'When on, an approved GRN, issue slip, count sheet, transfer challan or factory sheet adds its lines to the stock ledger. Off = nothing changes (default). Each form also has its own switch.', 71)
on conflict (key) do nothing;

create table if not exists public.forms_ledger_cfg (
  form_code text primary key references public.forms(code),
  is_on boolean not null default true,                     -- the master rule forms_post_to_ledger must be on as well
  changed_by uuid, changed_at timestamptz not null default now()
);
alter table public.forms_ledger_cfg enable row level security;
revoke all on public.forms_ledger_cfg from public, anon, authenticated;
grant select on public.forms_ledger_cfg to authenticated;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'forms_ledger_cfg' and policyname = 'forms_ledger_cfg_read') then
    create policy forms_ledger_cfg_read on public.forms_ledger_cfg for select to authenticated using (public.is_active());
  end if;
end $$;
insert into public.forms_ledger_cfg (form_code) select code from public.forms where code in ('04-1', '04-2', '04-3', '03-1', '05-1') on conflict do nothing;

create table if not exists public.entry_ledger_posts (
  id bigserial primary key,
  entry_id uuid not null references public.entries(id),
  gen int not null check (gen >= 1),                        -- a new generation when the approved content changed (the old one is reversed)
  line_no int not null,                                     -- 1-based line of the form table; 0 = the form as a whole
  form_code text not null,
  location_id int not null references public.locations(id), -- the entry's place
  to_location_id int references public.locations(id),
  kind text not null check (kind in ('in', 'out', 'count', 'transfer', 'prod', 'none')),
  item_id uuid references public.items(id),
  item_code text,
  qty_base numeric,                                         -- base unit; for a count the counted quantity
  sig text not null,                                        -- fingerprint of all lines of this generation
  status text not null check (status in ('posted', 'skipped', 'failed', 'reversed', 'void')),
  reason text,                                              -- why skipped / failed / the short note of a post
  ref text,                                                 -- entry:gen:line, written to stock_ledger.ref_id (ref_type 'entry')
  transfer_id uuid,
  posted_by uuid, posted_at timestamptz not null default now(), reversed_at timestamptz,
  unique (entry_id, gen, line_no)
);
create index if not exists entry_ledger_posts_entry on public.entry_ledger_posts (entry_id, gen);
create index if not exists entry_ledger_posts_bad on public.entry_ledger_posts (status) where status in ('failed', 'skipped');
alter table public.entry_ledger_posts enable row level security;
revoke all on public.entry_ledger_posts from public, anon, authenticated;
grant select on public.entry_ledger_posts to authenticated;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'entry_ledger_posts' and policyname = 'entry_ledger_posts_read') then
    create policy entry_ledger_posts_read on public.entry_ledger_posts for select to authenticated using (public.is_active() and (public.is_owner() or public.can_loc(location_id)));
  end if;
end $$;

-- ---------- small helpers ----------
create or replace function public._elp_num(p text) returns numeric
language sql immutable as $$ select case when btrim(p) ~ '^-?[0-9]+(\.[0-9]+)?$' then btrim(p)::numeric end $$;
create or replace function public._elp_flag(p text) returns boolean
language sql immutable as $$ select coalesce(lower(btrim(p)) in ('true', 't', '1', 'yes', 'on'), false) $$;
create or replace function public._elp_loc(p text) returns int
language sql stable security definer set search_path = public as $$
  select l.id from public.locations l where btrim(p) ~ '^[0-9]{1,9}$' and l.id = btrim(p)::int;
$$;
create or replace function public._elp_enabled(p_form text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_form in ('04-1', '04-2', '04-3', '03-1', '05-1') and public.rule_on('forms_post_to_ledger')
         and coalesce((select c.is_on from public.forms_ledger_cfg c where c.form_code = p_form), true);
$$;

-- ---------- the form -> ledger lines map (what each form means for the ledger; nothing is guessed) ----------
-- one jsonb object per non-empty row: {n, kind, item, qty, cost, from, to, recv, skip, note}.  qty / cost are in the item's own unit as written on the form.
create or replace function public._elp_lines(e public.entries) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out jsonb := '[]'::jsonb; r jsonb; n int; tab text; arr jsonb; q text; cr jsonb; kept boolean; note text; nrate numeric;
begin
  note := left(e.form_code || '-' || e.serial::text || coalesce(' ' || nullif(btrim(e.data->>'supplier'), ''), ''), 120);
  if e.form_code = '04-1' then
    nrate := public._elp_num(e.data->>'new_rate');
    for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) with ordinality x(v, o) loop
      continue when coalesce(nullif(btrim(r->>'item'), ''), nullif(btrim(r->>'counted'), '')) is null;
      q := coalesce(r->>'quality', 'accept');
      out := out || jsonb_build_object('n', n, 'kind', 'in', 'item', nullif(btrim(r->>'item'), ''), 'qty', public._elp_num(r->>'counted'),
        'cost', case when q = 'reduced' and nrate is not null then nrate else public._elp_num(r->>'rate') end,
        'skip', case when q = 'hold' then 'quality_hold' when q = 'return' then 'quality_return' end, 'note', note);
    end loop;
  elsif e.form_code = '04-2' then
    kept := not public._elp_flag(e.data->>'not_overnight');       -- the form's own rule: kept overnight = the whole quantity counts as used
    for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) with ordinality x(v, o) loop
      continue when coalesce(nullif(btrim(r->>'item'), ''), nullif(btrim(r->>'issued'), '')) is null;
      out := out || jsonb_build_object('n', n, 'kind', 'out', 'item', nullif(btrim(r->>'item'), ''),
        'qty', public._elp_num(r->>'issued') - case when kept then 0 else coalesce(public._elp_num(r->>'ret'), 0) end, 'note', note || ' ' || coalesce(e.data->>'purpose', ''));
    end loop;
  elsif e.form_code = '04-3' then
    for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data->'rows') = 'array' then e.data->'rows' else '[]'::jsonb end) with ordinality x(v, o) loop
      continue when coalesce(nullif(btrim(r->>'item'), ''), nullif(btrim(r->>'count'), '')) is null;
      out := out || jsonb_build_object('n', n, 'kind', 'count', 'item', nullif(btrim(r->>'item'), ''), 'qty', public._elp_num(r->>'count'), 'book', public._elp_num(r->>'book'),
        'skip', case when public._elp_num(r->>'book') is null then 'no_count_basis' end,
        'note', left(note || ' ' || coalesce(nullif(btrim(r->>'reason'), ''), 'stock count'), 190));
    end loop;
  elsif e.form_code = '03-1' then
    cr := case when jsonb_typeof(e.check_data->'items') = 'array' then e.check_data->'items' else '[]'::jsonb end;
    for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data->'items') = 'array' then e.data->'items' else '[]'::jsonb end) with ordinality x(v, o) loop
      continue when coalesce(nullif(btrim(r->>'item'), ''), nullif(btrim(r->>'sent'), '')) is null;
      out := out || jsonb_build_object('n', n, 'kind', 'transfer', 'item', nullif(btrim(r->>'item'), ''), 'qty', public._elp_num(r->>'sent'),
        'from', public._elp_loc(e.data->>'from_loc'), 'to', public._elp_loc(e.data->>'to_loc'),
        'recv', public._elp_num(cr->(n - 1)->>'received'), 'note', note);
    end loop;
  elsif e.form_code = '05-1' then
    for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data->'output') = 'array' then e.data->'output' else '[]'::jsonb end) with ordinality x(v, o) loop
      continue when coalesce(nullif(btrim(r->>'item'), ''), nullif(btrim(r->>'qty'), '')) is null;
      out := out || jsonb_build_object('n', n, 'kind', 'prod', 'item', nullif(btrim(r->>'item'), ''), 'qty', public._elp_num(r->>'qty'), 'note', note);
    end loop;
  end if;
  if jsonb_array_length(out) = 0 then
    out := jsonb_build_array(jsonb_build_object('n', 0, 'kind', 'none', 'skip', 'no_item_lines', 'note', note));
  end if;
  return out;
end $$;

-- ---------- post ONE line (runs inside a sub-transaction of entry_post_ledger: an error here undoes only this line) ----------
create or replace function public._elp_post_line(e public.entries, g int, sg text, l jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare it public.items; n int := (l->>'n')::int; kind text := l->>'kind'; qty numeric := nullif(l->>'qty', '')::numeric; bq numeric; f numeric; ucb numeric;
        ref text := e.id::text || ':g' || g::text || ':' || n::text; lid bigint; olid bigint; bal public.stock_balance; d numeric; tid uuid; fl int := nullif(l->>'from', '')::int;
        tl int := nullif(l->>'to', '')::int; rq numeric; rbq numeric; note text := nullif(l->>'note', ''); at_ timestamptz := now(); sl jsonb; exp timestamptz; bid bigint; sid text;
        stt text := 'posted'; why text; ucost numeric;
begin
  if l->>'skip' is null and kind = 'transfer' then
    if (fl is not null and fl <> e.location_id) or (fl is null and tl is not null and tl <> e.location_id) then why := 'location_mismatch'; stt := 'skipped';
    elsif not (public.is_owner() or ((fl is null or public.can_loc(fl)) and (tl is null or public.can_loc(tl)))) then why := 'location_mismatch'; stt := 'skipped';
    end if;
  end if;
  if l->>'skip' is not null then why := l->>'skip'; stt := 'skipped';
  elsif stt = 'skipped' then null;
  else
    if l->>'item' is null then raise exception 'item_missing'; end if;
    select * into it from public.items where code = l->>'item';
    if not found then raise exception 'item_not_found: %', l->>'item'; end if;
    if not it.is_active then raise exception 'item_not_active: %', it.code; end if;
    if not it.tracked then why := 'not_tracked'; stt := 'skipped';
    elsif not it.count_in_business then why := 'not_counted'; stt := 'skipped';
    end if;
  end if;
  if stt = 'skipped' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, tl, kind, (select i.id from public.items i where i.code = l->>'item'), left(l->>'item', 60), null, sg, 'skipped', why, ref, auth.uid());
    return;
  end if;
  if qty is null then raise exception 'qty_missing'; end if;
  if kind <> 'count' and not (qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if kind = 'count' and not (qty between 0 and 999999999) then raise exception 'bad_qty'; end if;
  bq := public._base_qty(it.id, qty, it.unit);
  if bq is null then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
  if not (bq between case when kind = 'count' then 0 else 0.0001 end and 999999999) then raise exception 'bad_qty'; end if;
  f := public._unit_factor_base(it.id, it.unit);
  if f is null or not (f > 0) then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
  ucost := nullif(l->>'cost', '')::numeric;
  if ucost is not null and not (ucost between 0 and 1000000000000) then ucost := null; end if;
  ucb := case when ucost is null then null else ucost / f end;

  if kind = 'in' then
    lid := public.stock_post(it.id, e.location_id, bq, 'purchase_in', 'entry', ref, ucb, null, at_, note, null, 'none');
  elsif kind = 'out' then
    lid := public.stock_post(it.id, e.location_id, -bq, 'issue_out', 'entry', ref, null, null, at_, note, null, 'full');
  elsif kind = 'count' then
    -- the count is against the system balance written on the sheet at COUNT time (a snapshot of the live balance is not possible later): delta = counted - that figure, applied to the CURRENT balance
    insert into public.stock_balance (item_id, location_id) values (it.id, e.location_id) on conflict do nothing;
    select * into bal from public.stock_balance where item_id = it.id and location_id = e.location_id for update;
    rbq := public._base_qty(it.id, nullif(l->>'book', '')::numeric, it.unit);
    if rbq is null then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
    d := round(bq - rbq, 4);
    if d <> 0 then lid := public.stock_post(it.id, e.location_id, d, 'count_adjust', 'entry', ref, null, null, at_, left(coalesce(note, 'stock count'), 200), null, 'none'); end if;
    why := case when d = 0 then 'no_change' else 'delta ' || d::text end;
  elsif kind = 'prod' then
    sl := public.shelf_life_for(it.id, (at_ at time zone 'Asia/Dhaka')::date);
    exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
    insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
      values (it.id, e.location_id, at_, bq, bq, exp, sl, left(note, 200), auth.uid()) returning id into bid;
    lid := public.stock_post(it.id, e.location_id, bq, 'production_in', 'entry', ref, null, bid, at_, left(note, 200), null, 'none');
  elsif kind = 'transfer' then
    if fl is not null and tl is not null then
      if fl = tl then raise exception 'same_location'; end if;
      rq := nullif(l->>'recv', '')::numeric;
      if rq is not null then
        if not (rq between 0 and 999999999) then raise exception 'bad_qty'; end if;
        rbq := public._base_qty(it.id, rq, it.unit);
        if rbq is null then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
        if rbq > bq then raise exception 'over_received'; end if;
      end if;
      tid := gen_random_uuid(); select staff_id into sid from public.profiles where id = auth.uid();
      insert into public.stock_transfers (id, from_location_id, to_location_id, item_id, qty, status, received_qty, note, sent_by, sent_staff, sent_at,
          received_by, received_staff, received_at)
        values (tid, fl, tl, it.id, bq, case when rq is null then 'sent' else 'received' end, rbq, left(note, 200), auth.uid(), sid, at_,
          case when rq is null then null else auth.uid() end, case when rq is null then null else sid end, case when rq is null then null else at_ end);
      olid := public.stock_post(it.id, fl, -bq, 'transfer_out', 'transfer', tid::text, null, null, at_, left(note, 200), null, 'full');
      if rq is not null and rbq > 0 then
        select unit_cost into ucost from public.stock_ledger where id = olid;
        perform public.stock_post(it.id, tl, rbq, 'transfer_in', 'transfer', tid::text, ucost, null, at_, left(note, 200), null, 'none');
      end if;
      why := case when rq is null then 'in_transit' when rbq < bq then 'short ' || (bq - rbq)::text else null end;
      insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, transfer_id, posted_by)
        values (e.id, g, n, e.form_code, e.location_id, tl, kind, it.id, it.code, bq, sg, 'posted', why, ref, tid, auth.uid());
      return;
    elsif fl is not null then          -- goods leave for a place outside the tracked places (customer, party ...): the sender's out leg only
      lid := public.stock_post(it.id, fl, -bq, 'transfer_out', 'entry', ref, null, null, at_, left(note, 200), null, 'full');
    elsif tl is not null then          -- goods come in from outside (party return ...): the receiver's in leg only
      lid := public.stock_post(it.id, tl, coalesce(public._base_qty(it.id, nullif(l->>'recv', '')::numeric, it.unit), bq), 'transfer_in', 'entry', ref, null, null, at_, left(note, 200), null, 'none');
    else raise exception 'location_missing';
    end if;
  end if;
  insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
    values (e.id, g, n, e.form_code, coalesce(fl, e.location_id), tl, kind, it.id, it.code, bq, sg, 'posted', why, ref, auth.uid());
end $$;

-- ---------- undo one generation (reversal rows; nothing is deleted) ----------
create or replace function public._elp_reverse(e public.entries, g int) returns void
language plpgsql security definer set search_path = public as $$
declare p public.entry_ledger_posts; o public.stock_ledger;
begin
  for p in select * from public.entry_ledger_posts where entry_id = e.id and gen = g and status = 'posted' order by line_no desc loop
    for o in select x.* from public.stock_ledger x where x.reason <> 'reversal'
             and ((p.transfer_id is not null and x.ref_type = 'transfer' and x.ref_id = p.transfer_id::text) or (p.transfer_id is null and x.ref_type = 'entry' and x.ref_id = p.ref))
             and not exists (select 1 from public.stock_ledger y where y.reverses_id = x.id) order by x.id desc loop
      perform public.stock_post(o.item_id, o.location_id, -o.qty_delta, 'reversal', o.ref_type, o.ref_id, o.unit_cost, o.batch_id, now(), 'entry revised: earlier posting undone', o.id, 'none');
    end loop;
    if p.transfer_id is not null then update public.stock_transfers set status = 'cancelled', cancelled_by = auth.uid(), cancelled_at = now() where id = p.transfer_id; end if;
    update public.entry_ledger_posts set status = 'reversed', reversed_at = now() where id = p.id;
  end loop;
  update public.entry_ledger_posts set status = 'void' where entry_id = e.id and gen = g and status in ('failed', 'skipped');
end $$;

create or replace function public._elp_exceptions(e public.entries, g int) returns void
language plpgsql security definer set search_path = public as $$
declare sk text; fl text; nsk int; nfl int;
begin
  delete from public.exceptions where entry_id = e.id and status = 'open' and flag_code in ('ledger_skip', 'ledger_post_failed');
  select count(*), string_agg('#' || line_no::text || ' ' || coalesce(item_code, '-') || ' ' || coalesce(reason, ''), '; ' order by line_no) into nsk, sk
    from public.entry_ledger_posts where entry_id = e.id and gen = g and status = 'skipped';
  select count(*), string_agg('#' || line_no::text || ' ' || coalesce(item_code, '-') || ': ' || coalesce(reason, ''), '; ' order by line_no) into nfl, fl
    from public.entry_ledger_posts where entry_id = e.id and gen = g and status = 'failed';
  if nsk > 0 then
    insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (e.id, e.form_code, e.location_id, e.entry_date, 'ledger_skip', 'yellow', nsk,
        jsonb_build_object('bn', e.form_code || '-' || e.serial || ': ' || nsk || ' লাইন স্টক লেজারে যায়নি — ' || left(sk, 300),
                           'en', e.form_code || '-' || e.serial || ': ' || nsk || ' line(s) were not posted to the stock ledger — ' || left(sk, 300)));
  end if;
  if nfl > 0 then
    insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (e.id, e.form_code, e.location_id, e.entry_date, 'ledger_post_failed', 'yellow', nfl,
        jsonb_build_object('bn', e.form_code || '-' || e.serial || ': ' || nfl || ' লাইন স্টক লেজারে পোস্ট হয়নি (আবার চেষ্টা করা যাবে) — ' || left(fl, 300),
                           'en', e.form_code || '-' || e.serial || ': ' || nfl || ' line(s) could not be posted to the stock ledger (retry is possible) — ' || left(fl, 300)));
  end if;
end $$;

-- ---------- the poster: idempotent. Same content = nothing new; changed content = reverse the old generation and post the new one ----------
create or replace function public.entry_post_ledger(p_entry uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; lines jsonb; sg text; g int; cur text; l jsonb; n int; nposted int := 0; nfail int := 0; nskip int := 0; msg text; sid text;
begin
  select * into e from public.entries where id = p_entry for update;
  if not found or e.status <> 'approved' then return jsonb_build_object('ok', false, 'why', 'not_approved'); end if;
  if not public._elp_enabled(e.form_code) then return jsonb_build_object('ok', true, 'enabled', false); end if;
  lines := public._elp_lines(e); sg := md5(lines::text);
  select max(gen) into g from public.entry_ledger_posts where entry_id = e.id;
  if g is null then g := 1;
  else
    select sig into cur from public.entry_ledger_posts where entry_id = e.id and gen = g limit 1;
    if cur is distinct from sg then
      begin
        perform public._elp_reverse(e, g);
        g := g + 1;
      exception when others then
        msg := sqlerrm;
        delete from public.exceptions where entry_id = e.id and status = 'open' and flag_code = 'ledger_post_failed';
        insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
          values (e.id, e.form_code, e.location_id, e.entry_date, 'ledger_post_failed', 'yellow', null,
            jsonb_build_object('bn', e.form_code || '-' || e.serial || ': সংশোধিত ফর্মের আগের লেজার পোস্টিং ফেরানো যায়নি — ' || left(msg, 200),
                               'en', e.form_code || '-' || e.serial || ': the earlier ledger posting of the revised form could not be undone — ' || left(msg, 200)));
        return jsonb_build_object('ok', false, 'why', 'reverse_failed', 'error', msg);
      end;
    end if;
  end if;
  for l in select * from jsonb_array_elements(lines) loop
    n := (l->>'n')::int;
    if exists (select 1 from public.entry_ledger_posts where entry_id = e.id and gen = g and line_no = n and status in ('posted', 'skipped')) then continue; end if;
    delete from public.entry_ledger_posts where entry_id = e.id and gen = g and line_no = n and status = 'failed';
    begin
      perform public._elp_post_line(e, g, sg, l);
    exception when others then
      insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_code, qty_base, sig, status, reason, posted_by)
        values (e.id, g, n, e.form_code, e.location_id, nullif(l->>'to', '')::int, coalesce(l->>'kind', 'none'), left(l->>'item', 60), null, sg, 'failed', left(sqlerrm, 200), auth.uid());
    end;
  end loop;
  select count(*) filter (where status = 'posted'), count(*) filter (where status = 'failed'), count(*) filter (where status = 'skipped') into nposted, nfail, nskip
    from public.entry_ledger_posts where entry_id = e.id and gen = g;
  perform public._elp_exceptions(e, g);
  return jsonb_build_object('ok', true, 'enabled', true, 'gen', g, 'posted', nposted, 'failed', nfail, 'skipped', nskip);
end $$;
revoke all on function public.entry_post_ledger(uuid), public._elp_post_line(public.entries, int, text, jsonb), public._elp_reverse(public.entries, int),
  public._elp_exceptions(public.entries, int), public._elp_lines(public.entries) from public, anon, authenticated;

-- the trigger: never blocks the approval (a failure of the whole poster becomes one exception)
create or replace function public._entries_post_ledger() returns trigger
language plpgsql security definer set search_path = public as $$
declare msg text;
begin
  if not public._elp_enabled(new.form_code) then return null; end if;
  begin
    perform public.entry_post_ledger(new.id);
  exception when others then
    msg := sqlerrm;
    begin
      insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (new.id, new.form_code, new.location_id, new.entry_date, 'ledger_post_failed', 'yellow', null,
          jsonb_build_object('bn', new.form_code || '-' || new.serial || ': স্টক লেজারে পোস্ট হয়নি — ' || left(msg, 200),
                             'en', new.form_code || '-' || new.serial || ': could not post to the stock ledger — ' || left(msg, 200)));
    exception when others then null;
    end;
  end;
  return null;
end $$;
revoke all on function public._entries_post_ledger() from public, anon, authenticated;
drop trigger if exists entries_post_ledger on public.entries;
create trigger entries_post_ledger after update on public.entries for each row
  when (new.status = 'approved' and (old.status is distinct from 'approved' or old.data is distinct from new.data or old.check_data is distinct from new.check_data))
  execute function public._entries_post_ledger();

-- ---------- public RPCs ----------
create or replace function public._elp_may(p_entry uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and exists (select 1 from public.entries e where e.id = p_entry
    and (public.is_owner() or (public.can_loc(e.location_id) and public.can_do(e.form_code, 'approve'))));
$$;
revoke all on function public._elp_may(uuid) from public, anon, authenticated;

create or replace function public.entry_post_ledger_retry(p_entry uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._elp_may(p_entry) then raise exception 'not allowed'; end if;
  return public.entry_post_ledger(p_entry);
end $$;

-- lines of one entry (what went to the ledger); no costs
create or replace function public.entry_ledger_lines(p_entry uuid)
returns table (gen int, line_no int, kind text, item_code text, qty_base numeric, status text, reason text, posted_at timestamptz, reversed_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_active() and exists (select 1 from public.entries e where e.id = p_entry and (public.is_owner() or public.can_loc(e.location_id)))) then raise exception 'not allowed'; end if;
  return query select x.gen, x.line_no, x.kind, x.item_code, x.qty_base, x.status, x.reason, x.posted_at, x.reversed_at from public.entry_ledger_posts x where x.entry_id = p_entry order by x.gen, x.line_no;
end $$;

-- approved entries whose latest generation has failed lines (the retry list)
create or replace function public.ledger_post_problems(p_loc int default null)
returns table (entry_id uuid, form_code text, serial int, location_id int, entry_date date, failed int, skipped int, first_reason text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    with cur as (select x.entry_id, max(x.gen) g from public.entry_ledger_posts x group by 1)
    select e.id, e.form_code, e.serial, e.location_id, e.entry_date,
           (count(*) filter (where x.status = 'failed'))::int, (count(*) filter (where x.status = 'skipped'))::int,
           min(x.reason) filter (where x.status = 'failed')
    from cur join public.entry_ledger_posts x on x.entry_id = cur.entry_id and x.gen = cur.g
    join public.entries e on e.id = x.entry_id
    where (p_loc is null or e.location_id = p_loc) and (public.is_owner() or (public.can_loc(e.location_id) and public.can_do(e.form_code, 'approve')))
    group by e.id, e.form_code, e.serial, e.location_id, e.entry_date
    having count(*) filter (where x.status in ('failed', 'skipped')) > 0
    order by e.entry_date desc, e.serial desc limit 200;
end $$;

-- owner: per-form switch
create or replace function public.forms_ledger_cfg_set(p_form text, p_on boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_form not in ('04-1', '04-2', '04-3', '03-1', '05-1') or p_on is null then raise exception 'bad_form'; end if;
  insert into public.forms_ledger_cfg (form_code, is_on, changed_by, changed_at) values (p_form, p_on, auth.uid(), now())
    on conflict (form_code) do update set is_on = excluded.is_on, changed_by = auth.uid(), changed_at = now();
  return jsonb_build_object('form_code', p_form, 'is_on', p_on);
end $$;

-- ---------- (3) discount approver on sales ----------
alter table public.sales add column if not exists discount_approved_by uuid;
alter table public.sales add column if not exists discount_approved_staff text;
alter table public.sales add column if not exists discount_approval text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'sales_discount_approval_chk') then
    alter table public.sales add constraint sales_discount_approval_chk check (discount_approval is null or discount_approval in ('grant', 'emergency'));
  end if;
end $$;

-- record_sale2 asks rule_ok('discount_over_limit', ...) BEFORE the insert: a granted role passes can_grant (= the seller holds the right), otherwise the one-use / window
-- emergency approval is consumed and use_emergency leaves 'id:grant' in the transaction setting bos.em_used.  The trigger reads exactly that.
create or replace function public._sales_discount_approver() returns trigger
language plpgsql security definer set search_path = public as $$
declare em text; rid bigint; r public.emergency_requests; lim jsonb;
begin
  if coalesce(new.discount, 0) <= 0 or new.discount_approved_by is not null then return new; end if;
  em := current_setting('bos.em_used', true);
  if em is not null and em ~ ':discount_over_limit' then
    select (x.m)[1]::bigint into rid from regexp_matches(em, '([0-9]+):discount_over_limit', 'g') as x(m) order by (x.m)[1]::bigint desc limit 1;
    select * into r from public.emergency_requests where id = rid;
    if found and r.decided_by is not null then
      new.discount_approved_by := r.decided_by; new.discount_approved_staff := r.decided_staff; new.discount_approval := 'emergency'; return new;
    end if;
  end if;
  select value into lim from public.location_settings where location_id = new.location_id and key = 'discount_limit';
  if public.rule_on('pos_discount_manager') and (lim is null or jsonb_typeof(lim) = 'null' or new.discount > (lim #>> '{}')::numeric) and public.can_grant('discount_over_limit') then
    new.discount_approved_by := new.created_by;
    select staff_id into new.discount_approved_staff from public.profiles where id = new.created_by;
    new.discount_approval := 'grant';
  end if;
  return new;
end $$;
revoke all on function public._sales_discount_approver() from public, anon, authenticated;
drop trigger if exists sales_discount_approver on public.sales;
create trigger sales_discount_approver before insert on public.sales for each row execute function public._sales_discount_approver();

create or replace function public.discounts_report(p_from date, p_to date, p_loc int default null, p_only_approved boolean default false)
returns table (sale_id uuid, location_id int, receipt int, sale_date date, status text, subtotal numeric, discount numeric, discount_kind text, discount_input numeric, total numeric,
               seller_staff text, approver_staff text, approval text, over_limit boolean, customer text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  return query
    select s.id, s.location_id, s.receipt, s.sale_date, s.status, s.subtotal, s.discount, s.discount_kind, s.discount_input, s.total, s.created_staff,
           s.discount_approved_staff, s.discount_approval,
           (s.discount_approval is not null), s.customer
    from public.sales s
    where s.sale_date between p_from and p_to and s.discount > 0 and (p_loc is null or s.location_id = p_loc) and public.can_loc(s.location_id)
      and (not coalesce(p_only_approved, false) or s.discount_approval is not null)
    order by s.sale_date desc, s.location_id, s.receipt desc limit 2000;
end $$;

-- ---------- (4) brand-level P&L ----------
-- The existing gross-profit figures (biz_daily: revenue, discount, voids, costed revenue, cost of goods) grouped by brand.  A location that is not in report_brand_map is
-- shown as 'unmapped' (nothing is guessed).  Cost / gross profit are NULL for callers without a cost right (biz_daily already blanks them).  Combined = the sum of the rows (web).
create or replace function public.brand_pnl(p_from date, p_to date, p_brand text default null)
returns table (brand_code text, brand_bn text, brand_en text, locations int, n bigint, revenue numeric, discount numeric, void_n bigint, void_amt numeric,
               costed_rev numeric, cogs numeric, gross_profit numeric, gp_pct numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  return query
    with d as (select x.* from public.biz_daily(p_from, p_to, null) x),
    m as (select d.*, coalesce(b.brand_code, 'unmapped') bc, b.brand_bn bbn, b.brand_en ben from d left join public.report_brand_map b on b.location_id = d.location_id)
    select m.bc, coalesce(max(m.bbn), 'ব্র্যান্ড ঠিক করা নেই'), coalesce(max(m.ben), 'Not mapped to a brand'), (count(distinct m.location_id))::int,
           sum(m.n)::bigint, sum(m.revenue), sum(m.discount), sum(m.void_n)::bigint, sum(m.void_amt),
           sum(m.costed_rev), sum(m.cogs),
           case when public.biz_cost_ok() then sum(m.costed_rev) - sum(m.cogs) end,
           case when public.biz_cost_ok() and sum(m.costed_rev) > 0 then round((sum(m.costed_rev) - sum(m.cogs)) / sum(m.costed_rev) * 100, 2) end
    from m where p_brand is null or m.bc = p_brand
    group by m.bc order by sum(m.revenue) desc nulls last;
end $$;

-- ---------- grants ----------
revoke all on function public.entry_post_ledger_retry(uuid), public.entry_ledger_lines(uuid), public.ledger_post_problems(int), public.forms_ledger_cfg_set(text, boolean),
  public.discounts_report(date, date, int, boolean), public.brand_pnl(date, date, text) from public, anon;
grant execute on function public.entry_post_ledger_retry(uuid), public.entry_ledger_lines(uuid), public.ledger_post_problems(int), public.forms_ledger_cfg_set(text, boolean),
  public.discounts_report(date, date, int, boolean), public.brand_pnl(date, date, text) to authenticated;
revoke all on function public._elp_num(text), public._elp_flag(text), public._elp_loc(text), public._elp_enabled(text), public._sales_discount_approver() from public, anon, authenticated;
