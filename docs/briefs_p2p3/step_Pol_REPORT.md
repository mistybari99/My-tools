# Step Pol (bos108): visual QA fixes, web only

Branch fix/phase-Pol (from integration/p72-p79). Source: independent visual QA (VISUAL_QA.md, 28 routes x 3 languages x 3 themes, 360x740 touch).

## যাচাই হয়েছে (measured by running it)
- tests/web/pol_test.js: 197 pass, 0 fail. Bottom bar fits at 320/360/412 px in en/bn/mix, Light and Classic (scrollWidth <= clientWidth, all tabs inside the screen). Main actions >= 44px on costsources, costattrib, s1setup, scan, inbox, books85, books96, optionsx, billpay, inboxpii. No snake_case key / "Cannot read" / "undefined" in visible text on 27 routes x 3 languages. Accounts with null reports shows no JS error. Link strip pills >= 44px. Fields >= 16px on five new routes. Drawer language buttons >= 44px. Four form-rule pages share one drawer group. Contrast computed from the CSS tokens: Premium Light primary top stop and Classic ok chip >= 4.5.
- Visual QA harness re-run (copy pointed at this worktree, 27 routes x 3 languages x 3 themes = 81 pages), before -> after: tap targets < 44px 419 -> 26 (mini buttons 395 -> 8, rest is old Classic .ctl-trg at 40px); inputs < 16px 96 -> 18 (all remaining are checkboxes); raw snake_case keys 54 -> 0; JS error text 9 -> 0; overflow 0 -> 0; contrast 3 -> 3 (the same false alarm, templates h3 'Method' in Dark; real G6/G7 checked by the token test); Bangla in English mode 6 -> 6 (user data only).
- Existing tests unchanged and passing: nav2, ia, control, favsync, settings2, navfold, kbd_test (69), optviews_ui2, lang_en, invoiceview (65), tplpicker (52), books96, dscr, accounts, guards, scan, s1setup, stepw (75).
- node --check on all web/*.js clean; no conflict markers.

## পড়ে বোঝা (read from the code, not measured)
- Drawer grouping: formguard, expenselink, transitshort moved to group 'appr' (same as unmatched). Verified only through ia byRoute.
- Header titles: Books 85 / Books 96 prefixes removed from the new page titles; other long titles were not shortened (a header clamp was not added, to avoid touching old screens).
- Classic `.mini` side padding applies to all Classic mini buttons except inside `.ph` (photo remove button), so some old Classic screens get 12px side padding (labels no longer touch the border, as asked).

## যাচাই হয়নি (not verified)
- Real phone, real iOS Safari zoom behaviour, real Bangla font (Google Fonts blocked in sandbox).
- Sheets (bottom sheets) inputs: 16px rule is scoped to the new page wrappers, not to sheets (kbdfix iOS rule remains).
- tests/web/nav_test.js fails at line 49 (drawer language click, footer collapsed by navfold) on the untouched baseline too; optionsx_test has 1 known failure (script order) on baseline too. Not caused by this step.
- Remaining small taps after the fix are old controls (Classic `.ctl-trg` 40px) and checkboxes with 13px font (rb_cost, opx_cr, opx_dc, not text fields).
- Breadcrumb wrapping, option-card alignment, the Save/Clear row wrap and recipebook checkbox row from the QA table (low severity) were not done.

## Files
web/theme.css (bos108 block at end), web/accounts.js (null guard, JS errors never shown), web/stepw_common.js (links: .wxlinks/.wxl + aria-current, JS-error label), web/optionsx.js (opx-lnk class), web/s1setup.js, web/scan.js, web/books96.js, web/books85.js (title), web/guards.js (no raw key title), web/formscreens.js (labels for expense_link_mode and unknown keys), web/posfail.js (open ?? 0), web/ia.js (group), tests/web/pol_test.js, tests/web/pol_rpcmock.js.
