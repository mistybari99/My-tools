# A5 - Factory-to-branch reconciliation (stage 1-2: audit + gap analysis)

Branch `audit/a5`, final DB = canonical order `docs/PASTE_ORDER.md` (phases 72..111) built by `tests/sql/final_build.sh` on scratch Postgres 16 (port 5544).
No SQL or web code was changed. Evidence scripts: `tests/sql/audit2/a5/` (`run.sh <db>` runs `a5_01_main.sql`, `a5_01b_statement.sql`, `a5_02_edges.sql` in one session on top of `tests/sql/e2e/00_common.sql`; last output `a5_last_output.txt`).
Hand-computed expectations are in the first lines of each script (written before the first run). Result: **101 checks, 90 PASS, 11 FAIL**; every FAIL is a finding below (none is a test mistake after the fixes noted in section 8).
Test data only, no real names. Locations: 1 = factory/main centre, 2 = branch A, 3 = branch B, 4 = outsider branch. Assumptions are marked **[ASSUMPTION]**.

## 1. Verdict in 8 lines

1. Core stock movement is correct and well protected: send (OUT at once at weighted average), in-transit, receive (IN at the sender's cost, batch + expiry travel), cancel, over-receive refused, duplicate client id idempotent, location rights enforced.
2. The money side is correct in the default and in `location_tagged` mode: clearing 1230 nets to 0 company-wide, transit loss goes to 5130, branch profit uses the transferred cost (A 14,460, B 9,125 = hand numbers).
3. The owner's whole example reconciles to the kg: made 100 - sold 65 - short 2 - wasted 2 = 31 = 13 + 5 + 13, in transit 0.
4. But nobody can SEE this: there is **no factory-to-branch statement** (sent / received / short / sold / returned / wasted / remaining per branch per period). Only an exception list (`transfers_gap`) exists. A prototype from existing tables took one query (a5_01b) and matched all hand numbers.
5. A **second receive is silently ignored** (first receive closes the transfer): partial deliveries (two lorries) leave the rest "short" for ever.
6. `transit_short_mode = loss` and `transit_short_resolve` **corrupt the GL** when transfers are location-tagged: phantom inventory (+150 / +200 in the test) and the loss entry stuck in `cost_missing`.
7. "Return to factory" is just a reverse transfer: no reason, no link to the original, no factory acknowledgement trail; the branch's blended cost leaks into the factory average.
8. Phone flow for the branch manager: 4 taps with no typing when the full quantity arrived, but nothing tells the branch that goods are on the way (no notification on send, no badge).

## 2. Code map (what exists, final-DB function bodies)

| Area | Object (file:line of the latest definition) | Notes |
|---|---|---|
| Send | `stock_transfer(from,to,item,qty,unit,note,client)` phase10.sql:669 | one item per call = one `stock_transfers` row; OUT at once via `stock_post(... 'transfer_out', 'full')` at sender's avg cost; guard = `_stock_guard` (sender location only), `_may('stock_transfer')`, idempotent on `client_id` |
| Receive | `stock_receive_transfer(id, received_qty, note)` phase89.sql:1886 (merged body, phase83 loss mode at :1922) | `received_qty` default = all; > sent raises `over_received`; < sent writes a yellow exception `transit_short`; IN at the OUT row's unit_cost; new batch row at destination with the same `made_at` / `expires_at`; **status becomes `received` after the first call** |
| Cancel | `stock_cancel_transfer` phase10.sql:735 | sender / owner / holder of grant; reversal rows; only while `sent` |
| In transit | `stock_in_transit` phase10.sql:813; `transit_open_list` phase83.sql:570 (hours, `over_limit`); `_transit_open_scan83` phase83.sql (owner notification when older than `transit_open_hours`, via `urgent_alerts`) | |
| Short | `transit_short_open` phase83.sql:538; `transit_short_resolve` :554; `_transit_loss83` :61; rule `transit_short_mode` (`keep_in_transit` default / `loss`); reason `transit_loss` in `stock_ledger` | |
| GL | `_acct_stock_moves85` + `_acct_docs` phase85.sql:150-170, 424-446 (final text merged in phase89/96/97/98/103/110); rules `acct_transfer_mode` (off / location_tagged / company_wide), `acct_transit_loss`, `acct_transit_loss_at` (receiver / sender); accounts 1230 `interloc_clearing`, 5130 `transit_loss` | everything default OFF |
| Forms | form `03-1` Transfer Challan (IBT) -> `_elp_post_line` phase83.sql:92 (`kind='transfer'` ~:200); `entry_post_ledger`; `unmatched_forms`; path switch `path_primary('stock_transfer')` (phase51) | `05-x` = factory daily sheet / spec / recipe, `06-x` = purchasing: they are NOT transfer forms |
| Production | `production_post(loc, recipe, batches, ...)` posts `production_in` into the location given (batch with expiry from `shelf_life_rules`) | no "factory" kind check; factory = any location the user may use |
| Branch sale | `record_sale2` -> `stock_post(... 'sale_out')` at the branch avg cost (FEFO batches) | |
| Waste / expiry | `stock_wastage` (`_wastage_post`), `stock_expire_batch`, `expiry_list`, `near_expiry_report` | |
| Levels | `stock_levels(p_loc, filters)` per location, no in-transit column; `stock_reconcile` ledger vs cache | |
| Reports | `transfers_gap` (phase21.sql:280, in `report_run2`) = list of transfers still `sent` or received short | the only transfer report |
| Print | template `stock_transfer` (web/tpl_docs.js:75: no, date, from, to, vehicle, items, 3 signatures) | **no caller**: `web/stock2.js` never prints it; vehicle/driver/challan no. are not stored |
| UI | `web/stock2.js` `#/stock` tabs levels / expiring / transit (loadTransit :323, recvSheet :504, receive :542, cancel :546); owner screen `#/transitshort` (web/formscreens.js:143) | online only, no outbox for transfers |

## 3. Scenario results (hand numbers vs run)

Scenario: factory (1) produces 100 kg sweet; send 60 -> A, 30 -> B; A receives 58, B receives 30; A sells 40, returns 3 to factory, wastes 2; B sells 25. Cost: recipe 350 per 10 kg = 35/kg. Accounting on, `acct_transfer_mode = location_tagged`, `acct_transit_loss = true`.

| Check | Hand | Run | Evidence |
|---|---|---|---|
| Factory qty / avg after production | 100 / 35 | 100 / 35 | P1, P2 |
| Factory after send | 10 | 10 | M1 |
| A holds before receive | 0 | 0 | M2 |
| In transit after send | 90 | 90 | M3 |
| Cost on the OUT row | 35 | 35 | M4 |
| Clearing 1230 at factory after send | Dr 3,150 | 3,150 | G1 |
| A after receive of 58 / B after 30 | 58 / 30 | 58 / 30 | M5 M6 |
| A average cost carried | 35 | 35 | M7 |
| short returned, flag, list, value | 2, yellow flag, 2 kg, 70 | 2, yes, 2, 70 | M8 M10-M12 |
| In transit after receipts | 0 | 0 | M9 |
| A remaining (58-40-3-2) | 13 | 13 | Q1 |
| B remaining (30-25) | 5 | 5 | Q2 |
| Factory remaining (10+3) | 13 | 13 | Q3 |
| Company stock | 31 | 31 | Q4 Q5 |
| Clearing 1230: factory / A / B / company | +3,045 / -1,995 / -1,050 / 0 | same | G2-G5 |
| 5130 transit loss | Dr 70 at receiver A | 70 at loc 2 | G6 G7 |
| Unbalanced journal entries | 0 | 0 | G8 |
| Inventory GL vs stock valuation | 0 diff (1,085 = 31 x 35) | 0 | `inventory_vs_gl` |
| Profit A = 16,000 - 1,400 COGS - 70 waste - 70 transit loss | 14,460 | 14,460 | `acct_income_statement(.., 2)` |
| Profit B = 10,000 - 875 | 9,125 | 9,125 | `acct_income_statement(.., 3)` |
| `stock_reconcile` | 0 differences | 0 | E13a |

Per-branch statement prototype (a5_01b_statement.sql, plain SQL over `stock_transfers`, `stock_ledger`, `stock_balance`):

| place | made | sent_in | received | short | returned out | sold | wasted | remaining |
|---|---|---|---|---|---|---|---|---|
| 1 factory | 100 | 3 (returns) | 3 | 0 | 90 | 0 | 0 | 13 |
| 2 branch A | 0 | 60 | 58 | 2 | 3 | 40 | 2 | 13 |
| 3 branch B | 0 | 30 | 30 | 0 | 0 | 25 | 0 | 5 |

Identities hold: A 58-3-40-2 = 13; B 30-25 = 5; factory 100-90+3 = 13; company 100-65-2-2 = 31 = 13+13+5 (ST-A1..ST-C2 all PASS).

## 4. Check list with verdicts

PASS / FAIL / NOT SUPPORTED. "FAIL" = differs from the business expectation of the brief (some are configurable defaults, called out).

### 4.1 Movement and reconciliation

| # | Check | Verdict | Evidence |
|---|---|---|---|
| C1 | Sent quantity recorded per branch, cost at weighted average at send | PASS | `stock_transfer` phase10.sql:669; M4 cost 35 |
| C2 | Goods in transit are neither at sender nor receiver, visible | PASS | M1-M3; `stock_in_transit` |
| C3 | Receive adds exactly the received quantity at the sender's cost; batch/expiry travel | PASS | M5 M7; E11a/E11b (8 kg batch, same made_at and expires_at as the factory batch) |
| C4 | Short receipt flagged and valued | PASS | M8 M10 M12 (value 70) |
| C5 | Company-wide reconciliation sent = received + short + in transit | PASS (data), NOT SUPPORTED (screen) | identities in section 3; see C20 |
| C6 | Branch sale uses transferred cost | PASS | COGS A 1,400 = 40 x 35 |
| C7 | Wastage at branch at transferred cost, in branch P&L | PASS | 5100 Dr 70 at A (IS_A) |
| C8 | Expiry write-off at branch | PASS | E11c-E11e: 8 kg x 40 = 320 at A |
| C9 | Return to factory | PARTIAL: PASS as stock+GL (reverse transfer, 3 kg x 35 = 105 clearing), NOT SUPPORTED as a business document (no reason, no link to the sent transfer, no return flag, no "damaged / expired / excess" split) | `stock_transfers` has no `kind`/`reason`/`ref_transfer` column; prototype had to infer "return" from direction |
| C10 | Customer sale return at branch is separate and not confused with C9 | PASS | `sale_return` (reason `sale_return`), not a transfer |
| C11 | Repeated partial receives (20 sent, 8 then 12) | **FAIL** | E1a-E1d: first receive closes the row (`status='received'`, received_qty 8); second call returns `{dup:true}`, A stays 8 (expected 20); the 12 stay "short" until written off |
| C12 | Receive without a send | PASS | E2a `not found` |
| C13 | Receive by a user without access to the destination | PASS | E2b `not allowed for this location` |
| C14 | Over-receive / negative | PASS | E3a `over_received`, E3b `bad_qty` |
| C15 | Receive 0 (nothing arrived) | PASS (closes as 100% short; no separate "rejected" status) | E3c short 10 |
| C16 | Cancelled transfer: stock back, no double receive, GL nets 0 | PASS | E2d E2e E2f; E2g E2h (out + reversal, 1230 nets 0) |
| C17 | Receiver cannot cancel the sender's transfer | PASS | E2c |
| C18 | Sender without access to source location | PASS | E4a |
| C19 | Send to a location the sender cannot access | PASS by design (cross-branch send is the point); no approval step | E4b |
| C19a | Send to a CLOSED location | PASS | E4c trigger `_loc_closed_guard` (phase16.sql:472) -> `location_paused:closed` |
| C19b | Send to a PAUSED location | **FAIL** (accepted, goods wait in transit for a paused place) | E4c2 |
| C20 | Duplicate client_id (retry / double tap) | PASS | E5a E5b one row; E5c a different user replaying the id gets the first user's transfer id back (no `client_id_taken`, unlike `stock_wastage`) - minor information leak |
| C21 | Offline | NOT SUPPORTED for transfers: no outbox; `SH.client` keeps the id so a manual retry is safe (stock2.js:196-204). POS has an outbox, stock screen does not | web/stock2.js |
| C22 | Sender cannot send more than the factory holds | **FAIL by default** (`stock_negative_mode = warn`): 5000 sent while 66 on hand; factory goes negative; only a yellow flag. Configurable to `block`. | E6a |
| C23 | Branch cannot sell goods that are still in transit | **FAIL by default** (same `warn` mode): B sold 2 kg with -2 on hand | E6b |
| C24 | Ageing of goods in transit | PASS (list + owner alert) with rule `transit_open_hours` blank by default (OFF) | E9a-E9c: 30 h, `over_limit`, `urgent_alerts` item `transit_open` |
| C25 | Receiving branch is told that goods are on the way | NOT SUPPORTED | E9d: neither function calls `_notif_add`; alert goes to the owner after N hours only |
| C26 | Short mode `loss` books the loss once in stock and GL | **FAIL** | E7 (below) |
| C27 | `transit_short_resolve` books an old short once in stock and GL | **FAIL in the GL** | E8 (below) |
| C28 | Forms: `03-1` transfer challan vs screen (no double posting) | PASS (guarded), with defaults OFF | E12a: `forms_post_to_ledger` is OFF, an approved 03-1 posts nothing; E12b turning it on flips `path_primary('stock_transfer')` to `b` (the form posts, `path_guard` keeps the screen path from posting the same movement) |
| C29 | Form 03-1 short receipt behaves like the screen | PARTIAL | E12c-E12e: one-step challan, the approver types the received count (no receiver login); short appears in `transit_short_open` but **no yellow `transit_short` exception** and `transit_short_mode = loss` is not applied on the form path (phase83.sql:~200) |
| C30 | Challan print from a transfer | NOT SUPPORTED | template exists (tpl_docs.js:75, phase93) but no screen calls it; no challan number, vehicle, driver stored |
| C31 | Ledger vs cache | PASS | E13a |
| C32 | Period lock | PASS: send and receive call `lock_check(today)` through `_stock_guard`; a receive cannot be back-dated | stock functions |

### 4.2 Accounting (location-tagged mode)

| # | Check | Verdict | Evidence |
|---|---|---|---|
| G1 | Out leg Dr 1230 / Cr inventory at sender place, in leg Dr inventory / Cr 1230 at receiver place | PASS | G1-G5 |
| G2 | Clearing nets 0 company-wide, per place = amount owed between places | PASS (but only visible by a trial-balance query) | factory +3,045, A -1,995, B -1,050: A owes the factory 60x35 - 3x35 = 1,995 |
| G3 | Transit loss Dr 5130 / Cr 1230, booked at receiver (or sender by rule) | PASS in `keep_in_transit` mode | G6 G7 |
| G4 | Transfer at cost (no mark-up / transfer price) | NOT SUPPORTED | `stock_transfers` has no price column (E10c); the 1230 is valued at cost only |
| G5 | Company-wide mode | NOT TESTED here [ASSUMPTION: same transit-loss defect as G6 because `_acct_docs` takes the same path]; covered by phase85_test C |
| G6 | Mode `loss`: Dr 5130 3 x 50 = 150 expected | **FAIL**: E7c 5130 grew 0; E7e `cost_missing` waiting row = 1; E7g/E7h inventory GL is **+150 above** stock valuation at place 2 |
| G7 | After `transit_short_resolve` of 4 kg x 50 | **FAIL**: E8c clearing moved -200; E8f cumulative phantom 350 (150 + 200); E8e waiting row = 1 |
| G8 | Cost drift: A holds 10 @80, receives 10 @50 -> 20 @65; A returns 4 @65 to factory holding 10 @50 -> factory avg 54.2857 | PASS as arithmetic (E10a E10b) but is a **finding**: a branch's blended cost contaminates the factory cost (returns are valued at the branch average, not at the original send cost) |
| G9 | Branch profit | PASS with caveat: the factory shows no revenue and no margin, all margin lands on the branch; waste and short charged to the receiver by default | IS_A / IS_B |
| G10 | `inventory_vs_gl` reasons | PASS: transfer reason is explained when mode is off (phase85.sql:604-642) | |

Root cause of G6/G7 (read from code and ledger): `_transit_loss83` (phase83.sql:61) writes `+short` as `transfer_in` with **NULL unit_cost**, then `-short` as `transit_loss`. `_acct_stock_moves85` (phase85.sql:150-170) whitelists `transfer_out`/`transfer_in` but not `transit_loss`, and it looks up a cost for a NULL-cost `transfer_in` from the OUT row, so the +short row is posted as Dr inventory / Cr 1230 (a phantom receipt) while the matching `-short` row has no GL leg. The `transit_loss` entry (phase85.sql:438-447) counts that NULL-cost row in `nulls` -> `cost_missing`, so the loss never posts (mode `loss` + receive) or stays at its first value (resolve after receive).

## 5. Owner phone workflow (branch manager confirms receipt)

Route: Home -> Stock (tile, `ia.js:52`) -> tab "In transit" -> card "Receive" -> sheet pre-filled with the sent quantity -> "Receive" button. **4 taps, no typing** when everything arrived; +1 field edit (decimal keypad) when short, an inline yellow notice appears (stock2.js:513). The sheet needs the `stock_transfer` grant at the destination (default for showroom manager, storekeeper, factory in-charge, management).
Missing for a phone-first flow: (a) no push/notification or Home badge to the receiving branch when a transfer is sent (nav.js has no transit count); (b) one card per item - a lorry with 40 items means 40 sends and 40 receives, no challan header, no "receive all" button; (c) no photo/damage reason on a short receipt (only a free note); (d) no offline outbox for receive; (e) receive quantity is in the **base unit** while a send can be typed in any sell unit (a branch counting pieces must convert by hand - E-note, code-read of `_base_qty`, not run) [ASSUMPTION: UI shows base unit label, stock2.js:505].

## 6. Does a factory-to-branch statement exist?

**NOT SUPPORTED.** Searched `pg_proc` for any function matching branch/showroom/factory + statement/recon/summary/ageing: none. Closest objects:

| Object | What it gives | What is missing |
|---|---|---|
| report `transfers_gap` (phase21.sql:280, E13b/E13c) | one row per transfer still `sent` or received short in the date range | no sold, no remaining, no returns/waste, no per-branch grouping, no value, no ageing columns, hides fully received transfers |
| `stock_in_transit`, `transit_open_list` | open lines, hours, `over_limit` | no totals per branch, no period |
| `transit_short_open` | unbooked short with value | only shorts |
| `stock_levels` | remaining per place | no in-transit, no sent/received/sold |
| `acct_income_statement(from,to,loc)` | branch profit at transferred cost | money only |
| trial balance of 1230 by place | what each branch owes the factory | no screen, no per-item |
| `report_run2` Reports hub | `wastage`, `stock_balance`, `expiry_soon` | none joins transfers with sales |

Required statement (per branch, per item and total, per period; opening + sent_in - returned - sold - wasted - short = closing, plus in-transit with ageing buckets 0-24 h / 1-3 d / >3 d, variance % = short / sent, value at transferred cost, and a "sent vs received vs signed challan" tick). The prototype in a5_01b_statement.sql proves all fields are derivable from `stock_transfers` + `stock_ledger` today; only "returned to factory" needs a marker (direction heuristic, [ASSUMPTION] location 1 is the factory).

## 7. GAP ANALYSIS

Severity: H = wrong money/stock or blocks the owner's control question; M = control weakness or manual workaround; L = polish. Effort: S <= 1 day, M = 2-5 days, L > 1 week.

| ID | Gap | Business impact | Sev | Evidence | Fix outline | Effort | Depends on |
|---|---|---|---|---|---|---|---|
| GAP-1 | No factory-to-branch statement report/screen | Owner cannot answer "what did I send, what arrived, what sold, what is left, who is short" without three screens and a calculator; disputes between factory and branches are unresolvable | H | section 6; `transfers_gap` columns (E13b); prototype a5_01b | new read RPC `factory_branch_statement(from,to,loc,item)` + report key + phone screen; add in-transit ageing buckets, variance %, value at cost, drill to transfers; export | M | GAP-3 (return marker) for exact "returned" |
| GAP-2 | Second/partial receive ignored (first receive closes) | Two-lorry deliveries or late-arriving rest become permanent "short"; branch stock understated until written off as loss; trust problem | H | E1a-E1d; phase89.sql:1886 `if t.status='received' then return dup` | allow `status='partial'` with `received_qty` accumulating until `qty` or until "close short"; each receive posts its own `transfer_in`; short = qty - received only at close | M | batch rows per receive; GL per ledger row already works |
| GAP-3 | "Return to factory" is an unmarked reverse transfer | Returns, damaged, expired and excess cannot be told apart from normal sends; factory cannot confirm; cost leaks (G8) | M | no column in `stock_transfers`; C9 | add `kind` (send / return / damage_return) + `reason` + `ref_transfer_id`; value returns at the original send cost; show in statement | M | GAP-1 |
| GAP-4 | Mode `loss` and `transit_short_resolve` break the GL in location-tagged mode | Inventory GL overstated by the shorted value (150 + 200 in test), loss entry stuck `cost_missing`, `inventory_vs_gl` unexplained diff; owner sees a wrong balance sheet | H | E7c E7e E7g E7h E8c E8f; `_transit_loss83` phase83.sql:61, `_acct_stock_moves85` phase85.sql:150-170, transit_loss entry phase85.sql:438-447 | write the `+short` leg with the transfer's cost, add `transit_loss` to `_acct_stock_moves85`'s mapping (Dr 5130 / Cr inventory) and exclude the synthetic `+short` pair from the 1230 legs and from `nulls`; re-test with phase85/83 tests | M | phase89/98 merge rules (re-create `_acct_docs` last) |
| GAP-5 | Send to a PAUSED location accepted | Goods wait for a place that is not receiving; shows as late in-transit | L | E4c2; `_loc_closed_guard` only blocks `closed` | extend guard to `paused`/`planned` for transfers (warn or refuse by rule) | S | none |
| GAP-6 | No notification / badge to the receiving branch on send | Goods sit unreceived, owner alert only after N hours and only if `transit_open_hours` is set (blank by default) | M | E9d; nav.js has no transit count; rule `transit_open_hours` default blank | on send: `_notif_add` to the destination location audience; Home badge "n to receive"; set a recommended default (e.g. 12 h) in setup advisor | S | none |
| GAP-7 | One item per transfer, no challan header (number, vehicle, driver, signed copy), print template not wired | 40-item lorry = 40 taps x2; no document to sign; template phase93 unused; disputes have no paper | M | stock_transfer columns; tpl_docs.js:75 has no caller; stock2.js has no print | add `transfer_batches` header (challan no., vehicle, driver, note, photo) + lines; "receive all" + per-line short; wire template print | L | GAP-2 |
| GAP-8 | Negative stock allowed on send and on branch sale of in-transit goods by default | Factory can ship what it does not have; branch can sell what has not arrived, so cost/stock are wrong until receipt | M | E6a E6b; `stock_negative_mode = warn` | setup advisor recommendation to `block` for transfers (grant `sell_below_zero` stays for emergencies); show a clear message | S | none (rule exists) |
| GAP-9 | No transfer price / mark-up; factory has no revenue or margin | Branch profit carries factory efficiency (and waste/short); factory performance cannot be judged; cost leak on returns | M | E10c; section 4.2 G4, G8, G9 | optional rule `transfer_price_mode` (cost / cost+% / list price) with factory sales and branch purchase legs, eliminated on consolidation; or at least report factory output value vs branch receipts | L | GAP-1; accountant decision |
| GAP-10 | Inter-branch balance (1230 by place) not shown anywhere | What each branch owes the factory is invisible; no settlement or sign-off | M | no function/screen reads 1230 (grep web/*.js, pg_proc) | add to the statement: running balance per place, and a month-end confirmation | S | GAP-1 |
| GAP-11 | Form 03-1 path differs from screen: no `transit_short` flag, ignores `transit_short_mode`, receiver count typed by approver | Two inconsistent short-handling paths when `forms_post_to_ledger` is on | M | E12c-E12e; phase83.sql:~200 | call the same receive code (or the same flag + loss helper) from `_elp_post_line` | S | GAP-4 |
| GAP-12 | No offline outbox for send/receive | A branch with weak signal cannot receive; retries are manual (safe thanks to client id) | M | stock2.js:196-204 (no queue) vs POS outbox | reuse the POS outbox with `p_client`; receive needs an idempotency key (status check already makes it safe) | M | none |
| GAP-13 | Short receipt has only a free note (no reason list, no photo) and no sign-off by the sender | Cannot separate theft / breakage / count error; weak evidence in a dispute | L | recvSheet stock2.js:504 | reason list (`transit_reasons`), optional photo (like wastage), sender acknowledgement | S | GAP-2 |
| GAP-14 | Replayed client id by another user returns the first user's transfer id | Minor information leak; inconsistent with wastage (`client_id_taken`) | L | E5c | compare `sent_by`, raise `client_id_taken` | S | none |
| GAP-15 | Receive quantity in base unit only | Branch counting in pieces/boxes must convert; risk of keying errors | L | `stock_receive_transfer` takes base qty; send accepts `p_unit` | accept `p_unit` on receive | S | none |
| GAP-16 | Accounting switches all OFF by default (`acct_transfer_mode`, `acct_transit_loss`) | A company that never turns them on has no GL trace of transfers, 1230, or transit loss; `inventory_vs_gl` shows the transfer reason instead | M | phase85 rules; section 4.2 | include in the setup advisor (phase101 rows exist for 82..98) as "recommended when more than one stock place"; documented in this report | S | none |

Top 5 by value: GAP-1, GAP-2, GAP-4, GAP-6, GAP-3 (GAP-7 is the biggest effort for the biggest daily saving).

## 8. How to reproduce

```
bash tests/sql/final_build.sh a5run
bash tests/sql/audit2/a5/run.sh a5run | tee /tmp/a5.txt     # fresh DB each time: the scripts are not re-runnable on the same DB
grep -c "NOTICE:  PASS" /tmp/a5.txt ; grep -c "NOTICE:  FAIL" /tmp/a5.txt    # 90 / 11
```
Test-script corrections made while auditing (so nobody mistakes them for product bugs): the first run was repeated on a used DB (numbers doubled); a closed location cannot be re-opened (`closed_is_final`), so the "paused" place (loc 7) is used for the reversible case; with `forms_post_to_ledger` OFF an approved 03-1 posts nothing at all (not even "skipped"), so E12 switches it on explicitly; E4c was changed from FAIL to PASS after reading `_loc_closed_guard`.
The 11 FAIL lines are: E1c (GAP-2), E4c2 (GAP-5), E6a E6b (GAP-8), E7c E7e E7g E7h (GAP-4), E8c E8f E8e (GAP-4).

## 9. Not covered (assumptions / next stage)

- Company-wide `acct_transfer_mode` and `transit_loss_at = sender` were read, not run [ASSUMPTION: same helper path, same defect].
- Multi-unit transfers (send in pieces) and many-batch partial shorts (loop at `stock_receive_transfer`, FEFO order of the OUT rows) were code-read only.
- Concurrency of two simultaneous receives: the row is locked `for update` (phase89.sql:1894) - not load-tested here (see phase109 concurrency step).
- Branch manager phone timing was derived from code, not measured on a device.
