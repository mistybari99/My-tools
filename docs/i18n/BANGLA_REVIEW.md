# Bangla / Bng-Eng proofreading of all NEW user-visible strings

Scope: everything added since commit `04eefa4` (`git diff 04eefa4..HEAD -- web/*.js web/ia.js`, the 45 new `BOS_T` keys in `web/i18n.js`, and the `label_bn / label_mix / label_en` seed rows in `supabase/phase72..103.sql`). Old (pre-04eefa4) texts are NOT reworded; they are used only as the style reference. Nothing in code was edited. Triples are `L(bn, en, mix)`.

Companion file with **every** instance (all 5634 rows, incl. the OK ones and the mechanical suggestions): `docs/i18n/BANGLA_REVIEW.csv`.

## 0. Numbers

| item | count |
|---|---|
| triple instances reviewed (web 5472 + SQL 162) | 5634 |
| unique triples (same en/bn/mix counted once) | 4608 |
| OK | 3510 (76.2%) |
| to fix (any non-OK verdict) | 1098 |
| - wrong rule: common word translated into Bangla in bn mode | 574 |
| - inconsistent term across screens | 199 |
| - mixed-up grammar | 178 |
| - too literal / machine-translated | 147 |
| of the to-fix: purely mechanical swaps (term / script / suffix), safe to batch | 816 |
| of the to-fix: need a human decision (meaning, grammar, literal) | 282 |
| "Bangla leaked into en" | 0 real cases (only the currency sign ৳ appears in 11 en strings; harmless) |

### How the verdicts were made (read this first)

1. **Automatic pass over all rows** (rule engine: owner word list, term table, bookish/literal lexicon, suffix spacing, mix-vs-en comparison). Suggestions starting with ≈ are mix lines derived from the bn text (owner words put in Latin, other loanwords still in Bangla letters) - polish by hand, then **manual reading** of the priority screens (POS, invoice, home badges, setup advisor, switchboard, ia.js, ownerboard, nav) and a random sample of ~130 rows the engine called OK. The sample was clean apart from the "mix drops detail" pattern, now also detected. Mechanical suggestions are marked `systemic`; check them in context (suffixes, verbs) before pasting.
2. **Rule interpretation for bn mode (assumption, please confirm).** "Common words stay English" is read as: Invoice, Stock, Cost, Bill, Item, Category, Sale, Report, Total, Date, Qty, Price, Supplier, Customer, Dashboard, Print, Share, Save, Cancel, Done, Apply, Switch, Approve, Draft, Void, Cash, Card, Bank appear **as the English word written in Bangla letters** in bn mode (this is how the OLD text does it: সেল, ডিসকাউন্ট, কার্ট, ইনভয়েস, স্টক) and **in Latin letters** in Bng/Eng mode. Exceptions kept in Latin in every mode: acronyms (GRN, POS, PIN, SMS, QR, CSV), `Qty`, `Done` (ডান reads as "right"), WhatsApp. If you instead want Latin letters in bn mode too, flip the "suggested bn" column: the only difference is the script of those ~28 words.
3. **Native Bangla used where the owner list wants the English word** is the single biggest finding (574 unique strings): খরচ for Cost, বিক্রি for Sale, গ্রাহক for Customer, অনুমোদন for Approve, বাতিল for Void/Cancel, তারিখ for Date, মোট for Total, দাম for Price/Cost, নগদ for Cash, সংরক্ষণ for Save, পণ্য/মাল for Item, সরবরাহকারী for Supplier. The new code uses both forms (e.g. আইটেম 102x vs পণ্য/মাল 26x; সাপ্লায়ার 30x vs সরবরাহকারী 20x; ক্যাশ 34x vs নগদ 7x), **often inside one file**, so the fix is a find-and-replace table (section 2), not 569 hand edits.
4. খরচ is overloaded: it is used for Cost and for Expense. Recommended split: **Cost = কস্ট, Expense = খরচ** (mix: cost / expense). Likewise বাতিল is used for Void, Cancel, Reject and Discard; বাকি for Due, Left and Waiting; ফেরত for Return, Refund and Change; জমা for Deposit, Submitted and Sync. The term table (section 3) gives one canonical word per concept.
5. Other recurring defects: (a) Latin word followed by a detached Bangla suffix ("Customer এর", "Production এ") - use the hyphen form already common in the app ("Customer-এর"); (b) mix lines that silently drop half of the English sentence ("Account ঠিক নয়" for "Account not valid (not a header or retired account)"); (c) over-formal words a shopkeeper does not say (অবচয়, অভাগিত, অনুমতিপ্রাপ্ত, বাধ্যতামূলক, আবশ্যক, তালাবদ্ধ, হিসাবরক্ষণ, প্রশাসন, ভূমিকা for Role); (d) mix = plain English copy for 4+ word sentences.

## 1. Priority list - the 30 worst strings the owner sees most

Order = screen traffic (setup advisor buttons, POS, invoice, Home badges, Switchboard, menu groups). Verdict names follow your list.

| # | file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|---|
| 1 | setupadvisor.js:20 | Apply recommended | প্রস্তাবিত প্রয়োগ | প্রস্তাবিত apply | too literal + wrong rule: common word translated into Bangla in bn mode (প্রয়োগ); mix half-English noun phrase | প্রস্তাবিতগুলো অ্যাপ্লাই করুন | Recommended apply করুন |
| 2 | setupadvisor.js:20 | Apply all recommended | সব প্রস্তাবিত প্রয়োগ | সব প্রস্তাবিত apply | too literal + wrong rule: common word translated into Bangla in bn mode | সব প্রস্তাবিত অ্যাপ্লাই করুন | সব recommended apply করুন |
| 3 | setupadvisor.js:21 | Apply anyway | তবুও প্রয়োগ | তবুও apply | too literal + wrong rule: common word translated into Bangla in bn mode | তবুও অ্যাপ্লাই করুন | তবুও apply করুন |
| 4 | setupadvisor.js:21 | Replace my value | আমার মানের বদলে প্রস্তাবিত | আমার value বদলে প্রস্তাবিত | too literal: reads as "recommended instead of my value", meaning unclear | আমার মান বদলে প্রস্তাবিতটা বসান | আমার value বদলে recommended বসান |
| 5 | setupadvisor.js:15 | Is it all flowing? | সব ঠিকঠাক বইছে? | সব ঠিকঠাক বইছে? | too literal ("বইছে" = flowing) | সব ঠিকমতো চলছে? | সব ঠিকমতো চলছে? |
| 6 | setupadvisor.js:31 | Flowing ✓ | ঠিক বইছে ✓ | ঠিক বইছে ✓ | too literal ("বইছে") | ঠিকমতো চলছে ✓ | ঠিকমতো চলছে ✓ |
| 7 | pos.js:41 | Save | সংরক্ষণ | Save | wrong rule: common word translated into Bangla in bn mode (সংরক্ষণ) - the most-pressed button | সেভ | Save |
| 8 | pos.js:41 | Unit conversion saved | এককের হিসাব সংরক্ষিত | Unit conversion saved | wrong rule: common word translated into Bangla in bn mode + mix is an English copy | ইউনিট কনভার্সন সেভ হয়েছে | Unit conversion save হয়েছে |
| 9 | invoiceview.js:32 | Total | সর্বমোট | Total | wrong rule: common word translated into Bangla in bn mode (সর্বমোট; elsewhere মোট) | টোটাল | Total |
| 10 | invoiceview.js:32 | Subtotal | মোট (ছাড়ের আগে) | Subtotal | wrong rule: common word translated into Bangla in bn mode (মোট (ছাড়ের আগে) clashes with Total) | সাবটোটাল (ছাড়ের আগে) | Subtotal (ছাড়ের আগে) |
| 11 | invoiceview.js:31 | Cashier | বিক্রেতা | Cashier | wrong term: Cashier rendered বিক্রেতা (= seller) | ক্যাশিয়ার | Cashier |
| 12 | invoiceview.js:33 | Change | ফেরত | Change | ambiguous: ফেরত also means Return/Refund on the same screen | খুচরা ফেরত | Change ফেরত |
| 13 | invoiceview.js:31 | Customer | গ্রাহক | Customer | wrong rule: common word translated into Bangla in bn mode (গ্রাহক) | কাস্টমার | Customer |
| 14 | invoiceview.js:35 | SMS | এসএমএস | SMS | inconsistent term: এসএমএস here, "SMS" in line 312 and purchaseprint.js | SMS | SMS |
| 15 | invoiceview.js:35 | WhatsApp | হোয়াটসঅ্যাপ | WhatsApp | inconsistent term: হোয়াটসঅ্যাপ here, "WhatsApp" in line 312/38 | WhatsApp | WhatsApp |
| 16 | invoiceview.js:28 | Pending sync: not on the server yet. It will be sent when the phone is online. This number is provisional; the final nu… | সার্ভারে এখনো যায়নি — নেট এলে নিজে জমা হবে। এই নম্বরটি সাময়িক, চূড়ান্ত নম্বর পরে পাবেন। | সার্ভারে এখনো যায়নি (pending sync) — net এলে নিজে জমা হবে। এই number টি সাময়িক, final number পরে পাবেন। | inconsistent term: sync rendered জমা (= deposit/submit) in bn, "sync" in mix | সার্ভারে এখনো যায়নি — নেট এলে নিজে সিঙ্ক হবে। এই নম্বরটি সাময়িক, সিঙ্কের পরে চূড়ান্ত নম্বর পাবেন। | Server-এ এখনো যায়নি — net এলে নিজে sync হবে। এই number টি সাময়িক, sync-এর পরে final number পাবেন। |
| 17 | badges107.js:19 | Ledger problems | খাতায় পোস্ট সমস্যা | Ledger post সমস্যা | mixed-up grammar (missing "-এর"; reads as noun pile) | খাতায় পোস্টের সমস্যা | Ledger post-এর সমস্যা |
| 18 | badges107.js:20 | Waiting for cost | খরচের অপেক্ষা | Cost-এর অপেক্ষা | wrong rule: Cost translated খরচ | কস্টের অপেক্ষায় | Cost-এর অপেক্ষায় |
| 19 | badges107.js:21 | Pending auto-posts | অটো পোস্ট বাকি | Auto post বাকি | inconsistent term: waiting rendered বাকি (= Due); mix not mixed | অটো পোস্টের অপেক্ষায় | Auto post-এর অপেক্ষায় |
| 20 | badges107.js:23 | Items with unknown cost | অজানা খরচের আইটেম | অজানা cost-এর item | wrong rule: Cost translated খরচ; word order unnatural | কস্ট জানা নেই এমন আইটেম | Cost জানা নেই এমন item |
| 21 | badges107.js:22 | Forms with no screen record | স্ক্রিন-রেকর্ডহীন ফর্ম | Screen record ছাড়া form | too literal ("স্ক্রিন-রেকর্ডহীন") | স্ক্রিনে রেকর্ড নেই এমন ফর্ম | Screen-এ record নেই এমন form |
| 22 | badges107.js:24 | Bills without payment | payment ছাড়া bill | Payment ছাড়া bill | inconsistent term: Latin "payment" in bn (everywhere else পেমেন্ট) | পেমেন্ট ছাড়া বিল | Payment ছাড়া bill |
| 23 | ia.js:16 | Sales & POS | বিক্রি ও POS | Sale ও POS | wrong rule: common word translated into Bangla in bn mode (বিক্রি) | সেল ও POS | Sale ও POS |
| 24 | ia.js:14 | Purchasing & Suppliers | ক্রয় ও সরবরাহকারী | Purchase ও Supplier | wrong rule: common word translated into Bangla in bn mode (সরবরাহকারী) | ক্রয় ও সাপ্লায়ার | Purchase ও Supplier |
| 25 | ia.js:17 | Customers, Orders & Invoices | গ্রাহক, অর্ডার ও ইনভয়েস | Customer, Order ও Invoice | wrong rule: common word translated into Bangla in bn mode (গ্রাহক) | কাস্টমার, অর্ডার ও ইনভয়েস | Customer, Order ও Invoice |
| 26 | switchboard.js:15 | Blind count | অন্ধ গণনা | Blind count | too literal ("অন্ধ গণনা") | ব্লাইন্ড কাউন্ট | Blind count |
| 27 | switchboard.js:29 | Look & feel | চেহারা / ব্যবহার | Look & feel | too literal/wrong: "ব্যবহার" = usage, not feel | দেখতে কেমন (থিম/রং) | Look & feel |
| 28 | switchboard.js:29 | Accounting | হিসাবরক্ষণ | Accounting | too literal/bookish (হিসাবরক্ষণ); ia.js uses "হিসাব ও অর্থ" for the same section | অ্যাকাউন্টিং | Accounting |
| 29 | switchboard.js:29 | Locations | জায়গা | Locations | inconsistent term across screens (জায়গা here, লোকেশন in ia.js/nav.js) | লোকেশন | Locations |
| 30 | pos.js:61 | This item is not for sale or has no selling price (Data needed) | এই আইটেম বিক্রির জন্য নয় বা দাম দেওয়া নেই (Data needed) | এই Item বিক্রির জন্য নয় বা দাম নেই (Data needed) | inconsistent term: Latin "(Data needed)" inside bn; other screens say (তথ্য লাগবে) | এই আইটেম সেলের জন্য নয় বা প্রাইস দেওয়া নেই (তথ্য লাগবে) | এই item sale-এর জন্য নয় বা price নেই (Data লাগবে) |

Other hand-reviewed items on those screens (verdict + suggestion are in the CSV and in section 4): switchboard "Customers & tiers", "Search by name or key", "People, attendance & payroll"; ia.js "Staff, Roles & Permissions", "Approvals & Exceptions", "Administration & Settings". Tone note: the setup advisor is otherwise written in good plain Bangla ("এটা শুধু পরামর্শ — কোনো কাজ আটকায় না"); only the button/status words above are off.

## 2. Mechanical substitution table (apply with find-and-replace, then eyeball)

Counts are unique triples. "native" = Bangla word used where the owner wants the English word.

| kind | term | unique strings | replace with (bn) | replace with (mix) |
|---|---|---|---|---|
| bn: native word instead of English word | Cost (found: খরচ 86, খরচের 22, খরচে 6) | 114 | কস্ট | - |
| mix/bn: detached Bangla suffix | Latin + space + suffix (এর, এ, কে, তে) | 101 | add hyphen: "X-এর" | add hyphen |
| bn: native word instead of English word | Approve (found: অনুমোদন 59, অনুমোদিত 22, অনুমোদনের 14, অনুমোদনে 2) | 97 | অ্যাপ্রুভ | - |
| bn: native word instead of English word | Sale (found: বিক্রি 53, বিক্রির 24, বিক্রিটা 1, বিক্রয় 1) | 79 | সেল | - |
| bn: native word instead of English word | Date (found: তারিখ 52, তারিখের 14, তারিখে 4) | 70 | ডেট | - |
| bn: native word instead of English word | Void (found: বাতিল 51, বাতিলের 4, বাতিলে 2) | 57 | ভয়েড | - |
| bn: native word instead of English word | Customer (found: গ্রাহক 27, গ্রাহকের 23, ক্রেতার 1, গ্রাহককে 1) | 52 | কাস্টমার | - |
| bn: Latin script word | stock | 47 | স্টক | keep Latin |
| bn: Latin script word | bill | 39 | বিল | keep Latin |
| bn: native word instead of English word | Price (found: দাম 27, দামের 7, দামে 3) | 37 | প্রাইস | - |
| bn: Latin script word | cost | 29 | কস্ট | keep Latin |
| bn: native word instead of English word | Draft (found: খসড়া 28) | 28 | ড্রাফট | - |
| bn: Latin script word | category | 27 | ক্যাটাগরি | keep Latin |
| bn: native word instead of English word | Total (found: মোট 22) | 22 | টোটাল | - |
| bn: Latin script word | payment | 21 | পেমেন্ট | keep Latin |
| bn: native word instead of English word | Save (found: সংরক্ষণ 13, সংরক্ষিত 6) | 19 | সেভ | - |
| bn: native word instead of English word | Supplier (found: সরবরাহকারীর 8, সরবরাহকারী 8, সরবরাহকারীকে 2) | 18 | সাপ্লায়ার | - |
| bn: native word instead of English word | Apply (found: প্রয়োগ 16, প্রয়োগের 1) | 17 | অ্যাপ্লাই | - |
| mix: Bangla word instead of Latin | Cost (found: খরচ 14, খরচের 1) | 15 | - | cost |
| bn: native word instead of English word | Qty (found: পরিমাণ 15) | 15 | Qty | - |
| bn: Latin script word | sale | 15 | সেল | keep Latin |
| mix: Bangla word instead of Latin | Price (found: দাম 11, দামের 2, দামে 1) | 14 | - | price |
| bn: Latin script word | item | 14 | আইটেম | keep Latin |
| bn: Latin script word | sub-category | 13 | সাব-ক্যাটাগরি | keep Latin |
| bn: native word instead of English word | Item (found: পণ্য 8, পণ্যের 3, পণ্যে 1) | 12 | আইটেম | - |
| mix: Bangla word instead of Latin | Date (found: তারিখ 6, তারিখের 3, তারিখে 1) | 10 | - | date |
| bn: Latin script word | inbox | 10 | ইনবক্স | keep Latin |
| bn: Latin script word | scan | 9 | স্ক্যান | keep Latin |
| bn: Latin script word | phone | 9 | ফোন | keep Latin |
| bn: native word instead of English word | Print (found: ছাপা 5, ছাপার 3) | 8 | প্রিন্ট | - |
| bn: Latin script word | cash | 8 | ক্যাশ | keep Latin |
| bn: Latin script word | message | 8 | মেসেজ | keep Latin |
| mix: Bangla word instead of Latin | Sale (found: বিক্রির 6, বিক্রি 1) | 7 | - | sale |
| mix: Bangla word instead of Latin | Void (found: বাতিল 7) | 7 | - | void |
| bn: Latin script word | address | 7 | ঠিকানা | keep Latin |
| bn: native word instead of English word | Cash (found: নগদ 6) | 6 | ক্যাশ | - |
| bn: native word instead of English word | Stock (found: মজুত 4, মজুতের 2) | 6 | স্টক | - |
| bn: Latin script word | opening | 6 | ওপেনিং | keep Latin |
| mix: Bangla word instead of Latin | Approve (found: অনুমোদন 3, অনুমোদিত 2, অনুমোদনের 1) | 6 | - | approve |
| bn: native word instead of English word | Cancel (found: বাতিল 6) | 6 | ক্যান্সেল | - |
| bn: Latin script word | order | 6 | অর্ডার | keep Latin |
| bn: Latin script word | supplier | 6 | সাপ্লায়ার | keep Latin |
| bn: Latin script word | mode | 6 | মোড | keep Latin |
| bn: Latin script word | confirm | 6 | কনফার্ম | keep Latin |
| mix: Bangla word instead of Latin | Stock (found: মজুত 3, মজুতের 2) | 5 | - | stock |
| bn: Latin script word | data | 5 | ডেটা | keep Latin |
| mix: Bangla word instead of Latin | Total (found: মোট 4) | 4 | - | total |
| bn: Latin script word | bank | 4 | ব্যাংক | keep Latin |
| bn: Latin script word | save | 3 | সেভ | keep Latin |
| bn: Latin script word | print | 3 | প্রিন্ট | keep Latin |

Caveats for the swap: খরচ -> কস্ট only where the English says *cost* (not expense/charge/fee); বাতিল -> ভয়েড/ক্যান্সেল by the English word; নগদ stays when it means the Nagad wallet; বিক্রি stays when it is a verb (sold/sell); অনুমোদন -> অ্যাপ্রুভ (verb) / অ্যাপ্রুভাল (noun) / অ্যাপ্রুভড (adj). Always re-read bn sentences after a swap; Bangla suffixes were adjusted automatically (কস্টের, ডেটে, কাস্টমারের).

## 3. Term consistency (71 terms, bn / mix rendering actually used, by file)

Counts are unique triples whose **English** text contains the term (web + SQL seed rows). "files" lists the top files for that rendering. ⚠ = more than one rendering with 2+ uses, or the dominant rendering is not the recommended one. Where the English side itself uses two words for one thing (place/location, waiting/pending), the Bangla cannot be consistent until the English is.

