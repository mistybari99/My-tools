-- Phase 96 (bos96) - W1-F / U-09: CHART AND MAPPING COMPLETENESS, expense heads, other income. Paste after phase87 (any later phase may come first), paste-twice safe.
-- Earlier phase files are not edited. No shared function is re-created here: every change to a shared function is a HOOK written in docs/integration/W1-F.md.
--
-- WHAT THIS ADDS
--   1. A seed catalogue (table w1f_seed_state) of chart accounts and mapping keys that a real shop needs: rent, utilities, marketing, other income (existing accounts 5300, 5400,
--      5500, 4900 get their mapping key), courier cash receivable 1250, staff security deposits 2700, purchase discounts 4910, rounding 5880, bad debts 5890, gain / loss on disposal
--      4920 / 5895, VAT payable 2800 and withholding tax payable 2810 (the last two inactive placeholders). An existing account is NEVER touched or overwritten: if the code is taken
--      the key stays unmapped and the owner chooses (_w1f_seed_map). Every name and mapping is editable by the owner (_w1f_seed_edit, _w1f_seed_map) and the owner can use another code (_w1f_seed_new_code: a new account takes over the key, the old one is retired when empty); each change has an audit_log line and a reason where it moves money between accounts.
--   2. Expense heads: rent, utilities and marketing are added to the list expense_heads as RETIRED rows (the 10-2 form does not offer them) until the owner turns each on with
--      _w1f_expense_head_set, which also sets the mapping key exp_<head>. Turning a head on never moves an old figure: documents older than the effective date that are still unposted
--      block it unless the owner gives a reason (audit_log + Exceptions row).
--   3. Other income (scrap, old oil, rent received, supplier discount ...): list other_income_heads, table other_income, entry _w1f_other_income_add (head, mode, money account from the
--      phase87 picker, photo), void, list. Dr cash / bank / wallet, Cr 4900 (or the head's own account). OFF until the owner switches rule other_income_on.
--   4. Mapping coverage check _w1f_mapping_coverage (unmapped key list for the Balance Check screen).
-- SETTINGS (rules; every change is written to audit_log by the rules trigger):  other_income_on (OFF)   other_income_from (blank = no start date)
-- HOOKS (not in this file, see the integration note): journal source _w1f_docs into _acct_docs, day book rows _w1f_daybook_rows into _daybook_lines, coverage line into _e_balance_check,
--   legacy wallets 1131-1134 into acct_cash_flow. Until the integrator pastes the hooks an other-income entry is recorded but not yet in the journal.

do $g$ begin
  if to_regprocedure('public._p87_present()') is null then raise exception 'phase96 needs phase87 (and 80-86) first'; end if;
  if to_regprocedure('public._m_grant_take(text,text,uuid,bigint,numeric,date,text)') is null or to_regclass('public.money_event_settings') is null then
    raise exception 'phase96 needs the money accounts of phase87';
  end if;
end $g$;

create or replace function public._w1f_present96() returns boolean language sql immutable as $$ select true $$;

-- ---------- generic helpers ----------
-- exact-text patch of a LIVE function with a marker of the caller's choice. phase87 _m_patch is a no-op on every function that already carries bos87 (all of the shared ones do),
-- so the hooks of this package use this one. Any missing patch site stops the paste and nothing is half changed. Already patched (marker present) = no-op.
create or replace function public._w1f_patch(p_fn regprocedure, p_pairs text[], p_marker text default 'bos96') returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int;
begin
  if p_marker is null or length(p_marker) < 4 then raise exception 'marker_required'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    if position(p_pairs[i] in def) = 0 then raise exception 'patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'patch of % carries no marker %', p_fn::text, p_marker; end if;
  execute def;
  return true;
end $$;

create or replace function public._w1f_audit(p_action text, p_table text, p_id text, p_detail jsonb) returns void language sql security definer set search_path = public as $$
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
  values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), p_action, p_table, p_id, p_detail) $$;

-- who may change the chart seeds and the heads: the owner (heads) and the accounts manager (seeds); a hidden button is also a refused request
create or replace function public._w1f_chart_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public._acct_manage()) $$;
create or replace function public._w1f_view_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public._acct_view()) $$;

-- a yellow line in the Exceptions list (table exceptions, the list used by void_collection) for a rule that was waived with a reason
create or replace function public._w1f_exception(p_form text, p_loc int, p_date date, p_flag text, p_amount numeric, p_text text) returns void
language plpgsql security definer set search_path = public as $$
declare lc int := coalesce(p_loc, (select min(ul.location_id) from public.user_locations ul where ul.user_id = auth.uid()), (select min(id) from public.locations));
begin
  insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
  values (null, null, p_form, lc, coalesce(p_date, public._acct_today()), p_flag, 'yellow', p_amount, jsonb_build_object('bn', p_text, 'en', p_text));
end $$;

