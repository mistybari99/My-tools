-- Phase 305 (CRM package B, local label 105) - DUPLICATE CUSTOMERS: a "possible duplicates" review list and a SOFT link ("same person").
-- Paste AFTER phase304. Paste-twice safe. No earlier phase file is edited and NO shared function is re-created. Nothing is merged, moved or deleted.
--
-- WHY (CRM audit rows 11, 12 and risk R3): customer_save only catches an exact mobile number. The same person under a second number or a spelling variant splits history,
-- points and tier. A hard merge is NOT safe: journal_lines.party_id (phase40), customer_dues, _cust_bal and collect_payment carry the customer id, so moving rows would change
-- accounting. The soft link only GROUPS two customers for CRM views: the list (_crmb_customer_list with collapse), the customer group view, and the message check
-- (a withdrawn "no" or a do-not-contact of one number protects the other number of the same person). Customer ids never change; sales, payments, dues and the journal are not touched.
-- WHAT THIS FILE ADDS
--   1. crm_customer_links      the soft link: primary customer + linked customer + reason + who + when; append-only, undone by a stamp, never deleted.
--                              One active link per linked customer; a primary can never be linked itself, so a loop (A under B and B under A) cannot exist.
--   2. crm_dup_reviews         "these two are not the same person" decisions, so a pair is not offered again (can be reopened).
--   3. _crmb_dup_candidates    the review list: same phone (mobile, WhatsApp, and customer_phones when that table exists), same name, similar name (one letter apart, only when the owner switches it on),
--                              each pair with its reasons and a strength (strong / possible / weak). Phones are masked by the privacy setting.
--   4. _crmb_link_customers / _crmb_unlink_customers / _crmb_dup_review / _crmb_customer_group / _crmb_links_list.
-- SETTINGS (rules, module crm): crm_dup_check_on (OFF = no list, no new link; customer_save and the POS behave exactly as today), crm_dup_similar_names_on (OFF = names must match after
--   removing spaces, capitals and punctuation; ON = also names one letter apart). GRANT: crm_merge (the owner always may). Every link needs a written reason and writes an audit line and a yellow row in the Exceptions list.

do $g$ begin
  if to_regprocedure('public._crmb_customer_rows(integer,boolean,boolean)') is null then raise exception 'phase305 needs phase304 (and 303) first'; end if;
  if to_regprocedure('public._cust_stats43(uuid,boolean)') is null then raise exception 'phase305 needs phase43 first'; end if;
end $g$;

do $r$ begin
  perform public._crmb_rule_seed('crm_dup_check_on', 'switch', 'false'::jsonb, null, null, null, null,
    'Look for duplicate customers and allow linking them as one person',
    'OFF = no duplicate list and no new link (today; saving a customer still stops on an identical mobile number). ON = the review list is built and people with the right can link two customers as the same person. A link never moves sales, payments, dues or the books.', 3200);
  perform public._crmb_rule_seed('crm_dup_similar_names_on', 'switch', 'false'::jsonb, null, null, null, null,
    'Also list names that differ by one letter',
    'OFF = names must be the same after removing spaces, capitals and punctuation. ON = a name that differs by one letter (a spelling slip) is also listed, as a weak hint, unless it shares an address or birthday.', 3201);
end $r$;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'crm_merge', 'pos', 98, 'Link two customers as the same person', 'Link two customers as the same person', 'Link two customers as the same person', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'crm_merge');

-- ---------- tables ----------
create table if not exists public.crm_customer_links (
  id bigserial primary key,
  client_id uuid unique,
  primary_id uuid not null references public.customers(id),
  linked_id uuid not null references public.customers(id),
  reason text not null check (length(btrim(reason)) between 3 and 300),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  undone_at timestamptz, undone_by uuid, undo_reason text check (undo_reason is null or length(undo_reason) <= 300), undo_client uuid unique,
  check (primary_id <> linked_id)
);
create unique index if not exists crm_customer_links_one_active on public.crm_customer_links (linked_id) where undone_at is null;
create index if not exists crm_customer_links_primary on public.crm_customer_links (primary_id) where undone_at is null;

