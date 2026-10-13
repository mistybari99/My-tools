---
id: assistant_setup
title_bn: সহকারী (প্রশ্ন করুন) সেটআপ
title_en: Set up the assistant
tags: assistant, ask, ai, সহকারী, প্রশ্ন
requires: 
optional_phase: 
steps:
- route: switchboard | check: rule:assistant_on | bn: সহকারী চালু / বন্ধ | en: Assistant on / off
- route: switchboard | check: rule:assistant_roles | bn: আর কোন ভূমিকা ব্যবহার করবে | en: Which other roles may use it
- route: delegation | check: grant:assistant_use | bn: নির্দিষ্ট মানুষকে ব্যবহারের অনুমতি | en: Give the right to specific people
- route: delegation | check: grant:assistant_health | bn: কে সেটআপ-চেক দেখবেন | en: Who may see the setup check
- route: switchboard | check: rule:assistant_provider | bn: ইঞ্জিন: ফোনেই (বিনা খরচে) থাকুক; AI প্রক্সি শুধু অনুমোদনের পরে | en: Engine: keep it on the phone (free); the AI proxy only after approval
---

