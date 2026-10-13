-- ===== phase52 =====
-- ============================================================
-- Phase 52 - P2 gap #6: journal auto-post SOURCES for payroll payments, staff advances and partner capital (+ owner-money count-once). Run AFTER phase51
-- (phase49 optional but its daybook_vs_journal is refreshed here). Idempotent (paste twice = no error). No existing row is changed or deleted.
--
--   NEW SOURCES in the accounting scanner _acct_docs (posted by acct_post_pending exactly like every other source: unique on (source_type, source_id), voided
--   source -> reversing entry via _acct_need, locked period skipped, accounting_on / accounting_start_date as before):
--     payroll_payment  payroll_payments (status done). Dr salary expense (5200) [+ advance recovery], Cr cash / bank / mobile by mode. A run that is a locked
--                      shadow of a 02-2 sheet (owner chose the sheet as the record) posts nothing. The advance recovery on the pay line (payroll_lines.advance_recovery)
--                      is split over the payments pro rata and credited to Staff advances (1220): gross cost = paid + recovered.
--     staff_advance    employee_advances with mode cash / bank / mobile. Dr Staff advances (1220), Cr cash / bank / mobile. Mode none (money not moved here) posts nothing.
--     partner_capital  contribution Dr cash / Cr owner capital; return_of_capital Dr owner capital / Cr cash; loan_in Dr cash / Cr Partner loans (2500);
--                      loan_repayment Dr Partner loans / Cr cash; owner_drawing Dr owner drawings / Cr cash. In-kind = no money moved: shown as "waiting: in_kind".
--   OWNER MONEY COUNT ONCE (phase51 link): while partner capital is the record, the linked cash move (owner_topup / owner_draw) is a locked shadow and neither posts
--   to the journal (a copy posted earlier is reversed) nor shows in the day book; the partner-capital record takes its place (same place, same day, once).
--   An unlinked cash move keeps posting as today. If the primary record is voided the shadow counts again (nothing is lost).
--   NEW KEYS in acct_mappings (the owner re-points them in the accounts screen): salary_exp -> 5200, staff_advance -> 1220, partner_loan -> 2500 (new account, seeded).
--   daybook_vs_journal: kinds normalised (payroll payment = salary, staff advance = advance, partner capital = owner_topup / owner_draw / loan_in ...); the paper-form
--   salary (02-2) / advance (02-3) lines stay day-book-only and are reported as their own kinds salary_form / advance_form; partner capital without a place as unplaced_*.
--   NOT done: 10-1 cash handover / 10-3 digital payment items (the hub side of a handover is not recorded -> a one-sided entry would be a guess; see the report).
-- ============================================================

-- ---------- 1. chart + mappings ----------
do $seed$
declare code_ text;
begin
  -- Partner loans (liability). Take 2500 unless the owner already used that code for something else.
  if not exists (select 1 from public.coa_accounts where code = '2500' and is_system and name_en = 'Partner / owner loans') then
    code_ := case when exists (select 1 from public.coa_accounts where code = '2500') then '2510' else '2500' end;
    insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, is_group, is_system, sort, parent_id)
      select code_, 'অংশীদার / মালিকের কাছ থেকে ঋণ', 'Partner / owner loans', 'liability', 'credit', false, true, 105, (select id from public.coa_accounts where code = '2000')
       where not exists (select 1 from public.coa_accounts where code = code_);
  end if;
end $seed$;

insert into public.acct_mappings (key, account_id, label_bn, label_en)
select v.k, a.id, v.lb, v.le from (values
  ('salary_exp', '5200', 'বেতন খরচ (পে-রোল পেমেন্ট)', 'Salary expense (payroll payments)'),
  ('staff_advance', '1220', 'স্টাফকে অগ্রিম (দেওয়া ও কাটা)', 'Staff advances (given and recovered)')
) as v(k, c, lb, le) join public.coa_accounts a on a.code = v.c
on conflict (key) do nothing;
insert into public.acct_mappings (key, account_id, label_bn, label_en)
select 'partner_loan', a.id, 'অংশীদার / মালিকের ঋণ', 'Partner / owner loans'
  from public.coa_accounts a where a.is_system and a.name_en = 'Partner / owner loans' order by a.code limit 1
on conflict (key) do nothing;

-- ---------- 2. count-once helper: is this record a locked shadow whose primary record is still live? ----------
--   cash_moves  shadow of a partner_capital that is still posted;  partner_capital shadow of a cash move that is still done. (A voided primary releases the shadow.)
create or replace function public._shadowed52(p_type text, p_id text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_shadow(p_type, p_id) and exists (
    select 1 from public.shadow_links x
     where x.shadow_type = p_type and x.shadow_id = p_id and x.state <> 'void'
       and case x.primary_type
             when 'partner_capital' then exists (select 1 from public.partner_capital c where c.id::text = x.primary_id and c.status = 'posted')
             when 'cash_moves' then exists (select 1 from public.cash_moves m where m.id::text = x.primary_id and m.status = 'done')
             else true end);
$$;
revoke all on function public._shadowed52(text, text) from public, anon, authenticated;

-- the source id of the CURRENT life of a record: a record that was reversed because it became a shadow (and is live again after its primary was voided) must be able to post
-- again, but journal_entries is unique on (source_type, source_id). Generation 0 = the plain id (all existing postings), generation n = id:gn.
create or replace function public._acct_sid52(p_type text, p_id text) returns text
language sql stable set search_path = public as $$
  select p_id || case when n = 0 then '' else ':g' || n::text end
    from (select count(*) n from public.journal_entries e where e.source_type = p_type and e.reverses_id is null and e.status = 'void'
                and (e.source_id = p_id or e.source_id like p_id || ':g%')) z;
$$;
revoke all on function public._acct_sid52(text, text) from public, anon, authenticated;

-- ---------- 3. _daybook_lines23 (latest definition, only bos52 lines differ) ----------
CREATE OR REPLACE FUNCTION public._daybook_lines23(p_locs integer[], p_from date, p_to date)
 RETURNS TABLE(loc integer, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamp with time zone, src text, src_id text, internal boolean, sensitive boolean)
 LANGUAGE sql
 STABLE
AS $function$
  select m.location_id, m.move_date, x.dir, x.mode, m.kind, m.amount, m.ref, nullif(btrim(concat_ws(' · ', c.name, m.note)), ''), m.created_staff, m.created_at,
         case when m.customer_id is not null then 'customer' else 'cash_move' end, coalesce(m.customer_id::text, m.id::text), (m.kind = 'hub_receipt'), false
    from public.cash_moves m
    left join public.customers c on c.id = m.customer_id
    cross join lateral (values (1)) one
    cross join lateral (
      select * from (values
        ('bank_deposit', 'out', 'cash'), ('bank_deposit', 'in', 'bank'), ('bank_withdraw', 'out', 'bank'), ('bank_withdraw', 'in', 'cash'),
        ('owner_topup', 'in', m.mode), ('owner_draw', 'out', m.mode), ('cust_advance', 'in', m.mode), ('cust_advance_refund', 'out', m.mode), ('hub_receipt', 'in', 'cash')
      ) v(k, dir, mode) where v.k = m.kind) x
   where m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */ and m.location_id = any (p_locs) and m.move_date between p_from and p_to
  union all
  -- phase42: salary paid from a payroll run (salary-sensitive: only with salary_view at that place)
  select p.location_id, p.pay_date, 'out', p.mode, 'salary', p.amount, 'PR-' || p.run_id::text, nullif(btrim(concat_ws(' · ', e.employee_no, e.full_name_bn, p.note)), ''), pr.staff_id, p.created_at,
         'payroll', p.id::text, false, true
    from public.payroll_payments p
    join public.employees e on e.id = p.employee_id
    left join public.profiles pr on pr.id = p.created_by
   where p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text) /* bos50 */ and p.location_id = any (p_locs) and p.pay_date between p_from and p_to and (public.is_owner() or public.has_grant('salary_view', p.location_id))
  union all
  -- phase42: staff advance paid out in cash / bank / mobile from the advance register (mode none = already in a 02-3 form, not counted again)
  select a.location_id, a.adv_date, 'out', a.mode, 'advance', a.amount, 'ADV-' || a.id::text, nullif(btrim(concat_ws(' · ', e.employee_no, e.full_name_bn, a.note)), ''), pr.staff_id, a.created_at,
         'staff_advance', a.id::text, false, true
    from public.employee_advances a
    join public.employees e on e.id = a.employee_id
    left join public.profiles pr on pr.id = a.created_by
   where a.status = 'active' and a.mode in ('cash', 'bank', 'mobile') and a.location_id = any (p_locs) and a.adv_date between p_from and p_to
     and (public.is_owner() or public.has_grant('salary_view', a.location_id))
  union all
  -- bos50: a quick expense typed in the day-book tab (its 10-2 copy is a locked shadow and is not counted again)
  select q.location_id, q.exp_date, 'out', q.mode, 'expense', q.amount, 'Q-' || left(q.id::text, 8), nullif(btrim(concat_ws(' · ', q.paid_to, q.head, q.note)), ''), q.created_staff, q.created_at,
         'quick_expense', q.id::text, false, false
    from public.quick_expenses q
   where q.status = 'done' and q.location_id = any (p_locs) and q.exp_date between p_from and p_to
  union all
  -- bos52: partner capital that is the record of a linked owner top-up / draw (the cash move is then a locked shadow and is not counted above); same place, same day, once
  select lk.location_id, c.cap_date, case c.kind when 'contribution' then 'in' else 'out' end, c.mode, case c.kind when 'contribution' then 'owner_topup' else 'owner_draw' end,
         c.amount, c.ref, nullif(btrim(concat_ws(' · ', 'partner capital', c.description)), ''), pr.staff_id, c.created_at, 'partner_capital', c.id::text, false, false
    from public.partner_capital c
    join lateral (select x.location_id from public.shadow_links x where x.primary_type = 'partner_capital' and x.primary_id = c.id::text and x.shadow_type = 'cash_moves'
                   and x.shadow_id is not null and x.state <> 'void' order by x.id limit 1) lk on true
    left join public.profiles pr on pr.id = c.created_by
   where c.status = 'posted' and c.kind in ('contribution', 'owner_drawing') and c.mode in ('cash', 'bank', 'mobile') and lk.location_id > 0
     and lk.location_id = any (p_locs) and c.cap_date between p_from and p_to;
