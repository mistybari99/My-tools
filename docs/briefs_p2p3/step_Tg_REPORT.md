# Step Tg REPORT - টেলিগ্রাম বিক্রি/বার্তা মাধ্যম (phase86, branch fix/phase-Tg, from integration/p72-p79)
Files: supabase/phase86.sql, supabase/phase86_test.sql, supabase/functions/telegram-webhook/index.ts (source only), web/inbox.js (+tests/web/inbox_test.js), docs/TELEGRAM_SETUP.md, this report.
Run order: ... phase76 phase77 phase78 phase79 phase86. Paste-twice safe (ব্যবহৃত DB-তেও দুইবার চালিয়ে দেখা)। কোনো পুরোনো phase ফাইল বদলানো হয়নি। নতুন ফাংশন ও টেবিলে real নাম নেই, secret নেই, service_role নেই।

## যা বানানো হয়েছে (Step H-এর নকশায়)
- Tg1 `sales_channels.kind`-এ `telegram`: পুরোনো check এক ব্লকে drop করে নতুন নামে (`sales_channels_kind_tg86`) আবার বসানো। `sales_channel_save` নতুন করে (bos86 চিহ্ন): telegram হলে বটের ref বাধ্যতামূলক। অর্ডারের পুরোনো `channel` টেক্সট কলামে telegram = `other`, আসল পরিচয় `channel_id`-তে (phase61 টেবিল ছোঁয়া হয়নি)।
- Tg2 `telegram_message_receive(channel_code, secret_hash, update_id, chat_id, username, name, text, time, attachment)` -> `inbound_messages` (একই টেবিল, একই `inbox_list/inbox_get/inbox_set_status`, একই PII মাস্ক + view audit)। `(channel_id, external_id=update_id)`-এ idempotent। চ্যাট আইডি handle হিসেবে `tg:<chat_id>`। উত্তর/অর্ডার/AI কিছু নেই। সুইচ `telegram_intake_on` (ডিফল্ট OFF, সাথে `inbox_on` লাগে)। ব্যর্থ হলে আগের failed list + `intake_retry_due` (পুরোনো ফাংশন অপরিবর্তিত) দিয়েই retry।
- Tg3 যাচাই: Telegram-এর `X-Telegram-Bot-Api-Secret-Token`-এর SHA-256 Edge-এ হয়; ডাটাবেসে শুধু hash (`telegram_secrets`, বন্ধ টেবিল, audit-এ টোকেন নেই); constant-time তুলনা SQL-এ। ভুল/না-থাকা টোকেন, অজানা/নিষ্ক্রিয় channel, টোকেন-বসানো-নেই -> বার্তা জমে না, failed list-এ `rejected` সারি (body/chat id ছাড়া)। `telegram_secret_set` (শুধু মালিক), `telegram_status` (মালিকের স্বাস্থ্য-দৃশ্য)।
- Tg4 `telegram_chat_link / telegram_chat_unlink / telegram_chat_info`: চ্যাট <-> গ্রাহক ও/বা অর্ডার জোড়া; কারণ ছাড়া unlink হয় না, সারি মোছা হয় না; ফোন/নাম মাস্ক ও audit; অন্য জায়গার লোক পারে না। ইনবক্স থেকে অর্ডার বানালে (`online_order_save2` p_msg_id) চ্যাট নিজে অর্ডারের সাথে জোড়া (trigger `_tg_autolink86`)। `inbox_board` নতুন করে (bos86): চ্যানেল তালিকায় telegram।
- Tg5 intake-bot role সামঞ্জস্য: রিসিভার `intake_bots` ব্যবহারকারী **অথবা** (যদি কখনো তৈরি হয়) role `intake_bot`-ওয়ালা ব্যবহারকারী মানে; রিসিভারে POS অনুমতি লাগে না, তাই "অর্ডার বানাতে পারে, POS-এ ঢুকতে পারে না" role চলে। S1 role এখনো নেই; এর উপর নির্ভরতা নেই (টেস্টে ডামি role দিয়ে দেখা)।
- Web (web/inbox.js, ছোট যোগ): Telegram চ্যানেল-ধরন (বাংলা/English/মিশ্র), টেলিগ্রাম বার্তায় "চ্যাট তথ্য / গ্রাহকের সাথে জোড়া / জোড়া খুলুন", Channels ট্যাবে মালিকের জন্য "+ টেলিগ্রাম মাধ্যম যোগ" ও "গোপন টোকেন বসান" ও টোকেন আছে/নেই চিহ্ন। নতুন data-act সব `ib_tg_*` (৫টি, কোথাও ডুপ্লিকেট নেই)। পুরোনো লেখা বদলানো হয়নি।
- Edge: supabase/functions/telegram-webhook/index.ts (secret রেপোতে নেই; bot login = meta-webhook-এর মতো, service_role নেই; বট টোকেন এই ফাংশন পড়েই না)।
- docs/TELEGRAM_SETUP.md: মালিকের ধাপ (BotFather, secrets, deploy, setWebhook), কোনটা বানানো/কোনটা মালিকের কাজ, যাচাই-হয়নি চিহ্ন।