create table if not exists public.crm_dup_reviews (
  id bigserial primary key,
  client_id uuid unique,
  a_id uuid not null references public.customers(id),
  b_id uuid not null references public.customers(id),
  reason text check (reason is null or length(reason) <= 300),
  decided_by uuid, decided_staff text, decided_at timestamptz not null default now(),
  undone_at timestamptz, undone_by uuid,
  check (a_id < b_id)
);
create unique index if not exists crm_dup_reviews_one_active on public.crm_dup_reviews (a_id, b_id) where undone_at is null;

-- a link row can only be stamped as undone (once); it can never be deleted or rewritten; a loop cannot be inserted even by a direct write
create or replace function public._crmb_links_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'crm_customer_links is append-only'; end if;
  if tg_op = 'UPDATE' then
    if old.undone_at is not null or new.undone_at is null or new.primary_id is distinct from old.primary_id or new.linked_id is distinct from old.linked_id
       or new.reason is distinct from old.reason or new.created_at is distinct from old.created_at or new.client_id is distinct from old.client_id then
      raise exception 'crm_customer_links can only be undone once';
    end if;
    return new;
  end if;
  if exists (select 1 from public.crm_customer_links l where l.linked_id = new.primary_id and l.undone_at is null) then raise exception 'primary_is_linked'; end if;
  if exists (select 1 from public.crm_customer_links l where l.primary_id = new.linked_id and l.undone_at is null) then raise exception 'linked_has_members'; end if;
  return new;
end $$;
drop trigger if exists crm_customer_links_guard on public.crm_customer_links;
create trigger crm_customer_links_guard before insert or update or delete on public.crm_customer_links for each row execute function public._crmb_links_guard();
drop trigger if exists audit_crm_customer_links on public.crm_customer_links;
create trigger audit_crm_customer_links after insert or update on public.crm_customer_links for each row execute function public.log_change('id');
drop trigger if exists crm_dup_reviews_nodel on public.crm_dup_reviews;
create trigger crm_dup_reviews_nodel before delete on public.crm_dup_reviews for each row execute function public.no_hard_delete();
drop trigger if exists audit_crm_dup_reviews on public.crm_dup_reviews;
create trigger audit_crm_dup_reviews after insert or update on public.crm_dup_reviews for each row execute function public.log_change('id');

do $t$ declare t text; begin
  foreach t in array array['crm_customer_links', 'crm_dup_reviews'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public._i62_ok() or public.has_grant(''crm_merge''))', t || '_read', t);
  end loop;
end $t$;
revoke usage, select on sequence public.crm_customer_links_id_seq, public.crm_dup_reviews_id_seq from public, anon, authenticated;

-- ---------- helpers ----------
create or replace function public._crmb_dup_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public._i62_ok() or public.has_grant('crm_merge'));
$$;
create or replace function public._crmb_merge_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_merge'));
$$;
create or replace function public._crmb_norm_name(p text) returns text language sql immutable set search_path = public as $$
  select regexp_replace(lower(btrim(coalesce(p, ''))), '[\s\.\,\-_''"()/]+', '', 'g');
$$;
create or replace function public._crmb_norm_phone(p text) returns text language plpgsql immutable set search_path = public as $$
begin
  if p is null or btrim(p) = '' then return null; end if;
  return public.norm_mobile(p);
exception when others then return null;
end $$;
-- spelling distance with a cap (stops early; returns cap + 1 when the names are further apart)
create or replace function public._crmb_lev(a text, b text, cap int) returns int language plpgsql immutable set search_path = public as $$
declare la int := length(a); lb int := length(b); prev int[]; cur int[]; i int; j int; cost int; best int;
begin
  if abs(la - lb) > cap then return cap + 1; end if;
  if la = 0 then return lb; end if;
  if lb = 0 then return la; end if;
  prev := array(select generate_series(0, lb));
  for i in 1 .. la loop
    cur := array[i];
    best := i;
    for j in 1 .. lb loop
      cost := case when substr(a, i, 1) = substr(b, j, 1) then 0 else 1 end;
      cur := cur || least(prev[j + 1] + 1, cur[j] + 1, prev[j] + cost);
      if cur[j + 1] < best then best := cur[j + 1]; end if;
    end loop;
    if best > cap then return cap + 1; end if;
    prev := cur;
  end loop;
  return prev[lb + 1];
