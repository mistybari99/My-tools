-- ============================================================
-- Phase 100 (bos100) - STEP Cat: ONE category / sub-category master for every item.
--   Needs phases 72..97 (docs/PASTE_ORDER.md) - guard below. Additive, paste-twice safe. NO existing function is re-created
--   (items.category / items.sub_category stay the text columns every old screen reads; nothing breaks), so there is nothing to re-base on phase98 / phase99.
--   Nothing is invented: names come from the existing items (category_bn), the existing editable lists (option_lists item_categories /
--   item_subcategories) or the stored code itself.
--
--   Table item_categories (tree: parent_id null = Category, parent_id set = Sub-category). `code` is the text value kept in items.category /
--   items.sub_category (stable on rename). items also get category_id / sub_category_id, kept in sync by a trigger (which also registers a new text value).
--   RPCs: category_list, category_save (add / sort / deactivate, client id = idempotent), category_rename (owner), category_merge (owner),
--         category_move (sub -> another category), category_reorder, item_set_category(+_bulk), category_sync100, category_rule_state, items_missing_category,
--         biz_items_by_category, stock_valuation_by_category (read-only wrappers: totals == the ungrouped report; cost columns only for cost-right holders).
--   Rule category_required_on_item = off (default) | warn | required (recommended: warn). 'required' refuses a NEW item without a category (and clearing it);
--   old items without a category stay editable. 'warn' is shown on the screens + the missing list.
--   Manage = owner or the item_create / item_bulk grant; rename + merge = owner only. Every change is in the audit log (log_change + a merge row).
-- Tag: bos100.
--   NOTE: item_sys stays set to the end of the transaction after merge / rename / move (transaction-local; PostgREST runs one RPC per transaction).
-- ============================================================

-- ---------- 0. guard ----------
do $g$
declare miss text := '';
begin
  if to_regprocedure('public._cogs_lines72(date,date,integer[])') is null then miss := miss || ' 72'; end if;
  if to_regprocedure('public._recipe_gate73(uuid)') is null then miss := miss || ' 73'; end if;
  if to_regprocedure('public._pool_rate(integer,date,text)') is null then miss := miss || ' 74'; end if;
  if to_regprocedure('public._cs_alloc(bigint)') is null then miss := miss || ' 75'; end if;
  if to_regclass('public.intake_failures') is null then miss := miss || ' 76'; end if;
  if to_regprocedure('public._oo_short77(uuid)') is null then miss := miss || ' 77'; end if;
  if to_regprocedure('public._c78_main_loc(date)') is null then miss := miss || ' 78'; end if;
  if to_regprocedure('public._cost_free80(uuid)') is null then miss := miss || ' 80'; end if;
  if to_regclass('public.setup_rec_defs81') is null then miss := miss || ' 81'; end if;
  if to_regprocedure('public.grn_bill_link(uuid,uuid,text)') is null then miss := miss || ' 82'; end if;
  if to_regprocedure('public._pf83_ro()') is null then miss := miss || ' 83'; end if;
  if to_regprocedure('public._aud84()') is null then miss := miss || ' 84'; end if;
  if to_regclass('public.acct_autopost_runs85') is null then miss := miss || ' 85'; end if;
  if to_regprocedure('public._tg_hash(text)') is null then miss := miss || ' 86'; end if;
  if to_regprocedure('public._prod_double_issue87()') is null then miss := miss || ' 87'; end if;
  if to_regprocedure('public._rcs88()') is null then miss := miss || ' 88'; end if;
  if to_regprocedure('public._sale_stock_out()') is null or position('bos89' in pg_get_functiondef('public._sale_stock_out()'::regprocedure)) = 0 then miss := miss || ' 89'; end if;
  if to_regclass('public.scan_jobs') is null then miss := miss || ' 90'; end if;
  if to_regprocedure('public._ov_key(text,text)') is null then miss := miss || ' 91'; end if;
  if to_regclass('public.invoice_shares') is null then miss := miss || ' 92'; end if;
  if to_regclass('public.doc_template_choice') is null then miss := miss || ' 93'; end if;
  if to_regprocedure('public.anon_exec_audit94()') is null then miss := miss || ' 94'; end if;
  if not exists (select 1 from public.rules where key = 'cash_drawer_mode') then miss := miss || ' 95'; end if;
  if to_regclass('public.ledger_cost_supply96') is null then miss := miss || ' 96'; end if;
  if to_regclass('public.landed_costs') is null then miss := miss || ' 97'; end if;
  if miss <> '' then raise exception 'phase100 needs phases 72..97 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

