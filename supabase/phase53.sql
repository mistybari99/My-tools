-- ============================================================
-- PHASE 53 (P2 gaps #1-#5 on top of phase40 accounting). Additive and idempotent (paste twice = no error). Needs phase8..phase28, phase40.
--   #1 Bank statement reconcile: bank_statement_lines (append-only) + bank_recon_matches (current state) + bank_recon_trail (append-only).
--      Owner / accounts_manage pastes statement lines (JSON rows, the browser turns CSV into rows); match to journal lines of the same bank/cash account
--      by amount + date window + reference; manual match / unmatch (reason) with a trail; unmatched report. NOTHING is auto-posted to the books.
--   #2 Year-end close: year_closes + ONE closing journal entry (income/expense -> retained earnings, per location), owner only, only after the period is
--      locked (rule period_closed_until >= year end), dry-run preview first, reversible by a reversing entry (phase40 _acct_reverse).
--   #3 VAT ledger: REPORT ONLY (vat_report). Uses the existing phase8 switches vat_on (OFF) + vat_rate (no default, owner enters). Output VAT from sales /
--      sale returns, input VAT from posted purchase bills / returns, only for items marked vat_applicable = true. Nothing is posted.
--   #4 Fixed-asset register fa_assets + straight-line schedule + monthly depreciation posting fa_depr_post (idempotent on (asset, month)).
--   #5 Budgets per account / month (/ location) with a change log, and the budget-vs-actual report.
-- Switches (rules, module books, ALL default OFF): bank_recon_on, year_close_on, fixed_assets_on, budgets_on, plus vat_prices_include (how the owner prices: ON = prices already include VAT).
-- Every write goes through a SECURITY DEFINER function (owner or accounts_manage; the year close is owner only). Tables are RLS read-only. Nothing is deleted.
-- ============================================================

-- ---------- rules ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('bank_recon_on', 'books', 'switch', 'false', null, null, null, null, 'ব্যাংক স্টেটমেন্ট মিলানো চালু', 'Bank statement reconcile চালু', 'Bank statement reconcile on',
  'চালু হলে স্টেটমেন্টের লাইন পেস্ট করে খতিয়ানের সাথে মেলানো যায়। কিছু নিজে পোস্ট হয় না।', 'On = paste statement lines and match them to the books. Nothing is posted by itself.', 93),
 ('year_close_on', 'books', 'switch', 'false', null, null, null, null, 'বছর শেষের ক্লোজ চালু', 'Year-end close চালু', 'Year-end close on',
  'শুধু মালিক। আগে হিসাব-লক তারিখ বছর শেষ পর্যন্ত দিতে হবে। আগে প্রিভিউ, উল্টানো যায়।', 'Owner only. The books-closed date must reach the year end first. Preview first; it can be reversed.', 94),
 ('fixed_assets_on', 'books', 'switch', 'false', null, null, null, null, 'স্থায়ী সম্পদ ও অবচয় চালু', 'Fixed assets ও depreciation চালু', 'Fixed assets and depreciation on',
  'চালু হলে সম্পদ তালিকা ও মাসিক অবচয় পোস্ট করা যায়।', 'On = enter assets and post monthly depreciation.', 95),
 ('budgets_on', 'books', 'switch', 'false', null, null, null, null, 'বাজেট চালু', 'Budget চালু', 'Budgets on',
  'চালু হলে হিসাব/মাস ধরে বাজেট দেওয়া যায়; বাজেট বনাম আসল রিপোর্ট দেখা যায়।', 'On = set budgets per account and month; budget-vs-actual report.', 96),
 ('vat_prices_include', 'books', 'switch', 'true', null, null, null, null, 'দামে ভ্যাট ধরা আছে', 'Prices এ VAT ধরা আছে', 'Prices already include VAT',
  'চালু = বিক্রি/কেনার দামে ভ্যাট ভেতরেই আছে (হার থেকে ভাগ করে বের হয়)। বন্ধ = ভ্যাট দামের উপরে যোগ হয়। আপনার পরামর্শদাতার কাছে নিশ্চিত হয়ে নিন।', 'On = sale / purchase prices already contain VAT (it is extracted from the rate). Off = VAT is added on top. Confirm with your adviser.', 97)
 on conflict (key) do nothing;

-- mapping keys for depreciation and the closing entry (the owner can re-point them with acct_mapping_set)
insert into public.acct_mappings (key, account_id, label_bn, label_en)
select v.k, a.id, v.lb, v.le from (values
  ('depreciation', '5820', 'অবচয় খরচ', 'Depreciation expense'),
  ('accum_depr', '1590', 'সঞ্চিত অবচয়', 'Accumulated depreciation'),
  ('retained_close', '3900', 'বছর শেষের ক্লোজ: জমা মুনাফা', 'Year-end close: retained earnings')
) as v(k, c, lb, le) join public.coa_accounts a on a.code = v.c
on conflict (key) do nothing;

-- ---------- tables ----------
create table if not exists public.bank_statement_lines (
  id bigserial primary key,
  batch_id uuid not null,
  account_id bigint not null references public.coa_accounts(id),
  line_date date not null check (line_date >= date '2000-01-01'),
  amount numeric not null check (amount <> 0 and abs(amount) <= 1000000000000),      -- signed: + money in, - money out
  reference text check (reference is null or length(reference) <= 120),
  description text check (description is null or length(description) <= 300),
  balance numeric check (balance is null or abs(balance) <= 1000000000000),
  row_hash text not null,
  created_by uuid, created_at timestamptz not null default now(),
  unique (account_id, row_hash)
);
create index if not exists bsl_acc_date on public.bank_statement_lines (account_id, line_date);
create index if not exists bsl_batch on public.bank_statement_lines (batch_id);

create table if not exists public.bank_recon_matches (
  id bigserial primary key,
  line_id bigint not null references public.bank_statement_lines(id),
  entry_id bigint not null,
  line_no int not null,
  active boolean not null default true,
  how text not null default 'manual' check (how in ('manual', 'suggested')),
  note text,
  matched_by uuid, matched_at timestamptz not null default now(),
  unmatched_by uuid, unmatched_at timestamptz, unmatch_note text,
  foreign key (entry_id, line_no) references public.journal_lines(entry_id, line_no)
);
create unique index if not exists brm_line_uq on public.bank_recon_matches (line_id) where active;
create unique index if not exists brm_jl_uq on public.bank_recon_matches (entry_id, line_no) where active;

create table if not exists public.bank_recon_trail (
  id bigserial primary key,
  line_id bigint not null references public.bank_statement_lines(id),
  action text not null check (action in ('match', 'unmatch')),
  entry_id bigint, line_no int,
  how text, note text,
  actor uuid, at timestamptz not null default now()
);

create table if not exists public.year_closes (
  id bigserial primary key,
  fiscal_from date not null, fiscal_to date not null check (fiscal_to >= fiscal_from),
  status text not null default 'closed' check (status in ('closed', 'reopened')),
  entry_id bigint references public.journal_entries(id),
  reversal_id bigint references public.journal_entries(id),
  income_total numeric not null default 0, expense_total numeric not null default 0, net_profit numeric not null default 0,
  note text, client_id uuid unique,
  closed_by uuid, closed_at timestamptz not null default now(),
  reopened_by uuid, reopened_at timestamptz, reopen_note text
);
create index if not exists yc_range on public.year_closes (fiscal_from, fiscal_to);

create table if not exists public.fa_assets (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  code text not null unique check (code ~ '^[0-9A-Za-z.\-]{1,20}$'),
  name text not null check (length(btrim(name)) between 1 and 120),
  category text check (category is null or length(category) <= 60),
  location_id int references public.locations(id),
  acquired_on date not null,
  cost numeric not null check (cost > 0 and cost <= 1000000000000),
  salvage numeric not null default 0 check (salvage >= 0 and salvage < cost),
  life_months int not null check (life_months between 1 and 1200),
  method text not null default 'straight_line' check (method in ('straight_line')),
  depr_from date not null check (extract(day from depr_from) = 1),           -- first month that is depreciated
  status text not null default 'active' check (status in ('active', 'disposed')),
  disposed_on date, note text,
  created_by uuid, created_at timestamptz not null default now(), updated_at timestamptz
);
create table if not exists public.fa_depr_posts (
  id bigserial primary key,
  asset_id uuid not null references public.fa_assets(id),
  month date not null check (extract(day from month) = 1),
  seq int not null,
  amount numeric not null check (amount > 0),
  entry_id bigint not null references public.journal_entries(id),
  created_by uuid, created_at timestamptz not null default now(),
  unique (asset_id, month)
);

create table if not exists public.budgets (
  id bigserial primary key,
  account_id bigint not null references public.coa_accounts(id),
  month date not null check (extract(day from month) = 1),
  location_id int references public.locations(id),
  amount numeric not null check (amount >= 0 and amount <= 1000000000000),
  updated_by uuid, updated_at timestamptz not null default now()
);
create unique index if not exists budgets_uq on public.budgets (account_id, month, coalesce(location_id, 0));
create table if not exists public.budget_log (
  id bigserial primary key,
  account_id bigint not null, month date not null, location_id int,
  old_amount numeric, new_amount numeric not null, note text,
  actor uuid, at timestamptz not null default now()
);

-- ---------- immutability ----------
create or replace function public._a53_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end $$;
create or replace function public._a53_nodel() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'nothing is deleted: %', tg_table_name; end $$;
do $t$
declare t text;
begin
  foreach t in array array['bank_statement_lines', 'bank_recon_trail', 'budget_log', 'fa_depr_posts'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_ro', t);
    execute format('create trigger %I before update or delete on public.%I for each row execute function public._a53_ro()', t || '_ro', t);
    execute format('drop trigger if exists %I on public.%I', t || '_ro_t', t);
    execute format('create trigger %I before truncate on public.%I for each statement execute function public._a53_ro()', t || '_ro_t', t);
  end loop;
  foreach t in array array['bank_recon_matches', 'year_closes', 'fa_assets', 'budgets'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nd', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public._a53_nodel()', t || '_nd', t);
    execute format('drop trigger if exists %I on public.%I', t || '_nd_t', t);
    execute format('create trigger %I before truncate on public.%I for each statement execute function public._a53_nodel()', t || '_nd_t', t);
  end loop;
end $t$;
drop trigger if exists audit_year_closes on public.year_closes;
create trigger audit_year_closes after insert or update on public.year_closes for each row execute function public.log_change('id');
drop trigger if exists audit_fa_assets on public.fa_assets;
create trigger audit_fa_assets after insert or update on public.fa_assets for each row execute function public.log_change('id');
drop trigger if exists audit_budgets on public.budgets;
create trigger audit_budgets after insert or update on public.budgets for each row execute function public.log_change('id');
drop trigger if exists audit_bank_recon_matches on public.bank_recon_matches;
create trigger audit_bank_recon_matches after insert or update on public.bank_recon_matches for each row execute function public.log_change('id');

create or replace function public._a53_mgr() returns boolean language sql stable security definer set search_path = public as $$ select public._acct_manage(); $$;
revoke all on function public._a53_mgr() from public, anon;
grant execute on function public._a53_mgr() to authenticated;

-- ---------- RLS: read only, owner / accounts_manage for the bank tables, accounts viewers for the rest ----------
alter table public.bank_statement_lines enable row level security;
alter table public.bank_recon_matches enable row level security;
alter table public.bank_recon_trail enable row level security;
alter table public.year_closes enable row level security;
alter table public.fa_assets enable row level security;
alter table public.fa_depr_posts enable row level security;
alter table public.budgets enable row level security;
alter table public.budget_log enable row level security;
drop policy if exists bsl_read on public.bank_statement_lines;
create policy bsl_read on public.bank_statement_lines for select to authenticated using (public._a53_mgr());
drop policy if exists brm_read on public.bank_recon_matches;
create policy brm_read on public.bank_recon_matches for select to authenticated using (public._a53_mgr());
drop policy if exists brt_read on public.bank_recon_trail;
create policy brt_read on public.bank_recon_trail for select to authenticated using (public._a53_mgr());
drop policy if exists yc_read on public.year_closes;
create policy yc_read on public.year_closes for select to authenticated using (public._acct_view() and public._acct_all());
drop policy if exists fa_read on public.fa_assets;
create policy fa_read on public.fa_assets for select to authenticated using (public._acct_view() and (public._acct_all() or (location_id is not null and public.can_loc(location_id))));
drop policy if exists fadp_read on public.fa_depr_posts;
create policy fadp_read on public.fa_depr_posts for select to authenticated using (public._acct_view() and exists (select 1 from public.fa_assets a where a.id = asset_id));
drop policy if exists bud_read on public.budgets;
create policy bud_read on public.budgets for select to authenticated using (public._acct_view() and (public._acct_all() or (location_id is not null and public.can_loc(location_id))));
drop policy if exists budlog_read on public.budget_log;
create policy budlog_read on public.budget_log for select to authenticated using (public._a53_mgr());
revoke all on public.bank_statement_lines, public.bank_recon_matches, public.bank_recon_trail, public.year_closes, public.fa_assets, public.fa_depr_posts, public.budgets, public.budget_log from public, anon, authenticated;
grant select on public.bank_statement_lines, public.bank_recon_matches, public.bank_recon_trail, public.year_closes, public.fa_assets, public.fa_depr_posts, public.budgets, public.budget_log to authenticated;

-- ---------- shared helpers (closed to browsers) ----------
-- income / expense movement per account and location, optionally leaving out year-close entries (so a closed year still shows its real profit)
create or replace function public._a53_pl(p_from date, p_to date, p_loc int, p_excl boolean) returns table(account_id bigint, location_id int, dr numeric, cr numeric)
language plpgsql stable security definer set search_path = public as $$
declare v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs();
begin
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return query
  select l.account_id, l.location_id, coalesce(sum(l.debit), 0), coalesce(sum(l.credit), 0)
  from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts a on a.id = l.account_id
  where a.type in ('income', 'expense') and e.entry_date between p_from and p_to
    and (not p_excl or coalesce(e.flags, '') not like '%year_close%')
    and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
  group by l.account_id, l.location_id;
end $$;

create or replace function public._a53_mon(p date) returns date language sql immutable as $$ select date_trunc('month', p)::date; $$;

-- ============================================================
-- #1 BANK STATEMENT RECONCILE
-- ============================================================
create or replace function public._a53_bank_acct(p_account bigint) returns public.coa_accounts language plpgsql stable security definer set search_path = public as $$
declare a public.coa_accounts; par public.coa_accounts;
begin
  select * into a from public.coa_accounts where id = p_account;
  if not found or a.is_group or a.type <> 'asset' or not a.active then raise exception 'bad_account'; end if;
  select * into par from public.coa_accounts where id = a.parent_id;
  if not found or par.code <> '1100' then raise exception 'bad_account'; end if;       -- only cash and bank accounts
  return a;
end $$;

-- candidate journal lines for one statement line: same account, exactly the same signed amount, posted, not matched yet, date within +-p_days
create or replace function public._a53_cands(p_line bigint, p_days int default 5) returns table(entry_id bigint, line_no int, entry_date date, memo text, source_type text, source_id text, amount numeric, days_off int, ref_hit boolean)
language plpgsql stable security definer set search_path = public as $$
declare s public.bank_statement_lines; v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs();
begin
  select * into s from public.bank_statement_lines where id = p_line;
  if not found then raise exception 'not found'; end if;
  return query
  select e.id, l.line_no, e.entry_date, e.memo, e.source_type, e.source_id, (l.debit - l.credit), (e.entry_date - s.line_date),
    (nullif(btrim(s.reference), '') is not null and (position(lower(btrim(s.reference)) in lower(coalesce(e.memo, '') || ' ' || e.source_id || ' ' || coalesce(l.memo, ''))) > 0))
  from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
  where l.account_id = s.account_id and (l.debit - l.credit) = s.amount and e.status = 'posted'
    and e.entry_date between s.line_date - greatest(coalesce(p_days, 5), 0) and s.line_date + greatest(coalesce(p_days, 5), 0)
    and (v_all or l.location_id = any (v_locs))
    and not exists (select 1 from public.bank_recon_matches m where m.entry_id = l.entry_id and m.line_no = l.line_no and m.active)
  order by 9 desc, abs(e.entry_date - s.line_date), e.id;
end $$;

-- import statement lines. p_rows = [{date:'YYYY-MM-DD', amount: signed number (+in / -out), reference, description, balance}]
create or replace function public.bank_stmt_import(p_account bigint, p_rows jsonb, p_client uuid default null, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.coa_accounts; e jsonb; ord int := 0; d date; amt numeric; ref text; dsc text; bal numeric; k text; cnt int; m jsonb := '{}'::jsonb;
  good jsonb := '[]'::jsonb; bad jsonb := '[]'::jsonb; nbad int := 0; hsh text; nnew int := 0; ndup int := 0; batch uuid; ins int; rec record; sum_in numeric := 0; sum_out numeric := 0;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('bank_recon_on') then raise exception 'switch_off: bank_recon_on'; end if;
  a := public._a53_bank_acct(p_account);
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'no_rows'; end if;
  if jsonb_array_length(p_rows) > 2000 then raise exception 'too_many_rows'; end if;
  if p_client is not null and not p_dry then
    perform public._client_lock(p_client);
    if exists (select 1 from public.bank_statement_lines where batch_id = p_client) then
      return jsonb_build_object('dup', true, 'batch_id', p_client, 'imported', (select count(*) from public.bank_statement_lines where batch_id = p_client));
    end if;
  end if;
  batch := coalesce(p_client, gen_random_uuid());
  for e in select * from jsonb_array_elements(p_rows) loop
    ord := ord + 1;
    begin
      if jsonb_typeof(e) <> 'object' then raise exception 'bad_row'; end if;
      if coalesce(e->>'date', '') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'bad_date'; end if;
      d := (e->>'date')::date;
      if d < date '2000-01-01' or d > public._acct_today() + 1 then raise exception 'bad_date'; end if;
      if coalesce(e->>'amount', '') !~ '^-?\d+(\.\d+)?$' then raise exception 'bad_amount'; end if;
      amt := round((e->>'amount')::numeric, 2);
      if amt = 0 or abs(amt) > 1000000000000 then raise exception 'bad_amount'; end if;
      ref := left(nullif(btrim(coalesce(e->>'reference', '')), ''), 120);
      dsc := left(nullif(btrim(coalesce(e->>'description', '')), ''), 300);
      bal := null;
      if nullif(e->>'balance', '') is not null then
        if e->>'balance' !~ '^-?\d+(\.\d+)?$' or abs((e->>'balance')::numeric) > 1000000000000 then raise exception 'bad_balance'; end if;
        bal := round((e->>'balance')::numeric, 2);
      end if;
      k := p_account::text || '|' || d::text || '|' || amt::text || '|' || lower(coalesce(ref, '')) || '|' || lower(coalesce(dsc, ''));
      cnt := coalesce((m->>k)::int, 0) + 1;
      m := m || jsonb_build_object(k, cnt);
      hsh := md5(k || '|' || cnt::text);
      good := good || jsonb_build_object('d', d, 'a', amt, 'r', ref, 'x', dsc, 'b', bal, 'h', hsh, 'n', ord);
    exception when others then
      nbad := nbad + 1;
      if nbad <= 20 then bad := bad || jsonb_build_object('row', ord, 'why', sqlerrm); end if;
    end;
  end loop;
  for rec in select (g->>'d')::date d, (g->>'a')::numeric a, g->>'h' h from jsonb_array_elements(good) g loop
    if exists (select 1 from public.bank_statement_lines where account_id = p_account and row_hash = rec.h) then ndup := ndup + 1;
    else nnew := nnew + 1; if rec.a > 0 then sum_in := sum_in + rec.a; else sum_out := sum_out + rec.a; end if; end if;
  end loop;
  if p_dry then
    return jsonb_build_object('dry', true, 'rows', ord, 'new', nnew, 'duplicate', ndup, 'invalid', nbad, 'invalid_list', bad, 'sum_in', sum_in, 'sum_out', sum_out);
  end if;
  if nbad > 0 then raise exception 'invalid_rows' using detail = bad::text; end if;
  for rec in select (g->>'d')::date d, (g->>'a')::numeric a, g->>'r' r, g->>'x' x, nullif(g->>'b', '')::numeric b, g->>'h' h from jsonb_array_elements(good) g loop
    insert into public.bank_statement_lines (batch_id, account_id, line_date, amount, reference, description, balance, row_hash, created_by)
      values (batch, p_account, rec.d, rec.a, rec.r, rec.x, rec.b, rec.h, auth.uid()) on conflict (account_id, row_hash) do nothing;
    get diagnostics ins = row_count;
  end loop;
  return jsonb_build_object('batch_id', batch, 'rows', ord, 'imported', nnew, 'duplicate', ndup, 'sum_in', sum_in, 'sum_out', sum_out);
end $$;

create or replace function public.bank_recon_candidates(p_line bigint, p_days int default 5) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('entry_id', c.entry_id, 'line_no', c.line_no, 'date', c.entry_date, 'memo', c.memo, 'source_type', c.source_type,
      'source_id', c.source_id, 'amount', c.amount, 'days_off', c.days_off, 'ref_hit', c.ref_hit)) from (select * from public._a53_cands(p_line, p_days) limit 20) c), '[]'::jsonb);
