-- Phase 86 (bos86) - FIXES after the independent check of phases 80-85. Paste LAST (after phase85), paste-twice safe. Earlier phase files are not edited.
--   M1  Named approver mode could be bypassed: owner_self_approve_set(true) turned the legacy switch ON again while the mode still read "named".
--       Now ANY change that turns owner_self_approve ON is refused while owner_approval_mode = named (trigger on rules, covers lists, releases, emergencies, item changes).
--   M2  Named mode: the decider must differ from the maker; the owner cannot enter named mode (or set the approver role) while he holds that role himself.
--   M3  _p27_pl: salary is exactly what it was before phase85 (all 02-2 sheets) while payroll_accrual_on is OFF. The app payroll runs (c_salary_by_month)
--       and the "shadow sheet is not counted" rule apply only when the owner has switched payroll accrual ON. Counted once in both cases.
--   M4  Wallet split switch d_wallet_split_on (default OFF). OFF: nothing moves from 1130 to the wallet accounts, wallet fees and moves post on 1130.
--       ON: the split of phase83 applies. Entries already posted are never rewritten (a posted split is still reversed if its payment is voided).
--   m5  Wallet negative block also covers a supplier payment made from a wallet (only a wallet that has an opening date, i.e. one the owner has started to keep).
--   m8  Recovery when the only other holder of the named role is gone: the owner can always switch the mode back to self (owner_approval_mode_set, audit line). Tested.
-- NOTHING IS TURNED ON BY THIS FILE. If phase83, phase85 or phase17/80 are pasted again later, paste this file again afterwards.

do $g$ begin
  if to_regprocedure('public._d_acct_docs(date)') is null or to_regprocedure('public._owner_named_guard()') is null
     or to_regprocedure('public._p27_pl(date,date,integer[])') is null or to_regprocedure('public.c_salary_by_month(date,date,integer[])') is null then
    raise exception 'phase86 needs phases 80, 82, 83 and 85 first';
  end if;
end $g$;

create or replace function public._p86_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- M4 rule ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('d_wallet_split_on', 'books', 'switch', 'false', null, null, null, null,
  'ওয়ালেট আলাদা খতিয়ান-হিসাবে ভাগ (বিকাশ, নগদ...)', 'Wallet আলাদা account এ ভাগ (bKash, Nagad...)', 'Book each mobile wallet on its own account',
  'বন্ধ থাকলে সব মোবাইল টাকা আগের মতোই একটি হিসাবে (1130)। চালু করলে নতুন লেনদেন ওয়ালেটের নিজের হিসাবে যায়; আগে উঠে যাওয়া এন্ট্রি বদলায় না।',
  'Off = all mobile money stays on the one mobile account (1130), as before; wallet fees and moves also use it. On = new sales, collections and supplier payments that name a wallet are moved to that wallet''s own account (1131-1134). Entries already posted are not changed.', 832)
on conflict (key) do nothing;

create or replace function public._d_split_on() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.rule_on('d_wallet_split_on'), false) $$;

-- ---------- M1 the legacy switch may not go ON while the named mode is active ----------
create or replace function public._rules_named_switch_guard86() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if current_setting('role', true) = 'authenticated' and new.key = 'owner_self_approve' and coalesce(new.value, new.default_value) = 'true'::jsonb
     and public._owner_mode() = 'named' and coalesce(current_setting('bos80.setting', true), '') <> '1' then
    raise exception 'named_mode_active';
  end if;
  return new;
end $$;
drop trigger if exists rules_named_switch_guard86 on public.rules;
create trigger rules_named_switch_guard86 before update on public.rules for each row execute function public._rules_named_switch_guard86();

