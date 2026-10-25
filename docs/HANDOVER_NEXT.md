# HANDOVER_NEXT — Islamia BOS (সম্পূর্ণ handover)

নতুন সেশনে প্রথমে এই ফাইল পড়ুন। আরও গভীরে: `docs/HANDOVER_3.md`, `docs/TODO.md`, `docs/BUILD-LOG.md`, `docs/MODULE_MAP.md`, `docs/OPS_SETUP.md`, `docs/ASSISTANT.md`।

---

## ৪) Repo, branch, Supabase, URL (আগে এটা)

| বিষয় | মান |
|---|---|
| PRIVATE repo (সব কোড, SQL, টেস্ট, docs) | `mistybari99/My-tools` |
| Branch | `ccr-2f54f832-rkdi5z` (এখানেই develop + push; PR তৈরি করবেন না যতক্ষণ মালিক না বলেন) |
| PUBLIC repo (শুধু হোস্টিং কপি) | `mistybari99/islamia-bos-app`, branch `main` |
| Live app (GitHub Pages) | https://mistybari99.github.io/islamia-bos-app/ |
| SQL পেস্ট পাতা | https://mistybari99.github.io/islamia-bos-app/setup-sql.html |
| Supabase project ref | `rpqrcmesbhwtyrikabhy` |
| Supabase SQL editor | https://supabase.com/dashboard/project/rpqrcmesbhwtyrikabhy/sql/new |
| Backup branch (শুধু PRIVATE repo) | `backups` (orphan; workflow চালু হলে) |

**Publish নিয়ম:** `python3 tools/build_kb.py` → `web/` এর ফাইল public repo-তে কপি (`setup-sql.html` বাদে; find+cp) → commit → `git push origin main`। SQL-পাতা এডিট আর web কপি আলাদা কমান্ডে। Public clone: `/home/user/islamia-bos-app` (না থাকলে clone)। Session-এ public repo না থাকলে `add_repo`।

**কাঠামো:** `web/` = plain-JS, no-build app। `supabase/` = additive, idempotent phase SQL (`phaseN.sql` + `phaseN_test.sql`)। `tests/sql`, `tests/web` = টেস্ট। `tools/` = Python (KB, backup, notify, fingerprint bridge)। `docs/` = সব নথি।

---

## মালিক ও কাজের নিয়ম

- মালিক শুধু **ফোন** ব্যবহার করেন; বাংলা/Bng-Eng; **ছোট, সৎ বাংলা উত্তর** চান।
- মালিক শুধু **SQL পেস্ট** করেন; push/publish সব আপনি। লিংক শুধু public GitHub Pages-এর।
- "Dry test" ছাড়া আসল ডেটা নয়; real data সফটওয়্যার শেষ হলে।
- Nothing hard-deleted; audit_log; period lock; costs/salary গোপন; RLS + SECURITY DEFINER (`search_path=public`)।
- sandbox থেকে supabase.co পৌঁছানো যায় না — আসল Supabase-এ কিছুই যাচাই হয়নি।

---

## ১) মূল দাবি ও feature তালিকা

**লক্ষ্য:** Islamia ব্যবসার পূর্ণ BOS — দোকান (showroom), কারখানা, গুদাম; কাগজের খাতা থেকে অ্যাপে ধাপে ধাপে যাওয়া (Rollout: Paper → Parallel → App)।

**মূল সিস্টেম (ফেজ ২–৩০):** আইটেম মাস্টার/ইউনিট/বারকোড, ক্রয় (GRN), স্টক ও blind count (সার্ভার-সিল), বিক্রি/POS (kg/pc ইউনিট বাছাই, বড় ফন্ট), বাকি/dues, ফেরত, ক্যাশ-মুভ/ডে-বুক, খরচ, উৎপাদন/রেসিপি (void সহ), supplier payables, PIN signature (দুই-জন ফর্ম), approvals/pending, ৫০+ রিপোর্ট (report engine 3, নেট অফ রিটার্ন), parallel-মোড তুলনা, paper books/print notes, delegation বোর্ড, guided stepper (দোকান খোলা/দিন বন্ধ/মাসশেষ), switchboard (সব ON/OFF এক পাতায়), Control Center, offline outbox + service worker, IA registry `web/ia.js` (skill `bos-organise`), সব স্ক্রিনে back ◀ আর sheet-এ ✕।

