-- ============================================================
-- Phase 103 (bos103) - STEP E2E: fixes for the defects an independent end-to-end run found (docs/briefs_p2p3/step_E2E_REPORT.md). Goes LAST.
--   Needs phases 72..101 pasted first (guard below, incl. phase98 = the _acct_docs merge, phase99, phase100, phase101). It carries the COMPLETE final text of the functions below, so if phase89 / 94 / 96 / 97 is ever pasted again, pasting phase103 again repairs it (phase98 itself would refuse: its body guard does not know bos103). Phase102 (item images) touches no accounting function.
--   Additive, paste-twice safe: every function is re-created from its LATEST body (phase98 / phase99 / phase96 / phase89 / phase81 text), only lines tagged bos103 differ,
--   every older bosNN tag is kept; one new switch (default OFF), one new advisor check row, three internal helper functions. No table, column, trigger or privilege of an
--   existing object is changed. Each create runs only if both guards passed (session flag phase103.ok).
--   D-1  production run whose ingredients are ALL free-cost items: a free-cost item is a known cost 0, so the run is no longer "cost_missing" for ever
--        (_acct_docs). Conversion cost, if any, is posted (Dr finished goods / Cr overhead absorbed); a run with nothing to book posts nothing and does not wait.
--   D-2  direct production-in without a recipe: appears in the cost-waiting list when its cost is missing (_cw_docs96 / _cw_rows96), and posts when the cost is known
--        if the new switch acct_manual_prod_in103 is ON (default OFF = as before; Dr inventory / Cr overhead absorbed, one entry per ledger row). inventory_vs_gl
--        removes what the entries cover from the manual_in reason.
--   D-3  cost supplied later to an opening row after the opening-stock helper: the helper (opening_stock_apply96) can be applied ONE more time for the rows the
--        first decision did not cover; no double count (the rows are frozen again, a second call answers already_applied).
--   D-4  recipe_cost: a free-cost ingredient is a known cost 0 (unit_cost 0, complete = true), the same as production_post.
--   D-5  GRN is the stock source + purchase_grn_guard off: new flow check flw_grn_double103 (setup_flow_check, level warn, never blocks) and the setup advisor
--        recommends skip for purchase_grn_guard while grn_receipt_source = grn (computed at read time; the phase101 row and every owner-chosen value are untouched).
--   D-6  inventory_vs_gl: GRN stock rows covered by a bill that added no stock of its own (guard skip / link) are no longer "manual_in".
--   D-7  inbox_pii_mode masked modes also mask a phone number typed inside free text (message text, name, address, order note); unmask stays audited.
--   D-8  customer_directory / find_customer follow inbox_pii_mode: mobile (and whatsapp / address / note) masked for a user who is neither owner nor holds view_customer_mobile.
--   Tag: bos103.
-- ============================================================

