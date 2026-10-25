-- Phase 461 (RPT-C3, package R7 part 4) - POST THE MARKETING SPEND OF FORM 18-1 TO THE JOURNAL (setting marketing_post_on, OFF) WITHOUT DOUBLE COUNTING FORM 10-2.
-- Paste AFTER phase460 (needs phase 40 accounting and phase 458). Paste-twice safe. No earlier phase file is edited; acct_post_pending and every shared function stay as they are.
--
-- Why: form 18-1 spend never reaches the journal or the profit figures (audit finding F8). If the same spend is ALSO typed in form 10-2 (expense head "marketing") or as a quick expense,
-- posting both would count it twice. Posting is therefore an owner decision, OFF by default, and every line is classified before anything is written:
--   posted               already in the journal (key = sheet : revision : line number)
--   to_post              an APPROVED 18-1 line, paid from bank / mobile / card, dated on or after the start dates, no 10-2 look-alike, period open
--   skip_imprest         paid from the imprest box: the imprest money is recorded by its 10-2 voucher, so posting it here would count it twice. NEVER posted by this file.
--   needs_source         the line has no "source of money": the credit side is unknown, so nothing is posted
--   owner_money          paid from the owner's own money: which account is credited is an accounting choice nobody made yet, so nothing is posted
--   possible_duplicate   an approved / submitted 10-2 voucher line (head marketing) or a quick expense of the SAME amount, SAME place and SAME date exists. It waits for a person's
--                        decision (mkt_post_decide: post | skip, reason required, kept for ever). Never posted by itself.
--   decided_skip         a person chose to skip it
--   before_start / not_set_up   dated before the start dates / the start dates are not set yet
--   period_locked        the period is closed
-- Entry written (two lines, Dr = Cr): Dr 'exp_marketing' mapping / Cr 'pay_bank' | 'pay_mobile' (card follows the supplier-payment rule: bank). Source type 'mkt_spend', dated the line date.
-- Settings (module books): marketing_post_on (switch, OFF), marketing_post_from (date, blank = cannot switch on). The switch can go ON only with a valid date, accounting ON with a start date
-- and the three mappings present. A re-opened sheet (new revision) has its old entry reversed and the new one posted on the next run; nothing is deleted.
-- NOTE for the owner and the accountant: the management profit view (L1 / T4) reads 10-2 vouchers, not 18-1; the journal profit includes these entries once posted.
-- Test data only (test_*).

