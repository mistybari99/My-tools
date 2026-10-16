# docs/demo: fictional demo and planning material

These files are **fictional demo and planning material**.

- They contain **invented names** (for example the roster in `DEMO_STAFF_ROSTER.md`) and **invented numbers**.
- They are **NOT part of the app**.
- They must **never be imported, bundled, served, seeded or pasted into any database**, live or test.
- No code in `web/`, `supabase/`, `data/` or `tools/` may read, link or copy them.
- Use them only as reading material and as a script for a demo in a **test project**.

Guard: run `python3 tools/check_no_demo_leak.py` from the repo root. It fails if app code references `docs/demo`, a demo file name or a demo staff name, or if `tools/build_kb.py` could read `docs/demo`.

Files here: `DEMO_DAY_SCREENS_STORIES_LEDGER_EN.md`, `DEMO_FULL_WORKFLOW_AND_LEDGER.md`, `DEMO_STAFF_ROSTER.md`, `FINAL_DEMO_BUSINESS_GUIDE.md`, `IMAGINED_FUTURE_SYSTEM_DEMO.md`, `REAL_LIFE_DAILY_WORKFLOW_GUIDE.md`, `REAL_LIFE_STORY_GUIDE.md`.