$function$;

-- ---------- 4. _acct_docs (latest definition = phase50, bos50 blocks kept, only bos52 lines/blocks differ) ----------
CREATE OR REPLACE FUNCTION public._acct_docs(p_start date)
 RETURNS TABLE(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- sales (payments split, discount, revenue, COGS only from real unit costs)
  return query
  select 'sale'::text, s.id::text, s.sale_date, s.location_id, ('Receipt ' || s.receipt)::text, null::text, s.status = 'done', (s.void_at at time zone 'Asia/Dhaka')::date,
    case when s.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out'
                   and l.item_id = (e->>'item_id')::uuid and l.unit_cost is not null)) then 'cogs_missing' end,
    null::text,
    case when s.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'pay_' || p.mode, 'd', sum(p.amount)) j from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided group by p.mode
        union all select 2, jsonb_build_object('a', 'receivable', 'd', round(s.total - pp.paid, 2), 'pt', case when s.customer_id is not null then 'customer' end, 'pid', s.customer_id::text) where s.total - pp.paid > 0.004
        union all select 3, jsonb_build_object('a', 'sales_discount', 'd', s.discount) where s.discount > 0
        union all select 4, jsonb_build_object('a', 'sales', 'c', s.subtotal)
        union all select 5, jsonb_build_object('a', 'cogs', 'd', cg.amt) from (select round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_id = s.id::text and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') and l.unit_cost is not null) cg where cg.amt > 0
        union all select 6, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt) from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id where l.ref_id = s.id::text and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') and l.unit_cost is not null group by it.item_type) z where z.amt > 0
      ) x) end
  from public.sales s cross join lateral (select coalesce(sum(p.amount), 0) paid from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided) pp
  where s.sale_date >= p_start and s.subtotal > 0 and public._acct_need('sale', s.id::text, s.status = 'done');

  -- sale returns
  return query
  select 'sale_return'::text, r.id::text, (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, ('Return of receipt ' || coalesce(s.receipt::text, '-'))::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when r.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return'
                   and l.item_id = (e->>'item_id')::uuid and l.unit_cost is not null)) then 'cogs_missing' end,
    null::text,
    case when r.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'sales_returns', 'd', r.amount) j
        union all select 2, jsonb_build_object('a', 'receivable', 'c', r.credit_amount, 'pt', case when r.customer_id is not null then 'customer' end, 'pid', r.customer_id::text) where r.credit_amount > 0
        union all select 3, jsonb_build_object('a', public._acct_paykey(coalesce(r.refund_mode, 'cash')), 'c', r.refund_amount) where r.refund_amount > 0
        union all select 4, jsonb_build_object('a', public._acct_inv_key(z.t), 'd', z.amt) from (select it.item_type t, round(sum(l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
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
        union all select 2, jsonb_build_object('a', 'pay_cash', 'c', v.total)
      ) y) end
  from public.entries e cross join lateral (
    select coalesce(sum(public._acct_num(x->>'amount')) filter (where public._acct_num(x->>'amount') > 0), 0) total,
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
          from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id
                where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
      ) y) end
  from public.stock_wastage w cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where l.unit_cost is null) nulls
    from public.stock_ledger l where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c
  where (w.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('wastage', w.id::text, true);

  -- production: ingredients (at their real cost) move from raw / packaging to finished goods
  return query
  select 'production'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, 'Production run'::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when r.status = 'done' and (c.amt is null or c.amt <= 0) then 'cost_missing' end,
    case when r.status = 'done' and c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', c.amt) j
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id
                where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
      ) y) end
  from public.production_runs r cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where l.unit_cost is null) nulls
    from public.stock_ledger l where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') c
  where (r.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('production', r.id::text, r.status = 'done');

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
end $function$;

-- ---------- 5. daybook_vs_journal: kind normalisation for the new sources (only bos52 lines differ from phase49) ----------
CREATE OR REPLACE FUNCTION public.daybook_vs_journal(p_from date, p_to date, p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); d1 date; locs int[]; rows jsonb; tot jsonb; own boolean := public.is_owner();
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'bad_range'; end if;
  if st is null then return jsonb_build_object('data_needed', true, 'why', 'accounting_start_date'); end if;
  d1 := greatest(p_from, st);
  select array_agg(l.id) into locs from public.locations l where (p_loc is null or l.id = p_loc) and (own or public.can_loc(l.id));
  if locs is null then raise exception 'not allowed'; end if;
  with db as (  -- the day book, internal hub lines kept apart, signed per mode (card settles to bank in the day book)
    select case when u.typ in ('bill', 'supplier') then 'supplier_payment' when u.src = 'entry' and u.typ in ('salary', 'advance') then u.typ || '_form' /* bos52 */ else u.typ end as k, u.mode, u.internal, case when u.dir = 'in' then u.amount else -u.amount end as s
      from (select * from public._daybook_lines(locs, locs, d1, p_to) union all select * from public._daybook_lines12(locs, d1, p_to) union all select * from public._daybook_lines23(locs, d1, p_to)) u
  ), jr as (    -- the journal: movement on the cash / bank / mobile accounts, by kind (cash_move keeps its own kind)
    select case je.source_type when 'cash_move' then coalesce(je.subtype, 'cash_move') when 'expense_voucher' then 'expense' when 'quick_expense' then 'expense'
             when 'payroll_payment' then 'salary' when 'staff_advance' then 'advance' /* bos52 */
             when 'partner_capital' then case when coalesce(je.location_id, nullif(lk.loc, 0)) is null then 'unplaced_' || je.subtype else case je.subtype when 'contribution' then 'owner_topup' when 'owner_drawing' then 'owner_draw' else je.subtype end end /* bos52 */
             else je.source_type end as k,
           case when a.key = 'pay_cash' then 'cash' when a.key = 'pay_mobile' then 'mobile' else 'bank' end as mode, (jl.debit - jl.credit) as s
      from public.journal_entries je
      join public.journal_lines jl on jl.entry_id = je.id
      left join lateral (select x.location_id as loc from public.shadow_links x where je.source_type = 'partner_capital' and x.primary_type = 'partner_capital' and x.primary_id = split_part(je.source_id, ':', 1)
                          and x.shadow_type = 'cash_moves' and x.shadow_id is not null and x.state <> 'void' order by x.id limit 1) lk on true /* bos52: a link made after posting still gives the place */
      join public.acct_mappings a on a.account_id = jl.account_id and a.key in ('pay_cash', 'pay_bank', 'pay_card', 'pay_mobile')
     where je.entry_date between d1 and p_to and je.source_type <> 'opening' and (coalesce(je.location_id, nullif(lk.loc, 0)) is null or coalesce(je.location_id, nullif(lk.loc, 0)) = any (locs))
  ), kk as (
    select k, mode, sum(s) filter (where not internal) as dbs, sum(s) filter (where internal) as dbi, 0::numeric as js from db group by k, mode
    union all select k, mode, null, null, sum(s) from jr group by k, mode
  ), agg as (
    select k, mode, coalesce(sum(dbs), 0) as daybook, coalesce(sum(dbi), 0) as hub_internal, coalesce(sum(js), 0) as journal from kk group by k, mode
  )
  select coalesce(jsonb_agg(jsonb_build_object('kind', k, 'mode', mode, 'daybook', daybook, 'journal', journal, 'diff', daybook - journal, 'hub_internal', hub_internal) order by k, mode)
           filter (where abs(daybook - journal) > 0.004 or hub_internal <> 0), '[]'::jsonb),
         jsonb_build_object('daybook', coalesce(sum(daybook), 0), 'journal', coalesce(sum(journal), 0), 'diff', coalesce(sum(daybook - journal), 0),
           'kinds_checked', count(*), 'kinds_differing', count(*) filter (where abs(daybook - journal) > 0.004))
    into rows, tot from agg;
  return jsonb_build_object('from', d1, 'to', p_to, 'location_id', p_loc, 'accounting_start', st, 'rows', rows, 'total', tot,
    'note', 'Day book counts a 10-2 voucher when submitted, the journal only when approved. Payroll payments (salary), staff advances (advance) and partner capital are posted from phase52; paper-form salary / advance lines (salary_form, advance_form) are day-book only; partner capital without a place shows as unplaced_*. Reversals post on the day they are made.');
end $function$;

notify pgrst, 'reload schema';

-- ===== phase53 =====
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
  unmatched_by uuid, unmatched_at timestamptz, unmatch_note text      -- (entry_id, line_no) is checked in _a53_match1; no FK so phase40's truncate guard on journal_lines stays the one that answers
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

-- ===== phase54 =====
-- ============================================================
-- Phase 54 - P2c: attendance, two paths counted once (gap #29) + form equation recompute (gap #20, safe core).
-- Run AFTER phase51 (needs phase42 attendance + phase48-50 path engine). Idempotent (paste twice = no error). No existing row is changed or deleted.
--
--   ATTENDANCE  path A = staff attendance (device / finger file / app punch / manager entry -> attendance_punches + attendance_days),
--               path B = the monthly paper register, form 02-1.   Same place + month = same event.
--               Owner default: path A is the record; an 02-1 that is submitted/approved for a month that path A already holds becomes a LOCKED SHADOW
--               copy (kept, shown, never counted again). Owner may switch primary to the form, or lock either path (Switch board, domain 'attendance').
--               Form 14-1 (daily showroom sheet) is NOT mapped to this domain: it is the cash drawer sheet, locking it would stop the drawer count.
--   (a) SELF PUNCH  staff punch from the phone (attendance_self_punch). Master switch = existing rule app_punch_on (OFF). Owner can lock one person
--               or one role (att_self_lock). A lock never deletes anything; it only refuses NEW self punches.
--   (b) EVIDENCE    fingerprint / face / browser-passkey registration is EVIDENCE ONLY: a flag + a reference (photo path, passkey id, device user id).
--               No biometric template is stored. The server cannot verify a passkey assertion or a face, so nothing here proves identity.
--               GPS is a SOFT flag (rule att_geo_check_on, OFF): a punch outside the radius is recorded and flagged, never refused.
--   (c) MARK OTHERS new grant attendance_mark_others (no role has it by default; the owner gives it to a person). Lets a manager mark another person's
--               day status, rest time and closing time by hand with a source tag device/finger/face/manual. Every call is written to an append-only log.
--               The tag is the manager's declaration, not a proof. Cannot mark himself. A month locked by approved/paid payroll is refused (month_locked).
--   EQUATIONS   entry_equation_check(entry) re-works the key totals of 10-2 and 02-2 on the server and lists differences against the flags the phone
--               stored. Rule entry_equation_flag_on (OFF): when ON, a submitted 10-2 / 02-2 that differs gets one red exception 'equation_mismatch'.
--   Re-created from the latest definition: attendance_app_punch (now a thin wrapper of attendance_self_punch; same errors, same 1-minute rule).
-- ============================================================

-- ---------- 1. the shadow engine: new domain ----------
insert into public.path_domains (domain, a_bn, a_en, b_bn, b_en, default_primary, note_bn, note_en, sort) values
 ('attendance', 'কর্মী হাজিরা (মেশিন / অ্যাপ পাঞ্চ)', 'Staff attendance (device / app punch)', 'ফর্ম 02-1 (মাসিক হাজিরা রেজিস্টার)', 'Form 02-1 (monthly attendance register)', 'a',
  'ডিফল্ট: পাঞ্চ/হাজিরা রেকর্ড মূল; সেই মাসের 02-1 লক করা শ্যাডো কপি। শুধু মাস-পর্যায়ের মিল; কাউকে শনাক্তের প্রমাণ নয়।',
  'Default: punch / attendance record is primary; the 02-1 of a month that path A holds is a locked shadow. Month-level match only; not proof of anybody''s identity.', 60)
on conflict (domain) do nothing;

-- ---------- 2. columns ----------
alter table public.attendance_days add column if not exists rest_minutes int check (rest_minutes is null or rest_minutes between 0 and 720);
alter table public.attendance_days add column if not exists mark_source text check (mark_source is null or mark_source in ('device', 'finger', 'face', 'manual'));
alter table public.attendance_punches add column if not exists evidence_kind text check (evidence_kind is null or evidence_kind in ('webauthn', 'face_photo'));
alter table public.attendance_punches add column if not exists evidence_ref text check (evidence_ref is null or char_length(evidence_ref) <= 300);
alter table public.attendance_punches add column if not exists evidence_state text check (evidence_state is null or evidence_state in ('registered', 'unregistered', 'none'));
alter table public.attendance_punches add column if not exists geo_lat numeric check (geo_lat is null or geo_lat between -90 and 90);
alter table public.attendance_punches add column if not exists geo_lng numeric check (geo_lng is null or geo_lng between -180 and 180);
alter table public.attendance_punches add column if not exists geo_flag text check (geo_flag is null or geo_flag in ('ok', 'outside', 'no_fix', 'unchecked'));

-- ---------- 3. tables ----------
create table if not exists public.att_self_lock (               -- owner's lock: this person / role may NOT self-punch
  scope text not null check (scope in ('person', 'role')),
  ref text not null check (char_length(ref) between 1 and 60),   -- employee id (uuid text) or role code
  locked boolean not null default true,
  note text check (note is null or char_length(note) <= 300),
  set_by uuid, set_at timestamptz not null default now(),
  primary key (scope, ref)
);
create table if not exists public.att_site_geo (                -- optional place coordinates for the soft GPS flag
  location_id int primary key references public.locations(id),
  lat numeric not null check (lat between -90 and 90), lng numeric not null check (lng between -180 and 180),
  set_by uuid, set_at timestamptz not null default now()
);
create table if not exists public.att_evidence_reg (            -- registration FLAG + reference. Never a biometric template. Evidence only.
  id bigserial primary key,
  employee_id uuid not null references public.employees(id),
  kind text not null check (kind in ('webauthn', 'face_photo', 'finger_device')),
  ref text not null check (char_length(ref) between 1 and 300),
  label text check (label is null or char_length(label) <= 80),
  active boolean not null default true,
  registered_by uuid, registered_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_reason text check (void_reason is null or char_length(void_reason) <= 300)
);
create unique index if not exists att_evidence_reg_uq on public.att_evidence_reg (employee_id, kind, ref) where active;
create table if not exists public.att_mark_log54 (              -- append-only audit of every "mark others" call
  id bigserial primary key, client_id uuid unique,
  employee_id uuid not null references public.employees(id), location_id int, day date not null,
  source_tag text not null check (source_tag in ('device', 'finger', 'face', 'manual')),
  status text not null, first_in timestamptz, last_out timestamptz, rest_minutes int, ot_minutes int,
  reason text not null, note text, prev jsonb, approved boolean not null default false,
  marked_by uuid, marked_staff text, marked_at timestamptz not null default now()
);
create or replace function public._att_log_ro54() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end $$;
drop trigger if exists att_mark_log54_ro on public.att_mark_log54;
create trigger att_mark_log54_ro before update or delete on public.att_mark_log54 for each row execute function public._att_log_ro54();

drop trigger if exists audit_att_self_lock on public.att_self_lock;
create trigger audit_att_self_lock after insert or update on public.att_self_lock for each row execute function public.log_change('scope,ref');
drop trigger if exists audit_att_site_geo on public.att_site_geo;
create trigger audit_att_site_geo after insert or update on public.att_site_geo for each row execute function public.log_change('location_id');
drop trigger if exists audit_att_evidence_reg on public.att_evidence_reg;
create trigger audit_att_evidence_reg after insert or update on public.att_evidence_reg for each row execute function public.log_change('id');

alter table public.att_self_lock enable row level security;
alter table public.att_site_geo enable row level security;
alter table public.att_evidence_reg enable row level security;
alter table public.att_mark_log54 enable row level security;
revoke all on public.att_self_lock, public.att_site_geo, public.att_evidence_reg, public.att_mark_log54 from public, anon, authenticated;
revoke all on sequence public.att_evidence_reg_id_seq, public.att_mark_log54_id_seq from public, anon, authenticated;
grant select on public.att_self_lock, public.att_site_geo, public.att_evidence_reg, public.att_mark_log54 to authenticated;
drop policy if exists att_self_lock_read on public.att_self_lock;
create policy att_self_lock_read on public.att_self_lock for select to authenticated using (public.is_owner());
drop policy if exists att_site_geo_read on public.att_site_geo;
create policy att_site_geo_read on public.att_site_geo for select to authenticated using (public.is_active());
drop policy if exists att_evidence_reg_read on public.att_evidence_reg;
create policy att_evidence_reg_read on public.att_evidence_reg for select to authenticated using (public._att_view(employee_id));
drop policy if exists att_mark_log54_read on public.att_mark_log54;
create policy att_mark_log54_read on public.att_mark_log54 for select to authenticated using (public.is_owner()
  or (location_id is not null and public.can_loc(location_id) and (public.has_grant('attendance_mark_others', location_id) or public.has_grant('attendance_manage', location_id))));

-- ---------- 4. rules and grant ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('att_geo_check_on', 'people', 'switch', 'false', null, null, null, null, 'স্ব-পাঞ্চে জিপিএস দূরত্বের নরম পতাকা', 'Self punch এ GPS দূরত্বের soft flag', 'Soft GPS flag on self punches',
  'চালু থাকলে অফিস/শোরুমের স্থানাঙ্ক থেকে দূরে পাঞ্চ হলে পতাকা পড়বে; পাঞ্চ বাতিল হবে না। জিপিএস সহজে ভুল/নকল হয়।', 'When ON, a punch far from the place coordinates is flagged, never refused. GPS can be wrong or faked.', 190),
 ('att_geo_radius_m', 'people', 'number', '300', 'm', null, 20, 20000, 'জিপিএস সীমা (মিটার)', 'GPS radius (meter)', 'GPS radius (metres)', null, null, 191),
 ('entry_equation_flag_on', 'entries', 'switch', 'false', null, null, null, null, 'জমা দেওয়ার সময় সার্ভারে হিসাব মিলিয়ে লাল ব্যতিক্রম', 'Submit এ server হিসাব মিলিয়ে red exception', 'Server re-check of 10-2 / 02-2 totals at submit (red exception)',
  'চালু থাকলে ফোনের হিসাব আর সার্ভারের পুনঃহিসাব না মিললে একটি লাল ব্যতিক্রম পড়বে; জমা আটকায় না।', 'When ON, a submitted 10-2 / 02-2 whose stored flags differ from the server re-work gets one red exception; the submit is not blocked.', 320)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select v.c, 'people', v.s, v.bn, v.mx, v.en, 'window', null
from (values
 ('attendance_mark_others', 76, 'অন্যের দৈনিক হাজিরা, বিরতি ও বন্ধের সময় হাতে লেখা (সোর্স ট্যাগসহ)', 'অন্যের daily attendance, rest ও closing time হাতে লেখা (source tag সহ)', 'Mark other people''s daily attendance, rest and closing time by hand (with a source tag)')
) as v(c, s, bn, mx, en)
where not exists (select 1 from public.grant_defs g where g.grant_code = v.c);

-- ---------- 5. helpers ----------
create or replace function public._att_geo_m54(lat1 numeric, lng1 numeric, lat2 numeric, lng2 numeric) returns numeric
language sql immutable as $$
  select (2 * 6371000 * asin(least(1, sqrt(power(sin(radians(lat2 - lat1) / 2), 2) + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)))))::numeric;
$$;

-- may this login punch itself right now? (shared by status + punch)
create or replace function public._att_self_state54(p_emp public.employees) returns text
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.rule_on('attendance_on') then return 'attendance_off'; end if;
  if not public.rule_on('app_punch_on') then return 'app_punch_off'; end if;
  if exists (select 1 from public.att_self_lock where scope = 'person' and ref = p_emp.id::text and locked) then return 'self_punch_locked'; end if;
  if exists (select 1 from public.att_self_lock l where l.scope = 'role' and l.locked
              and (l.ref = p_emp.primary_role_code or l.ref in (select ur.role_code from public.user_roles ur where ur.user_id = p_emp.profile_id))) then return 'self_punch_locked'; end if;
  if not public.path_allowed('attendance', coalesce(p_emp.primary_location_id, 0), 'a') then return 'path_locked'; end if;
  return 'ok';
end $$;

-- ---------- 6. SELF PUNCH (a) + EVIDENCE flags (b) ----------
create or replace function public.attendance_self_punch(p_dir text default 'unknown', p_lat numeric default null, p_lng numeric default null, p_acc numeric default null,
                                                         p_ev_kind text default null, p_ev_ref text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; v_id bigint; st text; dir text := case when p_dir in ('in', 'out') then p_dir else 'unknown' end; g public.att_site_geo; gf text := 'unchecked'; dist numeric;
        evs text := 'none'; evk text := null; evr text := null; rad numeric := coalesce(public.rule_num('att_geo_radius_m'), 300);
begin
  perform public._att_gate();
  if not public.rule_on('app_punch_on') then raise exception 'app_punch_off'; end if;
  select * into e from public.employees where profile_id = auth.uid() and status in ('active', 'on_leave');
  if not found then raise exception 'no_employee_record'; end if;
  st := public._att_self_state54(e);
  if st = 'self_punch_locked' then raise exception 'self_punch_locked: the owner has locked self punch for you or your role'; end if;
  if st = 'path_locked' then raise exception 'path_locked: attendance path A is locked here by the owner'; end if;
  if (p_lat is null) <> (p_lng is null) or abs(coalesce(p_lat, 0)) > 90 or abs(coalesce(p_lng, 0)) > 180 or abs(coalesce(p_acc, 0)) > 1e7 then raise exception 'bad_geo'; end if;
  if p_ev_kind is not null and p_ev_kind not in ('webauthn', 'face_photo') then raise exception 'bad_evidence'; end if;
  if p_ev_kind is not null and (nullif(btrim(p_ev_ref), '') is null or char_length(p_ev_ref) > 300) then raise exception 'bad_evidence'; end if;
  if exists (select 1 from public.attendance_punches where employee_id = e.id and source = 'app' and punched_at > now() - interval '1 minute' and not void) then raise exception 'too_soon'; end if;
  if p_ev_kind is not null then
    evk := p_ev_kind; evr := btrim(p_ev_ref);
    evs := case when exists (select 1 from public.att_evidence_reg r where r.employee_id = e.id and r.kind = p_ev_kind and r.ref = evr and r.active) then 'registered' else 'unregistered' end;
  end if;
  if public.rule_on('att_geo_check_on') then
    select * into g from public.att_site_geo where location_id = e.primary_location_id;
    if p_lat is null then gf := 'no_fix';
    elsif not found then gf := 'unchecked';
    else dist := public._att_geo_m54(p_lat, p_lng, g.lat, g.lng); gf := case when dist > rad then 'outside' else 'ok' end; end if;
  end if;
  insert into public.attendance_punches (employee_id, device_id, location_id, device_user_id, punched_at, direction, source, created_by, evidence_kind, evidence_ref, evidence_state, geo_lat, geo_lng, geo_flag, raw)
    values (e.id, null, e.primary_location_id, 'app:' || e.id::text, date_trunc('second', now()), dir, 'app', auth.uid(), evk, evr, evs, p_lat, p_lng, gf,
            case when p_acc is null then null else jsonb_build_object('geo_accuracy_m', p_acc) end) returning id into v_id;
  perform public._att_store(e.id, public._dhaka_today());
  if (now() at time zone 'Asia/Dhaka')::time < time '06:00' then perform public._att_store(e.id, public._dhaka_today() - 1); end if;
  return jsonb_build_object('id', v_id, 'at', now(), 'direction', dir, 'evidence_state', evs, 'geo_flag', gf, 'geo_distance_m', case when dist is null then null else round(dist) end,
    'note', 'evidence_only_not_identity_proof');
end $$;

-- bos54: the old one-argument entry point keeps its name, errors and 1-minute rule; it now goes through the same locks.
create or replace function public.attendance_app_punch(p_dir text default 'unknown') returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  return public.attendance_self_punch(p_dir);   -- bos54
end $$;

-- what the logged-in person may do now (for the screen)
create or replace function public.att_my_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.employees; st text; ev jsonb; last_p jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into e from public.employees where profile_id = auth.uid() and status in ('active', 'on_leave');
  if not found then return jsonb_build_object('employee', false, 'can_punch', false, 'state', 'no_employee_record'); end if;
  st := public._att_self_state54(e);
  select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'label', r.label, 'registered_at', r.registered_at) order by r.id), '[]') into ev
    from public.att_evidence_reg r where r.employee_id = e.id and r.active;
  select to_jsonb(x) into last_p from (select punched_at, direction, evidence_state, geo_flag from public.attendance_punches
                                        where employee_id = e.id and source = 'app' and not void order by punched_at desc limit 1) x;
  return jsonb_build_object('employee', true, 'employee_id', e.id, 'name_bn', e.full_name_bn, 'name_en', e.full_name_en, 'can_punch', st = 'ok', 'state', st, 'evidence', ev, 'last_punch', last_p,
    'geo_check_on', public.rule_on('att_geo_check_on'));
