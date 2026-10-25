# INTEGRATION REPORT 7 - Group ERP slices merged (phases 122 to 129)

Branch `local-int` (worktree /home/user/work-int), cut from `local-b1`. NOTHING is pushed, NOTHING is pasted on the live database, no public repo touched. The owner must say "push".

## 1. Branch map

| Merged in this order | What it brought | Phases |
|---|---|---|
| local-b1 (base) | Organization layer (groups, legal entities, businesses, branches) | 122 |
| local-c1 | Business isolation behind switch `org_scope_on` (default OFF), `setup-run-18` | 123 |
| local-ie | Import-Export basic module | 124 |
| local-var | Variants (size / colour / fabric), per-business items, price lists, big-catalogue search | 125, 126 |
| local-dl | Dealer / hardware-paint: cheque (PDC) register, principal schemes, tinting machine | 127, 128, 129 |
| local-b2 (includes local-b2ui) | Web: business context, Organization screen, DB-driven brand lists, business name in receipts | web only |
| local-audit-rls, local-audit-web | Only the two audit documents in docs/audit_c1/ | docs only |

Conflicts were only in docs (HANDOVER_7, REMAINING, TODO, PASTE_ORDER), `tests/sql/paste_order.env` and `supabase/phase122_test.sql` (test T2 exemption lists of C1 and VAR merged). Docs: both sides kept. `web/ia.js` and `web/index.html` had no conflicts; the new screens were registered by the lead (section 4).

## 2. Final canonical order

`... 118, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129` (phase119 is a test-only file). Same list in `tests/sql/paste_order.env` and `docs/PASTE_ORDER.md` (rows 50 to 57, notes N7 to N9). `python3 tools/check_paste_order.py` = OK. `bash tests/sql/tag_loss_check.sh` = NET LOST TAGS 0.

Re-paste tails: every re-paste suite that repairs after an older phase (phase89h, 94b, 98d, 98e, 103b, 103d, 110b, 112, 113b, 115b, 119) now ends with 120, 121, 122, 123, 124, 125, 126, 127, 128, 129 in that order (agents had only added their own phase). Rule for the owner: after re-pasting any older phase, paste 112..118, 120, 121, then 122..129 again.

## 3. Test results (fresh `final_build.sh` database, phases 72..129)

| Check | Result | Baseline |
|---|---|---|
| `run_all_sql.sh` | 9255 pass / 89 fail | 89 = only the known environment fails (phase16 7, phase18 1, phase21 17, phase21b 17, phase118 V10 1 and the other entries of baseline_fails.txt); nothing new; phase10 improved 1 -> 0. `baseline_fails.txt` NOT edited |
| New suites | phase122 111/0, phase123 171/0, phase124 118/0, phase125 139/0, phase126 53/0, phase127 109/0, phase128 88/0, phase129 91/0 | - |
| Integration (new, test only) `phase130_integration_test.sql` | 28 pass / 0 fail | - |
| e2e | def 206/0, rec 205/0 | same as before the merge |
| Before/after (OFF state identical) | b1 OK (11 fingerprints), c1 OK (OFF identical; ON identical for the owner), var125 OK (13), dl127 OK (14); each run against a final build that lacks only its own phases | - |
| Web | org122, b2, impexp124, variants125, dealer127, ia: no errors, 0 assert failures; order 37/0; order_lazy 37/0; lazy 32/0; lang_all: NEW 0 violations after the fix | - |
| `tools/build_web.sh` | builds (137 files, core.js gzip about 477 KB); scratch output deleted | - |

Real regression found and fixed at the root: `lang_all_test` flagged 38 two-argument `L(bn, en)` calls in `web/impexp124.js` and `web/variants125.js` (the third "mix" text is required) and one English text with Bangla letters. All fixed in those files.

## 4. Web registration (bos-organise rules)

From `docs/regs/impexp124.md`, `variants125.md`, `dealer127.md`: five `rec(...)` lines added to `web/ia.js` right after `organization` (impexp in settings, variants in stock, cheques in acc, schemes in purch, tinting in stock); no route renamed or removed. `web/index.html`: `impexp124.js`, `variants125.js`, `cheques127.js`, `schemes128.js`, `tinting129.js` loaded right after `org122.js` (after stock2.js, which the dealer screens need). Lazy loading needs no extra entry (build picks the files up).

## 5. What each phase does (plain language)

- 122 Organization: the company tree. One group, companies (legal entities), businesses, branches. Every old place is put under "Sweets business". Nothing else changes.
- 123 Walls between businesses: if the switch `org_scope_on` is turned ON, a manager of business A cannot see places, dues, assets, costs or staff of business B. OFF = exactly as today.
- 124 Import-Export: currencies, exchange rates, shipments (import / export), status steps, landed cost, report by currency. Not connected to the books.
- 125 Variants: option lists (size, colour, fabric), styles, one press creates every size x colour item; price lists by channel (retail, wholesale, online); each item belongs to one business.
- 126 Big catalogue: fast search (name, code, barcode) for 20,000+ items.
- 127 Cheque / PDC register: received and issued cheques, deposit, clear, bounce, replace, post-dated exposure. A cleared customer cheque writes one bank collection.
- 128 Principal schemes: slab / target rebate schemes from principals, accruals, claims, reconciliation of claims received.
- 129 Tinting machine: shades, formulas (base + colorants), tint jobs with stock use and cost.

## 6. What is OFF by default, and the order to switch things on

