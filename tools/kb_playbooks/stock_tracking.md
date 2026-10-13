---
id: stock_tracking
title_bn: স্টক-হিসাব চালু করা
title_en: Switch on stock tracking
tags: stock, tracking, inventory, স্টক, মজুত, opening
requires: 
optional_phase: 
steps:
- route: bulkitems | check: health:items_none_tracked | bn: যে আইটেমের স্টক গুনবেন সেগুলোতে "tracked" চালু করুন | en: Turn "tracked" on for items you count
- route: bulkitems | check: health:items_tracked_no_base | bn: tracked আইটেমের মূল একক ও ন্যূনতম স্টক দিন | en: Give tracked items a base unit and a minimum stock
- route: stock | check: grant:stock_opening | bn: প্রারম্ভিক স্টক লিখুন (stock_opening অনুমতি) | en: Enter opening stock (stock_opening right)
- route: switchboard | check: rule:stock_negative_mode | bn: স্টকের চেয়ে বেশি বিক্রি: allow / warn / block বেছে নিন | en: Choose what happens when selling beyond stock: allow / warn / block
- route: switchboard | check: rule:block_expired_sale | bn: মেয়াদোত্তীর্ণ মাল বিক্রি আটকাবেন কিনা | en: Decide whether expired stock is blocked at the till
- route: switchboard | check: rule:forms_post_to_ledger | bn: অনুমোদিত ফর্ম স্টক-খাতায় যাবে কিনা (পরে চালু করুন) | en: Decide whether approved forms post to the stock ledger
---

