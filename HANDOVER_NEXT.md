# HANDOVER_NEXT — ইসলামিয়া মিষ্টি ঘর BOS app (full handover)
Written 2026-10-25. Read this first, then `docs/HANDOVER.md` (detailed rules, test commands, build waves) and `docs/AUDIT.md`.

---
## 1. মূল দাবি ও feature তালিকা

### 1.1 Owner কী চান
ফোন-ওনলি owner (বাংলা/Bng-Eng লেখেন), "ইসলামিয়া মিষ্টি ঘর" (hub + ৭ লোকেশন) এর জন্য **ফ্রি** (Supabase free + GitHub Pages, ডোমেইন নেই) staff data-entry app + owner dashboard। BOS Build Kit-এর ৪২ ফর্ম, POS, স্টক, ক্রয়, রিপোর্ট, নিয়ন্ত্রণ।
স্থায়ী নিয়ম (owner-এর):
- ব্র্যান্ড সব ভাষায় ফিক্সড: **ISLAMIYA MISTY GHAR / ইসলামিয়া মিষ্টি ঘর** (অনুবাদ/বানান বদল নয়)। অন্য ব্র্যান্ড: মিষ্টি বাড়ি ("MISTY BARI" ধরা, owner নিশ্চিত করেননি), AL-CAKIZ।
- ৩ ভাষা মোড: বাংলা / Bng-Eng (হাইফেনসহ "Count-এর") / English।
- **কোনো সংখ্যা বানানো যাবে না**; সীমা সেটিংস থেকে, ফাঁকা = "Data needed"।
- **সবকিছু সেটিংসে অন-অফ**: সম্পাদনা, বাড়ানো-কমানো, যোগ-বাদ, সক্রিয়/নিষ্ক্রিয়, তালা/খোলা, লুকানো/দেখানো; owner যে-কাউকে ক্ষমতা দিতে পারবে (বা না-ও), যেকোনো সময় বন্ধ/চালু। ⋮ (তিন-ডট) মেনু অনেক জায়গায়।
- কাগজ + অ্যাপ **একসাথে**: কাগজের নম্বর unique/আলাদা, অ্যাপের নম্বর আলাদা, "পরে লেখা" + কাগজের সিরিয়াল + আসল সময়; per ফর্ম × লোকেশন Paper/Parallel/App সুইচ (চালু ফর্ম App দিয়ে শুরু)।
- ব্লাইন্ড গণনা সার্ভারে, তবে অনুমতিপ্রাপ্ত ব্যক্তি আগে প্রত্যাশিত অঙ্ক দেখতে পারবে (সুইচ)।
- আইটেম মাস্টার = পুরো ব্যবসার (সম্পদ, কাঁচামাল, প্যাকেজিং, কিনে-বিক্রি, তৈরি পণ্য): সম্পদ কখনও স্টক/বিক্রি/COGS-এ নয়; কাঁচামাল সরাসরি বিক্রি নয়; সম্পদ কিনলে আইটেম তালিকায় নিজে যোগ; কোড স্থায়ী, পুনর্ব্যবহার নয়, মোছা নয় (নিষ্ক্রিয়)।
- আর প্রশ্ন নয়: যুক্তি দিয়ে ডিফল্ট ঠিক করো, সুইচ রাখো। ডিজাইনে এখন হাত নয় (design-system artifact কেবল রেফারেন্স)।
- মালিকের নিজের অনুরোধ নিজে অনুমোদন: সুইচ (ডিফল্ট: owner exempt)।

