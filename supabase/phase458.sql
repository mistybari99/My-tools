-- Phase 458 (RPT-C3, package R7 part 1) - SHARED HELPERS, CAMPAIGN MASTER LIST, CAMPAIGN / OFFER CODE ON A SALE OR ORDER, AUDITED EXPORT.
-- Paste AFTER the build through phase 99 (any other phase may come before or after). Paste-twice safe. No earlier phase file is edited; no shared function is replaced.
--
-- What this adds (everything is additive and OPTIONAL: a sale with no campaign behaves exactly as today):
--   * list 'marketing_campaigns' (the campaign master list). It is an ordinary option list, so Add new / Other / add rule (open | approval | owner) / retire / history
--     all come from the existing list framework (phase15). Details (start, end, budget, channel, note) live in option_lists.extra. NOTHING is seeded: the owner enters campaigns.
--   * mkt_sale_tags / mkt_order_tags: the campaign and the offer / coupon code typed at the till (or on an online order), one row per sale / order.
--     The code is a LABEL on the sale. It does not give a discount and is not a second coupon system: validated coupons are the CRM-F tables (crmf_coupons / crmf_coupon_uses)
--     when they are installed - this package only READS them (see phase460) and, when a typed code matches a CRM-F coupon, stores that coupon's id next to the code.
--   * mkt_campaign_save, mkt_active_campaigns, mkt_tag_sale, mkt_tag_sale_client, mkt_tag_order
--   * rptc3_export_log: the audited-export check for every RPT-C3 report page (needs the owner or the export_data grant AND the report's own group).
--   * _c3_* helpers used by phases 459-468.
-- Reports stay OPEN: every report function of this package asks rpt_access(<group>) = owner, report_<group> grant or view_reports (phase 9). Cost columns also need rpt_cost_ok().
-- Test data only (test_*).

do $g$ begin
  if to_regprocedure('public.option_add(text,text,text,text,jsonb,boolean,uuid)') is null or to_regprocedure('public._r2_num(jsonb)') is null
     or to_regprocedure('public._p26_d(text)') is null or to_regprocedure('public.rpt_access(text)') is null or to_regclass('public.online_orders') is null then
    raise exception 'phase458 needs the build through phase 99 (phases 15, 21, 26, 40, 61 and 9)';
  end if;
end $g$;

create or replace function public._p458_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- shared helpers ----------
create or replace function public._c3_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function public._c3_locs(p_loc int) returns int[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(l.id order by l.id), '{}'::int[]) from public.locations l where public.can_loc(l.id) and (p_loc is null or l.id = p_loc)
$$;
create or replace function public._c3_need(p_group text) returns void language plpgsql stable security definer set search_path = public as $$
begin if not public.is_active() or not public.rpt_access(p_group) then raise exception 'not allowed'; end if; end $$;
create or replace function public._c3_range(p_from date, p_to date) returns void language plpgsql immutable as $$
begin if p_from is null or p_to is null or p_from > p_to or p_to - p_from > 1100 then raise exception 'bad_range'; end if; end $$;
create or replace function public._c3_staff(p_user uuid) returns text language sql stable security definer set search_path = public as $$
  select coalesce(nullif(p.staff_id, ''), nullif(p.full_name, '')) from public.profiles p where p.id = p_user
$$;
create or replace function public._c3_norm(t text) returns text language sql immutable as $$ select lower(regexp_replace(btrim(coalesce(t, '')), '\s+', ' ', 'g')) $$;
-- a number inside option_lists.extra (text or number); anything else is "not captured" (null), never 0
create or replace function public._c3_xnum(x jsonb, k text) returns numeric language sql immutable as $$
  select case when x ->> k ~ '^[0-9]{1,12}(\.[0-9]{1,4})?$' then (x ->> k)::numeric end
$$;
create or replace function public._c3_xdate(x jsonb, k text) returns date language plpgsql immutable as $$
begin
  if x ->> k ~ '^\d{4}-\d{2}-\d{2}$' then return (x ->> k)::date; end if;
  return null;
exception when others then return null;
end $$;
-- the CRM-F coupon tables are READ when they exist (no second coupon system)
create or replace function public._c3_crmf_present() returns boolean language sql stable as $$
  select to_regclass('public.crmf_coupons') is not null and to_regclass('public.crmf_coupon_uses') is not null
$$;

-- ---------- the campaign master list (an ordinary option list; nothing is seeded) ----------
insert into public.list_defs (list_code, add_rule, allow_other, title_bn, title_en, note)
  values ('marketing_campaigns', 'owner', true, 'মার্কেটিং ক্যাম্পেইন', 'Marketing campaigns',
          'The campaign master list: 18-1 lines, sales and online orders point to a campaign here. Start / end / budget / channel are kept with each campaign.')
  on conflict (list_code) do nothing;

-- owner / list manager: add or edit a campaign with its details (names via the list framework, details validated here)
create or replace function public.mkt_campaign_save(p_value text, p_patch jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ex jsonb := '{}'; v text; st date; en date; bud numeric; res jsonb; vc text := p_value; o public.option_lists; bn text; enm text;
begin
  if not public._list_mgr('marketing_campaigns') then raise exception 'not allowed'; end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'bad_value'; end if;
  if p_patch ? 'start' then
    if nullif(btrim(p_patch ->> 'start'), '') is not null then
      if (p_patch ->> 'start') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'bad_date'; end if;
      begin st := (p_patch ->> 'start')::date; exception when others then raise exception 'bad_date'; end;
      ex := ex || jsonb_build_object('start', st);
    end if;
  end if;
  if p_patch ? 'end' then
    if nullif(btrim(p_patch ->> 'end'), '') is not null then
      if (p_patch ->> 'end') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'bad_date'; end if;
      begin en := (p_patch ->> 'end')::date; exception when others then raise exception 'bad_date'; end;
      ex := ex || jsonb_build_object('end', en);
    end if;
  end if;
  if p_patch ? 'budget' and nullif(btrim(p_patch ->> 'budget'), '') is not null then
    if (p_patch ->> 'budget') !~ '^[0-9]{1,12}(\.[0-9]{1,2})?$' then raise exception 'bad_amount'; end if;
    bud := (p_patch ->> 'budget')::numeric; ex := ex || jsonb_build_object('budget', bud);
  end if;
  if p_patch ? 'channel' and nullif(btrim(p_patch ->> 'channel'), '') is not null then ex := ex || jsonb_build_object('channel', left(btrim(p_patch ->> 'channel'), 40)); end if;
  if p_patch ? 'note' and nullif(btrim(p_patch ->> 'note'), '') is not null then ex := ex || jsonb_build_object('note', left(btrim(p_patch ->> 'note'), 300)); end if;
  bn := nullif(btrim(p_patch ->> 'name_bn'), ''); enm := nullif(btrim(p_patch ->> 'name_en'), '');
  if vc is null then
    if bn is null then raise exception 'name_required'; end if;
    res := public.option_add('marketing_campaigns', bn, enm, null, ex, coalesce((p_patch ->> 'force')::boolean, false));
    if (res ->> 'status') <> 'added' then return res; end if;
    vc := res ->> 'value_code';
  else
    select * into o from public.option_lists where list_code = 'marketing_campaigns' and value_code = vc;
    if not found then raise exception 'bad_option'; end if;
    -- end before start is refused whichever of the two was sent
    st := coalesce(st, public._c3_xdate(o.extra, 'start')); en := coalesce(en, public._c3_xdate(o.extra, 'end'));
    if st is not null and en is not null and en < st then raise exception 'end_before_start'; end if;
    update public.option_lists set label_bn = coalesce(bn, label_bn), label_en = coalesce(enm, label_en),
        extra = jsonb_strip_nulls(coalesce(extra, '{}'::jsonb) || ex)
      where list_code = 'marketing_campaigns' and value_code = vc;
    res := jsonb_build_object('status', 'saved', 'value_code', vc);
  end if;
  if vc is not null and (select (public._c3_xdate(extra, 'start') is not null and public._c3_xdate(extra, 'end') is not null
                                 and public._c3_xdate(extra, 'end') < public._c3_xdate(extra, 'start')) from public.option_lists where list_code = 'marketing_campaigns' and value_code = vc) then
    raise exception 'end_before_start';
  end if;
  return res || jsonb_build_object('value_code', vc);
end $$;

-- campaigns a till may pick today (active, inside its dates when dates are given)
create or replace function public.mkt_active_campaigns() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare td date := public._c3_today();
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('code', o.value_code, 'name_bn', o.label_bn, 'name_en', o.label_en,
            'start', public._c3_xdate(o.extra, 'start'), 'end', public._c3_xdate(o.extra, 'end')) order by o.sort, o.value_code)
      from public.option_lists o
     where o.list_code = 'marketing_campaigns' and o.active
       and (public._c3_xdate(o.extra, 'start') is null or public._c3_xdate(o.extra, 'start') <= td)
       and (public._c3_xdate(o.extra, 'end') is null or public._c3_xdate(o.extra, 'end') >= td)), '[]'::jsonb);
