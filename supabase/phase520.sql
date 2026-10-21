-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase94.sql there and is already pasted on the live database under that name.
-- Renumbered to phase520.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 520 (bos94) - STEP Sec: fixes from the security review of phases 72-519 (docs/briefs_p2p3/step_Sec_REPORT.md).
--   Paste AFTER phase515 and after 90, 91, 92, 93, 95 (docs/PASTE_ORDER.md). Additive and paste-twice safe: create-or-replace functions, one new table,
--   new rules, new recommendation rows. Nothing is deleted. EVERY NEW SWITCH / LIMIT IS OFF / EMPTY BY DEFAULT = today's behaviour; the owner decides (see the report).
--   Functions re-created from their LATEST definition (changed lines carry the tag bos94, every older bosNN tag kept):
--     _scan_photo_ok, scan_get (H1) | _sale_stock_out (M5) | _intake_fail, _inb_insert_message (M3) | invoice_data92, invoice_share_log92 (L2)
--     inbound_message_receive, web_order_submit get ONE extra argument at the end (p_proof_hash, default null) - the old call shapes still work (M2).
--   H1  The photo of a purchase bill and its path follow the cost right (same rule as the extracted text).
--   M1  pii_exposure_report94(): owner view of who can read customer phone / address directly; recommendation row inbox_pii_guard_on already says ON (default NOT changed).
--   M2  Optional proof secrets (hash only, like the Telegram secret token): scope 'meta' and 'web_form'. Not set = exactly today's behaviour.
--   M3  intake_purge(days), optional limits intake_reject_max_per_min and inbox_rate_max_per_min (empty = no limit). The edge sources check their token BEFORE any sign-in.
--   M4  scan_ai_gate94(job): the edge function asks it before every paid AI call; rules scan_ai_max_per_job / scan_ai_max_per_user_day (empty = unlimited = today).
--   M5  rule offline_sale_max_age (hours, empty = today): an older sale no longer skips the stock guard.
--       (the same 3 lines are also merged into phase515's _sale_stock_out, identical text, so a repeated paste of phase515 cannot undo it - docs/PASTE_ORDER.md rule D.1)
--   M6  execute revoked from anon / public on the re-created functions; authenticated keeps what it had. anon_exec_audit94() lists what anon can still run.
--   L2  invoice_share_log92 collapses the same person + sale + channel within a minute; optional rule invoice_own_sales_only (default off).
--   Also: acct_autopost_runs_list (scheduler run history for owner / accounts viewers), recommendation rows for partner_base_estimate, packaging_return_mode and the new rules.
-- ============================================================

-- ---------- 0. guard ----------
do $g$
declare miss text := '';
begin
  if to_regclass('public.intake_failures') is null then miss := miss || ' 76'; end if;
  if to_regprocedure('public._tg_hash_eq(text,text)') is null then miss := miss || ' 86'; end if;
  if not exists (select 1 from public.rules where key = 'partner_base_estimate') then miss := miss || ' 80'; end if;
  if to_regclass('public.setup_rec_defs81') is null then miss := miss || ' 81'; end if;
  if to_regclass('public.acct_autopost_runs85') is null then miss := miss || ' 85'; end if;
  if to_regprocedure('public._sale_stock_out()') is null or position('bos89' in pg_get_functiondef('public._sale_stock_out()'::regprocedure)) = 0 then miss := miss || ' 89'; end if;
  if to_regclass('public.scan_jobs') is null then miss := miss || ' 90'; end if;
  if to_regclass('public.invoice_shares') is null then miss := miss || ' 92'; end if;
  if to_regclass('public.doc_template_choice') is null then miss := miss || ' 93'; end if;
  if miss <> '' then raise exception 'phase520 needs phases 76, 506, 507, 511, 512, 515, 516, 518, 519 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

-- ---------- 1. rules (all empty / off = today's behaviour) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('scan_ai_max_per_job', 'purchase', 'number', null, 'বার', null, 1, 1000,
  'Scan: একটি ছবিতে AI কতবার পড়বে (সর্বোচ্চ)', 'Scan: একটি ছবিতে AI কতবার পড়বে (max)', 'Scan: most AI readings per photo',
  'ফাঁকা = সীমা নেই (আগের মতো)। প্রতিবার AI পড়লে খরচ হয়; সীমা বসালে তার বেশি পড়া আটকে যায়।',
  'ফাঁকা = limit নেই (আগের মতো)। প্রতিবার AI পড়লে খরচ হয়; limit বসালে তার বেশি পড়া আটকে যায়।',
  'Empty = no limit (as before). Every AI reading costs money; with a limit, readings above it are refused. The security review suggested 5.', 940),
 ('scan_ai_max_per_user_day', 'purchase', 'number', null, 'বার', null, 1, 100000,
  'Scan: একজন ২৪ ঘণ্টায় AI কতবার পড়াতে পারবে (সর্বোচ্চ)', 'Scan: একজন ২৪ ঘণ্টায় AI কতবার পড়াতে পারবে (max)', 'Scan: most AI readings per person in 24 hours',
  'ফাঁকা = সীমা নেই (আগের মতো)।', 'ফাঁকা = limit নেই (আগের মতো)।', 'Empty = no limit (as before). The number is the owner''s choice; there is no built-in value.', 941),
 ('offline_sale_max_age', 'pos', 'number', null, 'ঘণ্টা', null, 1, 8760,
  'পুরোনো সময়ের বিক্রিতে স্টক-পাহারা কত ঘণ্টা পর্যন্ত ঢিলা', 'পুরোনো সময়ের sale-এ stock-পাহারা কত ঘণ্টা পর্যন্ত ঢিলা', 'Hours an old-dated sale may skip the stock guard',
  'ফাঁকা = আগের মতো (২ মিনিটের বেশি পুরোনো সময়ের বিক্রি স্টক আটকায় না)। সংখ্যা দিলে তার চেয়ে পুরোনো সময়ের বিক্রিতে স্টক-পাহারা পুরো চালু থাকে; ম্যানেজারের replay override আগের মতো চলে।',
  'ফাঁকা = আগের মতো (২ মিনিটের বেশি পুরোনো সময়ের sale stock আটকায় না)। সংখ্যা দিলে তার চেয়ে পুরোনো সময়ের sale-এ stock-পাহারা পুরো চালু থাকে; ম্যানেজারের replay override আগের মতো চলে।',
  'Empty = as before (a sale dated more than 2 minutes back never stops on stock). With a number, a sale dated older than that gets the full stock guard; a manager replay override works as before. Set it to the longest time a phone is normally offline.', 942),
 ('inbox_rate_max_per_min', 'pos', 'number', null, 'বার', null, 1, 100000,
  'ইনবক্স: এক চ্যানেলে মিনিটে সর্বোচ্চ কত বার্তা রাখা হবে', 'Inbox: এক channel-এ মিনিটে max কত message রাখা হবে', 'Inbox: most messages stored per channel per minute',
  'ফাঁকা = সীমা নেই (আগের মতো)। বেশি এলে বার্তা পরে আবার চেষ্টার তালিকায় যায়।', 'ফাঁকা = limit নেই (আগের মতো)। বেশি এলে message পরে retry তালিকায় যায়।',
  'Empty = no limit (as before). Above the limit a message goes to the retry list. The security review suggested 120.', 943),
 ('intake_reject_max_per_min', 'pos', 'number', null, 'বার', null, 1, 100000,
  'ভুল সই/টোকেনের লাইন মিনিটে সর্বোচ্চ কত রাখা হবে', 'ভুল signature/token-এর line মিনিটে max কত রাখা হবে', 'Most rejected-call lines kept per minute',
  'ফাঁকা = সীমা নেই (আগের মতো)। ভুয়া ডাকের বন্যায় তালিকা ভরে যাওয়া ঠেকায়।', 'ফাঁকা = limit নেই (আগের মতো)। ভুয়া ডাকের বন্যায় তালিকা ভরে যাওয়া ঠেকায়।',
  'Empty = no limit (as before). Stops a flood of forged calls from filling the failed list.', 944),
 ('invoice_own_sales_only', 'pos', 'switch', 'false', null, null, null, null,
  'ইনভয়েস: নিজের বিক্রি ছাড়া অন্যেরটা শুধু মালিক / POS approve দেখবে', 'Invoice: নিজের sale ছাড়া অন্যেরটা শুধু owner / POS approve দেখবে', 'Invoice: other people''s sales only for owner / POS approve',
  'বন্ধ = আগের মতো (জায়গার যে কেউ POS দিয়ে যেকোনো বিক্রির ইনভয়েস দেখতে পারে)। চালু = ক্যাশিয়ার শুধু নিজের বিক্রির ইনভয়েস দেখে ও লগ করে।',
  'বন্ধ = আগের মতো (জায়গার যে কেউ POS দিয়ে যেকোনো sale-এর invoice দেখতে পারে)। চালু = cashier শুধু নিজের sale-এর invoice দেখে ও log করে।',
  'Off = as before (anyone with POS at the place can open any sale''s invoice). On: a cashier opens and logs only his own sales'' invoices.', 945)
on conflict (key) do nothing;

-- ---------- 2. H1: the photo of a purchase bill follows the cost right ----------
CREATE OR REPLACE FUNCTION public._scan_photo_ok(p_name text, p_action text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare loc int;
begin
  if p_name is null or p_name !~ '^SCAN/[0-9]+/[A-Za-z0-9_.-]+$' or not public.is_active() then return false; end if;
  loc := split_part(p_name, '/', 2)::int;
  if p_action = 'enter' then return public.can_loc(loc) and public.has_grant('scan_upload', loc); end if;
  return exists (select 1 from public.scan_jobs j where j.image_path = p_name and public._scan_content_ok(j));   -- bos94: the photo of a purchase bill shows costs: same right as the extracted text
end $function$;


CREATE OR REPLACE FUNCTION public.scan_get(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare j public.scan_jobs; ok boolean; ev jsonb;
begin
  select * into j from public.scan_jobs where id = p_id;
  if not found or not public._scan_can_see(j) then raise exception 'not found'; end if;
  ok := public._scan_content_ok(j);
  select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'at', e.at, 'action', e.action, 'from', e.from_status, 'to', e.to_status, 'by', e.by_staff) order by e.id), '[]'::jsonb) into ev from public.scan_events e where e.job_id = j.id;
  return jsonb_build_object('id', j.id, 'kind', j.kind, 'location_id', j.location_id, 'status', j.status, 'engine', j.engine, 'image_path', case when ok then j.image_path end, 'note', j.note,   -- bos94: the photo path only with the content right
    'extract_error', j.extract_error, 'created_at', j.created_at, 'created_staff', j.created_staff, 'mine', j.created_by = auth.uid(),
    'cost_hidden', not ok, 'extracted', case when ok then j.extracted end, 'confidence', case when ok then j.confidence end, 'edited', case when ok then j.edited end,
    'dups', case when ok then j.dups end, 'warnings', case when ok and j.status in ('extracted', 'reviewed') then public._scan_warn(j, coalesce(j.edited, j.extracted, '{}'::jsonb)) end,
    'result_type', j.result_type, 'result_id', j.result_id, 'reject_reason', j.reject_reason, 'events', ev,
    'can_confirm', public.can_loc(j.location_id) and public.has_grant('scan_confirm', j.location_id) and ok);
