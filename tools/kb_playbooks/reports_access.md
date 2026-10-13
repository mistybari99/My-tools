---
id: reports_access
title_bn: রিপোর্ট ও কে দেখবেন
title_en: Reports and who may see them
tags: report, access, cost, profit, রিপোর্ট, খরচ, লাভ, অনুমতি
requires: 
optional_phase: 
steps:
- route: delegation | check: health:reports_owner_only | bn: ম্যানেজারদের দরকারি রিপোর্ট-অনুমতি দিন (report_sales ইত্যাদি) | en: Give managers the report rights they need (report_sales ...)
- route: delegation | check: grant:view_cost | bn: খরচ / লাভ দেখার অনুমতি খুব কম জনকে দিন | en: Give cost / profit rights to very few
- route: switchboard | check: health:calendar_defaults | bn: অর্থবছর ও সপ্তাহের শুরু ঠিক করুন | en: Set the fiscal year and week start
- route: switchboard | check: rule_set:report_aging_buckets | bn: বাকির বয়সের ধাপ (যেমন 7,30,60) দিন | en: Set the receivable ageing buckets (e.g. 7,30,60)
- route: switchboard | check: rule_set:report_expiry_soon_days | bn: "শিগগির মেয়াদ শেষ" কত দিন | en: Days that count as "expiring soon"
- route: reports | check: none | bn: রিপোর্ট হাব খুলুন | en: Open the reports hub
---

