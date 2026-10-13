---
id: open_shop
title_bn: দোকান খোলা (দিনের শুরু)
title_en: Open the shop (start of day)
tags: open, morning, start, দোকান খোলা, সকাল, শুরু
requires: 
optional_phase: 
steps:
- route: flow/open | check: none | bn: দিন শুরুর ধাপগুলো এক পেজে: "দোকান খোলা" রুটিন খুলুন | en: Open the "Open shop" routine: all morning steps on one page
- route: form/14-1 | check: none | bn: ড্রয়ার গণনা (14-1): গত রাতের রেখে-যাওয়া টাকা গুনে লিখুন | en: Drawer count (14-1): count the float left last night
- route: form/02-1 | check: none | bn: হাজিরা (02-1) লিখুন | en: Record attendance (02-1)
- route: stock | check: rule_set:count_tolerance_pct | bn: স্টক দেখুন; গণনার সহনশীলতা % নিয়মে লেখা থাকলে বেশি গরমিল নিজে থেকে ধরা পড়ে | en: Check stock; with count_tolerance_pct set, big count differences are flagged
- route: exceptions | check: none | bn: খোলা ব্যতিক্রম (গরমিল) আগে মিটিয়ে নিন | en: Clear open exceptions first
- route: pos | check: none | bn: বিক্রি শুরু করুন (POS) | en: Start selling (POS)
---
The routine page (#/flow/open) ticks a step only when the server shows it done; a skipped step needs a note.
