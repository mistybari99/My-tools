-- ============================================================
-- Phase 92 (bos92) - STEP Inv: show the invoice on screen right after a sale; Print / Email / SMS / WhatsApp / Share are device-side.
--   Needs phases 72..88 pasted first (guard below). Additive, paste-twice safe: one rule, one append-only table, two functions. No existing table or function is changed.
--
--   * Rule  pos_show_invoice_after_sale  (module pos, kind choice)
--       never   DEFAULT. Exactly today's behaviour: toast + the small "Print receipt" bar.  (Recommended for a shop with a phone-only owner: always.)
--       ask     After a sale a bar offers "Show invoice"; the cashier taps it when wanted.
--       always  The invoice opens on screen straight after every sale (a queued offline sale shows with a provisional number, marked pending sync).
--   * Table invoice_shares  - one row each time a cashier prints / emails / SMSes / WhatsApps / shares / copies / downloads an invoice.
--       APPEND-ONLY (update / delete / truncate are refused by triggers). No customer number or e-mail is stored, no cost data. Closed to the browser:
--       rows are written by invoice_share_log92 and read (owner / POS approve only) inside invoice_data92.
--   * invoice_data92(p_sale, p_client)  - one sale ready to show: header, lines, totals, VAT, payments, customer, staff.
--       SAFE FOR NON-COST USERS BY CONSTRUCTION: every line key is copied by name (item_id, code, name, name_en, name_mix, unit, qty, price, amount); nothing is `select *`d
--       from stock, item_costs or the ledger. Customer name is returned; the customer MOBILE only to the owner, POS approve, a view_customer_mobile holder, or the
--       cashier who made that very sale (customer_masked = true otherwise). E-mail is not held on file at all.
--   * invoice_share_log92(p_sale, p_channel, p_client) - the audited log call (channel print|email|sms|whatsapp, plus share|copy|download).
--   Sending itself happens from the user's own phone (mailto: / sms: / wa.me deep links). No provider, no secret, no server-side sending is built here.
-- ============================================================

do $g$ begin
  if to_regprocedure('public._rcs88()') is null                                   -- 88 (and with it 72..87)
     or to_regprocedure('public.rpt_mobile_ok()') is null                         -- 9
     or to_regprocedure('public.can_loc(integer)') is null
     or to_regprocedure('public.can_do(text, text)') is null
     or to_regclass('public.sales') is null or to_regclass('public.sale_payments') is null or to_regclass('public.rules') is null then
    raise exception 'phase92 needs phases 72..88 pasted first';
  end if;
end $g$;

-- ---------- the switch ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('pos_show_invoice_after_sale', 'pos', 'choice', '"never"', null, '["never","ask","always"]'::jsonb, null, null,
  'বিক্রির পর ইনভয়েস পর্দায় দেখানো: কখনো না / জিজ্ঞেস / সবসময়', 'Sale এর পর invoice screen এ দেখানো: never / ask / always', 'Show the invoice on screen after a sale: never, ask or always',
  'কখনো না = আগের মতো (শুধু ছোট "রসিদ প্রিন্ট" বার)। জিজ্ঞেস = বিক্রির পর "ইনভয়েস দেখুন" বার আসে। সবসময় = প্রতি বিক্রির পরই ইনভয়েস পর্দায় খোলে, সেখান থেকে Print, Email, SMS, WhatsApp। সুপারিশ: সবসময়।',
  'never = আগের মতো (শুধু ছোট "Receipt Print" bar)। ask = sale এর পর "Invoice দেখুন" bar আসে। always = প্রতি sale এর পরই invoice screen এ খোলে, সেখান থেকে Print, Email, SMS, WhatsApp। Recommended: always।',
  'never = as before (only the small "Print receipt" bar). ask = a "Show invoice" bar appears after a sale. always = the invoice opens on screen after every sale, with Print, Email, SMS and WhatsApp buttons. Recommended: always, so the customer can see and receive the invoice even when no printer is connected. Email, SMS and WhatsApp open the phone''s own app; nothing is sent from our server.', 92)
on conflict (key) do nothing;

-- ---------- the audited share log (append-only) ----------
create table if not exists public.invoice_shares (
  id bigint generated always as identity primary key,
  sale_id uuid not null references public.sales(id),
  channel text not null check (channel in ('print', 'email', 'sms', 'whatsapp', 'share', 'copy', 'download')),
  by_user uuid not null default auth.uid(),
  by_staff text,
  at timestamptz not null default now(),
  location_id int
);
create index if not exists invoice_shares_sale on public.invoice_shares (sale_id, at);
alter table public.invoice_shares enable row level security;
revoke all on table public.invoice_shares from public, anon, authenticated;     -- no policy, no grant: the browser never touches the table

create or replace function public._invoice_shares_ro92() returns trigger language plpgsql as $$
begin raise exception 'invoice_shares is append-only'; end $$;
revoke all on function public._invoice_shares_ro92() from public, anon, authenticated;
drop trigger if exists invoice_shares_no_change92 on public.invoice_shares;
create trigger invoice_shares_no_change92 before update or delete on public.invoice_shares for each row execute function public._invoice_shares_ro92();
drop trigger if exists invoice_shares_no_trunc92 on public.invoice_shares;
create trigger invoice_shares_no_trunc92 before truncate on public.invoice_shares for each statement execute function public._invoice_shares_ro92();
drop trigger if exists audit_invoice_shares on public.invoice_shares;
create trigger audit_invoice_shares after insert on public.invoice_shares for each row execute function public.log_change('id');