-- ---------- M2 named guard: decider <> maker ----------
create or replace function public._owner_named_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare maker uuid; decider uuid; rl text;
begin
  if public._owner_mode() <> 'named' then return new; end if;
  if tg_table_name = 'entries' then
    if not (old.status = 'submitted' and new.status in ('approved', 'rejected')) then return new; end if;
    maker := new.created_by; decider := new.checked_by;
  else
    if not (old.status = 'pending' and new.status in ('approved', 'rejected')) then return new; end if;
    maker := new.requested_by; decider := new.decided_by;
  end if;
  if not exists (select 1 from public.user_roles where user_id = maker and role_code = 'owner') then return new; end if;
  rl := public.rule_txt('owner_approver_role');
  if rl is null or decider is null or decider = maker /* bos86 */ or not exists (select 1 from public.user_roles where user_id = decider and role_code = rl) then raise exception 'named_approver_only'; end if;
  return new;
end $$;

create or replace function public.owner_approval_mode_set(p_mode text, p_role text default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old_m text := public._owner_mode(); old_r text := public.rule_txt('owner_approver_role'); rl text := nullif(btrim(coalesce(p_role, '')), '');
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_mode is null or p_mode not in ('self', 'named', 'logged', 'off') then raise exception 'bad_value'; end if;
  if p_mode = 'named' then
    rl := coalesce(rl, old_r);
    if rl is null then raise exception 'data_needed:owner_approver_role'; end if;
    if not exists (select 1 from public.roles where code = rl and active) or rl = 'owner' then raise exception 'bad_role'; end if;
    if not exists (select 1 from public.user_roles ur join public.profiles p on p.id = ur.user_id where ur.role_code = rl and p.status = 'active' and p.id <> auth.uid()) then raise exception 'no_other_approver'; end if;
  end if;
  -- bos86: the owner who makes the setting must not hold the approver role himself (in any mode, so the role cannot be pointed at a role he holds)
  if rl is not null and exists (select 1 from public.user_roles where user_id = auth.uid() and role_code = rl) then raise exception 'owner_holds_approver_role'; end if;
  perform set_config('bos80.setting', '1', true);
  update public.rules set value = to_jsonb(p_mode), updated_at = now(), updated_by = auth.uid() where key = 'owner_approval_mode';
  if rl is not null then update public.rules set value = to_jsonb(rl), updated_at = now(), updated_by = auth.uid() where key = 'owner_approver_role'; end if;
  perform public.set_rule('owner_self_approve', to_jsonb(p_mode <> 'named'));
  perform set_config('bos80.setting', '', true);
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'owner_approval_mode', 'rules', 'owner_approval_mode',
      jsonb_build_object('old', jsonb_build_object('mode', old_m, 'role', old_r), 'new', jsonb_build_object('mode', p_mode, 'role', coalesce(rl, old_r)), 'note', left(p_note, 300)));
  return jsonb_build_object('mode', p_mode, 'approver_role', coalesce(rl, old_r), 'owner_self_approve', p_mode <> 'named');
end $$;

create or replace function public._d_on_mobile86(p_type text, p_id text) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.journal_entries e join public.journal_lines l on l.entry_id = e.id join public.acct_mappings am on am.key = 'pay_mobile' and am.account_id = l.account_id
                  where e.source_type = p_type and e.source_id = p_id and e.reverses_id is null) $$;