end $$;

-- owner: lock / unlock self punch for one person or one role
create or replace function public.att_self_lock_set(p_scope text, p_ref text, p_locked boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() or not public.is_owner() then raise exception 'not allowed'; end if;
  if p_scope not in ('person', 'role') then raise exception 'bad_scope'; end if;
  if nullif(btrim(p_ref), '') is null or char_length(p_ref) > 60 then raise exception 'bad_ref'; end if;
  if char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long: note'; end if;
  if p_scope = 'person' and not exists (select 1 from public.employees where id::text = btrim(p_ref)) then raise exception 'not_found'; end if;
  if p_scope = 'role' and not exists (select 1 from public.roles where code = btrim(p_ref)) and not exists (select 1 from public.staff_roles where code = btrim(p_ref)) then raise exception 'not_found'; end if;
  insert into public.att_self_lock (scope, ref, locked, note, set_by, set_at) values (p_scope, btrim(p_ref), coalesce(p_locked, true), nullif(btrim(p_note), ''), auth.uid(), now())
    on conflict (scope, ref) do update set locked = excluded.locked, note = excluded.note, set_by = excluded.set_by, set_at = now();
  return jsonb_build_object('scope', p_scope, 'ref', btrim(p_ref), 'locked', coalesce(p_locked, true));
end $$;

create or replace function public.att_site_geo_set(p_loc int, p_lat numeric, p_lng numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() or not public.is_owner() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'not_found'; end if;
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then raise exception 'bad_geo'; end if;
  insert into public.att_site_geo (location_id, lat, lng, set_by, set_at) values (p_loc, p_lat, p_lng, auth.uid(), now())
    on conflict (location_id) do update set lat = excluded.lat, lng = excluded.lng, set_by = excluded.set_by, set_at = now();
  return jsonb_build_object('location_id', p_loc, 'lat', p_lat, 'lng', p_lng);
end $$;

-- owner / attendance manager: people at a place with their lock + evidence status
create or replace function public.att_staff_overview(p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows_ jsonb; roles_ jsonb;
begin
  if not public._att_loc_view(p_loc) then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('employee_id', x.id, 'employee_no', x.employee_no, 'name_bn', x.full_name_bn, 'name_en', x.full_name_en, 'role', x.primary_role_code,
      'has_login', x.profile_id is not null,
      'person_locked', exists (select 1 from public.att_self_lock l where l.scope = 'person' and l.ref = x.id::text and l.locked) and public.is_owner(),
      'evidence', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'label', r.label)) from public.att_evidence_reg r where r.employee_id = x.id and r.active), '[]'::jsonb))
      order by x.employee_no nulls last, x.full_name_bn), '[]') into rows_
    from public.employees x where x.primary_location_id = p_loc and x.status in ('active', 'on_leave');
  select coalesce(jsonb_agg(jsonb_build_object('role', l.ref, 'locked', l.locked)), '[]') into roles_ from public.att_self_lock l where l.scope = 'role' and public.is_owner();
  return jsonb_build_object('location_id', p_loc, 'rows', rows_, 'role_locks', roles_, 'self_punch_master', public.rule_on('app_punch_on'),
    'limits', 'evidence_only: registration is a flag + reference, not proof of identity; fingerprint only through the external device bridge; GPS is a soft flag');
