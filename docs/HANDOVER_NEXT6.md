# HANDOVER NEXT 6: Islamia Misty Ghar BOS (পরবর্তী সেশনের জন্য, প্রথমে এটি পড়ুন)

তারিখ: 2026-10-25। ভিত্তি: repo-তে থাকা কোড ও docs। কোনো live write করা হয়নি।
ট্যাগ: `[code]` = repo-র কোড/SQL থেকে যাচাই; `[live]` = read-only SELECT-এ যাচাই (2026-10-16); `[owner]` = owner-এর পাঠানো "Success" বা নিশ্চিত তথ্য; `[unverified]` = যাচাই হয়নি।

> নোট: এই handover-এর ভিত্তি হিসেবে আগের handover (`HANDOVER_5.md`, phase 62 পর্যন্ত) ও `REMAINING.md`, `TODO.md`, `DECISIONS.md`, `ROADMAP.md`, `BUILD-LOG.md` পড়া হয়েছে। phase 63–69-এর কোনো SQL ফাইল repo-তে নেই; এগুলোর কাজ কোথায় আছে তা `[unverified]`।

---

## ১. মূল দাবি ও feature তালিকা

**মূল দাবি:** Islamia Misty Ghar-এর একটি মোবাইল-প্রথম ব্যবসা-পরিচালনা অ্যাপ (BOS)। কাগজের ৪২/৪৬টি ফর্ম (Form Kit v1.39) ডিজিটাল করা; প্রতিটি কাজে "এন্ট্রি করেন একজন, অনুমোদন করেন আরেকজন"; স্টক, নগদ, বিক্রি ও দিনের খাতা এক জায়গায়; মালিক নিয়ম ও সুইচ নিয়ন্ত্রণ করেন। `[owner]` (DECISIONS.md, ROADMAP.md)

**নীতি (owner সিদ্ধান্ত):**
- Staff ID + PIN লগইন (SMS OTP নেই; খরচের কারণে)। `[owner]`
- কোনো কিছু নিজে অনুমোদন নয় (maker ≠ checker)। মালিক switch দিয়ে নিজের কাজ অনুমোদন করতে পারেন (`owner_self_approve`)। `[owner][code]`
- Count-first, লাল পতাকা জমা আটকায়, হলুদ শুধু সতর্কতা। `[owner][code]`
- কোনো অনুমান করা সংখ্যা/সীমা/রেসিপি নেই; খালি মানে "তথ্য দরকার"। `[owner]`
- ভাষা: বাংলা / বাংলিশ / ইংরেজি তিন মোড। `[owner][code: i18n.js]`
- খরচ শূন্য: Supabase free plan + GitHub Pages। `[owner]`
- Cost price আলাদা permission (`ITEM_COST`)। `[owner][code]`

**Feature তালিকা (route অনুযায়ী, `web/ia.js`, ৯০টি route) `[code]`:**

| গ্রুপ | প্রধান স্ক্রিন (hash) |
|---|---|
| Dashboard | `#/home` (সমস্যা আগে, সংক্ষিপ্ত সংখ্যা) |
| আইটেম | `#/items`, `#/items/new`, `#/bulkitems`, `#/itemmap`, `#/itemimport`, `#/itemtypes`, `#/lists`, `#/settings2/units` |
| স্টক | `#/stock` (levels, expiring, transit, wastage approval, ledger), `#/stockx`, `#/assets` |
| ক্রয় | `#/purchase`, `#/purchase/new`, `#/purchase/return`, `#/payables`, `#/settings2/suppliers` |
| কারখানা | `#/recipes`, `#/recipebook`, `#/costing`, `#/costsources`, `#/costattrib` |
| বিক্রি | `#/pos` (POS, offline queue), `#/salereturn`, `#/onlineorders`, `#/inbox`, `#/flow` |
| গ্রাহক | `#/dues`, `#/customers`, `#/tiers`, `#/invoice` |
| হিসাব | `#/daybook`, `#/quickexp`, `#/cashmoves`, `#/ledgerlinks`, `#/accounts`, `#/finance2`, `#/employees`, `#/deeds` |
| অনুমোদন | `#/exceptions`, `#/pending`, `#/releases`, `#/emergency`, `#/changes`, `#/itemreq`, `#/numaudit`, `#/outbox`, `#/eqcheck`, `#/notifications` |
| রিপোর্ট | `#/reports`, `#/report`, `#/biz`, `#/brandpnl`, `#/discounts`, `#/biexport`, `#/assistant` |
| স্টাফ | `#/attendance`, `#/attend2`, `#/leave`, `#/payroll`, `#/salary`, `#/staff`, `#/matrix`, `#/benefitsx` |
| লোকেশন | `#/locations`, `#/locset`, `#/locsheet`, `#/rollout` |
| সেটিংস | `#/control`, `#/rulehub`, `#/owner`, `#/switchboard`, `#/paths`, `#/settings2`, `#/logs`, `#/backup`, `#/twofa`, `#/restoredrill`, `#/integrations`, `#/printbooks`, `#/delegation`, `#/partners`, `#/saleforms`, `#/parallel` |

