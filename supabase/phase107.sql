-- ============================================================
-- Phase 107 (bos107) - STEP Errlog: a quiet error log the owner can read from a phone (docs/briefs_p2p3/step_Errlog_REPORT.md).
--   Why: the owner has no browser console. When a screen breaks nothing told us. The web (web/errlog.js) now sends a small, anonymised record of a script error,
--   an unhandled promise rejection, a failed (non-business) rpc call, or a note typed in "Report a problem"; the owner reads them on #/problems.
--   Needs phases 72..103 pasted first (guard below). Independent of 104 (dashboard), 105 (security), 106 (backup): none of them is read or changed here.
--   Additive, paste-twice safe (create ... if not exists / or replace / on conflict do nothing). No existing table, column, function, trigger, rule value or privilege is changed.
--   Whole file = one transaction: if the guard refuses, nothing is created.
--   Objects:
--     tables   client_errors (the log), client_error_seen107 (idempotency keys), client_error_hits107 (per user per hour counter for the rate limit)
--     rules    client_errors_on (switch, default OFF = today's behaviour; RECOMMENDED ON, see the advisor row), client_error_rate_max (number, owner-typed, blank = built-in
--              ceiling 200 per user per hour; a typed number can only LOWER it), client_errors_keep_days (number, blank = keep for ever)
--     grant    view_client_errors (read the log without being the owner)
--     RPC      client_error_log(p_client, p_batch)  any active user, batch <= 20, idempotent, deduped (same fingerprint within 10 minutes -> count + 1), rate limited, never raises
--              client_errors_list(p_from, p_to, p_kind, p_limit, p_status)   owner or view_client_errors
--              client_errors_summary()                                        owner or view_client_errors: top fingerprints of the last 7 days
--              client_error_resolve(p_id, p_note)                             owner only, audited (resolves every open row with the same fingerprint)
--              client_errors_purge(p_days default 60)                         owner only, audited; the rule client_errors_keep_days (blank = keep) drives the automatic purge
--   Privacy: no request body, token, or customer data is stored. extra is cleaned: every key that matches token|key|password|secret|authorization|cookie is removed (any depth),
--   long values are cut, the whole is capped at 2 KB. message / stack lose JWT-looking strings, "Bearer x", e-mail addresses and digit runs of 8+ (phone numbers). route loses its query string and ids.
--   user_report is the one kind that is accepted while client_errors_on is OFF (a person pressed Send on purpose).
--   Tag: bos107. No existing function is re-created.
-- ============================================================
begin;

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
    ('99', 'public._inb_pii_f99(text,text)'), ('103', 'public._cust_pii103(text,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.item_categories') is null then miss := miss || ' 100'; end if;
  if to_regclass('public.setup_rec_defs81') is null or not exists (select 1 from public.setup_rec_defs81 where code = 'purchase_grn_guard' and phase = '82') then miss := miss || ' 101'; end if;
  if to_regclass('public.audit_log') is null or to_regclass('public.grant_defs') is null or to_regclass('public.rules') is null then miss := miss || ' base'; end if;
  if miss <> '' then
    raise exception 'phase107 needs phases 72..103 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
end $g$;