end $$;

-- evidence registration: the person himself (passkey / face photo) or owner / attendance manager (any kind incl. finger_device)
create or replace function public.att_evidence_register(p_emp uuid, p_kind text, p_ref text, p_label text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; own boolean; v bigint;
begin
  perform public._att_gate();
  select * into e from public.employees where id = p_emp;
  if not found or e.status in ('draft', 'discarded') then raise exception 'not_found'; end if;
  if p_kind is null or p_kind not in ('webauthn', 'face_photo', 'finger_device') then raise exception 'bad_kind'; end if;
  own := e.profile_id is not null and e.profile_id = auth.uid();
  if not (public._emp_ok(p_emp, array['attendance_manage']) or (own and p_kind in ('webauthn', 'face_photo'))) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_ref), '') is null or char_length(p_ref) > 300 then raise exception 'bad_ref'; end if;
  if char_length(coalesce(p_label, '')) > 80 then raise exception 'too_long: label'; end if;
  if (select count(*) from public.att_evidence_reg where employee_id = p_emp and active) >= 10 then raise exception 'too_many'; end if;
  insert into public.att_evidence_reg (employee_id, kind, ref, label, registered_by) values (p_emp, p_kind, btrim(p_ref), nullif(btrim(p_label), ''), auth.uid())
    on conflict (employee_id, kind, ref) where active do nothing returning id into v;
  if v is null then select id into v from public.att_evidence_reg where employee_id = p_emp and kind = p_kind and ref = btrim(p_ref) and active; return jsonb_build_object('id', v, 'repeat', true); end if;
  return jsonb_build_object('id', v, 'kind', p_kind, 'note', 'evidence_only_not_identity_proof');
