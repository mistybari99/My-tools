-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase95.sql there and is already pasted on the live database under that name.
-- Renumbered to phase521.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 521 (bos95) - STEP Drw: an OPTION so a cash drawer can be connected later. (phase520 is reserved for the security step.)
--   Needs only the base schema + phase 8 (guard below). Additive, paste-twice safe: 4 rules, 1 grant, 1 append-only table, 3 functions. No existing table or function is changed.
--   Default = OFF = exactly today's behaviour: nothing opens, nothing is logged, POS is untouched.
--
--   Rules (module pos):
--     cash_drawer_mode     off (DEFAULT) | on_cash_sale | on_any_sale | manual_only      when the app asks the drawer to open
--     cash_drawer_when     before_payment | after_payment (DEFAULT)                       relative to saving the sale
--     cash_drawer_method   none (DEFAULT) | browser_print_pulse | web_serial | web_usb | bluetooth | kiosk_url
--                          Only methods a browser on a phone/PC can really do are built; kiosk_url is a PLANNED placeholder (the app says so).
--     cash_drawer_no_sale_requires_reason   switch, DEFAULT on: a "no sale" open must carry a reason.
--   Grant drawer_nosale: who may open the drawer with no sale (owner always may).
--   Table drawer_events: APPEND-ONLY audit of every open (auto_open | no_sale_open | test_open | failed). A test open is allowed to anyone who can use POS (setting up the till), and is counted separately in the report. No amounts, no cost, no customer data.
--   drawer_event_log(...)  idempotent by client id (offline queue can replay it safely); drawer_settings(); drawer_report(from,to) owner / view_reports only.
--   The drawer itself is opened from the user's own device (web/cashdrawer.js). The server only remembers the setting and the audit trail.
-- ============================================================

do $g$ begin
  if to_regprocedure('public.is_owner()') is null or to_regprocedure('public.is_active()') is null
     or to_regprocedure('public.has_grant(text, integer)') is null or to_regprocedure('public.can_loc(integer)') is null
     or to_regprocedure('public.can_do(text, text)') is null or to_regprocedure('public.log_change()') is null
     or to_regclass('public.rules') is null or to_regclass('public.grant_defs') is null or to_regclass('public.profiles') is null
     or to_regclass('public.locations') is null then
    raise exception 'phase521 needs the base schema and phase 8 (is_owner, is_active, has_grant, can_loc, can_do, log_change, rules, grant_defs, profiles, locations)';
  end if;
end $g$;

-- ---------- the switches (all default to today's behaviour) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('cash_drawer_mode', 'pos', 'choice', '"off"', null, '["off","on_cash_sale","on_any_sale","manual_only"]'::jsonb, null, null,
  'ক্যাশ ড্রয়ার: কখন খুলবে', 'Cash drawer: কখন খুলবে', 'Cash drawer: when it opens',
  'off = আগের মতো (ড্রয়ার কিছু করে না)। on_cash_sale = ক্যাশ পেমেন্ট নিলে খোলার অনুরোধ। on_any_sale = যেকোনো বিক্রিতে। manual_only = শুধু "No sale" বোতামে। ড্রয়ার না থাকলে বিক্রি কখনো আটকায় না।',
  'off = আগের মতো (drawer কিছু করে না)। on_cash_sale = cash payment নিলে open এর request। on_any_sale = যেকোনো sale এ। manual_only = শুধু "No sale" button এ। Drawer না থাকলে sale কখনো আটকায় না।',
  'off = as today (the drawer does nothing). on_cash_sale = ask the drawer to open when cash is taken. on_any_sale = on every sale. manual_only = only from the "No sale" button. A missing or broken drawer never blocks a sale. Recommended once a drawer is fitted: on_cash_sale.', 950),
 ('cash_drawer_when', 'pos', 'choice', '"after_payment"', null, '["before_payment","after_payment"]'::jsonb, null, null,
  'ক্যাশ ড্রয়ার: বিক্রি সেভের আগে নাকি পরে', 'Cash drawer: sale save এর আগে নাকি পরে', 'Cash drawer: before or after the sale is saved',
  'after_payment = বিক্রি সফল হলে তবেই খোলে (ডিফল্ট)। before_payment = সেভের বোতাম চাপলেই খোলে, সফল না হলেও।',
  'after_payment = sale সফল হলে তবেই খোলে (default)। before_payment = Save button চাপলেই খোলে, সফল না হলেও।',
  'after_payment = opens only once the sale is saved (default; recommended). before_payment = opens as soon as Save is tapped, even if the sale then fails.', 951),
 ('cash_drawer_method', 'pos', 'choice', '"none"', null, '["none","browser_print_pulse","web_serial","web_usb","bluetooth","kiosk_url"]'::jsonb, null, null,
  'ক্যাশ ড্রয়ার: সংযোগের ধরন', 'Cash drawer: connection type', 'Cash drawer: connection type',
  'none = কিছু না। browser_print_pulse = প্রিন্টারের ড্রাইভারে "print এর সময় drawer খোলো" চালু থাকলে। web_serial / web_usb / bluetooth = ডিভাইসে সরাসরি ESC/POS সংকেত (Android Chrome বা কম্পিউটার)। kiosk_url = পরিকল্পিত, এখনো কাজ করে না।',
  'none = কিছু না। browser_print_pulse = printer driver এ "print এর সময় drawer খোলো" on থাকলে। web_serial / web_usb / bluetooth = device এ সরাসরি ESC/POS signal (Android Chrome বা computer)। kiosk_url = planned, এখনো কাজ করে না।',
  'none = nothing. browser_print_pulse = a tiny print job; works when the printer driver is set to open the drawer on print. web_serial / web_usb / bluetooth = send the ESC/POS pulse straight to the device (Chrome on Android or a computer; iPhone browsers cannot). kiosk_url = PLANNED, not built yet.', 952),
 ('cash_drawer_no_sale_requires_reason', 'pos', 'switch', 'true', null, null, null, null,
  'ক্যাশ ড্রয়ার: "No sale" খুলতে কারণ লাগবে', 'Cash drawer: "No sale" open এ reason লাগবে', 'Cash drawer: a "No sale" open needs a reason',
  'চালু = কারণ না লিখলে No-sale খোলা যায় না (ডিফল্ট, প্রস্তাবিত)।', 'On = reason না লিখলে No-sale open হয় না (default, recommended)।',
  'On = a no-sale open cannot be logged without a reason (default and recommended: every open without a sale is an anti-theft signal).', 953)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('drawer_nosale', 'pos', 95, 'বিক্রি ছাড়া ক্যাশ ড্রয়ার খোলা (No sale)', 'Sale ছাড়া Cash drawer খোলা (No sale)', 'Open the cash drawer with no sale', 'window', null)
