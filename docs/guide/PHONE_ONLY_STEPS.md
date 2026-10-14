# ফোনে মালিকের নিজের করণীয় - ধাপে ধাপে

ফোনের ব্রাউজারে Supabase ও অ্যাপ খুলে যা যা হয়, আর যা ফোনে হয় না।
এই ফাইলের কোনো ধাপ লাইভ প্রজেক্টে বা আসল ফোনে চালিয়ে দেখা হয়নি। চিহ্ন `[যাচাই হয়নি]` সেখানে দেওয়া আছে।

## ০. আগে জানুন

- `docs/PASTE_ORDER.md` ফাইলটি **এই branch-এ নেই**। তাই নিচের ক্রম নেওয়া হয়েছে: **72 থেকে 79, তারপর 80 থেকে 88, তারপর 90 থেকে 93**।
- **phase 89 নামে কোনো ফাইল repo-তে নেই।** "89 সবার শেষে" নির্দেশ পালনের মতো কিছু নেই। কোনো phase 89 এলে সবার শেষে বসাবেন।
- **phase 92 আছে** (বিক্রির পর ইনভয়েস), তাই 92-ও তালিকায়।
- প্রতিটি phase-এর শুরুতে নিজের guard আছে। আগের phase না থাকলে সে নিজেই থামে আর স্পষ্ট error লেখে। কিছু ভাঙে না।
- সব ফাইল **দুবার paste করলেও ক্ষতি নেই** (paste-twice safe)।
- `*_test.sql` ফাইল paste করবেন না। ওগুলো পরীক্ষার জন্য।
- লাইভ ডাটাবেসে আজ কোন কোন phase আগে paste হয়েছে তা এই গাইড লেখার সময় জানা ছিল না। আগে নিচের "০.১" দিয়ে দেখে নিন।

### ০.১ আগে ডাটাবেসের অবস্থা দেখুন

1. অ্যাপে `#/setupadvisor` খুলুন।
2. যে সারি `not_installed` দেখায়, সেই phase এখনো paste হয়নি।
3. কিছু না খুললে বা error এলে ধরে নিন phase 72 এর আগের অবস্থা। [যাচাই হয়নি: এই পদ্ধতি লাইভে চালানো হয়নি]

## ১. SQL paste - ফোনে সম্ভব (আকার বড়, ধীরে করুন)

প্রতিবার: Supabase প্রজেক্ট খুলুন, **SQL Editor**, New query, ফাইলের পুরো লেখা কপি করে paste, **Run**, "Success" দেখুন।

`[যাচাই হয়নি]` ফোনের clipboard ও ব্রাউজারে 50 থেকে 90 KB paste ঠিকঠাক হবে কিনা, আর "Desktop site" লাগবে কিনা। না হলে কম্পিউটারওয়ালা কারও সাহায্য নিন।

