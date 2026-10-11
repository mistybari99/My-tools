# Reports hub — plan (planning only, no app code)
Project: /home/user/My-tools · date 2026-10-11 · research basis: repo files + my knowledge of Odoo/Zoho/Xero/QB/ERPNext/Tally/Vyapar (NOT web-verified; WebSearch not used).

## 0. What I found in the repo (facts)
- Structured tables: `sales` (lines jsonb with price snapshot, discount, total, pay_mode, sale_type, customer_id, paid, due_amount, quick, status, created_staff, sold_at), `sale_payments` (kind sale/collection, mode, wallet, ref, voided), `customers` (mobile, type, credit_limit), `items` + `item_costs` (cost hidden by ITEM_COST perm) + `item_price_history`, `entries` (42 forms, ALL field data in `data` jsonb + `flags`), `exceptions`, `release_requests`, `emergency_requests`, `audit_log`, `corrections`, `option_lists`, `rules`, `location_settings`, `login_failures`.
- Existing RPCs: sales_summary, payments_summary, customer_dues, customer_ledger, biz_daily/biz_items/biz_staff/biz_outlook/biz_suggest, number_audit(_summary). Pages: `#/biz`, `#/dues`, `#/numaudit`, home dash.
- Important gaps: (a) every form figure (purchases, expenses, stock counts, salary, temperatures...) is inside jsonb, line tables nested -> not report-friendly; (b) NO perpetual stock balance; (c) cost = current cost only (history exists in item_price_history but biz_* does not re-cost); (d) quick sales carry no cost; (e) no supplier/raw-material master (suppliers are free text in 04-1/06-x); (f) no budgets table; (g) no wastage reason list.

## 1. Catalogue (65 reports)
Legend — Data: **E** = structured data exists now · **J** = exists but inside entries.data jsonb (needs a fact view/extractor, no new capture) · **N** = needs new capture/form field/master data. ₵ = cost-price secret: owner or ITEM_COST view only; server must null the cost columns, not the UI. Pri: P1 first release, P2, P3.
Common filters: date range preset (today/yday/7d/this+last month/FY/custom), location multi-select (auto-limited by can_loc), + those listed. "Cmp" = supports compare-previous-period.

### A. Sales / বিক্রি
| # | বাংলা / English | Question | Source | Extra filters | Data | ₵ | Pri |
|---|---|---|---|---|---|---|---|
| S1 | বিক্রির সারসংক্ষেপ / Sales summary | How much, how many bills, avg bill, discount, due? | sales | staff, mode, sale type, customer | E (partly exists biz_daily) | GP only | P1 |
| S2 | বিক্রির ধারা / Sales trend (day/week/month, Cmp) | Up or down vs last period/same weekday? | sales | group by day/week/month | E | – | P1 |
| S3 | একত্রিত দোকান-ওয়াইজ / Combined multi-shop (row per shop) | Which shop earns what? | sales,sale_payments | – | E | GP col | P1 |
| S4 | আইটেম-ওয়াইজ বিক্রি / Item-wise sales | Qty & value per item; margin | sales.lines, items | item, category | E | margin | P1 |
| S5 | ক্যাটাগরি-ওয়াইজ / Category-wise sales | Which category carries sales? | same | category | E | margin | P1 |
| S6 | রসিদ তালিকা / Sales register | Every bill, drill to receipt | sales | search receipt/mobile | E | – | P1 |
| S7 | সময়/বার অনুযায়ী / Hour & weekday heat | When is peak? staffing | sales.sold_at | – | E | – | P2 |
| S8 | খুচরা বনাম পাইকারি ও পার্টি ইনভয়েস / Retail vs wholesale + party invoices | Wholesale share, party sales | sales; entries 20-4, 20-5 | customer | E + J | – | P2 |
| S9 | ডিসকাউন্ট ও দাম বদল / Discounts & price overrides | Who gives how much off, above limit? | sales (discount, lines.override), exceptions | staff, approver | E (approver stored? check) | – | P1 |
| S10 | অর্ডার, অনলাইন ও ডেলিভারি / Orders, online & delivery | Open orders, channel sales | entries 20-1, 20-6 | status | J | – | P3 |