do $g$ begin perform set_config('phase103.ok', 'off', false); end $g$;
do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.get_doc_templates(integer)'), ('94', 'public._intake_proof_ok94(text,text)'),
    ('95', 'public.drawer_settings(integer)'), ('96', 'public._cw_docs96()'), ('97', 'public._landed_jlines97(uuid,text)'),
    ('99', 'public._inb_pii_f99(text,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  -- 98: the merged _acct_docs (bos98), or phase103 itself pasted before, or the phase89 merge (bos89) with the markers of 96 and 97 above: phase103 carries the COMPLETE merged body, so it also repairs a re-paste of 89 / 96 / 97
  if to_regprocedure('public._acct_docs(date)') is null
     or (position('bos98' in pg_get_functiondef(to_regprocedure('public._acct_docs(date)'))) = 0 and position('bos103' in pg_get_functiondef(to_regprocedure('public._acct_docs(date)'))) = 0
         and position('bos89' in pg_get_functiondef(to_regprocedure('public._acct_docs(date)'))) = 0) then miss := miss || ' 98'; end if;
  if to_regclass('public.item_categories') is null then miss := miss || ' 100'; end if;
  if to_regclass('public.setup_rec_defs81') is null or not exists (select 1 from public.setup_rec_defs81 where code = 'purchase_grn_guard' and phase = '82') then miss := miss || ' 101'; end if;
  if miss <> '' then
    raise exception 'phase103 needs phases 72..101 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
  perform set_config('phase103.ok', 'guard1', false);
end $g$;

-- BODY GUARD: a live body with a tag this file does not know (a newer phase) is never overwritten
do $g$
declare d text; t text[]; r record;
begin
  if current_setting('phase103.ok', true) is distinct from 'guard1' then return; end if;
  for r in select * from (values
    ('public._acct_docs(date)', array['bos103', 'bos50', 'bos52', 'bos72', 'bos74', 'bos80', 'bos85', 'bos89', 'bos96', 'bos97', 'bos98']::text[]),
    ('public._acct_stock_moves85(date)', array['bos103', 'bos96']::text[]),
    ('public.inventory_vs_gl(date,integer)', array['bos103', 'bos85', 'bos96']::text[]),
    ('public._cw_docs96()', array['bos103']::text[]),
    ('public._cw_rows96(text,text)', array['bos103']::text[]),
    ('public._cw_posted96(text,text)', array['bos103']::text[]),
    ('public.recipe_cost(uuid,integer)', array['bos103', 'bos73', 'bos74']::text[]),
    ('public._ob_plan96(text,integer,text,date)', array['bos103']::text[]),
    ('public.opening_stock_apply96(text,integer,text,date,text,uuid)', array['bos103']::text[]),
    ('public._setup_chk81(text)', array['bos103']::text[]),
    ('public.setup_recommendations()', array['bos103']::text[]),
    ('public.setup_recommend_apply(uuid,text[],boolean,boolean)', array['bos103']::text[]),
    ('public._inb_pii_f99(text,text)', array['bos103']::text[]),
    ('public._inb_pii_json99(jsonb)', array['bos103']::text[]),
    ('public.inbox_list(integer,text,integer)', array['bos103', 'bos99']::text[]),
    ('public.customer_directory(integer)', array['bos103']::text[]),
    ('public.find_customer(text)', array['bos103']::text[]),
    ('public._ob_rows96(integer)', array['bos103']::text[]),
    ('public.online_order_get(uuid)', array['bos103', 'bos76', 'bos77', 'bos99']::text[]),
    ('public.online_orders_list(integer,text,date,date,integer)', array['bos103', 'bos76', 'bos77', 'bos99']::text[])) v(sig, known)
  loop
    d := pg_get_functiondef(r.sig::regprocedure);
    select array_agg(distinct x[1]) into t from regexp_matches(d, 'bos[0-9]+', 'g') x;
    if t is not null and not (t <@ r.known) then
      raise exception 'phase103: % carries tags this file does not know (%); build a newer merge instead of overwriting it', r.sig, t;
    end if;
  end loop;
  perform set_config('phase103.ok', 'on', false);
end $g$;
-- the statements below run only when both guards passed

-- ---------- follow-up decisions of the opening-stock helper (append-only, audited; one decision per place stays in opening_stock_actions96) ----------
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then
  create table if not exists public.opening_stock_followups103 (
    id bigint generated always as identity primary key,
    action_id bigint references public.opening_stock_actions96(id),
    location_id int references public.locations(id),
    option text not null check (option in ('owner_capital', 'existing_account', 'skip', 'difference')),
    account_code text, amount numeric(18,2) not null default 0, entry_id bigint,
    covered_ids bigint[] not null default '{}',                -- the opening ledger rows this follow-up covers (a cost supplied later, or an opening entered later)
    reason text, client_id uuid unique, created_by uuid, created_staff text, created_at timestamptz not null default now());
  alter table public.opening_stock_followups103 enable row level security;
  revoke all on public.opening_stock_followups103 from public, anon, authenticated;
  drop trigger if exists opening_stock_followups103_ro on public.opening_stock_followups103;
  create trigger opening_stock_followups103_ro before update or delete on public.opening_stock_followups103 for each row execute function public._ledger_immutable();
  drop trigger if exists opening_stock_followups103_nt on public.opening_stock_followups103;
  create trigger opening_stock_followups103_nt before truncate on public.opening_stock_followups103 for each statement execute function public._ledger_immutable();
  drop trigger if exists audit_opening_stock_followups103 on public.opening_stock_followups103;
  create trigger audit_opening_stock_followups103 after insert on public.opening_stock_followups103 for each row execute function public.log_change('id');
  create or replace view public.opening_covered103 as
    select a.location_id, a.covered_ids from public.opening_stock_actions96 a
    union all select f.location_id, f.covered_ids from public.opening_stock_followups103 f;
  revoke all on public.opening_covered103 from public, anon, authenticated;
end if; end $p103$;

-- ---------- new switch (default OFF = today's behaviour) ----------
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('acct_manual_prod_in103', 'books', 'switch', 'false', null, null, null,
  'Recipe ছাড়া সরাসরি production-in journal এ তোলা', 'Recipe ছাড়া direct production-in journal এ post করা', 'Post direct production-in (no recipe) to the books',
  'বন্ধ থাকলে আগের মতোই: recipe ছাড়া production-in শুধু stock বাড়ায়, journal এ যায় না (inventory_vs_gl এ manual_in হিসেবে দেখা যায়)। চালু করলে লেখা cost ধরে প্রতিটি row এর জন্য একটি entry হয়। cost না থাকলে cost-waiting তালিকায় থাকে।',
  'Off = as before: a production-in typed without a recipe raises the stock only and is not in the books (inventory_vs_gl lists it as manual_in). On = one entry per row at the typed cost: Dr inventory / Cr overhead absorbed. A row without a cost waits in the cost-waiting list either way.', 956)
on conflict (key) do nothing;
end if; end $p103$;

-- ---------- new advisor check (flow): the double count of a GRN + a bill that both add stock ----------
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then
insert into public.setup_check_defs81 (code, topic, kind, gate_rule, level, label_bn, label_mix, label_en, fix_bn, fix_mix, fix_en, nav, sort, active) values
 ('flw_grn_double103', 'stock_tracking', 'flow', null, 'warn',
  'GRN মালের উৎস, guard বন্ধ, আর bill-ও stock বাড়াচ্ছে: একই মাল দুবার গোনা হচ্ছে',
  'GRN goods এর source, guard off, আর bill-ও stock বাড়াচ্ছে: একই মাল দুবার গোনা হচ্ছে',
  'GRN is the stock source, the guard is off and bills also add stock: the same goods are counted twice',
  'purchase_grn_guard "skip" করুন (bill শুধু টাকা ধরবে), তারপর বাড়তি stock গুনে ঠিক করুন',
  'purchase_grn_guard "skip" করুন (bill শুধু money ধরবে), তারপর extra stock count করে ঠিক করুন',
  'Set purchase_grn_guard to skip (the bill then records money only), then correct the extra stock with a count', 'stock', 71, true)
on conflict (code) do update set topic = excluded.topic, kind = excluded.kind, level = excluded.level, label_bn = excluded.label_bn, label_mix = excluded.label_mix, label_en = excluded.label_en,
  fix_bn = excluded.fix_bn, fix_mix = excluded.fix_mix, fix_en = excluded.fix_en, nav = excluded.nav, sort = excluded.sort, active = excluded.active;
end if; end $p103$;

-- ---------- the grant that the customer screens already test (rpt_grant('view_customer_mobile')) becomes a grant the owner can give ----------
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select 'view_customer_mobile', 'pos', 97, 'গ্রাহকের মোবাইল নম্বর দেখা (ইনবক্স ঢাকা থাকলেও)', 'Customer এর mobile number দেখা (inbox mask থাকলেও)', 'See customer mobile numbers (even when inbox masking is on)', 'once'
where not exists (select 1 from public.grant_defs where grant_code = 'view_customer_mobile');
end if; end $p103$;

-- ---------- internal helpers ----------
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
create or replace function public._inb_mask_phones103(p text) returns text
language plpgsql immutable set search_path = public as $b$
-- masks every phone-number-like digit run (ASCII or Bangla digits, optional +, spaces / hyphens / brackets between digits, 8..15 digits; a date such as 2026-10-14 is left alone), keeps the last 3 digits
declare r text := p; m text[]; dg text; nd int;
begin
  if p is null or p !~ '[0-9০-৯]' then return p; end if;
  for m in select regexp_matches(p, '\+?[0-9০-৯](?:[0-9০-৯]|[ ()-]{1,2}(?=[0-9০-৯])){6,}', 'g') loop
    dg := regexp_replace(m[1], '[^0-9০-৯]', '', 'g'); nd := char_length(dg);
    if nd between 8 and 15 and m[1] !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      r := replace(r, m[1], repeat('•', greatest(nd - 3, 3)) || right(dg, 3));
    end if;
  end loop;
  return r;
end $b$;
$f$; end if; end $p103$;

do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
create or replace function public._cust_pii103(p_field text, p_val text) returns text
language plpgsql stable security definer set search_path = public as $b$
-- customer fields follow inbox_pii_mode; owner and view_customer_mobile holders see them as before
declare mode_ text := public._inb_pii_mode99();
begin
  if p_val is null or btrim(p_val) = '' or mode_ = 'off' then return p_val; end if;
  if public.is_owner() or public.rpt_grant('view_customer_mobile') then return p_val; end if;
  return case p_field
    when 'mobile' then public._inb_mask99('mobile', p_val)
    when 'address' then case when mode_ in ('mask_phone_address', 'mask_all_pii') then public._inb_mask99('address', p_val) else public._inb_mask_phones103(p_val) end
    else case when mode_ = 'mask_all_pii' then public._inb_mask99('text', p_val) else public._inb_mask_phones103(p_val) end end;
end $b$;
$f$; end if; end $p103$;

do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
create or replace function public._rec_value103(p_key text, p_rec jsonb) returns jsonb
language sql stable security definer set search_path = public as $b$
  -- purchase_grn_guard has no fixed recommendation (phase101); while GRN is the stock source the recommendation is skip
  select case when p_key = 'purchase_grn_guard' and p_rec is null and coalesce(public.rule_txt('grn_receipt_source'), 'purchase') = 'grn' then '"skip"'::jsonb else p_rec end
$b$;
$f$; end if; end $p103$;

do $p103$ begin if current_setting('phase103.ok', true) = 'on' then
  revoke all on function public._inb_mask_phones103(text), public._cust_pii103(text, text), public._rec_value103(text, jsonb) from public, anon, authenticated;
end if; end $p103$;

-- ---- public._acct_docs(date) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._acct_docs(p_start date)
 RETURNS TABLE(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- bos97: phase89 body + two landed-cost blocks at the end (landed_cost, landed_cost_void)
-- bos103: production run whose ingredients are all free-cost = known cost 0 (posts conversion only, or nothing when there is none); production-in without recipe via _acct_stock_moves85
-- bos98: merged by phase98 = phase89 body + every bos96 line (stock_ledger_eff96 reads) + both bos97 blocks, so neither phase96 nor phase97 can erase the other
-- bos89: merge of phase80 (free-cost) and phase85 (stock moves, card, voucher mode) bodies; every bos50/52/72/74/80/85 line kept
begin
  -- sales (payments split, discount, revenue, COGS only from real unit costs)
  return query
  select 'sale'::text, s.id::text, s.sale_date, s.location_id, ('Receipt ' || s.receipt)::text, null::text, s.status = 'done', (s.void_at at time zone 'Asia/Dhaka')::date,
    case when s.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0) and not public._cost_free80((e->>'item_id')::uuid)) then 'cogs_missing' end, /* bos72: cost 0 = unknown; bos80: free-cost item is a known cost */
    null::text,
    case when s.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'pay_' || p.mode, 'd', sum(p.amount)) j from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided group by p.mode
        union all select 2, jsonb_build_object('a', 'receivable', 'd', round(s.total - pp.paid, 2), 'pt', case when s.customer_id is not null then 'customer' end, 'pid', s.customer_id::text) where s.total - pp.paid > 0.004
        union all select 3, jsonb_build_object('a', 'sales_discount', 'd', s.discount) where s.discount > 0
        union all select 4, jsonb_build_object('a', 'sales', 'c', s.subtotal)
        union all select 5, jsonb_build_object('a', 'cogs', 'd', cg.amt) from (select round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_id = s.id::text and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') and l.unit_cost is not null) cg where cg.amt > 0
        union all select 6, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt) from public._acct_inv_split72(array['sale', 'sale_pack'], s.id::text, array['sale_out', 'issue_out'], -1) z where z.amt > 0 /* bos72: rounding remainder on the largest part */
      ) x) end
  from public.sales s cross join lateral (select coalesce(sum(p.amount), 0) paid from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided) pp
  where s.sale_date >= p_start and s.subtotal > 0 and public._acct_need('sale', s.id::text, s.status = 'done');

  -- sale returns
  return query
  select 'sale_return'::text, r.id::text, (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, ('Return of receipt ' || coalesce(s.receipt::text, '-'))::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when r.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0) and not public._cost_free80((e->>'item_id')::uuid)) then 'cogs_missing' end, /* bos72: cost 0 = unknown; bos80: free-cost item is a known cost */
    null::text,
    case when r.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'sales_returns', 'd', r.amount) j
        union all select 2, jsonb_build_object('a', 'receivable', 'c', r.credit_amount, 'pt', case when r.customer_id is not null then 'customer' end, 'pid', r.customer_id::text) where r.credit_amount > 0
        union all select 3, jsonb_build_object('a', public._acct_paykey(coalesce(r.refund_mode, 'cash')), 'c', r.refund_amount) where r.refund_amount > 0
        union all select 4, jsonb_build_object('a', public._acct_inv_key(z.t), 'd', z.amt) from public._acct_inv_split72(array['sale_return'], r.id::text, array['sale_return'], 1) z where z.amt > 0 /* bos72 */
        union all select 5, jsonb_build_object('a', 'cogs', 'c', cg.amt) from (select round(sum(l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.unit_cost is not null) cg where cg.amt > 0
      ) x) end
  from public.sale_returns r left join public.sales s on s.id = r.sale_id
  where (r.created_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('sale_return', r.id::text, r.status = 'done');

  -- customer collections (later payments of dues)
  return query
  select 'collection'::text, p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'Due collection'::text, null::text, not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(p.mode), 'd', p.amount),
      jsonb_build_object('a', 'receivable', 'c', p.amount, 'pt', case when p.customer_id is not null then 'customer' end, 'pid', p.customer_id::text)) end
  from public.sale_payments p
  where p.kind = 'collection' and (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('collection', p.id::text, not p.voided);

  -- purchase bills and purchase returns
  return query
  select 'purchase'::text, b.id::text, b.bill_date, b.location_id, ((case b.kind when 'return' then 'Purchase return ' else 'Purchase bill ' end) || coalesce(b.bill_no, '-'))::text, b.kind, b.status = 'posted' and b.total > 0, (b.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when b.status = 'posted' and b.total > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'payable', case when b.kind = 'return' then 'd' else 'c' end, b.total, 'pt', 'supplier', 'pid', b.supplier_id::text) j
        union all select 2, jsonb_build_object('a', al.k, case when b.kind = 'return' then 'c' else 'd' end, al.amt) from public._acct_purchase_alloc(b.id) al
      ) x) end
  from public.purchase_bills b
  where b.bill_date >= p_start and public._acct_need('purchase', b.id::text, b.status = 'posted' and b.total > 0);

  -- supplier payments
  return query
  select 'supplier_payment'::text, p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'Supplier payment'::text, null::text, not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', 'payable', 'd', p.amount, 'pt', 'supplier', 'pid', p.supplier_id::text),
      jsonb_build_object('a', public._acct_paykey(p.mode, true), 'c', p.amount)) end
  from public.supplier_payments p
  where (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('supplier_payment', p.id::text, not p.voided);

  -- supplier refunds
  return query
  select 'supplier_refund'::text, f.id::text, (f.refunded_at at time zone 'Asia/Dhaka')::date, f.location_id, 'Supplier refund'::text, null::text, not f.voided, public._acct_today(), null::text, null::text,
    case when not f.voided then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(f.mode, true), 'd', f.amount),
      jsonb_build_object('a', 'payable', 'c', f.amount, 'pt', 'supplier', 'pid', f.supplier_id::text)) end
  from public.supplier_refunds f
  where (f.refunded_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('supplier_refund', f.id::text, not f.voided);

  -- 10-2 expense vouchers (approved; a re-opened or re-numbered voucher is reversed, the new revision posted)
  return query
  select 'expense_voucher'::text, e.id::text || ':' || coalesce(e.rev_no, 0)::text, e.entry_date, e.location_id, ('Expense voucher ' || e.serial)::text, null::text, v.total > 0, public._acct_today(),
    case when v.bad > 0 then 'unreadable_lines' end, null::text,
    case when v.total > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'exp_' || h.head, 'd', h.amt) j from (
          select regexp_replace(lower(coalesce(nullif(btrim(x->>'head'), ''), 'other')), '[^a-z0-9_]', '_', 'g') head, sum(public._acct_num(x->>'amount')) amt
          from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x
          where public._acct_num(x->>'amount') > 0 group by 1) h
        union all select 2, jsonb_build_object('a', public._acct_paykey(v.pm, true) /* bos85 */, 'c', v.total)
      ) y) end
  from public.entries e cross join lateral (
    select case when e.data->>'pay_mode' in ('cash', 'bank', 'mobile', 'card') then e.data->>'pay_mode' else 'cash' end pm, /* bos85: how the voucher was paid; none = cash as before */
           coalesce(sum(public._acct_num(x->>'amount')) filter (where public._acct_num(x->>'amount') > 0), 0) total,
           count(*) filter (where coalesce(btrim(x->>'amount'), '') <> '' and public._acct_num(x->>'amount') is null) bad
    from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x) v
  where e.form_code = '10-2' and e.status = 'approved' and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.entry_date >= p_start and public._acct_need('expense_voucher', e.id::text || ':' || coalesce(e.rev_no, 0)::text, v.total > 0);
  return query
  select 'expense_voucher'::text, je.source_id, je.entry_date, je.location_id, 'Expense voucher no longer approved'::text, null::text, false, public._acct_today(), null::text, null::text, null::jsonb
  from public.journal_entries je
  where je.source_type = 'expense_voucher' and je.reverses_id is null
    and not exists (select 1 from public.entries e where e.form_code = '10-2' and e.status = 'approved' and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.id::text || ':' || coalesce(e.rev_no, 0)::text = je.source_id)
    and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id);

  -- bos50: quick expenses typed in the day-book tab: expense head debit, cash / bank / mobile credit
  return query
  select 'quick_expense'::text, q.id::text, q.exp_date, q.location_id, ('Quick expense: ' || q.head)::text, null::text, q.status = 'done', (q.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when q.status = 'done' then jsonb_build_array(
      jsonb_build_object('a', case when exists (select 1 from public.acct_mappings m where m.key = 'exp_' || q.head) then 'exp_' || q.head else 'exp_other' end, 'd', q.amount),
      jsonb_build_object('a', public._acct_paykey(q.mode), 'c', q.amount)) end
  from public.quick_expenses q
  where q.exp_date >= p_start and public._acct_need('quick_expense', q.id::text, q.status = 'done');

  -- cash moves (bank deposit / withdraw, owner top-up / draw, customer advances, hub receipt)
  return query
  select 'cash_move'::text, public._acct_sid52('cash_move', m.id::text) /* bos52 */, m.move_date, m.location_id, ('Cash move: ' || m.kind)::text, m.kind, m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */, (m.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */ then case m.kind
      when 'bank_deposit' then jsonb_build_array(jsonb_build_object('a', 'pay_bank', 'd', m.amount), jsonb_build_object('a', 'pay_cash', 'c', m.amount))
      when 'bank_withdraw' then jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', m.amount), jsonb_build_object('a', 'pay_bank', 'c', m.amount))
      when 'owner_topup' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(m.mode), 'd', m.amount), jsonb_build_object('a', 'owner_capital', 'c', m.amount))
      when 'owner_draw' then jsonb_build_array(jsonb_build_object('a', 'owner_drawings', 'd', m.amount), jsonb_build_object('a', public._acct_paykey(m.mode), 'c', m.amount))
      when 'cust_advance' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(m.mode), 'd', m.amount), jsonb_build_object('a', 'cust_advance', 'c', m.amount, 'pt', 'customer', 'pid', m.customer_id::text))
      when 'cust_advance_refund' then jsonb_build_array(jsonb_build_object('a', 'cust_advance', 'd', m.amount, 'pt', 'customer', 'pid', m.customer_id::text), jsonb_build_object('a', public._acct_paykey(m.mode), 'c', m.amount))
      when 'cust_advance_used' then jsonb_build_array(jsonb_build_object('a', 'cust_advance', 'd', m.amount, 'pt', 'customer', 'pid', m.customer_id::text), jsonb_build_object('a', 'receivable', 'c', m.amount, 'pt', 'customer', 'pid', m.customer_id::text))
      when 'hub_receipt' then jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', m.amount), jsonb_build_object('a', 'hub_clearing', 'c', m.amount))
    end end
  from public.cash_moves m
  where m.move_date >= p_start and public._acct_need('cash_move', public._acct_sid52('cash_move', m.id::text), m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */);

  -- wastage at the real cost in the stock ledger
  return query
  select 'wastage'::text, w.id::text, (w.made_at at time zone 'Asia/Dhaka')::date, w.location_id, 'Wastage written off'::text, null::text, true, null::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when c.amt is null or c.amt <= 0 then 'cost_missing' end,
    case when c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'wastage', 'd', c.amt) j
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from public._acct_inv_split72(array['wastage'], w.id::text, array['wastage'], -1) z where z.amt > 0 /* bos72 */
      ) y) end
  from public.stock_wastage w cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */
    from public.stock_ledger_eff96 l /* bos96 */ where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c
  where (w.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('wastage', w.id::text, true);

  -- production: ingredients (at their real cost) move from raw / packaging to finished goods
  return query
  select 'production'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, 'Production run'::text, null::text, r.status = 'done' and not c.zero103 /* bos103 */, (r.void_at at time zone 'Asia/Dhaka')::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when r.status = 'done' and (c.amt is null or c.amt <= 0) and not c.known103 /* bos103: every ingredient line is a real cost or a free-cost item */ then 'cost_missing' end,
    case when r.status = 'done' and (c.amt > 0 or (c.known103 and not c.zero103)) /* bos103 */ then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', coalesce(c.amt, 0) + round(coalesce(r.conversion_cost, 0), 2)) j /* bos74: material + conversion */ /* bos103 */
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from public._acct_inv_split72(array['production'], r.id::text, array['issue_out'], -1) z where z.amt > 0 /* bos72 */
        union all select 3, jsonb_build_object('a', 'overhead_absorbed', 'c', round(r.conversion_cost, 2)) where coalesce(r.conversion_cost, 0) >= 0.005 /* bos74: Cr overhead absorbed */
      ) y) end
  from public.production_runs r cross join lateral (
    select q.amt, q.nulls, (q.nulls = 0 and q.n > 0) as known103, (q.nulls = 0 and q.n > 0 and coalesce(q.amt, 0) <= 0 and round(coalesce(r.conversion_cost, 0), 2) < 0.005) as zero103 from (   /* bos103: known103 = no unknown cost; zero103 = known and nothing to book */
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */, count(*) n
    from public.stock_ledger_eff96 l /* bos96 */ where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') q) c
  where (r.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('production', r.id::text, r.status = 'done' and not c.zero103 /* bos103 */);

  -- bos52: payroll payments of the app payroll (a run whose sheet is the record, i.e. the run is a locked shadow, is skipped). Dr salary expense, Cr cash / bank / mobile.
  -- The advance recovery on the pay line is split over the payments pro rata and credited to the staff-advance asset (data: payroll_lines.advance_recovery).
  return query
  select 'payroll_payment'::text, public._acct_sid52('payroll_payment', p.id::text), p.pay_date, p.location_id, ('Salary payment PR-' || p.run_id::text)::text, null::text,
    p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text), (p.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text) then
      jsonb_build_array(jsonb_build_object('a', 'salary_exp', 'd', p.amount + r.rec, 'pt', 'staff', 'pid', p.employee_id::text),
                        jsonb_build_object('a', public._acct_paykey(p.mode), 'c', p.amount))
      || case when r.rec > 0 then jsonb_build_array(jsonb_build_object('a', 'staff_advance', 'c', r.rec, 'pt', 'staff', 'pid', p.employee_id::text)) else '[]'::jsonb end
    end
  from public.payroll_payments p
  cross join lateral (select case when l.advance_recovery > 0 and l.net > 0 then least(round(l.advance_recovery * p.amount / l.net, 2), l.advance_recovery) else 0 end as rec
                        from public.payroll_lines l where l.id = p.line_id) r
  where p.pay_date >= p_start
    and public._acct_need('payroll_payment', public._acct_sid52('payroll_payment', p.id::text), p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text));

  -- bos52: staff advances paid out of the business (cash / bank / mobile only; mode none = money not moved here, nothing posted). Dr staff advances, Cr cash / bank / mobile.
  return query
  select 'staff_advance'::text, a.id::text, a.adv_date, a.location_id, ('Staff advance ADV-' || a.id::text)::text, null::text,
    a.status = 'active' and a.mode in ('cash', 'bank', 'mobile'), (a.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when a.status = 'active' and a.mode in ('cash', 'bank', 'mobile') then
      jsonb_build_array(jsonb_build_object('a', 'staff_advance', 'd', a.amount, 'pt', 'staff', 'pid', a.employee_id::text),
                        jsonb_build_object('a', public._acct_paykey(a.mode), 'c', a.amount)) end
  from public.employee_advances a
  where a.adv_date >= p_start and public._acct_need('staff_advance', a.id::text, a.status = 'active' and a.mode in ('cash', 'bank', 'mobile'));

  -- bos52: partner capital (contribution / return of capital / loan in / loan repayment / owner drawing). The partner-capital record that is a locked shadow of a cash move
  -- is not posted (the cash move is the record then). A partner-capital record that is the primary of a cash-move shadow takes the place of the cash move (same place, once).
  -- In-kind contributions move no money: they are reported as waiting (in_kind), nothing is guessed.
  return query
  select 'partner_capital'::text, public._acct_sid52('partner_capital', c.id::text), c.cap_date, nullif(lk.loc, 0), ('Partner capital: ' || c.kind)::text, c.kind,
    c.status = 'posted' and not public._shadowed52('partner_capital', c.id::text), (c.void_at at time zone 'Asia/Dhaka')::date, null::text,
    case when c.mode = 'in_kind' then 'in_kind' end,
    case when c.status = 'posted' and c.mode <> 'in_kind' and not public._shadowed52('partner_capital', c.id::text) then case c.kind
      when 'contribution' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(c.mode), 'd', c.amount), jsonb_build_object('a', 'owner_capital', 'c', c.amount, 'pt', 'partner', 'pid', c.party_id::text))
      when 'return_of_capital' then jsonb_build_array(jsonb_build_object('a', 'owner_capital', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._acct_paykey(c.mode), 'c', c.amount))
      when 'loan_in' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(c.mode), 'd', c.amount), jsonb_build_object('a', 'partner_loan', 'c', c.amount, 'pt', 'partner', 'pid', c.party_id::text))
      when 'loan_repayment' then jsonb_build_array(jsonb_build_object('a', 'partner_loan', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._acct_paykey(c.mode), 'c', c.amount))
      when 'owner_drawing' then jsonb_build_array(jsonb_build_object('a', 'owner_drawings', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._acct_paykey(c.mode), 'c', c.amount))
    end end
  from public.partner_capital c
  left join lateral (select x.location_id as loc from public.shadow_links x where x.primary_type = 'partner_capital' and x.primary_id = c.id::text and x.shadow_type = 'cash_moves'
                      and x.shadow_id is not null and x.state <> 'void' order by x.id limit 1) lk on true
  where c.cap_date >= p_start and public._acct_need('partner_capital', public._acct_sid52('partner_capital', c.id::text), c.status = 'posted' and not public._shadowed52('partner_capital', c.id::text));

  -- bos85: stock movements that had no document: count adjustment, opening stock, own-use issue, location transfers (one entry per stock-ledger row, source_id = ledger id)
  return query
  select t.st, m.lid::text, m.d, m.loc,
    ((case m.cls when 'adjust' then 'Stock count adjustment' when 'opening' then 'Opening stock' when 'issue' then 'Stock issued for own use' when 'prodin' then 'Production-in without recipe' else 'Stock transfer' end) /* bos103 */ || case when m.rev then ' (reversal)' else '' end)::text,
    null::text, true, null::date, null::text, case when m.nocost then 'cost_missing' end,
    case when not m.nocost then jsonb_build_array(
      jsonb_build_object('a', case when m.qty < 0 then m.xkey else m.ikey end, 'd', m.amt),
      jsonb_build_object('a', case when m.qty < 0 then m.ikey else m.xkey end, 'c', m.amt)) end
  from public._acct_stock_moves85(p_start) m
  cross join lateral (select (case m.cls when 'adjust' then 'stock_adjust' when 'opening' then 'stock_opening' when 'issue' then 'stock_issue' when 'prodin' then 'stock_prodin' else 'stock_transfer' end)::text st /* bos103 */) t
  where public._acct_need(t.st, m.lid::text, true);

  -- bos85: goods short on a received transfer: Dr transit loss / Cr clearing (location-tagged transfers) or inventory
  return query
  select 'transit_loss'::text, t.id::text, (t.received_at at time zone 'Asia/Dhaka')::date, case when public.rule_txt('acct_transit_loss_at') = 'sender' then t.from_location_id else t.to_location_id end,
    'Stock short in transit'::text, null::text, true, null::date, null::text, case when c.nulls > 0 then 'cost_missing' end,
    case when c.nulls = 0 then jsonb_build_array(
      jsonb_build_object('a', 'transit_loss', 'd', c.l),
      jsonb_build_object('a', case when coalesce(public.rule_txt('acct_transfer_mode'), 'off') = 'location_tagged' then 'interloc_clearing' else public._acct_inv_key(it.item_type) end, 'c', c.l)) end
  from public.stock_transfers t join public.items it on it.id = t.item_id cross join lateral (
    select coalesce(sum(round(-s.qty_delta * s.unit_cost, 2)) filter (where s.reason = 'transfer_out'), 0) - coalesce(sum(round(s.qty_delta * s.unit_cost, 2)) filter (where s.reason = 'transfer_in'), 0) l,
           count(*) filter (where s.reason in ('transfer_out', 'transfer_in') and coalesce(s.unit_cost, 0) = 0) nulls
    from public.stock_ledger_eff96 s /* bos96 */ where s.ref_type = 'transfer' and s.ref_id = t.id::text and s.reason in ('transfer_out', 'transfer_in')) c
  where public.rule_on('acct_transit_loss') and t.status = 'received' and t.received_qty < t.qty
    and (t.received_at at time zone 'Asia/Dhaka')::date >= greatest(p_start, coalesce(public._acct_from85(), p_start)) and (c.nulls > 0 or c.l >= 0.01)
    and public._acct_need('transit_loss', t.id::text, true);

  -- bos85: purchase return price variance (stock left at ledger cost, supplier credit was at bill price)
  return query
  select 'purchase_variance'::text, b.id::text, b.bill_date, b.location_id, ('Purchase return price variance ' || coalesce(b.bill_no, '-'))::text, null::text, b.status = 'posted' and b.total > 0,
    (b.void_at at time zone 'Asia/Dhaka')::date, null::text, case when b.status = 'posted' and b.total > 0 and v.nulls > 0 then 'cost_missing' end,
    case when b.status = 'posted' and b.total > 0 and v.nulls = 0 then v.lines end
  from public.purchase_bills b cross join lateral public._pvar85(b.id) v
  where b.kind = 'return' and b.bill_date >= greatest(p_start, coalesce(public._acct_from85(), p_start)) and public.rule_on('acct_purchase_variance')
    and case when b.status = 'posted' and b.total > 0 then (v.nulls > 0 or v.nonzero) and public._acct_need('purchase_variance', b.id::text, true) else public._acct_need('purchase_variance', b.id::text, false) end;

  -- bos85: card settlement (typed by the person): Dr bank (net), Dr bank charges (fee), Cr card receivable (gross)
  return query
  select 'card_settlement'::text, c.id::text, c.settle_date, c.location_id, 'Card settlement'::text, null::text, c.status = 'done', (c.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when c.status = 'done' then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', public._acct_paykey(c.bank_mode), 'd', c.gross - c.fee) j
        union all select 2, jsonb_build_object('a', 'bank_charges', 'd', c.fee) where c.fee > 0
        union all select 3, jsonb_build_object('a', 'pay_card', 'c', c.gross)) x) end
  from public.card_settlements85 c
  where c.settle_date >= p_start and public._acct_need('card_settlement', c.id::text, c.status = 'done');

  -- bos97: landed cost (freight, duty, insurance ... added to the item cost). One entry once it is posted: Dr inventory raw / pack / finished (the part still on the shelf),
  -- Dr landed_variance (the part already sold), Dr expense / vat_input (charges that are not capitalised); Cr landed_payable / cash / bank / mobile. Lines come from the append-only landed_cost_alloc rows.
  return query
  select 'landed_cost'::text, c.id::text, c.cost_date, c.location_id, ('Landed cost ' || coalesce(nullif(c.shipment_ref, ''), left(c.id::text, 8)))::text, null::text, true, null::date, null::text, null::text,
    public._landed_jlines97(c.id, 'post')
  from public.landed_costs c
  where c.status in ('posted', 'void') and c.posted_at is not null and c.cost_date >= p_start and public._acct_need('landed_cost', c.id::text, true);

  -- bos97: a voided landed cost has its own counter entry (the sold part is released from the variance account, only what is still on the shelf leaves the inventory account)
  return query
  select 'landed_cost_void'::text, c.id::text, (c.void_at at time zone 'Asia/Dhaka')::date, c.location_id, ('Landed cost void ' || coalesce(nullif(c.shipment_ref, ''), left(c.id::text, 8)))::text, null::text, true, null::date, null::text, null::text,
    public._landed_jlines97(c.id, 'void')
  from public.landed_costs c
  where c.status = 'void' and c.posted_at is not null and (c.void_at at time zone 'Asia/Dhaka')::date >= p_start
    and exists (select 1 from public.journal_entries e where e.source_type = 'landed_cost' and e.source_id = c.id::text and e.reverses_id is null)
    and public._acct_need('landed_cost_void', c.id::text, true);