| ক্রম | ফাইল | আকার (KB, প্রায়) | কী করে (এক লাইন) | কী লাগে (guard) |
|---|---|---|---|---|
| 1 | `supabase/phase72.sql` | 77 | rounding, এক cost source, অজানা cost, `acct_status` | phase 8..71 |
| 2 | `supabase/phase73.sql` | 51 | recipe, artisan, approval | 8..71 |
| 3 | `supabase/phase74.sql` | 75 | costing ও overhead | 73 |
| 4 | `supabase/phase75.sql` | 54 | cost source ও ভাগ | 74 |
| 5 | `supabase/phase76.sql` | 66 | channel, inbox, web order | 8..71 |
| 6 | `supabase/phase77.sql` | 20 | অনলাইন অর্ডারের ফাঁক | 76 |
| 7 | `supabase/phase78.sql` | 36 | খরচ কোন শাখার | 75 |
| 8 | `supabase/phase79.sql` | 45 | **জোড়া ফাইল: 72 থেকে 78 এর ফাংশন একসঙ্গে মেলায়।** শুরুতে guard আছে | 72..78 সবগুলো |
| 9 | `supabase/phase80.sql` | 91 | free-cost চিহ্ন, partner base, packaging ফেরত, intake bot | 72..79 |
| 10 | `supabase/phase81.sql` | 64 | setup advisor | 72..79 (80 লাগে না) |
| 11 | `supabase/phase82.sql` | 48 | GRN, void, unit, মাইনাস guard | কোড পড়ে বোঝা: 78 পর্যন্ত |
| 12 | `supabase/phase83.sql` | 66 | form বনাম screen, transit, offline POS | 8..71 |
| 13 | `supabase/phase84.sql` | 11 | audit trail | 78 পর্যন্ত |
| 14 | `supabase/phase85.sql` | 82 | খাতায় stock move, card, scheduler | 72..79, phase 79 এর ফাংশন |
| 15 | `supabase/phase86.sql` | 23 | Telegram | 76 |
| 16 | `supabase/phase87.sql` | 55 | QA ঠিকঠাক: মালিক approve, expiry guard ইত্যাদি | 72..79, 82, 84 |
| 17 | `supabase/phase88.sql` | 21 | এক report cost source | 72..79, 82, 83, 84 |
| 18 | `supabase/phase90.sql` | 52 | ছবি থেকে Scan | 8..84 |
| 19 | `supabase/phase91.sql` | 42 | Show/Hide/Locked, permission পরামর্শ | 8..86 |
| 20 | `supabase/phase92.sql` | 12 | বিক্রির পর ইনভয়েস | 72..88 |
| 21 | `supabase/phase93.sql` | 5 | Template পছন্দ | 72..79, 88 |
| - | phase 89 | - | **ফাইল নেই** | - |

**নিয়ম:**
- ক্রম ভাঙবেন না। বিশেষ করে 79 সবসময় 72 থেকে 78 এর পরে।
- phase 81 এর ফাইল নিজে বলে "phase 80 লাগে না", তবু উপরের ক্রমে 80 আগে রাখাই নিরাপদ।
- **phase 85 এর পরে** পুরনো `phase40.sql` বা `ALL_NEW10.sql` **আবার paste করবেন না।** `acct_journal_post` এর দুই রূপ থেকে ambiguity হয়।
- প্রতিটি paste-এর পর `#/setupadvisor` খুলে দেখুন কোন সারি `not_installed` থেকে সরেছে।

## ২. ফোনে সম্ভব - অ্যাপের ভেতরের কাজ

| কাজ | কোথায় |
|---|---|
| সুইচ চালু/বন্ধ | `#/switchboard` |
| প্রস্তাবিত মান apply | `#/setupadvisor`, `#/guards` |
| ব্যক্তি/ভূমিকা অনুযায়ী Show/Hide/Locked | `#/optviews` |
| অধিকার (grant) দেওয়া। Approver role | `#/delegation` |
| Recipe, কারিগর, রূপান্তর rate, pool | `#/recipebook`, `#/costing` |
| Cost source, নিয়ম, বিল | `#/costsources` |
| খরচ কোন শাখার | `#/costattrib` |
| Sales channel যোগ | `#/saleschannels` |
| Telegram channel যোগ, secret token বসানো | `#/inbox` > Channels |
| Free-cost চিহ্ন, intake bot বানানো | `#/s1setup` |
| Template পছন্দ | `#/templates` |
| Scan চালু, grant (`scan_upload`, `scan_confirm`) | `#/switchboard`, `#/delegation` |
| `pos_show_invoice_after_sale` | `#/switchboard` |

## ৩. কিছু ধাপ ফোনে সম্ভব, কিন্তু বাইরের অ্যাকাউন্টে

