# Step Inv (bos92) — বিক্রির পর ইনভয়েস পর্দায় দেখানো, তারপর Print / Email / SMS / WhatsApp

Branch `fix/phase-Inv` (from `integration/p72-p79`). Live DB, main, other worktrees: not touched. No real person names (test data only).

## মালিকের অনুরোধ, এক লাইনে
ক্যাশ সেলের পর ইনভয়েস সরাসরি দেখা যাচ্ছিল না; Print কাজ করত শুধু প্রিন্টার জোড়া থাকলে। এখন: সেল শেষ হলেই ইনভয়েস ফোনের পর্দায় (রসিদ-আকারে), নিচে Print, Email, SMS, WhatsApp, Share, Copy, Download।

## কী বানানো হয়েছে
* `web/invoiceview.js` (নতুন) — `B.invoiceview`. পর্দায় ইনভয়েস কার্ড (ফোনের প্রস্থে), বোতাম: Print, SMS, WhatsApp, Email, Share, Copy text, Download (একটি স্বয়ংসম্পূর্ণ .html ফাইল, খুলে প্রিন্ট বা "Save as PDF" করা যায়)।
  * সেটিং `pos_show_invoice_after_sale`: `never` (ডিফল্ট = আজকের আচরণ, কিছুই বদলায় না) / `ask` (সেলের পর "Show invoice" বার) / `always` (নিজে থেকে খোলে)।
  * **সুপারিশ: `always`** (Rules / Switchboard থেকে মালিক বদলাবেন)। ডিফল্ট `never` রাখা হয়েছে যাতে কিছু না করলে আগের মতোই চলে।
  * অফলাইন: সেল কিউতে গেলে ইনভয়েস লোকাল কার্ট থেকে আঁকা হয়, নম্বর `Q-xxxxxx` (সাময়িক), "Pending sync" লেখা ও "Check sync" বোতাম; সার্ভারে গেলে চূড়ান্ত নম্বর আসে।
  * অনলাইনে প্রথমে কার্ট থেকে সঙ্গে সঙ্গে আঁকে, পরে `invoice_data92` এর সার্ভার-কপি দিয়ে বদলায় (VAT, আইটেমের ইংরেজি নাম সহ)। SQL না চালানো থাকলে কার্ট-কপি থেকে যায়, কিছু ভাঙে না।
  * Print: আগের পথেই (`B.invoice.templateFor` → `renderDoc` → `printHtml` → `window.print`)। প্রিন্ট না চললে (ফাংশন নেই / এরর) নরম লেখা: "এই ফোনে Print করা গেল না ... Share বা Download ব্যবহার করুন"; প্রিন্ট বোতামের নিচে সবসময় ছোট ইঙ্গিতও থাকে।
  * Email / SMS / WhatsApp: **শুধু ডিভাইসের deep link** — `mailto:`, `sms:+880…?body=` (iPhone-এ `&body=`), `https://wa.me/880…?text=`। বার্তায় ইনভয়েসের লেখা (SMS-এ ছোট সারাংশ)। গ্রাহকের নম্বর জানা থাকলে বসানো থাকে, নইলে লিখতে বলে। **পাঠানো হয় ব্যবহারকারীর নিজের ফোনের অ্যাপ থেকে, সেখানে Send চাপলে।** সার্ভার থেকে স্বয়ংক্রিয় SMS/WhatsApp বানানো হয়নি, কারণ তার জন্য প্রোভাইডার অ্যাকাউন্ট ও গোপন চাবি লাগে। কোনো paid API নেই, কোনো secret নেই।
  * ইনভয়েসের কোনো পাবলিক লিংক নেই (লিংক দিতে হলে সার্ভারে পাবলিক পাতা/টোকেন লাগত) — তাই বার্তায় শুধু লেখা যায়।
  * আজকের তালিকার সেল-শিটে নতুন বোতাম "View / send invoice"; এবং নতুন পাতা `#/invoiceview` (যেকোনো তারিখের সেল, ট্যাপ করলে ইনভয়েস) — `ia.js`-এ `rec('invoiceview', …)`।