end $$;

create or replace function public.att_evidence_void(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.att_evidence_reg; e public.employees;
begin
  perform public._att_gate();
  select * into r from public.att_evidence_reg where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  select * into e from public.employees where id = r.employee_id;
  if not (public._emp_ok(r.employee_id, array['attendance_manage']) or (e.profile_id is not null and e.profile_id = auth.uid() and r.kind in ('webauthn', 'face_photo'))) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_reason), '') is null or char_length(p_reason) > 300 then raise exception 'reason_required'; end if;
  if not r.active then return jsonb_build_object('id', p_id, 'repeat', true); end if;
  update public.att_evidence_reg set active = false, void_by = auth.uid(), void_at = now(), void_reason = btrim(p_reason) where id = p_id;
  return jsonb_build_object('id', p_id, 'active', false);
end $$;

-- ---------- 7. MARK OTHERS (c) ----------
-- rest / source columns follow the row: anything that is not this function resets them (a plain attendance_mark, a recompute)
create or replace function public._att_days_guard54() returns trigger language plpgsql set search_path = public as $$
begin
  if coalesce(current_setting('bos.mark54', true), '') <> '1' then
    new.rest_minutes := null;
    new.mark_source := case when new.source = 'manual' then 'manual' end;
  end if;
  return new;
end $$;
drop trigger if exists attendance_days_guard54 on public.attendance_days;
create trigger attendance_days_guard54 before insert or update on public.attendance_days for each row execute function public._att_days_guard54();

