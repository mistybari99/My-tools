# AI helpers: deployment guide (X4)

Status: built, NOT deployed. Nothing here calls a model until the owner does the steps below. Until then every AI switch is OFF and the app answers with the free on-phone router only.

## 1. What is in the app
- `ai_on` (OFF), `ai_pause_all` (OFF, the emergency stop), `ai_default_provider` (`local_rules`), `ai_speech_on` (OFF). Each has an (i) entry in `web/data/info.json`.
- Providers: `local_rules` (on, free), `anthropic`, `openai_compatible`, `gemini`, `custom_http` (all OFF, no key, no budget).
- Ten agents, all OFF. Each has its own provider, data scope, read tools, proposal actions, budget and approval rule.
- Every AI call, refusal, timeout and proposal lands in `ai_calls` (append-only, `actor_type` = human or agent).

## 2. Before you link a provider (owner decisions)
1. Choose the provider and a model name (typed in AI settings; the app never guesses a model).
2. Set a monthly budget: tokens, money, or both. A paid provider with no budget cannot run. Money is estimated only from prices you type; a blank price shows "price not set", never a made-up figure.
3. Keep data sharing at `none` unless you need more. `redacted` lets summaries leave the phone after redaction; `full` lets detail rows leave. Business data should not leave the phone at `full` without a reason.
4. Decide who approves: `owner` or `approver` per agent.

## 3. Put the key in a Supabase secret (never in the app, the repo or a table)
From a computer with the Supabase CLI, logged in to the owner's project:

    supabase secrets set AI_KEY_ANTHROPIC=<the key>          # use the code of the provider row, upper case
    supabase secrets set AI_KEY_OPENAI_COMPATIBLE=<the key>
    supabase secrets set AI_KEY_GEMINI=<the key>
    supabase secrets set AI_KEY_CUSTOM_HTTP=<the key> AI_URL_CUSTOM_HTTP=<https base URL>

The key is read only inside the Edge Function. The database never stores it (no column exists for it; `phase510_test.sql` checks this).

## 4. Deploy the Edge Function (owner, once)
    supabase functions deploy ai-proxy

Source: `tools/edge/ai-proxy.ts`. It re-checks everything in the database as the signed-in person (`ai_check`), redacts again, enforces the provider timeout and output cap, logs the token counts (`ai_log`) and returns tool calls and an output. It never runs a tool itself.

## 5. Turn it on, step by step (each step is a separate owner action)
1. Run the SQL: paste `phase510`, then `phase511` (paste-twice safe). Check: `ai_on` is still OFF.
2. In AI settings: enable the provider, set the model, the budget and the data level.
3. Enable one agent at a time (`ai_agent_save`). Start with `erp_guide` (read tools only).
4. Turn `ai_on` ON.
5. Watch the scorecard and the usage panel for one week. If anything looks wrong, press the emergency stop (`ai_pause_all` ON). It stops every agent and every provider at once.

Untrusted input (customer messages, web pages, photos): the agents that read these (`enquiry_classifier`, `order_assistant`, `market_summariser`, `camera_matcher`) get read tools only. Their output is a suggestion. A person creates any order, price or reply.

## 6. What the owner's text becomes
Suggestions, decisions and later outcomes are business memory for review. They are not used to train any model. A suggestion is never authoritative: only a verified knowledge entry (propose, then another owner verifies, then publish) is quoted as an approved rule.

## 7. Limits and known gaps
- The core (`web/ai_core.js`, tests in `tests/web/ai_core_test.js`) and the database (`phase510_test.sql`, `phase511_test.sql`) are tested with a mock provider and a throwaway Postgres. The Edge Function is source only and has not been run against a live provider (no key, no network in the build).
- Money estimates depend on the prices you type. Check them against your provider's bill.
- Proposals are suggestion rows until X1's `action_proposals` table exists; see `docs/integration/X4.md` for the adapter.
- Speech-to-text and the agent screens are switched off until the owner turns them on (`ai_speech_on`).

## 8. Stop or roll back
- Emergency: `ai_pause_all` ON (owner, Settings). Immediate for every agent and provider.
- Per provider: untick enabled. Per agent: untick enabled. Budgets can be lowered at any time.
- Nothing is deleted. Retired knowledge and disabled agents keep their history.
