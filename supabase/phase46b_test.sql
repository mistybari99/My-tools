-- FRESH DB ONLY. Phase 46 tests (backup bot access, whitelist, pagination, notifications, digest).
-- phase46b: copy of phase46_test.sql; F13 now allows token_a / token_b (permission names, phase91 perm_conflict, backup list fixed in phase106) and tokens_in / tokens_out. Run on the final build.
--   ORDER="phase8 ... phase28 phase46" bash tests/sql/build_fresh_db.sh a46t ; psql -h /tmp -p 5544 -U postgres -d a46t -qAt -f supabase/phase46_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set b '00000000-0000-0000-0000-000000000006'
\set n '00000000-0000-0000-0000-000000000007'
\set pend '00000000-0000-0000-0000-000000000008'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}'), (:'k','store3@s.app','{"full_name":"Store"}'),
  (:'b','bot-backup@s.app','{"full_name":"Backup bot"}'), (:'n','bot-notify@s.app','{"full_name":"Notify bot"}'), (:'pend','newbie@s.app','{"full_name":"Newbie"}') on conflict do nothing;
update profiles set status='active' where id <> :'pend';
update profiles set created_at = now() - interval '3 days' where id = :'pend';
insert into user_roles values (:'s','showroom_manager'),(:'k','storekeeper') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1) on conflict do nothing;

\echo == seed (as superuser)
create table public.zz_secret_stuff (id int primary key, v text);
create table public.zz_has_pin (id int primary key, pin_hash text);
create table public.zz_nopk (a int, b text);
insert into public.zz_nopk select g, 'r' || g from generate_series(1, 5) g;
insert into public.zz_nopk values (1, 'r1');                     -- an exact duplicate row must still be dumped twice
insert into customers (mobile, name, credit_limit) select '019' || lpad(g::text, 8, '0'), 'Cust ' || g, 0 from generate_series(1, 23) g;
insert into customers (id, mobile, name, credit_limit) values ('c0000000-0000-0000-0000-000000000001', '01700000001', 'Credit Cust', 100);
insert into items (id, code, name_bn, name_en, unit, min_stock, tracked, is_active) values ('a0000000-0000-0000-0000-000000000001', 'ZZ1', 'রসগোল্লা', 'Rasgulla', 'kg', 10, true, true);
insert into stock_balance (item_id, location_id, qty, avg_cost) values ('a0000000-0000-0000-0000-000000000001', 1, 3, 200);
insert into stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at) values ('a0000000-0000-0000-0000-000000000001', 1, now() - interval '1 day', 5, 5, now() + interval '1 day');
insert into suppliers (id, name, credit_days) values ('b0000000-0000-0000-0000-000000000001', 'Sup One', 7);
insert into purchase_bills (supplier_id, bill_no, bill_date, location_id, status, kind, subtotal, total, paid, posted_at)
  values ('b0000000-0000-0000-0000-000000000001', 'B1', (now() at time zone 'Asia/Dhaka')::date - 30, 1, 'posted', 'bill', 5000, 5000, 0, now() - interval '30 days');
insert into exceptions (form_code, location_id, entry_date, flag_code, level, amount, text, status, created_at)
  values ('POS', 1, (now() at time zone 'Asia/Dhaka')::date, 'discount_over_limit', 'red', 100, '{}', 'open', now() - interval '30 hours'),
         ('14-1', 1, (now() at time zone 'Asia/Dhaka')::date, 'cash_short_over', 'yellow', -800, '{}', 'open', now());
