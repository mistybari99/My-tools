# UI no-loss rule

When screens and forms are reorganised to be shorter and easier, NOTHING may be lost: no form name, form code, field, option, route, menu entry or button may disappear, and none may be renamed silently. A rename is allowed only on purpose, with a written reason.

The safety net is an inventory of everything a person can reach, a checker that compares the current tree with it, and a CI job that runs the checker on every push and pull request.

## What is inventoried
`tests/ui_inventory/baseline.json` holds one entry per item (format: `tests/ui_inventory/README.md`):

- routes (all labels in every language, group, drawer / bottom-bar / Home / Control Center placement, search keywords), groups, "Do" actions, registered screens, quick actions;
- paper forms: code, name in every language, every field (key, label, type, required, conditions) and every option;
- screen controls found in `web/*.js` and `web/index.html`: buttons, tabs, links, inputs with their labels, selects and their options, RPC names called;
- settings keys: rules, grants, location settings, option lists, with labels;
- the i18n texts of `web/i18n.js`.

## How to run the check
```
python3 tools/check_ui_inventory.py              # exit 0 = nothing lost, exit 1 = lost or renamed (list printed)
python3 tools/check_ui_inventory.py --report     # counts per category, confidence split, what could not be read
python3 tools/test_ui_inventory.py               # proves the check really fails when a route, field, option or button is removed
python3 tools/check_ui_inventory.py --update-baseline   # ADDS new items; never drops or edits an old one
```
Only the Python standard library and the preinstalled `node` are needed. No database is touched; everything is read from code and from the seed SQL files.

## What fails and what only warns
- Fails: a baseline item of level `must` is missing (route, form, field, option, button, tab, link, input, select, select option, RPC name, settings key, group, text key, quick action), or its label text changed in any language, or a live route stopped being live or left the drawer.
- Notes only: items of level `info` (search keywords, form sections, form notes, placement lists) and moves of a route to another group or slot. Use `--strict-info` and `--strict-placement` to make those fail too.
- Additions never fail.

## The process (in this order)
1. Inventory first: the baseline already exists. Run `python3 tools/check_ui_inventory.py` on the untouched branch; it must pass.
2. Reorganise (shorter forms, merged screens, new layout).
3. Run the check. For each line it prints, either put the thing back, or decide on purpose that it is renamed and add an alias (next section).
4. The check passes, the self-test passes, `python3 tools/check_no_demo_leak.py` passes. Only then merge.
5. After merging, run `python3 tools/check_ui_inventory.py --update-baseline` and commit the result, so new items are protected from now on.

## How to add an alias when a rename is intended
Edit `tests/ui_inventory/aliases.json`. Every entry needs a non-empty `reason`; an entry without one is rejected and the check fails.

```
{
  "aliases": [
    { "type": "rename",    "from": "route:bulkitems", "to": "route:bulk_items", "reason": "route renamed to match the new menu wording" },
    { "type": "prefix",    "from": "ctl:old.js:", "to": "ctl:new.js:", "reason": "screen code moved from old.js to new.js" },
    { "type": "label",     "id": "field:11-1:sheet_no", "lang": "en", "from": "Daily showroom sheet no.", "to": "Sheet no.", "reason": "shorter label, same meaning" },
    { "type": "label",     "id": "ctl:dues.js:button:du_limit", "lang": "texts", "from": "L:সংরক্ষণ|Save|Save", "to": "L:সংরক্ষণ|Store|Store", "reason": "wording decided with the owner" },
    { "type": "placement", "id": "route:lists", "attr": "drawer", "reason": "moved from the drawer to the Control Center" }
  ]
}
```
- `rename`: old id to new id; the new id must exist in the tree, and the labels must still match (add `label` entries if the text changed too).
- `prefix`: every id that starts with `from` is looked up under `to` (use when a file or screen moves).
- `label`: accepts one changed text. `lang` is `bn`, `en` or `mix` for named labels, or `texts` for the visible text of a control (the value is the canonical text printed by the check).
- `placement`: accepts that a live route leaves the drawer or stops being live (`attr` is `drawer` or `status`).

There is deliberately no alias that deletes something. If an item is truly retired, the owner decides that in a reviewed commit that edits `baseline.json` by hand and says why in the commit message.

## Limits (what static reading cannot see)
Screens that build HTML from data (rows, dropdowns filled from the database), buttons made with `document.createElement`, texts assembled at run time, and options that come from live lists are only seen as far as the code states them; such entries are marked `conf: medium`. The check cannot tell whether a screen works, only that nothing it showed before has gone. Keep the existing browser tests (`tests/web/*_test.js`) for behaviour.