* `web/pos.js` — তিনটি ছোট সংযোজন, সবই `bos92` চিহ্নিত এবং `if (B.invoiceview)` দিয়ে ঘেরা (invoiceview.js না থাকলে হুবহু আগের মতো): সফল সেলের পর, অফলাইন কিউতে রাখার পর, আর সেল-শিটে একটি বোতাম। অন্য এজেন্টদের bos83 / X সম্পাদনা অক্ষত।
* `web/ia.js` — একটি `rec` যোগ (শেষে)। `web/index.html` — `<script src="invoiceview.js">` শেষে যোগ।
* `supabase/phase92.sql` (+ `phase92_test.sql`) — additive, দুবার paste নিরাপদ, শুরুতে guard (phase 72..88 লাগবে):
  * rule `pos_show_invoice_after_sale` (module pos, choice never|ask|always, default never; hint-এ সুপারিশ বাংলা/mix/English)।
  * টেবিল `invoice_shares` (sale, channel print|email|sms|whatsapp|share|copy|download, by, at, location): **append-only** (update/delete/truncate ট্রিগারে বন্ধ), RLS চালু ও ব্রাউজারকে কোনো grant নেই, `audit_log`-এও ধরা পড়ে। গ্রাহকের নম্বর/ইমেইল এখানে রাখা হয় না, খরচের তথ্য নেই।
  * `invoice_data92(p_sale, p_client)`: একটি সেলের পূর্ণ ইনভয়েস-তথ্য (শিরোনাম, লাইন, মোট, ডিসকাউন্ট, VAT, পেমেন্ট, গ্রাহক, বিক্রেতা)। **খরচ-নিরাপদ গঠনগতভাবে:** লাইনের প্রতিটি key নাম ধরে বসানো (item_id, code, name, name_en, name_mix, unit, qty, price, amount, custom); `item_costs`/`stock_ledger` ছোঁয়াই হয় না। গ্রাহকের মোবাইল শুধু মালিক / POS approve / `view_customer_mobile` / সেই সেলের নিজের বিক্রেতা দেখেন; অন্যরা নাম পান, নম্বর `null` (`masked: true`)। ইমেইল ফাইলে রাখা হয় না (customers টেবিলে ইমেইল কলামই নেই) — তাই ইমেইল প্রতিবার লিখতে হয়। শেয়ার-লগ (কে/কখন/কোন চ্যানেল) দেখেন শুধু মালিক ও POS approve।
  * `invoice_share_log92(p_sale, p_channel, p_client)`: লগ লেখার একমাত্র পথ। POS view/enter ও স্থান-অনুমতি লাগে।

## যাচাই হয়েছে (চালিয়ে দেখা)
* SQL, ফ্রেশ বিল্ড (phase8…88 + 92), পোর্ট 5544: `phase92_test.sql` **46 pass / 0 fail**। দুবার paste: rule-এর মান ও লগের সারি অক্ষত। কভার: rule আকার/ডিফল্ট/তিন ভাষা/সুপারিশ; টেবিল ব্রাউজারের কাছে বন্ধ; ফাংশন anon-এর কাছে বন্ধ; ইনভয়েসের হিসাব হাতে-গোনা (সাবটোটাল 280, ডিসকাউন্ট 28, মোট 252); খরচ কোথাও নেই (সিক্রেট খরচ 63.37 আউটপুটে নেই, শুধু সাদা-তালিকার key); মোবাইল ঢাকা/খোলা (অন্য বিক্রেতা, ম্যানেজার, মালিক, নিজের সেল); অন্য স্থান/রোলহীন ব্যবহারকারী বন্ধ; লগ ৫টি চ্যানেল, ভুল চ্যানেল বন্ধ, update/delete/truncate বন্ধ, audit_log-এ ধরা; VAT (বাইরে 9.00, অন্তর্ভুক্ত 8.57, সুইচ বন্ধে নেই); `record_sale2` ইত্যাদি অপরিবর্তিত।
* Node, mocked rpc, একা একা: `invoiceview_test.js` **65 pass / 0 fail** (তিন ভাষা — ইংরেজি স্লটে বাংলা অক্ষর নেই; সেটিং never/ask/always; অফলাইন সেলের সাময়িক নম্বর; Check sync; deep link গঠন; ভুল নম্বর/ইমেইলে খোলে না; প্রিন্টার-না-থাকা তিন রকম ফলব্যাক; Share/Copy/Download; গোপনীয়তা; ইউনিক data-act নাম; pos.js সম্পাদনা সংখ্যা)।
* Playwright (ফোন ৩৬০px, আসল pos.js + invoice.js + invoiceview.js, mocked rpc): `invoiceview_pw_test.js` **37 pass / 0 fail**, পেজ এরর নেই: never = আগের মতো; always = কার্ড, পুরনো print-বার সরে যায়; Print → `window.print`; প্রিন্ট ব্যর্থ → ফলব্যাক লেখা; তিনটি deep link; লগে নম্বর/ইমেইল যায় না; ask-বার; অফলাইন Q-নম্বর → ফিরলে চূড়ান্ত নম্বর; ফাংশন-না-থাকা ডাটাবেস; আজকের তালিকা ও `#/invoiceview` থেকে খোলা; বাংলা মোড; কোথাও অনুভূমিক overflow নেই। স্ক্রিনশট: `tests/web/inv92_*.png`।
* আগের টেস্ট অপরিবর্তিত ও আমার চেকআউটের বিরুদ্ধে চালানো (ROOT বদলে কপি করে): pos2 — HEAD-এর সাথে হুবহু একই আউটপুট (HEAD-তেও "old queued payload sent" একটি পুরনো FAIL, bos83 replay পথের কারণে; আমার বদল নয়), pos_units 0 failure, posfail 23/0, lang_en 80 স্ট্রিং/0 বাংলা, ia 0, nav ok, nav2 0, customers 0, invoice_test 0 (ডিফল্ট never = পুরনো Print-বার অক্ষত)।
* পুরনো SQL স্যুট (প্রতিটি নিজের ফ্রেশ বিল্ডে, phase92 সহ): phase8 107 (1 fail), phase10 307 (1), phase43 144/0, phase53 112/0, phase62 74/0, phase79 77/0, phase83 76/0, phase84 64/0, phase87 53 (1 fail), phase88 47/0। প্রতিটি fail জানা baseline: phase8 T1 "staff direct update rules", phase10 T12 "overdue", phase87 T0 "re-created functions carry bos87 and KEEP older tags" (phase92 ছাড়া ফ্রেশ বিল্ডেও একই fail — যাচাই করা)। বাকি (phase11…82, 85, 86) নতুন করে চালানো হয়নি: phase92 কোনো পুরনো টেবিল/ফাংশন বদলায় না (শুধু নতুন টেবিল, ২ ফাংশন, ১ rule)।

