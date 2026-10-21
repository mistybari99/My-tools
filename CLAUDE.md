# Rules for every agent and contributor (read before any work)

## Demo and fictional material must never enter this repository
- Fictional demo staff, invented names, invented balance sheets, demo stories, demo rosters and "imagined system" documents are NOT part of this product.
- Never commit, push, seed, paste or reference them: not in code, SQL, seeds, tests, docs, the knowledge base (`web/data/kb.json`) or any database.
- Never create staff, users, roles, entries or fixtures from fictional names. Test fixtures use neutral `test_*` identifiers only.
- Never add a `docs/demo/` folder or any file named like `DEMO_*`, `IMAGINED_*`, `FINAL_DEMO_*`, `REAL_LIFE_STORY_*`, `REAL_LIFE_DAILY_*`.
- If the owner asks for a demo or a story, write it outside the repository (scratch folder) and hand the file to the owner. Do not push it.
- Check before every commit and every push: `python3 tools/check_no_demo_leak.py` (must print OK). GitHub also runs it on every push and pull request.

## Database safety
- Never write to the live Supabase project from an agent. Local throwaway Postgres only for tests. The owner pastes SQL himself after review.
- `supabase/phase84_test_project_only.sql` is for test projects only and must never be pasted into the live project.

## Build discipline
- Follow `docs/BUILD-RULES.md`. New SQL goes in a new phase file; do not edit old phase files. SQL must be safe to paste twice.
- Every journal entry must balance (Dr = Cr). New behaviour is OFF or safe by default.
- Every owner decision is a setting with a safe default; new behaviour starts only when the owner switches it on or from its effective-from date.
- Register new screens only through `web/ia.js` (see `docs/IA_RULES.md`).
- Printed form codes (NN-1, A-Z by English short name, owner decision 21 Oct 2026): the rule is `docs/FORM_SEQUENCE.md`. Change a code only through `tools/renumber.py` and a numbered phase, never by hand.