do $g$ begin
  if to_regprocedure('public.mkt_spend_by_campaign(date,date,integer)') is null or to_regprocedure('public._acct_write(date,integer,text,text,text,text,text,jsonb,bigint,uuid,text)') is null
     or to_regprocedure('public._append_only43()') is null then
    raise exception 'phase461 needs phases 459, 40 and 43 first';
  end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'books', v.kind, v.dv, v.unit, v.ch, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('marketing_post_on', 'switch', 'false'::jsonb, null::text, null::jsonb, null::numeric, null::numeric,
   'Post the marketing spend of form 18-1 to the books',
   'OFF = form 18-1 spend stays out of the journal (today). ON = approved 18-1 lines paid from bank / mobile / card are posted (Dr marketing expense, Cr bank / mobile), except lines that look like the same spend already typed in form 10-2 or as a quick expense: those wait for a decision. Imprest-paid lines are never posted here. Needs the date below, accounting ON with a start date, and the marketing / bank / mobile account mappings.', 960),
 ('marketing_post_from', 'text', null::jsonb, 'YYYY-MM-DD', null::jsonb, null::numeric, null::numeric,
   'Marketing spend is posted to the books from this date',
   'Only 18-1 lines dated on or after this date are posted. Blank = the switch above cannot be turned on. Lines before this date are never posted.', 961)
  ) as v(key, kind, dv, unit, ch, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

create or replace function public._c3_rules_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare v text; f text; d date;
begin
  if new.key = 'marketing_post_from' then
    v := nullif(new.value #>> '{}', '');
    if v is not null then
      if v !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'bad_date'; end if;
      begin d := v::date; exception when others then raise exception 'bad_date'; end;
    end if;
  elsif new.key = 'marketing_post_on' and coalesce((new.value #>> '{}')::boolean, false) then
    select nullif(coalesce(r.value, r.default_value) #>> '{}', '') into f from public.rules r where r.key = 'marketing_post_from';
    if f is null or public._acct_start() is null or not public.rule_on('accounting_on') then raise exception 'marketing_post_needs_setup'; end if;
    if (select count(*) from public.acct_mappings where key in ('exp_marketing', 'pay_bank', 'pay_mobile')) < 3 then raise exception 'marketing_post_needs_mappings'; end if;
  end if;
  return new;
end $$;
drop trigger if exists c3_rules_guard on public.rules;
create trigger c3_rules_guard before insert or update on public.rules for each row
  when (new.key in ('marketing_post_on', 'marketing_post_from')) execute function public._c3_rules_guard();

-- ---------- decisions on look-alike lines (append-only) ----------
create table if not exists public.mkt_post_decisions (
  id bigint generated by default as identity primary key,
  entry_id uuid not null references public.entries(id),
  rev_no int not null,
  line_no int not null,
  decision text not null check (decision in ('post', 'skip')),
  reason text not null check (length(btrim(reason)) >= 3 and length(reason) <= 300),
  decided_by uuid, decided_staff text, decided_at timestamptz not null default now()
);
create index if not exists mkt_post_decisions_key on public.mkt_post_decisions (entry_id, rev_no, line_no, id desc);
drop trigger if exists mkt_post_decisions_ro on public.mkt_post_decisions;
create trigger mkt_post_decisions_ro before update or delete on public.mkt_post_decisions for each row execute function public._append_only43();
drop trigger if exists mkt_post_decisions_ro_t on public.mkt_post_decisions;
create trigger mkt_post_decisions_ro_t before truncate on public.mkt_post_decisions for each statement execute function public._append_only43();
alter table public.mkt_post_decisions enable row level security;
revoke all on public.mkt_post_decisions from public, anon, authenticated;
grant select on public.mkt_post_decisions to authenticated;
drop policy if exists mkt_post_decisions_read on public.mkt_post_decisions;
create policy mkt_post_decisions_read on public.mkt_post_decisions for select to authenticated using (public._acct_view() or public._acct_manage());

-- ---------- classification of every approved 18-1 line ----------
create or replace function public._c3_post_lines(d1 date, d2 date, locs int[])
returns table (entry_id uuid, serial int, rev_no int, location_id int, line_no int, day date, head text, campaign_code text, amt numeric, source text, receipt text,
               skey text, cls text, why text, decision text)
language sql stable security definer set search_path = public as $$
  with st as (select public._acct_start() as a, nullif(public.rule_txt('marketing_post_from'), '') as f),
  l as (select * from public._c3_mkt_lines(d1, d2, locs, array['approved']) m where m.amt > 0),
  j as (
    select l.*, l.entry_id::text || ':' || l.rev_no || ':' || l.line_no as k,
           (select dd.decision from public.mkt_post_decisions dd where dd.entry_id = l.entry_id and dd.rev_no = l.rev_no and dd.line_no = l.line_no order by dd.id desc limit 1) as dec,
           exists (select 1 from public.journal_entries je where je.source_type = 'mkt_spend' and je.source_id = l.entry_id::text || ':' || l.rev_no || ':' || l.line_no and je.reverses_id is null
                    and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id)) as posted,
           exists (select 1 from public.entries e2, lateral jsonb_array_elements(case when jsonb_typeof(e2.data -> 'lines') = 'array' then e2.data -> 'lines' else '[]'::jsonb end) x
                    where e2.form_code = '10-2' and e2.status in ('submitted', 'approved') and e2.location_id = l.location_id and e2.entry_date = l.day
                      and x ->> 'head' = 'marketing' and public._r2_num(x -> 'amount') = l.amt)
           or exists (select 1 from public.quick_expenses q where q.status <> 'void' and q.location_id = l.location_id and q.exp_date = l.day and q.head = 'marketing' and q.amount = l.amt) as lookalike
      from l)
  select j.entry_id, j.serial, j.rev_no, j.location_id, j.line_no, j.day, j.head, j.campaign_code, j.amt, j.source, j.receipt, j.k,
    case when j.posted then 'posted'
         when j.dec = 'skip' then 'decided_skip'
         when j.source = 'imprest' then 'skip_imprest'
         when j.source is null then 'needs_source'
         when j.source = 'owner' then 'owner_money'
         when j.source not in ('bank', 'mobile', 'card') then 'needs_source'
         when j.dec is distinct from 'post' and j.lookalike then 'possible_duplicate'
         when (select a from st) is null or (select f from st) is null then 'not_set_up'
         when j.day < (select a from st) or j.day < (select f::date from st) then 'before_start'
         when public._acct_locked(j.day) then 'period_locked'
         else 'to_post' end,
    case when j.source = 'imprest' then 'the imprest money is recorded by its 10-2 voucher'
         when j.lookalike and j.dec is distinct from 'post' then 'a 10-2 voucher or quick expense with the same head, amount, place and date exists' end,
    j.dec
  from j
$$;

-- ---------- preview (no write) ----------
create or replace function public.mkt_post_preview(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; rows_ jsonb; cnt jsonb; st date := public._acct_start(); f text := nullif(public.rule_txt('marketing_post_from'), '');
begin
  if not public.is_active() or not (public.rpt_access('marketing') or public._acct_view() or public._acct_manage()) then raise exception 'not allowed'; end if;
  perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  select coalesce(jsonb_agg(to_jsonb(z) order by z.day, z.serial, z.line_no), '[]'::jsonb) into rows_ from (
    select entry_id, serial, rev_no, location_id, line_no, day, head, campaign_code, amt, source, receipt, cls, why, decision from public._c3_post_lines(p_from, p_to, locs)) z;
  select coalesce(jsonb_object_agg(cls, jsonb_build_object('lines', n, 'amount', a)), '{}'::jsonb) into cnt
    from (select cls, count(*) as n, round(sum(amt), 2) as a from public._c3_post_lines(p_from, p_to, locs) group by 1) c;
  return jsonb_build_object('key', 'mkt_post', 'from', p_from, 'to', p_to, 'loc', p_loc, 'rows', rows_, 'counts', cnt,
    'setting', jsonb_build_object('on', public.rule_on('marketing_post_on'), 'from', f, 'accounting_start', st, 'accounting_on', public.rule_on('accounting_on'),
       'mappings_ok', (select count(*) from public.acct_mappings where key in ('exp_marketing', 'pay_bank', 'pay_mobile')) = 3),
    'notes', jsonb_build_array('approved_sheets_only', 'imprest_never_posted_here', 'look_alikes_wait_for_a_decision', 'owner_money_not_posted', 'management_profit_view_unchanged'),
    'basis', 'Approved 18-1 lines with a paid amount, classified before anything is written. Only "to_post" lines are posted, and only while the setting is ON.');
end $$;

-- a person decides a look-alike (or any) line: post it anyway or skip it for good
create or replace function public.mkt_post_decide(p_entry uuid, p_line int, p_decision text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text; n int;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_decision not in ('post', 'skip') then raise exception 'bad_decision'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  select * into e from public.entries where id = p_entry and form_code = '18-1';
  if not found or e.status <> 'approved' then raise exception 'sheet_not_approved'; end if;
  if not public.can_loc(e.location_id) then raise exception 'not allowed for this location'; end if;
  select jsonb_array_length(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) into n;
  if p_line is null or p_line < 1 or p_line > n then raise exception 'bad_line'; end if;
  if coalesce(public._r2_num(e.data -> 'lines' -> (p_line - 1) -> 'amt'), 0) <= 0 then raise exception 'bad_line'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.mkt_post_decisions (entry_id, rev_no, line_no, decision, reason, decided_by, decided_staff) values (p_entry, e.rev_no, p_line, p_decision, left(btrim(p_reason), 300), auth.uid(), sid);
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'mkt_post_decide', 'entries', p_entry::text, jsonb_build_object('line', p_line, 'rev', e.rev_no, 'decision', p_decision, 'reason', left(btrim(p_reason), 300)));
  return jsonb_build_object('ok', true, 'decision', p_decision);
end $$;

-- ---------- the posting run (dry by default). Posts "to_post" lines; reverses entries whose sheet / revision / line is gone ----------
create or replace function public.mkt_post_run(p_dry boolean default true, p_limit int default 200) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; je record; lim int := least(greatest(coalesce(p_limit, 200), 1), 1000); n int := 0; rv int := 0; locked int := 0; errs jsonb := '[]'; more boolean := false; locs int[];
        lines_ jsonb; credit text; eid bigint; memo text; td date := public._acct_today(); st date := public._acct_start(); f date;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('marketing_post_on') then raise exception 'marketing_post_off'; end if;
  f := nullif(public.rule_txt('marketing_post_from'), '')::date;
  if st is null or f is null then raise exception 'marketing_post_needs_setup'; end if;
  select array_agg(l.id) into locs from public.locations l where public.can_loc(l.id);
  -- 1. reverse entries whose approved line no longer exists in that revision
  for je in select j.* from public.journal_entries j where j.source_type = 'mkt_spend' and j.reverses_id is null
              and not exists (select 1 from public.journal_entries r2 where r2.reverses_id = j.id)
              and not exists (select 1 from public.entries e, lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) with ordinality x(l, ord)
                               where e.form_code = '18-1' and e.status = 'approved' and e.id::text || ':' || e.rev_no || ':' || x.ord = j.source_id and public._r2_num(x.l -> 'amt') > 0)
              order by j.id loop
    if public._acct_locked(greatest(td, je.entry_date)) then locked := locked + 1; continue; end if;
    if not p_dry then perform public._acct_reverse(je.id, td, 'Marketing 18-1 line no longer approved'); end if;
    rv := rv + 1;
  end loop;
  -- 2. post what is classified to_post
  for r in select * from public._c3_post_lines(f, td + 1, coalesce(locs, '{}'::int[])) l where l.cls = 'to_post' order by l.day, l.serial, l.line_no loop
    if n >= lim then more := true; exit; end if;
    credit := case r.source when 'bank' then 'pay_bank' when 'card' then public._acct_paykey('card', true) when 'mobile' then 'pay_mobile' end;
    memo := left('Marketing 18-1 #' || r.serial || ' line ' || r.line_no || ': ' || coalesce(r.head, '') || coalesce(' / ' || r.campaign_code, ''), 300);
    begin
      if not p_dry then
        lines_ := public._acct_resolve(public._acct_merge(jsonb_build_array(jsonb_build_object('a', 'exp_marketing', 'd', r.amt), jsonb_build_object('a', credit, 'c', r.amt))), r.location_id);
        eid := public._acct_write(r.day, r.location_id, 'mkt_spend', r.skey, null, memo, null, lines_);
      end if;
      n := n + 1;
    exception when others then errs := errs || jsonb_build_object('key', r.skey, 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('dry', p_dry, 'posted', n, 'reversed', rv, 'period_locked', locked, 'more', more, 'errors', errs);
end $$;

-- the owner can move everything this file posted back to zero (use before switching the setting off for good); reason required
create or replace function public.mkt_post_wind_down(p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare je record; n int := 0; locked int := 0; td date := public._acct_today(); sid text;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  for je in select j.* from public.journal_entries j where j.source_type = 'mkt_spend' and j.reverses_id is null and not exists (select 1 from public.journal_entries r2 where r2.reverses_id = j.id) order by j.id loop
    if public._acct_locked(greatest(td, je.entry_date)) then locked := locked + 1; continue; end if;
    perform public._acct_reverse(je.id, td, 'Marketing posting wound down: ' || left(btrim(p_reason), 150)); n := n + 1;
  end loop;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail) values (auth.uid(), sid, 'mkt_post_wind_down', 'journal_entries', 'mkt_spend', jsonb_build_object('reversed', n, 'locked', locked, 'reason', left(btrim(p_reason), 300)));
  return jsonb_build_object('reversed', n, 'period_locked', locked);
end $$;

revoke all on function public._c3_rules_guard(), public._c3_post_lines(date, date, int[]) from public, anon, authenticated;
revoke all on function public.mkt_post_preview(date, date, int), public.mkt_post_decide(uuid, int, text, text), public.mkt_post_run(boolean, int), public.mkt_post_wind_down(text) from public, anon;
grant execute on function public.mkt_post_preview(date, date, int), public.mkt_post_decide(uuid, int, text, text), public.mkt_post_run(boolean, int), public.mkt_post_wind_down(text) to authenticated;
notify pgrst, 'reload schema';