| term | recommended bn / mix | bn renderings in use (count; top files) | mix renderings in use (count; top files) | ⚠ | note |
|---|---|---|---|---|---|
| on / off (n=269) | চালু / বন্ধ / ON / OFF | চালু/বন্ধ 160 (books85 11, twofa 10, accounts 8, customers 8) | চালু/বন্ধ 96 (twofa 10, customers 8, books85 7, catpick 6); ON/OFF 65 (books85 5, accounts 4, books96 4, phase82 4) | ⚠ | mix: ON/OFF capital as in old text |
| cost (n=183) | কস্ট / cost | খরচ 122 (books96 18, costboard 16, costattrib 11, costing 10); দাম 33 (landed 12, finance2 3, itemmaster 3, recipes 3); cost 29 (landed 15, phase97 6, landed_q4 2, optionsx 2); ক্রয়মূল্য 6 (bulkitems 3, reports 2, assistant 1) | cost 154 (landed 26, books96 20, costboard 15, costing 9); খরচ 18 (accounts 4, costattrib 4, optionsx 4, assistant 1); দাম 3 (landed 1, salesx 1, phase74 1) | ⚠ owner-rule | never দাম (=Price) |
| item (n=147) | আইটেম / item | আইটেম 102 (bulkitems 26, itemmaster 18, scan 6, assistant 5); item 15 (catpick 14, costboard 1); মাল 14 (landed 7, bulkitems 1, costboard 1, itemmaster 1); পণ্য 12 (inbox 4, salereturn 2, guards 1, purchase 1) | item 134 (bulkitems 24, itemmaster 18, catpick 14, landed 10); পণ্য 1 (inbox 1); মাল 1 (phase97 1) |  owner-rule | not পণ্য/মাল/জিনিস |
| stock (n=144) | স্টক / stock | স্টক 84 (books96 12, books85 11, bulkitems 8, itemmaster 6); stock 44 (books96 12, packflags 7, phase85 5, accounts 4); মাল 18 (books85 3, guards 2, phase87 2, accounts 1); মজুদ/মজুত 6 (accounts 5, locations 1) | stock 125 (books96 20, books85 15, bulkitems 7, packflags 7); মাল 8 (phase87 2, accounts 1, guards 1, pos 1); মজুদ/মজুত 5 (accounts 5) | ⚠ owner-rule | not মজুদ/মাল when it means Stock |
| owner (n=125) | মালিক / owner | মালিক 123 (assistant 9, daybook 6, finance2 6, itemmaster 6); owner 1 (phase85 1) | owner 107 (daybook 6, itemmaster 6, assistant 5, books96 5); মালিক 7 (costattrib 4, s1setup 2, customers 1) |  | consistent |
| bill (n=115) | বিল / bill | বিল 74 (landed 19, costsources 11, scan 9, landed_q4 7); bill 38 (optionsx 23, phase99 5, guards 4, phase82 3); ক্রয় বিল 13 (scan 4, landed 2, landed_q4 2, daybook 1) | bill 106 (optionsx 23, landed 19, costsources 10, scan 9); বিল 2 (costsources 1, guards 1) | ⚠ | purchase bill = ক্রয় বিল / Purchase bill |
| location / place (n=114) | লোকেশন (Location) / জায়গা (Place) / location / place | জায়গা 72 (locations 7, books96 6, costsources 6, accounts 5); লোকেশন 24 (rollout 7, control 3, nav 3, forms_stock 2); কর্মস্থল 5 (employees 5) | place 44 (locations 7, books96 6, accounts 5, costsources 5); location 36 (rollout 7, attend2 6, control 3, daybook 3); জায়গা 22 (attend2 3, costattrib 3, optionsx 3, attendance 2); কর্মস্থল 5 (employees 5) | ⚠ | same word per English word on every screen |
| sale (n=106) | সেল / sale | বিক্রি 89 (cashdrawer 10, costboard 7, itemmaster 7, assistant 6); sale 16 (cashdrawer 8, posfail 3, phase83 2, phase95 2); বিক্রয় 1 (i18n 1) | sale 93 (cashdrawer 18, costboard 7, salesx 6, assistant 5); বিক্রি 9 (itemmaster 4, bulkitems 2, pos 2, accounts 1) | ⚠ owner-rule | বিক্রি only as a verb (sold / sell) |
| approve (n=97) | অ্যাপ্রুভ (noun: অ্যাপ্রুভাল) / approve / approval | অনুমোদন 91 (rollout 9, payroll 7, costattrib 6, attendance 5); যাচাই 2 (entry 1, packflags 1); approve 2 (phase81 1, phase94 1) | approve 81 (rollout 9, entry 6, payroll 6, attendance 5); অনুমোদন 6 (costattrib 4, assistant 1, assistant_tools 1) |  owner-rule | owner list word; অনুমোদন only in old text |
| payment / pay (n=93) | পেমেন্ট / payment | payment 22 (optionsx 17, phase99 4, badges107 1); পেমেন্ট 10 (integrations 3, forms_stock 2, inbox 2, assistant_tools 1); পরিশোধ 4 (costsources 1, forms_stock 1, payroll 1, i18n 1); টাকা দেওয়া 1 (optionsx 1) | payment 47 (optionsx 17, payroll 7, phase99 4, integrations 3); টাকা দেওয়া 1 (optionsx 1) | ⚠ | not Latin in bn; পরিশোধ only for "pay off" |
| switch (on/off) (n=90) | সুইচ / switch | সুইচ 38 (books96 7, books85 4, attend2 3, assistant 2); switch 3 (finance2 1, optionsx 1, scan 1) | switch 38 (books96 7, books85 4, assistant 2, attend2 2); সুইচ 1 (customers 1) |  | consistent |
| post (to ledger) (n=86) | পোস্ট / post | পোস্ট 51 (accounts 12, landed 10, optionsx 5, books96 4); তোলা 10 (phase85 5, books96 4, phase103 1); এন্ট্রি 8 (accounts 5, finance2 1, optionsx 1, phase99 1); post (Latin) 3 (books96 1, guards 1, phase85 1) | post (Latin) 64 (accounts 12, landed 10, books96 8, phase85 6); তোলা 1 (books96 1); পোস্ট 1 (forms_stock 1) | ⚠ | not তোলা/এন্ট্রি for post |
| ledger / books (n=80) | খাতা = books, খতিয়ান = ledger, জার্নাল = journal / books / ledger / journal | খাতা 26 (books96 6, books85 5, costboard 5, finance2 4); খতিয়ান 10 (accounts 9, finance2 1); জার্নাল 10 (accounts 5, finance2 1, integrations 1, paths 1) | books 26 (finance2 6, books85 5, books96 5, costboard 4); ledger 14 (accounts 4, forms_stock 4, badges107 1, costboard 1); খতিয়ান 5 (accounts 5); খাতা 3 (accounts 1, books96 1, finance2 1); জার্নাল 1 (accounts 1) | ⚠ | keep the 3-way split |
| date (n=77) | ডেট / date | তারিখ 70 (accounts 13, daybook 8, finance2 8, books85 4) | date 58 (accounts 9, daybook 8, finance2 8, books85 4); তারিখ 10 (accounts 2, employees 2, restoredrill 2, attendance 1) | ⚠ owner-rule | not তারিখ |
| customer (n=62) | কাস্টমার / customer | গ্রাহক 54 (customers 15, assistant_tools 6, accounts 5, inbox 5); ক্রেতা 1 (lists 1); কাস্টমার 1 (i18n 1) | customer 55 (customers 13, assistant_tools 6, accounts 5, inbox 5) |  owner-rule | not গ্রাহক |
| permission / right (n=59) | অনুমতি / permission | অনুমতি 43 (daybook 3, optviews 3, accounts 2, assistant 2); অধিকার 9 (costattrib 2, delegation 2, catpick 1, costboard 1); right 1 (books96 1) | permission 24 (daybook 3, optviews 3, employees 2, posfail 2); অনুমতি 13 (accounts 2, s1setup 2, assistant 1, bulkitems 1); right 12 (delegation 3, costattrib 2, attend2 1, books96 1); অধিকার 4 (catpick 1, costboard 1, delegation 1, packflags 1) | ⚠ | one word for both; not অধিকার / right |
| supplier (n=58) | সাপ্লায়ার / supplier | সাপ্লায়ার 30 (scan 8, landed 5, purchase 5, forms_stock 4); সরবরাহকারী 20 (accounts 5, assistant 3, assistant_tools 3, ownerboard 2); supplier 6 (optionsx 5, phase82 1) | supplier 56 (scan 8, accounts 5, landed 5, optionsx 5) | ⚠ owner-rule | not সরবরাহকারী |
| void (n=57) | ভয়েড / void | বাতিল 57 (books85 5, optionsx 5, recipes 5, salereturn 4); void 2 (landed 1, phase97 1); উল্টানো 1 (i18n 1) | void 50 (books85 5, recipes 5, salereturn 4, stock2 4); বাতিল 7 (optionsx 5, payroll 2) |  owner-rule | বাতিল is shared by Void/Cancel/Reject - split them |
| save (n=55) | সেভ / save | সংরক্ষণ 20 (employees 3, accounts 2, landed 2, locations 2); সেভ 18 (entry 10, optionsx 3, cashdrawer 1, catpick 1); save 3 (cashdrawer 1, invoiceview 1, purchaseprint 1) | save 47 (entry 11, employees 3, optionsx 3, accounts 2) | ⚠ owner-rule | not সংরক্ষণ |
| waiting (n=52) | অপেক্ষায় / অপেক্ষায় | অপেক্ষায় 26 (assistant 4, books85 4, books96 3, assistant_tools 2); বাকি 10 (attend2 1, books85 1, control 1, itemmaster 1); অপেক্ষা 3 (books96 2, badges107 1); আটকে আছে 3 (books85 1, posfail 1, rollout 1) | অপেক্ষায় 20 (assistant 4, books96 3, assistant_tools 2, nav 2); বাকি 10 (payroll 2, attend2 1, books85 1, control 1); waiting 4 (books85 3, ownerboard 1); অপেক্ষা 3 (books96 2, badges107 1); আটকে আছে 2 (posfail 1, rollout 1) | ⚠ | never বাকি (বাকি = Due) |
| entry (n=52) | এন্ট্রি / entry | এন্ট্রি 44 (accounts 11, rollout 11, entry 10, costattrib 2); তোলা 2 (entry 1, rollout 1); entry 2 (phase81 1, phase85 1) | entry 46 (rollout 11, accounts 10, entry 10, locations 2); তোলা 2 (entry 1, rollout 1) |  | consistent |
| request (n=50) | অনুরোধ / request | অনুরোধ 46 (entry 8, rollout 7, control 4, lists 4); আবেদন 4 (attendance 4) | request 47 (entry 8, rollout 7, control 4, lists 4) |  | not আবেদন |
| cash (n=49) | ক্যাশ / cash | ক্যাশ 34 (cashdrawer 5, phase95 5, cashmoves 4, daybook 4); cash 8 (optionsx 7, phase99 1); নগদ 7 (assistant 2, daybook 2, accounts 1, assistant_tools 1) | cash 45 (optionsx 7, cashdrawer 5, daybook 5, phase95 5) | ⚠ owner-rule | নগদ only for the Nagad wallet |
| rule (n=47) | নিয়ম / rule | নিয়ম 44 (assistant 6, costsources 4, formscreens 4, lists 4); rule 2 (finance2 2) | rule 28 (costsources 4, formscreens 4, control 3, catpick 2); নিয়ম 13 (assistant 4, customers 3, lists 3, assistant_tools 1) | ⚠ | mostly consistent; minor outliers |
| recipe (n=46) | রেসিপি / recipe | রেসিপি 43 (recipes 16, recipebook 6, costattrib 5, phase73 5); recipe (Latin) 3 (itemimg 1, phase81 1, phase103 1) | recipe (Latin) 44 (recipes 16, recipebook 6, phase81 6, phase73 5); রেসিপি 1 (recipes 1) |  | consistent |
| purchase (n=45) | ক্রয় / purchase | ক্রয় 27 (scan 4, forms_stock 3, accounts 2, landed 2); কেনা 12 (customers 3, accounts 2, books96 2, finance2 2); purchase 4 (itemimg 1, optionsx 1, phase85 1, phase99 1) | purchase 37 (scan 4, forms_stock 3, accounts 2, books96 2); কেনা 8 (customers 3, accounts 2, costing 1, finance2 1) | ⚠ | কেনা only in verbs/sentences |
| category (n=44) | ক্যাটাগরি / category | category 30 (catpick 29, phase100 1); ক্যাটাগরি 12 (itemmaster 6, bulkitems 4, assistant_tools 1, items2 1); বিভাগ 2 (nav 2) | category 44 (catpick 29, itemmaster 6, bulkitems 4, nav 2) | ⚠ owner-rule | not Latin, not বিভাগ |
| staff / employee (n=42) | স্টাফ (login users) / কর্মচারী (HR record) / staff / employee | স্টাফ 14 (control 3, accounts 2, assistant_tools 2, assistant 1); কর্মচারী 9 (employees 6, attendance 3); কর্মী 7 (attend2 3, salesx 2, reports 1, switchboard 1) | staff 16 (control 3, accounts 2, assistant_tools 2, assistant 1); employee 12 (employees 6, attend2 2, attendance 2, salesx 2) | ⚠ | drop কর্মী |
| due (credit owed) (n=41) | বাকি = Due, পাওনা = Receivable, দেনা = Payable / due / receivable / payable | বাকি 14 (customers 4, salereturn 2, accounts 1, assistant_tools 1); পাওনা 7 (customers 2, payroll 2, assistant_tools 1, pos 1); দেনা 1 (landed 1) | due 11 (customers 4, salereturn 2, daybook 1, forms_stock 1); বাকি 4 (accounts 1, assistant_tools 1, invoiceview 1, optionsx 1); পাওনা 4 (customers 2, payroll 1, pos 1) | ⚠ | বাকি must not also mean Waiting or Left |
| opening (stock/balance) (n=39) | শুরুর (শুরুর স্টক, শুরুর জের) / opening | শুরুর 36 (books96 17, accounts 10, books85 3, daybook 2); জের 21 (accounts 9, books96 8, daybook 2, books85 1); opening 5 (phase81 2, accounts 1, books85 1, phase85 1) | opening 36 (books96 17, accounts 9, books85 3, phase81 2); জের 4 (accounts 3, daybook 1); শুরুর 2 (accounts 2) | ⚠ | mostly consistent; minor outliers |
| setting(s) (n=37) | সেটিংস / settings | সেটিংস/সেটিং 35 (locations 6, control 5, cashdrawer 3, nav 3); নিয়ম 1 (nav 1) | setting 37 (locations 7, control 5, cashdrawer 3, nav 3) |  | consistent |
| price (n=36) | প্রাইস / price | দাম 36 (bulkitems 7, itemmaster 5, landed 3, accounts 2) | price 23 (bulkitems 6, assistant 2, control 2, itemmaster 2); দাম 14 (itemmaster 3, items2 2, packflags 2, accounts 1) | ⚠ owner-rule | দাম is a different word from Cost |
| void/lock/locked (n=36) | লক / lock / locked | লক 18 (attend2 6, entry 5, itemmaster 3, bulkitems 2); তালাবদ্ধ 11 (optviews 4, customers 2, lists 2, entry 1); locked 1 (stepw_common 1) | locked 35 (attend2 7, entry 6, optviews 5, itemmaster 3) | ⚠ | not তালাবদ্ধ |
| expense (n=35) | খরচ / expense | খরচ 34 (formscreens 5, accounts 4, assistant 4, finance2 4); ব্যয় 1 (accounts 1) | expense 23 (formscreens 5, accounts 4, optionsx 3, books85 2); খরচ 10 (assistant 4, assistant_tools 3, accounts 1, flow 1) | ⚠ | খরচ = Expense only |
| production (n=35) | প্রোডাকশন / production | উৎপাদন 32 (recipes 11, costboard 4, costattrib 3, accounts 2); production 2 (phase81 1, phase103 1) | production 29 (recipes 9, costboard 4, phase81 2, accounts 1); উৎপাদন 2 (accounts 1, costattrib 1) |  | উৎপাদন is bookish but consistent; owner decision |
| balance (n=35) | ব্যালান্স / balance | জের 16 (accounts 9, daybook 4, books85 1, books96 1); মিল 10 (accounts 5, ownerboard 3, assistant_tools 1, books85 1); ব্যালান্স 9 (accounts 4, assistant 3, assistant_tools 1, phase81 1) | balance 22 (accounts 7, assistant 4, ownerboard 3, assistant_tools 2); জের 6 (accounts 3, daybook 3); মিল 5 (accounts 3, books85 1, ownerboard 1) | ⚠ | জের only in "শুরুর জের" |
| assets/liabilities/equity (n=34) | সম্পদ / দায় / মালিকের পুঁজি / Asset / Liability / Equity | সম্পদ/দায়/মালিকানা 30 (accounts 10, itemmaster 8, finance2 6, purchase 2); Asset/Liability/Equity 3 (books96 3) | Asset/Liability/Equity 30 (accounts 9, itemmaster 8, finance2 6, books96 3) |  | owner decision; the Bangla trio is accountants' language |
| cost unknown (n=32) | কস্ট অজানা (বাক্যে: "কস্ট জানা নেই") / cost অজানা | খরচ অজানা 12 (costboard 3, s1setup 2, phase81 2, accounts 1); খরচ জানা নেই 6 (books96 2, accounts 1, assistant 1, costboard 1); খরচহীন 1 (costboard 1); খরচ নেই 1 (costboard 1) | cost অজানা 13 (costboard 3, recipes 2, s1setup 2, phase81 2); খরচ অজানা 4 (accounts 1, badges107 1, catpick 1, costboard 1); খরচহীন 1 (costboard 1) | ⚠ owner-rule | one phrase everywhere; খরচ = Expense, not Cost |
| return (sale) (n=32) | ফেরত / return | ফেরত 30 (salereturn 13, books85 3, stock2 3, accounts 2); return 2 (guards 1, phase85 1) | return 31 (salereturn 13, books85 3, stock2 3, forms_stock 2); ফেরত 1 (accounts 1) |  | goods coming back |
| attendance (n=30) | হাজিরা / attendance | হাজিরা 17 (attend2 5, attendance 3, payroll 3, assistant_tools 1); পাঞ্চ 12 (attend2 8, attendance 4); attendance 1 (attend2 1) | attendance 9 (attend2 5, attendance 2, ownerboard 1, payroll 1); হাজিরা 5 (assistant_tools 1, flow 1, payroll 1, reports 1) | ⚠ | mostly consistent; minor outliers |
| apply (n=29) | অ্যাপ্লাই / apply | প্রয়োগ 20 (setupadvisor 7, customers 4, bulkitems 3, books96 2) | apply 21 (setupadvisor 7, customers 4, bulkitems 3, books96 2) |  owner-rule | not প্রয়োগ |
| ingredient (n=29) | উপকরণ / ingredient | উপকরণ 18 (recipes 12, costboard 1, costing 1, formscreens 1); কাঁচামাল 8 (recipes 4, accounts 1, costing 1, guards 1); ingredient 1 (books96 1) | ingredient 24 (recipes 13, phase81 2, books96 1, costboard 1); কাঁচামাল 1 (accounts 1); উপকরণ 1 (phase72 1) | ⚠ | কাঁচামাল = raw material only |
| draft (n=28) | ড্রাফট / draft | খসড়া 28 (locations 8, employees 5, landed 2, phase90 2) | draft 25 (locations 8, employees 4, landed 2, phase90 2); খসড়া 2 (inbox 1, phase76 1) |  owner-rule | not খসড়া |
| total (n=28) | টোটাল / total | মোট 23 (accounts 5, finance2 3, assistant 2, ownerboard 2); সর্বমোট 1 (invoiceview 1) | total 21 (accounts 5, finance2 3, ownerboard 2, scan 2); মোট 4 (assistant 1, customers 1, optionsx 1, recipes 1) | ⚠ owner-rule | not মোট/সর্বমোট |
| print (n=28) | প্রিন্ট / print | প্রিন্ট 17 (cashdrawer 5, invoiceview 4, purchaseprint 4, employees 2); ছাপা 9 (printbooks 5, control 2, recipebook 1, tplpicker 1); print 3 (cashdrawer 1, invoiceview 1, purchaseprint 1) | print 28 (cashdrawer 5, invoiceview 5, printbooks 5, purchaseprint 5); ছাপা 1 (printbooks 1) | ⚠ owner-rule | not ছাপা |
| salary / payroll (n=28) | বেতন (salary) / পে-রোল (payroll run) / salary / payroll | বেতন 21 (salary 6, payroll 3, daybook 2, salesx 2) | payroll 15 (payroll 9, salesx 2, attend2 1, attendance 1); salary 11 (salary 6, daybook 2, flow 1, nav 1); বেতন 1 (assistant_tools 1) | ⚠ | mix: both words appear for the same screen |
| landed cost (n=24) | Landed cost (প্রথমবার: + "মালের সাথে আসা খরচ") / landed cost | Landed cost (Latin) 23 (landed 15, phase97 6, landed_q4 2); মালের সাথে আসা খরচ 2 (landed 1, phase97 1) | Landed cost (Latin) 23 (landed 15, phase97 6, landed_q4 2); মালের সাথে আসা খরচ 2 (landed 1, phase97 1) |  | keep Latin technical term; always lower-case "cost" part same |
| bank (n=23) | ব্যাংক / bank | ব্যাংক 19 (daybook 4, finance2 4, books85 3, cashmoves 3); bank 4 (optionsx 4) | bank 21 (daybook 4, optionsx 4, books85 3, cashmoves 3) | ⚠ | mostly consistent; minor outliers |
| batch (n=23) | ব্যাচ / batch | ব্যাচ 21 (stockx 8, recipes 5, costing 3, assistant 2); batch 1 (guards 1) | batch 23 (stockx 8, recipes 6, costing 3, assistant 2) |  | consistent |
| default (n=22) | ডিফল্ট / default | ডিফল্ট 19 (tplpicker 4, customers 3, optviews 3, itemmaster 2); শুরুর মান 2 (setupadvisor 1, setupundo 1) | default 20 (tplpicker 4, customers 3, optviews 3, itemmaster 2) |  | not "শুরুর মান" |
| wastage (n=22) | নষ্ট (বাক্যে) / ওয়েস্টেজ (লেবেলে) / wastage | নষ্ট 12 (stock2 3, accounts 1, books96 1, control 1); অপচয় 11 (recipes 5, assistant 1, assistant_tools 1, forms_stock 1); wastage 1 (books96 1) | wastage 18 (recipes 5, stock2 3, accounts 1, books96 1); অপচয় 3 (assistant 1, assistant_tools 1, reports 1); নষ্ট 1 (stockx 1) | ⚠ | pick one: ওয়েস্টেজ for the label |
| GRN / goods received (n=19) | GRN (প্রথমবার: GRN — মাল গ্রহণ) / GRN | GRN 17 (landed_q4 5, guards 4, stockx 3, forms_stock 1); মাল গ্রহণ 4 (flow 1, forms_stock 1, stockx 1, i18n 1); মাল রিসিভ 1 (guards 1) | GRN 18 (landed_q4 5, guards 4, stockx 3, forms_stock 1); মাল গ্রহণ 2 (flow 1, i18n 1); মাল রিসিভ 2 (guards 1, stockx 1) | ⚠ | Latin acronym in all modes |
| report (n=19) | রিপোর্ট / report | রিপোর্ট 19 (assistant 2, ownerboard 2, salesx 2, cashdrawer 1); হিসাব 2 (assistant 1, salesx 1) | report 18 (ownerboard 2, salesx 2, assistant 1, cashdrawer 1); হিসাব 1 (salesx 1) |  owner-rule | not প্রতিবেদন |
| refund (n=17) | রিফান্ড / refund | ফেরত 13 (daybook 4, purchase 3, accounts 1, cashmoves 1); রিফান্ড 4 (purchase 3, stock2 1) | refund 14 (purchase 6, daybook 3, accounts 1, integrations 1); ফেরত 3 (cashmoves 1, daybook 1, finance2 1) | ⚠ | money going back; ফেরত is too overloaded |
| discount (n=17) | ডিসকাউন্ট / discount | ডিসকাউন্ট 9 (customers 3, reports 3, ownerboard 2, invoiceview 1); ছাড় 8 (assistant_tools 2, customers 2, assistant 1, landed 1) | discount 12 (customers 3, reports 3, ownerboard 2, invoiceview 1); ছাড় 5 (assistant_tools 2, customers 2, assistant 1) | ⚠ | not ছাড় (ছাড় = release/exempt) |
| share (n=16) | শেয়ার / share | শেয়ার 4 (invoiceview 3, purchaseprint 1); share 2 (invoiceview 1, purchaseprint 1); ভাগ 2 (landed 2) | share 10 (invoiceview 4, landed 2, purchaseprint 2, catpick 1) | ⚠ owner-rule | ভাগ = Allocate/Split |
| artisan (n=16) | কারিগর / artisan | কারিগর 16 (recipebook 13, phase73 3) | artisan 12 (recipebook 9, phase73 3); কারিগর 3 (recipebook 3) | ⚠ | mostly consistent; minor outliers |
| invoice (n=15) | ইনভয়েস / invoice | ইনভয়েস 13 (invoiceview 9, ia 1, settings2 1, phase92 1); বিল 2 (landed 2) | invoice 15 (invoiceview 9, landed 2, ia 1, settings2 1) | ⚠ owner-rule | mostly consistent; minor outliers |
| qty / quantity (n=15) | Qty / qty | পরিমাণ 15 (landed 3, salereturn 3, inbox 2, books96 1) | কিউটি/qty 8 (landed 3, inbox 2, books96 1, ownerboard 1); quantity 6 (salereturn 3, forms_stock 1, recipes 1, stockx 1); পরিমাণ 1 (entry 1) | ⚠ owner-rule | Latin abbreviation in all modes (কিউটি is unnatural) |
| switchboard (n=15) | সুইচবোর্ড / Switchboard | সুইচবোর্ড 13 (assistant 2, attend2 1, attendance 1, employees 1); Switchboard 1 (scan 1) | Switchboard 11 (assistant 2, attendance 1, employees 1, inbox 1) |  | consistent |
| done / complete (n=13) | Done / done | সম্পন্ন 1 (locations 1) | done 7 (nav 2, assistant 1, bulkitems 1, finance2 1) |  owner-rule | Latin in bn too ("ডান" reads as "right") |
| card (n=13) | কার্ড / card | কার্ড 13 (books85 6, accounts 1, cashdrawer 1, daybook 1) | card 13 (books85 6, accounts 1, cashdrawer 1, daybook 1) |  | consistent |
| pending (n=12) | অপেক্ষায় / Pending | অপেক্ষায় 6 (accounts 1, assistant 1, attendance 1, lists 1); বাকি 4 (badges107 1, costsources 1, nav 1, rollout 1); জমা 2 (invoiceview 1, rollout 1) | pending 8 (assistant 1, attendance 1, flow 1, invoiceview 1); অপেক্ষায় 2 (accounts 1, ownerboard 1); বাকি 2 (badges107 1, costsources 1); জমা 1 (invoiceview 1) | ⚠ | বাকি/জমা are taken by Due/Deposit |
| backup/restore (n=12) | ব্যাকআপ / রিস্টোর / backup / restore | ব্যাকআপ 8 (ownerboard 2, restoredrill 2, assistant_tools 1, control 1); রিস্টোর 1 (restoredrill 1) | backup 8 (ownerboard 2, restoredrill 2, assistant_tools 1, control 1); restore 2 (restoredrill 1, phase80 1) | ⚠ | not পুনরুদ্ধার |
| adjustment (n=10) | অ্যাডজাস্টমেন্ট / adjustment | সমন্বয় 7 (payroll 3, accounts 1, forms_stock 1, salesx 1) | adjust 8 (payroll 3, accounts 1, books85 1, forms_stock 1); সমন্বয় 1 (accounts 1) |  | not সমন্বয় |
| cancel (n=8) | ক্যান্সেল / cancel | বাতিল 6 (attendance 2, bulkitems 1, integrations 1, twofa 1) | cancel 6 (attendance 2, books85 1, bulkitems 1, integrations 1); বাতিল 1 (twofa 1) |  owner-rule | not বাতিল |
| unmatched (n=6) | মেলেনি / unmatched | মিলেনি 3 (finance2 1, formscreens 1, integrations 1) | মিলেনি 3 (finance2 1, formscreens 1, integrations 1) |  | pick মেলেনি (not মিলেনি) |
| sync (n=6) | সিঙ্ক / sync | জমা 5 (invoiceview 5) | sync 5 (invoiceview 4, ownerboard 1); জমা 2 (invoiceview 2) | ⚠ | not জমা (জমা = deposit/submitted) |
| shadow copy (n=4) | শ্যাডো কপি / shadow copy | শ্যাডো 4 (paths 3, attend2 1) | shadow 4 (paths 3, attend2 1) |  | consistent |
| reconcile (n=3) | মেলানো / reconcile | মিলানো 2 (accounts 1, flow 1); মেলানো 1 (finance2 1) | মিলানো 2 (accounts 1, flow 1); মেলানো 1 (finance2 1) |  | pick মেলানো (not মিলানো) |
| dashboard (n=2) | ড্যাশবোর্ড / dashboard | ড্যাশবোর্ড 2 (ia 1, twofa 1) | dashboard 2 (ia 1, twofa 1) |  | consistent |