| ধাপ | কোথায় | অবস্থা |
|---|---|---|
| Telegram bot বানানো (BotFather) | Telegram অ্যাপ | ফোনে সম্ভব। Bot token একটা password। চ্যাটে, repo-তে, স্ক্রিনশটে দেবেন না। ফাঁস হলে BotFather-এ `/revoke` |
| Telegram secret token ঠিক করা | আপনি নিজে | ১৬ থেকে ২৫৫ অক্ষর, শুধু অক্ষর, সংখ্যা, `_`, `-`। Password manager দিয়ে বানান। অ্যাপে "Set secret token" দিয়ে বসান। সার্ভারে শুধু hash থাকে |
| Telegram `setWebhook` | ব্রাউজারে লিংক খোলা | ফোনে সম্ভব, কিন্তু আগে Edge function deploy হতে হবে (নিচে, কম্পিউটার লাগে)। লিংকে bot token থাকে, ব্রাউজার history মুছে দিন |
| ওয়েব ফর্মের public URL সেটিং বসানো | `#/switchboard` (`web_form_public_url`) | ফোনে সম্ভব, কিন্তু URL আগে লাগে। URL পাওয়া যায় Edge function deploy-এর পর |
| `ai_vision` এর key বসানো | Supabase Dashboard > Edge Functions > Secrets | `[যাচাই হয়নি]` ফোনের ব্রাউজারে হবে কিনা |
| Anthropic অ্যাকাউন্ট ও খরচের সীমা (spending limit) | Anthropic Console | ফোনে সম্ভব। সীমা অবশ্যই বসান |
| Meta Developer অ্যাপ, Business Verification, App Review, Page/Instagram/WhatsApp সংযোগ, webhook URL নিবন্ধন | Meta-র সাইট | **বাইরের অ্যাকাউন্ট ও অনুমোদন।** কী কী লাগে, বাংলাদেশে প্রাপ্যতা ও খরচ: কিছুই যাচাই হয়নি। আগে নিজে দেখে নিন |
| Captcha পরিষেবার অ্যাকাউন্ট (ঐচ্ছিক) | প্রদানকারীর সাইট | বাইরের সেটআপ |

## ৪. ফোনে অসম্ভব (কম্পিউটার বা কম্পিউটারওয়ালা সাহায্যকারী লাগবে)

নিচের প্রতিটা ফোনে হয় না বলে ধরে নিন। কারণ আলাদা করে লেখা আছে।

| # | ধাপ | কেন ফোনে হয় না | কোন ফিচারের জন্য |
|---|---|---|---|
| 1 | **Edge function deploy** (`supabase functions deploy web-order --no-verify-jwt`) | Supabase CLI লাগে। Meta/Telegram/ওয়েব ফর্ম Supabase login token পাঠাতে পারে না, তাই `--no-verify-jwt` লাগে | ওয়েব অর্ডার ফর্ম |
| 2 | **Edge function deploy** (`meta-webhook --no-verify-jwt`) | একই কারণ | Facebook/Instagram/WhatsApp |
| 3 | **Edge function deploy** (`telegram-webhook --no-verify-jwt`) | একই কারণ | Telegram |
| 4 | **Edge function deploy** (`scan-extract`), JWT যাচাই চালু রেখে (`--no-verify-jwt` দেবেন না) | CLI লাগে। Dashboard editor ফোনে হতে পারে (Desktop site) `[যাচাই হয়নি]` | Scan `ai_vision` (ঐচ্ছিক। `manual` ও `browser_ocr`-এ লাগে না) |
| 5 | **Secrets সেট** (নিচে নামের তালিকা) | CLI (`supabase secrets set`) সবচেয়ে নিশ্চিত। Dashboard থেকে ফোনে হয় কিনা `[যাচাই হয়নি]` | সংশ্লিষ্ট Edge function |
| 6 | **Intake bot-এর login ব্যবহারকারী বানানো** (Supabase Auth) | Supabase Auth-এ নতুন ব্যবহারকারী বানাতে dashboard লাগে। ফোনে হতে পারে `[যাচাই হয়নি]`। রিপোর্টে এটাকে "ফোনে সম্ভব নয়" ধরা হয়েছে। এরপর `#/s1setup` (`intake_bot_create`) দিয়ে চিহ্নিত করা ফোনে হয় | ওয়েব ফর্ম, Meta, Telegram |
| 7 | **Scheduler চালু করা** (`acct_scheduler_enable`) | Postgres-এর `pg_cron` extension থাকতে হবে। সেটা সার্ভারের সেটিং। কোড কিছু install করে না। extension না থাকলে কিছু schedule হয় না | নিজে নিজে হিসাব post |
| 8 | **`intake_retry_due` নিয়মিত চালানো** | কেউ cron লেখেনি (GitHub Actions বা Supabase scheduled function)। এই cron-ও বানানো হয়নি | ব্যর্থ intake আবার চেষ্টা |
| 9 | **Meta Developer অ্যাপের webhook-callback নিবন্ধন** | Meta-র ওয়েবসাইট। ফোনে ব্রাউজারে সম্ভব হতে পারে, কিন্তু Edge function আগে deploy না হলে URL নেই | Meta |
| 10 | **ছবির (Scan) পুরনো orphan সাফ করা** | স্ক্রিপ্ট বানানো হয়নি | Scan |
| 11 | **আসল প্রিন্টারে পরীক্ষা** (থার্মাল 58/80 mm, A4/A5, লেবেল রোল) | প্রিন্টার ও ফোন জোড়া লাগাতে হয়। কখনো পরীক্ষা হয়নি | Template, ইনভয়েস |