end $function$
$f$; end if; end $p103$;

-- ---- public._acct_stock_moves85(date) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._acct_stock_moves85(p_start date)
 RETURNS TABLE(lid bigint, cls text, d date, loc integer, qty numeric, rev boolean, nocost boolean, amt numeric, ikey text, xkey text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with cfg as (select public.rule_on('acct_count_adjust') a, public.rule_on('acct_stock_opening') o, public.rule_on('acct_issue_out') i,
                      coalesce(public.rule_txt('acct_transfer_mode'), 'off') = 'location_tagged' x, greatest(p_start, coalesce(public._acct_from85(), p_start)) f,
                      public.rule_on('acct_manual_prod_in103') p /* bos103 */),
  m as (
    select l.id, l.location_id, l.qty_delta, l.reason = 'reversal' rv, it.item_type, (l.made_at at time zone 'Asia/Dhaka')::date d,
           case coalesce(o.reason, l.reason)
             when 'count_adjust' then 'adjust' when 'opening' then 'opening'
             when 'issue_out' then case when coalesce(o.ref_type, l.ref_type) in ('issue', 'entry') then 'issue' end
             when 'transfer_out' then 'xfer' when 'transfer_in' then 'xfer'
             when 'production_in' then case when not exists (select 1 from public.production_runs pr where pr.id::text = coalesce(o.ref_id, l.ref_id)) then 'prodin' end /* bos103: direct production-in, no recipe run */ end cls,
           case when coalesce(l.unit_cost, 0) > 0 then l.unit_cost
                when l.reason = 'transfer_in' then (select s.unit_cost from public.stock_ledger_eff96 s where s.reason = 'transfer_out' and s.ref_type is not distinct from l.ref_type
                                                      and s.ref_id is not distinct from l.ref_id and s.item_id = l.item_id and coalesce(s.unit_cost, 0) > 0 order by s.id limit 1) end c
    from public.stock_ledger_eff96 l join public.items it on it.id = l.item_id left join public.stock_ledger o on o.id = l.reverses_id /* bos96 */
    where l.reason in ('count_adjust', 'opening', 'issue_out', 'transfer_out', 'transfer_in', 'reversal', 'production_in') /* bos103 */
      and l.made_at >= ((p_start::timestamp at time zone 'Asia/Dhaka') - interval '2 days'))
  select m.id, m.cls, m.d, m.location_id, m.qty_delta, m.rv, m.c is null, round(abs(m.qty_delta) * coalesce(m.c, 0), 2), public._acct_inv_key(m.item_type),
         case m.cls when 'adjust' then 'stock_adjust' when 'opening' then 'stock_opening_equity' when 'issue' then 'stock_issue_use' when 'prodin' then 'overhead_absorbed' /* bos103 */ else 'interloc_clearing' end
  from m cross join cfg
  where m.cls is not null and m.d >= cfg.f
    and not (m.cls = 'opening' and exists (select 1 from public.opening_covered103 a where m.id = any (a.covered_ids) and (a.location_id is null or a.location_id = m.location_id))) /* bos96: an opening that a decision of the opening-stock helper covers is not posted twice */
    and ((m.cls = 'adjust' and cfg.a) or (m.cls = 'opening' and cfg.o) or (m.cls = 'issue' and cfg.i) or (m.cls = 'xfer' and cfg.x) or (m.cls = 'prodin' and cfg.p))
    and (m.c is null or round(abs(m.qty_delta) * m.c, 2) >= 0.01);
$function$
$f$; end if; end $p103$;

-- ---- public.inventory_vs_gl(date,integer) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.inventory_vs_gl(p_date date DEFAULT NULL::date, p_loc integer DEFAULT NULL::integer)
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
end $function$
$f$; end if; end $p103$;

-- ---- public._cw_docs96() ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._cw_docs96()
 RETURNS TABLE(kind text, ref text, loc integer, d date, n integer, gl boolean, move text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with u as (
    select l.id, l.location_id, l.reason, l.ref_type, l.ref_id, (l.made_at at time zone 'Asia/Dhaka')::date dd,
      case when l.reason = 'wastage' and l.ref_type = 'wastage' then 'wastage'
           when l.reason = 'issue_out' and l.ref_type = 'production' then 'production'
           when l.reason in ('transfer_out', 'transfer_in') and l.ref_type = 'transfer' then 'transfer'
           when l.reason = 'purchase_return' and l.ref_type = 'purchase' then 'purchase_return'
           when l.reason in ('count_adjust', 'opening') or (l.reason = 'issue_out' and l.ref_type is distinct from 'production')
           or (l.reason = 'production_in' and not exists (select 1 from public.production_runs pr where pr.id::text = l.ref_id)) /* bos103: direct production-in without a recipe */ then 'ledger' end k
    from public.stock_ledger_eff96 l
    where coalesce(l.unit_cost, 0) = 0 and l.reverses_id is null and l.reason <> 'reversal' and not public._cost_free80(l.item_id)
      and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id)
      and (l.reason <> 'transfer_in' or not exists (select 1 from public.stock_ledger_eff96 s where s.reason = 'transfer_out' and s.ref_type is not distinct from l.ref_type
                                                      and s.ref_id is not distinct from l.ref_id and s.item_id = l.item_id and coalesce(s.unit_cost, 0) > 0))
      and not (l.reason = 'opening' and exists (select 1 from public.opening_covered103 a where l.id = any (a.covered_ids)  /* bos103 */ and (a.location_id is null or a.location_id = l.location_id)))),
  g as (
    select u.k, case when u.k = 'ledger' then u.id::text else u.ref_id end ref, (array_agg(u.location_id order by u.id))[1] loc, min(u.dd) d, count(*)::int n, min(u.reason) r
    from u where u.k is not null group by 1, 2)
  select g.k, g.ref, g.loc, g.d, g.n,
         public.rule_on('accounting_on') and public._acct_start() is not null and g.d >= public._acct_start() and g.d >= coalesce(public._acct_from85(), public._acct_start())
         and case g.k when 'wastage' then true when 'production' then true when 'transfer' then coalesce(public.rule_txt('acct_transfer_mode'), 'off') = 'location_tagged'
                      when 'purchase_return' then public.rule_on('acct_purchase_variance')
                      else case g.r when 'count_adjust' then public.rule_on('acct_count_adjust') when 'opening' then public.rule_on('acct_stock_opening') when 'production_in' then public.rule_on('acct_manual_prod_in103') /* bos103 */ else public.rule_on('acct_issue_out') end end,
         g.r
  from g where g.ref is not null and not public._cw_posted96(g.k, g.ref);
$function$
$f$; end if; end $p103$;

-- ---- public._cw_rows96(text,text) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._cw_rows96(p_kind text, p_ref text)
 RETURNS TABLE(lid bigint, item_id uuid, loc integer, qty numeric, reason text, made_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select l.id, l.item_id, l.location_id, l.qty_delta, l.reason, l.made_at
  from public.stock_ledger_eff96 l
  where coalesce(l.unit_cost, 0) = 0 and l.reverses_id is null and l.reason <> 'reversal' and not public._cost_free80(l.item_id)
    and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id)
    and (l.reason <> 'transfer_in' or not exists (select 1 from public.stock_ledger_eff96 s where s.reason = 'transfer_out' and s.ref_type is not distinct from l.ref_type
                                                    and s.ref_id is not distinct from l.ref_id and s.item_id = l.item_id and coalesce(s.unit_cost, 0) > 0))
    and not (l.reason = 'opening' and exists (select 1 from public.opening_covered103 a where l.id = any (a.covered_ids)  /* bos103 */ and (a.location_id is null or a.location_id = l.location_id)))
    and case p_kind
      when 'wastage' then l.reason = 'wastage' and l.ref_type = 'wastage' and l.ref_id = p_ref
      when 'production' then l.reason = 'issue_out' and l.ref_type = 'production' and l.ref_id = p_ref
      when 'transfer' then l.reason in ('transfer_out', 'transfer_in') and l.ref_type = 'transfer' and l.ref_id = p_ref
      when 'purchase_return' then l.reason = 'purchase_return' and l.ref_type = 'purchase' and l.ref_id = p_ref
      when 'ledger' then l.id::text = p_ref and (l.reason in ('count_adjust', 'opening') or (l.reason = 'issue_out' and l.ref_type is distinct from 'production')
                                       or (l.reason = 'production_in' and not exists (select 1 from public.production_runs pr where pr.id::text = l.ref_id))) /* bos103 */
      else false end;
$function$
$f$; end if; end $p103$;

-- ---- public._cw_posted96(text,text) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._cw_posted96(p_kind text, p_ref text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case p_kind
    when 'wastage' then exists (select 1 from public.journal_entries e where e.source_type = 'wastage' and e.source_id = p_ref and e.reverses_id is null)
    when 'production' then exists (select 1 from public.journal_entries e where e.source_type = 'production' and e.source_id = p_ref and e.reverses_id is null)
    when 'purchase_return' then exists (select 1 from public.journal_entries e where e.source_type = 'purchase_variance' and e.source_id = p_ref and e.reverses_id is null)
    when 'transfer' then exists (select 1 from public.journal_entries e where e.reverses_id is null and ((e.source_type = 'stock_transfer' and e.source_id in
                                   (select s.id::text from public.stock_ledger s where s.ref_type = 'transfer' and s.ref_id = p_ref)) or (e.source_type = 'transit_loss' and e.source_id = p_ref)))
    when 'ledger' then exists (select 1 from public.journal_entries e where e.source_type in ('stock_adjust', 'stock_opening', 'stock_issue', 'stock_prodin') /* bos103 */ and e.source_id = p_ref and e.reverses_id is null)
    else false end;
$function$
$f$; end if; end $p103$;

-- ---- public.recipe_cost(uuid,integer) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.recipe_cost(p_recipe uuid, p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes; ls jsonb := '[]'::jsonb; raw_t numeric := 0; pack_t numeric := 0; raw_d numeric := 0; pack_d numeric := 0; complete boolean := true; n record; av numeric; td numeric; yb numeric; gate text;
        conv jsonb; conv_amt numeric; mat numeric; matd numeric; gap numeric; thr numeric; gl numeric; fb int := 0; cinc boolean; mode_ text;
begin
  if p_loc is not null then
    if not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;      -- same rule as the stock cost columns
  elsif not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  gate := public._recipe_gate73(p_recipe);      -- bos73: 'on' = refuse an unapproved recipe
  yb := public._base_qty(r.item_id, r.yield_qty, r.yield_unit);
  for n in select * from public._recipe_need(p_recipe, 1, coalesce(p_loc, 0)) order by kind, code loop      -- bos74: the same function the production run uses
    if p_loc is not null then
      select avg_cost into av from public.stock_balance where item_id = n.item_id and location_id = p_loc;
    else
      select sum(qty * avg_cost) / nullif(sum(qty), 0) into av from public.stock_balance
        where item_id = n.item_id and qty > 0 and avg_cost is not null and (public._all_locs() or public.can_loc(location_id)) and public._cost_ok(location_id);
    end if;
    if av is null and public._cost_free80(n.item_id) then av := 0; end if;   -- bos103: a free-cost item is a known cost 0 (production_post accepts it the same way)
    td := public._today_cost(n.item_id, p_loc);
    if av is null then complete := false;
    elsif n.kind = 'packaging' then pack_t := pack_t + n.need * av; else raw_t := raw_t + n.need * av; end if;
    if td is null then fb := fb + 1; end if;
    if coalesce(td, av) is not null then
      if n.kind = 'packaging' then pack_d := pack_d + n.need * coalesce(td, av); else raw_d := raw_d + n.need * coalesce(td, av); end if;
    end if;
    gl := case when av is not null and av > 0 and td is not null then round((td - av) / av * 100, 2) end;
    ls := ls || jsonb_build_object('ingredient_item_id', n.item_id, 'code', n.code, 'kind', n.kind, 'need_base', n.need, 'unit_cost', av, 'line_cost', case when av is null then null else round(n.need * av, 4) end,
      'today_unit_cost', td, 'gap_pct', gl, 'waste_missing', n.waste_missing);
  end loop;
  conv := public._conv_cost(p_recipe, p_loc, 1, yb, (now() at time zone 'Asia/Dhaka')::date, case when p_loc is null then 'recipe' end);
  conv_amt := coalesce((conv->>'amount')::numeric, 0); mode_ := conv->>'mode'; cinc := mode_ <> 'off' and not (conv->>'complete')::boolean;
  mat := raw_t + pack_t; matd := raw_d + pack_d;
  gap := case when complete and mat > 0 then round((matd - mat) / mat * 100, 2) end;
  thr := public.rule_num('cost_gap_warn_pct');
  return jsonb_build_object('recipe_id', p_recipe, 'lines', ls, 'complete', complete,
    'rows', jsonb_build_array(jsonb_build_object('row', 'raw', 'amount', case when complete then round(raw_t, 4) end), jsonb_build_object('row', 'packaging', 'amount', case when complete then round(pack_t, 4) end),
      jsonb_build_object('row', 'conversion', 'amount', round(conv_amt, 4), 'mode', mode_, 'complete', not cinc)),
    'raw_cost', case when complete then round(raw_t, 4) end, 'packaging_cost', case when complete then round(pack_t, 4) end, 'material_cost', case when complete then round(mat, 4) end,
    'conversion_cost', round(conv_amt, 4), 'conversion_mode', mode_, 'conversion_complete', not cinc, 'conversion_detail', conv->'detail', 'conversion_reason', conv->>'reason',
    'conversion_flag', case when cinc then 'রূপান্তর খরচ অসম্পূর্ণ' end,
    'batch_cost', case when complete then round(mat + conv_amt, 4) end,
    'unit_cost', case when complete and yb > 0 then round((mat + conv_amt) / yb, 6) end, 'yield_base', yb,
    'approved', r.approved_at is not null, 'approval_warn', gate = 'warn',
    'today', jsonb_build_object('raw_cost', round(raw_d, 4), 'packaging_cost', round(pack_d, 4), 'material_cost', round(matd, 4), 'batch_cost', round(matd + conv_amt, 4),
      'unit_cost', case when yb > 0 then round((matd + conv_amt) / yb, 6) end, 'gap_pct', gap, 'gap_warn', thr is not null and gap is not null and abs(gap) > thr,
      'lines_without_purchase_price', fb, 'note', 'display only - never booked'));
end $function$
$f$; end if; end $p103$;

-- ---- public._ob_plan96(text,integer,text,date) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._ob_plan96(p_option text, p_loc integer, p_account text, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); vals jsonb := '{}'::jsonb; cov jsonb := '{}'::jsonb; unt numeric := 0; k text; v numeric; c numeric; amt jsonb := '{}'::jsonb; tot numeric := 0;
        lines jsonb := '[]'::jsonb; ctr bigint; ctr_code text; acc public.coa_accounts; d date; n_unc int; sw numeric; warns jsonb := '[]'::jsonb; prior boolean := false; cov_all numeric; val_all numeric; maxlid bigint; cov_ids bigint[];
begin
  if st is null then return jsonb_build_object('ok', false, 'error', 'data_needed'); end if;
  if p_option is null or p_option not in ('owner_capital', 'existing_account', 'skip', 'difference') then return jsonb_build_object('ok', false, 'error', 'bad_option'); end if;
  if p_loc is null and p_option <> 'difference' then return jsonb_build_object('ok', false, 'error', 'place_needed'); end if;
  if p_loc is not null and not exists (select 1 from public.locations where id = p_loc) then return jsonb_build_object('ok', false, 'error', 'bad_location'); end if;
  prior := exists (select 1 from public.opening_stock_actions96 a where a.option <> 'skip' and (a.location_id is null or p_loc is null or a.location_id = p_loc));
  -- bos103: a decision that is already applied answers already_applied only when no opening row is left that it did not cover; a cost supplied LATER to an opening row
  -- (or an opening entered after the decision) can be booked ONCE by one more decision of that place (the rows it covers are then frozen again); a company-wide decision is still refused
  if prior and (p_loc is null or not exists (select 1 from public._ob_rows96(p_loc) r where not r.nocost and not r.by_switch and not r.handled)) then
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
  if prior then warns := warns || to_jsonb('followup'::text); end if;   -- bos103
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
      if p_option = 'difference' and not prior then v := greatest(v - c, 0); end if;   -- bos103: a follow-up decision books only the rows the first one did not cover
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
end $function$
$f$; end if; end $p103$;

-- ---- public.opening_stock_apply96(text,integer,text,date,text,uuid) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.opening_stock_apply96(p_option text, p_loc integer, p_account text DEFAULT NULL::text, p_date date DEFAULT NULL::date, p_reason text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pl jsonb; eid bigint; aid bigint; r public.opening_stock_actions96; staff text; nprev int; pa bigint; fl public.opening_stock_followups103;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if p_client is null then raise exception 'client_id_needed'; end if;
  perform public._client_lock(p_client);
  select * into r from public.opening_stock_actions96 where client_id = p_client;
  if found then return jsonb_build_object('dup', true, 'id', r.id, 'option', r.option, 'entry_id', r.entry_id); end if;
  select * into fl from public.opening_stock_followups103 where client_id = p_client;   -- bos103
  if found then return jsonb_build_object('dup', true, 'id', fl.id, 'option', fl.option, 'entry_id', fl.entry_id, 'followup', true); end if;
  perform pg_advisory_xact_lock(hashtextextended('opening_stock96', 0));
  pl := public._ob_plan96(p_option, p_loc, p_account, p_date);
  if not (pl->>'ok')::boolean then raise exception '%', pl->>'error' using detail = left(coalesce(pl->>'detail', ''), 500); end if;
  select staff_id into staff from public.profiles where id = auth.uid();
  select count(*), max(a.id) into nprev, pa from public.opening_stock_actions96 a where a.option <> 'skip' and (a.location_id is null or p_loc is null or a.location_id = p_loc);   -- bos103: one decision per place stays; a later cost is booked by ONE follow-up record
  if nprev > 0 then nprev := nprev + (select count(*) from public.opening_stock_followups103 f where f.location_id is not distinct from p_loc); end if;
  if p_option <> 'skip' then
    eid := public._acct_write((pl->>'date')::date, p_loc, 'opening_stock96', 'loc:' || coalesce(p_loc::text, 'all') || case when nprev > 0 then ':f' || nprev::text else '' end, p_option,
             'Opening stock (' || p_option || ')' || coalesce(': ' || nullif(btrim(p_reason), ''), ''), null, pl->'post_lines', null, p_client, null);
  end if;
  if nprev > 0 then   -- bos103: follow-up decision for the opening rows the first decision did not cover
    insert into public.opening_stock_followups103 (action_id, location_id, option, account_code, amount, entry_id, covered_ids, reason, client_id, created_by, created_staff)
      values (pa, p_loc, p_option, case when p_option in ('existing_account', 'difference') then p_account end, coalesce((pl->>'amount')::numeric, 0), eid,
              (select coalesce(array_agg(x::bigint), '{}') from jsonb_array_elements_text(pl->'covered_ids') x), left(nullif(btrim(p_reason), ''), 300), p_client, auth.uid(), staff) returning id into aid;
    return jsonb_build_object('id', aid, 'option', p_option, 'location_id', p_loc, 'entry_id', eid, 'amount', coalesce((pl->>'amount')::numeric, 0), 'warnings', pl->'warnings', 'followup', true);
  end if;
  insert into public.opening_stock_actions96 (location_id, option, account_code, amount, entry_id, covered_ids, reason, client_id, created_by, created_staff)
    values (p_loc, p_option, case when p_option in ('existing_account', 'difference') then p_account end, coalesce((pl->>'amount')::numeric, 0), eid, (select coalesce(array_agg(x::bigint), '{}') from jsonb_array_elements_text(pl->'covered_ids') x),
            left(nullif(btrim(p_reason), ''), 300), p_client, auth.uid(), staff) returning id into aid;
  return jsonb_build_object('id', aid, 'option', p_option, 'location_id', p_loc, 'entry_id', eid, 'amount', coalesce((pl->>'amount')::numeric, 0), 'warnings', pl->'warnings');
end $function$
$f$; end if; end $p103$;

-- ---- public._setup_chk81(text) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._setup_chk81(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n bigint := 0; tot bigint := 0; ap boolean := true; st date := public._acct_start(); td date := public._acct_today(); h numeric; last_in timestamptz;
        req text[] := array['sales', 'cogs', 'inv_finished', 'inv_raw', 'inv_pack', 'payable', 'receivable', 'pay_cash', 'owner_capital', 'overhead_absorbed'];
begin
  case p_code
  when 'stk_tracked' then
    select count(*) into tot from public.items where tracked and coalesce(is_active, true);
    n := case when tot = 0 then 1 else 0 end;
  when 'stk_unit' then
    select count(*), count(*) filter (where nullif(btrim(coalesce(base_unit, '')), '') is null) into tot, n from public.items where tracked and coalesce(is_active, true);
  when 'stk_opening' then
    select count(*), count(*) filter (where not exists (select 1 from public.stock_ledger l where l.item_id = i.id)) into tot, n from public.items i where i.tracked and coalesce(i.is_active, true);
  when 'stk_conv' then
    select count(*), count(*) filter (where exists (select 1 from unnest(coalesce(i.sell_units, '{}'::text[])) u where u is not null and u <> '' and public._unit_factor_base(i.id, u) is null))
      into tot, n from public.items i where i.tracked and coalesce(i.is_active, true);
  when 'stk_cost' then   -- stock on hand with no known cost; blank or 0 = unknown
    select count(*), count(*) filter (where not exists (select 1 from public.stock_balance b where b.item_id = i.id and b.avg_cost > 0)
                                      and not exists (select 1 from public.item_costs c where c.item_id = i.id and c.cost_price > 0))
      into tot, n from public.items i where i.tracked and coalesce(i.is_active, true) and exists (select 1 from public.stock_balance b2 where b2.item_id = i.id and b2.qty > 0);
  when 'stk_neg', 'flw_neg' then
    select count(*) into n from public.stock_balance where qty < 0;
    select count(*) into tot from public.stock_balance;
  when 'acc_start' then
    n := case when st is null then 1 else 0 end; tot := 1;
  when 'acc_coa' then
    select count(*) into tot from public.coa_accounts where active;
    n := case when tot = 0 then 1 else 0 end;
  when 'acc_map' then
    tot := array_length(req, 1);
    select count(*) into n from unnest(req) k where not exists (select 1 from public.acct_mappings m join public.coa_accounts a on a.id = m.account_id where m.key = k and a.active);
  when 'acc_opening' then
    tot := 1;
    n := case when exists (select 1 from public.journal_entries o where o.source_type = 'opening' and o.reverses_id is null and not exists (select 1 from public.journal_entries r where r.reverses_id = o.id)) then 0 else 1 end;
  when 'acc_wait', 'flw_acc_wait' then
    if st is null then ap := false; else select count(*) into n from public._acct_docs(st) d where d.waiting is not null; end if;
  when 'acc_err', 'flw_acc_err' then
    if st is null then ap := false; else
      select count(*) into n from public.acct_post_errors72 x where exists (select 1 from public._acct_docs(st) dd where dd.source_type = x.source_type and dd.source_id = x.source_id and dd.waiting is null);
    end if;
  when 'flw_acc_old' then   -- not yet in the books and dated before today (no invented age limit: "earlier than today")
    if st is null then ap := false; else
      select count(*) into n from public._acct_docs(st) d where d.waiting is null and d.entry_date < td;
    end if;
  when 'prd_recipes' then
    select count(*) into tot from public.recipes where active;
    n := case when tot = 0 then 1 else 0 end;
  when 'prd_lines' then
    select count(*), count(*) filter (where not exists (select 1 from public.recipe_lines l where l.recipe_id = r.id and l.active)) into tot, n from public.recipes r where r.active;
  when 'prd_yield' then
    select count(*), count(*) filter (where r.yield_qty is null or r.yield_qty <= 0) into tot, n from public.recipes r where r.active;
  when 'prd_approve' then
    select count(*), count(*) filter (where r.approved_at is null) into tot, n from public.recipes r where r.active;
  when 'prd_icost' then
    select count(distinct l.ingredient_item_id), count(distinct l.ingredient_item_id) filter (where not exists (select 1 from public.stock_balance b where b.item_id = l.ingredient_item_id and b.avg_cost > 0)
                                                              and not exists (select 1 from public.item_costs c where c.item_id = l.ingredient_item_id and c.cost_price > 0))
      into tot, n from public.recipe_lines l join public.recipes r on r.id = l.recipe_id and r.active where l.active;
  when 'prd_unit' then
    select count(*), count(*) filter (where nullif(l.unit, '') is not null and public._unit_factor_base(l.ingredient_item_id, l.unit) is null)
      into tot, n from public.recipe_lines l join public.recipes r on r.id = l.recipe_id and r.active where l.active;
  when 'prd_conv' then
    select count(*), count(*) filter (where (c.mode = 'pool' and coalesce(c.normal_monthly_output, 0) <= 0)
                                         or (c.mode = 'recipe' and not exists (select 1 from public.recipe_cost_components x where x.active)))
      into tot, n from public.location_cost_cfg c where c.mode <> 'off';
  when 'flw_prod_cost' then
    select count(*) into tot from public.production_runs where status is distinct from 'void';
    select count(*) into n from public.production_runs where status is distinct from 'void' and cost_complete is false;
  when 'flw_pool' then
    select count(*), count(*) filter (where not exists (select 1 from public.factory_cost_pools p where p.location_id = c.location_id and p.active and p.month = date_trunc('month', td)::date))
      into tot, n from public.location_cost_cfg c where c.mode = 'pool';
    ap := tot > 0;
  when 'cs_sources' then
    select count(*) into tot from public.cost_sources where active;
    n := case when tot = 0 then 1 else 0 end;
  when 'cs_rule' then
    select count(*), count(*) filter (where not exists (select 1 from public.cost_source_rules r where r.source_id = s.id and r.status = 'approved')) into tot, n from public.cost_sources s where s.active;
  when 'cs_attrib' then
    select count(*) into tot from public.location_cost_attribution where active;
    n := case when tot = 0 then 1 else 0 end;
  when 'onl_channels' then
    select count(*) into tot from public.sales_channels where active;
    n := case when tot = 0 then 1 else 0 end;
  when 'onl_url' then
    ap := public.rule_on('web_form_on'); n := case when ap and coalesce(public.rule_txt('web_form_public_url'), '') = '' then 1 else 0 end; tot := 1;
  when 'onl_bot' then
    ap := public.rule_on('meta_intake_on'); n := case when ap and not exists (select 1 from public.intake_bots where active) then 1 else 0 end; tot := 1;
  when 'flw_inbox_new' then
    select count(*) into n from public.inbound_messages where status = 'new' and (received_at at time zone 'Asia/Dhaka')::date < td;
    select count(*) into tot from public.inbound_messages;
  when 'flw_inbox_silent' then
    h := public.rule_num('inbox_silence_hours');
    if coalesce(h, 0) <= 0 then ap := false; else
      select max(received_at) into last_in from public.inbound_messages;
      n := case when last_in is not null and last_in < now() - make_interval(hours => h::int) then 1 else 0 end; tot := 1;
    end if;
  when 'flw_intake_fail' then
    select count(*) into n from public.intake_failures where state = 'failed';
    select count(*) into tot from public.intake_failures;
  when 'flw_grn_double103' then   -- bos103: GRN is the stock source, the guard is off and posted bills add their own stock after the first GRN stock row: the same goods are counted twice
    ap := coalesce(public.rule_txt('grn_receipt_source'), 'purchase') = 'grn' and coalesce(public.rule_txt('purchase_grn_guard'), 'off') = 'off';
    if ap then
      select count(distinct l.ref_id) into n from public.stock_ledger l
        where l.reason = 'purchase_in' and l.ref_type = 'purchase' and l.reverses_id is null and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id)
          and l.made_at >= (select min(g.made_at) from public.stock_ledger g where g.reason = 'purchase_in' and g.ref_type = 'entry' and g.reverses_id is null);
      select count(distinct g.ref_id) into tot from public.stock_ledger g where g.reason = 'purchase_in' and g.ref_type = 'entry' and g.reverses_id is null;
    end if;
  when 'flw_oo_flags' then
    select count(*) into n from public.online_order_flags where state = 'open';
    select count(*) into tot from public.online_order_flags;
  else
    return jsonb_build_object('n', null, 'total', null, 'applies', false, 'unknown_check', true);
  end case;
  return jsonb_build_object('n', n, 'total', tot, 'applies', ap);
end $function$
$f$; end if; end $p103$;

-- ---- public.setup_recommendations() ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.setup_recommendations()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare out_ jsonb := '[]'::jsonb; d record; r public.rules; eff jsonb; st text; chosen boolean; iss jsonb; c record; cj jsonb;
        cnt_ok int := 0; cnt_rec int := 0; cnt_own int := 0; cnt_info int := 0; cnt_ni int := 0; ready boolean; rv jsonb;
begin
  if not public._setup_view81() then raise exception 'not allowed'; end if;
  for d in select * from public.setup_rec_defs81 where active order by sort, code loop
    rv := public._rec_value103(d.rule_key, d.rec_value);   -- bos103: purchase_grn_guard = skip when GRN is the stock source
    select * into r from public.rules where key = d.rule_key;
    iss := '[]'::jsonb; ready := true;
    if not found then
      st := 'not_installed'; cnt_ni := cnt_ni + 1; eff := null; chosen := false;
    else
      eff := coalesce(r.value, r.default_value); chosen := r.value is not null;
      if rv is null then st := 'info'; cnt_info := cnt_info + 1;
      elsif eff is not distinct from rv then st := 'ok'; cnt_ok := cnt_ok + 1;
      elsif chosen then st := 'owner_chosen'; cnt_own := cnt_own + 1;
      else st := 'recommended'; cnt_rec := cnt_rec + 1; end if;
      for c in select x.code, x.label_bn, x.label_mix, x.label_en from public.setup_check_defs81 x where x.code = any (d.ready_checks) and x.active loop
        cj := public._setup_chk81(c.code);
        if coalesce((cj->>'applies')::boolean, false) and coalesce((cj->>'n')::bigint, 0) > 0 then
          ready := false;
          iss := iss || jsonb_build_object('code', c.code, 'n', (cj->>'n')::bigint, 'label_bn', c.label_bn, 'label_mix', c.label_mix, 'label_en', c.label_en);
        end if;
      end loop;
    end if;
    out_ := out_ || jsonb_build_object('code', d.code, 'rule_key', d.rule_key, 'phase', d.phase, 'module', d.module, 'kind', r.kind,
      'status', st, 'recommended', rv, 'current', eff, 'default', r.default_value, 'owner_chosen', chosen,
      'min', r.min_value, 'max', r.max_value, 'unit', r.unit, 'choices', r.choices,
      'ready', ready, 'ready_issues', iss,
      'rule_label_bn', r.label_bn, 'rule_label_mix', r.label_mix, 'rule_label_en', r.label_en,
      'reason_bn', d.reason_bn, 'reason_mix', coalesce(d.reason_mix, d.reason_bn), 'reason_en', d.reason_en, 'sort', d.sort);
  end loop;
  return jsonb_build_object('advisory', true, 'can_apply', public.is_owner(),
    'summary', jsonb_build_object('total', jsonb_array_length(out_), 'ok', cnt_ok, 'recommended', cnt_rec, 'owner_chosen', cnt_own, 'info', cnt_info, 'not_installed', cnt_ni),
    'items', out_);
end $function$
$f$; end if; end $p103$;

-- ---- public.setup_recommend_apply(uuid,text[],boolean,boolean) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.setup_recommend_apply(p_client uuid, p_codes text[] DEFAULT NULL::text[], p_overwrite boolean DEFAULT false, p_ignore_ready boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d record; r public.rules; eff jsonb; applied jsonb := '[]'::jsonb; skipped jsonb := '[]'::jsonb; old_ jsonb; ex public.setup_apply_batches81; res jsonb; sid text;
        c record; cj jsonb; ready boolean; owr boolean; rv jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_client is null then raise exception 'client_id_required'; end if;
  perform public._client_lock(p_client);
  select * into ex from public.setup_apply_batches81 where client_id = p_client;
  if found then return ex.result || jsonb_build_object('dup', true); end if;
  for d in select * from public.setup_rec_defs81 where active and (p_codes is null or code = any (p_codes)) order by sort, code loop
    rv := public._rec_value103(d.rule_key, d.rec_value);   -- bos103: purchase_grn_guard = skip when GRN is the stock source
    select * into r from public.rules where key = d.rule_key;
    if not found then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'not_installed'); continue; end if;
    if rv is null then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'no_recommendation'); continue; end if;
    eff := coalesce(r.value, r.default_value);
    if eff is not distinct from rv then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'already'); continue; end if;
    owr := r.value is not null;                       -- the owner already chose another value
    if owr and not (p_overwrite and p_codes is not null) then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'owner_chosen'); continue; end if;
    ready := true;
    if not p_ignore_ready then
      for c in select x.code from public.setup_check_defs81 x where x.code = any (d.ready_checks) and x.active loop
        cj := public._setup_chk81(c.code);
        if coalesce((cj->>'applies')::boolean, false) and coalesce((cj->>'n')::bigint, 0) > 0 then ready := false; end if;
      end loop;
    end if;
    if not ready then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'not_ready'); continue; end if;
    begin
      perform public.set_rule(d.rule_key, rv);      -- validates the value by the rule's kind; the rules audit trigger logs it too
    exception when others then
      skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'rejected', 'error', left(sqlerrm, 120)); continue;
    end;
    old_ := r.value;
    applied := applied || jsonb_build_object('code', d.code, 'rule_key', d.rule_key, 'old', old_, 'new', rv, 'overwrote', owr);
  end loop;
  res := jsonb_build_object('applied', applied, 'skipped', skipped, 'count', jsonb_array_length(applied));
  insert into public.setup_apply_batches81 (client_id, applied_by, overwrite, ignore_ready, result) values (p_client, auth.uid(), coalesce(p_overwrite, false), coalesce(p_ignore_ready, false), res);
  insert into public.setup_apply_lines81 (batch_id, code, rule_key, old_value, new_value, overwrote)
    select p_client, x->>'code', x->>'rule_key', case when jsonb_typeof(x->'old') = 'null' then null else x->'old' end, x->'new', (x->>'overwrote')::boolean from jsonb_array_elements(applied) x;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'setup_apply', 'setup_apply_batches81', p_client::text, jsonb_build_object('applied', applied, 'skipped_count', jsonb_array_length(skipped), 'overwrite', coalesce(p_overwrite, false), 'ignore_ready', coalesce(p_ignore_ready, false)));
  return res;
