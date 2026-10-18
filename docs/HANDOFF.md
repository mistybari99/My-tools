# HANDOFF — কাজ কোথায় থেমে আছে (নতুন সেশনে এখান থেকে শুরু করুন)

হালনাগাদ: ১৮ অক্টোবর ২০২৬। ব্রাঞ্চ: `claude/supabase-readonly-audit-xo3qkp`।
এই ফাইলটি পড়লে কোনো নতুন সেশন বা এজেন্ট বুঝবে কী হয়েছে, কী বাকি, আর কোন নিয়ম মানতে হবে। আগে `CLAUDE.md` পড়ুন।

## ১. মূল নিয়ম (ভাঙবেন না)
- কোনো demo, বানানো নাম বা বানানো স্টাফ কোড, ডাটাবেস বা docs-এ যাবে না। প্রতিটি commit-এর আগে `python3 tools/check_no_demo_leak.py` (OK ছাপতে হবে)।
- লাইভ Supabase-এ এজেন্ট কখনো লেখে না। SQL মালিক নিজে paste করেন।
- `phase84_test_project_only*`, `84b*`, `84c*`, `*_test.sql` কখনো লাইভে paste হয় না।
- নতুন SQL শুধু নতুন ফেজ ফাইলে। পুরনো ফেজ বদলানো যাবে না। SQL দুবার paste করলে নিরাপদ হতে হবে।
- নতুন screen শুধু `web/ia.js` দিয়ে (`docs/IA_RULES.md`)। প্রধান ফিচার দৃশ্যমান থাকবে; তার ভেতরের setting ডিফল্টে বন্ধ। কোন প্রধান ফিচার দেখানো/লুকানো হবে, তা মালিক পরে ঠিক করবেন।
- ছাপা ফর্মের কোড (যেমন `02-1`) মালিকের অনুমোদন ছাড়া বদলানো যাবে না।
- মালিক আর কোনো সিদ্ধান্তের প্রশ্ন চান না। যুক্তিসঙ্গত, ব্যবসায়িক বিচারে সিদ্ধান্ত নিয়ে কাজ করুন এবং কী ঠিক করলেন তা জানান।

## ২. কী হয়ে আছে (সব push করা)
- ফেজ ৮–৪৭৮ আগের ধারায়। ফেজ ৪৭৯–৪৯৮ নতুন নম্বরে (আগে ৪৮০–৫৫৪, সমান্তরাল এজেন্টদের দেওয়া)।
- প্যাকেজ: X1 ফাউন্ডেশন, X2 ওয়েবসাইট, X3 সোশ্যাল, X4 AI, X5 ক্যামেরা, X6 বাজার বিশ্লেষণ, XB অর্ডার, XC দৈনিক সারাংশ।
- নতুন screen: `#/xcunsold`, `#/xcsummary`, `#/paycapture`, `#/cakejobs`, `#/riders`।
- নেভিগেশন: `web/navstack.js` (আগের পাতায় ফেরা, ২–৩ ধাপ, "মূল পাতা")।
- Switchboard-এ দুই-স্টেট লেআউট (Default / সব ঐচ্ছিক অংশ), snapshot ফাইল ও revert।
- নম্বর টুল: `tools/renumber.py` (ডিফল্টে শুধু দেখায়), `tools/check_numbering.py`, `tools/numbering_map.json`, নিয়ম `docs/NUMBERING.md`।
- লাইভ করার ধাপ: `docs/GO_LIVE.md`। SQL paste ক্রম: `docs/PASTE_ORDER.md`।

## ৩. যাচাইয়ের কমান্ড (সব exit 0 / OK হতে হবে)
- `python3 tools/check_no_demo_leak.py`
- `python3 tools/check_info_coverage.py`
- `python3 tools/check_ui_inventory.py`
- `python3 tools/check_numbering.py`
- `python3 tools/build_phase477.py --check`
- `python3 tools/test_testonly_files.py`
- web টেস্ট: `python3 tests/web/run_all.py --copy <scratch> --out <scratch>` (১০৯ স্যুট; ডিস্কে অনেক জায়গা লাগে)। টেস্ট চালানোর পর `git checkout -- tests/web/*.png` করে screenshot ফিরিয়ে দিন, commit করবেন না।

## ৪. বাকি কাজ
আপনার (মালিকের) কাজ:
1. Supabase-এ SQL paste (`docs/PASTE_ORDER.md` ক্রমে)।
2. Web ফাইল আপলোড (`docs/GO_LIVE.md` §3)।
3. অনুমতি ঠিক করা: `pay_verify`, `cake_price_manage`, `rider_manage`।
4. বাংলা লেখা পড়া; ফোনে ৩৬০px লেআউট দেখা।
5. `supabase/phase487.sql`-এর seed বর্ণনায় "phase 490" লেখা দেখা।

এজেন্টের কাজ (সময় হলে):
- পূর্ণ web টেস্ট একটানা একবার (ডিস্ক খালি থাকলে)।
- ৯টি info entry-তে `related` ফিল্ড (ঐচ্ছিক): `pay_capture_on`, `pay_capture_tol`, `cake_flow_on`, `cake_capacity_day`, `cake_lead_days`, `cake_photo_required`, `xb_delivery_on`, `cake_spec`, `cake_price_manage`।
- ফর্ম কোডের ক্রম গোছানো (শুধু মালিকের অনুমোদনের পরে; `docs/NUMBERING.md`, `tools/numbering_map.json`-এ `form_groups_approved` এখনো `false`)।
- দুই-স্টেট ডিজাইন (backup default → all-on → revert), দুইজন architect-এর বিতর্কসহ।
- X3 সোশ্যাল screen (Meta/WhatsApp অ্যাকাউন্ট ও public media URL-এর সিদ্ধান্ত লাগবে)।
- X5 ক্যামেরা আসল ফোনে পরীক্ষা।

## ৫. যা জানা নেই
- মালিকের Claude প্রজেক্টের ৮০টি ফাইলের আসল বিষয়বস্তু (এই repo-তে নেই)।
- ফোনে ৩৬০px লেআউট, SMS-এর ঠিক লেখা, লাইভ Supabase-এ `set_rule`-এর আচরণ।

## ৬. ব্যাকআপ কোথায়
- মালিকের ফোন ও Google Drive ফোল্ডার "Islamia BOS backup 2026-10-18": সূচি, GO_LIVE, commit তালিকা।
- `BACKUP_islamia_bos.zip`: নথি, পরিকল্পনা ও পুরো কথোপকথনের gzip রেকর্ড। মালিকের চ্যাটে পাঠানো হয়েছে।
- আসল কোড: GitHub `mistybari99/My-tools`।