-- ---------- settings ----------
insert into public.rules (key, module, kind, default_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('other_income_on', 'books', 'switch', 'false', 'Other income entry (scrap, old oil, rent received)', 'Other income entry (scrap, old oil, rent received)', 'Other income entry (scrap, old oil, rent received)',
  'OFF = the Other income screen refuses entries', 'OFF (default) = the Other income screen refuses entries. ON = staff with the cash move permission can record money that is not a sale, posted to Other income.', 960),
 ('other_income_from', 'books', 'text', null, 'Other income counts from this date', 'Other income counts from this date', 'Other income counts from this date (YYYY-MM-DD)',
  'Blank = any date', 'Blank = any date. When set, an entry dated before it is refused, so an old month never changes.', 961)
on conflict (key) do nothing;

-- ---------- the seed catalogue ----------
create table if not exists public.w1f_seed_state (
  key text primary key,                                   -- mapping key
  code text not null,                                     -- proposed chart code (the account may be recoded by the owner later)
  name_en text not null, name_bn text not null,
  type text not null check (type in ('asset', 'liability', 'equity', 'income', 'expense')),
  parent_code text,
  purpose text not null,
  placeholder boolean not null default false,             -- created inactive
  existing boolean not null default false,                -- the account is one of the standard chart accounts: only the mapping key is added
  ord int not null default 100,
  status text not null default 'pending' check (status in ('pending', 'created', 'mapped_existing', 'owner_mapping_kept', 'code_taken', 'type_mismatch', 'history_exists')),
  account_id bigint references public.coa_accounts(id),
  note text,
  seeded_at timestamptz
);
insert into public.w1f_seed_state (key, code, name_en, name_bn, type, parent_code, purpose, placeholder, existing, ord) values
 ('exp_rent', '5300', 'Rent', 'Rent', 'expense', null, 'Rent paid for shops, factory and stores', false, true, 10),
 ('exp_utilities', '5400', 'Utilities', 'Utilities', 'expense', null, 'Electricity, gas, water and internet', false, true, 20),
 ('exp_marketing', '5500', 'Marketing', 'Marketing', 'expense', null, 'Advertising, printing and promotions', false, true, 30),
 ('other_income', '4900', 'Other income', 'Other income', 'income', null, 'Scrap, old oil, rent received and other money that is not a sale', false, true, 40),
 ('courier_receivable', '1250', 'Courier cash receivable', 'Courier cash receivable', 'asset', '1200', 'Cash on delivery collected by couriers and delivery platforms, not yet handed over', false, false, 50),
 ('staff_deposit', '2700', 'Staff security deposits', 'Staff security deposits', 'liability', '2000', 'Deposits held from staff and owed back to them', false, false, 60),
 ('purchase_discount', '4910', 'Purchase discounts received', 'Purchase discounts received', 'income', '4000', 'Discounts and rebates given by suppliers', false, false, 70),
 ('rounding', '5880', 'Rounding differences', 'Rounding differences', 'expense', null, 'Small rounding differences', false, false, 80),
 ('bad_debt', '5890', 'Bad debts written off', 'Bad debts written off', 'expense', null, 'Customer dues the owner has decided will not be paid', false, false, 90),
 ('disposal_gain', '4920', 'Gain on disposal of fixed assets', 'Gain on disposal of fixed assets', 'income', '4000', 'Profit when a fixed asset is sold above its book value', false, false, 100),
 ('disposal_loss', '5895', 'Loss on disposal of fixed assets', 'Loss on disposal of fixed assets', 'expense', null, 'Loss when a fixed asset is sold below its book value', false, false, 110),
 ('vat_payable', '2800', 'VAT payable (not in use yet)', 'VAT payable (not in use yet)', 'liability', '2000', 'Placeholder for VAT. Inactive until the owner and the adviser decide', true, false, 120),
 ('wht_payable', '2810', 'Withholding tax payable (not in use yet)', 'Withholding tax payable (not in use yet)', 'liability', '2000', 'Placeholder for withholding tax. Inactive until the owner and the adviser decide', true, false, 130)
on conflict (key) do nothing;

-- unposted documents that use an expense head and are dated before p_before (null = any date). Posted documents are in the journal already and never move.
create or replace function public._w1f_head_unposted(p_code text, p_before date default null) returns bigint language sql stable security definer set search_path = public as $$
  select (select count(*) from public.entries e
           where e.form_code = '10-2' and e.status in ('submitted', 'approved') and (p_before is null or e.entry_date < p_before)
             and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) x
                          where regexp_replace(lower(coalesce(nullif(btrim(x ->> 'head'), ''), 'other')), '[^a-z0-9_]', '_', 'g') = p_code and public._acct_num(x ->> 'amount') > 0)
             and not exists (select 1 from public.journal_entries j where j.source_type = 'expense_voucher' and j.source_id like e.id::text || ':%' and j.reverses_id is null))
       + (select count(*) from public.quick_expenses q
           where q.head = p_code and q.status = 'done' and (p_before is null or q.exp_date < p_before)
             and not exists (select 1 from public.journal_entries j where j.source_type = 'quick_expense' and j.source_id = q.id::text and j.reverses_id is null)) $$;