-- ---------- 1. the master table ----------
create table if not exists public.item_categories (
  id bigint generated always as identity primary key,
  parent_id bigint references public.item_categories(id),
  code text not null check (length(btrim(code)) between 1 and 80),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 120),
  name_en text check (name_en is null or length(btrim(name_en)) between 1 and 120),
  name_mix text,
  sort integer not null default 0,
  active boolean not null default true,
  merged_into bigint references public.item_categories(id),
  client_id uuid,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_by uuid,
  updated_at timestamptz not null default now()
);
create unique index if not exists item_categories_code_uq100 on public.item_categories ((coalesce(parent_id, 0)), code);
create unique index if not exists item_categories_name_uq100 on public.item_categories ((coalesce(parent_id, 0)), lower(btrim(name_bn))) where active;
create unique index if not exists item_categories_client_uq100 on public.item_categories (client_id) where client_id is not null;
create index if not exists item_categories_parent_idx100 on public.item_categories (parent_id);

alter table public.item_categories enable row level security;
drop policy if exists item_categories_read100 on public.item_categories;
create policy item_categories_read100 on public.item_categories for select to authenticated using (public.is_active());
revoke all on table public.item_categories from public, anon, authenticated;
grant select on table public.item_categories to authenticated;

create or replace function public._item_categories_before100() returns trigger language plpgsql security definer set search_path = public as $f$
begin   -- bos100
  new.name_bn := btrim(new.name_bn); new.code := btrim(new.code);
  if new.name_en is not null then new.name_en := nullif(btrim(new.name_en), ''); end if;
  if tg_op = 'UPDATE' then new.updated_at := now(); new.updated_by := auth.uid(); else new.created_by := coalesce(new.created_by, auth.uid()); end if;
  if new.parent_id is not null and exists (select 1 from public.item_categories p where p.id = new.parent_id and p.parent_id is not null) then raise exception 'cat_depth'; end if;   -- two levels only
  if new.parent_id is not null and new.parent_id = new.id then raise exception 'cat_depth'; end if;
  return new;
end $f$;
drop trigger if exists item_categories_before100 on public.item_categories;
create trigger item_categories_before100 before insert or update on public.item_categories for each row execute function public._item_categories_before100();
drop trigger if exists item_categories_no_delete100 on public.item_categories;
create trigger item_categories_no_delete100 before delete on public.item_categories for each row execute function public.no_hard_delete();
drop trigger if exists audit_item_categories100 on public.item_categories;
create trigger audit_item_categories100 after insert or update on public.item_categories for each row execute function public.log_change('id');

alter table public.items add column if not exists category_id bigint;
alter table public.items add column if not exists sub_category_id bigint;
create index if not exists items_category_id_idx100 on public.items (category_id);

-- ---------- 2. rule + recommendation ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('category_required_on_item', 'items', 'choice', '"off"', null, '["off","warn","required"]'::jsonb, null, null,
  'প্রতিটি আইটেমে Category / Sub-category: বন্ধ / warn / লাগবেই', 'প্রতিটি Item-এ Category / Sub-category: off / warn / required', 'Category / Sub-category on every item: off, warn or required',
  'বন্ধ = আগের মতো। warn = Category ছাড়া আইটেমের তালিকা দেখায়, আটকায় না (প্রস্তাবিত)। required = নতুন আইটেম Category ছাড়া সেভ হয় না (Category-র Sub-category থাকলে সেটাও লাগবে); পুরনো আইটেম আগের মতো এডিট করা যায়।',
  'off = আগের মতো। warn = Category ছাড়া Item-এর list দেখায়, আটকায় না (recommended)। required = নতুন Item Category ছাড়া save হয় না (Category-র Sub-category থাকলে সেটাও লাগবে); পুরনো Item আগের মতো edit করা যায়।',
  'off = as before. warn = lists the items with no category and never blocks (recommended). required = a NEW item cannot be saved without a Category (and a Sub-category when the Category has any); old items stay editable.', 910)
on conflict (key) do nothing;

insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('category_required_on_item', 'category_required_on_item', '100', 'items', '"warn"', '{}',
  'প্রতিটি আইটেমের Category ও Sub-category থাকলে বিক্রি, স্টক, খরচ ও রিপোর্ট ধরে ধরে দেখা যায়। প্রথমে warn রাখুন: Category ছাড়া আইটেমের তালিকা দেখে ঠিক করুন। সব ঠিক হলে required করা যায়। সিদ্ধান্ত মালিকের।',
  'প্রতিটি Item-এর Category ও Sub-category থাকলে sale, stock, cost ও report ধরে ধরে দেখা যায়। প্রথমে warn রাখুন: Category ছাড়া Item-এর list দেখে ঠিক করুন। সব ঠিক হলে required করা যায়। সিদ্ধান্ত owner-এর।',
  'With a Category and Sub-category on every item, sales, stock, cost and reports can be read by group. Start with warn, fix the items on the missing list, then switch to required when it is empty. The owner decides.', 300)