-- sales: today 1000 (discount 50) + 500 credit to Credit Cust + a void 300; yesterday 650; a week ago 2600; a return of 200 today
insert into sales (id, location_id, receipt, sale_date, lines, subtotal, discount, total, pay_mode, status, created_by, customer_id, due_amount) values
 ('d0000000-0000-0000-0000-000000000001', 1, 9001, (now() at time zone 'Asia/Dhaka')::date, '[{"name":"Rasgulla","qty":2,"amount":600},{"name":"Cake","qty":1,"amount":400}]', 1050, 50, 1000, 'cash', 'done', :'o', null, 0),
 ('d0000000-0000-0000-0000-000000000002', 1, 9002, (now() at time zone 'Asia/Dhaka')::date, '[{"name":"Rasgulla","qty":1,"amount":300},{"name":"Sandesh","qty":1,"amount":200}]', 500, 0, 500, 'due', 'done', :'o', 'c0000000-0000-0000-0000-000000000001', 500),
 ('d0000000-0000-0000-0000-000000000003', 1, 9003, (now() at time zone 'Asia/Dhaka')::date, '[{"name":"Voided","qty":1,"amount":300}]', 300, 0, 300, 'cash', 'done', :'o', null, 0),
 ('d0000000-0000-0000-0000-000000000004', 2, 9004, (now() at time zone 'Asia/Dhaka')::date - 1, '[]', 650, 0, 650, 'cash', 'done', :'o', null, 0),
 ('d0000000-0000-0000-0000-000000000005', 2, 9005, (now() at time zone 'Asia/Dhaka')::date - 7, '[]', 2600, 0, 2600, 'cash', 'done', :'o', null, 0);
update sales set status = 'void', void_at = now(), void_note = 'test' where id = 'd0000000-0000-0000-0000-000000000003';
insert into sale_returns (sale_id, location_id, lines, amount, credit_amount, refund_amount, reason_code, status) values ('d0000000-0000-0000-0000-000000000001', 1, '[]', 200, 0, 200, 'x', 'done');
insert into sale_payments (customer_id, location_id, kind, mode, amount, paid_at) values ('c0000000-0000-0000-0000-000000000001', 1, 'collection', 'cash', 250, now());
insert into stock_wastage (item_id, location_id, qty, reason_code, made_at) values ('a0000000-0000-0000-0000-000000000001', 1, 10, 'spoil', now());
insert into comparison_pairs (id, form_code, name_bn) values (9001, '14-1', 'drawer');
insert into form_rollout (form_code, location_id, mode) values ('14-1', 1, 'parallel') on conflict (form_code, location_id) do update set mode = 'parallel';
insert into comparison_days (pair_id, form_code, location_id, day, paper_value, app_value, result)
  values (9001, '14-1', 1, (date_trunc('month', (now() at time zone 'Asia/Dhaka')::date) - interval '2 days')::date, 100, 100, 'match');

\echo == ops accounts
set role authenticated; select tt.as(:'s');
select tt.err('F1 a manager cannot mark a bot', format($$select ops_account_set(%L,'backup',true)$$, :'b'), 'not allowed');
select tt.as(:'o');
select tt.err('F1 the owner cannot be the bot', format($$select ops_account_set(%L,'backup',true)$$, :'o'), 'owner_cannot_be_bot');
select tt.err('F1 unknown purpose refused', format($$select ops_account_set(%L,'root',true)$$, :'b'), 'bad_input');
select tt.err('F1 unknown user refused', $$select ops_account_set('99999999-0000-0000-0000-000000000000','backup',true)$$, 'user_not_found');
select ops_account_set(:'b','backup',true) is not null as a1 \gset
select ops_account_set(:'n','notify',true) is not null as a2 \gset
select tt.chk('F1 owner marks both bots', (select count(*) from ops_accounts where active)=2);
select tt.as(:'s'); select tt.chk('F1 staff cannot read ops_accounts', (select count(*) from ops_accounts)=0);

\echo == shape and grants
reset role;
select tt.chk('F2 RLS on every new table', (select count(*) from pg_class where relname in ('ops_accounts','backup_runs','notifications','notification_reads') and relrowsecurity)=4);
select tt.chk('F2 browser has no write grant', not has_table_privilege('authenticated','notifications','insert') and not has_table_privilege('authenticated','backup_runs','insert') and not has_table_privilege('authenticated','ops_accounts','insert') and not has_table_privilege('authenticated','notification_reads','insert'));
select tt.chk('F2 anon cannot run any module function', not has_function_privilege('anon','backup_dump(text,text,int)','execute') and not has_function_privilege('anon','notify_scan()','execute') and not has_function_privilege('anon','notifications_for_me(int,boolean,text)','execute') and not has_function_privilege('anon','daily_digest(date)','execute'));
select tt.chk('F2 helpers are not callable by the browser', not has_function_privilege('authenticated','_notif_add(text,text,text,text,text,text,text,text,text,int)','execute') and not has_function_privilege('authenticated','_backup_tables()','execute'));

