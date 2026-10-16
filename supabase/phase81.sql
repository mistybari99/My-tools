-- Phase 81 (bos81) - SHORTAGES: G4 hub/count cash short, G5 customer advance check, G6 transit short.
-- Paste AFTER phase79 (phase80 is a different, independent file). Additive and paste-twice safe: create or replace / if not exists / on conflict do nothing.
-- It edits NO existing function. The new journal sources are served by ONE new function, public._b_docs(date), which has exactly the columns of
-- public._acct_docs(date). The integrator adds one line to _acct_docs (see docs/integration/B.md). Until then, public.b_post_pending() posts them itself.
--
-- G4  shortage_cash_cases   one case per cash count with a short/over (made by a trigger on exceptions flag cash_short_over). Nothing posts until the
--                           owner approves. Source 'cash_short' (count date). short: Dr cash short/over 5800, Cr cash. over: Dr cash, Cr 5800.
--                           Owner setting cash_short_treatment 'staff_receivable' books a SHORT as Dr staff advances (1220, the named employee) instead of expense.
-- G5  cust_advance_check()  read-only: customer advance held per cash moves vs per journal account 2300. The posting already exists (phase40/52/79).
-- G6  shortage_transit      one row per transfer received short (trigger on stock_transfers). Value from the ledger cost at send. Owner decides:
--                           claim to carrier (Dr 1240 receivable from carrier, Cr inventory), recover (Dr cash/bank/mobile, Cr 1240),
--                           write off (Dr loss 5100, Cr inventory, or Cr 1240 after a claim). Every step is an append-only event = one journal source.
-- Owner decisions NOT guessed, all are rules with a safe default:
--   cash_short_post_on        OFF   (approved cases wait, nothing is posted)
--   cash_short_treatment      expense | staff_receivable   default expense
--   short_decider             owner | accounts_manager     default owner
--   transit_short_bearer      ask | carrier | shop         default ask (owner picks claim or write-off case by case)

do $g$ begin
  if to_regprocedure('public._acct_docs(date)') is null or to_regprocedure('public._acct_write(date,integer,text,text,text,text,text,jsonb,bigint,uuid,text)') is null
     or to_regclass('public.stock_transfers') is null or to_regclass('public.exceptions') is null or to_regclass('public.rules') is null then
    raise exception 'phase81 needs the accounts (phase40) and stock (phase10) phases pasted first';
  end if;
end $g$;

-- ---------- chart: 1240 Receivable from carrier (take 1240 unless the code is used for something else) ----------
do $seed$ declare code_ text;
begin
  if not exists (select 1 from public.coa_accounts where code = '1240' and name_en = 'Receivable from carrier') then
    code_ := case when exists (select 1 from public.coa_accounts where code = '1240') then '1245' else '1240' end;
    insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, is_group, is_system, sort, parent_id)
      select code_, 'বাহকের কাছে পাওনা (পথে কম)', 'Receivable from carrier', 'asset', 'debit', false, true, 24, (select id from public.coa_accounts where code = '1200')
       where not exists (select 1 from public.coa_accounts where code = code_);
  end if;
end $seed$;

insert into public.acct_mappings (key, account_id, label_bn, label_en)
select v.k, a.id, v.lb, v.le from (values
  ('cash_short', '5800', 'ক্যাশ কম / বেশি', 'Cash short / over'),
  ('transit_loss', '5100', 'পথে কমে যাওয়া মালের ক্ষতি', 'Loss on goods short in transit')
) as v(k, c, lb, le) join public.coa_accounts a on a.code = v.c
on conflict (key) do nothing;
insert into public.acct_mappings (key, account_id, label_bn, label_en)
select 'carrier_claim', a.id, 'বাহকের কাছে পাওনা', 'Receivable from carrier' from public.coa_accounts a where a.name_en = 'Receivable from carrier' and a.is_system
on conflict (key) do nothing;