end $$;
create or replace function public._crmb_exc(p_flag text, p_level text, p_en text) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
    values (null, 'CRM', (select min(id) from public.locations), (now() at time zone 'Asia/Dhaka')::date, p_flag, p_level, null, jsonb_build_object('bn', p_en, 'en', p_en));
end $$;

-- ---------- the review list ----------
create or replace function public._crmb_dup_candidates(p_limit int default 100, p_offset int default 0) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sim boolean; ok boolean; lim int := least(greatest(coalesce(p_limit, 100), 1), 500); off int := greatest(coalesce(p_offset, 0), 0); q text; extra text := ''; res jsonb;
begin
  if not public._crmb_dup_ok() then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_dup_check_on') then return jsonb_build_object('off', true, 'rows', '[]'::jsonb, 'total', 0); end if;
  sim := public.rule_on('crm_dup_similar_names_on');
  ok := public._crmb_contact_ok();
  -- the second-phone table of the profile package, when it is installed
  if to_regclass('public.customer_phones') is not null
     and (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'customer_phones' and column_name in ('customer_id', 'phone', 'active')) = 3 then
    extra := 'union select customer_id, public._crmb_norm_phone(phone) from public.customer_phones where coalesce(active, true)';
  end if;
  q := $q$
  with cust as (
    select c.id, c.name, c.active, c.mobile, c.birthday, public._crmb_norm_name(c.name) nn,
           regexp_replace(lower(btrim(coalesce(c.address, ''))), '[\s\.\,\-_''"()/]+', '', 'g') na,
           coalesce((select l.primary_id from public.crm_customer_links l where l.linked_id = c.id and l.undone_at is null), c.id) root
      from public.customers c),
  dk as (   -- one-letter-apart names share a key: the name itself, or the name with one letter taken out (so no all-pairs comparison)
    select c.id, c.nn, c.nn k from cust c where @SIM@ and length(c.nn) >= 4
    union all
    select c.id, c.nn, left(c.nn, i - 1) || substr(c.nn, i + 1) from cust c, generate_series(1, 200) i where @SIM@ and length(c.nn) >= 4 and i <= length(c.nn)),
  pk as (select id, ph from (
           select id, public._crmb_norm_phone(mobile) ph from public.customers
           union select id, public._crmb_norm_phone(whatsapp) from public.customers
           @EXTRA@) z where ph is not null),
  pairs as (
    select a.id aid, b.id bid, 'same_phone'::text reason from pk a join pk b on a.ph = b.ph and a.id < b.id
    union
    select a.id, b.id, 'same_name' from cust a join cust b on a.nn = b.nn and a.id < b.id
      where length(a.nn) >= 3 and a.nn in (select nn from cust where length(nn) >= 3 group by nn having count(*) between 2 and 10)
    union
    select a.id, b.id, 'similar_name' from dk a join dk b on a.k = b.k and a.id < b.id
      where @SIM@ and a.nn <> b.nn and abs(length(a.nn) - length(b.nn)) <= 1 and public._crmb_lev(a.nn, b.nn, 1) = 1),
  g as (
    select p.aid, p.bid, array_agg(distinct p.reason order by p.reason) reasons,
           (a.na <> '' and a.na = b.na) same_addr, (a.birthday is not null and a.birthday = b.birthday) same_bday, a.root ra, b.root rb
      from pairs p join cust a on a.id = p.aid join cust b on b.id = p.bid
     group by p.aid, p.bid, a.na, b.na, a.birthday, b.birthday, a.root, b.root),
  f as (
    select g.*, case when 'same_phone' = any(g.reasons) or ('same_name' = any(g.reasons) and (g.same_addr or g.same_bday)) then 'strong'
                     when 'same_name' = any(g.reasons) or g.same_addr or g.same_bday then 'possible' else 'weak' end strength
      from g
     where g.ra <> g.rb
       and not exists (select 1 from public.crm_dup_reviews r where r.a_id = g.aid and r.b_id = g.bid and r.undone_at is null)),
  pg as (select * from f order by case strength when 'strong' then 0 when 'possible' then 1 else 2 end, aid, bid limit @LIM@ offset @OFF@)
  select jsonb_build_object('off', false, 'total', (select count(*) from f), 'masked', not @OK@,
    'rows', coalesce(jsonb_agg(jsonb_build_object(
      'a_id', pg.aid, 'b_id', pg.bid, 'strength', pg.strength,
      'reasons', to_jsonb(pg.reasons || case when pg.same_addr then array['same_address'] else '{}'::text[] end || case when pg.same_bday then array['same_birthday'] else '{}'::text[] end),
      'a', jsonb_build_object('id', ca.id, 'name', ca.name, 'active', ca.active, 'mobile', case when @OK@ then ca.mobile else public._crmb_mask_phone(ca.mobile) end),
      'b', jsonb_build_object('id', cb.id, 'name', cb.name, 'active', cb.active, 'mobile', case when @OK@ then cb.mobile else public._crmb_mask_phone(cb.mobile) end))
      order by case pg.strength when 'strong' then 0 when 'possible' then 1 else 2 end, pg.aid, pg.bid), '[]'::jsonb))
    from pg join public.customers ca on ca.id = pg.aid join public.customers cb on cb.id = pg.bid
  $q$;
  q := replace(replace(replace(replace(replace(q, '@EXTRA@', extra), '@SIM@', sim::text), '@LIM@', lim::text), '@OFF@', off::text), '@OK@', ok::text);
  execute q into res;
  return res;
