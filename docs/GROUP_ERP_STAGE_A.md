# Group ERP — Stage A: audit and architecture blueprint (READ-ONLY, no code changed)

Status: **DRAFT for owner approval.** Nothing below has been implemented. Evidence = repo paths at branch `ccr-46b26d91-81vl9s` (HEAD `dbecc25`).
Honesty note: this audit is a *sampled* read (docs, schema.sql, phase2/7/16/40 SQL, greps over `supabase/*.sql` and `web/*.js`), not a line-by-line review of all 705 files.
Items marked **[unverified]** need a deeper read or a live-database check before they are relied on.
No live Supabase was available, so nothing here is verified against real data.

## 0. Protecting running work
- Working tree clean at start (`git status` empty). No other local Claude session was reachable (ListAgents: none).
- `origin` has ~90 side branches (`fix/phase-*`, `audit/*`, `qa/*`, `integration/p72-p79`, other `ccr-*`). Another chat may be using one of them: **owner must confirm which branch/phase numbers are in use before Stage B** (latest SQL file is `phase79.sql`).
- Rule for Stage B+: only one chat edits `web/ia.js`, `web/index.html`, `supabase/phaseNN.sql` numbering at a time (same fence as `docs/briefs/00_RULES.md`).

## 1. What exists today (evidence)
| Area | Finding | Evidence | Class |
|---|---|---|---|
| Platform | Supabase Postgres + plain-JS PWA, no build; Supabase free plan, GitHub Pages; web/ goes to a separate PUBLIC repo, costs never in public repo | `docs/DECISIONS.md`, `docs/briefs/00_RULES.md` | Fact |
| Size | ~208 tables, 79 phase SQL files + `_test.sql`, ~100 web modules | `supabase/`, `web/` | Fact |
| Organization | **Flat** `locations` table (id, code, name, kind in showroom/factory/godown/hub/online/other, status planned…closed, `supplied_by`). **No parent/child, no business/legal-entity/tenant table. No `business_id`/`tenant_id`/`company_id` anywhere** | `schema.sql:31`, `phase16.sql:30-60`; grep for tenant/business ids = 0 hits | Missing |
| Location scoping | `can_loc(loc)` = owner OR role `management` OR row in `user_locations`; 102 SQL files mention `location_id` [exact count of scoped tables unverified] | `phase2.sql:64`, redefined `phase7.sql:277` (latest definition **[unverified]**) | Implemented, single-tenant |
| Roles/grants | Global roles + `grant_defs` + role×form matrix + `has_grant(code[,loc])`; staff ID+PIN login | `docs/DECISIONS.md`, `phase2/7/16` | Implemented |
| Accounting | Double-entry exists: `coa_accounts`, `journal_entries`, `journal_lines` (append-only, reversing entries), `acct_mappings`, auto-post from sales/purchases/expenses/etc. Rule `accounting_on` is **OFF by default**. One global chart; entries carry `location_id` only | `phase40.sql:35-110` | Implemented, not verified on live data, single-ledger |
| Reports | `web/reports.js`, `reports2.js`, `ownerboard.js`; REMAINING.md says 34 of 65 reports not built (as of phase 21) | `docs/REMAINING.md` | Incomplete |
| Costing | Recipes/BOM, production, overhead pools, cost attribution to locations (phase 72–79) | recent commits `c8c4f56`, `1669f37`, `f8d786c` | Implemented, recent |
| Controls | Audit log, correction log, release/emergency requests, period lock, idempotency keys, append-only history, RLS on all new tables | `docs/briefs/00_RULES.md`, `phase23.sql` | Strong, reusable |
| Known gaps | GRN vs purchase both post `purchase_in` (possible double count); sale-return not netted in some reports; no service worker; server-side PIN lockout needs Auth hook | `docs/REMAINING.md` items 10,12,15 | Open |