-- ---------- owner settings (rules) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('cash_short_post_on', 'books', 'switch', 'false', null, null, null, null, 'ক্যাশ কম/বেশি অনুমোদনের পর খাতায় লিখুন', 'Cash কম/বেশি approve হলে খাতায় লিখুন', 'Post an approved cash short/over to the books',
  'বন্ধ থাকলে অনুমোদিত কেস অপেক্ষায় থাকে, খাতায় কিছু লেখা হয় না।', 'Off = approved cases wait and nothing is posted.', 820),
 ('cash_short_treatment', 'books', 'choice', '"expense"', null, '["expense","staff_receivable"]', null, null, 'ক্যাশ ঘাটতি কীভাবে ধরা হবে', 'Cash ঘাটতি কীভাবে ধরা হবে', 'How a cash SHORT is booked',
  'expense = ক্যাশ কম/বেশি খরচ (৫৮০০)। staff_receivable = নির্দিষ্ট কর্মীর কাছে পাওনা (১২২০)। বেশি হলে সবসময় ৫৮০০।', 'expense = cash short/over account (5800). staff_receivable = owed by the named employee (1220). An OVER always goes to 5800.', 821),
 ('short_decider', 'books', 'choice', '"owner"', null, '["owner","accounts_manager"]', null, null, 'কম/বেশির সিদ্ধান্ত কে নেবে', 'কম/বেশির সিদ্ধান্ত কে নেবে', 'Who decides cash short and transit short cases',
  'owner = শুধু মালিক। accounts_manager = হিসাবের ম্যানেজ অনুমতিওয়ালাও।', 'owner = only the owner. accounts_manager = also people with the accounts manage grant. Nobody decides a count they made themselves.', 822),
 ('transit_short_bearer', 'books', 'choice', '"ask"', null, '["ask","carrier","shop"]', null, null, 'পথে কম মালের ক্ষতি কে বহন করবে', 'পথে কম মালের loss কে বহন করবে', 'Who bears goods short in transit',
  'ask = প্রতিটি কেসে মালিক ঠিক করেন। carrier = আগে বাহকের কাছে দাবি করতে হবে। shop = দাবি নয়, সরাসরি ক্ষতি।', 'ask = the owner chooses per case. carrier = claim to the carrier first (no direct write-off). shop = no claim, write off as loss.', 823)
on conflict (key) do nothing;

-- ---------- tables ----------
create table if not exists public.shortage_cash_cases (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null unique references public.entries(id),
  form_code text,
  location_id int not null references public.locations(id),
  case_date date not null,                                        -- the count date: the journal date
  amount numeric not null check (amount <> 0),                    -- signed: counted minus expected. negative = SHORT, positive = OVER
  reason text,
  status text not null default 'open' check (status in ('open', 'approved', 'rejected', 'void')),
  treatment text check (treatment is null or treatment in ('expense', 'staff_receivable')),   -- frozen when approved
  employee_id uuid references public.employees(id),
  decided_by uuid, decided_at timestamptz, decide_note text,
  void_by uuid, void_at timestamptz, void_note text,
  created_at timestamptz not null default now(),
  check (treatment <> 'staff_receivable' or employee_id is not null)
);
create index if not exists shortage_cash_status on public.shortage_cash_cases (status, case_date);

create table if not exists public.shortage_transit (
  id uuid primary key default gen_random_uuid(),
  transfer_id uuid not null unique references public.stock_transfers(id),
  item_id uuid not null references public.items(id),
  from_location_id int not null references public.locations(id),
  to_location_id int not null references public.locations(id),
  qty_short numeric not null check (qty_short > 0),
  value numeric check (value is null or value > 0),               -- cost at send. null = cost missing: nothing posts until the owner enters a cost
  value_source text check (value_source is null or value_source in ('ledger', 'owner')),
  status text not null default 'open' check (status in ('open', 'claimed', 'recovered', 'written_off')),
  claimed_amount numeric not null default 0 check (claimed_amount >= 0),
  recovered_amount numeric not null default 0 check (recovered_amount >= 0),
  written_off_amount numeric not null default 0 check (written_off_amount >= 0),
  received_on date not null,
  decided_by uuid, decided_at timestamptz, note text,
  created_at timestamptz not null default now()
);
create index if not exists shortage_transit_status on public.shortage_transit (status);

create table if not exists public.shortage_transit_events (
  id uuid primary key default gen_random_uuid(),
  shortage_id uuid not null references public.shortage_transit(id),
  kind text not null check (kind in ('claim', 'recover', 'writeoff')),
  amount numeric not null check (amount > 0),
  mode text check (mode is null or mode in ('cash', 'bank', 'mobile')),
  against_claim boolean not null default false,                   -- a write-off made after a claim (Cr 1240 instead of inventory)
  location_id int not null references public.locations(id),
  event_date date not null,
  note text not null check (length(btrim(note)) >= 3),
  created_by uuid, created_at timestamptz not null default now(),
  check ((kind = 'recover') = (mode is not null))
);
create unique index if not exists shortage_one_claim on public.shortage_transit_events (shortage_id) where kind = 'claim';
create index if not exists shortage_events_sh on public.shortage_transit_events (shortage_id);

create or replace function public._b_events_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: shortage events are a record, they cannot be changed or deleted'; end $$;
drop trigger if exists shortage_events_ro on public.shortage_transit_events;
create trigger shortage_events_ro before update or delete on public.shortage_transit_events for each row execute function public._b_events_ro();
drop trigger if exists shortage_events_ro_t on public.shortage_transit_events;
create trigger shortage_events_ro_t before truncate on public.shortage_transit_events for each statement execute function public._b_events_ro();