create or replace function public.attendance_mark_others(p_emp uuid, p_day date, p_status text, p_in text, p_out text, p_rest_min int, p_source text, p_reason text,
                                                         p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; s public.shifts; v_today date := public._dhaka_today(); t1 time := public._hhmm(p_in); t2 time := public._hhmm(p_out); ti timestamptz; tout timestamptz;
        worked int := 0; late int := 0; early int := 0; ot int := 0; ss timestamptz; se timestamptz; v_kind text := 'normal'; hol public.holidays; v_appr boolean; rest int; prev jsonb; old public.attendance_days;
        lg public.att_mark_log54; sid text;
begin
  perform public._att_gate();
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into lg from public.att_mark_log54 where client_id = p_client;
    if found then
      if lg.marked_by is distinct from auth.uid() then raise exception 'client_id_in_use'; end if;
      return jsonb_build_object('employee_id', lg.employee_id, 'day', lg.day, 'status', lg.status, 'source_tag', lg.source_tag, 'duplicate', true);
    end if;
  end if;
  select * into e from public.employees where id = p_emp;
  if not found or e.status in ('draft', 'discarded') then raise exception 'not_found'; end if;
  if not (public.is_owner() or (e.primary_location_id is not null and public.can_loc(e.primary_location_id) and public.has_grant('attendance_mark_others', e.primary_location_id))) then raise exception 'not allowed'; end if;
  if e.profile_id is not null and e.profile_id = auth.uid() and not public.is_owner() then raise exception 'cannot_mark_self'; end if;
  perform public.path_guard('attendance', coalesce(e.primary_location_id, 0), 'a');
  if p_day is null or p_day > v_today or p_day < v_today - 62 then raise exception 'bad_date'; end if;
  if e.joining_date is not null and p_day < e.joining_date then raise exception 'bad_date'; end if;
  if p_status not in ('present', 'late', 'half_day', 'absent', 'off', 'holiday', 'unpaid') then raise exception 'bad_status'; end if;
  if p_source is null or p_source not in ('device', 'finger', 'face', 'manual') then raise exception 'bad_source'; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 or char_length(p_reason) > 300 then raise exception 'reason_required'; end if;
  if char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long: note'; end if;
  if p_rest_min is not null and (p_rest_min < 0 or p_rest_min > 720) then raise exception 'bad_rest'; end if;
  if (p_in is not null and btrim(p_in) <> '' and t1 is null) or (p_out is not null and btrim(p_out) <> '' and t2 is null) then raise exception 'bad_time'; end if;
  if public._att_locked(p_emp, p_day) then raise exception 'month_locked'; end if;
  if p_status = 'absent' then t1 := null; t2 := null; end if;
  s := public._att_shift_for(e.id, e.primary_location_id, p_day);
  hol := public._att_holiday(e.primary_location_id, p_day);
  if hol.id is not null then v_kind := 'holiday'; elsif public._att_is_off(e.id, p_day) then v_kind := 'off'; end if;
  if t1 is not null then ti := (p_day + t1) at time zone 'Asia/Dhaka'; end if;
  if t2 is not null then tout := (p_day + t2 + case when t1 is not null and t2 <= t1 then interval '1 day' else interval '0' end) at time zone 'Asia/Dhaka'; end if;
  rest := case when p_status = 'absent' then null else coalesce(p_rest_min, s.break_min, 0) end;
  if ti is not null and tout is not null then worked := greatest(0, floor(extract(epoch from (tout - ti)) / 60)::int - coalesce(rest, 0)); end if;
  if s.id is not null and ti is not null and v_kind = 'normal' then
    ss := (p_day + s.start_time) at time zone 'Asia/Dhaka';
    se := (p_day + s.end_time + case when s.crosses_midnight or s.end_time <= s.start_time then interval '1 day' else interval '0' end) at time zone 'Asia/Dhaka';
    if ti > ss + make_interval(mins => s.grace_late_min) then late := floor(extract(epoch from (ti - ss)) / 60)::int; end if;
    if tout is not null and tout < se - make_interval(mins => s.grace_early_min) then early := floor(extract(epoch from (se - tout)) / 60)::int; end if;
    if tout is not null and tout > se then ot := least(1440, floor(extract(epoch from (tout - se)) / 60)::int); end if;
  end if;
  if p_status in ('absent', 'off', 'holiday', 'unpaid') then late := 0; early := 0; end if;
  if p_status = 'late' and late = 0 then late := 1; end if;
  v_appr := public.is_owner() and public.rule_on('owner_self_approve');
  select * into old from public.attendance_days where employee_id = p_emp and day = p_day;
  prev := case when found then to_jsonb(old) end;
  perform set_config('bos.mark54', '1', true);
  insert into public.attendance_days as a (employee_id, day, status, day_kind, first_in, last_out, worked_minutes, late_minutes, early_leave_minutes, ot_minutes, ot_approved, punch_count, single_punch,
      shift_id, location_id, leave_type, paid_day, source, marked_by, marked_at, approved_by, approved_at, override_reason, note, computed_at, rest_minutes, mark_source)
    values (p_emp, p_day, p_status, v_kind, ti, tout, worked, late, early, ot, v_appr, 0, false, s.id, e.primary_location_id, null,
      case when p_status = 'holiday' then coalesce(hol.paid, true) when p_status = 'unpaid' then false end, 'manual', auth.uid(), now(),
      case when v_appr then auth.uid() end, case when v_appr then now() end, btrim(p_reason), nullif(btrim(p_note), ''), now(), rest, p_source)
  on conflict (employee_id, day) do update set status = excluded.status, day_kind = excluded.day_kind, first_in = excluded.first_in, last_out = excluded.last_out,
      worked_minutes = excluded.worked_minutes, late_minutes = excluded.late_minutes, early_leave_minutes = excluded.early_leave_minutes, ot_minutes = excluded.ot_minutes,
      ot_approved = excluded.ot_approved, punch_count = a.punch_count, shift_id = excluded.shift_id, location_id = excluded.location_id, leave_type = null, paid_day = excluded.paid_day,
      source = 'manual', marked_by = excluded.marked_by, marked_at = excluded.marked_at, approved_by = excluded.approved_by, approved_at = excluded.approved_at,
      override_reason = excluded.override_reason, note = excluded.note, computed_at = now(), rest_minutes = excluded.rest_minutes, mark_source = excluded.mark_source;
  perform set_config('bos.mark54', '', true);
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.att_mark_log54 (client_id, employee_id, location_id, day, source_tag, status, first_in, last_out, rest_minutes, ot_minutes, reason, note, prev, approved, marked_by, marked_staff)
    values (p_client, p_emp, e.primary_location_id, p_day, p_source, p_status, ti, tout, rest, ot, btrim(p_reason), nullif(btrim(p_note), ''), prev, v_appr, auth.uid(), sid);
  return jsonb_build_object('employee_id', p_emp, 'day', p_day, 'status', p_status, 'source', 'manual', 'source_tag', p_source, 'approved', v_appr, 'late_minutes', late,
    'ot_minutes', ot, 'rest_minutes', rest, 'worked_minutes', worked, 'note', 'source_tag_is_the_markers_declaration_not_proof');
end $$;

-- the board for a person who holds the new grant (attendance_board needs attendance_manage / employee_view)
create or replace function public.att_others_board(p_loc int, p_day date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_day, public._dhaka_today()); rows_ jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not (public.is_owner() or (p_loc is not null and public.can_loc(p_loc) and public.has_grant('attendance_mark_others', p_loc))) then raise exception 'not allowed'; end if;
  if d > public._dhaka_today() or d < date '2020-01-01' then raise exception 'bad_date'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('employee_id', x.id, 'employee_no', x.employee_no, 'name_bn', x.full_name_bn, 'name_en', x.full_name_en,
      'is_me', x.profile_id is not null and x.profile_id = auth.uid(),
      'status', j ->> 'status', 'first_in', j ->> 'first_in', 'last_out', j ->> 'last_out', 'worked_minutes', (j ->> 'worked_minutes')::int, 'rest_minutes', a.rest_minutes,
      'ot_minutes', (j ->> 'ot_minutes')::int, 'source', coalesce(j ->> 'source', 'auto'), 'mark_source', a.mark_source,
      'pending', (j ->> 'source') = 'manual' and (j ->> 'approved_by') is null, 'stored', a.employee_id is not null) order by x.employee_no nulls last, x.full_name_bn), '[]')
    into rows_
    from public.employees x
    left join public.attendance_days a on a.employee_id = x.id and a.day = d
    cross join lateral (select coalesce(to_jsonb(a.*), public._att_derive(x.id, d)) as j) q
   where x.primary_location_id = p_loc and (x.status in ('active', 'on_leave') or (x.status in ('resigned', 'terminated', 'retired') and x.status_date >= d))
     and (x.joining_date is null or x.joining_date <= d);
  return jsonb_build_object('day', d, 'location_id', p_loc, 'rows', rows_);
end $$;

-- ---------- 8. TWO PATHS COUNTED ONCE: guard, link, report ----------
create or replace function public._entries_att_guard54() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.form_code = '02-1' and coalesce(current_setting('bos.shadow_create', true), '') <> '1' then perform public.path_guard('attendance', new.location_id, 'b'); end if;
  return new;
end $$;
drop trigger if exists entries_att_guard54 on public.entries;
create trigger entries_att_guard54 before insert on public.entries for each row execute function public._entries_att_guard54();

-- does path A hold records for this place + month?
create or replace function public._att_month_has_a54(p_loc int, p_month date) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.attendance_days d where d.location_id = p_loc and d.day >= p_month and d.day < (p_month + interval '1 month')::date)
      or exists (select 1 from public.attendance_punches p where p.location_id = p_loc and not p.void and p.punched_at >= (p_month::timestamp at time zone 'Asia/Dhaka')
                  and p.punched_at < ((p_month + interval '1 month')::timestamp at time zone 'Asia/Dhaka'));
$$;

create or replace function public._att_form_month54(p_data jsonb, p_date date) returns date
language sql immutable as $$
  select coalesce(case when p_data->>'month' ~ '^(1[0-2]|[1-9])$' and p_data->>'year' ~ '^20[0-9]{2}$' then make_date((p_data->>'year')::int, (p_data->>'month')::int, 1) end, date_trunc('month', p_date)::date);
$$;

-- link one submitted / approved 02-1 as a shadow when path A is the record for its month. Returns 'linked' | 'already' | 'form_is_primary' | 'path_a_empty' | 'skip'
create or replace function public._att_form_link54(p_entry uuid) returns text
language plpgsql security definer set search_path = public as $$
declare e public.entries; m date; k text;
begin
  select * into e from public.entries where id = p_entry;
  if not found or e.form_code <> '02-1' or e.status not in ('submitted', 'approved') then return 'skip'; end if;
  if public.is_shadow('entries', e.id::text) then return 'already'; end if;
  if public.path_primary('attendance', e.location_id) <> 'a' then return 'form_is_primary'; end if;
  m := public._att_form_month54(e.data, e.entry_date);
  if not public._att_month_has_a54(e.location_id, m) then return 'path_a_empty'; end if;
  k := e.location_id::text || ':' || to_char(m, 'YYYY-MM');
  if exists (select 1 from public.shadow_links x where x.domain = 'attendance' and x.primary_type = 'attendance_month' and x.primary_id = k and x.shadow_type = 'entries' and x.state <> 'void') then return 'already'; end if;
  perform public.shadow_link_add('attendance', e.location_id, 'attendance_month', k, 'entries', e.id::text, 'bos54 02-1 shadow of staff attendance');
  return 'linked';
end $$;

create or replace function public._entries_att_link54() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public._att_form_link54(new.id);
  return null;