-- one pass over the catalogue. Never overwrites: an existing account, an existing mapping key or a taken code is left exactly as it is.
create or replace function public._w1f_seed_run() returns int language plpgsql security definer set search_path = public as $$
declare r public.w1f_seed_state; a public.coa_accounts; m public.acct_mappings; par public.coa_accounts; n int := 0; nid bigint; st text; nt text;
begin
  for r in select * from public.w1f_seed_state where status in ('pending', 'code_taken', 'type_mismatch', 'history_exists') order by ord, key loop
    st := null; nt := null; nid := null;
    select * into m from public.acct_mappings where key = r.key;
    if found then
      st := 'owner_mapping_kept'; nid := m.account_id; nt := 'the key was already mapped; left as it is';
    else
      select * into a from public.coa_accounts where code = r.code;
      if found and r.existing then
        if a.type <> r.type or a.is_group then st := 'type_mismatch'; nt := 'code ' || r.code || ' exists with another type; the owner chooses the account';
        elsif r.key like 'exp\_%' and public._w1f_head_unposted(substring(r.key from 5), null) > 0 then st := 'history_exists'; nt := 'unposted documents already use this head; map it with a reason';
        else
          insert into public.acct_mappings (key, account_id, label_bn, label_en) values (r.key, a.id, r.name_en, r.purpose);
          st := 'mapped_existing'; nid := a.id;
        end if;
      elsif found then
        st := 'code_taken'; nt := 'code ' || r.code || ' is used by another account; the owner chooses the account';
      else
        select * into par from public.coa_accounts where code = r.parent_code and is_group and type = r.type;
        insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, parent_id, is_group, is_system, active, sort)
          values (r.code, r.name_bn, r.name_en, r.type, case when r.type in ('asset', 'expense') then 'debit' else 'credit' end, par.id, false, false, not r.placeholder, 600 + r.ord)
          returning * into a;
        insert into public.acct_mappings (key, account_id, label_bn, label_en) values (r.key, a.id, r.name_en, r.purpose);
        st := 'created'; nid := a.id;
      end if;
    end if;
    if st is distinct from r.status or nid is distinct from r.account_id then
      update public.w1f_seed_state set status = st, account_id = nid, note = nt, seeded_at = now() where key = r.key;
      perform public._w1f_audit('w1f_seed', 'w1f_seed_state', r.key, jsonb_build_object('status', st, 'code', r.code, 'account_id', nid, 'note', nt));
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;

-- ---------- lists: other income heads (new list) and the three expense heads (retired until the owner turns them on) ----------
insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort, active, extra) values
 ('other_income_heads', 'scrap_sale', 'Scrap and packaging sale', 'Scrap and packaging sale', 'Scrap and packaging sale', 10, true, '{}'),
 ('other_income_heads', 'old_oil', 'Used cooking oil sale', 'Used cooking oil sale', 'Used cooking oil sale', 20, true, '{}'),
 ('other_income_heads', 'rent_received', 'Rent received', 'Rent received', 'Rent received', 30, true, '{}'),
 ('other_income_heads', 'supplier_discount', 'Supplier discount received in cash', 'Supplier discount received in cash', 'Supplier discount received in cash', 40, true, '{}'),
 ('other_income_heads', 'other', 'Other (write it)', 'Other (write it)', 'Other (write it)', 90, true, '{}')
on conflict (list_code, value_code) do nothing;
insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort, active, extra) values
 ('expense_heads', 'rent', 'Rent', 'Rent', 'Rent', 110, false, '{"w1f_seed": true}'),
 ('expense_heads', 'utilities', 'Utilities (electricity, gas, water)', 'Utilities (electricity, gas, water)', 'Utilities (electricity, gas, water)', 120, false, '{"w1f_seed": true}'),
 ('expense_heads', 'marketing', 'Marketing and advertising', 'Marketing and advertising', 'Marketing and advertising', 130, false, '{"w1f_seed": true}')
on conflict (list_code, value_code) do nothing;

select public._w1f_seed_run();
-- the supplier discount head books to the purchase discount account (only when that key exists and the head key does not)
insert into public.acct_mappings (key, account_id, label_bn, label_en)
select 'oi_supplier_discount', m.account_id, 'Other income: supplier discount', 'Other income head: supplier discount' from public.acct_mappings m
 where m.key = 'purchase_discount' and not exists (select 1 from public.acct_mappings x where x.key = 'oi_supplier_discount');

-- ---------- reports for the screen ----------
create or replace function public._w1f_seed_report() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._w1f_view_ok() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('key', s.key, 'proposed_code', s.code, 'purpose', s.purpose, 'status', s.status, 'placeholder', s.placeholder, 'note', s.note,
      'type', s.type, 'mapped', m.account_id is not null, 'account_id', c.id, 'code', c.code, 'name_en', c.name_en, 'name_bn', c.name_bn, 'active', c.active,
      'has_lines', c.id is not null and exists (select 1 from public.journal_lines l where l.account_id = c.id)) order by s.ord)
    from public.w1f_seed_state s left join public.acct_mappings m on m.key = s.key left join public.coa_accounts c on c.id = m.account_id), '[]'::jsonb);
end $$;

