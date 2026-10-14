
-- =====================================================================================================================
-- shared small helpers
-- =====================================================================================================================
create or replace function public._t96(p_bn text, p_mix text, p_en text) returns jsonb language sql immutable as $$
  select jsonb_build_object('bn', p_bn, 'mix', p_mix, 'en', p_en);
$$;

-- who may see the costed numbers of a place (null = every place)
create or replace function public._d23_gate96(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and case when p_loc is null
    then (public._acct_all() and not exists (select 1 from public.locations l where public.can_loc(l.id) and not public._cost_ok(l.id)))
    else (public.can_loc(p_loc) and public._cost_ok(p_loc)) end;
$$;

-- =====================================================================================================================
-- D2 opening stock helper
-- =====================================================================================================================
-- one row per opening ledger row of the accounting period (costed or not), with what already happened to it
create or replace function public._ob_rows96(p_loc int)
returns table(lid bigint, loc int, k text, val numeric, nocost boolean, by_switch boolean, handled boolean)
language sql stable security definer set search_path = public as $$
  select l.id, l.location_id, public._acct_inv_key(it.item_type), round(l.qty_delta * coalesce(l.unit_cost, 0), 2), coalesce(l.unit_cost, 0) = 0,
         exists (select 1 from public.journal_entries e where e.source_type = 'stock_opening' and e.source_id = l.id::text and e.reverses_id is null),
         exists (select 1 from public.opening_stock_actions96 a where l.id = any (a.covered_ids) and (a.location_id is null or a.location_id = l.location_id))
  from public.stock_ledger_eff96 l join public.items it on it.id = l.item_id
  where l.reason = 'opening' and l.reverses_id is null and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id)
    and (p_loc is null or l.location_id = p_loc)
    and (l.made_at at time zone 'Asia/Dhaka')::date >= greatest(public._acct_start(), coalesce(public._acct_from85(), public._acct_start()));
$$;

-- what the opening journal (acct_opening) already carries on the inventory accounts, per place (null place = not split by place) and inventory key
create or replace function public._ob_cover96() returns table(loc int, k text, amt numeric)
language sql stable security definer set search_path = public as $$
  select jl.location_id, m.key, sum(jl.debit - jl.credit)
  from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
  join public.acct_mappings m on m.account_id = jl.account_id and m.key in ('inv_finished', 'inv_raw', 'inv_pack')
  where e.source_type = 'opening' and e.reverses_id is null and not exists (select 1 from public.journal_entries r where r.reverses_id = e.id)
  group by 1, 2;
$$;

-- the plan of one option: lines that would post, warnings, or an error code. No writes.
create or replace function public._ob_plan96(p_option text, p_loc int, p_account text, p_date date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); vals jsonb := '{}'::jsonb; cov jsonb := '{}'::jsonb; unt numeric := 0; k text; v numeric; c numeric; amt jsonb := '{}'::jsonb; tot numeric := 0;
        lines jsonb := '[]'::jsonb; ctr bigint; ctr_code text; acc public.coa_accounts; d date; n_unc int; sw numeric; warns jsonb := '[]'::jsonb; cov_all numeric; val_all numeric; maxlid bigint; cov_ids bigint[];