### B. POS / ক্যাশিয়ার
| C1 | দিনশেষ / শিফট রিপোর্ট / Day-close (X/Z) report | Per shop-day: sales by mode vs counted cash vs handover | sales,sale_payments,entries 14-1,10-1 | shift | E+J | – | P1 |
| C2 | ক্যাশ কম/বেশি / Cash short-over | Who/where is short repeatedly? | entries 14-1 (counted, short), 10-1 | staff | J | – | P1 |
| C3 | বাতিল, ফেরত, রিটার্ন / Voids, refunds, returns | Volume, reasons, who | sales status=void, void_note; 20-3 | staff, reason | E+J | – | P1 |
| C4 | কুইক ও তালিকা-বহির্ভূত বিক্রি / Quick & unlisted sales | Sales with no item/cost; unlisted items | sales.quick, lines | staff | E | – | P2 |

### C. Purchase / Supplier / ক্রয়
| P1 | ক্রয় সারসংক্ষেপ ও সাপ্লায়ার-ওয়াইজ / Purchases by supplier & item | What do we buy from whom, how much | entries 04-1 (lines amt, rate), 06-3 | supplier, item | J | ₵ (all) | P1 |
| P2 | ক্রয়-দর ধারা / Purchase rate trend per item | Which input got dearer? | 04-1 lines rate | item, supplier | J | ₵ | P2 |
| P3 | সাপ্লায়ারকে দেনা ও বয়স / Supplier payable & aging | How much do we owe, since when? | 06-4, 06-5, 04-1 pay | supplier | J (supplier free text -> needs master) | ₵ | P1 |
| P4 | সাপ্লায়ার স্কোরকার্ড / Supplier scorecard | Short/rejected/late/rate-change per supplier | 04-1 quality, 06-4 short/return, 06-3 | supplier | J | ₵ | P2 |
| P5 | PO-GRN-বিল মিল ও খোলা PO / 3-way match & open POs | Mismatches, undelivered POs | 06-3, 04-1, 06-4 | status | J | ₵ | P2 |
| P6 | ক্রয় বনাম বাজেট/পূর্বাভাস / Purchase vs budget & outlook | Spent vs hub purchase budget (10-4) vs biz_outlook | 10-4, 04-1, biz_outlook | – | J | ₵ | P2 |

### D. Stock / Wastage / স্টক
| K1 | স্টক ব্যালান্স ও মূল্য / Stock balance & valuation | What is on hand per shop/godown, worth? | needs stock ledger | item, category, location | **N** (no perpetual stock) | ₵ valuation | P1 |
| K2 | স্টক গণনার পার্থক্য / Count variance | Book vs counted, repeat offenders | entries 04-3 (rows var,reason) | item, counter | J | ₵ value of var | P1 |
| K3 | স্টক মুভমেন্ট / Store ledger | In/out per item (GRN, issue, transfer, sale, count) | 04-1,04-2,04-4,03-1, sales | item, kind | J (+K1 fact) | ₵ | P2 |
| K4 | ট্রান্সফার ও রিসিভ মিল / Transfers & receiver mismatch | Sent vs received between locations | entries 03-1 | from/to, status | J | ₵ | P1 |
| K5 | নষ্ট / ওয়েস্টেজ ও মেয়াদোত্তীর্ণ / Wastage & expiry | How much stock lost, why | expired_removed 14-1, 05-1 raw_return, 20-3 taken_back; **new write-off form/list** | reason, item | **N** (reason list = option_lists) | ₵ | P1 |
| K6 | রিঅর্ডার ও ধীর স্টক / Reorder & slow stock | Low vs sales speed; dead stock | K1 + sales speed; reuse biz_items ABC | threshold (settings) | N (needs K1) | ₵ | P2 |

### E. Production / কারখানা
| F1 | দৈনিক উৎপাদন ও চালান / Production & dispatch | Batches made, sent to shops | entries 05-1 batches, challan | product | J (batch table must be structured by product/qty) | – | P2 |
| F2 | ফলন বনাম মান / Yield vs standard | Yield % per product/batch | 05-1, 05-4, 05-2 spec | product | J | ₵ | P2 |
| F3 | কাঁচামাল ব্যবহার বনাম রেসিপি / Raw usage vs recipe | Over-use of milk/sugar etc. | 04-2 issue, 05-3 recipe, 05-1 | product | **N** (recipe & issue lines not structured; no raw-material costs) | ₵ | P3 |
| F4 | মেশিন বন্ধ ও মেইনটেন্যান্স / Breakdown & maintenance | Downtime, repeat faults, open requests | 05-1 breakdown, 08-1 | machine | J | – | P3 |