-- the owner (or the accounts manager) edits a seeded account: names and active. The chart CODE of an account never changes (phase40 guard, BUILD-RULES: a code is never given to anything else);
-- to use another code the owner calls _w1f_seed_new_code below, which opens a new account and retires the old one when it is empty.
create or replace function public._w1f_seed_edit(p_key text, p_name_en text default null, p_name_bn text default null, p_active boolean default null, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.w1f_seed_state; a public.coa_accounts; bal numeric; why text := nullif(btrim(coalesce(p_reason, '')), ''); changed jsonb := '{}';
begin
  if not public._w1f_chart_ok() then raise exception 'not allowed'; end if;
  select * into s from public.w1f_seed_state where key = p_key;
  if not found then raise exception 'unknown_key'; end if;
  select c.* into a from public.acct_mappings m join public.coa_accounts c on c.id = m.account_id where m.key = p_key for update of c;
  if not found then raise exception 'not_mapped'; end if;
  if p_name_en is not null and (length(btrim(p_name_en)) not between 1 and 120) then raise exception 'name_required'; end if;
  if p_name_bn is not null and (length(btrim(p_name_bn)) not between 1 and 120) then raise exception 'name_required'; end if;
  if p_active is not null and p_active is distinct from a.active then
    if p_active then
      if a.parent_id is not null and not exists (select 1 from public.coa_accounts p where p.id = a.parent_id and p.active) then raise exception 'parent_inactive'; end if;
    else
      select coalesce(sum(l.debit - l.credit), 0) into bal from public.journal_lines l where l.account_id = a.id;
      if abs(bal) > 0.004 then raise exception 'account_has_balance'; end if;
      if why is null or length(why) < 3 then raise exception 'reason_required'; end if;
    end if;
    changed := changed || jsonb_build_object('active', jsonb_build_array(a.active, p_active));
  end if;
  if p_name_en is not null and btrim(p_name_en) is distinct from a.name_en then changed := changed || jsonb_build_object('name_en', jsonb_build_array(a.name_en, btrim(p_name_en))); end if;
  if p_name_bn is not null and btrim(p_name_bn) is distinct from a.name_bn then changed := changed || jsonb_build_object('name_bn', jsonb_build_array(a.name_bn, btrim(p_name_bn))); end if;
  if changed = '{}'::jsonb then return jsonb_build_object('key', p_key, 'changed', false); end if;
  update public.coa_accounts set name_en = coalesce(nullif(btrim(p_name_en), ''), name_en), name_bn = coalesce(nullif(btrim(p_name_bn), ''), name_bn), active = coalesce(p_active, active) where id = a.id;
  perform public._w1f_audit('w1f_seed_edit', 'coa_accounts', a.id::text, jsonb_build_object('key', p_key, 'changes', changed, 'reason', why));
  return jsonb_build_object('key', p_key, 'changed', true, 'account_id', a.id);
end $$;

-- "use another code": a new account with the owner's code (same type and parent as the seed) takes over the key from now on. The old account is retired when it has no journal lines and
-- stays active when it has (its history is never moved). Works also for a key whose proposed code was taken (no account yet). Reason required when the key already pointed at an account.
create or replace function public._w1f_seed_new_code(p_key text, p_code text, p_name_en text default null, p_name_bn text default null, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.w1f_seed_state; old public.coa_accounts; par public.coa_accounts; nw public.coa_accounts; why text := nullif(btrim(coalesce(p_reason, '')), ''); nm_en text; nm_bn text; retired boolean := false;
begin
  if not public._w1f_chart_ok() then raise exception 'not allowed'; end if;
  select * into s from public.w1f_seed_state where key = p_key for update;
  if not found then raise exception 'unknown_key'; end if;
  if p_code is null or p_code !~ '^[0-9A-Za-z.\-]{1,12}$' then raise exception 'bad_code'; end if;
  if exists (select 1 from public.coa_accounts where code = p_code) then raise exception 'code_taken'; end if;
  select c.* into old from public.acct_mappings m join public.coa_accounts c on c.id = m.account_id where m.key = p_key;
  if old.id is not null and (why is null or length(why) < 3) then raise exception 'reason_required'; end if;
  nm_en := left(coalesce(nullif(btrim(p_name_en), ''), old.name_en, s.name_en), 120);
  nm_bn := left(coalesce(nullif(btrim(p_name_bn), ''), old.name_bn, s.name_bn), 120);
  select * into par from public.coa_accounts where id = coalesce(old.parent_id, (select id from public.coa_accounts where code = s.parent_code and is_group and type = s.type));
  insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, parent_id, is_group, is_system, active, sort)
    values (p_code, nm_bn, nm_en, s.type, case when s.type in ('asset', 'expense') then 'debit' else 'credit' end, par.id, false, false, true, 600 + s.ord) returning * into nw;
  insert into public.acct_mappings (key, account_id, label_bn, label_en, updated_by) values (p_key, nw.id, s.name_en, s.purpose, auth.uid())
    on conflict (key) do update set account_id = excluded.account_id, updated_by = auth.uid(), updated_at = now();
  if old.id is not null and not old.is_system and not exists (select 1 from public.journal_lines l where l.account_id = old.id)
     and not exists (select 1 from public.money_accounts x where x.coa_account_id = old.id) then
    update public.coa_accounts set active = false where id = old.id; retired := true;
  end if;
  update public.w1f_seed_state set status = 'owner_mapping_kept', account_id = nw.id, note = 'owner chose code ' || p_code, seeded_at = now() where key = p_key;
  perform public._w1f_audit('w1f_seed_new_code', 'coa_accounts', nw.id::text, jsonb_build_object('key', p_key, 'old_account', old.id, 'old_code', old.code, 'new_code', p_code, 'old_retired', retired, 'reason', why));
  if old.id is not null then perform public._w1f_exception('ACCOUNTS', null, null, 'chart_code_replaced', null, 'Key ' || p_key || ' moved from ' || old.code || ' to ' || p_code || ' (' || why || ')'); end if;
  return jsonb_build_object('key', p_key, 'account_id', nw.id, 'code', p_code, 'old_retired', retired);
end $$;

-- point a seeded key at an account the owner chooses (used when the proposed code was taken, or to change where a key books). Future postings only: the journal is never rewritten.
create or replace function public._w1f_seed_map(p_key text, p_account_code text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.w1f_seed_state; a public.coa_accounts; m public.acct_mappings; why text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public._w1f_chart_ok() then raise exception 'not allowed'; end if;
  select * into s from public.w1f_seed_state where key = p_key;
  if not found then raise exception 'unknown_key'; end if;
  select * into a from public.coa_accounts where code = p_account_code;
  if not found or a.is_group then raise exception 'bad_account'; end if;
  if a.type <> s.type then raise exception 'wrong_account_type'; end if;
  if not a.active and not s.placeholder then raise exception 'bad_account'; end if;
  select * into m from public.acct_mappings where key = p_key;
  if found and m.account_id = a.id then return jsonb_build_object('key', p_key, 'changed', false); end if;
  if found and (why is null or length(why) < 3) then raise exception 'reason_required'; end if;
  if s.key like 'exp\_%' and public._w1f_head_unposted(substring(s.key from 5), null) > 0 and (why is null or length(why) < 3) then raise exception 'older_documents_unposted'; end if;
  insert into public.acct_mappings (key, account_id, label_bn, label_en, updated_by) values (p_key, a.id, s.name_en, s.purpose, auth.uid())
    on conflict (key) do update set account_id = excluded.account_id, updated_by = auth.uid(), updated_at = now();
  update public.w1f_seed_state set status = case when status in ('created', 'mapped_existing') then status else 'owner_mapping_kept' end, account_id = a.id, note = 'mapped by the owner', seeded_at = now() where key = p_key;
  perform public._w1f_audit('w1f_seed_map', 'acct_mappings', p_key, jsonb_build_object('from', m.account_id, 'to', a.id, 'code', a.code, 'reason', why));
  if why is not null then perform public._w1f_exception('ACCOUNTS', null, null, 'chart_mapping_changed', null, 'Mapping ' || p_key || ' set to ' || a.code || ' (' || why || ')'); end if;
  return jsonb_build_object('key', p_key, 'changed', true, 'account_id', a.id);
end $$;

-- ---------- expense heads ----------
create or replace function public._w1f_expense_heads() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._w1f_view_ok() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('code', o.value_code, 'label_en', o.label_en, 'label_bn', o.label_bn, 'active', o.active, 'seeded', coalesce((o.extra ->> 'w1f_seed')::boolean, false),
      'effective_from', o.extra ->> 'effective_from', 'key', 'exp_' || o.value_code, 'mapped', m.account_id is not null, 'account_code', c.code, 'account_name', c.name_en,
      'unposted', public._w1f_head_unposted(o.value_code, null)) order by o.sort, o.value_code)
    from public.option_lists o left join public.acct_mappings m on m.key = 'exp_' || o.value_code left join public.coa_accounts c on c.id = m.account_id where o.list_code = 'expense_heads'), '[]'::jsonb);