-- ---------- tables ----------
create table if not exists public.client_errors (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),                       -- first seen
  last_at timestamptz not null default now(),                  -- last seen (moves when the same error repeats inside 10 minutes)
  user_id uuid,
  staff_id text,
  app_build text check (app_build is null or char_length(app_build) <= 40),
  route text check (route is null or char_length(route) <= 200),
  kind text not null check (kind in ('js_error', 'unhandled_rejection', 'rpc_error', 'user_report')),
  message text check (message is null or char_length(message) <= 500),
  stack text check (stack is null or char_length(stack) <= 2000),
  ua text check (ua is null or char_length(ua) <= 200),
  lang text check (lang is null or char_length(lang) <= 10),
  extra jsonb check (extra is null or octet_length(extra::text) <= 2048),
  user_note text check (user_note is null or char_length(user_note) <= 1000),
  fingerprint text,                                            -- md5(kind | first line of message with numbers folded | route)
  count int not null default 1 check (count >= 1),
  resolved_at timestamptz, resolved_by uuid, resolve_note text check (resolve_note is null or char_length(resolve_note) <= 500)
);
create index if not exists client_errors_fp107 on public.client_errors (fingerprint, last_at desc);
create index if not exists client_errors_user_fp107 on public.client_errors (user_id, fingerprint, last_at desc);
create index if not exists client_errors_at107 on public.client_errors (at desc);
create table if not exists public.client_error_seen107 (
  user_id uuid not null, client_key text not null, at timestamptz not null default now(), primary key (user_id, client_key));
create table if not exists public.client_error_hits107 (
  user_id uuid not null, hr timestamptz not null, n int not null default 0, primary key (user_id, hr));

-- RLS: nobody inserts / updates / deletes directly (only the definer RPCs write); select only for the owner or a holder of view_client_errors
alter table public.client_errors enable row level security;
alter table public.client_error_seen107 enable row level security;
alter table public.client_error_hits107 enable row level security;
revoke all on public.client_errors, public.client_error_seen107, public.client_error_hits107 from public, anon, authenticated;
grant select on public.client_errors to authenticated;
drop policy if exists client_errors_read107 on public.client_errors;
create policy client_errors_read107 on public.client_errors for select to authenticated using (public.is_owner() or public.has_grant('view_client_errors'));

-- ---------- rules ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('client_errors_on', 'settings', 'switch', 'false', null, null, null, null,
  'অ্যাপের ভাঙা স্ক্রিনের খবর নিজে থেকে জমা হবে', 'App এর ভাঙা screen এর খবর নিজে থেকে জমা হবে', 'Collect error reports from the app automatically',
  'বন্ধ = আগের মতোই (ডিফল্ট)। চালু করলে কোনো স্ক্রিন ভাঙলে সংক্ষিপ্ত খবর (কোন স্ক্রিন, কী ভুল, কোন সংস্করণ) জমা হয়; মালিক "সমস্যা" পাতায় দেখেন। পাসওয়ার্ড, টোকেন, গ্রাহকের তথ্য কখনো জমা হয় না। "সমস্যা জানান" বোতাম এই সুইচ ছাড়াও কাজ করে।',
  'বন্ধ = আগের মতোই (default)। চালু করলে কোনো screen ভাঙলে সংক্ষিপ্ত খবর (কোন screen, কী error, কোন build) জমা হয়; owner Problems পাতায় দেখেন। Password, token, customer এর তথ্য কখনো জমা হয় না। Report a problem বোতাম এই switch ছাড়াও কাজ করে।',
  'Off = as before (default). On: when a screen breaks, a short note (which screen, what error, which build) is saved and the owner reads it on the Problems page. Passwords, tokens and customer data are never stored. The Report a problem button works even while this is off.', 990),
 ('client_error_rate_max', 'settings', 'number', null, 'per hour', null, 1, 200,
  'একজন ব্যবহারকারী ঘণ্টায় সর্বোচ্চ কতটি ত্রুটির খবর পাঠাতে পারবে', 'একজন user ঘণ্টায় সর্বোচ্চ কতটি error report পাঠাতে পারবে', 'Most error reports one user may send per hour',
  'ফাঁকা = ভেতরের নিরাপত্তা সীমা ২০০ (এটা ব্যবসার সংখ্যা নয়, শুধু ভুল লুপ থেকে সার্ভার বাঁচানোর জন্য)। সংখ্যা দিলে শুধু সীমা কমানো যায়, ২০০ এর বেশি নয়।',
  'ফাঁকা = ভেতরের safety limit 200 (এটা business এর সংখ্যা নয়, শুধু ভুল loop থেকে server বাঁচানোর জন্য)। সংখ্যা দিলে শুধু limit কমানো যায়, 200 এর বেশি নয়।',
  'Blank = the built-in safety ceiling of 200 (not a business number, only a guard against a runaway loop hammering the server). A number can only lower it, never raise it above 200.', 991),
 ('client_errors_keep_days', 'settings', 'number', null, 'days', null, 1, 3650,
  'ত্রুটির খবর কত দিন রাখা হবে', 'Error report কত দিন রাখা হবে', 'Days to keep error reports',
  'ফাঁকা = চিরকাল রাখা হবে (ডিফল্ট)। সংখ্যা দিলে তার চেয়ে পুরনো খবর নিজে থেকে মুছে যায়। মালিক "সমস্যা" পাতা থেকেও হাতে মুছতে পারেন।',
  'ফাঁকা = চিরকাল রাখা হবে (default)। সংখ্যা দিলে তার চেয়ে পুরনো report নিজে থেকে মুছে যায়। Owner Problems পাতা থেকেও হাতে মুছতে পারেন।',
  'Blank = keep for ever (default). A number: reports older than that are deleted automatically. The owner can also purge by hand from the Problems page.', 992)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select 'view_client_errors', 'settings', 98, 'অ্যাপের ত্রুটির খবর দেখা (সমস্যা পাতা)', 'App এর error report দেখা (Problems পাতা)', 'See the app error reports (Problems page)', 'once'
