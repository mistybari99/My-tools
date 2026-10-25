# QA_COVERAGE (independent scope check) - state of origin as fetched 2026-10-14

Method: `git fetch origin`, exported branches to scratch dirs, read the SQL/JS, grep'd added lines (`git diff 65145c9 origin/<branch>`, 65145c9 = phase A base). Nothing executed (no DB available to me). "done+tested" = a branch report claims a passing SQL/node test for it AND I found the code at the cited line; I did NOT re-run any test. Branches that exist: A, B, C0, C, C2a, C2b, E9, H, Ea, integration/p72-p79 (INT). NOT pushed yet: Eb, D, F, S1 (phase80), S2 (phase81), G.

Legend: D = done+tested (report claims), P = partial, M = missing.

## 1. Finding -> fix -> status

Files: INT = integration/p72-p79 (supabase/phaseNN.sql), Ea = fix/phase-Ea (phase82.sql; NOT in INT).

### a1 (production cost)
| id | fixed by | status | evidence |
|---|---|---|---|
| a1-F1 method note (avg-cost is correct) | C | D (note only) | phase74.sql:5 header; "today's purchase price" separate row phase74 recipe_cost :238; costing.js todayRow |
| a1-F2 no overhead | C (74) + C-2ka (75) + C2b (78) | D, default OFF (mode off/recipe/pool per place) | location_cost_cfg phase74.sql:90-92; pools; overhead_trueup :486; cost_bill_add phase75.sql:384; GL overhead_absorbed in `_acct_docs` (phase79 merged) |
| a1-F3 NULL cost never back-filled | B4 + C9 | P | B4 flag/refuse done (phase72.sql:23 production_requires_cost, :629 refuse block, merged into phase79 production_post :288). Back-fill / recost (C9) NOT built (owner decision). Per-item "cost truly zero" flag (S1/phase80) NOT built; grep for it = nothing. UI label for `cost_missing` missing in recipes.js (only accounts.js has a reason label) |
| a1-F4 actual yield | C7 | P | DB: p_actual_yield phase74.sql:373,401,444 (yield_std/actual/variance). NO web screen passes p_actual_yield (grep web = 0; recipes.js:286 calls production_post without it) |
| a1-F5 recipe_cost vs run packaging | C4 | D | recipe_cost phase74.sql:238 (re-asserted phase79) |
| a1-F6 two cost sources | B2 | P | `_cogs_lines72` phase72.sql:55 feeds biz_daily :110, `_p27_pl` :168, l1/l2/l3, brand_pnl, partner base. NOT moved: biz_items (phase4.sql:65), report builder rpt_meas/rpt_agg_sql (phase9.sql:458), items_with_cost still read item_costs (phaseB report sec.3 item 1) |
| a1-F7 manual production cost | C8 | D | stock_production_in phase74.sql:530; production_manual_needs_reason :27/:540; production_requires_recipe -> recipe_required :539 |
| a1-F8 void/reversal | none needed | OK as audited | - |
| a1-F9 landed cost | C9 | M (owner decision, not built) | no landed/recost function in 72-82 |
| a1-F10 negative ingredient | E4 | D (Ea only) | phase82.sql:276-282 production_negative_reason; NOT in INT |
| a1-F11 cost drill-down | C3 | D | production_runs conversion_* columns phase74.sql:103,362,444; no web run-detail screen found (P for UI) |