## 4. Per-file review (non-mechanical findings in full)

First a size table (unique triples per file), then each file with its **non-mechanical** findings: meaning/grammar/literal problems, wrong terms, cross-screen inconsistencies and the hand-reviewed priority rows. Rows whose only problem is the mechanical swap of section 2 are counted in the table but listed in the CSV (column `systemic_mechanical_fix = Y`) to keep this page readable.

| file | unique | OK | to fix | of which mechanical |
|---|---|---|---|---|
| accounts.js | 230 | 164 | 66 | 48 |
| optionsx.js | 117 | 54 | 63 | 60 |
| catpick.js | 72 | 29 | 43 | 39 |
| landed.js | 146 | 104 | 42 | 31 |
| assistant.js | 170 | 132 | 38 | 24 |
| books96.js | 101 | 66 | 35 | 32 |
| customers.js | 149 | 118 | 31 | 26 |
| cashdrawer.js | 65 | 41 | 24 | 24 |
| finance2.js | 124 | 100 | 24 | 13 |
| locations.js | 97 | 73 | 24 | 19 |
| phase81.sql | 38 | 14 | 24 | 24 |
| costattrib.js | 72 | 49 | 23 | 9 |
| entry.js | 87 | 65 | 22 | 8 |
| itemmaster.js | 138 | 118 | 20 | 14 |
| books85.js | 102 | 84 | 18 | 15 |
| recipes.js | 88 | 70 | 18 | 13 |
| bulkitems.js | 144 | 127 | 17 | 16 |
| costboard.js | 30 | 13 | 17 | 16 |
| employees.js | 207 | 190 | 17 | 11 |
| invoiceview.js | 41 | 24 | 17 | 8 |
| ownerboard.js | 116 | 99 | 17 | 13 |
| scan.js | 103 | 86 | 17 | 13 |
| assistant_tools.js | 76 | 60 | 16 | 15 |
| costing.js | 57 | 41 | 16 | 11 |
| payroll.js | 98 | 82 | 16 | 9 |
| stockx.js | 49 | 33 | 16 | 12 |
| control.js | 46 | 31 | 15 | 8 |
| inbox.js | 84 | 69 | 15 | 12 |
| lists.js | 59 | 44 | 15 | 11 |
| phase85.sql | 15 | 0 | 15 | 12 |
| attendance.js | 131 | 117 | 14 | 9 |
| daybook.js | 78 | 64 | 14 | 10 |
| stock2.js | 31 | 17 | 14 | 12 |
| packflags.js | 27 | 14 | 13 | 11 |
| reports.js | 31 | 18 | 13 | 8 |
| salereturn.js | 28 | 15 | 13 | 12 |
| salesx.js | 52 | 39 | 13 | 11 |
| setupadvisor.js | 37 | 25 | 12 | 5 |
| costsources.js | 62 | 51 | 11 | 7 |
| guards.js | 14 | 4 | 10 | 8 |
| rollout.js | 69 | 59 | 10 | 8 |
| switchboard.js | 26 | 16 | 10 | 2 |
| attend2.js | 120 | 111 | 9 | 2 |
| nav.js | 66 | 58 | 8 | 6 |
| recipebook.js | 73 | 65 | 8 | 7 |
| listctl.js | 25 | 18 | 7 | 6 |
| purchase.js | 27 | 20 | 7 | 5 |
| phase97.sql | 9 | 2 | 7 | 6 |
| phase99.sql | 8 | 1 | 7 | 7 |
| badges107.js | 8 | 2 | 6 | 0 |
| cashmoves.js | 20 | 14 | 6 | 5 |
| forms_stock.js | 51 | 45 | 6 | 4 |
| ia.js | 13 | 7 | 6 | 0 |
| itemimg.js | 16 | 10 | 6 | 6 |
| s1setup.js | 24 | 18 | 6 | 6 |
| i18n.js | 29 | 23 | 6 | 5 |
| phase82.sql | 6 | 0 | 6 | 5 |
| formscreens.js | 50 | 45 | 5 | 3 |
| integrations.js | 28 | 23 | 5 | 4 |
| optviews.js | 29 | 24 | 5 | 0 |
| phase90.sql | 5 | 0 | 5 | 5 |
| posfail.js | 13 | 9 | 4 | 4 |
| printbooks.js | 26 | 22 | 4 | 4 |
| phase73.sql | 6 | 2 | 4 | 4 |
| phase76.sql | 12 | 8 | 4 | 1 |
| phase78.sql | 4 | 0 | 4 | 4 |
| phase94.sql | 6 | 2 | 4 | 3 |
| phase95.sql | 5 | 1 | 4 | 3 |
| delegation.js | 13 | 10 | 3 | 1 |
| flow.js | 37 | 34 | 3 | 3 |
| items2.js | 16 | 13 | 3 | 3 |
| landed_q4.js | 12 | 9 | 3 | 3 |
| pos.js | 15 | 12 | 3 | 0 |
| stepw_common.js | 25 | 22 | 3 | 1 |
| tplpicker.js | 17 | 14 | 3 | 1 |
| phase74.sql | 11 | 8 | 3 | 1 |
| phase75.sql | 7 | 4 | 3 | 3 |
| phase83.sql | 5 | 2 | 3 | 3 |
| phase87.sql | 3 | 0 | 3 | 2 |
| chanedit.js | 22 | 20 | 2 | 1 |
| parallel.js | 35 | 33 | 2 | 0 |
| paths.js | 19 | 17 | 2 | 1 |
| purchaseprint.js | 13 | 11 | 2 | 2 |
| restoredrill.js | 24 | 22 | 2 | 2 |
| setupundo.js | 11 | 9 | 2 | 2 |
| twofa.js | 37 | 35 | 2 | 1 |
| phase103.sql | 2 | 0 | 2 | 2 |
| notifications.js | 22 | 21 | 1 | 0 |
| partners.js | 2 | 1 | 1 | 1 |
| pinsign.js | 9 | 8 | 1 | 0 |
| salary.js | 32 | 31 | 1 | 1 |
| settings2.js | 9 | 8 | 1 | 1 |
| phase72.sql | 1 | 0 | 1 | 1 |
| phase80.sql | 2 | 1 | 1 | 1 |
| phase88.sql | 1 | 0 | 1 | 1 |
| phase92.sql | 1 | 0 | 1 | 1 |
| phase96.sql | 1 | 0 | 1 | 1 |
| phase100.sql | 1 | 0 | 1 | 1 |
| phase102.sql | 3 | 2 | 1 | 1 |
| biz.js | 3 | 3 | 0 | 0 |
| controls.js | 7 | 7 | 0 | 0 |
| invoice.js | 1 | 1 | 0 | 0 |
| phase77.sql | 2 | 2 | 0 | 0 |
| phase86.sql | 1 | 1 | 0 | 0 |

### accounts.js (18 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| accounts.js:34 | The accounting start date has not been set. Set it, enter the opening balances, then switch accounting on. | হিসাব শুরুর তারিখ দেওয়া হয়নি। তারিখ দিন, তারপর শুরুর জের লিখুন, তারপর হিসাবরক্ষণ চালু করুন। | Hisab shuru-r date দেওয়া হয়নি। Date দিন, তারপর opening balance, তারপর accounting on করুন। | **mixed-up grammar** - mixed-up grammar: Romanized Bangla ("Hisab shuru-r") in mix - the only such case | হিসাব শুরুর ডেট দেওয়া হয়নি। ডেট দিন, তারপর শুরুর জের লিখুন, তারপর অ্যাকাউন্টিং চালু করুন। | Accounting শুরুর date দেওয়া হয়নি। Date দিন, তারপর opening balance, তারপর accounting on করুন। |
| accounts.js:35 | No permission for this page (it needs the accounts view or accounts manage permission). | এই পাতা দেখার অনুমতি নেই (হিসাব দেখা বা হিসাব পরিচালনার অনুমতি লাগবে)। | এই page দেখার অনুমতি নেই। | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ এই পাতা দেখার অনুমতি নেই (হিসাব দেখা বা হিসাব পরিচালনার অনুমতি লাগবে)। |
| accounts.js:36 | Accounting is switched off - the owner can switch it on in Settings; then new transactions are posted. | হিসাবরক্ষণ বন্ধ আছে — মালিক সেটিংস থেকে চালু করলে নতুন লেনদেন খতিয়ানে উঠবে। | Accounting off আছে — owner Settings থেকে on করলে নতুন লেনদেন post হবে। | **too literal / machine-translated** - too literal / bookish: হিসাবরক্ষণ -> অ্যাকাউন্টিং | অ্যাকাউন্টিং বন্ধ আছে — মালিক সেটিংস থেকে চালু করলে নতুন লেনদেন খতিয়ানে উঠবে। |  |
| accounts.js:69 | Reason code (needed when the guard is on) | কারণ-কোড (পাহারা চালু থাকলে লাগে) | Reason code (guard চালু থাকলে লাগে) | **too literal / machine-translated** - too literal / bookish: পাহারা -> গার্ড | কারণ-কোড (গার্ড চালু থাকলে লাগে) |  |
| accounts.js:76 | Opening balances: enter what each account held on the start date. Done once. Any difference can be put to "Retained earnings". | শুরুর জের: হিসাব শুরুর তারিখে প্রতিটি হিসাবে কত ছিল তা লিখুন। একবারই দেওয়া যায়। যে অঙ্ক মিলবে না তা "জমা মুনাফা" দিয়ে মেলানো যাবে। | Opening: start date-এ প্রতিটি account-এ কত ছিল। একবারই। পার্থক্য Retained earnings-এ। | **mixed-up grammar** - wrong rule (bn): Date=তারিখে; mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) | শুরুর জের: হিসাব শুরুর ডেটে প্রতিটি হিসাবে কত ছিল তা লিখুন। একবারই দেওয়া যায়। যে অঙ্ক মিলবে না তা "জমা মুনাফা" দিয়ে মেলানো যাবে। | ≈ শুরুর জের: হিসাব শুরুর date-এ প্রতিটি হিসাবে কত ছিল তা লিখুন। একবারই দেওয়া যায়। যে অঙ্ক মিলবে না তা "জমা মুনাফা" দিয়ে মেলানো যাবে। |
| accounts.js:86 | Accounting on | হিসাবরক্ষণ চালু | Accounting on | **too literal / machine-translated** - too literal / bookish: হিসাবরক্ষণ -> অ্যাকাউন্টিং | অ্যাকাউন্টিং চালু |  |
| accounts.js:101 | Earlier date: value replayed from the ledger (not the average cost) | আগের তারিখ: মূল্য লেজার থেকে হিসাব করা (গড় খরচ নয়) | আগের তারিখ: মূল্য ledger থেকে | **mixed-up grammar** - wrong rule (bn): Cost=খরচ, Date=তারিখ; wrong rule (mix): Date=তারিখ; mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) | আগের ডেট: মূল্য লেজার থেকে হিসাব করা (গড় কস্ট নয়) | আগের date: মূল্য ledger থেকে |
| accounts.js:118 | Stock issued for own use | নিজের কাজে stock | Stock issued for own use | **mixed-up grammar** - inconsistent term (Latin script in bn): stock; mixed-up grammar: mix is a plain English copy (not Bng/Eng) | নিজের কাজে স্টক | ≈ নিজের কাজে stock |
| accounts.js:119 | Stock short in transit | পথে কম পৌঁছানো stock | Stock short in transit | **mixed-up grammar** - inconsistent term (Latin script in bn): stock; mixed-up grammar: mix is a plain English copy (not Bng/Eng) | পথে কম পৌঁছানো স্টক | ≈ পথে কম পৌঁছানো stock |
| accounts.js:126 | Pick a reason code (the guard is on) | কারণ-কোড বেছে নিন (পাহারা চালু আছে) | Reason code বেছে নিন (guard চালু) | **too literal / machine-translated** - too literal / bookish: পাহারা -> গার্ড | কারণ-কোড বেছে নিন (গার্ড চালু আছে) |  |
| accounts.js:128 | Accounting is off - switch it on first | হিসাবরক্ষণ বন্ধ — আগে চালু করুন | Accounting off — আগে on করুন | **too literal / machine-translated** - too literal / bookish: হিসাবরক্ষণ -> অ্যাকাউন্টিং | অ্যাকাউন্টিং বন্ধ — আগে চালু করুন |  |
| accounts.js:135 | Code is not valid (letters / digits, up to 12) | কোড ঠিক নয় (অক্ষর/সংখ্যা, ১২টির মধ্যে) | Code ঠিক নয় | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ কোড ঠিক নয় (অক্ষর/সংখ্যা, ১২টির মধ্যে) |
| accounts.js:136 | Header is not valid (same type needed) | গ্রুপ ঠিক নয় (একই ধরনের গ্রুপ লাগবে) | Group ঠিক নয় | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ গ্রুপ ঠিক নয় (একই ধরনের গ্রুপ লাগবে) |
| accounts.js:136 | This account is used by a mapping - change the mapping first | এই হিসাব ম্যাপিংয়ে ব্যবহার হচ্ছে — আগে ম্যাপিং বদলান | Mapping-এ ব্যবহার হচ্ছে | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ এই হিসাব ম্যাপিংয়ে ব্যবহার হচ্ছে — আগে ম্যাপিং বদলান |
| accounts.js:138 | Entries already exist before that date | এর আগের তারিখে এন্ট্রি আছে — শুরুর তারিখ সামনে নেওয়া যাবে না | এর আগে entry আছে | **mixed-up grammar** - wrong rule (bn): Date=তারিখ, Date=তারিখে; mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) | এর আগের ডেটে এন্ট্রি আছে — শুরুর ডেট সামনে নেওয়া যাবে না | ≈ এর আগের date-এ এন্ট্রি আছে — শুরুর date সামনে নেওয়া যাবে না |
| accounts.js:139 | A party needs its id / mobile | পক্ষ বেছে নিলে তার আইডি/মোবাইল লাগবে | Party-র id লাগবে | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ পক্ষ বেছে নিলে তার আইডি/মোবাইল লাগবে |
| accounts.js:140 | This is an automatic entry - void the original document instead | এটি স্বয়ংক্রিয় এন্ট্রি — মূল কাগজ (বিক্রি/ক্রয় ইত্যাদি) বাতিল করুন | Auto entry — মূল document void করুন | **too literal / machine-translated** - wrong rule (bn): Void=বাতিল; too literal / bookish: স্বয়ংক্রিয় | এটি অটো এন্ট্রি — মূল কাগজ (বিক্রি/ক্রয় ইত্যাদি) ভয়েড করুন |  |
| accounts.js:142 | Account not valid (not a header or retired account) | হিসাব ঠিক নয় (গ্রুপ বা বন্ধ হিসাব নেওয়া যায় না) | Account ঠিক নয় | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ হিসাব ঠিক নয় (গ্রুপ বা বন্ধ হিসাব নেওয়া যায় না) |