end $$;

-- turn a head on / off or edit it (owner only). On: the option row is active and the key exp_<code> books to the chosen expense account. An unposted older document blocks it unless a reason is given.
create or replace function public._w1f_expense_head_set(p_code text, p_label_en text default null, p_label_bn text default null, p_account_code text default null, p_active boolean default true,
  p_effective_from date default null, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.option_lists; a public.coa_accounts; m public.acct_mappings; why text := nullif(btrim(coalesce(p_reason, '')), ''); eff date := coalesce(p_effective_from, public._acct_today()); n bigint; nm_changed boolean := false;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if p_code is null or p_code !~ '^[a-z][a-z0-9_]{1,30}$' then raise exception 'bad_head'; end if;
  select * into o from public.option_lists where list_code = 'expense_heads' and value_code = p_code for update;
  if not found and (p_label_en is null or length(btrim(p_label_en)) < 1) then raise exception 'name_required'; end if;
  if p_account_code is not null then
    select * into a from public.coa_accounts where code = p_account_code;
    if not found or a.is_group or a.type <> 'expense' or not a.active then raise exception 'bad_account'; end if;
  end if;
  select * into m from public.acct_mappings where key = 'exp_' || p_code;
  if coalesce(p_active, true) then
    if not found and a.id is null then raise exception 'account_required'; end if;
    if a.id is not null and (not found or m.account_id <> a.id) then
      n := public._w1f_head_unposted(p_code, eff);
      if n > 0 and (why is null or length(why) < 3) then raise exception 'older_documents_unposted' using detail = n::text || ' unposted document(s) dated before ' || eff::text; end if;
      insert into public.acct_mappings (key, account_id, label_bn, label_en, updated_by) values ('exp_' || p_code, a.id, coalesce(nullif(btrim(p_label_bn), ''), nullif(btrim(p_label_en), ''), p_code), 'Expense head: ' || p_code, auth.uid())
        on conflict (key) do update set account_id = excluded.account_id, updated_by = auth.uid(), updated_at = now();
      if n > 0 then perform public._w1f_exception('10-2', null, eff, 'expense_head_history', n, 'Head ' || p_code || ' mapped with ' || n::text || ' older unposted document(s): ' || why); end if;
    end if;
  elsif (why is null or length(why) < 3) then raise exception 'reason_required';
  end if;
  if o.list_code is null then
    insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort, active, extra)
      values ('expense_heads', p_code, coalesce(nullif(btrim(p_label_bn), ''), btrim(p_label_en)), btrim(p_label_en), btrim(p_label_en),
              coalesce((select max(sort) from public.option_lists where list_code = 'expense_heads'), 0) + 10, coalesce(p_active, true), jsonb_build_object('effective_from', eff::text));
  else
    update public.option_lists set label_en = coalesce(nullif(btrim(p_label_en), ''), label_en), label_mix = coalesce(nullif(btrim(p_label_en), ''), label_mix), label_bn = coalesce(nullif(btrim(p_label_bn), ''), nullif(btrim(p_label_en), ''), label_bn),
      active = coalesce(p_active, active), retired_reason = case when coalesce(p_active, true) then null else left(why, 300) end,
      extra = case when coalesce(p_active, true) then extra || jsonb_build_object('effective_from', eff::text) else extra end
     where list_code = 'expense_heads' and value_code = p_code;
  end if;
  perform public._w1f_audit('w1f_expense_head_set', 'option_lists', 'expense_heads:' || p_code,
    jsonb_build_object('active', coalesce(p_active, true), 'account', a.code, 'effective_from', eff, 'unposted_older', n, 'reason', why));
  return jsonb_build_object('code', p_code, 'active', coalesce(p_active, true), 'account_code', a.code);
end $$;