end $$;

-- "these two are not the same person" (p_not_duplicate true) or reopen the pair (false)
create or replace function public._crmb_dup_review(p_client uuid, p_a uuid, p_b uuid, p_not_duplicate boolean, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a uuid := least(p_a, p_b); b uuid := greatest(p_a, p_b); ex public.crm_dup_reviews; n int;
begin
  if not public._crmb_dup_ok() then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_dup_check_on') then raise exception 'module_off'; end if;
  if p_client is null or p_a is null or p_b is null or p_not_duplicate is null or p_reason is not null and length(p_reason) > 300 then raise exception 'bad_input'; end if;
  if p_a = p_b then raise exception 'self_link'; end if;
  if p_not_duplicate and coalesce(length(btrim(p_reason)), 0) < 3 then raise exception 'reason_required'; end if;
  if (select count(*) from public.customers where id in (p_a, p_b)) <> 2 then raise exception 'customer_not_found'; end if;
  perform public._client_lock(p_client);
  select * into ex from public.crm_dup_reviews where client_id = p_client;
  if found then return jsonb_build_object('id', ex.id, 'a_id', ex.a_id, 'b_id', ex.b_id, 'duplicate', true); end if;
  if p_not_duplicate then
    begin
      insert into public.crm_dup_reviews (client_id, a_id, b_id, reason, decided_by, decided_staff) values (p_client, a, b, nullif(btrim(p_reason), ''), auth.uid(), public._crmb_staff());
    exception when unique_violation then
      return jsonb_build_object('a_id', a, 'b_id', b, 'unchanged', true, 'duplicate', false);
    end;
    return jsonb_build_object('a_id', a, 'b_id', b, 'not_duplicate', true, 'unchanged', false, 'duplicate', false);
  end if;
  update public.crm_dup_reviews set undone_at = now(), undone_by = auth.uid() where a_id = a and b_id = b and undone_at is null;
  get diagnostics n = row_count;
  return jsonb_build_object('a_id', a, 'b_id', b, 'not_duplicate', false, 'unchanged', n = 0, 'duplicate', false);
end $$;

-- ---------- link / unlink ----------
create or replace function public._crmb_link_customers(p_client uuid, p_primary uuid, p_linked uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ex public.crm_customer_links; lid bigint; m record; moved int := 0;
begin
  if not public._crmb_merge_ok() then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_dup_check_on') then raise exception 'module_off'; end if;
  if p_client is null or p_primary is null or p_linked is null then raise exception 'bad_input'; end if;
  if p_primary = p_linked then raise exception 'self_link'; end if;
  if coalesce(length(btrim(p_reason)), 0) < 3 then raise exception 'reason_required'; end if;
  if length(p_reason) > 300 then raise exception 'bad_input'; end if;
  perform public._client_lock(p_client);
  select * into ex from public.crm_customer_links where client_id = p_client;
  if found then return jsonb_build_object('id', ex.id, 'primary_id', ex.primary_id, 'linked_id', ex.linked_id, 'duplicate', true); end if;
  if (select count(*) from public.customers where id in (p_primary, p_linked)) <> 2 then raise exception 'customer_not_found'; end if;
  perform pg_advisory_xact_lock(hashtextextended('crmb_link', 0));
  if exists (select 1 from public.crm_customer_links where linked_id = p_primary and undone_at is null) then raise exception 'primary_is_linked'; end if;
  if exists (select 1 from public.crm_customer_links where linked_id = p_linked and primary_id = p_primary and undone_at is null) then raise exception 'already_linked'; end if;
  if exists (select 1 from public.crm_customer_links where linked_id = p_linked and undone_at is null) then raise exception 'linked_elsewhere'; end if;
  -- the linked customer already has duplicates of its own: they move under the new primary (one group, one level)
  for m in select id, linked_id from public.crm_customer_links where primary_id = p_linked and undone_at is null order by id loop
    update public.crm_customer_links set undone_at = now(), undone_by = auth.uid(), undo_reason = 'regrouped under ' || p_primary::text where id = m.id;
    insert into public.crm_customer_links (primary_id, linked_id, reason, created_by, created_staff) values (p_primary, m.linked_id, left('regrouped: ' || btrim(p_reason), 300), auth.uid(), public._crmb_staff());
    moved := moved + 1;
  end loop;
  insert into public.crm_customer_links (client_id, primary_id, linked_id, reason, created_by, created_staff)
    values (p_client, p_primary, p_linked, btrim(p_reason), auth.uid(), public._crmb_staff()) returning id into lid;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), public._crmb_staff(), 'crm_link', 'crm_customer_links', lid::text, jsonb_build_object('primary', p_primary, 'linked', p_linked, 'reason', btrim(p_reason), 'regrouped', moved));
  perform public._crmb_exc('customers_linked', 'yellow', 'Two customers were linked as the same person (ledgers stay separate). Reason: ' || btrim(p_reason));
  return jsonb_build_object('id', lid, 'primary_id', p_primary, 'linked_id', p_linked, 'regrouped', moved, 'duplicate', false);
