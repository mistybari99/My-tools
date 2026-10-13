---
id: pos_discounts
title_bn: POS: ছাড়, দাম বদল ও অনুমোদন
title_en: POS discounts, price changes and approvals
tags: discount, approval, price override, credit, ছাড়, ডিসকাউন্ট, অনুমোদন, বাকি
requires: 
optional_phase: 
steps:
- route: switchboard | check: rule:discount_mode_amount_on | bn: টাকায় ছাড় চালু / বন্ধ | en: Discount by amount on / off
- route: switchboard | check: rule:discount_mode_percent_on | bn: শতাংশে ছাড় চালু / বন্ধ | en: Discount by percent on / off
- route: locset | check: health:loc_limit_blank | bn: প্রতি শোরুমের ছাড়ের সীমা (discount_limit) দিন | en: Set the discount limit per showroom
- route: switchboard | check: rule:pos_discount_manager | bn: সীমার বেশি ছাড়ে অনুমোদন লাগবে কিনা | en: Whether a discount above the limit needs a granted person
- route: delegation | check: grant:discount_over_limit | bn: কে সীমার বেশি ছাড় দিতে পারবেন তা দিন | en: Give the discount_over_limit right to the right people
- route: switchboard | check: rule:pos_credit_mode | bn: বাকির সীমা পেরোলে: block / warn / off | en: Credit limit exceeded: block / warn / off
- route: exceptions | check: none | bn: ব্যতিক্রমগুলো নিয়মিত দেখুন | en: Review exceptions regularly
---