on conflict (code) do nothing;

-- ---------- 3. helpers ----------
create or replace function public._cat_mgr100() returns boolean language sql stable security definer set search_path = public as $f$
  select public.is_active() and (public.is_owner() or public.has_grant('item_create') or public.has_grant('item_bulk'));   -- bos100
$f$;

-- a stable text code for a new Category / Sub-category (never shown)
create sequence if not exists public.item_cat_seq100;
create or replace function public._cat_newcode100(p_sub boolean) returns text language plpgsql security definer set search_path = public as $f$
declare c text;
begin   -- bos100
  loop
    c := case when p_sub then 's' else 'k' end || lpad(nextval('public.item_cat_seq100')::text, 3, '0');
    exit when not exists (select 1 from public.item_categories where code = c)
          and not exists (select 1 from public.option_lists where list_code in ('item_categories', 'item_subcategories') and value_code = c)
          and not exists (select 1 from public.items where category = c or sub_category = c);
  end loop;
  return c;
end $f$;

-- keep the editable lists (option_lists) that the item editor reads in step with the master (best effort: a locked list is left alone)
create or replace function public._cat_ol_put100(p_sub boolean, p_code text, p_bn text, p_en text, p_active boolean, p_sort integer) returns void language plpgsql security definer set search_path = public as $f$
declare lc text := case when p_sub then 'item_subcategories' else 'item_categories' end;
begin   -- bos100
  insert into public.option_lists (list_code, value_code, label_bn, label_en, sort, active) values (lc, p_code, p_bn, p_en, coalesce(p_sort, 0), coalesce(p_active, true))
  on conflict (list_code, value_code) do update set label_bn = excluded.label_bn, label_en = coalesce(excluded.label_en, public.option_lists.label_en), active = excluded.active, sort = excluded.sort;
exception when others then null;   -- list locked / rule: the master still works
end $f$;

-- the seed: master rows for every distinct existing value (idempotent; also what category_sync100 runs)
create or replace function public._cat_seed100() returns jsonb language plpgsql security definer set search_path = public as $f$
declare r record; nm text; n_top int := 0; n_sub int := 0; pid bigint; cnt int := 0;
begin   -- bos100
  for r in
    select v.code,
           coalesce((select nullif(btrim(o.label_bn), '') from public.option_lists o where o.list_code = 'item_categories' and o.value_code = v.code),
                    (select max(i.category_bn) from public.items i where i.category = v.code and nullif(btrim(i.category_bn), '') is not null),
                    (select nullif(btrim(o.label_en), '') from public.option_lists o where o.list_code = 'item_categories' and o.value_code = v.code), v.code) as bn,
           (select nullif(btrim(o.label_en), '') from public.option_lists o where o.list_code = 'item_categories' and o.value_code = v.code) as en,
           coalesce((select o.sort from public.option_lists o where o.list_code = 'item_categories' and o.value_code = v.code), 0) as srt,
           coalesce((select o.active from public.option_lists o where o.list_code = 'item_categories' and o.value_code = v.code), true) as act
    from (select btrim(category) code from public.items where nullif(btrim(category), '') is not null
          union select value_code from public.option_lists where list_code = 'item_categories') v
    order by 4, 2, 1
  loop
    if exists (select 1 from public.item_categories where parent_id is null and code = r.code) then continue; end if;
    nm := r.bn;
    if exists (select 1 from public.item_categories where parent_id is null and active and lower(btrim(name_bn)) = lower(btrim(nm))) then nm := nm || ' (' || r.code || ')'; end if;
    insert into public.item_categories (parent_id, code, name_bn, name_en, sort, active) values (null, r.code, nm, r.en, r.srt, r.act);
    n_top := n_top + 1;
  end loop;
  for r in
    select distinct btrim(i.category) cat, btrim(i.sub_category) sub from public.items i
    where nullif(btrim(i.category), '') is not null and nullif(btrim(i.sub_category), '') is not null order by 1, 2
  loop
    select id into pid from public.item_categories where parent_id is null and code = r.cat;
    if pid is null or exists (select 1 from public.item_categories where parent_id = pid and code = r.sub) then continue; end if;
    nm := coalesce((select nullif(btrim(o.label_bn), '') from public.option_lists o where o.list_code = 'item_subcategories' and o.value_code = r.sub),
                   (select nullif(btrim(o.label_en), '') from public.option_lists o where o.list_code = 'item_subcategories' and o.value_code = r.sub), r.sub);
    if exists (select 1 from public.item_categories where parent_id = pid and active and lower(btrim(name_bn)) = lower(btrim(nm))) then nm := nm || ' (' || r.sub || ')'; end if;
    insert into public.item_categories (parent_id, code, name_bn, name_en, sort, active)
      values (pid, r.sub, nm, (select nullif(btrim(o.label_en), '') from public.option_lists o where o.list_code = 'item_subcategories' and o.value_code = r.sub), 0, true);
    n_sub := n_sub + 1;
  end loop;
  -- link the items (no audit noise, locked items included: only the id columns change; the items trigger is not fired by these columns)
  perform set_config('bos.item_sys', '1', true); perform set_config('bos.item_import', '1', true);
  update public.items i set category_id = c.id
    from public.item_categories c where c.parent_id is null and c.code = btrim(i.category) and i.category_id is distinct from c.id;
  get diagnostics cnt = row_count;
  update public.items i set sub_category_id = s.id
    from public.item_categories c join public.item_categories s on s.parent_id = c.id
    where c.parent_id is null and c.code = btrim(i.category) and s.code = btrim(i.sub_category) and i.sub_category_id is distinct from s.id;
  update public.items i set category_id = null where nullif(btrim(i.category), '') is null and i.category_id is not null;
  update public.items i set sub_category_id = null where nullif(btrim(i.sub_category), '') is null and i.sub_category_id is not null;
  perform set_config('bos.item_sys', '', true); perform set_config('bos.item_import', '', true);
  return jsonb_build_object('categories_added', n_top, 'sub_categories_added', n_sub, 'items_linked', cnt);