where not exists (select 1 from public.grant_defs where grant_code = 'view_client_errors');

-- the setup advisor: client_errors_on recommended ON; the two numbers are owner-typed (no value recommended)
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('client_errors_on', 'client_errors_on', '107', 'settings', 'true'::jsonb, '{}'::text[],
  'ফোনে কনসোল খোলা যায় না, তাই স্ক্রিন ভাঙলে কেউ জানতে পারে না। চালু রাখলে শুধু সংক্ষিপ্ত খবর জমা হয় (কোন স্ক্রিন, কী ভুল); কোনো বিক্রি, হিসাব বা দাম বদলায় না, পাসওয়ার্ড বা গ্রাহকের তথ্য জমা হয় না।',
  'Phone এ console খোলা যায় না, তাই screen ভাঙলে কেউ জানতে পারে না। চালু রাখলে শুধু সংক্ষিপ্ত খবর জমা হয় (কোন screen, কী error); কোনো sale, হিসাব বা দাম বদলায় না, password বা customer এর তথ্য জমা হয় না।',
  'You cannot open a browser console on a phone, so a broken screen goes unnoticed. With this on, only a short note is saved (which screen, what error); no sale, book or price is touched and no password or customer data is stored.', 990),
 ('client_error_rate_max', 'client_error_rate_max', '107', 'settings', null, '{}'::text[],
  'ফাঁকা থাকলে ভেতরের সীমা ২০০ কাজ করে। কম সীমা চাইলে মালিক নিজে লিখুন; ২০০ এর বেশি হয় না।',
  'ফাঁকা থাকলে ভেতরের limit 200 কাজ করে। কম limit চাইলে owner নিজে লিখুন; 200 এর বেশি হয় না।',
  'Blank keeps the built-in ceiling of 200. Type a number only to lower it; it can never go above 200.', 991),
 ('client_errors_keep_days', 'client_errors_keep_days', '107', 'settings', null, '{}'::text[],
  'কত দিন রাখবেন তা আপনার সিদ্ধান্ত, তাই কোনো সংখ্যা ঠিক করা নেই। ফাঁকা = চিরকাল রাখা।',
  'কত দিন রাখবেন তা আপনার decision, তাই কোনো সংখ্যা ঠিক করা নেই। ফাঁকা = চিরকাল রাখা।',
  'How long to keep reports is your decision, so no number is recommended. Blank = keep for ever.', 992)
on conflict (code) do nothing;

