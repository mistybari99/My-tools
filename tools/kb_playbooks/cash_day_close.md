---
id: cash_day_close
title_bn: দিনের ক্যাশ বন্ধ (14-1 → 10-1 → 10-3)
title_en: Cash day close (14-1, 10-1, 10-3)
tags: close, day close, cash, deposit, ক্যাশ, দিন শেষ, জমা, হিসাব মেলানো
requires: 
optional_phase: 
steps:
- route: flow/close | check: none | bn: "দিন শেষ" রুটিন খুলুন: সব ধাপ এক পেজে | en: Open the "Close day" routine: all steps on one page
- route: form/14-1 | check: none | bn: ড্রয়ার গণনা ও হিসাব (14-1) | en: Drawer count and balance (14-1)
- route: form/10-1 | check: none | bn: হাবে ক্যাশ হস্তান্তর (10-1) | en: Cash handover to the hub (10-1)
- route: form/10-3 | check: none | bn: ডিজিটাল / ব্যাংক জমা (10-3) | en: Digital / bank deposit (10-3)
- route: cashmoves | check: grant:cash_move | bn: ব্যাংক জমা, মালিকের টাকা, অগ্রিম লিখুন | en: Record bank deposits, owner money, advances
- route: daybook | check: health:daybook_no_start | bn: দৈনিক খাতার শুরুর তারিখ দিন | en: Set the day-book start date
- route: daybook | check: health:daybook_no_opening | bn: শুরুর ক্যাশ / ব্যাংক / মোবাইল ব্যালান্স দিন | en: Enter the opening cash / bank / mobile balances
---