begin
  if st is null then return jsonb_build_object('ok', false, 'error', 'data_needed'); end if;
  if p_option is null or p_option not in ('owner_capital', 'existing_account', 'skip', 'difference') then return jsonb_build_object('ok', false, 'error', 'bad_option'); end if;
  if p_loc is null and p_option <> 'difference' then return jsonb_build_object('ok', false, 'error', 'place_needed'); end if;
  if p_loc is not null and not exists (select 1 from public.locations where id = p_loc) then return jsonb_build_object('ok', false, 'error', 'bad_location'); end if;
  if exists (select 1 from public.opening_stock_actions96 a where a.option <> 'skip' and (a.location_id is null or p_loc is null or a.location_id = p_loc)) then
    return jsonb_build_object('ok', false, 'error', 'already_applied'); end if;
  select coalesce(jsonb_object_agg(x.k, x.s), '{}'::jsonb) into vals from (select r.k, sum(r.val) s from public._ob_rows96(p_loc) r where not r.nocost and not r.by_switch and not r.handled group by r.k) x;
  select count(*) filter (where r.nocost and not r.by_switch and not r.handled), coalesce(sum(r.val) filter (where r.by_switch), 0) into n_unc, sw from public._ob_rows96(p_loc) r;
  select coalesce(jsonb_object_agg(x.k, x.s), '{}'::jsonb) into cov from (select o.k, sum(o.amt) s from public._ob_cover96() o where p_loc is null or o.loc = p_loc group by o.k) x;
  select coalesce(sum(o.amt), 0) into unt from public._ob_cover96() o where o.loc is null;
  if p_option = 'difference' and p_loc is not null and unt > 0 then return jsonb_build_object('ok', false, 'error', 'untagged_opening_inventory'); end if;
  d := coalesce(p_date, st);
  if d < st then return jsonb_build_object('ok', false, 'error', 'before_start'); end if;
  if d > public._acct_today() + 1 then return jsonb_build_object('ok', false, 'error', 'bad_date'); end if;
  select coalesce(sum(value::numeric), 0) into val_all from jsonb_each_text(vals);
  select coalesce(sum(value::numeric), 0) into cov_all from jsonb_each_text(cov);
  if n_unc > 0 then warns := warns || to_jsonb('uncosted_openings'::text); end if;
  if public.rule_on('acct_stock_opening') then warns := warns || to_jsonb('switch_on'::text); end if;
  if p_option = 'skip' then
    if cov_all + unt < val_all then warns := warns || to_jsonb('skip_but_not_in_opening_journal'::text); end if;
  else
    if p_option = 'existing_account' and p_account is null then return jsonb_build_object('ok', false, 'error', 'account_needed'); end if;
    if p_account is not null then
      select * into acc from public.coa_accounts a where a.code = p_account and a.active and not a.is_group and a.type in ('equity', 'liability')
        and not exists (select 1 from public.acct_mappings m where m.account_id = a.id and m.key in ('inv_finished', 'inv_raw', 'inv_pack'));
      if not found then return jsonb_build_object('ok', false, 'error', 'bad_account'); end if;
      ctr := acc.id; ctr_code := acc.code;
    elsif p_option <> 'existing_account' then
      select m.account_id, a.code into ctr, ctr_code from public.acct_mappings m join public.coa_accounts a on a.id = m.account_id where m.key = 'stock_opening_equity';
      if ctr is null then return jsonb_build_object('ok', false, 'error', 'mapping_missing:stock_opening_equity'); end if;
    end if;
    if p_option = 'owner_capital' and p_account is not null then return jsonb_build_object('ok', false, 'error', 'bad_option'); end if;   -- owner_capital always uses the stock_opening_equity mapping
    for k in select unnest(array['inv_finished', 'inv_raw', 'inv_pack']) loop
      v := coalesce((vals->>k)::numeric, 0); c := coalesce((cov->>k)::numeric, 0);
      if p_option = 'difference' then v := greatest(v - c, 0); end if;
      v := round(v, 2);
      if v > 0 then
        select a.id into maxlid from public.acct_mappings m join public.coa_accounts a on a.id = m.account_id where m.key = k;
        if maxlid is null then return jsonb_build_object('ok', false, 'error', 'mapping_missing:' || k); end if;
        amt := amt || jsonb_build_object(k, v); tot := tot + v;
        lines := lines || jsonb_build_object('account_id', maxlid, 'debit', v, 'credit', 0, 'location_id', p_loc, 'memo', 'Opening stock');
      end if;
    end loop;
    if tot <= 0 then return jsonb_build_object('ok', false, 'error', 'nothing_to_post', 'detail', jsonb_build_object('uncosted_rows', n_unc, 'posted_by_switch', sw)); end if;
    lines := lines || jsonb_build_object('account_id', ctr, 'debit', 0, 'credit', tot, 'location_id', p_loc, 'memo', 'Opening stock counterpart');
    if public._acct_locked(d) then return jsonb_build_object('ok', false, 'error', 'period_closed'); end if;
  end if;
  select coalesce(array_agg(r.lid order by r.lid) filter (where not r.handled and not r.by_switch and (p_option = 'skip' or not r.nocost)), '{}') into cov_ids from public._ob_rows96(p_loc) r;
  return jsonb_build_object('ok', true, 'option', p_option, 'location_id', p_loc, 'date', d, 'amount', tot, 'by_key', amt, 'counter_code', ctr_code, 'covered_ids_n', coalesce(array_length(cov_ids, 1), 0),
    'opening_value', val_all, 'already_in_opening_journal', cov_all, 'untagged_in_opening_journal', unt, 'uncosted_rows', n_unc, 'posted_by_switch', sw,
    'warnings', warns, 'covered_ids', cov_ids,
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', (x->>'debit')::numeric, 'credit', (x->>'credit')::numeric, 'location_id', p_loc)), '[]'::jsonb)
                from jsonb_array_elements(lines) x join public.coa_accounts a on a.id = (x->>'account_id')::bigint),
    'post_lines', lines);
end $$;

-- READ ONLY: per place the opening stock, what the opening journal already carries, the GL inventory, the valuation and their difference; warnings for the double count
create or replace function public.opening_stock_check96(p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); rowsj jsonb := '[]'::jsonb; l record; ov numeric; orows int; unc int; sw numeric; hd text; oj numeric; gl numeric; vl numeric; tov numeric := 0; toj numeric := 0; tgl numeric := 0; tvl numeric := 0;
        unt numeric; untgl numeric; warns jsonb := '[]'::jsonb; todo numeric := 0; risk boolean; sw_on boolean := public.rule_on('acct_stock_opening'); keys text[] := array['inv_finished', 'inv_raw', 'inv_pack'];
begin
  if not (public._acct_view() and public._d23_gate96(p_loc)) then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  for l in select x.id, x.name_bn, x.name_en from public.locations x where x.is_active and (p_loc is null or x.id = p_loc) and public.can_loc(x.id) and public._cost_ok(x.id) order by x.sort, x.id loop
    select coalesce(sum(r.val) filter (where not r.nocost and not r.handled and not r.by_switch), 0), count(*) filter (where not r.handled and not r.by_switch), count(*) filter (where r.nocost and not r.handled and not r.by_switch),
           coalesce(sum(r.val) filter (where r.by_switch), 0)
      into ov, orows, unc, sw from public._ob_rows96(l.id) r;
    select a.option into hd from public.opening_stock_actions96 a where a.location_id = l.id or a.location_id is null order by (a.option <> 'skip') desc, a.id desc limit 1;
    select coalesce(sum(o.amt), 0) into oj from public._ob_cover96() o where o.loc = l.id;
    select coalesce(sum(jl.debit - jl.credit), 0) into gl from public.journal_lines jl join public.acct_mappings m on m.account_id = jl.account_id and m.key = any (keys) where jl.location_id = l.id;
    select coalesce(sum(round(b.qty * b.avg_cost, 2)), 0) into vl from public.stock_balance b join public.items it on it.id = b.item_id
      where b.location_id = l.id and it.count_in_business and b.qty <> 0 and b.avg_cost is not null;
    rowsj := rowsj || jsonb_build_object('location_id', l.id, 'name_bn', l.name_bn, 'name_en', l.name_en, 'opening_value', ov, 'opening_rows', orows, 'uncosted_rows', unc, 'posted_by_switch', sw,
      'decision', hd, 'opening_journal_inventory', oj, 'gl_inventory', gl, 'valuation', vl, 'diff', round(gl - vl, 2));
    tov := tov + ov; toj := toj + oj; tgl := tgl + gl; tvl := tvl + vl; todo := todo + ov;
    if unc > 0 and not (warns ? 'uncosted_openings') then warns := warns || to_jsonb('uncosted_openings'::text); end if;
  end loop;
  select coalesce(sum(o.amt), 0) into unt from public._ob_cover96() o where o.loc is null;
  select coalesce(sum(jl.debit - jl.credit), 0) into untgl from public.journal_lines jl join public.acct_mappings m on m.account_id = jl.account_id and m.key = any (keys) where jl.location_id is null;
  toj := toj + unt; tgl := tgl + untgl;
  risk := toj > 0 and todo > 0;
  if toj > 0 then warns := warns || to_jsonb('opening_journal_has_inventory'::text); end if;
  if risk and sw_on then warns := warns || to_jsonb('switch_on_double_count'::text);
  elsif risk then warns := warns || to_jsonb('switch_would_double_count'::text); end if;
  if unt > 0 then warns := warns || to_jsonb('opening_journal_not_split_by_place'::text); end if;
  return jsonb_build_object('start', st, 'accounting_on', public.rule_on('accounting_on'), 'switch_on', sw_on, 'rows', rowsj,
    'untagged', jsonb_build_object('opening_journal_inventory', unt, 'gl_inventory', untgl),
    'total', jsonb_build_object('opening_value', tov, 'opening_journal_inventory', toj, 'gl_inventory', tgl, 'valuation', tvl, 'diff', round(tgl - tvl, 2)),
    'risk', risk, 'warnings', warns,
    'note', jsonb_build_object('bn', 'শুধু দেখা: কিছু post হয়নি। শুরুর জের (opening journal) এ stock আগেই থাকলে acct_stock_opening চালালে দুইবার গোনা হবে।',
      'mix', 'Read only: কিছু post হয়নি। Opening journal এ stock আগেই থাকলে acct_stock_opening চালালে দুইবার গোনা হবে।',
      'en', 'Read only: nothing is posted. If the stock is already in the opening journal, turning acct_stock_opening on would count it twice.'));