\echo == backup access
set role authenticated;
select tt.as(:'o'); select tt.err('F3 even the owner cannot call backup_dump', $$select backup_dump('customers')$$, 'not allowed');
select tt.as(:'s'); select tt.err('F3 a manager cannot call backup_dump', $$select backup_dump('customers')$$, 'not allowed');
select tt.as(:'n'); select tt.err('F3 the notify bot cannot call backup_dump', $$select backup_dump('customers')$$, 'not allowed');
select tt.err('F3 the notify bot cannot call backup_manifest', $$select backup_manifest()$$, 'not allowed');
select tt.err('F3 the notify bot cannot log a backup', $$select backup_log('ok')$$, 'not allowed');
select tt.as(:'b'); select tt.err('F3 the backup bot cannot run the scan', $$select notify_scan()$$, 'not allowed');
select tt.err('F3 the backup bot cannot read the digest', $$select daily_digest()$$, 'not allowed');
select tt.chk('F3 the backup bot sees no table directly', (select count(*) from customers)=0 and (select count(*) from backup_runs)=0);
select tt.chk('F3 the backup bot can dump', (backup_dump('customers', null, 5) ->> 'total')::int = 24);
reset role; set role anon; select tt.as('');
select tt.err('F3 anon cannot call backup_dump', $$select backup_dump('customers')$$, 'permission denied');
reset role; set role authenticated; select tt.as(:'b');

\echo == whitelist
reset role;
select tt.chk('F4 whitelist excludes login data', not (_backup_tables() && array['login_failures','login_attempts','login_throttle']));
select tt.chk('F4 whitelist excludes *_secret* and tables with a pin_hash column', not (_backup_tables() && array['zz_secret_stuff','zz_has_pin']));
select tt.chk('F4 whitelist excludes ops internals and own run tables', not (_backup_tables() && array['ops_accounts','backup_runs','notifications','notification_reads']));
select tt.chk('F4 whitelist includes the business tables', _backup_tables() @> array['sales','entries','customers','audit_log','profiles','stock_ledger','rules']);
select tt.chk('F4 whitelist has only public tables', not exists (select 1 from unnest(_backup_tables()) t where to_regclass('public.' || quote_ident(t)) is null));
set role authenticated; select tt.as(:'b');
select tt.err('F4 a login table cannot be dumped', $$select backup_dump('login_failures')$$, 'table_not_allowed');
select tt.err('F4 a secret table cannot be dumped', $$select backup_dump('zz_secret_stuff')$$, 'table_not_allowed');
select tt.err('F4 a table with a pin hash cannot be dumped', $$select backup_dump('zz_has_pin')$$, 'table_not_allowed');
select tt.err('F4 an auth table cannot be dumped', $$select backup_dump('users')$$, 'table_not_allowed');
select tt.err('F4 a schema-qualified name cannot be used', $$select backup_dump('auth.users')$$, 'table_not_allowed');
select tt.err('F4 an injection attempt is refused', $$select backup_dump('customers; drop table customers')$$, 'table_not_allowed');
select tt.err('F4 a bad cursor is refused', $$select backup_dump('customers', 'x''; drop table customers; --')$$, 'bad_cursor');

