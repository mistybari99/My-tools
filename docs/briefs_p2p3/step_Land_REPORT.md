# Step Land (phase97) - Landed cost, সব practical option সহ (audit a1-F9)
Branch `fix/phase-Land` (integration/p72-p79 + INT2 phase89 merge করা; ia.js-এর conflict-marker fix-ও integration থেকে এসেছে)। Files: `supabase/phase97.sql`, `phase97_test.sql`, `web/landed.js`, `tests/web/landed_test.js`, `landed_pw_test.js`, ia.js-এ ১টি rec (শেষে), index.html-এ ১টি script tag (শেষে)।
Paste order: ... phase91, phase89, **phase97**। phase89 আবার paste করলে phase97 আবার paste করতে হবে (নিচে)।

## কী বানানো হয়েছে
* Default = আজকের আচরণ: `landed_cost_mode = off`, তখন item cost = বিলের দাম; save/post refuse (`landed_off`), preview চলে।
* Rules: `landed_cost_mode` off|manual|per_bill|per_shipment; `landed_alloc_default` value|qty|weight|volume|manual|equal; `landed_late_mode` split_remaining_and_cogs|post_to_remaining_stock|variance_account; `landed_cost_requires_approval` warn|required; `landed_reminder_on` (off), `landed_reminder_days`, `landed_base_currency`। সব bn/mix/en।
* Tables (browser-এর কাছে বন্ধ, RLS, শুধু function): `cost_charge_types` (15 seed: freight, duty, insurance, clearing, loading, unloading, bank, packaging, vat_nonrec, delivery, fx_diff, other = capitalise; vat_recov = recoverable tax; freight_exp, bank_exp = expense only; owner নতুন যোগ + treatment বদলাতে পারেন), `landed_costs` (draft/approved/posted/void), `landed_cost_docs` (bill বা GRN), `landed_cost_lines` (currency + rate), `landed_cost_basis` (line-প্রতি weight/volume/%), `landed_cost_alloc` ও `landed_cost_stock` (APPEND-ONLY), `item_logistics`, `landed_supplier_flags`, `landed_skips`।
* Stock: posted cost average cost-এ যায় ledger-এর `cost_adjust` জোড়া দিয়ে (on-hand qty পুরনো average-এ out, নতুন average-এ in, ref_type landed)। ledger immutable ও replayable থাকে (stock_reconcile, inventory_vs_gl বদলানো লাগেনি); জোড়ার মান = ঠিক যোগ হওয়া অঙ্ক।
* Journal: `_acct_docs`-এ `landed_cost` ও `landed_cost_void` (counter entry): Dr inv_raw/inv_pack/inv_finished (shelf-এ যা আছে), Dr landed_variance (যা বিক্রি হয়ে গেছে), Dr expense/vat_input (capitalise নয় এমন), Cr landed_payable/pay_cash/pay_bank/pay_mobile (supplier party সহ)। নতুন mapping key: vat_input (1240), landed_payable (2150), landed_variance (5150)।
* RPC: landed_preview (write নেই; সব method পাশাপাশি), landed_recommendation, landed_save (client_id idempotent), landed_approve, landed_post (re-post = 0), landed_void, landed_get, landed_list, landed_reminders, landed_return_info, landed_info, landed_resolve_docs, landed_charge_type_save, landed_logistics_set, landed_supplier_flag_set, landed_skip।
* Safety: cost right (view_cost) + grant `landed_entry` / `landed_approve` (role default: purchasing, management)। posted bill-এর landed cost থাকলে bill void trigger-এ আটকায়। phase89 আবার paste হয়ে block হারালে landed_post `journal_not_ready` দিয়ে থামে (stock বদলায় না)। accounting start-এর আগের তারিখে post হয় না।
* Weight/volume অনুমান হয় না: এককে kg/g/ton বা l/ml থাকলে সেখান থেকে, নইলে item বা line-এ লেখা; জানা না থাকলে method "?" ও list-এ কোন item।
* Web `#/landed`: list + settings (owner), bill বাছা, editor (charge list, currency+rate, method chip, লাইভ পাশাপাশি preview, ★ প্রস্তাবিত + কারণ, weight/volume/% box, late chip), save/approve/post/void, "যোগ হয়নি?" list (`#/landed/rem`), return-এর landed view। purchase.js বদলানো হয়নি: bill পাতায় guarded "Landed cost যোগ" button (MutationObserver) + menu entry।

