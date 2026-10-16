# Integration notes: Builder D (G9 wallets, G10 production materials)

Branch files: `supabase/phase83.sql`, `supabase/phase83_test.sql`, `web/wallets.js`, `tests/web/wallets_test.js`, this file.
No existing file was edited. Everything below is for the integrator. Paste order: after phase79 (and after every other builder's phase); phase83 only needs phase40 (books) and the recipe phases 19/73/74. It does not replace any existing function, so a later paste of an older phase never undoes it. Paste twice is safe (tested).

## 1. Hooks the integrator must add (one line each)

| # | Shared function | Hook | Without the hook |
|---|---|---|---|
| H1 | `_acct_docs(date)` (latest body; every phase that re-creates it must keep this line) | at the end of the body, before `end`: `return query select * from public._d_acct_docs(p_start);` | Wallet entries, the wallet fee expense (Dr 5815) and wallet moves are NOT posted to the books. The wallet register (balances, counts) still works. |
| H2 | `_p27_pl(date,date,int[])` | in the expense union where the bos50 quick expenses are read, add `union all select m, loc, amount from public._d_wallet_fee_rows(p_from, p_to, p_locs)` (adapt the local variable names; it returns `(m date = month start, loc int, amount numeric)`) | The operational P&L does not show the wallet fee (the journal income statement does, through account 5815). |
| H3 | `_daybook_lines(int[],int[],date,date)` | add `union all select * from public._d_daybook_rows(p_locs, p_from, p_to)` (same 14 columns; typ `wallet_fee`, mode `mobile`, dir `out`); add a label for type `wallet_fee` in the day-book type dictionary | The fee is missing from the day book. |
| H4 (optional) | `recipe_cost`, `production_post` | only if the owner chooses a costing method other than `average_purchase`: take the unit cost from `public._d_material_cost(item, loc)` instead of `stock_balance.avg_cost`. Not wired in this phase: production issues stock at the ledger average cost, so changing the method would also change what the stock ledger books. Today the setting drives `d_material_unit_cost` and `d_recipe_cost_gaps` only. | No effect on today's costing (default equals current behaviour). |

Test of H1: `phase83_test.sql` simulates H1 in the test database only (it renames `_acct_docs` and wraps it with a union). The real one-line hook in the real body is UNTESTED until the integrator adds it and re-runs `phase83_test.sql` without the simulation block (T1).

Other builders' sources (opening balance, owner modes) must be added to `_acct_docs` in the same single re-creation; H1 is a plain `return query` so it composes with theirs.

### Opening per wallet (depends on builder A / G3)
Wallet balances start at `d_wallets.opening_amount` (set with `d_wallet_opening_set(wallet, amount, date)`, owner or accounts manager, locked after the first phone count). The books get the same opening through the opening screen on the wallet's own accounts (codes 1131 bKash, 1132 Nagad, 1133 Rocket, 1134 Upay). Type the same amount in both places; `d_wallet_balances().journal_gap` shows any difference.

## 2. Web registration (web/ia.js and web/index.html, owned by the integrator)

index.html, next to `cashmoves.js`:
```html
<script src="wallets.js"></script>
```

ia.js, one line next to the `cashmoves` record (group acc, per bos-organise: pick by the job, not the person):
```js
rec('wallets', 'acc', ['মোবাইল ওয়ালেট (বিকাশ/নগদ/রকেট)', 'Mobile wallets', 'Mobile ওয়ালেট'], { icon: 'money', ok: (c) => c.own || c.P('10-3', 'view') || c.P('10-3', 'enter') || c.GF.accounts_view === true,
  kw: ['wallet', 'bkash', 'nagad', 'rocket', 'upay', 'mobile money', 'wallet fee', 'cash out', 'digital payment', '10-3', 'reconcile', 'বিকাশ', 'নগদ', 'রকেট', 'উপায়', 'ওয়ালেট', 'মোবাইল ব্যাংকিং', 'ডিজিটাল পেমেন্ট'],
  verbs: ['count wallet', 'add wallet fee', 'move wallet money'], aliases: ['bkash', 'nagad'] }),
```
Optional (not required): `home: { acc: <free slot> }` for a Home tile and `cc: 'rules'` is NOT used; the four settings of section 4 appear in the existing rules screen by themselves. Route `wallets` is new, no route renamed. Run `node tests/web/ia_test.js <abs tests/web>` plus nav, nav2, control, favsync, settings2 after adding it. The icon `money` already exists. The server decides permission (every RPC checks it); the `ok` line only hides the entry.

## 3. Tables and functions added

Tables (all RLS on, no hard delete trigger, audit trigger on the first four, browsers read only through a policy, write only through the functions):
`d_wallets` (code, names bn/en, aliases, chart account, opening, active), `d_wallet_fees`, `d_wallet_moves`, `d_wallet_checks`, `d_material_roles` (seed rows milk, chhana, packing: structure, not items), `d_item_roles`, `d_product_role_req`, `d_material_fixed_price`.
Chart/mapping: accounts 1131, 1132, 1133, 1134 (asset, under 1100; more via `d_wallet_add`, next free code up to 1139), account 5815 Wallet fees (expense), mapping keys `wallet_fee` and `d_wallet_<code>`. Account 1130 stays as the generic mobile account and the fallback: a payment whose wallet text is unknown stays on 1130 (reported as `unassigned_mobile`).

Journal sources (via `_d_acct_docs`, each entry balanced two-line, written only by the existing `_acct_write` which refuses Dr <> Cr):
- `d_wallet_split` `sp:<sale_payment id>` / `sup:<supplier_payment id>`: moves the amount from 1130 to the wallet account (sale: Dr wallet, Cr 1130; supplier payment: Dr 1130, Cr wallet). Voided or reversed sources are reversed.
- `d_wallet_fee`: Dr 5815, Cr wallet. Only while `d_wallet_fee_treatment = separate_expense`.
- `d_wallet_move`: wallet against cash (1110), bank (1120) or another wallet.

Functions (API, all `security definer`, anon has no access): `d_wallet_add`, `d_wallet_update`, `d_wallet_opening_set`, `d_wallet_fee_add`, `d_wallet_fee_void`, `d_wallet_move_add`, `d_wallet_move_void`, `d_wallet_check_save`, `d_wallet_check_explain`, `d_wallet_balances`, `d_wallet_recon_report`, `d_wallet_statement`, `d_item_role_set`, `d_item_roles_import`, `d_product_req_set`, `d_fixed_price_set`, `d_material_unit_cost`, `d_recipe_material_check`, `d_recipe_cost_gaps`, `d_production_cost_breakdown`. Internal helpers `_d_*` are closed (only `_d_view_ok` and `_d_cash_ok` are executable because the table policies call them). Two triggers: `d_production_runs_gate` (before insert on `production_runs`) and `d_recipes_activate_gate` (before update of `active` on `recipes`); they are no-ops while the setting is `off`.

Rules for the 10-3 reconcile (BUILD-RULE 9, blind count): the phone total is typed first (`d_wallet_check_save`); the book figure, the journal figure and the difference come back only after it is saved, and `d_wallet_balances` hides the book figure of an uncounted wallet from everybody except the owner and accounts managers. The difference is always written (also 0). A difference needs a reason once (`d_wallet_check_explain`), then it is closed.
What is NOT reached by the wallet register: money that carries no wallet name (owner top-up, salary or advance paid by mobile, quick expenses by mobile, sale refunds by mobile, supplier refunds). Those stay on 1130. Add a wallet column to those sources later if the owner wants them per wallet.
Existing tables are not changed; free-text `wallet` columns of `sale_payments` / `supplier_payments` are matched by lower-case code, English name, Bangla name or alias. The sale and supplier-payment screens can keep sending 'bkash' / 'nagad' / 'rocket' / 'upay'. A supplier payment that would push a wallet below zero is not stopped (that code is existing); `d_wallet_balances` shows the negative book figure.

G10 finding (verified before building, tested in `phase83_test.sql` T9 to T11): milk, chhana and packing already work as stock items (item types `raw_material` and `packaging`); `recipe_lines` consume them, `product_packaging` consumes packing when rule `packaging_consume_on = production`, `recipe_cost` and `production_post` already add raw + packaging + conversion, and a recipe without lines is already refused (`no_lines`). Test numbers: milk 20 kg x 60 + chhana 5 kg x 300 + 5 boxes x 10 = 2750; unit cost 275 per kg for 10 kg; breakdown by role milk 1200, chhana 1500, packing 50. What phase83 adds: the roles, "this product requires these roles", the warn/block gate, the cost-gap report, the costing-method helper and the per-run breakdown. No item was created; `d_item_roles_import([{item_code, role}])` maps EXISTING items by code (unknown codes are reported, nothing is created).

## 4. Open owner decisions, exposed as settings (safe defaults)

| Setting key | Choices | Default (today's behaviour) | English label | Decision it carries |
|---|---|---|---|---|
| `d_wallet_fee_treatment` | `separate_expense`, `not_posted` | `separate_expense` | Wallet fee treatment: booked as its own expense (Dr Wallet fees, Cr the wallet), or kept in the register only | Q1 (fee policy). Switching to `not_posted` reverses the posted fee entries; switching back posts them again. Other ways to treat fees (net against sales, charged to the customer) are NOT built; ask the owner before adding them. |
| `d_wallet_negative_mode` | `refuse`, `warn` | `refuse` | When a fee or a move would make a wallet balance negative: refuse it, or warn | none; refuse is the safe side |
| `d_recipe_materials_mode` | `off`, `warn`, `block` | `off` | When a recipe lacks a material its product requires (milk, chhana, packing): off, warn, or block activation and production | which products require which roles is entered by the owner (`d_product_req_set`); nothing is required until then |
| `d_material_cost_method` | `average_purchase`, `last_purchase`, `fixed_price` | `average_purchase` | How a material's unit cost is taken: weighted average of purchases, last purchase bill, or an owner-fixed price | Q5 (purchase bill or fixed value). `fixed_price` needs rows in `d_material_fixed_price` (`d_fixed_price_set`); an item without one shows in the cost-gap report. Wiring into `recipe_cost` / `production_post` is hook H4, owner decides first. |

A blank or missing value never invents a number: with `fixed_price` and no price the item has no cost and is listed as a gap.

## 5. Test status (local Postgres on port 5548, temp data dir, all phases 8 to 79 then 83)

- `phase83_test.sql`: 92 pass, 0 fail (hand-computed amounts in the file). Covers: three wallet sales land on three accounts, a label spelling resolves, an unknown wallet stays on 1130, fee Dr = Cr, moves cash/bank/wallet, journal equals register per wallet, blind count and difference, reason once, void reverses, fee-treatment switch, negative balance refused/warned, wallet mismatch, unbalanced entry refused by the writer, salesperson refused, paste twice, recipe missing a required material (off/warn/block, activation), cost gaps, fixed price, import, production cost breakdown.
- `phase79_test.sql` re-run on a database with phase83 applied: 77 pass, 0 fail (nothing existing changed).
- `tests/web/wallets_test.js` (Playwright, mocked RPCs): 0 failures, no console errors. The script is injected by the test because `index.html` is the integrator's.
- UNTESTED: the real H1/H2/H3 hooks in the real function bodies; `last_purchase` costing method (no purchase bill fixture); H4 wiring; the screen on a real phone and with real RPCs; the two-language/three-mode label check (labels exist in all three modes in `wallets.js`, not visually checked); `ia_test`/nav tests with the new `rec` line.

## 6. BUILD-LOG entry for the integrator to paste (rule 16)

"phase83 (builder D): G9 separate wallets with fee expense 5815 and 10-3 blind phone reconcile; G10 production material roles, required-material gate (setting, default off), cost-gap report, costing-method helper. New tables d_*; no existing function edited; hooks H1 to H3 needed in _acct_docs, _p27_pl, _daybook_lines. Not confirmed: real hooks, last_purchase method, phone check, live database (never touched)."