drop trigger if exists audit_shortage_cash on public.shortage_cash_cases;
create trigger audit_shortage_cash after insert or update on public.shortage_cash_cases for each row execute function public.log_change('id');
drop trigger if exists audit_shortage_transit on public.shortage_transit;
create trigger audit_shortage_transit after insert or update on public.shortage_transit for each row execute function public.log_change('id');
drop trigger if exists audit_shortage_events on public.shortage_transit_events;
create trigger audit_shortage_events after insert on public.shortage_transit_events for each row execute function public.log_change('id');

alter table public.shortage_cash_cases enable row level security;
alter table public.shortage_transit enable row level security;
alter table public.shortage_transit_events enable row level security;
drop policy if exists shortage_cash_read on public.shortage_cash_cases;
create policy shortage_cash_read on public.shortage_cash_cases for select to authenticated using (public._acct_view() and public.can_loc(location_id));
drop policy if exists shortage_transit_read on public.shortage_transit;
create policy shortage_transit_read on public.shortage_transit for select to authenticated using (public._acct_view() and (public.can_loc(from_location_id) or public.can_loc(to_location_id)));
drop policy if exists shortage_events_read on public.shortage_transit_events;
create policy shortage_events_read on public.shortage_transit_events for select to authenticated using (public._acct_view() and public.can_loc(location_id));
revoke all on public.shortage_cash_cases, public.shortage_transit, public.shortage_transit_events from public, anon, authenticated;
grant select on public.shortage_cash_cases, public.shortage_transit, public.shortage_transit_events to authenticated;

-- ---------- helpers ----------
create or replace function public._b_may_decide() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or (coalesce(public.rule_txt('short_decider'), 'owner') = 'accounts_manager' and public._acct_manage()));
$$;

-- every posting line set must balance; refuse otherwise (used before a decision is stored and by the tests)
create or replace function public._b_assert_balanced(p_lines jsonb) returns void language plpgsql immutable set search_path = public as $$
declare d numeric := 0; c numeric := 0; e jsonb;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 2 then raise exception 'need_two_lines'; end if;
  for e in select * from jsonb_array_elements(p_lines) loop
    d := d + coalesce(nullif(e->>'d', '')::numeric, 0); c := c + coalesce(nullif(e->>'c', '')::numeric, 0);
  end loop;
  if d <> c or d <= 0 then raise exception 'unbalanced' using detail = 'debit ' || d::text || ' credit ' || c::text; end if;
end $$;

create or replace function public._b_need_map(p_key text) returns void language plpgsql stable security definer set search_path = public as $$
begin if not exists (select 1 from public.acct_mappings where key = p_key) then raise exception 'mapping_missing:%', p_key; end if; end $$;

create or replace function public._b_check_date(p_date date) returns void language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start();
begin
  if st is null then raise exception 'data_needed'; end if;
  if p_date is null or p_date > public._acct_today() then raise exception 'bad_date'; end if;
  if p_date < st then raise exception 'before_start'; end if;
  if public._acct_locked(p_date) then raise exception 'period_locked'; end if;
end $$;

-- ---------- G4: a case is made for every cash_short_over exception ----------
create or replace function public._b_cash_case_trg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.flag_code = 'cash_short_over' and coalesce(new.amount, 0) <> 0 then
    insert into public.shortage_cash_cases (entry_id, form_code, location_id, case_date, amount)
      values (new.entry_id, new.form_code, new.location_id, new.entry_date, new.amount)
      on conflict (entry_id) do update set amount = excluded.amount, case_date = excluded.case_date, location_id = excluded.location_id
        where public.shortage_cash_cases.status = 'open';
  end if;
  return null;
end $$;
drop trigger if exists exceptions_cash_case on public.exceptions;
create trigger exceptions_cash_case after insert on public.exceptions for each row execute function public._b_cash_case_trg();

-- owner: make cases for short/over exceptions that existed before this phase (not automatic)
create or replace function public.cash_short_backfill() returns jsonb language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  with ins as (
    insert into public.shortage_cash_cases (entry_id, form_code, location_id, case_date, amount)
    select distinct on (x.entry_id) x.entry_id, x.form_code, x.location_id, x.entry_date, x.amount from public.exceptions x
     where x.flag_code = 'cash_short_over' and coalesce(x.amount, 0) <> 0 order by x.entry_id, x.id desc
    on conflict (entry_id) do nothing returning 1)
  select count(*) into n from ins;
  return jsonb_build_object('made', n);
end $$;

