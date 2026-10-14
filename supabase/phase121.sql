-- ============================================================
-- Phase 121 (marker sec121) - SECURITY / ROBUSTNESS fixes found by the review of phases 112..118. Runs LAST (after phase118).
--   Needs phases 72..118 pasted first (guard below). Paste twice = no change. Behaviour-neutral at the defaults (every switch of 112..118 is OFF).
--   Fixes
--     1 customer_dues_net113()          revoke from public / anon, execute for authenticated only (it lists customers and their dues).
--     2 pool_set, _pool_gl_after_bill117  the GL sync (_pool_gl_sync117) is started only when pool_gl_post117 is ON AND the caller is the owner or an accountant
--                                       (is_owner() or _acct_manage()); for everybody else the existing catch-up posts it later.
--     3 cost_wait_supply96              with cost_supply_to_avg116 ON the average move (_cw_apply_avg116) needs is_owner() or _recipe_mgr() or _acct_manage();
--                                       otherwise the supplied cost is saved as before, the average is NOT moved and the answer carries needs_manager = true.
--     4 sale_return                     with return_uses_sale_rows ON the sold quantity of an item is the sum of _base_qty(item, qty, unit) over ALL its lines
--                                       (mixed units), the returned part is bq / sold_line_base, so a mixed-unit sale never restores more than it sold
--                                       (unknown unit on any line = the old factor path, as before).
--     5 bank_stmt_post113               the p_client duplicate lookup runs BEFORE line_already_matched / already_posted, so a retry returns dup:true.
--     6 stock_return_transfer           the original transfer row is locked (for update) before the returned-quantity check.
--     7 production_recost116            the rights are checked BEFORE the row lock of the run is taken.
--   Marker: sec121, deliberately NOT a bosNN tag (like perf110 / b2s115): the body guards of phases 98 / 103 / 109 / 114 / 116 / 117 refuse a body with a bosNN tag
--   they do not know, which would make the documented re-paste tail (89, 103 .. 111, 112 .. 118, 121) impossible. Re-paste rule: after any re-paste of 112..118 paste phase121 again.
--   Method: exact-text patch of the CURRENT body (helper _s121_patch dropped at the end; every older tag kept; a body that no longer holds the expected text stops the file).
-- ============================================================
begin;

do $g$
declare miss text := ''; f text;
begin
  foreach f in array array['public.customer_dues_net113()', 'public._pool_gl_sync117(integer,date)', 'public._pool_gl_after_bill117(bigint)', 'public._cw_apply_avg116(uuid,text,text)',
                           'public.bank_stmt_post113(bigint,text,integer,text,uuid,boolean)', 'public.stock_return_transfer(integer,integer,uuid,numeric,text,uuid,text,text,uuid)',
                           'public.production_recost116(uuid,boolean)', 'public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'public.cost_wait_supply96(text,text,text,jsonb,text,uuid,boolean)',
                           'public.pool_set(integer,date,text,numeric,text,boolean,text,uuid)', 'public.net_profit_report(date,date,integer,text)']
  loop
    if to_regprocedure(f) is null then miss := miss || ' ' || f; end if;
  end loop;
  if miss <> '' then raise exception 'phase121 needs phases 72..118 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

create or replace function public._s121_patch(p_sig text, p_old text[], p_new text[], p_marker text) returns void
language plpgsql set search_path = public as $$
declare d text; f regprocedure := to_regprocedure(p_sig); n int; i int;
begin
  if f is null then raise exception 'phase121: function % not found', p_sig; end if;
  d := pg_get_functiondef(f);
  if position(p_marker in d) > 0 then return; end if;                               -- already patched: paste twice = no change
  for i in 1 .. array_length(p_old, 1) loop
    n := (length(d) - length(replace(d, p_old[i], ''))) / length(p_old[i]);
    if n <> 1 then raise exception 'phase121: expected text #% found % times (need exactly 1) in %; the function changed - merge by hand', i, n, p_sig; end if;
    d := replace(d, p_old[i], p_new[i]);
  end loop;
  execute d;
end $$;

-- 1 ---------------------------------------------------------------------------------------------------------------
revoke all on function public.customer_dues_net113() from public, anon;
grant execute on function public.customer_dues_net113() to authenticated;

-- 2 ---------------------------------------------------------------------------------------------------------------
select public._s121_patch('public.pool_set(integer,date,text,numeric,text,boolean,text,uuid)',
  array[$a$if public.rule_on('pool_gl_post117') then      -- bos117:$a$],
  array[$a$if public.rule_on('pool_gl_post117') and (public.is_owner() or public._acct_manage()) then      -- sec121: owner / accountant only, others rely on the catch-up; bos117:$a$], 'sec121');