## 2. Hardcoded single-business assumptions (blockers for "any new business")
1. **No organization layer above `locations`** — a second business would have to share one location list, one item master, one chart of accounts.
2. **Brands hardcoded in JS**: `web/app.js:14` (`BRAND` hub/bari/cakiz), `web/forms_cash.js:34,300` (showroom + brand lists), `web/forms_factory.js:259` (`BRANDS`), `web/forms_sales.js:298`, `web/forms_staff.js:317-318` (duty slots naming the four sweets showrooms). They have DB-driven first choices with **hardcoded fallbacks**; brand is mapped by `report_brand_map` (`phase9.sql:33`), not stored on sales.
3. **Location codes/kinds baked into migrations**: phase16 seeds `cake_factory`, `mishti_factory`, `godown`, `main`; `kind` CHECK list is a closed set (`locations_kind_chk`).
4. **Global master data**: items (1,312), customers, suppliers, employees have no owner-unit scope **[unverified per table]**.
5. **Single global CoA** seeded as "bakery / sweets-shop chart" (`phase40.sql` header); `journal_entries` has no legal-entity column.
6. **Roles are "business-common" sweets roles** (showroom manager, storekeeper, factory in-charge…), `management` role bypasses all location checks (`can_loc`) — would leak across businesses.
7. **Public web repo** holds the app: a multi-business UI still ships to every device; secrets/costs must stay server-side (already the rule).
8. Language/labels are Bangla/Banglish for the sweets domain (extendable, not blocking).

## 3. Target design (recommendation)
### 3.1 Key decision — one database, add an org layer (recommended) vs one Supabase project per business
| | A. One DB + org tree (recommended) | B. Project per business + aggregator |
|---|---|---|
| Cost | stays on free plan until limits | each project = free-plan limits, more owner admin |
| Isolation | RLS by org scope (must be proven by tests) | physical isolation |
| Group dashboard | simple SQL | needs cross-project sync/ETL (hard on free tier) |
| Risk to sweets | schema change on live system | none |
Recommendation: **A**, built *additively*, with a **read-only owner view** first. Revisit B only if a business needs hard physical separation (e.g. separate legal owners/partners). **Owner decision needed.**

### 3.2 Org model (additive, idempotent, no table rewrites)
```
org_units(id, parent_id, kind[group|legal_entity|business|branch|site|department|cost_centre|project],
          code, name_bn/en, template_id, status, effective_from/to, currency, tz, geo jsonb, attrs jsonb)
legal_entities(org_unit_id, tax_cfg jsonb, fiscal_start, base_currency)       -- only where truly separate legally
locations.org_unit_id  -> existing locations become leaf nodes (kind showroom/factory/godown…) — NO id change
```
- Key idea: **do not add `business_id` to ~200 tables.** Scope is *derived*: every transactional row already carries `location_id` → location → org_unit → business/legal entity. Only **master data** (items, customers, suppliers, employees, CoA) gets an explicit `scope` (`group | legal_entity | business | location`) column.
- Dynamic attributes: **hybrid** — typed columns for anything queried/posted (money, stock, dates), `attrs jsonb` + `attr_defs(entity, key, type, validation)` for per-industry extras. **No pure EAV** for transactional data (slow, unsafe for accounting).
- Deactivate = `status`/`effective_to`; never delete (consistent with `no_hard_delete()`).

### 3.3 Accounting
- Add `legal_entity_id` to `coa_accounts` (nullable → default entity "sweets") and `journal_entries`; CoA templates per industry copied on entity creation. Existing entries back-filled to the sweets entity by migration (reviewed, dry-run first).
- Divisions inside one legal entity use cost-centre/location dimensions (already on `journal_lines.location_id`), not separate ledgers.
- Group consolidation = **view/function**, not stored: sum entities, translate currency if any, eliminate `intercompany` pairs. New `intercompany_links(entry_a, entry_b, kind)` + elimination accounts. **Needs professional accounting validation; tax/statutory not invented.**

### 3.4 Access control
- Replace `can_loc(loc)` internals with `can_scope(org_unit)`: owner → all; user grants `(user, org_unit, role)` inherited downward. `management` role stops being global; becomes "all locations of *its* business".
- Every SECURITY DEFINER function keeps `p_client` idempotency + `set search_path`; add negative tests: user of business A cannot read/write B via id swap, RPC param, or direct table select (RLS select policies today are mostly `is_active()` — **must be tightened per table; scope of work unverified, likely largest cost**).

### 3.5 Templates / module activation
`business_templates(code, modules[], default_coa, role_presets, workflows jsonb, status)` and `org_modules(org_unit_id, module, state[active|configured|needs_setup|planned|not_implemented])`. The existing `rules` + `grant_defs` mechanism (per-feature ON/OFF) is reused as the activation switch. Sweets = template `food_manufacturing` mapped to current phases 1–79. Dealership/tech/construction/digital templates ship as **records with `not_implemented`**, no screens.