\echo == pagination covers every row exactly once
create temp table pg_seen (tbl text, k text);
grant all on pg_seen to authenticated;
do $$ declare t text; cur text; r jsonb; row_ jsonb; pages int; begin
  foreach t in array array['customers', 'user_roles', 'zz_nopk', 'audit_log', 'rules'] loop
    cur := null; pages := 0;
    loop
      r := public.backup_dump(t, cur, 7); pages := pages + 1;
      for row_ in select * from jsonb_array_elements(r -> 'rows') loop insert into pg_seen values (t, row_::text); end loop;
      cur := r ->> 'next';
      exit when cur is null or pages > 400;
    end loop;
  end loop;
end $$;
reset role;
select tt.chk('F5 customers: every row once (' || (select count(*) from pg_seen where tbl='customers') || ')', (select count(*) from pg_seen where tbl='customers') = (select count(*) from customers) and (select count(distinct k) from pg_seen where tbl='customers') = (select count(*) from customers));
select tt.chk('F5 composite key table (user_roles) every row once', (select count(*) from pg_seen where tbl='user_roles') = (select count(*) from user_roles) and (select count(distinct k) from pg_seen where tbl='user_roles') = (select count(*) from user_roles));
select tt.chk('F5 table without a primary key: all 6 rows incl. the duplicate', (select count(*) from pg_seen where tbl='zz_nopk') = 6);
select tt.chk('F5 audit_log and rules fully covered', (select count(*) from pg_seen where tbl='audit_log') = (select count(*) from audit_log) and (select count(*) from pg_seen where tbl='rules') = (select count(*) from rules));
set role authenticated; select tt.as(:'b');
select tt.chk('F5 a page never exceeds the limit and total is exact', jsonb_array_length(backup_dump('customers', null, 4) -> 'rows') = 4 and (backup_dump('customers', null, 4) ->> 'total')::int = 24);
select tt.chk('F5 the last page has no cursor', (backup_dump('customers', null, 1000) -> 'next') = 'null'::jsonb);
select tt.chk('F5 the limit is capped at 5000', jsonb_array_length(backup_dump('customers', null, 999999) -> 'rows') = 24);
select tt.chk('F5 rows are whole json objects with their values', (backup_dump('customers', null, 1) -> 'rows' -> 0 ->> 'mobile') is not null);

\echo == photos bucket read for the backup bot only
reset role; insert into storage.objects (bucket_id, name) values ('photos', 'zz/1/a.jpg'), ('other', 'zz/1/b.jpg');
set role authenticated; select tt.as(:'b');
select tt.chk('F5b the backup bot can list the photos bucket (and only that bucket)', (select count(*) from storage.objects) = 1 and (select count(*) from storage.objects where bucket_id = 'photos') = 1);
select tt.as(:'s'); select tt.chk('F5b a manager gains nothing', (select count(*) from storage.objects where name = 'zz/1/a.jpg') = 0);
select tt.as(:'n'); select tt.chk('F5b the notify bot gains nothing', (select count(*) from storage.objects) = 0);
select tt.as(:'b');

\echo == manifest and log
select backup_manifest() as man \gset
select tt.chk('F6 manifest counts match', (:'man'::jsonb ->> 'schema_version')::int = 46 and (select (e ->> 'rows')::int from jsonb_array_elements(:'man'::jsonb -> 'tables') e where e ->> 'name' = 'customers') = 24 and length(:'man'::jsonb ->> 'fingerprint') = 32);
reset role; select tt.chk('F6 manifest lists exactly the whitelist', (:'man'::jsonb ->> 'table_count')::int = array_length(_backup_tables(), 1));
set role authenticated; select tt.as(:'b');
select tt.err('F6 bad status refused', $$select backup_log('great')$$, 'bad_status');
select tt.as(:'o'); select tt.chk('F6 no run yet: configured and stale', (backup_status() ->> 'configured')::boolean and (backup_status() ->> 'stale')::boolean);
select tt.as(:'b'); select backup_log('ok', '{"note":"t"}'::jsonb, now() - interval '1 minute', 40, 1234, 99999, 'github') as rid \gset
select tt.as(:'o'); select tt.chk('F6 owner reads the run', (select count(*) from backup_runs where id = :'rid' and status = 'ok' and rows = 1234 and tables = 40) = 1);
select tt.chk('F6 fresh OK run is not stale', not (backup_status() ->> 'stale')::boolean and (backup_status() -> 'last_ok' ->> 'rows')::int = 1234);
select tt.as(:'s'); select tt.chk('F6 a manager cannot read runs', (select count(*) from backup_runs) = 0);
select tt.err('F6 a manager cannot read the status', $$select backup_status()$$, 'not allowed');
reset role; update backup_runs set finished_at = now() - interval '40 hours';
set role authenticated; select tt.as(:'o');
select tt.chk('F6 40 hours old with a 36 hour rule = stale', (backup_status() ->> 'stale')::boolean);
select set_rule('backup_max_age_hours', '48'::jsonb) is null as sr \gset
select tt.chk('F6 the rule moves the limit', not (backup_status() ->> 'stale')::boolean);
select set_rule('backup_max_age_hours', null) is null as sr2 \gset

