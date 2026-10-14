# Step H REPORT - বাইরের অর্ডার ও বার্তা ইনটেক (phase76, branch fix/phase-H)
Files: supabase/phase76.sql, supabase/phase76_test.sql, web/inbox.js, tests/web/inbox_test.js, tools/edge/web-order.ts, tools/edge/meta-webhook.ts, this report.
Run order: ... phase62 phase70 phase71 phase76. Paste-twice safe (verified). Old phase files untouched. Re-created only: `online_orders_list`, `online_order_get` (latest = phase61, `bos76` marks: phone/address mask + view audit).

## আগে যা ছিল (পরীক্ষা করে, নকল করিনি)
online_orders + online_order_save/status/cancel/deliver/link_sale/list/get (phase61), payment_webhook_log (phase62). কোনো channel/inbox/webhook টেবিল বা বাইরের auto-entry পথ ছিল না। এখন শুধু যা নেই তা বানানো হয়েছে।

## যা বানানো হয়েছে (গ্যাপ অনুযায়ী)
- **H1** `sales_channels` (kind: ওয়েব ফর্ম / ফেসবুক / ইনস্টাগ্রাম / হোয়াটসঅ্যাপ / ফোন / ওয়াক-ইন / ☐ অন্য:লেখা; কোন শাখা + কোন role; account_ref শুধু মালিক দেখে; active; কখনো মোছা যায় না)। `online_orders` এ নতুন কলাম: channel_id, external_ref (channel+ref unique), source, pay_mode (cod/cash/mobile/card/bank/other + pay_mode_other), pay_ref। পুরনো `channel` টেক্সট কলাম ও `online_order_save` অপরিবর্তিত। `online_order_save2` = বিদ্যমান `online_order_save` কে ডেকে নতুন কলাম বসায় (এক ট্রানজ্যাকশন, client_id একই থাকলে একই অর্ডার)।
- **H2** `inbound_messages` (unique channel+external_id; status new/seen/converted/ignored; linked_order_id; text/handle/নাম/attachment ব্রাউজারে সরাসরি পড়া যায় না, শুধু `inbox_get` দিয়ে, প্রতিবার audit) + `inbound_message_events` trail। `inbox_list/get/set_status/board`। বোর্ডে "নতুন বার্তা X", "শেষ বার্তা এসেছে কখন", দীর্ঘ নীরবতার সতর্কতা (সীমা = সেটিং `inbox_silence_hours`)। "অর্ডার বানাও" = web/inbox.js এ ফর্ম খোলে (নাম/মাধ্যম আগে থেকে ভরা, পণ্য-পরিমাণ-ঠিকানা স্টাফ লেখে) → `online_order_save2` → বার্তা converted + linked।
- **H3** `web_order_submit` + `web_form_catalog` + `web_form_embed` + edge সোর্স `tools/edge/web-order.ts`। সংরক্ষণ বিদ্যমান online_order_save দিয়ে (সরাসরি টেবিল লেখা নেই); client_id = জমার id; ক্লায়েন্টের দাম বাদ, সার্ভার দাম/মোট; শুধু active+sellable+hidden-নয়+দামওয়ালা পণ্য; ক্যাপচা hook (`web_form_captcha_on`) + rate limit (`web_form_rate_max` / `_window_min`, device-hash দিয়ে); শুধু প্রয়োজনীয় ফিল্ড। ব্যবহারকারীর ভুল (bad_qty ইত্যাদি) সরাসরি ফেরত; সিস্টেমের ব্যর্থতা failed list-এ।
- **H4** `inbound_message_receive` + edge সোর্স `tools/edge/meta-webhook.ts` (GET verify, X-Hub-Signature-256 যাচাই edge এ, secret সেখানেই)। SQL এও pure-SQL HMAC (`inbound_sig_verify`, RFC 4231 ভেক্টরে পাস)। ভুল signature = বার্তা জমা হয় না, শুধু `rejected` লাইন (body ছাড়া)। শুধু বার্তা ঢোকে; উত্তর পাঠানো নেই।
- **H5** বার্তা নিজে অর্ডার হয় না। ঐচ্ছিক খসড়া: `online_order_save2(p_draft=true)` (সুইচ `inbox_autodraft_on` ডিফল্ট OFF, AI কল নেই)। খসড়ায় `is_draft`, নোট "খসড়া, যাচাই বাকি"; trigger `_oo_draft_guard76` খসড়াকে confirm/pack/deliver করতে দেয় না; মানুষ `online_order_draft_verify` করলে তবেই সাধারণ পথ।
- **H6** (ক) `order_dup_flags`: একই মোবাইল + একই পণ্য + একই দিন + ভিন্ন মাধ্যম = শুধু ফ্ল্যাগ (মার্জ নয়), `order_dup_flag_review` (POS approve)। (খ) `inbox_pii_guard_on` (OFF): ON হলে ফোন/ঠিকানা শুধু মালিক বা নতুন অনুমতি `inbox_contact_view` ধারকের; ব্রাউজারের সরাসরি কলাম-পড়াও rules-trigger দিয়ে বন্ধ হয়; প্রতিটি দেখা audit_log এ (action `view`, সবসময়)। (গ) `intake_failures` + `intake_retry_due` (সেটিং: `intake_max_tries`, `intake_retry_min`) + `intake_failures_list`/`dismiss`।
- **H7** `online_order_deliver` অপরিবর্তিত; নতুন কলাম সহ অর্ডারে পরীক্ষা: এক ডেলিভারি = এক বিক্রি, স্টক একবার কাটে, retry = dup।