**মডিউল ৪০–৪৭ (সর্বশেষ):**
| ফেজ | মডিউল | প্রধান ফাইল |
|---|---|---|
| 40 | হিসাব-বই: ledger, balance sheet (১২ ট্যাব) | `supabase/phase40.sql`, `web/accounts.js` |
| 41 | কর্মী রেজিস্ট্রেশন, ছবি, বেতন, সুবিধা, **deed** (বিশেষ ভূমিকা/নিয়ম) | `phase41.sql`, `employees.js` |
| 42 | হাজিরা, ছুটি, overtime, bonus, paid leave, স্বয়ংক্রিয় বেতন, ফিঙ্গারপ্রিন্ট আমদানি | `phase42.sql`, `attendance.js`, `payroll.js`, `tools/fingerprint_bridge.py`, `docs/FINGERPRINT.md` |
| 43 | কাস্টমার স্তর (walking/Elite/Gold…), discount, gift, loyalty; POS-এ tier চিপ | `phase43.sql`, `customers.js`, `pos.js` |
| 44 | অংশীদারি/বিনিয়োগ/লাভ-ভাগ deed engine (নিজের নিয়মে, version সংরক্ষণ) | `phase44.sql`, `partners.js` |
| 45 | মালিক-মোড বোর্ড (সাজানো যায়), Home পরিষ্কার (Recent/★ বাদ; favourite ⋮ মেনুতে: উপর/নিচ/শীর্ষ/তলা, rename, hide) | `phase45.sql`, `ownerboard.js`, `nav.js` |
| 46 | Auto backup (GitHub `backups` branch, ঐচ্ছিক Google Drive) + নোটিফিকেশন (app ঘণ্টা + Gmail digest) | `phase46.sql`, `notifications.js`, `.github/workflows/{backup,notify}.yml`, `tools/*`, `docs/OPS_SETUP.md` |
| 47 | AI Business Assistant (read-only MVP): বাংলা-ইংরেজি, গাইড + বিশ্লেষণ, লোকাল deterministic router, approved tool registry (কোনো arbitrary SQL নয়) | `phase47.sql`, `assistant.js`, `assistant_tools.js`, `data/kb.json`, `tools/build_kb.py`, `tools/edge/assistant-proxy.ts`, `docs/ASSISTANT*.md` |

---

## ২) কাজের অগ্রগতি

### Done (কোডে + টেস্টে)
- TODO গ্রুপ A, B, C, D (ফেজ ২৩–২৮) ✔; POS ইউনিট + ফন্ট ✔; back/✕ সর্বত্র ✔।
- ফেজ ৪০–৪৭ লেখা, টেস্ট, publish ✔। মালিক SQL **ALL_NEW9 (২৩–২৮)** এবং **৬ পার্টে ৪০–৪৭** Supabase-এ চালিয়েছেন — সব "Success"।
- SQL টেস্ট: p23 92, p24 22, p25 91, p26 117, p27 55, p28 41, p40 119, p41 171, p42 160, p43 144, p44 181, p45 46, p46 117, p47 72/72 — সব পাশ।
- Web: ৫০টা `tests/web/*_test.js` — শেষ রানে কোনো FAIL নেই (theme_test আইকন ফিক্সের পর ০ FAIL; বাকি ৪৯টা ফিক্সের আগের কোডে চলেছিল, পুরো সেট আবার চালানো হয়নি)।
- সর্বশেষ publish: public `main` commit `be20df6`।

### বাকি — কোড/যাচাই
- পুরো web regression আবার একবার চালানো (আইকন ফিক্সের পর)।
- **আসল Supabase/ফোনে smoke test** (sandbox থেকে সম্ভব হয়নি): নতুন মডিউলের RPC, grants, RLS।
- ফিঙ্গারপ্রিন্ট আসল ডিভাইসে পরীক্ষা হয়নি।
- GitHub Actions (backup/notify) আসলে চালিয়ে দেখা হয়নি।
- AI assistant: keyword-ভিত্তিক; LLM proxy লেখা আছে কিন্তু **deploy/চালু নয়**।

### বাকি — মালিকের কাজ (কোড নয়)
1. **Accounting:** শুরুর তারিখ (`accounting_start_date`) + opening balance বসানো; `accounting_on` চালু।
2. **Grants:** `employee_manage, salary_manage, deed_manage, attendance_manage, payroll_manage, accounts_view, accounts_manage, customer_manage, assistant_use` (ম্যানেজার/স্টাফ)।
3. কাস্টমার স্তরের discount মান বসানো + সংশ্লিষ্ট switch চালু।
4. হাজিরা/ছুটি/বেতনের default যাচাই (ছুটির দিন শ্রম আইনের সঙ্গে মিলিয়ে)।
5. Backup + Gmail: ops bot Supabase user, GitHub secrets, Gmail app password, **workflow ফাইল My-tools-এর default branch-এ সরানো** (`docs/OPS_SETUP.md`)। Google Drive ঐচ্ছিক — চাইলে মালিক বলবেন।
6. ফিঙ্গারপ্রিন্ট ডিভাইস রেজিস্টার + bridge চালানো (`docs/FINGERPRINT.md`)।
7. `docs/TODO.md` গ্রুপ E: আইটেমের দাম/ইউনিট/min-stock (`#/bulkitems`), ৫৭ legacy আইটেম (`#/itemmap`), বাংলা ক্যাটাগরি, কাগজ-ফর্ম চেক, auth hook, ফোন checklist (`docs/DEVICE_CHECKLIST.md`), VAT/Mushak বন্ধ থাকবে (উপদেষ্টার রেট না পাওয়া পর্যন্ত)।

