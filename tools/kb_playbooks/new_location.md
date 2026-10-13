---
id: new_location
title_bn: নতুন জায়গা (শোরুম / কারখানা) চালু করা
title_en: Set up a new location
tags: new location, branch, showroom, নতুন শোরুম, শাখা, জায়গা
requires: 
optional_phase: 
steps:
- route: locations | check: grant:location_manage | bn: লোকেশন পেজে নতুন জায়গা যোগ করুন (মালিক বা location_manage অনুমতি) | en: Add the place on Locations (owner or the location_manage right)
- route: locset | check: health:loc_no_sheet | bn: সেটিংস-শিট (0-1) পূরণ করে অনুমোদন দিন | en: Fill and approve the Location Settings Sheet (0-1)
- route: locset | check: health:loc_limit_blank | bn: সীমাগুলো লিখুন: ড্রয়ারের ফ্লোট, ক্যাশ সহনশীলতা, ছাড়ের সীমা, খরচের সর্বোচ্চ | en: Write the limits: drawer float, cash tolerance, discount limit, expense max
- route: switchboard | check: rule:location_start_first_of_month | bn: শুরু শুধু মাসের ১ তারিখে হবে কিনা ঠিক করুন | en: Decide whether a place may start only on the 1st of a month
- route: rollout | check: none | bn: কোন ফর্ম কাগজে / পাশাপাশি / অ্যাপে চলবে ঠিক করুন | en: Choose Paper / Parallel / App per form
- route: staff | check: health:staff_no_location | bn: স্টাফদের এই জায়গায় যুক্ত করুন | en: Give staff this place
---

