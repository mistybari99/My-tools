# Step TplInv REPORT: template system wired into the customer-facing outputs (bos98)

Branch fix/phase-TplInv (from integration/p72-p79). WEB ONLY, no SQL. Live DB, main and other worktrees not touched. No real person names (test data only).

## Rule kept everywhere
If `B.tpl` is absent, or `B.tpl.render` / `printHTML` returns null (the owner chose nothing), or anything throws, or the choices could not be fetched: the output is exactly what it was before. Every edit is tagged `bos98` and guarded by `if (B.tpl)`. Existing text is never rewritten. Customer-facing data given to templates has no cost field (and `B.tpl` strips cost-like keys again as a safety net).

## What is wired
* `web/tpl_registry.js`: new `B.tpl.ensure(sb)`: fetches the owner choices (`get_doc_templates`) ONCE per session, 2-second cap, cached; a failure or timeout is remembered for 30 s and never throws (callers then keep today's output). `B.tpl.ensureReset()` for tests.
* `web/invoiceview.js` (post-sale invoice view): choices are warmed when the sheet opens.
  * Print: `pos_receipt` template via `B.tpl.print` (hidden iframe). Nothing chosen: old `B.invoice` path.
  * Download: the chosen receipt page as the .html file; else today's file.
  * SMS / WhatsApp / Email buttons: `msg_invoice` template text per channel (sms single line, whatsapp, email with Subject split into the `mailto:` subject/body). WhatsApp link built with `B.tpl.waUrl(text)` plus the customer number. Nothing chosen: today's text. Copy text / Share are unchanged.
  * On-screen card is unchanged (an A4 template does not fit a 360 px phone; the card stays the same for everyone).
* `web/salereturn.js`: after a return is recorded, if a `sale_return` template is chosen the slip is printed (items returned, value, refund; no cost). Nothing chosen: nothing printed, as before.
* `web/payroll.js`: pay slip print (`ln_slip`) uses a chosen `pay_slip` template (earnings, deductions, net); else today's slip.
* `web/invoice.js`: barcode label print (`iv_lb_print`, the label page; `barcode.js` itself is only the scanner and prints nothing) uses a chosen `barcode_label` template (name, barcode, SELLING price, copies); else today's label sheet. The labels page warms the choice cache.
* Purchase bill print: `purchase.js` has NO print path today, so there is nothing to hook without a large edit. Not wired (stated plainly).

## Language rule
No new visible text was added (the templates carry their own English / Bangla-with-common-English-words / mix labels). The test checks English mode: SMS, WhatsApp, Email and the receipt page contain no Bangla letters.

## যাচাই হয়েছে (চালিয়ে দেখা)
* node syntax check of every web/*.js: ok.
* `tests/web/tplwire_test.js` (new): **66 pass / 0 fail**, in bn, en, mix: (a) no `B.tpl` vs nothing chosen: identical SMS / WhatsApp / Email links, identical print calls, identical downloaded file; (b) chosen templates: receipt page uses `data-tpl="a4_modern"`, name `<img onerror>` is escaped, SMS one line, WhatsApp link `https://wa.me/<number>?text=` equals the template text, Email subject/body split, download is the template page; (c) every key handed to the templates checked against the cost pattern (none), cost values (61, 60) absent from output; choices fetched once for 5 outputs; hung fetch falls back within the 2 s cap (about 2.0 s); rpc throwing, and a broken `B.tpl`, give today's output.
* `invoiceview_test.js` 65 / 0; `invoiceview_pw_test.js` (360 px, real pos.js + invoice.js) 37 / 0, no page errors; `tpl_test.js` 2248 / 0; `tplpicker_test.js` 52 / 0; `lang_en_test.js` 87 English strings, 0 Bangla; `guards_test.js` 35 / 0.
* Existing tests unchanged, run as copies pointed at this worktree: pos_units 0 failures, posfail 23 / 0, salereturn 0 failures, barcode 0 failures, nav no errors payroll 0 failures, invoice 0 failures, ia 0 failures, pos2 output identical with and without my edits (one old FAIL "old queued payload sent" exists on HEAD already, same as the Inv report).
* No conflict markers in web, docs, tests.

## পড়ে বোঝা (read / reasoned only)
* The salereturn slip, pay slip and barcode label hooks are small guarded blocks that were syntax-checked, and the existing tests for those screens pass with `B.tpl` present but nothing chosen; they were not driven with a chosen template in a test (the choice-to-print path is the same `B.tpl` calls that the invoiceview test exercises).
* Mapping of payroll fields to the `pay_slip` sections (labels reuse existing payroll words) and of the return value (`amount x discount factor`) is by reading.

## যাচাই হয়নি (not verified)
* Real printers (thermal, A4/A5, label rolls), real phone browser print dialog, WhatsApp / SMS / Email apps opening with the text.
* Purchase bill print is not wired (no print path exists today).