\echo == notify_scan: access, switches, thresholds
select tt.as(:'s'); select tt.err('F7 a manager cannot scan', $$select notify_scan()$$, 'not allowed');
select tt.as(:'o');
select set_rule('notify_on', 'false'::jsonb) is null as r0 \gset
select tt.chk('F7 master switch off = nothing made', (notify_scan() ->> 'created')::int = 0 and (select count(*) from notifications) = 0);
select set_rule('notify_on', 'true'::jsonb) is null as r1 \gset
select set_rule('notify_exceptions_hours', '100'::jsonb) is null as r2 \gset
select set_rule('notify_approvals_on', 'false'::jsonb) is null as r3 \gset
select set_rule('notify_lowstock_min', '5'::jsonb) is null as r4 \gset
select set_rule('notify_cash_limit', '5000'::jsonb) is null as r5 \gset
select set_rule('day_close_deadline', '"23:59"'::jsonb) is null as r6 \gset
select tt.as(:'n'); select notify_scan() as sc1 \gset
select tt.as(:'o');
select tt.chk('F7 exception threshold 100h: a 30h exception is not reported', (select count(*) from notifications where kind = 'red_exceptions') = 0);
select tt.chk('F7 approvals switch off: not reported', (select count(*) from notifications where kind = 'approvals_waiting') = 0);
select tt.chk('F7 low-stock minimum 5 items: 1 low item is not reported', (select count(*) from notifications where kind = 'low_stock') = 0);
select tt.chk('F7 cash limit 5000: a 800 gap is not reported', (select count(*) from notifications where kind = 'cash_gap') = 0);
select tt.chk('F7 deadline 23:59: day-close not yet reported', (select count(*) from notifications where kind = 'day_close_missing') = 0 or to_char(now() at time zone 'Asia/Dhaka', 'HH24:MI') = '23:59');
select tt.chk('F7 other kinds were made', (select count(*) from notifications where kind in ('expiring_batches','supplier_overdue','credit_breach','wastage_spike','backup_stale')) = 5);
select tt.as(:'o');
select set_rule('notify_exceptions_hours', '24'::jsonb) is null as q2 \gset
select set_rule('notify_approvals_on', 'true'::jsonb) is null as q3 \gset
select set_rule('notify_lowstock_min', '1'::jsonb) is null as q4 \gset
select set_rule('notify_cash_limit', '500'::jsonb) is null as q5 \gset
select set_rule('day_close_deadline', '"00:00"'::jsonb) is null as q6 \gset
select tt.as(:'n'); select notify_scan() as sc2 \gset
select tt.as(:'o');
reset role;
select id as nid_exc from notifications where kind = 'red_exceptions' \gset
select id as nid_dc2 from notifications where kind = 'day_close_missing' and location_id = 2 \gset
select count(*) as nbad from notifications where level = 'bad' and user_id is null \gset
select count(*) as nall from notifications \gset
select string_agg(id::text, ',') as allids from notifications \gset
set role authenticated; select tt.as(:'o');
select tt.chk('F8 loosened thresholds now report: red exception (bad)', (select count(*) from notifications where kind = 'red_exceptions' and level = 'bad' and audience = 'owner') = 1);
select tt.chk('F8 approvals now reported (the pending newbie)', (select count(*) from notifications where kind = 'approvals_waiting') = 1);
select tt.chk('F8 low stock reported for place 1 only, manager audience', (select count(*) from notifications where kind = 'low_stock' and location_id = 1 and audience = 'manager') = 1 and (select count(*) from notifications where kind = 'low_stock') = 1);
select tt.chk('F8 cash gap reported once with its amount', (select count(*) from notifications where kind = 'cash_gap' and title_en like '%800%') = 1);
select tt.chk('F8 day-close missing for all 4 showrooms', (select count(*) from notifications where kind = 'day_close_missing') = 4);
select tt.chk('F8 parallel decision waiting reported for 14-1 at place 1', (select count(*) from notifications where kind = 'parallel_decision' and key = '14-1:1' and audience = 'owner') = 1);
select tt.chk('F8 supplier overdue carries the total', (select count(*) from notifications where kind = 'supplier_overdue' and body_en like '%5000%') = 1);
select tt.chk('F8 credit breach counted', (select count(*) from notifications where kind = 'credit_breach' and title_en like '1 customer%') = 1);
select tt.chk('F8 wastage spike reported (2000 vs a 0 average)', (select count(*) from notifications where kind = 'wastage_spike' and title_en like '%2000%') = 1);
select tt.chk('F8 backup stale was reported (40h > 36h), level bad', (select count(*) from notifications where kind = 'backup_stale' and level = 'bad') = 1);
select tt.chk('F9 a second scan the same day adds nothing', (notify_scan() ->> 'created')::int = 0); select tt.as(:'o');
select tt.chk('F9 idempotent: still one per (kind, key, day)', (select count(*) from (select kind, key, day from notifications group by 1,2,3 having count(*) > 1) z) = 0);
select tt.as(:'o'); select tt.chk('F9 the owner may scan too', (notify_scan() ->> 'created')::int = 0);