Form registry: ৪৬টি form code (`web/forms*.js`) `[code]`; বিস্তারিত `docs/DEMO_DAY_SCREENS_STORIES_LEDGER_EN.md` §3.3।

---

## ২. কাজের অগ্রগতি

### Done (code আছে এবং test/owner যাচাই আছে, ক্রম অনুযায়ী)

| ধাপ | কী হয়েছে | যাচাই |
|---|---|---|
| P1 Core | auth (Staff ID+PIN), roles, matrix, items, approvals, audit log, backup | `[owner]` live |
| P2 Form engine | 14-1, 10-1, 10-2, 03-1, 04-3, exceptions, release, location settings | `[owner]` live |
| Hosting | GitHub Pages, owner registered, signup/login/home | `[owner]` live |
| P3a–c | POS, owner dashboard, photos (10-2, 04-1, 08-1) — phase3 | `[owner]`: user ran phase3 + phase4 "Success" |
| P4 | সব form (41 spec) live, 3 audit round | local test; `[owner]` live |
| POS v2 | customers by mobile, split payment, dues/FIFO, discount limit | phase5/6/ALL_NEW; `[unverified]` live |
| Rules & emergency | rules table, grants, emergency request, `#/rulehub` | phase7; tests pass locally |
| Plan v2 | masters, report engine (phase9), UI v2 | phase8 106/106, phase9 125/125 local |
| Items v2 + stock ledger | items2, barcode, stock2, purchase, payables (phase10) | phase10 307/307 local |
| Bulk items & item map | phase22, `#/bulkitems`, `#/itemmap` | 82/0 local, live `[unverified]` |
| IA rebuild | `web/ia.js` = single registry | ia_test local |
| Theme & controls kit | theme.css, icons3d, controls.js/css (phase30) | controls_test local; phone `[unverified]` |
| Groups A+B (phase23) | GRN vs purchase source, returns net, cash moves | ALL_NEW8/9 local |
| Groups C+D (phase24–28) | 34 reports, parallel comparison, print & books, needs-you | ALL_NEW9 local |
| P1 shadow engine (phase48–51) | path switches, shadow copies, day book vs journal, dup suspects, `#/paths`, `#/quickexp` | 48:54, 49:16, 50:45, 51:23 pass local |
| P2/P3 (phase52–54, 60–62) | accounts auto-post, finance2, attendance, stockx, online/BI/SMS, 2FA-tightened assistant | 52:33, 53:112, 54:84, 60:62, 61:114, 62:74 local |
| Restore drill & 2FA | phase70 (restore drill), phase71 (TOTP, safe core) | `[unverified]` live |
| Phase 72–79 integration | COGS single source, recipe master, costing/overhead, cost sources, sales channels & inbox, online order fixes, cost attribution, merged functions (phase79 LAST) | `[unverified]` live; test files present |
| Read-only audit | `docs/SUPABASE_READONLY_AUDIT.md`, 265 public tables, RLS on | `[live]` |
| Demo docs | 5 Bangla demo docs + `DEMO_DAY_SCREENS_STORIES_LEDGER_EN.md` (28 stories, ledger, balance sheet, 14 gaps) | docs only |

### বাকি (পুরোনো `REMAINING.md` ও `TODO.md` থেকে, এখনো অসম্পূর্ণ)

