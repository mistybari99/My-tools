-- ============================================================
-- BOS tool · Phase 7: business RULES the owner can edit, role GRANTS (who may do what), EMERGENCY requests.
-- Run AFTER phase6 (phase5/6/7 together are in ALL_NEW.sql). Run once.
--
-- Rules  : switches, numbers and choices (e.g. "customer mobile needed on a due sale: on/off").
-- Grants : which role may do a controlled action (e.g. give a discount above the limit). Owner always may.
-- Emergency: a staff member who is blocked by a rule asks at once; the owner approves for a short time (one use or a
--            short window) and later decides in the Rules page which roles should get the grant for good.
-- ============================================================

-- ---------- rules ----------
create table public.rules (
  key text primary key,
  module text not null,                                   -- pos | books | emergency | entries ...
  kind text not null check (kind in ('switch', 'number', 'text', 'choice')),
  value jsonb,                                            -- null = use the default
  default_value jsonb,
  unit text, choices jsonb,                               -- choices: ["block","warn","off"]
  label_bn text not null, label_mix text, label_en text,
  hint_bn text, hint_mix text, hint_en text,
  sort int not null default 0,
  updated_at timestamptz not null default now(), updated_by uuid
);
create trigger audit_rules after insert or update on public.rules for each row execute function public.log_change('key');
alter table public.rules enable row level security;
create policy rules_read on public.rules for select to authenticated using (public.is_active());
grant select on public.rules to authenticated;

