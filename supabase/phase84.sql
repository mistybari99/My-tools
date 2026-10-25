-- ============================================================
-- Phase 84 (bos84) - STEP F: audit trail for the stock cache, batches, transfers, purchase lines, production void; reconcile fixes are logged.
--   Needs phase8 ... phase78 (phase72 is another branch and is NOT needed). Additive; paste-twice safe. No amount / threshold is hard-coded. Old phases are NOT edited.
--   1. stock_balance : (a) BEFORE DELETE refused (nothing is deleted) - only an EMPTY phantom row (qty 0, no cost, no ledger row at all) may go;
--                      (b) BEFORE UPDATE refuses a change of item_id / location_id (identity);
--                      (c) AFTER UPDATE audit_log row (who / when / old / new) for qty and avg_cost, EXCEPT the updates that come from a ledger insert
--                          (stock_post -> _ledger_to_balance, trigger depth > 1): those are fully derivable from the immutable ledger, so logging them would only
--                          slow every sale. Everything else (a SECURITY DEFINER function, the SQL editor, service_role) IS logged.
--   2. stock_batches : BEFORE DELETE refused; BEFORE UPDATE refuses a change of item_id / location_id / qty_made / made_at (identity, never edited by any code);
--                      AFTER UPDATE audit row for every other change (qty_remaining by stock_post, expires_at, note, batch_no ...).
--   3. stock_transfers : BEFORE DELETE refused (insert / update were already audited since phase10).
--   4. purchase_lines : BEFORE DELETE refused unless the bill is still a DRAFT (save_purchase replaces the lines of a draft); on a posted / void bill the
--                      identity + amounts (bill_id, line_no, item_id, qty, unit_cost, amount) cannot be changed. base_qty / unit_cost_base (set at posting) stay writable.
--   5. stock_wastage : already immutable since phase10 (stock_wastage_no_update refuses UPDATE and DELETE) - nothing to add, tested here.
--   6. production_runs : AFTER UPDATE audit, only when status / void_by / void_at / void_note change (the void). The normal post-time update of ledger_in_id etc. is not logged.
--   7. stock_reconcile(true) : writes ONE audit_log row per balance it corrects (action 'reconcile_fix', old + new qty / avg_cost, who). Only this function is re-created (-- bos84).
--   Not covered (cannot be tested here): service_role / direct-DB. Triggers do fire for them, but only a real Supabase project can prove it. See step_F_REPORT.md.
-- ============================================================

-- ---------- one audit function (same row shape as log_change; skip switches) ----------
-- tg_argv[0] = id columns (comma list); tg_argv[1] = '' | 'nested' (nested = skip when fired from inside another trigger, i.e. the ledger insert);
-- tg_argv[2] = optional comma list of columns to watch (default all). set_config('bos.audit_skip84','1',true) silences it (reconcile writes its own row).
create or replace function public._aud84() returns trigger language plpgsql security definer set search_path = public as $$
declare
  o jsonb; n jsonb; k text; oldd jsonb := '{}'; newd jsonb := '{}'; cols text[] := string_to_array(tg_argv[0], ','); c text; rid text := ''; sid text;
  watch text[] := case when coalesce(tg_argv[2], '') = '' then null else string_to_array(tg_argv[2], ',') end;
begin
  if coalesce(tg_argv[1], '') = 'nested' and pg_trigger_depth() > 1 then return new; end if;
  if coalesce(current_setting('bos.audit_skip84', true), '') = '1' then return new; end if;
  o := to_jsonb(old); n := to_jsonb(new);
  foreach c in array cols loop rid := rid || case when rid = '' then '' else ':' end || coalesce(n->>c, ''); end loop;
  for k in select jsonb_object_keys(n) loop
    if watch is not null and not (k = any (watch)) then continue; end if;
    if n->k is distinct from o->k then oldd := oldd || jsonb_build_object(k, o->k); newd := newd || jsonb_build_object(k, n->k); end if;
  end loop;
  if newd = '{}'::jsonb then return new; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'update', tg_table_name, rid,
            jsonb_build_object('old', oldd, 'new', newd, 'db_user', session_user, 'src', 'phase84'));
  return new;
end $$;
revoke all on function public._aud84() from public, anon, authenticated;

-- ---------- identity guards ----------
create or replace function public._sb_guard84() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    if old.qty = 0 and old.avg_cost is null and not exists (select 1 from public.stock_ledger l where l.item_id = old.item_id and l.location_id = old.location_id) then
      return old;                                                                  -- an empty phantom row (never had a movement) may go
    end if;
    raise exception 'nothing is deleted – retire instead' using hint = 'stock_balance is the cache of the ledger; fix it with stock_reconcile';
  end if;
  if new.item_id is distinct from old.item_id or new.location_id is distinct from old.location_id then
    raise exception 'identity_immutable' using hint = 'stock_balance item / place cannot be changed';
  end if;
  return new;
end $$;
revoke all on function public._sb_guard84() from public, anon, authenticated;

create or replace function public._batch_guard84() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'nothing is deleted – retire instead' using hint = 'a batch is closed by qty_remaining = 0'; end if;
  if new.item_id is distinct from old.item_id or new.location_id is distinct from old.location_id
     or new.qty_made is distinct from old.qty_made or new.made_at is distinct from old.made_at then
    raise exception 'identity_immutable' using hint = 'batch item / place / quantity made / date made cannot be changed';
  end if;
  return new;
