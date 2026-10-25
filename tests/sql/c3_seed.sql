-- C3 shared seed (phase133_test, tests/sql/c3_probe.sql, tests/sql/c3_before_after.sh). Run after tests/sql/e2e/00_common.sql on a database built through phase123 (or later).
-- Creates TWO real-looking businesses with the same kinds of rows in each, so that "A cannot see B" can be proven for any function:
--   A = SWEETS (locations 1..7)        users  a_staff (salesperson at place 1), a_mgr (management scope), a_super (management scope + EVERY grant, no place)
--   B = HARDWARE (hw1 under a branch, hw2) users  b_staff, b_mgr, b_super (same shape)       plus the group owner o
-- c3.seed_data(loc, loc2, staff, tag, biz) puts into one business: stock, three sales (one with a due), a return, a collection, a purchase bill, a wastage, an entry, an exception,
-- notifications, an employee + payroll run, an emergency request, a channel + inbound message, an online order, an expense, a cash move, a fixed asset, a drawer event.
-- psql variables set here: ao am as (A staff/manager/super), bo bm bs (B), sbz hbz hb1 (units), hw1 hw2 (B places), orph.
\set ON_ERROR_STOP off
create schema if not exists c3;
grant usage on schema c3 to authenticated, anon;
\set ao '00000000-0000-0000-0000-0000000c3a01'
\set am '00000000-0000-0000-0000-0000000c3a02'
\set as '00000000-0000-0000-0000-0000000c3a03'
\set bo '00000000-0000-0000-0000-0000000c3b01'
\set bm '00000000-0000-0000-0000-0000000c3b02'
\set bs '00000000-0000-0000-0000-0000000c3b03'
\set xn '00000000-0000-0000-0000-0000000c3c01'
\set aop '00000000-0000-0000-0000-0000000c3a04'
\set bop '00000000-0000-0000-0000-0000000c3b04'
insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner@c3.app','{"full_name":"Owner"}'),(:'ao','a_staff@c3.app','{"full_name":"A Staff"}'),(:'am','a_mgr@c3.app','{"full_name":"A Manager"}'),(:'as','a_super@c3.app','{"full_name":"A Super"}'),
 (:'bo','b_staff@c3.app','{"full_name":"B Staff"}'),(:'bm','b_mgr@c3.app','{"full_name":"B Manager"}'),(:'bs','b_super@c3.app','{"full_name":"B Super"}'),(:'xn','x_none@c3.app','{"full_name":"Nowhere"}'),(:'aop','a_ops@c3.app','{"full_name":"A Ops bot"}'),(:'bop','b_ops@c3.app','{"full_name":"B Ops bot"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'ao','salesperson'),(:'am','management'),(:'as','management'),(:'bo','salesperson'),(:'bm','management'),(:'bs','management'),(:'xn','salesperson'),(:'aop','salesperson'),(:'bop','salesperson') on conflict do nothing;
-- the "super" users hold EVERY role except owner (so every role-based form right and role grant applies)
insert into user_roles select u, r.code from (values (:'as'::uuid), (:'bs'::uuid)) v(u) cross join roles r where r.code <> 'owner' on conflict do nothing;
select tt.as(:'o');
select org_unit_save(null, (select id from org_units where kind='group'), 'legal_entity', 'le-c3', 'হার্ডওয়্যার কোম্পানি', 'Hardware Co', null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, '{"owner_pct":100}'::jsonb, '00000000-0000-0000-0000-0000000c3f01') ->> 'id' as hle \gset
select org_unit_save(null, :'hle'::bigint, 'business', 'HARDWARE', 'হার্ডওয়্যার ও রং', 'Hardware and paint', 'hardware_paint', 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000c3f02') ->> 'id' as hbz \gset
select org_unit_save(null, :'hbz'::bigint, 'branch', 'HW-B1', 'শাখা ১', 'Branch 1', null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000c3f03') ->> 'id' as hb1 \gset
select id as sbz from org_units where code = 'SWEETS' \gset
insert into locations (code, name_bn, name_en, kind, status, org_unit_id) values ('hw1','হার্ডওয়্যার ১','Hardware 1','showroom','live', :'hb1'::bigint),('hw2','হার্ডওয়্যার ২','Hardware 2','showroom','live', :'hbz'::bigint),
 ('orphan','অমিল','Unmapped','showroom','live', null);
select id as hw1 from locations where code = 'hw1' \gset
select id as hw2 from locations where code = 'hw2' \gset
select id as orph from locations where code = 'orphan' \gset
insert into user_locations values (:'ao',1),(:'bo',:'hw1'),(:'aop',1),(:'bop',:'hw1') on conflict do nothing;
insert into ops_accounts (user_id, purpose, active) values (:'aop','notify',true),(:'aop','backup',true),(:'bop','notify',true),(:'bop','backup',true) on conflict do nothing;
select org_scope_grant(:'am'::uuid, :'sbz'::bigint, 'management', 'a mgr', gen_random_uuid()) is not null as sc1 \gset
select org_scope_grant(:'as'::uuid, :'sbz'::bigint, 'management', 'a super', gen_random_uuid()) is not null as sc2 \gset
select org_scope_grant(:'bm'::uuid, :'hbz'::bigint, 'management', 'b mgr', gen_random_uuid()) is not null as sc3 \gset
select org_scope_grant(:'bs'::uuid, :'hbz'::bigint, 'management', 'b super', gen_random_uuid()) is not null as sc4 \gset
-- the "super" users hold EVERY grant of the catalogue with no place (a personal NULL-location grant = the worst case for the business border)
do $$ declare g record; begin
  for g in select grant_code from public.grant_defs where grant_code <> 'org_manage' loop      -- org_manage is a GROUP-level grant (phase122): not part of "every grant of a business"

    perform public.set_user_grant('00000000-0000-0000-0000-0000000c3a03'::uuid, g.grant_code);
    perform public.set_user_grant('00000000-0000-0000-0000-0000000c3b03'::uuid, g.grant_code);
  end loop;
end $$;
select tt.as(:'o');
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values ('C3-X','x','Item X','pc','pc','finished_good',true,100,true) on conflict do nothing;
select acct_set_start(tt.today()-5)->>'start' as sd \gset

create or replace function c3.seed_data(p_loc int, p_loc2 int, p_staff uuid, p_tag text, p_biz bigint) returns jsonb language plpgsql as $f$
declare itm uuid := (select id from public.items where code = 'C3-X'); cust uuid; sup uuid; s1 jsonb; s2 jsonb; pur jsonb; ent uuid; emp uuid; pr bigint; ch int; oo uuid; fa uuid; sale uuid; ids jsonb := '{}'::jsonb; nid bigint; exid bigint; emr bigint; inb bigint; mob text;
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
  mob := '0171' || lpad((abs(hashtext(p_tag)) % 10000000)::text, 7, '0');
  perform public.stock_opening(itm, p_loc, 100, 40 + length(p_tag));
  s1 := public.record_sale2(gen_random_uuid(), p_loc, format('[{"item_id":"%s","qty":10,"price":100}]', itm)::jsonb, 0, '[{"mode":"cash","amount":400}]', mob, 'Cust ' || p_tag, 'retail', null, false);
  s2 := public.record_sale2(gen_random_uuid(), p_loc, format('[{"item_id":"%s","qty":4,"price":100}]', itm)::jsonb, 0, '[{"mode":"cash","amount":400}]', null, null, 'retail', null, false);
  sale := (s1 ->> 'id')::uuid;
  select id into cust from public.customers where mobile like '%' || right(mob, 8) limit 1;
  begin perform public.sale_return(gen_random_uuid(), (s2 ->> 'id')::uuid, format('[{"item_id":"%s","qty":1}]', itm)::jsonb, 'damaged', null, 'cash', null, null); exception when others then null; end;
  begin perform public.collect_payment(gen_random_uuid(), p_loc, cust, '[{"mode":"cash","amount":100}]'::jsonb, 'c'); exception when others then null; end;
  insert into public.suppliers (name) values ('Supplier ' || p_tag) returning id into sup;
  pur := public.save_purchase(gen_random_uuid(), null, sup, p_loc, 'P-' || p_tag, current_date, format('[{"item_id":"%s","qty":10,"unit":"pc","unit_cost":50}]', itm)::jsonb);
  begin perform public.stock_wastage(itm, p_loc, 2, (select value_code from public.option_lists where list_code = 'wastage_reasons' and active order by sort, value_code limit 1), 'w ' || p_tag); exception when others then null; end;
  insert into public.entries (form_code, location_id, serial, entry_date, created_by, data) values ('ITEMS', p_loc, 1, current_date, p_staff, jsonb_build_object('tag', p_tag)) returning id into ent;
  insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text) values (ent, 'ITEMS', p_loc, current_date, 'cash_short_over', 'red', -50, jsonb_build_object('tag', p_tag)) returning id into exid;
  insert into public.notifications (audience, kind, level, title_bn, title_en, location_id, key, day) values ('manager', 'c_three', 'bad', 'x', 'note ' || p_tag, p_loc, 'c3' || p_tag, current_date) returning id into nid;
  insert into public.employees (full_name_bn, full_name_en, primary_location_id, status) values ('E ' || p_tag, 'Emp ' || p_tag, p_loc, 'active') returning id into emp;
  insert into public.payroll_runs (month, location_id) values (date_trunc('month', current_date)::date, p_loc) returning id into pr;
  insert into public.emergency_requests (grant_code, requested_by, location_id, reason, status) values ('loc_access', p_staff, p_loc, 'r ' || p_tag, 'pending') returning id into emr;
  insert into public.sales_channels (code, kind, other_text, name_bn, location_id, account_ref) values ('c3_' || lower(p_tag), 'other', 'x', 'ch ' || p_tag, p_loc, 'acc_' || p_tag) returning id into ch;
  insert into public.inbound_messages (channel_id, location_id, external_id, customer_handle, customer_name, msg_text, status) values (ch, p_loc, 'ext-' || p_tag, 'h', 'Chat ' || p_tag, 'hello ' || p_tag, 'new') returning id into inb;
  insert into public.online_orders (order_no, location_id, channel, customer_name, customer_mobile, lines, subtotal, delivery_mode, status, created_by) values ((select coalesce(max(order_no), 0) + 1 from public.online_orders), p_loc, 'other', 'Online ' || p_tag, mob, format('[{"item_id":"%s","qty":1,"price":10}]', itm)::jsonb, 10, 'pickup', 'new', p_staff) returning id into oo;
  insert into public.quick_expenses (location_id, exp_date, head, amount, mode, created_by) values (p_loc, current_date, 'tea', 25, 'cash', p_staff);
  begin perform public.cash_move_add(p_loc, 'owner_topup', 300, current_date, 'cash', null, 'r', 'n ' || p_tag, gen_random_uuid(), false); exception when others then null; end;
  begin perform public.post_purchase((pur ->> 'id')::uuid, '[]'::jsonb); exception when others then null; end;
  insert into public.fa_assets (code, name, location_id, acquired_on, cost, life_months, depr_from) values ('FA-' || p_tag, 'Asset ' || p_tag, p_loc, current_date - 100, 1000, 10, date_trunc('month', current_date - 90)::date) returning id into fa;
  insert into public.drawer_events (client_id, event, location_id, by_user, by_staff, reason, at) values (gen_random_uuid(), 'no_sale_open', p_loc, p_staff, p_tag, 'r', now());
  insert into public.location_settings (location_id, key, value) values (p_loc, 'c3k', to_jsonb(p_tag));
  insert into public.holidays (day, location_id, name_bn) values (current_date + 5, p_loc, 'h ' || p_tag);
  insert into public.shifts (name_bn, location_id, start_time, end_time) values ('s ' || p_tag, p_loc, '09:00', '17:00');
  return jsonb_build_object('sale_' || p_tag, sale, 'cust_' || p_tag, cust, 'sup_' || p_tag, sup, 'pur_' || p_tag, pur ->> 'id', 'entry_' || p_tag, ent, 'emp_' || p_tag, emp, 'payrun_' || p_tag, pr, 'fa_' || p_tag, fa,
    'oo_' || p_tag, oo, 'notif_' || p_tag, nid, 'exc_' || p_tag, exid, 'emreq_' || p_tag, emr, 'inb_' || p_tag, inb, 'chan_' || p_tag, ch);
end $f$;
grant execute on function c3.seed_data(int, int, uuid, text, bigint) to authenticated, anon;