-- ---------- other income heads ----------
create or replace function public._w1f_other_income_heads() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('code', o.value_code, 'label_en', o.label_en, 'active', o.active, 'key', 'oi_' || o.value_code, 'own_account', m.account_id is not null,
      'account_code', coalesce(c.code, c0.code), 'account_name', coalesce(c.name_en, c0.name_en)) order by o.sort, o.value_code)
    from public.option_lists o left join public.acct_mappings m on m.key = 'oi_' || o.value_code left join public.coa_accounts c on c.id = m.account_id
    left join public.acct_mappings m0 on m0.key = 'other_income' left join public.coa_accounts c0 on c0.id = m0.account_id where o.list_code = 'other_income_heads'), '[]'::jsonb);
end $$;

create or replace function public._w1f_other_income_head_set(p_code text, p_label_en text default null, p_label_bn text default null, p_account_code text default null, p_active boolean default true, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.option_lists; a public.coa_accounts; why text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if p_code is null or p_code !~ '^[a-z][a-z0-9_]{1,30}$' then raise exception 'bad_head'; end if;
  select * into o from public.option_lists where list_code = 'other_income_heads' and value_code = p_code for update;
  if not found and (p_label_en is null or length(btrim(p_label_en)) < 1) then raise exception 'name_required'; end if;
  if p_account_code is not null then
    select * into a from public.coa_accounts where code = p_account_code;
    if not found or a.is_group or a.type <> 'income' or not a.active then raise exception 'bad_account'; end if;
    insert into public.acct_mappings (key, account_id, label_bn, label_en, updated_by) values ('oi_' || p_code, a.id, 'Other income: ' || p_code, 'Other income head: ' || p_code, auth.uid())
      on conflict (key) do update set account_id = excluded.account_id, updated_by = auth.uid(), updated_at = now();
  end if;
  if not coalesce(p_active, true) and (why is null or length(why) < 3) then raise exception 'reason_required'; end if;
  if o.list_code is null then
    insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort, active)
      values ('other_income_heads', p_code, coalesce(nullif(btrim(p_label_bn), ''), btrim(p_label_en)), btrim(p_label_en), btrim(p_label_en),
              coalesce((select max(sort) from public.option_lists where list_code = 'other_income_heads' and value_code <> 'other'), 0) + 10, coalesce(p_active, true));
  else
    update public.option_lists set label_en = coalesce(nullif(btrim(p_label_en), ''), label_en), label_mix = coalesce(nullif(btrim(p_label_en), ''), label_mix), label_bn = coalesce(nullif(btrim(p_label_bn), ''), nullif(btrim(p_label_en), ''), label_bn),
      active = coalesce(p_active, active), retired_reason = case when coalesce(p_active, true) then null else left(why, 300) end
     where list_code = 'other_income_heads' and value_code = p_code;
  end if;
  perform public._w1f_audit('w1f_other_income_head_set', 'option_lists', 'other_income_heads:' || p_code, jsonb_build_object('active', coalesce(p_active, true), 'account', a.code, 'reason', why));
  return jsonb_build_object('code', p_code, 'active', coalesce(p_active, true), 'account_code', a.code);
end $$;

-- ---------- money source for an incoming payment (shared by other income here and by the customer receipts of phase97) ----------
-- Same rules as the phase87 payment source trigger (default account of the event, owner fixed source, require source, place, one-off owner exceptions), without needing the shared _m_event patch.
-- Returns the account to use (null = none, behave as before) and the payment mode that follows the account.
create or replace function public._w1f_pick_source(p_event text, p_acc bigint, p_loc int, p_mode text, p_amt numeric, p_client uuid, p_date date, p_ref text, out o_acc bigint, out o_mode text)
language plpgsql security definer set search_path = public as $$
declare st public.money_event_settings; a public.money_accounts; usr boolean := auth.uid() is not null; dflt boolean := false;
begin
  o_acc := null; o_mode := p_mode;
  select * into st from public.money_event_settings where event_type = p_event;
  if not found then raise exception 'unknown_event'; end if;
  o_acc := p_acc;
  if o_acc is null and st.default_account_id is not null then
    select * into a from public.money_accounts where id = st.default_account_id and active;
    if found and (p_mode is null or p_mode = public._m_mode_of_kind(a.kind) or (a.kind = 'bank' and p_mode = 'card')) and (a.location_id is null or p_loc is null or a.location_id = p_loc) then
      o_acc := a.id; dflt := true;
    end if;
  end if;
  if o_acc is null then
    if st.require_source and usr and not public._m_grant_take('require_source', p_event, p_client, null, p_amt, p_date, p_ref) then raise exception 'money_source_required'; end if;
    return;
  end if;
  select * into a from public.money_accounts where id = o_acc;
  if not found then raise exception 'unknown_money_account'; end if;
  if not a.active then raise exception 'money_account_inactive'; end if;
  if usr and not dflt and st.default_account_id is not null and o_acc <> st.default_account_id and not st.allow_override
     and not public._m_grant_take('override', p_event, p_client, o_acc, p_amt, p_date, p_ref) then raise exception 'money_source_fixed'; end if;
  if usr and a.location_id is not null and p_loc is not null and a.location_id <> p_loc and not public._m_grant_take('override', p_event, p_client, o_acc, p_amt, p_date, p_ref) then
    raise exception 'money_account_place';
  end if;
  o_mode := public._m_mode_of_kind(a.kind);
end $$;

insert into public.money_event_settings (event_type, label_en, dir, sort) values ('other_income', 'Other income received (not a sale)', 'in', 150) on conflict (event_type) do nothing;

