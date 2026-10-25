# Step Vis REPORT - কে কী দেখবে: Show / Hide / Locked + অনুমতির পরামর্শ (phase91, branch fix/phase-Vis, from integration/p72-p79)
Files: supabase/phase91.sql, supabase/phase91_test.sql, web/optviews.js, tests/web/optviews_test.js, tests/web/optviews_ui_test.js, এই রিপোর্ট। ছোট বদল: web/ia.js (এক rec লাইন + `visible()`-এ guarded Hide শর্ত), web/nav.js (দুটি guarded লাইন), web/index.html (script tag শেষে যোগ)।
Run order: ... phase86 phase91 (guard: আগের phase না থাকলে পরিষ্কার error)। paste-twice নিরাপদ। কোনো পুরোনো phase ফাইল বদলানো হয়নি।

## আগে যা ছিল (তদন্ত)
- nav.js-এ `npMode()` (rule `ui_noperm_mode` = lock|hide): অনুমতি না থাকলে lock-সারাংশ বা লুকানো; Home-এ lockcard (pos/dues/biz/items)। `entries()` সবকিছুর একমাত্র উৎস (drawer, Home, search, group page) - hook এখানেই। ia.js `visible(r, c)` search/bottom bar/topUp-এ ব্যবহার হয়।
- অনুমতি: `user_grants` + `rule_grants` (`has_grant`/`can_grant`), ফর্মের `role_form_perms` (`can_do`, `my_context().perms`)। UI ক্লায়েন্টের ctx এই দিয়েই `ok()` চালায়।
- option key: nav.js ইতিমধ্যে `r:<route>` / `f:<form code>` ব্যবহার করে (favourites) - একই key রাখা হয়েছে।

## যা বানানো হয়েছে
- Tables: `user_option_view(user_id, option_key, mode show|hide|locked, set_by, set_at)`, `role_option_view` (ভূমিকার ডিফল্ট; user সারি জেতে; একাধিক ভূমিকায় কম-নিষেধ জেতে: show > locked > hide), `option_view_ops` (client_id)। RLS: নিজেরটা পড়া/মালিক সব; লেখা শুধু RPC।
- RPC: `set_option_view`, `set_option_view_bulk` (সব-অথবা-কিছুই-না, ≤500), `set_role_option_view(_bulk)` (মালিক ছাড়া refused), `my_option_views()` (নিজেরটা, কার্যকর), `option_views_for_user(user)` (মালিক বা নিজে; সাথে ভূমিকা/অনুমতি/grants - "granted / not granted" দেখাতে), `role_option_views`। mode `default` = পছন্দ মুছে ডিফল্টে। `r:home` ও `r:optviews` hide/locked করা যায় না (মালিক নিজেকে বন্ধ করতে পারবে না)। প্রতিটি আসল বদল audit_log-এ (old -> new, কে)। একই client_id আবার = কিছু হয় না (dup), অন্যের/অন্য ধরনের id = client_id_taken।
- ডিফল্ট = আজকের আচরণ: কোনো সারি না থাকলে কারও view বদলায় না।
- **সুরক্ষা:** এগুলো শুধু UI গোছানো। has_grant/can_do/RLS এই টেবিল পড়ে না; hide/locked কোনো অনুমতি দেয় না বা কাড়ে না (টেস্টে grant/permission টেবিলের hash আগে-পরে এক)। অনুমতি থাকলে hidden পাতা সরাসরি লিংকে এখনও খোলে (নথিভুক্ত সিদ্ধান্ত); অনুমতি না থাকলে locked পাতাও সার্ভার refuse করে।
- Recommendations (মালিকের সংযোজন, শুধু পরামর্শ, কিছু আটকায় না): `perm_reco_role` (ভূমিকা -> সাধারণত দরকারি grant + bn/mix/en কারণ; আজকের `rule_grants` থেকে seed + cash_controller/party_coordinator-এর কয়েকটি সাধারণ যোগ), `perm_conflict` (একসাথে না থাকাই ভালো জোড়া, ১৫টি seed: ক্রয় লেখা+সরবরাহকারী payment/void, রেসিপি বদল+অনুমোদন, wastage লেখা+অনুমোদন, বিক্রি void/stock-ছাড়া-বিক্রি+গণনা সমন্বয়, cash move/supplier pay/closed-period + খাতা বদল, cost দেখা+price/discount, item bulk+change approve, payroll+salary structure, intake_bot + যেকোনো POS অধিকার), `perm_reco_ignore`। সব `ON CONFLICT DO NOTHING` - মালিকের বদল দ্বিতীয়বার চালালেও থাকে। কোনো সংখ্যা বানানো হয়নি।
  `permission_recommendations(user)` -> `recommended_missing`, `not_recommended_combo` (দুই grant + কারণ), `unused` (অনুমতিহীন ফর্ম -> Hide প্রস্তাব), `ignored`। `reco_ignore_set`, `reco_apply` (এক ট্যাপ, মালিক-only, audited, client_id: miss = ব্যক্তিগত grant দেওয়া, unused = Hide, combo = ব্যক্তিগত grant ফেরত নেওয়া - ভূমিকা থেকে এলে `not_personal_grant`), `reco_role_set`, `reco_conflict_set` (মালিক তালিকা বদলায়)।