create or replace function public.rule_val(p_key text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(value, default_value) from public.rules where key = p_key;
$$;
create or replace function public.rule_on(p_key text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((public.rule_val(p_key) #>> '{}')::boolean, false);
$$;
create or replace function public.rule_num(p_key text) returns numeric
language sql stable security definer set search_path = public as $$
  select nullif(public.rule_val(p_key) #>> '{}', '')::numeric;
$$;
create or replace function public.rule_txt(p_key text) returns text
language sql stable security definer set search_path = public as $$
  select nullif(public.rule_val(p_key) #>> '{}', '');
$$;

-- owner changes a rule (validated by its kind); p_value null = back to the default
create or replace function public.set_rule(p_key text, p_value jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare r public.rules;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into r from public.rules where key = p_key;
  if not found then raise exception 'rule not found'; end if;
  if p_value is not null and jsonb_typeof(p_value) <> 'null' then
    if r.kind = 'switch' and jsonb_typeof(p_value) <> 'boolean' then raise exception 'bad_value'; end if;
    if r.kind = 'number' and (jsonb_typeof(p_value) <> 'number' or (p_value #>> '{}')::numeric < 0) then raise exception 'bad_value'; end if;
    if r.kind = 'choice' and not (r.choices @> jsonb_build_array(p_value #>> '{}')) then raise exception 'bad_value'; end if;
    if r.kind = 'text' and jsonb_typeof(p_value) <> 'string' then raise exception 'bad_value'; end if;
    if p_key = 'period_closed_until' then
      if (p_value #>> '{}') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'bad_value'; end if;
      begin perform (p_value #>> '{}')::date; exception when others then raise exception 'bad_value'; end;
    end if;
  end if;
  update public.rules set value = case when p_value is null or jsonb_typeof(p_value) = 'null' then null else p_value end, updated_at = now(), updated_by = auth.uid() where key = p_key;
end $$;

insert into public.rules (key, module, kind, default_value, unit, choices, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('pos_customer_on_due', 'pos', 'switch', 'true', null, null, 'বাকি রেখে সেল করলে গ্রাহকের মোবাইল নম্বর ও নাম লাগবে', 'Due রেখে sale করলে Customer এর mobile number ও নাম লাগবে', 'A customer mobile number and name are required when anything is left due', 'বন্ধ করলে বাকির সেল গ্রাহক ছাড়াই হবে — সুপারিশ করা হয় না', 'If off, a due sale can be made without a customer — not recommended', 10),
 ('pos_customer_on_wholesale', 'pos', 'switch', 'true', null, null, 'পাইকারি সেলে গ্রাহক লাগবে', 'Wholesale sale এ Customer লাগবে', 'A customer is required on every wholesale sale', null, null, 11),
 ('pos_customer_on_discount', 'pos', 'switch', 'false', null, null, 'যেকোনো ডিসকাউন্টে গ্রাহক লাগবে (খুচরা সহ)', 'যেকোনো Discount এ Customer লাগবে (retail সহ)', 'A customer is required on any discount, retail included', null, null, 12),
 ('pos_discount_manager', 'pos', 'switch', 'true', null, null, 'ডিসকাউন্ট সীমার উপরে (বা সীমা লেখা না থাকলে) নির্ধারিত ভূমিকা লাগবে', 'Discount limit এর উপরে (বা limit না থাকলে) নির্ধারিত role লাগবে', 'A granted role is needed for a discount above the limit (or when no limit is written)', 'কে পারবে তা নিচের "কে কী পারবে" ছকে ঠিক হয়', 'Who may is set in the "Who may do what" grid below', 13),
 ('pos_override_manager', 'pos', 'switch', 'true', null, null, 'তালিকার দাম বদলাতে নির্ধারিত ভূমিকা লাগবে', 'List এর দাম বদলাতে নির্ধারিত role লাগবে', 'A granted role is needed to change a list price', null, null, 14),
 ('pos_credit_mode', 'pos', 'choice', '"block"', null, '["block","warn","off"]', 'গ্রাহকের বাকির সীমা পার হলে: block = আটকাবে, warn = শুধু জানাবে, off = দেখবে না', 'Customer এর credit limit পার হলে: block = আটকাবে, warn = শুধু জানাবে, off = দেখবে না', 'When a customer’s credit limit is exceeded: block, warn only, or off', null, null, 15),
 ('pos_unlisted', 'pos', 'choice', '"flag"', null, '["allow","flag","block"]', 'তালিকায় নেই এমন আইটেম বিক্রি: allow = চলবে, flag = চলবে আর মালিককে জানাবে, block = আটকাবে', 'List এ নেই এমন item বিক্রি: allow, flag (মালিককে জানাবে), block', 'Selling an item that is not in the list: allow, flag (tell the owner), or block', null, null, 16),
 ('pos_offline_hours', 'pos', 'number', '72', 'ঘণ্টা', null, 'ফোনে জমা থাকা সেল কত ঘণ্টা পর্যন্ত নিজের সময়ে বসবে', 'ফোনে জমা sale কত ঘণ্টা পর্যন্ত নিজের সময়ে বসবে', 'How many hours an offline sale keeps its own time', 'এর পরে পাঠালে সেটা পাঠানোর সময়ে বসে', 'Sent later than this, it takes the time it was sent', 17),
 ('period_closed_until', 'books', 'text', null, 'YYYY-MM-DD', null, 'হিসাব বন্ধের তারিখ — এই তারিখ পর্যন্ত কিছু বদলাতে অনুমতি লাগবে', 'হিসাব বন্ধের date — এই date পর্যন্ত কিছু বদলাতে অনুমতি লাগবে', 'Books closed until — changing anything dated up to this day needs permission', 'যেমন 2026-09-30। ফাঁকা = কিছু বন্ধ নয়। মালিক সবসময় পারেন', 'e.g. 2026-09-30. Empty = nothing closed. The owner always may', 20),
 ('entry_paper_no_required', 'entries', 'switch', 'false', null, null, 'ফর্ম জমা দিতে কাগজের ছাপা নম্বর বাধ্যতামূলক', 'Form জমা দিতে কাগজের ছাপা number বাধ্যতামূলক', 'The printed paper number is required to submit a form', 'কাগজের ফর্ম আর অ্যাপ একসাথে চালালে চালু করুন', 'Turn on when paper forms run alongside the app', 30),
 ('em_enabled', 'emergency', 'switch', 'true', null, null, 'জরুরি অনুরোধ চালু', 'জরুরি request চালু', 'Emergency requests are on', 'বন্ধ করলে স্টাফ আটকে গেলে অনুরোধ পাঠাতে পারবে না', 'If off, a blocked staff member cannot send a request', 40),
 ('em_minutes', 'emergency', 'number', '30', 'মিনিট', null, 'জরুরি অনুমোদন কত মিনিট চলবে', 'জরুরি অনুমোদন কত minute চলবে', 'How many minutes an emergency approval lasts', 'এই সময়ের মধ্যে ব্যবহার না হলে মেয়াদ শেষ', 'It expires if unused in this time', 41),
 ('em_discount', 'emergency', 'switch', 'true', null, null, 'জরুরি অনুরোধ চলবে: সীমার উপরে ডিসকাউন্ট', 'জরুরি request চলবে: limit এর উপরে discount', 'Emergency allowed for: discount above the limit', null, null, 42),
 ('em_price', 'emergency', 'switch', 'true', null, null, 'জরুরি অনুরোধ চলবে: দাম বদল', 'জরুরি request চলবে: দাম বদল', 'Emergency allowed for: price change', null, null, 43),
 ('em_credit', 'emergency', 'switch', 'true', null, null, 'জরুরি অনুরোধ চলবে: বাকির সীমা পার', 'জরুরি request চলবে: credit limit পার', 'Emergency allowed for: credit limit exceeded', null, null, 44),
 ('em_customer', 'emergency', 'switch', 'false', null, null, 'জরুরি অনুরোধ চলবে: গ্রাহকের মোবাইল ছাড়া সেল', 'জরুরি request চলবে: Customer এর mobile ছাড়া sale', 'Emergency allowed for: a sale without the customer mobile', 'ডিফল্টে বন্ধ — মোবাইল নম্বর নিয়ম কড়া রাখতে', 'Off by default — keeps the mobile-number rule strict', 45),
 ('em_period', 'emergency', 'switch', 'true', null, null, 'জরুরি অনুরোধ চলবে: বন্ধ হিসাবের তারিখে এন্ট্রি', 'জরুরি request চলবে: বন্ধ হিসাবের date এ entry', 'Emergency allowed for: an entry in a closed period', null, null, 46),
 ('em_access', 'emergency', 'switch', 'true', null, null, 'জরুরি অনুরোধ চলবে: যে ফর্ম বা লোকেশনে অনুমতি নেই', 'জরুরি request চলবে: যে form বা location এ অনুমতি নেই', 'Emergency allowed for: a form or location the person has no access to', null, null, 47);

-- ---------- grants: which role may do a controlled action ----------
create table public.rule_grants (
  grant_code text not null, role_code text not null references public.roles(code) on delete cascade,
  allowed boolean not null default true,
  primary key (grant_code, role_code)
);
create table public.grant_defs (
  grant_code text primary key, module text not null, sort int not null default 0,
  label_bn text not null, label_mix text, label_en text,
  window_type text not null default 'once' check (window_type in ('once', 'window')),     -- an emergency approval is used once, or lasts a short window
  emergency_rule text                                                                        -- the rule switch that allows an emergency request for it
);
create trigger audit_rule_grants after insert or update or delete on public.rule_grants for each row execute function public.log_change('grant_code,role_code');
alter table public.rule_grants enable row level security;
alter table public.grant_defs enable row level security;
create policy rule_grants_read on public.rule_grants for select to authenticated using (public.is_active());
create policy grant_defs_read on public.grant_defs for select to authenticated using (public.is_active());
grant select on public.rule_grants, public.grant_defs to authenticated;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('discount_over_limit', 'pos', 1, 'সীমার উপরে ডিসকাউন্ট দেওয়া', 'Limit এর উপরে discount দেওয়া', 'Give a discount above the limit', 'once', 'em_discount'),
 ('price_override', 'pos', 2, 'তালিকার দাম বদলানো', 'List এর দাম বদলানো', 'Change a list price', 'once', 'em_price'),
 ('credit_over_limit', 'pos', 3, 'গ্রাহকের বাকির সীমার উপরে বাকি দেওয়া', 'Customer এর credit limit এর উপরে due দেওয়া', 'Give credit above a customer’s limit', 'once', 'em_credit'),
 ('sale_without_customer', 'pos', 4, 'গ্রাহকের মোবাইল ছাড়া বাকি/পাইকারি সেল', 'Customer এর mobile ছাড়া due/wholesale sale', 'Make a due / wholesale sale without the customer mobile', 'once', 'em_customer'),
 ('sale_void', 'pos', 5, 'সেল বাতিল করা', 'Sale বাতিল করা', 'Void a sale', 'once', null),
 ('collection_void', 'pos', 6, 'বাকি আদায় বাতিল করা', 'বাকি আদায় বাতিল করা', 'Reverse a collection', 'once', null),
 ('closed_period_edit', 'books', 7, 'বন্ধ হিসাবের তারিখে এন্ট্রি দেওয়া/বদলানো', 'বন্ধ হিসাবের date এ entry দেওয়া/বদলানো', 'Enter or change something in a closed period', 'window', 'em_period'),
 ('form_access', 'access', 8, 'অনুমতি নেই এমন ফর্মে এন্ট্রি (অস্থায়ী)', 'অনুমতি নেই এমন form এ entry (অস্থায়ী)', 'Use a form without the permission (temporary)', 'window', 'em_access'),
 ('loc_access', 'access', 9, 'নিজের নয় এমন লোকেশনে কাজ (অস্থায়ী)', 'নিজের নয় এমন location এ কাজ (অস্থায়ী)', 'Work at a location that is not theirs (temporary)', 'window', 'em_access'),
 ('emergency_decide', 'emergency', 10, 'জরুরি অনুরোধ অনুমোদন করা', 'জরুরি request অনুমোদন করা', 'Decide emergency requests', 'once', null);
-- start the same as today: whoever could approve on the POS form keeps these grants
insert into public.rule_grants (grant_code, role_code)
  select g.grant_code, p.role_code from public.role_form_perms p
  cross join (values ('discount_over_limit'), ('price_override'), ('credit_over_limit'), ('sale_void'), ('collection_void')) g(grant_code)
  where p.form_code = 'POS' and p.can_approve
  on conflict do nothing;

create or replace function public.can_grant(p_code text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and exists (
    select 1 from public.user_roles ur join public.rule_grants g on g.role_code = ur.role_code and g.grant_code = p_code and g.allowed
    join public.roles r on r.code = ur.role_code and r.active where ur.user_id = auth.uid()));
$$;
create or replace function public.set_grant(p_code text, p_role text, p_allowed boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.grant_defs where grant_code = p_code) then raise exception 'unknown grant'; end if;
  if p_role = 'owner' then return; end if;
  if p_allowed then insert into public.rule_grants (grant_code, role_code) values (p_code, p_role) on conflict (grant_code, role_code) do update set allowed = true;
  else delete from public.rule_grants where grant_code = p_code and role_code = p_role; end if;
end $$;

-- ---------- emergency requests ----------
create table public.emergency_requests (
  id bigserial primary key,
  grant_code text not null references public.grant_defs(grant_code),
  requested_by uuid not null, requested_staff text, location_id int,
  context jsonb not null default '{}',                       -- what was attempted, e.g. {"discount":120} or {"form":"10-2","action":"enter"}
  reason text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'used', 'expired', 'cancelled')),
  created_at timestamptz not null default now(),
  decided_by uuid, decided_staff text, decided_at timestamptz, decision_note text,
  valid_until timestamptz, used_at timestamptz, used_ref text
);
create index emergency_open on public.emergency_requests (status, created_at desc);
create index emergency_user on public.emergency_requests (requested_by, grant_code, status);
create trigger audit_emergency after insert or update on public.emergency_requests for each row execute function public.log_change('id');
alter table public.emergency_requests enable row level security;
create policy emergency_read on public.emergency_requests for select to authenticated
  using (requested_by = auth.uid() or public.is_owner() or public.can_grant('emergency_decide'));
grant select on public.emergency_requests to authenticated;

create or replace function public.request_emergency(p_grant text, p_loc int, p_context jsonb, p_reason text) returns bigint
language plpgsql security definer set search_path = public as $$
declare d public.grant_defs; sid text; nid bigint;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('em_enabled') then raise exception 'emergency_off'; end if;
  select * into d from public.grant_defs where grant_code = p_grant;
  if not found or d.emergency_rule is null then raise exception 'emergency_not_available'; end if;
  if not public.rule_on(d.emergency_rule) then raise exception 'emergency_off'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if (select count(*) from public.emergency_requests where requested_by = auth.uid() and status = 'pending') >= 5 then raise exception 'too_many_pending'; end if;
  if length(coalesce(p_context, '{}')::text) > 2000 then raise exception 'bad_context'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.emergency_requests (grant_code, requested_by, requested_staff, location_id, context, reason)
    values (p_grant, auth.uid(), sid, p_loc, coalesce(p_context, '{}'), left(btrim(p_reason), 300)) returning id into nid;
  return nid;
end $$;

create or replace function public.decide_emergency(p_id bigint, p_approve boolean, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.emergency_requests; sid text; mins numeric;
begin
  if not public.can_grant('emergency_decide') then raise exception 'not allowed'; end if;
  select * into r from public.emergency_requests where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if r.status <> 'pending' then raise exception 'already decided'; end if;
  if r.requested_by = auth.uid() and not public.is_owner() then raise exception 'own_request'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  mins := coalesce(public.rule_num('em_minutes'), 30);
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.emergency_requests set status = case when p_approve then 'approved' else 'rejected' end, decided_by = auth.uid(), decided_staff = sid, decided_at = now(),
    decision_note = left(nullif(btrim(p_note), ''), 300), valid_until = case when p_approve then now() + make_interval(mins => mins::int) end where id = p_id;
end $$;

create or replace function public.cancel_emergency(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.emergency_requests set status = 'cancelled' where id = p_id and requested_by = auth.uid() and status = 'pending';
end $$;

-- use an approved request: 'once' grants are consumed, 'window' grants stay valid until they expire
create or replace function public.use_emergency(p_grant text, p_loc int, p_ref text) returns boolean
language plpgsql security definer set search_path = public as $$
declare r public.emergency_requests; w text;
begin
  select * into r from public.emergency_requests
    where requested_by = auth.uid() and grant_code = p_grant and status = 'approved' and valid_until > now() and (location_id is null or p_loc is null or location_id = p_loc)
    order by id limit 1 for update;
  if not found then return false; end if;
  select window_type into w from public.grant_defs where grant_code = p_grant;
  if w = 'once' then update public.emergency_requests set status = 'used', used_at = now(), used_ref = left(p_ref, 80) where id = r.id; end if;
  perform set_config('bos.em_used', coalesce(current_setting('bos.em_used', true), '') || ',' || r.id || ':' || p_grant, true);
  return true;
end $$;
create or replace function public.rule_ok(p_grant text, p_loc int) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  return public.can_grant(p_grant) or public.use_emergency(p_grant, p_loc, 'rule');
end $$;

-- approved requests that were never used become 'expired' when looked at
create or replace function public.my_emergency() returns table (id bigint, grant_code text, status text, reason text, decision_note text, created_at timestamptz, valid_until timestamptz, context jsonb)
language sql stable security definer set search_path = public as $$
  select r.id, r.grant_code, case when r.status = 'approved' and r.valid_until <= now() then 'expired' else r.status end, r.reason, r.decision_note, r.created_at, r.valid_until, r.context
  from public.emergency_requests r where r.requested_by = auth.uid() and r.created_at > now() - interval '2 days' order by r.id desc limit 30;
$$;

-- a short-window emergency approval also opens a form or a location for that person
create or replace function public.can_do(p_form text, p_action text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (
    public.is_active() and (exists (
      select 1 from public.user_roles ur
      join public.role_form_perms p on p.role_code = ur.role_code and p.form_code = p_form
      join public.roles r on r.code = ur.role_code and r.active
      where ur.user_id = auth.uid()
        and case p_action when 'view' then p.can_view when 'enter' then p.can_enter
                          when 'approve' then p.can_approve else false end)
    or (p_action in ('view', 'enter') and exists (
      select 1 from public.emergency_requests e
      where e.requested_by = auth.uid() and e.grant_code = 'form_access' and e.status = 'approved' and e.valid_until > now()
        and e.context->>'form' = p_form and (e.context->>'action' is null or e.context->>'action' = p_action or p_action = 'view')))));
$$;
create or replace function public.can_loc(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (
    public.is_owner()
    or exists (select 1 from public.user_roles where user_id = auth.uid() and role_code = 'management')
    or exists (select 1 from public.user_locations where user_id = auth.uid() and location_id = p_loc)
    or exists (select 1 from public.emergency_requests e where e.requested_by = auth.uid() and e.grant_code = 'loc_access' and e.status = 'approved' and e.valid_until > now()
               and (e.context->>'loc')::int = p_loc));
$$;

-- the printed paper number can be made mandatory for submitting a form
create or replace function public.entries_paper_required() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'submitted' and (tg_op = 'INSERT' or old.status is distinct from 'submitted') and public.rule_on('entry_paper_no_required')
     and nullif(btrim(new.data->>'paper_no'), '') is null then raise exception 'paper_no_required'; end if;
  return new;
end $$;
create trigger entries_paper_required before insert or update on public.entries for each row execute function public.entries_paper_required();

revoke all on function public.rule_val(text), public.rule_on(text), public.rule_num(text), public.rule_txt(text), public.set_rule(text, jsonb), public.can_grant(text),
  public.set_grant(text, text, boolean), public.request_emergency(text, int, jsonb, text), public.decide_emergency(bigint, boolean, text), public.cancel_emergency(bigint),
  public.use_emergency(text, int, text), public.rule_ok(text, int), public.my_emergency() from public, anon;
grant execute on function public.rule_val(text), public.rule_on(text), public.rule_num(text), public.rule_txt(text), public.set_rule(text, jsonb), public.can_grant(text),
  public.set_grant(text, text, boolean), public.request_emergency(text, int, jsonb, text), public.decide_emergency(bigint, boolean, text), public.cancel_emergency(bigint),
  public.my_emergency() to authenticated;
