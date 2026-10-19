# NUMBERING: phase ও form নম্বরের নিয়ম

এই ফাইল বলে দেয় phase নম্বর (`supabase/phaseNNN.sql`) এবং printed form কোড কীভাবে এক সারিতে রাখতে হবে, নতুন phase কীভাবে যোগ করতে হবে, এবং একটি পুনঃনম্বর (renumber) কীভাবে নিরাপদে করতে হবে। যন্ত্র: `tools/numbering_map.json`, `tools/renumber.py`, `tools/check_numbering.py`।

## 1. কেন এটা দরকার

phase 479 থেকে 498 পর্যন্ত ফাইলগুলো আগে 480 থেকে 554 নম্বরে ছিল। প্যারালেল বিল্ডাররা আলাদা আলাদা সংখ্যা নিয়েছিল, তাই ক্রম ছিল এলোমেলো। commit `6a01cf8` তাদের পেস্ট-ক্রম অনুযায়ী 479 থেকে 498 করেছে। লক্ষ্য হলো: নম্বর সব সময় ধারাবাহিক থাকবে, প্যাকেজ অনুযায়ী সাজানো থাকবে, আর কোনো রেফারেন্স পুরনো নম্বরে পড়ে থাকলে গার্ড ধরে ফেলবে।

printed form কোড এখনো ছাপা হয়নি, তাই সেগুলোর কোড বদলানো যায়। তবে তা শুধু মালিক map অনুমোদন করার পরে।

## 2. নিয়ম

1. **phase নম্বর ধারাবাহিক ও প্যাকেজ অনুযায়ী।** প্যাকেজের ভেতরে ছোট নম্বর আগে বসে। নতুন নম্বর `numbering_map.json`-এর `new` ঘরে থাকে।
2. **phase 8 থেকে 478 কখনো বদলানো হবে না।** যন্ত্র 479-এর নিচের কোনো নম্বর ছুঁতে পারে না। এটা কোডেও আটকানো আছে।
3. **SQL statement ও function-এর নাম কখনো বদলায় না।** বদলায় শুধু: কমেন্ট লাইন, ফাইলের নাম, এবং লেখায় (টেক্সট ফাইলে) রেফারেন্স।
4. **`supabase/*.sql`-এ কোনো SQL কমেন্ট না-হওয়া লাইন বদলানো যাবে না।** যেমন `raise exception 'phaseNNN ...'`, `\i supabase/phaseNNN.sql`, `select 'x6 phaseNNN: ...'`, বা ডেটার ভেতরের লেখা। এ রকম লাইনকে যন্ত্র BLOCKED বলে দেখায় এবং `--apply` রিফিউজ করে। এসব লাইন মালিক নিজে ঠিক করবেন।
5. **printed form কোড বদলানো যাবে শুধু মালিকের অনুমোদনের পরে।** `tools/numbering_map.json`-এ `form_groups_approved` `true` না হওয়া পর্যন্ত form কোড বদলানো রিফিউজ হয়। অনুমোদনের আগে `form_groups` ঘরের নতুন কোড প্রস্তাব মাত্র। কোনো form কোড নতুন করে বানানো বা পুনঃব্যবহার করা যাবে না (BUILD-RULES নিয়ম ২)।
6. **প্রতিটি phase ও form-এর একটি ছোট নাম থাকে।** phase-এর নাম `file_stem`-এ (উদাহরণ: `x1_foundation_part1`)। form-এর নাম "form kit" থেকে নিন। নাম বানাবেন না, ব্যবসার তথ্য বানাবেন না।
7. **`_test` জোড়া।** প্রতিটি `supabase/phaseNNN.sql`-এর সঙ্গে `supabase/phaseNNN_test.sql` থাকবে। না থাকলে কেন নেই, সেটা কোনো ডকুমেন্টে লেখা থাকতে হবে ("no test for NNN")।
8. **একই সংখ্যা দুই অর্থে থাকলে অস্পষ্টতা হয়।** বর্তমানে 480, 481, 490, 491 নম্বর পুরনোও ছিল, নতুনও। তাই এগুলো শুধু অংশে অংশে আলাদা করা যায় না। যন্ত্র এদের গোনে ও দেখায়, কিন্তু বদলায় না। হাতে যাচাই করতে হবে।
9. **এক পাসে বদল।** যন্ত্র সব নম্বর একবারে বদলায়, ধাপে ধাপে নয়। তাই 481 -> 480 এবং 480 -> 479 একসাথে ভুল চেইন তৈরি করে না।

