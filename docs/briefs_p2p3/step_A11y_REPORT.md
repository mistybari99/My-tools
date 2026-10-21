# Step A11y (bos113) - report

Branch `fix/a11y` (from integration/p72-p79, merged with the latest origin). WEB only. One new helper `web/a11yfix.js` (loaded right after `kbdfix.js`, before `pos.js`; one tagged `bos113` line in `index.html`). It adds attributes and key handling through a MutationObserver. It never edits existing wording. No old file other than `index.html` was changed.

## What it does
1. `openSheet` sheets: `role=dialog`, `aria-modal`, `aria-labelledby` (heading), Tab trap, Esc clicks the existing `closesheet` action, focus returns to the opener. Focus goes into the first field only when the user is on the keyboard. For touch and mouse it goes to the sheet itself, so the on-screen keyboard never pops up (pointer behaviour is unchanged).
2. Pickers (`.ctl-bg`): the Tab trap now works from the `tabindex=-1` options (it leaked before); roving tabindex.
3. Drawer: focus goes in on open, the trap includes `select`, focus returns to the Menu button, `aria-expanded` on the Menu button.
4. `div[data-act]` rows (home forms, settings2, staff, suppliers...): `role=button tabindex=0`, Enter/Space call the existing click. Skipped when the row holds other controls (no nesting).
5. `<label>` without `for`: tied to the next control. Fields with no name get `aria-label` from the placeholder or the heading just before them.
6. `aria-pressed` on `button.tog` and the `cdr_set` chips, synced with `on`/`warn` classes.
7. "Skip to content" link (the route hash is never touched) and `role=main` on `#app` (the header there is `role=none`, because a banner may not sit inside main).
8. NEW screens only (`#app[data-a11y-new]`, set from the registry; old screens `home items staff matrix rules settings logs backup itemreq pos` are untouched): 44px `.mini`/dots/q4 chip, header and fields shrink, 320px no overflow. Also the dark-theme template preview headings (white paper).

Labels: English mode is all English; Bangla mode uses `L('মূল অংশে যান','Skip to content','Content-এ যান')`.

## axe-core 4.10.2, 121 routes + 4 extra, 360px, mocked data, light theme (nodes)
| Rule | before | after |
|---|---|---|
| label (critical, 8 routes) | 70 | 0 |
| landmark-one-main | 125 | 0 |
| region | 1565 | 0 |
| heading-order | 15 | 15 (report only) |
| nested-interactive | 13 | 13 (report only) |
| color-contrast, dark theme templates | 10 | 0 |

The 8 target routes (critical nodes before -> after): locset 54->0, purchase/new 3->0, purchase/return 3->0, settings2/units 5->0, settings 2->0, settings2/shelf 1->0, invoice 1->0, rulehub 1->0.

## Not fixed, on purpose (needs edits in old files)
- nested-interactive (stock, payables, purchase, purchaseprint): card `role=button` that holds the kebab button. A fix changes the card markup, so it is risky for pointer users.
- heading-order (15 routes): h1 followed by h3. Needs heading level edits in each screen.
- whatsnew `wn_dot` contrast in dark theme (15 nodes): inline style in whatsnew.js.
- Template/rollout status chips (colour only), 180px width (200% browser zoom): out of scope. bulkitems still overflows by 2px at 320px.
- No real screen reader was used; only attributes, tab order and axe.

## Tests
`tests/web/a11y_test.js` (62 checks): load order, sheet role/label/focus/trap/Esc/focus return, touch user (no focus jump, backdrop and close unchanged), picker trap and roving tabindex, drawer, data-act rows by keyboard, page geometry identical with and without the helper, labels, aria-pressed, skip link and `main`, 320px, axe before/after. `order_test.js` is unchanged.
Existing tests, unchanged: ia, order, pol, kbd, navfold, nav_b, nav2, lang_all, lang_en, optviews_ui2, pos_units, posfail, pos2b, itemimg all pass. catpick (5), glass (3) and invoiceview (1) fail the same checks with and without the helper (checked against a copy of web without it).