## পড়ে বোঝা (চালিয়ে দেখা হয়নি)
* `sms:` লিংকের `?body=` / `&body=` ভেদ (Android / iOS) কোড পড়ে ও পরিচিত আচরণ থেকে; আসল ফোনে পরীক্ষা হয়নি।
* `navigator.share` ও Clipboard-এর আচরণ ব্রাউজারভেদে আলাদা; কোডে ফলব্যাক আছে (শেয়ার না থাকলে কপি)।
* অন্য দেশের নম্বর: `+` দিয়ে লিখলে অঙ্কগুলো wa.me-তে যায়; শুধু বাংলাদেশি 01XXXXXXXXX নিয়মটি যাচাই করা।
* সার্ভারের `invoice_data92` আর পুরনো ডাটাবেসে (phase92 না চালানো) — ক্লায়েন্ট কার্ট-কপিতে ফিরে যায়, এটা mocked "function missing" দিয়ে দেখা হয়েছে, আসল পুরনো ডাটাবেসে নয়।

## যাচাই হয়নি (স্পষ্ট বলা)
* **আসল প্রিন্টার** (থার্মাল/A4) — কোনো প্রিন্টারে ছাপা হয়নি; ব্রাউজার জানে না প্রিন্টার জোড়া আছে কি না, তাই "প্রিন্টার নেই" ধরা যায় শুধু যখন print ফাংশন নেই বা এরর দেয়; নইলে ফোনের নিজের প্রিন্ট জানালা খোলে (সেখানে "Save as PDF" মেলে) এবং নিচের হিন্ট Share/Download দেখায়।
* **আসল ফোন, আসল WhatsApp / SMS / Email অ্যাপ** — কেবল লিংকের গঠন যাচাই (হেডলেস ব্রাউজারে anchor click ধরে), অ্যাপ খুলে বার্তা সত্যিই বসেছে কি না দেখা হয়নি। দীর্ঘ বার্তা কোনো অ্যাপ ছেঁটে দেয় কি না অজানা (SMS তাই ছোট সারাংশ)।
* PDF/ছবি সরাসরি তৈরি হয় না (লাইব্রেরি ছাড়া নির্ভরযোগ্য নয়); Download মানে .html ফাইল, যা খুলে PDF করা যায়।
* লাইভ ডাটাবেসে phase92 চালানো হয়নি; মালিককে SQL Editor-এ paste করতে হবে (phase 72..88 আগে থাকতে হবে)। না চালালে ওয়েব অংশ কার্ট-কপি দিয়ে কাজ করে, শুধু শেয়ার-লগ ও VAT/ইংরেজি নাম আসে না।
* স্বয়ংক্রিয় সার্ভার-সাইড SMS/WhatsApp/Email: **বানানো হয়নি** (provider account লাগে)।

## মালিকের জন্য ধাপ
1. phase92.sql একবার paste (দুবার করলেও ক্ষতি নেই)।
2. Rules-এ `pos_show_invoice_after_sale` = `always` (সুপারিশ)।
3. ফোনে একটি ক্যাশ সেল করে দেখুন: ইনভয়েস আসে কি না, Print / WhatsApp / SMS / Email-এ নিজের নম্বরে একবার পাঠিয়ে দেখুন।