## 3. ধাপগুলো (পুনঃনম্বর)

এই ধাপগুলো এই ক্রমে করুন। কোনো ধাপ ফেল করলে থামুন, পরের ধাপে যাবেন না।

1. **কাজের গাছ পরিষ্কার করুন।** `git status` খালি থাকতে হবে (scope: `supabase`, `tests/sql`, `docs/PASTE_ORDER.md`, `docs/integration`, `tools`, `web/data/info.json`)।
2. **ব্যাকআপ ট্যাগ।** `git tag backup/numbering-YYYYMMDD` (HEAD-এ)। `--apply` এই ট্যাগ ছাড়া চলবে না।
3. **ড্রাই রান।** `python3 tools/renumber.py`। এটা কিছু লেখে না। প্রতিটি ফাইল ও লাইন দেখায়, সংখ্যা গোনে, আর BLOCKERS তালিকা দেয়। প্রথমে দেখুন:
   - "Pending phase renames" সংখ্যা;
   - BLOCKED লাইনের তালিকা (মালিক হাতে ঠিক করবেন);
   - form-কোড লাইনের সংখ্যা (অনুমোদন ছাড়া এগুলো বদলাবে না)।
4. **অনুমোদন।** form কোড বদলাতে হলে মালিকের লিখিত হ্যাঁ নিয়ে `form_groups_approved` `true` করুন। অন্যথায় form কোড বাদ দিন।
5. **প্রয়োগ।** `python3 tools/renumber.py --apply`। যন্ত্র আগে সব গার্ড যাচাই করে; একটিও ব্যর্থ হলে কিছু লেখে না, exit code 2।
6. **গার্ড যাচাই।** যন্ত্রের গার্ড:
   - গাছ পরিষ্কার নয় -> রিফিউজ;
   - ব্যাকআপ ট্যাগ নেই -> রিফিউজ;
   - লক্ষ্য ফাইল আগে থেকে আছে -> রিফিউজ (এটা "collision" হিসেবে দেখায়);
   - BLOCKED SQL লাইন -> রিফিউজ;
   - form অনুমোদন নেই কিন্তু form লাইন বদলাবে -> রিফিউজ;
   - নম্বর 479-এর নিচে -> কোডে অসম্ভব।
7. **পরীক্ষা।** `python3 tools/check_numbering.py` (PASS হতে হবে), `python3 tools/check_no_demo_leak.py` (`OK` লিখতে হবে), এবং `.github/workflows/integration-checks.yml`-এর অন্য গার্ডগুলো (`tools/check_info_coverage.py`, `tools/test_testonly_files.py`, `tools/build_phase477.py --check`, `tools/build_report_registry.py --check`)।
8. **পূর্ণ ওয়েব স্যুইট।** `python3 tests/web/run_all.py --out <scratch-folder>`। এটি নিজের কপিতে চলে এবং screenshot রিপোজিটরিতে লেখে না। ফলাফল `<out>/summary.txt`-এ।
9. **কমিট।** বার্তা: `Renumber phases <from>-<to>: <একটি লাইন>`। আগে `git add -A` এবং `git status` দিয়ে যাচাই করুন। কমিট বার্তার শেষে প্রচলিত Co-Authored-By ও Claude-Session লাইন থাকবে।

যদি কোনো ধাপের পরে ভুল ধরা পড়ে, ট্যাগে ফিরে যান (`git reset --hard backup/numbering-YYYYMMDD` শুধু মালিকের অনুমতিতে)।

## 4. নতুন phase কীভাবে যোগ করবেন

