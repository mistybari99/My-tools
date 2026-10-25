-- FRESH DB ONLY. Phase 324 tests (CRM-G part 2: leads, notes, assign, stage moves, lost, reopen, quotes, the lead sheet).
--   build: phases 8..98, then 323 and 324;  psql -h /tmp -p 5575 -U postgres -d <db> -qAt -f supabase/phase324_test.sql 2>&1 | grep -E 'FAIL|RESULT'
\ir ../tests/sql/crmg_common.sql
select tt.books() as b0 \gset
insert into customers (mobile, name) values ('01712345601', 'test_crmg_customer') on conflict do nothing;

\echo == T0 module OFF by default: every call is refused, nothing is written
set role authenticated; select tt.as(:'u_s1');
select tt.err('T0 save while OFF', $$select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_a"}')$$, 'module_off');
select tt.err('T0 get while OFF', $$select _crmg_lead_get(gen_random_uuid())$$, 'module_off');
select tt.chk('T0 no lead exists', tt.q('select count(*) from crm_leads') = '0');
reset role;
select tt.as(:'u_o');
set role authenticated;
select set_rule('crm_lead_on', 'true') is null as on1 \gset

\echo == T1 create, rights, outlets, idempotence
select tt.as(:'u_s1');
select gen_random_uuid() as k1 \gset
select _crmg_lead_save(null, :'k1'::uuid, 1, '{"contact_name":"test_party_one","contact_phone":"01812345678","source":"phone","occasion":"wedding","event_date":"2030-01-20","guests":120,"est_value":50000}') as r1 \gset
select (:'r1'::jsonb ->> 'id') as l1 \gset
select tt.chk('T1 a salesperson creates an enquiry for her outlet, stage enquiry, she is the assignee',
  tt.q($q$select stage || '/' || (owner_user = '00000000-0000-0000-0000-000000003203')::text || '/' || contact_phone from crm_leads where id = '$q$ || :'l1' || $q$'$q$) = 'enquiry/true/01812345678');
select tt.chk('T1 the same client key again returns the same enquiry', (_crmg_lead_save(null, :'k1'::uuid, 1, '{"contact_name":"test_party_one"}') ->> 'id') = :'l1' and tt.q('select count(*) from crm_leads') = '1');
select tt.err('T1 an outlet the person does not work at is refused', $$select _crmg_lead_save(null, gen_random_uuid(), 2, '{"contact_name":"test_b"}')$$, 'not allowed');
select tt.err('T1 a name is required', $$select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_phone":"01812345678"}')$$, 'contact_name_required');
select tt.err('T1 an unknown source is refused', $$select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_b","source":"test_nowhere"}')$$, 'unknown_source');
select tt.err('T1 an unknown occasion is refused', $$select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_b","occasion":"test_nope"}')$$, 'unknown_occasion');
select tt.err('T1 a bad phone is refused', $$select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_b","contact_phone":"12ab"}')$$, 'bad_phone');
select tt.err('T1 a bad date is refused', $$select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_b","event_date":"31-31-31"}')$$, 'bad_date');
select tt.err('T1 guests out of range', $$select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_b","guests":0}')$$, 'bad_guests');
select tt.err('T1 a plain salesperson cannot give an enquiry to someone else', format($$select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_b","owner_user":"%s"}')$$, :'u_s1b'), 'only a manager');
select tt.as(:'u_x');
select tt.err('T1 a person with no sales right cannot create', $$select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_b"}')$$, 'not allowed');
select tt.as(:'u_s2');
select _crmg_lead_save(null, gen_random_uuid(), 2, '{"contact_name":"test_branch_two","source":"walk_in"}') ->> 'id' as l2 \gset
select tt.chk('T1 the other outlet creates its own enquiry', :'l2' is not null and tt.q('select count(*) from crm_leads') = '2');
select tt.as(:'u_m1');
select _crmg_lead_save(null, gen_random_uuid(), 1, format('{"contact_name":"test_party_two","contact_phone":"01712345601","owner_user":"%s"}', :'u_s1b')::jsonb) as r3 \gset
select (:'r3'::jsonb ->> 'id') as l3 \gset
select tt.chk('T1 a manager gives an enquiry to a colleague', tt.q($q$select (owner_user = '00000000-0000-0000-0000-000000003204')::text from crm_leads where id = '$q$ || :'l3' || $q$'$q$) = 'true');
select tt.chk('T1 the mobile of an existing customer links the customer', tt.q($q$select (customer_id = (select id from customers where mobile = '01712345601'))::text from crm_leads where id = '$q$ || :'l3' || $q$'$q$) = 'true');
select tt.err('T1 an assignee from another outlet is refused', format($$select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_b","owner_user":"%s"}')$$, :'u_s2'), 'assignee_not_at_outlet');
select (_crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_party_dup","contact_phone":"01812345678"}')) -> 'same_phone_open_leads' as dups \gset
select tt.chk('T1 an open enquiry with the same phone at the same outlet is reported', jsonb_array_length(:'dups'::jsonb) = 1);

\echo == T2 who can see what (other outlet, same outlet colleague, head office, grant)
select tt.as(:'u_s1b');
select tt.err('T2 a colleague of the same outlet cannot see an enquiry that is not hers', format($$select _crmg_lead_get('%s')$$, :'l1'), 'not_found');
select tt.chk('T2 she sees the one given to her', (_crmg_lead_get(:'l3'::uuid) -> 'lead' ->> 'contact_name') = 'test_party_two');
select tt.as(:'u_m2');
select tt.err('T2 a manager of another outlet gets not_found, no hint it exists', format($$select _crmg_lead_get('%s')$$, :'l1'), 'not_found');
select tt.as(:'u_hq');
select tt.err('T2 head office without the right to see all gets not_found', format($$select _crmg_lead_get('%s')$$, :'l1'), 'not_found');
select tt.as(:'u_m1');
select tt.chk('T2 the manager of the outlet sees it with the manager buttons', (_crmg_lead_get(:'l1'::uuid) -> 'can' ->> 'assign')::boolean and (_crmg_lead_get(:'l1'::uuid) -> 'can' ->> 'close_lost')::boolean);
select tt.as(:'u_s1');
select tt.chk('T2 the assignee sees it without the manager buttons', not (_crmg_lead_get(:'l1'::uuid) -> 'can' ->> 'assign')::boolean and not (_crmg_lead_get(:'l1'::uuid) -> 'can' ->> 'close_lost')::boolean and (_crmg_lead_get(:'l1'::uuid) -> 'can' ->> 'note')::boolean);
select tt.as(:'u_o');
reset role; insert into user_grants (user_id, grant_code, location_id) values (:'u_hq', 'crm_lead_all', null) on conflict do nothing; set role authenticated;
select tt.as(:'u_hq');
select tt.chk('T2 a holder of the right to see every outlet sees both outlets', (_crmg_lead_get(:'l1'::uuid) -> 'lead' ->> 'contact_name') = 'test_party_one' and (_crmg_lead_get(:'l2'::uuid) -> 'lead' ->> 'contact_name') = 'test_branch_two');

\echo == T3 phone privacy follows the customer package guard when it exists
reset role;
insert into rules (key, module, kind, default_value, label_bn, label_en) values ('crm_pii_guard_on', 'crm', 'switch', 'true'::jsonb, 'test guard', 'test guard') on conflict (key) do update set default_value = 'true'::jsonb;
set role authenticated; select tt.as(:'u_hq');
select tt.chk('T3 guard ON: a viewer who is neither owner, assignee nor holder of the contact right sees a masked phone', (_crmg_lead_get(:'l1'::uuid) -> 'lead' ->> 'contact_phone') = '018******78');
select tt.as(:'u_s1');
select tt.chk('T3 the assignee sees the real phone', (_crmg_lead_get(:'l1'::uuid) -> 'lead' ->> 'contact_phone') = '01812345678');
reset role; update rules set default_value = 'false'::jsonb where key = 'crm_pii_guard_on'; set role authenticated;

\echo == T4 notes
select tt.as(:'u_s1');
select _crmg_lead_note(:'l1'::uuid, 'call', 'test_called, wants a 3 kg cake') ->> 'noted' as n1 \gset
select tt.chk('T4 the assignee writes a call note', :'n1' = 'true' and tt.q($q$select count(*) from crm_lead_events where kind = 'note' and detail->>'activity' = 'call'$q$) = '1');
select tt.err('T4 a bad kind', format($$select _crmg_lead_note('%s', 'letter', 'x')$$, :'l1'), 'bad_note_kind');
select tt.err('T4 an empty note', format($$select _crmg_lead_note('%s', 'note', '   ')$$, :'l1'), 'note_required');
select tt.as(:'u_s1b');
select tt.err('T4 a colleague who cannot see the enquiry cannot write on it', format($$select _crmg_lead_note('%s', 'note', 'x')$$, :'l1'), 'not_found');

\echo == T5 assign
select tt.as(:'u_s1');
select tt.err('T5 a salesperson cannot reassign', format($$select _crmg_lead_assign('%s', '%s')$$, :'l1', :'u_s1b'), 'only a manager');
select tt.as(:'u_m1');
select tt.err('T5 not to a person of another outlet', format($$select _crmg_lead_assign('%s', '%s')$$, :'l1', :'u_s2'), 'assignee_not_at_outlet');
select _crmg_lead_assign(:'l1'::uuid, :'u_s1b'::uuid, 'test_busy') ->> 'owner_user' as a1 \gset
select tt.chk('T5 the manager reassigns, the trail says who to whom', :'a1' = :'u_s1b' and tt.q($q$select count(*) from crm_lead_events where kind = 'assign'$q$) = '1');
select tt.chk('T5 assigning to the same person changes nothing', (_crmg_lead_assign(:'l1'::uuid, :'u_s1b'::uuid) ->> 'noop')::boolean);
select _crmg_lead_assign(:'l1'::uuid, :'u_s1'::uuid) is not null as back \gset

\echo == T6 stage moves
select tt.as(:'u_s1');
select tt.err('T6 quoted needs a sent quote first', format($$select _crmg_lead_stage('%s', 'quoted')$$, :'l1'), 'quote_needed');
select tt.err('T6 an unknown stage', format($$select _crmg_lead_stage('%s', 'sold')$$, :'l1'), 'bad_stage');
select tt.chk('T6 moving to the stage it is already in changes nothing', (_crmg_lead_stage(:'l1'::uuid, 'enquiry') ->> 'noop')::boolean);
select _crmg_lead_stage(:'l1'::uuid, 'following_up', 'test_will call back', jsonb_build_object('follow_up', (now() + interval '2 days')::text)) ->> 'stage' as s1 \gset
select tt.chk('T6 the assignee moves it to following up with a follow-up time', :'s1' = 'following_up' and tt.q($q$select (next_follow_up is not null)::text from crm_leads where id = '$q$ || :'l1' || $q$'$q$) = 'true');
select tt.err('T6 by default only a manager may close as lost', format($$select _crmg_lead_stage('%s', 'lost', 'x', '{"lost_reason":"no_reply"}')$$, :'l1'), 'only a manager');
select tt.as(:'u_m1');
select tt.err('T6 lost needs a reason', format($$select _crmg_lead_stage('%s', 'lost')$$, :'l1'), 'lost_reason_required');
select tt.err('T6 a reason not in the list is refused', format($$select _crmg_lead_stage('%s', 'lost', 'x', '{"lost_reason":"test_whim"}')$$, :'l1'), 'lost_reason_required');
select tt.err('T6 the reason Other needs a note', format($$select _crmg_lead_stage('%s', 'lost', '', '{"lost_reason":"other"}')$$, :'l1'), 'lost_note_required');
select tt.chk('T6 nothing changed after the refusals', tt.q($q$select stage from crm_leads where id = '$q$ || :'l1' || $q$'$q$) = 'following_up');
select _crmg_lead_stage(:'l1'::uuid, 'lost', 'test_chose another shop', '{"lost_reason":"other_shop"}') ->> 'stage' as s2 \gset
select tt.chk('T6 a manager closes it as lost with a listed reason; follow-up cleared', :'s2' = 'lost' and tt.q($q$select lost_reason || '/' || coalesce(next_follow_up::text,'none') || '/' || (closed_at is not null)::text from crm_leads where id = '$q$ || :'l1' || $q$'$q$) = 'other_shop/none/true');
select tt.err('T6 lost to won is an illegal jump', format($$select _crmg_lead_stage('%s', 'won')$$, :'l1'), 'illegal_stage_move');
select tt.err('T6 lost to enquiry is an illegal jump (reopen is the only way)', format($$select _crmg_lead_stage('%s', 'enquiry')$$, :'l1'), 'illegal_stage_move');
select tt.err('T6 a lost enquiry cannot be edited', format($$select _crmg_lead_save('%s', null, 1, '{"guests":5}')$$, :'l1'), 'lead_closed');

\echo == T7 reopen with a reason (an exception)
select tt.as(:'u_s1');
select tt.err('T7 a salesperson cannot reopen', format($$select _crmg_lead_reopen('%s', 'test_customer came back')$$, :'l1'), 'only a manager');
select tt.as(:'u_m1');
select tt.err('T7 a reopen needs a reason', format($$select _crmg_lead_reopen('%s', 'ab')$$, :'l1'), 'reason_required');
select tt.err('T7 only a lost enquiry can be reopened', format($$select _crmg_lead_reopen('%s', 'test_customer came back')$$, :'l3'), 'not_lost');
select tt.err('T7 it reopens only to enquiry or following up', format($$select _crmg_lead_reopen('%s', 'test_customer came back', 'won')$$, :'l1'), 'bad_stage');
select tt.as(:'u_o'); select set_rule('crm_lead_reopen_mode', '"owner"') is null as m1 \gset
select tt.as(:'u_m1');
select tt.err('T7 mode owner: a manager is refused', format($$select _crmg_lead_reopen('%s', 'test_customer came back')$$, :'l1'), 'only the owner');
select tt.as(:'u_o'); select set_rule('crm_lead_reopen_mode', '"off"') is null as m2 \gset
select tt.err('T7 mode off: even the owner is refused', format($$select _crmg_lead_reopen('%s', 'test_customer came back')$$, :'l1'), 'reopen_off');
select set_rule('crm_lead_reopen_mode', '"reason"') is null as m3 \gset
select tt.as(:'u_m1');
select _crmg_lead_reopen(:'l1'::uuid, 'test_customer came back') ->> 'stage' as s3 \gset
select tt.chk('T7 reopened: stage enquiry, lost reason cleared, counted, the old reason kept in the trail',
  :'s3' = 'enquiry' and tt.q($q$select reopened_count::text || '/' || coalesce(lost_reason,'none') from crm_leads where id = '$q$ || :'l1' || $q$'$q$) = '1/none'
  and tt.q($q$select detail->>'was_lost_because' from crm_lead_events where kind = 'reopen'$q$) = 'other_shop');
select tt.chk('T7 the Exceptions list and the audit log have the reopen with its reason',
  tt.q($q$select count(*) from money_exceptions where kind = 'crmg_lead_reopen' and reason = 'test_customer came back'$q$) = '1' and tt.q($q$select count(*) from audit_log where action = 'exception' and detail->>'kind' = 'crmg_lead_reopen'$q$) = '1');
select tt.chk('T7 it can be lost again', (_crmg_lead_stage(:'l1'::uuid, 'lost', '', '{"lost_reason":"price_high"}') ->> 'stage') = 'lost');

\echo == T8 quotes
select tt.as(:'u_o');
select tt.as(:'u_m1');
select _crmg_lead_save(null, gen_random_uuid(), 1, format('{"contact_name":"test_quote_lead","contact_phone":"01912345678","event_date":"%s","guests":40}', current_date + 10)::jsonb) ->> 'id' as q1 \gset
select tt.err('T8 a quote needs lines', format($$select _crmg_quote_save('%s', null, '{"items":[]}')$$, :'q1'), 'no_items');
select tt.err('T8 a line without an item or a description', format($$select _crmg_quote_save('%s', null, '{"items":[{"qty":1,"price":5}]}')$$, :'q1'), 'line_needs_item_or_description');
select tt.err('T8 an item without a list price needs a typed price', format($$select _crmg_quote_save('%s', null, '{"items":[{"item_id":"%s","qty":1}]}')$$, :'q1', :'inp'), 'price_required');
select tt.err('T8 a bad quantity', format($$select _crmg_quote_save('%s', null, '{"items":[{"desc":"test_x","qty":0,"price":5}]}')$$, :'q1'), 'bad_qty');
select tt.err('T8 a discount above the lines', format($$select _crmg_quote_save('%s', null, '{"items":[{"desc":"test_x","qty":1,"price":5}],"discount":6}')$$, :'q1'), 'bad_discount');
select _crmg_quote_save(:'q1'::uuid, null, format('{"items":[{"item_id":"%s","qty":2},{"desc":"test_box","qty":1,"price":50}],"discount":20}', :'ia')::jsonb) as d1 \gset
select tt.chk('T8 a draft: item price 100 x 2 + 50 = 250, discount 20, total 230, no validity needed, enquiry stays enquiry',
  (:'d1'::jsonb ->> 'total')::numeric = 230 and (:'d1'::jsonb ->> 'status') = 'draft' and (:'d1'::jsonb ->> 'stage') = 'enquiry' and tt.q($q$select stage from crm_leads where id = '$q$ || :'q1' || $q$'$q$) = 'enquiry');
select tt.err('T8 sending needs a validity date (setting blank)', format($$select _crmg_quote_save('%s', null, jsonb_build_object('quote_id','%s','items','[{"desc":"test_x","qty":1,"price":5}]'::jsonb,'send',true))$$, :'q1', :'d1'::jsonb ->> 'quote_id'), 'validity_required');
select tt.err('T8 a past validity needs a reason (late quote)', format($$select _crmg_quote_save('%s', null, jsonb_build_object('items','[{"desc":"test_x","qty":1,"price":5}]'::jsonb,'send',true,'valid_until',(current_date - 1)::text))$$, :'q1'), 'reason_required');
select tt.chk('T8 nothing was sent by the refusals', tt.q($q$select count(*) from crm_lead_quotes where status = 'sent'$q$) = '0');
select _crmg_quote_save(:'q1'::uuid, null, jsonb_build_object('quote_id', :'d1'::jsonb ->> 'quote_id', 'items', format('[{"item_id":"%s","qty":2},{"desc":"test_box","qty":1,"price":50}]', :'ia')::jsonb, 'discount', 20, 'send', true, 'valid_until', (current_date + 7)::text, 'note', 'test_terms')) as s5 \gset
select tt.chk('T8 sent: version 1, status sent, the enquiry is now Quoted, estimate filled from the total',
  (:'s5'::jsonb ->> 'status') = 'sent' and (:'s5'::jsonb ->> 'stage') = 'quoted' and (:'s5'::jsonb ->> 'version') = '1' and tt.q($q$select est_value from crm_leads where id = '$q$ || :'q1' || $q$'$q$)::numeric = 230);
select tt.err('T8 a sent quote cannot be edited, only replaced', format($$select _crmg_quote_save('%s', null, jsonb_build_object('quote_id','%s','items','[{"desc":"test_x","qty":1,"price":5}]'::jsonb))$$, :'q1', :'s5'::jsonb ->> 'quote_id'), 'quote_sent');
select _crmg_quote_save(:'q1'::uuid, null, jsonb_build_object('items','[{"desc":"test_cake","qty":1,"price":900}]'::jsonb,'send',true,'valid_until',(current_date + 10)::text)) as s6 \gset
select tt.chk('T8 a new version supersedes the old one', (:'s6'::jsonb ->> 'version') = '2' and tt.q($q$select status from crm_lead_quotes where lead_id = '$q$ || :'q1' || $q$' and version = 1$q$) = 'superseded');
select tt.as(:'u_o'); select set_rule('crm_lead_quote_valid_days', '14') is null as v1 \gset
select tt.as(:'u_m1');
select _crmg_quote_save(:'q1'::uuid, null, '{"items":[{"desc":"test_cake","qty":1,"price":950}],"send":true}') as s7 \gset
select tt.chk('T8 with a default validity setting the date is filled as today + 14', (:'s7'::jsonb ->> 'valid_until')::date = current_date + 14 or (:'s7'::jsonb ->> 'valid_until')::date = (now() at time zone 'Asia/Dhaka')::date + 14);
select tt.as(:'u_o'); select set_rule('crm_quote_min_lead_days', '30') is null as v2 \gset
select tt.as(:'u_m1');
select tt.err('T8 setting: an event closer than the minimum needs a reason', format($$select _crmg_quote_save('%s', null, '{"items":[{"desc":"test_cake","qty":1,"price":960}],"send":true}')$$, :'q1'), 'reason_required');
select _crmg_quote_save(:'q1'::uuid, null, '{"items":[{"desc":"test_cake","qty":1,"price":960}],"send":true,"late_reason":"test_customer asked late"}') ->> 'status' as s8 \gset
select tt.chk('T8 with a reason the late quote goes out and is on the Exceptions list', :'s8' = 'sent' and tt.q($q$select count(*) from money_exceptions where kind = 'crmg_late_quote' and reason = 'test_customer asked late'$q$) = '1'
  and tt.q($q$select late_reason from crm_lead_quotes where lead_id = '$q$ || :'q1' || $q$' and version = 4$q$) = 'test_customer asked late');
select tt.as(:'u_o'); select set_rule('crm_quote_min_lead_days', null) is null as v3 \gset
select tt.as(:'u_m1');
select tt.err('T8 answering an unknown quote', $$select _crmg_quote_respond(gen_random_uuid(), 'accepted')$$, 'not_found');
select tt.chk('T8 one live quote only: older sent versions are superseded', tt.q($q$select count(*) from crm_lead_quotes where lead_id = '$q$ || :'q1' || $q$' and status = 'sent'$q$) = '1');

\echo == T9 win rules
select tt.as(:'u_s1b');
select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_win_lead"}') ->> 'id' as w1 \gset
select _crmg_lead_stage(:'w1'::uuid, 'won') ->> 'stage' as w1s \gset
select tt.chk('T9 default: an enquiry can be won without a quote', :'w1s' = 'won');
select tt.err('T9 a won enquiry is final', format($$select _crmg_lead_stage('%s', 'enquiry')$$, :'w1'), 'illegal_stage_move');
select tt.err('T9 a won enquiry cannot be edited', format($$select _crmg_lead_save('%s', null, 1, '{"guests":3}')$$, :'w1'), 'lead_closed');
select tt.as(:'u_o'); select set_rule('crm_lead_win_needs_quote', 'true') is null as wq \gset
select tt.as(:'u_s1b');
select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_win_lead2"}') ->> 'id' as w2 \gset
select tt.err('T9 setting ON: a salesperson cannot win without a sent quote', format($$select _crmg_lead_stage('%s', 'won')$$, :'w2'), 'quote_needed_to_win');
select tt.as(:'u_m1');
select tt.err('T9 setting ON: a manager needs a written reason', format($$select _crmg_lead_stage('%s', 'won')$$, :'w2'), 'reason_required');
select _crmg_lead_stage(:'w2'::uuid, 'won', null, '{"reason":"test_deal made on the phone"}') ->> 'stage' as w2s \gset
select tt.chk('T9 with a reason it is won and the exception is listed', :'w2s' = 'won' and tt.q($q$select count(*) from money_exceptions where kind = 'crmg_win_without_quote'$q$) = '1');
select _crmg_lead_stage(:'q1'::uuid, 'won') ->> 'stage' as w3 \gset
select tt.chk('T9 with a sent quote it is won without a reason; the sent quote is marked accepted', :'w3' = 'won' and tt.q($q$select status from crm_lead_quotes where lead_id = '$q$ || :'q1' || $q$' and version = 4$q$) = 'accepted');
select tt.as(:'u_o'); select set_rule('crm_lead_win_needs_quote', 'false') is null as wq2 \gset

\echo == T10 the lead sheet, the trail, and the books
select tt.as(:'u_m1');
select _crmg_lead_get(:'q1'::uuid) as g1 \gset
select tt.chk('T10 the sheet holds the lead, four quotes (newest first) and the trail', jsonb_array_length(:'g1'::jsonb -> 'quotes') = 4);
select tt.chk('T10 the first quote of the sheet is the newest version', (:'g1'::jsonb -> 'quotes' -> 0 ->> 'version')::int = 4);
select tt.chk('T10 the trail shows created, quote and stage events', (select count(distinct x ->> 'kind') from jsonb_array_elements(:'g1'::jsonb -> 'events') x) >= 3);
reset role;
select tt.chk('T10 the audit log has the lead changes', tt.q($q$select count(*) from audit_log where table_name = 'crm_leads'$q$)::int >= 10);
select tt.chk('T10 NOTHING in the books changed: journal, sales, payments, stock, cash moves', tt.books() = :'b0');
select tt.chk('T10 no earlier order or form was created by a lead', tt.q('select count(*) from online_orders') = '0' and tt.q('select count(*) from entries where form_code in (''20-1'',''20-4'')') = '0');
select 'RESULT ' || count(*) filter (where ok) || ' pass ' || count(*) filter (where not ok) || ' fail' from tt.res;