on conflict (grant_code) do nothing;

-- ---------- the audit trail (append-only) ----------
create table if not exists public.drawer_events (
  id bigint generated always as identity primary key,
  client_id uuid not null,
  event text not null check (event in ('auto_open', 'no_sale_open', 'test_open', 'failed')),
  location_id int,
  by_user uuid not null default auth.uid(),
  by_staff text,
  sale_ref text check (sale_ref is null or length(sale_ref) <= 80),
  reason text check (reason is null or length(reason) <= 300),
  method text check (method is null or method ~ '^[a-z_]{1,30}$'),
  at timestamptz not null default now(),          -- when it happened on the device (an offline queue may log later)
  logged_at timestamptz not null default now()
);
create unique index if not exists drawer_events_client on public.drawer_events (client_id);
create index if not exists drawer_events_at on public.drawer_events (at);
create index if not exists drawer_events_user on public.drawer_events (by_user, event, at);
alter table public.drawer_events enable row level security;
revoke all on table public.drawer_events from public, anon, authenticated;     -- the browser never touches the table; only the functions below

create or replace function public._drawer_events_ro95() returns trigger language plpgsql as $$
begin raise exception 'drawer_events is append-only'; end $$;
revoke all on function public._drawer_events_ro95() from public, anon, authenticated;
drop trigger if exists drawer_events_no_change95 on public.drawer_events;
create trigger drawer_events_no_change95 before update or delete on public.drawer_events for each row execute function public._drawer_events_ro95();
drop trigger if exists drawer_events_no_trunc95 on public.drawer_events;
create trigger drawer_events_no_trunc95 before truncate on public.drawer_events for each statement execute function public._drawer_events_ro95();
drop trigger if exists audit_drawer_events on public.drawer_events;
create trigger audit_drawer_events after insert on public.drawer_events for each row execute function public.log_change('id');

-- ---------- settings the screen and POS read ----------
create or replace function public.drawer_settings(p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'mode', coalesce(public.rule_txt('cash_drawer_mode'), 'off'),
    'when', coalesce(public.rule_txt('cash_drawer_when'), 'after_payment'),
    'method', coalesce(public.rule_txt('cash_drawer_method'), 'none'),
    'no_sale_requires_reason', coalesce(public.rule_on('cash_drawer_no_sale_requires_reason'), true),
    'can_no_sale', public.has_grant('drawer_nosale', p_loc),
    'can_report', (public.is_owner() or public.has_grant('view_reports')),
    'is_owner', public.is_owner(),
    'methods', jsonb_build_array(
      jsonb_build_object('id', 'none', 'status', 'ready'),
      jsonb_build_object('id', 'browser_print_pulse', 'status', 'ready'),
      jsonb_build_object('id', 'web_serial', 'status', 'ready'),
      jsonb_build_object('id', 'web_usb', 'status', 'ready'),
      jsonb_build_object('id', 'bluetooth', 'status', 'experimental'),
      jsonb_build_object('id', 'kiosk_url', 'status', 'planned')));