end $$;

-- suggestions only (writes nothing). confident = the only candidate, or the only one whose text contains the statement reference.
create or replace function public.bank_recon_suggest(p_account bigint, p_from date default null, p_to date default null, p_days int default 3) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb := '[]'::jsonb; s record; n int; hits int; best record; used text[] := '{}'; kk text; conf boolean;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  perform public._a53_bank_acct(p_account);
  for s in select l.* from public.bank_statement_lines l
           where l.account_id = p_account and (p_from is null or l.line_date >= p_from) and (p_to is null or l.line_date <= p_to)
             and not exists (select 1 from public.bank_recon_matches m where m.line_id = l.id and m.active)
           order by l.line_date, l.id limit 500 loop
    select count(*), count(*) filter (where ref_hit) into n, hits from public._a53_cands(s.id, p_days);
    if n = 0 then continue; end if;
    select * into best from public._a53_cands(s.id, p_days) c where (hits <> 1 or c.ref_hit) and not ((c.entry_id::text || ':' || c.line_no::text) = any (used)) limit 1;
    if not found then continue; end if;
    conf := (n = 1) or (hits = 1);
    kk := best.entry_id::text || ':' || best.line_no::text;
    if conf then used := used || kk; end if;
    out_ := out_ || jsonb_build_object('line_id', s.id, 'line_date', s.line_date, 'amount', s.amount, 'reference', s.reference, 'entry_id', best.entry_id, 'line_no', best.line_no,
      'entry_date', best.entry_date, 'memo', best.memo, 'days_off', best.days_off, 'ref_hit', best.ref_hit, 'candidates', n, 'confident', conf);
  end loop;
  return jsonb_build_object('suggestions', out_, 'count', jsonb_array_length(out_));
