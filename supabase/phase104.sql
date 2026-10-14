-- ============================================================
-- Phase 104 (bos104) - Owner dashboard (#/dashx): per-user dashboard layout (tile order, metric ids, chart types, sizes, period, location).
--   Needs phases 72..103 pasted first (guard below, incl. phase103's check row flw_grn_double103). Goes LAST.
--   Additive, paste-twice safe: one new table (dash_layouts, RLS: a user sees / writes ONLY their own row), two functions, one audit trigger.
--   No existing table, column, function or privilege is changed. The default layout lives in web/dashx.js (no server rule).
--   dash_layout_get()                    -> {layout, updated_at} of the caller (layout null when nothing saved yet)
--   dash_layout_save(p_layout, p_client) -> {ok, changed, updated_at}; saving the same layout again changes nothing and is not audited again (idempotent).
--   Tag: bos104.
-- ============================================================

do $g$ begin perform set_config('phase104.ok', 'off', false); end $g$;
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
    ('99', 'public._inb_pii_f99(text,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  -- 98: the merged _acct_docs (bos98), or phase103 pasted before (bos103), or the phase89 merge (bos89)
  if to_regprocedure('public._acct_docs(date)') is null
     or (position('bos98' in pg_get_functiondef(to_regprocedure('public._acct_docs(date)'))) = 0 and position('bos103' in pg_get_functiondef(to_regprocedure('public._acct_docs(date)'))) = 0
         and position('bos89' in pg_get_functiondef(to_regprocedure('public._acct_docs(date)'))) = 0) then miss := miss || ' 98'; end if;
  if to_regclass('public.item_categories') is null then miss := miss || ' 100'; end if;
  if to_regclass('public.setup_rec_defs81') is null or not exists (select 1 from public.setup_rec_defs81 where code = 'purchase_grn_guard' and phase = '82') then miss := miss || ' 101'; end if;
  if to_regclass('public.setup_check_defs81') is null or not exists (select 1 from public.setup_check_defs81 where code = 'flw_grn_double103') then miss := miss || ' 103'; end if;
  if miss <> '' then
    raise exception 'phase104 needs phases 72..103 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
  perform set_config('phase104.ok', 'guard1', false);
end $g$;

do $p$ begin if current_setting('phase104.ok', true) = 'guard1' then
  create table if not exists public.dash_layouts (
    user_id uuid primary key references auth.users (id) on delete cascade,
    layout jsonb not null,
    client text,
    updated_at timestamptz not null default now(),
    constraint dash_layouts_obj_chk check (jsonb_typeof(layout) = 'object' and octet_length(layout::text) <= 65536)
  );
  alter table public.dash_layouts enable row level security;
  drop policy if exists dash_layouts_sel on public.dash_layouts;
  create policy dash_layouts_sel on public.dash_layouts for select to authenticated using (user_id = auth.uid());
  drop policy if exists dash_layouts_ins on public.dash_layouts;
  create policy dash_layouts_ins on public.dash_layouts for insert to authenticated with check (user_id = auth.uid());
  drop policy if exists dash_layouts_upd on public.dash_layouts;
  create policy dash_layouts_upd on public.dash_layouts for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
  revoke all on public.dash_layouts from public, anon, authenticated;
  grant select, insert, update on public.dash_layouts to authenticated;
  drop trigger if exists audit_dash_layouts on public.dash_layouts;
  create trigger audit_dash_layouts after insert or update on public.dash_layouts for each row execute function public.log_change('user_id');
end if; end $p$;

do $p$ begin if current_setting('phase104.ok', true) = 'guard1' then
  execute $f$
  create or replace function public.dash_layout_get() returns jsonb
  language plpgsql stable security definer set search_path = public as $b$
  declare r public.dash_layouts;
  begin   -- bos104
    if auth.uid() is null or not public.is_active() then raise exception 'not allowed'; end if;
    select * into r from public.dash_layouts where user_id = auth.uid();
    if not found then return jsonb_build_object('layout', null, 'updated_at', null); end if;
    return jsonb_build_object('layout', r.layout, 'updated_at', r.updated_at);
  end $b$ $f$;
  execute $f$
  create or replace function public.dash_layout_save(p_layout jsonb, p_client text default null) returns jsonb
  language plpgsql security definer set search_path = public as $b$
  declare r public.dash_layouts; t timestamptz;
  begin   -- bos104
    if auth.uid() is null or not public.is_active() then raise exception 'not allowed'; end if;
    if p_layout is null or jsonb_typeof(p_layout) <> 'object' then raise exception 'bad_layout'; end if;
    if octet_length(p_layout::text) > 65536 then raise exception 'layout_too_big'; end if;
    if p_layout ? 'tiles' and (jsonb_typeof(p_layout -> 'tiles') <> 'array' or jsonb_array_length(p_layout -> 'tiles') > 40) then raise exception 'bad_tiles'; end if;
    select * into r from public.dash_layouts where user_id = auth.uid() for update;
    if found then
      if r.layout = p_layout then return jsonb_build_object('ok', true, 'changed', false, 'updated_at', r.updated_at); end if;   -- the same layout again: nothing written, nothing audited
      update public.dash_layouts set layout = p_layout, client = left(p_client, 80), updated_at = now() where user_id = auth.uid() returning updated_at into t;
    else
      insert into public.dash_layouts (user_id, layout, client) values (auth.uid(), p_layout, left(p_client, 80)) on conflict (user_id) do update set layout = excluded.layout, client = excluded.client, updated_at = now() returning updated_at into t;
    end if;
    return jsonb_build_object('ok', true, 'changed', true, 'updated_at', t);
  end $b$ $f$;
  revoke all on function public.dash_layout_get() from public, anon;
  revoke all on function public.dash_layout_save(jsonb, text) from public, anon;
  grant execute on function public.dash_layout_get() to authenticated;
  grant execute on function public.dash_layout_save(jsonb, text) to authenticated;
end if; end $p$;
