---
id: recipes_production
title_bn: রেসিপি ও উৎপাদন
title_en: Recipes and production
tags: recipe, production, factory, yield, রেসিপি, উৎপাদন, কারখানা
requires: 
optional_phase: 
steps:
- route: recipes | check: grant:recipe_manage | bn: রেসিপি লিখুন (recipe_manage অনুমতি) | en: Write recipes (recipe_manage right)
- route: recipes | check: health:recipe_no_yield | bn: প্রতিটি রেসিপিতে উৎপাদন-পরিমাণ (yield) দিন | en: Give every recipe a yield
- route: recipes | check: health:recipe_waste_blank | bn: লাইনগুলোতে অপচয় % দিন | en: Give the lines a waste %
- route: switchboard | check: rule:production_requires_recipe | bn: উৎপাদন শুধু রেসিপি দিয়ে হবে কিনা (রেসিপি তৈরির পরেই চালু করুন) | en: Production only through a recipe (switch on after recipes exist)
- route: switchboard | check: rule:production_short_mode | bn: কাঁচামাল কম হলে: আটকাবে, না সাধারণ স্টক-নিয়ম | en: When raw material is short: refuse or follow the stock rule
- route: switchboard | check: rule:packaging_consume_on | bn: প্যাকেজিং কখন স্টক থেকে কমবে | en: When packaging leaves stock
---