end $$;

create or replace function public._a53_match1(p_line bigint, p_entry bigint, p_no int, p_how text, p_note text) returns bigint
language plpgsql security definer set search_path = public as $$
declare s public.bank_statement_lines; jl public.journal_lines; je public.journal_entries; id_ bigint;
begin
  select * into s from public.bank_statement_lines where id = p_line for update;
  if not found then raise exception 'not found'; end if;
  select * into jl from public.journal_lines where entry_id = p_entry and line_no = p_no;
  if not found then raise exception 'journal_line_not_found'; end if;
  select * into je from public.journal_entries where id = p_entry;
  if je.status <> 'posted' then raise exception 'entry_not_posted'; end if;
  if jl.account_id <> s.account_id then raise exception 'wrong_account'; end if;
  if jl.location_id is not null and not public.can_loc(jl.location_id) then raise exception 'not allowed for this location'; end if;
  if (jl.debit - jl.credit) <> s.amount then raise exception 'amount_mismatch' using detail = 'statement ' || s.amount::text || ' book ' || (jl.debit - jl.credit)::text; end if;
  if exists (select 1 from public.bank_recon_matches where line_id = p_line and active) then raise exception 'line_already_matched'; end if;
  if exists (select 1 from public.bank_recon_matches where entry_id = p_entry and line_no = p_no and active) then raise exception 'journal_already_matched'; end if;
  insert into public.bank_recon_matches (line_id, entry_id, line_no, how, note, matched_by) values (p_line, p_entry, p_no, p_how, left(nullif(btrim(p_note), ''), 200), auth.uid()) returning id into id_;
  insert into public.bank_recon_trail (line_id, action, entry_id, line_no, how, note, actor) values (p_line, 'match', p_entry, p_no, p_how, left(nullif(btrim(p_note), ''), 200), auth.uid());
  return id_;