end $$;

create or replace function public._crmb_unlink_customers(p_client uuid, p_linked uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.crm_customer_links;
begin
  if not public._crmb_merge_ok() then raise exception 'not allowed'; end if;
  if p_client is null or p_linked is null then raise exception 'bad_input'; end if;
  if coalesce(length(btrim(p_reason)), 0) < 3 then raise exception 'reason_required'; end if;
  if length(p_reason) > 300 then raise exception 'bad_input'; end if;
  perform public._client_lock(p_client);
  select * into l from public.crm_customer_links where undo_client = p_client;
  if found then return jsonb_build_object('id', l.id, 'primary_id', l.primary_id, 'linked_id', l.linked_id, 'unlinked', true, 'duplicate', true); end if;
  perform pg_advisory_xact_lock(hashtextextended('crmb_link', 0));
  select * into l from public.crm_customer_links where linked_id = p_linked and undone_at is null;
  if not found then raise exception 'not_linked'; end if;
  update public.crm_customer_links set undone_at = now(), undone_by = auth.uid(), undo_reason = btrim(p_reason), undo_client = p_client where id = l.id;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), public._crmb_staff(), 'crm_unlink', 'crm_customer_links', l.id::text, jsonb_build_object('primary', l.primary_id, 'linked', l.linked_id, 'reason', btrim(p_reason)));
  return jsonb_build_object('id', l.id, 'primary_id', l.primary_id, 'linked_id', l.linked_id, 'unlinked', true, 'duplicate', false);