end $$;

-- ---------- tags: campaign and offer / coupon code on a sale or an online order ----------
create table if not exists public.mkt_sale_tags (
  sale_id uuid primary key references public.sales(id),
  campaign_code text check (campaign_code is null or length(campaign_code) between 1 and 40),
  offer_code text check (offer_code is null or offer_code ~ '^[A-Z0-9][A-Z0-9_-]{1,29}$'),
  coupon_id uuid,                                   -- only when the CRM-F coupon table exists and knows the typed code (no foreign key on purpose)
  location_id int,
  tagged_by uuid, tagged_staff text, tagged_at timestamptz not null default now(),
  check (campaign_code is not null or offer_code is not null)
);
create table if not exists public.mkt_order_tags (
  order_id uuid primary key references public.online_orders(id),
  campaign_code text check (campaign_code is null or length(campaign_code) between 1 and 40),
  offer_code text check (offer_code is null or offer_code ~ '^[A-Z0-9][A-Z0-9_-]{1,29}$'),
  coupon_id uuid,
  location_id int,
  tagged_by uuid, tagged_staff text, tagged_at timestamptz not null default now(),
  check (campaign_code is not null or offer_code is not null)
);
create index if not exists mkt_sale_tags_campaign on public.mkt_sale_tags (campaign_code);
create index if not exists mkt_sale_tags_offer on public.mkt_sale_tags (offer_code) where offer_code is not null;
create index if not exists mkt_order_tags_campaign on public.mkt_order_tags (campaign_code);
drop trigger if exists audit_mkt_sale_tags on public.mkt_sale_tags;
create trigger audit_mkt_sale_tags after insert or update on public.mkt_sale_tags for each row execute function public.log_change('sale_id');
drop trigger if exists mkt_sale_tags_no_delete on public.mkt_sale_tags;
create trigger mkt_sale_tags_no_delete before delete on public.mkt_sale_tags for each row execute function public.no_hard_delete();
drop trigger if exists audit_mkt_order_tags on public.mkt_order_tags;
create trigger audit_mkt_order_tags after insert or update on public.mkt_order_tags for each row execute function public.log_change('order_id');
drop trigger if exists mkt_order_tags_no_delete on public.mkt_order_tags;
create trigger mkt_order_tags_no_delete before delete on public.mkt_order_tags for each row execute function public.no_hard_delete();
alter table public.mkt_sale_tags enable row level security;
alter table public.mkt_order_tags enable row level security;
revoke all on public.mkt_sale_tags, public.mkt_order_tags from public, anon, authenticated;
grant select on public.mkt_sale_tags, public.mkt_order_tags to authenticated;
drop policy if exists mkt_sale_tags_read on public.mkt_sale_tags;
create policy mkt_sale_tags_read on public.mkt_sale_tags for select to authenticated
  using (public.is_active() and public.can_loc(location_id) and (public.can_do('POS', 'view') or public.rpt_access('marketing')));