end $function$
$f$; end if; end $p103$;

-- ---- public._inb_pii_f99(text,text) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._inb_pii_f99(p_field text, p_val text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare mode_ text := public._inb_pii_mode99(); hide boolean;
begin
  if mode_ = 'off' or p_val is null then return p_val; end if;
  if coalesce(current_setting('bos.inb_unmask99', true), '') = txid_current()::text then return p_val; end if;      -- inside inbox_unmask only
  hide := case p_field
    when 'mobile' then true
    when 'handle' then mode_ = 'mask_all_pii' or p_val ~ '^\+?[0-9][0-9 ()-]{5,}$'
    when 'address' then mode_ in ('mask_phone_address', 'mask_all_pii')
    else mode_ = 'mask_all_pii' end;
  return case when hide then public._inb_mask99(p_field, p_val)
              when p_field in ('text', 'name', 'address', 'attachment') then public._inb_mask_phones103(p_val)   -- bos103: a number typed inside free text is masked too
              else p_val end;
end $function$
$f$; end if; end $p103$;

-- ---- public._inb_pii_json99(jsonb) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._inb_pii_json99(j jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare mode_ text := public._inb_pii_mode99(); k text;
begin
  if mode_ = 'off' then return j; end if;
  if j ? 'customer_mobile' and jsonb_typeof(j->'customer_mobile') = 'string' then j := jsonb_set(j, '{customer_mobile}', to_jsonb(public._inb_pii_f99('mobile', j->>'customer_mobile'))); end if;
  if j ? 'address' and jsonb_typeof(j->'address') = 'string' then j := jsonb_set(j, '{address}', to_jsonb(public._inb_pii_f99('address', j->>'address'))); end if;
  if j ? 'customer_name' and jsonb_typeof(j->'customer_name') = 'string' then j := jsonb_set(j, '{customer_name}', to_jsonb(public._inb_pii_f99('name', j->>'customer_name'))); end if;
  for k in select unnest(array['note', 'draft_note', 'cancel_reason']) loop   -- bos103: free text of the order
    if j ? k and jsonb_typeof(j->k) = 'string' then j := jsonb_set(j, array[k], to_jsonb(public._inb_pii_f99('text', j->>k))); end if;
  end loop;
  return j || jsonb_build_object('pii_mode', mode_);
end $function$
$f$; end if; end $p103$;

-- ---- public.inbox_list(integer,text,integer) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.inbox_list(p_loc integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 100)
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
    select m.id rid, jsonb_build_object('id', m.id, 'channel_id', m.channel_id, 'channel', c.name_bn, 'kind', c.kind, 'location_id', m.location_id, 'status', m.status, 'received_at', m.received_at, 'msg_time', m.msg_time,
      'linked_order_id', m.linked_order_id, 'draft_order_id', m.draft_order_id, 'has_attachment', m.attachment_ref is not null,
      'handle', case when public._inb_contact_ok(m.location_id) then public._inb_pii_f99('handle', m.customer_handle) end, 'name', case when public._inb_contact_ok(m.location_id) then public._inb_pii_f99('name', m.customer_name) end,   /* bos99 */
      'text', case when public._inb_contact_ok(m.location_id) then left(public._inb_pii_f99('text', m.msg_text), 200) /* bos103: mask first, cut after */ end, 'masked', not public._inb_contact_ok(m.location_id), 'pii_mode', public._inb_pii_mode99()) j   /* bos99 */
      from public.inbound_messages m join public.sales_channels c on c.id = m.channel_id
     where m.location_id = any (l) and (p_status is null or m.status = p_status)
     order by m.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z;
  if exists (select 1 from jsonb_array_elements(r) e where (e->>'masked')::boolean is false) then
    perform public._inb_audit_view('inbound_messages', 'list', jsonb_build_object('count', jsonb_array_length(r), 'loc', p_loc, 'status', p_status));
  end if;
  return r;
end $function$
$f$; end if; end $p103$;

-- ---- public.customer_directory(integer) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.customer_directory(p_limit integer DEFAULT 5000)
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
    select c.id, public._cust_pii103('mobile', c.mobile) /* bos103 */, c.name, c.type, c.active, c.tier_id, c.tier_locked, c.birthday, c.anniversary, public._cust_pii103('address', c.address), public._cust_pii103('mobile', c.whatsapp), public._cust_pii103('text', c.note), c.credit_limit, c.customer_since,
           coalesce(d.bal, 0), coalesce(s.tot, 0) - coalesce(r.amt, 0), coalesce(s.n, 0), s.last_d, coalesce(p.pts, 0)
    from public.customers c left join s on s.cid = c.id left join r on r.cid = c.id left join d on d.cid = c.id left join p on p.cid = c.id
    order by lower(c.name), c.mobile limit least(greatest(coalesce(p_limit, 5000), 1), 20000);
end $function$
$f$; end if; end $p103$;

-- ---- public.find_customer(text) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.find_customer(p_mobile text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m text := public.norm_mobile(p_mobile); c public.customers;
begin
  if not (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then raise exception 'not allowed'; end if;
  select * into c from public.customers where mobile = m;
  if not found then return jsonb_build_object('mobile', m, 'found', false); end if;
  return jsonb_build_object('found', true, 'id', c.id, 'mobile', public._cust_pii103('mobile', c.mobile) /* bos103 */, 'name', c.name, 'type', c.type, 'credit_limit', c.credit_limit, 'balance', public.customer_balance(c.id));
end $function$
$f$; end if; end $p103$;

-- ---- public._ob_rows96(integer) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._ob_rows96(p_loc integer)
 RETURNS TABLE(lid bigint, loc integer, k text, val numeric, nocost boolean, by_switch boolean, handled boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select l.id, l.location_id, public._acct_inv_key(it.item_type), round(l.qty_delta * coalesce(l.unit_cost, 0), 2), coalesce(l.unit_cost, 0) = 0,
         exists (select 1 from public.journal_entries e where e.source_type = 'stock_opening' and e.source_id = l.id::text and e.reverses_id is null),
         exists (select 1 from public.opening_covered103 a where l.id = any (a.covered_ids)   /* bos103 */ and (a.location_id is null or a.location_id = l.location_id))
  from public.stock_ledger_eff96 l join public.items it on it.id = l.item_id
  where l.reason = 'opening' and l.reverses_id is null and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id)
    and (p_loc is null or l.location_id = p_loc)
    and (l.made_at at time zone 'Asia/Dhaka')::date >= greatest(public._acct_start(), coalesce(public._acct_from85(), public._acct_start()));
$function$
$f$; end if; end $p103$;

-- ---- public.online_order_get(uuid) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.online_order_get(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$   -- bos76: was STABLE
declare o public.online_orders; ok boolean; j jsonb;
begin
  select * into o from public.online_orders where id = p_id;
  if not found or not public.is_active() or not public.can_do('POS', 'view') or not public.can_loc(o.location_id) then raise exception 'not allowed'; end if;
  ok := public._inb_contact_ok(o.location_id);                                                                -- bos76
  if ok then perform public._inb_audit_view('online_orders', o.id::text, jsonb_build_object('fields', 'customer_mobile,address')); end if;   -- bos76
  j := to_jsonb(o) - 'sale_client';
  if not ok then j := (j - 'customer_mobile' - 'address') || jsonb_build_object('masked', true); end if;      -- bos76
  j := public._inb_pii_json99(j);                                                                               -- bos99
  j := j || jsonb_build_object('flags', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'kind', f.kind, 'note', f.note, 'state', f.state, 'at', f.created_at) order by f.id) from public.online_order_flags f where f.order_id = o.id), '[]'::jsonb));   -- bos77
  return j || jsonb_build_object('events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_status, 'to', e.to_status, 'note', e.note, 'by', e.by_staff, 'at', e.at) order by e.id)
                                                                                  from public.online_order_events e where e.order_id = o.id), '[]'::jsonb));
