# Language and numbering standard (Islamia BOS)

## 1. Names that are fixed (never translated, never re-spelled, in every language mode)
| Where | Bangla | Latin |
|---|---|---|
| Hub brand | ইসলামিয়া মিষ্টি ঘর | **ISLAMIYA MISTY GHAR** |
| Brand 2 | মিষ্টি বাড়ি | **MISTY BARI** (spelling to be confirmed by the owner) |
| Brand 3 | AL-CAKIZ | **AL-CAKIZ** |
The app header always shows the Bangla name with the Latin name under it. The locations use the guidebook's seven names
(phase5.sql). English mode only translates *descriptions* ("2nd Branch", "Main Showroom"), never the brand part.

## 2. Three language modes
- **বাংলা** — Bangla text.
- **Bng-Eng** — Bangla text with simple everyday English words mixed in (not Bangla written in Latin letters).
- **English** — full English, brand and fixed names unchanged.

## 3. One English term per Bangla term
`tools/glossary.py` holds the standard terms (units KG / Piece / Pound / Litre, Quantity, Remark, Discount, Status, Start date,
End date, Within the limit, Outside the limit ...). Run `python3 tools/glossary.py` before a release: it must print
"terms still inconsistent: 0". `--fix` rewrites the standard terms everywhere. Add a term there when two places disagree.
Context words that legitimately differ (e.g. "বাকি" = Due on a sale, Remaining on a ledger) are not in the list.

## 4. Numbers
- Digits are Latin (0-9) everywhere: money, quantities, dates, form numbers (the kit's rule: form numbers in English digits).
  Typing Bangla digits is accepted and converted.
- Dates are ISO inside the app (2026-10-11); the day name is shown next to it.

## 5. Numbering that must match the paper forms
- **Form number** (14-1, 10-2 ...) is the kit's number and never changes.
- **App serial** `FORM-LOCATION-n` (example `10-2-main-5`) counts entries per form and location, never skips or repeats.
- **Printed paper no.** — every form has a field for the serial printed in the numbered paper book. The same printed number can be
  entered only once per form and location (the database refuses a duplicate). The *Number gap audit* page lists printed numbers
  that were never entered (a missing page = a missing transaction; the guidebook calls a gap "an investigation").
- POS receipts have their own running receipt number per location (no paper counterpart).