end $f$;

-- ---------- 4. trigger on items: keep ids in step with the text columns, register new values, enforce the rule ----------
create or replace function public._items_cat100() returns trigger language plpgsql security definer set search_path = public as $f$
declare cid bigint; sid bigint; cat text := nullif(btrim(new.category), ''); sub text := nullif(btrim(new.sub_category), ''); sysq boolean;
begin   -- bos100
  sysq := coalesce(current_setting('bos.item_sys', true), '') = '1' or coalesce(current_setting('bos.item_import', true), '') = '1';
  if cat is not null then
    select id into cid from public.item_categories where parent_id is null and code = cat;
    if cid is null and not sysq then
      begin   -- registering is an add-on: it can never block an item save
        insert into public.item_categories (parent_id, code, name_bn) values (null, cat, coalesce(nullif(btrim(new.category_bn), ''), cat))
          on conflict do nothing returning id into cid;
        if cid is null then select id into cid from public.item_categories where parent_id is null and code = cat; end if;
        if cid is null then   -- the name is taken by another code: register under the code
          insert into public.item_categories (parent_id, code, name_bn) values (null, cat, cat || ' (' || cat || ')') on conflict do nothing returning id into cid;
        end if;
      exception when others then cid := null;
      end;
    end if;
  end if;
  new.category_id := cid;
  sid := null;
  if sub is not null and cid is not null then
    select id into sid from public.item_categories where parent_id = cid and code = sub;
    if sid is null and not sysq then
      begin
        insert into public.item_categories (parent_id, code, name_bn) values (cid, sub, sub) on conflict do nothing returning id into sid;
        if sid is null then select id into sid from public.item_categories where parent_id = cid and code = sub; end if;
        if sid is null then insert into public.item_categories (parent_id, code, name_bn) values (cid, sub, sub || ' (' || sub || ')') on conflict do nothing returning id into sid; end if;
      exception when others then sid := null;
      end;
    end if;
  end if;
  new.sub_category_id := sid;
  return new;
end $f$;
drop trigger if exists items_cat100 on public.items;
create trigger items_cat100 before insert or update of category, sub_category on public.items for each row execute function public._items_cat100();

-- the rule 'required' is checked at the END of the statement's transaction (a deferred constraint trigger on the FINAL row): the item editor inserts the item first
-- and sets the Sub-category in a second statement, so a per-statement check would refuse a complete item
create or replace function public._items_cat_req100() returns trigger language plpgsql security definer set search_path = public as $f$
declare mode text; cur record; sysq boolean;
begin   -- bos100
  sysq := coalesce(current_setting('bos.item_sys', true), '') = '1' or coalesce(current_setting('bos.item_import', true), '') = '1';
  if sysq then return null; end if;
  mode := coalesce(public.rule_txt('category_required_on_item'), 'off');
  if mode <> 'required' then return null; end if;
  select i.category, i.sub_category, i.category_id into cur from public.items i where i.id = new.id;
  if not found then return null; end if;
  if nullif(btrim(cur.category), '') is null then
    if tg_op = 'INSERT' or nullif(btrim(old.category), '') is not null then raise exception 'category_required' using hint = 'category_required_on_item'; end if;
    return null;
  end if;
  if nullif(btrim(cur.sub_category), '') is null and exists (select 1 from public.item_categories s where s.parent_id = cur.category_id and s.active)
     and (tg_op = 'INSERT' or cur.category is distinct from old.category or old.sub_category is distinct from cur.sub_category) then
    raise exception 'sub_category_required' using hint = 'category_required_on_item';
  end if;
  return null;
