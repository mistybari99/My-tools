# REMAINING — what is built vs what still needs building (checked after phase 21)

Status of the owner's scope (HANDOVER §4,§5,§8,§9). "Built" = code + local SQL/web tests + independent audit. Nothing is verified on real Supabase/phone except the owner's pasted SQL "Success".

## Built (waves W0–W7)
W0 carry-over 1-20 · W1 hardening · W2 item master (1,312 imported by owner) + assets register · W3 list add-rules/Other queue/shared control (5 screens wired) · W4 locations + Control Center + settings sheet versions · W5a rollout Paper/Parallel/App, entered-later, change requests/revisions, offline form outbox, owner_self_approve switch · W5b blind count + PIN signatures (14-1, 10-1) · W6 recipes/BOM/packaging/production · W7 forms→ledger, discount approver, brand P&L, 12 new reports, nav leftovers, device checklist.

## STILL TO BUILD (priority order, by value for the owner)
P1 (needed to actually use the 1,312 items) -- BUILT in phase22 (needs the owner to paste supabase/phase22.sql; not tried on real Supabase / phone)
1. DONE: Bulk item editor `#/bulkitems` (grid 50 rows/page, filters, inline edit, Preview then Apply through `items_bulk_apply`, CSV paste `code,price[,unit,track,min_stock]`, CSV export without costs, bulk hide / inactivate with reason). Still manual: the owner must type the ~1,255 prices (or paste a CSV).
2. DONE: `#/itemmap` rebuilt: per old item link / use the dictionary item instead (copies price + unit, retires the old item, undoable) / keep separate / decide later, search box, accept-all-high-confidence, progress counter. The owner still has to decide the real 57 (or 43) items.
3. PARTLY: legacy categories are labelled "Old list" and sorted after the 25 dictionary ones; "Unpriced finished goods / resale" chip in the item list; Bangla names of the 25 categories are typed by the owner on the Bangla names tab of the bulk editor (label_bn is still empty until then). Count badges per type/class on the list are NOT built.

P2 (rule 4 / consistency)
4. ~50 pickers still plain selects (purchase unit/return reasons, sale-return reasons, stock unit, wallets, asset condition, itemmaster type/class, unit-conversion selects) → wire B.listctl.
5. Hard-coded location lists in forms_cash.js / forms_sales.js (SHOWROOMS, brands), forms_staff.js duty slots; entry pickers still show paused/closed places (server refuses).
6. Owner self-approval switch not yet applied to wastage, supplier refund, sale returns, location settings approvals (done for entries/releases/emergency/item changes).
7. Blind count only 14-1 and 10-1; 04-3 stock count, 04-1 GRN not blind; browser still computes expected (hidden, not sealed). PIN signature only for 14-1/10-1 witness; other two-person forms (e.g. 11-1, 08-1) unchanged.

P3 (reports / accounting)
8. 34 of 65 reports remain (list in BUILD-LOG W7: S10, P2, P4–P6, K2, K3, F1–F4, E2–E4, W1, W2, D5, T3, T4, L1–L5, X2–X5, G2, M1, M2, Q1–Q3). Parallel-mode comparison pairs/month-end pass-fail (Build cmd 7) and "Parallel" labels on reports not built.
9. Day book gaps: bank deposits (10-3), customer order advances, owner top-ups, hub receiving side of 10-1.
10. GRN (04-1) vs purchase page both post purchase_in → possible double count; GRN has no batch/expiry per line.
11. Production run void/undo; recipe/production reports; packaging line on receipt.
12. Sales/due reports not yet net of sale returns and refund cash.

P4 (platform / ops)
13. Form-vs-paper check docs/forms/<code>.md for all 41 forms (Build cmd 11) — needs the owner's paper kit text; not in repo.
14. Control Center tiles "Rollout board" and "Print & books" are placeholders; Needs-you shows counts, not oldest-first rows; release_decide delegates have no page; no UI for blind_count_cfg / pin_sig_cfg per-form tables.
15. No service worker: first load needs internet (offline only for already-open app: POS + form outbox).
16. Old tests: pos_test.js stale selector (#cart_given); p9 report tests not re-run after phase 14+.
17. VAT/Mushak 6.3 line stays OFF (adviser's rate needed).

## OWNER ACTIONS (no code)
- Supabase Dashboard → Authentication → Hooks → enable `hook_password_verification_attempt` (server-side PIN lockout; without it lockout guards only the app screen).
- Set item prices; switch `tools_stock_on`, `blind_count_on`, `pin_signature_on`, `forms_post_to_ledger`, `packaging_consume_on` only when ready; give grants (see_expected, rollout_manage, change_approve, list_manage, location_manage…).
- Resume `mishti_factory` (paused) when needed; run docs/DEVICE_CHECKLIST.md on a real phone/printer.
- Design pass (colours/typography/layout) — deliberately last.


## UPDATE after audits (phases 112-121) - see docs/HANDOVER_6.md for the full list
Built and live: audit fix batches 1-4 (phases 112-118) + security fixes (121), all switches default OFF. PENDING: phase120 is merged and tested on local-c4 (setup-run-16 built, owner must say "push", then paste Run 16 and Check), switch roll-out (docs/guide/AUDIT_SWITCHES.md), remaining audit gaps (A1 G5/G9/G11-G14, A2 G7/G10-G15, A3 G7/G11-G17, A4 G02/G06/G07/G09-G20, A5 GAP-5/7/11-13), 23 gaps without probes, old HANDOFF_6 items (wording, Category phase 2, dashboard phase 2, security leftovers, accounting review, phone-only steps).

## UPDATE Group ERP (Stage B1) - see docs/HANDOVER_7.md and docs/GROUP_ERP_STAGE_A.md (sections 10-11)
Built locally on branch local-b1, NOT pushed, NOT pasted: phase122 (organization tables org_units / legal_entities / business_templates, locations.org_unit_id, rule org_scope_on OFF, grant org_manage, org_tree / org_unit_scope / org_unit_save / org_unit_deactivate), phase122_test 111/0, setup-run-17 built locally. No behaviour change. NOT built: B2 organization UI + DB-driven brand/location lists, C1 scope-based access and RLS tightening, C2 master-data scope and per-entity chart of accounts, D templates/modules, E intercompany (default OFF), F owner-only group dashboard, partnerships (my share), all industry workflows.

## UPDATE dealer / hardware-paint business (phases 127-129) - see docs/HANDOVER_7.md
Built locally on branch local-dl, NOT pushed, NOT pasted: cheque / PDC register (phase127), principal scheme engine with preview, claims and reconciliation (phase128), tinting machine with versioned formulas, stock consumption, cost and customer shade history (phase129); three screens web/cheques127.js, web/schemes128.js, web/tinting129.js; rules dealer_cheque_on / dealer_scheme_on / dealer_tint_on all OFF. REMAINING: the lead applies docs/regs/dealer127.md (ia.js + index.html); owner decides to paste; master-data (customer / supplier) scope per business; posting of scheme accruals / receipts to the books (needs the accountant); dealer POS screens; bulk item import and variants (other agents, phases 124-126); sale returns in sale-based schemes.