\echo == notification reads per user
select tt.as(:'o'); select notifications_unread_count() as ou0 \gset
select tt.as(:'s'); select notifications_unread_count() as su0 \gset
select tt.chk('F10 owner sees every note', :ou0 = :nall);
select tt.chk('F10 manager (place 1) sees only manager notes for place 1: low stock, expiry, day close', :su0 = 3);
select tt.as(:'k'); select tt.chk('F10 a storekeeper (not a manager role) sees none', notifications_unread_count() = 0 and jsonb_array_length(notifications_for_me()) = 0);
select tt.as(:'s'); select (notifications_for_me(10) -> 0 ->> 'id')::bigint as sid \gset
select tt.chk('F10 list is newest first', (notifications_for_me(10) -> 0 ->> 'id')::bigint >= (notifications_for_me(10) -> 1 ->> 'id')::bigint);
select notification_read(:sid) as rd \gset
select tt.chk('F10 reading one lowers only my count', notifications_unread_count() = :su0 - 1);
select tt.as(:'o'); select tt.chk('F10 the owner count is unchanged by the manager''s read', notifications_unread_count() = :ou0);
select tt.as(:'s'); select tt.chk('F10 unread-only filter hides the read one', (select count(*) from jsonb_array_elements(notifications_for_me(50, true)) e where (e ->> 'id')::bigint = :sid) = 0 and jsonb_array_length(notifications_for_me(50, true)) = :su0 - 1);
select tt.chk('F10 level filter works', (select bool_and(e ->> 'level' = 'warn') from jsonb_array_elements(notifications_for_me(50, false, 'warn')) e));
select tt.err('F10 a manager cannot read an owner-only note', format($$select notification_read(%s)$$, :nid_exc), 'not allowed');
select tt.err('F10 a manager cannot read another place''s note', format($$select notification_read(%s)$$, :nid_dc2), 'not allowed');
select tt.chk('F10 read twice is harmless', notification_read(:sid));
select tt.as(:'o'); select notification_read_all() >= 0 as ra \gset
select tt.chk('F10 read-all clears the owner count', notifications_unread_count() = 0);
select tt.as(:'s'); select tt.chk('F10 ...but not the manager''s', notifications_unread_count() = :su0 - 1);
select tt.as(:'o'); select tt.chk('F10 the manager''s reads are private', (select count(*) from notification_reads where user_id = :'s') = 0);
select tt.as(:'s'); select tt.chk('F10 a user reads only their own read marks', (select count(*) from notification_reads) = 1);
reset role; select tt.chk('F10 nothing can be deleted', (select count(*) from notifications) > 0);
set role authenticated;
select tt.err('F10 notifications cannot be hard-deleted', $$delete from notifications$$, 'permission denied');