## যাচাই হয়েছে (চালিয়ে)
- supabase/phase76_test.sql: **108 pass / 0 fail** (ফ্রেশ DB, phase8..71+76; phase76 দ্বিতীয়/তৃতীয়বার চালানো নির্ভুল)। বিষয়: ১) একই ওয়েব জমা দুইবার = ১ অর্ডার (phase76_test.sql, T7) ২) ক্লায়েন্টের ভুল দাম (1) উপেক্ষিত, মোট ৩×১০০=৩০০ (T7) ৩) একই বার্তা দুইবার = ১ ইনবক্স সারি, অন্য channel-এ একই external_id আলাদা (T3) ৪) ভুল signature প্রত্যাখ্যাত, বার্তা নেই (T3), HMAC RFC 4231 কেস ২ ও ৬ (T4) ৫) ইনবক্স থেকে রূপান্তরে status+link, দ্বিতীয়বার refused, অন্য channel-এর বার্তা refused (T6) ৬) একই অর্ডার দুই channel = ফ্ল্যাগ, একই channel/ভিন্ন পণ্য = না (T8) ৭) ফোন/ঠিকানা অননুমোদিতের কাছে ঢাকা, অনুমতিধারী/মালিক দেখে, প্রতিবার audit (T9) ৮) webhook/ফর্ম ব্যর্থতা failed list-এ, retry, max-tries পরে dead (T5, T7) ৯) ব্রাউজার role সরাসরি insert refused (T6, T0) ১০) খসড়া confirm/deliver refused, স্টক ও sales অপরিবর্তিত, verify এর পর স্বাভাবিক (T10) ১১) deliver → ১ sale, স্টক ১ বার (T11) ১২) বোর্ড সংখ্যা/নীরবতা সতর্কতা (T12) ১৩) append-only (T13)।
- web: `node tests/web/inbox_test.js` → **29 pass / 0 fail** (stub DOM, ব্রাউজার নয়); `node --check web/inbox.js` ঠিক।
- রিগ্রেশন (phase71 পর্যন্ত DB বনাম +phase76 DB): phase61 114/0 → 114/0; phase62 74/0 → 74/0; phase47 70/2 → 70/2 (একই ২টি ফেল, phase62 এর ইচ্ছাকৃত পরিবর্তন: "T1 role list opens it", "T1 head management allowed + health"); phase48 54/0 → 54/0; phase54 84/0 → 84/0; phase70 28/0 → 28/0; phase71 26/0 → 26/0।