### F. Expense / খরচ
| E1 | খরচ-হেড ও লোকেশন-ওয়াইজ / Expenses by head & shop | Where does money go? | 10-2 lines (head, amount), 18-1 | head, payee | J | owner-level | P1 |
| E2 | খরচের ধারা ও আগের সময়ের তুলনা / Expense trend (Cmp) | Which head is rising? | same | head | J | – | P1 |
| E3 | রসিদহীন/সীমা-ছাড়া/ইমপ্রেস্ট / No-receipt, over-limit, imprest | Weak-control spend | 10-2 (no_receipt_reason, approved_by), 14-1 imp_* ; exceptions | approver | J | – | P1 |
| E4 | মার্কেটিং খরচ বনাম মাসিক সীমা / Marketing spend vs head limit | Head limits (option_lists) used? | 18-1, option_lists | head | J | – | P2 |

### G. Cash / Bank / Wallet / ক্যাশ
| W1 | দৈনিক ক্যাশ প্রবাহ / Cash flow | In (cash sales+collections) − out (expense, purchase cash, handover) | sales/payments + 10-2,04-1,10-1 | location | E+J | – | P1 |
| W2 | হ্যান্ডওভার বনাম হাব গণনা / Handover vs hub count | Cash lost in transit? | 10-1 | courier, location | J | – | P1 |
| W3 | ডিজিটাল পেমেন্ট মিল / Digital reconciliation (bKash/Nagad/card) | App vs statement | sale_payments(ref) + 10-3 | wallet | E+J | – | P1 |
| W4 | পেমেন্ট মোড-ওয়াইজ / By payment mode & wallet | Cash/mobile/card/due mix | sale_payments | mode, wallet | E | – | P1 |
(Bank balance / owner-funded payments: only if bank opening balance is captured — N, folded into W1 as P3 extension.)

### H. Dues / Customers / বাকি ও গ্রাহক
| D1 | গ্রাহকের কাছে পাওনা / Due from customers | Who owes how much | customer_dues (exists) | customer, type | E | – | P1 |
| D2 | বাকির বয়স / Receivable aging (0-7,8-30,31-60,60+; buckets editable) | How old is the baki | sales+collections FIFO | customer | E | – | P1 |
| D3 | আদায় রিপোর্ট / Collections | Collected by day/mode/staff | sale_payments kind=collection | staff, mode | E | – | P1 |
| D4 | সেরা গ্রাহক / Best customers | Top by value, visits, avg bill | sales | customer, type | E | – | P1 |
| D5 | নিষ্ক্রিয় ও নতুন-পুরনো গ্রাহক / Lapsed, new vs repeat | Who stopped coming | sales | days-silent | E | – | P2 |
| D6 | ক্রেডিট লিমিট ব্যবহার / Credit-limit use | Near/over limit, override use | customers, customer_dues, grants | customer | E (limit empty -> "Data needed") | – | P2 |

### I. Staff / কর্মী
| T1 | সেরা কর্মী / Best employee | Sales, bills, avg bill, items/bill, void/discount rate | sales; reuse biz_staff | staff, shop | E | – | P1 |
| T2 | হাজিরা ও ওভারটাইম / Attendance & OT | Absence/OT per person/shop | entries 02-1, 02-5 | staff | J | – | P2 |
| T3 | বেতন ও অ্যাডভান্স / Payroll & advances | Net pay, advance outstanding | 02-2, 02-3, 10-5 | staff | J | owner-only (salary secret) | P2 |
| T4 | স্টাফ খরচ ÷ বিক্রি / Staff cost ratio | Payroll as % of sales by shop | 02-2 + sales | shop | J | owner-only | P2 |

### J. Profit / Loss / লাভ-ক্ষতি
| L1 | লাভ-ক্ষতি (P&L) / Profit & loss by period & shop | Sales − COGS − expenses − salary − fixed = ? (each line labelled source/uncosted share) | sales,item_costs,10-2,02-2,settings fixed_cost_month | shop | E+J | ₵ | P1 |
| L2 | আইটেম/ক্যাটাগরি মার্জিন / Margin by item & category | Which product earns? | sales.lines × cost | item, category | E | ₵ | P1 |
| L3 | দোকান P&L তুলনা / Shop P&L comparison (rent burden if rent captured) | Which shop is weak? | L1 per shop | – | E+J | ₵ | P1 |
| L4 | মালিকের মাসিক শিট বনাম সিস্টেম / Owner 01-2 sheet vs system | Do typed P&L figures match computed? | entries 01-2 + L1 | month | J | ₵ | P2 |
| L5 | ব্রেক-ইভেন ও কস্ট কভারেজ / Break-even & cost coverage | Sales needed; % sales with no cost | biz_daily (exists) + settings | – | E | ₵ | P2 |