**Code বাকি:**
- P2: ~50 plain select এখনো `listctl` নয় (সব `TODO D1` tick হয়েছে, কিন্তু REMAINING #4 খোলা — পুনরায় যাচাই দরকার)।
- Hard-coded location list কিছু জায়গায় এখনো আছে (`forms_cash.js`, `forms_sales.js`, `forms_staff.js` duty slots)। `[code, TODO A3 tick]` — পুনরায় যাচাই।
- Blind count শুধু 14-1 ও 10-1 (TODO B2 tick আছে; REMAINING #7 পুরোনো)।
- Barcode/print, service worker — TODO D4 tick; `[unverified]` phone।
- 34 reports (TODO C1 tick), তবে মাঝে মাঝে পুরোনো তালিকা `REMAINING` P3 #8 এখনো বলে — পুনরায় যাচাই।
- Packaging line on receipt "unclear" (TODO status)।
- Production void/undo (TODO A5 tick)।
- Stock count-এ counter ও witness recorded নয় (demo gap G6)।
- Period lock (`period_closed_until`) ফাঁকা — ব্যবহার নেই (G9)।
- Count variance flag শুধু tolerance সেট থাকলে (G4)।
- Stock opening owner-only (G1), count adjust management-only (G2)।
- Short transfer receipt-এ stock "হারিয়ে যায়" — ledger row নেই (G3)।
- Issue-এ receiving place নেই (G7)।
- Branch cash → hub handover auto cash move নেই (G8, `[unverified]`)।
- `18-1` marketing expense ও `0-1` location settings — demo flow-তে নেই (G13)।
- Duplicate expense (10-2 ও quick expense) সতর্কতা নেই, শুধু report (G10)।

**Live/owner কাজ (code নয়):**
- Supabase Dashboard: `hook_password_verification_attempt` চালু (PIN lockout server-side)। `[owner TODO]`
- Leaked-password protection চালু; advisor-এর 12 anon SECURITY DEFINER, 80 function search_path, 34 RLS initplan, duplicate index ঠিক করা — owner অনুমোদন ছাড়া নয়। `[live]` audit
- phase22, phase23–28, phase48–54, phase60–62, phase70–79 — live DB-তে চালানো হয়েছে কি না নিশ্চিত নয়। শুধু phase3 + phase4 "Success" নিশ্চিত `[owner]`। **প্রথমে owner-কে জিজ্ঞেস করুন কোন phase কোন অবস্থায়।**
- Switch সিদ্ধান্ত: `tools_stock_on`, `blind_count_on`, `pin_signature_on`, `forms_post_to_ledger`, `packaging_consume_on`। `[owner]`
- Grants দেওয়া (see_expected, rollout_manage, change_approve, list_manage, location_manage)। live এ এখনো মাত্র owner + management একটি account `[live]`।
- Staff account তৈরি (17 demo roster) — শুধু test project-এ।
- `mishti_factory` (paused) পুনরায় চালু কি না — owner-এর সিদ্ধান্ত।
- VAT/Mushak 6.3 OFF; adviser-এর rate প্রয়োজন। `[owner]`
- `docs/DEVICE_CHECKLIST.md` — আসল ফোন ও প্রিন্টারে এখনো চালানো হয়নি। `[unverified]`
- Design pass (রং/টাইপোগ্রাফি/লেআউট) — সবশেষে (owner সিদ্ধান্ত)।

**Docs বাকি:**
- `setup-sql.html` (public repo) এখনো phase48–51 অনুযায়ী rebuild হয়নি। `[owner HANDOVER_5]`
- `docs/forms/<code>.md` per-form paper check (paper kit text repo-তে নেই) — TODO E2।
- `tools/kit_match.py` → `KIT_MATCH.md`: ~500 paper-only ও ~700 app-only label — মানুষের review দরকার।

---

## ৩. খোলা সমস্যা ও সিদ্ধান্ত

### ৩.১ Code/সিস্টেম সমস্যা (যাচাইকৃত)

| # | সমস্যা | প্রমাণ | পরবর্তী পদক্ষেপ |
|---|---|---|---|
| S1 | **Self-approve drift:** seed-এ `showroom_manager.allow_self_approve = true`, live-এ কোনো role-এ নেই। migration পুনরায় চালালে self-approve ফিরে আসতে পারে। | `[code: phase seed]`, `[live]` | Live রাখুন; একটি regression test যোগ করুন যা self-approve role পেলে fail করে। |
| S2 | **Maker-approver:** `decide_entry`-এ role-এর `allow_self_approve` থাকলে maker নিজে অনুমোদন করতে পারে। | `[code: phase17]` | S1 সিদ্ধান্তের পর ঠিক করুন। |
| S3 | **Short transfer = stock হারায়।** | `[code: phase10 stock_receive_transfer]` | `transit_loss` ledger reason + অনুমোদন (G3)। |
| S4 | **Count-এ counter/witness enforce নেই।** | `[code]` | `counted_by`/`witnessed_by` যোগ; `pin_signature_on` চালু (G6)। |
| S5 | **Period lock ফাঁকা।** Back-dated পরিবর্তন সম্ভব। | `[live]`, comment `ALL_NEW10` | Owner day-end এ close date সেট করুন (G9)। |
| S6 | **Count variance flag tolerance-এর ওপর নির্ভর।** | `[code: stock_count_adjust]` | Default tolerance সেট করুন বা ফাঁকা হলে warn (G4)। |
| S7 | **Security advisor** (উপরে)। | `[live]` audit | Owner অনুমোদনের পর ধাপে ধাপে। |
| S8 | **Schema drift রোধ:** repo-তে ALL_NEW/phase বহু সংস্করণ; কোনটি live-এ চলেছে তা অজানা। | repo ফাইল সংখ্যা ১২০+ | Live `list_migrations`/schema snapshot নিয়ে repo-র সাথে মেলান (read-only)। |
| S9 | **Migration সমস্যা:** পুরোনো phase পুনরায় paste করলে patched function ফিরে যায় (HANDOVER_5 hazard)। | `[owner note]` | Paste order সবসময় লিখে রাখুন; পরের patch সর্বদা শেষে। |

### ৩.২ Owner সিদ্ধান্ত (খোলা)

1. কোড `IMG-3`, `CF`, `SF`, `GD` — কোন জায়গা? (এখনো নিশ্চিত নয়)
2. Hub = `main` (live `hub_functions = true`) — আলাদা hub place দরকার কি?
3. `mishti_factory` (SF) কবে চালু হবে?
4. Stock opening কে দেবে — owner, না storekeeper (G1)?
5. Count adjust কে করবে — management, না storekeeper/purchasing (G2)?
6. Owner self-approve ON রাখবেন? (সব role-এ নাকি শুধু owner?)
7. Witness: `pin_signature_on` চালু হবে কখন?
8. Period lock-এর কতদিন পরে বন্ধ?
9. VAT rate ও Mushak 6.3 কখন?
10. 18-1 marketing limit: মাসিক না প্রতি খরচ? (ROADMAP open)
11. Leave-এ paid leave অন্তর্ভুক্ত কি না (ROADMAP open)।
12. `hook_password_verification_attempt` চালু করবেন কি না।
13. Demo-র সংখ্যা (price ৳800/kg সুইট A, ৳300/kg কেক B) — demo মাত্র, আসল price `items` টেবিল থেকে।

### ৩.৩ তথ্য-অসংগতি (সংশোধন দরকার)
- Supabase region: `DECISIONS.md` বলছে Singapore; read-only audit বলছে `ap-southeast-2` (Sydney)। **কোনটি সঠিক owner-কে জিজ্ঞেস করুন।** (Dashboard থেকে নিশ্চিত করা যায়।)
- `REMAINING.md` ও `TODO.md` পরস্পরবিরোধী (উদাহরণ: TODO-তে D1/B2 tick, REMAINING-এ খোলা)। TODO-কে সর্বশেষ ধরুন, তবে প্রতিটি code দিয়ে যাচাই করুন।
- `HANDOVER_5.md`-এর branch `ccr-9ef9353a-q2wsec` এবং `ROADMAP.md`-র `ccr-78d03e25-k7ksyo` — পুরোনো; বর্তমান branch আলাদা।
- Earlier demo doc (`DEMO_FULL_WORKFLOW_AND_LEDGER.md`) ভুল: opening Jamal দেয়, branch2 opening ৫ + transfer ৫ double count, transit 1 kg ভুল (C1–C6 দেখুন `DEMO_DAY_SCREENS_STORIES_LEDGER_EN.md` §১)।

---

## ৪. Repo, branch, Supabase ও URL

| বিষয় | মান | উৎস |
|---|---|---|
| Private repo | `https://github.com/mistybari99/My-tools` | `git remote -v` `[code]` |
| Public repo (শুধু `web/`) | `islamia-bos-app` (GitHub Pages, main) — সর্বশেষ সিঙ্ক অজানা `[unverified]` | `ROADMAP.md`, `DECISIONS.md` |
| বর্তমান branch | `claude/supabase-readonly-audit-xo3qkp` | `git status` `[code]` |
| সর্বশেষ commit | `87f7895` (merge, origin-এর সাথে এক) | `git log` `[code]` |
| Draft PR | #5 (এই branch) | আগের সেশন |
| পুরোনো branch | `ccr-9ef9353a-q2wsec` (PR #2), `ccr-78d03e25-k7ksyo` (ROADMAP) | docs |
| Supabase project ID | `rpqrcmesbhwtyrikabhy` | `[live]` audit |
| Supabase API URL | `https://rpqrcmesbhwtyrikabhy.supabase.co` | `web/config.js` `[code]`; MCP `get_project_url` permission denied, তাই live যাচাই হয়নি |
| Postgres | 17.11 | `[live]` audit |
| Region | `[সংশোধন দরকার]` — §৩.৩ | |
| Plan | Free | `DECISIONS.md` |
| Public key | `web/config.js`-এ (publishable, secret নয়) — এখানে লেখা হয়নি | |
| Secret/service_role | repo-তে নয় — owner-এর কাছে, কখনো commit নয় | `DECISIONS.md` |

**Live DB snapshot (read-only, 2026-10-16):** 265 public table, সব RLS on; `stock_ledger` = 0 row; `purchase_bills` = 0; `production_runs` = 0; sales 10 (test); customers 1; profiles 1 (owner + management একই account); switches: `forms_post_to_ledger` OFF, `blind_count_on` OFF, `owner_self_approve` ON, `period_closed_until` blank, `stock_negative_mode` warn, `em_enabled` ON, `tools_stock_on` OFF।

**কাজের নিয়ম (owner):**
- Owner ফোনে কাজ করেন; বাংলা/বাংলিশ; ছোট সৎ উত্তর; এক প্রশ্ন একবারে। `[owner]`
- Owner SQL paste করেন; agent push করে। agent live DB-তে write করে না। `[owner]`
- প্রতি phase: build → local test → audit → owner OK → push। `[owner]`
- Public repo-তে শুধু `web/`; cost/price private repo-তে। `[owner]`

**কমান্ড (local test):** `docs/HANDOVER_5.md`-এ local Postgres 16 নির্দেশ আছে (initdb, role anon/authenticated/service_role)। Web test: `tests/web/*.js` (headless Chromium, `/opt/pw-browsers`)।

---

## ৫. পরবর্তী সেশনের প্রথম ধাপ (সুপারিশ)

1. `git status` ও `git log -5` যাচাই; এই branch-এ কাজ করুন।
2. Owner-কে জিজ্ঞেস করুন: live Supabase-এ কোন phase কোন অবস্থায় চালানো হয়েছে; region কোনটি।
3. Read-only SELECT দিয়ে `list_migrations`/স্কিমা snapshot নিয়ে repo-র সাথে মেলান (S8)।
4. §৩.২-এর owner সিদ্ধান্ত একসাথে নিন (একবারে এক প্রশ্ন)।
5. S1–S6 code fix ও regression test — owner অনুমোদন পেলে।
6. Security advisor (S7) — owner-এর অনুমোদিত তালিকা অনুযায়ী।
7. ফোনে checklist (`DEVICE_CHECKLIST.md`) চালান।

---

## ৬. যা এই handover-এ নিশ্চিত নয়

- phase 63–69 repo-তে নেই; এদের কাজ `BUILD-LOG`-এ আছে কি না যাচাই হয়নি।
- Live Supabase-এ কোন phase চলেছে তা জানা নেই (শুধু phase3+4 owner-এর "Success")।
- কোনো web page আসল ফোনে পরীক্ষা হয়নি।
- Supabase `get_project_url` MCP call permission denied; URL `web/config.js` থেকে নেওয়া।
- Demo সংখ্যা ও ledger কোড থেকে নয়, হাতে বানানো demo।