### assistant.js (14 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| assistant.js:29 | The assistant is not open for you. The owner can give the "assistant_use" right. | আপনার জন্য সহকারী চালু নেই। মালিক "assistant_use" অনুমতি দিতে পারেন। | আপনার জন্য assistant চালু নেই। | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ আপনার জন্য সহকারী চালু নেই। মালিক "assistant_use" অনুমতি দিতে পারেন। |
| assistant.js:41 | I never know or show passwords, PINs, tokens or any secret. If a PIN is forgotten, ask the owner. | পাসওয়ার্ড, পিন, টোকেন বা কোনো গোপন তথ্য আমি জানি না ও দেখাই না। পিন ভুলে গেলে মালিককে বলুন। | Password / PIN / token কখনো দেখাই না। | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ পাসওয়ার্ড, পিন, টোকেন বা কোনো গোপন তথ্য আমি জানি না ও দেখাই না। পিন ভুলে গেলে মালিককে বলুন। |
| assistant.js:58 | No AI proxy is deployed - no paid service is on. It needs the owner’s approval and an Edge Function (docs/ASSISTANT.md). | AI প্রক্সি বসানো নেই — কোনো পেইড সার্ভিস চালু নেই। চালু করতে মালিকের অনুমোদন ও Edge Function লাগবে (docs/ASSISTANT.md)। | AI proxy বসানো নেই — কোনো paid service চালু নেই। | **mixed-up grammar** - wrong rule (bn): Approve=অনুমোদন; mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) | AI প্রক্সি বসানো নেই — কোনো পেইড সার্ভিস চালু নেই। চালু করতে মালিকের অ্যাপ্রুভ ও Edge Function লাগবে (docs/ASSISTANT.md)। | ≈ AI প্রক্সি বসানো নেই — কোনো পেইড সার্ভিস চালু নেই। চালু করতে মালিকের approve ও Edge Function লাগবে (docs/ASSISTANT.md)। |
| assistant.js:68 | What I can show (within your access): | আমি যা দেখাতে পারি (আপনার অনুমতি অনুযায়ী): | যা দেখাতে পারি: | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ আমি যা দেখাতে পারি (আপনার অনুমতি অনুযায়ী): |
| assistant.js:69 | I never write, change or approve anything; I give the link to the right screen. | আমি কিছু লিখি না, বদলাই না, অনুমোদন দিই না; ঠিক পেজের লিংক দিই। | আমি কিছু লিখি/বদলাই না; লিংক দিই। | **mixed-up grammar** - wrong rule (bn): Approve=অনুমোদন; mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) | আমি কিছু লিখি না, বদলাই না, অ্যাপ্রুভ দিই না; ঠিক পেজের লিংক দিই। | ≈ আমি কিছু লিখি না, বদলাই না, approve দিই না; ঠিক পেজের লিংক দিই। |
| assistant.js:74 | Verified lines added up (cash + receivable + stock - payable) | যাচাইকৃত লাইনগুলোর যোগ-বিয়োগ (নগদ + পাওনা + স্টক − দেনা) | Verified line-এর যোগফল | **mixed-up grammar** - wrong rule (bn): Cash=নগদ; mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) | যাচাইকৃত লাইনগুলোর যোগ-বিয়োগ (ক্যাশ + পাওনা + স্টক − দেনা) | ≈ যাচাইকৃত লাইনগুলোর যোগ-বিয়োগ (cash + পাওনা + stock − দেনা) |
| assistant.js:75 | This is not a balance sheet: fixed assets, loans and owner capital are not in the data. | এটা ব্যালান্স শিট নয়: স্থায়ী সম্পদ, ঋণ ও মালিকের মূলধন ডেটায় নেই। | এটা balance sheet নয়। | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ এটা ব্যালান্স শিট নয়: স্থায়ী সম্পদ, ঋণ ও মালিকের মূলধন ডেটায় নেই। |
| assistant.js:76 | Opening balances not set, or you do not see every place | শুরুর ব্যালান্স নেই বা সব জায়গা আপনি দেখেন না | Opening balance নেই | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ শুরুর ব্যালান্স নেই বা সব জায়গা আপনি দেখেন না |
| assistant.js:78 | No warning signal in this period (in the reports I could see). | এই সময়ে কোনো সতর্ক-লক্ষণ পাওয়া যায়নি (যে রিপোর্টগুলো দেখা গেল)। | কোনো warning signal নেই। | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ এই সময়ে কোনো সতর্ক-লক্ষণ পাওয়া যায়নি (যে report-গুলো দেখা গেল)। |
| assistant.js:79 | These come from the app’s existing detectors - no new guessing model. | এগুলো অ্যাপের বিদ্যমান ধরার নিয়ম থেকে; নতুন কোনো অনুমান-মডেল নয়। | বিদ্যমান detector থেকে। | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ এগুলো অ্যাপের বিদ্যমান ধরার নিয়ম থেকে; নতুন কোনো অনুমান-মডেল নয়। |
| assistant.js:80 | Suggested order (rule of thumb: blocked work and money at risk first) - interpretation, not a calculation. | প্রস্তাবিত ক্রম (নিয়ম: আটকে থাকা কাজ ও ঝুঁকিতে থাকা টাকা আগে) — এটা ব্যাখ্যা, হিসাব নয়। | প্রস্তাবিত ক্রম — ব্যাখ্যা। | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ প্রস্তাবিত ক্রম (নিয়ম: আটকে থাকা কাজ ও ঝুঁকিতে থাকা টাকা আগে) — এটা ব্যাখ্যা, হিসাব নয়। |
| assistant.js:99 | Expired batches | মেয়াদোত্তীর্ণ ব্যাচ | Expired batch | **too literal / machine-translated** - too literal / bookish: মেয়াদোত্তীর্ণ -> মেয়াদ শেষ | মেয়াদ শেষ ব্যাচ |  |
| assistant.js:102 | Overdue | মেয়াদোত্তীর্ণ | Overdue | **too literal / machine-translated** - too literal / bookish: মেয়াদোত্তীর্ণ -> মেয়াদ শেষ | মেয়াদ শেষ |  |
| assistant.js:473 | Overdue to suppliers | মেয়াদোত্তীর্ণ দেনা | Overdue দেনা | **too literal / machine-translated** - too literal / bookish: মেয়াদোত্তীর্ণ -> মেয়াদ শেষ | মেয়াদ শেষ দেনা |  |

### assistant_tools.js (1 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| assistant_tools.js:237 | Lapsed, new and repeat customers | নিষ্ক্রিয় ও নতুন-পুরনো গ্রাহক | Lapsed ও নতুন-পুরনো customer | **too literal / machine-translated** - wrong rule (bn): Customer=গ্রাহক; too literal / bookish: নিষ্ক্রিয় | বন্ধ ও নতুন-পুরনো কাস্টমার |  |

### attend2.js (7 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| attend2.js:92 | Staff & locks | কর্মী ও লক | Staff ও lock | **inconsistent term across screens** - inconsistent term: staff rendered কর্মী/কর্মচারী | স্টাফ ও লক |  |
| attend2.js:100 | The owner has locked self punch for you or your role | মালিক আপনার (বা আপনার ভূমিকার) স্ব-পাঞ্চ লক করেছেন | Owner আপনার/role-এর self punch lock করেছেন | **too literal / machine-translated** - too literal / bookish: ভূমিকা -> রোল | মালিক আপনার (বা আপনার রোলের) স্ব-পাঞ্চ লক করেছেন |  |
| attend2.js:102 | Your login is not linked to an employee record | আপনার লগইন কর্মী-তথ্যের সাথে জোড়া নেই | Login employee record-এর সাথে জোড়া নেই | **inconsistent term across screens** - inconsistent term: employee rendered কর্মী | আপনার লগইন কর্মচারী-তথ্যের সাথে জোড়া নেই |  |
| attend2.js:118 (+1 more) | Waiting approval | অনুমোদন বাকি | Approval বাকি | **wrong rule** - wrong rule (bn): Approve=অনুমোদন; inconsistent term: waiting rendered বাকি (=Due) | অ্যাপ্রুভ অপেক্ষায় | Approval অপেক্ষায় |
| attend2.js:121 | Lock by role | ভূমিকা অনুযায়ী লক | Role অনুযায়ী lock | **too literal / machine-translated** - too literal / bookish: ভূমিকা -> রোল | রোল অনুযায়ী লক |  |
| attend2.js:124 | Master switch app_punch_on | মাস্টার সুইচ app_punch_on | Master switch app_punch_on | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ মাস্টার সুইচ app_punch_on |
| attend2.js:132 | People are matched by name / employee no.; a difference is a prompt to look, not a verdict. | নাম/কর্মী নম্বর মিলিয়ে ধরা হয়েছে — পার্থক্য দেখার ইঙ্গিত, রায় নয়। | নাম/employee no. মিলিয়ে — পার্থক্য দেখার ইঙ্গিত, রায় নয়। | **inconsistent term across screens** - inconsistent term: employee rendered কর্মী | নাম/কর্মচারী নম্বর মিলিয়ে ধরা হয়েছে — পার্থক্য দেখার ইঙ্গিত, রায় নয়। |  |

### attendance.js (5 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| attendance.js:52 | Requests | আবেদন | Requests | **inconsistent term across screens** - inconsistent term: request rendered আবেদন | অনুরোধ |  |
| attendance.js:52 | ＋ Leave request | ＋ ছুটির আবেদন | ＋ Leave request | **inconsistent term across screens** - inconsistent term: request rendered আবেদন | ＋ ছুটির অনুরোধ |  |
| attendance.js:66 | There is already a leave request on these dates | এই তারিখে আগেই ছুটির আবেদন আছে | এই তারিখে আগেই leave আছে | **wrong rule** - wrong rule (bn): Date=তারিখে; wrong rule (mix): Date=তারিখে; inconsistent term: request rendered আবেদন | এই ডেটে আগেই ছুটির অনুরোধ আছে | এই date-এ আগেই leave আছে |
| attendance.js:68 | This request was already decided | এই আবেদনের সিদ্ধান্ত হয়ে গেছে | আগেই decide হয়েছে | **inconsistent term across screens** - inconsistent term: request rendered আবেদন | এই অনুরোধের সিদ্ধান্ত হয়ে গেছে |  |
| attendance.js:73 | Half-day hours must be below full-day hours | অর্ধ দিনের ঘণ্টা পূর্ণ দিনের চেয়ে কম হবে | Half < full | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ অর্ধ দিনের ঘণ্টা পূর্ণ দিনের চেয়ে কম হবে |

### badges107.js (6 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| badges107.js:19 | Ledger problems | খাতায় পোস্ট সমস্যা | Ledger post সমস্যা | **mixed-up grammar** - mixed-up grammar (missing "-এর"; reads as noun pile) | খাতায় পোস্টের সমস্যা | Ledger post-এর সমস্যা |
| badges107.js:20 | Waiting for cost | খরচের অপেক্ষা | Cost-এর অপেক্ষা | **wrong rule** - wrong rule: Cost translated খরচ | কস্টের অপেক্ষায় | Cost-এর অপেক্ষায় |
| badges107.js:21 | Pending auto-posts | অটো পোস্ট বাকি | Auto post বাকি | **inconsistent term across screens** - inconsistent term: waiting rendered বাকি (= Due); mix not mixed | অটো পোস্টের অপেক্ষায় | Auto post-এর অপেক্ষায় |
| badges107.js:22 (+1 more) | Forms with no screen record | স্ক্রিন-রেকর্ডহীন ফর্ম | Screen record ছাড়া form | **too literal / machine-translated** - too literal ("স্ক্রিন-রেকর্ডহীন") | স্ক্রিনে রেকর্ড নেই এমন ফর্ম | Screen-এ record নেই এমন form |
| badges107.js:23 | Items with unknown cost | অজানা খরচের আইটেম | অজানা cost-এর item | **wrong rule** - wrong rule: Cost translated খরচ; word order unnatural | কস্ট জানা নেই এমন আইটেম | Cost জানা নেই এমন item |
| badges107.js:24 (+1 more) | Bills without payment | payment ছাড়া bill | Payment ছাড়া bill | **inconsistent term across screens** - inconsistent term: Latin "payment" in bn (everywhere else পেমেন্ট) | পেমেন্ট ছাড়া বিল | Payment ছাড়া bill |

### books85.js (3 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| books85.js:26 | A recommendation never blocks you; keep whatever you prefer. | প্রস্তাব মানা বাধ্যতামূলক নয়; আপনি যা চান সেটাই রাখতে পারেন। | Recommendation মানা বাধ্যতামূলক নয়; আপনার পছন্দই থাকবে। | **too literal / machine-translated** - too literal / bookish: বাধ্যতামূলক | প্রস্তাব মানা জরুরি নয়; আপনি যা চান সেটাই রাখতে পারেন। | Recommendation মানা জরুরি নয়; আপনার পছন্দই থাকবে। |
| books85.js:39 | Posts waiting documents to the books by itself. See what is waiting, what is held by a closed period, and the run history. | বাকি কাগজ নিজে নিজে খাতায় তোলা। এখানে অপেক্ষায় থাকা কাগজ, বন্ধ মাসে আটকে থাকা কাগজ ও চালানোর ইতিহাস দেখা যায়। | বাকি document নিজে নিজে books-এ তোলা। Waiting, locked ও run history এখানে। | **inconsistent term across screens** - inconsistent term: waiting rendered বাকি (=Due) | অপেক্ষায় কাগজ নিজে নিজে খাতায় তোলা। এখানে অপেক্ষায় থাকা কাগজ, বন্ধ মাসে আটকে থাকা কাগজ ও চালানোর ইতিহাস দেখা যায়। | অপেক্ষায় document নিজে নিজে books-এ তোলা। Waiting, locked ও run history এখানে। |
| books85.js:130 | Accounting is switched off | হিসাবরক্ষণ বন্ধ আছে | Accounting বন্ধ আছে | **too literal / machine-translated** - too literal / bookish: হিসাবরক্ষণ -> অ্যাকাউন্টিং | অ্যাকাউন্টিং বন্ধ আছে |  |

### books96.js (3 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| books96.js:27 | A recommendation never blocks you and nothing is applied by itself; choose what you want. | প্রস্তাব মানা বাধ্যতামূলক নয়; সিস্টেম নিজে থেকে কিছু করে না, আপনি যা চান সেটাই বেছে নিন। | Recommendation মানা বাধ্যতামূলক নয়; system নিজে কিছু করে না, আপনার পছন্দই চলবে। | **too literal / machine-translated** - too literal / bookish: বাধ্যতামূলক | প্রস্তাব মানা জরুরি নয়; সিস্টেম নিজে থেকে কিছু করে না, আপনি যা চান সেটাই বেছে নিন। | Recommendation মানা জরুরি নয়; system নিজে কিছু করে না, আপনার পছন্দই চলবে। |
| books96.js:37 | Opening stock posting switch | শুরুর স্টক পোস্টিং সুইচ | Opening stock posting switch | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ শুরুর stock পোস্টিং সুইচ |
| books96.js:73 | Last purchase cost | শেষ কেনা দাম | Last purchase cost | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price) | শেষ কেনা কস্ট |  |

### bulkitems.js (1 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| bulkitems.js:52 | No high-confidence match left | নিশ্চিত মিল নেই (অথবা সব মানা হয়ে গেছে) | Confident মিল নেই | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ নিশ্চিত মিল নেই (অথবা সব মানা হয়ে গেছে) |

### cashmoves.js (1 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| cashmoves.js:30 | Enter a known customer mobile | সঠিক মোবাইল দিন (গ্রাহক খুঁজে পাওয়া যায়নি) | Customer mobile দিন | **mixed-up grammar** - wrong rule (bn): Customer=গ্রাহক; mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) | সঠিক মোবাইল দিন (কাস্টমার খুঁজে পাওয়া যায়নি) | ≈ সঠিক মোবাইল দিন (customer খুঁজে পাওয়া যায়নি) |

### catpick.js (4 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| catpick.js:46 | Required - a new item cannot be saved without one | বাধ্যতামূলক — নতুন Item Category ছাড়া সেভ হবে না | Required — নতুন Item Category ছাড়া save হবে না | **too literal / machine-translated** - inconsistent term (Latin script in bn): Category, Item; too literal / bookish: বাধ্যতামূলক | জরুরি — নতুন Item Category ছাড়া সেভ হবে না |  |
| catpick.js:57 | No cost right, so cost is blank | খরচ দেখার অধিকার নেই, তাই খরচ ফাঁকা | Cost দেখার অধিকার নেই, তাই cost ফাঁকা | **wrong rule** - wrong rule (bn): Cost=খরচ; inconsistent term: right/permission rendered অধিকার | কস্ট দেখার অনুমতি নেই, তাই কস্ট ফাঁকা |  |
| catpick.js:66 | A Category is required (rule: required) | Category লাগবে (নিয়ম: বাধ্যতামূলক) | Category লাগবে (rule: required) | **too literal / machine-translated** - inconsistent term (Latin script in bn): Category; too literal / bookish: বাধ্যতামূলক | ক্যাটাগরি লাগবে (নিয়ম: জরুরি) |  |
| catpick.js:67 | Choose a Sub-category of this Category (rule: required) | এই Category-র Sub-category বাছুন (নিয়ম: বাধ্যতামূলক) | এই Category-র Sub-category বাছুন (rule: required) | **too literal / machine-translated** - inconsistent term (Latin script in bn): Category, Sub-category; too literal / bookish: বাধ্যতামূলক | এই ক্যাটাগরি-র সাব-ক্যাটাগরি বাছুন (নিয়ম: জরুরি) |  |