end $$;
revoke all on function public._batch_guard84() from public, anon, authenticated;

create or replace function public._pl_guard84() returns trigger language plpgsql set search_path = public as $$
declare st text;
begin
  select status into st from public.purchase_bills where id = coalesce(old.bill_id, new.bill_id);
  if tg_op = 'DELETE' then
    if st = 'draft' then return old; end if;                                      -- save_purchase replaces the lines of a draft
    raise exception 'nothing is deleted – retire instead' using hint = 'lines of a posted / void bill stay; void the bill';
  end if;
  if st is distinct from 'draft' and (new.bill_id is distinct from old.bill_id or new.line_no is distinct from old.line_no or new.item_id is distinct from old.item_id
        or new.qty is distinct from old.qty or new.unit_cost is distinct from old.unit_cost or new.amount is distinct from old.amount) then
    raise exception 'identity_immutable' using hint = 'lines of a posted / void bill cannot be edited';
  end if;
  return new;
end $$;
revoke all on function public._pl_guard84() from public, anon, authenticated;

-- ---------- triggers ----------
drop trigger if exists stock_balance_guard84 on public.stock_balance;
create trigger stock_balance_guard84 before update or delete on public.stock_balance for each row execute function public._sb_guard84();
drop trigger if exists audit_stock_balance84 on public.stock_balance;
create trigger audit_stock_balance84 after update on public.stock_balance for each row
  when (old.qty is distinct from new.qty or old.avg_cost is distinct from new.avg_cost)
  execute function public._aud84('item_id,location_id', 'nested', 'qty,avg_cost');

drop trigger if exists stock_batches_guard84 on public.stock_batches;
create trigger stock_batches_guard84 before update or delete on public.stock_batches for each row execute function public._batch_guard84();
drop trigger if exists audit_stock_batches84 on public.stock_batches;
create trigger audit_stock_batches84 after update on public.stock_batches for each row execute function public._aud84('id', '', '');

drop trigger if exists stock_transfers_no_delete84 on public.stock_transfers;
create trigger stock_transfers_no_delete84 before delete on public.stock_transfers for each row execute function public.no_hard_delete();

drop trigger if exists purchase_lines_guard84 on public.purchase_lines;
create trigger purchase_lines_guard84 before update or delete on public.purchase_lines for each row execute function public._pl_guard84();

drop trigger if exists audit_production_runs_void84 on public.production_runs;
create trigger audit_production_runs_void84 after update on public.production_runs for each row
  when (old.status is distinct from new.status or old.void_by is distinct from new.void_by or old.void_at is distinct from new.void_at or old.void_note is distinct from new.void_note)
  execute function public._aud84('id', '', 'status,void_by,void_at,void_note');

-- ---------- stock_reconcile: latest definition (phase10) + audit row per fixed balance ----------
create or replace function public.stock_reconcile(p_fix boolean default false)
 returns table(item_id uuid, location_id integer, ledger_qty numeric, cached_qty numeric, qty_diff numeric, cached_avg numeric, replay_avg numeric)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_column
declare r record; l record; q numeric; a numeric; bq numeric; bavg numeric;
        sid text;                                                                                            -- bos84
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select p.staff_id into sid from public.profiles p where p.id = auth.uid();                                  -- bos84
  for r in
    select k.iid, k.lid from (select x.item_id iid, x.location_id lid from public.stock_ledger x group by 1, 2
                              union select y.item_id, y.location_id from public.stock_balance y) k order by 1, 2 loop
    if p_fix then
      insert into public.stock_balance (item_id, location_id) values (r.iid, r.lid) on conflict do nothing;
      perform 1 from public.stock_balance z where z.item_id = r.iid and z.location_id = r.lid for update;     -- nobody can post to this pair until we are done
    end if;
    select z.qty, z.avg_cost into bq, bavg from public.stock_balance z where z.item_id = r.iid and z.location_id = r.lid;
    bq := coalesce(bq, 0);
    q := 0; a := null;
    for l in select x.qty_delta, x.unit_cost, x.reason from public.stock_ledger x where x.item_id = r.iid and x.location_id = r.lid order by x.id loop
      a := public._avg_next(q, a, l.qty_delta, l.unit_cost, l.reason); q := q + l.qty_delta;
    end loop;
    if q <> bq or bavg is distinct from a then
      item_id := r.iid; location_id := r.lid; ledger_qty := q; cached_qty := bq; qty_diff := bq - q; cached_avg := bavg; replay_avg := a;
      if p_fix then
        perform set_config('bos.audit_skip84', '1', true);                                                    -- bos84 (this function writes its own, single row)
        update public.stock_balance z set qty = q, avg_cost = a, updated_at = now() where z.item_id = r.iid and z.location_id = r.lid;
        perform set_config('bos.audit_skip84', '', true);                                                     -- bos84
        insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)               -- bos84
          values (auth.uid(), sid, 'reconcile_fix', 'stock_balance', r.iid::text || ':' || r.lid::text,
                  jsonb_build_object('old', jsonb_build_object('qty', bq, 'avg_cost', bavg), 'new', jsonb_build_object('qty', q, 'avg_cost', a),
                                     'source', 'stock_reconcile', 'src', 'phase84'));                          -- bos84
      end if;
      return next;
    end if;
  end loop;
end $function$;
