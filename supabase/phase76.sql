-- ============================================================
-- Phase 76 (bos76) - Step H: sales channels + message inbox + web order form intake + Meta message intake (pull-in only).
-- Run AFTER phase61/62/70/71. Additive + idempotent (paste twice = no error). No old phase file is changed.
-- Re-created (latest definition, only bos76 lines changed): online_orders_list, online_order_get (customer phone/address mask + view audit).
--
--   H1  sales_channels (kind, branch, role, account ref, active). online_orders gets channel_id, external_ref, source, pay_mode(+other), pay_ref
--       (old text column `channel` keeps working). online_order_save2() = the EXISTING online_order_save + the new columns, one transaction.
--   H2  inbound_messages (unique per channel + external id) + trail; inbox_list / inbox_get / inbox_set_status / inbox_board.
--   H3  web_order_submit(): web / landing form, fully automatic, saves THROUGH online_order_save (never a table write). client id = submission id.
--       Price and total are computed by the server; only active + sellable items; captcha hook + rate limit (rules).
--   H4  inbound_message_receive(): Meta (Messenger / Instagram / WhatsApp) webhook receiver side; signature result comes from the Edge function
--       (the HMAC itself is also available in SQL: inbound_sig_verify). Idempotent on (channel, external id). Pull in only; no reply.
--   H5  messages never become orders by themselves. online_order_save2(p_draft) makes a DRAFT (switch inbox_autodraft_on, default OFF);
--       a draft cannot be confirmed / packed / delivered until a person verifies it (online_order_draft_verify). No AI call here.
--   H6  order_dup_flags (same customer + same item + same day, different channels = FLAG only), PII mask + view audit,
--       intake_failures (failed list + retry), inbox_board (new messages, last message time, silence warning).
-- Switches (all OFF unless noted): inbox_on, meta_intake_on, web_form_on, web_form_captcha_on, inbox_autodraft_on, inbox_pii_guard_on.
-- Numbers: web_form_rate_max, web_form_rate_window_min, inbox_silence_hours, intake_max_tries, intake_retry_min. Text: web_form_public_url.
-- ============================================================

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('inbox_on', 'pos', 'switch', 'false', null, null, null, null, 'বার্তা ইনবক্স চালু', 'Message inbox চালু', 'Message inbox is on',
  'চালু হলে বাইরের বার্তা ইনবক্সে জমা হয়; অর্ডার বানায় মানুষ।', 'When on, outside messages collect in the inbox; a person makes the order.', 620),
 ('meta_intake_on', 'pos', 'switch', 'false', null, null, null, null, 'ফেসবুক/ইনস্টাগ্রাম/হোয়াটসঅ্যাপ বার্তা ঢোকা চালু', 'FB / IG / WhatsApp বার্তা intake চালু', 'Facebook / Instagram / WhatsApp message intake is on',
  'বাইরের সংযোগ (Edge ফাংশন) তৈরি না হওয়া পর্যন্ত এটি চালু করলেও কিছু আসবে না।', 'Nothing arrives until the outside connection (Edge function) exists, even if this is on.', 621),
 ('web_form_on', 'pos', 'switch', 'false', null, null, null, null, 'ওয়েব অর্ডার ফর্ম চালু', 'Web order form চালু', 'Web order form is on',
  'চালু হলে ওয়েব ফর্মের অর্ডার নিজে থেকে অর্ডার তালিকায় ঢোকে (নতুন অবস্থায়, স্টাফ নিশ্চিত করে)।', 'When on, web form orders enter the order list by themselves (status new; staff confirm).', 622),
 ('web_form_captcha_on', 'pos', 'switch', 'false', null, null, null, null, 'ওয়েব ফর্মে ক্যাপচা বাধ্যতামূলক', 'Web form-এ captcha বাধ্যতামূলক', 'Web form needs a captcha pass',
  'চালু হলে ক্যাপচা পাশ না করা জমা নেওয়া হয় না (ক্যাপচা পরিষেবা আলাদা সেটআপ লাগে)।', 'When on, a submission without a passed captcha is refused (needs a captcha service set up separately).', 623),
 ('web_form_rate_max', 'pos', 'number', '10', 'বার', null, 0, 1000, 'ওয়েব ফর্ম: এক ডিভাইস সর্বোচ্চ কতবার', 'Web form: এক device-এ সর্বোচ্চ কতবার', 'Web form: max submissions per device',
  '০ = সীমা নেই। সময়ের জানালা পরের সেটিংয়ে।', '0 = no limit. The time window is the next setting.', 624),
 ('web_form_rate_window_min', 'pos', 'number', '60', 'মিনিট', null, 1, 1440, 'ওয়েব ফর্ম: সীমার সময়ের জানালা', 'Web form: limit-এর সময়ের window', 'Web form: rate window',
  null, null, 625),
 ('inbox_autodraft_on', 'pos', 'switch', 'false', null, null, null, null, 'বার্তা থেকে অর্ডারের খসড়া (যাচাই বাকি) চালু', 'Message থেকে order খসড়া (যাচাই বাকি) চালু', 'Order drafts from messages (needs checking)',
  'খসড়া কখনো নিজে নিশ্চিত হয় না; মানুষ যাচাই না করলে স্টক/বিক্রি কিছু নড়ে না।', 'A draft never confirms itself; without a person checking it, no stock and no sale moves.', 626),
 ('inbox_pii_guard_on', 'pos', 'switch', 'false', null, null, null, null, 'গ্রাহকের ফোন/ঠিকানা শুধু অনুমতিপ্রাপ্তদের', 'Customer ফোন/ঠিকানা শুধু অনুমতিপ্রাপ্তদের', 'Customer phone/address only for authorised people',
  'চালু হলে মালিক বা "গ্রাহকের যোগাযোগ দেখা" অনুমতি ছাড়া ফোন/ঠিকানা ঢাকা থাকে। প্রতিবার দেখা লগে থাকে।', 'When on, phone/address are hidden unless owner or the contact-view grant. Every view is logged.', 627),
 ('inbox_silence_hours', 'pos', 'number', '24', 'ঘণ্টা', null, 0, 720, 'এত ঘণ্টা বার্তা না এলে সতর্কতা', 'এত ঘণ্টা message না এলে warning', 'Warn when no message for (hours)',
  '০ = সতর্কতা বন্ধ।', '0 = no warning.', 628),
 ('intake_max_tries', 'pos', 'number', '5', 'বার', null, 1, 20, 'ব্যর্থ ঢোকা কতবার আবার চেষ্টা', 'Failed intake কতবার retry', 'Failed intake: max tries', null, null, 629),
 ('intake_retry_min', 'pos', 'number', '5', 'মিনিট', null, 1, 1440, 'আবার চেষ্টার বিরতি (প্রতিবার এর গুণ)', 'Retry-র বিরতি (প্রতিবার এর গুণ)', 'Retry delay (times the try number)', null, null, 630)
 on conflict (key) do nothing;
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('web_form_public_url', 'pos', 'text', '""', null, null, null, null, 'ওয়েব ফর্মের পাবলিক ঠিকানা (Edge ফাংশনের URL)', 'Web form public URL (Edge function)', 'Web form public URL (Edge function)',
  'ফাংশন চালু হওয়ার পরে এখানে বসান; এর আগে শেয়ার-লিংক তৈরি হয় না।', 'Fill after the function is deployed; no share link is made before.', 631)
 on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'inbox_contact_view', 'pos', 95, 'গ্রাহকের ফোন/ঠিকানা দেখা (ইনবক্স/অনলাইন অর্ডার)', 'Customer ফোন/ঠিকানা দেখা (inbox / online order)', 'See customer phone / address (inbox / online orders)', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'inbox_contact_view');

