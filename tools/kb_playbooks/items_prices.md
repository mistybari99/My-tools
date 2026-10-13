---
id: items_prices
title_bn: আইটেম ও দাম বসানো
title_en: Add items and prices
tags: item, price, product, দাম, আইটেম, পণ্য, unit, একক
requires: 
optional_phase: 
steps:
- route: itemimport | check: none | bn: মাস্টার তালিকা ইমপোর্ট (একবার, মালিক) | en: Import the item master (once, owner)
- route: bulkitems | check: health:items_no_price | bn: বিক্রয়যোগ্য সব আইটেমে বিক্রয়মূল্য দিন | en: Give every sellable item a selling price
- route: bulkitems | check: health:items_no_unit | bn: প্রতিটি আইটেমের একক (কেজি / পিস) দিন | en: Give every item a unit (kg / piece)
- route: switchboard | check: rule:items_hide_unpriced_in_pos | bn: দাম ছাড়া আইটেম POS-এ লুকানো থাকবে কিনা | en: Decide whether unpriced items are hidden in POS
- route: itemmap | check: none | bn: পুরনো আইটেমগুলো মাস্টার কোডের সাথে মেলান | en: Link old items to master codes
---