end $$;

-- DRY RUN: the entry an option would post, or the reason it cannot. No writes.
create or replace function public.opening_stock_preview96(p_option text, p_loc int default null, p_account text default null, p_date date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pl jsonb;
begin
  if not (public._acct_view() and public._d23_gate96(p_loc)) then raise exception 'not allowed'; end if;
  pl := public._ob_plan96(p_option, p_loc, p_account, p_date) - 'post_lines' - 'covered_ids';
  return pl || jsonb_build_object('dry', true);
end $$;

-- APPLY: owner only, audited (decision table + journal entry), idempotent by client id, one posting per place
create or replace function public.opening_stock_apply96(p_option text, p_loc int, p_account text default null, p_date date default null, p_reason text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pl jsonb; eid bigint; aid bigint; r public.opening_stock_actions96; staff text;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if p_client is null then raise exception 'client_id_needed'; end if;
  perform public._client_lock(p_client);
  select * into r from public.opening_stock_actions96 where client_id = p_client;
  if found then return jsonb_build_object('dup', true, 'id', r.id, 'option', r.option, 'entry_id', r.entry_id); end if;
  perform pg_advisory_xact_lock(hashtextextended('opening_stock96', 0));
  pl := public._ob_plan96(p_option, p_loc, p_account, p_date);
  if not (pl->>'ok')::boolean then raise exception '%', pl->>'error' using detail = left(coalesce(pl->>'detail', ''), 500); end if;
  select staff_id into staff from public.profiles where id = auth.uid();
  if p_option <> 'skip' then
    eid := public._acct_write((pl->>'date')::date, p_loc, 'opening_stock96', 'loc:' || coalesce(p_loc::text, 'all'), p_option,
             'Opening stock (' || p_option || ')' || coalesce(': ' || nullif(btrim(p_reason), ''), ''), null, pl->'post_lines', null, p_client, null);
  end if;
  insert into public.opening_stock_actions96 (location_id, option, account_code, amount, entry_id, covered_ids, reason, client_id, created_by, created_staff)
    values (p_loc, p_option, case when p_option in ('existing_account', 'difference') then p_account end, coalesce((pl->>'amount')::numeric, 0), eid, (select coalesce(array_agg(x::bigint), '{}') from jsonb_array_elements_text(pl->'covered_ids') x),
            left(nullif(btrim(p_reason), ''), 300), p_client, auth.uid(), staff) returning id into aid;
  return jsonb_build_object('id', aid, 'option', p_option, 'location_id', p_loc, 'entry_id', eid, 'amount', coalesce((pl->>'amount')::numeric, 0), 'warnings', pl->'warnings');
end $$;

-- RECOMMENDATION from the numbers (never applied by itself)
create or replace function public.opening_stock_recommend96(p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v numeric; cv numeric; unt numeric; n_unc int; scope int := p_loc; opt text; why jsonb; alts jsonb := '[]'::jsonb; o text; pl jsonb; handled text;
begin
  if not (public._acct_view() and public._d23_gate96(p_loc)) then raise exception 'not allowed'; end if;
  if public._acct_start() is null then return jsonb_build_object('data_needed', true, 'never_auto', true); end if;
  select coalesce(sum(o2.amt), 0) into unt from public._ob_cover96() o2 where o2.loc is null;
  if unt > 0 and p_loc is not null then scope := null; end if;            -- the opening journal is not split by place: judge the whole company
  select coalesce(sum(r.val) filter (where not r.nocost and not r.handled and not r.by_switch), 0), count(*) filter (where r.nocost and not r.handled and not r.by_switch)
    into v, n_unc from public._ob_rows96(scope) r;
  select coalesce(sum(o2.amt), 0) into cv from public._ob_cover96() o2 where scope is null or o2.loc = scope or o2.loc is null;
  select a.option into handled from public.opening_stock_actions96 a where scope is null or a.location_id is null or a.location_id = scope order by (a.option <> 'skip') desc, a.id desc limit 1;
  if handled is not null and v = 0 then
    opt := 'none'; why := public._t96('এই opening stock নিয়ে সিদ্ধান্ত আগেই নেওয়া হয়েছে; আর কিছু করার নেই।', 'এই opening stock নিয়ে decision আগেই নেওয়া হয়েছে; আর কিছু করার নেই।', 'A decision about this opening stock was already taken; nothing more to do.');
  elsif v = 0 and n_unc > 0 then
    opt := 'wait_for_cost'; why := public._t96('opening stock এর cost জানা নেই; আগে cost দিন (cost waiting list), তারপর অপশন বেছে নিন।', 'Opening stock এর cost জানা নেই; আগে cost দিন (cost waiting list), তারপর option বাছুন।', 'The cost of the opening stock is unknown; supply the cost first (cost waiting list), then choose an option.');
  elsif v = 0 then
    opt := 'none'; why := public._t96('post করার মতো opening stock নেই।', 'Post করার মতো opening stock নেই।', 'There is no opening stock to post.');
  elsif cv > 0 and cv >= v then
    opt := 'skip'; why := public._t96('শুরুর জের (opening journal) এ stock এর টাকা আগেই ধরা আছে; আবার ধরলে দুইবার গোনা হবে। তাই সিদ্ধান্ত লিখে রাখুন, কিছু post করবেন না।', 'Opening journal এ stock এর টাকা আগেই ধরা আছে; আবার ধরলে দুইবার গোনা হবে। তাই decision লিখে রাখুন, কিছু post করবেন না।', 'The opening journal already carries the stock value; posting again would count it twice. Record the decision and post nothing.');
  elsif cv > 0 then
    opt := 'difference'; why := public._t96('শুরুর জের এ stock এর টাকা আংশিক ধরা আছে; শুধু বাকি অংশটুকু post করুন।', 'Opening journal এ stock এর টাকা আংশিক ধরা আছে; শুধু বাকি অংশটুকু post করুন।', 'The opening journal carries only part of the stock value; post only the part that is missing.');
  else
    opt := 'owner_capital'; why := public._t96('শুরুর জের এ stock নেই; opening stock মালিকের মূলধনের বিপরীতে ধরাই সবচেয়ে যুক্তিসঙ্গত।', 'Opening journal এ stock নেই; opening stock owner capital এর against এ ধরাই সবচেয়ে যুক্তিসঙ্গত।', 'The opening journal has no stock; booking the opening stock against owner capital is the most reasonable choice.');
  end if;
  foreach o in array array['owner_capital', 'existing_account', 'skip', 'difference'] loop
    pl := public._ob_plan96(case when o = 'existing_account' then 'owner_capital' else o end, scope, null, null);
    alts := alts || jsonb_build_object('option', o, 'amount', case when o = 'skip' then 0 else coalesce((pl->>'amount')::numeric, 0) end, 'possible', coalesce((pl->>'ok')::boolean, false),
              'error', case when coalesce((pl->>'ok')::boolean, false) then null else pl->>'error' end, 'needs_account', o = 'existing_account');
  end loop;
  return jsonb_build_object('location_id', p_loc, 'scope_location_id', scope, 'recommended', opt, 'reason', why, 'numbers', jsonb_build_object('opening_value', v, 'already_in_opening_journal', cv, 'uncosted_rows', n_unc),
    'alternatives', alts, 'never_auto', true);
end $$;

-- a warning in the audit trail when acct_stock_opening is turned ON while the opening journal already carries inventory
create or replace function public._ob_rule_watch96() returns trigger language plpgsql security definer set search_path = public as $$
declare toj numeric; todo numeric; sid text;
begin
  if new.key = 'acct_stock_opening' and coalesce(new.value, new.default_value) = 'true'::jsonb and coalesce(old.value, old.default_value) is distinct from 'true'::jsonb then
    select coalesce(sum(o.amt), 0) into toj from public._ob_cover96() o;
    select coalesce(sum(r.val) filter (where not r.nocost and not r.handled and not r.by_switch), 0) into todo from public._ob_rows96(null) r;
    if toj > 0 and todo > 0 then
      select staff_id into sid from public.profiles where id = auth.uid();
      insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
        values (auth.uid(), sid, 'warn', 'rules', 'acct_stock_opening', jsonb_build_object('code', 'switch_on_double_count', 'opening_journal_inventory', toj, 'opening_stock_to_post', todo));
    end if;
  end if;
  return new;
end $$;
drop trigger if exists rules_watch_opening96 on public.rules;
create trigger rules_watch_opening96 after update on public.rules for each row execute function public._ob_rule_watch96();

-- =====================================================================================================================
-- D3 cost waiting
-- =====================================================================================================================
-- the ledger rows of one document that still have no cost (cost 0 = unknown, "cost really zero" items excluded, reversed rows excluded)
create or replace function public._cw_rows96(p_kind text, p_ref text)
returns table(lid bigint, item_id uuid, loc int, qty numeric, reason text, made_at timestamptz)
language sql stable security definer set search_path = public as $$
  select l.id, l.item_id, l.location_id, l.qty_delta, l.reason, l.made_at
  from public.stock_ledger_eff96 l
  where coalesce(l.unit_cost, 0) = 0 and l.reverses_id is null and l.reason <> 'reversal' and not public._cost_free80(l.item_id)
    and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id)
    and (l.reason <> 'transfer_in' or not exists (select 1 from public.stock_ledger_eff96 s where s.reason = 'transfer_out' and s.ref_type is not distinct from l.ref_type
                                                    and s.ref_id is not distinct from l.ref_id and s.item_id = l.item_id and coalesce(s.unit_cost, 0) > 0))
    and not (l.reason = 'opening' and exists (select 1 from public.opening_stock_actions96 a where l.id = any (a.covered_ids) and (a.location_id is null or a.location_id = l.location_id)))
    and case p_kind
      when 'wastage' then l.reason = 'wastage' and l.ref_type = 'wastage' and l.ref_id = p_ref
      when 'production' then l.reason = 'issue_out' and l.ref_type = 'production' and l.ref_id = p_ref
      when 'transfer' then l.reason in ('transfer_out', 'transfer_in') and l.ref_type = 'transfer' and l.ref_id = p_ref
      when 'purchase_return' then l.reason = 'purchase_return' and l.ref_type = 'purchase' and l.ref_id = p_ref
      when 'ledger' then l.id::text = p_ref and (l.reason in ('count_adjust', 'opening') or (l.reason = 'issue_out' and l.ref_type is distinct from 'production'))
      else false end;
$$;

-- is the document already in the journal (then a late cost cannot post it again)
create or replace function public._cw_posted96(p_kind text, p_ref text) returns boolean language sql stable security definer set search_path = public as $$
  select case p_kind
    when 'wastage' then exists (select 1 from public.journal_entries e where e.source_type = 'wastage' and e.source_id = p_ref and e.reverses_id is null)
    when 'production' then exists (select 1 from public.journal_entries e where e.source_type = 'production' and e.source_id = p_ref and e.reverses_id is null)
    when 'purchase_return' then exists (select 1 from public.journal_entries e where e.source_type = 'purchase_variance' and e.source_id = p_ref and e.reverses_id is null)
    when 'transfer' then exists (select 1 from public.journal_entries e where e.reverses_id is null and ((e.source_type = 'stock_transfer' and e.source_id in
                                   (select s.id::text from public.stock_ledger s where s.ref_type = 'transfer' and s.ref_id = p_ref)) or (e.source_type = 'transit_loss' and e.source_id = p_ref)))
    when 'ledger' then exists (select 1 from public.journal_entries e where e.source_type in ('stock_adjust', 'stock_opening', 'stock_issue') and e.source_id = p_ref and e.reverses_id is null)
    else false end;
$$;

-- every document that waits for a cost and is not in the journal yet
create or replace function public._cw_docs96() returns table(kind text, ref text, loc int, d date, n int, gl boolean, move text)
language sql stable security definer set search_path = public as $$
  with u as (
    select l.id, l.location_id, l.reason, l.ref_type, l.ref_id, (l.made_at at time zone 'Asia/Dhaka')::date dd,
      case when l.reason = 'wastage' and l.ref_type = 'wastage' then 'wastage'
           when l.reason = 'issue_out' and l.ref_type = 'production' then 'production'
           when l.reason in ('transfer_out', 'transfer_in') and l.ref_type = 'transfer' then 'transfer'
           when l.reason = 'purchase_return' and l.ref_type = 'purchase' then 'purchase_return'
           when l.reason in ('count_adjust', 'opening') or (l.reason = 'issue_out' and l.ref_type is distinct from 'production') then 'ledger' end k
    from public.stock_ledger_eff96 l
    where coalesce(l.unit_cost, 0) = 0 and l.reverses_id is null and l.reason <> 'reversal' and not public._cost_free80(l.item_id)
      and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id)
      and (l.reason <> 'transfer_in' or not exists (select 1 from public.stock_ledger_eff96 s where s.reason = 'transfer_out' and s.ref_type is not distinct from l.ref_type
                                                      and s.ref_id is not distinct from l.ref_id and s.item_id = l.item_id and coalesce(s.unit_cost, 0) > 0))
      and not (l.reason = 'opening' and exists (select 1 from public.opening_stock_actions96 a where l.id = any (a.covered_ids) and (a.location_id is null or a.location_id = l.location_id)))),
  g as (
    select u.k, case when u.k = 'ledger' then u.id::text else u.ref_id end ref, (array_agg(u.location_id order by u.id))[1] loc, min(u.dd) d, count(*)::int n, min(u.reason) r
    from u where u.k is not null group by 1, 2)
  select g.k, g.ref, g.loc, g.d, g.n,
         public.rule_on('accounting_on') and public._acct_start() is not null and g.d >= public._acct_start() and g.d >= coalesce(public._acct_from85(), public._acct_start())
         and case g.k when 'wastage' then true when 'production' then true when 'transfer' then coalesce(public.rule_txt('acct_transfer_mode'), 'off') = 'location_tagged'
                      when 'purchase_return' then public.rule_on('acct_purchase_variance')
                      else case g.r when 'count_adjust' then public.rule_on('acct_count_adjust') when 'opening' then public.rule_on('acct_stock_opening') else public.rule_on('acct_issue_out') end end,
         g.r
  from g where g.ref is not null and not public._cw_posted96(g.k, g.ref);
$$;

-- candidate costs of an item at a place: average, last purchase before the movement, recipe standard
create or replace function public._cw_cands96(p_item uuid, p_loc int, p_at timestamptz) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare av numeric; lb numeric; rc numeric; rid uuid; j jsonb;
begin
  select b.avg_cost into av from public.stock_balance b where b.item_id = p_item and b.location_id = p_loc;
  if coalesce(av, 0) <= 0 then
    select sum(b.qty * b.avg_cost) / nullif(sum(b.qty), 0) into av from public.stock_balance b where b.item_id = p_item and b.qty > 0 and b.avg_cost > 0;
  end if;
  if coalesce(av, 0) <= 0 then av := null; else av := round(av, 6); end if;
  select l.unit_cost into lb from public.stock_ledger_eff96 l where l.item_id = p_item and l.reason = 'purchase_in' and coalesce(l.unit_cost, 0) > 0 and l.made_at <= p_at order by l.made_at desc, l.id desc limit 1;
  select r.id into rid from public.recipes r where r.item_id = p_item and r.active order by r.version desc limit 1;
  if rid is not null then
    begin j := public.recipe_cost(rid, p_loc); rc := nullif(j->>'unit_cost', '')::numeric; if coalesce(rc, 0) <= 0 then rc := null; end if;
    exception when others then rc := null; end;
  end if;
  return jsonb_build_object('item_average', av, 'last_purchase', lb, 'recipe_standard', rc);
end $$;

create or replace function public._cw_manual96(p_manual jsonb, p_item uuid, p_groups int) returns numeric
language plpgsql immutable as $$
begin
  if p_manual is null then return null; end if;
  return case jsonb_typeof(p_manual)
    when 'array' then (select nullif(btrim(e->>'cost'), '')::numeric from jsonb_array_elements(p_manual) e where e->>'item_id' = p_item::text limit 1)
    when 'object' then nullif(btrim(p_manual->>(p_item::text)), '')::numeric
    when 'number' then case when p_groups = 1 then (p_manual #>> '{}')::numeric end
    else null end;
exception when others then return -1;
end $$;

-- THE PLAN: which cost each item of the document would get with a method (or the recommended one). No writes.
create or replace function public._cw_plan96(p_kind text, p_ref text, p_method text, p_manual jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare g record; c jsonb; m text; cost numeric; items_ jsonb := '[]'::jsonb; total numeric := 0; missing text[] := '{}'; ng int; qa numeric; derived jsonb := '[]'::jsonb; locs int[] := '{}';
        ing numeric; conv numeric; pin record; ing_ok boolean := true; bad_manual boolean := false; alts jsonb; rec text; need_manual jsonb := '[]'::jsonb;
begin
  if p_kind is null or p_kind not in ('wastage', 'production', 'transfer', 'purchase_return', 'ledger') then return jsonb_build_object('ok', false, 'error', 'bad_kind'); end if;
  if p_method is null or p_method not in ('item_average', 'last_purchase', 'recipe_standard', 'manual', 'recommended') then return jsonb_build_object('ok', false, 'error', 'bad_method'); end if;
  select count(distinct r.item_id) into ng from public._cw_rows96(p_kind, p_ref) r;
  if ng = 0 then return jsonb_build_object('ok', false, 'error', 'nothing_waiting'); end if;
  select coalesce(array_agg(distinct r.loc), '{}') into locs from public._cw_rows96(p_kind, p_ref) r;
  for g in select r.item_id, array_agg(r.lid order by r.lid) lids, (array_agg(r.loc order by r.lid))[1] loc, min(r.made_at) made_at,
                  sum(abs(r.qty)) filter (where r.reason <> 'transfer_in') q_main, sum(abs(r.qty)) q_all, it.code, it.name_bn, it.name_en, it.base_unit
             from public._cw_rows96(p_kind, p_ref) r join public.items it on it.id = r.item_id group by r.item_id, it.code, it.name_bn, it.name_en, it.base_unit order by it.code loop
    qa := coalesce(g.q_main, g.q_all);
    c := public._cw_cands96(g.item_id, g.loc, g.made_at);
    m := p_method;
    if m = 'recommended' then
      m := case when c->>'recipe_standard' is not null then 'recipe_standard' when c->>'item_average' is not null then 'item_average' when c->>'last_purchase' is not null then 'last_purchase' else 'manual' end;
    end if;
    if m = 'manual' then cost := public._cw_manual96(p_manual, g.item_id, ng); else cost := nullif(c->>m, '')::numeric; end if;
    if cost is not null and cost < 0 then bad_manual := true; cost := null; end if;
    if cost is not null and (cost <= 0 or cost >= 1000000000000) then bad_manual := true; cost := null; end if;
    if cost is null then
      if p_method = 'recommended' then need_manual := need_manual || to_jsonb(g.code); else missing := missing || g.code; end if;
    end if;
    rec := case when c->>'recipe_standard' is not null then 'recipe_standard' when c->>'item_average' is not null then 'item_average' when c->>'last_purchase' is not null then 'last_purchase' else 'manual' end;
    alts := (select coalesce(jsonb_agg(jsonb_build_object('method', k, 'unit_cost', nullif(c->>k, '')::numeric, 'amount', round(qa * nullif(c->>k, '')::numeric, 2))), '[]'::jsonb)
               from unnest(array['item_average', 'last_purchase', 'recipe_standard']) k where c->>k is not null);
    items_ := items_ || jsonb_build_object('item_id', g.item_id, 'code', g.code, 'name_bn', g.name_bn, 'name_en', g.name_en, 'unit', g.base_unit, 'qty', qa, 'location_id', g.loc, 'lids', to_jsonb(g.lids),
               'method', m, 'unit_cost', cost, 'amount', case when cost is not null then round(qa * cost, 2) end, 'recommended', rec, 'candidates', c, 'alternatives', alts,
               'reason', case rec when 'recipe_standard' then public._t96('এই item নিজেদের তৈরি; recipe এর standard cost ধরাই সবচেয়ে যুক্তিসঙ্গত।', 'এই item নিজেদের তৈরি; recipe এর standard cost ধরাই সবচেয়ে যুক্তিসঙ্গত।', 'This item is made in-house; the recipe standard cost is the most reasonable figure.')
                                  when 'item_average' then public._t96('stock এ এই item এর average cost আগে থেকেই আছে; এটি ধরলে খাতা আর stock valuation এক থাকে।', 'Stock এ এই item এর average cost আগে থেকেই আছে; এটি ধরলে খাতা আর stock valuation এক থাকে।', 'The stock already carries this item at its average cost; using it keeps the books and the stock valuation in step.')
                                  when 'last_purchase' then public._t96('average cost জানা নেই; সবচেয়ে সাম্প্রতিক কেনা cost সবচেয়ে কাছের প্রমাণ।', 'Average cost জানা নেই; সবচেয়ে recent purchase cost-ই সবচেয়ে কাছের প্রমাণ।', 'No average cost is known; the latest purchase cost is the closest evidence.')
                                  else public._t96('কোনো cost জানা নেই; নিজে cost লিখুন ও কারণ দিন, সিস্টেম কিছু ধরে নেয় না।', 'কোনো cost জানা নেই; নিজে cost লিখুন ও reason দিন, system কিছু ধরে নেয় না।', 'No cost is known; type the cost and give a reason - the system assumes nothing.') end);
    total := total + coalesce(round(qa * cost, 2), 0);
  end loop;
  if bad_manual then return jsonb_build_object('ok', false, 'error', 'bad_manual', 'items', items_); end if;
  if coalesce(array_length(missing, 1), 0) > 0 then return jsonb_build_object('ok', false, 'error', 'cost_unavailable', 'detail', array_to_string(missing, ','), 'items', items_); end if;
  -- the finished good of a production run: ingredient cost + conversion cost, per unit (a record for the ledger valuation; the stock average cache is not changed)
  if p_kind = 'production' and jsonb_array_length(need_manual) = 0 then
    select coalesce(sum(abs(l.qty_delta) * l.unit_cost) filter (where coalesce(l.unit_cost, 0) > 0), 0) + total into ing from public.stock_ledger_eff96 l
      where l.ref_type = 'production' and l.ref_id = p_ref and l.reason = 'issue_out' and l.reverses_id is null;
    select coalesce(r.conversion_cost, 0) into conv from public.production_runs r where r.id::text = p_ref;
    for pin in select l.item_id, array_agg(l.id order by l.id) lids, sum(l.qty_delta) q from public.stock_ledger_eff96 l
                where l.ref_type = 'production' and l.ref_id = p_ref and l.reason = 'production_in' and coalesce(l.unit_cost, 0) = 0 and l.reverses_id is null
                  and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id) group by l.item_id loop
      if pin.q > 0 and ing + coalesce(conv, 0) > 0 then
        derived := derived || jsonb_build_object('item_id', pin.item_id, 'lids', to_jsonb(pin.lids), 'method', 'from_ingredients', 'unit_cost', round((ing + coalesce(conv, 0)) / pin.q, 6), 'qty', pin.q);
      end if;
    end loop;
  end if;
  return jsonb_build_object('ok', true, 'kind', p_kind, 'ref', p_ref, 'method', p_method, 'items', items_, 'derived', derived, 'total', round(total, 2), 'location_ids', to_jsonb(locs), 'needs_manual', need_manual);
end $$;

-- the list (shared by the list and the alert)
create or replace function public._cw_list96(p_loc int, p_limit int, p_only_old boolean) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare dd record; days numeric := public.rule_num('acct_cost_wait_alert_days'); t date := public._acct_today(); arr jsonb := '[]'::jsonb; n int := 0; tot int := 0; old int := 0; oldest int := 0; age int; over boolean;
        lim int := least(greatest(coalesce(p_limit, 100), 1), 500); by_kind jsonb := '{}'::jsonb;
begin
  for dd in select * from public._cw_docs96() x where (p_loc is null or x.loc = p_loc) and public.can_loc(x.loc) and public._cost_ok(x.loc) order by x.d, x.kind, x.ref loop
    age := t - dd.d; over := days is not null and age > days;
    tot := tot + 1; if over then old := old + 1; end if; oldest := greatest(oldest, age);
    by_kind := jsonb_set(by_kind, array[dd.kind], to_jsonb(coalesce((by_kind->>dd.kind)::int, 0) + 1));
    if n < lim and (not p_only_old or over) then
      n := n + 1;
      arr := arr || jsonb_build_object('kind', dd.kind, 'ref', dd.ref, 'location_id', dd.loc, 'date', dd.d, 'age_days', age, 'rows', dd.n, 'move', dd.move, 'gl_post', dd.gl, 'over_alert', case when days is not null then over end,
        'items', (select coalesce(jsonb_agg(jsonb_build_object('item_id', z.item_id, 'code', z.code, 'name_bn', z.name_bn, 'name_en', z.name_en, 'unit', z.base_unit, 'qty', z.q) order by z.code), '[]'::jsonb)
                    from (select r.item_id, it.code, it.name_bn, it.name_en, it.base_unit, sum(abs(r.qty)) filter (where r.reason <> 'transfer_in') q
                            from public._cw_rows96(dd.kind, dd.ref) r join public.items it on it.id = r.item_id group by 1, 2, 3, 4, 5) z));
    end if;
  end loop;
  return jsonb_build_object('as_of', t, 'alert_days', days, 'alert_enabled', days is not null, 'total', tot, 'shown', n, 'old_count', case when days is not null then old end, 'oldest_days', oldest, 'by_kind', by_kind, 'items', arr);
end $$;

create or replace function public.cost_wait_list96(p_loc int default null, p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not exists (select 1 from public.locations l where public.can_loc(l.id) and public._cost_ok(l.id)) then raise exception 'not allowed'; end if;
  if p_loc is not null and not (public.can_loc(p_loc) and public._cost_ok(p_loc)) then raise exception 'not allowed'; end if;
  return public._cw_list96(p_loc, p_limit, false);
end $$;

-- the aging alert: documents waiting longer than the number the owner typed (blank = no alert)
create or replace function public.cost_wait_alert96(p_loc int default null, p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not public.is_active() or not exists (select 1 from public.locations l where public.can_loc(l.id) and public._cost_ok(l.id)) then raise exception 'not allowed'; end if;
  if p_loc is not null and not (public.can_loc(p_loc) and public._cost_ok(p_loc)) then raise exception 'not allowed'; end if;
  r := public._cw_list96(p_loc, p_limit, true);
  return r || jsonb_build_object('alert', coalesce((r->>'alert_enabled')::boolean and (r->>'old_count')::int > 0, false),
    'message', public._t96('এই document গুলো cost এর অপেক্ষায় আছে; cost দিলে একবারই post হবে।', 'এই document গুলো cost এর অপেক্ষায় আছে; cost দিলে একবারই post হবে।', 'These documents are waiting for their cost; once a cost is supplied each posts once.'));
end $$;

create or replace function public._cw_visible96(p_kind text, p_ref text) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and exists (select 1 from public._cw_rows96(p_kind, p_ref))
     and not exists (select 1 from public._cw_rows96(p_kind, p_ref) r where not (public.can_loc(r.loc) and public._cost_ok(r.loc)));
$$;

-- DRY RUN of one method (or the recommended choice per item): costs, amounts, what is missing. No writes.
create or replace function public.cost_wait_preview96(p_kind text, p_ref text, p_method text default 'recommended', p_manual jsonb default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pl jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if exists (select 1 from public._cw_rows96(p_kind, p_ref) r where not (public.can_loc(r.loc) and public._cost_ok(r.loc))) then raise exception 'not allowed'; end if;
  pl := public._cw_plan96(p_kind, p_ref, p_method, p_manual);
  return (pl - 'items') || jsonb_build_object('dry', true, 'items', (select coalesce(jsonb_agg(x - 'lids'), '[]'::jsonb) from jsonb_array_elements(coalesce(pl->'items', '[]'::jsonb)) x),
    'gl_post', (select d.gl from public._cw_docs96() d where d.kind = p_kind and d.ref = p_ref));
end $$;

-- RECOMMENDATION: the best method per item from the numbers (never applied by itself)
create or replace function public.cost_wait_recommend96(p_kind text, p_ref text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pl jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if exists (select 1 from public._cw_rows96(p_kind, p_ref) r where not (public.can_loc(r.loc) and public._cost_ok(r.loc))) then raise exception 'not allowed'; end if;
  pl := public._cw_plan96(p_kind, p_ref, 'recommended', null);
  if not (pl->>'ok')::boolean then return pl || jsonb_build_object('never_auto', true); end if;
  return (pl - 'items') || jsonb_build_object('never_auto', true, 'items', (select coalesce(jsonb_agg(x - 'lids'), '[]'::jsonb) from jsonb_array_elements(pl->'items') x));
end $$;

-- SUPPLY: owner or cost-right holder; the cost is kept in the append-only table, the document then posts once (je_source_uq)
create or replace function public.cost_wait_supply96(p_kind text, p_ref text, p_method text, p_manual jsonb default null, p_reason text default null, p_client uuid default null, p_post boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pl jsonb; it jsonb; lid jsonb; n int := 0; staff text; pr jsonb; cnt int; posted boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_client is null then raise exception 'client_id_needed'; end if;
  if p_method is null or p_method not in ('item_average', 'last_purchase', 'recipe_standard', 'manual') then raise exception 'bad_method'; end if;
  perform public._client_lock(p_client);
  select count(*) into cnt from public.ledger_cost_supply96 where client_id = p_client;
  if cnt > 0 then return jsonb_build_object('dup', true, 'rows', cnt, 'posted', public._cw_posted96(p_kind, p_ref)); end if;
  if exists (select 1 from public._cw_rows96(p_kind, p_ref) r where not (public.can_loc(r.loc) and public._cost_ok(r.loc))) then raise exception 'not allowed'; end if;
  if p_method = 'manual' and length(btrim(coalesce(p_reason, ''))) = 0 then raise exception 'reason_needed'; end if;
  perform pg_advisory_xact_lock(hashtextextended('cost_supply96', 0));
  if public._cw_posted96(p_kind, p_ref) then raise exception 'already_posted'; end if;
  pl := public._cw_plan96(p_kind, p_ref, p_method, p_manual);
  if not (pl->>'ok')::boolean then raise exception '%', pl->>'error' using detail = left(coalesce(pl->>'detail', ''), 500); end if;
  select staff_id into staff from public.profiles where id = auth.uid();
  for it in select * from jsonb_array_elements(pl->'items') loop
    for lid in select * from jsonb_array_elements(it->'lids') loop
      insert into public.ledger_cost_supply96 (ledger_id, unit_cost, method, reason, doc_kind, doc_ref, client_id, basis, supplied_by, supplied_staff)
        values ((lid #>> '{}')::bigint, (it->>'unit_cost')::numeric, it->>'method', left(nullif(btrim(p_reason), ''), 300), p_kind, p_ref, p_client, it->'candidates', auth.uid(), staff);
      n := n + 1;
    end loop;
  end loop;
  for it in select * from jsonb_array_elements(pl->'derived') loop
    for lid in select * from jsonb_array_elements(it->'lids') loop
      insert into public.ledger_cost_supply96 (ledger_id, unit_cost, method, reason, doc_kind, doc_ref, client_id, basis, supplied_by, supplied_staff)
        values ((lid #>> '{}')::bigint, (it->>'unit_cost')::numeric, 'from_ingredients', left(nullif(btrim(p_reason), ''), 300), p_kind, p_ref, p_client, null, auth.uid(), staff);
      n := n + 1;
    end loop;
  end loop;
  if coalesce(p_post, true) and public.rule_on('accounting_on') and public._acct_manage() then pr := public.acct_post_pending(false, 1500); end if;
  posted := public._cw_posted96(p_kind, p_ref);
  return jsonb_build_object('kind', p_kind, 'ref', p_ref, 'method', p_method, 'rows', n, 'total', pl->'total', 'posted', posted,
    'post_run', case when pr is null then null else jsonb_build_object('posted', pr->'posted', 'locked', pr->'locked', 'errors', pr->'errors') end);
end $$;

-- ---------- privileges: internals closed; the calls are for signed-in people (each one checks its own right) ----------
revoke all on function public._t96(text, text, text), public._d23_gate96(int), public._ob_rows96(int), public._ob_cover96(), public._ob_plan96(text, int, text, date), public._ob_rule_watch96(),
  public._cw_rows96(text, text), public._cw_posted96(text, text), public._cw_docs96(), public._cw_cands96(uuid, int, timestamptz), public._cw_manual96(jsonb, uuid, int),
  public._cw_plan96(text, text, text, jsonb), public._cw_list96(int, int, boolean), public._cw_visible96(text, text) from public, anon, authenticated;
revoke all on function public.opening_stock_check96(int), public.opening_stock_preview96(text, int, text, date), public.opening_stock_apply96(text, int, text, date, text, uuid), public.opening_stock_recommend96(int),
  public.cost_wait_list96(int, int), public.cost_wait_alert96(int, int), public.cost_wait_preview96(text, text, text, jsonb), public.cost_wait_recommend96(text, text),
  public.cost_wait_supply96(text, text, text, jsonb, text, uuid, boolean) from public, anon;
grant execute on function public.opening_stock_check96(int), public.opening_stock_preview96(text, int, text, date), public.opening_stock_apply96(text, int, text, date, text, uuid), public.opening_stock_recommend96(int),
  public.cost_wait_list96(int, int), public.cost_wait_alert96(int, int), public.cost_wait_preview96(text, text, text, jsonb), public.cost_wait_recommend96(text, text),
  public.cost_wait_supply96(text, text, text, jsonb, text, uuid, boolean) to authenticated;