\echo == e-mail side
select tt.as(:'s'); select tt.err('F11 a manager cannot get urgent alerts', $$select urgent_alerts()$$, 'not allowed');
select tt.as(:'b'); select tt.err('F11 the backup bot cannot get urgent alerts', $$select urgent_alerts()$$, 'not allowed');
select tt.as(:'n'); select urgent_alerts() as ua \gset
select tt.chk('F11 urgent alerts = bad level, owner audience, not yet mailed', jsonb_array_length(:'ua'::jsonb) = :nbad and :nbad >= 3);
select tt.as(:'o'); select tt.chk('F11 listing does not mark anything', (select count(*) from notifications where emailed_at is not null) = 0); select tt.as(:'n');
select tt.err('F11 mark_emailed refuses a huge list', $$select notifications_mark_emailed((select array_agg(g::bigint) from generate_series(1, 600) g))$$, 'bad_input');
select notifications_mark_emailed((select array_agg((e ->> 'id')::bigint) from jsonb_array_elements(:'ua'::jsonb) e)) as marked \gset
select tt.chk('F11 marked rows counted', :marked = :nbad);
select tt.chk('F11 nothing urgent is left', jsonb_array_length(urgent_alerts()) = 0);
select tt.chk('F11 marking again changes nothing', notifications_mark_emailed(array[:allids]::bigint[]) = :nall - :marked);
select tt.chk('F11 config for the sender', (notify_config() ->> 'digest_times') = '08,21' and (notify_config() ->> 'email_on')::boolean);