### K. Control / Exceptions / Audit
| X1 | ব্যতিক্রম তালিকা / Exceptions | Open/resolved by level, form, shop, age, time-to-resolve | exceptions | level, form, status | E | – | P1 |
| X2 | ছাড়, জরুরি অনুমোদন, গ্রান্ট ব্যবহার / Releases, emergency, grant use | Who bypasses rules how often | release_requests, emergency_requests | staff, grant | E | – | P1 |
| X3 | অডিট ও সংশোধন লগ / Audit & correction log | Who changed what (price, cost, rules) | audit_log, corrections | table, user | E | owner-only | P1 |
| X4 | ফর্ম জমার নিয়ম-পালন / Form compliance | Missing 14-1/10-1 per shop-day, stale drafts, late submits | entries | form, shop | E | – | P1 |
| X5 | স্টাফ সূচক ধারা / Staff indicators over time | Same as biz_staff but monthly trend | exists biz_staff | – | E | – | P3 |

### L. Paper-number gaps / ছাপা নম্বর
| G1 | নম্বরের ফাঁক / Gap audit | Missing paper numbers | number_audit (exists) | form, shop, date | E | – | P1 (reuse) |
| G2 | ডুপ্লিকেট/উল্টো ক্রম ও বই-ব্যবহার / Duplicate, out-of-order, book usage | Same number twice? dates going backward? | entries paper_no | form, shop | E | – | P2 |

### M. Marketing / মার্কেটিং
| M1 | গ্রাহক সেগমেন্ট (RFM) / Customer segments | Champions, at-risk, one-time | sales | – | E | – | P3 |
| M2 | মার্কেটিং খরচ বনাম বিক্রি / Marketing spend vs sales | Spend by head vs sales in same days (correlation only, no causal claim) | 18-1 + sales | head | J | – | P3 |

### N. Compliance / মান ও নিয়ম
| Q1 | ফ্রিজ তাপমাত্রা লগ / Fridge temperature log | Out-of-range days, which fridge | 14-1/05-1 temp (+ limits in location_settings) | fridge | J | – | P2 |
| Q2 | হাইজিন, মেয়াদ ও চেকলিস্ট পালন / Hygiene, expiry & checklist compliance | Skipped steps, expired shown | 14-1, 05-1 | shop | J | – | P2 |
| Q3 | অভিযোগ ও রিটার্নের কারণ / Complaints & return root causes (+ VAT/Mushak when owner confirms) | Repeat product/shop complaints | 20-3 | product, cause | J | – | P2 |

Totals: P1 = 30, P2 = 24, P3 = 11. New capture needed: K1, K5, F3 (+ supplier master for P3/P4, budgets for any "vs budget"). Everything else is derivable from data already captured.

Business-logic rules for all reports: no invented thresholds (age buckets, near-limit %, low-stock, margin floor come from rules/location_settings; empty -> "Data needed"); every cost figure states "uncosted share"; indicators are labelled "worth a look", not proof; period always shown; closed-book dates respected.

