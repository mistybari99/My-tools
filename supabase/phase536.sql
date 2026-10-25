-- Phase 536 (UNION-8: the advanced line's logic in 43 shared functions (bank_recon_report ... items_with_cost) put back where a repaste of the early phases reset it). Paste-twice safe. Earlier phase files are not edited.
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
-- bank_recon_report(bigint,date,date)
insert into _u_plan (fn, kind, a, b) values
  ('public.bank_recon_report(bigint,date,date)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.bank_recon_report(p_account bigint, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); fr date := coalesce(p_from, date '2000-01-01'); to_ date := coalesce(p_to, date '2999-12-31');
  su jsonb; bu jsonb; sn int; sa numeric; bn int; ba numeric; mn int; ma numeric; st numeric; bk numeric; lb numeric; lbd date;
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
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
end $function$$r0_0$, null),
  ('public.bank_recon_report(bigint,date,date)', 'known', 'b80680d7434a3507d5847a5fd091212c', null);
-- bank_recon_suggest(bigint,date,date,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.bank_recon_suggest(bigint,date,date,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.bank_recon_suggest(p_account bigint, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_days integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare out_ jsonb := '[]'::jsonb; s record; n int; hits int; best record; used text[] := '{}'; kk text; conf boolean;
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
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
end $function$$r0_0$, null),
  ('public.bank_recon_suggest(bigint,date,date,integer)', 'known', 'afe12b6773c81b35ae357b3123868a44', null);
-- bank_recon_unmatch(bigint,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.bank_recon_unmatch(bigint,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.bank_recon_unmatch(p_line bigint, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.bank_recon_matches;
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('bank_recon_on') then raise exception 'switch_off: bank_recon_on'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into m from public.bank_recon_matches where line_id = p_line and active for update;
  if not found then raise exception 'not_matched'; end if;
  update public.bank_recon_matches set active = false, unmatched_by = auth.uid(), unmatched_at = now(), unmatch_note = left(btrim(p_note), 200) where id = m.id;
  insert into public.bank_recon_trail (line_id, action, entry_id, line_no, how, note, actor) values (p_line, 'unmatch', m.entry_id, m.line_no, m.how, left(btrim(p_note), 200), auth.uid());
  return jsonb_build_object('unmatched', p_line);
end $function$$r0_0$, null),
  ('public.bank_recon_unmatch(bigint,text)', 'known', '7e36ecfc9c301bf483d0541be6ea2b09', null);
-- bank_stmt_import(bigint,jsonb,uuid,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.bank_stmt_import(bigint,jsonb,uuid,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.bank_stmt_import(p_account bigint, p_rows jsonb, p_client uuid DEFAULT NULL::uuid, p_dry boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.coa_accounts; e jsonb; ord int := 0; d date; amt numeric; ref text; dsc text; bal numeric; k text; cnt int; m jsonb := '{}'::jsonb;
  good jsonb := '[]'::jsonb; bad jsonb := '[]'::jsonb; nbad int := 0; hsh text; nnew int := 0; ndup int := 0; batch uuid; ins int; rec record; sum_in numeric := 0; sum_out numeric := 0;
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
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
end $function$$r0_0$, null),
  ('public.bank_stmt_import(bigint,jsonb,uuid,boolean)', 'known', '2246f73e6879cc1c8e6eb6a41b204dff', null);
-- blind_active(text,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.blind_active(text,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.blind_active(p_form text, p_loc integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p_form in ('14-1', '10-1') and public.rule_on('blind_count_on')
     and coalesce((select enabled from public.blind_count_cfg where form_code = p_form and location_id = p_loc and public._cfgvis133(p_loc)), true);   /* scope133 */
$function$$r0_0$, null),
  ('public.blind_active(text,integer)', 'known', '16d3e4dd208233e5d6854661267f96da', null);
-- cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.cash_move_add(p_loc integer, p_kind text, p_amount numeric, p_date date DEFAULT NULL::date, p_mode text DEFAULT NULL::text, p_customer uuid DEFAULT NULL::uuid, p_ref text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid, p_dry boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare today date := (now() at time zone 'Asia/Dhaka')::date; d date := coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date); sid text; r public.cash_moves; id_ uuid := gen_random_uuid(); bal numeric;
begin
  if not public.is_active() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if not (public.is_owner() or public.has_grant('cash_move', p_loc)) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if p_kind is null or p_kind not in ('bank_deposit', 'bank_withdraw', 'owner_topup', 'owner_draw', 'cust_advance', 'cust_advance_refund', 'cust_advance_used', 'hub_receipt') then raise exception 'bad_kind'; end if;
  if p_amount is null or not (p_amount between 0.01 and 1000000000000) or round(p_amount, 2) <= 0 then raise exception 'bad_amount'; end if;
  if d < date '2000-01-01' or d > today + 1 then raise exception 'bad_date'; end if;
  if p_kind = 'hub_receipt' then p_mode := 'cash'; end if;
  if p_kind in ('bank_deposit', 'bank_withdraw', 'cust_advance_used') then p_mode := null;
  elsif p_mode is null or p_mode not in ('cash', 'bank', 'mobile') then raise exception 'bad_mode';
  end if;
  if p_kind = 'hub_receipt' then p_mode := 'cash'; end if;
  if p_kind like 'cust_advance%' and p_customer is not null then perform pg_advisory_xact_lock(hashtext('adv:' || p_customer::text)); end if;
  if p_kind like 'cust_advance%' then
    if p_customer is null or not exists (select 1 from public.customers where id = p_customer and public._m132_own(customers.org_unit_id) /* m132b:customers */) then raise exception 'customer_required'; end if;
    if p_kind in ('cust_advance_refund', 'cust_advance_used') then
      select coalesce(sum(case when kind = 'cust_advance' then amount else -amount end), 0) into bal from public.cash_moves where customer_id = p_customer and status = 'done' and kind like 'cust_advance%';
      if round(p_amount, 2) > bal then raise exception 'exceeds_advance' using detail = bal::text; end if;
    end if;
  else p_customer := null;
  end if;
  perform public.lock_check(d);
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.cash_moves where client_id = p_client;
    if found then
      if r.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', r.id);
    end if;
  end if;
  perform public._w1b_backdate_check('cash_move', d, p_client, 'cash_moves');   -- bos89
  if p_dry then
    return jsonb_build_object('dry', true, 'kind', p_kind, 'mode', p_mode, 'amount', round(p_amount, 2), 'date', d, 'location_id', p_loc, 'customer_id', p_customer,
      'daybook', case p_kind when 'bank_deposit' then 'cash out, bank in' when 'bank_withdraw' then 'bank out, cash in' when 'owner_topup' then p_mode || ' in' when 'owner_draw' then p_mode || ' out'
                             when 'cust_advance' then p_mode || ' in' when 'cust_advance_refund' then p_mode || ' out' when 'hub_receipt' then 'cash in (internal)' else 'no money moves (advance used)' end);
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.cash_moves (id, client_id, location_id, kind, mode, amount, move_date, customer_id, ref, note, created_by, created_staff)
    values (id_, p_client, p_loc, p_kind, p_mode, round(p_amount, 2), d, p_customer, left(btrim(p_ref), 80), left(btrim(p_note), 300), auth.uid(), sid);
  return jsonb_build_object('id', id_, 'kind', p_kind, 'amount', round(p_amount, 2)) || public._w1e_cash_pending(id_); /* bos87 w1e94c */
end $function$$r0_0$, null),
  ('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)', 'known', '0d095c78e935bd5ce34a6d274fb508b4', null),
  ('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)', 'known', '7c0e3d340d494d62dadb5ffd57ae423d', null),
  ('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)', 'known', 'c6e46f450b3a65fa9e4f7af93c470bf6', null);
-- control_counts()
insert into _u_plan (fn, kind, a, b) values
  ('public.control_counts()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.control_counts()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare own boolean := public.is_owner(); hd boolean; lm boolean; sa boolean; lg boolean; res jsonb := '{}'; n int; q jsonb;
begin
  if not public.is_active() then return '{}'::jsonb; end if;
  perform public._sheet_sync_due();
  hd := public.has_grant('head_management'); lm := public.has_grant('location_manage'); sa := public.has_grant('settings_approve'); lg := public.has_grant('list_manage');
  res := jsonb_build_object('tier', case when own then 'owner' when hd then 'head' else 'delegate' end);
  if own then
    select count(*) into n from public.item_changes where status = 'pending'; res := res || jsonb_build_object('item_requests', n);
    select count(*) into n from public.exceptions where status = 'open'; res := res || jsonb_build_object('exceptions', n);
    select count(*) into n from public.release_requests where status = 'pending'; res := res || jsonb_build_object('releases', n);
    select count(*) into n from public.emergency_requests where status = 'pending'; res := res || jsonb_build_object('emergency', n);
    select count(*) into n from public.profiles where status = 'pending'; res := res || jsonb_build_object('staff_pending', n);
    select count(*) into n from public.wastage_requests where status = 'pending'; res := res || jsonb_build_object('wastage', n);
  end if;
  if own or hd or lm then
    select count(*) into n from public.locations where status in ('planned', 'setting_up') and ((select not public._org_on123()) or public.can_loc(id));   /* scope133 */ res := res || jsonb_build_object('location_setup', n);
  end if;
  if own or hd or sa then
    select count(*) into n from public.settings_sheets where status = 'draft' and ((select not public._org_on123()) or public.can_loc(location_id));   /* scope133 */ res := res || jsonb_build_object('settings_drafts', n);
  end if;
  -- the list queue is for people who may DECIDE it (the list_manage grant); head_management alone does not (the server would refuse the Lists screen)
  if (own or lg) and to_regprocedure('public.list_queue_counts()') is not null then
    execute 'select public.list_queue_counts()' into q;
    res := res || jsonb_build_object('lists', coalesce((q->>'requests')::int, 0) + coalesce((q->>'other')::int, 0));
  end if;
  return res;
end $function$$r0_0$, null),
  ('public.control_counts()', 'known', 'f09b8dc9906803dbf745f9759126d607', null);
-- cost_attrib_main_set(integer,date,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.cost_attrib_main_set(integer,date,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.cost_attrib_main_set(p_loc integer, p_effective date, p_reason text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.cost_attrib_main; same public.cost_attrib_main; m date; nid bigint; cur date := public._m1(public._c78_today());
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._c78_manage() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into a from public.cost_attrib_main where client_id = p_client; if found then return jsonb_build_object('dup', true, 'id', a.id); end if; end if;
  if p_loc is not null and not exists (select 1 from public.locations where id = p_loc and is_active) then raise exception 'unknown_location'; end if;
  if p_effective is null then raise exception 'bad_date'; end if;
  m := public._m1(p_effective);
  if m < cur then raise exception 'effective_in_past'; end if;
  perform public.lock_check(m);
  if exists (select 1 from public.cost_attrib_main where active and effective_from <= m) and (p_reason is null or length(btrim(p_reason)) < 3) then raise exception 'reason_required'; end if;
  select * into same from public.cost_attrib_main where active and effective_from = m;
  if found then update public.cost_attrib_main set active = false, retired_at = now(), retired_by = auth.uid() where id = same.id; end if;
  insert into public.cost_attrib_main (location_id, effective_from, reason, client_id, created_by) values (p_loc, m, left(btrim(p_reason), 300), p_client, auth.uid()) returning id into nid;
  if same.id is not null then update public.cost_attrib_main set replaced_by = nid where id = same.id; end if;
  return jsonb_build_object('id', nid, 'effective_from', m);
end $function$$r0_0$, null),
  ('public.cost_attrib_main_set(integer,date,text,uuid)', 'known', '2dbd65c94d4f883eead5b13bc654c2ee', null);
-- cost_rule_approve(bigint,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.cost_rule_approve(bigint,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.cost_rule_approve(p_rule bigint, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.cost_source_rules; b record; n int := 0; selfap boolean := false; sid text;   -- bos87
begin
  if not public._cs_approve() then raise exception 'not allowed'; end if;
  select * into r from public.cost_source_rules where id = p_rule for update;
  if not found then raise exception 'not_found'; end if;
  if not public._cs_src_ok(r.source_id) then raise exception 'not allowed'; end if;
  if r.status = 'approved' then return jsonb_build_object('dup', true, 'id', r.id); end if;
  if r.status <> 'draft' then raise exception 'rule_not_draft'; end if;
  if not r.complete then raise exception 'rule_incomplete'; end if;
  if r.created_by is not distinct from auth.uid() then   -- bos87: the owner is never refused; others as before (switch cost_rule_self_approve)
    if public.is_owner() or public.rule_on('cost_rule_self_approve') then selfap := true; else raise exception 'self_approve_refused'; end if;   -- bos87
  end if;   -- bos87
  update public.cost_source_rules set status = 'superseded' where source_id = r.source_id and status = 'approved' and effective_from = r.effective_from;      -- same date: the new one replaces the old (kept)
  update public.cost_source_rules set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_rule;
  -- bills that still wait for a split (no rule / blank) may now be allocated; fully allocated bills are NOT touched
  for b in select distinct bl.id from public.cost_source_bills bl where bl.source_id = r.source_id and bl.status = 'active' and bl.period_month >= date_trunc('month', r.effective_from)::date
      and (not exists (select 1 from public.cost_bill_shares x where x.bill_id = bl.id and x.active) or exists (select 1 from public.cost_bill_shares x where x.bill_id = bl.id and x.active and x.kind = 'unallocated')) loop
    perform public._cs_alloc(b.id); n := n + 1;
  end loop;
  if selfap then   -- bos87
    select staff_id into sid from public.profiles where id = auth.uid();   -- bos87
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)   -- bos87
      values (auth.uid(), sid, 'self_approved', 'cost_source_rules', p_rule::text, jsonb_build_object('self_approved', true, 'owner', public.is_owner(), 'note', left(p_note, 200), 'src', 'phase87'));   -- bos87
  end if;   -- bos87
  return jsonb_build_object('id', p_rule, 'approved', true, 'bills_allocated', n) || public._self_approve_hint87(selfap);   -- bos87
end $function$$r0_0$, null),
  ('public.cost_rule_approve(bigint,text)', 'known', '99a2d3954ba5bdb66effd9bc24e1808a', null);
-- cost_source_set_active(bigint,boolean,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.cost_source_set_active(bigint,boolean,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.cost_source_set_active(p_id bigint, p_active boolean, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public._cs_enter() then raise exception 'not allowed'; end if;
  if p_active is null then raise exception 'bad_value'; end if;
  if public._org_on123() and auth.uid() is not null and not public._cs_src_ok(p_id) then raise exception 'source_not_found'; end if;   /* scope133: a cost source of another business is a missing id */
  if not p_active and length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'note_required'; end if;
  update public.cost_sources set active = p_active, retired_at = case when p_active then null else now() end, retired_reason = case when p_active then null else left(btrim(p_reason), 200) end where id = p_id;
  if not found then raise exception 'source_not_found'; end if;
end $function$$r0_0$, null),
  ('public.cost_source_set_active(bigint,boolean,text)', 'known', '591affe276bd9e22d4e028952639e194', null);
-- count_lines_seal(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.count_lines_seal(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.count_lines_seal(p_entry uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e public.entries; k text; cf text; r jsonb; n int; cnt numeric; it public.items; bk numeric; tot int := 0;
begin
  select * into e from public.entries where id = p_entry for update;
  if not found or not public.can_loc(e.location_id) then raise exception 'not allowed'; end if;
  if e.created_by is distinct from auth.uid() and not public.is_owner() then raise exception 'not allowed'; end if;
  if e.status <> 'draft' then raise exception 'count_not_open'; end if;
  if not public.stock_blind_active(e.form_code, e.location_id) then return jsonb_build_object('blind', false, 'sealed', 0); end if;
  k := case e.form_code when '04-3' then 'rows' else 'lines' end; cf := case e.form_code when '04-3' then 'count' else 'counted' end;
  for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data -> k) = 'array' then e.data -> k else '[]'::jsonb end) with ordinality x(v, o) loop
    continue when nullif(btrim(r ->> 'item'), '') is null;
    if nullif(btrim(coalesce(r ->> cf, '')), '') is null then raise exception 'count_missing'; end if;
    cnt := public._n18(r, cf);
    if cnt < 0 then raise exception 'bad_count'; end if;
    if not exists (select 1 from public.entry_count_seals where entry_id = e.id and line_no = n) then
      select * into it from public.items where code = btrim(r ->> 'item') and public._m132_at(org_unit_id, e.location_id) /* m132 */;
      if not found then raise exception 'item_not_found'; end if;
      bk := null;
      if e.form_code = '04-3' then
        select coalesce(b.qty, 0) into bk from public.stock_balance b where b.item_id = it.id and b.location_id = e.location_id;
        bk := coalesce(bk, 0);
      end if;
      insert into public.entry_count_seals (entry_id, line_no, form_code, item_code, counted, book_base, sealed_by) values (e.id, n, e.form_code, btrim(r ->> 'item'), cnt, bk, auth.uid());
    end if;
  end loop;
  select count(*) into tot from public.entry_count_seals where entry_id = e.id;
  return jsonb_build_object('blind', true, 'sealed', tot);
end $function$$r0_0$, null),
  ('public.count_lines_seal(uuid)', 'known', '0c6f2b998e0ff8df221c8568b6033816', null);
-- count_unsubmitted_scan()
insert into _u_plan (fn, kind, a, b) values
  ('public.count_unsubmitted_scan()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.count_unsubmitted_scan()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
    select e.id, e.form_code, e.location_id, e.entry_date, 'count_unsubmitted', 'red', null,
           jsonb_build_object('bn', 'গণনা সেভ হয়েছে কিন্তু শিট জমা হয়নি', 'en', 'Count saved but the sheet was never submitted')
    from public.entry_counts c join public.entries e on e.id = c.entry_id
    where c.section = 'drawer' and e.status = 'draft' and e.entry_date < (now() at time zone 'Asia/Dhaka')::date
      and not exists (select 1 from public.exceptions x where x.entry_id = e.id and x.flag_code = 'count_unsubmitted')
      and ((select not public._org_on123()) or public.can_loc(e.location_id));   /* scope133: only the places of the caller */
  get diagnostics n = row_count;
  return n;
end $function$$r0_0$, null),
  ('public.count_unsubmitted_scan()', 'known', '68e8da0c14e0ceee2d4a14761696ca38', null);
-- customer_advances()
insert into _u_plan (fn, kind, a, b) values
  ('public.customer_advances()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.customer_advances()
 RETURNS TABLE(customer_id uuid, name text, mobile text, balance numeric, last_at date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select c.id, c.name, public._cust_pii103('mobile', c.mobile) /* bos105 */, sum(case when m.kind = 'cust_advance' then m.amount else -m.amount end), max(m.move_date)
    from public.cash_moves m join public.customers c on c.id = m.customer_id
   where m.status = 'done' and m.kind like 'cust_advance%' and public.is_active() and public.can_loc(m.location_id) and (public.is_owner() or public.has_grant('cash_move', m.location_id) or public.has_grant('view_daybook', m.location_id))
   group by c.id, c.name, c.mobile having sum(case when m.kind = 'cust_advance' then m.amount else -m.amount end) <> 0;
$function$$r0_0$, null),
  ('public.customer_advances()', 'known', '533cc9d5486899115fb2bcc814b2a182', null);
-- customer_balance(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.customer_balance(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.customer_balance(p_customer uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when public.is_active() and (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then (case when public._m132_own((select c.org_unit_id from public.customers c where c.id = p_customer)) /* m132 */ then public._cust_bal(p_customer) end) end;
$function$$r0_0$, null),
  ('public.customer_balance(uuid)', 'known', '030b0d2494c9bee644e8237481766d7f', null);
-- customer_directory(integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.customer_directory(integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.customer_directory(p_limit integer DEFAULT 5000)
 RETURNS TABLE(id uuid, mobile text, name text, type text, active boolean, tier_id bigint, tier_locked boolean, birthday date, anniversary date, address text, whatsapp text, note text, credit_limit numeric, customer_since date, balance numeric, spend numeric, orders integer, last_sale date, points integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  return query
    with s as (select x.customer_id cid, sum(x.total) tot, count(*)::int n, max(x.sale_date) last_d from public.sales x
               where x.status = 'done' and x.customer_id is not null and public.can_loc(x.location_id) group by 1),
         r as (select y.customer_id cid, sum(y.amount) amt from public.sale_returns y join public.sales z on z.id = y.sale_id
               where y.status = 'done' and y.customer_id is not null and public.can_loc(z.location_id) group by 1),
         d as (select q.id cid, q.balance bal from public.customer_dues() q),
         p as (select l.customer_id cid, sum(l.delta)::int pts from public.customer_points_ledger l group by 1)
    select c.id, public._cust_pii103('mobile', c.mobile) /* bos103 */, public._cust_pii103('name', c.name) /* sec2-L6 */, c.type, c.active, c.tier_id, c.tier_locked, c.birthday, c.anniversary, public._cust_pii103('address', c.address), public._cust_pii103('mobile', c.whatsapp), public._cust_pii103('text', c.note), c.credit_limit, c.customer_since,
           coalesce(d.bal, 0), coalesce(s.tot, 0) - coalesce(r.amt, 0), coalesce(s.n, 0), s.last_d, coalesce(p.pts, 0)
    from public.customers c left join s on s.cid = c.id left join r on r.cid = c.id left join d on d.cid = c.id left join p on p.cid = c.id
    where public._m132_own(c.org_unit_id) /* m132 */ order by lower(c.name), c.mobile limit least(greatest(coalesce(p_limit, 5000), 1), 20000);
end $function$$r0_0$, null),
  ('public.customer_directory(integer)', 'known', '484043d32143b4d2ec77be5cc641fa67', null);
-- customer_ledger(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.customer_ledger(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.customer_ledger(p_customer uuid)
 RETURNS TABLE(at timestamp with time zone, kind text, ref text, location_id integer, debit numeric, credit numeric, balance numeric, note text, pid bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with e as (
    select public._w1a_cust_open_at(p_customer) at, 'opening'::text kind, null::text ref, null::int location_id, o.ob debit, 0::numeric credit, 'opening balance'::text note, null::bigint pid /* bos88 */
      from (select public._w1a_cust_open(p_customer) ob) o where o.ob <> 0
    union all
    select s.sold_at at, 'sale'::text kind, '#' || s.receipt ref, s.location_id, s.total debit, 0::numeric credit, case when s.sale_type = 'wholesale' then 'wholesale' end note, null::bigint pid
      from public.sales s where s.customer_id = p_customer and s.status = 'done' and (not (select public._org_on123()) or public.can_loc(s.location_id))
    union all
    select p.paid_at, case when p.kind = 'collection' then 'collection' else 'paid' end, coalesce(p.wallet, p.mode), p.location_id, 0, p.amount, p.note, p.id
      from public.sale_payments p where p.customer_id = p_customer and not p.voided and (not (select public._org_on123()) or public.can_loc(p.location_id))
    union all
    select r.created_at, 'sale_return', '#' || s.receipt, r.location_id, 0, r.credit_amount, r.reason_code, null::bigint
      from public.sale_returns r join public.sales s on s.id = r.sale_id where r.customer_id = p_customer and r.status = 'done' and r.credit_amount > 0 and (not (select public._org_on123()) or public.can_loc(r.location_id)))
  select e.at, e.kind, e.ref, e.location_id, e.debit, e.credit, sum(e.debit - e.credit) over (order by e.at, (e.debit > 0) desc, e.kind), e.note, e.pid
  from e where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) order by e.at, (e.debit > 0) desc, e.kind;
$function$$r0_0$, null),
  ('public.customer_ledger(uuid)', 'known', 'dbba32ccc6c52bd97e77bb0252b02dbb', null),
  ('public.customer_ledger(uuid)', 'known', 'ded875bcc1da74da42da271b1f9fac41', null),
  ('public.customer_ledger(uuid)', 'known', 'fe27f4e36ceabdd7cf8f0da215bfcdce', null);
-- customer_points_adjust(uuid,integer,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.customer_points_adjust(uuid,integer,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.customer_points_adjust(p_customer uuid, p_delta integer, p_note text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare bal int; why text := left(btrim(coalesce(p_note, '')), 300);
begin
  if not public._cust_mgr43() then raise exception 'not allowed'; end if;
  if p_delta is null or p_delta = 0 or abs(p_delta) > 10000000 then raise exception 'bad_number'; end if;
  if length(why) < 3 then raise exception 'note_required'; end if;
  perform public._client_lock(p_client);
  if p_client is not null and exists (select 1 from public.customer_points_ledger where client_id = p_client) then
    return jsonb_build_object('dup', true, 'balance', (select sum(delta) from public.customer_points_ledger where customer_id = p_customer));
  end if;
  perform 1 from public.customers where id = p_customer and public._m132_own(customers.org_unit_id) /* m132b:customers */ for update;
  if not found then raise exception 'customer_not_found'; end if;
  select coalesce(sum(delta), 0) into bal from public.customer_points_ledger where customer_id = p_customer;
  if bal + p_delta < 0 then raise exception 'not_enough_points'; end if;
  insert into public.customer_points_ledger (customer_id, delta, reason, client_id, note, by_user, by_staff)
    values (p_customer, p_delta, 'adjust', p_client, why, auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
  return jsonb_build_object('dup', false, 'balance', bal + p_delta);
end $function$$r0_0$, null),
  ('public.customer_points_adjust(uuid,integer,text,uuid)', 'known', 'f758e0f59a2e94c726161defac575ce9', null);
-- customer_points_redeem(uuid,integer,text,uuid,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.customer_points_redeem(uuid,integer,text,uuid,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.customer_points_redeem(p_customer uuid, p_points integer, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid, p_dry boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare bal int; val numeric; mn numeric;
begin
  if not (public._cust_mgr43() or (public.is_active() and public.can_do('POS', 'enter'))) then raise exception 'not allowed'; end if;
  if not public.rule_on('loyalty_points_on') then raise exception 'loyalty_off'; end if;
  if p_points is null or p_points <= 0 or p_points > 10000000 then raise exception 'bad_number'; end if;
  mn := coalesce(public.rule_num('redeem_min_points'), 0);
  if p_points < mn then raise exception 'below_min_points'; end if;
  val := round(p_points * coalesce(public.rule_num('point_value_taka'), 0), 2);
  perform public._client_lock(p_client);
  if not coalesce(p_dry, false) and p_client is not null and exists (select 1 from public.customer_points_ledger where client_id = p_client) then
    return jsonb_build_object('dup', true, 'points', p_points, 'value_taka', val, 'balance', (select sum(delta) from public.customer_points_ledger where customer_id = p_customer));
  end if;
  perform 1 from public.customers where id = p_customer and public._m132_own(customers.org_unit_id) /* m132b:customers */ for update;
  if not found then raise exception 'customer_not_found'; end if;
  select coalesce(sum(delta), 0) into bal from public.customer_points_ledger where customer_id = p_customer;
  if p_points > bal then raise exception 'not_enough_points'; end if;
  if coalesce(p_dry, false) then return jsonb_build_object('dry', true, 'points', p_points, 'value_taka', val, 'balance', bal, 'balance_after', bal - p_points); end if;
  insert into public.customer_points_ledger (customer_id, delta, reason, client_id, note, by_user, by_staff)
    values (p_customer, -p_points, 'redeem', p_client, left(nullif(btrim(p_note), ''), 300), auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
  return jsonb_build_object('dry', false, 'dup', false, 'points', p_points, 'value_taka', val, 'balance', bal - p_points);
end $function$$r0_0$, null),
  ('public.customer_points_redeem(uuid,integer,text,uuid,boolean)', 'known', '1a6adfda8d0e208551dfabe985f497f0', null);
-- customer_pos_info(text)
insert into _u_plan (fn, kind, a, b) values
  ('public.customer_pos_info(text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.customer_pos_info(p_mobile text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m text; c public.customers; t public.customer_tiers; g int := 0;
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  m := public.norm_mobile(p_mobile);
  select * into c from public.customers where mobile = m and public._m132_own(org_unit_id) /* m132 */ order by (org_unit_id is not distinct from public._m132_caller_biz()) desc, org_unit_id limit 1;
  if not found then return jsonb_build_object('found', false, 'mobile', m); end if;
  select * into t from public.customer_tiers where id = c.tier_id;
  if public.rule_on('customer_gifts_on') then select count(*)::int into g from public.gifts_due(c.id); end if;
  return jsonb_build_object('found', true, 'id', c.id, 'name', c.name, 'birthday', c.birthday,
    'tier', case when t.id is null then null else jsonb_build_object('id', t.id, 'code', t.code, 'name_bn', t.name_bn, 'name_en', t.name_en, 'color', t.color, 'badge', t.badge, 'perks', t.perks,
        'discount_percent', t.discount_percent, 'discount_cap_amount', t.discount_cap_amount, 'birthday_gift', t.birthday_gift) end,
    'tier_discount_on', public.rule_on('tier_discount_on') and coalesce(t.discount_percent, 0) > 0 and c.active and coalesce(t.active, false),
    'gifts_due', g,
    'points', case when public.rule_on('loyalty_points_on') then coalesce((select sum(delta) from public.customer_points_ledger where customer_id = c.id), 0) end);
end $function$$r0_0$, null),
  ('public.customer_pos_info(text)', 'known', 'f2060f1f46fa4c12803f0e7b0e2f238f', null);
-- customer_profile(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.customer_profile(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.customer_profile(p_customer uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.customers; st record; res jsonb;
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  select * into c from public.customers where id = p_customer and public._m132_own(customers.org_unit_id) /* m132b:customers */;
  if not found then raise exception 'customer_not_found'; end if;
  select * into st from public._cust_stats43(p_customer, true);
  return jsonb_build_object(
    'customer', jsonb_build_object('id', c.id, 'mobile', public._cust_pii103('mobile', c.mobile) /* bos105 */, 'name', c.name, 'type', c.type, 'active', c.active, 'tier_id', c.tier_id, 'tier_locked', c.tier_locked, 'birthday', c.birthday,
        'anniversary', c.anniversary, 'address', public._cust_pii103('address', c.address), 'whatsapp', public._cust_pii103('mobile', c.whatsapp), 'note', public._cust_pii103('text', c.note) /* bos105 */, 'source', c.source, 'credit_limit', c.credit_limit, 'customer_since', c.customer_since),
    'spend', st.spend, 'orders', st.orders, 'orders_12m', st.orders_12m, 'first_sale', st.first_sale, 'last_sale', st.last_sale,
    'avg_bill', case when st.orders > 0 then round(st.spend / st.orders, 2) end,
    'balance', public._cust_bal(p_customer),
    'points', coalesce((select sum(delta) from public.customer_points_ledger where customer_id = p_customer), 0),
    'history', coalesce((select jsonb_agg(jsonb_build_object('at', h.at, 'from_tier', h.from_tier, 'to_tier', h.to_tier, 'reason', h.reason, 'note', h.note, 'by', h.by_staff) order by h.at desc, h.id desc)
                         from (select * from public.customer_tier_history where customer_id = p_customer order by at desc, id desc limit 30) h), '[]'::jsonb),
    'gifts', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'text_bn', g.gift_text_bn, 'text_en', g.gift_text_en, 'value', g.value_taka, 'issued_at', g.issued_at, 'valid_until', g.valid_until, 'claimed_at', g.claimed_at)
                                        order by g.issued_at desc) from (select * from public.customer_gifts where customer_id = p_customer order by issued_at desc limit 30) g), '[]'::jsonb),
    'points_log', coalesce((select jsonb_agg(jsonb_build_object('at', l.at, 'delta', l.delta, 'reason', l.reason, 'note', l.note) order by l.at desc, l.id desc)
                            from (select * from public.customer_points_ledger where customer_id = p_customer order by at desc, id desc limit 30) l), '[]'::jsonb),
    'recent_sales', coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'receipt', z.receipt, 'date', z.sale_date, 'total', z.total, 'due', z.due_amount, 'status', z.status, 'loc', z.location_id) order by z.sold_at desc)
                              from (select * from public.sales x where x.customer_id = p_customer and public.can_loc(x.location_id) order by x.sold_at desc limit 10) z), '[]'::jsonb));
end $function$$r0_0$, null),
  ('public.customer_profile(uuid)', 'known', '13ad334a4ee0a61c1604c7f3cb9f7d78', null);
-- customer_save(uuid,jsonb,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.customer_save(uuid,jsonb,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.customer_save(p_id uuid, p jsonb, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare mob text; c public.customers; nm text; ty text; mgr boolean; tid bigint; wa text; old_tier bigint;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  mgr := public._cust_mgr43();
  if not (mgr or public.can_do('POS', 'enter')) then raise exception 'not allowed'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_value'; end if;
  if (p ? 'birthday' and public._d43(p, 'birthday') > public._today43()) or (p ? 'anniversary' and public._d43(p, 'anniversary') > public._today43()) then raise exception 'bad_date'; end if;
  if p_id is not null then p := p - array(select e.key from jsonb_each_text(p) e where e.key in ('name', 'address', 'note', 'whatsapp') and e.value like '%•%'); end if;   -- bos105: a masked value read from the screen is never saved back over the real one
  perform public._client_lock(p_client);
  if p ? 'name' then
    nm := left(btrim(coalesce(p ->> 'name', '')), 80);
    if nm = '' then raise exception 'customer_name_required'; end if;
  end if;
  if p ? 'type' then ty := p ->> 'type'; if ty is null or ty not in ('retail', 'wholesale') then raise exception 'bad_sale_type'; end if; end if;
  if p ? 'whatsapp' then
    wa := nullif(btrim(coalesce(p ->> 'whatsapp', '')), '');
    if wa is not null then wa := public.norm_mobile(wa); end if;
  end if;
  if p_id is null then
    if nullif(btrim(coalesce(p ->> 'mobile', '')), '') is null then raise exception 'bad_mobile'; end if;
    mob := public.norm_mobile(p ->> 'mobile');
    if nm is null then raise exception 'customer_name_required'; end if;
    select * into c from public.customers where mobile = mob and public._m132_own(org_unit_id) /* m132 */ order by (org_unit_id is not distinct from public._m132_caller_biz()) desc, org_unit_id limit 1;
    if found then return jsonb_build_object('dup', true, 'id', c.id, 'name', c.name, 'active', c.active); end if;
    if (p ? 'tier_id' or p ? 'tier_locked' or p ? 'credit_limit') and not mgr then raise exception 'not allowed'; end if;
    tid := nullif(p ->> 'tier_id', '')::bigint;
    if tid is not null and not exists (select 1 from public.customer_tiers where id = tid and active) then raise exception 'tier_not_found'; end if;
    insert into public.customers (org_unit_id, mobile, name, type, created_by, tier_id, tier_locked, birthday, anniversary, address, note, source, whatsapp, credit_limit)
      values (nullif(p ->> 'org_unit_id', '')::bigint /* m132 */, mob, nm, coalesce(ty, 'retail'), auth.uid(), tid, coalesce((p ->> 'tier_locked')::boolean, tid is not null), public._d43(p, 'birthday'), public._d43(p, 'anniversary'),
              left(nullif(btrim(p ->> 'address'), ''), 200), left(nullif(btrim(p ->> 'note'), ''), 500), left(nullif(btrim(p ->> 'source'), ''), 60), wa, public._n43(p, 'credit_limit', 0))
      returning * into c;
    if tid is not null and tid is distinct from (select id from public.customer_tiers where is_default limit 1) then
      insert into public.customer_tier_history (customer_id, from_tier, to_tier, reason, note, by_user, by_staff)
        values (c.id, (select id from public.customer_tiers where is_default limit 1), tid, 'manual', 'at registration', auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
    end if;
    return jsonb_build_object('id', c.id, 'mobile', c.mobile, 'name', c.name, 'dup', false);
  end if;
  select * into c from public.customers where id = p_id and public._m132_own(customers.org_unit_id) /* m132b:customers */ for update;
  if not found then raise exception 'customer_not_found'; end if;
  if (p ? 'tier_id' or p ? 'tier_locked' or p ? 'credit_limit' or p ? 'active') and not mgr then raise exception 'not allowed'; end if;
  update public.customers set
    name = coalesce(nm, name), type = coalesce(ty, type),
    birthday = case when p ? 'birthday' then public._d43(p, 'birthday') else birthday end,
    anniversary = case when p ? 'anniversary' then public._d43(p, 'anniversary') else anniversary end,
    address = case when p ? 'address' then left(nullif(btrim(p ->> 'address'), ''), 200) else address end,
    note = case when p ? 'note' then left(nullif(btrim(p ->> 'note'), ''), 500) else note end,
    source = case when p ? 'source' then left(nullif(btrim(p ->> 'source'), ''), 60) else source end,
    whatsapp = case when p ? 'whatsapp' then wa else whatsapp end,
    credit_limit = case when p ? 'credit_limit' then public._n43(p, 'credit_limit', 0) else credit_limit end,
    tier_locked = case when p ? 'tier_locked' then coalesce((p ->> 'tier_locked')::boolean, tier_locked) else tier_locked end,
    active = case when p ? 'active' then coalesce((p ->> 'active')::boolean, active) else active end
  where id = p_id returning * into c;
  if p ? 'tier_id' then
    tid := nullif(p ->> 'tier_id', '')::bigint;
    if tid is not null then perform public.customer_set_tier(p_id, tid, coalesce(nullif(btrim(p ->> 'tier_reason'), ''), 'edited'), case when p ? 'tier_locked' then (p ->> 'tier_locked')::boolean end); end if;
  end if;
  return jsonb_build_object('id', c.id, 'mobile', c.mobile, 'name', c.name, 'dup', false);
end $function$$r0_0$, null),
  ('public.customer_save(uuid,jsonb,uuid)', 'known', '56fd859271382effabb220827db3d7ad', null);
-- customer_set_tier(uuid,bigint,text,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.customer_set_tier(uuid,bigint,text,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.customer_set_tier(p_customer uuid, p_tier bigint, p_reason text, p_lock boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.customers; t public.customer_tiers; why text := left(btrim(coalesce(p_reason, '')), 300);
begin
  if not public._cust_mgr43() then raise exception 'not allowed'; end if;
  if length(why) < 3 then raise exception 'note_required'; end if;
  select * into c from public.customers where id = p_customer and public._m132_own(customers.org_unit_id) /* m132b:customers */ for update;
  if not found then raise exception 'customer_not_found'; end if;
  select * into t from public.customer_tiers where id = p_tier;
  if not found or not t.active then raise exception 'tier_not_found'; end if;
  if c.tier_id is distinct from p_tier then
    insert into public.customer_tier_history (customer_id, from_tier, to_tier, reason, note, by_user, by_staff)
      values (c.id, c.tier_id, p_tier, 'manual', why, auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
  end if;
  update public.customers set tier_id = p_tier, tier_locked = coalesce(p_lock, true) where id = c.id;
  return jsonb_build_object('id', c.id, 'tier_id', p_tier, 'changed', c.tier_id is distinct from p_tier, 'tier_locked', coalesce(p_lock, true));
end $function$$r0_0$, null),
  ('public.customer_set_tier(uuid,bigint,text,boolean)', 'known', '36b55a268dd6cef296b8c234dc2eae47', null);
-- decide_emergency(bigint,boolean,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.decide_emergency(bigint,boolean,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.decide_emergency(p_id bigint, p_approve boolean, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.emergency_requests; sid text; mins numeric;
begin
  if not public.can_grant('emergency_decide') then raise exception 'not allowed'; end if;
  select * into r from public.emergency_requests where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if public._org_on123() and not public.is_owner() and (r.location_id is null or not public._biz_ok123(r.location_id)) then raise exception 'not found'; end if;   -- scope123
  if r.status <> 'pending' then raise exception 'already decided'; end if;
  if r.created_at < now() - interval '1 day' then update public.emergency_requests set status = 'expired' where id = p_id; return; end if;      -- a day-old request is stale: ask again
  if r.requested_by = auth.uid() and not (public.is_owner() and public.rule_on('owner_self_approve')) then raise exception 'own_request'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  mins := coalesce(public.rule_num('em_minutes'), 30);
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.emergency_requests set status = case when p_approve then 'approved' else 'rejected' end, decided_by = auth.uid(), decided_staff = sid, decided_at = now(),
    decision_note = left(nullif(btrim(p_note), ''), 300), valid_until = case when p_approve then now() + make_interval(mins => mins::int) end where id = p_id;
end $function$$r0_0$, null),
  ('public.decide_emergency(bigint,boolean,text)', 'known', '00dfa679b8711fb289b4e1f2a28cde34', null);
-- dup_suspects(date,date)
insert into _u_plan (fn, kind, a, b) values
  ('public.dup_suspects(date,date)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.dup_suspects(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'bad_range'; end if;
  return jsonb_build_object('from', p_from, 'to', p_to,
    -- D1: a payroll month paid in the app AND a 02-2 sheet for the same place and month
    'payroll', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select r.id as run_id, r.month, r.location_id, e.id as entry_id, e.serial, e.status as form_status
          from public.payroll_runs r join public.entries e on e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.location_id = coalesce(r.location_id, e.location_id)
            and date_trunc('month', e.entry_date) = date_trunc('month', r.month::timestamp)
         where r.status <> 'void' and r.month between date_trunc('month', p_from)::date and p_to
           and not public.is_shadow('entries', e.id::text) order by r.month, r.id limit 200) z), '[]'::jsonb),
    -- D2: a form-posted stock line (ref_type entry) and a screen-posted line for the same item, place, day, reason and quantity
    'stock', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select f.item_id, f.location_id, (f.made_at at time zone 'Asia/Dhaka')::date as day, f.reason, f.qty_delta, f.id as form_ledger_id, s.id as screen_ledger_id
          from public.stock_ledger f join public.stock_ledger s on s.item_id = f.item_id and s.location_id = f.location_id and s.reason = f.reason and s.qty_delta = f.qty_delta
            and (s.made_at at time zone 'Asia/Dhaka')::date = (f.made_at at time zone 'Asia/Dhaka')::date and coalesce(s.ref_type, '') <> 'entry' and s.id <> f.id and s.reverses_id is null
         where f.ref_type = 'entry' and f.reverses_id is null and f.reason in ('issue_out', 'transfer_out', 'transfer_in', 'count_adjust', 'production_in', 'purchase_in')
           and f.made_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and f.made_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
           and coalesce(s.ref_type, '') not in ('sale', 'sale_pack', 'sale_return') order by f.made_at limit 200) z), '[]'::jsonb),
    -- D3: a 05-1 output line posted from the form and a production run for the same finished item, place and day
    'production', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select f.item_id, f.location_id, (f.made_at at time zone 'Asia/Dhaka')::date as day, f.qty_delta, f.id as form_ledger_id, r.id as run_id
          from public.stock_ledger f join public.production_runs r on r.item_id = f.item_id and r.location_id = f.location_id and r.status = 'done'
            and (r.made_at at time zone 'Asia/Dhaka')::date = (f.made_at at time zone 'Asia/Dhaka')::date
         where f.ref_type = 'entry' and f.reason = 'production_in' and f.reverses_id is null
           and f.made_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and f.made_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka') order by f.made_at limit 200) z), '[]'::jsonb),
    -- D4: an owner top-up / draw in partner capital and the same amount on a cash move within 3 days
    'owner_money', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select pc.id as capital_id, pc.cap_date, pc.kind as capital_kind, pc.amount, m.id as cash_move_id, m.move_date, m.kind as cash_kind, m.location_id
          from public.partner_capital pc join public.cash_moves m on m.kind in ('owner_topup', 'owner_draw') and m.status = 'done' and m.amount = pc.amount and abs(m.move_date - pc.cap_date) <= 3
         where pc.status = 'posted' and pc.cap_date between p_from and p_to and not public.is_shadow('cash_moves', m.id::text) order by pc.cap_date limit 200) z), '[]'::jsonb),
    -- D8: a hub receipt (cash move) and a cash handover slip 10-1 for the same place and day
    'handover', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select m.id as cash_move_id, m.move_date, m.location_id, m.amount, e.id as entry_id, e.serial
          from public.cash_moves m join public.entries e on e.form_code = '10-1' and e.status in ('submitted', 'approved') and e.entry_date = m.move_date
         where m.kind = 'hub_receipt' and m.status = 'done' and m.move_date between p_from and p_to order by m.move_date limit 200) z), '[]'::jsonb),
    -- bos83 F10: two finished-goods screens for the same item, place and day - a recipe run (production_post) and a plain finished-goods entry (stock_production_in)
    'production_screens', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select r.item_id, r.location_id, (r.made_at at time zone 'Asia/Dhaka')::date as day, r.id as run_id, s.id as plain_ledger_id, s.qty_delta as plain_qty, r.yield_base as run_qty
          from public.production_runs r join public.stock_ledger s on s.item_id = r.item_id and s.location_id = r.location_id and s.reason = 'production_in' and s.ref_type = 'production'
            and s.reverses_id is null and s.id is distinct from r.ledger_in_id and (s.made_at at time zone 'Asia/Dhaka')::date = (r.made_at at time zone 'Asia/Dhaka')::date
         where r.status = 'done' and r.made_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and r.made_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
           and not exists (select 1 from public.production_runs r2 where r2.ledger_in_id = s.id) order by r.made_at limit 200) z), '[]'::jsonb),
    -- bos83 E6 (a4-F5): a quick expense and an approved 10-2 voucher line for the same place, day, head and amount that are NOT linked as a shadow
    'expense', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select q.id as quick_id, q.location_id, q.exp_date as day, q.head, q.amount, e.id as entry_id, e.serial
          from public.quick_expenses q
          join public.entries e on e.form_code = '10-2' and e.status = 'approved' and e.location_id = q.location_id and e.entry_date = q.exp_date
            and jsonb_typeof(e.data -> 'lines') = 'array' and not public.is_shadow('entries', e.id::text)
          join lateral jsonb_array_elements(e.data -> 'lines') ln on lower(btrim(ln ->> 'head')) = q.head and public._db_num(ln -> 'amount') = q.amount
         where q.status = 'done' and q.exp_date between p_from and p_to
           and not exists (select 1 from public.shadow_links x where x.primary_type = 'quick_expenses' and x.primary_id = q.id::text and x.state = 'confirmed')
         order by q.exp_date, q.id limit 200) z), '[]'::jsonb));
end $function$$r0_0$, null),
  ('public.dup_suspects(date,date)', 'known', '9d22f4c1f28144978ab4f1984b4c96f1', null);
-- fa_register(date)
insert into _u_plan (fn, kind, a, b) values
  ('public.fa_register(date)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.fa_register(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare as_ date := coalesce(p_as_of, public._acct_today());
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('fixed_assets_on'), 'as_of', as_, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name', a.name, 'category', a.category, 'location_id', a.location_id, 'acquired_on', a.acquired_on, 'cost', a.cost, 'salvage', a.salvage,
      'life_months', a.life_months, 'method', a.method, 'depr_from', a.depr_from, 'status', a.status, 'disposed_on', a.disposed_on,
      'accumulated', coalesce(p.s, 0), 'book_value', a.cost - coalesce(p.s, 0), 'months_posted', coalesce(p.n, 0), 'last_month', p.mx) order by a.code)
    from public.fa_assets a left join lateral (select sum(amount) s, count(*) n, max(month) mx from public.fa_depr_posts x where x.asset_id = a.id and x.month <= as_) p on true
    where (not public._org_on123() or public.can_loc(a.location_id))), '[]'::jsonb));   -- scope123: the caller's places (no place = owner only)
end $function$$r0_0$, null),
  ('public.fa_register(date)', 'known', '7e2da3ac91436ede29cf5ee268b59cf3', null);
-- fa_schedule(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.fa_schedule(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.fa_schedule(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.fa_assets; rows_ jsonb;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  select * into a from public.fa_assets where id = p_id;
  if not found then raise exception 'not found'; end if;
  if public._org_on123() and not public.can_loc(a.location_id) then raise exception 'not found'; end if;   -- scope123: same answer as a missing id
  select coalesce(jsonb_agg(jsonb_build_object('k', k, 'month', m, 'amount', amt, 'accumulated', acc, 'book_value', a.cost - acc, 'posted', p.id is not null,
      'skipped_after_disposal', a.status = 'disposed' and m > public._a53_mon(a.disposed_on)) order by k), '[]'::jsonb) into rows_ from (
    select g k, (a.depr_from + ((g - 1) || ' months')::interval)::date m, public._a53_fa_amt(a.cost, a.salvage, a.life_months, g) amt,
      sum(public._a53_fa_amt(a.cost, a.salvage, a.life_months, g)) over (order by g) acc from generate_series(1, a.life_months) g) s
    left join public.fa_depr_posts p on p.asset_id = a.id and p.month = s.m;
  return jsonb_build_object('asset_id', a.id, 'code', a.code, 'name', a.name, 'cost', a.cost, 'salvage', a.salvage, 'life_months', a.life_months, 'method', a.method, 'status', a.status, 'rows', rows_);
end $function$$r0_0$, null),
  ('public.fa_schedule(uuid)', 'known', '4f6c3a49f93c00f58c0505ea5d47d9d8', null);
-- gift_claim(uuid,uuid,bigint,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.gift_claim(uuid,uuid,bigint,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.gift_claim(p_customer uuid, p_gift uuid DEFAULT NULL::uuid, p_rule bigint DEFAULT NULL::bigint, p_occasion text DEFAULT NULL::text, p_sale uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g public.customer_gifts; due record; r public.gift_rules; ok boolean := false; sid text;
begin
  if not (public.is_active() and (public.can_do('POS', 'enter') or public._cust_mgr43())) then raise exception 'not allowed'; end if;
  if not public.rule_on('customer_gifts_on') then raise exception 'gifts_off'; end if;
  perform 1 from public.customers where id = p_customer and public._m132_own(customers.org_unit_id) /* m132b:customers */ for update;
  if not found then raise exception 'customer_not_found'; end if;
  if p_sale is not null and not exists (select 1 from public.sales where id = p_sale and customer_id = p_customer) then raise exception 'sale_not_found'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_gift is not null then
    select * into g from public.customer_gifts where id = p_gift and customer_id = p_customer for update;
    if not found then raise exception 'gift_not_found'; end if;
    if g.claimed_at is not null then return jsonb_build_object('dup', true, 'id', g.id, 'claimed_at', g.claimed_at); end if;
    if g.valid_until is not null and g.valid_until < public._today43() then raise exception 'gift_expired'; end if;
  else
    if p_rule is null or nullif(btrim(p_occasion), '') is null then raise exception 'bad_value'; end if;
    select * into g from public.customer_gifts where customer_id = p_customer and rule_id = p_rule and occasion = p_occasion for update;
    if found then
      if g.claimed_at is not null then return jsonb_build_object('dup', true, 'id', g.id, 'claimed_at', g.claimed_at); end if;
      if g.valid_until is not null and g.valid_until < public._today43() then raise exception 'gift_expired'; end if;
    else
      for due in select * from public.gifts_due(p_customer) x where x.rule_id = p_rule and x.occasion = p_occasion and not x.issued loop ok := true; end loop;
      if not ok then raise exception 'gift_not_due'; end if;
      select * into r from public.gift_rules where id = p_rule;
      insert into public.customer_gifts (customer_id, rule_id, occasion, gift_text_bn, gift_text_en, value_taka, issued_by, valid_until)
        values (p_customer, p_rule, p_occasion, r.gift_text_bn, r.gift_text_en, r.value_taka, auth.uid(), public._today43() + coalesce(r.valid_days, public.rule_num('gift_valid_days')::int, 30))
        on conflict do nothing returning * into g;
      if not found then select * into g from public.customer_gifts where customer_id = p_customer and rule_id = p_rule and occasion = p_occasion; end if;
      if g.claimed_at is not null then return jsonb_build_object('dup', true, 'id', g.id, 'claimed_at', g.claimed_at); end if;
    end if;
  end if;
  update public.customer_gifts set claimed_at = now(), claimed_by = auth.uid(), claimed_staff = sid, claimed_sale_id = p_sale where id = g.id;
  return jsonb_build_object('dup', false, 'id', g.id, 'claimed_at', now());
end $function$$r0_0$, null),
  ('public.gift_claim(uuid,uuid,bigint,text,uuid)', 'known', 'b99e7a30db187dd6167bb7704e059ea5', null);
-- gift_issue(uuid,text,text,numeric,date,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.gift_issue(uuid,text,text,numeric,date,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.gift_issue(p_customer uuid, p_text_bn text, p_text_en text, p_value numeric DEFAULT NULL::numeric, p_valid_until date DEFAULT NULL::date, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g public.customer_gifts; occ text;
begin
  if not public._cust_mgr43() then raise exception 'not allowed'; end if;
  if not public.rule_on('customer_gifts_on') then raise exception 'gifts_off'; end if;
  if coalesce(nullif(btrim(p_text_bn), ''), nullif(btrim(p_text_en), '')) is null then raise exception 'gift_text_required'; end if;
  if p_value is not null and (p_value = 'NaN'::numeric or p_value < 0 or p_value > 1e12) then raise exception 'bad_number'; end if;
  if p_valid_until is not null and (p_valid_until < public._today43() or p_valid_until > public._today43() + 3650) then raise exception 'bad_date'; end if;
  perform public._client_lock(p_client);
  occ := 'manual:' || coalesce(p_client::text, gen_random_uuid()::text);
  perform 1 from public.customers where id = p_customer and public._m132_own(customers.org_unit_id) /* m132b:customers */;
  if not found then raise exception 'customer_not_found'; end if;
  select * into g from public.customer_gifts where customer_id = p_customer and rule_id is null and occasion = occ;
  if found then return jsonb_build_object('dup', true, 'id', g.id); end if;
  insert into public.customer_gifts (customer_id, rule_id, occasion, gift_text_bn, gift_text_en, value_taka, issued_by, valid_until, note)
    values (p_customer, null, occ, left(nullif(btrim(p_text_bn), ''), 200), left(nullif(btrim(p_text_en), ''), 200), round(p_value, 2), auth.uid(),
            coalesce(p_valid_until, public._today43() + coalesce(public.rule_num('gift_valid_days')::int, 30)), left(nullif(btrim(p_note), ''), 300)) returning * into g;
  return jsonb_build_object('dup', false, 'id', g.id);
end $function$$r0_0$, null),
  ('public.gift_issue(uuid,text,text,numeric,date,text,uuid)', 'known', '0a021ac09e2e0a34005e6ad032727961', null);
-- gifts_due(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.gifts_due(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.gifts_due(p_customer uuid)
 RETURNS TABLE(gift_id uuid, rule_id bigint, occasion text, kind text, text_bn text, text_en text, value_taka numeric, valid_until date, issued boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.customers; st record; r public.gift_rules; today date := public._today43(); win int := coalesce(public.rule_num('gift_window_days'), 7)::int;
        y int; d date; occ text; vd int; k int;
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  if not public.rule_on('customer_gifts_on') then return; end if;
  select * into c from public.customers where id = p_customer and public._m132_own(customers.org_unit_id) /* m132b:customers */;
  if not found or not c.active then return; end if;
  -- already issued, not claimed, not expired
  return query select g.id, g.rule_id, g.occasion, coalesce(gr.trigger, 'manual'), g.gift_text_bn, g.gift_text_en, g.value_taka, g.valid_until, true
    from public.customer_gifts g left join public.gift_rules gr on gr.id = g.rule_id
    where g.customer_id = p_customer and g.claimed_at is null and (g.valid_until is null or g.valid_until >= today) order by g.issued_at;
  select * into st from public._cust_stats43(p_customer, false);
  for r in select * from public.gift_rules x where x.active and x.trigger <> 'manual' and (x.tier_id is null or x.tier_id = c.tier_id) order by x.id loop
    occ := null; vd := coalesce(r.valid_days, public.rule_num('gift_valid_days')::int, 30);
    if r.trigger in ('birthday', 'anniversary') then
      d := case r.trigger when 'birthday' then c.birthday else c.anniversary end;
      if d is not null then
        for y in extract(year from today)::int - 1 .. extract(year from today)::int + 1 loop
          if abs((make_date(y, 1, 1) + (to_char(d, 'DDD')::int - 1)) - today) <= win then occ := r.trigger || ':' || y; end if;
        end loop;
      end if;
    elsif r.trigger = 'first_purchase' then
      if st.orders >= 1 then occ := 'first'; end if;
    elsif r.trigger = 'every_n_purchases' then
      k := floor(st.orders / r.threshold)::int;
      if k >= 1 then occ := 'nth:' || k; end if;
    elsif r.trigger = 'spend_threshold' then
      if st.spend >= r.threshold then occ := 'spend:' || trim_scale(r.threshold)::text; end if;
    end if;
    if occ is not null and not exists (select 1 from public.customer_gifts g where g.customer_id = p_customer and g.rule_id = r.id and g.occasion = occ) then
      return query select null::uuid, r.id, occ, r.trigger, r.gift_text_bn, r.gift_text_en, r.value_taka, today + vd, false;
    end if;
  end loop;
end $function$$r0_0$, null),
  ('public.gifts_due(uuid)', 'known', 'f5f53befd6bbe4e16fe160fb2753dd27', null);
-- has_grant(text,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.has_grant(text,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.has_grant(p_code text, p_loc integer DEFAULT NULL::integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.is_owner() or (public.is_active() and (case when not coalesce((select (coalesce(r.value, r.default_value) #>> '{}')::boolean from public.rules r where r.key = 'org_scope_on'), false) then (   -- the switch read inline
    -- OFF: exactly the rule of phase8
    public.can_grant(p_code)
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = p_code
               and (g.valid_until is null or g.valid_until > now()) and (g.location_id is null or g.location_id = p_loc))
    or exists (select 1 from public.emergency_requests e join public.grant_defs d on d.grant_code = e.grant_code and d.window_type = 'window'
               where e.requested_by = auth.uid() and e.grant_code = p_code and e.status = 'approved' and e.valid_until > now()
               and (p_loc is null or e.location_id is null or e.location_id = p_loc)))
  else (
    -- ON (scope123 + scope133): with a location it must be one of the caller's businesses; the role matrix is the one of THAT business; a personal grant without a location = the caller's businesses
    (p_loc is null or public._biz_ok123(p_loc)) and (
      (case when p_loc is null then public.can_grant(p_code) else public._can_grant_in133(p_code, public._business_of_loc123(p_loc)) end)
      or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = p_code
                 and (g.valid_until is null or g.valid_until > now()) and (g.location_id is null or g.location_id = p_loc))
      or exists (select 1 from public.emergency_requests e join public.grant_defs d on d.grant_code = e.grant_code and d.window_type = 'window'
                 where e.requested_by = auth.uid() and e.grant_code = p_code and e.status = 'approved' and e.valid_until > now()
                 and (p_loc is null or e.location_id is null or e.location_id = p_loc)))
  ) end));
$function$$r0_0$, null),
  ('public.has_grant(text,integer)', 'known', '85f7d00b93db4bf6562506095ff35bc1', null);
-- inbox_board(integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.inbox_board(integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.inbox_board(p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l int[]; last_at timestamptz; hrs numeric := coalesce(public.rule_num('inbox_silence_hours'), 0); hs numeric; fcount int := 0;
begin
  if not public.is_active() or not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  if not public.rule_on('inbox_on') then return jsonb_build_object('on', false); end if;
  select coalesce(array_agg(x.id), '{}') into l from public.locations x where public.can_loc(x.id) and (p_loc is null or x.id = p_loc);
  select max(received_at) into last_at from public.inbound_messages where location_id = any (l);
  hs := case when last_at is null then null else round(extract(epoch from now() - last_at) / 3600, 1) end;
  if public.is_owner() or public.can_do('POS', 'approve') then select count(*) into fcount from public.intake_failures where state = 'failed'; end if;
  return jsonb_build_object('on', true,
    'new_count', (select count(*) from public.inbound_messages where location_id = any (l) and status = 'new'),
    'seen_count', (select count(*) from public.inbound_messages where location_id = any (l) and status = 'seen'),
    'last_at', last_at, 'hours_since', hs, 'silence_hours', hrs,
    'silent', hrs > 0 and hs is not null and hs > hrs,
    'failed_count', fcount,
    'dup_open', (select count(*) from public.order_dup_flags where location_id = any (l) and state = 'open'),
    'drafts', (select count(*) from public.online_orders where location_id = any (l) and is_draft and status = 'new'),
    'channels', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name_bn, 'kind', c.kind,
        'last_at', (select max(received_at) from public.inbound_messages m where m.channel_id = c.id),
        'new_count', (select count(*) from public.inbound_messages m where m.channel_id = c.id and m.status = 'new')) order by c.id)
        from public.sales_channels c where c.active and c.kind in ('facebook', 'instagram', 'whatsapp', 'telegram') and (c.location_id is null or c.location_id = any (l))), '[]'::jsonb));   -- bos86: + telegram
end $function$$r0_0$, null),
  ('public.inbox_board(integer)', 'known', '44c5e6a1347f85568728e2205aed00d0', null);
-- inbox_get(bigint)
insert into _u_plan (fn, kind, a, b) values
  ('public.inbox_get(bigint)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.inbox_get(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.inbound_messages; c public.sales_channels; ok boolean;
begin
  select * into m from public.inbound_messages where id = p_id;
  if not found then raise exception 'not_found'; end if;
  perform public._inb_gate(m.location_id, 'view');
  select * into c from public.sales_channels where id = m.channel_id;
  ok := public._inb_contact_ok(m.location_id);
  if ok then perform public._inb_audit_view('inbound_messages', m.id::text, jsonb_build_object('fields', 'handle,name,text,attachment')); end if;
  return jsonb_build_object('id', m.id, 'channel_id', m.channel_id, 'channel', c.name_bn, 'kind', c.kind, 'location_id', m.location_id, 'status', m.status, 'received_at', m.received_at, 'msg_time', m.msg_time,
    'linked_order_id', m.linked_order_id, 'draft_order_id', m.draft_order_id, 'masked', not ok,
    'handle', case when ok then public._inb_pii_f99('handle', m.customer_handle) end, 'name', case when ok then public._inb_pii_f99('name', m.customer_name) end, 'text', case when ok then public._inb_pii_f99('text', m.msg_text) end, 'attachment_ref', case when ok then public._inb_pii_f99('attachment', m.attachment_ref) end, 'pii_mode', public._inb_pii_mode99(),   /* bos99 */
    'events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_status, 'to', e.to_status, 'note', e.note, 'at', e.at) order by e.id) from public.inbound_message_events e where e.msg_id = m.id), '[]'::jsonb));
end $function$$r0_0$, null),
  ('public.inbox_get(bigint)', 'known', 'adb9e108a51bfb1fe0a762c993652745', null);
-- inbox_list(integer,text,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.inbox_list(integer,text,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.inbox_list(p_loc integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb; unmasked boolean := false; l int[];
begin
  perform public._inb_gate(p_loc, 'view');
  if p_status is not null and p_status not in ('new', 'seen', 'converted', 'ignored') then raise exception 'bad_input'; end if;
  select coalesce(array_agg(x.id), '{}') into l from public.locations x where public.can_loc(x.id) and (p_loc is null or x.id = p_loc);
  select coalesce(jsonb_agg(z.j order by z.rid desc), '[]'::jsonb) into r from (
    with lo as materialized (select x as id, public._inb_contact_ok(x) as ok from unnest(l) x),   -- perf110: the contact check once per place, not four times per row
         pm as materialized (select public._inb_pii_mode99() as m)
    select m.id rid, jsonb_build_object('id', m.id, 'channel_id', m.channel_id, 'channel', c.name_bn, 'kind', c.kind, 'location_id', m.location_id, 'status', m.status, 'received_at', m.received_at, 'msg_time', m.msg_time,
      'linked_order_id', m.linked_order_id, 'draft_order_id', m.draft_order_id, 'has_attachment', m.attachment_ref is not null,
      'handle', case when lo.ok then public._inb_pii_f99('handle', m.customer_handle) end, 'name', case when lo.ok then public._inb_pii_f99('name', m.customer_name) end,   /* bos99 */
      'text', case when lo.ok then left(public._inb_pii_f99('text', m.msg_text), 200) /* bos103: mask first, cut after */ end, 'masked', not lo.ok, 'pii_mode', pm.m) j   /* bos99 */
      from public.inbound_messages m join public.sales_channels c on c.id = m.channel_id join lo on lo.id = m.location_id cross join pm
     where m.location_id = any (l) and (p_status is null or m.status = p_status)
     order by m.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z;
  if exists (select 1 from jsonb_array_elements(r) e where (e->>'masked')::boolean is false) then
    perform public._inb_audit_view('inbound_messages', 'list', jsonb_build_object('count', jsonb_array_length(r), 'loc', p_loc, 'status', p_status));
  end if;
  return r;
end $function$$r0_0$, null),
  ('public.inbox_list(integer,text,integer)', 'known', '41de5df76cf6e81eebf968965e3a1aee', null);
-- intake_failures_list(text,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.intake_failures_list(text,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.intake_failures_list(p_state text DEFAULT NULL::text, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_active() or not (public.is_owner() or public.can_do('POS', 'approve')) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
    select f.id, f.kind, f.channel_id, f.external_id, f.error, f.attempts, f.next_try_at, f.last_try_at, f.state, f.created_at, f.done_at
      from public.intake_failures f where (p_state is null or f.state = p_state) and ((select not public._org_on123()) or public.is_owner() or exists (select 1 from public.sales_channels sc where sc.id = f.channel_id and public._biz_ok123(sc.location_id))) /* scope133 */ order by f.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
end $function$$r0_0$, null),
  ('public.intake_failures_list(text,integer)', 'known', 'e042a95d48fbaaaf3b0d6e385be5e4ce', null);
-- inventory_vs_gl(date,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.inventory_vs_gl(date,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.inventory_vs_gl(p_date date DEFAULT NULL::date, p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); d date := coalesce(p_date, public._acct_today()); t date := public._acct_today(); k text; acct bigint; acode text; anbn text; anen text;
        gl numeric; v numeric; rw record; rs jsonb; ex numeric; df numeric; rows_ jsonb := '[]'::jsonb; tg numeric := 0; tv numeric := 0; tx numeric := 0; basis text;
        g_open numeric; g_man numeric; j_adj numeric; j_issue numeric; j_xfer numeric; j_var numeric; /* bos85 */ g_prod numeric; g_pret numeric; ok boolean; j_skip numeric; j_prodin numeric; g_dup numeric; /* bos103 */
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if p_loc is null then
    if not public._acct_all() or exists (select 1 from public.locations l where public.can_loc(l.id) and not public._cost_ok(l.id)) then raise exception 'not allowed'; end if;
  elsif not (public.can_loc(p_loc) and public._cost_ok(p_loc)) then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  basis := case when d >= t then 'average_cost' else 'ledger_replay' end;
  foreach k in array array['inv_finished', 'inv_raw', 'inv_pack'] loop
    select m.account_id, a.code, a.name_bn, a.name_en into acct, acode, anbn, anen from public.acct_mappings m join public.coa_accounts a on a.id = m.account_id where m.key = k;
    if acct is null then continue; end if;
    select coalesce(sum(jl.debit - jl.credit), 0) into gl from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(x.v), 0) as lv_all, coalesce(sum(x.v) filter (where x.cib), 0) as lv_cib,
           coalesce(sum(x.v) filter (where x.reason = 'count_adjust'), 0) as g_count,
           coalesce(sum(x.v) filter (where x.reason = 'opening'), 0) as g_opening,
           coalesce(sum(x.v) filter (where x.reason in ('transfer_out', 'transfer_in') or x.ref_type = 'transfer'), 0) as g_transfer,
           coalesce(sum(x.v) filter (where x.reason = 'issue_out' and x.ref_type in ('issue', 'entry')), 0) as g_issue,
           coalesce(sum(x.v) filter (where (x.reason = 'production_in' and not x.has_run) or (x.reason = 'purchase_in' and x.ref_type = 'entry') or (x.reason = 'reversal' and x.ref_type = 'entry')), 0) as g_manual_in,
           coalesce(sum(x.v) filter (where x.reason = 'purchase_in' and x.ref_type = 'entry'), 0) as g_grn_in, /* bos103 */
           coalesce(sum(x.v) filter (where x.reason = 'purchase_in' and x.ref_type = 'purchase' and x.bill_date < st), 0) as g_prestart
      into rw
      from (select sl.reason, sl.ref_type, coalesce(sl.qty_delta * sl.unit_cost, 0) as v, it.count_in_business as cib,
                   exists (select 1 from public.production_runs pr where pr.id::text = sl.ref_id) as has_run,
                   (select b.bill_date from public.purchase_bills b where sl.ref_type = 'purchase' and b.id::text = sl.ref_id) as bill_date
            from public.stock_ledger_eff96 sl join public.items it on it.id = sl.item_id /* bos96 */
            where public._acct_inv_key(it.item_type) = k and (sl.made_at at time zone 'Asia/Dhaka')::date <= d and (p_loc is null or sl.location_id = p_loc)) x;
    v := case when basis = 'average_cost' then
            (select coalesce(sum(round(b.qty * b.avg_cost, 2)), 0) from public.stock_balance b join public.items it on it.id = b.item_id
              where it.count_in_business and public._acct_inv_key(it.item_type) = k and b.qty <> 0 and b.avg_cost is not null and (p_loc is null or b.location_id = p_loc))
          else rw.lv_cib end;
    -- journal side
    select coalesce(sum(jl.debit - jl.credit), 0) into g_open from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type in ('opening', 'stock_opening', 'opening_stock96') /* bos85 bos96 */ and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(jl.debit - jl.credit), 0) into g_man from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type = 'manual' and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(jl.debit), 0) into g_prod from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type = 'production' and e.reverses_id is null and e.flags like '%cogs_missing%'
        and not exists (select 1 from public.journal_entries r where r.reverses_id = e.id) and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(o.lo - o.jc), 0) into g_pret from (
        select b.id, coalesce((select sum(-sl.qty_delta * coalesce(sl.unit_cost, 0)) from public.stock_ledger_eff96 sl join public.items it on it.id = sl.item_id /* bos96 */
                                where sl.ref_type = 'purchase' and sl.reason = 'purchase_return' and sl.ref_id = b.id::text and public._acct_inv_key(it.item_type) = k), 0) as lo,
               coalesce((select sum(jl.credit - jl.debit) from public.journal_entries e join public.journal_lines jl on jl.entry_id = e.id
                          where e.source_type = 'purchase' and e.source_id = b.id::text and e.reverses_id is null and jl.account_id = acct), 0) as jc
        from public.purchase_bills b where b.kind = 'return' and b.status = 'posted' and b.bill_date <= d and (p_loc is null or b.location_id = p_loc)
          and not exists (select 1 from public.journal_entries r join public.journal_entries o2 on o2.id = r.reverses_id where o2.source_type = 'purchase' and o2.source_id = b.id::text)) o;
    select coalesce(sum(jl.debit - jl.credit) filter (where e.source_type = 'stock_adjust'), 0), coalesce(sum(jl.debit - jl.credit) filter (where e.source_type = 'stock_issue'), 0),
           coalesce(sum(jl.debit - jl.credit) filter (where e.source_type in ('stock_transfer', 'transit_loss')), 0), coalesce(sum(jl.debit - jl.credit) filter (where e.source_type = 'purchase_variance'), 0)
      into j_adj, j_issue, j_xfer, j_var from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and (p_loc is null or jl.location_id = p_loc);   -- bos85: what the new stock-movement entries put on this inventory account
    -- bos103: inventory a posted bill booked while it added no stock rows of its own (guard skip / link: the stock came from the GRN) covers GRN stock rows; direct production-in rows that were posted by acct_manual_prod_in103
    select coalesce(sum(jl.debit - jl.credit), 0) into j_skip from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id join public.purchase_bills pb on pb.id::text = e.source_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type = 'purchase' and e.reverses_id is null and pb.kind = 'bill' and (p_loc is null or jl.location_id = p_loc)
        and not exists (select 1 from public.journal_entries r where r.reverses_id = e.id)
        and not exists (select 1 from public.stock_ledger sl where sl.ref_type = 'purchase' and sl.reason = 'purchase_in' and sl.ref_id = pb.id::text);
    -- bos103: with GRN as the stock source, a bill that added its own stock after the first GRN stock row duplicates GRN stock (guard off): that part is NOT explained as manual_in, it stays in "unexplained"
    select coalesce(sum(coalesce(sl.qty_delta * sl.unit_cost, 0)), 0) into g_dup from public.stock_ledger_eff96 sl join public.items it on it.id = sl.item_id
      where public._acct_inv_key(it.item_type) = k and sl.reason = 'purchase_in' and sl.ref_type = 'purchase' and (sl.made_at at time zone 'Asia/Dhaka')::date <= d and (p_loc is null or sl.location_id = p_loc)
        and sl.made_at >= (select min(g.made_at) from public.stock_ledger g where g.reason = 'purchase_in' and g.ref_type = 'entry' and g.reverses_id is null)
        and not exists (select 1 from public.stock_ledger v where v.reverses_id = sl.id);
    select coalesce(sum(jl.debit - jl.credit), 0) into j_prodin from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type = 'stock_prodin' and (p_loc is null or jl.location_id = p_loc);
    df := round(gl - v, 2);
    rs := jsonb_build_array(
      jsonb_build_object('code', 'valuation_basis', 'amount', round(rw.lv_all - v, 2)),
      jsonb_build_object('code', 'count_adjust', 'amount', round(-rw.g_count + j_adj, 2)),   -- bos85
      jsonb_build_object('code', 'opening', 'amount', round(g_open - rw.g_opening, 2)),
      jsonb_build_object('code', 'transfer', 'amount', round(-rw.g_transfer + j_xfer, 2)),   -- bos85
      jsonb_build_object('code', 'issue_out', 'amount', round(-rw.g_issue + j_issue, 2)),   -- bos85
      jsonb_build_object('code', 'manual_in', 'amount', round(-rw.g_manual_in + least(greatest(j_skip, 0), greatest(rw.g_grn_in, 0)) + least(greatest(rw.g_grn_in - least(greatest(j_skip, 0), greatest(rw.g_grn_in, 0)), 0), greatest(g_dup, 0)) + j_prodin, 2)),   -- bos103
      jsonb_build_object('code', 'purchase_before_start', 'amount', round(-rw.g_prestart, 2)),
      jsonb_build_object('code', 'purchase_return_variance', 'amount', round(g_pret + j_var, 2)),   -- bos85
      jsonb_build_object('code', 'production_cost_missing', 'amount', round(g_prod, 2)),
      jsonb_build_object('code', 'manual_journal', 'amount', round(g_man, 2)));
    ex := df - (select coalesce(sum((x->>'amount')::numeric), 0) from jsonb_array_elements(rs) x);
    rows_ := rows_ || jsonb_build_object('key', k, 'code', acode, 'name_bn', anbn, 'name_en', anen, 'gl', round(gl, 2), 'valuation', round(v, 2), 'ledger_value', round(rw.lv_all, 2),
                'diff', df, 'reasons', (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(rs) x where abs((x->>'amount')::numeric) >= 0.005), 'unexplained', round(ex, 2));
    tg := tg + gl; tv := tv + v; tx := tx + ex;
  end loop;
  ok := abs(tg - tv) < 0.05;
  return jsonb_build_object('as_of', d, 'location_id', p_loc, 'start', st, 'accounting_on', public.rule_on('accounting_on'), 'valuation_basis', basis, 'rows', rows_,
    'total', jsonb_build_object('gl', round(tg, 2), 'valuation', round(tv, 2), 'diff', round(tg - tv, 2), 'unexplained', round(tx, 2)), 'agree', ok,
    'note', 'Read only: nothing is posted. Reasons are movements the books or the stock ledger do not have; "unexplained" is what is left.');
end $function$$r0_0$, null),
  ('public.inventory_vs_gl(date,integer)', 'known', 'fe8cd894585ad965a496be4d1e516893', null);
-- item_apply(uuid,jsonb,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.item_apply(uuid,jsonb,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.item_apply(p_item uuid, p_patch jsonb, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sid text; cid bigint; k text; iid uuid;
begin
  if p_item is null or p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'bad_request'; end if;
  if not exists (select 1 from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */) then raise exception 'item_not_found'; end if;
  if not (public.is_owner() or public.can_do('ITEMS', 'enter') or public.has_grant('item_create')) then raise exception 'not allowed'; end if;
  if p_patch ? 'cost_price' and not public.can_do('ITEM_COST', 'enter') then raise exception 'not allowed to change cost'; end if;
  if p_patch ? 'locked' and not public.is_owner() then raise exception 'not allowed'; end if;               -- only the owner locks / unlocks
  perform set_config('bos.item_apply', '1', true); perform public._item_patch_check(p_patch);
  if public.is_owner() or public.has_grant('item_create') then
    iid := public.apply_item_patch(p_item, p_patch); perform set_config('bos.item_apply', '', true);
    return jsonb_build_object('status', 'applied', 'item_id', iid);
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.item_changes (item_id, patch, note, requested_by, requested_staff) values (p_item, p_patch, left(p_note, 300), auth.uid(), sid) returning id into cid;
  perform set_config('bos.item_apply', '', true);
  return jsonb_build_object('status', 'pending', 'id', cid);
end $function$$r0_0$, null),
  ('public.item_apply(uuid,jsonb,text)', 'known', '5262f9672019bc7681cb7612b3615eae', null);
-- item_dup_check(text,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.item_dup_check(text,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.item_dup_check(p_name_bn text, p_name_en text, p_exclude uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, code text, name_bn text, name_en text, why text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select i.id, i.code, i.name_bn, i.name_en,
         case when lower(regexp_replace(i.name_bn, '\s+', '', 'g')) = lower(regexp_replace(coalesce(p_name_bn, ''), '\s+', '', 'g')) then 'same_name_bn' else 'same_name_en' end
  from public.items i
  where public.is_active() and public._m132_vis('items', i.org_unit_id, i.id::text, false) /* m132 */ and (p_exclude is null or i.id <> p_exclude)
    and ((nullif(btrim(p_name_bn), '') is not null and lower(regexp_replace(i.name_bn, '\s+', '', 'g')) = lower(regexp_replace(p_name_bn, '\s+', '', 'g')))
      or (nullif(btrim(p_name_en), '') is not null and i.name_en is not null and lower(regexp_replace(i.name_en, '\s+', '', 'g')) = lower(regexp_replace(p_name_en, '\s+', '', 'g'))))
  order by i.code limit 20;
$function$$r0_0$, null),
  ('public.item_dup_check(text,text,uuid)', 'known', '93569294281c61f7316e39bbe2ec674a', null);
-- item_map_accept_confident(boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.item_map_accept_confident(boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.item_map_accept_confident(p_dry boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; n int := 0; mn numeric; codes text[] := '{}'; skipped int := 0;
begin
  if not (public.is_owner() or public.has_grant('item_create')) then raise exception 'not allowed'; end if;
  mn := public.rule_num('item_map_accept_min_conf');
  for r in select m.* from public.item_mapping_review m where m.status in ('pending', 'later') and m.suggested_code is not null
           and (m.auto_ok or (mn is not null and m.confidence >= mn)) order by m.id loop
    if not exists (select 1 from public.items t where t.code = r.suggested_code and t.import_batch is not null and t.is_active)
       or exists (select 1 from public.item_master_links l where l.dict_code = r.suggested_code and l.active and l.item_id <> r.item_id)
       or exists (select 1 from public.items t where t.id = r.item_id and t.master_code is not null) then skipped := skipped + 1; continue; end if;
    begin
      if not coalesce(p_dry, true) then
        perform public._item_link(r.item_id, r.suggested_code, 'accepted', false);
        update public.item_mapping_review set status = 'linked', decided_by = auth.uid(), decided_at = now(), note = 'accepted (high confidence)' where id = r.id;
        insert into public.item_map_actions (item_id, dict_code, action, note, created_by) values (r.item_id, r.suggested_code, 'accept_all', 'high confidence', auth.uid());
      end if;
      n := n + 1; codes := codes || (select code from public.items where id = r.item_id and public._m132_own(items.org_unit_id) /* m132b:items */);
    exception when others then skipped := skipped + 1;
    end;
  end loop;
  return jsonb_build_object('dry', coalesce(p_dry, true), 'accepted', n, 'skipped', skipped, 'codes', to_jsonb(codes));
end $function$$r0_0$, null),
  ('public.item_map_accept_confident(boolean)', 'known', 'c2b1ebab661e7b4ff526b65e9291a664', null);
-- item_map_decide2(uuid,text,text,text,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.item_map_decide2(uuid,text,text,text,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.item_map_decide2(p_item uuid, p_action text, p_dict text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_force boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare lg public.items; dc public.items; rv public.item_mapping_review; act public.item_map_actions; aid bigint; f record; cur_status text; dstock boolean; bc_moved boolean := false;
begin
  if not (public.is_owner() or public.has_grant('item_create')) then raise exception 'not allowed'; end if;
  if p_action not in ('link', 'keep', 'later', 'use_dict', 'undo') then raise exception 'bad_request'; end if;
  select * into lg from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */ and import_batch is null;
  if not found then raise exception 'item_not_found'; end if;
  insert into public.item_mapping_review (item_id) values (p_item) on conflict (item_id) do nothing;
  select * into rv from public.item_mapping_review where item_id = p_item;
  cur_status := rv.status;

  if p_action = 'link' then
    if cur_status = 'replaced' then raise exception 'undo_first'; end if;
    perform public.item_mapping_decide(p_item, p_dict, 'linked', p_note, p_force);
    insert into public.item_map_actions (item_id, dict_code, action, note, created_by) values (p_item, btrim(p_dict), 'link', left(p_note, 300), auth.uid());
    return jsonb_build_object('status', 'linked');
  elsif p_action = 'keep' then
    if cur_status = 'replaced' then raise exception 'undo_first'; end if;
    perform public.item_mapping_decide(p_item, null, 'rejected', p_note);
    insert into public.item_map_actions (item_id, action, note, created_by) values (p_item, 'keep', left(p_note, 300), auth.uid());
    return jsonb_build_object('status', 'rejected');
  elsif p_action = 'later' then
    if cur_status = 'replaced' then raise exception 'undo_first'; end if;
    if cur_status in ('linked', 'rejected') then perform public.item_mapping_decide(p_item, null, 'pending', p_note); end if;
    update public.item_mapping_review set status = 'later', decided_by = auth.uid(), decided_at = now(), note = left(p_note, 300) where item_id = p_item;
    insert into public.item_map_actions (item_id, action, note, created_by) values (p_item, 'later', left(p_note, 300), auth.uid());
    return jsonb_build_object('status', 'later');
  elsif p_action = 'undo' then
    if cur_status = 'replaced' then
      if not public.is_owner() then raise exception 'not allowed'; end if;           -- undoing a replacement is the owner's only
      select * into act from public.item_map_actions a where a.item_id = p_item and a.action = 'use_dict'
         and not exists (select 1 from public.item_map_actions u where u.action = 'undo_use_dict' and u.ref_id = a.id) order by a.id desc limit 1;
      if not found then raise exception 'nothing_to_undo'; end if;
      select * into dc from public.items where code = act.dict_code and import_batch is not null;
      if (found and dc.locked) or lg.locked then raise exception 'item_locked'; end if;
      if found and not coalesce(p_force, false) and (dc.sell_price is distinct from (act.before->'dict'->>'new_price')::numeric) then raise exception 'changed_since'; end if;
      perform set_config('bos.item_sys', '1', true);
      if found then
        update public.items set sell_price = (act.before->'dict'->>'sell_price')::numeric, wholesale_price = (act.before->'dict'->>'wholesale_price')::numeric, unit = act.before->'dict'->>'unit',
          hidden = (act.before->'dict'->>'hidden')::boolean, sellable = (act.before->'dict'->>'sellable')::boolean, barcode = act.before->'dict'->>'barcode' where id = dc.id;
      end if;
      update public.items set barcode = coalesce(act.before->'legacy'->>'barcode', barcode) where id = p_item and act.before->'legacy'->>'barcode' is not null;
      update public.items set is_active = (act.before->'legacy'->>'is_active')::boolean, retired_at = (act.before->'legacy'->>'retired_at')::timestamptz,
        retired_reason = act.before->'legacy'->>'retired_reason' where id = p_item;
      perform set_config('bos.item_sys', '', true);
      update public.item_mapping_review set status = 'pending', decided_by = auth.uid(), decided_at = now(), note = left(p_note, 300) where item_id = p_item;
      insert into public.item_map_actions (item_id, dict_code, action, ref_id, note, created_by) values (p_item, act.dict_code, 'undo_use_dict', act.id, left(p_note, 300), auth.uid());
    else
      perform public.item_mapping_decide(p_item, null, 'pending', p_note);
      insert into public.item_map_actions (item_id, action, note, created_by) values (p_item, 'undo', left(p_note, 300), auth.uid());
    end if;
    return jsonb_build_object('status', 'pending');
  end if;

  -- use_dict
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if cur_status = 'replaced' then raise exception 'already_replaced'; end if;
  if lg.master_code is not null then raise exception 'unlink_first'; end if;
  if not lg.is_active then raise exception 'item_inactive'; end if;
  if lg.locked then raise exception 'item_locked'; end if;
  if lg.sell_price is null then raise exception 'legacy_has_no_price'; end if;
  if exists (select 1 from public.stock_balance where item_id = lg.id and qty <> 0) then raise exception 'legacy_has_stock'; end if;
  select * into dc from public.items where code = btrim(coalesce(p_dict, '')) and import_batch is not null for update;
  if not found then raise exception 'master_code_not_found'; end if;
  if not dc.is_active then raise exception 'dict_retired'; end if;
  if dc.locked then raise exception 'item_locked'; end if;
  if dc.item_type in ('asset', 'raw_material', 'packaging', 'consumable', 'controlled') and not coalesce(p_force, false) then raise exception 'master_type_mismatch'; end if;
  if exists (select 1 from public.item_master_links where dict_code = dc.code and active) then raise exception 'master_code_taken'; end if;
  if exists (select 1 from public.item_map_actions a where a.dict_code = dc.code and a.action = 'use_dict'
             and not exists (select 1 from public.item_map_actions u where u.action = 'undo_use_dict' and u.ref_id = a.id)) then raise exception 'master_code_taken'; end if;
  dstock := exists (select 1 from public.stock_balance where item_id = dc.id and qty <> 0);
  if dstock and dc.unit is distinct from lg.unit then raise exception 'dict_unit_has_stock'; end if;      -- never re-label units under stock (no override)
  if not coalesce(p_force, false) then                                                                        -- the owner can confirm these
    if dstock then raise exception 'dict_has_stock'; end if;
    if dc.sell_price is not null and dc.sell_price is distinct from lg.sell_price then raise exception 'dict_price_differs'; end if;
    if dc.unit is not null and dc.unit is distinct from lg.unit then raise exception 'dict_unit_differs'; end if;
  end if;
  select * into f from public._item_type_flags(dc.item_type);
  perform set_config('bos.item_sys', '1', true);
  insert into public.item_map_actions (item_id, dict_code, action, before, note, created_by) values (lg.id, dc.code, 'use_dict', jsonb_build_object(
      'dict', jsonb_build_object('sell_price', dc.sell_price, 'wholesale_price', dc.wholesale_price, 'unit', dc.unit, 'hidden', dc.hidden, 'sellable', dc.sellable, 'new_price', lg.sell_price, 'barcode', dc.barcode),
      'legacy', jsonb_build_object('is_active', lg.is_active, 'retired_at', lg.retired_at, 'retired_reason', lg.retired_reason, 'barcode', case when lg.barcode is not null and dc.barcode is null then lg.barcode end)), left(p_note, 300), auth.uid()) returning id into aid;
  if lg.barcode is not null and dc.barcode is null then            -- the barcode on the shelf now scans the dictionary item (the legacy one is cleared first: barcodes are unique)
    update public.items set barcode = null where id = lg.id; bc_moved := true;
  end if;
  update public.items set sell_price = lg.sell_price, wholesale_price = coalesce(lg.wholesale_price, wholesale_price), unit = lg.unit, hidden = false, sellable = coalesce(f.o_sell, sellable),
    barcode = case when bc_moved then lg.barcode else barcode end where id = dc.id;
  update public.items set is_active = false, retired_at = coalesce(retired_at, now()), retired_reason = 'replaced by ' || dc.code where id = lg.id;
  perform set_config('bos.item_sys', '', true);
  update public.item_mapping_review set status = 'replaced', suggested_code = dc.code, decided_by = auth.uid(), decided_at = now(), note = left(p_note, 300) where item_id = p_item;
  return jsonb_build_object('status', 'replaced', 'action_id', aid, 'dict_code', dc.code, 'barcode_moved', bc_moved, 'barcode_kept', (lg.barcode is not null and not bc_moved));
end $function$$r0_0$, null),
  ('public.item_map_decide2(uuid,text,text,text,boolean)', 'known', '61f9f1e6f906245b6169e9635b23a2bd', null);
-- item_mapping_decide(uuid,text,text,text,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.item_mapping_decide(uuid,text,text,text,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.item_mapping_decide(p_item uuid, p_dict text, p_status text, p_note text DEFAULT NULL::text, p_force boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare old_code text; tid uuid;
begin
  if not (public.is_owner() or public.has_grant('item_create')) then raise exception 'not allowed'; end if;
  if p_status not in ('linked', 'rejected', 'pending') then raise exception 'bad_request'; end if;
  if not exists (select 1 from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */ and import_batch is null) then raise exception 'item_not_found'; end if;
  insert into public.item_mapping_review (item_id) values (p_item) on conflict (item_id) do nothing;
  if p_status = 'linked' then
    if nullif(btrim(p_dict), '') is null then raise exception 'master_code_not_found'; end if;
    if coalesce(p_force, false) and not public.is_owner() then raise exception 'not allowed'; end if;
    perform public._item_link(p_item, btrim(p_dict), 'manual', p_force);
    update public.item_mapping_review set status = 'linked', suggested_code = coalesce(suggested_code, btrim(p_dict)), decided_by = auth.uid(), decided_at = now(), note = left(p_note, 300) where item_id = p_item;
  else
    select master_code into old_code from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;
    if old_code is not null then
      perform set_config('bos.item_sys', '1', true);
      update public.item_master_links set active = false, unlinked_at = now() where item_id = p_item and active;
      update public.items set master_code = null where id = p_item;
      select id into tid from public.items where code = old_code and import_batch is not null;
      if tid is not null then update public.items set hidden = false, sellable = (select o_sell from public._item_type_flags(items.item_type)) where id = tid; end if;
      perform set_config('bos.item_sys', '', true);
    end if;
    update public.item_mapping_review set status = p_status, decided_by = auth.uid(), decided_at = now(), note = left(p_note, 300) where item_id = p_item;
  end if;
  return jsonb_build_object('status', p_status);
end $function$$r0_0$, null),
  ('public.item_mapping_decide(uuid,text,text,text,boolean)', 'known', 'd6207b19cbf2dcb0fe81903f88f2c4b4', null);
-- item_master_import_apply(jsonb,text,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.item_master_import_apply(jsonb,text,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.item_master_import_apply(p_rows jsonb, p_batch text, p_expected integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; f record; nb boolean := false; cr int := 0; sk int := 0; rt int := 0; cf int := 0; seen int := 0; catv text; subv text; iid uuid; n int; confl jsonb := '[]'::jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then raise exception 'bad_request'; end if;
  if jsonb_array_length(p_rows) > 500 then raise exception 'too_many_rows'; end if;
  if p_batch is null or p_batch !~ '^[A-Za-z0-9_.:-]{3,60}$' then raise exception 'bad_batch'; end if;
  perform pg_advisory_xact_lock(hashtext('item_master_import'));              -- one chunk at a time
  perform set_config('bos.item_import', '1', true); perform set_config('bos.item_sys', '1', true);
  insert into public.item_import_batches (batch_id, started_by, expected_rows) values (p_batch, auth.uid(), p_expected) on conflict (batch_id) do nothing;
  get diagnostics n = row_count; nb := n > 0;
  for r in select * from public._item_master_classify(p_rows) loop
    seen := seen + 1;
    if r.status = 'conflict' then cf := cf + 1; if jsonb_array_length(confl) < 50 then confl := confl || jsonb_build_object('code', r.code, 'reason', r.reason); end if; continue; end if;
    if r.status = 'skip_existing' then sk := sk + 1; continue; end if;
    catv := 'c' || r.cat_no;
    insert into public.option_lists (list_code, value_code, label_bn, label_en, sort, extra)
      values ('item_categories', catv, '', r.category, r.cat_no::int, jsonb_build_object('cat_no', r.cat_no, 'source', 'dictionary')) on conflict (list_code, value_code) do nothing;
    subv := null;
    if r.subcategory <> '' then
      subv := catv || '_' || left(md5(lower(r.subcategory)), 8);
      insert into public.option_lists (list_code, value_code, label_bn, label_en, sort, extra)
        values ('item_subcategories', subv, '', r.subcategory, r.cat_no::int, jsonb_build_object('category', catv, 'cat_no', r.cat_no, 'source', 'dictionary')) on conflict (list_code, value_code) do nothing;
    end if;
    select * into f from public._item_type_flags(r.item_type);
    insert into public.items (code, name_bn, name_en, category, unit, sub_category, sell_price, is_active, item_type, control_class, count_in_business, sellable, tracked, source, import_batch, retired_at, retired_reason)
      values (r.code, coalesce(nullif(r.name_bn, ''), r.name_en), nullif(r.name_en, ''), catv, r.unit_code, subv, null, not r.retired, r.item_type, r.control_class,
              f.o_count and not r.retired, f.o_sell, false, case r.item_type when 'finished_good' then 'made' when 'resale' then 'bought' end, p_batch,
              case when r.retired then now() end, case when r.retired then left(coalesce(nullif(r.note, ''), 'Retired in the dictionary'), 200) end)
      on conflict (org_unit_id, code) /* m132 */ do nothing;
    get diagnostics n = row_count;
    if n = 0 then sk := sk + 1; continue; end if;
    cr := cr + 1; if r.retired then rt := rt + 1; end if;
  end loop;
  update public.item_import_batches set chunks = chunks + 1, rows_seen = rows_seen + seen, created = created + cr, skipped = skipped + sk, retired = retired + rt,
    conflicts = conflicts + cf, last_at = now(), expected_rows = coalesce(p_expected, expected_rows),
    detail = jsonb_set(detail, '{conflicts}', coalesce(detail->'conflicts', '[]'::jsonb) || confl) where batch_id = p_batch;
  if nb then      -- ONE audit line per batch (the per-row audit is switched off during the import)
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'import', 'items', p_batch, jsonb_build_object('batch', p_batch, 'source', 'item dictionary', 'expected_rows', p_expected));
  end if;
  begin perform public.item_mapping_autolink(); exception when undefined_function then null; end;
  perform set_config('bos.item_import', '', true); perform set_config('bos.item_sys', '', true);
  return jsonb_build_object('batch', p_batch, 'rows', seen, 'created', cr, 'skipped_existing', sk, 'retired_created', rt, 'conflicts', cf, 'conflict_list', confl);
end $function$$r0_0$, null),
  ('public.item_master_import_apply(jsonb,text,integer)', 'known', '417489316d983a75e9dbb0239e7f9d39', null);
-- item_new(jsonb,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.item_new(jsonb,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.item_new(p_patch jsonb, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sid text; cid bigint; iid uuid; direct boolean; ty text; cat text;
begin
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'bad_request'; end if;
  if not (public.is_owner() or public.can_do('ITEMS', 'enter') or public.has_grant('item_create')) then raise exception 'not allowed'; end if;
  if p_patch ? 'cost_price' and not public.can_do('ITEM_COST', 'enter') then raise exception 'not allowed to change cost'; end if;
  if p_patch ? 'locked' and not public.is_owner() then raise exception 'not allowed'; end if;
  if nullif(btrim(coalesce(p_patch->>'name_bn', p_patch->>'name_en')), '') is null then raise exception 'name_required'; end if;
  ty := coalesce(nullif(p_patch->>'item_type', ''), 'finished_good'); cat := nullif(btrim(p_patch->>'category'), '');
  if not exists (select 1 from public.item_types where code = ty and active) then raise exception 'bad_item_type'; end if;
  if cat is not null and not exists (select 1 from public.option_lists where list_code = 'item_categories' and value_code = cat and active)
     and not exists (select 1 from public.items where category = cat) then raise exception 'bad_category'; end if;
  direct := public.is_owner() or public.has_grant('item_create') or not public.rule_on('item_create_needs_approval');
  perform set_config('bos.item_apply', '1', true); perform public._item_patch_check(p_patch);
  if direct then
    iid := public.apply_item_patch(null, p_patch); perform set_config('bos.item_apply', '', true);
    return jsonb_build_object('status', 'created', 'item_id', iid, 'code', (select code from public.items where id = iid and public._m132_own(items.org_unit_id) /* m132b:items */));
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.item_changes (item_id, patch, note, requested_by, requested_staff) values (null, p_patch, left(p_note, 300), auth.uid(), sid) returning id into cid;
  perform set_config('bos.item_apply', '', true);
  return jsonb_build_object('status', 'pending', 'id', cid);
end $function$$r0_0$, null),
  ('public.item_new(jsonb,text)', 'known', 'dd04b5bbe99f986f5364a9cd738aa648', null);
-- items_with_cost()
insert into _u_plan (fn, kind, a, b) values
  ('public.items_with_cost()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.items_with_cost()
 RETURNS TABLE(item_id uuid, cost_price numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select c.item_id, c.cost_price from (
    select e.item_id, e.cost_price from public._item_cost_eff88() e where (select not public._org_on123() or public.is_owner())   -- bos88: the effective cost of the ONE source (report_cost_source); an item with no known cost has NO row = unknown, never 0
    union all
    select s.item_id, s.cost_price from public._item_cost_scoped123() s where (select public._org_on123() and not public.is_owner())   -- scope123: my own places only
  ) c
  -- a location-scoped personal view_cost grant counts too (the list is company wide, so any location grant is enough; role grants and the owner as before)
  where public.is_active() and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost')
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'view_cost' and (g.valid_until is null or g.valid_until > now())));
$function$$r0_0$, null),
  ('public.items_with_cost()', 'known', 'cce3ebb32149b8ae0541c35f4c8036aa', null);
do $u536$
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
  if miss <> '' then raise exception 'phase536: these functions have an unknown text, nothing was changed. Send this message to the agent:%', miss; end if;
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then
      execute rbody; nfix := nfix + 1; continue;
    end if;
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    insert into public._union_fn_backup (fn, why, def) values (f.fn, 'phase536: merged text of the two lines', cur);
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
  raise notice 'phase536: % function(s) changed', nfix;
end $u536$;
drop table if exists _u_plan;