create or replace function public.cash_short_list(p_status text default null, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(j order by j->>'case_date' desc, j->>'created_at' desc) from (
    select jsonb_build_object('id', c.id, 'entry_id', c.entry_id, 'form_code', c.form_code, 'location_id', c.location_id, 'location', coalesce(l.name_en, l.name_bn),
      'case_date', c.case_date, 'amount', c.amount, 'kind', case when c.amount < 0 then 'short' else 'over' end, 'status', c.status, 'treatment', c.treatment,
      'employee_id', c.employee_id, 'decide_note', c.decide_note, 'decided_at', c.decided_at, 'created_at', c.created_at,
      'posted', exists (select 1 from public.journal_entries e where e.source_type = 'cash_short' and e.source_id = c.id::text and e.reverses_id is null),
      'can_decide', public._b_may_decide() and c.status = 'open') j
    from public.shortage_cash_cases c left join public.locations l on l.id = c.location_id
    where public.can_loc(c.location_id) and (p_status is null or c.status = p_status)
    order by c.case_date desc, c.created_at desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) q), '[]'::jsonb);
end $$;

create or replace function public.cash_short_decide(p_id uuid, p_approve boolean, p_note text, p_employee uuid default null, p_force boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.shortage_cash_cases; en public.entries; tr text; dup boolean := false; lines jsonb; a numeric;
begin
  if p_approve is null then raise exception 'bad_input'; end if;
  if not public._b_may_decide() then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into c from public.shortage_cash_cases where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(c.location_id) then raise exception 'not allowed for this location'; end if;
  if c.status <> 'open' then raise exception 'already_decided'; end if;
  select * into en from public.entries where id = c.entry_id;
  if en.created_by = auth.uid() and not public.is_owner() then raise exception 'own_count'; end if;   -- nobody decides the count they made
  if not p_approve then
    update public.shortage_cash_cases set status = 'rejected', decided_by = auth.uid(), decided_at = now(), decide_note = left(btrim(p_note), 300) where id = c.id;
    return jsonb_build_object('id', c.id, 'status', 'rejected');
  end if;
  a := abs(c.amount);
  tr := coalesce(public.rule_txt('cash_short_treatment'), 'expense');
  if c.amount > 0 then tr := 'expense'; end if;                    -- an over always goes to the cash short/over account
  if tr = 'staff_receivable' and (p_employee is null or not exists (select 1 from public.employees where id = p_employee)) then raise exception 'employee_required'; end if;
  perform public._b_need_map('cash_short'); perform public._b_need_map('pay_cash');
  if tr = 'staff_receivable' then perform public._b_need_map('staff_advance'); end if;
  perform public._b_check_date(c.case_date);
  lines := public._b_cash_lines(c.amount, tr, p_employee);
  perform public._b_assert_balanced(lines);
  -- double count warning (a manual journal for the same short on the same day and place)
  select exists (select 1 from public.journal_entries e join public.journal_lines l on l.entry_id = e.id
                   where e.entry_date = c.case_date and e.location_id = c.location_id and e.source_type = 'manual' and e.reverses_id is null
                     and l.account_id = (select account_id from public.acct_mappings where key = 'cash_short')) into dup;
  if dup and not coalesce(p_force, false) then raise exception 'possible_duplicate' using hint = 'a manual journal for cash short/over already exists on this day and place; repeat with p_force = true if it is a different amount'; end if;
  update public.shortage_cash_cases set status = 'approved', treatment = tr, employee_id = case when tr = 'staff_receivable' then p_employee end,
    decided_by = auth.uid(), decided_at = now(), decide_note = left(btrim(p_note), 300) where id = c.id;
  return jsonb_build_object('id', c.id, 'status', 'approved', 'amount', c.amount, 'treatment', tr, 'duplicate_warning', dup, 'posts_now', public.rule_on('cash_short_post_on'));
end $$;

create or replace function public.cash_short_void(p_id uuid, p_note text) returns jsonb language plpgsql security definer set search_path = public as $$
declare c public.shortage_cash_cases;
begin
  if not public._b_may_decide() then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into c from public.shortage_cash_cases where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(c.location_id) then raise exception 'not allowed for this location'; end if;
  if c.status <> 'approved' then raise exception 'not_approved'; end if;
  update public.shortage_cash_cases set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = c.id;
  return jsonb_build_object('id', c.id, 'status', 'void');
end $$;

-- the two journal sides of a case (keys resolve through acct_mappings)
create or replace function public._b_cash_lines(p_amount numeric, p_treatment text, p_employee uuid) returns jsonb language sql immutable set search_path = public as $$
  select case
    when p_amount < 0 and p_treatment = 'staff_receivable' then jsonb_build_array(jsonb_build_object('a', 'staff_advance', 'd', abs(p_amount), 'pt', 'staff', 'pid', p_employee::text), jsonb_build_object('a', 'pay_cash', 'c', abs(p_amount)))
    when p_amount < 0 then jsonb_build_array(jsonb_build_object('a', 'cash_short', 'd', abs(p_amount)), jsonb_build_object('a', 'pay_cash', 'c', abs(p_amount)))
    else jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', abs(p_amount)), jsonb_build_object('a', 'cash_short', 'c', abs(p_amount))) end;
$$;

-- ---------- G6: a row for every transfer received short ----------
create or replace function public._b_transit_make(p_transfer uuid) returns uuid language plpgsql security definer set search_path = public as $$
declare t public.stock_transfers; ov numeric; iv numeric; miss boolean; v numeric; id_ uuid;
begin
  select * into t from public.stock_transfers where id = p_transfer;
  if not found or t.status <> 'received' or t.received_qty is null or t.received_qty >= t.qty then return null; end if;
  select coalesce(sum(-l.qty_delta * coalesce(l.unit_cost, 0)), 0), count(*) = 0 or bool_or(coalesce(l.unit_cost, 0) <= 0) into ov, miss
    from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = t.id::text and l.reason = 'transfer_out';
  select coalesce(sum(l.qty_delta * coalesce(l.unit_cost, 0)), 0), miss or coalesce(bool_or(coalesce(l.unit_cost, 0) <= 0), false) into iv, miss
    from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = t.id::text and l.reason = 'transfer_in';
  v := round(ov - iv, 2);
  if miss or v <= 0 then v := null; end if;                        -- unknown cost stays unknown, never guessed
  insert into public.shortage_transit (transfer_id, item_id, from_location_id, to_location_id, qty_short, value, value_source, received_on)
    values (t.id, t.item_id, t.from_location_id, t.to_location_id, t.qty - t.received_qty, v, case when v is not null then 'ledger' end,
            coalesce((t.received_at at time zone 'Asia/Dhaka')::date, public._acct_today()))
    on conflict (transfer_id) do nothing returning id into id_;
  return id_;
end $$;
create or replace function public._b_transit_trg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'received' and old.status is distinct from 'received' then perform public._b_transit_make(new.id); end if;
  return null;
end $$;
drop trigger if exists stock_transfers_short on public.stock_transfers;
create trigger stock_transfers_short after update on public.stock_transfers for each row execute function public._b_transit_trg();

create or replace function public.transit_short_backfill() returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  for r in select id from public.stock_transfers where status = 'received' and received_qty < qty loop
    if public._b_transit_make(r.id) is not null then n := n + 1; end if;
  end loop;
  return jsonb_build_object('made', n);
end $$;

create or replace function public.transit_short_list(p_status text default null, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(j order by j->>'received_on' desc) from (
    select jsonb_build_object('id', s.id, 'transfer_id', s.transfer_id, 'item_id', s.item_id, 'item_bn', i.name_bn, 'item_en', coalesce(i.name_en, i.name_bn),
      'from_location_id', s.from_location_id, 'to_location_id', s.to_location_id, 'from_name', coalesce(lf.name_en, lf.name_bn), 'to_name', coalesce(lt.name_en, lt.name_bn),
      'qty_short', s.qty_short, 'value', s.value, 'cost_missing', s.value is null, 'status', s.status, 'claimed_amount', s.claimed_amount, 'recovered_amount', s.recovered_amount,
      'written_off_amount', s.written_off_amount, 'outstanding_claim', s.claimed_amount - s.recovered_amount - (select coalesce(sum(e.amount), 0) from public.shortage_transit_events e where e.shortage_id = s.id and e.kind = 'writeoff' and e.against_claim),
      'received_on', s.received_on, 'note', s.note, 'bearer_rule', coalesce(public.rule_txt('transit_short_bearer'), 'ask'), 'can_decide', public._b_may_decide() and s.status in ('open', 'claimed')) j
    from public.shortage_transit s join public.items i on i.id = s.item_id
    left join public.locations lf on lf.id = s.from_location_id left join public.locations lt on lt.id = s.to_location_id
    where (public.can_loc(s.from_location_id) or public.can_loc(s.to_location_id)) and (p_status is null or s.status = p_status)
    order by s.received_on desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) q), '[]'::jsonb);
