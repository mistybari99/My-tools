# Form names and sequence: proposal (42 printed forms)

## সারসংক্ষেপ (বাংলা)

- মোট ছাপা ফর্ম ৪২টি (`schema.sql`-এর `forms` seed: ৪১টি `NN-N` কোড + `0-1` লোকেশন সেটিংস শিট)। ৪২টির সবগুলোর নাম (বাংলা ও ইংরেজি) আগে থেকেই আছে, তাই অ্যাপে নতুন নাম যোগ করার দরকার ছিল না।
- মালিকের সর্বশেষ সিদ্ধান্ত: ফর্ম এখনো ছাপা হয়নি, তাই কোড বদলানো যাবে। বিকল্প B নেওয়া হয়েছে: ফর্মগুলো ছোট নামের A-Z ক্রমে সাজানো হবে, নতুন কোড `01-1` থেকে `41-1`। `0-1` (লোকেশন সেটিংস) অপরিবর্তিত থাকবে, কারণ অ্যাপ লিটারেল `'0-1'` ধরে কাজ করে।
- এই ধাপে কোনো কোড বদলানো হয়নি। `tools/numbering_map.json`-এর `form_groups_approved` `false` রয়েছে। `renumber.py --apply` চালানো হয়নি।
- ড্রাই রানে তিনটি সমস্যা ধরা পড়েছে: (১) ফর্ম কোডের মানচিত্র এখনো গ্রুপ-ভিত্তিক, প্রতিটি কোড ধরে সাজানো নয়; (২) এই মানচিত্রে `--apply` দ্বিতীয়বার চালালে কোড আবার বদলে যাবে; (৩) নতুন কোডের ১২টি স্ট্রিং আগের অন্য ফর্মের পুরনো কোডের সমান। অ্যাপ্লাই-এর আগে এগুলো ঠিক করতে হবে।
- ডাটাবেসে `form_code` ২০টির বেশি টেবিলে আছে এবং `forms.code` পরিবর্তন-অযোগ্য ট্রিগার আছে। তাই এটি শুধু কোড বদলানোর কাজ নয়; এর জন্য মালিকের পেস্ট করার নতুন phase ফাইল লাগবে। এজেন্ট লাইভ ডাটাবেসে কিছু লিখবে না।
- মালিকের যা নিশ্চিত করতে হবে: নিচের তালিকা ৭ নম্বর বিভাগে।

## 1. Options

- **Option A (আগে প্রস্তাবিত, এখন নেওয়া হয়নি):** সব ছাপা কোড অপরিবর্তিত; শুধু নাম ও সূচি যোগ।
- **Option B (মালিক বেছেছেন):** A-Z সংক্ষিপ্ত নাম অনুযায়ী ক্রম; মানচিত্র `docs/FORM_SEQUENCE.md` সেকশন ৪-এ।

## 2. Inventory (42 forms, code order)

Columns: current code; area (seed); kit file that defines the form screen; name in the database seed (English); short name (EN / BN); Option A position (seed `sort`); Option B new code.