end $$;

-- ---------- read side ----------
-- one person: every number in the group, ledgers kept apart, CRM figures added up (spend, orders, last purchase, points). Balances are listed per customer and never added.
create or replace function public._crmb_customer_group(p_customer uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare root uuid; ok boolean := public._crmb_contact_ok(); members jsonb; sp numeric := 0; ord int := 0; ls date; pt int := 0; m record; st record;
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.customers where id = p_customer) then raise exception 'customer_not_found'; end if;
  root := public._crmb_group_root(p_customer);
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'mobile', case when ok then c.mobile else public._crmb_mask_phone(c.mobile) end, 'active', c.active,
           'is_primary', c.id = root, 'balance', public._cust_bal(c.id), 'linked_at', l.created_at, 'link_reason', l.reason) order by (c.id = root) desc, l.created_at, c.id), '[]'::jsonb)
    into members
    from public.customers c left join public.crm_customer_links l on l.linked_id = c.id and l.undone_at is null
   where c.id = root or c.id in (select linked_id from public._crmb_links_active() where primary_id = root);
  for m in select c.id from public.customers c where c.id = root or c.id in (select linked_id from public._crmb_links_active() where primary_id = root) loop
    select * into st from public._cust_stats43(m.id, true);
    sp := sp + coalesce(st.spend, 0); ord := ord + coalesce(st.orders, 0); ls := greatest(ls, st.last_sale);
    pt := pt + coalesce((select sum(delta) from public.customer_points_ledger where customer_id = m.id), 0)::int;
  end loop;
  return jsonb_build_object('customer_id', p_customer, 'root_id', root, 'is_primary', p_customer = root, 'in_group', jsonb_array_length(members) > 1, 'members', members,
    'combined', jsonb_build_object('spend', sp, 'orders', ord, 'last_sale', ls, 'points', pt), 'ledgers_separate', true,
    'note', 'Dues, payments and the books stay on each customer. Only spend, orders, last purchase and points are shown together.');
end $$;

create or replace function public._crmb_links_list(p_limit int default 100, p_include_undone boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ok boolean := public._crmb_contact_ok();
begin
  if not public._crmb_dup_ok() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
    select l.id, l.primary_id, pc.name as primary_name, case when ok then pc.mobile else public._crmb_mask_phone(pc.mobile) end as primary_mobile,
           l.linked_id, lc.name as linked_name, case when ok then lc.mobile else public._crmb_mask_phone(lc.mobile) end as linked_mobile,
           l.reason, l.created_staff, l.created_at, l.undone_at, l.undo_reason
      from public.crm_customer_links l join public.customers pc on pc.id = l.primary_id join public.customers lc on lc.id = l.linked_id
     where p_include_undone or l.undone_at is null order by l.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
end $$;

-- ---------- privileges (only the functions of THIS file) ----------
do $p$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
            and p.proname = any (array['_crmb_links_guard', '_crmb_dup_ok', '_crmb_merge_ok', '_crmb_norm_name', '_crmb_norm_phone', '_crmb_lev', '_crmb_exc', '_crmb_dup_candidates',
              '_crmb_dup_review', '_crmb_link_customers', '_crmb_unlink_customers', '_crmb_customer_group', '_crmb_links_list']) loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $p$;
grant execute on function public._crmb_dup_candidates(int, int), public._crmb_dup_review(uuid, uuid, uuid, boolean, text), public._crmb_link_customers(uuid, uuid, uuid, text),
  public._crmb_unlink_customers(uuid, uuid, text), public._crmb_customer_group(uuid), public._crmb_links_list(int, boolean) to authenticated;
