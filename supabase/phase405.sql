-- Phase 405 (bos405) - RPT-B4 / R3b: PRODUCTION CAPTURE, ENTRY FUNCTIONS.
-- Paste after phase404. Paste-twice safe. No earlier phase file is edited; production_post is NOT touched (another package sends the actual yield from the production screen).
--
-- ENTRY FUNCTIONS (all need the owner or the grant stock_production at the place; every refusal is a server refusal, not only a hidden button)
--   prod_plan_add / prod_plan_cancel           a plan line for a day, place and item (batches and/or quantity)
--   prod_order_add / prod_order_close / prod_order_cancel   an order for a product (producing place, optional requesting outlet, quantity, due day)
--   prod_run_link                               tell which plan / order a finished run belongs to
--   prod_actual_issue_set                       the REAL quantity used per ingredient for a run (partial calls allowed; an older line becomes history)
--   prod_loss_add / prod_loss_void              reject / rework quantity with a reason, or "checked, none"
--   prod_run_detail / prod_runs_recent          read side of the entry screen (blind: the booked recipe quantity of a line is shown only after the real quantity was saved, BUILD-RULES 9)
-- Nothing here posts stock or money. The real use is a record; the stock was booked by the production screen from the recipe (see the note in docs/integration/RPT-B4.md).

do $g$ begin
  if to_regclass('public.production_loss') is null then raise exception 'phase405 needs phase404 first'; end if;
end $g$;

