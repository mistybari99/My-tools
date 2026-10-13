---
id: backups
title_bn: ব্যাকআপ ও সতর্কবার্তা
title_en: Backups and alerts
tags: backup, restore, alert, notification, ব্যাকআপ, সতর্ক
requires: 
optional_route: backup
optional_phase: phase46
steps:
- route: backup | check: health:backup_none | bn: স্বয়ংক্রিয় ব্যাকআপ চালু করুন (docs/OPS_SETUP.md) | en: Turn on the automatic backup (docs/OPS_SETUP.md)
- route: backup | check: health:backup_stale | bn: শেষ ব্যাকআপ কত পুরনো দেখুন | en: Check how old the last backup is
- route: switchboard | check: rule:backup_max_age_hours | bn: কত ঘণ্টা পুরনো হলে সতর্ক করবে | en: Hours before a backup counts as stale
- route: switchboard | check: rule:notify_on | bn: অ্যাপের ভিতরের সতর্কবার্তা চালু | en: In-app notifications on
---

