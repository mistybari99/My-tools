---
id: blind_count_pin
title_bn: ব্লাইন্ড কাউন্ট ও পিন-সই
title_en: Blind count and PIN signature
tags: blind count, pin, signature, witness, গণনা, পিন, সই, সাক্ষী
requires: 
optional_phase: 
steps:
- route: switchboard | check: rule:blind_count_on | bn: ব্লাইন্ড কাউন্ট চালু: আগে গণনা, পরে প্রত্যাশিত সংখ্যা | en: Blind count on: count first, then see the expected figure
- route: switchboard | check: health:blind_no_form | bn: কোন ফর্মে ব্লাইন্ড কাউন্ট হবে তা চালু করুন | en: Switch it on for the forms that need it
- route: switchboard | check: rule:owner_sees_expected_first | bn: মালিক আগে প্রত্যাশিত সংখ্যা দেখবেন কিনা | en: Whether the owner may see the expected figure first
- route: delegation | check: grant:see_expected | bn: কে আগে প্রত্যাশিত সংখ্যা দেখতে পারবেন | en: Who may see the expected figure before counting
- route: switchboard | check: rule:pin_signature_on | bn: পিন-সই চালু: দ্বিতীয় জন নিজের লগইন ও পিনে সই করেন | en: PIN signature on: the second person signs with their own login and PIN
- route: switchboard | check: health:pin_no_form | bn: কোন ফর্মে পিন-সই লাগবে তা চালু করুন | en: Switch it on for the forms that need it
---