### a2 (sales/stock)
| id | fixed by | status | evidence |
|---|---|---|---|
| a2-F1 unit mismatch skips deduction | E3 | D (Ea only; UI unwired) | phase82.sql:232 unit_conv_required, :222 late-sale rule, :351 item trigger, unit_unknown_items :369. pos.js:75 BUSINESS regex lacks `unit_unknown` -> refused queued sale retries 3x instead of failed list (confirmed: regex has none of unit_unknown / production_negative_reason_needed) |
| a2-F2 negative default / never-opened | E4 | D (Ea only) | phase82.sql:298 neg_grant_log, :383 never_opened_negative_items; defaults unchanged (warn). stock_negative_mode block is a recommendation only |
| a2-F3 offline failed card/override | E8 | M | no branch; Eb not pushed. Only the pos.js regex gap above |
| a2-F4 return margin | B3 | D | phase72.sql:11,54 (discount share), test claim 150/150/120 |
| a2-F5 COGS source | B2 | P | see a1-F6 |
| a2-F6 online order gaps | E9 | D server / P UI | phase77.sql online_pack_warn_on :18, online_keep_order_price :22, sale-void flag trigger :46. No screen shows pack warn/short or flag list (E9 report); salesx.js:123 `select('*')` on online_orders will hit the column-grant (phase61.sql:642-645) on real PG - reported by H, unfixed |
| a2-F7 packaging return | E9 proposal -> S1 | M (proposal only) | no `packaging_return_mode` anywhere (grep 72-82 = 0). S1 not pushed |
| a2-F8 expired stock sold | not in tracker map | M (unassigned) | add to a step or mark "accepted" |
| a2-F9 client_id other user / raw unique violation | not in map | M (unassigned) | |
| a2-F10 return to sale location | by design | OK | |
| a2-F11 return netting date | verified OK | OK | |

### a3 (accounts)
| id | fixed by | status | evidence |
|---|---|---|---|
| a3-F1 two profit numbers | B2 | P | profit_source_check / biz_daily_src72 phase72.sql:147; report screens biz.js/reports.js do NOT call acct_status/biz_daily_src72 (grep = 0) |
| a3-F2 costed_rev gross returns | B3 | D | phase72.sql:54 |
| a3-F3 unknown cost silent | B4 | D server / P UI | unknown_cost_rev in l1/l2/l3 + acct_income_statement; shown only in web/accounts.js (unkCost note); biz.js/reports.js not |
| a3-F4 uncosted wastage/production wait | D3 | M | D not pushed (B only improves flag) |
| a3-F5 rounding / unposted unbalanced | B1 + B6 | D | `_acct_inv_split72` phase72.sql:37; acct_post_errors72; strip in accounts.js |
| a3-F6 inventory vs GL | B5 (report) + D1 (posting) | P | inventory_vs_gl phase72.sql:781 read-only; D1 posting (stock_adjust, purchase_variance, transfers) M |
| a3-F7 opening not checked | D2 | M | |
| a3-F8 autopost delay | B6 + D5 | P | acct_status phase72.sql:713 (pending/last_post_at); scheduler + >1 day alert M (D5) |
| a3-F9 locked docs | D5 | P | acct_status.locked count only; list M |
| a3-F10 manual journal | D4 | M | |
| a3-F11 | verified OK | OK | |
| a3-F12 overhead | C | D (default OFF) | see a1-F2 |
| a3-F13 card settlement / expense pay mode | D6 | M | |

### a4
| id | fixed by | status | evidence |
|---|---|---|---|
| a4-F1 GL vs ledger | B5/D1 | P | report only |
| a4-F2 GRN vs purchase | E1 | D (Ea only; UI unwired) | phase82.sql:92 purchase_grn_guard, :397 grn_bill_link, :412 grn_pending_report; default off |
| a4-F3 bill void after use | E2 | D (Ea only) | phase82.sql:178 purchase_void_guard, :201 purchase_void_payments; default off/void |
| a4-F4 form vs screen (05-1 creates stock from nothing) | E5 | M | Eb not pushed |
| a4-F5 expense double-count | E6 | M | (C2a has a 10-2 duplicate flag for COST BILLS only, not the quick-expense/10-2 case) |
| a4-F6 transit shortage | E7 | M | |
| a4-F7 manual journal control accts | D4 | M | |
| a4-F8 autopost scheduler | D5 | M (phone-impossible part) | |
| a4-F9 audit triggers/no-delete on stock tables | F | M | |
| a4-F10 shadow pairing | E5 | M | |
| a4-F11 ledger timing now() vs bill_date | not in map | M (unassigned, LOW) | |
| a4-F12 entries post failure doesn't block approval | not in map | M (unassigned, "known") | |

Unassigned in the tracker map: a2-F8, a2-F9, a4-F11, a4-F12 (and a1-F8/a2-F10/F11/a3-F11 which are "OK" findings). Put them in a step or write "accepted".