end $$;

-- one place for the checks every transit decision shares; returns the locked row
create or replace function public._b_transit_pick(p_id uuid, p_note text, p_date date) returns public.shortage_transit language plpgsql security definer set search_path = public as $$
declare s public.shortage_transit;
begin
  if not public._b_may_decide() then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into s from public.shortage_transit where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not (public.can_loc(s.from_location_id) or public.can_loc(s.to_location_id)) then raise exception 'not allowed for this location'; end if;
  if s.status in ('recovered', 'written_off') then raise exception 'already_decided'; end if;
  if s.value is null then raise exception 'cost_missing'; end if;
  if p_date is not null and p_date < s.received_on then raise exception 'bad_date'; end if;
  perform public._b_check_date(coalesce(p_date, public._acct_today()));
  return s;
end $$;

create or replace function public.transit_short_set_cost(p_id uuid, p_unit_cost numeric, p_note text) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.shortage_transit;
begin
  if not public._b_may_decide() then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  if p_unit_cost is null or not (p_unit_cost > 0 and p_unit_cost <= 1000000000) then raise exception 'bad_amount'; end if;
  select * into s from public.shortage_transit where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if s.status <> 'open' then raise exception 'already_decided'; end if;
  if s.value is not null then raise exception 'cost_known'; end if;
  update public.shortage_transit set value = round(p_unit_cost * qty_short, 2), value_source = 'owner', note = left(btrim(p_note), 300) where id = s.id;
  return jsonb_build_object('id', s.id, 'value', round(p_unit_cost * s.qty_short, 2));