drop policy if exists mkt_order_tags_read on public.mkt_order_tags;
create policy mkt_order_tags_read on public.mkt_order_tags for select to authenticated
  using (public.is_active() and public.can_loc(location_id) and (public.can_do('POS', 'view') or public.rpt_access('marketing')));

-- the CRM-F coupon id for a typed code (null when CRM-F is not installed or the code is unknown)
create or replace function public._c3_coupon_id(p_code text) returns uuid language plpgsql stable security definer set search_path = public as $$
declare r uuid;
begin
  if p_code is null or not public._c3_crmf_present() then return null; end if;
  execute 'select id from public.crmf_coupons where code = $1' into r using p_code;
  return r;
end $$;

create or replace function public._c3_tag_clean(p_campaign text, p_offer text, out camp text, out offer text) language plpgsql stable security definer set search_path = public as $$
begin
  camp := nullif(btrim(coalesce(p_campaign, '')), '');
  offer := nullif(upper(btrim(coalesce(p_offer, ''))), '');
  if camp is not null and not exists (select 1 from public.option_lists o where o.list_code = 'marketing_campaigns' and o.value_code = camp and o.active) then raise exception 'unknown_campaign'; end if;
  if offer is not null and offer !~ '^[A-Z0-9][A-Z0-9_-]{1,29}$' then raise exception 'bad_offer_code'; end if;
  if camp is null and offer is null then raise exception 'nothing_to_tag'; end if;