end $$;

create or replace function public.bank_recon_match(p_line bigint, p_entry bigint, p_line_no int, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare id_ bigint;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('bank_recon_on') then raise exception 'switch_off: bank_recon_on'; end if;
  id_ := public._a53_match1(p_line, p_entry, p_line_no, 'manual', p_note);
  return jsonb_build_object('match_id', id_);
end $$;

-- accept a reviewed list of suggestions [{line_id, entry_id, line_no}]; dry = check only. Each pair is checked on its own; failures are listed, the rest go through.
create or replace function public.bank_recon_match_many(p_pairs jsonb, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p jsonb; ok int := 0; fails jsonb := '[]'::jsonb;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('bank_recon_on') then raise exception 'switch_off: bank_recon_on'; end if;
  if p_pairs is null or jsonb_typeof(p_pairs) <> 'array' or jsonb_array_length(p_pairs) = 0 then raise exception 'no_rows'; end if;
  if jsonb_array_length(p_pairs) > 500 then raise exception 'too_many_rows'; end if;
  for p in select * from jsonb_array_elements(p_pairs) loop
    begin
      perform public._a53_match1((p->>'line_id')::bigint, (p->>'entry_id')::bigint, (p->>'line_no')::int, 'suggested', null);
      ok := ok + 1;
      if p_dry then raise exception 'dry_rollback'; end if;
    exception when others then
      if sqlerrm = 'dry_rollback' then null; else fails := fails || jsonb_build_object('line_id', p->'line_id', 'why', sqlerrm); end if;
    end;
  end loop;
  return jsonb_build_object('dry', p_dry, 'ok', ok, 'failed', jsonb_array_length(fails), 'failures', fails);
end $$;

create or replace function public.bank_recon_unmatch(p_line bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.bank_recon_matches;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('bank_recon_on') then raise exception 'switch_off: bank_recon_on'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into m from public.bank_recon_matches where line_id = p_line and active for update;
  if not found then raise exception 'not_matched'; end if;
  update public.bank_recon_matches set active = false, unmatched_by = auth.uid(), unmatched_at = now(), unmatch_note = left(btrim(p_note), 200) where id = m.id;
  insert into public.bank_recon_trail (line_id, action, entry_id, line_no, how, note, actor) values (p_line, 'unmatch', m.entry_id, m.line_no, m.how, left(btrim(p_note), 200), auth.uid());
  return jsonb_build_object('unmatched', p_line);
end $$;

create or replace function public.bank_recon_report(p_account bigint, p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); fr date := coalesce(p_from, date '2000-01-01'); to_ date := coalesce(p_to, date '2999-12-31');
  su jsonb; bu jsonb; sn int; sa numeric; bn int; ba numeric; mn int; ma numeric; st numeric; bk numeric; lb numeric; lbd date;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  perform public._a53_bank_acct(p_account);
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'date', x.line_date, 'amount', x.amount, 'reference', x.reference, 'description', x.description) order by x.line_date, x.id), '[]'::jsonb), count(*), coalesce(sum(x.amount), 0)
    into su, sn, sa from (select l.* from public.bank_statement_lines l where l.account_id = p_account and l.line_date between fr and to_
      and not exists (select 1 from public.bank_recon_matches m where m.line_id = l.id and m.active) order by l.line_date, l.id limit 500) x;
  select count(*), coalesce(sum(l.amount), 0) into sn, sa from public.bank_statement_lines l where l.account_id = p_account and l.line_date between fr and to_
      and not exists (select 1 from public.bank_recon_matches m where m.line_id = l.id and m.active);
  select coalesce(jsonb_agg(jsonb_build_object('entry_id', x.entry_id, 'line_no', x.line_no, 'date', x.entry_date, 'memo', x.memo, 'source_type', x.source_type, 'amount', x.amount) order by x.entry_date, x.entry_id), '[]'::jsonb)
    into bu from (select e.id entry_id, l.line_no, e.entry_date, e.memo, e.source_type, (l.debit - l.credit) amount from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
      where l.account_id = p_account and e.status = 'posted' and e.entry_date between fr and to_ and (v_all or l.location_id = any (v_locs))
        and not exists (select 1 from public.bank_recon_matches m where m.entry_id = l.entry_id and m.line_no = l.line_no and m.active) order by e.entry_date, e.id limit 500) x;
  select count(*), coalesce(sum(l.debit - l.credit), 0) into bn, ba from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
      where l.account_id = p_account and e.status = 'posted' and e.entry_date between fr and to_ and (v_all or l.location_id = any (v_locs))
        and not exists (select 1 from public.bank_recon_matches m where m.entry_id = l.entry_id and m.line_no = l.line_no and m.active);
  select count(*), coalesce(sum(l.amount), 0) into mn, ma from public.bank_statement_lines l join public.bank_recon_matches m on m.line_id = l.id and m.active
      where l.account_id = p_account and l.line_date between fr and to_;
  select coalesce(sum(amount), 0) into st from public.bank_statement_lines where account_id = p_account and line_date between fr and to_;
  select coalesce(sum(l.debit - l.credit), 0) into bk from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
      where l.account_id = p_account and e.status = 'posted' and e.entry_date between fr and to_ and (v_all or l.location_id = any (v_locs));
  select balance, line_date into lb, lbd from public.bank_statement_lines where account_id = p_account and balance is not null order by line_date desc, id desc limit 1;
  return jsonb_build_object('account_id', p_account, 'from', p_from, 'to', p_to,
    'statement_unmatched', su, 'statement_unmatched_count', sn, 'statement_unmatched_sum', sa,
    'book_unmatched', bu, 'book_unmatched_count', bn, 'book_unmatched_sum', ba,
    'matched_count', mn, 'matched_sum', ma, 'statement_total', st, 'book_total', bk, 'difference', st - bk,
    'last_statement_balance', lb, 'last_statement_balance_date', lbd);
end $$;