### 1.2 Feature তালিকা (যা তৈরি আছে — বিস্তারিত docs/MODULE_MAP.md)
| এলাকা | কী আছে |
|---|---|
| Auth | Staff ID + PIN (fake email `<id>@staff.islamia-bos.app` + `<pin>-bos`), role × form permission, location scope, rules/grants/per-person grants/emergency requests |
| ৪২ ফর্ম | ৪১টা JS spec (entries.data jsonb), ০-১ = Location settings screen; count-first, লাল exception + owner release, change log, photo, supplier picker, paper-number গ্যাপ অডিট |
| POS v2 | item-wise + quick sale, split/partial payment, customer (due/wholesale-এ মোবাইল বাধ্যতামূলক), বাকি আদায়, void, offline queue, discount টাকা/শতাংশ, barcode scan, রসিদ প্রিন্ট |
| Items v2 | `#/items`: filter, add/edit, Advance Options (sub-category, wholesale, unit, VAT, barcode, ≤৫ ছবি, tracked, min_stock), item-change approval |
| Stock (phase10) | append-only ledger, weighted-avg cost, batch/expiry (season shelf-life), wastage, transfer in-transit, opening, count adjust, issue, production; `#/stock` |
| Purchase | বিল (draft/post/void/return), supplier payment FIFO, payables, ledger; `#/purchase`, `#/payables` |
| Reports | `report_run` engine, ১৯ রিপোর্ট, ফিল্টার, তুলনা, ব্র্যান্ড/শোরুম/মোট, saved views, CSV/print; `#/reports` |
| Settings hub | `#/settings2`: fiscal year, week start, VAT on/off+rate, barcode camera/device (আলাদা), lock|hide, stock-negative mode, unit conversions, shelf-life seasons, suppliers, access manager (per-person grants), role favourites |
| Invoice | `#/invoice`: template designer (common/A4/thermal58/80/label), প্রিন্ট profiles, barcode label |
| UI v2 | calm mode, drawer, bottom nav, home v2 (Business/Accounting, period tabs, favourites/pins server-synced) |
| Lists | editable `option_lists` (expense/marketing heads, wallets, categories, units, wastage/return reasons…) |
| Backup/Logs | Backup tile, change log (audit_log), exceptions, release requests |

---
## 2. কাজের অগ্রগতি

### 2.1 Done (tested)
- phase 1–10 SQL লেখা + local test: phase8 106/106, phase9 125/125, phase10 307/307; ১৪টা Playwright suite সবুজ (allforms pos2 rules lists biz nav reports settings2 invoice favsync items2 barcode stock2 purchase)।
- প্রতিটা বড় phase আলাদা adversarial audit এজেন্ট দিয়ে অডিট + সংশোধন (phase7, 8, 9, 10)।
- Owner আসল DB-তে চালিয়েছে (Success জানিয়েছে): schema, phase2, phase3+4, ALL_NEW (5+6+7), ALL_NEW2 (8+9), phase10 (ALL_NEW3.sql = phase10)।
- Plan docs: `docs/plan_v2/` (UI, REPORTS, BUSINESS, OWNER_ANSWERS, FUNCTIONS_PLAN), `docs/AUDIT.md` (Command-0 audit: ১৬ নিয়মের মধ্যে ১ Met, ১১ Partly, ৪ Not met), `docs/inputs/` (owner-এর দুটো ফাইল), `tests/` (portable test harness)।