end $f$;
drop trigger if exists items_cat_req100 on public.items;
create constraint trigger items_cat_req100 after insert or update of category, sub_category on public.items deferrable initially deferred for each row execute function public._items_cat_req100();

-- a Category added to the editable list later is registered too (a Sub-category needs its parent, which the first item that uses it gives)
create or replace function public._ol_cat100() returns trigger language plpgsql security definer set search_path = public as $f$
declare nm text := coalesce(nullif(btrim(new.label_bn), ''), nullif(btrim(new.label_en), ''), new.value_code);
begin   -- bos100
  if new.list_code = 'item_categories' and not exists (select 1 from public.item_categories where parent_id is null and code = new.value_code) then
    begin   -- the master is an add-on: whatever goes wrong here must never block the editable list
      insert into public.item_categories (parent_id, code, name_bn, name_en, sort, active)
        values (null, new.value_code, case when exists (select 1 from public.item_categories x where x.parent_id is null and x.active and lower(btrim(x.name_bn)) = lower(btrim(nm))) then nm || ' (' || new.value_code || ')' else nm end,
                nullif(btrim(new.label_en), ''), coalesce(new.sort, 0), new.active);
    exception when others then null;
    end;
  end if;
  return new;
end $f$;
drop trigger if exists option_lists_cat100 on public.option_lists;
create trigger option_lists_cat100 after insert on public.option_lists for each row execute function public._ol_cat100();

select public._cat_seed100();

-- ---------- 5. RPCs ----------
create or replace function public.category_list(p_include_inactive boolean default false)
returns table (id bigint, parent_id bigint, code text, name_bn text, name_en text, name_mix text, sort integer, active boolean, item_count bigint)
language plpgsql stable security definer set search_path = public as $f$
#variable_conflict use_column
begin   -- bos100
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    select c.id, c.parent_id, c.code, c.name_bn, c.name_en, c.name_mix, c.sort, c.active,
           (select count(*) from public.items i where case when c.parent_id is null then i.category_id = c.id else i.sub_category_id = c.id end)::bigint
    from public.item_categories c
    where (p_include_inactive or (c.active and (c.parent_id is null or exists (select 1 from public.item_categories p where p.id = c.parent_id and p.active))))
    order by coalesce(c.parent_id, c.id), (c.parent_id is not null), c.sort, c.name_bn, c.id;
end $f$;