create or replace function public.bank_recon_lines(p_account bigint, p_status text default 'all', p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  perform public._a53_bank_acct(p_account);
  if p_status not in ('all', 'matched', 'unmatched') then raise exception 'bad_status'; end if;
  return coalesce((select jsonb_agg(j order by (j->>'date') desc, (j->>'id')::bigint desc) from (
    select jsonb_build_object('id', l.id, 'date', l.line_date, 'amount', l.amount, 'reference', l.reference, 'description', l.description,
      'matched', m.id is not null, 'entry_id', m.entry_id, 'line_no', m.line_no, 'how', m.how) j
    from public.bank_statement_lines l left join public.bank_recon_matches m on m.line_id = l.id and m.active
    where l.account_id = p_account and (p_status = 'all' or (p_status = 'matched') = (m.id is not null))
    order by l.line_date desc, l.id desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) z), '[]'::jsonb);
end $$;

-- ============================================================
-- #2 YEAR-END CLOSE
-- ============================================================
create or replace function public._a53_close_plan(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lines jsonb := '[]'::jsonb; r record; ti numeric := 0; te numeric := 0; re_acc bigint; net numeric; problems jsonb := '[]'::jsonb; lk text; lkd date; cnt int := 0; dr_sum numeric := 0; cr_sum numeric := 0;
begin
  select account_id into re_acc from public.acct_mappings where key = 'retained_close';
  if re_acc is null then problems := problems || '"no_retained_mapping"'::jsonb; end if;
  for r in select p.account_id, p.location_id, a.type, a.code, a.name_en, (p.dr - p.cr) n from public._a53_pl(p_from, p_to, null, true) p join public.coa_accounts a on a.id = p.account_id
           where p.dr - p.cr <> 0 order by a.code, p.location_id loop
    cnt := cnt + 1;
    if r.type = 'income' then ti := ti - r.n; else te := te + r.n; end if;
    if r.n > 0 then
      lines := lines || jsonb_build_object('account_id', r.account_id, 'debit', 0, 'credit', r.n, 'location_id', r.location_id, 'code', r.code, 'name', r.name_en); cr_sum := cr_sum + r.n;
    else
      lines := lines || jsonb_build_object('account_id', r.account_id, 'debit', -r.n, 'credit', 0, 'location_id', r.location_id, 'code', r.code, 'name', r.name_en); dr_sum := dr_sum - r.n;
    end if;
  end loop;
  net := dr_sum - cr_sum;           -- credit-balance accounts closed minus debit-balance accounts closed = profit
  if cnt = 0 then problems := problems || '"nothing_to_close"'::jsonb; end if;
  -- retained-earnings line(s): one per location so a location's own books also balance
  for r in select nullif(l->>'location_id', '')::int location_id, sum(((l->>'debit')::numeric) - ((l->>'credit')::numeric)) d from jsonb_array_elements(lines) l group by 1 having sum(((l->>'debit')::numeric) - ((l->>'credit')::numeric)) <> 0 loop
    lines := lines || jsonb_build_object('account_id', re_acc, 'debit', case when r.d < 0 then -r.d else 0 end, 'credit', case when r.d > 0 then r.d else 0 end, 'location_id', r.location_id, 'code', 'RE', 'name', 'Retained earnings');
  end loop;
  lk := public.rule_txt('period_closed_until');
  if lk is null or lk !~ '^\d{4}-\d{2}-\d{2}$' then problems := problems || '"period_not_locked"'::jsonb;
  else
    begin lkd := lk::date; exception when others then lkd := null; end;
    if lkd is null or lkd < p_to then problems := problems || '"period_not_locked"'::jsonb; end if;
  end if;
  if exists (select 1 from public.year_closes where status = 'closed' and daterange(fiscal_from, fiscal_to, '[]') && daterange(p_from, p_to, '[]')) then problems := problems || '"already_closed"'::jsonb; end if;
  if public._acct_start() is null then problems := problems || '"data_needed"'::jsonb;
  elsif p_from < public._acct_start() then problems := problems || '"before_start"'::jsonb; end if;
  return jsonb_build_object('from', p_from, 'to', p_to, 'income_total', ti, 'expense_total', te, 'net_profit', ti - te, 'accounts', cnt, 'lines', lines, 'problems', problems,
    'period_closed_until', lk, 'ok', jsonb_array_length(problems) = 0);
end $$;

create or replace function public.year_close_run(p_from date, p_to date, p_note text default null, p_client uuid default null, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare plan jsonb; yc_id bigint; ent bigint; r public.year_closes; prob text;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not public.rule_on('year_close_on') then raise exception 'switch_off: year_close_on'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 370 or p_to > public._acct_today() then raise exception 'bad_range'; end if;
  plan := public._a53_close_plan(p_from, p_to);
  if p_dry then return plan || jsonb_build_object('dry', true); end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.year_closes where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id, 'entry_id', r.entry_id); end if;
  end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  if jsonb_array_length(plan->'problems') > 0 then raise exception '%', plan->'problems'->>0; end if;
  insert into public.year_closes (fiscal_from, fiscal_to, income_total, expense_total, net_profit, note, client_id, closed_by)
    values (p_from, p_to, (plan->>'income_total')::numeric, (plan->>'expense_total')::numeric, (plan->>'net_profit')::numeric, left(btrim(p_note), 300), p_client, auth.uid()) returning id into yc_id;
  ent := public._acct_write(p_to, null, 'year_close', yc_id::text, null, 'Year-end close ' || p_from::text || ' to ' || p_to::text, 'year_close', plan->'lines', null, null, null);
  update public.year_closes set entry_id = ent where id = yc_id;
  return jsonb_build_object('id', yc_id, 'entry_id', ent, 'net_profit', plan->'net_profit');
end $$;

create or replace function public.year_close_reverse(p_id bigint, p_note text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare y public.year_closes; rv bigint; r public.year_closes;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not public.rule_on('year_close_on') then raise exception 'switch_off: year_close_on'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.year_closes where reopened_by is not null and id = p_id and status = 'reopened';
    if found then return jsonb_build_object('dup', true, 'id', r.id, 'reversal_id', r.reversal_id); end if;
  end if;
  select * into y from public.year_closes where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if y.status <> 'closed' then raise exception 'already_reopened'; end if;
  if exists (select 1 from public.year_closes where status = 'closed' and fiscal_from > y.fiscal_to) then raise exception 'later_close_exists'; end if;
  rv := public._acct_reverse(y.entry_id, y.fiscal_to, 'Reopen year ' || y.fiscal_from::text || ' to ' || y.fiscal_to::text || ' (' || left(btrim(p_note), 150) || ')', p_client);
  update public.year_closes set status = 'reopened', reversal_id = rv, reopened_by = auth.uid(), reopened_at = now(), reopen_note = left(btrim(p_note), 300) where id = p_id;
  return jsonb_build_object('id', p_id, 'reversal_id', rv);
end $$;

create or replace function public.year_close_list() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('year_close_on'), 'period_closed_until', public.rule_txt('period_closed_until'), 'owner', public.is_owner(),
    'rows', coalesce((select jsonb_agg(to_jsonb(y) - 'client_id' order by y.fiscal_to desc, y.id desc) from public.year_closes y), '[]'::jsonb));
end $$;

-- income statement that leaves the closing entries out (phase40's acct_income_statement shows them, so a closed year there reads 0)
create or replace function public.acct_pnl_ex_close(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ti numeric; te numeric; rows_ jsonb;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception 'bad_range'; end if;
  select coalesce(sum(case when a.type = 'income' then p.cr - p.dr end), 0), coalesce(sum(case when a.type = 'expense' then p.dr - p.cr end), 0),
    coalesce(jsonb_agg(jsonb_build_object('code', a.code, 'name_en', a.name_en, 'name_bn', a.name_bn, 'type', a.type, 'amount', case when a.type = 'income' then p.cr - p.dr else p.dr - p.cr end) order by a.code), '[]'::jsonb)
    into ti, te, rows_ from (select account_id, sum(dr) dr, sum(cr) cr from public._a53_pl(p_from, p_to, p_loc, true) group by account_id) p join public.coa_accounts a on a.id = p.account_id;
  return jsonb_build_object('from', p_from, 'to', p_to, 'total_income', ti, 'total_expense', te, 'net_profit', ti - te, 'rows', rows_);
end $$;

-- ============================================================
-- #3 VAT LEDGER (report only; vat_on + vat_rate are the phase8 switches)
-- ============================================================
create or replace function public.vat_report(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rate numeric := public.rule_num('vat_rate'); inc boolean := public.rule_on('vat_prices_include'); v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs();
  out_t numeric := 0; out_v numeric := 0; out_u numeric := 0; out_n int := 0; ret_t numeric := 0; ret_v numeric := 0; in_t numeric := 0; in_v numeric := 0; in_u numeric := 0; in_n int := 0; inr_t numeric := 0; inr_v numeric := 0;
  months jsonb;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if not public.rule_on('vat_on') then return jsonb_build_object('off', true); end if;
  if rate is null then return jsonb_build_object('data_needed', true, 'need', 'vat_rate'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 800 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  create temporary table if not exists _a53_vat (kind text, d date, taxable numeric, undecided numeric) on commit drop;
  delete from _a53_vat;
  -- sales: taxable = value of vat_applicable=true lines, less the bill discount share
  insert into _a53_vat
  select 'out', s.sale_date,
    coalesce(t.tx, 0) * case when s.subtotal > 0 then (s.subtotal - s.discount) / s.subtotal else 1 end,
    coalesce(t.und, 0) * case when s.subtotal > 0 then (s.subtotal - s.discount) / s.subtotal else 1 end
  from public.sales s cross join lateral (
    select sum(coalesce((e->>'amount')::numeric, 0)) filter (where i.vat_applicable is true) tx,
           sum(coalesce((e->>'amount')::numeric, 0)) filter (where i.vat_applicable is null) und
    from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
    left join public.items i on i.id = nullif(e->>'item_id', '')::uuid) t
  where s.status = 'done' and s.sale_date between p_from and p_to and (v_all or s.location_id = any (v_locs)) and (p_loc is null or s.location_id = p_loc);
  -- sale returns reduce output VAT (the value taken back, in the share of VAT-applicable lines)
  insert into _a53_vat
  select 'outret', r.created_at::date, r.amount * case when t.tot > 0 then coalesce(t.tx, 0) / t.tot else 0 end, 0
  from public.sale_returns r cross join lateral (
    select sum(coalesce((e->>'amount')::numeric, 0)) tot, sum(coalesce((e->>'amount')::numeric, 0)) filter (where i.vat_applicable is true) tx
    from jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e left join public.items i on i.id = nullif(e->>'item_id', '')::uuid) t
  where r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to and (v_all or r.location_id = any (v_locs)) and (p_loc is null or r.location_id = p_loc);
  -- purchases: bill total (after the bill discount) in the share of VAT-applicable lines
  insert into _a53_vat
  select case when b.kind = 'return' then 'inret' else 'in' end, b.bill_date,
    b.total * case when t.tot > 0 then coalesce(t.tx, 0) / t.tot else 0 end, b.total * case when t.tot > 0 then coalesce(t.und, 0) / t.tot else 0 end
  from public.purchase_bills b cross join lateral (
    select sum(l.amount) tot, sum(l.amount) filter (where i.vat_applicable is true) tx, sum(l.amount) filter (where i.id is null or i.vat_applicable is null) und
    from public.purchase_lines l left join public.items i on i.id = l.item_id where l.bill_id = b.id) t
  where b.status = 'posted' and b.bill_date between p_from and p_to and (v_all or b.location_id = any (v_locs)) and (p_loc is null or b.location_id = p_loc);
  select coalesce(sum(taxable) filter (where kind = 'out'), 0), coalesce(sum(undecided) filter (where kind = 'out'), 0), count(*) filter (where kind = 'out'),
         coalesce(sum(taxable) filter (where kind = 'outret'), 0), coalesce(sum(taxable) filter (where kind = 'in'), 0), coalesce(sum(undecided) filter (where kind = 'in'), 0),
         count(*) filter (where kind = 'in'), coalesce(sum(taxable) filter (where kind = 'inret'), 0)
    into out_t, out_u, out_n, ret_t, in_t, in_u, in_n, inr_t from _a53_vat;
  out_v := round(case when inc then (out_t) * rate / (100 + rate) else out_t * rate / 100 end, 2);
  ret_v := round(case when inc then ret_t * rate / (100 + rate) else ret_t * rate / 100 end, 2);
  in_v := round(case when inc then in_t * rate / (100 + rate) else in_t * rate / 100 end, 2);
  inr_v := round(case when inc then inr_t * rate / (100 + rate) else inr_t * rate / 100 end, 2);
  select coalesce(jsonb_agg(jsonb_build_object('month', m, 'output_taxable', ot, 'output_vat', ov, 'input_taxable', it, 'input_vat', iv) order by m), '[]'::jsonb) into months from (
    select date_trunc('month', d)::date m,
      sum(case kind when 'out' then taxable when 'outret' then -taxable else 0 end) ot,
      round(sum(case kind when 'out' then taxable when 'outret' then -taxable else 0 end) * case when inc then rate / (100 + rate) else rate / 100 end, 2) ov,
      sum(case kind when 'in' then taxable when 'inret' then -taxable else 0 end) it,
      round(sum(case kind when 'in' then taxable when 'inret' then -taxable else 0 end) * case when inc then rate / (100 + rate) else rate / 100 end, 2) iv
    from _a53_vat group by 1) z;
  return jsonb_build_object('from', p_from, 'to', p_to, 'rate', rate, 'prices_include_vat', inc,
    'output', jsonb_build_object('taxable_sales', out_t, 'returns_taxable', ret_t, 'vat', out_v - ret_v, 'vat_before_returns', out_v, 'returns_vat', ret_v, 'documents', out_n, 'undecided_amount', out_u),
    'input', jsonb_build_object('taxable_purchases', in_t, 'returns_taxable', inr_t, 'vat', in_v - inr_v, 'vat_before_returns', in_v, 'returns_vat', inr_v, 'documents', in_n, 'undecided_amount', in_u),
    'net_vat_payable', (out_v - ret_v) - (in_v - inr_v), 'months', months,
    'note', 'report only: nothing is posted; items with VAT status undecided are not taxed and are shown as undecided_amount');
end $$;

-- ============================================================
-- #4 FIXED ASSETS + STRAIGHT-LINE DEPRECIATION
-- ============================================================
-- month k (1-based) of the schedule: equal parts, the last month takes the rounding remainder
create or replace function public._a53_fa_amt(p_cost numeric, p_salvage numeric, p_life int, p_k int) returns numeric language sql immutable as $$
  select case when p_k < 1 or p_k > p_life then 0
              when p_k < p_life then round((p_cost - p_salvage) / p_life, 2)
              else (p_cost - p_salvage) - round((p_cost - p_salvage) / p_life, 2) * (p_life - 1) end;
$$;

create or replace function public.fa_asset_save(p_id uuid, p_code text, p_name text, p_category text, p_loc int, p_acquired date, p_cost numeric, p_salvage numeric,
  p_life_months int, p_depr_from date, p_note text default null, p_client uuid default null, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.fa_assets; id_ uuid; df date := public._a53_mon(p_depr_from); sched numeric;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('fixed_assets_on') then raise exception 'switch_off: fixed_assets_on'; end if;
  if p_name is null or length(btrim(p_name)) = 0 or length(p_name) > 120 then raise exception 'name_required'; end if;
  if p_cost is null or p_cost <= 0 or p_cost > 1000000000000 then raise exception 'bad_amount'; end if;
  if p_salvage is null or p_salvage < 0 or p_salvage >= p_cost then raise exception 'bad_salvage'; end if;
  if p_life_months is null or p_life_months < 1 or p_life_months > 1200 then raise exception 'bad_life'; end if;
  if p_acquired is null or p_acquired < date '2000-01-01' or p_acquired > public._acct_today() + 1 then raise exception 'bad_date'; end if;
  if p_depr_from is null or df < public._a53_mon(p_acquired) then raise exception 'bad_depr_start'; end if;
  if p_loc is not null and (not exists (select 1 from public.locations where id = p_loc) or not public.can_loc(p_loc)) then raise exception 'bad_location'; end if;
  if p_category is not null and length(p_category) > 60 then raise exception 'bad_category'; end if;
  sched := public._a53_fa_amt(p_cost, p_salvage, p_life_months, 1);
  if p_dry then
    return jsonb_build_object('dry', true, 'monthly', sched, 'last_month', public._a53_fa_amt(p_cost, p_salvage, p_life_months, p_life_months), 'depr_from', df,
      'depr_to', (df + ((p_life_months - 1) || ' months')::interval)::date, 'depreciable', p_cost - p_salvage);
  end if;
  if p_id is null then
    if p_code is null or p_code !~ '^[0-9A-Za-z.\-]{1,20}$' then raise exception 'bad_code'; end if;
    if p_client is not null then
      perform public._client_lock(p_client);
      select * into a from public.fa_assets where client_id = p_client;
      if found then return jsonb_build_object('dup', true, 'id', a.id); end if;
    end if;
    if exists (select 1 from public.fa_assets where code = p_code) then raise exception 'code_taken'; end if;
    insert into public.fa_assets (client_id, code, name, category, location_id, acquired_on, cost, salvage, life_months, depr_from, note, created_by)
      values (p_client, p_code, btrim(p_name), nullif(btrim(p_category), ''), p_loc, p_acquired, p_cost, p_salvage, p_life_months, df, left(nullif(btrim(p_note), ''), 300), auth.uid()) returning id into id_;
    return jsonb_build_object('id', id_, 'monthly', sched);
  end if;
  select * into a from public.fa_assets where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if a.location_id is not null and not public.can_loc(a.location_id) then raise exception 'not allowed for this location'; end if;
  if exists (select 1 from public.fa_depr_posts where asset_id = p_id)
     and (p_cost <> a.cost or p_salvage <> a.salvage or p_life_months <> a.life_months or df <> a.depr_from or p_acquired <> a.acquired_on or p_loc is distinct from a.location_id) then
    raise exception 'depreciation_already_posted';
  end if;
  if a.status <> 'active' then raise exception 'asset_disposed'; end if;
  update public.fa_assets set name = btrim(p_name), category = nullif(btrim(p_category), ''), location_id = p_loc, acquired_on = p_acquired, cost = p_cost, salvage = p_salvage,
    life_months = p_life_months, depr_from = df, note = left(nullif(btrim(p_note), ''), 300), updated_at = now() where id = p_id;
  return jsonb_build_object('id', p_id, 'monthly', sched);
end $$;

-- retire an asset from the register: no further depreciation after the month of p_date. (No disposal journal is posted: use the manual journal for the sale / write-off.)
create or replace function public.fa_asset_dispose(p_id uuid, p_date date, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.fa_assets;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('fixed_assets_on') then raise exception 'switch_off: fixed_assets_on'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into a from public.fa_assets where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if a.status <> 'active' then raise exception 'asset_disposed'; end if;
  if p_date is null or p_date < a.acquired_on or p_date > public._acct_today() + 1 then raise exception 'bad_date'; end if;
  if exists (select 1 from public.fa_depr_posts where asset_id = p_id and month > public._a53_mon(p_date)) then raise exception 'depreciation_posted_after_date'; end if;
  update public.fa_assets set status = 'disposed', disposed_on = p_date, note = left(coalesce(note || ' | ', '') || btrim(p_note), 300), updated_at = now() where id = p_id;
  return jsonb_build_object('id', p_id, 'disposed_on', p_date);
end $$;

create or replace function public.fa_schedule(p_id uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a public.fa_assets; rows_ jsonb;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  select * into a from public.fa_assets where id = p_id;
  if not found then raise exception 'not found'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('k', k, 'month', m, 'amount', amt, 'accumulated', acc, 'book_value', a.cost - acc, 'posted', p.id is not null,
      'skipped_after_disposal', a.status = 'disposed' and m > public._a53_mon(a.disposed_on)) order by k), '[]'::jsonb) into rows_ from (
    select g k, (a.depr_from + ((g - 1) || ' months')::interval)::date m, public._a53_fa_amt(a.cost, a.salvage, a.life_months, g) amt,
      sum(public._a53_fa_amt(a.cost, a.salvage, a.life_months, g)) over (order by g) acc from generate_series(1, a.life_months) g) s
    left join public.fa_depr_posts p on p.asset_id = a.id and p.month = s.m;
  return jsonb_build_object('asset_id', a.id, 'code', a.code, 'name', a.name, 'cost', a.cost, 'salvage', a.salvage, 'life_months', a.life_months, 'method', a.method, 'status', a.status, 'rows', rows_);
end $$;

-- post depreciation for every due month up to and including p_through's month (only COMPLETED months). Idempotent on (asset, month).
create or replace function public.fa_depr_post(p_through date, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare st date := public._acct_start(); thr date; r record; list_ jsonb := '[]'::jsonb; skipped jsonb := '[]'::jsonb; n int := 0; tot numeric := 0; ent bigint; ex bigint; ac bigint; me date; sid text; done_ text[] := '{}';
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('fixed_assets_on') then raise exception 'switch_off: fixed_assets_on'; end if;
  if st is null then raise exception 'data_needed'; end if;
  if p_through is null then raise exception 'bad_date'; end if;
  thr := public._a53_mon(p_through);
  if (thr + interval '1 month')::date - 1 > public._acct_today() then raise exception 'month_not_complete'; end if;
  select account_id into ex from public.acct_mappings where key = 'depreciation';
  select account_id into ac from public.acct_mappings where key = 'accum_depr';
  if ex is null or ac is null then raise exception 'no_mapping'; end if;
  for r in
    select a.id, a.code, a.location_id, a.depr_from, a.cost, a.salvage, a.life_months, a.status, a.disposed_on, g k, (a.depr_from + ((g - 1) || ' months')::interval)::date m
    from public.fa_assets a cross join lateral generate_series(1, a.life_months) g
    where (a.depr_from + ((g - 1) || ' months')::interval)::date <= thr
      and (a.status = 'active' or (a.disposed_on is not null and (a.depr_from + ((g - 1) || ' months')::interval)::date <= public._a53_mon(a.disposed_on)))
      and (a.location_id is null or public.can_loc(a.location_id))
      and not exists (select 1 from public.fa_depr_posts p where p.asset_id = a.id and p.month = (a.depr_from + ((g - 1) || ' months')::interval)::date)
    order by 11, a.code limit 600 loop
    me := (r.m + interval '1 month')::date - 1;
    if me < st then skipped := skipped || jsonb_build_object('code', r.code, 'month', r.m, 'why', 'before_start'); continue; end if;
    if public._acct_locked(me) then skipped := skipped || jsonb_build_object('code', r.code, 'month', r.m, 'why', 'period_closed'); continue; end if;
    -- months must be posted in order for one asset
    if exists (select 1 from generate_series(1, r.k - 1) q where not exists (select 1 from public.fa_depr_posts p where p.asset_id = r.id and p.month = (r.depr_from + ((q - 1) || ' months')::interval)::date)
                 and not ((r.id::text || '_' || q::text) = any (done_))
                 and (r.depr_from + ((q - 1) || ' months')::interval)::date >= st) then
      skipped := skipped || jsonb_build_object('code', r.code, 'month', r.m, 'why', 'earlier_month_missing'); continue;
    end if;
    done_ := done_ || (r.id::text || '_' || r.k::text);
    n := n + 1; tot := tot + public._a53_fa_amt(r.cost, r.salvage, r.life_months, r.k);
    list_ := list_ || jsonb_build_object('code', r.code, 'month', r.m, 'k', r.k, 'amount', public._a53_fa_amt(r.cost, r.salvage, r.life_months, r.k));
    if not p_dry then
      sid := r.id::text || '_' || r.m::text;
      ent := public._acct_write(me, r.location_id, 'fa_depr', sid, null, 'Depreciation ' || r.code || ' ' || to_char(r.m, 'YYYY-MM'), null,
        jsonb_build_array(jsonb_build_object('account_id', ex, 'debit', public._a53_fa_amt(r.cost, r.salvage, r.life_months, r.k), 'credit', 0, 'location_id', r.location_id),
                          jsonb_build_object('account_id', ac, 'debit', 0, 'credit', public._a53_fa_amt(r.cost, r.salvage, r.life_months, r.k), 'location_id', r.location_id)), null, null, null);
      insert into public.fa_depr_posts (asset_id, month, seq, amount, entry_id, created_by) values (r.id, r.m, r.k, public._a53_fa_amt(r.cost, r.salvage, r.life_months, r.k), ent, auth.uid());
    end if;
  end loop;
  return jsonb_build_object('dry', p_dry, 'through', thr, 'count', n, 'total', tot, 'rows', list_, 'skipped', skipped);
end $$;

create or replace function public.fa_register(p_as_of date default null) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare as_ date := coalesce(p_as_of, public._acct_today());
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('fixed_assets_on'), 'as_of', as_, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name', a.name, 'category', a.category, 'location_id', a.location_id, 'acquired_on', a.acquired_on, 'cost', a.cost, 'salvage', a.salvage,
      'life_months', a.life_months, 'method', a.method, 'depr_from', a.depr_from, 'status', a.status, 'disposed_on', a.disposed_on,
      'accumulated', coalesce(p.s, 0), 'book_value', a.cost - coalesce(p.s, 0), 'months_posted', coalesce(p.n, 0), 'last_month', p.mx) order by a.code)
    from public.fa_assets a left join lateral (select sum(amount) s, count(*) n, max(month) mx from public.fa_depr_posts x where x.asset_id = a.id and x.month <= as_) p on true), '[]'::jsonb));
end $$;

-- ============================================================
-- #5 BUDGETS
-- ============================================================
-- p_rows = [{account_id, month:'YYYY-MM-01', location_id?, amount}]; dry first. Every change is logged (old -> new).
create or replace function public.budget_set(p_rows jsonb, p_note text default null, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e jsonb; a public.coa_accounts; mo date; amt numeric; lc int; old_ numeric; n_new int := 0; n_chg int := 0; n_same int := 0; ord int := 0;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('budgets_on') then raise exception 'switch_off: budgets_on'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'no_rows'; end if;
  if jsonb_array_length(p_rows) > 1000 then raise exception 'too_many_rows'; end if;
  for e in select * from jsonb_array_elements(p_rows) loop
    ord := ord + 1;
    select * into a from public.coa_accounts where id = nullif(e->>'account_id', '')::bigint;
    if not found or a.is_group or a.type not in ('income', 'expense') or not a.active then raise exception 'bad_account (row %)', ord; end if;
    if coalesce(e->>'month', '') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'bad_month (row %)', ord; end if;
    mo := public._a53_mon((e->>'month')::date);
    if mo < date '2000-01-01' or mo > public._acct_today() + 3650 then raise exception 'bad_month (row %)', ord; end if;
    if coalesce(e->>'amount', '') !~ '^\d+(\.\d+)?$' then raise exception 'bad_amount (row %)', ord; end if;
    amt := round((e->>'amount')::numeric, 2);
    if amt > 1000000000000 then raise exception 'bad_amount (row %)', ord; end if;
    lc := nullif(e->>'location_id', '')::int;
    if lc is not null and (not exists (select 1 from public.locations where id = lc) or not public.can_loc(lc)) then raise exception 'bad_location (row %)', ord; end if;
    if lc is null and not public._acct_all() then raise exception 'not allowed for this location'; end if;
    select amount into old_ from public.budgets where account_id = a.id and month = mo and coalesce(location_id, 0) = coalesce(lc, 0);
    if not found then n_new := n_new + 1; elsif old_ = amt then n_same := n_same + 1; continue; else n_chg := n_chg + 1; end if;
    if not p_dry then
      insert into public.budgets (account_id, month, location_id, amount, updated_by) values (a.id, mo, lc, amt, auth.uid())
        on conflict (account_id, month, coalesce(location_id, 0)) do update set amount = excluded.amount, updated_by = auth.uid(), updated_at = now();
      insert into public.budget_log (account_id, month, location_id, old_amount, new_amount, note, actor) values (a.id, mo, lc, old_, amt, left(nullif(btrim(p_note), ''), 200), auth.uid());
    end if;
  end loop;
  return jsonb_build_object('dry', p_dry, 'new', n_new, 'changed', n_chg, 'unchanged', n_same);
end $$;

create or replace function public.budget_list(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs();
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('budgets_on'), 'rows', coalesce((select jsonb_agg(jsonb_build_object('account_id', b.account_id, 'code', a.code, 'name_en', a.name_en, 'name_bn', a.name_bn,
      'month', b.month, 'location_id', b.location_id, 'amount', b.amount) order by a.code, b.month) from public.budgets b join public.coa_accounts a on a.id = b.account_id
      where b.month between public._a53_mon(p_from) and public._a53_mon(p_to) and (p_loc is null or b.location_id = p_loc)
        and (v_all or b.location_id = any (v_locs))), '[]'::jsonb));
end $$;

create or replace function public.budget_vs_actual(p_from date, p_to date, p_loc int default null, p_by_month boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); f date; t date; rows_ jsonb; tb_i numeric; ta_i numeric; tb_e numeric; ta_e numeric;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 800 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  f := public._a53_mon(p_from); t := (public._a53_mon(p_to) + interval '1 month')::date - 1;
  create temporary table if not exists _a53_bva (account_id bigint, m date, bud numeric, act numeric) on commit drop;
  delete from _a53_bva;
  insert into _a53_bva
  select account_id, case when p_by_month then m else null end, sum(bud), sum(act) from (
    select b.account_id, b.month m, b.amount bud, 0::numeric act from public.budgets b
      where b.month between f and t and (v_all or b.location_id = any (v_locs)) and (p_loc is null or b.location_id = p_loc)
    union all
    select l.account_id, public._a53_mon(e.entry_date), 0, case when a.type = 'income' then l.credit - l.debit else l.debit - l.credit end
      from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts a on a.id = l.account_id
      where a.type in ('income', 'expense') and e.entry_date between f and t and coalesce(e.flags, '') not like '%year_close%'
        and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)) u
  group by account_id, case when p_by_month then m else null end;
  select coalesce(jsonb_agg(jsonb_build_object('account_id', a.id, 'code', a.code, 'name_en', a.name_en, 'name_bn', a.name_bn, 'type', a.type, 'month', x.m, 'budget', x.bud, 'actual', x.act,
      'variance', case when a.type = 'income' then x.act - x.bud else x.bud - x.act end,           -- positive = good (more income / less spend)
      'pct_used', case when x.bud > 0 then round(x.act * 100 / x.bud, 1) end) order by a.code, x.m), '[]'::jsonb),
    coalesce(sum(x.bud) filter (where a.type = 'income'), 0), coalesce(sum(x.act) filter (where a.type = 'income'), 0),
    coalesce(sum(x.bud) filter (where a.type = 'expense'), 0), coalesce(sum(x.act) filter (where a.type = 'expense'), 0)
    into rows_, tb_i, ta_i, tb_e, ta_e from _a53_bva x join public.coa_accounts a on a.id = x.account_id where x.bud <> 0 or x.act <> 0;
  return jsonb_build_object('on', public.rule_on('budgets_on'), 'from', f, 'to', t, 'by_month', p_by_month, 'rows', rows_,
    'income_budget', tb_i, 'income_actual', ta_i, 'expense_budget', tb_e, 'expense_actual', ta_e, 'profit_budget', tb_i - tb_e, 'profit_actual', ta_i - ta_e);
end $$;

-- ---------- privileges ----------
revoke all on function public._a53_ro(), public._a53_nodel(), public._a53_pl(date, date, int, boolean), public._a53_mon(date), public._a53_bank_acct(bigint), public._a53_cands(bigint, int),
  public._a53_match1(bigint, bigint, int, text, text), public._a53_close_plan(date, date), public._a53_fa_amt(numeric, numeric, int, int) from public, anon, authenticated;
revoke all on function public.bank_stmt_import(bigint, jsonb, uuid, boolean), public.bank_recon_candidates(bigint, int), public.bank_recon_suggest(bigint, date, date, int),
  public.bank_recon_match(bigint, bigint, int, text), public.bank_recon_match_many(jsonb, boolean), public.bank_recon_unmatch(bigint, text), public.bank_recon_report(bigint, date, date),
  public.bank_recon_lines(bigint, text, int), public.year_close_run(date, date, text, uuid, boolean), public.year_close_reverse(bigint, text, uuid), public.year_close_list(),
  public.acct_pnl_ex_close(date, date, int), public.vat_report(date, date, int),
  public.fa_asset_save(uuid, text, text, text, int, date, numeric, numeric, int, date, text, uuid, boolean), public.fa_asset_dispose(uuid, date, text), public.fa_schedule(uuid),
  public.fa_depr_post(date, boolean), public.fa_register(date), public.budget_set(jsonb, text, boolean), public.budget_list(date, date, int), public.budget_vs_actual(date, date, int, boolean)
  from public, anon;
grant execute on function public.bank_stmt_import(bigint, jsonb, uuid, boolean), public.bank_recon_candidates(bigint, int), public.bank_recon_suggest(bigint, date, date, int),
  public.bank_recon_match(bigint, bigint, int, text), public.bank_recon_match_many(jsonb, boolean), public.bank_recon_unmatch(bigint, text), public.bank_recon_report(bigint, date, date),
  public.bank_recon_lines(bigint, text, int), public.year_close_run(date, date, text, uuid, boolean), public.year_close_reverse(bigint, text, uuid), public.year_close_list(),
  public.acct_pnl_ex_close(date, date, int), public.vat_report(date, date, int),
  public.fa_asset_save(uuid, text, text, text, int, date, numeric, numeric, int, date, text, uuid, boolean), public.fa_asset_dispose(uuid, date, text), public.fa_schedule(uuid),
  public.fa_depr_post(date, boolean), public.fa_register(date), public.budget_set(jsonb, text, boolean), public.budget_list(date, date, int), public.budget_vs_actual(date, date, int, boolean)
  to authenticated;