-- ---------- helpers (internal, no privilege for anyone) ----------
create or replace function public._ce_strip107(j jsonb, d int default 0) returns jsonb
language plpgsql immutable set search_path = public as $$
-- removes every object key matching token|key|password|secret|authorization|cookie (any depth), cuts long strings, limits depth / array size
declare o jsonb; k text; v jsonb; n int := 0; r jsonb;
begin
  if j is null then return null; end if;
  if d > 4 then return to_jsonb('…'::text); end if;
  case jsonb_typeof(j)
    when 'object' then
      o := '{}'::jsonb;
      for k, v in select * from jsonb_each(j) loop
        if k ~* 'token|key|password|secret|authorization|cookie' then continue; end if;
        n := n + 1; if n > 30 then exit; end if;
        o := o || jsonb_build_object(left(k, 60), public._ce_strip107(v, d + 1));
      end loop;
      return o;
    when 'array' then
      r := '[]'::jsonb;
      for v in select * from jsonb_array_elements(j) limit 20 loop r := r || jsonb_build_array(public._ce_strip107(v, d + 1)); end loop;
      return r;
    when 'string' then return to_jsonb(left(j #>> '{}', 200));
    else return j;
  end case;
end $$;

create or replace function public._ce_clean107(p text, p_max int) returns text
language sql immutable set search_path = public as $$
  -- JWT-looking strings, Bearer values, e-mail addresses and digit runs of 8+ (phone / account numbers) are replaced; then cut to p_max
  select left(regexp_replace(regexp_replace(regexp_replace(regexp_replace(p,
    'eyJ[A-Za-z0-9_-]{8,}(\.[A-Za-z0-9_-]+){0,2}', '[jwt]', 'g'),
    'Bearer\s+[^\s"'',;]+', 'Bearer [x]', 'gi'),
    '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[email]', 'g'),
    '[0-9০-৯]{8,}', '[num]', 'g'), p_max)
$$;

create or replace function public._ce_route107(p text) returns text
language sql immutable set search_path = public as $$
  -- no query string, no hash parameters, no ids: uuids and long numbers become :id
  select left(regexp_replace(regexp_replace(split_part(coalesce(p, ''), '?', 1),
    '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', ':id', 'g'),
    '/[0-9]{2,}(?=/|$)', '/:id', 'g'), 200)
$$;

create or replace function public._ce_fp107(p_kind text, p_msg text, p_route text) returns text
language sql immutable set search_path = public as $$
  select md5(coalesce(p_kind, '') || '|' || regexp_replace(left(split_part(coalesce(p_msg, ''), E'\n', 1), 200), '[0-9]+', '#', 'g') || '|' || coalesce(p_route, ''))
$$;

create or replace function public._client_errors_autopurge107() returns int
language plpgsql security definer set search_path = public as $$
-- rule client_errors_keep_days blank = keep. Also drops the idempotency keys / hour counters older than 2 days (they only matter for a day).
declare dd numeric := public.rule_num('client_errors_keep_days'); n int := 0;
begin
  delete from public.client_error_seen107 where at < now() - interval '2 days';
  delete from public.client_error_hits107 where hr < now() - interval '2 days';
  if dd is not null and dd >= 1 then
    delete from public.client_errors where at < now() - (dd::int || ' days')::interval; get diagnostics n = row_count;
  end if;
  return n;
end $$;

-- ---------- write: a batch of up to 20 reports from the device ----------
create or replace function public.client_error_log(p_client text, p_batch jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); sid text; on_ boolean; cap int; hr_ timestamptz := date_trunc('hour', now()); used int := 0; startused int;
  e jsonb; i int := 0; kind_ text; msg text; stk text; rt text; fp text; cid text; ck text; ex jsonb; note text; cnt int; did bigint;
  acc int := 0; dedup int := 0; dup int := 0; skip int := 0; offc int := 0; lim int := 0; bad int := 0; drop_ int := 0; ins int;
begin
  if uid is null or not public.is_active() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_batch is null or jsonb_typeof(p_batch) <> 'array' then return jsonb_build_object('ok', false, 'error', 'bad_batch'); end if;
  on_ := coalesce(public.rule_on('client_errors_on'), false);
  cap := greatest(1, least(coalesce(public.rule_num('client_error_rate_max'), 200), 200))::int;   -- the typed number can only lower the built-in ceiling
  select n into used from public.client_error_hits107 where user_id = uid and hr = date_trunc('hour', now());
  used := coalesce(used, 0); startused := used;
  select staff_id into sid from public.profiles where id = uid;
  for e in select x from jsonb_array_elements(p_batch) x loop
    i := i + 1;
    if i > 20 then drop_ := drop_ + 1; continue; end if;
    begin
      kind_ := e ->> 'kind';
      if kind_ is null or kind_ not in ('js_error', 'unhandled_rejection', 'rpc_error', 'user_report') then skip := skip + 1; continue; end if;
      if not on_ and kind_ <> 'user_report' then offc := offc + 1; continue; end if;
      if used >= cap then lim := lim + 1; continue; end if;
      cid := nullif(left(btrim(coalesce(e ->> 'cid', '')), 64), '');
      if cid is not null then
        ck := left(coalesce(p_client, ''), 64) || ':' || cid;
        insert into public.client_error_seen107 (user_id, client_key) values (uid, ck) on conflict do nothing;
        get diagnostics ins = row_count;
        if ins = 0 then dup := dup + 1; continue; end if;
      end if;
      msg := public._ce_clean107(e ->> 'message', 500);
      stk := public._ce_clean107(e ->> 'stack', 2000);
      rt := public._ce_route107(e ->> 'route');
      note := left(e ->> 'note', 1000);
      ex := public._ce_strip107(case when jsonb_typeof(e -> 'extra') = 'object' then e -> 'extra' else null end);
      if ex is not null and octet_length(ex::text) > 2048 then ex := jsonb_build_object('truncated', true, 'keys', (select coalesce(jsonb_agg(k), '[]'::jsonb) from (select jsonb_object_keys(ex) k limit 10) q)); end if;
      cnt := greatest(1, least(coalesce(nullif(e ->> 'count', '')::int, 1), 1000));
      fp := public._ce_fp107(kind_, msg, rt);
      used := used + 1;
      did := null;
      if kind_ <> 'user_report' then
        update public.client_errors set count = least(count + cnt, 1000000), last_at = now()
         where id = (select id from public.client_errors where user_id = uid and fingerprint = fp and resolved_at is null and last_at > now() - interval '10 minutes' order by last_at desc limit 1)
        returning id into did;
      end if;
      if did is not null then dedup := dedup + 1;
      else
        insert into public.client_errors (user_id, staff_id, app_build, route, kind, message, stack, ua, lang, extra, user_note, fingerprint, count)
        values (uid, sid, left(e ->> 'app_build', 40), rt, kind_, msg, stk, left(e ->> 'ua', 200), left(e ->> 'lang', 10), ex, note, fp, cnt);
        acc := acc + 1;
      end if;
    exception when others then bad := bad + 1;
    end;
  end loop;
  if used > startused then
    insert into public.client_error_hits107 (user_id, hr, n) values (uid, hr_, used) on conflict (user_id, hr) do update set n = greatest(public.client_error_hits107.n, excluded.n);
  end if;
  if random() < 0.02 then perform public._client_errors_autopurge107(); end if;
  return jsonb_build_object('ok', true, 'accepted', acc, 'deduped', dedup, 'duplicate', dup, 'skipped', skip, 'off', offc, 'limited', lim, 'dropped', drop_, 'bad', bad);
exception when others then
  return jsonb_build_object('ok', false, 'error', 'failed');   -- logging must never break the app
end $$;

-- ---------- read ----------
create or replace function public.client_errors_list(p_from timestamptz default null, p_to timestamptz default null, p_kind text default null, p_limit int default 200, p_status text default 'all')
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_owner() or public.has_grant('view_client_errors')) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(q) order by q.last_at desc) from (
    select id, at, last_at, user_id, staff_id, app_build, route, kind, message, stack, ua, lang, extra, user_note, fingerprint, count, resolved_at, resolve_note
      from public.client_errors
     where (p_from is null or last_at >= p_from) and (p_to is null or at <= p_to) and (p_kind is null or kind = p_kind)
       and (coalesce(p_status, 'all') = 'all' or (p_status = 'open' and resolved_at is null) or (p_status = 'resolved' and resolved_at is not null))
     order by last_at desc limit greatest(1, least(coalesce(p_limit, 200), 500))) q), '[]'::jsonb);