end $$;
drop trigger if exists entries_att_link54 on public.entries;
create trigger entries_att_link54 after update of status on public.entries for each row
  when (new.form_code = '02-1' and new.status in ('submitted', 'approved') and old.status is distinct from new.status) execute function public._entries_att_link54();

-- the manager's "link now" for a month whose punches arrived after the form
create or replace function public.attendance_form_link_run(p_loc int, p_month date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; m date := date_trunc('month', p_month)::date; res jsonb := '{}'::jsonb; x text;
begin
  perform public._att_gate();
  if not (public.is_owner() or (public.can_loc(p_loc) and public.has_grant('attendance_manage', p_loc))) then raise exception 'not allowed'; end if;
  for r in select e.id from public.entries e where e.form_code = '02-1' and e.location_id = p_loc and e.status in ('submitted', 'approved') and public._att_form_month54(e.data, e.entry_date) = m order by e.serial loop
    x := public._att_form_link54(r.id);
    res := res || jsonb_build_object(x, coalesce((res ->> x)::int, 0) + 1);
  end loop;
  return jsonb_build_object('location_id', p_loc, 'month', m, 'result', res);
end $$;

-- read-only: per person, what path A says vs what the 02-1 register says, and which one is counted
create or replace function public.attendance_count_once(p_loc int, p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := date_trunc('month', p_month)::date; m2 date; cfg jsonb; rows_ jsonb; forms_ jsonb; mism int;
begin
  if not public._att_loc_view(p_loc) then raise exception 'not allowed'; end if;
  if p_month is null or m > public._dhaka_today() or m < date '2020-01-01' then raise exception 'bad_date'; end if;
  m2 := (m + interval '1 month')::date;
  cfg := public.path_cfg('attendance', p_loc);
  with emp as (select x.id, x.employee_no, x.full_name_bn, x.full_name_en from public.employees x where x.primary_location_id = p_loc and x.status in ('active', 'on_leave', 'resigned', 'terminated', 'retired')),
  dv as (select a.employee_id,
                count(*) filter (where a.status in ('present', 'late')) + 0.5 * count(*) filter (where a.status = 'half_day') as present,
                count(*) filter (where a.status = 'late') as late, count(*) filter (where a.status = 'absent') as absent, round(sum(a.ot_minutes) / 60.0, 2) as ot_hours
           from public.attendance_days a where a.day >= m and a.day < m2 group by a.employee_id),
  fm as (select e.id as entry_id, r as row_ from public.entries e
           cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'staff') = 'array' then e.data -> 'staff' else '[]'::jsonb end) r
          where e.form_code = '02-1' and e.status in ('submitted', 'approved') and e.location_id = p_loc and public._att_form_month54(e.data, e.entry_date) = m
            and btrim(coalesce(r ->> 'name', '')) <> ''),
  fx as (select emp.id as employee_id,
                sum(coalesce(public._db_num(fm.row_ -> 'present'), 0)) as present, sum(coalesce(public._db_num(fm.row_ -> 'late'), 0)) as late,
                sum(coalesce(public._db_num(fm.row_ -> 'absent'), 0)) as absent, sum(coalesce(public._db_num(fm.row_ -> 'ot_hours'), 0)) as ot_hours, count(*) as lines
           from emp join fm on lower(btrim(fm.row_ ->> 'name')) = lower(btrim(emp.full_name_bn)) or (nullif(btrim(emp.full_name_en), '') is not null and lower(btrim(fm.row_ ->> 'name')) = lower(btrim(emp.full_name_en)))
                                or (nullif(btrim(emp.employee_no), '') is not null and lower(btrim(fm.row_ ->> 'name')) = lower(btrim(emp.employee_no)))
          group by emp.id),
  j as (select emp.id, emp.employee_no, emp.full_name_bn, emp.full_name_en, dv.present as d_present, dv.late as d_late, dv.absent as d_absent, dv.ot_hours as d_ot,
               fx.present as f_present, fx.late as f_late, fx.absent as f_absent, fx.ot_hours as f_ot, fx.lines as f_lines,
               (dv.employee_id is not null and fx.employee_id is not null and (dv.present <> fx.present or dv.late <> fx.late or dv.absent <> fx.absent or abs(coalesce(dv.ot_hours, 0) - fx.ot_hours) > 0.5)) as mismatch
          from emp left join dv on dv.employee_id = emp.id left join fx on fx.employee_id = emp.id where dv.employee_id is not null or fx.employee_id is not null)
  select coalesce(jsonb_agg(jsonb_build_object('employee_id', j.id, 'employee_no', j.employee_no, 'name_bn', j.full_name_bn, 'name_en', j.full_name_en,
           'device', case when j.d_present is null and j.d_absent is null then null else jsonb_build_object('present', j.d_present, 'late', j.d_late, 'absent', j.d_absent, 'ot_hours', j.d_ot) end,
           'form', case when j.f_lines is null then null else jsonb_build_object('present', j.f_present, 'late', j.f_late, 'absent', j.f_absent, 'ot_hours', j.f_ot) end,
           'mismatch', j.mismatch) order by j.employee_no nulls last, j.full_name_bn), '[]'), count(*) filter (where j.mismatch)
    into rows_, mism from j;
  select coalesce(jsonb_agg(jsonb_build_object('entry_id', e.id, 'serial', e.serial, 'status', e.status, 'is_shadow', public.is_shadow('entries', e.id::text)) order by e.serial), '[]') into forms_
    from public.entries e where e.form_code = '02-1' and e.location_id = p_loc and e.status in ('submitted', 'approved') and public._att_form_month54(e.data, e.entry_date) = m;
  return jsonb_build_object('location_id', p_loc, 'month', m, 'primary', cfg ->> 'primary', 'a_open', cfg -> 'a_open', 'b_open', cfg -> 'b_open',
    'counted', case when cfg ->> 'primary' = 'b' then 'form_02_1' else 'attendance_record' end,
    'path_a_has_month', public._att_month_has_a54(p_loc, m), 'forms', forms_, 'rows', rows_, 'mismatches', mism,
    'limits', 'People are matched by name / employee no. written on the register; a difference is a prompt to look, not a verdict.');
end $$;