-- =====================================================================
-- H1 channels
-- =====================================================================
create table if not exists public.sales_channels (
  id int generated always as identity primary key,
  code text not null unique check (code ~ '^[a-z0-9_]{2,30}$'),
  kind text not null check (kind in ('web_form', 'facebook', 'instagram', 'whatsapp', 'phone', 'walkin', 'other')),
  other_text text check (other_text is null or char_length(other_text) <= 60),
  name_bn text not null check (char_length(btrim(name_bn)) between 1 and 60),
  location_id int references public.locations(id),
  role_code text,
  account_ref text check (account_ref is null or char_length(account_ref) <= 120),     -- Meta page id / phone number id / form id: not shown to staff
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (kind <> 'other' or other_text is not null)
);
create unique index if not exists sales_channels_ref on public.sales_channels (kind, account_ref) where account_ref is not null;

create table if not exists public.intake_bots (
  user_id uuid primary key references public.profiles(id), active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

alter table public.online_orders add column if not exists channel_id int references public.sales_channels(id);
alter table public.online_orders add column if not exists external_ref text check (external_ref is null or char_length(external_ref) <= 120);
alter table public.online_orders add column if not exists source text check (source is null or char_length(source) <= 80);
alter table public.online_orders add column if not exists pay_mode text check (pay_mode is null or pay_mode in ('cod', 'cash', 'mobile', 'card', 'bank', 'other'));
alter table public.online_orders add column if not exists pay_mode_other text check (pay_mode_other is null or char_length(pay_mode_other) <= 60);
alter table public.online_orders add column if not exists pay_ref text check (pay_ref is null or char_length(pay_ref) <= 80);
alter table public.online_orders add column if not exists is_draft boolean not null default false;
alter table public.online_orders add column if not exists draft_note text check (draft_note is null or char_length(draft_note) <= 300);
alter table public.online_orders add column if not exists draft_verified_by uuid;
alter table public.online_orders add column if not exists draft_verified_at timestamptz;
create unique index if not exists online_orders_ext on public.online_orders (channel_id, external_ref) where channel_id is not null and external_ref is not null;

-- =====================================================================
-- H2 inbox
-- =====================================================================
create table if not exists public.inbound_messages (
  id bigint generated always as identity primary key,
  channel_id int not null references public.sales_channels(id), location_id int not null references public.locations(id),
  external_id text not null check (char_length(external_id) between 1 and 200),
  customer_handle text check (customer_handle is null or char_length(customer_handle) <= 120),
  customer_name text check (customer_name is null or char_length(customer_name) <= 120),
  msg_text text check (msg_text is null or char_length(msg_text) <= 4000),
  msg_time timestamptz, received_at timestamptz not null default now(),
  attachment_ref text check (attachment_ref is null or char_length(attachment_ref) <= 500),
  status text not null default 'new' check (status in ('new', 'seen', 'converted', 'ignored')),
  linked_order_id uuid references public.online_orders(id), draft_order_id uuid references public.online_orders(id),
  seen_by uuid, seen_at timestamptz, ignore_note text,
  unique (channel_id, external_id)
);
create index if not exists inbound_messages_board on public.inbound_messages (location_id, status, received_at desc);
alter table public.online_orders add column if not exists inbox_msg_id bigint references public.inbound_messages(id);

create table if not exists public.inbound_message_events (
  id bigint generated always as identity primary key, msg_id bigint not null references public.inbound_messages(id),
  from_status text, to_status text not null, note text, by_user uuid, at timestamptz not null default now()
);

create table if not exists public.intake_failures (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('message', 'web_order', 'bad_signature')),
  channel_id int, external_id text, error text, payload jsonb,
  attempts int not null default 0, next_try_at timestamptz, last_try_at timestamptz,
  state text not null default 'failed' check (state in ('failed', 'done', 'dead', 'rejected')),
  created_at timestamptz not null default now(), done_at timestamptz, note text
);
create index if not exists intake_failures_due on public.intake_failures (state, next_try_at);

create table if not exists public.intake_hits (
  id bigint generated always as identity primary key, channel_id int not null, key_hash text not null, at timestamptz not null default now()
);
create index if not exists intake_hits_k on public.intake_hits (channel_id, key_hash, at desc);

create table if not exists public.order_dup_flags (
  id bigint generated always as identity primary key,
  order_a uuid not null references public.online_orders(id), order_b uuid not null references public.online_orders(id),
  location_id int not null, day date not null, items jsonb not null,
  state text not null default 'open' check (state in ('open', 'reviewed')), review_note text, reviewed_by uuid, reviewed_at timestamptz,
  created_at timestamptz not null default now(), unique (order_a, order_b), check (order_a < order_b)
);

-- trails / read-only guards
create or replace function public._inb_ro76() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_table_name = 'inbound_message_events' then raise exception 'append_only: the message trail cannot be changed or deleted'; end if;
  if tg_table_name = 'order_dup_flags' then
    if tg_op = 'DELETE' then raise exception 'append_only: a flag is reviewed, never deleted'; end if;
    if (to_jsonb(new) - 'state' - 'review_note' - 'reviewed_by' - 'reviewed_at') <> (to_jsonb(old) - 'state' - 'review_note' - 'reviewed_by' - 'reviewed_at') then raise exception 'append_only: only the review can change'; end if;
    return new;
  end if;
  if tg_table_name = 'inbound_messages' then
    if tg_op = 'DELETE' then raise exception 'append_only: a message is never deleted'; end if;
    if new.external_id <> old.external_id or new.channel_id <> old.channel_id or new.msg_text is distinct from old.msg_text or new.customer_handle is distinct from old.customer_handle
       or new.received_at <> old.received_at then raise exception 'append_only: the received message cannot be changed'; end if;
    if old.status = 'converted' and new.status <> 'converted' then raise exception 'order_closed: a converted message stays converted'; end if;
    return new;
  end if;
  if tg_table_name = 'sales_channels' and tg_op = 'DELETE' then raise exception 'append_only: a channel is switched off, never deleted'; end if;
  return new;
