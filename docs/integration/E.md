# Integration note E: Balance Check (G11) and guarded test reset (G13)

SQL number: **phase84** only. Paste after phase79 (or the latest phase). Paste-twice safe. No existing file was edited.

## 1. Hooks needed (integrator)

- `web/index.html`: add `<script src="balancecheck.js"></script>` (anywhere after `app.js`; next to `accounts.js` is natural).
- `web/ia.js`: add the registry line in section 2.
- Optional, not required: a red/green banner at the top of `#/accounts` and `#/finance2` (the gap plan asks for it). The data comes from one call, `sb.rpc('_e_balance_check')`; read `.status` (`red` | `green` | `data_needed`). Not done here because it needs edits in `accounts.js` / `finance2.js`.
- `web/sw.js`: add `balancecheck.js` to the precache list if the other screen files are listed there [not checked].
- Do not rename the route `balancecheck`.
- Re-pasting an old phase never touches phase84 (it only calls existing reports: `acct_balance_sheet`, `acct_trial_balance`, `daybook_vs_journal`, `inventory_vs_gl`, `acct_status`). If any of those is renamed later, the matching cross-check shows "not run" instead of failing.

## 2. `web/ia.js` registration (route, label, tile / keywords per bos-organise)

Put it next to the `accounts` record (group `acc`, Accounting & Finance):

```js
  rec('balancecheck', 'acc', ['হিসাব মেলানো (ব্যালান্স চেক)', 'Balance check', 'Balance check (হিসাব মেলানো)'], { icon: 'check', ok: (c) => c.own || c.GF.accounts_view === true || c.GF.accounts_manage === true, kw: ['balance check', 'books agree', 'trial balance', 'equation', 'assets liabilities equity', 'unbalanced', 'stock identity', 'red green', 'test reset', 'হিসাব মেলানো', 'ব্যালান্স চেক', 'মেলে না', 'ট্রায়াল ব্যালান্স'] }),
```

- No Home tile, no bottom-bar slot (leave `mob` / `home` at defaults); it is reachable from the drawer (Accounting & Finance), search and Control Center.
- The test `tests/web/balancecheck_test.js` injects a shortened version of this line itself, so the screen test passes before and after the integrator adds the real line.
- Run `node tests/web/ia_test.js` plus nav, nav2, control, favsync, settings2 after adding it. The records count in `ia_test` may need +1 (intentional).
- The screen has its own 3-language labels (`L(bn, en, mix)`), no `i18n.js` keys needed.

## 3. Tables and functions added (all in `supabase/phase84.sql`)

| Name | Kind | Notes |
|---|---|---|
| `_e_balance_check(p_date, p_loc, p_days)` | function, READ ONLY | one jsonb answer, grant: authenticated; needs `accounts_view` / `accounts_manage` or owner (`_acct_view`); all-places view needs `_acct_all` |
| `_e_test_reset(p_phrase)` | function, WRITES (test projects only) | refuses unless owner AND rule `allow_test_reset` ON AND exact phrase |
| `_e_test_reset_state()` | function, read | `{allowed, owner, flag, last}`; the screen shows the reset card only when owner and flag are on |
| `_e_reset_tables()` | function (list) | transactional tables the reset may clear; only names that exist are used |
| `_e_reset_protected()` | function (list) | setup tables that must never be cleared; a name on both lists stops the reset |
| `_e_reset_log` | table | append only, RLS on, no browser access; one line per reset (who, when, database name, counts) |
| `_e_reset_log_ro()` | trigger function | blocks update, delete, truncate on the log |
| rule `allow_test_reset` | `rules` row, module `settings`, switch | default OFF |

`_e_balance_check` result keys: `status`, `as_of`, `equation` (assets, liabilities, equity, earnings, difference, ok), `trial_balance`, `journal` (broken count + rows, max 200), `stock_identity` (broken count + rows, max 200), `cross_checks` (`daybook_vs_journal`, `inventory_vs_gl`, `unposted_sources`), `warnings`, `reds`.

Status rules: RED when the equation, the trial balance, any journal entry (Dr <> Cr, or an entry with no lines) or any stock identity (opening + in - out <> `stock_balance`) fails. The three cross-checks are AMBER only: they are listed in `warnings` and never turn the status red, because a day book vs journal difference is normal timing (a voucher counts when submitted, the journal when approved).

Journal note: the database already refuses an unbalanced entry at commit (`jl_balance` trigger), so a red journal row means data written around that trigger (restore, manual SQL, a disabled trigger). The test seeds one by disabling that trigger inside the test only.

## 4. Open owner decisions exposed as settings (safe defaults)

| Setting | Default | Decision |
|---|---|---|
| rule `allow_test_reset` (Rules page, module settings) | **OFF** | Turn ON only in a test project. After one successful reset it switches itself OFF. The confirmation phrase is fixed in the function: `DELETE ALL TEST DATA`. |
| Which tables a test reset clears | list in `_e_reset_tables()` | Review the list once before first use in a test project. Not cleared: `audit_log` (change log), items, recipes, rules, grants, roles, users, places, forms, option lists, chart of accounts, mappings, customers, suppliers, employees, serials. |
| Cross-check window | 31 days (`p_days`, max 366) | The day book vs journal check looks back this many days. |

Gap plan G13 advised no SQL reset in `supabase/` and a documented scratch-project procedure instead. This phase follows the later task instruction (guarded function). Residual risk: if the owner turns `allow_test_reset` ON in the live project and types the phrase, live transactions are destroyed (and the append-only triggers on those tables are bypassed for that statement). Mitigations: default OFF, owner only, exact phrase, one-shot flag, log line. The integrator may choose NOT to paste phase84 into the live project at all; the Balance Check part works without the reset (drop `_e_test_reset` from the paste if preferred).

## 5. Tests

- `supabase/phase84_test.sql` (fresh DB built through phase79 + phase84): 41 pass, 0 fail on local Postgres 16, port 5549. Includes negative tests: seeded unbalanced journal detected; entry with no lines detected; stock identity break detected; non-accounts user refused; reset refuses by default, with no / wrong / near-miss phrase, as non-owner, and a second time; reset leaves items, rules, roles, locations, forms, chart of accounts, mappings, lists, user roles, profiles, grant defs and `audit_log` intact; append-only triggers are back on after the reset.
- Paste-twice: `phase84.sql` applied twice on a used DB with no error.
- `tests/web/balancecheck_test.js`: 0 failures (headless Chromium, stubbed data, 360px, 3 languages). Run: `node tests/web/balancecheck_test.js $PWD/tests/web`. It serves this checkout's `web/` folder.
- NOT done: real Supabase project, real phone, `ia_test` and the other nav suites with the real registry line (integrator step), the optional banner on `#/accounts` and `#/finance2`.