Missing steps entirely (no branch): D (a3-F4,F6,F7,F8,F9,F10,F13; a4-F1,F7,F8), Eb (E5-E8), F (a4-F9), S1, S2, G (regression incl. hand calc 661/10=66.10 - grep for 66.10 in tests = none).

## 2. Owner rules vs diffs

| # | check | result |
|---|---|---|
| 1 one step = one branch, stop after step | cannot verify from diffs. Note C-2ka branch fix/phase-C2a contains C0+C; C2b contains C2a; Ea contains C2b; H is contained in E9. Chained, not independent - merging order matters |
| 2 only new migrations, additive | OK. `git diff --name-status` vs 65145c9: no old supabase/phase*.sql modified. Modified non-SQL: web/accounts.js, delegation.js, ia.js, index.html, tests/web/accounts_test.js and 3 .png screenshots (tests/web/ac_overview.png, n_drawer_staff.png, sx_order_form.png overwritten - harmless but unrequested binary churn). Destructive SQL grep (drop table/delete from/truncate): none; only `drop trigger/policy if exists` for paste-twice. |
| 3 nothing on live | no evidence of live access in diffs (cannot verify actions) |
| 4 defaults = today, no limits in code | MOSTLY OK. Rules default off/warn/false. Concerns: (a) phase76 seeds ACTIVE-looking numbers 10 per 60 min web form rate (web_form_rate_max/_window_min) and inbox_silence_hours=24 (phase76.sql:30-38) - settings, not hard-coded, and the module is off by default, but they are invented numbers; (b) phase74.sql:43-51 seeds smoothing windows gas/electricity 3 months, repair 12, licence yearly/12 "taken from the brief" (settings on the type; report asks owner to confirm); (c) phase82 interval '2 minutes' is pre-existing (phase10.sql:466). |
| 5 cost fields start BLANK, flagged | OK per reports (rates, normal_monthly_output, shares blank; "অসম্পূর্ণ" flags). Not independently run. |
| 6 view_cost/RLS/grants/client_id/audit | Grants/revoke present for every NEW function (script check, only re-created old functions lack revoke - fine). Audit triggers on new tables seen (phase73-78). client_id gap: these new WRITE functions have no p_client param: artisan_set_active, cost_type_add, cost_type_smoothing, recipe_cost_component_retire, loc_cost_cfg_set, cost_source_type_add, cost_source_set_active, cost_bill_reallocate, cost_bill_void, cost_bill_dup_ack, cost_rule_approve, cost_attrib_retire, sales_channel_save, intake_bot_set, inbox_set_status, online_order_draft_verify, order_dup_flag_review, online_order_flag_review, online_order_status, online_order_deliver (the last two pre-existing). They are state toggles with audit triggers (log_change) and are naturally idempotent, but the literal rule "every new write path has client_id" is not met - lead decides if accepted. web_order_submit has p_submission uuid (idempotency). grn_bill_link (phase82.sql:397) goes through existing shadow_link_add. |
| 7 tests + regressions with numbers | Reports give numbers (INT: 72:70/1, 73:98, 74:96, 75:76, 76:108, 77:26, 78:101, 79:77; Ea 82: 57/0 but built on 73-78 ONLY). Known failing tests are carried, not fixed: phase72 T0 (now 70/1 in INT, was 71/0 on its branch), phase19 T0, phase23 T0 (expected: phase74 adds cost columns), phase8 T1, phase10 T12, phase15 T0, phase21 T1, phase47 T1 x2. Rule 7 says "no pollution excuses" - each is explained but none fixed; the phase72 T0 assertion should be updated to look at the 7-arg core. phase82 NEVER run on the final build (72..79+82). |
| 8 3-part reports | OK in all 8 reports read (যাচাই হয়েছে / পড়ে বোঝা / যাচাই হয়নি). B, C, C2a, C2b, INT, Ea, H, E9 each have it. |
| 9 printed forms 05-3/05-4/10-2 untouched | OK: web/forms.js, web/forms_factory.js not in any diff. Mismatches are listed in C/C2a/C2b reports (10-2 has no bill number column; 05-4 target yield not wired; 02-2 payroll vs labour pool). |
| 10 phone-impossible listed separately | OK in H (edge deploy, secrets, Meta, cron); S/D/F N/A. |
| 11 partial stated plainly | OK in reports. Caution for tracker wording: H = "built, pull-in only, nothing connected"; channel-create UI absent (H report); E9 UI absent. |
| 12 no real person names | grep of all added lines (SQL, JS, tests, docs, edge fns) for common BD/English names: none. Test artisans use 'nm-a1' etc. |
| 13 language rule | Script check: 0 English-slot strings with Bangla chars in 8 web files' L() calls (accounts, costattrib, costing, costsources, recipebook, inbox, delegation, guards) and in ia.js rec() EN titles; 0 `'en'`/`*_en` SQL strings with Bangla in phases 72-79. phase82 not scanned beyond report claim (guards_test 35/0, phase82_test asserts). No removed text lines in accounts.js/delegation.js are wording changes (removed lines are code reshaped). Not checked: Bangla-mode "common words stay English" (subjective). No `service_role`, no JWT/keys in repo (only a comment "service_role is NOT used" in tools/edge/meta-webhook.ts). Edge functions read secrets from Deno.env only. |