1. **পরবর্তী খালি নম্বর নিন।** `ls supabase | grep -E '^phase[0-9]+\.sql$'` দিয়ে সবচেয়ে বড় নম্বর দেখুন, তারপর +1। বর্তমানে সর্বশেষ 498, তাই পরেরটি 499। নম্বর কখনো পুনঃব্যবহার করবেন না (BUILD-RULES নিয়ম ২ ও ৩)।
2. **ফাইল তৈরি করুন।** `supabase/phaseNNN.sql` এবং `supabase/phaseNNN_test.sql`। ফাইলের প্রথম লাইনে লিখুন `Phase NNN - <নাম>`, আর "Paste AFTER phaseMMM" (আগের phase) ও "Paste-twice safe" লেখা থাকবে। নতুন আচরণ বন্ধ (OFF) অবস্থায় শুরু হবে।
3. **তথ্য এন্ট্রি।** `web/data/info.json`-এ নতুন এন্ট্রির `src` ঘরে `phaseNNN.sql (...)` লিখুন। এই ফাইলটি এই নির্দেশনার বাইরে; মালিক বা নির্ধারিত এজেন্ট এটি সম্পাদনা করবেন।
4. **paste ক্রম।** `docs/PASTE_ORDER.md`-এর টেবিলে প্যাকেজ ও এক লাইনের বর্ণনাসহ একটি সারি যোগ করুন। সাধারণত শেষে যোগ করুন, কারণ মাঝখানে বসালে পরের সব Pos. সংখ্যা বদলাতে হয়। `tests/sql/ORDER.txt`-এও ফাইলের নাম একবার যোগ করুন।
5. **Map-এ যোগ করবেন না।** `numbering_map.json` শুধু পুনঃনম্বরের জন্য। নতুন phase সেখানে যাবে না।
6. **যাচাই।** `python3 tools/check_numbering.py` চালান। নতুন `phaseNNN.sql`-এর `_test` জোড়া না থাকলে সেটি FAIL দেখাবে।
7. **মালিক পেস্ট করবেন।** এজেন্ট live Supabase-এ কিছু চালাবে না (CLAUDE.md, Database safety)। মালিক SQL নিজে পেস্ট করবেন।

## 5. একটি ফাইল কোন paste position-এ

- **টেবিল:** `docs/PASTE_ORDER.md`-এর "Pos." কলামে ফাইলের নাম (`phaseNNN.sql`) খুঁজুন। ওই সারির Pos. সংখ্যাই paste ক্রম।
- **ক্রম-তালিকা:** `tests/sql/ORDER.txt`-এ ফাইলের নাম যে ক্রমে আছে, সেটিও paste ক্রম (বাম থেকে ডানে)।
- **প্যাকেজ ও নাম:** `tools/numbering_map.json`-এর `package` ও `file_stem`।
- **নির্ভরতা:** ফাইলের প্রথম কয়েক লাইনে "Run AFTER" বা "Paste AFTER" লেখা থাকে। সেই আগের ফাইলটি আগে পেস্ট করুন, সংখ্যা যতই বড় হোক।
- **নিয়ম:** সংখ্যা মানে "কখন তৈরি হলো" নয়। 479 থেকে 498 পর্যন্ত সংখ্যা শুধু ক্রম দেখায়। নির্ভরতা ফাইলের হেডার থেকে দেখুন।
- **XB ফাইল:** 491 থেকে 493 এখনো `tests/sql/ORDER.txt`-এ নেই। তাই `docs/PASTE_ORDER.md` অনুযায়ী একবার যোগ করতে হবে (check এটি WARN দেখায়)।

## 6. Form কোড

- পুরনো form কোড `form_groups.old`, নতুন প্রস্তাব `form_groups.new`।
- বর্তমান map শুধু প্রস্তাব। `form_groups_approved: false`।
- form-এর নাম "form kit" থেকে নিন। এই ফাইলে বা কোডে নাম বানাবেন না।
- কোনো form কোড মুছবেন না। অবসর নেওয়া form তার কোড রেখে `closed` অবস্থায় থাকবে (BUILD-RULES নিয়ম ২)।

## 7. কী যাচাই করা হয়নি (সীমা)

- `web/` ফাইলের JavaScript কমেন্টে phase নম্বর এই যন্ত্রের scope-এ নেই। পুনঃনম্বরের পরে সেগুলো হাতে দেখুন।
- `docs/` ফাইলের ইতিহাসমূলক লেখা (যেমন BUILD-LOG) বদলানো হয় না, কারণ তা ইতিহাস।
- BLOCKED SQL লাইনগুলো যন্ত্র ঠিক করে না। মালিকের সিদ্ধান্তের পরেই সেগুলো বদলানো যাবে।

## 8. 500 is skipped (sweets fixes, SW)

The sweets fixes after phase 498 are phases 499 and 501 to 505. Number 500 is an old-only number (the pre-renumber series used it for a file that is not in this branch), and `tools/check_numbering.py` lists it as stale. It is skipped on purpose, so no old reference to phase 500 can be read as the new file. Do not create a phase 500.