- Web (web/optviews.js, `#/optviews`, মালিক-only, ফোন-প্রস্থ): ব্যক্তি বা ভূমিকা বাছুন; ia.js-এর মতো গ্রুপ করা সব অপশন (+ফর্ম); প্রতিটির পাশে Granted/Not granted (বাছা ব্যক্তির ctx দিয়ে ia `ok()` চালিয়ে) ও Show/Hide/Locked চিপ; বাল্ক: "Hide all not granted", "Show all", "Locked for not granted", "Reset all to default"; সারির পাশে পরামর্শ-ইঙ্গিত + এক-ট্যাপ Apply, নিচে পরামর্শ প্যানেল (Apply / Ignore / Undo)। ভাষা: English মোডে পুরোটা English; Bangla মোডে সাধারণ শব্দ English; mix। নতুন data-act সব `ov_*` (৫টি, অন্য ফাইলে নেই)।
- Nav hook (সংক্ষিপ্ত, guarded): `B.optviews.load()` একবার `my_option_views` পড়ে cache (২ সেকেন্ড সীমা), `entries()`-এ `apply()` (Hide = বাদ; Locked = থাকে, " · locked" চিহ্ন, ট্যাপ ধরে "ask the owner" sheet খোলে, পাতা নয়), `ia.visible()` Hide মানে (search/bottom bar)। ডেটা না এলে/ফাংশন না থাকলে/নেটওয়ার্ক ত্রুটিতে আগের মতোই।

## যাচাই হয়েছে (চালিয়ে দেখা)
- supabase/phase91_test.sql ফ্রেশ DB (phase8..86+91): **97 pass / 0 fail**। বিষয়: ডিফল্ট কিছু বদলায় না; মালিক set/bulk/role; সাধারণ ব্যবহারকারী/অন্য ব্যবহারকারী refused; protected key; খারাপ mode/key; all-or-nothing bulk; ৫০১ আইটেম refused; RLS (নিজেরটা, মালিক সব, ব্রাউজারে সরাসরি লেখা বন্ধ); client_id dup/taken; audit লাইন (বদল হলেই); role default + user override + দুই ভূমিকা; hide/locked-এ grant/permission টেবিল hash অপরিবর্তিত ও can_do/has_grant এক; recommendations (missing, combo, intake_bot+POS, unused, ignore, apply তিন ধরন, নন-ওনার refused, মালিকের বদল, ৩ ভাষার কারণ, English-এ বাংলা অক্ষর নেই); phase91.sql দ্বিতীয়বার (টেস্টের ভেতরে `\i`): ডুপ্লিকেট নেই, মালিকের বদল থাকে।
- phase91.sql ফ্রেশ ও ব্যবহৃত DB-তে দুইবার error ছাড়া।
- রিগ্রেশন (phase8..86 DB বনাম +phase91 DB, প্রতিটি ফ্রেশ কপিতে): phase8, 10, 15, 19, 21, 22, 23, 47, 72, 76, 84, 86 - FAIL/RESULT লাইনের হুবহু একই ফল (জানা বেসলাইন ফেলগুলো একই: phase8 T1, phase10 T12, phase15 T0, phase19/23 T0, phase21/22 (phase84 fixtures), phase47 T1x2, phase72 T0)।
- Node: tests/web/optviews_test.js **58 pass / 0 fail**; tests/web/optviews_ui_test.js (আসল nav.js+ia.js+optviews.js ব্রাউজারে) সব assert পাস, console error নেই; lang_en_test 79 স্ট্রিং, বাংলা 0।
- বিদ্যমান: nav, nav2, ia, control, favsync, settings2 - বদলের আগের (HEAD) কপির সাথে হুবহু একই আউটপুট (সবগুলো assert failures 0 / errors none)।

## পড়ে বোঝা (চালানো হয়নি)
- Locked সারির ট্যাপ ধরা কেবল `data-act="nav_go"` ও `"go"` বাটনে (drawer/Home tile/search)। অন্য কোনো লিংক/বাটন থেকে সরাসরি hash বদলালে locked পাতা খুলতে পারে (অনুমতি থাকলে) - নথিভুক্ত।
- Home-এর বড় কার্ড/অন্য ফাইলের নিজস্ব `location.hash=` বোতাম (যেমন কিছু রিপোর্ট লিংক) `entries()` ব্যবহার না করলে Hide/Locked দেখায় না।
- ভূমিকার seed "সাধারণত দরকার" কারণ আজকের default থেকে নেওয়া সাধারণ বাক্য; প্রতিটি grant-এর আলাদা ব্যবসায়িক কারণ মালিক চাইলে `reco_role_set` দিয়ে লিখবেন।

## যাচাই হয়নি / নেই
- আসল ফোনে/আসল DB-তে চালানো হয়নি (live DB ছোঁয়া হয়নি)। ব্রাউজার টেস্ট stub backend-এ।
- `unused` পরামর্শ সার্ভারে শুধু ফর্ম (`f:`) জন্য; পাতা (`r:`) "অনুমতি নেই" চিহ্ন ক্লায়েন্ট দেখায় ও "Hide all not granted" বাল্ক দেয়, কিন্তু "কখনও ব্যবহার করেনি" ব্যবহার-গণনা থেকে নয় (সিদ্ধান্ত: ব্যবহার-ইতিহাস থেকে অনুমান বানানো হয়নি)।
- অ-মালিকের জন্য আলাদা "নিজের view পড়ো" স্ক্রিন নেই (`option_views_for_user(নিজে)` প্রস্তুত, UI ছাড়া)।
- Locked + অনুমতি আছে এমন পাতার জন্য সার্ভার-পক্ষে কিছু আটকানো হয়নি (ইচ্ছাকৃত: এটা UI-only)।
