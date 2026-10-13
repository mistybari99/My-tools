---
id: books_close
title_bn: হিসাব বন্ধ (লক) করা
title_en: Close the books (period lock)
tags: close books, lock, period, month end, হিসাব বন্ধ, লক, মাস শেষ
requires: 
optional_phase: 
steps:
- route: flow/month | check: none | bn: মাস-শেষের রুটিন চালান | en: Run the month-end routine
- route: pending | check: none | bn: অপেক্ষমাণ এন্ট্রি ও অনুমোদন শেষ করুন | en: Finish pending entries and approvals
- route: rules | check: health:books_never_closed | bn: হিসাব বন্ধের তারিখ (period_closed_until) দিন | en: Set the books-closed date (period_closed_until)
- route: delegation | check: grant:closed_period_edit | bn: বন্ধ সময়ে কে বদলাতে পারবেন (সাধারণত কেউ না) | en: Who may change closed dates (usually nobody)
- route: switchboard | check: rule:em_period | bn: বন্ধ সময়ে জরুরি অনুমোদন চলবে কিনা | en: Whether emergency approval works for closed dates
---

