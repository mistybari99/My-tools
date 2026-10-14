-- Phase 96 (step D23): the two items step D left unbuilt.
-- Additive, paste-twice safe. Paste AFTER phase89 (which comes after phase91/92/93): this file re-creates functions from their latest definition (the phase89 bodies),
-- the file is produced by tests/sql/gen_phase96.py from a database built through phase89 - see the BODY GUARD below.
--
--   D2 OPENING STOCK HELPER   Before / when the switch acct_stock_opening is turned on: detect whether the opening stock is already inside the opening journal (acct_opening)
--                             = double count risk, and show per place: opening stock value, what the opening journal already carries on the inventory accounts, the GL inventory,
--                             the stock valuation and their difference.  Four ways to get the opening stock into the books (all built, the owner chooses; nothing is automatic):
--                               owner_capital     Dr inventory / Cr stock_opening_equity (owner capital 3100 unless re-pointed)
--                               existing_account  Dr inventory / Cr an existing opening balance account the owner names (equity or liability account)
--                               skip              already in the GL: only the decision is kept, nothing is posted, the switch will not post these openings
--                               difference        post only what the opening journal does not carry yet
--                             opening_stock_check96 (read only), opening_stock_preview96 (dry run, no writes), opening_stock_apply96 (OWNER ONLY, audited, idempotent by client id,
--                             one entry per place via je_source_uq), opening_stock_recommend96 (picks the best option from the numbers, never applies it).
--                             The phase85 posting of openings (switch acct_stock_opening) leaves out the opening rows a decision here already covers, so the same stock is never counted twice.
--   D3 COST WAITING           Stock moves that have no cost wait as cost_missing (wastage, production ingredients, count gains/losses, opening, own-use issue, transfers, purchase returns).
--                             cost_wait_list96 = the waiting list (documents awaiting cost, oldest first), cost_wait_preview96 (dry run), cost_wait_recommend96,
--                             cost_wait_supply96 (owner or cost-right holder supplies the cost: item_average | last_purchase | recipe_standard | manual with a reason; the ledger is NOT edited,
--                             the cost is kept in the append-only table ledger_cost_supply96 and the posting then reads it; the document posts ONCE, je_source_uq),
--                             cost_wait_alert96 + rule acct_cost_wait_alert_days (owner types the number; blank = no alert, no built-in number).
--                             Not done here: a finished good's stock AVERAGE cost cache is not changed (that needs a new ledger row); a document already posted with a partial cost is not re-posted.
-- Tag: bos96 marks every changed line inside a re-created function.

-- ---------- guard ----------
do $g$ begin
  if to_regprocedure('public._acct_stock_moves85(date)') is null or to_regprocedure('public._pvar85(uuid)') is null
     or to_regprocedure('public._acct_inv_split72(text[], text, text[], integer)') is null or to_regprocedure('public._cost_free80(uuid)') is null then
    raise exception 'phase96 needs phase85 (and phase80) pasted first';
  end if;
  if position('bos85' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) = 0 then
    raise exception 'phase96 needs phase85 pasted first (_acct_docs carries no bos85 line)';
  end if;
  if position('bos89' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) = 0 then
    raise exception 'phase96 needs phase89 pasted first (the re-created functions below are built on the phase89 bodies)';
  end if;
end $g$;

-- @@BODY_GUARD@@

-- ---------- the owner types the number (no built-in number): blank = no aging alert ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('acct_cost_wait_alert_days', 'books', 'number', null, 'days', null, 0, 3650,
  'খরচ (cost) ছাড়া পড়ে থাকা document কত দিন পর সতর্কতা (ফাঁকা = সতর্কতা বন্ধ)', 'Cost ছাড়া পড়ে থাকা document কত দিন পর alert (ফাঁকা = alert বন্ধ)', 'Alert when a document has waited for its cost longer than this many days (blank = no alert)',
  'সংখ্যাটি আপনি নিজে বসাবেন; সিস্টেমে কোনো ধরা সংখ্যা নেই। ফাঁকা থাকলে শুধু তালিকা দেখা যাবে, সতর্কতা আসবে না।', 'সংখ্যাটা আপনি নিজে দেবেন; system এ কোনো built-in সংখ্যা নেই। ফাঁকা থাকলে শুধু list দেখা যাবে, alert আসবে না।',
  'You type the number; there is no built-in value. Blank = the waiting list is shown but no alert is raised.', 961)
