-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase86.sql there and is already pasted on the live database under that name.
-- Renumbered to phase512.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 512 (bos86) - Step Tg: Telegram as a sales / message channel (pull-in only, no auto-reply).
-- Run AFTER phase76 (and 77..79). Additive + idempotent (paste twice = no error). No old phase file is changed.
-- Re-created (latest definition = phase76, only bos86 lines changed): sales_channel_save, inbox_board.
--
--   Tg1 sales_channels.kind accepts 'telegram' (old check dropped and re-added in one block). A telegram channel needs an account ref (the bot's id/name, never shown to staff).
--   Tg2 telegram_message_receive(): intake into inbound_messages (same table, same inbox_list / inbox_get / inbox_set_status, same PII mask + view audit).
--       Idempotent on (channel, update_id) = (channel_id, external_id). Chat id is kept as handle 'tg:<chat_id>'. NO reply to the customer, NO order made, NO AI call.
--   Tg3 verification: Telegram sends the secret_token in header X-Telegram-Bot-Api-Secret-Token. Only its SHA-256 is stored (telegram_secrets, closed table);
--       the Edge function hashes the header and the database compares (constant time). A wrong / missing token is logged as a 'rejected' bad_signature line (no body).
--   Tg4 telegram_chat_link / telegram_chat_unlink / telegram_chat_info: link a Telegram chat to a customer and / or an order (inbox actions, audited, mask-aware).
--       An order made from a telegram message (online_order_save2 p_msg_id) links its chat automatically.
--   Tg5 intake-bot role compatibility: the receiver accepts an intake_bots user OR (if it ever exists) a user with role code 'intake_bot'. The receiver itself needs no POS permission,
--       so a role that can create orders but cannot enter POS works. Nothing here depends on that role existing.
-- Switch (default OFF): telegram_intake_on (also needs inbox_on).
-- ============================================================

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('telegram_intake_on', 'pos', 'switch', 'false', null, null, null, null, 'টেলিগ্রাম বার্তা ঢোকা চালু', 'Telegram বার্তা intake চালু', 'Telegram message intake is on',
  'বাইরের সংযোগ (Edge ফাংশন + বট) তৈরি না হওয়া পর্যন্ত এটি চালু করলেও কিছু আসবে না। উত্তর নিজে থেকে যায় না।', 'Nothing arrives until the Edge function and the bot are set up. No reply is ever sent automatically.', 640)
 on conflict (key) do nothing;

-- =====================================================================
-- Tg1 channel kind
-- =====================================================================
do $$
declare c record;
begin
  for c in select conname from pg_constraint
            where conrelid = 'public.sales_channels'::regclass and contype = 'c' and conname <> 'sales_channels_kind_tg86' and pg_get_constraintdef(oid) like '%web_form%' loop
    execute format('alter table public.sales_channels drop constraint %I', c.conname);
  end loop;
  if not exists (select 1 from pg_constraint where conrelid = 'public.sales_channels'::regclass and conname = 'sales_channels_kind_tg86') then
    alter table public.sales_channels add constraint sales_channels_kind_tg86
      check (kind in ('web_form', 'facebook', 'instagram', 'whatsapp', 'telegram', 'phone', 'walkin', 'other'));
  end if;
end $$;

create or replace function public.sales_channel_save(p_id int, p_code text, p_kind text, p_other text, p_name text, p_loc int, p_role text, p_account_ref text, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.sales_channels;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_kind not in ('web_form', 'facebook', 'instagram', 'whatsapp', 'telegram', 'phone', 'walkin', 'other') then raise exception 'bad_kind'; end if;   -- bos86: + telegram
  if p_kind = 'telegram' and nullif(btrim(p_account_ref), '') is null then raise exception 'account_ref_required'; end if;                           -- bos86
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

-- =====================================================================
-- Tg3 secret token (only the SHA-256 is stored)
-- =====================================================================
create table if not exists public.telegram_secrets (
  channel_id int primary key references public.sales_channels(id),
  secret_hash text not null check (secret_hash ~ '^[0-9a-f]{64}$'),
  set_by uuid, set_at timestamptz not null default now()
);

create or replace function public._tg_hash(p text) returns text language sql immutable set search_path = public as $$
  select encode(sha256(convert_to(coalesce(p, ''), 'UTF8')), 'hex');
$$;

-- constant-time compare of two hex hashes
create or replace function public._tg_hash_eq(p_a text, p_b text) returns boolean language plpgsql immutable set search_path = public as $$
declare diff int := 0; i int;
begin
  if p_a is null or p_b is null or p_a !~ '^[0-9a-f]{64}$' or p_b !~ '^[0-9a-f]{64}$' then return false; end if;
  for i in 1..64 loop diff := diff | (ascii(substr(p_a, i, 1)) # ascii(substr(p_b, i, 1))); end loop;
  return diff = 0;
end $$;

create or replace function public._tg_actor_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public._inb_is_bot() or public.is_owner()
      or (public.is_active() and exists (select 1 from public.user_roles ur where ur.user_id = auth.uid() and ur.role_code = 'intake_bot'));   -- Tg5: only if such a role is ever created
$$;

-- owner sets (or rotates) the secret_token of one telegram channel; the database keeps only its hash. Do not log the argument.
create or replace function public.telegram_secret_set(p_channel int, p_secret text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ch public.sales_channels;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into ch from public.sales_channels where id = p_channel and kind = 'telegram';
  if not found then raise exception 'channel_not_found'; end if;
  if p_secret is null or p_secret !~ '^[A-Za-z0-9_-]{16,255}$' then raise exception 'bad_secret: 16-255 characters, letters, digits, _ and - only'; end if;
  insert into public.telegram_secrets (channel_id, secret_hash, set_by) values (ch.id, public._tg_hash(p_secret), auth.uid())
    on conflict (channel_id) do update set secret_hash = excluded.secret_hash, set_by = excluded.set_by, set_at = now();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'update', 'telegram_secrets', ch.id::text, jsonb_build_object('channel_id', ch.id, 'event', 'secret_set'));
  return jsonb_build_object('channel_id', ch.id, 'set', true);
end $$;

-- owner's health view: which telegram channels exist, is a secret set, last message, wrong-token count in 24h
create or replace function public.telegram_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return jsonb_build_object('switch_on', public.rule_on('telegram_intake_on') and public.rule_on('inbox_on'),
    'rejected_24h', (select count(*) from public.intake_failures where kind = 'bad_signature' and state = 'rejected' and created_at > now() - interval '24 hours'
                       and coalesce(payload->>'kind', '') = 'telegram'),
    'channels', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'code', c.code, 'name', c.name_bn, 'active', c.active, 'location_id', c.location_id,
        'secret_set', exists (select 1 from public.telegram_secrets s where s.channel_id = c.id),
        'last_at', (select max(received_at) from public.inbound_messages m where m.channel_id = c.id)) order by c.id)
        from public.sales_channels c where c.kind = 'telegram'), '[]'::jsonb));
