-- ============================================================
-- Phase 78 (bos78) - STEP C-2খ: where does showroom / admin cost belong (profit-and-cost attribution) + approval separation hint.
--   Needs phase8 ... phase71 + phase73 + phase74 + phase75 (phase72 is another branch and is NOT needed). Additive; paste-twice safe. Old phases are NOT edited.
--   1. location_cost_attribution : per place (and optionally per cost type) the owner chooses where the layer-3 cost SHARES of a cost bill (phase75 cost_bill_shares,
--                                  dest showroom / admin) are charged: showroom (that place's own P&L) | main_centre | unallocated. Effective-dated: a new choice applies from its month
--                                  (this month or later - an earlier month is never rewritten); the old row stays (active=false when replaced, previous values copied). Default = no row = unallocated.
--   2. cost_attrib_main          : which place is the 'main centre' (effective-dated, may be blank = the main centre stays a bucket that only the cost view shows).
--   3. cost_share_reassign       : APPEND-ONLY trail. A single share can be re-assigned to another showroom / the main centre / unallocated, MANDATORY reason, old + new destination,
--                                  never silent; a locked (closed) period is refused for non-owners, an owner override is flagged (row + yellow exception).
--   4. branch_cost_view(month, loc) : read-only list of every share and where it is charged (and why).
--   5. The numbers reach the branch P&L (l1_pnl, l3_shop_pnl) ONLY when rule cost_attrib_in_pl is ON (default OFF = today's output, byte for byte). ON adds SEPARATE ROWS
--      (row_type 'cost_share'); the existing rows and every other function that reads _p27_pl (owner sheet, break-even, partner profit) are untouched.
--   6. grant_separation_hint(user, grant): a NON-BLOCKING suggestion when the same person would hold both the entry and the approve right (recipes, cost bills / allocation rules).
--   Cost-right holders only (view); changing = owner or grant cost_attrib_manage. Every write has an audit row (client_id where it creates something). Nothing is seeded (blank start).
--   NOT built: switch cost_bill_creates_payment (a bill that also posts the payment / payable) - it touches cash, bank and the ledger; owner decision, see the report.
-- ============================================================

-- ---------- settings, grants ----------
insert into public.rules (key, module, kind, default_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('cost_attrib_in_pl', 'stock', 'switch', 'false',
  'খরচের বিলের শোরুম/অ্যাডমিন অংশ শাখার লাভ-ক্ষতিতে আলাদা সারিতে দেখান', 'Cost bill-এর showroom/admin অংশ branch P&L-এ আলাদা সারিতে দেখান', 'Show the showroom / admin cost-bill shares as separate rows in the branch P&L',
  'Off (default) = the branch P&L is exactly as today. On = the shares, as attributed in the cost-attribution screen, are added as separate rows (existing rows never change).', 745)
on conflict (key) do nothing;
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('cost_attrib_manage', 'cost', 82, 'খরচ কোন শাখার — ঠিক ও বদল', 'Cost কোন শাখার — set ও change', 'Set and change which showroom a cost belongs to', 'window', null)
on conflict (grant_code) do nothing;

-- ---------- helpers ----------
create or replace function public._c78_manage() returns boolean language sql stable security definer set search_path = public as $$
  select public._recipe_cost_ok() and (public.is_owner() or public.has_grant('cost_attrib_manage'));
$$;
create or replace function public._c78_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
-- is the date inside the closed period? (the same test lock_check uses, but it only answers)
create or replace function public._c78_locked(p_date date) returns boolean language plpgsql stable security definer set search_path = public as $$
declare v text; d date;
begin
  if p_date is null then return false; end if;
  v := public.rule_txt('period_closed_until');
  if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then return false; end if;
  begin d := v::date; exception when others then return false; end;
  return p_date <= d;
end $$;
create or replace function public._c78_nodml() returns trigger language plpgsql as $$ begin raise exception 'nothing is deleted or rewritten – the trail is append-only'; end $$;

-- ---------- tables ----------
create table if not exists public.location_cost_attribution (
  id bigserial primary key,
  location_id int not null references public.locations(id),          -- the place where the share ARISES (the share's own place)
  cost_type text references public.cost_source_types(code),          -- null = every cost type of that place; a typed row beats the general one
  dest text not null check (dest in ('showroom', 'main_centre', 'unallocated')),
  effective_from date not null check (effective_from = date_trunc('month', effective_from)::date),
  active boolean not null default true,
  reason text check (reason is null or length(reason) <= 300),
  prev_id bigint, prev_dest text, prev_effective_from date,           -- the setting this one replaced (previous values kept)
  replaced_by bigint, retired_at timestamptz, retired_by uuid, retired_reason text,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now()
);
create unique index if not exists lca_one_active on public.location_cost_attribution (location_id, coalesce(cost_type, ''), effective_from) where active;
create index if not exists lca_lookup on public.location_cost_attribution (location_id, effective_from) where active;

create table if not exists public.cost_attrib_main (
  id bigserial primary key,
  location_id int references public.locations(id),                   -- blank = no place stands for the main centre (its shares then show only in the cost view)
  effective_from date not null check (effective_from = date_trunc('month', effective_from)::date),
  active boolean not null default true,
  reason text check (reason is null or length(reason) <= 300),
  replaced_by bigint, retired_at timestamptz, retired_by uuid,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now()
);
create unique index if not exists cam_one_active on public.cost_attrib_main (effective_from) where active;

create table if not exists public.cost_share_reassign (
  id bigserial primary key,
  share_id bigint not null references public.cost_bill_shares(id),
  bill_id bigint not null references public.cost_source_bills(id),
  share_loc int not null references public.locations(id),
  cost_type text,
  period_month date not null,
  amount numeric not null,                                            -- snapshot of the share at that time
  from_kind text not null check (from_kind in ('location', 'main_centre', 'unallocated')),
  from_loc int references public.locations(id),
  to_kind text not null check (to_kind in ('location', 'main_centre', 'unallocated')),
  to_loc int references public.locations(id),
  reason text not null check (length(btrim(reason)) between 3 and 300),
  locked_override boolean not null default false,                     -- the period was closed and the owner (or a rule) allowed it: flagged
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  check ((to_kind = 'location') = (to_loc is not null))
);
create index if not exists csr78_share on public.cost_share_reassign (share_id, id desc);

create table if not exists public.grant_separation_pairs (
  code text primary key check (code ~ '^[a-z0-9_]{2,40}$'),
  entry_grant text not null references public.grant_defs(grant_code),
  approve_grant text not null references public.grant_defs(grant_code),
  label_bn text not null, label_en text not null
);
insert into public.grant_separation_pairs (code, entry_grant, approve_grant, label_bn, label_en) values
 ('recipe', 'recipe_manage', 'recipe_approve', 'রেসিপি লেখা ও অনুমোদন', 'Recipe entry and approval'),
 ('cost_rules', 'cost_bill_entry', 'cost_rule_approve', 'খরচের বিল / ভাগের নিয়ম লেখা ও অনুমোদন', 'Cost bill / allocation rule entry and approval')
on conflict (code) do nothing;

-- ---------- triggers (audit, nothing is deleted) / RLS ----------
create or replace function public._c78_lca_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'nothing is deleted – retire or replace instead'; end if;
  if new.location_id is distinct from old.location_id or new.cost_type is distinct from old.cost_type or new.dest is distinct from old.dest or new.effective_from is distinct from old.effective_from
     or new.reason is distinct from old.reason or new.prev_id is distinct from old.prev_id or new.prev_dest is distinct from old.prev_dest or new.client_id is distinct from old.client_id then
    raise exception 'a setting is never rewritten – add a new one from a later month';
  end if;
  return new;
end $$;
drop trigger if exists lca_guard on public.location_cost_attribution;
create trigger lca_guard before update or delete on public.location_cost_attribution for each row execute function public._c78_lca_guard();
create or replace function public._c78_cam_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'nothing is deleted – retire or replace instead'; end if;
  if new.location_id is distinct from old.location_id or new.effective_from is distinct from old.effective_from or new.reason is distinct from old.reason or new.client_id is distinct from old.client_id then
    raise exception 'a setting is never rewritten – add a new one from a later month';
  end if;
  return new;
end $$;
drop trigger if exists cam_guard on public.cost_attrib_main;
create trigger cam_guard before update or delete on public.cost_attrib_main for each row execute function public._c78_cam_guard();
drop trigger if exists csr78_nodml on public.cost_share_reassign;
create trigger csr78_nodml before update or delete on public.cost_share_reassign for each row execute function public._c78_nodml();
drop trigger if exists gsp_nd on public.grant_separation_pairs;
create trigger gsp_nd before delete on public.grant_separation_pairs for each row execute function public._cs_no_delete();
drop trigger if exists audit_lca on public.location_cost_attribution; create trigger audit_lca after insert or update on public.location_cost_attribution for each row execute function public.log_change('id');
drop trigger if exists audit_cam on public.cost_attrib_main; create trigger audit_cam after insert or update on public.cost_attrib_main for each row execute function public.log_change('id');
drop trigger if exists audit_csr78 on public.cost_share_reassign; create trigger audit_csr78 after insert on public.cost_share_reassign for each row execute function public.log_change('id');

alter table public.location_cost_attribution enable row level security;
alter table public.cost_attrib_main enable row level security;
alter table public.cost_share_reassign enable row level security;
alter table public.grant_separation_pairs enable row level security;
drop policy if exists lca_read on public.location_cost_attribution; create policy lca_read on public.location_cost_attribution for select to authenticated using (public._cs_view() and (public._all_locs() or public.can_loc(location_id)));
drop policy if exists cam_read on public.cost_attrib_main; create policy cam_read on public.cost_attrib_main for select to authenticated using (public._cs_view());
drop policy if exists csr78_read on public.cost_share_reassign; create policy csr78_read on public.cost_share_reassign for select to authenticated using (public._cs_view() and (public._all_locs() or public.can_loc(share_loc)));
drop policy if exists gsp_read on public.grant_separation_pairs; create policy gsp_read on public.grant_separation_pairs for select to authenticated using (public.is_active());
revoke all on public.location_cost_attribution, public.cost_attrib_main, public.cost_share_reassign, public.grant_separation_pairs from anon, authenticated;
grant select on public.location_cost_attribution, public.cost_attrib_main, public.cost_share_reassign, public.grant_separation_pairs to authenticated;
revoke all on sequence public.location_cost_attribution_id_seq, public.cost_attrib_main_id_seq, public.cost_share_reassign_id_seq from anon, authenticated;

-- ---------- where does a share go? ----------
-- the main-centre place in force for a month (null = none chosen)
create or replace function public._c78_main_loc(p_month date) returns int language sql stable security definer set search_path = public as $$
  select location_id from public.cost_attrib_main where active and effective_from <= public._m1(p_month) order by effective_from desc, id desc limit 1;
$$;
-- (kind, place, how): a re-assignment beats the place's setting; a typed cost type beats the general row; nothing set = unallocated (today)
create or replace function public._c78_dest(p_share bigint, p_month date) returns table (dkind text, dloc int, via text)
language plpgsql stable security definer set search_path = public as $$
declare r public.cost_share_reassign; sh public.cost_bill_shares; a public.location_cost_attribution; ct text; m date := public._m1(p_month);
begin
  select * into r from public.cost_share_reassign where share_id = p_share order by id desc limit 1;
  if found then
    dkind := r.to_kind; dloc := case when r.to_kind = 'main_centre' then public._c78_main_loc(m) else r.to_loc end; via := 'reassigned'; return next; return;
  end if;
  select * into sh from public.cost_bill_shares where id = p_share;
  select s.cost_type into ct from public.cost_source_bills b join public.cost_sources s on s.id = b.source_id where b.id = sh.bill_id;
  select * into a from public.location_cost_attribution where active and location_id = sh.location_id and cost_type = ct and effective_from <= m order by effective_from desc, id desc limit 1;
  if not found then
    select * into a from public.location_cost_attribution where active and location_id = sh.location_id and cost_type is null and effective_from <= m order by effective_from desc, id desc limit 1;
  end if;
  if not found or a.dest = 'unallocated' then dkind := 'unallocated'; dloc := null; via := case when found then 'setting' else 'default' end;
  elsif a.dest = 'showroom' then dkind := 'location'; dloc := sh.location_id; via := 'setting';
  else dkind := 'main_centre'; dloc := public._c78_main_loc(m); via := 'setting';
  end if;
  return next;
end $$;

-- every layer-3 share (showroom / admin) with its attribution, month by month (a yearly fee is spread /12 like branch_overhead)
create or replace function public._c78_rows(p_from date, p_to date) returns table (mth date, share_id bigint, bill_id bigint, source_code text, cost_type text, type_bn text, type_en text,
  share_loc int, share_dest text, amount numeric, dkind text, dloc int, via text)
language sql stable security definer set search_path = public as $$
  select z.mth, z.share_id, z.bill_id, z.code, z.cost_type, z.tbn, z.ten, z.share_loc, z.share_dest, z.amt, d.dkind, d.dloc, d.via
    from (
      select (case when b.period_kind = 'month' then b.period_month else (b.period_month + make_interval(months => g))::date end) mth, sh.id share_id, b.id bill_id, s.code, s.cost_type,
             t.label_bn tbn, coalesce(t.label_en, t.label_bn) ten, sh.location_id share_loc, sh.dest share_dest, (case when b.period_kind = 'month' then sh.amount else sh.amount / 12 end) amt
        from public.cost_bill_shares sh join public.cost_source_bills b on b.id = sh.bill_id join public.cost_sources s on s.id = b.source_id join public.cost_source_types t on t.code = s.cost_type
        cross join lateral generate_series(0, case when b.period_kind = 'year' then 11 else 0 end) g
       where sh.active and sh.kind = 'share' and sh.dest in ('showroom', 'admin') and b.status = 'active') z
    cross join lateral public._c78_dest(z.share_id, z.mth) d
   where z.mth between public._m1(coalesce(p_from, date '2000-01-01')) and coalesce(p_to, date '2999-12-31');
$$;

-- ---------- the read-only report: each share and where it is charged ----------
create or replace function public.branch_cost_view(p_month date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := public._m1(coalesce(p_month, public._c78_today())); rows_ jsonb; tot jsonb; allv boolean;
begin
  if not public._cs_view() then raise exception 'not allowed'; end if;
  allv := public._all_locs();
  if p_loc is not null and not (allv or public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('share_id', r.share_id, 'bill_id', r.bill_id, 'source', r.source_code, 'cost_type', r.cost_type, 'type_bn', r.type_bn, 'type_en', r.type_en,
      'share_location', r.share_loc, 'share_dest', r.share_dest, 'amount', round(r.amount, 2), 'dest_kind', r.dkind, 'dest_location', r.dloc, 'via', r.via,
      'reassigned', r.via = 'reassigned', 'reason', (select x.reason from public.cost_share_reassign x where x.share_id = r.share_id order by x.id desc limit 1),
      'locked_override', coalesce((select x.locked_override from public.cost_share_reassign x where x.share_id = r.share_id order by x.id desc limit 1), false)) order by r.share_loc, r.cost_type, r.share_id), '[]'::jsonb)
    into rows_ from public._c78_rows(m, m) r
   where (allv or public.can_loc(r.share_loc) or (r.dloc is not null and public.can_loc(r.dloc)))
     and (p_loc is null or r.share_loc = p_loc or r.dloc = p_loc);
  select coalesce(jsonb_agg(jsonb_build_object('dest_kind', k, 'dest_location', l, 'amount', a) order by k, l), '[]'::jsonb) into tot
    from (select x->>'dest_kind' k, nullif(x->>'dest_location', '')::int l, round(sum((x->>'amount')::numeric), 2) a from jsonb_array_elements(rows_) x group by 1, 2) q;
  return jsonb_build_object('month', m, 'location_id', p_loc, 'in_pl', public.rule_on('cost_attrib_in_pl'), 'main_centre_location', public._c78_main_loc(m), 'rows', rows_, 'totals', tot,
    'note', 'showroom / admin shares only; factory shares are in the product cost. A share with no setting is unallocated (not charged anywhere).');
end $$;

-- ---------- the owner's choice per place (and cost type), effective from a month ----------
create or replace function public.cost_attrib_set(p_loc int, p_cost_type text, p_dest text, p_effective date, p_reason text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.location_cost_attribution; prev public.location_cost_attribution; same public.location_cost_attribution; m date; nid bigint; ct text := nullif(btrim(p_cost_type), ''); cur date := public._m1(public._c78_today()); rs text := nullif(btrim(p_reason), '');
begin
  if not public._c78_manage() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into a from public.location_cost_attribution where client_id = p_client; if found then return jsonb_build_object('dup', true, 'id', a.id); end if; end if;
  if p_dest is null or p_dest not in ('showroom', 'main_centre', 'unallocated') then raise exception 'bad_value'; end if;
  if not exists (select 1 from public.locations where id = p_loc and is_active) then raise exception 'unknown_location'; end if;
  if not (public._all_locs() or public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  if ct is not null and not exists (select 1 from public.cost_source_types where code = ct) then raise exception 'unknown_type'; end if;
  if p_effective is null then raise exception 'bad_date'; end if;
  m := public._m1(p_effective);
  if m < cur then raise exception 'effective_in_past'; end if;        -- an earlier month is never rewritten
  if rs is not null and length(rs) > 300 then raise exception 'bad_value'; end if;
  perform public.lock_check(m);
  select * into prev from public.location_cost_attribution where active and location_id = p_loc and cost_type is not distinct from ct and effective_from <= m order by effective_from desc, id desc limit 1;
  if found and (rs is null or length(rs) < 3) then raise exception 'reason_required'; end if;
  select * into same from public.location_cost_attribution where active and location_id = p_loc and cost_type is not distinct from ct and effective_from = m;
  if found then update public.location_cost_attribution set active = false, retired_at = now(), retired_by = auth.uid(), retired_reason = 'replaced' where id = same.id; end if;
  insert into public.location_cost_attribution (location_id, cost_type, dest, effective_from, reason, prev_id, prev_dest, prev_effective_from, client_id, created_by)
    values (p_loc, ct, p_dest, m, rs, prev.id, prev.dest, prev.effective_from, p_client, auth.uid()) returning id into nid;
  if same.id is not null then update public.location_cost_attribution set replaced_by = nid where id = same.id; end if;
  return jsonb_build_object('id', nid, 'effective_from', m, 'previous', prev.dest);
end $$;

-- take a not-yet-past setting back (the earlier setting applies again). Only this month or later; the row stays, inactive.
create or replace function public.cost_attrib_retire(p_id bigint, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare a public.location_cost_attribution;
begin
  if not public._c78_manage() then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  select * into a from public.location_cost_attribution where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not (public._all_locs() or public.can_loc(a.location_id)) then raise exception 'not allowed'; end if;
  if not a.active then return; end if;
  if a.effective_from < public._m1(public._c78_today()) then raise exception 'effective_in_past'; end if;
  perform public.lock_check(a.effective_from);
  update public.location_cost_attribution set active = false, retired_at = now(), retired_by = auth.uid(), retired_reason = left(btrim(p_reason), 300) where id = p_id;
end $$;

-- which place stands for the 'main centre' (blank = none); effective from a month, never earlier than this month
create or replace function public.cost_attrib_main_set(p_loc int, p_effective date, p_reason text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.cost_attrib_main; same public.cost_attrib_main; m date; nid bigint; cur date := public._m1(public._c78_today());
begin
  if not public._c78_manage() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into a from public.cost_attrib_main where client_id = p_client; if found then return jsonb_build_object('dup', true, 'id', a.id); end if; end if;
  if p_loc is not null and not exists (select 1 from public.locations where id = p_loc and is_active) then raise exception 'unknown_location'; end if;
  if p_effective is null then raise exception 'bad_date'; end if;
  m := public._m1(p_effective);
  if m < cur then raise exception 'effective_in_past'; end if;
  perform public.lock_check(m);
  if exists (select 1 from public.cost_attrib_main where active and effective_from <= m) and (p_reason is null or length(btrim(p_reason)) < 3) then raise exception 'reason_required'; end if;
  select * into same from public.cost_attrib_main where active and effective_from = m;
  if found then update public.cost_attrib_main set active = false, retired_at = now(), retired_by = auth.uid() where id = same.id; end if;
  insert into public.cost_attrib_main (location_id, effective_from, reason, client_id, created_by) values (p_loc, m, left(btrim(p_reason), 300), p_client, auth.uid()) returning id into nid;
  if same.id is not null then update public.cost_attrib_main set replaced_by = nid where id = same.id; end if;
  return jsonb_build_object('id', nid, 'effective_from', m);
end $$;

-- ---------- re-assign ONE share (reason compulsory, trail append-only, locked period respected) ----------
create or replace function public.cost_share_reassign(p_share bigint, p_to_kind text, p_to_loc int, p_reason text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sh public.cost_bill_shares; b public.cost_source_bills; s public.cost_sources; o public.cost_share_reassign; cur record; nid bigint; lk boolean; rs text := nullif(btrim(p_reason), ''); tkind text := p_to_kind; tloc int := p_to_loc;
begin
  if not public._c78_manage() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into o from public.cost_share_reassign where client_id = p_client; if found then return jsonb_build_object('dup', true, 'id', o.id); end if; end if;
  if rs is null or length(rs) < 3 then raise exception 'reason_required'; end if;
  if length(rs) > 300 then raise exception 'bad_value'; end if;
  if tkind is null or tkind not in ('location', 'main_centre', 'unallocated') then raise exception 'bad_value'; end if;
  if tkind <> 'location' then tloc := null; end if;
  if tkind = 'location' and not exists (select 1 from public.locations where id = tloc and is_active) then raise exception 'unknown_location'; end if;
  select * into sh from public.cost_bill_shares where id = p_share;
  if not found then raise exception 'not_found'; end if;
  select * into b from public.cost_source_bills where id = sh.bill_id;
  select * into s from public.cost_sources where id = b.source_id;
  if not public._cs_src_ok(s.id) then raise exception 'not allowed'; end if;
  if not sh.active or sh.kind <> 'share' or b.status <> 'active' then raise exception 'share_not_active'; end if;
  if sh.dest not in ('showroom', 'admin') then raise exception 'factory_share_not_reassignable'; end if;     -- the factory share is product cost (layer 2)
  if exists (select 1 from public.cost_bill_shares where bill_id = b.id and active and kind = 'unallocated') then raise exception 'bill_not_fully_allocated'; end if;
  select * into cur from public._c78_dest(p_share, b.period_month);
  if cur.dkind = tkind and cur.dloc is not distinct from (case when tkind = 'main_centre' then public._c78_main_loc(b.period_month) else tloc end) then raise exception 'same_destination'; end if;
  lk := public._c78_locked(b.period_month);
  perform public.lock_check(b.period_month);           -- a non-owner is refused in a closed period (period_closed); the owner passes and is flagged below
  insert into public.cost_share_reassign (share_id, bill_id, share_loc, cost_type, period_month, amount, from_kind, from_loc, to_kind, to_loc, reason, locked_override, client_id, created_by)
    values (p_share, b.id, sh.location_id, s.cost_type, b.period_month, sh.amount, cur.dkind, cur.dloc, tkind, tloc, rs, lk, p_client, auth.uid()) returning id into nid;
  if lk then
    perform public._stock_exc(sh.location_id, 'cost_share_locked_reassign', 'yellow', 'বন্ধ হিসাব-মাসের খরচের ভাগ বদলানো হয়েছে (মালিক/অনুমতিপ্রাপ্ত)', 'A cost share of a closed period was re-assigned (owner / allowed)', null, b.period_month, 'STOCK', sh.amount);
  end if;
  return jsonb_build_object('id', nid, 'from_kind', cur.dkind, 'from_location', cur.dloc, 'to_kind', tkind, 'to_location', tloc, 'locked_override', lk);
end $$;

-- ---------- the branch P&L: shares reach it ONLY through rule cost_attrib_in_pl (default off) ----------
-- Both functions below are re-created from their LATEST definitions (phase27 _r3q_*; _p27_pl last changed in phase50). Only the lines tagged bos78 are new.
create or replace function public._r3q_l1_pnl(d1 date, d2 date, locs integer[], flt jsonb)
 returns setof jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object(
    'month', to_char(p.o_m, 'YYYY-MM'), 'location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'sales', round(p.o_gross, 2), 'returns', round(p.o_ret, 2), 'net_sales', round(p.o_net, 2),
    'cogs', round(p.o_cogs, 2),
    'uncosted_pct', case when p.o_net > 0 then round(100 * greatest(p.o_net - p.o_costed, 0) / p.o_net, 2) end,
    'expenses', round(p.o_exp, 2), 'salary', round(p.o_sal, 2), 'fixed', p.o_fixed,
    'profit', round(p.o_net - p.o_cogs - coalesce(p.o_exp, 0) - coalesce(p.o_sal, 0) - coalesce(p.o_fixed, 0), 2),
    'gaps', nullif(concat_ws(', ', case when p.o_exp is null then 'expenses' end, case when p.o_sal is null then 'salary' end, case when p.o_fixed is null then 'fixed' end, case when p.o_net > 0 and p.o_costed < p.o_net then 'cogs(uncosted)' end), ''))
  from public._p27_pl(d1, d2, locs) p join public.locations l on l.id = p.o_loc
  union all  -- bos78: attributed cost-bill shares as SEPARATE rows (only when the switch is on)
  select jsonb_build_object(
    'month', to_char(z.mth, 'YYYY-MM'), 'location_id', l.id,
    'location_bn', l.name_bn || ' · খরচ ভাগ: ' || z.type_bn || case when z.dkind = 'main_centre' then ' (মূল কেন্দ্র)' else '' end,
    'location_en', coalesce(l.name_en, l.name_bn) || ' · cost share: ' || z.type_en || case when z.dkind = 'main_centre' then ' (main centre)' else '' end,
    'expenses', z.amt, 'profit', -z.amt, 'row_type', 'cost_share', 'cost_type', z.cost_type, 'cost_share_dest', z.dkind)
  from (select r.mth, r.dloc, r.dkind, r.cost_type, min(r.type_bn) type_bn, min(r.type_en) type_en, round(sum(r.amount), 2) amt
          from public._c78_rows(d1, d2) r where r.dkind <> 'unallocated' and r.dloc = any (locs) group by 1, 2, 3, 4) z
  join public.locations l on l.id = z.dloc
  where public.rule_on('cost_attrib_in_pl');
$function$;

create or replace function public._r3q_l3_shop_pnl(d1 date, d2 date, locs integer[], flt jsonb)
 returns setof jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with a as (select o_loc, sum(o_net) net, sum(o_costed) costed, sum(o_cogs) cogs, sum(o_exp) ex, sum(o_sal) sal, sum(o_fixed) fx from public._p27_pl(d1, d2, locs) group by o_loc)
  select jsonb_build_object(
    'location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'net_sales', round(a.net, 2), 'cogs', round(a.cogs, 2),
    'uncosted_pct', case when a.net > 0 then round(100 * greatest(a.net - a.costed, 0) / a.net, 2) end,
    'expenses', round(a.ex, 2), 'salary', round(a.sal, 2), 'fixed', a.fx,
    'profit', round(a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0), 2),
    'profit_pct', case when a.net > 0 then round(100 * (a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0)) / a.net, 2) end,
    'gaps', nullif(concat_ws(', ', case when a.ex is null then 'expenses' end, case when a.sal is null then 'salary' end, case when a.fx is null then 'fixed' end, case when a.net > 0 and a.costed < a.net then 'cogs(uncosted)' end), ''))
  from a join public.locations l on l.id = a.o_loc
  union all  -- bos78: attributed cost-bill shares as SEPARATE rows (only when the switch is on)
  select jsonb_build_object(
    'location_id', l.id,
    'location_bn', l.name_bn || ' · খরচ ভাগ: ' || z.type_bn || case when z.dkind = 'main_centre' then ' (মূল কেন্দ্র)' else '' end,
    'location_en', coalesce(l.name_en, l.name_bn) || ' · cost share: ' || z.type_en || case when z.dkind = 'main_centre' then ' (main centre)' else '' end,
    'expenses', z.amt, 'profit', -z.amt, 'row_type', 'cost_share', 'cost_type', z.cost_type, 'cost_share_dest', z.dkind)
  from (select r.dloc, r.dkind, r.cost_type, min(r.type_bn) type_bn, min(r.type_en) type_en, round(sum(r.amount), 2) amt
          from public._c78_rows(d1, d2) r where r.dkind <> 'unallocated' and r.dloc = any (locs) group by 1, 2, 3) z
  join public.locations l on l.id = z.dloc
  where public.rule_on('cost_attrib_in_pl');
$function$;

-- ---------- approval separation hint (NON-BLOCKING) ----------
-- Does this person hold the right: his own grant (not expired) or through one of his roles. The owner holds everything.
create or replace function public._c78_holds(p_user uuid, p_grant text) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_roles where user_id = p_user and role_code = 'owner')
      or exists (select 1 from public.user_grants g where g.user_id = p_user and g.grant_code = p_grant and (g.valid_until is null or g.valid_until > now()))
      or exists (select 1 from public.user_roles ur join public.rule_grants rg on rg.role_code = ur.role_code and rg.allowed where ur.user_id = p_user and rg.grant_code = p_grant);
$$;
-- p_user: the person who is being given p_grant. suggest = true when he would then hold BOTH sides of an entry/approve pair. Never raises for the owner's choice, never blocks anything.
create or replace function public.grant_separation_hint(p_user uuid, p_grant text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pr record; other text; hit jsonb := '[]'::jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if exists (select 1 from public.user_roles where user_id = p_user and role_code = 'owner') then
    return jsonb_build_object('suggest', false, 'blocking', false, 'reason', 'owner', 'pairs', '[]'::jsonb);      -- the owner can always do everything
  end if;
  for pr in select * from public.grant_separation_pairs where p_grant in (entry_grant, approve_grant) order by code loop
    other := case when p_grant = pr.entry_grant then pr.approve_grant else pr.entry_grant end;
    if public._c78_holds(p_user, other) then
      hit := hit || jsonb_build_object('code', pr.code, 'entry_grant', pr.entry_grant, 'approve_grant', pr.approve_grant, 'label_bn', pr.label_bn, 'label_en', pr.label_en);
    end if;
  end loop;
  return jsonb_build_object('suggest', jsonb_array_length(hit) > 0, 'blocking', false, 'pairs', hit,
    'message_bn', case when jsonb_array_length(hit) > 0 then 'অন্য কাউকে অনুমোদনের দায়িত্ব দেওয়া ভালো — একই ব্যক্তি এন্ট্রি ও অনুমোদন দুটোই করলে ঝুঁকি' end,
    'message_en', case when jsonb_array_length(hit) > 0 then 'Better to give the approval to someone else - if the same person enters and approves, there is a risk' end);
end $$;
-- the same question for everybody at once: who holds both sides today (owner only; the owner himself is not listed)
create or replace function public.grant_separation_report() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('user_id', u.id, 'pair', pr.code, 'label_bn', pr.label_bn, 'label_en', pr.label_en) order by pr.code, u.id)
    from public.profiles u cross join public.grant_separation_pairs pr
   where u.status = 'active' and not exists (select 1 from public.user_roles where user_id = u.id and role_code = 'owner')
     and public._c78_holds(u.id, pr.entry_grant) and public._c78_holds(u.id, pr.approve_grant)), '[]'::jsonb);
end $$;

-- ---------- privileges ----------
revoke all on function public._c78_manage(), public._c78_today(), public._c78_locked(date), public._c78_nodml(), public._c78_lca_guard(), public._c78_cam_guard(), public._c78_main_loc(date), public._c78_dest(bigint, date),
  public._c78_rows(date, date), public._c78_holds(uuid, text) from public, anon, authenticated;
revoke all on function public.branch_cost_view(date, int), public.cost_attrib_set(int, text, text, date, text, uuid), public.cost_attrib_retire(bigint, text), public.cost_attrib_main_set(int, date, text, uuid),
  public.cost_share_reassign(bigint, text, int, text, uuid), public.grant_separation_hint(uuid, text), public.grant_separation_report() from public, anon;
grant execute on function public.branch_cost_view(date, int), public.cost_attrib_set(int, text, text, date, text, uuid), public.cost_attrib_retire(bigint, text), public.cost_attrib_main_set(int, date, text, uuid),
  public.cost_share_reassign(bigint, text, int, text, uuid), public.grant_separation_hint(uuid, text), public.grant_separation_report() to authenticated;
revoke all on function public._r3q_l1_pnl(date, date, integer[], jsonb), public._r3q_l3_shop_pnl(date, date, integer[], jsonb) from public, anon, authenticated;