### chanedit.js (1 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| chanedit.js:20 | Role in charge (optional) | দায়িত্বপ্রাপ্ত ভূমিকা (ঐচ্ছিক) | Role in charge (ঐচ্ছিক) | **too literal / machine-translated** - too literal / bookish: ভূমিকা -> রোল | দায়িত্বপ্রাপ্ত রোল (ঐচ্ছিক) |  |

### control.js (7 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| control.js:14 | Nothing is waiting ✓ | এখন কিছু বাকি নেই ✓ | এখন কিছু বাকি নেই ✓ | **inconsistent term across screens** - inconsistent term: waiting rendered বাকি (=Due) | এখন কিছু অপেক্ষায় নেই ✓ | এখন কিছু অপেক্ষায় নেই ✓ |
| control.js:20 | Options, add rules, Other queue | অপশন, যোগের নিয়ম, “অন্যান্য” | Options, add rules, Other queue | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ অপশন, যোগের নিয়ম, “অন্যান্য” |
| control.js:22 | Staff, roles, unlock | স্টাফ, ভূমিকা, লক খোলা | Staff, roles, unlock | **too literal / machine-translated** - too literal / bookish: ভূমিকা -> রোল | স্টাফ, রোল, লক খোলা |  |
| control.js:23 | Role × form permissions | ভূমিকা × ফর্ম অনুমতি | Role × form permissions | **too literal / machine-translated** - too literal / bookish: ভূমিকা -> রোল | রোল × ফর্ম অনুমতি |  |
| control.js:24 | Count first, red block, on/off | আগে গণনা, লাল ব্লক, চালু/বন্ধ | Count first, red block, on/off | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ আগে গণনা, লাল ব্লক, চালু/বন্ধ |
| control.js:29 | Red-control release requests | লাল-নিয়ন্ত্রণ মুক্তির অনুরোধ | Red-control release requests | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ লাল-নিয়ন্ত্রণ মুক্তির অনুরোধ |
| control.js:32 | Delegate | অনুমতিপ্রাপ্ত | Delegate | **too literal / machine-translated** - too literal / bookish: অনুমতিপ্রাপ্ত | অনুমতি-পাওয়া |  |

### costattrib.js (14 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| costattrib.js:20 (+3 more) | Not allowed — the cost right is needed | অনুমতি নেই — খরচ দেখার অধিকার লাগবে | অনুমতি নেই — cost right লাগবে | **wrong rule** - wrong rule (bn): Cost=খরচ; inconsistent term: right/permission rendered অধিকার | অনুমতি নেই — কস্ট দেখার অনুমতি লাগবে |  |
| costattrib.js:23 | Factory cost goes into the product cost. The showroom and admin shares are charged as you choose below. If nothing is set, nothing is charged anywher… | কারখানার খরচ পণ্যের দামে যায়। শোরুম ও অ্যাডমিনের অংশ নিচের পছন্দ অনুযায়ী ধরা হয়। কিছু ঠিক না করলে কোথাও ধরা হয় না (আজকের মতোই)। | Factory খরচ product cost-এ যায়। Showroom ও admin অংশ নিচের পছন্দে ধরা হয়। কিছু না বাছলে কোথাও ধরা হয় না (আজকের মতো)। | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price) | কারখানার খরচ পণ্যের কস্টে যায়। শোরুম ও অ্যাডমিনের অংশ নিচের পছন্দ অনুযায়ী ধরা হয়। কিছু ঠিক না করলে কোথাও ধরা হয় না (আজকের মতোই)। |  |
| costattrib.js:24 | Charge nowhere (unallocated) | কোথাও ধরবেন না (অভাগিত) | কোথাও ধরবেন না (অভাগিত) | **too literal / machine-translated** - too literal / bookish: অভাগিত | কোথাও ধরবেন না (ভাগ-না-হওয়া) | কোথাও ধরবেন না (ভাগ-না-হওয়া) |
| costattrib.js:25 (+1 more) | Unallocated | অভাগিত | অভাগিত | **too literal / machine-translated** - too literal / bookish: অভাগিত | ভাগ-না-হওয়া | ভাগ-না-হওয়া |
| costattrib.js:31 | Costs set to "main centre" go to this place as separate rows. If none is chosen they show in the cost view only. | "মূল কেন্দ্রে রাখুন" বাছা খরচ এই জায়গার লাভ-ক্ষতিতে আলাদা সারিতে যাবে। কিছু না বাছলে শুধু খরচের হিসাবে দেখা যাবে। | "মূল কেন্দ্র" খরচ এই place-এর P&L-এ আলাদা সারিতে যাবে। | **mixed-up grammar** - wrong rule (bn): Cost=খরচ, Cost=খরচের; wrong rule (mix): Cost=খরচ; mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) | "মূল কেন্দ্রে রাখুন" বাছা কস্ট এই জায়গার লাভ-ক্ষতিতে আলাদা সারিতে যাবে। কিছু না বাছলে শুধু কস্টের হিসাবে দেখা যাবে। | "মূল কেন্দ্র" cost এই place-এর P&L-এ আলাদা সারিতে যাবে। |
| costattrib.js:39 | Off (as today): the P&L does not change at all. On: the shares, as chosen above, are added as separate rows; the existing rows stay unchanged. | বন্ধ (এখনকার মতো): লাভ-ক্ষতির হিসাব একটুও বদলায় না। চালু: উপরের পছন্দ অনুযায়ী খরচের অংশ আলাদা সারিতে যোগ হয়; আগের সারি অপরিবর্তিত থাকে। | বন্ধ: P&L বদলায় না। চালু: পছন্দ অনুযায়ী অংশ আলাদা সারিতে যোগ হয়। | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ বন্ধ (এখনকার মতো): লাভ-ক্ষতির হিসাব একটুও বদলায় না। চালু: উপরের পছন্দ অনুযায়ী খরচের অংশ আলাদা সারিতে যোগ হয়; আগের সারি অপরিবর্তিত থাকে। |
| costattrib.js:41 | Off: works without approval (as today). Warn: a yellow warning without approval, work goes on. Required: no recipe cost or production before approval. | বন্ধ: অনুমোদন ছাড়াই চলে (এখনকার মতো)। সতর্ক: অনুমোদন না থাকলে হলুদ সতর্কতা আসে, কাজ আটকায় না। বাধ্যতামূলক: অনুমোদন ছাড়া রেসিপির খরচ ও উৎপাদন চলবে … | Off: আজকের মতো। Warn: অনুমোদন না থাকলে হলুদ সতর্কতা। Required: অনুমোদন ছাড়া চলবে না। | **too literal / machine-translated** - wrong rule (bn): Approve=অনুমোদন, Cost=খরচ; wrong rule (mix): Approve=অনুমোদন; too literal / bookish: বাধ্যতামূলক | বন্ধ: অ্যাপ্রুভ ছাড়াই চলে (এখনকার মতো)। সতর্ক: অ্যাপ্রুভ না থাকলে হলুদ সতর্কতা আসে, কাজ আটকায় না। জরুরি: অ্যাপ্রুভ ছাড়া রেসিপির কস্ট ও উৎপাদন চলবে… | Off: আজকের মতো। Warn: approve না থাকলে হলুদ সতর্কতা। Required: approve ছাড়া চলবে না। |
| costattrib.js:42 (+1 more) | Required | বাধ্যতামূলক | Required | **too literal / machine-translated** - too literal / bookish: বাধ্যতামূলক | জরুরি |  |
| costattrib.js:43 | Recipe required for production | উৎপাদনে রেসিপি বাধ্যতামূলক | উৎপাদনে recipe বাধ্যতামূলক | **too literal / machine-translated** - too literal / bookish: বাধ্যতামূলক | উৎপাদনে রেসিপি জরুরি | উৎপাদনে recipe জরুরি |
| costattrib.js:44 | If on: production cannot be entered with a hand-typed cost without a recipe; every product cost comes from a recipe (recommended). If off: a typed co… | চালু করলে: রেসিপি ছাড়া হাতে খরচ লিখে উৎপাদন ঢোকানো যাবে না; প্রতিটি পণ্যের খরচ রেসিপি থেকেই আসবে (সুপারিশ)। বন্ধ থাকলে হাতে লেখা খরচ চলে, তবে হলুদ স… | On: recipe ছাড়া হাতে cost দিয়ে production হবে না (সুপারিশ)। Off: চলে, তবে হলুদ সতর্কতা। | **mixed-up grammar** - wrong rule (bn): Cost=খরচ; mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) | চালু করলে: রেসিপি ছাড়া হাতে কস্ট লিখে উৎপাদন ঢোকানো যাবে না; প্রতিটি পণ্যের কস্ট রেসিপি থেকেই আসবে (সুপারিশ)। বন্ধ থাকলে হাতে লেখা কস্ট চলে, তবে হলু… | ≈ চালু করলে: রেসিপি ছাড়া হাতে cost লিখে উৎপাদন ঢোকানো যাবে না; প্রতিটি পণ্যের cost রেসিপি থেকেই আসবে (সুপারিশ)। বন্ধ থাকলে হাতে লেখা cost চলে, তবে হ… |
| costattrib.js:47 (+1 more) | Which right | কোন অধিকার | কোন right | **inconsistent term across screens** - inconsistent term: right/permission rendered অধিকার | কোন অনুমতি |  |
| costattrib.js:48 | No risk seen — the same person does not hold both entry and approval. | কোনো ঝুঁকি দেখা যাচ্ছে না — একই ব্যক্তি এন্ট্রি ও অনুমোদন দুটোই ধরছে না। | ঝুঁকি দেখা যাচ্ছে না। | **mixed-up grammar** - wrong rule (bn): Approve=অনুমোদন; mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) | কোনো ঝুঁকি দেখা যাচ্ছে না — একই ব্যক্তি এন্ট্রি ও অ্যাপ্রুভ দুটোই ধরছে না। | ≈ কোনো ঝুঁকি দেখা যাচ্ছে না — একই ব্যক্তি এন্ট্রি ও approve দুটোই ধরছে না। |
| costattrib.js:49 | This is advice only — the owner may approve himself or give the duty to anyone; nothing is blocked. | এটি শুধু পরামর্শ — মালিক চাইলে নিজে অনুমোদন করতে বা যে কাউকে দায়িত্ব দিতে পারেন; কিছু আটকায় না। | শুধু পরামর্শ — কিছু আটকায় না। | **mixed-up grammar** - wrong rule (bn): Approve=অনুমোদন; mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) | এটি শুধু পরামর্শ — মালিক চাইলে নিজে অ্যাপ্রুভ করতে বা যে কাউকে দায়িত্ব দিতে পারেন; কিছু আটকায় না। | ≈ এটি শুধু পরামর্শ — মালিক চাইলে নিজে approve করতে বা যে কাউকে দায়িত্ব দিতে পারেন; কিছু আটকায় না। |
| costattrib.js:57 | Allocate the unallocated part of the bill first | বিলের অভাগিত অংশ আগে ভাগ করুন | আগে অভাগিত অংশ ভাগ করুন | **too literal / machine-translated** - too literal / bookish: অভাগিত | বিলের ভাগ-না-হওয়া অংশ আগে ভাগ করুন | আগে ভাগ-না-হওয়া অংশ ভাগ করুন |

### costboard.js (1 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| costboard.js:34 | The cost right is needed | খরচ দেখার অধিকার লাগবে | Cost দেখার অধিকার লাগবে | **wrong rule** - wrong rule (bn): Cost=খরচ; inconsistent term: right/permission rendered অধিকার | কস্ট দেখার অনুমতি লাগবে |  |

### costing.js (5 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| costing.js:26 | Monthly pool ÷ normal output | মাসিক পুল ÷ স্বাভাবিক উৎপাদন | Monthly pool ÷ normal output | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ মাসিক পুল ÷ স্বাভাবিক উৎপাদন |
| costing.js:27 | Normal monthly output (kg) | স্বাভাবিক মাসিক উৎপাদন (কেজি) | Normal monthly output (kg) | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ স্বাভাবিক মাসিক উৎপাদন (কেজি) |
| costing.js:31 | Some ingredient costs are unknown | কিছু উপকরণের দাম জানা নেই | কিছু ingredient-এর cost অজানা | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price) | কিছু উপকরণের কস্ট জানা নেই |  |
| costing.js:34 | Per kg (base unit) | প্রতি কেজি (বেস একক) | Per kg (base unit) | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ প্রতি কেজি (বেস একক) |
| costing.js:39 | Showroom and admin cost are not here — they go to the branch P&L | শো-রুম ও অ্যাডমিন খরচ এখানে নয় — সেগুলো শাখার লাভ-ক্ষতিতে যায় | Showroom ও admin cost এখানে নয় — branch P&L-এ | **mixed-up grammar** - wrong rule (bn): Cost=খরচ; mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) | শো-রুম ও অ্যাডমিন কস্ট এখানে নয় — সেগুলো শাখার লাভ-ক্ষতিতে যায় | ≈ শো-রুম ও অ্যাডমিন cost এখানে নয় — সেগুলো শাখার লাভ-ক্ষতিতে যায় |

### costsources.js (4 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| costsources.js:24 | Bill pending | বিল বাকি | বিল বাকি | **inconsistent term across screens** - inconsistent term: waiting rendered বাকি (=Due) | বিল অপেক্ষায় | বিল অপেক্ষায় |
| costsources.js:27 | Provider / meter / contract no. (may be blank) | প্রদানকারী / মিটার / চুক্তি নং (ফাঁকা চলে) | Provider / meter / contract no (blank চলে) | **too literal / machine-translated** - too literal / bookish: প্রদান |  |  |
| costsources.js:32 | Floor area (sq ft) | জায়গার মাপ (বর্গফুট) | Floor area (sq ft) | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ জায়গার মাপ (বর্গফুট) |
| costsources.js:46 | The rule has blank values — fill them first | নিয়মে ফাঁকা ঘর আছে — আগে পূরণ করুন | Rule-এ blank আছে | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ নিয়মে ফাঁকা ঘর আছে — আগে পূরণ করুন |

### customers.js (5 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| customers.js:34 | Lock the tier (no automatic change) | স্তর তালা দিন (নিজে থেকে বদলাবে না) | Tier lock (auto বদলাবে না) | **too literal / machine-translated** - too literal / bookish: তালা দিন -> লক করুন | স্তর লক করুন (নিজে থেকে বদলাবে না) |  |
| customers.js:61 | Automatic refresh may also move down | স্বয়ংক্রিয় রিফ্রেশে নামানোও চলবে | Auto refresh-এ নামানোও | **too literal / machine-translated** - too literal / bookish: স্বয়ংক্রিয় | অটো রিফ্রেশে নামানোও চলবে |  |
| customers.js:65 | Automatic tier refresh | স্বয়ংক্রিয় স্তর রিফ্রেশ | Auto tier refresh | **too literal / machine-translated** - too literal / bookish: স্বয়ংক্রিয় | অটো স্তর রিফ্রেশ |  |
| customers.js:79 | The date is not valid (not in the future) | তারিখ ঠিক নয় (ভবিষ্যতের তারিখ হয় না) | Date ঠিক নয় | **mixed-up grammar** - wrong rule (bn): Date=তারিখ; mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) | ডেট ঠিক নয় (ভবিষ্যতের ডেট হয় না) | ≈ date ঠিক নয় (ভবিষ্যতের date হয় না) |
| customers.js:82 | The default tier cannot be retired — make another tier the default first | ডিফল্ট স্তর বন্ধ করা যায় না — আগে অন্য স্তরকে ডিফল্ট করুন | Default tier বন্ধ করা যায় না | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ ডিফল্ট স্তর বন্ধ করা যায় না — আগে অন্য স্তরকে ডিফল্ট করুন |

### daybook.js (4 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| daybook.js:34 | Cash = sales cash and imprest spending together (no separate drawer / imprest books) | নগদ = বিক্রির নগদ + ইমপ্রেস্টের খরচ একসাথে (আলাদা ড্রয়ার/ইমপ্রেস্ট হিসাব নেই) | Cash = sales cash + imprest খরচ একসাথে | **mixed-up grammar** - wrong rule (bn): Sale=বিক্রির; mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) | নগদ = সেলের নগদ + ইমপ্রেস্টের খরচ একসাথে (আলাদা ড্রয়ার/ইমপ্রেস্ট হিসাব নেই) | ≈ নগদ = sale-এর নগদ + ইমপ্রেস্টের খরচ একসাথে (আলাদা ড্রয়ার/ইমপ্রেস্ট হিসাব নেই) |
| daybook.js:47 | Start date (YYYY-MM-DD) | শুরুর তারিখ (YYYY-MM-DD) | Start date (YYYY-MM-DD) | **mixed-up grammar** - wrong rule (bn): Date=তারিখ; mixed-up grammar: mix is a plain English copy (not Bng/Eng) | শুরুর ডেট (YYYY-MM-DD) | ≈ শুরুর date (YYYY-MM-DD) |
| daybook.js:51 | Negative | ঋণাত্মক | Negative | **too literal / machine-translated** - too literal / bookish: ঋণাত্মক | মাইনাস |  |
| daybook.js:56 | Net movement counted from the start date — opening balances are not set, so this is "Net since start", not Opening/Closing | জের গোনা হয় শুরুর তারিখ থেকে (নিট) — শুরুর নগদ/ব্যাংক/মোবাইল জের বসানো নেই, তাই "শুরু/শেষ জের" নয়, "শুরু থেকে নিট" | Start date থেকে net — opening balance বসানো নেই, তাই "Net since start" | **mixed-up grammar** - wrong rule (bn): Date=তারিখ; mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) | জের গোনা হয় শুরুর ডেট থেকে (নিট) — শুরুর নগদ/ব্যাংক/মোবাইল জের বসানো নেই, তাই "শুরু/শেষ জের" নয়, "শুরু থেকে নিট" | ≈ জের গোনা হয় শুরুর date থেকে (নিট) — শুরুর নগদ/ব্যাংক/মোবাইল জের বসানো নেই, তাই "শুরু/শেষ জের" নয়, "শুরু থেকে নিট" |

### delegation.js (2 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| delegation.js:10 | Search person or right | নাম বা অধিকার খুঁজুন | নাম বা অধিকার খুঁজুন | **inconsistent term across screens** - inconsistent term: right/permission rendered অধিকার | নাম বা অনুমতি খুঁজুন |  |
| delegation.js:14 | Remove this right? | এই অধিকার সরাবেন? | এই right সরাবেন? | **inconsistent term across screens** - inconsistent term: right/permission rendered অধিকার | এই অনুমতি সরাবেন? |  |

### employees.js (6 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| employees.js:19 | Name / no. / mobile / NID | নাম / নম্বর / মোবাইল / NID | Name / no. / mobile / NID | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ নাম / নম্বর / মোবাইল / NID |
| employees.js:20 (+1 more) | Role | ভূমিকা | Role | **too literal / machine-translated** - too literal / bookish: ভূমিকা -> রোল | রোল |  |
| employees.js:37 | Main role (for deeds) | প্রধান ভূমিকা (ডিডের জন্য) | প্রধান role (deed-এর জন্য) | **too literal / machine-translated** - too literal / bookish: ভূমিকা -> রোল | প্রধান রোল (ডিডের জন্য) |  |
| employees.js:82 | Role is not valid | ভূমিকা ঠিক নয় | Role ঠিক নয় | **too literal / machine-translated** - too literal / bookish: ভূমিকা -> রোল | রোল ঠিক নয় |  |
| employees.js:89 | An active deed for this role exists - make a revision | এই ভূমিকায় আগেই একটি কার্যকর ডিড আছে - নতুন সংস্করণ করুন | এই role-এ আগেই active deed আছে - revision করুন | **too literal / machine-translated** - too literal / bookish: ভূমিকা -> রোল | এই রোলে আগেই একটি কার্যকর ডিড আছে - নতুন সংস্করণ করুন |  |
| employees.js:94 | The template is for another role | টেমপ্লেট অন্য ভূমিকার | Template অন্য role-এর | **too literal / machine-translated** - too literal / bookish: ভূমিকা -> রোল | টেমপ্লেট অন্য রোলের |  |