## পড়ে বোঝা (চালানো হয়নি)
- tools/edge/web-order.ts, tools/edge/meta-webhook.ts: Deno/TS সোর্স, কখনো চালানো/deploy করা হয়নি; Meta payload ফিল্ডের নাম (entry[].messaging[].message.mid, entry[].changes[].value.messages[], metadata.phone_number_id) স্মৃতি থেকে — Meta-র বর্তমান ডকে মেলাতে হবে।
- Meta সম্পর্কে ওয়েব সার্চে (সরাসরি developers.facebook.com খোলা যায়নি, নেটওয়ার্ক বন্ধ) যা পাওয়া গেছে: X-Hub-Signature-256 = "sha256=" + HMAC-SHA256(app secret, **raw body**); ওয়েবহুক ব্যর্থ থাকলে ১৫ মিনিটে alert, ১ ঘণ্টা ব্যর্থ থাকলে অ্যাপ ওই Page-এর webhook থেকে unsubscribe হতে পারে (Messenger ডক সার্চ-সারাংশ); Instagram: instagram_basic, instagram_manage_messages, pages_manage_metadata দরকার, অ্যাপ publish/Live হতে হয়, নিজের ব্যবসার জন্য হলে App Review লাগে না — অন্যের হলে লাগে (সার্চ-সারাংশ); WhatsApp: গ্রাহক মেসেজ দিলে ২৪ ঘণ্টার সার্ভিস উইন্ডো, তার বাইরে অনুমোদিত টেমপ্লেট (সার্চ-সারাংশ, আংশিক তৃতীয়-পক্ষ সূত্র); Meta ডুপ্লিকেট ডেলিভারি পাঠাতে পারে (তাই external_id unique)।
- web/inbox.js এর ব্যবহার ফোনে কেমন দেখায়: চোখে দেখা হয়নি।

## যাচাই হয়নি
- Meta Business Verification কী কী লাগে, pages_messaging ও WhatsApp Business-এর App Review নিয়ম, **বাংলাদেশে প্রাপ্যতা/খরচ**, Messenger-এর উত্তরের সময়সীমা: কিছুই যাচাই হয়নি। retry "৩৬ ঘণ্টা" দাবি একটি তৃতীয়-পক্ষ সূত্রে, Meta-র নিজের সারাংশে ভিন্ন — অযাচাইকৃত।
- সত্যিকারের Meta/ক্যাপচা/ফর্ম হোস্টিং-এর সাথে কোনো সংযোগ বানানো বা পরীক্ষা হয়নি। সুতরাং "ফেসবুক/ইনস্টাগ্রাম/হোয়াটসঅ্যাপ বার্তা আসছে" — **এটা চলছে না**; কেবল ডাটাবেস দিক তৈরি ও পরীক্ষিত।
- intake_retry_due কে নিয়মিত ডাকার cron (GitHub Actions/Supabase cron) লেখা হয়নি।
- ক্যাপচা প্রদানকারীর verify-URL/ফিল্ড (Turnstile/reCAPTCHA) যাচাই হয়নি; edge-এ জেনেরিক।
- ছবি/ফাইল সংযুক্তি: শুধু রেফারেন্স (URL/id) রাখা হয়; ফাইল ডাউনলোড/সংরক্ষণ নেই; Meta-র ছবি-URL অল্প সময়ে মেয়াদ শেষ হয় কিনা যাচাই হয়নি।
- ওয়েব ফর্মের দাম দেখানো হয় ক্যাটালগ থেকে (শুধু প্রদর্শন); delivery charge/advance ফর্মে নেই (স্টাফ নিশ্চিতের সময় বদলায়)।

## অন্য জরুরি পর্যবেক্ষণ
- web/salesx.js:123 `sb.from('online_orders').select('*')` — টেবিলে কলাম-স্তরের grant (sale_client বাদ) থাকায় রিয়েল Postgres/PostgREST-এ `select *` permission-denied হওয়ার কথা (mock টেস্টে ধরা পড়েনি)। `online_order_get` ব্যবহার করা উচিত। আমি salesx.js বদলাইনি।
- ব্যর্থ-signature লাইন আক্রমণকারী ভরিয়ে দিতে পারে (rejected সারি); সীমা/পরিষ্কারের নীতি মালিকের সিদ্ধান্ত।
- intake bot একটি সাধারণ সীমিত ব্যবহারকারী যার POS 'enter' role ও শাখা লাগে (কারণ অর্ডার বিদ্যমান online_order_save দিয়ে যায়) — পাসওয়ার্ড ফাঁস হলে সে বিক্রিও করতে পারবে। বিকল্প: আলাদা সীমিত role/শাখা।