| Code | Area | Kit file | Seed name (EN) | Short name (EN / BN) | A pos | B new |
|---|---|---|---|---|---|---|
| 0-1 | settings | nav.js (special case) | Location Settings Sheet | Location Settings / লোকেশন সেটিংস | 5 | 0-1 (fixed) |
| 01-1 | owner | forms_sales.js | Weekly Review Note | Weekly Review / সাপ্তাহিক রিভিউ | 23 | 40-1 |
| 01-2 | owner | forms_sales.js | Monthly P&L and KPI Sheet | Monthly P&L and KPI / মাসিক P&L ও KPI | 24 | 20-1 |
| 02-1 | staff | forms_staff.js | Monthly Attendance Register | Monthly Attendance / মাসিক হাজিরা | 25 | 19-1 |
| 02-2 | staff | forms_staff.js | Monthly Salary Sheet | Monthly Salary / মাসিক বেতন | 26 | 21-1 |
| 02-3 | staff | forms_staff.js | Staff Advance Register | Staff Advance / স্টাফ অ্যাডভান্স | 27 | 35-1 |
| 02-4 | staff | forms_staff.js | Appointment Letter — Terms & Duties | Appointment Letter / নিয়োগপত্র | 28 | 01-1 |
| 02-5 | staff | forms_staff.js | Leave Application | Leave Application / ছুটির আবেদন | 29 | 15-1 |
| 02-6 | staff | forms_staff.js | Exit Clearance Form | Exit Clearance / এক্সিট ক্লিয়ারেন্স | 30 | 10-1 |
| 02-7 | staff | forms_staff.js | Duty & Backup Card | Duty and Backup Card / ডিউটি ও ব্যাকআপ কার্ড | 36 | 09-1 |
| 02-8 | staff | forms_staff.js | Skill Checklist | Skill Checklist / স্কিল চেকলিস্ট | 37 | 34-1 |
| 03-1 | stock | forms.js | Transfer Challan (IBT) | Transfer Challan / ট্রান্সফার চালান | 2 | 39-1 |
| 04-1 | stock | forms_stock.js | Goods Received Note (GRN) | Goods Received (GRN) / মালামাল গ্রহণ (GRN) | 8 | 13-1 |
| 04-2 | stock | forms_stock.js | Material Issue Slip | Material Issue / মালামাল ইস্যু | 9 | 18-1 |
| 04-3 | stock | forms.js | Stock Count Sheet | Stock Count / স্টক কাউন্ট | 21 | 36-1 |
| 04-4 | stock | forms_stock.js | Store Ledger | Store Ledger / স্টোর লেজার | 39 | 37-1 |
| 05-1 | factory | forms_factory.js | Factory Daily Sheet | Factory Daily / কারখানা দৈনিক | 12 | 12-1 |
| 05-2 | factory | forms_factory.js | Product Spec Card | Product Spec Card / প্রোডাক্ট স্পেক কার্ড | 13 | 26-1 |
| 05-3 | factory | forms_factory.js | Recipe Card | Recipe Card / রেসিপি কার্ড | 34 | 31-1 |
| 05-4 | factory | forms_factory.js | Yield Test Sheet | Yield Test / ফলন টেস্ট | 35 | 41-1 |
| 05-5 | factory | forms_factory.js | New Product Decision Sheet | New Product Decision / নতুন প্রোডাক্ট সিদ্ধান্ত | 42 | 22-1 |
| 06-1 | purchase | forms_stock.js | Purchase Requisition | Purchase Requisition / পারচেজ রিকুইজিশন | 14 | 28-1 |
| 06-2 | purchase | forms_stock.js | Comparative Statement (CS) | Quotation Comparison / কোটেশন তুলনা | 15 | 29-1 |
| 06-3 | purchase | forms_stock.js | Purchase Order (PO) | Purchase Order / পারচেজ অর্ডার | 16 | 27-1 |
| 06-4 | purchase | forms_stock.js | Bill Check & Payment Request | Bill Check and Payment / বিল যাচাই ও পেমেন্ট | 17 | 02-1 |
| 06-5 | purchase | forms_stock.js | Supplier Ledger | Supplier Ledger / সাপ্লায়ার লেজার | 18 | 38-1 |
| 08-1 | assets | forms_sales.js | Maintenance Request & Record | Maintenance Request / মেইনটেন্যান্স অনুরোধ | 31 | 16-1 |
| 10-1 | cash | forms.js | Cash Handover Slip | Cash Handover / ক্যাশ হ্যান্ডওভার | 4 | 03-1 |
| 10-2 | cash | forms.js | Expense Voucher | Expense Voucher / ব্যয় ভাউচার | 7 | 11-1 |
| 10-3 | cash | forms_cash.js | Digital Payment Reconciliation Register | Digital Payment Reconciliation / ডিজিটাল পেমেন্ট রিকনসিলিয়েশন | 19 | 07-1 |
| 10-4 | cash | forms_cash.js | Cash Position & Purchase Budget | Cash Position and Budget / ক্যাশ পজিশন ও বাজেট | 20 | 04-1 |
| 10-5 | cash | forms_cash.js | Receivable & Advance Reconciliation | Receivable and Advance / প্রাপ্য ও অ্যাডভান্স | 22 | 30-1 |
| 11-1 | staff | forms_staff.js | Shift Handover Register | Shift Handover / শিফট হ্যান্ডওভার | 6 | 33-1 |
| 14-1 | showroom | forms.js | Daily Showroom Sheet | Daily Showroom Sheet / দৈনিক শোরুম শিট | 1 | 06-1 |
| 14-2 | showroom | forms_cash.js | Jalebi Counter Daily Record | Jalebi Counter Daily / জিলাপি কাউন্টার দৈনিক | 38 | 14-1 |
| 18-1 | sales | forms_cash.js | Marketing Expense Register | Marketing Expense / মার্কেটিং ব্যয় | 40 | 17-1 |
| 20-1 | sales | forms_sales.js | Customer Order Form | Customer Order / কাস্টমার অর্ডার | 3 | 05-1 |
| 20-2 | sales | forms_sales.js | Discount Approval Slip | Discount Approval / ডিসকাউন্ট অনুমোদন | 10 | 08-1 |
| 20-3 | sales | forms_sales.js | Return & Complaint Register | Return and Complaint / রিটার্ন ও অভিযোগ | 11 | 32-1 |
| 20-4 | sales | forms_sales.js | Party & Wholesale Invoice | Party and Wholesale Invoice / পার্টি ও পাইকারি ইনভয়েস | 32 | 24-1 |
| 20-5 | sales | forms_cash.js | Party & Wholesale Ledger | Party and Wholesale Ledger / পার্টি ও পাইকারি লেজার | 33 | 25-1 |
| 20-6 | sales | forms_cash.js | Online & Delivery Ledger | Online and Delivery Ledger / অনলাইন ও ডেলিভারি লেজার | 41 | 23-1 |