## 2. Engine design (one definition + one RPC)
**Report definition (JS spec in web/reports_defs.js, one object per report):** `{key, group, title:L(bn,en,mix), question, source:'sales_fact'|..., dims:[{k,label,type}], measures:[{k,label,agg,fmt,cost:bool,ownerOnly:bool}], filters:[date,loc,staff,item,category,paymode,customer,saletype,...], defaultGroup, defaultSort, compare:true, drill:{dim->reportKey or document}, minRole/grant}`. UI is generic: filter bar (bottom sheet), group-by chips, compare toggle, sort header, search, column picker, results as cards on phone / scroll table on wide, totals row, export.
**One RPC:** `report_run(p_key text, p_filters jsonb, p_group text[], p_measures text[], p_sort jsonb, p_page jsonb, p_compare text)` returns jsonb `{columns, rows, totals, compare_rows, next_cursor, uncosted_pct, truncated}`. Server holds the catalogue in table `report_catalog(key, source, dims jsonb{dim:sql_expr}, measures jsonb{m:{expr,cost,owner_only}}, base_where, min_grant)`; the dispatcher builds SQL ONLY from catalogue whitelist expressions (format %I/%L; user input is never SQL). Rows with non-aggregable shape (lists like register, exceptions) use same RPC with `p_group = '{}'`.
**Fact layer (key to performance and to the 42 jsonb forms):** (1) `sales_fact` view: sales exploded by `jsonb_array_elements(lines)` joined to items + current cost (cost columns exist only in a view that is revoked from everyone but a security-definer function that checks biz_cost_ok). (2) `entry_facts` table: typed rows (entry_id, form_code, location_id, date, kind, party/supplier, item_id, qty, amount, ref, status) written by an AFTER trigger when an entry becomes approved, from a small per-form extractor (js spec already knows the field keys) — backfill once. Reports read facts, never parse jsonb at query time. (3) `rpt_daily` rollup (date x location x staff x paymode x saletype x category: n, revenue, discount, voids, due, cogs) maintained by trigger/ nightly job; used for trends/combined shop views so phone queries touch hundreds not millions of rows. Compare-period = same query on shifted range in the same call (prev period / same weekday last week / same month last year).
**Pagination:** aggregate results capped (e.g. 500 groups, show "top N + others"); lists use keyset cursor (sold_at,id) page 50; totals computed server-side so they are right beyond page 1 (fixes the PostgREST 1000-row cap already hit once). Hard `statement_timeout` ~8 s and max range 366 days for line-level reports.
**Security:** SECURITY DEFINER RPC, always filter `location_id` by can_loc (management/owner all); report needs grant `report_<group>` (reuse rule_grants/grant_defs so owner decides who sees which group, per role); cost/salary measures dropped server-side unless owner or ITEM_COST view; customer mobile masked unless POS approve; export is a separate grant (`report_export`) and logged in audit_log; staff PIN/lock unchanged.
**Saved views:** `report_views(id, owner, report_key, name, spec jsonb {filters,group,sort,columns,compare,preset}, shared_roles text[])`; date presets stored as presets (e.g. "this_month"), not fixed dates; RLS own + shared.
**Export:** CSV built client-side from paged full result (BOM for Excel, Bangla headers); Print/PDF via print stylesheet + window.print (avoids shipping a Bangla font into a PDF lib, works on phone "Save as PDF"); each export footer shows filters, period, who/when, and "cost shown/hidden". Share-as-image optional later.
**Drill-down:** every aggregate row carries `drill` = {report, filters} (shop -> day -> receipts -> single receipt/entry via existing openentry); breadcrumb back; filter chip state preserved.
**Phone UX:** Reports hub = group tiles + search box + "recent" + "my saved views"; one screen per report, filters in sheet, sticky totals; 3 language modes via existing `L()`; no chart libraries beyond the existing bar style (maybe one simple line/bar SVG).

## 3. Already exists — do NOT rebuild (wrap/link or extend)
- Home dashboard problems list, today numbers, 7-day bars (dash.js). Business analysis page (#/biz): daily/margin/break-even/outlook/ABC/staff indicators/limit suggestions -> becomes reports L5, S4 (ABC part), T1/X5 sources; reuse biz_daily/biz_items/biz_staff/biz_outlook/biz_suggest as report sources.
- Dues page, customer_dues, customer_ledger, collections (D1, ledger) ; payments_summary, sales_summary; number gap audit (G1); pending approvals page; exceptions/release/emergency queues (X1/X2 only need history/filters, not new queues); audit log (raw data exists; only a browser is new).
- Rules/grants/lists/location-limits infrastructure: use it for thresholds and report permissions.

## 4. Risks and open questions
Risks: (1) jsonb extraction drift if a form field is renamed — fact extractors need tests per form; (2) cost uses CURRENT cost, so old-period margin is restated when cost changes -> consider snapshotting cost into sale lines going forward (cost visible only server-side); (3) quick sales uncosted -> margin shown on costed part only, always display coverage %; (4) no perpetual stock -> K1/K6 are unreliable until counts and write-offs are disciplined; show "as of last count" label; (5) supplier names free text -> duplicates in supplier reports until a supplier list exists; (6) phone performance if reading line-level data over a year; (7) role leakage via export or drill-down (re-check grant at every level); (8) Supabase plan limits for pg_cron/materialised views; (9) reports for locations with few days of data are noisy — show sample size/"Data needed".
Open questions for owner: Which 15-20 reports first (suggest the P1 set)? Fiscal year start? Does Bng-Eng mode name rows bilingual? Who besides owner may see cost/salary/P&L (management only)? Are expense heads/units/age-buckets to be editable lists? Is a supplier list and raw-material list acceptable to add? Do you want a wastage write-off form (reason list: expired, broken, tasting, return)? Is rent per shop to be captured (for shop P&L)? Budgets per shop/head (needed for vs-budget, currently none)? VAT/Mushak requirement pending adviser. Is approver of discounts stored on sales (need check in record_sale2) for S9?
Suggested build order: engine + sales_fact + S1-S6, W4, D1-D4 (all structured data, ~no new capture) -> entry_facts for expenses/purchases/cash (E1-E3, P1, P3, W1-W3, C1-C2) -> P&L (L1-L3) -> stock (needs new capture) -> rest.
