-- PROPOSED FIXES for the findings of tests/sql/concurrency/CONCURRENCY_REPORT.md.
-- NOT applied to any phase file. Each block rebuilds one function from its current text (pg_get_functiondef) with a minimal textual change, so it can be
-- applied to the scratch DB the harness uses (tests/sql/concurrency/verify_fixes.sh does exactly that and re-runs the failing scenarios).
-- A later step should copy the changed lines into the latest phase text of each function (see "where" in the report) and keep every bosNN tag.
-- psql -f this file; each block fails loudly (assert) if the text to replace is not found.

\set ON_ERROR_STOP on
create or replace function pg_temp.patch(p_sig text, p_old text, p_new text, p_all boolean default false) returns text language plpgsql as $$
declare d text := pg_get_functiondef(p_sig::regprocedure); n int; r text;
begin
  n := (length(d) - length(replace(d, p_old, ''))) / greatest(length(p_old), 1);
  if n = 0 then raise exception 'patch text not found in %', p_sig; end if;
  if n > 1 and not p_all then raise exception 'patch text found % times in %', n, p_sig; end if;
  r := replace(d, p_old, p_new);
  execute r; return p_sig || ' patched (' || n || 'x)';
end $$;

-- F1  S04  production_post(7 args): the "not enough stock" check reads on_hand without a lock, so N cooks pass the check together and all go negative
--          (stock_negative_mode=warn + production_short_mode=refuse = the defaults). Lock the ingredient balance rows (item order, same as the later stock_post calls) BEFORE the check.
select pg_temp.patch('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)',
  $$  mode := coalesce(public.rule_txt('production_short_mode'), 'refuse');$$,
  $$  mode := coalesce(public.rule_txt('production_short_mode'), 'refuse');
  perform 1 from public.stock_balance sbl where sbl.location_id = p_loc and sbl.item_id in (select n2.item_id from public._recipe_need(r.id, p_batches, p_loc) n2) order by sbl.item_id for update;   -- bos104: serialise with other cooks / sales before the check$$);

-- F2  S09b  supplier lock "for update" -> "for no key update" (same mutual exclusion between posters, but it no longer conflicts with the FOR KEY SHARE lock that
--           inserting a purchase_bills / supplier_payments row takes on the supplier through its foreign key; scan_confirm(p_post) saves the bill and posts it in ONE transaction).
select pg_temp.patch('public._post_purchase_p13(uuid,jsonb)', 'from public.suppliers where id = pb.supplier_id for update;', 'from public.suppliers where id = pb.supplier_id for no key update;');
select pg_temp.patch('public._void_purchase_p13(uuid,text)',   'from public.suppliers where id = pb.supplier_id for update;', 'from public.suppliers where id = pb.supplier_id for no key update;');
select pg_temp.patch('public._bp_pay99(text,text,text,numeric,text,uuid,text,boolean)', 'from public.suppliers where id = pb.supplier_id for update;', 'from public.suppliers where id = pb.supplier_id for no key update;');
-- (the same one-word change belongs in pay_supplier, void_supplier_payment, supplier_refund, void_supplier_refund: they lock the same row the same way)

-- F3  S10  inbox_unmask: count-then-insert of the daily limit has no lock -> N parallel calls all see used < max. One advisory lock per user, held to the end of the transaction.
select pg_temp.patch('public.inbox_unmask(text,text,text)',
  $$  if lim is not null and not public.is_owner() then$$,
  $$  if lim is not null and not public.is_owner() then
    perform pg_advisory_xact_lock(hashtextextended('inbox_unmask:' || auth.uid()::text, 0));   -- bos104: the count below and the insert further down are one step per user$$);

-- F4  S13  set_option_view_bulk / set_role_option_view_bulk: rows are upserted in the order the client sent them; two owners sending the same keys in opposite order deadlock. Sort by key.
select pg_temp.patch('public.set_option_view_bulk(uuid,jsonb,uuid)', $$for it in select * from jsonb_array_elements(p_items) loop$$, $$for it in select e.value from jsonb_array_elements(p_items) e order by e.value->>'key' loop$$);
select pg_temp.patch('public.set_role_option_view_bulk(text,jsonb,uuid)', $$for it in select * from jsonb_array_elements(p_items) loop$$, $$for it in select e.value from jsonb_array_elements(p_items) e order by e.value->>'key' loop$$);

-- F5  S12b  setup_recommend_apply: with different client ids the first changed rule is "applied" (and audited) by every tapper. One apply at a time.
select pg_temp.patch('public.setup_recommend_apply(uuid,text[],boolean,boolean)',
  $$  perform public._client_lock(p_client);$$,
  $$  perform public._client_lock(p_client);
  perform pg_advisory_xact_lock(hashtextextended('setup_recommend_apply', 0));   -- bos104: a second tap with another client id waits, then sees the rules already set ('already')$$);

-- F6  S08  card_settle: "unsettled" is the GL balance of the card account, and the GL lags the books (acct_post_pending), so settlements that are saved but not yet posted are not
--          counted; the function only returns an `over` flag and never refuses. Count the not-yet-posted settlements, serialise per place, and refuse an over-settlement.
select pg_temp.patch('public.card_settle(integer,date,numeric,numeric,text,uuid,text)',
  $$  insert into public.card_settlements85 (client_id, location_id, settle_date, gross, fee, bank_mode, note, created_by, created_staff)$$,
  $$  perform pg_advisory_xact_lock(hashtextextended('card_settle:' || p_loc::text, 0));   -- bos104
  bal := bal - coalesce((select sum(c2.gross) from public.card_settlements85 c2 where c2.location_id = p_loc and c2.status = 'done'
                          and not exists (select 1 from public.journal_entries e where e.source_type = 'card_settlement' and e.source_id = c2.id::text and e.reverses_id is null)), 0);   -- bos104: saved but not yet booked
  if round(p_gross, 2) > bal then raise exception 'over_settlement' using detail = 'unsettled ' || bal::text, hint = 'card_settlement_list'; end if;   -- bos104 (or keep the old flag-only behaviour behind a rule)
  insert into public.card_settlements85 (client_id, location_id, settle_date, gross, fee, bank_mode, note, created_by, created_staff)$$);