\echo == daily digest (seeded numbers)
select tt.as(:'s'); select tt.err('F12 a manager cannot read the digest', $$select daily_digest()$$, 'not allowed');
select tt.as(:'n'); select daily_digest() as dg \gset
select tt.chk('F12 today net = 1500 sales - 200 return (void excluded)', (:'dg'::jsonb #>> '{sales,today,net}')::numeric = 1300 and (:'dg'::jsonb #>> '{sales,today,bills}')::int = 2 and (:'dg'::jsonb #>> '{sales,today,total}')::numeric = 1500);
select tt.chk('F12 vs yesterday +100.0 % and vs last week -50.0 %', (:'dg'::jsonb #>> '{sales,vs_yesterday_pct}')::numeric = 100.0 and (:'dg'::jsonb #>> '{sales,vs_last_week_pct}')::numeric = -50.0);
select tt.chk('F12 discount and void figures', (:'dg'::jsonb #>> '{voids_discounts,discount_total}')::numeric = 50 and (:'dg'::jsonb #>> '{voids_discounts,discount_count}')::int = 1 and (:'dg'::jsonb #>> '{voids_discounts,void_count}')::int = 1 and (:'dg'::jsonb #>> '{voids_discounts,void_total}')::numeric = 300);
select tt.chk('F12 top item is Rasgulla 900 (3 kg), then Cake, Sandesh', (:'dg'::jsonb #>> '{top_items,0,name}') = 'Rasgulla' and (:'dg'::jsonb #>> '{top_items,0,amount}')::numeric = 900 and (:'dg'::jsonb #>> '{top_items,0,qty}')::numeric = 3 and (:'dg'::jsonb #>> '{top_items,1,name}') = 'Cake' and (:'dg'::jsonb #>> '{top_items,2,name}') = 'Sandesh');
select tt.chk('F12 cash short 800, collections 250', (:'dg'::jsonb #>> '{cash,short}')::numeric = 800 and (:'dg'::jsonb #>> '{cash,over}')::numeric = 0 and (:'dg'::jsonb ->> 'collections')::numeric = 250);
select tt.chk('F12 customer dues 250 (500 - 250), supplier payable 5000 all overdue', (:'dg'::jsonb #>> '{dues,customers_total}')::numeric = 250 and (:'dg'::jsonb #>> '{dues,suppliers,payable}')::numeric = 5000 and (:'dg'::jsonb #>> '{dues,suppliers,overdue}')::numeric = 5000);
select tt.chk('F12 wastage 2000, open exceptions 1 red / 1 yellow, 1 approval, stock alerts', (:'dg'::jsonb #>> '{wastage,value}')::numeric = 2000 and (:'dg'::jsonb #>> '{exceptions_open,red}')::int = 1 and (:'dg'::jsonb #>> '{exceptions_open,yellow}')::int = 1 and (:'dg'::jsonb ->> 'approvals_pending')::int = 1 and (:'dg'::jsonb #>> '{stock_alerts,low_items}')::int = 1 and (:'dg'::jsonb #>> '{stock_alerts,expiring_batches}')::int = 1);
select tt.chk('F12 day-close status for the 4 showrooms, none closed', jsonb_array_length(:'dg'::jsonb -> 'day_close') = 4 and not exists (select 1 from jsonb_array_elements(:'dg'::jsonb -> 'day_close') e where (e ->> 'closed')::boolean));
select tt.chk('F12 per-place sales: place 1 = 1300', (select (e ->> 'net')::numeric from jsonb_array_elements(:'dg'::jsonb #> '{sales,by_location}') e where (e ->> 'location_id')::int = 1) = 1300);
select tt.chk('F12 backup status is in the digest', (:'dg'::jsonb #>> '{backup,configured}')::boolean);
select tt.err('F12 a future date is refused', $$select daily_digest((now() at time zone 'Asia/Dhaka')::date + 5)$$, 'bad_date');
select tt.chk('F12 a past day works and is empty', (daily_digest((now() at time zone 'Asia/Dhaka')::date - 3) #>> '{sales,today,bills}')::int = 0);
select tt.as(:'o');
select set_rule('reports_net_of_returns', 'false'::jsonb) is null as nr \gset
select tt.chk('F12 follows the report rule: returns not subtracted when off', (daily_digest() #>> '{sales,today,net}')::numeric = 1500);
select set_rule('reports_net_of_returns', 'true'::jsonb) is null as nr2 \gset

\echo == nothing secret leaves the database
set role authenticated; select tt.as(:'b');
create temp table leak (tbl text, k text); grant all on leak to authenticated;
do $$ declare t text; r jsonb; k text; begin
  for t in select e ->> 'name' from jsonb_array_elements(backup_manifest() -> 'tables') e loop
    for r in select * from jsonb_array_elements(backup_dump(t, null, 3) -> 'rows') loop
      for k in select jsonb_object_keys(r) loop if k ~* '(password|passwd|pin_hash|secret|token|salt|api_key|private_key)' and k !~ '^(tokens_(in|out)|token_[ab])$' then insert into leak values (t, k); end if; end loop;
    end loop;
  end loop;
end $$;
select tt.chk('F13 no dumped row has a password / pin / secret / token column', (select count(*) from leak) = 0);
select tt.chk('F13 the profiles dump carries no auth e-mail or password', not exists (select 1 from jsonb_array_elements(backup_dump('profiles') -> 'rows') r where r ? 'encrypted_password' or r ? 'email'));
reset role;
select tt.chk('F13 the module tables hold no secret-like column', not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name in ('ops_accounts','backup_runs','notifications','notification_reads') and column_name ~* '(password|secret|token)'));

select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
select 'FAIL ' || name from tt.res where not ok;
