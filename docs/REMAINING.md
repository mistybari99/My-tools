# REMAINING — what is built vs what still needs building (checked after phase 21)

Status of the owner's scope (HANDOVER §4,§5,§8,§9). "Built" = code + local SQL/web tests + independent audit. Nothing is verified on real Supabase/phone except the owner's pasted SQL "Success".

## Built (waves W0–W7)
W0 carry-over 1-20 · W1 hardening · W2 item master (1,312 imported by owner) + assets register · W3 list add-rules/Other queue/shared control (5 screens wired) · W4 locations + Control Center + settings sheet versions · W5a rollout Paper/Parallel/App, entered-later, change requests/revisions, offline form outbox, owner_self_approve switch · W5b blind count + PIN signatures (14-1, 10-1) · W6 recipes/BOM/packaging/production · W7 forms→ledger, discount approver, brand P&L, 12 new reports, nav leftovers, device checklist.

## STILL TO BUILD (priority order, by value for the owner)
P1 (needed to actually use the 1,312 items)
1. Bulk item editor: set selling price / unit / track-stock / min-stock / Bangla name for many items (inline grid or CSV paste, with dry-run + approval). Today imported items have NO price → "Data needed", not sellable.
2. Needs-decision list UX for the 43 old sweets (docs/inputs/seed_item_mapping.csv): bulk "link / keep separate" + hide dictionary twins.
3. Item list filters by type/class/category count badges; Bangla category names (label_bn empty).

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