-- ---------- other income: table, entry, void, list ----------
create table if not exists public.other_income (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  location_id int not null references public.locations(id),
  income_date date not null,
  head text not null,                                     -- value_code of the list other_income_heads (the id, never the label)
  amount numeric not null check (amount > 0 and amount <= 1000000000),
  mode text not null check (mode in ('cash', 'mobile', 'bank')),
  money_account_id bigint references public.money_accounts(id),
  received_from text check (received_from is null or length(received_from) <= 120),
  ref text check (ref is null or length(ref) <= 80),
  note text check (note is null or length(note) <= 300),
  photo text check (photo is null or (length(photo) <= 300 and photo not like '%..%')),
  status text not null default 'done' check (status in ('done', 'void')),
  void_by uuid, void_at timestamptz, void_note text,
  created_by uuid, created_staff text, created_at timestamptz not null default now()
);
create index if not exists other_income_d on public.other_income (income_date);
alter table public.other_income enable row level security;
revoke all on public.other_income from public, anon, authenticated;
drop trigger if exists other_income_nodel on public.other_income;
create trigger other_income_nodel before delete on public.other_income for each row execute function public.no_hard_delete();
drop trigger if exists audit_other_income on public.other_income;
create trigger audit_other_income after insert or update on public.other_income for each row execute function public.log_change('id');
drop trigger if exists other_income_money_bu on public.other_income;
create or replace function public._w1f_oi_bu() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.money_account_id is distinct from old.money_account_id or new.amount is distinct from old.amount or new.head is distinct from old.head or new.income_date is distinct from old.income_date
     or new.mode is distinct from old.mode or new.location_id is distinct from old.location_id then raise exception 'other_income_fixed'; end if;
  return new;
end $$;
create trigger other_income_money_bu before update on public.other_income for each row execute function public._w1f_oi_bu();

create or replace function public._w1f_other_income_add(p_loc int, p_date date, p_head text, p_amount numeric, p_mode text, p_money_account bigint default null, p_received_from text default null,
  p_ref text default null, p_note text default null, p_photo text default null, p_client uuid default null, p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare today date := (now() at time zone 'Asia/Dhaka')::date; d date := coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date); r public.other_income; sid text; amt numeric := round(p_amount, 2);
  src record; frm text := public.rule_txt('other_income_from'); md text;
begin
  if not public.is_active() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if not (public.is_owner() or public._acct_manage() or public.has_grant('cash_move', p_loc)) then raise exception 'not allowed'; end if;
  if not public.rule_on('other_income_on') then raise exception 'other_income_off'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if p_head is null or not exists (select 1 from public.option_lists where list_code = 'other_income_heads' and value_code = p_head and active) then raise exception 'bad_head'; end if;
  if amt is null or not (amt between 0.01 and 1000000000) then raise exception 'bad_amount'; end if;
  if p_mode is null or p_mode not in ('cash', 'mobile', 'bank') then raise exception 'bad_mode'; end if;
  if d < date '2000-01-01' or d > today + 1 then raise exception 'bad_date'; end if;
  if frm is not null and frm ~ '^\d{4}-\d{2}-\d{2}$' and d < frm::date then raise exception 'before_start_date' using detail = frm; end if;
  if p_photo is not null and (length(p_photo) > 300 or p_photo like '%..%') then raise exception 'bad_photo'; end if;
  perform public.lock_check(d);
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.other_income where client_id = p_client;
    if found then
      if r.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', r.id);
    end if;
  end if;
  select * into src from public._w1f_pick_source('other_income', p_money_account, p_loc, p_mode, amt, p_client, d, 'other_income');
  md := coalesce(src.o_mode, p_mode);
  if p_dry then return jsonb_build_object('dry', true, 'amount', amt, 'mode', md, 'money_account_id', src.o_acc, 'date', d, 'head', p_head); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.other_income (client_id, location_id, income_date, head, amount, mode, money_account_id, received_from, ref, note, photo, created_by, created_staff)
    values (p_client, p_loc, d, p_head, amt, md, src.o_acc, left(nullif(btrim(p_received_from), ''), 120), left(nullif(btrim(p_ref), ''), 80), left(nullif(btrim(p_note), ''), 300), nullif(btrim(p_photo), ''), auth.uid(), sid)
    returning * into r;
  return jsonb_build_object('id', r.id, 'amount', r.amount, 'mode', r.mode, 'money_account_id', r.money_account_id);
end $$;