-- ---------- one sale, ready to show (no cost column anywhere) ----------
create or replace function public.invoice_data92(p_sale uuid default null, p_client uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  s public.sales; loc public.locations; cu public.customers; lines_j jsonb; pays_j jsonb; shares_j jsonb := '[]';
  mob_ok boolean; sub numeric; share numeric := 1; tx numeric; rate numeric; inc boolean; vat_j jsonb := null; can_log boolean;
begin
  if not public.is_active() or not (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then raise exception 'not allowed'; end if;
  if p_sale is not null then select * into s from public.sales where id = p_sale;
  elsif p_client is not null then select * into s from public.sales where client_id = p_client and created_by = auth.uid();
  else raise exception 'no_sale'; end if;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(s.location_id) then raise exception 'not allowed for this location'; end if;
  select * into loc from public.locations where id = s.location_id;
  -- lines: whitelist of keys, in sale order; names in all three languages from the item master
  select coalesce(jsonb_agg(jsonb_build_object(
      'item_id', e.v ->> 'item_id', 'code', coalesce(i.code, e.v ->> 'code'), 'name', e.v ->> 'name', 'name_en', i.name_en, 'name_mix', i.name_mix,
      'unit', e.v ->> 'unit', 'qty', coalesce((e.v ->> 'qty')::numeric, 1), 'price', coalesce((e.v ->> 'price')::numeric, (e.v ->> 'amount')::numeric),
      'amount', coalesce((e.v ->> 'amount')::numeric, 0), 'custom', coalesce((e.v ->> 'custom')::boolean, false)) order by e.n), '[]')
    into lines_j
    from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) with ordinality e(v, n)
    left join public.items i on i.id = nullif(e.v ->> 'item_id', '')::uuid;
  select coalesce(jsonb_agg(jsonb_build_object('mode', p.mode, 'wallet', p.wallet, 'amount', p.amount) order by p.id), '[]') into pays_j
    from public.sale_payments p where p.sale_id = s.id and not p.voided and p.kind = 'sale';
  if s.customer_id is not null then select * into cu from public.customers where id = s.customer_id; end if;
  mob_ok := public.is_owner() or public.rpt_mobile_ok() or s.created_by = auth.uid();
  -- VAT: the same base as vat_report (VAT-applicable lines, after the bill discount share); shown only when the VAT switch is on and a rate is entered
  rate := public.rule_num('vat_rate'); inc := public.rule_on('vat_prices_include');
  if public.rule_on('vat_on') and rate is not null then
    sub := coalesce(s.subtotal, 0); if sub > 0 then share := (sub - coalesce(s.discount, 0)) / sub; end if;
    select coalesce(sum(coalesce((e.v ->> 'amount')::numeric, 0)) filter (where i.vat_applicable is true), 0) * share into tx
      from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e(v)
      left join public.items i on i.id = nullif(e.v ->> 'item_id', '')::uuid;
    vat_j := jsonb_build_object('rate', rate, 'included', coalesce(inc, false), 'taxable', round(tx, 2),
                                'amount', round(case when coalesce(inc, false) then tx * rate / (100 + rate) else tx * rate / 100 end, 2));
  end if;
  if public.is_owner() or public.can_do('POS', 'approve') then
    select coalesce(jsonb_agg(jsonb_build_object('channel', x.channel, 'by', x.by_staff, 'at', x.at) order by x.at desc), '[]') into shares_j
      from (select channel, by_staff, at from public.invoice_shares where sale_id = s.id order by at desc limit 20) x;
  end if;
  return jsonb_build_object(
    'id', s.id, 'client_id', s.client_id, 'receipt', s.receipt, 'location_id', s.location_id, 'location_code', loc.code,
    'location', jsonb_build_object('bn', loc.name_bn, 'mix', loc.name_mix, 'en', loc.name_en),
    'sale_date', s.sale_date, 'sold_at', s.sold_at, 'status', s.status, 'sale_type', s.sale_type, 'cashier', s.created_staff,
    'lines', lines_j, 'subtotal', s.subtotal, 'discount', s.discount, 'total', s.total, 'paid', s.paid, 'due', s.due_amount,
    'payments', pays_j, 'vat', vat_j,
    'customer', case when s.customer_id is null then case when s.customer is null then null else jsonb_build_object('name', s.customer, 'mobile', null, 'masked', false) end
                     else jsonb_build_object('name', cu.name, 'mobile', case when mob_ok then cu.mobile end, 'whatsapp', case when mob_ok then cu.whatsapp end, 'masked', not mob_ok) end,
    'shares', shares_j);
end $$;

-- ---------- the audited log call ----------
create or replace function public.invoice_share_log92(p_sale uuid default null, p_channel text default null, p_client uuid default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare s public.sales; nid bigint;
begin
  if not public.is_active() or not (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then raise exception 'not allowed'; end if;
  if p_channel is null or p_channel not in ('print', 'email', 'sms', 'whatsapp', 'share', 'copy', 'download') then raise exception 'bad_channel'; end if;
  if p_sale is not null then select * into s from public.sales where id = p_sale;
  elsif p_client is not null then select * into s from public.sales where client_id = p_client and created_by = auth.uid();
  else raise exception 'no_sale'; end if;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(s.location_id) then raise exception 'not allowed for this location'; end if;
  insert into public.invoice_shares (sale_id, channel, by_user, by_staff, location_id)
    values (s.id, p_channel, auth.uid(), (select coalesce(nullif(full_name, ''), staff_id) from public.profiles where id = auth.uid()), s.location_id) returning id into nid;
  return nid;
end $$;

revoke all on function public.invoice_data92(uuid, uuid), public.invoice_share_log92(uuid, text, uuid) from public, anon;
grant execute on function public.invoice_data92(uuid, uuid), public.invoice_share_log92(uuid, text, uuid) to authenticated;