-- ---------- M4 the wallet journal source with the switch ----------
create or replace function public._d_acct_docs(p_start date)
returns table(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
language plpgsql stable security definer set search_path = public as $$
declare treat text := coalesce(public.rule_txt('d_wallet_fee_treatment'), 'separate_expense'); sp boolean := public._d_split_on();
begin
  -- a sale or collection paid into a named wallet: move it from the generic mobile account to the wallet account (only with the split switch ON, or to reverse one already posted)
  return query
  select 'd_wallet_split'::text, 'sp:' || p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, ('Wallet ' || w.code || ' payment received')::text, null::text,
    (not p.voided and (p.sale_id is null or s.status = 'done')), public._acct_today(), null::text, null::text,
    case when not p.voided and (p.sale_id is null or s.status = 'done') then jsonb_build_array(jsonb_build_object('a', 'd_wallet_' || w.code, 'd', p.amount), jsonb_build_object('a', 'pay_mobile', 'c', p.amount)) end
  from public.sale_payments p left join public.sales s on s.id = p.sale_id join public.d_wallets w on w.id = public._d_wallet_of(p.wallet)
  where p.mode = 'mobile' and p.kind in ('sale', 'collection') and p.amount > 0 and (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start
    and (sp or exists (select 1 from public.journal_entries je where je.source_type = 'd_wallet_split' and je.source_id = 'sp:' || p.id::text and je.reverses_id is null))
    and public._acct_need('d_wallet_split', 'sp:' || p.id::text, (not p.voided and (p.sale_id is null or s.status = 'done')));
  -- a supplier payment from a named wallet
  return query
  select 'd_wallet_split'::text, 'sup:' || p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, ('Wallet ' || w.code || ' supplier payment')::text, null::text,
    not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', 'pay_mobile', 'd', p.amount), jsonb_build_object('a', 'd_wallet_' || w.code, 'c', p.amount)) end
  from public.supplier_payments p join public.d_wallets w on w.id = public._d_wallet_of(p.wallet)
  where p.mode = 'mobile' and p.amount > 0 and (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start
    and (sp or exists (select 1 from public.journal_entries je where je.source_type = 'd_wallet_split' and je.source_id = 'sup:' || p.id::text and je.reverses_id is null))
    and public._acct_need('d_wallet_split', 'sup:' || p.id::text, not p.voided);
  -- wallet fees: Dr Wallet fees (5815), Cr the wallet (its own account with the split ON, else the mobile account 1130)
  return query
  select 'd_wallet_fee'::text, f.id::text, f.fee_date, f.location_id, ('Wallet fee ' || w.code)::text, f.kind, (not f.voided and treat = 'separate_expense'), coalesce((f.void_at at time zone 'Asia/Dhaka')::date, public._acct_today()),
    null::text, null::text,
    case when not f.voided and treat = 'separate_expense' then jsonb_build_array(jsonb_build_object('a', 'wallet_fee', 'd', f.amount),
      jsonb_build_object('a', case when sp then 'd_wallet_' || w.code else 'pay_mobile' end, 'c', f.amount)) end
  from public.d_wallet_fees f join public.d_wallets w on w.id = f.wallet_id
  where f.fee_date >= p_start and public._acct_need('d_wallet_fee', f.id::text, (not f.voided and treat = 'separate_expense'));
  -- wallet moves: cash / bank / other wallet on the other side; with the split OFF the wallet side is 1130 and a wallet-to-wallet move has nothing to book
  return query
  select 'd_wallet_move'::text, m.id::text, m.move_date, m.location_id, ('Wallet ' || w.code || ' ' || m.direction || ' ' || m.counter)::text, m.counter, not m.voided,
    coalesce((m.void_at at time zone 'Asia/Dhaka')::date, public._acct_today()), null::text, null::text,
    case when not m.voided then jsonb_build_array(
      jsonb_build_object('a', case m.direction when 'in' then case when sp then 'd_wallet_' || w.code else 'pay_mobile' end
                         else case m.counter when 'cash' then 'pay_cash' when 'bank' then 'pay_bank' else case when sp then 'd_wallet_' || w2.code else 'pay_mobile' end end end, 'd', m.amount),
      jsonb_build_object('a', case m.direction when 'out' then case when sp then 'd_wallet_' || w.code else 'pay_mobile' end
                         else case m.counter when 'cash' then 'pay_cash' when 'bank' then 'pay_bank' else case when sp then 'd_wallet_' || w2.code else 'pay_mobile' end end end, 'c', m.amount)) end
  from public.d_wallet_moves m join public.d_wallets w on w.id = m.wallet_id left join public.d_wallets w2 on w2.id = m.counter_wallet_id
  where m.move_date >= p_start
    and (sp or m.counter_wallet_id is null or exists (select 1 from public.journal_entries je where je.source_type = 'd_wallet_move' and je.source_id = m.id::text and je.reverses_id is null))
    and public._acct_need('d_wallet_move', m.id::text, not m.voided);
  -- the split switch turned ON later: a fee or a move out/in with cash or bank that was posted on the mobile account while the switch was OFF is moved to the wallet account
  return query
  select 'd_wallet_split'::text, 'fee:' || f.id::text, f.fee_date, f.location_id, ('Wallet ' || w.code || ' fee moved to the wallet account')::text, null::text, not f.voided,
    public._acct_today(), null::text, null::text,
    case when not f.voided then jsonb_build_array(jsonb_build_object('a', 'pay_mobile', 'd', f.amount), jsonb_build_object('a', 'd_wallet_' || w.code, 'c', f.amount)) end
  from public.d_wallet_fees f join public.d_wallets w on w.id = f.wallet_id
  where f.fee_date >= p_start and public._d_on_mobile86('d_wallet_fee', f.id::text)
    and (sp or exists (select 1 from public.journal_entries je where je.source_type = 'd_wallet_split' and je.source_id = 'fee:' || f.id::text and je.reverses_id is null))
    and public._acct_need('d_wallet_split', 'fee:' || f.id::text, not f.voided);
  return query
  select 'd_wallet_split'::text, 'mv:' || m.id::text, m.move_date, m.location_id, ('Wallet ' || w.code || ' move moved to the wallet account')::text, null::text, not m.voided,
    public._acct_today(), null::text, null::text,
    case when not m.voided then jsonb_build_array(
      jsonb_build_object('a', case m.direction when 'in' then 'd_wallet_' || w.code else 'pay_mobile' end, 'd', m.amount),
      jsonb_build_object('a', case m.direction when 'in' then 'pay_mobile' else 'd_wallet_' || w.code end, 'c', m.amount)) end
  from public.d_wallet_moves m join public.d_wallets w on w.id = m.wallet_id
  where m.move_date >= p_start and m.counter_wallet_id is null and public._d_on_mobile86('d_wallet_move', m.id::text)
    and (sp or exists (select 1 from public.journal_entries je where je.source_type = 'd_wallet_split' and je.source_id = 'mv:' || m.id::text and je.reverses_id is null))
    and public._acct_need('d_wallet_split', 'mv:' || m.id::text, not m.voided);
end $$;

-- ---------- m5 supplier payment from a wallet: the same negative check as fees and moves ----------
create or replace function public._d_supplier_pay_neg86() returns trigger language plpgsql security definer set search_path = public as $$
declare wid int;
begin
  if new.mode = 'mobile' and not coalesce(new.voided, false) and coalesce(new.amount, 0) > 0 then
    wid := public._d_wallet_of(new.wallet);
    if wid is not null and exists (select 1 from public.d_wallets w where w.id = wid and w.opening_date is not null) then
      perform public._d_neg_check(wid, (coalesce(new.paid_at, now()) at time zone 'Asia/Dhaka')::date, new.amount);
    end if;
  end if;
  return new;
end $$;
drop trigger if exists supplier_pay_wallet_neg86 on public.supplier_payments;
create trigger supplier_pay_wallet_neg86 before insert on public.supplier_payments for each row execute function public._d_supplier_pay_neg86();

revoke all on function public._p86_present(), public._d_split_on(), public._rules_named_switch_guard86(), public._d_supplier_pay_neg86(), public._d_on_mobile86(text, text), public._d_acct_docs(date), public.owner_approval_mode_set(text, text, text), public._owner_named_guard() from public, anon, authenticated;
grant execute on function public.owner_approval_mode_set(text, text, text) to authenticated;

-- ---------- M3 _p27_pl: phase85 body, salary of the app payroll runs only when payroll_accrual_on is ON ----------
create or replace function public._p27_pl(d1 date, d2 date, locs integer[])
 returns table(o_m date, o_loc integer, o_gross numeric, o_ret numeric, o_net numeric, o_costed numeric, o_cogs numeric, o_exp numeric, o_sal numeric, o_fixed numeric)
 language sql stable security definer set search_path to 'public'
as $function$
  with net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  s as (select x.id, date_trunc('month', x.sale_date)::date as m, x.location_id, x.total, x.subtotal, x.lines from public.sales x
        where x.status = 'done' and x.sale_date between d1 and d2 and x.location_id = any (locs)),
  tot as (select m, location_id, sum(total) as rev from s group by 1, 2),
  ag as (  -- bos72: stock-ledger cost of what was sold (item_costs only as fallback), returns subtracted with their discount share
    select date_trunc('month', h.d)::date as m, h.loc as location_id,
           sum((case h.src when 'sale' then 1 else -1 end) * (h.led_rev + h.fb_rev)) as cr,
           sum((case h.src when 'sale' then 1 else -1 end) * (h.led_cogs + h.fb_cogs)) as cg
    from public._cogs_lines72(d1, d2, locs) h group by 1, 2),
  rr as (select r.id, date_trunc('month', (r.created_at at time zone 'Asia/Dhaka')::date)::date as m, r.location_id, r.amount, r.lines
         from public.sale_returns r, net_on
         where net_on.v and r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs)),
  rt as (select m, location_id, sum(amount) as ra from rr group by 1, 2),
  ex as (
    select u.m, u.location_id, sum(u.amt) as amt from (
      select date_trunc('month', e.entry_date)::date as m, e.location_id, public._r2_num(ln -> 'amount') as amt
      from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) ln
      where e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.entry_date between d1 and d2 and e.location_id = any (locs)
      union all  -- bos50: quick expenses
      select date_trunc('month', q.exp_date)::date, q.location_id, q.amount from public.quick_expenses q
      where q.status = 'done' and q.exp_date between d1 and d2 and q.location_id = any (locs)
      union all  -- bos85: mobile wallet fees (phase83), zero rows while the fee treatment is not_posted
      select w.m, w.loc, w.amount from public._d_wallet_fee_rows(d1, d2, locs) w) u group by 1, 2),
  sa as (  -- bos86 (replaces the bos85 comment here): accrual OFF = all 02-2 forms, exactly as before phase85; accrual ON = the 02-2 forms that are not a shadow of an app payroll run + the approved or paid app runs (each salary once)
    select z.m, z.location_id, sum(z.amt) as amt from (
      select date_trunc('month', e.entry_date)::date as m, e.location_id,
             sum(coalesce(public._r2_num(r -> 'due'), 0) + coalesce(public._r2_num(r -> 'overtime'), 0) + coalesce(public._r2_num(r -> 'other'), 0)) as amt
      from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'pay') = 'array' then e.data -> 'pay' else '[]'::jsonb end) r
      where e.form_code = '02-2' and e.status in ('submitted', 'approved') and (not public.rule_on('payroll_accrual_on') or not public.is_shadow('entries', e.id::text)) /* bos85 bos86 */
        and e.entry_date between d1 and d2 and e.location_id = any (locs) group by 1, 2
      union all
      select c.m, c.loc, c.amt from public.c_salary_by_month(d1, d2, locs) c where public.rule_on('payroll_accrual_on') /* bos85 bos86 */) z group by 1, 2),
  k as (select m, location_id from tot union select m, location_id from rt union select m, location_id from ex union select m, location_id from sa)
  select k.m, k.location_id,
         coalesce(t.rev, 0), coalesce(x.ra, 0), coalesce(t.rev, 0) - coalesce(x.ra, 0),
         round(coalesce(a.cr, 0), 2), round(coalesce(a.cg, 0), 2),
         e.amt, s2.amt,
         case when fm.v is not null then round(fm.v * (least(d2, (k.m + interval '1 month')::date - 1) - greatest(d1, k.m) + 1)
                / extract(day from (k.m + interval '1 month' - interval '1 day')), 2) end
  from k
  left join tot t on t.m = k.m and t.location_id = k.location_id
  left join rt x on x.m = k.m and x.location_id = k.location_id
  left join ag a on a.m = k.m and a.location_id = k.location_id
  left join ex e on e.m = k.m and e.location_id = k.location_id
  left join sa s2 on s2.m = k.m and s2.location_id = k.location_id
  left join lateral (select public._r2_num(ls.value) as v from public.location_settings ls where ls.location_id = k.location_id and ls.key = 'fixed_cost_month') fm on true;
$function$;

revoke all on function public._p27_pl(date, date, int[]) from public, anon, authenticated;