-- ---------- 9. EQUATION RECOMPUTE (gap #20, read-only) ----------
create or replace function public._eq_limit54(p_loc int, p_key text, p_date date) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  begin v := public.get_limit(p_loc, p_key, p_date); exception when others then return null; end;
  return public._db_num(v);
end $$;

create or replace function public._eq_truthy54(j jsonb) returns boolean language sql immutable as $$
  select coalesce(j = 'true'::jsonb or j = '"true"'::jsonb or j = '"yes"'::jsonb or j = '"1"'::jsonb or j = '1'::jsonb, false);
$$;

-- the engine: no permission check (callers do it); returns {form, supported, recomputed, mismatches, observations, ok}
create or replace function public._eq_check54(e public.entries) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d jsonb := coalesce(e.data, '{}'::jsonb); lines jsonb; r jsonb; rc jsonb;
        total numeric := 0; amt numeric; norec numeric := 0; maxa numeric := 0; lim numeric; imp numeric; cashn numeric; rcpt numeric; diff numeric;
        exp_ jsonb := '{}'::jsonb;      -- expected flags: code -> amount (null amount = flag without amount)
        mism jsonb := '[]'::jsonb; obs jsonb := '[]'::jsonb; rec jsonb := '{}'::jsonb; k text; c text; st jsonb;
        neg int := 0; noreason int := 0; unsigned boolean := false; t_due numeric := 0; t_ot numeric := 0; t_other numeric := 0; t_adv numeric := 0; t_od numeric := 0; g numeric; n numeric; any_ boolean; t_rc numeric := 0;
        codes text[];
begin
  if e.form_code = '10-2' then
    codes := array['imprest_mismatch', 'no_receipt', 'over_limit'];
    lines := case when jsonb_typeof(d -> 'lines') = 'array' then d -> 'lines' else '[]'::jsonb end;
    lim := public._eq_limit54(e.location_id, 'expense_max', e.entry_date);
    imp := public._eq_limit54(e.location_id, 'imprest', e.entry_date);
    for r in select * from jsonb_array_elements(lines) loop
      amt := coalesce(public._db_num(r -> 'amount'), 0);
      total := total + amt; maxa := greatest(maxa, amt);
      if r ->> 'receipt' = 'no' and amt > 0 then norec := norec + amt; end if;
    end loop;
    cashn := public._db_num(d -> 'cash_now'); rcpt := coalesce(public._db_num(d -> 'receipts_total'), 0);
    if lim is not null and maxa > lim then exp_ := exp_ || jsonb_build_object('over_limit', maxa); end if;
    if norec > 0 then exp_ := exp_ || jsonb_build_object('no_receipt', norec); end if;
    if imp is not null and cashn is not null then
      diff := coalesce(cashn, 0) + rcpt - imp;
      if diff <> 0 then exp_ := exp_ || jsonb_build_object('imprest_mismatch', diff); end if;
    end if;
    rec := jsonb_build_object('total', total, 'cash_plus_receipts', coalesce(cashn, 0) + rcpt, 'imprest', imp, 'expense_max', lim, 'imprest_diff', diff, 'no_receipt_amount', norec);
  elsif e.form_code = '02-2' then
    codes := array['net_negative', 'other_no_reason', 'paid_unsigned'];
    lines := case when jsonb_typeof(d -> 'pay') = 'array' then d -> 'pay' else '[]'::jsonb end;
    for r in select * from jsonb_array_elements(lines) loop
      any_ := exists (select 1 from jsonb_each_text(case when jsonb_typeof(r) = 'object' then r else '{}'::jsonb end) kv where btrim(kv.value) <> '');
      g := coalesce(public._db_num(r -> 'due'), 0) + coalesce(public._db_num(r -> 'overtime'), 0) + coalesce(public._db_num(r -> 'other'), 0);
      n := g - coalesce(public._db_num(r -> 'adv_ded'), 0) - coalesce(public._db_num(r -> 'other_ded'), 0);
      t_due := t_due + coalesce(public._db_num(r -> 'due'), 0); t_ot := t_ot + coalesce(public._db_num(r -> 'overtime'), 0); t_other := t_other + coalesce(public._db_num(r -> 'other'), 0);
      t_adv := t_adv + coalesce(public._db_num(r -> 'adv_ded'), 0); t_od := t_od + coalesce(public._db_num(r -> 'other_ded'), 0);
      if any_ then
        if n < 0 then neg := neg + 1; end if;
        if (coalesce(public._db_num(r -> 'other'), 0) > 0 or coalesce(public._db_num(r -> 'other_ded'), 0) > 0) and nullif(btrim(coalesce(r ->> 'remark', '')), '') is null then noreason := noreason + 1; end if;
      end if;
    end loop;
    for r in select * from jsonb_array_elements(case when jsonb_typeof(d -> 'receipts') = 'array' then d -> 'receipts' else '[]'::jsonb end) loop
      t_rc := t_rc + coalesce(public._db_num(r -> 'net'), 0);
      if coalesce(public._db_num(r -> 'net'), 0) > 0 and not public._eq_truthy54(r -> 'signed') then unsigned := true; end if;
    end loop;
    if neg > 0 then exp_ := exp_ || jsonb_build_object('net_negative', neg); end if;
    if noreason > 0 then exp_ := exp_ || jsonb_build_object('other_no_reason', noreason); end if;
    if unsigned then exp_ := exp_ || jsonb_build_object('paid_unsigned', null); end if;
    rec := jsonb_build_object('t_due', t_due, 't_ot', t_ot, 't_other', t_other, 't_gross', t_due + t_ot + t_other, 't_adv', t_adv, 't_other_ded', t_od,
                              't_net', t_due + t_ot + t_other - t_adv - t_od, 't_receipts', t_rc, 'negative_net_people', neg, 'other_without_reason', noreason);
    if abs(t_rc - (t_due + t_ot + t_other - t_adv - t_od)) > 0.004 and t_rc > 0 then
      obs := obs || jsonb_build_array(jsonb_build_object('code', 'receipts_vs_net', 'receipts_total', t_rc, 'sheet_net', t_due + t_ot + t_other - t_adv - t_od,
                                                          'note', 'information only: the receipt acknowledgement does not add up to the sheet net'));
    end if;
  else
    return jsonb_build_object('form', e.form_code, 'supported', false, 'ok', true, 'mismatches', '[]'::jsonb, 'why', 'only 10-2 and 02-2 are re-worked; 14-1 is not');
  end if;
  -- compare to the flags the phone stored
  foreach c in array codes loop
    select x into st from jsonb_array_elements(coalesce(e.flags, '[]'::jsonb)) x where x ->> 'code' = c limit 1;
    if exp_ ? c and st is null then
      mism := mism || jsonb_build_array(jsonb_build_object('code', c, 'kind', 'flag_missing', 'recomputed', exp_ -> c, 'stored', null));
    elsif not (exp_ ? c) and st is not null and st ->> 'level' = 'red' then
      mism := mism || jsonb_build_array(jsonb_build_object('code', c, 'kind', 'flag_extra', 'recomputed', null, 'stored', st -> 'amount'));
    elsif exp_ ? c and st is not null and jsonb_typeof(exp_ -> c) = 'number' and public._db_num(st -> 'amount') is distinct from (exp_ ->> c)::numeric then
      mism := mism || jsonb_build_array(jsonb_build_object('code', c, 'kind', 'amount_differs', 'recomputed', exp_ -> c, 'stored', st -> 'amount'));
    end if;
  end loop;
  return jsonb_build_object('form', e.form_code, 'supported', true, 'recomputed', rec, 'expected_flags', exp_, 'mismatches', mism, 'observations', obs, 'ok', jsonb_array_length(mism) = 0,
    'note', 'limits (expense_max, imprest) are read as they are today; a limit changed after the sheet was saved can show as a difference');
end $$;

create or replace function public.entry_equation_check(p_entry uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.entries;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into e from public.entries where id = p_entry;
  if not found then raise exception 'not_found'; end if;
  if not (public.is_owner() or (public.can_loc(e.location_id) and (public.can_do(e.form_code, 'view') or public.can_do(e.form_code, 'enter') or e.created_by = auth.uid()))) then raise exception 'not allowed'; end if;
  return public._eq_check54(e) || jsonb_build_object('entry_id', e.id, 'serial', e.serial, 'status', e.status);
end $$;

-- optional (switch entry_equation_flag_on, default OFF): at the end of the submitting transaction, one red exception when the stored flags differ from the re-work.
-- A deferred constraint trigger, so submit_entry (which clears and rewrites open exceptions) is not touched and cannot erase it.
create or replace function public._entries_eq_flag54() returns trigger
language plpgsql security definer set search_path = public as $$
declare e public.entries; res jsonb;
begin
  if not public.rule_on('entry_equation_flag_on') then return null; end if;
  select * into e from public.entries where id = new.id;
  if not found or e.status not in ('submitted', 'approved') then return null; end if;
  res := public._eq_check54(e);
  if coalesce((res ->> 'ok')::boolean, true) then return null; end if;
  if not exists (select 1 from public.exceptions x where x.entry_id = e.id and x.flag_code = 'equation_mismatch' and x.status = 'open') then
    insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (e.id, e.form_code, e.location_id, e.entry_date, 'equation_mismatch', 'red', null,
              jsonb_build_object('bn', 'ফোনের হিসাব আর সার্ভারের পুনঃহিসাব মেলেনি — ' || (select string_agg(m ->> 'code', ', ') from jsonb_array_elements(res -> 'mismatches') m),
                                 'en', 'Phone totals and the server re-work differ: ' || (select string_agg(m ->> 'code', ', ') from jsonb_array_elements(res -> 'mismatches') m)));
  end if;
  return null;
end $$;
drop trigger if exists entries_eq_flag54 on public.entries;
create constraint trigger entries_eq_flag54 after update of status on public.entries deferrable initially deferred for each row
  when (new.form_code in ('10-2', '02-2') and new.status = 'submitted' and old.status is distinct from new.status) execute function public._entries_eq_flag54();

-- ---------- 10. rights ----------
revoke all on function public._att_geo_m54(numeric, numeric, numeric, numeric), public._att_self_state54(public.employees), public._att_log_ro54(), public._att_days_guard54(),
  public._entries_att_guard54(), public._att_month_has_a54(int, date), public._att_form_month54(jsonb, date), public._att_form_link54(uuid), public._entries_att_link54(),
  public._eq_limit54(int, text, date), public._eq_truthy54(jsonb), public._eq_check54(public.entries), public._entries_eq_flag54() from public, anon, authenticated;
revoke all on function public.attendance_self_punch(text, numeric, numeric, numeric, text, text), public.att_my_status(), public.att_self_lock_set(text, text, boolean, text),
  public.att_site_geo_set(int, numeric, numeric), public.att_staff_overview(int), public.att_evidence_register(uuid, text, text, text), public.att_evidence_void(bigint, text),
  public.attendance_mark_others(uuid, date, text, text, text, int, text, text, text, uuid), public.att_others_board(int, date), public.attendance_form_link_run(int, date),
  public.attendance_count_once(int, date), public.entry_equation_check(uuid) from public, anon;
grant execute on function public.attendance_self_punch(text, numeric, numeric, numeric, text, text), public.att_my_status(), public.att_self_lock_set(text, text, boolean, text),
  public.att_site_geo_set(int, numeric, numeric), public.att_staff_overview(int), public.att_evidence_register(uuid, text, text, text), public.att_evidence_void(bigint, text),
  public.attendance_mark_others(uuid, date, text, text, text, int, text, text, text, uuid), public.att_others_board(int, date), public.attendance_form_link_run(int, date),
  public.attendance_count_once(int, date), public.entry_equation_check(uuid) to authenticated;