Additional rule-adjacent issues found:
* Owner decision 1 / 5 "owner can ALWAYS do everything": phase73.sql:379 `self_approve_refused` also blocks the owner for a recipe he changed himself (phase73_test.sql:126 asserts exactly this), unless recipe_self_approve is ON (default OFF). Same in phase75.sql:498 (cost_rule_self_approve). Conflicts with the decision as recorded in the tracker; the owner is stuck until a recipe_approver login exists. Either exempt is_owner() or set/recommend the switch; at minimum say so.
* H intake bot needs a POS "enter" role (H report); leaked bot password could sell. Redesign is in S1 (not built).
* phase76 sets nothing to service_role: confirmed.

## 3. Owner decisions -> implementation
| decision | where | status |
|---|---|---|
| approval delegation (owner approves OR grants others) + non-blocking suggestion | recipe_approve grant phase73.sql:370; grant_separation_hint / report phase78.sql:372-390 (non-blocking, owner exempt); wired in web/delegation.js (hint after grant) | D, BUT owner self-approval block above (conflict) |
| recipe_approval_required warn/required | phase73.sql:20 choice off/warn/on; gate in recipe_cost/production | D (value 'on' = "required") |
| costing method per place (off / recipe rate / pool) | location_cost_cfg.mode phase74.sql:92, setter loc_cost_cfg_set; UI costing.js | D |
| production_requires_recipe | existing rule (phase19) enforced phase74.sql:539; recommended ON only | D (option) |
| bill entry / rule approval permissions with separation suggestion | cost_bill_entry, cost_rule_approve; pairs table grant_separation_pairs phase78 | D |
| attribution showroom / main centre + audit | phase78: location_cost_attribution, cost_attrib_main, cost_share_reassign append-only with mandatory reason; cost_attrib_in_pl default OFF; l1/l3 rows merged in phase79 | D; l4/l5/partner profit do NOT read shares (C2b report) |
| location_cost_cfg kept + change with reason/audit/history | table phase74.sql:90; reassign trail phase78.sql:74; cost_attrib_retire needs reason (:238) | D |
| lead-delegated: cost 0 = unknown unless "truly zero" flag | cost 0 = unknown done (B4); per-item free-cost flag | P (S1 not built) |
| production_requires_cost warn -> recommend refuse; cost_missing label | rule exists; Bangla label for cost_missing M (S1) | P |
| report item_costs fallback labelled 'অনুমান' | biz_daily_src72 splits fallback; label in accounts.js only | P |
| partner base switch warn|refuse | not built (S1); partner base silently includes fallback estimate (phaseB report) | M |
| D bookings (stock_adjust, opening, transfers pair, purchase_variance) | D not built | M |
| channels / phone-address guard / drafts OFF | phase76 (inbox_pii_guard_on, inbox_contact_view, inbox_autodraft_on) | D server; no channel-create UI |
| E9 pack_warn / keep price / return flag; packaging_return_mode | switches phase77; packaging_return_mode | D / M (S1) |
| setup_recommendations() + activation guide (S2) | none; only guard_recommendations() in Ea (phase82.sql:432) | M |
| INT integration | phase79 | D |