-- ---------- plan ----------
create or replace function public.prod_plan_add(p_date date, p_loc int, p_item uuid, p_batches numeric default null, p_qty numeric default null, p_unit text default null,
                                                p_recipe uuid default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare prev public.production_plans; it public.items; r public.recipes; sid text; id_ uuid; bq numeric; pq numeric; pb numeric := p_batches; n text := nullif(btrim(p_note), ''); yb numeric;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into prev from public.production_plans where client_id = p_client;
    if found then
      if prev.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', prev.id);
    end if;
  end if;
  if p_loc is null or not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if not public._rb4_prod_entry(p_loc) then raise exception 'not allowed'; end if;
  if p_date is null or abs(p_date - public._rb4_today()) > 400 then raise exception 'bad_date'; end if;
  select * into it from public.items where id = p_item;
  if not found or not it.is_active then raise exception 'item_not_found'; end if;
  if pb is null and p_qty is null then raise exception 'plan_needs_batches_or_qty'; end if;
  if pb is not null and not (pb > 0 and pb <= 100000) then raise exception 'bad_qty'; end if;
  if n is not null and length(n) > 300 then raise exception 'bad_note'; end if;
  if p_recipe is not null then
    select * into r from public.recipes where id = p_recipe;
    if not found or r.item_id <> p_item then raise exception 'recipe_not_found'; end if;
  elsif pb is not null then
    select * into r from public.recipes where item_id = p_item and active order by version desc limit 1;      -- the newest active recipe of the item; none = the quantity stays blank
  end if;
  if p_qty is not null then
    bq := public._base_qty(p_item, p_qty, p_unit);
    if bq is null then raise exception 'unit_unknown'; end if;
    if not (bq between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
    pq := bq;
  elsif r.id is not null then
    yb := public._base_qty(r.item_id, r.yield_qty, r.yield_unit);
    if yb is not null and yb > 0 then pq := round(yb * pb, 4); end if;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.production_plans (client_id, plan_date, location_id, item_id, recipe_id, planned_batches, planned_qty, note, created_by, created_staff)
    values (p_client, p_date, p_loc, p_item, r.id, pb, pq, n, auth.uid(), sid) returning id into id_;
  return jsonb_build_object('id', id_, 'planned_batches', pb, 'planned_qty', pq, 'recipe_id', r.id);
end $$;

create or replace function public.prod_plan_cancel(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.production_plans;
begin
  select * into r from public.production_plans where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public._rb4_prod_entry(r.location_id) then raise exception 'not allowed'; end if;
  if r.status = 'cancelled' then return jsonb_build_object('dup', true, 'status', 'cancelled'); end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.production_plans set status = 'cancelled', cancel_note = left(btrim(p_note), 300), cancelled_by = auth.uid(), cancelled_at = now() where id = p_id;
  return jsonb_build_object('status', 'cancelled');
end $$;

-- ---------- order ----------
create or replace function public.prod_order_add(p_date date, p_due date, p_loc int, p_for_loc int, p_item uuid, p_qty numeric, p_unit text default null,
                                                 p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare prev public.production_orders; it public.items; sid text; id_ bigint; bq numeric; n text := nullif(btrim(p_note), '');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into prev from public.production_orders where client_id = p_client;
    if found then
      if prev.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', prev.id);
    end if;
  end if;
  if p_loc is null or not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if p_for_loc is not null and (p_for_loc = p_loc or not exists (select 1 from public.locations where id = p_for_loc)) then raise exception 'bad_location'; end if;
  -- the producing place's production staff, or the requesting outlet's transfer staff, or the owner
  if not (public._rb4_prod_entry(p_loc) or (p_for_loc is not null and public.can_loc(p_for_loc) and public.has_grant('stock_transfer', p_for_loc))) then raise exception 'not allowed'; end if;
  if p_date is null or abs(p_date - public._rb4_today()) > 400 then raise exception 'bad_date'; end if;
  if p_due is not null and p_due < p_date then raise exception 'bad_date'; end if;
  select * into it from public.items where id = p_item;
  if not found or not it.is_active then raise exception 'item_not_found'; end if;
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not (bq between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if n is not null and length(n) > 300 then raise exception 'bad_note'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.production_orders (client_id, order_date, due_date, location_id, for_location_id, item_id, qty, note, created_by, created_staff)
    values (p_client, p_date, p_due, p_loc, p_for_loc, p_item, bq, n, auth.uid(), sid) returning id into id_;
  return jsonb_build_object('id', id_, 'qty', bq);
end $$;

-- the quantity made so far on an order = the finished runs linked to it (void runs do not count)
create or replace function public._rb4_order_made(p_order bigint) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(r.yield_base), 0) from public.production_run_links k join public.production_runs r on r.id = k.run_id where k.order_id = p_order and r.status = 'done';
$$;

create or replace function public.prod_order_close(p_id bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.production_orders; made numeric;
begin
  select * into o from public.production_orders where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not (public._rb4_prod_entry(o.location_id) or (o.for_location_id is not null and public.can_loc(o.for_location_id) and public.has_grant('stock_transfer', o.for_location_id))) then raise exception 'not allowed'; end if;
  if o.status = 'closed' then return jsonb_build_object('dup', true, 'status', 'closed'); end if;
  if o.status <> 'open' then raise exception 'order_not_open'; end if;
  made := public._rb4_order_made(p_id);
  if made < o.qty and length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;      -- closing short of the ordered quantity needs a reason
  update public.production_orders set status = 'closed', close_note = left(btrim(p_note), 300), closed_by = auth.uid(), closed_at = now() where id = p_id;
  return jsonb_build_object('status', 'closed', 'made', made, 'ordered', o.qty);
end $$;

create or replace function public.prod_order_cancel(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.production_orders;
begin
  select * into o from public.production_orders where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not (public._rb4_prod_entry(o.location_id) or (o.for_location_id is not null and public.can_loc(o.for_location_id) and public.has_grant('stock_transfer', o.for_location_id))) then raise exception 'not allowed'; end if;
  if o.status = 'cancelled' then return jsonb_build_object('dup', true, 'status', 'cancelled'); end if;
  if o.status <> 'open' then raise exception 'order_not_open'; end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.production_orders set status = 'cancelled', close_note = left(btrim(p_note), 300), closed_by = auth.uid(), closed_at = now() where id = p_id;
  return jsonb_build_object('status', 'cancelled');
end $$;

-- ---------- link a finished run to a plan / an order ----------
create or replace function public.prod_run_link(p_run uuid, p_plan uuid default null, p_order bigint default null, p_clear_plan boolean default false, p_clear_order boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.production_runs; pl public.production_plans; o public.production_orders; k public.production_run_links; np uuid; no_ bigint;
begin
  select * into r from public.production_runs where id = p_run;
  if not found then raise exception 'not found'; end if;
  if not public._rb4_prod_entry(r.location_id) then raise exception 'not allowed'; end if;
  if r.status <> 'done' then raise exception 'run_void'; end if;
  select * into k from public.production_run_links where run_id = p_run;
  np := case when p_clear_plan then null when p_plan is not null then p_plan else k.plan_id end;
  no_ := case when p_clear_order then null when p_order is not null then p_order else k.order_id end;
  if np is not null then
    select * into pl from public.production_plans where id = np;
    if not found or pl.item_id <> r.item_id or pl.location_id <> r.location_id then raise exception 'link_mismatch'; end if;
    if pl.status = 'cancelled' then raise exception 'plan_cancelled'; end if;
  end if;
  if no_ is not null then
    select * into o from public.production_orders where id = no_;
    if not found or o.item_id <> r.item_id or o.location_id <> r.location_id then raise exception 'link_mismatch'; end if;
    if o.status <> 'open' and no_ is distinct from k.order_id then raise exception 'order_not_open'; end if;      -- an already linked closed order keeps its link; a new link needs an open order
  end if;
  insert into public.production_run_links (run_id, plan_id, order_id, linked_by) values (p_run, np, no_, auth.uid())
    on conflict (run_id) do update set plan_id = excluded.plan_id, order_id = excluded.order_id, linked_by = excluded.linked_by, linked_at = now();
  return jsonb_build_object('run_id', p_run, 'plan_id', np, 'order_id', no_);
end $$;

-- ---------- the real use of ingredients ----------
-- p_lines = [{"item_id": "...", "qty": 4.2, "unit": "kg"}]; only the lines sent are set. A second call for the same ingredient keeps the first line as history.
create or replace function public.prod_actual_issue_set(p_run uuid, p_lines jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.production_runs; ln jsonb; it public.items; bq numeric; sid text; n text := nullif(btrim(p_note), ''); done_ int := 0; ids uuid[] := '{}'; seen uuid[] := '{}';
begin
  select * into r from public.production_runs where id = p_run;
  if not found then raise exception 'not found'; end if;
  if not public._rb4_prod_entry(r.location_id) then raise exception 'not allowed'; end if;
  if r.status <> 'done' then raise exception 'run_void'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  if jsonb_array_length(p_lines) > 100 then raise exception 'too_many_lines'; end if;
  if n is not null and length(n) > 300 then raise exception 'bad_note'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  -- checks first, nothing is written until every line is fine
  for ln in select * from jsonb_array_elements(p_lines) loop
    if coalesce(ln ->> 'item_id', '') !~ '^[0-9a-f-]{36}$' then raise exception 'item_not_found'; end if;
    select * into it from public.items where id = (ln ->> 'item_id')::uuid;
    if not found or not it.is_active then raise exception 'item_not_found'; end if;
    if (ln ->> 'item_id')::uuid = any (seen) then raise exception 'duplicate_item'; end if;
    seen := seen || (ln ->> 'item_id')::uuid;
    if coalesce(ln ->> 'qty', '') !~ '^[0-9]+(\.[0-9]+)?$' then raise exception 'bad_qty'; end if;
    bq := public._base_qty(it.id, (ln ->> 'qty')::numeric, nullif(ln ->> 'unit', ''));
    if bq is null then raise exception 'unit_unknown'; end if;
    if not (bq between 0 and 999999999) then raise exception 'bad_qty'; end if;
  end loop;
  for ln in select * from jsonb_array_elements(p_lines) loop
    bq := round(public._base_qty((ln ->> 'item_id')::uuid, (ln ->> 'qty')::numeric, nullif(ln ->> 'unit', '')), 4);
    update public.production_issue_actual set status = 'replaced', replaced_by = auth.uid(), replaced_at = now() where run_id = p_run and item_id = (ln ->> 'item_id')::uuid and status = 'active';
    insert into public.production_issue_actual (run_id, item_id, actual_qty, note, entered_by, entered_staff) values (p_run, (ln ->> 'item_id')::uuid, bq, n, auth.uid(), sid);
    done_ := done_ + 1;
  end loop;
  return jsonb_build_object('run_id', p_run, 'lines', done_);
end $$;

-- ---------- reject / rework ----------
create or replace function public.prod_loss_add(p_run uuid, p_kind text, p_qty numeric default null, p_unit text default null, p_reason text default null,
                                                p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare prev public.production_loss; r public.production_runs; bq numeric; sid text; id_ uuid; n text := nullif(btrim(p_note), ''); used numeric;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into prev from public.production_loss where client_id = p_client;
    if found then
      if prev.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', prev.id);
    end if;
  end if;
  select * into r from public.production_runs where id = p_run;
  if not found then raise exception 'not found'; end if;
  if not public._rb4_prod_entry(r.location_id) then raise exception 'not allowed'; end if;
  if r.status <> 'done' then raise exception 'run_void'; end if;
  if p_kind is null or p_kind not in ('reject', 'rework', 'none') then raise exception 'bad_kind'; end if;
  if n is not null and length(n) > 300 then raise exception 'bad_note'; end if;
  if p_kind = 'none' then
    if exists (select 1 from public.production_loss where run_id = p_run and status = 'active' and kind in ('reject', 'rework')) then raise exception 'loss_already_recorded'; end if;
    bq := 0;
  else
    if p_qty is null then raise exception 'bad_qty'; end if;
    bq := public._base_qty(r.item_id, p_qty, p_unit);
    if bq is null then raise exception 'unit_unknown'; end if;
    if not (bq between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
    if p_reason is null or not exists (select 1 from public.option_lists where list_code = 'wastage_reasons' and value_code = p_reason and active) then raise exception 'reason_required'; end if;
    select coalesce(sum(qty), 0) into used from public.production_loss where run_id = p_run and status = 'active' and kind in ('reject', 'rework');
    if used + bq > r.yield_base then raise exception 'exceeds_output'; end if;      -- reject + rework cannot be more than the run made
    -- a recorded loss replaces an earlier "checked, none" line of the run
    update public.production_loss set status = 'void', void_note = 'replaced by a loss entry', void_by = auth.uid(), void_at = now() where run_id = p_run and kind = 'none' and status = 'active';
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.production_loss (client_id, run_id, kind, qty, reason_code, note, created_by, created_staff)
    values (p_client, p_run, p_kind, bq, case when p_kind = 'none' then null else p_reason end, n, auth.uid(), sid) returning id into id_;
  return jsonb_build_object('id', id_, 'qty', bq);
end $$;

create or replace function public.prod_loss_void(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.production_loss; r public.production_runs;
begin
  select * into l from public.production_loss where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  select * into r from public.production_runs where id = l.run_id;
  if not public._rb4_prod_entry(r.location_id) then raise exception 'not allowed'; end if;
  if l.status = 'void' then return jsonb_build_object('dup', true, 'status', 'void'); end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.production_loss set status = 'void', void_note = left(btrim(p_note), 300), void_by = auth.uid(), void_at = now() where id = p_id;
  return jsonb_build_object('status', 'void');
end $$;

-- ---------- read side of the entry screen ----------
-- what the production screen booked out for a run (the recipe need at the average cost of the day)
create or replace function public._rb4_run_booked(p_run uuid) returns table (item_id uuid, qty numeric, unit_cost numeric)
language sql stable security definer set search_path = public as $$
  select l.item_id, sum(-l.qty_delta), case when sum(-l.qty_delta) > 0 then sum(-l.qty_delta * coalesce(l.unit_cost, 0)) / sum(-l.qty_delta) end
    from public.stock_ledger l where l.ref_type = 'production' and l.ref_id = p_run::text and l.reason = 'issue_out' group by l.item_id;
$$;

create or replace function public.prod_run_detail(p_run uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r public.production_runs; out_ jsonb;
begin
  select * into r from public.production_runs where id = p_run;
  if not found then raise exception 'not found'; end if;
  if not public._rb4_prod_view(r.location_id) then raise exception 'not allowed'; end if;
  select jsonb_build_object('run_id', r.id, 'made_at', r.made_at, 'day', public._rb4_day(r.made_at), 'status', r.status, 'location_id', r.location_id,
      'location', l.name_bn, 'location_en', l.name_en, 'item_id', r.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(r.item_id),
      'batches', r.batches, 'output', r.yield_base, 'yield_std', r.yield_std, 'yield_actual', r.yield_actual,
      'can_edit', public._rb4_prod_entry(r.location_id) and r.status = 'done',
      'link', (select jsonb_build_object('plan_id', k.plan_id, 'order_id', k.order_id) from public.production_run_links k where k.run_id = r.id),
      -- ingredients: the booked recipe quantity is shown ONLY for a line whose real quantity is already saved
      'issue_lines', coalesce((select jsonb_agg(jsonb_build_object('item_id', u.item_id, 'code', ii.code, 'name_bn', ii.name_bn, 'name_en', ii.name_en, 'base_unit', public._item_base(u.item_id),
            'actual_qty', a.actual_qty, 'actual_at', a.entered_at, 'booked_qty', case when a.id is not null then u.qty end, 'diff', case when a.id is not null then round(a.actual_qty - u.qty, 4) end) order by ii.code)
          from public._rb4_run_booked(r.id) u join public.items ii on ii.id = u.item_id
          left join public.production_issue_actual a on a.run_id = r.id and a.item_id = u.item_id and a.status = 'active'), '[]'::jsonb),
      'extra_lines', coalesce((select jsonb_agg(jsonb_build_object('item_id', a.item_id, 'code', ii.code, 'name_bn', ii.name_bn, 'name_en', ii.name_en, 'base_unit', public._item_base(a.item_id), 'actual_qty', a.actual_qty) order by ii.code)
          from public.production_issue_actual a join public.items ii on ii.id = a.item_id
         where a.run_id = r.id and a.status = 'active' and not exists (select 1 from public._rb4_run_booked(r.id) u where u.item_id = a.item_id)), '[]'::jsonb),
      'losses', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'kind', x.kind, 'qty', x.qty, 'reason_code', x.reason_code, 'reason', o.label_en, 'reason_bn', o.label_bn, 'note', x.note, 'created_staff', x.created_staff, 'created_at', x.created_at) order by x.created_at)
          from public.production_loss x left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = x.reason_code where x.run_id = r.id and x.status = 'active'), '[]'::jsonb),
      'candidate_plans', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'plan_date', p.plan_date, 'planned_qty', p.planned_qty, 'planned_batches', p.planned_batches) order by p.plan_date desc)
          from public.production_plans p where p.location_id = r.location_id and p.item_id = r.item_id and p.status = 'planned' and p.plan_date between public._rb4_day(r.made_at) - 14 and public._rb4_day(r.made_at) + 14), '[]'::jsonb),
      'open_orders', coalesce((select jsonb_agg(jsonb_build_object('id', o2.id, 'order_date', o2.order_date, 'due_date', o2.due_date, 'qty', o2.qty, 'made', public._rb4_order_made(o2.id)) order by o2.due_date nulls last, o2.id)
          from public.production_orders o2 where o2.location_id = r.location_id and o2.item_id = r.item_id and o2.status = 'open'), '[]'::jsonb))
    into out_ from public.locations l, public.items i where l.id = r.location_id and i.id = r.item_id;
  return out_;
end $$;

-- finished runs of a period with what is already captured for each (counts only; "none" for loss is its own state)
create or replace function public.prod_runs_recent(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  return jsonb_build_object('from', f, 'to', t, 'rows', coalesce((select jsonb_agg(jsonb_build_object('run_id', r.id, 'made_at', r.made_at, 'day', public._rb4_day(r.made_at), 'location_id', r.location_id, 'location', l.name_bn, 'location_en', l.name_en,
        'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(r.item_id), 'batches', r.batches, 'output', r.yield_base, 'yield_actual', r.yield_actual,
        'actual_issue_lines', (select count(*) from public.production_issue_actual a where a.run_id = r.id and a.status = 'active'),
        'loss_state', (select case when bool_or(x.kind in ('reject', 'rework')) then 'recorded' when bool_or(x.kind = 'none') then 'none' end from public.production_loss x where x.run_id = r.id and x.status = 'active'),
        'linked', exists (select 1 from public.production_run_links k where k.run_id = r.id and (k.plan_id is not null or k.order_id is not null)),
        'can_edit', public._rb4_prod_entry(r.location_id)) order by r.made_at desc)
      from (select * from public.production_runs x where x.status = 'done' and public._rb4_day(x.made_at) between f and t and (p_loc is null or x.location_id = p_loc) and public._rb4_prod_view(x.location_id) order by x.made_at desc limit 500) r
      join public.items i on i.id = r.item_id join public.locations l on l.id = r.location_id), '[]'::jsonb));
end $$;

-- ---------- privileges ----------
do $p$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_rb4_order_made', '_rb4_run_booked') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('prod_plan_add', 'prod_plan_cancel', 'prod_order_add', 'prod_order_close', 'prod_order_cancel', 'prod_run_link', 'prod_actual_issue_set', 'prod_loss_add', 'prod_loss_void', 'prod_run_detail', 'prod_runs_recent') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $p$;

notify pgrst, 'reload schema';
