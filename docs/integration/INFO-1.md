# Integration note INFO-1: the (i) information system

Owner request: "For every critical system, put an (i) sign with the information of what it does inside it." This package builds the shared system and the first content. No existing file was edited. No SQL. No database was touched.

New files: `web/infohint.js`, `web/data/info.json`, `tests/web/infohint_test.js`, `tools/check_info_coverage.py`, this note. The style is injected by `infohint.js` (the project convention), so there is no CSS file and no `<link>` to add.

## 1. What it is

* A small round (i) button (44px touch target, a real `<button>`, `aria-label="What is this?"`). A tap opens a bottom sheet with: title, What it does, Why it matters, Default, What changes if you switch it, Who can change it, Related. An optional `warn` shows as a boxed warning at the top (used for the test-project reset and the backup passphrase). An entry with `verified:false` also says "This text is not fully confirmed yet."
* Related items: `screen:<route>` links to `#/<route>`; any other key opens that entry in the same sheet (with a Back button).
* The sheet is its own layer (z-index 90), not `BOS_APP.openSheet`: `openSheet` is single instance and would destroy a sheet that already holds the (i) (for example a settings sheet). It reuses the look of the app sheets through the same tokens. Escape, outside tap, X and Done close it; focus is trapped inside and goes back to the (i) that opened it. A tap on the (i) never reaches the row or label around it.
* Missing key, missing or broken `info.json`, bad entry: renders nothing, never throws (tested: 404, not JSON, network error, partial entry, html in text, `__proto__`).
* English only. Text is escaped (no html from the data file runs).

## 2. Hooks the integrator must add

`web/index.html`: one line, after `app.js` (anywhere before `</body>`; next to `freshness.js` is fine):

```html
<script src="infohint.js"></script>
```

`web/sw.js`: **no line to add.** `sw.js` has no precache list (network first, cache as the fallback, see its header). `infohint.js` fetches `data/info.json` once at start with a plain same-origin GET, and the existing handler stores every `res.ok && type === 'basic'` GET. So after the first online visit the sheet works offline. If a precache list is ever added, the exact line is `'data/info.json'` (and `'infohint.js'`).

Nothing else. `web/ia.js` is not touched (the (i) is not a screen).

## 3. How screens call it

Two ways. Both do nothing when the key has no entry.

A settings row or any template string (returns html, or `''`):

```js
// web/switchboard.js, line 46: after the row title
`<b>${esc(lab(rl(r)))}</b>${B.info ? B.info('rule:' + r.key) : ''}`
```

A screen title or any static markup (an attribute; the (i) is added as the last child, also for elements added later):

```js
shell('Period lock', ...)           // existing
// in the markup the screen writes:
`<h2 data-info="screen:periodlock">${esc(T('title'))}</h2>`
// optional, when you build a node by hand:
B.infoMount(rootEl);
```

Rules: put the (i) beside a button, never inside one. Key shapes: `rule:<rule_key>`, `screen:<route>`, `grant:<grant_key>`, `switch:path:<domain>`, `feature:<name>` (for systems that are not one rule, screen or grant). `B.info.open(key)` opens a sheet from code; `B.info.has(key)` tells if an entry exists.

## 4. Adding entries (every later package)

Each package that adds a rule, grant, screen or switch ships `docs/integration/<pkg>_info.json` with its entries (flat object, or `{ "entries": { ... } }`). The integrator merges them:

```
python3 tools/check_info_coverage.py --merge docs/integration/<pkg>_info.json --dry
python3 tools/check_info_coverage.py --merge docs/integration/<pkg>_info.json
```

The merge refuses a key that exists (use `--replace` on purpose), refuses a bad key shape, and writes `web/data/info.json` sorted. Entry shape (all text is one line of short plain English, no jargon):

```json
"rule:example_key": {
  "title": "Same words as the setting label",
  "does": "1 to 3 short sentences.",
  "why": "1 sentence.",
  "default": "What happens if you do nothing.",
  "change": "1 to 2 sentences. Say 'past figures never change' only where true.",
  "who": "Role or grant.",
  "related": ["screen:route", "rule:other_key"],
  "warn": "optional boxed warning",
  "verified": true,
  "src": "phaseNN.sql; <pkg>.md section"
}
```