create or replace function public.category_save(p_id bigint default null, p_parent bigint default null, p_name_bn text default null, p_name_en text default null,
                                                p_sort integer default null, p_active boolean default null, p_client uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $f$
declare r public.item_categories; bn text; en text; code_ text; nid bigint;
begin   -- bos100
  if not public._cat_mgr100() then raise exception 'not allowed'; end if;
  if p_client is not null then
    select * into r from public.item_categories where client_id = p_client;
    if found then return jsonb_build_object('id', r.id, 'code', r.code, 'duplicate', true); end if;
  end if;
  if p_id is null then
    bn := nullif(btrim(p_name_bn), ''); en := nullif(btrim(p_name_en), '');
    bn := coalesce(bn, en);
    if bn is null then raise exception 'name_required'; end if;
    if p_parent is not null and not exists (select 1 from public.item_categories where id = p_parent and parent_id is null and active) then raise exception 'bad_parent'; end if;
    if exists (select 1 from public.item_categories where coalesce(parent_id, 0) = coalesce(p_parent, 0) and active and lower(btrim(name_bn)) = lower(bn)) then raise exception 'name_taken'; end if;
    code_ := public._cat_newcode100(p_parent is not null);
    insert into public.item_categories (parent_id, code, name_bn, name_en, sort, active, client_id)
      values (p_parent, code_, bn, en, coalesce(p_sort, (select coalesce(max(x.sort), 0) + 10 from public.item_categories x where coalesce(x.parent_id, 0) = coalesce(p_parent, 0))), true, p_client) returning id into nid;
    perform public._cat_ol_put100(p_parent is not null, code_, bn, en, true, coalesce(p_sort, 0));
    return jsonb_build_object('id', nid, 'code', code_);
  end if;
  select * into r from public.item_categories where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if p_name_bn is not null or p_name_en is not null then raise exception 'use_rename'; end if;   -- names change only through category_rename (owner)
  if p_active is true and not r.active and r.merged_into is not null then raise exception 'merged'; end if;
  if p_active is true and not r.active and exists (select 1 from public.item_categories x where coalesce(x.parent_id, 0) = coalesce(r.parent_id, 0) and x.active and x.id <> r.id and lower(btrim(x.name_bn)) = lower(btrim(r.name_bn))) then raise exception 'name_taken'; end if;
  update public.item_categories set sort = coalesce(p_sort, sort), active = coalesce(p_active, active) where id = p_id;
  perform public._cat_ol_put100(r.parent_id is not null, r.code, r.name_bn, r.name_en, coalesce(p_active, r.active), coalesce(p_sort, r.sort));
  return jsonb_build_object('id', p_id, 'code', r.code);
end $f$;

create or replace function public.category_reorder(p_ids bigint[]) returns integer language plpgsql security definer set search_path = public as $f$
declare i int := 0; x bigint; c public.item_categories;
begin   -- bos100
  if not public._cat_mgr100() then raise exception 'not allowed'; end if;
  foreach x in array coalesce(p_ids, '{}') loop
    i := i + 10;
    update public.item_categories set sort = i where id = x;
    select * into c from public.item_categories where id = x;
    if found then perform public._cat_ol_put100(c.parent_id is not null, c.code, c.name_bn, c.name_en, c.active, i); end if;
  end loop;
  return i / 10;
end $f$;

create or replace function public.category_rename(p_id bigint, p_name_bn text, p_name_en text default null) returns jsonb language plpgsql security definer set search_path = public as $f$
declare r public.item_categories; bn text := nullif(btrim(p_name_bn), ''); en text := nullif(btrim(p_name_en), ''); n int := 0;
begin   -- bos100
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if bn is null then raise exception 'name_required'; end if;
  select * into r from public.item_categories where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if exists (select 1 from public.item_categories x where coalesce(x.parent_id, 0) = coalesce(r.parent_id, 0) and x.active and x.id <> r.id and lower(btrim(x.name_bn)) = lower(bn)) then raise exception 'name_taken'; end if;
  update public.item_categories set name_bn = bn, name_en = en where id = p_id;
  if r.parent_id is null then   -- items keep the code; their Bangla display name follows the master
    perform set_config('bos.item_sys', '1', true);   -- stays on to the end of the transaction (the deferred 'required' check reads it)
    update public.items set category_bn = bn where category_id = p_id and category_bn is distinct from bn;
    get diagnostics n = row_count;
  end if;
  perform public._cat_ol_put100(r.parent_id is not null, r.code, bn, en, r.active, r.sort);
  return jsonb_build_object('id', p_id, 'items_updated', n);
end $f$;

create or replace function public.category_merge(p_from bigint, p_into bigint, p_client uuid default null) returns jsonb language plpgsql security definer set search_path = public as $f$
declare f public.item_categories; t public.item_categories; s record; tg bigint; n_items int := 0; n_subs int := 0; sid text;
begin   -- bos100
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_from is null or p_into is null or p_from = p_into then raise exception 'bad_request'; end if;
  select * into f from public.item_categories where id = p_from for update;
  select * into t from public.item_categories where id = p_into for update;
  if f.id is null or t.id is null then raise exception 'not_found'; end if;
  if f.merged_into = t.id then return jsonb_build_object('items_moved', 0, 'subs_moved', 0, 'duplicate', true); end if;
  if (f.parent_id is null) <> (t.parent_id is null) then raise exception 'same_level_only'; end if;
  if not t.active then raise exception 'target_inactive'; end if;
  perform set_config('bos.item_sys', '1', true);
  if f.parent_id is null then
    -- sub-categories of the source: moved under the target, or folded into a same-code / same-name one of the target
    for s in select * from public.item_categories where parent_id = f.id order by id loop
      select x.id into tg from public.item_categories x where x.parent_id = t.id and (x.code = s.code or (x.active and lower(btrim(x.name_bn)) = lower(btrim(s.name_bn)))) order by (x.code = s.code) desc limit 1;
      if tg is null then
        update public.item_categories set parent_id = t.id where id = s.id;
        n_subs := n_subs + 1;
      else
        update public.items set sub_category = (select x.code from public.item_categories x where x.id = tg) where category_id = f.id and sub_category_id = s.id;
        update public.item_categories set active = false, merged_into = tg where id = s.id;
      end if;
    end loop;
    update public.items set category = t.code, category_bn = t.name_bn where category_id = f.id;
    get diagnostics n_items = row_count;
  else
    update public.items set category = (select x.code from public.item_categories x where x.id = t.parent_id), category_bn = (select x.name_bn from public.item_categories x where x.id = t.parent_id),
           sub_category = t.code where sub_category_id = f.id;
    get diagnostics n_items = row_count;
  end if;
  update public.item_categories set active = false, merged_into = t.id where id = f.id;
  perform public._cat_ol_put100(f.parent_id is not null, f.code, f.name_bn, f.name_en, false, f.sort);
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'category_merge', 'item_categories', p_from::text, jsonb_build_object('into', p_into, 'items_moved', n_items, 'subs_moved', n_subs, 'client_id', p_client));
  return jsonb_build_object('items_moved', n_items, 'subs_moved', n_subs);