## যাচাই হয়েছে (চালিয়ে দেখা)
- supabase/phase86_test.sql ফ্রেশ DB (phase8..79+86): **65 pass / 0 fail**। বিষয়: সুইচ ডিফল্ট OFF; হ্যাশ SHA-256 জানা ভেক্টর; ব্রাউজার role টেবিল/ফাংশন বন্ধ; telegram kind + পুরোনো kind চলে, অজানা kind ও raw insert refused; টোকেন বসালে শুধু hash থাকে (টেবিল ও audit-এ আসল টোকেন নেই); একই update_id দুইবার = ১ সারি; ভুল/নেই/বিকৃত টোকেন = কিছু জমে না, rejected সারি, payload `{"kind":"telegram"}`; অন্য channel-এর টোকেন চলে না; টোকেন-বসানো-নেই channel refused; অজানা/নিষ্ক্রিয় channel refused; audit-এ বার্তার লেখা/chat id নেই; failed list -> retry -> একবার জমা; ইনবক্স list/get/status পুরোনো ফাংশনেই; PII guard ON-এ handle/লেখা/গ্রাহকের নাম ঢাকা; লিংক/রিলিংক/আনলিংক (কারণ লাগে, সারি থাকে); অন্য জায়গার লোক refused; অর্ডার বানালে চ্যাট অটো-লিংক; বোর্ডে telegram; মালিকের status; role `intake_bot`-ওয়ালা (POS অনুমতি ছাড়া) রিসিভার চালায় কিন্তু ইনবক্স খুলতে পারে না।
- phase86.sql দ্বিতীয়/তৃতীয়বার (ফ্রেশ ও ব্যবহৃত DB উভয়ে) নির্ভুল।
- রিগ্রেশন (phase79 পর্যন্ত DB বনাম +phase86 DB): phase76 108/0 -> **107/1**; phase77 26/0 -> 26/0; phase78 101/0 -> 101/0; phase79 77/0 -> 77/0।
  একমাত্র ফেল: `phase76_test T1 "bad kind refused"` — ওই টেস্ট 'telegram'-কে অবৈধ kind ধরত; এখন telegram বৈধ হওয়ায় এটাই প্রত্যাশিত পরিবর্তন (পুরোনো টেস্ট ফাইল ইচ্ছে করে বদলানো হয়নি; সমাধান: ওই লাইনে 'telegram'-এর জায়গায় অন্য কিছু, যেমন 'signal')।
- tests/web/inbox_test.js: **47 pass / 0 fail** (আগে 29, নতুন 18: telegram লেবেল তিন মোডে, বোতাম শুধু telegram বার্তায়, escape, মাস্ক, লিংক/আনলিংক কল, মালিক বনাম অন্যজন, টোকেন সেট/ভুল টোকেনের বন্ধুত্বপূর্ণ ত্রুটি, চ্যানেল যোগ, পেজে টোকেন দেখা যায় না)।
- Edge ফাংশনের parse/hash/তুলনা অংশ node দিয়ে আলাদা করে চালানো (৮ চেক পাস: SHA-256 ভেক্টর SQL-এর সাথে মেলে, private/group/bot/edited/photo/voice)।

## পড়ে বোঝা (চালানো হয়নি)
- Telegram Update-এর ফিল্ড নাম ও `message.photo[]` গঠন স্মৃতি থেকে লেখা।
- `setWebhook` লিংকের রূপ, `allowed_updates`, header-এর নাম বানান।
- Supabase Edge-এ `--no-verify-jwt` ও `npm:@supabase/supabase-js@2` import meta-webhook-এর মতোই ধরা।

## যাচাই হয়নি / নেই
- **আসল Telegram কল একবারও হয়নি।** Edge ফাংশন deploy/চালানো হয়নি; Deno টাইপ-চেক হয়নি।
- বট টোকেন ও secret_token মালিকের কাজ (BotFather, `supabase secrets set`, `setWebhook`); deploy-এর জন্য কম্পিউটার লাগে।
- ছবি/ডকুমেন্ট ডাউনলোড নেই (শুধু `photo:<file_id>` চিহ্ন), গ্রুপ/চ্যানেল ইগনোর, কোনো স্বয়ংক্রিয় উত্তর নেই, retry worker (cron) লেখা নেই (Meta-র মতোই)।
- ভুল-টোকেনের অনুরোধে প্রতিবার একটি `rejected` সারি লেখা হয়, rate limit নেই (বন্যা হলে চ্যানেল বন্ধ/কোড বদল) - পরের ধাপের কাজ।
- ফোন নম্বর Telegram দেয় না; গ্রাহকের সাথে জোড়া মানুষ করে (মোবাইল নম্বর লিখে)।
- ia.js/নেভিগেশন বদল লাগেনি (পুরোনো `inbox` পেজেই যোগ)।