end $$;
revoke all on function public.drawer_settings(int) from public, anon;
grant execute on function public.drawer_settings(int) to authenticated;

-- ---------- log one drawer event (idempotent by client id) ----------
create or replace function public.drawer_event_log(p_client uuid, p_event text, p_loc int default null, p_sale_ref text default null,
                                                    p_reason text default null, p_method text default null, p_at timestamptz default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid text; r text := nullif(btrim(coalesce(p_reason, '')), ''); t timestamptz; v_id bigint;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_client is null then raise exception 'client_required'; end if;
  if p_event is null or p_event not in ('auto_open', 'no_sale_open', 'test_open', 'failed') then raise exception 'bad_event'; end if;
  if p_loc is not null then
    if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
    if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  end if;
  if not (public.is_owner() or public.can_do('POS', 'enter') or public.can_do('POS', 'view')) then raise exception 'not allowed'; end if;
  if p_event = 'no_sale_open' then
    if not public.has_grant('drawer_nosale', p_loc) then raise exception 'not allowed'; end if;
    if r is null and coalesce(public.rule_on('cash_drawer_no_sale_requires_reason'), true) then raise exception 'reason_required'; end if;
  end if;
  -- a device clock that is wildly off must not rewrite history: outside [-30 days, +5 minutes] the server time is used
  t := case when p_at is not null and p_at <= now() + interval '5 minutes' and p_at >= now() - interval '30 days' then p_at else now() end;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.drawer_events (client_id, event, location_id, by_user, by_staff, sale_ref, reason, method, at)
    values (p_client, p_event, p_loc, auth.uid(), sid, left(p_sale_ref, 80), left(r, 300), case when p_method ~ '^[a-z_]{1,30}$' then p_method end, t)
    on conflict (client_id) do nothing returning id into v_id;
  if v_id is null then return jsonb_build_object('client_id', p_client, 'dup', true); end if;
  return jsonb_build_object('client_id', p_client, 'id', v_id, 'dup', false);
end $$;
revoke all on function public.drawer_event_log(uuid, text, int, text, text, text, timestamptz) from public, anon;
grant execute on function public.drawer_event_log(uuid, text, int, text, text, text, timestamptz) to authenticated;

-- ---------- the anti-theft view: counts per person (owner or a view_reports holder only) ----------
create or replace function public.drawer_report(p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 29); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date); res jsonb;
begin
  if not (public.is_owner() or public.has_grant('view_reports')) then raise exception 'not allowed'; end if;
  if t < f then raise exception 'bad_range'; end if;
  if t - f > 366 then raise exception 'range_too_long'; end if;
  with e as (
    select d.*, (d.at at time zone 'Asia/Dhaka')::date as day from public.drawer_events d where (d.at at time zone 'Asia/Dhaka')::date between f and t)
  select jsonb_build_object(
    'from', f, 'to', t,
    'totals', jsonb_build_object(
      'auto_open', (select count(*) from e where event = 'auto_open'), 'no_sale_open', (select count(*) from e where event = 'no_sale_open'),
      'test_open', (select count(*) from e where event = 'test_open'), 'failed', (select count(*) from e where event = 'failed')),
    'by_user', coalesce((select jsonb_agg(x order by (x ->> 'no_sale_open')::int desc, x ->> 'staff') from (
        select jsonb_build_object('user_id', by_user, 'staff', coalesce(max(by_staff), ''), 'name', coalesce(max(p.full_name), ''),
                 'no_sale_open', count(*) filter (where event = 'no_sale_open'), 'auto_open', count(*) filter (where event = 'auto_open'),
                 'failed', count(*) filter (where event = 'failed'), 'last_no_sale', max(e.at) filter (where event = 'no_sale_open')) as x
        from e left join public.profiles p on p.id = e.by_user group by by_user) q), '[]'::jsonb),
    'by_day', coalesce((select jsonb_agg(jsonb_build_object('day', day, 'no_sale_open', n) order by day) from (
        select day, count(*) as n from e where event = 'no_sale_open' group by day) q), '[]'::jsonb),
    'recent_no_sale', coalesce((select jsonb_agg(jsonb_build_object('at', at, 'staff', by_staff, 'location_id', location_id, 'reason', reason) order by at desc) from (
        select * from e where event = 'no_sale_open' order by at desc limit 50) q), '[]'::jsonb))
  into res;
  return res;
end $$;
revoke all on function public.drawer_report(date, date) from public, anon;
grant execute on function public.drawer_report(date, date) to authenticated;