end $$;
drop trigger if exists inbound_message_events_ro76 on public.inbound_message_events;
create trigger inbound_message_events_ro76 before update or delete on public.inbound_message_events for each row execute function public._inb_ro76();
drop trigger if exists order_dup_flags_ro76 on public.order_dup_flags;
create trigger order_dup_flags_ro76 before update or delete on public.order_dup_flags for each row execute function public._inb_ro76();
drop trigger if exists inbound_messages_ro76 on public.inbound_messages;
create trigger inbound_messages_ro76 before update or delete on public.inbound_messages for each row execute function public._inb_ro76();
drop trigger if exists sales_channels_ro76 on public.sales_channels;
create trigger sales_channels_ro76 before delete on public.sales_channels for each row execute function public._inb_ro76();

-- audit (no message text / handle / payload is copied into the audit log)
create or replace function public._inb_audit76() returns trigger language plpgsql security definer set search_path = public as $$
declare sid text;
begin
  select staff_id into sid from public.profiles where id = auth.uid();
  if tg_table_name = 'inbound_messages' then
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), sid, lower(tg_op), tg_table_name, new.id::text, jsonb_build_object('channel_id', new.channel_id, 'external_id', new.external_id, 'status', new.status, 'linked_order_id', new.linked_order_id));
  elsif tg_table_name = 'intake_failures' then
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), sid, lower(tg_op), tg_table_name, new.id::text, jsonb_build_object('kind', new.kind, 'state', new.state, 'attempts', new.attempts, 'error', left(new.error, 200)));
  end if;
  return new;
end $$;
drop trigger if exists audit_inbound_messages on public.inbound_messages;
create trigger audit_inbound_messages after insert or update on public.inbound_messages for each row execute function public._inb_audit76();
drop trigger if exists audit_intake_failures on public.intake_failures;
create trigger audit_intake_failures after insert or update on public.intake_failures for each row execute function public._inb_audit76();
drop trigger if exists audit_sales_channels on public.sales_channels;
create trigger audit_sales_channels after insert or update on public.sales_channels for each row execute function public.log_change('id');
drop trigger if exists audit_intake_bots on public.intake_bots;
create trigger audit_intake_bots after insert or update on public.intake_bots for each row execute function public.log_change('user_id');
drop trigger if exists audit_order_dup_flags on public.order_dup_flags;
create trigger audit_order_dup_flags after insert or update on public.order_dup_flags for each row execute function public.log_change('id');

-- a draft can never be confirmed / packed / delivered (nor linked to a sale) until a person verified it
create or replace function public._oo_draft_guard76() returns trigger language plpgsql set search_path = public as $$
begin
  if old.is_draft and new.is_draft and new.status is distinct from old.status and new.status in ('confirmed', 'packed', 'delivered') then
    raise exception 'draft_unverified: this order is a draft; a person must check and verify it first';
  end if;
  return new;
end $$;
drop trigger if exists online_orders_draft76 on public.online_orders;
create trigger online_orders_draft76 before update on public.online_orders for each row execute function public._oo_draft_guard76();

-- H6 duplicate flag: same customer (mobile) + same item + same day, from DIFFERENT channels => flag only
create or replace function public._oo_dup76() returns trigger language plpgsql security definer set search_path = public as $$
declare b public.online_orders; common jsonb; a_ uuid; b_ uuid;
begin
  if new.status = 'cancelled' then return new; end if;
  for b in select o.* from public.online_orders o
            where o.id <> new.id and o.customer_mobile = new.customer_mobile and o.status <> 'cancelled'
              and (o.created_at at time zone 'Asia/Dhaka')::date = (new.created_at at time zone 'Asia/Dhaka')::date
              and (o.channel is distinct from new.channel or o.channel_id is distinct from new.channel_id) loop
    select coalesce(jsonb_agg(distinct x->>'item_id'), '[]'::jsonb) into common
      from jsonb_array_elements(new.lines) x where (x->>'item_id') in (select y->>'item_id' from jsonb_array_elements(b.lines) y);
    if jsonb_array_length(common) > 0 then
      if new.id < b.id then a_ := new.id; b_ := b.id; else a_ := b.id; b_ := new.id; end if;
      insert into public.order_dup_flags (order_a, order_b, location_id, day, items) values (a_, b_, new.location_id, (new.created_at at time zone 'Asia/Dhaka')::date, common)
        on conflict (order_a, order_b) do nothing;
    end if;
  end loop;
  return new;
end $$;
drop trigger if exists online_orders_dup76 on public.online_orders;
create trigger online_orders_dup76 after insert or update of lines, customer_mobile on public.online_orders for each row execute function public._oo_dup76();

-- =====================================================================
-- helpers
-- =====================================================================
create or replace function public._inb_is_bot() returns boolean language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and exists (select 1 from public.intake_bots b where b.user_id = auth.uid() and b.active);
$$;