Everything new is OFF: `org_scope_on`, `impexp_on`, `variants_on`, `dealer_cheque_on`, `dealer_scheme_on`, `dealer_tint_on`. Paste alone changes nothing the owner sees (the 5 new menu entries only open empty screens that say the module is off).

Switch-on order (one step per day, check after each, style as docs/guide/AUDIT_SWITCHES.md):
1. Org setup: #/organization. Check the sweets tree; rename the placeholder names. Add legal entity, then business, then branches.
2. Map locations: every place must belong to a business (`locations.org_unit_id`). New places are not mapped automatically.
3. Create businesses / users scopes: give each manager a scope (`org_scope_grant`), assign staff places (`user_locations`), give grants (impexp_*, variants_manage, dealer_*).
4. Run `select org_scope_preflight();` as owner. Fix everything it lists (unmapped places, managers without scope, NULL-place config rows, personal grants without a place).
5. Turn `org_scope_on` ON in #/switchboard. Test with a manager of each business. OFF goes back instantly.
6. Then, per business that needs it: `impexp_on`, `variants_on`, `dealer_cheque_on`, `dealer_scheme_on`, `dealer_tint_on` (each separately, one per day).

## 7. Cross-phase safety (what was proven)

`phase130_integration_test.sql`: with `org_scope_on` ON and extra businesses HW (dealer) and IE (import-export) plus sweets: an HW manager reads and writes only HW cheques, schemes, tint formulas, items; cannot read IE shipments, cannot search IE items, cannot post at an IE place; an IE manager sees only IE shipments and no dealer data or HW items; a sweets manager holding every grant sees none of it; direct table reads are filtered the same way; the owner sees everything with the same numbers ON and OFF; after switching OFF again the owner's counts and trial balance equal the first snapshot.

## 8. Known risks and unverified items

- Nothing ran on the owner's live Supabase or on a phone. All numbers are synthetic scratch databases.
- The phone (360px) look of impexp, variants, cheques, schemes, tinting is checked only by mocked-RPC Playwright tests.
- Browser grants of function EXECUTE on Supabase (functions without explicit revoke stay open to `authenticated`) is an audit assumption, not verified live.
- `items.code` and barcode are still globally unique: a second business cannot reuse a sweets code (plan in docs/regs/variants125.md section e).
- Cost of the extra switch lookup in `can_loc` / `has_grant` measured on scratch only (+7% on 100k calls).
- `items_read` policy: phase125 leaves it to phase123's policy when 123 is present. Both tested together here; only synthetic data.
- Setup pages 19 and 20 are verified on a scratch DB (CHECK 0/N before, N/N after), not clicked on a phone.
- Names of seeded units are placeholders; the trade licence is left empty.

## 9. Remaining work

1. Deferred global masters (Stage C2): customers, suppliers, recipes, chart of accounts, categories, tiers and other ~31 any-active tables are still one master.
2. Per-business rules, roles and grants (a rule changed in business A must not change B).
3. About 170 unscoped reader RPCs of the C1 audit (Appendix B); owner-only families stay group-wide.
4. Dealer POS (sales with scheme / tint / cheque at the counter); wiring `price_for125` into POS and invoices.
5. GL posting for schemes (rebate accruals, claims) and for import-export (landed cost, FX gain / loss, stock link).
6. Fashion slices: retail, wholesale, online, tailoring (cut-make-trim costing), exchange rules, size-colour grid in purchase and POS, labels, CSV import of styles.
7. Stage E intercompany between businesses, default OFF (cross-business stock transfer is refused until then).
8. Stage F master owner dashboard with `data_status` (what is complete, what is missing, per business).
9. Template seed for `fashion_apparel` (the template row is still missing; the variants regs mention it).
10. Per-business item codes (relax the global unique), storage bucket layout per business, Telegram / edge bot identity per business.
11. Web: item lists on `items_search` paging; business switcher on those lists.

## 10. Owner checklist (short MCQ, simple English)

Answer with the letter. Nothing is switched on until you say so.

1. Do you want the walls between businesses ON now?
   A) Not yet, first I will add my second business. B) Yes, but only after the preflight list is empty. C) No, I run one business only.
2. Which new business should we use first?
   A) Cloth / fashion (variants). B) Hardware / paint dealer (cheque, scheme, tint). C) Import-export. D) None yet.
3. Cheque (PDC) register: do you take post-dated cheques from customers?
   A) Yes, many. B) Yes, a few. C) No.
4. Principal schemes (rebate on target): who checks the claim amounts?
   A) The accountant. B) Me. C) We do not have schemes.
5. Import-export: which money do you use besides taka?
   A) US dollar. B) Euro / other. C) Taka only.
6. When may we paste Run 19 and Run 20 on the live database (they change nothing you see)?
   A) Today. B) After the Run 17 and Run 18 checks are all green. C) Ask me again next week.
7. Who may see the cost price of the new businesses?
   A) Owner only. B) Owner and accountant. C) Decide later.
8. Do you want me to push the finished work to the public site now?
   A) No, wait. B) Yes, push after I check the screens on my phone.

## 11. Setup pages (local only, NOT published)

`/home/user/work-c4-out/`: setup-run-16 (phase 120/121), 17 (phase 122), 18 (phase 123), 19 (phases 124, 125, 126; about 99 KB; CHECK 0/41 before, 41/41 after on a scratch DB), 20 (phases 127, 128, 129; about 141 KB; CHECK 0/60 before, 60/60 after). Each is chain-locked behind the previous run, has a read-only CHECK, and is below the 200 KB limit, so no further split. Paste order for the owner: 16, 17, 18, 19, 20, each with its Check.
