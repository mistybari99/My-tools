# Integration notes: RPT-C3 (reports package: R7 marketing, R8 audit and control, R9 planning)

Source: `docs/REPORTS_AUDIT_3.md` (reports #164-171, #173-177, #180, #182-190, #192-193). Branch `rpt-c3`. Loans and VAT are NOT built.

## 1. Files
New SQL (paste in this order, after the build through phase 99; every file is paste-twice safe, no old file is edited, none is in `tests/sql/ORDER.txt` - the integrator adds them to the owner paste order): `supabase/phase458.sql` .. `phase468.sql` with `phase458_test.sql` .. `phase468_test.sql`.
New web: `web/rptkit.js` (shared report engine), `web/campaigns.js`, `web/couponuse.js`, `web/auditreports.js`, `web/forecast.js`.
Tests: `tests/sql/rptc3_head.sql`, `rptc3_fixture.sql`, `rptc3_history.sql`, `rptc3_build.sh`, `rptc3_run.sh`; `tests/web/rptc3_test.js`, `rptc3_run_all.sh`, `rptc3_regress.sh`; `tests/web/s10_common.js` got one line (`BOS_WEB_ROOT`, so a worktree can serve its own `web/`).
Docs: this file, `RPT-C3_info.json` (plain-English entries for the (i) info sheet), `docs/REPORTS_AUDIT_3.md`.

## 2. What the owner gets
| Phase | Adds |
|---|---|
| 458 | campaign master list (an option list `marketing_campaigns`, nothing seeded), `mkt_campaign_save`, campaign / offer code tags on a sale (`mkt_sale_tags`) and an online order (`mkt_order_tags`), `rptc3_export_log` (audited CSV check for every report of this package), `_c3_*` helpers |
| 459 | #164 spend by campaign (+ drill), #165 spend vs sales (no-causal-claim note), #166 campaign revenue and contribution, #167 discount campaigns |
| 460 | #168 coupon usage (reads the CRM-F tables when present), #169 CAC with source coverage %, #170 repeat purchase after a promotion, #171 marketing ROI; setting `mkt_repeat_days` |
| 461 | setting `marketing_post_on` (OFF) + `marketing_post_from`; `mkt_post_preview / decide / run / wind_down`: posts 18-1 spend to the journal without double counting 10-2 |
| 462 | #173 audit log pager (owner only), #182 void / reversal / correction register |
| 463 | #180 approval delays, #174 stock adjustment approval history, #183 data gaps (wraps `d_recipe_cost_gaps`) |
| 464 | #175 price-override approver captured (trigger `sales_c3_override_capture`) and reported, #176 unusual list, #177 per-user activity |
| 465 | `festival_calendar` (owner enters), #184 sales forecast, #185 item demand, each with an assumptions panel; settings `fc_window_days`, `fc_payroll_day` |
| 466 | #186 production requirement, #187 recipe-exploded raw material purchase forecast |
| 467 | #189 upcoming supplier payments, #188 expected cash in / out calendar, #190 expiry and wastage risk |
| 468 | #192 what-if scenario, #193 seasonal / festival analysis |

Every report is read-only and OPEN to the existing report grants (`rpt_access(group)`: owner, `report_<group>`, `view_reports`): marketing, control, sales, stock, cash, profit. Exceptions that follow existing table rules: the raw audit log is owner only (its table policy is owner-only); login / audit columns of per-user activity are owner only; salary-related rows need `salary_view`; cost columns need `rpt_cost_ok()`.

## 3. Behaviour that changes at the defaults
Nothing that moves money. Every new setting is OFF or blank. Three additive things exist from the moment the SQL is pasted: (a) a new AFTER INSERT trigger on `sales` (`sales_c3_override_capture`) that writes one row to its own table when a bill has a changed price (never blocks a sale: errors are swallowed); (b) two indexes on `audit_log`; (c) new settings and the list `marketing_campaigns`. The 18-1 form gets one optional list field `campaign_id`; the free-text campaign field stays.

## 4. Settings (module reports / books; English labels; the Rules page and the Switchboard list them)
`marketing_post_on` switch OFF; `marketing_post_from` date blank (the switch cannot be turned ON without it, accounting ON with a start date, and the mappings `exp_marketing`, `pay_bank`, `pay_mobile`); `mkt_repeat_days` blank; `fc_window_days` blank; `fc_payroll_day` blank. A blank number means the report asks the person to type it or says "data needed". No limit, window, threshold or festival uplift is invented.

## 5. Posting 18-1 (phase 461), what is and is not posted
Posted: approved lines paid from bank / mobile / card (card follows the supplier-payment rule: bank), dated on or after both start dates, period open, no 10-2 or quick-expense look-alike (same head `marketing`, amount, place and date). Never posted: imprest lines (the 10-2 voucher already holds that money), owner-money lines and lines with no source (nobody chose the credit account). A look-alike waits for `mkt_post_decide` (post | skip, reason, kept for ever). A re-opened sheet has its old entry reversed and the new revision posted. Source type `mkt_spend`, key `sheet:revision:line`. The management profit view (L1 / T4) reads 10-2, not 18-1, and is unchanged. UNTESTED with an accountant.

## 6. Hooks for the integrator (the web test proves each; text is exact)
| # | File | Change (already applied on this branch) | Without it |
|---|---|---|---|
| H1 | `web/pos.js` `cartSheet()` | `${B.mkt && B.mkt.posBox ? B.mkt.posBox() : ''}` before the total row | no campaign / offer-code box on the till |
| H2 | `web/pos.js` `submitSale()` after `B.invoice.offer(...)` | `if (B.mkt && B.mkt.afterSale) B.mkt.afterSale(data.id);` | a typed campaign / code is never saved on the sale |
| H3 | `web/pos.js` queued branch | `if (B.mkt && B.mkt.queued) B.mkt.queued(p.p_client);` | an offline sale loses its tag (with it, the tag is retried through `mkt_tag_sale_client`) |
| H4 | `web/forms_cash.js` form 18-1 lines | one `SEL('campaign_id', ..., B.optsX('marketing_campaigns', []), { list: 'marketing_campaigns' })` after the free-text campaign column | 18-1 lines can only be matched to a campaign by exact free-text name |
| H5 | `web/index.html` | five script tags after `daybook.js`: `rptkit.js`, `campaigns.js`, `couponuse.js`, `auditreports.js`, `forecast.js` (kit first) | the screens do not load |
| H6 | `web/ia.js` | four `rec(...)` lines before the settings group: `campaigns` (reports, also acc), `couponuse` (reports, sub page of campaigns), `auditreports` (appr, also item), `forecast` (reports, also factory / purch / stock); icon keys added to `I3` | no menu entry (routes still open by address) |
| H7 | `web/nav.js` `loadGrantFlags` | `view_reports`, `report_marketing`, `report_control`, `report_sales`, `report_stock`, `report_cash`, `report_profit` added to both grant-code lists | the menu predicates cannot see a report grant; the server still decides |
| H8 | CRM-F merge | CRM-F (`.claude/worktrees/agent-a86a4094f30d136b0`, phases 316-319) edits the same three places of `pos.js`. The two sets of lines sit next to each other and do not depend on each other | merge by hand: keep both |

Coupons: this package creates NO coupon table. `crmf_coupons.campaign_ref` (text) is matched to a campaign code or name in the usage report; a code typed at the till is stored as a label and, when the CRM-F table exists and knows the code, its id is stored next to it. The CRM-F test stand-ins used by `phase460_test.sql` are created inside the test database only.

## 7. Not confirmed / not built
Not tested on a real phone or against a real accountant. Emergency-approval price override is tested end to end in `phase464_test.sql`; the customer credit-days column used by the cash calendar belongs to another package (the calendar detects it, a test adds it to a scratch DB). Loans and VAT (#127, #128) are not built. No demo data in any file: every fixture uses `test_*` names.
Known limits worth reading: forecasts need a typed or set window (no default); the cash calendar excludes opening balance and forecast sales; item demand counts stock-out days as zero; the repeat-purchase and CAC reports cover identified customers only.
