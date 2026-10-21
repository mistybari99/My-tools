# Backend and developer documentation (English)

Scope: the Supabase (Postgres) backend, the plain-JavaScript web app, the two source-only edge functions, and how to extend, test and deploy them.
Language rule (owner rule): all backend and developer documentation is written in English. The app UI itself is trilingual (bn / mix / en) through `B.L`; that is a UI concern and is not documented here.

Every statement below is taken from files in this repository. Where something could not be verified from the repository it is marked **UNKNOWN** or **UNVERIFIED**. No secrets, keys, passwords or personal names are (or may ever be) written in these files.

## Reading order

| File | Read it when you need to know |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | The layers, the module map of phases 8..103 (+ web-only steps), the shadow-copy engine, costing layers, accounting engine, stock engine, `inventory_vs_gl` |
| [DATA_FLOW.md](DATA_FLOW.md) | Sequence diagrams: purchase, GRN, production, sale, return, landed cost, card settlement, online/inbox/Telegram intake, offline POS replay, scan |
| [SECURITY_MODEL.md](SECURITY_MODEL.md) | Grants, cost secrecy, RLS patterns, PII masking, idempotency, append-only trails, intake bot, anon revokes, secrets, owner-only duties |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Symptom -> cause -> fix tables for problems that were actually met |
| [DEVELOPER_RUNBOOK.md](DEVELOPER_RUNBOOK.md) | How to add a phase safely, how to run the tests, how to deploy, branch/worktree conventions |

## Repository map (as found in this tree)

| Path | What it holds |
|---|---|
| `supabase/schema.sql`, `phase2.sql` ... `phase103.sql`, `ALL_NEW*.sql` | The database. One additive, paste-twice-safe file per phase; `ALL_NEW*.sql` are older bundles of phases 5..28 |
| `supabase/phaseNN_test.sql` | One SQL test suite per phase (copies `phaseNNb_test.sql` where an old assertion became false by design) |
| `supabase/functions/scan-extract`, `supabase/functions/telegram-webhook` | Edge function **sources** (never deployed or run from this repo) |
| `tools/edge/` (`assistant-proxy.ts`, `meta-webhook.ts`, `web-order.ts`) | More edge sources; `tools/*.py` are ops scripts (backup, restore drill, notify, fingerprint bridge, item import) |
| `web/` | The app: static files, no build step, scripts loaded in order from `web/index.html`; `web/ia.js` is the single registry of screens |
| `tests/sql/` | Build scripts (`final_build.sh`, `run_all_sql.sh`), `baseline_fails.txt`, `e2e/`, `p9/` |
| `tests/web/` | Node tests (`*_test.js`), `run_all.sh`, `order_test.js`, `README_TESTS.md` |
| `tests/py/` | Python test for item import |
| `docs/PASTE_ORDER.md` | The single canonical SQL paste order and the rules for the next phase |
| `docs/briefs_p2p3/*_REPORT.md` | One report per step: what was built, test numbers, what is NOT done |
| `.github/workflows/` | `backup.yml`, `notify.yml` (scheduled ops; need secrets stored in GitHub, never in the repo) |

## Principles that hold across the whole backend

1. **Additive and paste-twice safe.** A phase never edits an older phase file; it only `create or replace`s functions and `create ... if not exists`. Pasting twice must give no error and no change.
2. **Every default equals today's behaviour.** New switches are OFF or empty until the owner decides; the system may only *recommend* (setup advisor).
3. **Nothing is deleted.** Retire with an `active`/void flag; mistakes are fixed by a reversing row. Audit tables are append-only.
4. **Writes only through `SECURITY DEFINER` functions;** tables are read-only for the browser through RLS and column grants.
5. **Count once.** One primary record plus locked shadow copies; postings are unique on `(source_type, source_id)`.
6. **Nothing is invented.** A missing cost stays "unknown" and waits; it is never guessed.