### entry.js (14 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| entry.js:270 | Paper serial (required) | কাগজের ছাপা নম্বর (আবশ্যক) | কাগজের ছাপা Number (আবশ্যক) | **too literal / machine-translated** - too literal / bookish: আবশ্যক | কাগজের ছাপা নম্বর (লাগবেই) | কাগজের ছাপা Number (লাগবেই) |
| entry.js:271 | Original date and time on the paper (required) | কাগজে লেখার আসল তারিখ ও সময় (আবশ্যক) | কাগজে লেখার আসল Date ও Time (আবশ্যক) | **too literal / machine-translated** - wrong rule (bn): Date=তারিখ; too literal / bookish: আবশ্যক | কাগজে লেখার আসল ডেট ও সময় (লাগবেই) | কাগজে লেখার আসল Date ও Time (লাগবেই) |
| entry.js:285 | An approved entry cannot be edited. Change what is wrong, then send the request; when the owner or a delegate approves, the old version stays as a re… | অনুমোদিত এন্ট্রি বদলানো যায় না। যা বদলাতে চান লিখুন, তারপর অনুরোধ পাঠান; মালিক বা অনুমতিপ্রাপ্ত কেউ অনুমোদন করলে পুরনোটা সংস্করণ হিসেবে থাকবে। | Approved entry বদলানো যায় না। যা বদলাতে চান লিখুন, request পাঠান; approve হলে পুরনোটা revision হিসেবে থাকবে। | **too literal / machine-translated** - wrong rule (bn): Approve=অনুমোদন, Approve=অনুমোদিত; too literal / bookish: অনুমতিপ্রাপ্ত | অ্যাপ্রুভড এন্ট্রি বদলানো যায় না। যা বদলাতে চান লিখুন, তারপর অনুরোধ পাঠান; মালিক বা অনুমতি-পাওয়া কেউ অ্যাপ্রুভ করলে পুরনোটা সংস্করণ হিসেবে থাকবে। |  |
| entry.js:409 | The expected figure and the short/over appear only after you save the count. A saved count cannot be changed. | গণনা সেভ করার পরেই প্রত্যাশিত অঙ্ক ও কম/বেশি দেখা যাবে। সেভ করলে গণনা আর বদলানো যায় না। | Count save করার পরেই expected ও কম/বেশি দেখা যাবে। Save করলে count আর বদলানো যায় না। | **too literal / machine-translated** - too literal / bookish: প্রত্যাশিত | গণনা সেভ করার পরেই ধরা অঙ্ক ও কম/বেশি দেখা যাবে। সেভ করলে গণনা আর বদলানো যায় না। |  |
| entry.js:410 | Show expected first (logged) | আগে প্রত্যাশিত দেখুন (লগ হবে) | আগে expected দেখুন (log হবে) | **too literal / machine-translated** - too literal / bookish: প্রত্যাশিত | আগে ধরা দেখুন (লগ হবে) |  |
| entry.js:412 | The expected figure and the short/over are shown to the approver after you submit | প্রত্যাশিত অঙ্ক ও কম/বেশি জমা দেওয়ার পর যাচাইকারীর কাছে দেখা যাবে | Expected ও কম/বেশি submit করার পর approver দেখবেন | **too literal / machine-translated** - too literal / bookish: প্রত্যাশিত | ধরা অঙ্ক ও কম/বেশি জমা দেওয়ার পর যাচাইকারীর কাছে দেখা যাবে |  |
| entry.js:413 | Expected | প্রত্যাশিত | Expected | **too literal / machine-translated** - too literal / bookish: প্রত্যাশিত | ধরা |  |
| entry.js:414 | The expected figure was seen before the count | প্রত্যাশিত অঙ্ক গণনার আগে দেখা হয়েছিল | Expected count-এর আগে দেখা হয়েছিল | **too literal / machine-translated** - too literal / bookish: প্রত্যাশিত | ধরা অঙ্ক গণনার আগে দেখা হয়েছিল |  |
| entry.js:415 | The sender's count and handover amount stay hidden until your count is saved | লেখকের গণনা ও হ্যান্ডওভার অঙ্ক আপনার গণনা সেভ হওয়া পর্যন্ত লুকানো | Sender-এর count ও handover আপনার count save হওয়া পর্যন্ত লুকানো | **too literal / machine-translated** - too literal / bookish: লেখক -> এন্ট্রিদাতা | এন্ট্রিদাতার গণনা ও হ্যান্ডওভার অঙ্ক আপনার গণনা সেভ হওয়া পর্যন্ত লুকানো |  |
| entry.js:417 | The second person signs on this phone with their own staff ID and PIN. The writer cannot sign. | দ্বিতীয় স্বাক্ষরকারী এই ফোনেই নিজের স্টাফ আইডি ও পিন দিয়ে স্বাক্ষর করবেন। লেখক নিজে স্বাক্ষর করতে পারবেন না। | দ্বিতীয় signer এই phone-এই নিজের staff ID ও PIN দিয়ে sign করবেন। লেখক নিজে sign করতে পারবেন না। | **too literal / machine-translated** - too literal / bookish: লেখক -> এন্ট্রিদাতা | দ্বিতীয় স্বাক্ষরকারী এই ফোনেই নিজের স্টাফ আইডি ও পিন দিয়ে স্বাক্ষর করবেন। এন্ট্রিদাতা নিজে স্বাক্ষর করতে পারবেন না। |  |
| entry.js:423 | Blind count: count every item and lock. The book balance is added by the system when you submit. | অন্ধ গণনা: আগে সব আইটেম গুনে লক করুন। লেজারের হিসাব জমা দেওয়ার পরে সিস্টেম নিজে বসাবে। | Blind count: আগে সব item গুনে lock করুন। Book balance submit-এর পরে system বসাবে। | **too literal / machine-translated** - too literal / bookish: অন্ধ -> ব্লাইন্ড | ব্লাইন্ড গণনা: আগে সব আইটেম গুনে লক করুন। লেজারের হিসাব জমা দেওয়ার পরে সিস্টেম নিজে বসাবে। |  |
| entry.js:424 | Blind receiving: count and lock first, then write the memo figure. | অন্ধ গ্রহণ: আগে গুনে লক করুন, তারপর মেমোর অঙ্ক লিখুন। | Blind receiving: আগে গুনে lock করুন, তারপর memo-র অঙ্ক লিখুন। | **too literal / machine-translated** - too literal / bookish: অন্ধ -> ব্লাইন্ড | ব্লাইন্ড গ্রহণ: আগে গুনে লক করুন, তারপর মেমোর অঙ্ক লিখুন। |  |
| entry.js:430 (+1 more) | The writer cannot sign | লেখক নিজে স্বাক্ষর করতে পারবেন না | লেখক নিজে sign করতে পারবেন না | **too literal / machine-translated** - too literal / bookish: লেখক -> এন্ট্রিদাতা | এন্ট্রিদাতা নিজে স্বাক্ষর করতে পারবেন না |  |
| entry.js:433 | This login is locked after wrong PINs - try later | এই লগইন ভুল পিনে তালাবদ্ধ — কিছুক্ষণ পরে | এই login ভুল PIN-এ locked — কিছুক্ষণ পরে | **too literal / machine-translated** - inconsistent term: lock rendered তালাবদ্ধ; too literal / bookish: তালাবদ্ধ | এই লগইন ভুল পিনে লক — কিছুক্ষণ পরে |  |

### finance2.js (11 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| finance2.js:93 | Needs the accounting start date first (Accounts page). | হিসাব শুরুর তারিখ না থাকলে এটি চলবে না — আগে Accounts পাতায় তারিখ দিন। | Accounts page-এ আগে start date দিন। | **mixed-up grammar** - wrong rule (bn): Date=তারিখ; mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) | হিসাব শুরুর ডেট না থাকলে এটি চলবে না — আগে Accounts পাতায় ডেট দিন। | ≈ হিসাব শুরুর date না থাকলে এটি চলবে না — আগে Accounts পাতায় date দিন। |
| finance2.js:118 | Cost | কেনা দাম | Cost | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price) | কেনা কস্ট |  |
| finance2.js:119 | Depreciation starts | অবচয় শুরুর মাস | Depreciation start | **too literal / machine-translated** - too literal / bookish: অবচয় | ডেপ্রিসিয়েশন শুরুর মাস |  |
| finance2.js:120 | Accumulated | জমা অবচয় | Accumulated | **too literal / machine-translated** - too literal / bookish: অবচয় | জমা ডেপ্রিসিয়েশন |  |
| finance2.js:121 | Post monthly depreciation | মাসিক অবচয় পোস্ট | Monthly depreciation post | **too literal / machine-translated** - too literal / bookish: অবচয় | মাসিক ডেপ্রিসিয়েশন পোস্ট |  |
| finance2.js:132 | Account not valid (a bank / cash or income / expense account is needed) | হিসাব ঠিক নয় (ব্যাংক/ক্যাশ বা আয়/খরচের হিসাব লাগবে) | Account ঠিক নয় | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ হিসাব ঠিক নয় (bank/cash বা আয়/খরচের হিসাব লাগবে) |
| finance2.js:137 | Date range not valid (a year that has not ended cannot be closed) | তারিখের সীমা ঠিক নয় (শেষ হয়নি এমন বছর নেওয়া যায় না) | Date range ঠিক নয় | **mixed-up grammar** - wrong rule (bn): Date=তারিখের; mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) | ডেটের সীমা ঠিক নয় (শেষ হয়নি এমন বছর নেওয়া যায় না) | ≈ date-এর সীমা ঠিক নয় (শেষ হয়নি এমন বছর নেওয়া যায় না) |
| finance2.js:139 | Depreciation is posted - cost / life cannot change | অবচয় পোস্ট হয়ে গেছে — দাম/আয়ু বদলানো যায় না | Depreciation post হয়েছে | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price); mixed-up grammar: mix drops part of the meaning (much shorter than bn/en); too literal / bookish: অবচয় | ডেপ্রিসিয়েশন পোস্ট হয়ে গেছে — কস্ট/আয়ু বদলানো যায় না | ≈ ডেপ্রিসিয়েশন পোস্ট হয়ে গেছে — cost/আয়ু বদলানো যায় না |
| finance2.js:140 | Salvage must be below the cost | অবশিষ্ট মূল্য দামের চেয়ে কম হতে হবে | Salvage < cost | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price); mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) | অবশিষ্ট মূল্য কস্টের চেয়ে কম হতে হবে | ≈ অবশিষ্ট মূল্য cost-এর চেয়ে কম হতে হবে |
| finance2.js:141 | Depreciation cannot start before the acquisition month | অবচয় কেনার মাসের আগে শুরু হয় না | Depreciation start আগে হয় না | **too literal / machine-translated** - too literal / bookish: অবচয় | ডেপ্রিসিয়েশন কেনার মাসের আগে শুরু হয় না |  |
| finance2.js:142 | Depreciation mapping missing | অবচয়ের ম্যাপিং নেই | Mapping নেই | **too literal / machine-translated** - too literal / bookish: অবচয় | ডেপ্রিসিয়েশনের ম্যাপিং নেই |  |

### forms_stock.js (2 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| forms_stock.js:441 | Off = nothing changes. Forms approved before you switch it on are not posted by themselves. | বন্ধ থাকলে কিছুই বদলায় না। চালু করার আগে পুরোনো অনুমোদিত ফর্ম নিজে থেকে পোস্ট হয় না। | Off = কিছুই বদলায় না। | **mixed-up grammar** - wrong rule (bn): Approve=অনুমোদিত; mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) | বন্ধ থাকলে কিছুই বদলায় না। চালু করার আগে পুরোনো অ্যাপ্রুভড ফর্ম নিজে থেকে পোস্ট হয় না। | ≈ বন্ধ থাকলে কিছুই বদলায় না। চালু করার আগে পুরোনো অ্যাপ্রুভড ফর্ম নিজে থেকে পোস্ট হয় না। |
| forms_stock.js:444 | Only the owner can change these | শুধু মালিক বদলাতে পারেন | Only the owner can change these | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ শুধু মালিক বদলাতে পারেন |

### formscreens.js (2 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| formscreens.js:30 | Each switch shows the system recommendation next to it. Following it is optional. | প্রতিটি সুইচের পাশে সিস্টেমের পরামর্শ আছে। পরামর্শ মানা বাধ্যতামূলক নয়। | প্রতিটি switch-এর পাশে system-এর পরামর্শ আছে। মানা বাধ্যতামূলক নয়। | **too literal / machine-translated** - too literal / bookish: বাধ্যতামূলক | প্রতিটি সুইচের পাশে সিস্টেমের পরামর্শ আছে। পরামর্শ মানা জরুরি নয়। | প্রতিটি switch-এর পাশে system-এর পরামর্শ আছে। মানা জরুরি নয়। |
| formscreens.js:52 (+1 more) | Reason (required) | কারণ লিখুন (বাধ্যতামূলক) | কারণ লিখুন (required) | **too literal / machine-translated** - too literal / bookish: বাধ্যতামূলক | কারণ লিখুন (জরুরি) |  |

### guards.js (2 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| guards.js:12 | See each switch, its current value and the recommended one. Nothing is forced; it changes only when you tap apply. | প্রতিটি সুইচের বর্তমান মান ও প্রস্তাবিত মান দেখুন। প্রস্তাব মানা বাধ্যতামূলক নয়; চাপলে তবেই বদলায়। | প্রতিটি switch-এর current ও recommended মান দেখুন। কিছু forced নয়; apply চাপলে তবেই বদলায়। | **too literal / machine-translated** - too literal / bookish: বাধ্যতামূলক | প্রতিটি সুইচের বর্তমান মান ও প্রস্তাবিত মান দেখুন। প্রস্তাব মানা জরুরি নয়; চাপলে তবেই বদলায়। |  |
| guards.js:28 (+1 more) | Write a reason to use more ingredient than the stock on hand | stock-এর বেশি কাঁচামাল নিতে কারণ লিখুন | Stock-এর বেশি ingredient নিতে reason লিখুন | **inconsistent term across screens** - inconsistent term (Latin script in bn): stock; inconsistent term: ingredient rendered কাঁচামাল | স্টকের বেশি উপকরণ নিতে কারণ লিখুন |  |

### i18n.js (1 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| i18n.js:222 | Inactive / Hidden | নিষ্ক্রিয় | Inactive | **too literal / machine-translated** - too literal / bookish: নিষ্ক্রিয় | বন্ধ |  |

### ia.js (6 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| ia.js:14 | Purchasing & Suppliers | ক্রয় ও সরবরাহকারী | Purchase ও Supplier | **wrong rule** - wrong rule: common word translated into Bangla in bn mode (সরবরাহকারী) | ক্রয় ও সাপ্লায়ার | Purchase ও Supplier |
| ia.js:16 | Sales & POS | বিক্রি ও POS | Sale ও POS | **wrong rule** - wrong rule: common word translated into Bangla in bn mode (বিক্রি) | সেল ও POS | Sale ও POS |
| ia.js:17 | Customers, Orders & Invoices | গ্রাহক, অর্ডার ও ইনভয়েস | Customer, Order ও Invoice | **wrong rule** - wrong rule: common word translated into Bangla in bn mode (গ্রাহক) | কাস্টমার, অর্ডার ও ইনভয়েস | Customer, Order ও Invoice |
| ia.js:19 | Approvals & Exceptions | অনুমোদন ও ব্যতিক্রম | Approval ও Exception | **wrong rule** - wrong rule: common word translated into Bangla in bn mode (অনুমোদন) | অ্যাপ্রুভাল ও এক্সেপশন | Approval ও Exception |
| ia.js:21 | Staff, Roles & Permissions | স্টাফ, ভূমিকা ও অনুমতি | Staff, Role ও Permission | **too literal / machine-translated** - too literal ("ভূমিকা" = role) | স্টাফ, রোল ও অনুমতি | Staff, Role ও Permission |
| ia.js:23 | Administration & Settings | প্রশাসন ও সেটিংস | Administration ও Settings | **too literal / machine-translated** - too literal/bookish (প্রশাসন) | অ্যাডমিন ও সেটিংস | Admin ও Settings |

### inbox.js (3 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| inbox.js:20 | Ignored | উপেক্ষা | Ignored | **too literal / machine-translated** - too literal / bookish: উপেক্ষা | বাদ |  |
| inbox.js:22 (+1 more) | Ignore | উপেক্ষা | Ignore | **too literal / machine-translated** - too literal / bookish: উপেক্ষা | বাদ |  |
| inbox.js:49 | This message already became an order or was ignored | এই বার্তা থেকে আগেই অর্ডার হয়েছে বা উপেক্ষা করা হয়েছে | এই message আগেই order/ignored | **too literal / machine-translated** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en); too literal / bookish: উপেক্ষা | এই বার্তা থেকে আগেই অর্ডার হয়েছে বা বাদ করা হয়েছে | ≈ এই বার্তা থেকে আগেই অর্ডার হয়েছে বা বাদ করা হয়েছে |

### integrations.js (1 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| integrations.js:29 | Roles | যে ভূমিকায় | Roles | **too literal / machine-translated** - too literal / bookish: ভূমিকা -> রোল | যে রোলে |  |

### invoiceview.js (9 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| invoiceview.js:28 | Pending sync: not on the server yet. It will be sent when the phone is online. This number is provisional; the final number comes after sync. | সার্ভারে এখনো যায়নি — নেট এলে নিজে জমা হবে। এই নম্বরটি সাময়িক, চূড়ান্ত নম্বর পরে পাবেন। | সার্ভারে এখনো যায়নি (pending sync) — net এলে নিজে জমা হবে। এই number টি সাময়িক, final number পরে পাবেন। | **inconsistent term across screens** - inconsistent term: sync rendered জমা (= deposit/submit) in bn, "sync" in mix | সার্ভারে এখনো যায়নি — নেট এলে নিজে সিঙ্ক হবে। এই নম্বরটি সাময়িক, সিঙ্কের পরে চূড়ান্ত নম্বর পাবেন। | Server-এ এখনো যায়নি — net এলে নিজে sync হবে। এই number টি সাময়িক, sync-এর পরে final number পাবেন। |
| invoiceview.js:29 | Synced to the server | সার্ভারে জমা হয়েছে | সার্ভারে জমা হয়েছে | **inconsistent term across screens** - inconsistent term: জমা for sync | সার্ভারে সিঙ্ক হয়েছে | Server-এ sync হয়েছে |
| invoiceview.js:31 | Cashier | বিক্রেতা | Cashier | **inconsistent term across screens** - wrong term: Cashier rendered বিক্রেতা (= seller) | ক্যাশিয়ার | Cashier |
| invoiceview.js:32 | Subtotal | মোট (ছাড়ের আগে) | Subtotal | **wrong rule** - wrong rule: common word translated into Bangla in bn mode (মোট (ছাড়ের আগে) clashes with Total) | সাবটোটাল (ছাড়ের আগে) | Subtotal (ছাড়ের আগে) |
| invoiceview.js:32 | Total | সর্বমোট | Total | **wrong rule** - wrong rule: common word translated into Bangla in bn mode (সর্বমোট; elsewhere মোট) | টোটাল | Total |
| invoiceview.js:33 | Change | ফেরত | Change | **inconsistent term across screens** - ambiguous: ফেরত also means Return/Refund on the same screen | খুচরা ফেরত | Change ফেরত |
| invoiceview.js:35 (+1 more) | SMS | এসএমএস | SMS | **inconsistent term across screens** - inconsistent term: এসএমএস here, "SMS" in line 312 and purchaseprint.js | SMS | SMS |
| invoiceview.js:36 | Copy text | কপি | Text Copy | **mixed-up grammar** - mixed-up grammar (mix "Text Copy" reversed; bn lost the word "text") | টেক্সট কপি | Text copy |
| invoiceview.js:40 | The customer number is hidden for your role. Type it in. | আপনার ভূমিকায় গ্রাহকের নম্বর দেখানো হয় না — নিজে লিখুন। | আপনার role এ customer এর number দেখানো হয় না — নিজে লিখুন। | **too literal / machine-translated** - wrong rule (bn): Customer=গ্রাহকের; too literal / bookish: ভূমিকা -> রোল; mixed-up grammar: suffix spacing (Latin word + detached Bangla suffix) | আপনার রোলে কাস্টমারের নম্বর দেখানো হয় না — নিজে লিখুন। | আপনার role-এ customer-এর number দেখানো হয় না — নিজে লিখুন। |