end $$;

-- tag a finished sale. The first tag: anyone who may enter POS sales at that location. Changing an existing tag: the owner or a POS approver. Every change is in audit_log.
create or replace function public.mkt_tag_sale(p_sale uuid, p_campaign text, p_offer text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.sales; c record; t public.mkt_sale_tags; cid uuid; sid text; st date; en date; outside boolean := false;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into s from public.sales where id = p_sale;
  if not found then raise exception 'sale_not_found'; end if;
  if not (public.can_do('POS', 'enter') and public.can_loc(s.location_id)) then raise exception 'not allowed'; end if;
  if s.status <> 'done' then raise exception 'sale_not_done'; end if;
  select * into c from public._c3_tag_clean(p_campaign, p_offer);
  cid := public._c3_coupon_id(c.offer);
  select * into t from public.mkt_sale_tags where sale_id = p_sale;
  if found then
    if t.campaign_code is not distinct from c.camp and t.offer_code is not distinct from c.offer then return jsonb_build_object('ok', true, 'unchanged', true); end if;
    if not (public.is_owner() or public.can_do('POS', 'approve')) then raise exception 'tag_change_needs_approver'; end if;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.mkt_sale_tags (sale_id, campaign_code, offer_code, coupon_id, location_id, tagged_by, tagged_staff)
    values (p_sale, c.camp, c.offer, cid, s.location_id, auth.uid(), sid)
    on conflict (sale_id) do update set campaign_code = excluded.campaign_code, offer_code = excluded.offer_code, coupon_id = excluded.coupon_id,
      tagged_by = excluded.tagged_by, tagged_staff = excluded.tagged_staff, tagged_at = now();
  if c.camp is not null then
    select public._c3_xdate(o.extra, 'start'), public._c3_xdate(o.extra, 'end') into st, en from public.option_lists o where o.list_code = 'marketing_campaigns' and o.value_code = c.camp;
    outside := (st is not null and s.sale_date < st) or (en is not null and s.sale_date > en);
  end if;
  return jsonb_build_object('ok', true, 'campaign', c.camp, 'offer_code', c.offer, 'coupon_id', cid, 'crmf_installed', public._c3_crmf_present(),
    'coupon_known', cid is not null, 'outside_campaign_dates', outside);
end $$;

-- same, found by the till's own sale id (client id): used to tag a sale that was queued offline and has just been sent
create or replace function public.mkt_tag_sale_client(p_client uuid, p_campaign text, p_offer text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid uuid;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select id into sid from public.sales where client_id = p_client and created_by = auth.uid();
  if sid is null then raise exception 'sale_not_found'; end if;
  return public.mkt_tag_sale(sid, p_campaign, p_offer);
end $$;

create or replace function public.mkt_tag_order(p_order uuid, p_campaign text, p_offer text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; c record; t public.mkt_order_tags; cid uuid; sid text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into o from public.online_orders where id = p_order;
  if not found then raise exception 'order_not_found'; end if;
  if not (public.can_do('POS', 'enter') and public.can_loc(o.location_id)) then raise exception 'not allowed'; end if;
  select * into c from public._c3_tag_clean(p_campaign, p_offer);
  cid := public._c3_coupon_id(c.offer);
  select * into t from public.mkt_order_tags where order_id = p_order;
  if found then
    if t.campaign_code is not distinct from c.camp and t.offer_code is not distinct from c.offer then return jsonb_build_object('ok', true, 'unchanged', true); end if;
    if not (public.is_owner() or public.can_do('POS', 'approve')) then raise exception 'tag_change_needs_approver'; end if;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.mkt_order_tags (order_id, campaign_code, offer_code, coupon_id, location_id, tagged_by, tagged_staff)
    values (p_order, c.camp, c.offer, cid, o.location_id, auth.uid(), sid)
    on conflict (order_id) do update set campaign_code = excluded.campaign_code, offer_code = excluded.offer_code, coupon_id = excluded.coupon_id,
      tagged_by = excluded.tagged_by, tagged_staff = excluded.tagged_staff, tagged_at = now();
  return jsonb_build_object('ok', true, 'campaign', c.camp, 'offer_code', c.offer, 'coupon_id', cid, 'crmf_installed', public._c3_crmf_present(), 'coupon_known', cid is not null);
end $$;

-- ---------- the campaign each sale belongs to: its own tag first, else the tag of the online order it came from ----------
create or replace function public._c3_sale_campaign(d1 date, d2 date, locs int[]) returns table (sale_id uuid, campaign_code text, offer_code text, coupon_id uuid, via text)
language sql stable security definer set search_path = public as $$
  select s.id, coalesce(t.campaign_code, ot.campaign_code), coalesce(t.offer_code, ot.offer_code), coalesce(t.coupon_id, ot.coupon_id),
         case when t.sale_id is not null then 'sale' when ot.order_id is not null then 'order' end
    from public.sales s
    left join public.mkt_sale_tags t on t.sale_id = s.id
    left join public.online_orders oo on oo.sale_id = s.id
    left join public.mkt_order_tags ot on ot.order_id = oo.id
   where s.sale_date between d1 and d2 and s.location_id = any (locs) and (t.sale_id is not null or ot.order_id is not null)
$$;

-- ---------- audited export for every RPT-C3 report page ----------
create or replace function public._c3_export_group(p_key text) returns text language sql immutable as $$
  select case
    when p_key in ('mkt_spend', 'mkt_vs_sales', 'mkt_campaign_perf', 'mkt_discount', 'mkt_coupons', 'mkt_cac', 'mkt_repeat', 'mkt_roi', 'mkt_post') then 'marketing'
    when p_key in ('aud_voids', 'aud_approvals', 'aud_gaps', 'aud_stockadj', 'aud_overrides', 'aud_unusual', 'aud_users') then 'control'
    when p_key = 'aud_log' then '*owner'
    when p_key in ('fc_sales', 'fc_items', 'fc_festivals', 'fc_seasonal') then 'sales'
    when p_key in ('fc_production', 'fc_raw', 'fc_expiry') then 'stock'
    when p_key in ('fc_cash', 'fc_suppliers') then 'cash'
    when p_key = 'fc_scenario' then 'profit'
  end
$$;
create or replace function public.rptc3_export_log(p_key text, p_kind text, p_filters jsonb, p_rows int) returns void
language plpgsql security definer set search_path = public as $$
declare g text := public._c3_export_group(p_key); sid text; f jsonb := coalesce(p_filters, '{}'::jsonb);
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if g is null then raise exception 'unknown_report'; end if;
  if g = '*owner' then
    if not public.is_owner() then raise exception 'not allowed'; end if;
  elsif not public.rpt_access(g) then raise exception 'not allowed'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;

-- ---------- privileges ----------
revoke all on function public._c3_today(), public._c3_locs(int), public._c3_need(text), public._c3_range(date, date), public._c3_staff(uuid), public._c3_norm(text),
  public._c3_xnum(jsonb, text), public._c3_xdate(jsonb, text), public._c3_crmf_present(), public._c3_coupon_id(text), public._c3_tag_clean(text, text),
  public._c3_sale_campaign(date, date, int[]), public._c3_export_group(text), public._p458_present() from public, anon, authenticated;
revoke all on function public.mkt_campaign_save(text, jsonb), public.mkt_active_campaigns(), public.mkt_tag_sale(uuid, text, text), public.mkt_tag_sale_client(uuid, text, text),
  public.mkt_tag_order(uuid, text, text), public.rptc3_export_log(text, text, jsonb, int) from public, anon;
grant execute on function public.mkt_campaign_save(text, jsonb), public.mkt_active_campaigns(), public.mkt_tag_sale(uuid, text, text), public.mkt_tag_sale_client(uuid, text, text),
  public.mkt_tag_order(uuid, text, text), public.rptc3_export_log(text, text, jsonb, int) to authenticated;
notify pgrst, 'reload schema';