---

## ৩) খোলা সমস্যা ও সিদ্ধান্ত

**সিদ্ধান্ত**
- AI সহকারী **ফ্রি লোকাল ইঞ্জিনে** থাকবে; কোনো পেইড সার্ভিস মালিকের স্পষ্ট অনুমোদন ছাড়া চালু নয়। খরচ-আন্দাজ (শুধু অনুমান): Haiku ≈ $0.10–2/মাস, Sonnet ≈ $2–40/মাস।
- Backup শুধু PRIVATE repo-র orphan `backups` branch-এ; public repo-তে কোনো গোপন তথ্য/SQL-এ secret নেই।
- নতুন SQL সবসময় মালিকের বর্তমান অবস্থার (ফেজ ৪৭) ওপর additive ও "দুবার পেস্ট নিরাপদ" হতে হবে। **ফেজ ২১ আর পেস্ট করা যাবে না ফেজ ২৪-এর পর** (report_run2 wrap)।
- হিসাব/বেতনের নিয়ম ডেটা-চালিত (rules টেবিল); ফর্ম ফ্লো: Paper/Parallel/App rollout অক্ষত।

**পরিচিত ঝুঁকি / শিক্ষা**
- **Action নাম ইউনিক হতে হবে** সব `web/*.js` জুড়ে (গ্লোবাল handler map)। আজ দুটো সংঘর্ষ ধরা পড়ে ঠিক হয়েছে (`ob_open` ownerboard↔rollout → `obd_open`; `as_save` attendance↔itemmaster → `shf_save`)। নতুন action-এর আগে grep করুন।
- আইকন key অবশ্যই `web/icons3d.js`-এ থাকতে হবে (`ear` নেই; `info` ব্যবহার হয়েছে)।
- নতুন স্ক্রিন/মেনু = `web/ia.js` (skill `bos-organise`)।
- Heavy Playwright টেস্ট একসাথে চালালে flaky; একটা একটা করে চালান।
- Service worker শুধু https-এ রেজিস্টার (localhost টেস্ট ধীর হত)।
- নতুন পাতা সরাসরি খুললে `if (B.loadStatic) await B.loadStatic();` লাগে।
- `tests/web/s10_common.js`-এ `ROOT` হার্ড-কোডেড `/home/user/My-tools/web` (worktree টেস্টে বদলাতে হয়)।
- মডিউল টেস্ট (accounts/partners/notifications) index.html-এ script না থাকলে তবেই inject করে।

**লোকাল টেস্ট পরিবেশ (এফেমেরাল — প্রতি সেশনে আবার)**
- Postgres 16 socket `/tmp` port 5544: `su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pgtest/data -o '-p 5544 -k /tmp' -l /tmp/pg.log start"` (data dir না থাকলে `initdb` লাগবে)।
- ডিবি বানাতে: `ORDER="phase8 … phase30_controls phase40 … phase47" bash tests/sql/build_fresh_db.sh <db>`; টেস্ট: `psql -h /tmp -p 5544 -U postgres -d <db> -f supabase/phaseN_test.sql` (একবারই; ব্যবহৃত DB-তে পুনরায় চালালে ব্যর্থ হতে পারে — নতুন DB বানান)।
- Web: `node tests/web/<name>_test.js /home/user/My-tools/tests/web`।

**পরের সেশনে সুপারিশকৃত প্রথম ধাপ**
1. মালিককে জিজ্ঞেস নয় — `git log`, এই ফাইল, `docs/TODO.md` দেখে অবস্থা ধরুন।
2. মালিকের নতুন কাজ শুনে ছোট TODO বানান (পুরো অ্যাপ আবার পড়বেন না), একটা একটা করে dry-test সহ।
3. প্রতি গ্রুপ শেষে থামুন ও ছোট বাংলা রিপোর্ট দিন; নতুন SQL লাগলে পার্টে ভাগ করে `setup-sql.html`-এ কার্ড দিন।