### Secrets-এর নাম (মান কখনো এখানে বা চ্যাটে লিখবেন না)

| Secret নাম | কোন function-এ |
|---|---|
| `INTAKE_BOT_EMAIL`, `INTAKE_BOT_PASSWORD` | web-order, meta-webhook, telegram-webhook |
| `WEB_FORM_SALT` | web-order |
| `CAPTCHA_SECRET`, `CAPTCHA_VERIFY_URL` | web-order (ঐচ্ছিক) |
| `META_APP_SECRET`, `META_VERIFY_TOKEN` | meta-webhook |
| `TELEGRAM_SECRET_TOKEN` | telegram-webhook (ঐচ্ছিক দ্বিতীয় যাচাই) |
| `ANTHROPIC_API_KEY`, `SCAN_AI_MODEL` | scan-extract |

কোড থেকে নাম মিলিয়ে দেখা: ওপরের নামগুলো `tools/edge/*.ts` ও `supabase/functions/*/index.ts` এ আছে। `ASSISTANT_MODEL` নামে আরও একটা আছে `assistant-proxy.ts`-এ, এই গাইডের বাইরে।
`SUPABASE_URL` ও `SUPABASE_ANON_KEY` Supabase নিজে দেয়।

কখনো যা করবেন না:
- `service_role` key কোথাও বসাবেন না। কোনো ফাংশনের তা লাগে না।
- Secret repo-তে, চ্যাটে, ছবিতে, SQL-এ দেবেন না।
- Telegram `setWebhook` লিংক ব্রাউজারে খোলার পর history মুছুন।

## ৫. প্রতিটি কম্পিউটার-লাগা ধাপে কারও কাছে কী চাইবেন

কম্পিউটারওয়ালা সাহায্যকারীকে বলুন: "ডিরেক্টরি `supabase/functions/` ও `tools/edge/` থেকে উপরের তালিকার function deploy করুন। secret আমি নিজে Supabase dashboard-এ বসাব (অথবা আপনার সামনে বসে বসাব)। আমার কোনো password বা key আপনাকে পাঠাব না।"

## ৬. যা এই গাইডে যাচাই হয়নি

- লাইভ ডাটাবেসে কোন phase আগে paste হয়েছে।
- ফোনে বড় SQL ফাইল paste করা।
- Supabase dashboard ফোনের ব্রাউজারে Edge function / Secrets / Auth user বানানো।
- Meta ও Telegram-এর বর্তমান নিয়ম। রিপোর্টের সব লিংক ও ক্ষেত্রের নাম স্মৃতি থেকে লেখা।
