---
id: rollout
title_bn: কাগজ → পাশাপাশি → অ্যাপ
title_en: Paper, Parallel, App rollout
tags: rollout, paper, parallel, app, কাগজ, পাশাপাশি, অ্যাপ
requires: 
optional_phase: 
steps:
- route: rollout | check: grant:rollout_manage | bn: রোলআউট বোর্ডে ফর্ম × জায়গা বেছে মোড ঠিক করুন | en: On the rollout board choose the mode per form x place
- route: rollout | check: health:paper_never_app | bn: কাগজে চলা ফর্ম একবার পাশাপাশি চালিয়ে দেখুন | en: Try a paper form in Parallel
- route: parallel | check: health:parallel_no_pair | bn: পাশাপাশি মাসের জন্য তুলনার জোড়া ঠিক করুন | en: Name a comparison pair for the parallel month
- route: switchboard | check: rule:parallel_compare_on | bn: মাস-শেষে পাস/ফেল লাগবে কিনা | en: Whether month-end pass / fail is required
- route: switchboard | check: rule:rollout_enforce | bn: কাগজের ফর্মে নতুন অ্যাপ-এন্ট্রি আটকানো | en: Refuse new app entries on paper forms
- route: printbooks | check: none | bn: ছাপা বইয়ের নম্বর ও নোট রাখুন | en: Keep printed book serials and notes
---