Note: the "A pos" column is the seed `sort` value in `supabase/schema.sql`. The kit file is where `B.forms[code]` is defined. The short names are proposals; they are the owner's to confirm.

## 3. App names: what was checked

- Names for all 41 printed forms come from the database `forms` table (`name_bn`, `name_mix`, `name_en`, read in `web/nav.js` and `web/app.js`) and from the form kit title (`B.forms[code].title`). No name was missing, so no name was added to the app.
- `0-1` has no form-kit entry (it opens `#/locset`); its name comes from the database seed only.
- Result: the app label layer is unchanged (360px layout unchanged). The new test (`tests/web/form_names_test.js`) asserts that every printed code has a name, and that the mapping in `docs/FORM_SEQUENCE.md` is complete and in order.

## 4. Option B collisions

**(a) Reused strings (new code = old code of another form), 12 of them.** Until the old text is changed, a reader of an old document sees the wrong form:

| New code | Now means (old) | After apply means |
|---|---|---|
| 01-1 | Weekly Review (01-1) | Appointment Letter |
| 02-1 | Monthly Attendance (02-1) | Bill Check and Payment |
| 03-1 | Transfer Challan (03-1) | Cash Handover |
| 04-1 | Goods Received (04-1) | Cash Position and Budget |
| 05-1 | Factory Daily (05-1) | Customer Order |
| 06-1 | Purchase Requisition (06-1) | Daily Showroom Sheet |
| 08-1 | Maintenance Request (08-1) | Discount Approval |
| 10-1 | Cash Handover (10-1) | Exit Clearance |
| 11-1 | Shift Handover (11-1) | Expense Voucher |
| 14-1 | Daily Showroom Sheet (14-1) | Jalebi Counter Daily |
| 18-1 | Marketing Expense (18-1) | Material Issue |
| 20-1 | Customer Order (20-1) | Monthly P&L and KPI |

**(b) Dangling strings (old code that no form has after apply), 29 of them:** 01-2, 02-2 to 02-8, 04-2 to 04-4, 05-2 to 05-5, 06-2 to 06-5, 10-2 to 10-5, 14-2, 20-2 to 20-6. These strings must be read as "retired" after apply.