on conflict (key) do nothing;

-- ---------- D3: costs supplied for ledger rows that have none (the ledger itself is never edited) ----------
create table if not exists public.ledger_cost_supply96 (
  id bigint generated always as identity primary key,
  ledger_id bigint not null unique,                       -- no foreign key on purpose: a key into stock_ledger would stop the ledger's own truncate guard from answering first
  unit_cost numeric(18,6) not null check (unit_cost > 0 and unit_cost < 1000000000000),
  method text not null check (method in ('item_average', 'last_purchase', 'recipe_standard', 'manual', 'from_ingredients')),
  reason text, doc_kind text not null, doc_ref text not null, client_id uuid, basis jsonb,
  supplied_by uuid, supplied_staff text, supplied_at timestamptz not null default now(),
  constraint ledger_cost_supply96_reason check (method <> 'manual' or length(btrim(coalesce(reason, ''))) > 0));
create index if not exists ledger_cost_supply96_doc on public.ledger_cost_supply96 (doc_kind, doc_ref);
create index if not exists ledger_cost_supply96_client on public.ledger_cost_supply96 (client_id) where client_id is not null;
alter table public.ledger_cost_supply96 enable row level security;
revoke all on public.ledger_cost_supply96 from public, anon, authenticated;
drop trigger if exists ledger_cost_supply96_ro on public.ledger_cost_supply96;
create trigger ledger_cost_supply96_ro before update or delete on public.ledger_cost_supply96 for each row execute function public._ledger_immutable();
drop trigger if exists ledger_cost_supply96_nt on public.ledger_cost_supply96;
create trigger ledger_cost_supply96_nt before truncate on public.ledger_cost_supply96 for each statement execute function public._ledger_immutable();
drop trigger if exists audit_ledger_cost_supply96 on public.ledger_cost_supply96;
create trigger audit_ledger_cost_supply96 after insert on public.ledger_cost_supply96 for each row execute function public.log_change('id');

-- the ledger as the books read it: a supplied cost replaces a blank / zero cost. Closed to the browser (cost secrecy).
create or replace view public.stock_ledger_eff96 as
  select l.id, l.item_id, l.location_id, l.qty_delta,
         case when coalesce(l.unit_cost, 0) = 0 and s.unit_cost is not null then s.unit_cost else l.unit_cost end as unit_cost,
         l.reason, l.ref_type, l.ref_id, l.batch_id, l.reverses_id, l.client_id, l.made_at, l.note, l.created_by, l.created_at, (s.id is not null) as cost_supplied
  from public.stock_ledger l left join public.ledger_cost_supply96 s on s.ledger_id = l.id;
revoke all on public.stock_ledger_eff96 from public, anon, authenticated;

-- ---------- D2: what the owner decided about the opening stock (append-only, audited) ----------
create table if not exists public.opening_stock_actions96 (
  id bigint generated always as identity primary key,
  location_id int references public.locations(id),           -- null = company wide
  option text not null check (option in ('owner_capital', 'existing_account', 'skip', 'difference')),
  account_code text, amount numeric(18,2) not null default 0, entry_id bigint,
  covered_ids bigint[] not null default '{}',                -- the opening ledger rows this decision covers (costed ones for a post, all for a skip)
  reason text, client_id uuid unique, created_by uuid, created_staff text, created_at timestamptz not null default now());
create unique index if not exists opening_stock_actions96_one on public.opening_stock_actions96 (coalesce(location_id, 0)) where option <> 'skip';
alter table public.opening_stock_actions96 enable row level security;
revoke all on public.opening_stock_actions96 from public, anon, authenticated;
drop trigger if exists opening_stock_actions96_ro on public.opening_stock_actions96;
create trigger opening_stock_actions96_ro before update or delete on public.opening_stock_actions96 for each row execute function public._ledger_immutable();
drop trigger if exists opening_stock_actions96_nt on public.opening_stock_actions96;
create trigger opening_stock_actions96_nt before truncate on public.opening_stock_actions96 for each statement execute function public._ledger_immutable();
drop trigger if exists audit_opening_stock_actions96 on public.opening_stock_actions96;
create trigger audit_opening_stock_actions96 after insert on public.opening_stock_actions96 for each row execute function public.log_change('id');