### 2.2 বাকি (মাস্ট — owner বলেছে কিছু বাদ যাবে না) — ক্রম
**W0 carry-over (docs/HANDOVER.md §8, ২০টা):** items.details; view_cost-only user-এর cost; items-এ real low-stock; stock list category label/unit/item-name search; purchase/stock-এ barcode; Day-book টাইল; purchase বিলে stock-effect preview; stock/purchase ছবির আলাদা prefix; stock actions-এ emergency rule keys; wastage maker-checker; supplier refund + sale_return; expired-sale block সুইচ; salary report page; stock_ledger.ref_id leak বন্ধ; ফর্ম↔স্টক লিংক (04-1/04-2/04-3/03-1/05-1 → ledger, সুইচ, ডিফল্ট off; 04-4/06-5 view হবে); discount approver + ব্র্যান্ড-P&L + বাকি ৪৬ রিপোর্ট; nav leftovers (Year ট্যাব = fiscal rule, drawer search, location switcher, staff home); smoke.js + real-device চেক; নিরাপত্তা backlog; VAT বন্ধ।
**W1 hardening:** docs/BUILD-RULES.md + BUILD-LOG.md; BACKUP_TABLES সম্পূর্ণ (web/app.js ~448, এখন ১২টা); audit_log append-only; location/form/item code immutable; option/item delete revoke; সার্ভারে failed-login লগ + ৫ ভুলে ১০ মিনিট লক।
**W2 item master (phase11):** item_type (finished/resale/raw/packaging/consumable/asset/controlled/infrastructure) + flags (active/lock/hide/count-in-business); `docs/inputs/AL-CAKIZ_IMG_Master_Item_Dictionary_FINAL.xlsx` (১,৩১২ আইটেম, ২৫ ক্যাটাগরি, কোড `01-001`, দাম নেই) import **আগে dry-run**; পুরনো ৫৭ আইটেম (দামসহ) অক্ষত, best-match; asset register; নতুন আইটেম/ক্যাটাগরি/সরানো/⋮; asset কিনলে auto-add।
**W3 lists:** add rule (open|approval|owner), retire, Other queue, similar-name, shared list control (search/Add new/Other) ফর্ম ধরে ধরে।
**W4 locations + Control Center:** kind/model/status/hub, নতুন শোরুম + ১৭ ধাপ, pause/close; ১২ টাইল; head-management স্তর; merged Needs-you; settings sheet 0-1 ভার্সনসহ + getLimit (আমাদের ৩৮ key ↔ কাগজের ১–৩১, ৭ক–৭চ ম্যাপ)।
**W5 সার্ভারের নিয়ম:** server-withheld blind count + see-expected grant; PIN স্বাক্ষর সুইচ; approve-এর পর lock + revision + change request; ফর্ম offline queue; entered-later + paper serial; Paper/Parallel/App সুইচ; owner-self-approval সুইচ। ১৪-১ ও ১০-১ আগে। ৪১ ফর্ম নতুন করে বানানো নয় — পাশে server check।
**W6 recipe/BOM + packaging:** প্রতি কেজি মিষ্টিতে কাঁচামাল, প্রতি বিক্রিতে প্যাকেজিং, production-এ raw material নিজে কমা।
**W7:** প্রতি ফর্ম কাগজের সাথে মিলানো (docs/forms/*.md), রিপোর্ট শেষ, ফর্ম↔স্টক।

প্রতি ধাপের চক্র: লেখা → আলাদা audit agent → fix → সব test নিজে চালানো → commit/push → owner-কে এক-পেস্ট SQL পেজ।

---
## 3. খোলা সমস্যা ও সিদ্ধান্ত

### 3.1 সিদ্ধান্ত নেওয়া (আর জিজ্ঞেস করো না)
Controlled Item = আলাদা "tools stock" count (ডিফল্ট off, সুইচ); নতুন আইটেম অনুমোদন = owner বা owner যাকে দেয়; পুরনো ৫৭ আইটেম best-match, বাকি "needs decision"; কাগজ/অ্যাপ নম্বর আলাদা; চালু ফর্ম = App; spec-এর ১৮ খোলা প্রশ্ন → নিরাপদ ডিফল্ট + BUILD-LOG-এ লেখা + সুইচ; spec-এর নতুন `lists/list_options` টেবিল নয় → আমাদের `option_lists` বাড়াও; ফর্ম-ইঞ্জিন বদল নয়; নিরাপত্তা: শুধু public URL + publishable key, কখনও service_role/DB password নয়।
চালিত ডিফল্ট rule: `vat_on=false`, `stock_negative_mode=warn`, `ui_noperm_mode=lock`, `costing_method=avg`, discount amount+percent দুটোই on, barcode camera/device off।
স্থির নকশা-সিদ্ধান্ত: ইমার্জেন্সি window লোকেশন-নির্দিষ্ট হলেও `has_grant(code)` (p_loc null) তা গ্রহণ করে — ইচ্ছাকৃত (time-boxed, owner-অনুমোদিত, লগড)।

### 3.2 খোলা ঝুঁকি / সমস্যা
| # | বিষয় | অবস্থা |
|---|---|---|
| 1 | VAT/Mushak 6.3 হার | অনিশ্চিত; রসিদে VAT লাইন বন্ধ; হার বানানো যাবে না; হিসাবরক্ষক নিশ্চিত করবেন |
| 2 | "MISTY BARI" ইংরেজি বানান | assumed, unconfirmed |
| 3 | Real-device পরীক্ষা (থার্মাল প্রিন্টার ৫৮/৮০, ক্যামেরা বারকোড, ফোনে offline sale sync, Chrome auto-translate) | কখনও হয়নি — owner-কে করতে বলো |
| 4 | Blind count/PIN স্বাক্ষর/limit চেক শুধু browser-এ; PIN lockout browser-based (`login_failed` যে কেউ ডাকতে পারে); audit_log mutable | W1/W5-এ বন্ধ করতে হবে |
| 5 | ফর্ম (04-1 ইত্যাদি) এখনও paper-style; নতুন stock/purchase পেজ সরাসরি ledger-এ লেখে (দুই জায়গা) | W0 #15 |
| 6 | কারখানার/নিয়মগুলো: কোন ফর্ম live আর কোন প্লেস live — owner-এর কাছ থেকে নিশ্চিত নয় (AUDIT প্রশ্ন ১, ২) | লগে লিখে নিরাপদ ডিফল্ট |
| 7 | সম্পদ/কাঁচামাল/প্যাকেজিং-এর recipe হিসাব নেই | W6 |
| 8 | নতুন আইটেম আমদানির পর দাম নেই → POS-এ "Data needed" | owner দাম বসাবে |
| 9 | Margin পুরনো সময়ের জন্য আজকের cost দিয়ে (cost snapshot নেই) | পরবর্তী চিন্তা |
| 10 | Supabase free plan limits (pg_cron, storage) যাচাই হয়নি | চেক করো |
| 11 | sandbox থেকে supabase.co পৌঁছানো যায় না → আসল DB-তে SQL শুধু owner চালাতে পারে। *নোট:* এই সেশনে `mcp__Supabase__*` টুল তালিকায় এসেছে; **owner-এর স্পষ্ট অনুমতি ছাড়া ব্যবহার করবে না**, আর ব্যবহার করলেও আগে backup + dry-run | সিদ্ধান্ত owner-এর |

---
## 4. Repo, branch, Supabase, URL
| বিষয় | মান |
|---|---|
| প্রাইভেট repo | `https://github.com/mistybari99/My-tools` — branch **`ccr-78d03e25-k7ksyo`** (সব কাজ: web/, supabase/*.sql, docs/, tests/, data/items_seed.csv **cost সহ — কখনও public নয়**) |
| পাবলিক repo | `https://github.com/mistybari99/islamia-bos-app` — branch `main` — শুধু `web/` কপি + অস্থায়ী `setup-sql.html` (cost/secret নেই) |
| Live app | https://mistybari99.github.io/islamia-bos-app/ |
| One-paste SQL পেজ | https://mistybari99.github.io/islamia-bos-app/setup-sql.html (`const SQL=` লাইন নতুন SQL দিয়ে বদলাও; কাজ শেষে মুছে ফেলো) |
| Supabase project ref | `rpqrcmesbhwtyrikabhy` |
| Supabase URL | https://rpqrcmesbhwtyrikabhy.supabase.co |
| Dashboard / SQL editor | https://supabase.com/dashboard/project/rpqrcmesbhwtyrikabhy/sql/new |
| Publishable (anon) key | `web/config.js`-এ আছে (public, শিপ করা নিরাপদ). service_role/secret/DB password **কখনও না** |
| Local clone path (এই sandbox) | `/home/user/My-tools`, `/home/user/islamia-bos-app` (না থাকলে re-clone) |
| SQL ফাইল | `supabase/schema.sql, phase2–10.sql`, `ALL_NEW.sql` (5+6+7), `ALL_NEW2.sql` (8+9), `ALL_NEW3.sql` (10) |
| Tests | `tests/web/*_test.js` (`node tests/web/X_test.js tests/web`), `tests/sql/` (`build_fresh_db.sh`, mocks), `supabase/phase8_test.sql`, `phase10_test.sql`, `tests/sql/p9/` ; local PG16 cluster `/tmp/pgtest` port 5544 |
| ডকস | `docs/HANDOVER.md`, `docs/AUDIT.md`, `docs/MODULE_MAP.md`, `docs/ROADMAP.md`, `docs/DECISIONS.md`, `docs/LANGUAGE.md`, `docs/plan_v2/*`, `docs/inputs/*` |
| Publish ধাপ | `cp web/*.js web/*.css web/index.html → islamia-bos-app/`, commit, push main |

### নতুন চ্যাটের প্রথম বার্তা
> `HANDOVER_NEXT.md` আর `docs/HANDOVER.md` পুরোটা পড়ো। §2.2-এর W0 থেকে W7 সব ক্রমানুসারে করো। প্রশ্ন কোরো না, যুক্তি দিয়ে ডিফল্ট ঠিক করো, সব জায়গায় অন-অফ সেটিংস রাখো। প্রতি ধাপে: লিখো → আলাদা এজেন্টে অডিট → টেস্ট → commit/push → আমাকে এক-পেস্ট SQL পেজ। আসল ডেটা বদলানোর আগে dry-run দেখাবে।