### 3.6 Owner Group dashboard
Reuse `ownerboard.js`/accounting reports with an org filter; show per-unit `data_status` (ok / partial / not_implemented) — never a fake zero (matches existing "empty = data needed" rule in `DECISIONS.md`). Drill-down group → business → location → journal entry using existing reports.

## 4. Reuse-versus-build matrix
| Capability | Decision |
|---|---|
| Auth, PIN, roles, grants, rules, audit/correction log, release requests | **Reuse**; extend scope check |
| Locations | **Reuse as leaf**; add `org_unit_id` |
| Org tree, legal entity, templates, module activation, attr_defs | **Build** (new tables, additive) |
| Journal/CoA | **Reuse**; add `legal_entity_id`, per-entity CoA, intercompany |
| Items/customers/suppliers | **Reuse**; add `scope` |
| Stock ledger, production, costing | **Reuse** unchanged for sweets |
| Reports/ownerboard | **Reuse**; add org filter + data_status |
| Hardcoded brand/location lists in web | **Replace with DB-driven** (small, safe change) |
| Dealership/tech/construction/digital workflows | **Do not build now** |

## 5. API / permission boundary
Keep "all writes through SECURITY DEFINER RPCs" (no REST table writes). New RPCs: `org_unit_save/deactivate`, `template_apply` (dry-run first), `module_set`, `scope_grant`, `group_dashboard(from,to,unit)`. No arbitrary SQL, no service key in the browser.

## 6. Migration, rollback, regression plan
1. Create new tables empty (additive). 2. Insert group + sweets legal entity + business + map the 7 existing locations (`locations.org_unit_id`), **dry-run report first, owner approves**. 3. Back-fill `legal_entity_id` on CoA/journal with a reconciliation query (trial balance before = after, row counts equal). 4. Switch `can_loc` to scope-based behind a rule flag `org_scope_on` (default OFF → identical behaviour). 5. Turn flag ON in a test DB, run full SQL+Playwright suites (`tests/sql/build_fresh_db.sh`, `tests/web`). 6. Rollback = flag OFF; new columns are nullable so old code keeps working; no data deleted/renamed. Backup before each step (owner's "download all data" + `tools/backup_dump.py`; restore drill `docs/RESTORE_DRILL.md`).

## 7. Roadmap (estimates are rough; unverified)
| Stage | Content | Depends on | Effort | Main risk |
|---|---|---|---|---|
| B1 | org_units + legal_entities + map existing locations (no behaviour change) | owner approval, branch/phase numbering | S–M | none (additive) |
| B2 | UI "Organization" admin + DB-driven brands/locations (remove fallbacks) | B1 | M | web fence conflicts |
| C1 | Scope-based access (`can_scope`) + RLS tightening + isolation tests | B1 | **L** | leaks if any table missed |
| C2 | Master data `scope`, per-entity CoA, back-fill | B1 | M | accounting reconciliation |
| D | Templates + module activation (records only) | B1 | S | mislabelling "ready" |
| E | Intercompany + consolidation functions | C2 | M | needs accountant review |
| F | Owner group dashboard | C1, E | M | partial data honesty |
| Final | Migration rehearsal, backup/restore, regression | all | M | live-DB not available to me |

## 8. Acceptance criteria (from the directive, made testable)
- New business + branches created from UI with zero code change; second business has independent branches.
- User of business A gets 0 rows / error on B via direct select, RPC param swap, id guess (SQL tests per table list).
- Sweets regression: trial balance, stock balances, sales totals identical before/after migration (checksum queries).
- Dashboard includes new unit automatically; unimplemented modules show "not implemented", never 0.
- Deactivating a unit keeps all history; all new tables RLS + audit trigger + idempotent re-run.

## 9. Open questions for the owner (block Stage B)
1. Legal reality: are the future businesses separate legal entities (separate trade licence/tax/partners) or one proprietorship?
2. Approve option A (one DB) vs B (project per business)?
3. Which branch/phase numbers is the other chat using? Reserve phase80+ for this work?
4. Is the existing sweets accounting (`accounting_on`) actually switched on and in use on the live DB? (changes migration risk)
5. Free-plan limits (DB size, connections) acceptable for group growth, or is a paid plan authorised later?
6. Should `management` role stay group-wide, or become per-business?
