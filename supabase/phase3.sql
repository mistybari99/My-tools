-- ============================================================
-- BOS tool · Phase 3 schema: POS sales, photos storage.
-- Run AFTER schema.sql and phase2.sql (SQL Editor -> paste -> Run). Run once.
-- ============================================================

-- ---------- the POS form entry in the form list + suggested default permissions ----------
insert into public.forms (code, area, name_bn, name_mix, name_en, version, sort) values
  ('POS','showroom','সেল (POS)','Sale (POS)','Sales (POS)','',0);
insert into public.role_form_perms (role_code, form_code, can_view, can_enter, can_approve) values
  ('management','POS',true,false,true),
  ('cash_controller','POS',true,false,false),
  ('showroom_manager','POS',true,true,true),
  ('salesperson','POS',true,true,false);

-- ---------- sales ----------
create table public.sales (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,                          -- set by the phone; makes a re-sent sale harmless
  location_id int not null references public.locations(id),
  receipt int not null,                           -- running receipt number per location
  sale_date date not null default (now() at time zone 'Asia/Dhaka')::date,
  sold_at timestamptz not null default now(),
  lines jsonb not null default '[]',              -- [{item_id,name,unit,qty,price,amount,override}] (price = snapshot)
  subtotal numeric not null,
  discount numeric not null default 0,
  total numeric not null,
  pay_mode text not null check (pay_mode in ('cash','mobile','card','due')),
  tendered numeric,                               -- cash given by the customer (for change)
  customer text,
  note text,
  quick boolean not null default false,
  status text not null default 'done' check (status in ('done','void')),
  created_by uuid not null, created_staff text,
  void_by uuid, void_staff text, void_at timestamptz, void_note text,
  unique (location_id, receipt)
);
create index sales_day on public.sales (location_id, sale_date, sold_at);

alter table public.exceptions alter column entry_id drop not null;
alter table public.exceptions add column sale_id uuid references public.sales(id);

create trigger audit_sales after insert or update on public.sales for each row execute function public.log_change('id');

-- ---------- record a sale (price check and totals are done here, not trusted from the phone) ----------
create or replace function public.record_sale(
  p_client uuid, p_loc int, p_lines jsonb, p_discount numeric, p_mode text,
  p_tendered numeric, p_customer text, p_note text, p_quick boolean, p_sold_at timestamptz default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  n int; sid text; s public.sales; ln jsonb; it public.items; qty numeric; pr numeric; amt numeric; shown numeric;
  out_lines jsonb := '[]'; sub numeric := 0; disc numeric := coalesce(p_discount, 0); ov boolean;
  any_ov boolean := false; any_drift boolean := false; at_ timestamptz := coalesce(p_sold_at, now());
begin
  if not public.can_do('POS', 'enter') then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_client is not null then
    select * into s from public.sales where client_id = p_client and created_by = auth.uid();
    if found then return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'dup', true); end if;
  end if;
  -- a sale made offline keeps its own time, but only within the last 3 days and never in the future
  if at_ > now() + interval '10 minutes' or at_ < now() - interval '3 days' then at_ := now(); end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  if p_mode is null or p_mode not in ('cash','mobile','card','due') then raise exception 'bad_mode'; end if;
  if p_tendered is not null and (p_tendered < 0 or p_tendered = 'NaN'::numeric) then raise exception 'bad_amount'; end if;
  if disc = 'NaN'::numeric then raise exception 'bad_discount'; end if;
  for ln in select * from jsonb_array_elements(p_lines) loop
    ov := false;
    if nullif(ln->>'item_id','') is not null then
      select * into it from public.items where id = (ln->>'item_id')::uuid;
      if not found or not it.is_active then raise exception 'item_not_found'; end if;
      qty := (ln->>'qty')::numeric;
      if qty is null or qty = 'NaN'::numeric or qty <= 0 then raise exception 'bad_qty'; end if;
      pr := it.sell_price;
      if (ln->>'override')::boolean is true then
        pr := (ln->>'price')::numeric;
        if pr is null or pr = 'NaN'::numeric or pr < 0 then raise exception 'bad_price'; end if;
        if pr is distinct from it.sell_price then ov := true; any_ov := true; end if;
      else
        -- the phone showed this price; if the list price moved meanwhile the list price wins and it is flagged
        shown := nullif(ln->>'price','')::numeric;
        if shown is not null and shown is distinct from it.sell_price then any_drift := true; end if;
      end if;
      if pr is null then raise exception 'no_price'; end if;
      amt := round(qty * pr, 2);
      out_lines := out_lines || jsonb_build_object('item_id', it.id, 'code', it.code, 'name', it.name_bn, 'unit', it.unit,
        'qty', qty, 'price', pr, 'amount', amt, 'override', ov);
    else
      amt := (ln->>'amount')::numeric;
      if amt is null or amt = 'NaN'::numeric or amt <= 0 then raise exception 'bad_amount'; end if;
      out_lines := out_lines || jsonb_build_object('item_id', null, 'name', left(coalesce(nullif(ln->>'name',''), 'Quick sale'), 80), 'qty', 1, 'price', amt, 'amount', amt, 'override', false);
    end if;
    sub := sub + amt;
  end loop;
  if disc < 0 or disc > sub then raise exception 'bad_discount'; end if;
  if p_mode = 'due' and (p_customer is null or length(btrim(p_customer)) = 0) then raise exception 'due_needs_customer'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.serials (form_code, location_id, last) values ('POS', p_loc, 1)
    on conflict (form_code, location_id) do update set last = public.serials.last + 1 returning last into n;
  begin
    insert into public.sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, tendered, customer, note, quick, created_by, created_staff)
      values (p_client, p_loc, n, at_, (at_ at time zone 'Asia/Dhaka')::date, out_lines, sub, disc, sub - disc, p_mode, p_tendered, left(nullif(btrim(p_customer), ''), 80), left(nullif(btrim(p_note), ''), 200), coalesce(p_quick, false), auth.uid(), sid)
      returning * into s;
  exception when unique_violation then
    select * into s from public.sales where client_id = p_client and created_by = auth.uid();
    if found then return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'dup', true); end if;
    raise;
  end;
  if any_ov or any_drift then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, s.id, 'POS', p_loc, s.sale_date, case when any_ov then 'price_override' else 'price_changed' end, 'yellow', s.total,
        case when any_ov then jsonb_build_object('bn', 'রসিদ ' || n || ': নির্ধারিত দামের বদলে অন্য দামে বিক্রি', 'en', 'Receipt ' || n || ': sold at a price different from the list price')
          else jsonb_build_object('bn', 'রসিদ ' || n || ': ফোনে দেখানো দাম আর তালিকার দাম আলাদা ছিল (তালিকার দাম ধরা হয়েছে)', 'en', 'Receipt ' || n || ': the price shown on the phone differed from the list price (list price used)') end);
  end if;
  return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total);