## পরিস্থিতি -> option -> প্রস্তাবিত
| পরিস্থিতি | built-in option | প্রস্তাবিত |
|---|---|---|
| আমদানি করা মাল | mode per_shipment, একাধিক bill/GRN এক lot, shipment ref | per_shipment, প্রতি charge-এ নিজের method |
| ভাড়া / transport in | charge freight | ওজন (সব line-এ জানা থাকলে), নইলে দাম |
| মাল তোলা-নামানো | loading / unloading | পরিমাণ (একক এক রকম হলে) |
| শুল্ক | duty | দাম |
| বীমা, clearing, bank/LC | insurance, clearing, bank | দাম (সাধারণ bank fee হলে bank_exp = শুধু খরচ) |
| lot-এর জন্য কেনা packaging | packaging | পরিমাণ |
| ফেরত-অযোগ্য কর | vat_nonrec (capitalise); ফেরতযোগ্য = vat_recov (item cost-এ নয়) | যেটা সত্যি, owner treatment বদলাতে পারেন |
| স্থানীয় কেনায় delivery | delivery, mode manual | পরিমাণ |
| মাল আগেই বিক্রি/ব্যবহার, দেরিতে bill | late mode: ভাগ / সব বাকি stock / variance | ভাগ (সব বিক্রি হয়ে গেলে variance) |
| এমন কেনার return | return supplier-কে bill দামে credit, landed অংশ purchase variance-এ (switch acct_purchase_variance); landed_return_info দেখায়; supplier ভাড়া ফেরত দিলে ঋণাত্মক charge | variance switch চালু |
| বিদেশি মুদ্রা | charge-এ ccy + rate (rate লাগে, অনুমান নয়), fx_diff | rate নিজে লেখা |
| bill vs lot | per_bill (১ bill) / per_shipment / manual | আমদানিতে per_shipment |
| ভাগের পদ্ধতি | value, qty, weight, volume, manual %, equal; charge-প্রতি override | জানা থাকলে weight (ভাড়া), নইলে value |
| অনুমোদন | warn (হলুদ সতর্কতা) বা required (বানানো লোক নিজে approve করতে পারে না, owner পারেন) | বড় অঙ্কে required |

## যাচাই হয়েছে (চালিয়ে দেখা)
* `phase97_test.sql` ফ্রেশ বিল্ডে **155 pass / 0 fail** (দুবার paste সহ): হাতে-গোনা (freight 100: qty 40/60, value 25/75, weight 62.5/37.5, equal 50/50; avg 13.625 ও 22.25; discount 0.9 + USD 3 x 100 + কর 50 + bank fee 20; late split 30/20 avg 25, post_to_remaining avg 28.333333, variance_account avg 20; void-এ 3/6 অংশ ফেরে avg 20; per_shipment দুই bill 40/40 avg 24; GRN + ঋণাত্মক charge; return info 14.5), valuation = GL, inventory_vs_gl agree, trial balance balanced, stock_reconcile 0, re-post 0, append-only/lock, cost secrecy, তিন ভাষা (English-এ বাংলা অক্ষর নেই)।
* পুরনো ৬৭টি suite (প্রতিটি phase97 ছাড়া ও সহ আলাদা clone-এ): মোট 5762 pass / 34 fail, সব fail জানা baseline (phase8 T1, 10 T12, 15 T0, 19 T0, 21/21b T1, 22, 23 T0, 47 x2, 72, 73 x2, 76) — phase97 দিয়ে নতুন fail নেই, শুধু phase89_test P2 নিচে।
* Node `landed_test.js` 18/0; Playwright 360px `landed_pw_test.js` 65 assertion / 0 fail, page error নেই (list, off, bill বাছা, লাইভ preview, unknown weight, late, approve/post/void, reminder, settings, bill-পাতার link, return, bn/mix/en, overflow নেই)। ia_test, lang_en_test, nav_test চালিয়ে 0 fail।

## পড়ে বোঝা (চালানো হয়নি)
* Supabase-এ pg_cron/autopost tick: journal tick-এর মাধ্যমে (acct_post_pending) হয়, আমি tick হাতে চালিয়েছি।
* আসল ফোনে ব্যবহার, ধীর নেটওয়ার্কে debounce preview।

## যাচাই হয়নি / সীমা
* **phase89 সম্পর্ক**: phase97 শুধু `_acct_docs` re-create করে (phase89-এর শরীর + 2 bos97 block, সব পুরনো tag আছে)। phase89 আবার paste হলে block চলে যায় -> phase97 আবার paste; `supabase/phase89_test.sql` P2 ("second paste identical") phase97 থাকা DB-তে fail করে (phase97 ছাড়া 64/0)। স্থায়ী সমাধান: INT2 phase89-এ ওই দুই block ঢুকিয়ে নেবে। stock_post, purchase function বদলানো হয়নি।
* production-এ ব্যবহৃত অংশ finished goods-এ যায় না, variance খাতে যায় (late mode); lot-এর "কতটা বাকি" = min(on-hand, lot qty), FIFO অনুমান নয়, এক জায়গার stock।
* একটি landed cost = এক জায়গার bill; GRN শুধু linked bill হয়ে আসে (bill ছাড়া GRN-এ দাম নেই)।
* GRN বাছার UI নেই (server resolve আছে: `landed_resolve_docs`); screen-এ bill বাছা হয়।
* Phone-impossible: pg_cron scheduler, role grant দেওয়া owner-এর কাজ (Permissions screen)।

## ia.js / index.html
`rec('landed', 'purch', [...], { icon: 'doc', ok: own || GF.landed_entry || GF.landed_approve, ... })` ia.js-এর শেষ rec; `<script src="landed.js"></script>` index.html-এর শেষে। GF-এ grant flag landed.js নিজে probe করে (nav.js বদলানো হয়নি)।