**(c) Not checked:** whether any new code string also appears in a non-form context (for example a version or an amount) was not checked by hand; the dry-run scan counts all `NN-N` strings.

## 5. Where each printed code appears (occurrence counts, substring scan of the repository)

Counts are textual occurrences of the old code in the tree (history docs included). "sql" = `supabase/`; "web" = `web/` (JS and JSON, including `web/data/info.json`); "tests" = `tests/`; "docs" = `docs/`; "tools" = `tools/`.

| Code | sql | web | tests | docs | tools | total |
|---|---|---|---|---|---|---|
| 0-1 | 30 | 39 | 7 | 76 | 3 | 157 |
| 01-1 | 4 | 8 | 71 | 40 | 0 | 123 |
| 01-2 | 14 | 11 | 73 | 40 | 0 | 138 |
| 02-1 | 83 | 37 | 71 | 106 | 3 | 300 |
| 02-2 | 214 | 50 | 101 | 209 | 1 | 575 |
| 02-3 | 63 | 19 | 39 | 80 | 0 | 201 |
| 02-4 | 5 | 7 | 52 | 20 | 0 | 84 |
| 02-5 | 4 | 10 | 36 | 20 | 0 | 70 |
| 02-6 | 3 | 9 | 63 | 20 | 0 | 95 |
| 02-7 | 7 | 7 | 118 | 29 | 0 | 161 |
| 02-8 | 7 | 7 | 55 | 29 | 0 | 98 |
| 03-1 | 42 | 27 | 122 | 99 | 0 | 290 |
| 04-1 | 149 | 62 | 100 | 162 | 4 | 477 |
| 04-2 | 44 | 30 | 53 | 67 | 1 | 195 |
| 04-3 | 145 | 37 | 45 | 138 | 3 | 368 |
| 04-4 | 9 | 24 | 43 | 42 | 0 | 118 |
| 05-1 | 121 | 39 | 122 | 163 | 3 | 448 |
| 05-2 | 3 | 7 | 71 | 22 | 0 | 103 |
| 05-3 | 9 | 12 | 77 | 43 | 0 | 141 |
| 05-4 | 22 | 12 | 62 | 44 | 3 | 143 |
| 05-5 | 3 | 8 | 56 | 27 | 0 | 94 |
| 06-1 | 3 | 12 | 52 | 35 | 0 | 102 |
| 06-2 | 3 | 10 | 34 | 24 | 0 | 71 |
| 06-3 | 31 | 26 | 53 | 43 | 6 | 159 |
| 06-4 | 26 | 20 | 61 | 45 | 3 | 155 |
| 06-5 | 5 | 22 | 76 | 38 | 0 | 141 |
| 08-1 | 23 | 14 | 61 | 48 | 1 | 147 |
| 10-1 | 141 | 77 | 93 | 179 | 6 | 496 |
| 10-2 | 498 | 91 | 171 | 478 | 4 | 1242 |
| 10-3 | 12 | 44 | 77 | 67 | 5 | 205 |
| 10-4 | 17 | 14 | 43 | 43 | 1 | 118 |
| 10-5 | 3 | 8 | 44 | 26 | 0 | 81 |
| 11-1 | 6 | 10 | 36 | 39 | 0 | 91 |
| 14-1 | 448 | 119 | 299 | 347 | 15 | 1228 |
| 14-2 | 5 | 7 | 89 | 35 | 0 | 136 |
| 18-1 | 57 | 51 | 98 | 120 | 1 | 327 |
| 20-1 | 97 | 37 | 128 | 106 | 2 | 370 |
| 20-2 | 34 | 14 | 34 | 59 | 0 | 141 |
| 20-3 | 32 | 19 | 73 | 58 | 3 | 185 |
| 20-4 | 50 | 15 | 66 | 61 | 0 | 192 |
| 20-5 | 3 | 8 | 45 | 25 | 0 | 81 |
| 20-6 | 26 | 17 | 53 | 42 | 1 | 139 |

