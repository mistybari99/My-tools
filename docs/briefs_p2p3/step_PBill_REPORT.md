# Step PBill REPORT: purchase bill Print / Share / Download / Email / SMS / WhatsApp (bos104)

Branch fix/phase-PBill (from integration/p72-p79). WEB ONLY, no SQL. Live DB, main and other worktrees not touched. No real person names (test data only).

## What was built
* New file `web/purchaseprint.js` (a decorator). `purchase.js` is NOT edited (the Cat agent edits it). Only `web/ia.js` (one rec appended at the end, `purchaseprint`) and `web/index.html` (script tag appended at the end) changed.
* On the purchase bill page (`#/purchase/<id>`) a `Print / Send` card (Print, Share, Download, Email · SMS · WhatsApp) is added by a MutationObserver on `#app`; not added on the editor, not twice. API `B.purchaseprint.open(id)`. Page `#/purchaseprint` lists recent bills with a Print button (reachable even if the decorator fails; also in the IA registry).
* The sheet: Print, Print GRN (non-return bills), Share, Download, supplier phone / email (phone prefilled from the supplier list when known), Email, SMS, WhatsApp. data-act prefix `pbp_`.
* Data: `purchase_get(p_id)` only (same RPC the bill page uses). Layout: `B.tpl.ensure(sb)` then `B.tpl.render('purchase_bill' | 'grn', data, undefined, {lang, loc, shop})`. Nothing chosen (null), `B.tpl` missing or throwing: a built-in plain layout (new, in the new file), so Print always works.
* Print: hidden iframe + `print()` (same idea as `B.tpl.print`); no printer / print throws: a friendly line pointing to Share / Download. Email / SMS / WhatsApp are device-side links (`mailto:`, `sms:`, `https://wa.me/<n>?text=` via `B.tpl.waUrl`); nothing is sent by the app.
* Cost secrecy: if `purchase_get` / `purchase_list` refuse (no purchase permission), nothing is shown or built (toast only, no sheet, no template fetch). Fields are picked one by one: bill rate and amount only (a supplier-side paper), never a sale price or margin. GRN carries quantities only (no rate, amount, total).
* Status: DRAFT (not posted) / VOID shown in a red band on the print page, in the message text and mail subject; paid / due only for posted bills.
* Language: English mode all English. Bangla mode keeps Bill, Supplier, Date, Qty, Rate, Total, Paid, Due in English on the printed page; UI strings have bn / en / mix. Existing text never rewritten.

## যাচাই হয়েছে (চালিয়ে দেখা)
* `node --check` of every web/*.js ok; no conflict markers.
* `tests/web/purchaseprint_test.js` (new, mocked rpc): **85 pass / 0 fail**: template used when chosen (purchase_bill and grn), built-in when nothing chosen / `B.tpl` absent / throwing, XSS escaped (`<img onerror>` in line and note), refusal gives no sheet / no print / no template fetch / no list rows, DRAFT and VOID marking, WhatsApp / SMS / mailto links and bad number / address handling, share-to-copy fallback, download file name, no-printer notice, English mode no Bangla letters, bn / mix common words, decorator injects once and not on the editor.
* `tests/web/purchaseprint_pw_test.js` (new, real app in Chromium at 360 px, mocked rpc): **27 pass / 0 fail**, no page errors, no horizontal overflow (bill page, sheet, route page, Bangla sheet, printed page at 360 px); button group on the real `purchase.js` bill page; built-in and chosen-template print pages generated, VOID band present; refusal shows nothing. Screenshots `tests/web/pbill_*.png`.
* Existing tests (run as copies pointed at this worktree): tpl_test 2248 / 0, tplwire_test 66 / 0, invoiceview_test 65 / 0, lang_en_test 91 English strings 0 Bangla, purchase_test errors none / 0 failures, purchase3_test 0 failures, ia_test 0 failures, nav2_test 0 failures.

## পড়ে বোঝা (read / reasoned only)
* `nav_test` times out at the drawer English-language click, the same on HEAD without my changes (pre-existing, not caused by this step).
* Print count inside the iframe is not measured in Chromium (headless print is a no-op); the page handed to the iframe is checked instead.
* The "Tax ID: [Tax ID]" placeholder line seen on the formal template page is the template engine's own shop header, not this step.

## যাচাই হয়নি (not verified)
* Real printers (A4 / A5), real phone print dialog, and WhatsApp / SMS / Email apps opening with the text.
* Supplier phone prefill with real supplier rows (tested with a mocked supplier list); `navigator.share` on a real phone.
* Real role refusal on a live database (tested with a mocked "not allowed" error).