create or replace function public._w1f_other_income_void(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.other_income;
begin
  select * into r from public.other_income where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not (public.is_owner() or public._acct_manage() or (r.created_by = auth.uid() and r.income_date = public._acct_today() and public.can_loc(r.location_id))) then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  if r.status = 'void' then return jsonb_build_object('id', r.id, 'noop', true); end if;
  perform public.lock_check(r.income_date);
  update public.other_income set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = r.id;
  return jsonb_build_object('id', r.id, 'status', 'void');
end $$;

create or replace function public._w1f_other_income_list(p_loc int default null, p_from date default null, p_to date default null, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not (public.is_owner() or public._acct_view() or public._acct_manage() or public.has_grant('cash_move', p_loc)) then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return jsonb_build_object('on', public.rule_on('other_income_on'), 'from', public.rule_txt('other_income_from'), 'rows', coalesce((select jsonb_agg(to_jsonb(z) order by z.income_date desc, z.created_at desc) from (
      select o.id, o.location_id, o.income_date, o.head, h.label_en as head_label, o.amount, o.mode, o.money_account_id, a.name_en as account_name, o.received_from, o.ref, o.note, o.photo, o.status, o.void_note, o.created_staff, o.created_at
        from public.other_income o left join public.option_lists h on h.list_code = 'other_income_heads' and h.value_code = o.head left join public.money_accounts a on a.id = o.money_account_id
       where (p_loc is null or o.location_id = p_loc) and o.income_date between coalesce(p_from, date '2000-01-01') and coalesce(p_to, date '2100-01-01') and (public.is_owner() or public._acct_view() or public.can_loc(o.location_id))
       order by o.income_date desc, o.created_at desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) z), '[]'::jsonb));
end $$;

-- ---------- journal source and day book rows (HOOKED in by the integrator, see the note) ----------
create or replace function public._w1f_docs(p_start date)
returns table(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  -- other income: Dr the cash / bank / wallet account the money went to, Cr the head's own account (key oi_<head>) or Other income
  return query
  select 'other_income'::text, o.id::text, o.income_date, o.location_id, ('Other income: ' || o.head)::text, null::text, o.status = 'done',
    coalesce((o.void_at at time zone 'Asia/Dhaka')::date, public._acct_today()), null::text, null::text,
    case when o.status = 'done' then jsonb_build_array(
      jsonb_build_object('a', public._m_key(o.money_account_id, public._acct_paykey(o.mode)), 'd', o.amount),
      jsonb_build_object('a', case when exists (select 1 from public.acct_mappings m where m.key = 'oi_' || o.head) then 'oi_' || o.head else 'other_income' end, 'c', o.amount)) end
  from public.other_income o
  where o.income_date >= p_start and public._acct_need('other_income', o.id::text, o.status = 'done');
end $$;

create or replace function public._w1f_daybook_rows(p_locs int[], p_from date, p_to date)
returns table(loc integer, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamp with time zone, src text, src_id text, internal boolean, sensitive boolean)
language sql stable security definer set search_path = public as $$
  select o.location_id, o.income_date, 'in'::text, o.mode, 'other_income'::text, o.amount, o.ref,
         nullif(btrim(concat_ws(' · ', coalesce(h.label_en, o.head), o.received_from, a.name_en, o.note)), ''), o.created_staff, o.created_at, 'other_income'::text, o.id::text, false, false
    from public.other_income o left join public.option_lists h on h.list_code = 'other_income_heads' and h.value_code = o.head left join public.money_accounts a on a.id = o.money_account_id
   where o.status = 'done' and o.location_id = any (p_locs) and o.income_date between p_from and p_to $$;

-- ---------- mapping coverage ----------
create or replace function public._w1f_mapping_coverage() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare rows_ jsonb := '[]'; bad int := 0; r record; core text[] := array['sales', 'sales_discount', 'sales_returns', 'receivable', 'payable', 'pay_cash', 'pay_bank', 'pay_mobile', 'pay_card', 'cogs',
    'inv_finished', 'inv_raw', 'inv_pack', 'owner_capital', 'owner_drawings', 'exp_other', 'other_income'];
begin
  if not public._w1f_view_ok() then raise exception 'not allowed'; end if;
  for r in select k as key, 'core' as kind from unnest(core) k loop
    if not exists (select 1 from public.acct_mappings m join public.coa_accounts c on c.id = m.account_id where m.key = r.key and c.active) then bad := bad + 1; rows_ := rows_ || jsonb_build_object('kind', r.kind, 'key', r.key, 'problem', 'not mapped to an active account'); end if;
  end loop;
  for r in select s.key, s.placeholder from public.w1f_seed_state s loop
    if r.placeholder then continue; end if;
    if not exists (select 1 from public.acct_mappings m join public.coa_accounts c on c.id = m.account_id where m.key = r.key and c.active) then bad := bad + 1; rows_ := rows_ || jsonb_build_object('kind', 'seed', 'key', r.key, 'problem', 'not mapped to an active account'); end if;
  end loop;
  for r in select o.value_code from public.option_lists o where o.list_code = 'expense_heads' and o.active loop
    if not exists (select 1 from public.acct_mappings m join public.coa_accounts c on c.id = m.account_id where m.key = 'exp_' || r.value_code and c.active) then
      bad := bad + 1; rows_ := rows_ || jsonb_build_object('kind', 'expense_head', 'key', 'exp_' || r.value_code, 'problem', 'active head with no account: its money is booked to Other expenses');
    end if;
  end loop;
  for r in select a.id from public.money_accounts a where a.active loop
    if not exists (select 1 from public.acct_mappings m where m.key = 'm_acct_' || r.id::text) then bad := bad + 1; rows_ := rows_ || jsonb_build_object('kind', 'money_account', 'key', 'm_acct_' || r.id::text, 'problem', 'money account has no mapping'); end if;
  end loop;
  return jsonb_build_object('ran', true, 'ok', bad = 0, 'unmapped', bad, 'rows', rows_);
end $$;

-- ---------- privileges ----------
do $pv$ declare f record; pub text[] := array['_w1f_seed_report', '_w1f_seed_edit', '_w1f_seed_new_code', '_w1f_seed_map', '_w1f_expense_heads', '_w1f_expense_head_set', '_w1f_other_income_heads', '_w1f_other_income_head_set',
  '_w1f_other_income_add', '_w1f_other_income_void', '_w1f_other_income_list', '_w1f_mapping_coverage'];
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like '\_w1f\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname = any (pub) then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
  revoke all on public.w1f_seed_state from public, anon, authenticated;
  alter table public.w1f_seed_state enable row level security;
  drop trigger if exists w1f_seed_state_nodel on public.w1f_seed_state;
  create trigger w1f_seed_state_nodel before delete on public.w1f_seed_state for each row execute function public.no_hard_delete();
end $pv$;