end $f$;

create or replace function public.category_move(p_id bigint, p_new_parent bigint) returns jsonb language plpgsql security definer set search_path = public as $f$
declare r public.item_categories; np public.item_categories; n int := 0;
begin   -- bos100
  if not public._cat_mgr100() then raise exception 'not allowed'; end if;
  select * into r from public.item_categories where id = p_id for update;
  select * into np from public.item_categories where id = p_new_parent;
  if r.id is null or np.id is null then raise exception 'not_found'; end if;
  if r.parent_id is null or np.parent_id is not null or not np.active then raise exception 'bad_parent'; end if;
  if r.parent_id = np.id then return jsonb_build_object('items_moved', 0); end if;
  if exists (select 1 from public.item_categories x where x.parent_id = np.id and (x.code = r.code or (x.active and lower(btrim(x.name_bn)) = lower(btrim(r.name_bn))))) then raise exception 'sub_exists'; end if;
  perform set_config('bos.item_sys', '1', true);
  update public.item_categories set parent_id = np.id where id = r.id;
  update public.items set category = np.code, category_bn = np.name_bn where sub_category_id = r.id;
  get diagnostics n = row_count;
  return jsonb_build_object('items_moved', n);
end $f$;

create or replace function public.item_set_category(p_item uuid, p_cat bigint, p_sub bigint default null) returns jsonb language plpgsql security definer set search_path = public as $f$
declare c public.item_categories; s public.item_categories;
begin   -- bos100
  if not public._cat_mgr100() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.items where id = p_item) then raise exception 'not_found'; end if;
  if p_cat is null then
    if p_sub is not null then raise exception 'bad_parent'; end if;
    update public.items set category = null, category_bn = null, sub_category = null where id = p_item;   -- the items trigger refuses it when the rule is 'required'
    return jsonb_build_object('item_id', p_item, 'category', null, 'sub_category', null);
  end if;
  select * into c from public.item_categories where id = p_cat;
  if c.id is null or c.parent_id is not null or not c.active then raise exception 'bad_category'; end if;
  if p_sub is not null then
    select * into s from public.item_categories where id = p_sub;
    if s.id is null or s.parent_id is distinct from c.id or not s.active then raise exception 'bad_sub_category'; end if;
  end if;
  update public.items set category = c.code, category_bn = c.name_bn, sub_category = s.code where id = p_item;
  return jsonb_build_object('item_id', p_item, 'category', c.code, 'sub_category', s.code);
end $f$;

create or replace function public.item_set_category_bulk(p_items uuid[], p_cat bigint, p_sub bigint default null, p_client uuid default null) returns jsonb language plpgsql security definer set search_path = public as $f$
declare x uuid; n int := 0;
begin   -- bos100
  if not public._cat_mgr100() then raise exception 'not allowed'; end if;
  if coalesce(array_length(p_items, 1), 0) > 500 then raise exception 'too_many'; end if;
  foreach x in array coalesce(p_items, '{}') loop perform public.item_set_category(x, p_cat, p_sub); n := n + 1; end loop;
  return jsonb_build_object('items', n);
end $f$;

create or replace function public.category_sync100() returns jsonb language plpgsql security definer set search_path = public as $f$
begin   -- bos100
  if not public._cat_mgr100() then raise exception 'not allowed'; end if;
  return public._cat_seed100();
end $f$;

create or replace function public.category_rule_state() returns jsonb language plpgsql stable security definer set search_path = public as $f$
begin   -- bos100
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object('mode', coalesce(public.rule_txt('category_required_on_item'), 'off'), 'recommended', 'warn',
    'missing', (select count(*) from public.items i where i.is_active and i.count_in_business and nullif(btrim(i.category), '') is null),
    'missing_sub', (select count(*) from public.items i where i.is_active and i.count_in_business and nullif(btrim(i.category), '') is not null and nullif(btrim(i.sub_category), '') is null
                       and exists (select 1 from public.item_categories s where s.parent_id = i.category_id and s.active)));
end $f$;

