---
id: staff_access
title_bn: স্টাফ, ভূমিকা ও জায়গা
title_en: Staff, roles and places
tags: staff, role, permission, user, স্টাফ, কর্মী, ভূমিকা, অনুমতি
requires: 
optional_phase: 
steps:
- route: staff | check: health:staff_pending | bn: নতুন স্টাফ অ্যাকাউন্ট অনুমোদন দিন | en: Approve new staff accounts
- route: staff | check: health:staff_no_role | bn: প্রত্যেককে একটি ভূমিকা দিন | en: Give everyone a role
- route: staff | check: health:staff_no_location | bn: প্রত্যেককে তাঁর জায়গা দিন | en: Give everyone their place
- route: matrix | check: none | bn: ভূমিকা × ফর্ম অনুমতি দেখুন | en: Check role x form permissions
- route: delegation | check: health:only_owner_release_decide | bn: মালিক না থাকলে কে লাল-নিয়ন্ত্রণ ছাড় দেবেন | en: Who releases red controls when the owner is away
---