## মালিকের সিদ্ধান্ত (OWNER DECISIONS)
1. কোন কোন channel চালু (শাখা/role সহ)? ফেসবুক/ইনস্টাগ্রাম/হোয়াটসঅ্যাপ আদৌ নেবেন কিনা (বাংলাদেশে প্রাপ্যতা যাচাই আগে)।
2. `inbox_pii_guard_on` চালু হবে কিনা, এবং কারা `inbox_contact_view` পাবে (ডিফল্ট: কেউ না, শুধু মালিক)।
3. ওয়েব ফর্মের rate limit (ডিফল্ট ১০ বার/৬০ মিনিট), ক্যাপচা বাধ্যতামূলক কিনা, নীরবতার সতর্কতা কত ঘণ্টা (ডিফল্ট ২৪; ০ = বন্ধ)।
4. স্বয়ংক্রিয় খসড়া (`inbox_autodraft_on`) আদৌ চালু করবেন কিনা; কে খসড়া যাচাই করবে।
5. intake bot-এর জন্য আলাদা role/শাখা, এবং ব্যর্থ-signature সারি কতদিন রাখা হবে।
6. ফর্মের অর্ডারে delivery charge/advance কীভাবে ঠিক হবে (এখন স্টাফ পরে বদলায়)।

## মালিকের ফোনে করার কাজ (সুইচবোর্ড/অনুমতি পর্দা; কোনো কম্পিউটার লাগে না)
- phase76.sql পেস্ট (আগের মতো), সুইচবোর্ডে `online_orders_on`, `inbox_on`, পরে দরকার মতো `web_form_on`/`meta_intake_on` চালু; সংখ্যার সেটিং ঠিক করা।
- (ইনবক্স পর্দার "মাধ্যম" ট্যাব এখন শুধু দেখায়; channel তৈরির পর্দা এখনো নেই — `sales_channel_save` ফাংশন আছে, তৈরির UI বাকি।) → এই কারণে channel যোগ করতে আপাতত সাহায্য লাগবে।

## ফোনে সম্ভব নয় এমন সেটআপ (আলাদা তালিকা)
1. Supabase Edge Function deploy (`supabase functions deploy web-order --no-verify-jwt`, `meta-webhook --no-verify-jwt`) — CLI/কম্পিউটার লাগে।
2. Secrets সেট (শুধু নাম): META_APP_SECRET, META_VERIFY_TOKEN, INTAKE_BOT_EMAIL, INTAKE_BOT_PASSWORD, WEB_FORM_SALT, CAPTCHA_SECRET, CAPTCHA_VERIFY_URL (সব Supabase secret store-এ; repo/চ্যাটে কখনো নয়)।
3. intake bot ব্যবহারকারী তৈরি (Supabase Auth) + `intake_bot_set` দিয়ে চিহ্নিত + POS role/শাখা দেওয়া।
4. Meta Developer অ্যাপ তৈরি, Business Verification/App Review (প্রযোজ্য হলে), Page/Instagram/WhatsApp নম্বর সংযোগ, webhook callback URL নিবন্ধন — বাইরের অ্যাকাউন্ট ও অনুমোদন।
5. ক্যাপচা পরিষেবার অ্যাকাউন্ট (ঐচ্ছিক); ওয়েব ফর্মের পাবলিক URL পাওয়ার পর `web_form_public_url` সেটিংয়ে বসানো (এটা ফোনে সম্ভব, কিন্তু URL আগে লাগে)।
6. `intake_retry_due` নিয়মিত চালানোর cron (GitHub Actions বা Supabase scheduled function)।

## ia.js ও index.html (লিড যোগ করবে; আমি ছুঁইনি)
```
rec('inbox', 'sale', ['বার্তা ইনবক্স', 'Message inbox', 'Message inbox'], { icon: 'doc', ok: pos, kw: ['inbox', 'message', 'facebook', 'messenger', 'instagram', 'whatsapp', 'web form', 'বার্তা', 'ইনবক্স', 'অর্ডার'] }),
```
`<script src="inbox.js"></script>` — salesx.js এর পরে। sw.js precache থাকলে inbox.js যোগ করুন। data-act নাম ib_ প্রিফিক্সে।