create or replace function public.intake_bot_set(p_user uuid, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_user is null or p_active is null then raise exception 'bad_input'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'user_not_found'; end if;
  if exists (select 1 from public.user_roles where user_id = p_user and role_code = 'owner') then raise exception 'owner_cannot_be_bot'; end if;
  insert into public.intake_bots (user_id, active, created_by) values (p_user, p_active, auth.uid())
    on conflict (user_id) do update set active = excluded.active, updated_at = now();
  return jsonb_build_object('user_id', p_user, 'active', p_active);
end $$;

create or replace function public._inb_gate(p_loc int, p_action text default 'view') returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('inbox_on') then raise exception 'module_off'; end if;
  if not public.can_do('POS', p_action) then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
end $$;

-- may this person see the customer phone / address of this place?
create or replace function public._inb_contact_ok(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select case when not public.rule_on('inbox_pii_guard_on') then public.can_do('POS', 'view') and public.can_loc(p_loc)
              else public.is_owner() or (public.can_loc(p_loc) and public.has_grant('inbox_contact_view', p_loc)) end;
$$;

create or replace function public._inb_audit_view(p_table text, p_id text, p_detail jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'view', p_table, p_id, p_detail);
end $$;

create or replace function public._inb_kind_text(p_kind text) returns text language sql immutable as $$
  select case p_kind when 'web_form' then 'website' when 'facebook' then 'facebook' when 'instagram' then 'instagram' when 'whatsapp' then 'whatsapp' when 'phone' then 'phone' else 'other' end;
$$;

-- pure-SQL HMAC-SHA256 (no extension needed); used by inbound_sig_verify and the tests (RFC 4231 vectors)
create or replace function public._inb_hmac_sha256(p_key bytea, p_msg bytea) returns text
language plpgsql immutable set search_path = public as $$
declare k bytea := p_key; ip bytea; op bytea; i int;
begin
  if length(k) > 64 then k := sha256(k); end if;
  k := k || decode(repeat('00', 64 - length(k)), 'hex');
  ip := k; op := k;
  for i in 0..63 loop ip := set_byte(ip, i, get_byte(k, i) # 54); op := set_byte(op, i, get_byte(k, i) # 92); end loop;
  return encode(sha256(op || sha256(ip || p_msg)), 'hex');
end $$;

-- Meta style header "sha256=<hex>" over the RAW body. The default place for this check is the Edge function (the secret stays there);
-- this SQL copy exists so the rule is testable and usable as a fallback. Never log the secret argument.
create or replace function public.inbound_sig_verify(p_secret text, p_raw_body text, p_header text) returns boolean
language plpgsql immutable set search_path = public as $$
declare exp text; got text; diff int := 0; i int;
begin
  if p_secret is null or p_secret = '' or p_raw_body is null or p_header is null or p_header !~ '^sha256=[0-9a-fA-F]{64}$' then return false; end if;
  exp := public._inb_hmac_sha256(convert_to(p_secret, 'UTF8'), convert_to(p_raw_body, 'UTF8'));
  got := lower(substr(p_header, 8));
  for i in 1..64 loop diff := diff | (ascii(substr(exp, i, 1)) # ascii(substr(got, i, 1))); end loop;
  return diff = 0;
end $$;

create or replace function public._intake_fail(p_kind text, p_channel int, p_ext text, p_err text, p_payload jsonb, p_state text default 'failed') returns bigint
language plpgsql security definer set search_path = public as $$
declare id_ bigint;
begin
  insert into public.intake_failures (kind, channel_id, external_id, error, payload, state, next_try_at)
    values (p_kind, p_channel, left(p_ext, 200), left(p_err, 500), p_payload, p_state,
            case when p_state = 'failed' then now() + make_interval(mins => greatest(1, coalesce(public.rule_num('intake_retry_min'), 5)::int)) end)
    returning id into id_;
  return id_;
end $$;

-- =====================================================================
-- H1 channel functions
-- =====================================================================
create or replace function public.sales_channel_save(p_id int, p_code text, p_kind text, p_other text, p_name text, p_loc int, p_role text, p_account_ref text, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.sales_channels;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_kind not in ('web_form', 'facebook', 'instagram', 'whatsapp', 'phone', 'walkin', 'other') then raise exception 'bad_kind'; end if;
  if p_kind = 'other' and nullif(btrim(p_other), '') is null then raise exception 'other_text_required'; end if;
  if nullif(btrim(p_name), '') is null or char_length(btrim(p_name)) > 60 then raise exception 'name_required'; end if;
  if p_code is null or p_code !~ '^[a-z0-9_]{2,30}$' then raise exception 'bad_code'; end if;
  if p_loc is not null and not exists (select 1 from public.locations where id = p_loc) then raise exception 'location_not_found'; end if;
  if p_role is not null and not exists (select 1 from public.roles where code = p_role) then raise exception 'role_not_found'; end if;
  if p_id is null then
    insert into public.sales_channels (code, kind, other_text, name_bn, location_id, role_code, account_ref, active, created_by)
      values (p_code, p_kind, case when p_kind = 'other' then left(btrim(p_other), 60) end, btrim(p_name), p_loc, p_role, nullif(btrim(p_account_ref), ''), coalesce(p_active, true), auth.uid()) returning * into c;
  else
    update public.sales_channels set code = p_code, kind = p_kind, other_text = case when p_kind = 'other' then left(btrim(p_other), 60) end, name_bn = btrim(p_name), location_id = p_loc,
        role_code = p_role, account_ref = nullif(btrim(p_account_ref), ''), active = coalesce(p_active, true), updated_at = now() where id = p_id returning * into c;
    if not found then raise exception 'not_found'; end if;
  end if;
  return jsonb_build_object('id', c.id, 'code', c.code, 'active', c.active);
end $$;

create or replace function public.sales_channels_list(p_all boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o boolean := public.is_owner();
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'code', c.code, 'kind', c.kind, 'other_text', c.other_text, 'name_bn', c.name_bn, 'location_id', c.location_id, 'role_code', c.role_code,
            'active', c.active, 'account_ref', case when o then c.account_ref end) order by c.id)
     from public.sales_channels c where (c.active or (p_all and o)) and (o or c.location_id is null or public.can_loc(c.location_id))), '[]'::jsonb);
end $$;

-- =====================================================================
-- H2 / H4 receive (called by the Edge function logged in as the intake bot)
-- =====================================================================
create or replace function public._inb_insert_message(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ch public.sales_channels; m public.inbound_messages; n int;
begin
  select * into ch from public.sales_channels where kind = p->>'kind' and account_ref = p->>'account_ref' and active;
  if not found then raise exception 'channel_not_found'; end if;
  if ch.location_id is null then raise exception 'channel_no_location'; end if;
  insert into public.inbound_messages (channel_id, location_id, external_id, customer_handle, customer_name, msg_text, msg_time, attachment_ref)
    values (ch.id, ch.location_id, p->>'external_id', left(p->>'handle', 120), left(p->>'name', 120), left(p->>'text', 4000),
            nullif(p->>'msg_time', '')::timestamptz, left(p->>'attachment', 500))
    on conflict (channel_id, external_id) do nothing returning * into m;
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('duplicate', true); end if;
  insert into public.inbound_message_events (msg_id, from_status, to_status, note, by_user) values (m.id, null, 'new', 'received', auth.uid());
  return jsonb_build_object('duplicate', false, 'id', m.id);
end $$;

create or replace function public.inbound_message_receive(p_kind text, p_account_ref text, p_external_id text, p_handle text, p_name text, p_text text,
                                                          p_msg_time timestamptz, p_attachment text, p_signature_ok boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pl jsonb; res jsonb; fid bigint; ch int;
begin
  if not (public._inb_is_bot() or public.is_owner()) then raise exception 'not allowed'; end if;
  if not public.rule_on('inbox_on') then return jsonb_build_object('off', true); end if;
  if p_kind in ('facebook', 'instagram', 'whatsapp') and not public.rule_on('meta_intake_on') then return jsonb_build_object('off', true); end if;
  if p_kind not in ('facebook', 'instagram', 'whatsapp', 'web_form', 'other') or p_signature_ok is null or p_external_id is null or char_length(p_external_id) not between 1 and 200
     or char_length(coalesce(p_account_ref, '')) > 120 or char_length(coalesce(p_text, '')) > 20000 then raise exception 'bad_input'; end if;
  if not p_signature_ok then
    -- a wrong signature is never stored as a message; only the fact (no body) goes to the failed list for the owner to see
    fid := public._intake_fail('bad_signature', null, p_external_id, 'bad_signature', jsonb_build_object('kind', p_kind), 'rejected');
    return jsonb_build_object('rejected', 'bad_signature', 'failure_id', fid);
  end if;
  pl := jsonb_build_object('kind', p_kind, 'account_ref', p_account_ref, 'external_id', p_external_id, 'handle', p_handle, 'name', p_name, 'text', p_text,
                           'msg_time', p_msg_time, 'attachment', p_attachment);
  select id into ch from public.sales_channels where kind = p_kind and account_ref = p_account_ref;
  begin
    res := public._inb_insert_message(pl);
  exception when others then
    fid := public._intake_fail('message', ch, p_external_id, sqlerrm, pl);
    return jsonb_build_object('failed', true, 'queued', true, 'failure_id', fid);
  end;
  return res;
end $$;

create or replace function public.inbox_list(p_loc int default null, p_status text default null, p_limit int default 100) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; unmasked boolean := false; l int[];
begin
  perform public._inb_gate(p_loc, 'view');
  if p_status is not null and p_status not in ('new', 'seen', 'converted', 'ignored') then raise exception 'bad_input'; end if;
  select coalesce(array_agg(x.id), '{}') into l from public.locations x where public.can_loc(x.id) and (p_loc is null or x.id = p_loc);
  select coalesce(jsonb_agg(z.j order by z.rid desc), '[]'::jsonb) into r from (
    select m.id rid, jsonb_build_object('id', m.id, 'channel_id', m.channel_id, 'channel', c.name_bn, 'kind', c.kind, 'location_id', m.location_id, 'status', m.status, 'received_at', m.received_at, 'msg_time', m.msg_time,
      'linked_order_id', m.linked_order_id, 'draft_order_id', m.draft_order_id, 'has_attachment', m.attachment_ref is not null,
      'handle', case when public._inb_contact_ok(m.location_id) then m.customer_handle end, 'name', case when public._inb_contact_ok(m.location_id) then m.customer_name end,
      'text', case when public._inb_contact_ok(m.location_id) then left(m.msg_text, 200) end, 'masked', not public._inb_contact_ok(m.location_id)) j
      from public.inbound_messages m join public.sales_channels c on c.id = m.channel_id
     where m.location_id = any (l) and (p_status is null or m.status = p_status)
     order by m.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z;
  if exists (select 1 from jsonb_array_elements(r) e where (e->>'masked')::boolean is false) then
    perform public._inb_audit_view('inbound_messages', 'list', jsonb_build_object('count', jsonb_array_length(r), 'loc', p_loc, 'status', p_status));
  end if;
  return r;
end $$;

create or replace function public.inbox_get(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
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
    'handle', case when ok then m.customer_handle end, 'name', case when ok then m.customer_name end, 'text', case when ok then m.msg_text end, 'attachment_ref', case when ok then m.attachment_ref end,
    'events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_status, 'to', e.to_status, 'note', e.note, 'at', e.at) order by e.id) from public.inbound_message_events e where e.msg_id = m.id), '[]'::jsonb));
end $$;

create or replace function public.inbox_set_status(p_id bigint, p_to text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.inbound_messages;
begin
  select * into m from public.inbound_messages where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  perform public._inb_gate(m.location_id, 'enter');
  if p_to not in ('new', 'seen', 'ignored') then raise exception 'bad_status'; end if;
  if m.status = p_to then return jsonb_build_object('id', m.id, 'status', m.status, 'noop', true); end if;
  if m.status = 'converted' then raise exception 'order_closed: a converted message stays converted'; end if;
  if p_to = 'new' and m.status <> 'ignored' then raise exception 'bad_status'; end if;
  if p_to = 'ignored' and nullif(btrim(p_note), '') is null then raise exception 'reason_required'; end if;
  update public.inbound_messages set status = p_to, seen_by = case when p_to = 'seen' then auth.uid() else seen_by end, seen_at = case when p_to = 'seen' then now() else seen_at end,
      ignore_note = case when p_to = 'ignored' then left(btrim(p_note), 300) else ignore_note end where id = m.id;
  insert into public.inbound_message_events (msg_id, from_status, to_status, note, by_user) values (m.id, m.status, p_to, left(nullif(btrim(p_note), ''), 300), auth.uid());
  return jsonb_build_object('id', m.id, 'status', p_to);
end $$;

-- board numbers: new messages, last message time, silence warning, failed list size, open duplicate flags, drafts
create or replace function public.inbox_board(p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
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
        from public.sales_channels c where c.active and c.kind in ('facebook', 'instagram', 'whatsapp') and (c.location_id is null or c.location_id = any (l))), '[]'::jsonb));
end $$;

-- =====================================================================
-- order save with channel columns (wraps the EXISTING online_order_save), draft support, inbox link
-- =====================================================================
create or replace function public.online_order_save2(p_id uuid, p_client uuid, p_loc int, p_channel_id int, p_name text, p_mobile text, p_address text, p_lines jsonb,
  p_delivery_mode text, p_delivery_by text, p_delivery_date date, p_charge numeric, p_discount numeric, p_advance numeric, p_adv_mode text, p_adv_wallet text, p_note text,
  p_external_ref text default null, p_source text default null, p_pay_mode text default null, p_pay_mode_other text default null, p_pay_ref text default null,
  p_msg_id bigint default null, p_draft boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ch public.sales_channels; m public.inbound_messages; res jsonb; oid uuid; o public.online_orders; ext text := nullif(btrim(p_external_ref), '');
begin
  if p_channel_id is null then raise exception 'channel_required'; end if;
  if p_id is null and p_client is not null then          -- a retry of an already saved order returns it before anything else is checked
    select * into o from public.online_orders where client_id = p_client and created_by = auth.uid();
    if found then return jsonb_build_object('id', o.id, 'order_no', o.order_no, 'status', o.status, 'dup', true); end if;
  end if;
  select * into ch from public.sales_channels where id = p_channel_id;
  if not found or not ch.active then raise exception 'channel_not_found'; end if;
  if p_id is not null then select * into o from public.online_orders where id = p_id; if not found then raise exception 'not_found'; end if; end if;
  if ch.location_id is not null and ch.location_id <> coalesce(o.location_id, p_loc) then raise exception 'channel_other_location'; end if;
  if p_pay_mode is not null and p_pay_mode not in ('cod', 'cash', 'mobile', 'card', 'bank', 'other') then raise exception 'bad_pay_mode'; end if;
  if p_pay_mode = 'other' and nullif(btrim(p_pay_mode_other), '') is null then raise exception 'pay_mode_other_required'; end if;
  if coalesce(p_draft, false) then
    if not public.rule_on('inbox_autodraft_on') then raise exception 'module_off: drafts are off'; end if;
    if p_id is not null and not o.is_draft then raise exception 'not_a_draft'; end if;
  elsif p_id is not null and o.is_draft then
    null;   -- editing a draft keeps it a draft until verified
  end if;
  if p_msg_id is not null then
    select * into m from public.inbound_messages where id = p_msg_id for update;
    if not found or m.channel_id <> p_channel_id then raise exception 'message_not_found'; end if;
    perform public._inb_gate(m.location_id, 'enter');
    if m.status in ('converted', 'ignored') then raise exception 'message_closed: this message is already converted or ignored'; end if;
    if m.draft_order_id is not null and p_id is distinct from m.draft_order_id and not coalesce(p_draft, false) then raise exception 'message_has_draft: verify the draft instead'; end if;
    ext := coalesce(ext, m.external_id);
  end if;
  res := public.online_order_save(p_id, p_client, p_loc, public._inb_kind_text(ch.kind), p_name, p_mobile, p_address, p_lines, p_delivery_mode, p_delivery_by, p_delivery_date,
                                  p_charge, p_discount, p_advance, p_adv_mode, p_adv_wallet, p_note);
  if coalesce((res->>'dup')::boolean, false) then return res; end if;
  oid := (res->>'id')::uuid;
  update public.online_orders set channel_id = ch.id, external_ref = ext, source = left(nullif(btrim(p_source), ''), 80), pay_mode = p_pay_mode,
      pay_mode_other = case when p_pay_mode = 'other' then left(btrim(p_pay_mode_other), 60) end, pay_ref = left(nullif(btrim(p_pay_ref), ''), 80),
      inbox_msg_id = coalesce(p_msg_id, inbox_msg_id), is_draft = case when p_id is null then coalesce(p_draft, false) else is_draft end,
      draft_note = case when p_id is null and coalesce(p_draft, false) then 'খসড়া, যাচাই বাকি' else draft_note end
    where id = oid;
  if p_msg_id is not null and p_id is null then
    if coalesce(p_draft, false) then
      update public.inbound_messages set draft_order_id = oid where id = p_msg_id;
      insert into public.inbound_message_events (msg_id, from_status, to_status, note, by_user) values (p_msg_id, m.status, m.status, 'draft order made (unverified)', auth.uid());
    else
      update public.inbound_messages set status = 'converted', linked_order_id = oid, seen_by = coalesce(seen_by, auth.uid()), seen_at = coalesce(seen_at, now()) where id = p_msg_id;
      insert into public.inbound_message_events (msg_id, from_status, to_status, note, by_user) values (p_msg_id, m.status, 'converted', 'order made', auth.uid());
    end if;
  end if;
  return res || jsonb_build_object('draft', coalesce(p_draft, false) and p_id is null);
end $$;

create or replace function public.online_order_draft_verify(p_id uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; m public.inbound_messages;
begin
  select * into o from public.online_orders where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id, 'enter');
  if not o.is_draft then return jsonb_build_object('id', o.id, 'noop', true); end if;
  if o.status <> 'new' then raise exception 'order_closed'; end if;
  update public.online_orders set is_draft = false, draft_verified_by = auth.uid(), draft_verified_at = now(), draft_note = left(coalesce(nullif(btrim(p_note), ''), 'যাচাই হয়েছে'), 300), updated_at = now() where id = o.id;
  perform public._oo_event61(o.id, 'new', 'new', 'draft verified by a person' || coalesce(' | ' || nullif(btrim(p_note), ''), ''));
  if o.inbox_msg_id is not null then
    select * into m from public.inbound_messages where id = o.inbox_msg_id for update;
    if found and m.status not in ('converted') then
      update public.inbound_messages set status = 'converted', linked_order_id = o.id where id = m.id;
      insert into public.inbound_message_events (msg_id, from_status, to_status, note, by_user) values (m.id, m.status, 'converted', 'draft verified', auth.uid());
    end if;
  end if;
  return jsonb_build_object('id', o.id, 'verified', true);
end $$;

-- =====================================================================
-- H3 web / landing form
-- =====================================================================
create or replace function public._web_order_run(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ch public.sales_channels; sub uuid := (p->>'submission')::uuid; ex public.online_orders; clean jsonb := '[]'; ln jsonb; it public.items; q numeric; res jsonb; n int := 0;
begin
  select * into ch from public.sales_channels where code = p->>'channel' and kind = 'web_form' and active;
  if not found then raise exception 'channel_not_found'; end if;
  if ch.location_id is null then raise exception 'channel_no_location'; end if;
  select * into ex from public.online_orders where channel_id = ch.id and external_ref = sub::text;
  if found then return jsonb_build_object('order_no', ex.order_no, 'status', ex.status, 'subtotal', ex.subtotal, 'dup', true); end if;
  if p->>'delivery_mode' not in ('pickup', 'home') then raise exception 'bad_delivery_mode'; end if;
  if jsonb_typeof(p->'lines') <> 'array' or jsonb_array_length(p->'lines') not between 1 and 100 then raise exception 'no_lines'; end if;
  for ln in select * from jsonb_array_elements(p->'lines') loop
    n := n + 1;
    begin q := (ln->>'qty')::numeric; exception when others then raise exception 'bad_qty'; end;
    if q is null or q = 'NaN'::numeric or q <= 0 or q > 1000000 then raise exception 'bad_qty'; end if;
    begin select * into it from public.items where id = (ln->>'item_id')::uuid; exception when others then raise exception 'item_not_found'; end;
    -- only active, sellable, visible, priced items; the CLIENT PRICE (if any) is dropped here: only item_id + qty go on
    if not found or not it.is_active or not it.sellable or it.hidden or it.retired_at is not null or it.sell_price is null then raise exception 'item_unavailable'; end if;
    clean := clean || jsonb_build_object('item_id', it.id, 'qty', q);
  end loop;
  res := public.online_order_save2(null, sub, ch.location_id, ch.id, p->>'name', p->>'mobile', p->>'address', clean, p->>'delivery_mode', null, null, 0, 0, 0, null, null, p->>'note',
                                   sub::text, p->>'source', p->>'pay_mode', p->>'pay_mode_other', p->>'pay_ref', null, false);
  return jsonb_build_object('order_no', res->'order_no', 'status', res->'status', 'subtotal', res->'subtotal', 'dup', coalesce((res->>'dup')::boolean, false));
end $$;

create or replace function public.web_order_submit(p_channel text, p_submission uuid, p_name text, p_mobile text, p_address text, p_delivery_mode text, p_lines jsonb, p_note text,
  p_source text default null, p_pay_mode text default null, p_pay_ref text default null, p_key_hash text default null, p_captcha_ok boolean default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ch public.sales_channels; pl jsonb; res jsonb; fid bigint; mx int; win int; c int; k text := coalesce(p_key_hash, '');
begin
  if not (public._inb_is_bot() or public.is_owner()) then raise exception 'not allowed'; end if;
  if not public.rule_on('web_form_on') then return jsonb_build_object('off', true); end if;
  if p_submission is null then raise exception 'bad_input'; end if;
  select * into ch from public.sales_channels where code = p_channel and kind = 'web_form' and active;
  if not found then return jsonb_build_object('ok', false, 'error', 'channel_not_found'); end if;
  if public.rule_on('web_form_captcha_on') and p_captcha_ok is not true then return jsonb_build_object('ok', false, 'error', 'captcha_required'); end if;
  -- same submission twice must never count as spam: an existing order is just returned
  if exists (select 1 from public.online_orders where channel_id = ch.id and external_ref = p_submission::text) then
    return jsonb_build_object('ok', true) || public._web_order_run(jsonb_build_object('channel', p_channel, 'submission', p_submission));
  end if;
  mx := coalesce(public.rule_num('web_form_rate_max'), 0)::int; win := greatest(1, coalesce(public.rule_num('web_form_rate_window_min'), 60)::int);
  if mx > 0 then
    select count(*) into c from public.intake_hits where channel_id = ch.id and key_hash = k and at > now() - make_interval(mins => win);
    if c >= mx then return jsonb_build_object('ok', false, 'error', 'rate_limited'); end if;
  end if;
  insert into public.intake_hits (channel_id, key_hash) values (ch.id, k);
  -- whitelist: only the necessary fields are kept
  pl := jsonb_build_object('channel', p_channel, 'submission', p_submission, 'name', left(btrim(p_name), 80), 'mobile', left(p_mobile, 30), 'address', left(p_address, 300),
          'delivery_mode', p_delivery_mode, 'lines', p_lines, 'note', left(p_note, 300), 'source', left(p_source, 80), 'pay_mode', p_pay_mode, 'pay_ref', left(p_pay_ref, 80));
  begin
    res := public._web_order_run(pl);
  exception when others then
    if sqlerrm ~ '^(bad_|item_|customer_name|address_required|no_lines|no_price|too_long|advance_|channel_not_found|pay_mode_other)' then
      return jsonb_build_object('ok', false, 'error', split_part(sqlerrm, ':', 1));
    end if;
    fid := public._intake_fail('web_order', ch.id, p_submission::text, sqlerrm, pl);
    return jsonb_build_object('ok', false, 'queued', true, 'failure_id', fid);
  end;
  return jsonb_build_object('ok', true) || res;
end $$;

-- the catalogue for the public form: ONLY active + sellable + visible + priced items; the price is for display, the server recomputes
create or replace function public.web_form_catalog(p_channel text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._inb_is_bot() or public.is_owner()) then raise exception 'not allowed'; end if;
  if not public.rule_on('web_form_on') then return jsonb_build_object('off', true); end if;
  if not exists (select 1 from public.sales_channels where code = p_channel and kind = 'web_form' and active) then return jsonb_build_object('ok', false, 'error', 'channel_not_found'); end if;
  return jsonb_build_object('ok', true, 'items', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'name_bn', i.name_bn, 'name_en', i.name_en, 'unit', i.unit, 'price', i.sell_price) order by i.name_bn)
     from public.items i where i.is_active and i.sellable and not i.hidden and i.retired_at is null and i.sell_price is not null), '[]'::jsonb));
end $$;

-- share link / embed code for the owner's phone (the public URL is a setting; nothing is made up before the function exists)
create or replace function public.web_form_embed(p_channel text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare u text := nullif(btrim(coalesce(public.rule_val('web_form_public_url') #>> '{}', '')), '');
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.sales_channels where code = p_channel and kind = 'web_form') then raise exception 'channel_not_found'; end if;
  if u is null then return jsonb_build_object('configured', false); end if;
  return jsonb_build_object('configured', true, 'link', rtrim(u, '/') || '?c=' || p_channel,
    'embed', '<iframe src="' || rtrim(u, '/') || '?c=' || p_channel || '" style="width:100%;max-width:480px;height:720px;border:0" loading="lazy"></iframe>');
end $$;

-- =====================================================================
-- H6 failed list + retry; dup flags
-- =====================================================================
create or replace function public.intake_failures_list(p_state text default null, p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not (public.is_owner() or public.can_do('POS', 'approve')) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
    select f.id, f.kind, f.channel_id, f.external_id, f.error, f.attempts, f.next_try_at, f.last_try_at, f.state, f.created_at, f.done_at
      from public.intake_failures f where p_state is null or f.state = p_state order by f.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
end $$;

create or replace function public.intake_retry_due(p_limit int default 20) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f public.intake_failures; mt int := greatest(1, coalesce(public.rule_num('intake_max_tries'), 5)::int); ok int := 0; bad int := 0; dead int := 0; res jsonb; err text;
begin
  if not (public._inb_is_bot() or public.is_owner()) then raise exception 'not allowed'; end if;
  for f in select * from public.intake_failures where state = 'failed' and next_try_at <= now() order by id limit least(greatest(coalesce(p_limit, 20), 1), 200) for update skip locked loop
    begin
      if f.kind = 'message' then res := public._inb_insert_message(f.payload);
      elsif f.kind = 'web_order' then res := public._web_order_run(f.payload);
      else raise exception 'not_retryable'; end if;
      update public.intake_failures set state = 'done', attempts = attempts + 1, last_try_at = now(), done_at = now(), error = null where id = f.id;
      ok := ok + 1;
    exception when others then
      err := sqlerrm;
      update public.intake_failures set attempts = attempts + 1, last_try_at = now(), error = left(err, 500),
          state = case when attempts + 1 >= mt then 'dead' else 'failed' end,
          next_try_at = now() + make_interval(mins => greatest(1, coalesce(public.rule_num('intake_retry_min'), 5)::int) * (attempts + 1)) where id = f.id;
      if f.attempts + 1 >= mt then dead := dead + 1; else bad := bad + 1; end if;
    end;
  end loop;
  return jsonb_build_object('done', ok, 'failed_again', bad, 'dead', dead);
end $$;

create or replace function public.intake_failure_dismiss(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if nullif(btrim(p_note), '') is null then raise exception 'reason_required'; end if;
  update public.intake_failures set state = 'dead', note = left(btrim(p_note), 300), payload = null where id = p_id and state in ('failed', 'rejected');
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('id', p_id, 'state', 'dead');
end $$;

create or replace function public.order_dup_flags_list(p_loc int default null, p_state text default 'open') returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'order_a', d.order_a, 'order_b', d.order_b, 'order_no_a', a.order_no, 'order_no_b', b.order_no, 'channel_a', a.channel, 'channel_b', b.channel,
        'day', d.day, 'items', d.items, 'state', d.state, 'location_id', d.location_id) order by d.id desc)
     from public.order_dup_flags d join public.online_orders a on a.id = d.order_a join public.online_orders b on b.id = d.order_b
     where public.can_loc(d.location_id) and (p_loc is null or d.location_id = p_loc) and (p_state is null or d.state = p_state)), '[]'::jsonb);
end $$;

create or replace function public.order_dup_flag_review(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.order_dup_flags;
begin
  select * into d from public.order_dup_flags where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public.is_active() or not public.can_do('POS', 'approve') or not public.can_loc(d.location_id) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_note), '') is null then raise exception 'reason_required'; end if;
  update public.order_dup_flags set state = 'reviewed', review_note = left(btrim(p_note), 300), reviewed_by = auth.uid(), reviewed_at = now() where id = p_id;
  return jsonb_build_object('id', p_id, 'state', 'reviewed');
end $$;

-- =====================================================================
-- re-created: online_orders_list / online_order_get (latest = phase61) + bos76 mask and view audit
-- =====================================================================
create or replace function public.online_orders_list(p_loc int default null, p_status text default null, p_from date default null, p_to date default null, p_limit int default 100) returns jsonb
language plpgsql security definer set search_path = public as $$   -- bos76: was STABLE (now writes the view audit)
declare r jsonb;
begin
  if not public.is_active() or not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  r := coalesce((select jsonb_agg(to_jsonb(z) order by z.created_at desc) from (
    select o.id, o.order_no, o.location_id, o.channel, o.customer_name,
           case when public._inb_contact_ok(o.location_id) then o.customer_mobile end as customer_mobile,   -- bos76
           o.delivery_mode, o.delivery_date, o.subtotal, o.discount, o.delivery_charge, o.advance,
           o.subtotal - o.discount + o.delivery_charge - o.advance as balance, o.status, o.sale_id, o.created_at,
           o.channel_id, o.is_draft, not public._inb_contact_ok(o.location_id) as masked                           -- bos76
      from public.online_orders o
     where (p_loc is null or o.location_id = p_loc) and public.can_loc(o.location_id) and (p_status is null or o.status = p_status)
       and (p_from is null or o.created_at::date >= p_from) and (p_to is null or o.created_at::date <= p_to)
     order by o.created_at desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
  if exists (select 1 from jsonb_array_elements(r) e where (e->>'masked')::boolean is false) then   -- bos76
    perform public._inb_audit_view('online_orders', 'list', jsonb_build_object('count', jsonb_array_length(r), 'loc', p_loc, 'status', p_status));
  end if;
  return r;
end $$;

create or replace function public.online_order_get(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$   -- bos76: was STABLE
declare o public.online_orders; ok boolean; j jsonb;
begin
  select * into o from public.online_orders where id = p_id;
  if not found or not public.is_active() or not public.can_do('POS', 'view') or not public.can_loc(o.location_id) then raise exception 'not allowed'; end if;
  ok := public._inb_contact_ok(o.location_id);                                                                -- bos76
  if ok then perform public._inb_audit_view('online_orders', o.id::text, jsonb_build_object('fields', 'customer_mobile,address')); end if;   -- bos76
  j := to_jsonb(o) - 'sale_client';
  if not ok then j := (j - 'customer_mobile' - 'address') || jsonb_build_object('masked', true); end if;      -- bos76
  return j || jsonb_build_object('events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_status, 'to', e.to_status, 'note', e.note, 'by', e.by_staff, 'at', e.at) order by e.id)
                                                                                  from public.online_order_events e where e.order_id = o.id), '[]'::jsonb));
end $$;

-- =====================================================================
-- RLS + privileges
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array['sales_channels', 'intake_bots', 'inbound_messages', 'inbound_message_events', 'intake_failures', 'intake_hits', 'order_dup_flags'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_sel', t);
  end loop;
end $$;
grant select (id, code, kind, other_text, name_bn, location_id, role_code, active, created_at, updated_at) on public.sales_channels to authenticated;
grant select (id, channel_id, location_id, external_id, msg_time, received_at, status, linked_order_id, draft_order_id, seen_by, seen_at) on public.inbound_messages to authenticated;   -- text / handle / name / attachment: only via inbox_get (audited)
grant select on public.inbound_message_events, public.order_dup_flags to authenticated;
grant select (channel_id, external_ref, source, pay_mode, pay_mode_other, pay_ref, is_draft, draft_note, draft_verified_by, draft_verified_at, inbox_msg_id) on public.online_orders to authenticated;
create policy sales_channels_sel on public.sales_channels for select to authenticated using (public.is_active());
create policy inbound_messages_sel on public.inbound_messages for select to authenticated using (public.can_do('POS', 'view') and public.can_loc(location_id));
create policy inbound_message_events_sel on public.inbound_message_events for select to authenticated
  using (exists (select 1 from public.inbound_messages m where m.id = msg_id and public.can_do('POS', 'view') and public.can_loc(m.location_id)));
create policy order_dup_flags_sel on public.order_dup_flags for select to authenticated using (public.can_do('POS', 'view') and public.can_loc(location_id));
revoke usage, select on sequence public.sales_channels_id_seq, public.inbound_messages_id_seq, public.inbound_message_events_id_seq, public.intake_failures_id_seq, public.intake_hits_id_seq, public.order_dup_flags_id_seq from public, anon, authenticated;

-- phone / address column hide follows the switch (direct table reads); the functions above are the way to read them with the mask + audit
create or replace function public._inb_pii_cols76() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.key = 'inbox_pii_guard_on' then
    if coalesce((new.value #>> '{}')::boolean, (new.default_value #>> '{}')::boolean, false) then
      revoke select (customer_mobile, address) on public.online_orders from authenticated;
    else
      grant select (customer_mobile, address) on public.online_orders to authenticated;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists rules_pii76 on public.rules;
create trigger rules_pii76 after insert or update on public.rules for each row execute function public._inb_pii_cols76();

revoke all on function public.intake_bot_set(uuid, boolean), public.sales_channel_save(int, text, text, text, text, int, text, text, boolean), public.sales_channels_list(boolean),
  public.inbound_message_receive(text, text, text, text, text, text, timestamptz, text, boolean), public.inbox_list(int, text, int), public.inbox_get(bigint), public.inbox_set_status(bigint, text, text),
  public.inbox_board(int), public.online_order_save2(uuid, uuid, int, int, text, text, text, jsonb, text, text, date, numeric, numeric, numeric, text, text, text, text, text, text, text, text, bigint, boolean),
  public.online_order_draft_verify(uuid, text), public.web_order_submit(text, uuid, text, text, text, text, jsonb, text, text, text, text, text, boolean), public.web_form_catalog(text), public.web_form_embed(text),
  public.intake_failures_list(text, int), public.intake_retry_due(int), public.intake_failure_dismiss(bigint, text), public.order_dup_flags_list(int, text), public.order_dup_flag_review(bigint, text),
  public.online_orders_list(int, text, date, date, int), public.online_order_get(uuid), public.inbound_sig_verify(text, text, text) from public, anon;
grant execute on function public.intake_bot_set(uuid, boolean), public.sales_channel_save(int, text, text, text, text, int, text, text, boolean), public.sales_channels_list(boolean),
  public.inbound_message_receive(text, text, text, text, text, text, timestamptz, text, boolean), public.inbox_list(int, text, int), public.inbox_get(bigint), public.inbox_set_status(bigint, text, text),
  public.inbox_board(int), public.online_order_save2(uuid, uuid, int, int, text, text, text, jsonb, text, text, date, numeric, numeric, numeric, text, text, text, text, text, text, text, text, bigint, boolean),
  public.online_order_draft_verify(uuid, text), public.web_order_submit(text, uuid, text, text, text, text, jsonb, text, text, text, text, text, boolean), public.web_form_catalog(text), public.web_form_embed(text),
  public.intake_failures_list(text, int), public.intake_retry_due(int), public.intake_failure_dismiss(bigint, text), public.order_dup_flags_list(int, text), public.order_dup_flag_review(bigint, text),
  public.online_orders_list(int, text, date, date, int), public.online_order_get(uuid), public.inbound_sig_verify(text, text, text) to authenticated;
revoke all on function public._inb_ro76(), public._inb_audit76(), public._oo_draft_guard76(), public._oo_dup76(), public._inb_is_bot(), public._inb_gate(int, text), public._inb_contact_ok(int),
  public._inb_audit_view(text, text, jsonb), public._inb_kind_text(text), public._inb_hmac_sha256(bytea, bytea), public._intake_fail(text, int, text, text, jsonb, text), public._inb_insert_message(jsonb),
  public._web_order_run(jsonb), public._inb_pii_cols76() from public, anon, authenticated;
notify pgrst, 'reload schema';