end $function$
$f$; end if; end $p103$;

-- ---- public.online_orders_list(integer,text,date,date,integer) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.online_orders_list(p_loc integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$   -- bos76: was STABLE (now writes the view audit)
declare r jsonb;
begin
  if not public.is_active() or not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  r := coalesce((select jsonb_agg(to_jsonb(z) order by z.created_at desc) from (
    select o.id, o.order_no, o.location_id, o.channel, public._inb_pii_f99('name', o.customer_name) as customer_name,   -- bos99
           case when public._inb_contact_ok(o.location_id) then public._inb_pii_f99('mobile', o.customer_mobile) end as customer_mobile,   -- bos76 bos99
           o.delivery_mode, o.delivery_date, o.subtotal, o.discount, o.delivery_charge, o.advance,
           o.subtotal - o.discount + o.delivery_charge - o.advance as balance, o.status, o.sale_id, o.created_at,
           o.channel_id, o.is_draft, not public._inb_contact_ok(o.location_id) as masked, public._inb_pii_mode99() as pii_mode,   -- bos76 bos99
           (select count(*) from public.online_order_flags f where f.order_id = o.id and f.state = 'open') as flags_open   -- bos77
      from public.online_orders o
     where (p_loc is null or o.location_id = p_loc) and public.can_loc(o.location_id) and (p_status is null or o.status = p_status)
       and (p_from is null or o.created_at::date >= p_from) and (p_to is null or o.created_at::date <= p_to)
     order by o.created_at desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
  if exists (select 1 from jsonb_array_elements(r) e where (e->>'masked')::boolean is false) then   -- bos76
    perform public._inb_audit_view('online_orders', 'list', jsonb_build_object('count', jsonb_array_length(r), 'loc', p_loc, 'status', p_status));
  end if;
  return r;
end $function$
$f$; end if; end $p103$;

-- ---------- marker: phase103 pasted (tests read this) ----------
do $g$ begin
  if current_setting('phase103.ok', true) = 'on' then
    raise notice 'phase103 applied (bos103)';
  else
    raise notice 'phase103 NOT applied: a guard stopped it';
  end if;
end $g$;