end $$;

-- ---------- void (a sale is never edited; a note is required) ----------
create or replace function public.void_sale(p_id uuid, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare s public.sales; sid text;
begin
  if not (public.is_owner() or public.can_do('POS', 'approve')) then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into s from public.sales where id = p_id for update;
  if not found then raise exception 'sale not found'; end if;
  if not public.can_loc(s.location_id) then raise exception 'not allowed for this location'; end if;
  if s.status = 'void' then raise exception 'already void'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.sales set status = 'void', void_by = auth.uid(), void_staff = sid, void_at = now(), void_note = btrim(p_note) where id = p_id;
  insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
    values (null, s.id, 'POS', s.location_id, s.sale_date, 'sale_void', 'yellow', s.total,
      jsonb_build_object('bn', 'রসিদ ' || s.receipt || ' বাতিল: ' || btrim(p_note), 'en', 'Receipt ' || s.receipt || ' voided: ' || btrim(p_note)));
end $$;

-- ---------- privileges and RLS ----------
alter table public.sales enable row level security;
grant select on public.sales to authenticated;
grant execute on function public.record_sale(uuid, int, jsonb, numeric, text, numeric, text, text, boolean, timestamptz),
  public.void_sale(uuid, text) to authenticated;
create policy sales_read on public.sales for select to authenticated
  using (public.can_do('POS', 'view') and public.can_loc(location_id));

-- ---------- location scope for exceptions (POS exceptions follow the sale's location) ----------
drop policy exceptions_read on public.exceptions;
create policy exceptions_read on public.exceptions for select to authenticated
  using (public.is_owner() or (public.can_do(form_code, 'approve') and public.can_loc(location_id)));
create or replace function public.resolve_exception(p_id bigint, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare x public.exceptions; sid text;
begin
  select * into x from public.exceptions where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not (public.is_owner() or (public.can_do(x.form_code, 'approve') and public.can_loc(x.location_id))) then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.exceptions set status = 'resolved', resolved_by = auth.uid(), resolved_staff = sid, resolved_at = now(), resolved_note = btrim(p_note) where id = p_id;
end $$;

-- POS sales live in `sales`; the generic entry table must never carry a POS "form"
create or replace function public.no_pos_entries() returns trigger language plpgsql as $$
begin
  if new.form_code = 'POS' then raise exception 'POS has its own sale screen'; end if;
  return new;
end $$;
create trigger entries_no_pos before insert on public.entries for each row execute function public.no_pos_entries();

-- ---------- day / location / payment summary (the dashboard asks this instead of downloading every sale) ----------
create or replace function public.sales_summary(p_from date) returns table (sale_date date, location_id int, pay_mode text, status text, n bigint, total numeric, discount numeric)
language sql stable set search_path = public as $$
  select s.sale_date, s.location_id, s.pay_mode, s.status, count(*), sum(s.total), sum(s.discount)
  from public.sales s where s.sale_date >= p_from group by 1, 2, 3, 4;
$$;
grant execute on function public.sales_summary(date) to authenticated;

-- ---------- photos (receipts, goods, repairs) — path is <form code>/<location id>/<file>.jpg ----------
create or replace function public.photo_ok(p_name text, p_action text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active()
    and split_part(p_name, '/', 2) ~ '^[0-9]+$'
    and public.can_do(split_part(p_name, '/', 1), p_action)
    and public.can_loc(split_part(p_name, '/', 2)::int);
$$;
grant execute on function public.photo_ok(text, text) to authenticated;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('photos', 'photos', false, 3145728, array['image/jpeg']) on conflict (id) do nothing;
create policy photos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and public.photo_ok(name, 'enter'));
create policy photos_read on storage.objects for select to authenticated
  using (bucket_id = 'photos' and public.photo_ok(name, 'view'));