Where the codes are stored as data (these must change in the same apply step, through a new phase file):
- `forms.code` (immutable trigger `forms_code_immutable`, `supabase/ALL_NEW4.sql`, `phase11.sql`), referenced by foreign keys from tables that hold `form_code` (for example `supabase/schema.sql` line 58; the full list is below).
- Tables with a `form_code` column (20 found by a CREATE TABLE scan): blind_count_cfg, comparison_days, comparison_pairs, corrections, entries, entry_count_seals, entry_ledger_posts, exceptions, form_rollout, forms_ledger_cfg, list_other_entries, paper_books, parallel_months, pin_sig_cfg, print_notes, role_form_overrides133, role_form_perms, sale_form_links, serials, shortage_cash_cases. The `serials` table holds the paper-serial counter per form and location, so a renamed code can break numbering continuity. This was not checked against the live database (rule: no live access).
- Routes and links: `#/entry/new/<code>/...` in the web app. Old links and any queued offline entries that store a code are not verified here.
- Print and paper templates: `web/printbooks.js` contains codes (text search). `tests/web/rb_book.pdf` is a binary PDF and was not searched; any printed PDF outside this repository is not visible from here.
- Documentation and history: 478 files in the tree mention at least one printed code (count of distinct files, from the same scan). History documents are not rewritten.

## 6. Dry run (no writes)

Commands run from the worktree:

`python3 tools/renumber.py` (dry run) and `python3 tools/check_numbering.py`.

renumber.py summary:
- Phase files: pending renames **0**. Applied earlier: 9 (500->483, 540->491, 541->492, 542->493, 550->494, 551->495, 552->496, 553->497, 554->498). Collisions: 11 (480->479, 481->480, 490->481, 491->482, 510->484, 511->485, 520->486, 530->487, 531->488, 532->489, 533->490): the target phase file already exists, so the tool refuses these.
- Text references to old phase numbers: 0 lines to change. BLOCKED SQL lines (phase): 0.
- Form codes (`form_groups_approved = false`): **1304 lines in 201 files** would change under the current group-level map; **BLOCKED (non-comment SQL): 957**. Many of these are not form codes; the pattern `NN-N` also matches amounts, dates and version strings, so the 1304 figure is an upper bound and is not a list of forms.
- Numbers that are both old and new (480, 481, 490, 491): 134 references in 25 files, reported only.
- BLOCKERS: 11 phase collisions; 957 BLOCKED form-code lines in `supabase/*.sql`; 1304 form-code lines while the approval flag is false.
- The full dry-run text was written to `/tmp/form_wt_dryrun.txt` (outside the repository). Nothing in the repository was written by the dry run.

check_numbering.py: **RESULT: PASS** (0 failures, 0 warnings). 20 phase files in 479-498 have a _test pair or a "no test" note; no old-only reference left (500, 540-542, 550-554); 255 phases in ORDER.txt, no duplicates, no missing file; 0 missing include.

## 7. Decisions the owner must confirm (Option B)

1. The sort: plain A-Z by the English short name (section 2 table), with `0-1` kept as a fixed exception.
2. The code shape: `NN-1` (suffix `-1` for every form), or a bare two-digit `NN`. The first keeps the printed shape; the second is a separate, larger change.
3. The 12 reused strings (section 4a) and the 29 retired strings (4b): accepted, and how old documents are labelled.
4. The database migration: a new phase file (owner pastes it), covering the immutable trigger, the 20 `form_code` tables, and the paper-serial counters. Whether the owner accepts a rename of stored `entries.form_code` values, and when.
5. Whether the printed manual already exists. `docs/NUMBERING.md` says the forms are not printed yet; the owner's latest message says they are not yet printed. Confirm before apply.
6. Renumber tool: it must be extended to a per-code map and given an applied guard before `--apply`; until then the group-level map must not be applied.
7. The short names: confirm or edit the 41 English and Bangla short names (section 2).

Nothing in this proposal has been applied. `form_groups_approved` stays `false` until the owner gives the final approval after a clean dry run.