end $$;

create or replace function public.transit_short_claim(p_id uuid, p_note text, p_date date default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.shortage_transit; d date := coalesce(p_date, public._acct_today()); ev uuid := gen_random_uuid(); it text;
begin
  s := public._b_transit_pick(p_id, p_note, p_date);
  if s.status <> 'open' then raise exception 'already_decided'; end if;
  if coalesce(public.rule_txt('transit_short_bearer'), 'ask') = 'shop' then raise exception 'shop_bears'; end if;
  perform public._b_need_map('carrier_claim');
  select item_type into it from public.items where id = s.item_id; perform public._b_need_map(public._acct_inv_key(it));
  perform public._b_assert_balanced(public._b_transit_lines('claim', s.value, null, false, it));
  insert into public.shortage_transit_events (id, shortage_id, kind, amount, against_claim, location_id, event_date, note, created_by)
    values (ev, s.id, 'claim', s.value, false, s.from_location_id, d, left(btrim(p_note), 300), auth.uid());
  update public.shortage_transit set status = 'claimed', claimed_amount = s.value, decided_by = auth.uid(), decided_at = now(), note = left(btrim(p_note), 300) where id = s.id;
  return jsonb_build_object('id', s.id, 'status', 'claimed', 'event_id', ev, 'amount', s.value);
end $$;

create or replace function public.transit_short_recover(p_id uuid, p_amount numeric, p_mode text, p_note text, p_date date default null, p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.shortage_transit; d date := coalesce(p_date, public._acct_today()); ev uuid := gen_random_uuid(); out_ numeric; loc int; it text;
begin
  s := public._b_transit_pick(p_id, p_note, p_date);
  if s.status <> 'claimed' then raise exception 'not_claimed'; end if;
  if p_mode is null or p_mode not in ('cash', 'bank', 'mobile') then raise exception 'bad_mode'; end if;
  select s.claimed_amount - s.recovered_amount - coalesce(sum(e.amount), 0) into out_ from public.shortage_transit_events e where e.shortage_id = s.id and e.kind = 'writeoff' and e.against_claim;
  p_amount := round(coalesce(p_amount, out_), 2);
  if p_amount is null or p_amount <= 0 or p_amount > out_ then raise exception 'bad_amount' using detail = 'outstanding ' || out_::text; end if;
  loc := coalesce(p_loc, s.from_location_id);
  if not public.can_loc(loc) then raise exception 'not allowed for this location'; end if;
  perform public._b_need_map('carrier_claim'); perform public._b_need_map(public._acct_paykey(p_mode));
  perform public._b_assert_balanced(public._b_transit_lines('recover', p_amount, p_mode, false, null));
  insert into public.shortage_transit_events (id, shortage_id, kind, amount, mode, location_id, event_date, note, created_by)
    values (ev, s.id, 'recover', p_amount, p_mode, loc, d, left(btrim(p_note), 300), auth.uid());
  update public.shortage_transit set recovered_amount = s.recovered_amount + p_amount, decided_by = auth.uid(), decided_at = now(),
    status = case when out_ - p_amount = 0 then 'recovered' else 'claimed' end where id = s.id;
  return jsonb_build_object('id', s.id, 'status', case when out_ - p_amount = 0 then 'recovered' else 'claimed' end, 'event_id', ev, 'amount', p_amount, 'outstanding', out_ - p_amount);
end $$;

create or replace function public.transit_short_writeoff(p_id uuid, p_note text, p_date date default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.shortage_transit; d date := coalesce(p_date, public._acct_today()); ev uuid := gen_random_uuid(); amt numeric; ac boolean; it text; bearer text := coalesce(public.rule_txt('transit_short_bearer'), 'ask');
begin
  s := public._b_transit_pick(p_id, p_note, p_date);
  ac := s.status = 'claimed';
  if not ac and bearer = 'carrier' then raise exception 'claim_first'; end if;
  if ac then
    select s.claimed_amount - s.recovered_amount - coalesce(sum(e.amount), 0) into amt from public.shortage_transit_events e where e.shortage_id = s.id and e.kind = 'writeoff' and e.against_claim;
  else amt := s.value; end if;
  if amt is null or amt <= 0 then raise exception 'bad_amount'; end if;
  select item_type into it from public.items where id = s.item_id;
  perform public._b_need_map('transit_loss'); perform public._b_need_map(case when ac then 'carrier_claim' else public._acct_inv_key(it) end);
  perform public._b_assert_balanced(public._b_transit_lines('writeoff', amt, null, ac, it));
  insert into public.shortage_transit_events (id, shortage_id, kind, amount, against_claim, location_id, event_date, note, created_by)
    values (ev, s.id, 'writeoff', amt, ac, s.from_location_id, d, left(btrim(p_note), 300), auth.uid());
  update public.shortage_transit set status = 'written_off', written_off_amount = amt, decided_by = auth.uid(), decided_at = now(), note = left(btrim(p_note), 300) where id = s.id;
  return jsonb_build_object('id', s.id, 'status', 'written_off', 'event_id', ev, 'amount', amt);
end $$;

create or replace function public._b_transit_lines(p_kind text, p_amount numeric, p_mode text, p_against_claim boolean, p_item_type text) returns jsonb language sql immutable set search_path = public as $$
  select case p_kind
    when 'claim' then jsonb_build_array(jsonb_build_object('a', 'carrier_claim', 'd', p_amount), jsonb_build_object('a', public._acct_inv_key(p_item_type), 'c', p_amount))
    when 'recover' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(p_mode), 'd', p_amount), jsonb_build_object('a', 'carrier_claim', 'c', p_amount))
    else jsonb_build_array(jsonb_build_object('a', 'transit_loss', 'd', p_amount), jsonb_build_object('a', case when p_against_claim then 'carrier_claim' else public._acct_inv_key(p_item_type) end, 'c', p_amount)) end;
$$;

-- ---------- the journal source: same columns as _acct_docs, the integrator calls it from there (docs/integration/B.md) ----------
create or replace function public._b_docs(p_start date) returns table(
  source_type text, source_id text, entry_date date, location_id int, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
language plpgsql stable security definer set search_path = public as $fn$
begin
  -- G4: an approved cash short / over (a voided one is reversed)
  return query
  select 'cash_short'::text, c.id::text, c.case_date, c.location_id,
    ('Cash ' || case when c.amount < 0 then 'short' else 'over' end || ' at count ' || c.case_date::text)::text, null::text,
    c.status = 'approved', (c.void_at at time zone 'Asia/Dhaka')::date, null::text,
    case when c.status = 'approved' and not public.rule_on('cash_short_post_on') then 'cash_short_post_off' end,
    public._b_cash_lines(c.amount, coalesce(c.treatment, 'expense'), c.employee_id)
  from public.shortage_cash_cases c
  where c.case_date >= p_start and c.status in ('approved', 'void') and public._acct_need('cash_short', c.id::text, c.status = 'approved');

  -- G6: claim / recover / write-off events (append-only, never voided)
  return query
  select ('transit_' || e.kind)::text, e.id::text, e.event_date, e.location_id,
    (case e.kind when 'claim' then 'Transit short claimed from carrier' when 'recover' then 'Transit short recovered from carrier' else 'Transit short written off' end)::text, null::text,
    true, null::date, null::text, null::text,
    public._b_transit_lines(e.kind, e.amount, e.mode, e.against_claim, it.item_type)
  from public.shortage_transit_events e join public.shortage_transit s on s.id = e.shortage_id join public.items it on it.id = s.item_id
  where e.event_date >= p_start and public._acct_need('transit_' || e.kind, e.id::text, true);
end $fn$;

-- standalone poster for these sources (same rules as acct_post_pending). Not needed once the one-line hook is in _acct_docs.
create or replace function public.b_post_pending(p_dry boolean default false) returns jsonb language plpgsql security definer set search_path = public as $$
declare st date := public._acct_start(); d record; ln jsonb; orig public.journal_entries; rdate date; posted int := 0; rev int := 0; locked int := 0; waiting int := 0; errors jsonb := '[]';
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true, 'dry', p_dry); end if;
  if not p_dry and not public.rule_on('accounting_on') then raise exception 'accounting_off'; end if;
  if not p_dry then perform pg_advisory_xact_lock(hashtextextended('acct_post', 0)); end if;
  for d in select * from public._b_docs(st) order by 3, 1, 2 loop
    if d.waiting is not null then waiting := waiting + 1; continue; end if;
    begin
      if d.live then
        if public._acct_locked(d.entry_date) then locked := locked + 1; continue; end if;
        ln := public._acct_resolve(public._acct_merge(d.lines), d.location_id);
        if not p_dry then perform public._acct_write(d.entry_date, d.location_id, d.source_type, d.source_id, d.subtype, d.memo, d.flags, ln); end if;
        posted := posted + 1;
      else
        select * into orig from public.journal_entries o where o.source_type = d.source_type and o.source_id = d.source_id and o.reverses_id is null;
        rdate := greatest(coalesce(d.void_date, public._acct_today()), orig.entry_date);
        if public._acct_locked(rdate) then locked := locked + 1; continue; end if;
        if not p_dry then perform public._acct_reverse(orig.id, rdate, 'Reversal: ' || orig.memo); end if;
        rev := rev + 1;
      end if;
    exception when others then
      errors := errors || jsonb_build_object('source_type', d.source_type, 'source_id', d.source_id, 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('dry', p_dry, 'posted', posted, 'reversed', rev, 'locked', locked, 'waiting', waiting, 'errors', errors);
end $$;

-- ---------- G5: customer advance held, cash moves vs journal 2300 (read only) ----------
create or replace function public.cust_advance_check() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); adv bigint; rows_ jsonb; tot_j numeric; tot_m numeric;
begin
  if not public._acct_view() or not public._acct_all() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  select account_id into adv from public.acct_mappings where key = 'cust_advance';
  if adv is null then raise exception 'mapping_missing:cust_advance'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('customer_id', x.cid, 'name', x.nm, 'journal', x.j, 'cash_moves', x.m, 'difference', x.j - x.m) order by abs(x.j - x.m) desc), '[]'::jsonb)
    into rows_ from (
      select c.id::text cid, c.name nm, coalesce(j.bal, 0) j, coalesce(m.bal, 0) m
        from public.customers c
        left join (select party_id, sum(credit - debit) bal from public.journal_lines where account_id = adv and party_type = 'customer' group by party_id) j on j.party_id = c.id::text
        left join (select customer_id, sum(case when kind = 'cust_advance' then amount else -amount end) bal from public.cash_moves
                    where status = 'done' and kind like 'cust_advance%' and move_date >= st group by customer_id) m on m.customer_id = c.id
       where coalesce(j.bal, 0) <> 0 or coalesce(m.bal, 0) <> 0) x
    where abs(x.j - x.m) > 0.005;
  select coalesce(sum(credit - debit), 0) into tot_j from public.journal_lines where account_id = adv;
  select coalesce(sum(case when kind = 'cust_advance' then amount else -amount end), 0) into tot_m from public.cash_moves where status = 'done' and kind like 'cust_advance%' and move_date >= st;
  return jsonb_build_object('start', st, 'account_total_journal', tot_j, 'account_total_cash_moves', tot_m, 'difference', tot_j - tot_m, 'customers_off', rows_,
    'note', 'Cash moves before the accounting start date are not in the books; a difference equal to such an old advance is expected until an opening balance is posted.');