end $$;

-- =====================================================================
-- Tg2 intake (called by the Edge function logged in as the intake bot)
-- =====================================================================
create or replace function public.telegram_message_receive(p_channel_code text, p_secret_hash text, p_update_id bigint, p_chat_id bigint, p_username text, p_name text,
                                                           p_text text, p_msg_time timestamptz, p_attachment text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ch public.sales_channels; sh text; pl jsonb; res jsonb; fid bigint; nm text;
begin
  if not public._tg_actor_ok() then raise exception 'not allowed'; end if;
  if not public.rule_on('inbox_on') or not public.rule_on('telegram_intake_on') then return jsonb_build_object('off', true); end if;
  if p_update_id is null or p_update_id < 0 or p_chat_id is null or char_length(coalesce(p_channel_code, '')) not between 1 and 30
     or char_length(coalesce(p_text, '')) > 20000 or char_length(coalesce(p_attachment, '')) > 500 then raise exception 'bad_input'; end if;
  select * into ch from public.sales_channels where code = p_channel_code and kind = 'telegram' and active;
  if not found then
    fid := public._intake_fail('bad_signature', null, p_update_id::text, 'channel_not_found', jsonb_build_object('kind', 'telegram'), 'rejected');
    return jsonb_build_object('rejected', 'channel_not_found', 'failure_id', fid);
  end if;
  select secret_hash into sh from public.telegram_secrets where channel_id = ch.id;
  if sh is null or not public._tg_hash_eq(sh, p_secret_hash) then
    -- a wrong / missing secret_token is never stored as a message; only the fact (no body, no chat id) goes to the failed list
    fid := public._intake_fail('bad_signature', ch.id, p_update_id::text, case when sh is null then 'secret_not_set' else 'bad_signature' end, jsonb_build_object('kind', 'telegram'), 'rejected');
    return jsonb_build_object('rejected', case when sh is null then 'secret_not_set' else 'bad_signature' end, 'failure_id', fid);
  end if;
  nm := nullif(btrim(coalesce(p_name, '')), '');
  if nm is null and nullif(btrim(coalesce(p_username, '')), '') is not null then nm := '@' || btrim(p_username); end if;
  pl := jsonb_build_object('kind', 'telegram', 'account_ref', ch.account_ref, 'external_id', p_update_id::text, 'handle', 'tg:' || p_chat_id::text, 'name', nm, 'text', p_text,
                           'msg_time', p_msg_time, 'attachment', p_attachment);
  begin
    res := public._inb_insert_message(pl);
  exception when others then
    fid := public._intake_fail('message', ch.id, p_update_id::text, sqlerrm, pl);
    return jsonb_build_object('failed', true, 'queued', true, 'failure_id', fid);
  end;
  return res;
end $$;

-- =====================================================================
-- Tg4 link a telegram chat to a customer / an order
-- =====================================================================
create table if not exists public.telegram_chat_links (
  id bigint generated always as identity primary key,
  channel_id int not null references public.sales_channels(id),
  chat_id text not null check (chat_id ~ '^-?[0-9]{1,20}$'),
  customer_id uuid references public.customers(id),
  order_id uuid references public.online_orders(id),
  note text check (note is null or char_length(note) <= 300),
  linked_by uuid, linked_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unlinked_at timestamptz, unlink_note text,
  unique (channel_id, chat_id)
);

create or replace function public._tg_chat_of(p_handle text) returns text language sql immutable set search_path = public as $$
  select case when p_handle ~ '^tg:-?[0-9]{1,20}$' then substr(p_handle, 4) end;
$$;

create or replace function public.telegram_chat_link(p_msg_id bigint, p_customer uuid default null, p_order uuid default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.inbound_messages; c public.sales_channels; chat text; o public.online_orders; l public.telegram_chat_links;
begin
  select * into m from public.inbound_messages where id = p_msg_id;
  if not found then raise exception 'not_found'; end if;
  perform public._inb_gate(m.location_id, 'enter');
  select * into c from public.sales_channels where id = m.channel_id;
  chat := public._tg_chat_of(m.customer_handle);
  if c.kind <> 'telegram' or chat is null then raise exception 'not_telegram'; end if;
  if p_customer is null and p_order is null then raise exception 'bad_input'; end if;
  if p_customer is not null and not exists (select 1 from public.customers where id = p_customer and active) then raise exception 'customer_not_found'; end if;
  if p_order is not null then
    select * into o from public.online_orders where id = p_order;
    if not found or o.location_id <> m.location_id then raise exception 'order_not_found'; end if;
  end if;
  insert into public.telegram_chat_links (channel_id, chat_id, customer_id, order_id, note, linked_by)
    values (m.channel_id, chat, p_customer, p_order, left(nullif(btrim(p_note), ''), 300), auth.uid())
    on conflict (channel_id, chat_id) do update set customer_id = coalesce(excluded.customer_id, case when public.telegram_chat_links.unlinked_at is null then public.telegram_chat_links.customer_id end),
        order_id = coalesce(excluded.order_id, case when public.telegram_chat_links.unlinked_at is null then public.telegram_chat_links.order_id end),
        note = coalesce(excluded.note, public.telegram_chat_links.note), linked_by = auth.uid(), updated_at = now(), unlinked_at = null, unlink_note = null
    returning * into l;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'update', 'telegram_chat_links', l.id::text,
            jsonb_build_object('event', 'link', 'channel_id', l.channel_id, 'msg_id', m.id, 'customer_id', l.customer_id, 'order_id', l.order_id));
  return jsonb_build_object('id', l.id, 'customer_id', l.customer_id, 'order_id', l.order_id);
end $$;

create or replace function public.telegram_chat_unlink(p_msg_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.inbound_messages; l public.telegram_chat_links;
begin
  select * into m from public.inbound_messages where id = p_msg_id;
  if not found then raise exception 'not_found'; end if;
  perform public._inb_gate(m.location_id, 'enter');
  if nullif(btrim(p_reason), '') is null then raise exception 'reason_required'; end if;
  update public.telegram_chat_links set unlinked_at = now(), unlink_note = left(btrim(p_reason), 300), updated_at = now(), linked_by = auth.uid()
    where channel_id = m.channel_id and chat_id = public._tg_chat_of(m.customer_handle) and unlinked_at is null returning * into l;
  if not found then raise exception 'not_found'; end if;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'update', 'telegram_chat_links', l.id::text, jsonb_build_object('event', 'unlink', 'channel_id', l.channel_id, 'msg_id', m.id));
  return jsonb_build_object('id', l.id, 'unlinked', true);
end $$;

-- what is known about the chat of one message: link, customer, orders made from this chat, how many messages. Customer name / mobile only for people allowed to see contacts (audited).
create or replace function public.telegram_chat_info(p_msg_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.inbound_messages; c public.sales_channels; chat text; l public.telegram_chat_links; ok boolean; cu public.customers; oo public.online_orders;
begin
  select * into m from public.inbound_messages where id = p_msg_id;
  if not found then raise exception 'not_found'; end if;
  perform public._inb_gate(m.location_id, 'view');
  select * into c from public.sales_channels where id = m.channel_id;
  chat := public._tg_chat_of(m.customer_handle);
  if c.kind <> 'telegram' or chat is null then raise exception 'not_telegram'; end if;
  ok := public._inb_contact_ok(m.location_id);
  select * into l from public.telegram_chat_links where channel_id = m.channel_id and chat_id = chat and unlinked_at is null;
  if found and l.customer_id is not null then select * into cu from public.customers where id = l.customer_id; end if;
  if found and l.order_id is not null then select * into oo from public.online_orders where id = l.order_id; end if;
  if ok and found and l.customer_id is not null then
    perform public._inb_audit_view('telegram_chat_links', l.id::text, jsonb_build_object('fields', 'customer_name,customer_mobile'));
  end if;
  return jsonb_build_object('msg_id', m.id, 'linked', l.id is not null, 'masked', not ok,
    'customer_id', l.customer_id, 'customer_name', case when ok then cu.name end, 'customer_mobile', case when ok then cu.mobile end,
    'order_id', l.order_id, 'order_no', oo.order_no, 'note', l.note,
    'message_count', (select count(*) from public.inbound_messages x where x.channel_id = m.channel_id and x.customer_handle = m.customer_handle),
    'orders', coalesce((select jsonb_agg(jsonb_build_object('id', o2.id, 'order_no', o2.order_no, 'status', o2.status) order by o2.created_at)
                          from public.online_orders o2 where o2.id in (select x.linked_order_id from public.inbound_messages x
                                                                        where x.channel_id = m.channel_id and x.customer_handle = m.customer_handle and x.linked_order_id is not null)), '[]'::jsonb));
end $$;

-- an order made from a telegram message links its chat to that order automatically
create or replace function public._tg_autolink86() returns trigger language plpgsql security definer set search_path = public as $$
declare chat text;
begin
  if new.linked_order_id is not null and new.linked_order_id is distinct from old.linked_order_id
     and exists (select 1 from public.sales_channels c where c.id = new.channel_id and c.kind = 'telegram') then
    chat := public._tg_chat_of(new.customer_handle);
    if chat is not null then
      insert into public.telegram_chat_links (channel_id, chat_id, order_id, linked_by) values (new.channel_id, chat, new.linked_order_id, auth.uid())
        on conflict (channel_id, chat_id) do update set order_id = excluded.order_id, updated_at = now(), unlinked_at = null, unlink_note = null;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists inbound_messages_tg86 on public.inbound_messages;
create trigger inbound_messages_tg86 after update on public.inbound_messages for each row execute function public._tg_autolink86();

-- =====================================================================
-- re-created: inbox_board (latest = phase76) + bos86: telegram channels shown beside Meta channels
-- =====================================================================
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
        from public.sales_channels c where c.active and c.kind in ('facebook', 'instagram', 'whatsapp', 'telegram') and (c.location_id is null or c.location_id = any (l))), '[]'::jsonb));   -- bos86: + telegram
end $$;

-- =====================================================================
-- RLS + privileges
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array['telegram_secrets', 'telegram_chat_links'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;
revoke usage, select on sequence public.telegram_chat_links_id_seq from public, anon, authenticated;

revoke all on function public.telegram_secret_set(int, text), public.telegram_status(), public.telegram_message_receive(text, text, bigint, bigint, text, text, text, timestamptz, text),
  public.telegram_chat_link(bigint, uuid, uuid, text), public.telegram_chat_unlink(bigint, text), public.telegram_chat_info(bigint) from public, anon;
grant execute on function public.telegram_secret_set(int, text), public.telegram_status(), public.telegram_message_receive(text, text, bigint, bigint, text, text, text, timestamptz, text),
  public.telegram_chat_link(bigint, uuid, uuid, text), public.telegram_chat_unlink(bigint, text), public.telegram_chat_info(bigint) to authenticated;
revoke all on function public._tg_hash(text), public._tg_hash_eq(text, text), public._tg_actor_ok(), public._tg_chat_of(text), public._tg_autolink86() from public, anon, authenticated;
notify pgrst, 'reload schema';
