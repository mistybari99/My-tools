# Step W report - missing phone-width screens for phases 72-84 (new files only)

Branch fix/phase-W (from integration/p72-p79). No SQL changed. No existing screen file edited (pos.js, stock2.js, salesx.js, recipes.js, guards.js, biz.js, reports.js untouched). Edited only: web/ia.js (9 rec lines appended after `backup`), web/index.html (script tags appended after twofa.js).

## New files
- web/stepw_common.js - readable error labels (`B.w.errText/err`), the "System recommends" card (`B.w.recCard`: now / recommended / reason / "advice only" line / owner buttons -> set_rule), place names.
- web/formscreens.js - #/unmatched (unmatched_forms, unmatched_forms_sync), #/formguard (form_guard_recommendations: form_051_mode, transit_short_mode, transit_open_hours, offline_soft_stock), #/expenselink (suggest_expense_link, expense_link_apply), #/transitshort (transit_open_list, transit_short_open, transit_short_resolve + the two transit recommendation cards).
- web/chanedit.js - #/saleschannels create/edit (sales_channel_save, sales_channels_list); owner only.
- web/costboard.js - #/costunknown (profit_source_check unknown_cost_rev / fallback, runs with cost_complete=false, items with no cost, production_requires_cost next to a recommendation). Linked from ia.js, biz.js / reports.js not edited.
- web/packflags.js - #/packflags (E9): packed orders + online_order_stock_check, sale-voided flags + review, duplicate-order flags + review, the 3 E9 switches with advice.
- tests/web/stepw_test.js.
- ia.js records: unmatched, formguard, expenselink, transitshort, saleschannels, costunknown, packflags, and posfailed (the E-b lead line that was never wired; posfail.js now also has its script tag).

## Rules followed
- Owner-gated where the backend is (formguard, saleschannels, sync button, switches); other screens show the server refusal as a readable label.
- Every switch/choice shows the system recommendation + reason and "advice only"; nothing is forced or blocked. Server recommendations are used for E5-E7; for costboard the recommendation is computed on the page (warn while costs are missing, refuse when none are); for the 3 E9 switches the advice text is written from the migration hints (the server gives none).
- Errors mapped: not_fully_covered, not_a_voucher, entry_is_a_primary, bad_status, note_needed/reason_required, not_short, bad_range, bad_kind, other_text_required, name_required, bad_code, duplicate code, location/role not found, cost_missing (+ ingredient detail), not allowed (+ for this location), function-missing (old database).
- Language: every string bn/en/mix via B.L; English slot has no Bangla letters (test); Bangla mode keeps common words English. No existing text rewritten.
- data-act names prefixed wx_ wfg_ wch_ wcb_ wpf_; test checks no clash with any other web file.

## 1. যাচাই হয়েছে
- node tests/web/stepw_test.js: 75 pass / 0 fail (mocked rpc, vm, no browser): language (all strings 3 languages, no Bangla in English slot), error labels, recommendation card and set_rule args, every screen's rpc names/arguments, reason-required checks, owner vs non-owner, route/ia/index wiring, unique data-act, handlers exist.
- Existing: lang_en_test 76 English strings 0 Bangla; posfail_test 23/0; ia_test 0 assert failures, no page errors; nav_test no errors (see bottom of this file for nav2/control/favsync/settings2).

## 2. পড়ে বোঝা
- Column names used in direct selects (entries: id,serial,entry_date,location_id,status; production_runs.cost_complete; roles; items) were read from schema/phase files, not run. production_runs.cost_complete is a cost fact: for a person without the cost right the select may be refused; the page then shows the "cost right is needed" note.
- online_orders_list masks contact data by design; the page shows only order number and place.
- Expense link applies only when every line is covered (server rule); the button stays visible and the server decides.

## 3. যাচাই হয়নি
- Real phone, real browser rendering at 360px of the new pages (no playwright run of them), real Supabase with phase82-84 applied.
- CSS classes used (card, notice info/warn/bad, row, tog, btn) exist in theme.css but the look was not viewed.
- The sheet `<select>` change listener for the channel type is a document-level listener (tested with a mock only).
- Nothing was done for: "form 05-1 / expense-link offer inside the 10-2 approval sheet" (needs editing forms code); the screens are standalone.

## Owner notes
Packaged routes are #/unmatched #/formguard #/expenselink #/transitshort #/saleschannels #/costunknown #/packflags #/posfailed. Deploy = web files only.
- nav2 / control / favsync / settings2 tests: run, no page errors (favsync fails 0, settings2 assert failures 0).