select public._s121_patch('public._pool_gl_after_bill117(bigint)',
  array[$a$if not public.rule_on('pool_gl_post117') then return; end if;$a$],
  array[$a$if not (public.rule_on('pool_gl_post117') and (public.is_owner() or public._acct_manage())) then return; end if;      -- sec121: owner / accountant only, others rely on the catch-up$a$], 'sec121');

-- 3 ---------------------------------------------------------------------------------------------------------------
select public._s121_patch('public.cost_wait_supply96(text,text,text,jsonb,text,uuid,boolean)',
  array[$a$declare pl jsonb;$a$,
        $a$if public.rule_on('cost_supply_to_avg116') then perform public._cw_apply_avg116(p_client, p_kind, p_ref); end if;$a$,
        $a$'errors', pr->'errors') end);$a$],
  array[$a$declare nm121 boolean := false; pl jsonb;$a$,
        $a$if public.rule_on('cost_supply_to_avg116') then      -- sec121: the average move needs a manager
    if public.is_owner() or public._recipe_mgr() or public._acct_manage() then perform public._cw_apply_avg116(p_client, p_kind, p_ref); else nm121 := true; end if;
  end if;$a$,
        $a$'errors', pr->'errors') end) || case when nm121 then jsonb_build_object('needs_manager', true) else '{}'::jsonb end;$a$], 'sec121');

-- 4 ---------------------------------------------------------------------------------------------------------------
select public._s121_patch('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)',
  array[$a$bq := coalesce((select z.sold_base * ln.q / z.sold_line from (select$a$,
        $a$(select sum(nullif(e->>'qty', '')::numeric) from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
              where e->>'item_id' = it.id::text and (e->>'unit') is not distinct from ln.u) sold_line) z$a$],
  array[$a$bq := coalesce((select z.sold_base * bq / z.sold_line from (select$a$,
        $a$(select case when count(*) filter (where q.b is null) > 0 then null else sum(q.b) end from (select public._base_qty(it.id, nullif(e->>'qty', '')::numeric, e->>'unit') b      -- sec121: all lines of the item, in base units
              from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e where e->>'item_id' = it.id::text) q) sold_line) z$a$], 'sec121');

-- 5 ---------------------------------------------------------------------------------------------------------------
select public._s121_patch('public.bank_stmt_post113(bigint,text,integer,text,uuid,boolean)',
  array[$a$  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.journal_entries where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id); end if;
  end if;
  memo :=$a$,
        $a$  if exists (select 1 from public.bank_recon_matches where line_id = p_line and active) then raise exception 'line_already_matched'; end if;$a$],
  array[$a$  memo :=$a$,
        $a$  if p_client is not null and not coalesce(p_dry, false) then      -- sec121: a retry with the same client id answers dup before line_already_matched / already_posted
    perform public._client_lock(p_client);
    select * into r from public.journal_entries where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id); end if;
  end if;
  if exists (select 1 from public.bank_recon_matches where line_id = p_line and active) then raise exception 'line_already_matched'; end if;$a$], 'sec121');

-- 6 ---------------------------------------------------------------------------------------------------------------
select public._s121_patch('public.stock_return_transfer(integer,integer,uuid,numeric,text,uuid,text,text,uuid)',
  array[$a$select * into o from public.stock_transfers where id = p_ref;$a$],
  array[$a$select * into o from public.stock_transfers where id = p_ref for update;      -- sec121: two returns of one transfer are serial$a$], 'sec121');

-- 7 ---------------------------------------------------------------------------------------------------------------
select public._s121_patch('public.production_recost116(uuid,boolean)',
  array[$a$  select * into run from public.production_runs where id = p_run for update;
  if not found then raise exception 'not_found'; end if;
  if not (public._recipe_mgr() and public._cost_ok(run.location_id) and public.can_loc(run.location_id)) then raise exception 'not allowed'; end if;$a$],
  array[$a$  select * into run from public.production_runs where id = p_run;      -- sec121: rights first, the row lock only for an allowed caller
  if not found then raise exception 'not_found'; end if;
  if not (public._recipe_mgr() and public._cost_ok(run.location_id) and public.can_loc(run.location_id)) then raise exception 'not allowed'; end if;
  select * into run from public.production_runs where id = p_run for update;$a$], 'sec121');

drop function public._s121_patch(text, text[], text[], text);
commit;
