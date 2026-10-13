---
id: purchase_flow
title_bn: ক্রয়ের ধারা (সরবরাহকারী থেকে পরিশোধ)
title_en: Purchase flow (supplier to payment)
tags: purchase, supplier, grn, bill, payable, ক্রয়, কেনা, সরবরাহকারী, বিল
requires: 
optional_phase: 
steps:
- route: settings2/suppliers | check: health:supplier_no_credit_days | bn: সরবরাহকারী যোগ করুন, বাকির দিন দিন | en: Add suppliers with their credit days
- route: switchboard | check: rule:grn_receipt_source | bn: কেনা মাল কোথা থেকে স্টকে ওঠে: ক্রয় পেজ না GRN | en: Choose where bought goods enter stock: purchase page or GRN
- route: purchase/new | check: grant:purchase_entry | bn: ক্রয় বিল লিখে পোস্ট করুন | en: Write and post the purchase bill
- route: switchboard | check: rule:purchase_separate_poster | bn: যিনি লিখলেন তিনিই পোস্ট করবেন না (চাইলে) | en: Optionally: the writer cannot post
- route: switchboard | check: rule_set:purchase_cost_jump_pct | bn: দাম হঠাৎ বাড়লে জানানোর % দিন | en: Set the cost-jump % that alerts the owner
- route: payables | check: grant:supplier_pay | bn: পাওনা দেখে পরিশোধ করুন | en: See payables and pay
---