Facts come only from the code and the integration notes; if you cannot confirm a fact, set `"verified": false` (then only `title` and `does` are required) and say so in the text. The web test `tests/web/infohint_test.js` fails when: a section is missing (and not `verified:false`), a text is too long, a `rule:` key is not in the seed SQL (`supabase/*.sql`, not `*_test.sql`), a `grant:` key is not in `grant_defs`, a `screen:` key is not in `web/ia.js`, a `switch:path:` domain is not in `phase48.sql`, a related key has no entry, or a demo name appears.

`python3 tools/check_info_coverage.py` lists critical rules, grants and screens with no entry. It exits 1 only when a rule added in phase 80 or later has no entry (`--strict` also fails on a missing Wave 1 / critical screen). Add it to the integrator's checks.

## 5. First content (125 entries, 123 verified, 2 not)

All 82 rules added in phases 80 to 98, all 4 grants added since phase 80 (`return_override`, `exit_keep_access`, `late_sale_release`, `backdate_over_limit`) and `closed_period_edit`, the 8 Wave 1 screens plus `accounts`, `moneyaccounts`, `balancecheck`, `shortages`, `wallets`, `monthclose`, `exceptions`, `ledgerlinks`, `paths`, the 7 path switches, and the systems the owner listed: opening balance, owner approval modes, money accounts and payment source, transfers, exceptions with reason, balance check, test-project reset (warning: test projects only), period lock and override, back-date window, late sale policy, staff exit lockout, return window and restock, one profit number and its effective-from date, report parity, owner money entry, supplier duplicate payment guard, journal location check and attachment threshold, other income, bank and cheque receipts, scheduled posting, backup encryption and retention, `forms_post_to_ledger`, `accounting_on`, path switches, wallet split, cash short, transit short, customer advance, payroll accrual, partner settlement.

Not verified (`verified:false`): `feature:money_transfer` (which grant allows it is not in the notes), `feature:customer_advance` (the full flow of using an advance is not described in the code notes; only the posting and the read-only check are).

Older critical rules (before phase 80) with no entry are listed by the tool as information (about 28 by its name/kind rule; for example `costing_method`, `pos_credit_mode`, `twofa_required_roles`, `wastage_approval_limit`, `block_expired_sale`). A later pass can add them.

## 6. Screens and rows that should get an (i) first (integrator and screen owners)

1. `web/switchboard.js` and the Rules hub row (one line, section 3): every setting row, by `'rule:' + r.key`. This alone covers all 82 new rules and the older ones as entries are added.
2. Screen titles (add `data-info="screen:<route>"` to the title element): `periodlock`, `openparties`, `returnrules`, `profitcheck`, `moneycontrols`, `otherincome`, `bankreceipt`, `freshness`, `moneyaccounts`, `balancecheck`, `shortages`, `wallets`, `monthclose`, `accounts`, `exceptions`, `ledgerlinks`, `paths`.
3. `web/paths.js` rows: `'switch:path:' + d.domain`. `web/forms_stock.js` ledger links master switch: `rule:forms_post_to_ledger`.
4. `web/moneyaccounts.js` tab "Payment defaults": `feature:payment_source`; tab "Transfers & charges": `feature:money_transfer`; Exceptions tab: `feature:exception_reason`.
5. `web/accounts.js` Opening tab: `feature:opening_balance`. The test reset card in `web/balancecheck.js`: `rule:allow_test_reset` (carries the warning).
6. Grant rows on the Delegation board / grant lists: `'grant:' + grant_code`.

## 7. Tests

* `node tests/web/infohint_test.js $PWD/tests/web`: 0 assert failures, no console errors (headless Chromium, 360px; harness page with the real `styles.css` and `theme.css`, plus a smoke load of the real app with the script injected). Covers: button and sheet, 44px target, missing key, keyboard (Enter, Space, Tab trap, Escape, focus return), dark and light contrast, big text, every key opens and fits 360px, data file 404 / broken / offline then online, escaped text, data shape, keys exist in SQL / ia.js / phase48, demo-name check, coverage tool.
* Screenshots are written to the temp folder (set `INFO_SHOTS` to choose), never into the repository.

## 8. Not confirmed

A real phone, a real service worker offline run (the app registers `sw.js` on https only, so tests cover the fetch, the recovery on `online` and the code path, not the cache itself), and translation (English only by owner decision). The text is a plain-English summary of the code and notes; the owner should read the `who` lines, which describe grants as the server enforces them.
