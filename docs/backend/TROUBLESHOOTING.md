# Troubleshooting

Only problems that were actually met (or that a guard in the code is written to catch) are listed. Evidence file in the last column. "Paste" always means: the owner pastes a whole `supabase/phaseNN.sql` into the Supabase SQL editor and runs it. Never run SQL on the live database from an agent session (the sandbox cannot reach it).

## 1. SQL paste order, guards and lost function tags

| Symptom | Cause | Fix | Evidence |
|---|---|---|---|
| Paste stops with `phaseNN needs phases ... pasted first ... missing: <numbers>` (NN = 89, 94, 98, 99, 103) | A prerequisite phase has not been pasted. The guard looks for one marker object per phase (and for `bos89` / `bos98` tags in `_acct_docs`) | Paste the missing phases listed in `missing:` in the order of `docs/PASTE_ORDER.md` (section B), then the failing file again. Nothing was changed by the failed paste (creates run only if both guards passed) | `phase98.sql` line ~34, `phase103.sql` line ~46 |
| `phase96 needs phase85 (and phase80) pasted first` / `... _acct_docs carries no bos85 line` / `... needs phase89 pasted first` | phase96 re-creates functions from the phase89 bodies | Paste 85, 89 first (canonical order: ... 90, 91, 89, 92, 93, 95, 94, 96) | `phase96.sql` guard |
| `phase98: <function> carries tags this file does not know (<tag>); build a newer merge instead of overwriting it` (same text with `phase103:`) | The live body is NEWER than the file (a later phase's tag, e.g. bos103, is present). The body guard refuses to put an older text back | Do not force it. If phase103 is on the database, phase98 is not needed; to repair a re-pasted older file paste **phase103** instead | `phase98.sql` line ~54, `phase103.sql` line ~81 |
| `bosNN` tag missing from a function body (`phase89_test` T0, `phase94_test`, `phase96_test`, `phase98_test`, `phase103_test` show FAIL) - "function tag loss on re-paste" | An older phase file was pasted again after a newer one, so its older function text overwrote the newer text (`create or replace` has no memory). Known cases: phase89 re-paste puts back older `_acct_docs` and `inventory_vs_gl`; phase97 after phase96 drops all bos96 lines; phase76 after phase94 brings back old `inbound_message_receive` / `web_order_submit` signatures | **Invariant (PASTE_ORDER.md): if phase89, 94, 96, 97, 98 or 99 is ever pasted again, paste phase98 (only if it was 89/94/96/97) and then phase103 again.** phase103 carries the final text of 20 functions and one paste repairs a re-paste of phase89. Then re-run `phase89c`, `phase89d`/`89e`, `phase94`, `phase96`, `phase98`, `phase99`, `phase101`, `phase103` tests | `docs/PASTE_ORDER.md` sections C, E, G; step_INT3 and step_E2E reports |
| Two `acct_journal_post` functions (7-argument one is back); manual journal guard ignored | phase21 pasted after phase24, or phase40 / `ALL_NEW10.sql` pasted after phase85 | Paste phase89 again (it removes the old overload), then phase98 / phase103 again | `docs/PASTE_ORDER.md` section A |
| Two versions of `inbound_message_receive` / `web_order_submit` (ambiguous call) | phase76 pasted again after phase94 | Never paste phase76 after phase94. Fix on the database: paste phase94 again (it drops the old overloads) | step_Sec report, PASTE_ORDER row 24 |
| After phase89 re-paste, `phase89_test` P2 "second paste identical" fails | By design: phase89 is no longer the end of the chain once 96/97/103 exist | Use `phase89c_test.sql` / `phase89e_test.sql` (P2 = 89 then 98/103 = identical). Never edit `phase89_test.sql`; the same applies to `phase98_test` P1b/G1 -> `phase98b_test.sql` | step_INT3 and step_E2E reports |
| A new phase of yours erases a tag of an older phase | You re-created a function from an old file text | Take the LATEST body with `pg_get_functiondef`, change only your own lines, keep every `bosNN`, and merge into the last file of the chain (see DEVELOPER_RUNBOOK.md) | `docs/PASTE_ORDER.md` sections D, F, G |
| Paste of `phase102.sql` is not in the numbered table | Built in parallel (item images); no accounting function touched | If used, paste between 101 and 103; phase103 does not need it | `docs/PASTE_ORDER.md` row (31) |

How to prove a tag is present: `select position('bos98' in pg_get_functiondef('public._acct_docs(date)'::regprocedure));` (0 = missing).

## 2. Costs and accounting

| Symptom | Cause | Fix | Evidence |
|---|---|---|---|
| Documents "waiting" in the books (`cost_missing`, list from `cost_wait_list96`); `inventory_vs_gl` shows "waiting for cost" | A stock move (wastage, production ingredient/finished good, count gain/loss, opening, own-use issue, transfer, purchase return) has no known unit cost. By design it is NOT posted and NOT guessed | Supply the cost: `cost_wait_supply96` (owner or cost-right holder; item_average / last_purchase / recipe_standard / manual with reason). For opening stock use `opening_stock_apply96` (owner, client id). The document then posts once. If the item's cost is really zero, mark it free with `item_cost_free_set` (phase 80). Set `acct_cost_wait_alert_days` to get an alert | phase96, step_D23, step_E2E (D-1..D-3) |
| Production refused with `cost_missing` (detail lists ingredients) | Rule `production_requires_cost = refuse` and an ingredient average cost is NULL or 0 | Buy/open the ingredient with a cost, flag it free if truly zero, or set the rule back to `warn` | phase72, phase79 `production_post` |
| Finished good has no cost; profit shows "provisional / unknown cost revenue" | Cost 0 or blank counts as unknown (phase 72) | Same as above; look at `#/costunknown` (`costboard.js`) and `profit_source_check` | phase72, phase88 |
| Opening stock counted twice (opening journal + ledger posting) | Switch `acct_stock_opening` turned on while the opening journal already carries the stock | Run `opening_stock_check96` (read-only) / `opening_stock_recommend96`, then choose owner_capital / existing_account / skip / difference in `opening_stock_apply96` | phase96, phase103 D-3 |
| Reports show different costs on different screens | Old screens read hand-typed `item_costs`, journal reads ledger | Rule `report_cost_source` (phase 88): `ledger_then_item_costs` default | phase88 |
| Trial balance difference / unbalanced entry | Should not exist (entries must balance; rounding remainder goes on the largest part). Failures are listed | `acct_status()` -> errors (`acct_post_errors72`); fix the cause, the tick retries | phase72 |
| Entry not posted for a date | `accounting_on` OFF, before `accounting_start_date`, or period locked (`period_closed_until`) | Check `acct_status()` (last post, pending, locked, errors); the period lock is respected by the autopost (phase 85) | phase40, phase85 |
| `inventory_vs_gl` unexplained difference | Something bypassed the engine (manual journal to an inventory account, older posting) | Read the reasons block, `manual_journal_guard`, `dup_suspects`; do not edit the ledger - post a reversing/adjusting entry | phase72, phase103 |

## 3. Stock

| Symptom | Cause | Fix | Evidence |
|---|---|---|---|
| **Double count of GRN**: bought goods counted twice in stock (bill + GRN) | Both the purchase page and an approved GRN (13-1) add stock. Rule `grn_receipt_source` decides the single source (default `purchase`; GRN in-lines are then skipped with reason `covered_by_purchase_page`). If the source is `grn` and `purchase_grn_guard = off`, a bill still adds its own stock | Set `grn_receipt_source` to the one real source; when it is `grn` set `purchase_grn_guard` = `skip` (bill records money only) or `link`. Check `receipt_duplicates()` and `grn_pending_report()`; setup advisor flow check `flw_grn_double103` warns and recommends `skip` | phase23 A1, phase82 E1, phase103 D-5 |
| **Negative stock** (yellow exception "stock is now negative", or error when blocked) | More went out than on hand. Mode `stock_negative_mode` allow / warn / block (default warn). A late offline sale never blocks. Tracked items never opened are "not started", not negative | Enter the missing receipt/opening (`stock_opening`) or count (`stock_count_adjust`, grant); to sell anyway use grant `sell_below_zero` (once) or an approved emergency request. List: `never_opened_negative_items()`. Prove cache: `stock_reconcile()` (`p_fix` logs the fix). Offline sale refused for short stock: rule `offline_soft_stock` or manager override | phase10, phase82 E4, phase83 |
| `unit_unknown` on posting | Unit conversion for a tracked item missing | Add the conversion (`unit_conversions`); list with `unit_unknown_items()`; rule `unit_conv_required` | phase82 E3 |
| Cache and ledger disagree | Should not happen (trigger); known only in fixture suites | `stock_reconcile(false)` to see, `true` to repair (logged) | phase10, phase84 |
| Void of posted bill refused | `purchase_void_guard = refuse` (returns / negative stock / live GRN batch) | Do a purchase return, or set `warn`; payments: `purchase_void_payments` void/keep | phase82 E2 |
| Sale from expired batch | `expiry_sale_guard` / `block_expired_sale` | Choose off / warn / refuse | phase87 |

## 4. Shadow copies and paths

| Symptom | Cause | Fix | Evidence |
|---|---|---|---|
| **Shadow link pending** (`shadow_links.state = 'pending'`) for payroll month, 19-1 register, quick expenses ... | The second path has not been filled/confirmed yet; a pending shadow is normal and is never counted | Open `#/paths`; `shadow_report(domain, loc)` lists them. Confirm with `shadow_confirm(link)` (expenses: one click confirms the day's 11-1 voucher), or `shadow_void(link, note)` if wrong. Run `shadow_count_once_check()` and `daybook_vs_journal` to prove nothing is double counted | phase48, phase49, phase50 |
| Error `path_locked: <domain> path a|b is locked here by the owner` | The owner locked that path for the place (`path_switch.a_open/b_open = false`) | Use the open path, or the owner changes it with `path_switch_set(domain, loc, a_open, b_open, primary, note)` | `phase48.sql path_guard` |
| Same payroll/expense/stock event counted twice | Both paths posted | Owner chooses the primary (`a`/`b`/`first`); `dup_suspects(from, to)` lists look-alikes; legacy `forms_post_to_ledger` keeps the form as primary | phase49, phase51 |
| Form 20-x without a sale | Not linked | `unlinked_sale_forms()`, owner links | phase61 |

## 5. Edge functions and intake

| Symptom | Cause | Fix | Evidence |
|---|---|---|---|
| **scan-extract answers 409** | One of: (a) job status not `uploaded`/`extracted` (`not_open`); (b) rule `scan_engine` is not `ai_vision` (`engine_is_not_ai_vision`); (c) `scan_ai_gate94` is missing/failed - the new edge code is deployed before **phase94 was pasted** (any gate error except `too_many_attempts` is returned as 409 `not_open`) | (a) create a new job; (b) owner sets `scan_engine = ai_vision`; (c) paste phase94 first, then deploy the edge code | `scan-extract/index.ts`, step_Sec report section 5 |
| scan-extract 503 `not_configured` | Missing `Authorization`, `SCAN_AI_MODEL` or `ANTHROPIC_API_KEY` | Set the Supabase secrets (names only in SCAN_SETUP.md) | index.ts |
| scan-extract 429 `too_many_attempts` | Owner limits `scan_ai_max_per_job` / `scan_ai_max_per_user_day` reached | Raise or clear the rule | phase94 M4 |
| scan-extract 502 / 422 | Model error / unreadable photo (`photo_unreadable`, `photo_size`, `bad_model_output`) / save refused (`save_failed`, fixed code since bos94) | Retake the photo (<= ~3 MB), or enter manually | index.ts |
| **Telegram 403** from `telegram-webhook` | `TELEGRAM_SECRET_TOKEN` unset (fails closed since bos94), or the `X-Telegram-Bot-Api-Secret-Token` header differs from it, or the DB check failed (hash stored by `telegram_secret_set` differs / channel unknown or secret-less) | Set the Supabase secret to the SAME value given to `setWebhook`, and give it once to the app (Inbox > Channels > "Set secret token"). A wrong token also leaves a "rejected" line (no body) in the failed list | `telegram-webhook/index.ts`, docs/TELEGRAM_SETUP.md |
| Telegram 503 `retry` / `bot_login` | Intake bot login failed, DB unreachable, or switch `inbox_on` / telegram intake is OFF (message not stored; Telegram resends for a while) | Check `INTAKE_BOT_EMAIL/PASSWORD`, `intake_bot_check(user)`, switches | index.ts |
| Telegram status unverified | No real Telegram call was ever made; the Update field names were written from memory | Verify against the current Bot API before deploy | header of index.ts, TELEGRAM_SETUP.md |
| Messages arrive but failed list grows | Intake errors | `intake_failures` retried by `intake_retry_due()` (`intake_max_tries`, `intake_retry_min`); clean with `intake_purge(days)` | phase76, phase94 |
| Web order refused | Rate limit (`web_form_rate_max` per `web_form_rate_window_min`), captcha/proof, inactive item | Raise limit / fix proof (`intake_proof_status94`) | phase76 |

## 6. Web app and offline

| Symptom | Cause | Fix | Evidence |
|---|---|---|---|
| **Service-worker cache mixing**: after a deploy the phone shows a mix of old and new screens, or an old script with a new `index.html` | `sw.js` caches each same-origin GET separately (network first, cache fallback). When the network is flaky or the app is offline, each file falls back independently, so files from different deployments can be combined; `bos-sw-*` caches of an older `VERSION` also survive until activate | Bump `VERSION` in `web/sw.js` on every deploy that changes script names/order (activate deletes older `bos-sw-*`); on a phone set `localStorage.bos_sw = 'off'` or switch rule `offline_cache_on` OFF (swreg unregisters and clears `bos-sw-*`); the worker only runs on `https:` so local dev is never cached. The exact original incident is **not recorded** in the repo (UNKNOWN); the mechanism above is read from the code | `web/sw.js`, `web/swreg.js` |
| Offline sale shows as a "failed card" | Replay refused for a business reason (`insufficient_stock`, `period_closed`, `client_id_taken` ...) | Owner board counts them; manager override `pos_replay_override` with the original client id, or export JSON and discard | `web/pos.js`, `web/posfail.js` |
| `period_closed` toast | Date is in a closed period (`period_closed_until`) | Owner edits, or an emergency grant `closed_period_edit` is offered | `web/app.js fail()` |
| List stops at 1000 rows | Server cut | Use `BOS_ALL` (`pager.js`) | pager.js |
| New screen missing from the menu | Not in `web/ia.js` or script not in `index.html` | See DEVELOPER_RUNBOOK; `tests/web/order_test.js` and `ia_test.js` catch it | tests |
| On-screen keyboard hides buttons / iOS zoom | Fixed in `kbdfix.js` (bos102) and 16 px inputs in `theme.css` (bos94) | Make sure both are loaded; real-phone check **UNVERIFIED** | step_Sec, step_Pol |

## 7. Tests that fail "as expected"
`tests/sql/baseline_fails.txt` records the known failing assertions (31 fails at INT/E2E, all understood; older INT3 count was 22). `run_all_sql.sh` exits 0 only if every suite equals the baseline. A number that changes must be edited in the same commit. `phase73` shows 2 fails even without phase103 (owner self-approve, T4) - pre-existing. See DEVELOPER_RUNBOOK.md section 3.