## 4. Web wiring gaps (INT branch)
* DONE in INT: ia.js rec lines (recipebook, costing, costsources, costattrib, inbox: ia.js:62-65,79) and index.html script tags for the same five; accounts.js carries B6/B5 UI.
* MISSING: `guards` page - web/guards.js exists only on fix/phase-Ea: no rec('guards', ...) line in ia.js, no `<script src="guards.js">` in index.html (INT has neither, and Ea branch has not touched ia.js/index.html either).
* MISSING: web/pos.js:75 BUSINESS regex lacks `unit_unknown` and `production_negative_reason_needed` (checked on both INT and Ea). Also stock2.js ~559 map lacks stock_unit_unknown_late, sell_below_zero_used, production_negative, purchase_void_unsafe, purchase_void_credit (text still shows from row).
* MISSING screens: B4/B6 figures on biz.js / reports.js; actual-yield input on production screen (recipes.js:286); cost_missing label; sales_channel create UI; E9 pack warn/flag list; salesx.js:123 select('*') bug on online_orders (column grants phase61.sql:642-645).
* sw.js: INT report says no precache list, so nothing to add. Not independently confirmed.

## 5. Phase numbers / overwrites
* Numbers used: 72 B, 73 C0, 74 C, 75 C2a, 76 H, 77 E9, 78 C2b, 79 INT, 82 Ea. 80 (S1) and 81 (S2) reserved, not yet written. No file-name collision across branches (each number appears once; copies of 73/74/75/78 in Ea and C2b are byte-identical to INT by md5).
* Ea (fix/phase-Ea) is based on C2b, NOT on INT: it lacks 72, 76, 77, 79. Correct paste order for everything: 72,73,74,75,76,77,78,79 then 82. phase82 has no phase guard (INT's phase79 has one). phase82 re-creates `_post_purchase_p13`, `_void_purchase_p13`, `_sale_stock_out`, `stock_post` from pg_get_functiondef captured at phase78; none of 72-79 re-creates those (script check), so no silent loss today - but any later D/F step touching stock_post or the purchase post/void would overwrite bos82 unless it starts from the phase82 text. Add a tag-survival test for bos82 in the future phase79-style test.
* Functions defined in several new phases (script check): `_acct_docs` 72,74,79; `_r3q_l1_pnl` and `_r3q_l3_shop_pnl` 72,78,79; `production_post` 72,73,74,79; `recipe_cost` 73,74,79; `pool_set` 74,75,79; `online_order_get`/`online_orders_list` 76,77. Silent loss without phase79 (INT report): `_acct_docs` bos72, production_post core bos72, l1/l3 bos72 keys. phase79 fixes them; INT report claims 32 tag checks and 77 tests. Anyone pasting 72..78 and skipping 79 gets wrong accounting silently (phase79 has a guard only for the reverse case). Recommend a prominent "paste 79 last" line in the setup page.
* Future risk: S1/S2/D/F phases that re-create production_post, _acct_docs, l1/l3, recipe_cost, stock_post must be written against the phase79/82 text and be pasted after them; assign numbers now: Eb/D/F > 82 (not yet assigned in the tracker) and make sure D (touches `_acct_docs`) starts from phase79's body, not phase52/72.
* phase72_test T0 expects bos72 in the 6-arg production_post (now a wrapper) - fails after 74; phase19/phase23 T0 "no cost columns" fail after 74. Documented, unchanged.

## Could not verify
Any test result (nothing executed); real Supabase behaviour; whether live DB already has any of 72+; behaviour of phase82 on the integrated build; Bangla-mode wording; edge functions' Meta signature logic (H marks unverified); tracker rule 1/3/8 compliance by the agents beyond what reports state; ccr-* branches (handover/docs branches, not reviewed).