### itemmaster.js (6 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| itemmaster.js:63 | Nothing waiting ✓ | সিদ্ধান্ত বাকি নেই ✓ | Decision বাকি নেই ✓ | **inconsistent term across screens** - inconsistent term: waiting rendered বাকি (=Due) | সিদ্ধান্ত অপেক্ষায় নেই ✓ | Decision অপেক্ষায় নেই ✓ |
| itemmaster.js:68 | Tools (controlled) stock count | যন্ত্রপাতির (নিয়ন্ত্রিত) আলাদা স্টক গণনা | Tools (controlled) stock count | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ যন্ত্রপাতির (নিয়ন্ত্রিত) আলাদা stock গণনা |
| itemmaster.js:72 | Cost ৳ | দাম ৳ | Cost ৳ | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price) | কস্ট ৳ |  |
| itemmaster.js:73 | Retire (sold / lost / scrapped) | বন্ধ করুন (বিক্রি / হারানো / বাতিল) | Retire (sold / lost / scrapped) | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ বন্ধ করুন (বিক্রি / হারানো / বাতিল) |
| itemmaster.js:76 | Cost is visible to the owner and permitted people only | দাম শুধু মালিক বা অনুমতিপ্রাপ্তরা দেখেন | Cost শুধু Owner/permitted দেখেন | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price); too literal / bookish: অনুমতিপ্রাপ্ত | কস্ট শুধু মালিক বা অনুমতি-পাওয়ারা দেখেন |  |
| itemmaster.js:515 | Cost is not valid | দাম ঠিক নয় | Cost ঠিক নয় | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price) | কস্ট ঠিক নয় |  |

### landed.js (11 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| landed.js:32 | Not allowed — the cost right and the landed cost permission are needed | অনুমতি নেই — cost দেখার অধিকার আর Landed cost-এর অনুমতি লাগবে | অনুমতি নেই — cost right আর landed cost permission লাগবে | **inconsistent term across screens** - inconsistent term (Latin script in bn): cost; inconsistent term: right/permission rendered অধিকার | অনুমতি নেই — কস্ট দেখার অনুমতি আর Landed cost-এর অনুমতি লাগবে |  |
| landed.js:35 | Off — item cost = invoice price | বন্ধ — মালের দাম = বিলের দাম | Off — item cost = invoice price | **mixed-up grammar** - wrong rule (bn): Price=দাম; mixed-up grammar: mix is a plain English copy (not Bng/Eng) | বন্ধ — মালের প্রাইস = বিলের প্রাইস | ≈ বন্ধ — মালের price = বিলের price |
| landed.js:50 | Amount (negative = refund) | টাকা (ঋণাত্মক = ফেরত) | Amount (negative = refund) | **too literal / machine-translated** - too literal / bookish: ঋণাত্মক | টাকা (মাইনাস = ফেরত) |  |
| landed.js:54 | Added to item cost | মালের দামে যোগ হবে | Item cost-এ যোগ হবে | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price) | মালের কস্টে যোগ হবে |  |
| landed.js:54 | Recoverable tax — not in item cost | ফেরতযোগ্য কর — মালের দামে নয় | Recoverable tax — item cost-এ নয় | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price) | ফেরতযোগ্য কর — মালের কস্টে নয় |  |
| landed.js:63 | New unit cost per line — every method side by side | প্রতি লাইনে নতুন একক দাম — সব পদ্ধতি পাশাপাশি | প্রতি line-এ নতুন unit cost — সব method পাশাপাশি | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price) | প্রতি লাইনে নতুন একক কস্ট — সব পদ্ধতি পাশাপাশি |  |
| landed.js:64 | New unit cost | নতুন একক দাম | নতুন unit cost | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price) | নতুন একক কস্ট |  |
| landed.js:65 | Added to item cost | মালের দামে যোগ | Item cost-এ যোগ | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price) | মালের কস্টে যোগ |  |
| landed.js:66 | Effect on the average cost | গড় দামের উপর প্রভাব | Average cost-এর উপর effect | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price) | গড় কস্টের উপর প্রভাব |  |
| landed.js:70 | added to stock cost | stock-এর দামে যোগ | stock cost-এ যোগ | **too literal / machine-translated** - inconsistent term (Latin script in bn): stock; wrong term: Cost rendered as দাম (=Price) | স্টকের কস্টে যোগ |  |
| landed.js:71 | Posting changes the average cost of the items. Sure? | পোস্ট করলে মালের গড় দাম বদলাবে। নিশ্চিত? | Post করলে item-এর average cost বদলাবে। নিশ্চিত? | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price) | পোস্ট করলে মালের গড় কস্ট বদলাবে। নিশ্চিত? |  |

### listctl.js (1 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| listctl.js:32 | This list is locked | তালিকা তালাবদ্ধ | List locked | **too literal / machine-translated** - inconsistent term: lock rendered তালাবদ্ধ; too literal / bookish: তালাবদ্ধ | তালিকা লক |  |

### lists.js (4 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| lists.js:34 | Owner only — the owner (and delegates) add; others write "Other" | শুধু মালিক — মালিক (ও অনুমতিপ্রাপ্ত) যোগ করেন; বাকিরা "অন্যান্য" লিখুন | Owner only — Owner (ও delegate) Add করেন; বাকিরা "Other" লিখুন | **too literal / machine-translated** - too literal / bookish: অনুমতিপ্রাপ্ত | শুধু মালিক — মালিক (ও অনুমতি-পাওয়া) যোগ করেন; বাকিরা "অন্যান্য" লিখুন |  |
| lists.js:36 | Locked | তালাবদ্ধ | Locked | **too literal / machine-translated** - inconsistent term: lock rendered তালাবদ্ধ; too literal / bookish: তালাবদ্ধ | লক |  |
| lists.js:38 | Lock the list | তালাবদ্ধ করুন | List Lock | **too literal / machine-translated** - inconsistent term: lock rendered তালাবদ্ধ; too literal / bookish: তালাবদ্ধ | লক করুন |  |
| lists.js:42 | Reason for retiring (required) | বন্ধ করার কারণ (আবশ্যক) | বন্ধ করার কারণ (আবশ্যক) | **too literal / machine-translated** - too literal / bookish: আবশ্যক | বন্ধ করার কারণ (লাগবেই) | বন্ধ করার কারণ (লাগবেই) |

### locations.js (5 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| locations.js:20 | Inactive | নিষ্ক্রিয় | Inactive | **too literal / machine-translated** - too literal / bookish: নিষ্ক্রিয় | বন্ধ |  |
| locations.js:22 | Planned opening (YYYY-MM-DD) | পরিকল্পিত খোলার তারিখ (YYYY-MM-DD) | Planned opening (YYYY-MM-DD) | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ পরিকল্পিত খোলার তারিখ (YYYY-MM-DD) |
| locations.js:25 | Switch inactive | নিষ্ক্রিয় করুন | Switch inactive | **too literal / machine-translated** - too literal / bookish: নিষ্ক্রিয় | বন্ধ করুন |  |
| locations.js:27 | Reason (required) | কারণ (আবশ্যক) | Reason (আবশ্যক) | **too literal / machine-translated** - too literal / bookish: আবশ্যক | কারণ (লাগবেই) | Reason (লাগবেই) |
| locations.js:51 | Old version (read only) | পুরোনো সংস্করণ (শুধু পড়া) | Old version (read only) | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ পুরোনো সংস্করণ (শুধু পড়া) |

### nav.js (2 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| nav.js:38 | Pending | বাকি | Pending | **inconsistent term across screens** - inconsistent term: waiting rendered বাকি (=Due) | অপেক্ষায় |  |
| nav.js:51 | Wastage approvals waiting | নষ্টের অনুমোদন বাকি | Wastage approval বাকি | **wrong rule** - wrong rule (bn): Approve=অনুমোদন; inconsistent term: waiting rendered বাকি (=Due) | নষ্টের অ্যাপ্রুভ অপেক্ষায় | Wastage approval অপেক্ষায় |

### notifications.js (1 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| notifications.js:19 | Automatic backup | স্বয়ংক্রিয় ব্যাকআপ | Auto backup | **too literal / machine-translated** - too literal / bookish: স্বয়ংক্রিয় | অটো ব্যাকআপ |  |

### optionsx.js (3 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| optionsx.js:64 | People with the inbox_unmask permission can reveal one at a time; every reveal is logged: who, when, which message. | অনুমতিপ্রাপ্ত (অনুমতি: inbox_unmask) মানুষ একটি একটি করে খুলতে পারেন; প্রতিবার log-এ থাকে: কে, কখন, কোন message। | Authorised (permission: inbox_unmask) মানুষ একটি একটি করে খুলতে পারেন; প্রতিবার log-এ থাকে: কে, কখন, কোন message। | **too literal / machine-translated** - inconsistent term (Latin script in bn): inbox, message; too literal / bookish: অনুমতিপ্রাপ্ত | অনুমতি-পাওয়া (অনুমতি: ইনবক্স_unmask) মানুষ একটি একটি করে খুলতে পারেন; প্রতিবার log-এ থাকে: কে, কখন, কোন মেসেজ। |  |
| optionsx.js:127 | Asking with a small sheet is the safe middle: money never moves by mistake and you do not type bill and payment twice. Use a fully automatic mode onl… | ছোট sheet দিয়ে জিজ্ঞেস করা নিরাপদ: টাকা কখনো ভুলে সরে না, আবার bill ও payment দুবার type করতে হয় না। পুরোপুরি স্বয়ংক্রিয় শুধু cash-এ শোধ হওয়া ছো… | ছোট sheet দিয়ে জিজ্ঞেস করা safe: টাকা কখনো ভুলে সরে না, আবার bill ও payment দুবার type করতে হয় না। পুরোপুরি auto শুধু cash-এ শোধ হওয়া ছোট bill-এর … | **too literal / machine-translated** - inconsistent term (Latin script in bn): bill, cash, payment; too literal / bookish: স্বয়ংক্রিয় | ছোট sheet দিয়ে জিজ্ঞেস করা নিরাপদ: টাকা কখনো ভুলে সরে না, আবার বিল ও পেমেন্ট দুবার type করতে হয় না। পুরোপুরি অটো শুধু ক্যাশে শোধ হওয়া ছোট বিলের জন… |  |
| optionsx.js:130 | Hiding phone and address is the better default: most work does not need the full number and a leak costs a lot. Name and message text stay visible so… | phone ও address ঢেকে রাখা ভালো: বেশিরভাগ কাজে পুরো নম্বর লাগে না, আর ফাঁস হলে ক্ষতি বেশি। নাম ও message-এর লেখা খোলা থাকে যাতে কাজ আটকায় না। দরকারে … | Phone ও address ঢেকে রাখা ভালো: বেশিরভাগ কাজে পুরো নম্বর লাগে না, আর leak হলে ক্ষতি বেশি। নাম ও message-এর লেখা খোলা থাকে যাতে কাজ আটকায় না। দরকারে … | **too literal / machine-translated** - inconsistent term (Latin script in bn): address, message, phone; too literal / bookish: অনুমতিপ্রাপ্ত | ফোন ও ঠিকানা ঢেকে রাখা ভালো: বেশিরভাগ কাজে পুরো নম্বর লাগে না, আর ফাঁস হলে ক্ষতি বেশি। নাম ও মেসেজের লেখা খোলা থাকে যাতে কাজ আটকায় না। দরকারে অনুমতি… |  |

### optviews.js (5 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| optviews.js:25 | Role defaults | ভূমিকার ডিফল্ট | Role-এর default | **too literal / machine-translated** - too literal / bookish: ভূমিকা -> রোল | রোলের ডিফল্ট |  |
| optviews.js:27 | from role | ভূমিকা থেকে | role থেকে | **too literal / machine-translated** - too literal / bookish: ভূমিকা -> রোল | রোল থেকে |  |
| optviews.js:33 | Recommendations (advice only - never blocking) | পরামর্শ (শুধু পরামর্শ — বাধ্যতামূলক নয়) | Recommendation (শুধু পরামর্শ — বাধ্যতামূলক নয়) | **too literal / machine-translated** - too literal / bookish: বাধ্যতামূলক | পরামর্শ (শুধু পরামর্শ — জরুরি নয়) | Recommendation (শুধু পরামর্শ — জরুরি নয়) |
| optviews.js:36 | ignored | উপেক্ষা করা | ignored | **too literal / machine-translated** - too literal / bookish: উপেক্ষা | বাদ করা |  |
| optviews.js:37 | This permission comes from the role - change it in the role | এই অনুমতি ভূমিকা থেকে এসেছে — ভূমিকায় বদলান | এই permission role থেকে এসেছে — role-এ বদলান | **too literal / machine-translated** - too literal / bookish: ভূমিকা -> রোল | এই অনুমতি রোল থেকে এসেছে — রোলে বদলান |  |

### ownerboard.js (4 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| ownerboard.js:29 | Overdue after this many days | কত দিনের বেশি পুরনো হলে "মেয়াদোত্তীর্ণ" | কত দিন পরে "overdue" | **too literal / machine-translated** - too literal / bookish: মেয়াদোত্তীর্ণ -> মেয়াদ শেষ | কত দিনের বেশি পুরনো হলে "মেয়াদ শেষ" |  |
| ownerboard.js:34 | overdue | মেয়াদোত্তীর্ণ | overdue | **too literal / machine-translated** - too literal / bookish: মেয়াদোত্তীর্ণ -> মেয়াদ শেষ | মেয়াদ শেষ |  |
| ownerboard.js:106 | Customer dues (total & overdue) | গ্রাহকের বাকি (মোট ও মেয়াদোত্তীর্ণ) | Customer due (total ও overdue) | **too literal / machine-translated** - wrong rule (bn): Customer=গ্রাহকের, Total=মোট; too literal / bookish: মেয়াদোত্তীর্ণ -> মেয়াদ শেষ | কাস্টমারের বাকি (টোটাল ও মেয়াদ শেষ) |  |
| ownerboard.js:132 | Parallel-month decisions waiting | পাশাপাশি মাসের সিদ্ধান্ত বাকি | Parallel মাসের decision বাকি | **inconsistent term across screens** - inconsistent term: waiting rendered বাকি (=Due) | পাশাপাশি মাসের সিদ্ধান্ত অপেক্ষায় | Parallel মাসের decision অপেক্ষায় |

### packflags.js (2 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| packflags.js:21 | What you checked / did (required) | কী দেখলেন / কী করলেন (বাধ্যতামূলক) | কী দেখলেন / কী করলেন (required) | **too literal / machine-translated** - too literal / bookish: বাধ্যতামূলক | কী দেখলেন / কী করলেন (জরুরি) |  |
| packflags.js:24 | Marking reviewed needs the POS approve right | যাচাই করতে POS অনুমোদনের অধিকার লাগবে | Review করতে POS approve-এর অধিকার লাগবে | **wrong rule** - wrong rule (bn): Approve=অনুমোদনের; inconsistent term: right/permission rendered অধিকার | যাচাই করতে POS অ্যাপ্রুভের অনুমতি লাগবে |  |

### parallel.js (2 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| parallel.js:13 | No pair yet - the owner must name one | এখনও কোনো জোড়া নেই — মালিক একটি নাম দিন | এখনও কোনো জোড়া নেই | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ এখনও কোনো জোড়া নেই — মালিক একটি নাম দিন |
| parallel.js:23 | Some days are still waiting | কিছু দিনের তুলনা বাকি | কিছু দিনের তুলনা বাকি | **inconsistent term across screens** - inconsistent term: waiting rendered বাকি (=Due) | কিছু দিনের তুলনা অপেক্ষায় | কিছু দিনের তুলনা অপেক্ষায় |

### paths.js (1 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| paths.js:17 | Day book vs journal | ডে-বুক বনাম জার্নাল | Day book vs journal | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ ডে-বুক বনাম জার্নাল |

### payroll.js (7 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| payroll.js:23 | After approval this month's attendance and pay cannot change. Approve? | অনুমোদনের পর এই মাসের হাজিরা ও বেতন আর বদলানো যাবে না। অনুমোদন করবেন? | Approve করলে মাস lock হবে। করবেন? | **mixed-up grammar** - wrong rule (bn): Approve=অনুমোদন, Approve=অনুমোদনের; mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) | অ্যাপ্রুভের পর এই মাসের হাজিরা ও বেতন আর বদলানো যাবে না। অ্যাপ্রুভ করবেন? | ≈ approve-এর পর এই মাসের হাজিরা ও বেতন আর বদলানো যাবে না। approve করবেন? |
| payroll.js:43 | days without attendance (counted as paid) | দিনের হাজিরা হিসাব হয়নি (বেতনসহ ধরা হলো) | দিনের হাজিরা নেই | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ দিনের হাজিরা হিসাব হয়নি (বেতনসহ ধরা হলো) |
| payroll.js:44 | manual days waiting approval | দিন হাতে লেখা, অনুমোদন বাকি | manual দিন approval বাকি | **wrong rule** - wrong rule (bn): Approve=অনুমোদন; inconsistent term: waiting rendered বাকি (=Due) | দিন হাতে লেখা, অ্যাপ্রুভ অপেক্ষায় | manual দিন approval অপেক্ষায় |
| payroll.js:45 | OT minutes waiting approval (not paid) | মিনিট ওভারটাইম অনুমোদনের অপেক্ষায় (ধরা হয়নি) | OT মিনিট approval বাকি | **wrong rule** - wrong rule (bn): Approve=অনুমোদনের; inconsistent term: waiting rendered বাকি (=Due) | মিনিট ওভারটাইম অ্যাপ্রুভের অপেক্ষায় (ধরা হয়নি) | OT মিনিট approval অপেক্ষায় |
| payroll.js:47 | Net pay is negative! | হাতে পাওয়া ঋণাত্মক! | Net negative! | **too literal / machine-translated** - too literal / bookish: ঋণাত্মক | হাতে পাওয়া মাইনাস! |  |
| payroll.js:47 | advance owed in register 35-1 - add it here to recover | ৩৫-১ রেজিস্টারে অগ্রিম বাকি - এখানে যোগ করলে কাটা হবে | ০২-৩-এ advance বাকি | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ ৩৫-১ রেজিস্টারে অগ্রিম বাকি - এখানে যোগ করলে কাটা হবে |
| payroll.js:59 | Salaries were paid - void the payments first | বেতন দেওয়া হয়ে গেছে - আগে পেমেন্ট বাতিল করুন | আগে payment বাতিল | **mixed-up grammar** - wrong rule (bn): Void=বাতিল; wrong rule (mix): Void=বাতিল; mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) | বেতন দেওয়া হয়ে গেছে - আগে পেমেন্ট ভয়েড করুন | আগে payment void |

### pinsign.js (1 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| pinsign.js:21 | This login is locked after wrong PINs - try in 10 minutes | এই লগইন ভুল পিনে তালাবদ্ধ — ১০ মিনিট পরে চেষ্টা করুন | এই login ভুল PIN-এ locked — ১০ মিনিট পরে চেষ্টা করুন | **too literal / machine-translated** - inconsistent term: lock rendered তালাবদ্ধ; too literal / bookish: তালাবদ্ধ | এই লগইন ভুল পিনে লক — ১০ মিনিট পরে চেষ্টা করুন |  |

### pos.js (3 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| pos.js:41 | Unit conversion saved | এককের হিসাব সংরক্ষিত | Unit conversion saved | **wrong rule** - wrong rule: common word translated into Bangla in bn mode + mix is an English copy | ইউনিট কনভার্সন সেভ হয়েছে | Unit conversion save হয়েছে |
| pos.js:59 | Selling expired stock is blocked (owner setting) — the sale was not made | মেয়াদোত্তীর্ণ মাল বিক্রি বন্ধ আছে (মালিকের সেটিং) — বিক্রি হয়নি | মেয়াদোত্তীর্ণ মাল বিক্রি বন্ধ (owner setting) — বিক্রি হয়নি | **too literal / machine-translated** - too literal/bookish (মেয়াদোত্তীর্ণ) + wrong rule: common word translated into Bangla in bn mode | মেয়াদ শেষ স্টক বিক্রি বন্ধ আছে (মালিকের সেটিং) — সেল হয়নি | মেয়াদ শেষ stock বিক্রি বন্ধ (owner setting) — sale হয়নি |
| pos.js:61 | This item is not for sale or has no selling price (Data needed) | এই আইটেম বিক্রির জন্য নয় বা দাম দেওয়া নেই (Data needed) | এই Item বিক্রির জন্য নয় বা দাম নেই (Data needed) | **inconsistent term across screens** - inconsistent term: Latin "(Data needed)" inside bn; other screens say (তথ্য লাগবে) | এই আইটেম সেলের জন্য নয় বা প্রাইস দেওয়া নেই (তথ্য লাগবে) | এই item sale-এর জন্য নয় বা price নেই (Data লাগবে) |