end $$;

create or replace function public.client_errors_summary() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_owner() or public.has_grant('view_client_errors')) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(q) order by q.total desc, q.last_at desc) from (
    select fingerprint, (array_agg(kind order by last_at desc))[1] as kind, (array_agg(message order by last_at desc))[1] as message, (array_agg(route order by last_at desc))[1] as route,
           sum(count)::int as total, count(distinct user_id)::int as users, max(last_at) as last_at, bool_or(resolved_at is null) as open
      from public.client_errors where last_at >= now() - interval '7 days' group by fingerprint order by sum(count) desc, max(last_at) desc limit 20) q), '[]'::jsonb);
end $$;

-- ---------- owner actions (audited) ----------
create or replace function public.client_error_resolve(p_id bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.client_errors; n int; sid text;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into r from public.client_errors where id = p_id;
  if not found then raise exception 'not found'; end if;
  update public.client_errors set resolved_at = now(), resolved_by = auth.uid(), resolve_note = left(p_note, 500)
   where resolved_at is null and (id = p_id or (fingerprint is not null and fingerprint = r.fingerprint));
  get diagnostics n = row_count;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
  values (auth.uid(), sid, 'resolve', 'client_errors', p_id::text, jsonb_build_object('fingerprint', r.fingerprint, 'rows', n, 'note', left(p_note, 500)));
  return jsonb_build_object('ok', true, 'resolved', n);
end $$;

create or replace function public.client_errors_purge(p_days int default 60) returns int
language plpgsql security definer set search_path = public as $$
-- the 60 is only this function's default; the automatic purge follows the rule client_errors_keep_days (blank = keep). Explicit call by the owner deletes rows older than p_days.
declare n int; sid text; dd int := p_days;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if dd is null then dd := public.rule_num('client_errors_keep_days')::int; end if;
  if dd is null then return 0; end if;
  if dd < 1 then raise exception 'bad_value'; end if;
  delete from public.client_errors where at < now() - (dd || ' days')::interval; get diagnostics n = row_count;
  delete from public.client_error_seen107 where at < now() - interval '2 days';
  delete from public.client_error_hits107 where hr < now() - interval '2 days';
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
  values (auth.uid(), sid, 'purge', 'client_errors', null, jsonb_build_object('days', dd, 'deleted', n));
  return n;
end $$;

revoke all on function public._ce_strip107(jsonb, int), public._ce_clean107(text, int), public._ce_route107(text), public._ce_fp107(text, text, text), public._client_errors_autopurge107() from public, anon, authenticated;
revoke all on function public.client_error_log(text, jsonb), public.client_errors_list(timestamptz, timestamptz, text, int, text), public.client_errors_summary(),
  public.client_error_resolve(bigint, text), public.client_errors_purge(int) from public, anon;
grant execute on function public.client_error_log(text, jsonb), public.client_errors_list(timestamptz, timestamptz, text, int, text), public.client_errors_summary(),
  public.client_error_resolve(bigint, text), public.client_errors_purge(int) to authenticated;

commit;