end $function$;


-- ---------- 3. M2: optional proof secrets (hash only; the secret itself is never stored) ----------
create table if not exists public.intake_proofs94 (
  scope text primary key check (scope in ('meta', 'web_form')),
  secret_hash text not null check (secret_hash ~ '^[0-9a-f]{64}$'),
  set_by uuid, set_at timestamptz not null default now()
);
alter table public.intake_proofs94 enable row level security;
revoke all on public.intake_proofs94 from public, anon, authenticated;

-- no proof set for the scope = true (today's behaviour). Set = the caller must send the matching hash (constant-time compare). The owner is never blocked.
create or replace function public._intake_proof_ok94(p_scope text, p_hash text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare sh text;
begin
  if public.is_owner() then return true; end if;
  select secret_hash into sh from public.intake_proofs94 where scope = p_scope;
  if sh is null then return true; end if;
  return public._tg_hash_eq(sh, lower(coalesce(p_hash, '')));
end $$;

create or replace function public.intake_proof_set94(p_scope text, p_secret text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_scope is null or p_scope not in ('meta', 'web_form') then raise exception 'bad_scope'; end if;
  if p_secret is null then      -- empty secret = remove the proof = back to today's behaviour
    delete from public.intake_proofs94 where scope = p_scope;
  else
    if p_secret !~ '^[A-Za-z0-9_-]{16,255}$' then raise exception 'bad_secret: 16-255 characters, letters, digits, _ and - only'; end if;
    insert into public.intake_proofs94 (scope, secret_hash, set_by) values (p_scope, public._tg_hash(p_secret), auth.uid())
      on conflict (scope) do update set secret_hash = excluded.secret_hash, set_by = excluded.set_by, set_at = now();
  end if;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'update', 'intake_proofs94', p_scope, jsonb_build_object('scope', p_scope, 'event', case when p_secret is null then 'proof_cleared' else 'proof_set' end));
  return jsonb_build_object('scope', p_scope, 'set', p_secret is not null);
end $$;

create or replace function public.intake_proof_status94() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return jsonb_build_object('meta', exists (select 1 from public.intake_proofs94 where scope = 'meta'), 'web_form', exists (select 1 from public.intake_proofs94 where scope = 'web_form'));
end $$;

drop function if exists public.inbound_message_receive(text, text, text, text, text, text, timestamptz, text, boolean);
CREATE OR REPLACE FUNCTION public.inbound_message_receive(p_kind text, p_account_ref text, p_external_id text, p_handle text, p_name text, p_text text, p_msg_time timestamp with time zone, p_attachment text, p_signature_ok boolean, p_proof_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  if not public._intake_proof_ok94('meta', p_proof_hash) then      -- bos94: the signature result is believed only with the stored proof (when the owner has set one)
    fid := public._intake_fail('bad_signature', null, p_external_id, 'bad_proof', jsonb_build_object('kind', p_kind), 'rejected');   -- bos94
    return jsonb_build_object('rejected', 'bad_proof', 'failure_id', fid);   -- bos94
  end if;   -- bos94
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
end $function$;


drop function if exists public.web_order_submit(text, uuid, text, text, text, text, jsonb, text, text, text, text, text, boolean);
CREATE OR REPLACE FUNCTION public.web_order_submit(p_channel text, p_submission uuid, p_name text, p_mobile text, p_address text, p_delivery_mode text, p_lines jsonb, p_note text, p_source text DEFAULT NULL::text, p_pay_mode text DEFAULT NULL::text, p_pay_ref text DEFAULT NULL::text, p_key_hash text DEFAULT NULL::text, p_captcha_ok boolean DEFAULT NULL::boolean, p_proof_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ch public.sales_channels; pl jsonb; res jsonb; fid bigint; mx int; win int; c int; k text := coalesce(p_key_hash, '');
begin
  if not (public._inb_is_bot() or public.is_owner()) then raise exception 'not allowed'; end if;
  if not public.rule_on('web_form_on') then return jsonb_build_object('off', true); end if;
  if p_submission is null then raise exception 'bad_input'; end if;
  if not public._intake_proof_ok94('web_form', p_proof_hash) then return jsonb_build_object('ok', false, 'error', 'bad_proof'); end if;   -- bos94: captcha result and rate key are believed only with the stored proof (when set)
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
end $function$;


-- ---------- 4. M3: limits on the failed list + purge ----------
CREATE OR REPLACE FUNCTION public._intake_fail(p_kind text, p_channel integer, p_ext text, p_err text, p_payload jsonb, p_state text DEFAULT 'failed'::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare id_ bigint; cap94 numeric := public.rule_num('intake_reject_max_per_min');
begin
  -- bos94: a flood of forged calls must not fill the table: over the owner's per-minute limit a rejected line is counted by nobody and stored by nobody (empty rule = no limit = as before)
  if p_state = 'rejected' and cap94 is not null and cap94 > 0
     and (select count(*) from public.intake_failures where state = 'rejected' and created_at > now() - interval '1 minute') >= cap94 then return 0; end if;   -- bos94
  insert into public.intake_failures (kind, channel_id, external_id, error, payload, state, next_try_at)
    values (p_kind, p_channel, left(p_ext, 200), left(p_err, 500), p_payload, p_state,
            case when p_state = 'failed' then now() + make_interval(mins => greatest(1, coalesce(public.rule_num('intake_retry_min'), 5)::int)) end)
    returning id into id_;
  return id_;
end $function$;


CREATE OR REPLACE FUNCTION public._inb_insert_message(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ch public.sales_channels; m public.inbound_messages; n int;
begin
  select * into ch from public.sales_channels where kind = p->>'kind' and account_ref = p->>'account_ref' and active;
  if not found then raise exception 'channel_not_found'; end if;
  if ch.location_id is null then raise exception 'channel_no_location'; end if;
  -- bos94: optional per-channel limit of stored messages per minute (rule inbox_rate_max_per_min; empty = no limit = as before). The caller queues the message for a later retry.
  if public.rule_num('inbox_rate_max_per_min') is not null and public.rule_num('inbox_rate_max_per_min') > 0
     and (select count(*) from public.inbound_messages where channel_id = ch.id and received_at > now() - interval '1 minute') >= public.rule_num('inbox_rate_max_per_min') then raise exception 'rate_limited'; end if;   -- bos94
  insert into public.inbound_messages (channel_id, location_id, external_id, customer_handle, customer_name, msg_text, msg_time, attachment_ref)
    values (ch.id, ch.location_id, p->>'external_id', left(p->>'handle', 120), left(p->>'name', 120), left(p->>'text', 4000),
            nullif(p->>'msg_time', '')::timestamptz, left(p->>'attachment', 500))
    on conflict (channel_id, external_id) do nothing returning * into m;
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('duplicate', true); end if;
  insert into public.inbound_message_events (msg_id, from_status, to_status, note, by_user) values (m.id, null, 'new', 'received', auth.uid());
  return jsonb_build_object('duplicate', false, 'id', m.id);
end $function$;

create index if not exists inbound_messages_chan_time94 on public.inbound_messages (channel_id, received_at);

-- owner: delete finished / rejected / dismissed lines older than N days (the audit trail itself is never touched) and old rate-limit hits
create or replace function public.intake_purge(p_days int default 30) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int; h int;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_days is null or p_days < 1 or p_days > 3650 then raise exception 'bad_input'; end if;
  delete from public.intake_failures where state in ('rejected', 'done', 'dismissed') and created_at < now() - make_interval(days => p_days);
  get diagnostics n = row_count;
  delete from public.intake_hits where at < now() - make_interval(days => p_days);
  get diagnostics h = row_count;
  return jsonb_build_object('failures_deleted', n, 'hits_deleted', h, 'days', p_days);
end $$;

-- ---------- 5. M4: the paid AI call is counted BEFORE it is made ----------
alter table public.scan_events drop constraint if exists scan_events_action_check;
alter table public.scan_events add constraint scan_events_action_check
  check (action in ('created', 'extracted', 'extract_failed', 'saved', 'reviewed', 'confirmed', 'confirm_replay', 'rejected', 'ai_call'));

create or replace function public.scan_ai_gate94(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.scan_jobs; capj numeric := public.rule_num('scan_ai_max_per_job'); capu numeric := public.rule_num('scan_ai_max_per_user_day'); nj int; nu int;
begin
  select * into j from public.scan_jobs where id = p_id for update;
  if not found or not public._scan_can_see(j) then raise exception 'not found'; end if;
  if not (j.created_by = auth.uid() or public.has_grant('scan_confirm', j.location_id)) then raise exception 'not allowed'; end if;
  if j.status not in ('uploaded', 'extracted') then raise exception 'not_open: %', j.status; end if;
  select count(*) into nj from public.scan_events where job_id = p_id and action = 'ai_call';
  select count(*) into nu from public.scan_events where by_user = auth.uid() and action = 'ai_call' and at > now() - interval '24 hours';
  if capj is not null and nj >= capj then raise exception 'too_many_attempts'; end if;
  if capu is not null and nu >= capu then raise exception 'too_many_attempts_today'; end if;
  perform public._scan_event(p_id, 'ai_call', j.status, j.status, jsonb_build_object('n', nj + 1));
  return jsonb_build_object('ok', true, 'attempt', nj + 1, 'cap_job', capj, 'cap_user_day', capu);
end $$;

-- ---------- 6. M5: old-dated sale and the stock guard ----------
CREATE OR REPLACE FUNCTION public._sale_stock_out()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- bos89: merge of phase508 (unit_conv_required) and phase509 (offline soft stock); the original Bangla wording of the unit message is kept
declare ln jsonb; it public.items; q numeric; bq numeric; neg text; um text; soft83 boolean := false; bal83 numeric;   -- bos82 bos83
begin
  if new.status <> 'done' or new.lines is null or jsonb_typeof(new.lines) <> 'array' then return new; end if;
  -- a sale that syncs late (an offline phone) has already happened: it is recorded, it never blocks (a yellow line still tells the owner)
  neg := case when new.sold_at < now() - interval '2 minutes' then 'soft' else 'full' end;
  -- bos94: owner can limit how old a sale may be and still count as a late sync (rule offline_sale_max_age, hours; empty = no limit = as before). A manager replay override stays soft.
  if neg = 'soft' and public.rule_num('offline_sale_max_age') is not null and new.sold_at < now() - make_interval(hours => public.rule_num('offline_sale_max_age')::int)
     and coalesce(current_setting('bos.replay_override', true), '') <> '1' then neg := 'full'; end if;   -- bos94
  -- bos83: a sale replayed from the offline queue (record_sale_offline / manager override) is soft too when the owner switch offline_soft_stock is on (override: always) - flagged below
  if neg = 'full' and coalesce(current_setting('bos.offline_replay', true), '') = '1'
     and (public.rule_on('offline_soft_stock') or coalesce(current_setting('bos.replay_override', true), '') = '1') then neg := 'soft'; soft83 := true; end if;
  -- items in a fixed order, so two sales that share items can never wait on each other in a circle
  for ln in select x from jsonb_array_elements(new.lines) x where nullif(x->>'item_id', '') is not null order by x->>'item_id' loop
    select * into it from public.items where id = (ln->>'item_id')::uuid;
    if not found or not it.tracked then continue; end if;
    q := nullif(ln->>'qty', '')::numeric;
    if q is null or q <= 0 then continue; end if;
    if not (q <= 999999999) then raise exception 'bad_qty'; end if;                    -- Infinity / NaN / absurd: the sale is refused
    bq := public._base_qty(it.id, q, ln->>'unit');
    if bq is null then
      um := coalesce(public.rule_txt('unit_conv_required'), 'warn');   -- bos82: off | warn (today) | refuse
      if um = 'refuse' and neg = 'full' then raise exception 'unit_unknown' using detail = 'Unit conversion unknown for ' || it.code || ': set the conversion or sell in the base unit', hint = it.code; end if;   -- bos82
      if um = 'refuse' then   -- bos82: a sale that already happened (offline) is recorded, never lost, but flagged red
        perform public._stock_exc(new.location_id, 'stock_unit_unknown_late', 'red',
          'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — offline বিক্রি নেওয়া হয়েছে কিন্তু unit-এর conversion জানা নেই, stock কমেনি',
          'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.code) || ' — offline sale accepted but the unit conversion is unknown, stock was NOT reduced', new.id, new.sale_date, 'POS');   -- bos82
      elsif um <> 'off' then   -- bos82
      perform public._stock_exc(new.location_id, 'stock_unit_unknown', 'yellow',
        'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — এককের রূপান্তর জানা নেই, স্টক কমানো হয়নি',
        'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — the unit conversion is unknown, stock was NOT reduced', new.id, new.sale_date, 'POS');
      end if;   -- bos82
      continue;
    end if;
    if not (bq <= 999999999) then raise exception 'bad_qty'; end if;
    if round(bq, 4) = 0 then continue; end if;                                          -- under 0.00005 of a base unit: nothing to take out
    if soft83 then      -- bos83
      select b.qty into bal83 from public.stock_balance b where b.item_id = it.id and b.location_id = new.location_id;
      if coalesce(bal83, 0) < bq then
        perform public._stock_exc(new.location_id, 'offline_soft_stock', 'yellow',
          'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — offline sale, stock-এর চেয়ে বেশি; sale গ্রহণ হয়েছে, stock ঋণাত্মক হতে পারে',
          'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — offline sale above the stock on hand; accepted, stock may go negative', new.id, new.sale_date, 'POS');
      end if;
    end if;
    perform public.stock_post(it.id, new.location_id, -bq, 'sale_out', 'sale', new.id::text, null, null, new.sold_at, null, null, neg, new.id);
  end loop;
  return new;
end $function$;


-- ---------- 7. L2: invoice scoping + log dedupe ----------
CREATE OR REPLACE FUNCTION public.invoice_data92(p_sale uuid DEFAULT NULL::uuid, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  s public.sales; loc public.locations; cu public.customers; lines_j jsonb; pays_j jsonb; shares_j jsonb := '[]';
  mob_ok boolean; sub numeric; share numeric := 1; tx numeric; rate numeric; inc boolean; vat_j jsonb := null; can_log boolean;
begin
  if not public.is_active() or not (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then raise exception 'not allowed'; end if;
  if p_sale is not null then select * into s from public.sales where id = p_sale;
  elsif p_client is not null then select * into s from public.sales where client_id = p_client and created_by = auth.uid();
  else raise exception 'no_sale'; end if;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(s.location_id) then raise exception 'not allowed for this location'; end if;
  if public.rule_on('invoice_own_sales_only') and s.created_by is distinct from auth.uid() and not (public.is_owner() or public.can_do('POS', 'approve')) then raise exception 'not_found'; end if;   -- bos94: optional, own sales only
  select * into loc from public.locations where id = s.location_id;
  -- lines: whitelist of keys, in sale order; names in all three languages from the item master
  select coalesce(jsonb_agg(jsonb_build_object(
      'item_id', e.v ->> 'item_id', 'code', coalesce(i.code, e.v ->> 'code'), 'name', e.v ->> 'name', 'name_en', i.name_en, 'name_mix', i.name_mix,
      'unit', e.v ->> 'unit', 'qty', coalesce((e.v ->> 'qty')::numeric, 1), 'price', coalesce((e.v ->> 'price')::numeric, (e.v ->> 'amount')::numeric),
      'amount', coalesce((e.v ->> 'amount')::numeric, 0), 'custom', coalesce((e.v ->> 'custom')::boolean, false)) order by e.n), '[]')
    into lines_j
    from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) with ordinality e(v, n)
    left join public.items i on i.id = nullif(e.v ->> 'item_id', '')::uuid;
  select coalesce(jsonb_agg(jsonb_build_object('mode', p.mode, 'wallet', p.wallet, 'amount', p.amount) order by p.id), '[]') into pays_j
    from public.sale_payments p where p.sale_id = s.id and not p.voided and p.kind = 'sale';
  if s.customer_id is not null then select * into cu from public.customers where id = s.customer_id; end if;
  mob_ok := public.is_owner() or public.rpt_mobile_ok() or s.created_by = auth.uid();
  -- VAT: the same base as vat_report (VAT-applicable lines, after the bill discount share); shown only when the VAT switch is on and a rate is entered
  rate := public.rule_num('vat_rate'); inc := public.rule_on('vat_prices_include');
  if public.rule_on('vat_on') and rate is not null then
    sub := coalesce(s.subtotal, 0); if sub > 0 then share := (sub - coalesce(s.discount, 0)) / sub; end if;
    select coalesce(sum(coalesce((e.v ->> 'amount')::numeric, 0)) filter (where i.vat_applicable is true), 0) * share into tx
      from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e(v)
      left join public.items i on i.id = nullif(e.v ->> 'item_id', '')::uuid;
    vat_j := jsonb_build_object('rate', rate, 'included', coalesce(inc, false), 'taxable', round(tx, 2),
                                'amount', round(case when coalesce(inc, false) then tx * rate / (100 + rate) else tx * rate / 100 end, 2));
  end if;
  if public.is_owner() or public.can_do('POS', 'approve') then
    select coalesce(jsonb_agg(jsonb_build_object('channel', x.channel, 'by', x.by_staff, 'at', x.at) order by x.at desc), '[]') into shares_j
      from (select channel, by_staff, at from public.invoice_shares where sale_id = s.id order by at desc limit 20) x;
  end if;
  return jsonb_build_object(
    'id', s.id, 'client_id', s.client_id, 'receipt', s.receipt, 'location_id', s.location_id, 'location_code', loc.code,
    'location', jsonb_build_object('bn', loc.name_bn, 'mix', loc.name_mix, 'en', loc.name_en),
    'sale_date', s.sale_date, 'sold_at', s.sold_at, 'status', s.status, 'sale_type', s.sale_type, 'cashier', s.created_staff,
    'lines', lines_j, 'subtotal', s.subtotal, 'discount', s.discount, 'total', s.total, 'paid', s.paid, 'due', s.due_amount,
    'payments', pays_j, 'vat', vat_j,
    'customer', case when s.customer_id is null then case when s.customer is null then null else jsonb_build_object('name', s.customer, 'mobile', null, 'masked', false) end
                     else jsonb_build_object('name', cu.name, 'mobile', case when mob_ok then cu.mobile end, 'whatsapp', case when mob_ok then cu.whatsapp end, 'masked', not mob_ok) end,
    'shares', shares_j);
end $function$;


CREATE OR REPLACE FUNCTION public.invoice_share_log92(p_sale uuid DEFAULT NULL::uuid, p_channel text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.sales; nid bigint;
begin
  if not public.is_active() or not (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then raise exception 'not allowed'; end if;
  if p_channel is null or p_channel not in ('print', 'email', 'sms', 'whatsapp', 'share', 'copy', 'download') then raise exception 'bad_channel'; end if;
  if p_sale is not null then select * into s from public.sales where id = p_sale;
  elsif p_client is not null then select * into s from public.sales where client_id = p_client and created_by = auth.uid();
  else raise exception 'no_sale'; end if;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(s.location_id) then raise exception 'not allowed for this location'; end if;
  if public.rule_on('invoice_own_sales_only') and s.created_by is distinct from auth.uid() and not (public.is_owner() or public.can_do('POS', 'approve')) then raise exception 'not_found'; end if;   -- bos94
  select x.id into nid from public.invoice_shares x where x.sale_id = s.id and x.channel = p_channel and x.by_user = auth.uid() and x.at > now() - interval '1 minute' order by x.id desc limit 1;   -- bos94: the same person + sale + channel within a minute is one log line
  if nid is not null then return nid; end if;   -- bos94
  insert into public.invoice_shares (sale_id, channel, by_user, by_staff, location_id)
    values (s.id, p_channel, auth.uid(), (select coalesce(nullif(full_name, ''), staff_id) from public.profiles where id = auth.uid()), s.location_id) returning id into nid;
  return nid;
end $function$;


-- ---------- 8. M1: who can read customer phone / address directly (owner view) ----------
create or replace function public.pii_exposure_report94() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'guard_on', public.rule_on('inbox_pii_guard_on'),
    'direct_mobile_read', has_column_privilege('authenticated', 'public.online_orders', 'customer_mobile', 'select'),
    'direct_address_read', has_column_privilege('authenticated', 'public.online_orders', 'address', 'select'),
    'users_with_pos_view', (select count(distinct ur.user_id) from public.user_roles ur join public.role_form_perms p on p.role_code = ur.role_code and p.form_code = 'POS' and p.can_view
                              join public.roles r on r.code = ur.role_code and r.active),
    'audited_views_30d', (select count(*) from public.audit_log a where a.action = 'view' and a.table_name in ('inbound_messages', 'online_orders') and a.at > now() - interval '30 days'),
    'note', 'While inbox_pii_guard_on is off, every POS-view user can read phone and address with a plain table read; the database cannot log such a read (only inbox_get / inbox_list / online_order_get leave a view line). Recommended: switch inbox_pii_guard_on on.');
end $$;

-- ---------- 9. M6: nobody anonymous runs the re-created functions ----------
do $m6$
declare r record; had boolean;
begin
  for r in select p.oid, p.oid::regprocedure as sig from pg_proc p
           where p.pronamespace = 'public'::regnamespace
             and p.proname = any (array['acct_income_statement', 'acct_overview', 'acct_post_pending', 'partner_calculate', 'partner_settlement_save', 'sale_return', 'stock_count_adjust',
                                        'stock_receive_transfer', 'record_sale2', 'urgent_alerts', 'biz_items', 'items_with_cost', 'online_order_save', 'rpt_agg_sql', 'stock_post', 'recipe_save', 'recipe_copy'])
  loop
    had := has_function_privilege('authenticated', r.oid, 'execute');       -- keep exactly what signed-in users had (they may have got it through PUBLIC)
    execute format('revoke execute on function %s from public, anon', r.sig);
    if had then execute format('grant execute on function %s to authenticated', r.sig); end if;
  end loop;
end $m6$;

-- owner: every SECURITY DEFINER function in public that the anon role can still execute (run it on the live database and compare with what you expect: login_precheck, login_failed, attendance_punch_push)
create or replace function public.anon_exec_audit94() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(p.oid::regprocedure::text order by p.proname) from pg_proc p
                    where p.pronamespace = 'public'::regnamespace and p.prosecdef and has_function_privilege('anon', p.oid, 'execute')), '[]'::jsonb);
end $$;

-- ---------- 10. scheduler run history without a direct table grant ----------
create or replace function public.acct_autopost_runs_list(p_limit int default 20) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.ran_at desc, z.id desc) from (
    select r.id, r.ran_at, r.posted, r.reversed, r.errors, r.locked, r.waiting, r.more, r.note
      from public.acct_autopost_runs85 r order by r.ran_at desc, r.id desc limit least(greatest(coalesce(p_limit, 20), 1), 200)) z), '[]'::jsonb);
end $$;

-- ---------- 11. recommendations for the setup guide (the owner decides; nothing is applied here) ----------
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('partner_base_estimate', 'partner_base_estimate', '80', 'partners', '"refuse"', '{}',
  'অংশীদারের হিসাব সেভ করার সময় বিক্রিত মালের খরচ যদি আনুমানিক (item খরচের তালিকা থেকে) হয়, refuse দিলে সেভ আটকে যায়; ভুল লাভের ভিত্তিতে অংশ ভাগ হয় না। হাতে লেখা base দিলে সেটাই চলে। তার আগে warn থাকুক।',
  'Partner-এর হিসাব save করার সময় বিক্রিত মালের cost যদি আনুমানিক (item cost তালিকা থেকে) হয়, refuse দিলে save আটকে যায়; ভুল profit-এর ভিত্তিতে অংশ ভাগ হয় না। হাতে লেখা base দিলে সেটাই চলে। তার আগে warn থাকুক।',
  'A partner settlement is not saved when part of the cost of goods is only an estimate from the item cost list, so profit is never split on a guessed base; a typed base still works. Keep warn until the ledger costs are in. The owner decides.', 200),
 ('packaging_return_mode', 'packaging_return_mode', '80', 'stock', '"wastage"', '{}',
  'ফেরত আসা বিক্রির মোড়ক সাধারণত আর বিক্রিতে লাগে না। wastage দিলে সেটা কারণসহ নষ্ট হিসাবে লেখা হয়, তাই স্টক ও হিসাব মেলে। মোড়ক সত্যিই আবার ব্যবহার করা গেলে restore। none = আগের মতো।',
  'ফেরত আসা sale-এর packaging সাধারণত আর বিক্রিতে লাগে না। wastage দিলে সেটা reason-সহ নষ্ট হিসাবে লেখা হয়, তাই stock ও হিসাব মেলে। Packaging সত্যিই আবার ব্যবহার করা গেলে restore। none = আগের মতো।',
  'Packaging of a returned sale usually cannot be sold again. wastage records it as waste with a reason, so stock and books agree. Use restore only if the packaging can really be reused. none = as before. The owner decides.', 201),
 ('scan_ai_max_per_job', 'scan_ai_max_per_job', '94', 'purchase', null, '{}',
  'AI দিয়ে ছবি পড়ালে প্রতিবার খরচ হয়। একটি ছবিতে কতবার পড়া যাবে তার সীমা বসানো ভালো; সংখ্যা মালিক ঠিক করবেন (পর্যালোচনার পরামর্শ: ৫)।',
  'AI দিয়ে ছবি পড়ালে প্রতিবার cost হয়। একটি ছবিতে কতবার পড়া যাবে তার limit বসানো ভালো; সংখ্যা owner ঠিক করবেন (review-এর পরামর্শ: ৫)।',
  'Every AI reading of a photo costs money, so a limit per photo is advisable. The number is the owner''s choice (the review suggested 5). Empty = unlimited = as before.', 202),
 ('scan_ai_max_per_user_day', 'scan_ai_max_per_user_day', '94', 'purchase', null, '{}',
  'একজন মানুষ ২৪ ঘণ্টায় কতবার AI পড়াতে পারবে তার সীমা; সংখ্যা মালিক ঠিক করবেন। ফাঁকা = সীমা নেই।',
  'একজন মানুষ ২৪ ঘণ্টায় কতবার AI পড়াতে পারবে তার limit; সংখ্যা owner ঠিক করবেন। ফাঁকা = limit নেই।',
  'A daily limit of AI readings per person; the number is the owner''s choice. Empty = unlimited = as before.', 203),
 ('offline_sale_max_age', 'offline_sale_max_age', '94', 'pos', null, '{}',
  'পুরোনো সময় দিয়ে পাঠানো বিক্রি স্টক-পাহারা এড়াতে পারে। ফোন সাধারণত সর্বোচ্চ কত ঘণ্টা অফলাইন থাকে সেটা দিয়ে সীমা বসান; সংখ্যা মালিক ঠিক করবেন।',
  'পুরোনো সময় দিয়ে পাঠানো sale stock-পাহারা এড়াতে পারে। Phone সাধারণত সর্বোচ্চ কত ঘণ্টা offline থাকে সেটা দিয়ে limit বসান; সংখ্যা owner ঠিক করবেন।',
  'A sale sent with an old date can skip the stock guard. Set the limit to the longest time a phone is normally offline; the number is the owner''s choice. Empty = as before.', 204),
 ('inbox_rate_max_per_min', 'inbox_rate_max_per_min', '94', 'pos', null, '{}',
  'এক চ্যানেলে মিনিটে কত বার্তা রাখা হবে তার সীমা; ভুয়া বার্তার বন্যা ঠেকায়। সংখ্যা মালিক ঠিক করবেন (পর্যালোচনার পরামর্শ: ১২০)।',
  'এক channel-এ মিনিটে কত message রাখা হবে তার limit; ভুয়া message-এর বন্যা ঠেকায়। সংখ্যা owner ঠিক করবেন (review-এর পরামর্শ: ১২০)।',
  'A per-channel limit of stored messages per minute; stops a flood of fake messages. The number is the owner''s choice (the review suggested 120). Empty = no limit = as before.', 205),
 ('intake_reject_max_per_min', 'intake_reject_max_per_min', '94', 'pos', null, '{}',
  'ভুল সই/টোকেনের ডাকের লাইন মিনিটে কত রাখা হবে তার সীমা; তালিকা ভরে যাওয়া ঠেকায়। সংখ্যা মালিক ঠিক করবেন। পুরোনো লাইন মুছতে intake_purge।',
  'ভুল signature/token-এর ডাকের line মিনিটে কত রাখা হবে তার limit; তালিকা ভরে যাওয়া ঠেকায়। সংখ্যা owner ঠিক করবেন। পুরোনো line মুছতে intake_purge।',
  'A limit of rejected-call lines kept per minute so the list cannot be filled by forged calls. The number is the owner''s choice. Old lines can be removed with intake_purge. Empty = no limit = as before.', 206),
 ('invoice_own_sales_only', 'invoice_own_sales_only', '94', 'pos', 'true', '{}',
  'চালু করলে ক্যাশিয়ার শুধু নিজের বিক্রির ইনভয়েস দেখে ও শেয়ার লগ করে; অন্যের বিক্রির ইনভয়েস মালিক ও POS approve-এর জন্য।',
  'চালু করলে cashier শুধু নিজের sale-এর invoice দেখে ও share log করে; অন্যের sale-এর invoice owner ও POS approve-এর জন্য।',
  'With this on a cashier opens and logs only his own sales'' invoices; other sales'' invoices stay with the owner and POS approve. The owner decides.', 207)
on conflict (code) do nothing;

-- ---------- 12. privileges ----------
revoke all on function public.inbound_message_receive(text, text, text, text, text, text, timestamptz, text, boolean, text) from public, anon;
grant execute on function public.inbound_message_receive(text, text, text, text, text, text, timestamptz, text, boolean, text) to authenticated;
revoke all on function public.web_order_submit(text, uuid, text, text, text, text, jsonb, text, text, text, text, text, boolean, text) from public, anon;
grant execute on function public.web_order_submit(text, uuid, text, text, text, text, jsonb, text, text, text, text, text, boolean, text) to authenticated;
revoke all on function public._intake_proof_ok94(text, text) from public, anon, authenticated;
revoke all on function public.intake_proof_set94(text, text), public.intake_proof_status94(), public.intake_purge(int), public.scan_ai_gate94(uuid), public.pii_exposure_report94(),
  public.anon_exec_audit94(), public.acct_autopost_runs_list(int) from public, anon;
grant execute on function public.intake_proof_set94(text, text), public.intake_proof_status94(), public.intake_purge(int), public.scan_ai_gate94(uuid), public.pii_exposure_report94(),
  public.anon_exec_audit94(), public.acct_autopost_runs_list(int) to authenticated;
notify pgrst, 'reload schema';