end $$;

-- ---------- privileges ----------
revoke all on function public._b_events_ro(), public._b_assert_balanced(jsonb), public._b_need_map(text), public._b_check_date(date), public._b_may_decide(),
  public._b_cash_case_trg(), public._b_cash_lines(numeric, text, uuid), public._b_transit_make(uuid), public._b_transit_trg(), public._b_transit_pick(uuid, text, date),
  public._b_transit_lines(text, numeric, text, boolean, text), public._b_docs(date) from public, anon, authenticated;
revoke all on function public.cash_short_backfill(), public.cash_short_list(text, int), public.cash_short_decide(uuid, boolean, text, uuid, boolean), public.cash_short_void(uuid, text),
  public.transit_short_backfill(), public.transit_short_list(text, int), public.transit_short_set_cost(uuid, numeric, text), public.transit_short_claim(uuid, text, date),
  public.transit_short_recover(uuid, numeric, text, text, date, int), public.transit_short_writeoff(uuid, text, date), public.b_post_pending(boolean), public.cust_advance_check() from public, anon;
grant execute on function public.cash_short_backfill(), public.cash_short_list(text, int), public.cash_short_decide(uuid, boolean, text, uuid, boolean), public.cash_short_void(uuid, text),
  public.transit_short_backfill(), public.transit_short_list(text, int), public.transit_short_set_cost(uuid, numeric, text), public.transit_short_claim(uuid, text, date),
  public.transit_short_recover(uuid, numeric, text, text, date, int), public.transit_short_writeoff(uuid, text, date), public.b_post_pending(boolean), public.cust_advance_check() to authenticated;