### purchase.js (2 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| purchase.js:55 | new average cost | নতুন গড় দাম | নতুন average cost | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price) | নতুন গড় কস্ট |  |
| purchase.js:56 | average cost not available | গড় দাম দেখার অনুমতি/তথ্য নেই | average cost দেখার permission/data নেই | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price) | গড় কস্ট দেখার অনুমতি/তথ্য নেই |  |

### recipebook.js (1 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| recipebook.js:30 | Printed recipe card no. | ছাপা রেসিপি কার্ড নং | Printed recipe card no. | **mixed-up grammar** - wrong rule (bn): Print=ছাপা; mixed-up grammar: mix is a plain English copy (not Bng/Eng) | প্রিন্ট রেসিপি কার্ড নং | ≈ print রেসিপি card নং |

### recipes.js (5 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| recipes.js:46 | avg cost | গড় দাম | avg cost | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price) | গড় কস্ট |  |
| recipes.js:47 | Some ingredients have no known cost — no total is shown | কিছু উপকরণের দাম জানা নেই — মোট বসানো হয়নি | কিছু ingredient-এর cost অজানা — total নেই | **too literal / machine-translated** - wrong rule (bn): Total=মোট; wrong term: Cost rendered as দাম (=Price) | কিছু উপকরণের কস্ট জানা নেই — টোটাল বসানো হয়নি |  |
| recipes.js:59 | An ingredient cost is unknown — set the cost first, then produce | কোনো কাঁচামালের দাম অজানা — আগে দাম বসান, তারপর উৎপাদন করুন | কোনো ingredient-এর cost অজানা — আগে cost বসান, তারপর production করুন | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price); inconsistent term: ingredient rendered কাঁচামাল | কোনো উপকরণের কস্ট অজানা — আগে কস্ট বসান, তারপর উৎপাদন করুন |  |
| recipes.js:62 | Production now needs a recipe — use "Produce from a recipe" | উৎপাদন এখন শুধু রেসিপি দিয়ে — "রেসিপি দিয়ে উৎপাদন" ব্যবহার করুন | Production এখন শুধু recipe দিয়ে | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ উৎপাদন এখন শুধু রেসিপি দিয়ে — "রেসিপি দিয়ে উৎপাদন" ব্যবহার করুন |
| recipes.js:63 | This item cannot be an ingredient (raw material / packaging / resale only) | এই আইটেম উপকরণ হতে পারে না (শুধু কাঁচামাল / প্যাকেজিং / রিসেল) | এই item ingredient হতে পারে না | **inconsistent term across screens** - inconsistent term: ingredient rendered কাঁচামাল | এই আইটেম উপকরণ হতে পারে না (শুধু উপকরণ / প্যাকেজিং / রিসেল) |  |

### reports.js (5 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| reports.js:24 | Staff attendance | কর্মীর হাজিরা | Staff হাজিরা | **inconsistent term across screens** - inconsistent term: staff rendered কর্মী/কর্মচারী | স্টাফের হাজিরা |  |
| reports.js:547 | Gross profit (costed part) | মোট লাভ (খরচ জানা অংশে) | Gross profit (costed part) | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ মোট লাভ (খরচ জানা অংশে) |
| reports.js:550 | Nothing in this period | এই সময়ে কিছু নেই | Nothing in this period | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ এই সময়ে কিছু নেই |
| reports.js:552 | by role right | ভূমিকার অনুমতিতে | by role right | **too literal / machine-translated** - too literal / bookish: ভূমিকা -> রোল | রোলের অনুমতিতে |  |
| reports.js:553 | within the limit / not recorded | সীমার ভেতরে / রেকর্ড নেই | within the limit / not recorded | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ সীমার ভেতরে / রেকর্ড নেই |

### rollout.js (2 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| rollout.js:34 | Reason for rejecting (required) | বাতিলের কারণ (আবশ্যক) | Reject-এর কারণ (আবশ্যক) | **too literal / machine-translated** - too literal / bookish: আবশ্যক | বাতিলের কারণ (লাগবেই) | Reject-এর কারণ (লাগবেই) |
| rollout.js:44 | Submit pending | জমা দেওয়া বাকি | Submit pending | **inconsistent term across screens** - inconsistent term: waiting rendered বাকি (=Due) | জমা দেওয়া অপেক্ষায় |  |

### salereturn.js (1 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| salereturn.js:31 | Reason for voiding (required) | বাতিলের কারণ (আবশ্যক) | Void-এর reason (আবশ্যক) | **too literal / machine-translated** - wrong rule (bn): Void=বাতিলের; too literal / bookish: আবশ্যক | ভয়েডের কারণ (লাগবেই) | Void-এর reason (লাগবেই) |

### salesx.js (2 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| salesx.js:23 | Employee benefits (report) | কর্মীর সুবিধা (রিপোর্ট) | Employee সুবিধা (report) | **inconsistent term across screens** - inconsistent term: employee rendered কর্মী | কর্মচারীর সুবিধা (রিপোর্ট) |  |
| salesx.js:42 | Employee | কর্মী | Employee | **inconsistent term across screens** - inconsistent term: employee rendered কর্মী | কর্মচারী |  |

### scan.js (4 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| scan.js:35 | Photos waiting to be sent | পাঠানো বাকি ছবি | পাঠানো বাকি photo | **inconsistent term across screens** - inconsistent term: waiting rendered বাকি (=Due) | পাঠানো অপেক্ষায় ছবি | পাঠানো অপেক্ষায় photo |
| scan.js:41 | You do not have the right to see the costs of this purchase bill. | এই ক্রয় বিলের দাম দেখার অধিকার আপনার নেই। | এই purchase bill-এর cost দেখার right আপনার নেই। | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price); inconsistent term: right/permission rendered অধিকার | এই ক্রয় বিলের কস্ট দেখার অনুমতি আপনার নেই। |  |
| scan.js:46 | Unit cost Tk | একক দাম ৳ | Unit cost Tk | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price) | একক কস্ট ৳ |  |
| scan.js:74 | The cost is not valid | দাম ঠিক নয় | Cost ঠিক নয় | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price) | কস্ট ঠিক নয় |  |

### setupadvisor.js (7 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| setupadvisor.js:15 | Is it all flowing? | সব ঠিকঠাক বইছে? | সব ঠিকঠাক বইছে? | **too literal / machine-translated** - too literal ("বইছে" = flowing) | সব ঠিকমতো চলছে? | সব ঠিকমতো চলছে? |
| setupadvisor.js:18 | Default | শুরুর মান | শুরুর value | **inconsistent term across screens** - inconsistent term across screens (switchboard/ownerboard say ডিফল্ট) | ডিফল্ট | Default |
| setupadvisor.js:20 | Apply recommended | প্রস্তাবিত প্রয়োগ | প্রস্তাবিত apply | **too literal / machine-translated** - too literal + wrong rule: common word translated into Bangla in bn mode (প্রয়োগ); mix half-English noun phrase | প্রস্তাবিতগুলো অ্যাপ্লাই করুন | Recommended apply করুন |
| setupadvisor.js:20 | Apply all recommended | সব প্রস্তাবিত প্রয়োগ | সব প্রস্তাবিত apply | **too literal / machine-translated** - too literal + wrong rule: common word translated into Bangla in bn mode | সব প্রস্তাবিত অ্যাপ্লাই করুন | সব recommended apply করুন |
| setupadvisor.js:21 | Apply anyway | তবুও প্রয়োগ | তবুও apply | **too literal / machine-translated** - too literal + wrong rule: common word translated into Bangla in bn mode | তবুও অ্যাপ্লাই করুন | তবুও apply করুন |
| setupadvisor.js:21 | Replace my value | আমার মানের বদলে প্রস্তাবিত | আমার value বদলে প্রস্তাবিত | **too literal / machine-translated** - too literal: reads as "recommended instead of my value", meaning unclear | আমার মান বদলে প্রস্তাবিতটা বসান | আমার value বদলে recommended বসান |
| setupadvisor.js:31 | Flowing ✓ | ঠিক বইছে ✓ | ঠিক বইছে ✓ | **too literal / machine-translated** - too literal ("বইছে") | ঠিকমতো চলছে ✓ | ঠিকমতো চলছে ✓ |

### stepw_common.js (2 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| stepw_common.js:41 | Role not found | ভূমিকা পাওয়া যায়নি | Role পাওয়া যায়নি | **too literal / machine-translated** - too literal / bookish: ভূমিকা -> রোল | রোল পাওয়া যায়নি |  |
| stepw_common.js:42 | An ingredient cost is unknown (empty or 0) - fill the cost first, then produce | কোনো উপকরণের দাম অজানা (ফাঁকা বা ০) — আগে দাম বসান, তারপর উৎপাদন | কোনো ingredient-এর cost অজানা (ফাঁকা বা ০) — আগে cost বসান, তারপর production | **too literal / machine-translated** - wrong term: Cost rendered as দাম (=Price) | কোনো উপকরণের কস্ট অজানা (ফাঁকা বা ০) — আগে কস্ট বসান, তারপর উৎপাদন |  |

### stock2.js (2 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| stock2.js:55 | Reason for rejecting (required) | নামঞ্জুরের কারণ (আবশ্যক) | Reject-এর reason (আবশ্যক) | **too literal / machine-translated** - too literal / bookish: আবশ্যক | নামঞ্জুরের কারণ (লাগবেই) | Reject-এর reason (লাগবেই) |
| stock2.js:95 | Selling expired stock is blocked (owner setting) | মেয়াদোত্তীর্ণ মাল বিক্রি বন্ধ আছে (মালিকের সেটিং) | মেয়াদোত্তীর্ণ মাল বিক্রি বন্ধ (owner setting) | **too literal / machine-translated** - too literal / bookish: মেয়াদোত্তীর্ণ -> মেয়াদ শেষ | মেয়াদ শেষ মাল বিক্রি বন্ধ আছে (মালিকের সেটিং) |  |

### stockx.js (4 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| stockx.js:28 | Source (purchase bill / GRN) | উৎস (ক্রয় বিল / GRN) | Source (purchase bill / GRN) | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ উৎস (ক্রয় বিল / GRN) |
| stockx.js:31 | Goods received (GRN / purchase) | মাল গ্রহণ (GRN / ক্রয়) | Goods received (GRN / purchase) | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ মাল গ্রহণ (GRN / ক্রয়) |
| stockx.js:40 | More than the bill received | বিলে যত এসেছে তার বেশি ব্যাচ করা যায় না | Bill এর চেয়ে বেশি | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en); mixed-up grammar: suffix spacing (Latin word + detached Bangla suffix) |  | Bill-এর চেয়ে বেশি |
| stockx.js:43 | Source not found (it must be submitted / posted) | উৎস পাওয়া যায়নি (জমা/পোস্ট হতে হবে) | Source পাওয়া যায়নি | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ উৎস পাওয়া যায়নি (জমা/পোস্ট হতে হবে) |

### switchboard.js (8 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| switchboard.js:12 | Search by name or key | নাম বা কী দিয়ে খুঁজুন | নাম বা key দিয়ে খুঁজুন | **inconsistent term across screens** - ambiguous: "কী" reads as the question word "what" | নাম বা কোড দিয়ে খুঁজুন | নাম বা key দিয়ে খুঁজুন |
| switchboard.js:15 | Blind count | অন্ধ গণনা | Blind count | **too literal / machine-translated** - too literal ("অন্ধ গণনা") | ব্লাইন্ড কাউন্ট | Blind count |
| switchboard.js:16 | Master "blind count" is OFF - these do nothing | মূল সুইচ "অন্ধ গণনা" বন্ধ — নিচের সুইচ কাজ করবে না | Master "blind count" OFF - এগুলো কাজ করবে না | **too literal / machine-translated** - too literal / bookish: অন্ধ -> ব্লাইন্ড | মূল সুইচ "ব্লাইন্ড গণনা" বন্ধ — নিচের সুইচ কাজ করবে না |  |
| switchboard.js:29 | Accounting | হিসাবরক্ষণ | Accounting | **too literal / machine-translated** - too literal/bookish (হিসাবরক্ষণ); ia.js uses "হিসাব ও অর্থ" for the same section | অ্যাকাউন্টিং | Accounting |
| switchboard.js:29 | Customers & tiers | গ্রাহক ও স্তর | Customer ও Tier | **wrong rule** - wrong rule: common word translated into Bangla in bn mode (গ্রাহক) | কাস্টমার ও টিয়ার | Customer ও Tier |
| switchboard.js:29 | People, attendance & payroll | কর্মী, হাজিরা ও বেতন | People, হাজিরা ও Payroll | **mixed-up grammar** - mixed-up grammar: mix starts with English "People" then Bangla; bn কর্মী vs স্টাফ elsewhere | স্টাফ, হাজিরা ও পে-রোল | Staff, হাজিরা ও Payroll |
| switchboard.js:29 | Locations | জায়গা | Locations | **inconsistent term across screens** - inconsistent term across screens (জায়গা here, লোকেশন in ia.js/nav.js) | লোকেশন | Locations |
| switchboard.js:29 | Look & feel | চেহারা / ব্যবহার | Look & feel | **too literal / machine-translated** - too literal/wrong: "ব্যবহার" = usage, not feel | দেখতে কেমন (থিম/রং) | Look & feel |

### tplpicker.js (2 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| tplpicker.js:14 | Applies to | কোথায় প্রযোজ্য | Applies to | **too literal / machine-translated** - too literal / bookish: প্রযোজ্য | কোথায় খাটে |  |
| tplpicker.js:19 | Plain text only | শুধু লেখা, কোনো ছবি বা কোড নেই | Plain text only | **mixed-up grammar** - mixed-up grammar: mix drops part of the meaning (much shorter than bn/en) |  | ≈ শুধু লেখা, কোনো ছবি বা কোড নেই |

### twofa.js (1 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| twofa.js:30 | Your role is expected to use 2FA - please turn it on now. | আপনার ভূমিকায় 2FA লাগার কথা — এখনই চালু করুন। | আপনার role-এ 2FA লাগার কথা — এখনই চালু করুন। | **too literal / machine-translated** - too literal / bookish: ভূমিকা -> রোল | আপনার রোলে 2FA লাগার কথা — এখনই চালু করুন। |  |

### phase74.sql (2 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| phase74.sql:27 | The direct production-in needs a reason note | সরাসরি "উৎপাদিত মাল তোলা"-য় কারণ (নোট) বাধ্যতামূলক | Direct "Production in"-এ reason (note) বাধ্যতামূলক | **too literal / machine-translated** - too literal / bookish: বাধ্যতামূলক | সরাসরি "উৎপাদিত মাল তোলা"-য় কারণ (নোট) জরুরি | Direct "Production in"-এ reason (note) জরুরি |
| phase74.sql:50 | Depreciation | অবচয় |  | **too literal / machine-translated** - too literal / bookish: অবচয় | ডেপ্রিসিয়েশন |  |

### phase76.sql (3 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| phase76.sql:28 | Web form needs a captcha pass | ওয়েব ফর্মে ক্যাপচা বাধ্যতামূলক | Web form-এ captcha বাধ্যতামূলক | **too literal / machine-translated** - too literal / bookish: বাধ্যতামূলক | ওয়েব ফর্মে ক্যাপচা জরুরি | Web form-এ captcha জরুরি |
| phase76.sql:36 | Customer phone/address only for authorised people | গ্রাহকের ফোন/ঠিকানা শুধু অনুমতিপ্রাপ্তদের | Customer ফোন/ঠিকানা শুধু অনুমতিপ্রাপ্তদের | **too literal / machine-translated** - wrong rule (bn): Customer=গ্রাহকের; too literal / bookish: অনুমতিপ্রাপ্ত | কাস্টমারের ফোন/ঠিকানা শুধু অনুমতি-পাওয়াদের | Customer ফোন/ঠিকানা শুধু অনুমতি-পাওয়াদের |
| phase76.sql:44 | Web form public URL (Edge function) | ওয়েব ফর্মের পাবলিক ঠিকানা (Edge ফাংশনের URL) | Web form public URL (Edge function) | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ ওয়েব ফর্মের পাবলিক ঠিকানা (Edge ফাংশনের URL) |

### phase82.sql (1 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| phase82.sql:37 | Production taking an ingredient below zero: off, warn or reason required | উৎপাদনে কাঁচামাল ঋণাত্মক হলে কারণ: বন্ধ / warn / required | Production-এ ingredient negative হলে reason: off / warn / required | **too literal / machine-translated** - inconsistent term: ingredient rendered কাঁচামাল; too literal / bookish: ঋণাত্মক | উৎপাদনে উপকরণ মাইনাস হলে কারণ: বন্ধ / warn / required |  |

### phase85.sql (3 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| phase85.sql:66 | Manual journal guard: off or on | হাতে লেখা journal এর পাহারা: বন্ধ / চালু | Manual journal guard: off / on | **too literal / machine-translated** - too literal / bookish: পাহারা -> গার্ড; mixed-up grammar: suffix spacing (Latin word + detached Bangla suffix) | হাতে লেখা journal-এর গার্ড: বন্ধ / চালু |  |
| phase85.sql:69 | Scheduled auto posting (scheduler) | নির্ধারিত সময়ে নিজে নিজে posting (scheduler) | Scheduled auto posting (scheduler) | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ নির্ধারিত সময়ে নিজে নিজে posting (scheduler) |
| phase85.sql:72 | Alert for documents waiting longer than this many days | কত দিনের বেশি পুরোনো বাকি document এ সতর্কতা | কত দিনের বেশি পুরোনো pending document এ alert | **mixed-up grammar** - inconsistent term: waiting rendered বাকি (=Due); mixed-up grammar: suffix spacing (Latin word + detached Bangla suffix) | কত দিনের বেশি পুরোনো অপেক্ষায় document-এ সতর্কতা | কত দিনের বেশি পুরোনো pending document-এ alert |

### phase87.sql (1 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| phase87.sql:35 | Selling expired stock: off, warn or refuse | মেয়াদোত্তীর্ণ মাল বিক্রি: বন্ধ / warn / block | Expired মাল বিক্রি: off / warn / refuse | **too literal / machine-translated** - too literal / bookish: মেয়াদোত্তীর্ণ -> মেয়াদ শেষ | মেয়াদ শেষ মাল বিক্রি: বন্ধ / warn / block |  |

### phase94.sql (1 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| phase94.sql:46 | Hours an old-dated sale may skip the stock guard | পুরোনো সময়ের বিক্রিতে স্টক-পাহারা কত ঘণ্টা পর্যন্ত ঢিলা | পুরোনো সময়ের sale-এ stock-পাহারা কত ঘণ্টা পর্যন্ত ঢিলা | **too literal / machine-translated** - too literal / bookish: পাহারা -> গার্ড | পুরোনো সময়ের বিক্রিতে স্টক-গার্ড কত ঘণ্টা পর্যন্ত ঢিলা |  |

### phase95.sql (1 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| phase95.sql:40 | Cash drawer: connection type | ক্যাশ ড্রয়ার: সংযোগের ধরন | Cash drawer: connection type | **mixed-up grammar** - mixed-up grammar: mix is a plain English copy (not Bng/Eng) |  | ≈ cash ড্রয়ার: সংযোগের ধরন |

### phase97.sql (1 findings)

| file:line | en | current bn | current mix | verdict | suggested bn | suggested mix |
|---|---|---|---|---|---|---|
| phase97.sql:95 | Approval before a landed cost is posted: warn / required | Landed cost পোস্টের আগে অনুমোদন: সতর্কতা / বাধ্যতামূলক | Landed cost post-এর আগে approval: warn / required | **too literal / machine-translated** - wrong rule (bn): Approve=অনুমোদন; inconsistent term (Latin script in bn): cost; too literal / bookish: বাধ্যতামূলক | Landed cost পোস্টের আগে অ্যাপ্রুভ: সতর্কতা / জরুরি |  |