create or replace function public.items_missing_category(p_limit integer default 200)
returns table (item_id uuid, code text, name_bn text, name_en text, item_type text, category text, sub_category text, reason text)
language plpgsql stable security definer set search_path = public as $f$
#variable_conflict use_column
begin   -- bos100
  if not public._cat_mgr100() then raise exception 'not allowed'; end if;
  return query
    select i.id, i.code, i.name_bn, i.name_en, i.item_type, i.category, i.sub_category,
           case when nullif(btrim(i.category), '') is null then 'no_category' else 'no_sub_category' end
    from public.items i
    where i.is_active and i.count_in_business and (nullif(btrim(i.category), '') is null
          or (nullif(btrim(i.sub_category), '') is null and exists (select 1 from public.item_categories s where s.parent_id = i.category_id and s.active)))
    order by i.code limit least(greatest(coalesce(p_limit, 200), 1), 2000);
end $f$;

-- ---------- 6. reports by Category / Sub-category (read-only wrappers: same permission checks and cost secrecy as the ungrouped report) ----------
create or replace function public.biz_items_by_category(p_from date, p_to date, p_loc integer default null, p_level text default 'category')
returns table (category text, sub_category text, cat_name_bn text, cat_name_en text, sub_name_bn text, sub_name_en text, items bigint, revenue numeric, cogs numeric, cogs_unknown_items bigint, share_pct numeric)
language plpgsql stable security definer set search_path = public as $f$
#variable_conflict use_column
begin   -- bos100
  if p_level not in ('category', 'sub') then raise exception 'bad_level'; end if;
  return query
  with b as (select * from public.biz_items(p_from, p_to, p_loc)),   -- biz_items refuses a caller without report rights and hides cost without the cost right
  j as (
    select nullif(btrim(i.category), '') cat, case when p_level = 'sub' then nullif(btrim(i.sub_category), '') end sb, b.revenue rev, b.cogs cg
    from b join public.items i on i.id = b.item_id),
  g as (select j.cat, j.sb, count(*) n, sum(j.rev) rev, sum(j.cg) cg, count(*) filter (where j.cg is null and j.rev > 0) unk from j group by 1, 2),
  tot as (select coalesce(sum(g.rev), 0) t from g)
  select g.cat, g.sb, c.name_bn, c.name_en, s.name_bn, s.name_en, g.n, g.rev, g.cg, g.unk,
         case when (select t from tot) > 0 then round(100 * g.rev / (select t from tot), 2) else 0 end
  from g left join public.item_categories c on c.parent_id is null and c.code = g.cat
         left join public.item_categories s on s.parent_id = c.id and s.code = g.sb
  order by g.rev desc nulls last, g.cat nulls last, g.sb nulls last;
end $f$;

create or replace function public.stock_valuation_by_category(p_loc integer default null, p_level text default 'category')
returns table (category text, sub_category text, cat_name_bn text, cat_name_en text, sub_name_bn text, sub_name_en text, items bigint, value numeric)
language plpgsql stable security definer set search_path = public as $f$
#variable_conflict use_column
begin   -- bos100
  if p_level not in ('category', 'sub') then raise exception 'bad_level'; end if;
  return query
  with v as (select * from public.stock_valuation(p_loc)),   -- stock_valuation checks the cost right per place
  j as (select nullif(btrim(i.category), '') cat, case when p_level = 'sub' then nullif(btrim(i.sub_category), '') end sb, v.item_id iid, v.value val from v join public.items i on i.id = v.item_id),
  g as (select j.cat, j.sb, count(distinct j.iid) n, sum(j.val) val from j group by 1, 2)
  select g.cat, g.sb, c.name_bn, c.name_en, s.name_bn, s.name_en, g.n, g.val
  from g left join public.item_categories c on c.parent_id is null and c.code = g.cat
         left join public.item_categories s on s.parent_id = c.id and s.code = g.sb
  order by g.val desc nulls last, g.cat nulls last, g.sb nulls last;
end $f$;

-- ---------- 7. privileges: the browser calls only the public RPCs ----------
do $p$
declare r record;
begin
  for r in select p.oid::regprocedure f, p.proname n from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('category_list', 'category_save', 'category_reorder', 'category_rename', 'category_merge', 'category_move', 'item_set_category', 'item_set_category_bulk',
                             'category_sync100', 'category_rule_state', 'items_missing_category', 'biz_items_by_category', 'stock_valuation_by_category',
                             '_cat_mgr100', '_cat_newcode100', '_cat_ol_put100', '_cat_seed100', '_items_cat100', '_items_cat_req100', '_ol_cat100', '_item_categories_before100')
  loop
    execute format('revoke all on function %s from public, anon', r.f);
    if left(r.n, 1) = '_' then execute format('revoke all on function %s from authenticated', r.f); else execute format('grant execute on function %s to authenticated', r.f); end if;
  end loop;
  revoke all on sequence public.item_cat_seq100 from public, anon, authenticated;
end $p$;
