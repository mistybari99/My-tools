# Step Tpl REPORT: selectable templates per document type (phase 93)

Branch fix/phase-Tpl (from integration/p72-p79). 20 document types x 5-6 designs = 120 templates. Forms/printbooks/forms_factory untouched. pos.js and invoiceview.js untouched.

## Files
- supabase/phase93.sql + phase93_test.sql: table doc_template_choice, RPCs set_doc_template (owner only, null clears, audited) and get_doc_templates. Additive, paste-twice safe, guarded on phases 72..79 and 88. No row = no choice = today's output.
- web/tpl_registry.js (engine, registry, barcode EAN-13/Code 39 SVG), tpl_docs.js (16 document specs), tpl_labels.js (barcode labels, price tags), tpl_msgs.js (message texts), tpl_samples.js (invented sample data), tplpicker.js (owner page #/templates; data-act names all tpl93_*).
- web/ia.js: one rec line 'templates' (owner, group cust). web/index.html: six script tags appended after guards.js.
- tests/web/tpl_test.js (2134 checks), tests/web/tplpicker_test.js (52 checks).

## For the Inv agent (post-sale invoice view)
BOS.tpl.render('pos_receipt', data, templateId?, { lang, loc, shop }) returns an HTML string (style + div, with @page for the paper size), or **null when the owner chose nothing: then keep printing what you print today**. BOS.tpl.printHTML(...) gives a full document; BOS.tpl.print(...) prints through a hidden iframe. Load the owner choices once with BOS.tpl.load(sb, locationId). pos_receipt data: { no, date, cashier, location, customer:{name,phone,address}, items:[{name,qty,price,amount}], subtotal, discount, vat, total, paid, change, due, note }. Other doc types' fields: see tpl_samples.js. Message types (msg_invoice, msg_due) return PLAIN TEXT; options channel sms|whatsapp|email.
Shop logo / name / footer / tax id: BOS.tpl.setShop({name, logo, address, phone, taxId, footer}) (the picker reads settings keys business_name, shop_logo, invoice_footer, tax_id, shop_address, shop_phone when present; otherwise placeholders [Shop name] / [Tax ID] and "Thank you").

## Document types x template names
| Document type | Templates (id (name)) | Suggested |
|---|---|---|
| pos_receipt (Receipt) | thermal80_slip (Centered slip · Thermal 80 mm); thermal80_receipt (Plain receipt · Thermal 80 mm); thermal58_slip (Centered slip · Thermal 58 mm); a4_formal (Formal · A4); a4_modern (Modern · A4); a5_split (Split header · A5) | thermal80_slip |
| sale_return (Credit note / sale return) | thermal80_slip (Centered slip · Thermal 80 mm); thermal58_receipt (Plain receipt · Thermal 58 mm); a4_classic (Classic · A4); a4_minimal (Minimal · A4); a5_boxed (Boxed · A5); a4_formal (Formal · A4) | thermal80_slip |
| order_confirm (Order confirmation) | a4_modern (Modern · A4); a4_classic (Classic · A4); a5_split (Split header · A5); a4_minimal (Minimal · A4); a5_compact (Compact · A5); thermal80_slip (Centered slip · Thermal 80 mm) | a5_split |
| delivery_challan (Delivery challan) | a4_classic (Classic · A4); a4_boxed (Boxed · A4); a5_split (Split header · A5); a4_formal (Formal · A4); a4_minimal (Minimal · A4); thermal80_slip (Centered slip · Thermal 80 mm) | a4_formal |
| purchase_bill (Purchase bill) | a4_classic (Classic · A4); a4_formal (Formal · A4); a4_modern (Modern · A4); a4_compact (Compact · A4); a5_boxed (Boxed · A5); a4_minimal (Minimal · A4) | a4_formal |
| grn (Goods received note (GRN)) | a4_classic (Classic · A4); a4_boxed (Boxed · A4); a4_formal (Formal · A4); a4_minimal (Minimal · A4); a5_compact (Compact · A5); a4_modern (Modern · A4) | a4_classic |
| stock_transfer (Stock transfer challan) | a4_classic (Classic · A4); a4_boxed (Boxed · A4); a5_split (Split header · A5); a4_formal (Formal · A4); a4_minimal (Minimal · A4); thermal80_slip (Centered slip · Thermal 80 mm) | a4_classic |
| stock_count (Stock count sheet) | a4_boxed (Boxed · A4); a4_minimal (Minimal · A4); a4_compact (Compact · A4); a5_classic (Classic · A5); a4_modern (Modern · A4); a4_formal (Formal · A4) | a4_boxed |
| wastage_sheet (Wastage sheet) | a4_classic (Classic · A4); a4_minimal (Minimal · A4); a4_boxed (Boxed · A4); a4_compact (Compact · A4); a5_split (Split header · A5); a4_formal (Formal · A4) | a4_classic |
| production_slip (Production slip) | a5_classic (Classic · A5); a5_boxed (Boxed · A5); a4_modern (Modern · A4); thermal80_slip (Centered slip · Thermal 80 mm); a4_minimal (Minimal · A4); a5_compact (Compact · A5) | a5_classic |
| recipe_card (Recipe card) | a5_boxed (Boxed · A5); a4_classic (Classic · A4); a4_modern (Modern · A4); a5_minimal (Minimal · A5); a4_formal (Formal · A4); a6_compact (Compact · A6) | a5_boxed |
| pay_slip (Pay slip) | a5_classic (Classic · A5); a4_formal (Formal · A4); a5_modern (Modern · A5); a5_boxed (Boxed · A5); a4_minimal (Minimal · A4); thermal80_slip (Centered slip · Thermal 80 mm) | a5_classic |
| partner_statement (Partner settlement statement) | a4_classic (Classic · A4); a4_formal (Formal · A4); a4_modern (Modern · A4); a4_minimal (Minimal · A4); a4_boxed (Boxed · A4); a4_compact (Compact · A4) | a4_formal |
| daily_report (Daily report) | thermal80_slip (Centered slip · Thermal 80 mm); a4_classic (Classic · A4); a4_modern (Modern · A4); a4_compact (Compact · A4); a4_minimal (Minimal · A4); a4_formal (Formal · A4) | thermal80_slip |
| pnl (Profit & loss) | a4_classic (Classic · A4); a4_formal (Formal · A4); a4_modern (Modern · A4); a4_minimal (Minimal · A4); a4_boxed (Boxed · A4); a4_compact (Compact · A4) | a4_classic |
| balance_sheet (Balance sheet) | a4_formal (Formal · A4); a4_classic (Classic · A4); a4_modern (Modern · A4); a4_minimal (Minimal · A4); a4_boxed (Boxed · A4); a4_compact (Compact · A4) | a4_formal |
| barcode_label (Barcode item label) | label_50x30 (50 x 30 mm roll); label_38x25 (38 x 25 mm small); label_40x20 (40 x 20 mm barcode only); label_58x40 (58 x 40 mm roll); sheet_70x37 (A4 sheet 3 x 8); label_100x50 (100 x 50 mm large) | label_50x30 |
| price_tag (Price tag sticker) | tag_45x30 (45 x 30 mm small tag); tag_60x40 (60 x 40 mm boxed tag); shelf_70x35 (70 x 35 mm shelf tag); hang_30x50 (30 x 50 mm hanging tag); sale_50x30 (50 x 30 mm sale tag); sheet_105x50 (A4 sheet 2 x 6) | shelf_70x35 |
| msg_invoice (Invoice message (SMS / WhatsApp / Email)) | short (Short); medium (Medium); detailed (Detailed); friendly (Friendly); formal (Formal); bilingual (Bilingual (Bangla + English)) | medium |
| msg_due (Due reminder (SMS / WhatsApp / Email)) | short (Short); medium (Medium); detailed (Detailed); friendly (Friendly); formal (Formal); bilingual (Bilingual (Bangla + English)) | friendly |

Messages: variants short, medium, detailed, friendly, formal, bilingual (Bangla + English), for SMS / WhatsApp / Email. Labels: 50x30, 38x25, 40x20, 58x40 roll, A4 3x8 sheet, 100x50. Price tags: 45x30, 60x40, 70x35 shelf, 30x50 hanging, 50x30 sale (strike-through old selling price), A4 2x6 sheet.
Design basis (design-guide skill applied): one accent (green 0f6b4f on white, AA contrast), tinted greys, black on white for thermal; no status colour used alone; sale tag red is paired with the word SALE. design-assets skill: no raster/vector asset was needed (pure CSS/SVG bars), so Recraft was not used; no logo was generated.

## যাচাই হয়েছে (verified by running)
- SQL: phase93_test.sql 17 pass / 0 fail on a fresh Postgres 16 build (owner-only set, staff refused, bad ids/location refused, location beats all-locations, clear, audit rows, no direct table writes, grants, paste-twice). Older suite phase88_test.sql on a fresh build including phase93: 47 pass / 0 fail.
- tpl_test.js: all 120 templates render in bn/en/mix from sample data; @page sizes (80/58 mm, A4, A5, label sizes); every string XSS-escaped (poisoned data and shop settings); injected cost/cogs/margin/profit keys never appear; unsafe logo URL dropped; English output has zero Bangla letters; EAN-13 and Code 39 bars equal the python-barcode reference strings; no choice returns null; choice resolution; email subject / SMS single line / header-injection stripping.
- tplpicker_test.js: page for bn/mix/en, set/clear/location rpc arguments, server refusal shows error (no success toast), missing SQL notice, XSS in location names, unique data-act names, ia + index wiring.
- lang_en_test.js and guards_test.js still pass. A Chromium render (my own check, not committed) of 20 sample templates showed layouts correct after I fixed two CSS leaks between label sizes.

## পড়ে বোঝা (read / reasoned only)
- The A4/A5 ratio scaling in the picker preview (fit()) was not run in a real phone browser; only the markup was checked.
- Existing language rule: Bangla mode text is Bangla with common words English; wording of Bangla labels is mine and should be read by the owner.
- Settings key names for shop logo / footer / tax id (shop_logo, invoice_footer, tax_id, shop_address, shop_phone) are guesses; business_name exists in schema. Missing keys fall back to placeholders.

## যাচাই হয়নি (not verified)
- Real thermal 58/80 mm printer output, real A4/A5 printing, label stickers on a roll printer and barcode scanning of the printed bars.
- Real phone browser, swipe behaviour (the carousel uses Previous/Next buttons and chips, no swipe gesture), dark mode of the picker page.
- ia_test.js / nav_test.js (playwright, need port 8472 used by another run): not run.
- SMS delivery, Unicode SMS segment cost, WhatsApp / Email sending (texts only).
- Nothing is wired into pos.js / invoiceview.js / purchase.js etc.: those screens still print as before until their owners call BOS.tpl.render.
