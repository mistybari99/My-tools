# Architecture and UI/UX design (merged, decided)

Status: proposal for the owner to approve. Builders execute it after approval. Date: 2026-10-16. Branch: `worktree-agent-a8a411701d915b2be`.

This document merges three proposals and two debate rounds into one design:

| Source | Short name | Position |
|---|---|---|
| Architecture proposal X | X | Jobs and roles: a person sees their jobs for today |
| Architecture proposal Y | Y | Modules and objects: one kit, power for long sessions |
| Architecture proposal Z | Z | UI and UX system: 8 templates, tokens, interaction rules |
| Audits C (usability) and D (compact screens) | C, D | Findings and patterns the three proposals build on |
| Debate round 2 (X, Y, Z) | R2 | Questions, attacks, adoptions, tie-breakers |

Evidence tags used everywhere: **[code]** read in this worktree; **[baseline]** counted in `tests/ui_inventory/baseline.json` (branch `worktree-agent-af358bfac93193f23`, commit `ac004ce`); **[model]** computed from a height model, not measured on a device; **[unverified]** needs a device, real data or the live database; **PV-n** provisional decision until a named test.

Standing rules applied to every line: nothing is lost (no form name, form code, field, option, route, menu entry or button removed or silently renamed); every policy is a setting with a safe default; every new behaviour has a per-phone switch with instant rollback; labels are written in English first (Bangla translation comes later, through the existing three-mode `L(bn, en, mix)` pattern and `tools/glossary.py`); no demo material, no live database writes (CLAUDE.md).

---

## Owner summary (one page)

**What your people will see**

- They open the app on **Today**: their own jobs, at most 6 big cards, the main job as one big round button. Every person gets the same five buttons in the same places: **Today, Find, main job, To do, Menu**.
- Everything else is under **Menu**: 8 areas (Sell, Goods, Make, Money, People, Checks, Reports, Setup), the 42 paper forms in paper-book order, an A-Z list of every screen, and the **Classic** menu (the old 13 categories, kept).
- **Find** finds anything: screens, jobs, form codes (`04-1`), old names ("GRN"), receipt and phone numbers, and settings by plain sentence.
- Jobs that exist as a paper form and as a screen become **one job with two ways**. Both ways stay. A small line says which one counts.

**What you get as owner**

- **Show everything**: every screen, nothing folded, locked screens greyed with the reason. **See as role**: preview what a role sees.
- One **Checks inbox** for approvals and exceptions. A **Day board**: for each shop, was it opened, the drawer counted, the cash handed over, anything skipped and why.
- **Setup** as a path: a 13-step checklist, nine purpose cards over about 297 rules, three dials (Relaxed, Normal, Strict), three business shapes. Every change shows a preview and can be undone.

**Nothing is lost, proved by machine**

- `tests/ui_inventory/baseline.json` freezes 6,917 items: 102 routes, 91 registered pages (8 not yet in the menu), 45 form codes (42 paper forms plus 3 permission codes), 1,742 form fields, 662 form options, 895 buttons, 405 server calls, 445 setting keys [baseline].
- After every build step `python3 tools/check_ui_inventory.py` must pass. A rename needs a written reason in `aliases.json`. This design asks for **no** route, form, field, option or button rename.
- The old screens stay in the code. Switch off the new design on a phone and that phone shows today's app, byte for byte.

**Shorter screens [model, to be measured in step 0]**

| Screen | Now | After |
|---|---:|---:|
| Home | 4.5 pages | 1.0 (staff) to 1.3 (owner) |
| Daily showroom sheet 14-1 | 12.5 pages | 6.3 in total, at most 2.5 per step |
| Switchboard | 18 pages | 1.6 |
| Role x form matrix | 6.3 pages | 1.3 |
| Expense voucher 10-2 | 3.7 pages | 1.4 |

**Easy to teach**: staff learn three things (Today, Find, Menu). A 10-minute script and a printed card per role are generated from the registry. A new person passes if they do their role's 5 jobs alone in 10 minutes.

**Safe to roll out**: owner phone first, then one shop for a week, then everyone. Each phone keeps its own off switch for the first month. Three safety fixes come before any screen is folded (section 6).

**Cost**: about 144 developer-days for the core, plus 24 gated days that are built only if a test says so. The current Wave 3 plan has 88 days without the optional item. The extra 56 days buy the front door, the job page, the owner Day board, record pages, big type, and the preservation gate. Section 7 shows each package.

**Three decisions stay provisional until a test** (the cheapest default is already chosen, and each is reversible by one setting):

1. **PV-1** Job tile tap: open a new entry (default for people who enter data) or open the list. Test: receive-goods task and find-yesterday's-record task.
2. **PV-2** Menu vocabulary: 8 areas (default) or 12 modules. Test: tree test with 28 tasks.
3. **PV-3** How much to invest in grids, desktop layout and keyboard keys. Default: grids off per job until the timed 30-line entry test passes; desktop layer not built until the usage log shows enough laptop use.

**What I need from you** (details in section 8): approve the front door; choose the default way for each two-way job (27, with a safe default already in place); confirm role start kits; confirm the three business-shape values; decide if salespeople see shop totals (default: no, only "My sales today"); decide who may use Show everything (default: owner only); agree to the usage log (default: off until you agree).

---

## 1. Decision summary (one page)

### 1.1 The decided design in 21 lines

| # | Decision | Final default | Status |
|---|---|---|---|
| D01 | Front door | **Today**: permission-derived job cards (max 6), one main job, "Now" line, collapsed Numbers. Owner adds Needs you and the Day board | Decided |
| D02 | Navigation | Menu lists **8 areas** (page per area: Jobs, More, Forms strip, Show all). **12 modules** stay as index and as the "Modules view" preset. **Classic** (13 categories) stays | **PV-2** |
| D03 | Bottom bar | `Today / Find / main job / To do / Menu`. One-word labels, same positions for everyone, only the main job and the badges change | Decided |
| D04 | Chrome | Header 56 px, optional context strip 32, state strip 36 only when needed, **one bottom region at a time**. Chrome at most 30% of the window | Decided |
| D05 | Control Center | `#/control` becomes the **Setup** front page. Title stays "Control Center"; "Setup" is the area name. The 12 tiles and 8 extras stay under "All Setup screens" | Decided |
| D06 | Search | **Find** as a full-screen page: sections Do, Go, Forms, Things, Settings. Number resolver. Old names matched. Browse always exists. Desktop palette and keyboard keys are gated | Decided (keys: PV-3) |
| D07 | Job page | Job card + document hub: Way strip, one status line, merged Records list, linked-copy chip. Tile opens a new entry for people who enter, the list for approvers | Decided (tap mode: **PV-1**) |
| D08 | Record pages | **Object Kit, reduced**: Customer, Item, Supplier, Employee. Tabs: Overview, Activity, Money, History, More (max 5). Drill-down only along existing keys | Decided (drill: gated) |
| D09 | Grid Kit | Five jobs: purchase lines, stock count (blind), production run, attendance register, price list. Phone form = compact rows + half-height "Add line" sheet | **PV-3** (flags off until test) |
| D10 | Checks inbox | One inbox, filter chips, age and amount, inline decision only for low-risk kinds, no bulk approve for money, price, period or posting | Decided |
| D11 | Day board | Owner block, one card per place, read-only, built from existing timestamps. Time windows off by default. Staff see only their own record | Decided |
| D12 | Settings | **Nine purpose cards**, dials Relaxed/Normal/Strict/Custom, three business shapes, 13-step checklist, preview diff, 10-second undo, revert | Decided |
| D13 | Confirm ladder | **A0 to A4**; no browser `confirm()` or `prompt()`; undo only for reversible non-money writes | Decided |
| D14 | Type and touch | Body 14 px, floor 12 px, inputs 16 px, targets 48 px (icon buttons 44), edges 3:1, Text size S/L/X | Decided |
| D15 | Home size | Staff Today about 1.0 page, owner about 1.3, hard cap 1.5 | Decided |
| D16 | Desktop layer | Master-detail, dense table, keyboard keys, scan sink: **not built** until the usage log passes | **PV-3** |
| D17 | Show everything | Per phone, owner only by default, visible pill, locked rows greyed with reason, "See as role" preview | Decided |
| D18 | Rollout | Master switch `ia_arch_v1` (rule, default off) plus per-phone key; each capability has its own off switch; Classic one tap | Decided |
| D19 | Preservation | Inventory gate after every package; map tool; DOM parity test; zero renames | Decided |
| D20 | Language | English labels first; `LANGUAGE.md` three modes kept; Bng-Eng wording tested with a reading test | Decided |
| D21 | Order | Safety fixes first, controls backlog (Audit A/B) outranks anything not on the beginner's path, tokens and shell next, then front door, then productivity | Decided |

### 1.2 One app, several doors (nothing removed, each view stays reachable)

| View | How a person gets there | Who it is for | Kept as |
|---|---|---|---|
| **Today** (default) | Opens at sign-in; bottom-bar `Today` | Everyone | The front door |
| **Areas** (8) | `Menu` > area row | Everyone | Default Menu |
| **Modules** (12) | Me > "Menu view: Modules", or `Show everything` | Power users, accountants, owner | Preset `nav_view=modules`; the `module` field of every record |
| **Classic** (13 categories) | `Menu` > Classic; Me > "Classic view" turns the whole new design off for this phone | Anyone who prefers the old menu | Old drawer and `#/group/<id>` pages, unchanged for at least two releases |
| **A-Z** | `Menu` > All screens | Anyone | Every record, alphabetical |
| **Forms** (paper-book order) | `Menu` > Forms; area page Forms strip; Find by code | Paper-trained staff, owner | All 42 codes with today's status |
| **Find** | Bottom bar, header icon | Everyone | Any screen, job, form code, old name |
| **Show everything** | Pill in the context strip (owner) | Owner | Nothing folded, nothing hidden |

### 1.3 Numbers that bind every builder

| Measure | Value | Where it comes from |
|---|---|---|
| Registered routes | 102 now, 110 after the 8 pending screens are registered | [baseline] 102 routes; 8 pages without route (`bankreceipt`, `freshness`, `moneycontrols`, `openparties`, `otherincome`, `periodlock`, `profitcheck`, `returnrules`) |
| Form codes | 42 paper forms + `ITEMS`, `ITEM_COST`, `POS` permission codes | [baseline] 45 form items |
| Reach | Find at most 3 taps; A-Z at most 3; area page "Every day" row at most 3; folded row at most 4; Forms door at most 3 | X's contract, corrected in R2 (folds counted) |
| Taps to start a daily job | average at most 1.42 over 52 jobs (now 2.56) | Audit C |
| Chrome | at most 30% of a 360x640 window (180 px of 600 visible) | Z |
| Type | body 14 px, smallest text 12 px, inputs 16 px | Z; today body 12.5 and 216 of 254 inline sizes are under 12 px [code, Z] |
| Touch | 48 px controls, 44 px icon buttons and chips, 8 px gap, 56 px confirm buttons | Z |
| Pages | Today <= 1.5, area page <= 1.2, job screen first view <= 1.5, settings card <= 0.8 | X, Z |
| Today load | at most 8 requests and 1.5 s on the cheapest phone at 3G | TB6 below |

---

## 2. Decision records: who proposed what, who won, what settles it

Format of each record: **Proposed** (X, Y, Z), **Winner and why**, **Evidence**, **Tie-breaker** (a measurable test), **Status**. Test protocols TB1 to TB10 are defined once in 2.2.

### 2.1 The records

**D01 Front door**

| | |
|---|---|
| Proposed | **X**: Today of permission-derived jobs (Now line, max 6 cards, orb); areas behind it. **Y**: 12 object modules are the spine; beginners get a "My day" Workbench from role presets (X objected that the 76-day plan has no line for it; Y conceded in R2). **Z**: neutral; one-page Home (primary job, Do next, shortcuts, numbers). |
| Winner | **X.** Y conceded (X1, X2: "the Workbench is X's Today"); Z merged its Home into X's job cards (Z R2 3.1). |
| Why | Home is 4.5 pages and shows POS five ways (C-01). `persona()` guesses wrong for at least five seeded roles: showroom manager lands in the hub list, cash controller is "accountant", management gets entry shortcuts it cannot use, purchasing and HR fall to "cashier" [code, X F3]. A job list read from `role_form_perms` and grants needs no new permission logic. |
| Evidence | Taps for the top 25 jobs: 68 to 27 (2.72 to 1.08) [code-derived, X 2.4]; 52 jobs: 2.56 to 1.42 (Audit C). |
| Tie-breaker | **TB2 new-hire test** and Today <= 1.3 pages, 52-job average <= 1.42 taps. Failing role: fix its kit, never blame the user; the phone can go Classic. |
| Status | Decided |

**D02 Menu vocabulary: 8 areas, 12 modules, or Audit C's 9 areas**

| | |
|---|---|
| Proposed | **X**: 8 areas (Buy merged into Goods). **Y**: 12 modules as the staff-facing tree; Audit C's 9 areas as a "Simple view" preset. **Z**: areas are the view, objects are the index (R2). |
| Winner | **8 areas as the default view; the `module` field (12) kept as index and as preset `nav_view=modules`.** Every record carries both `area` and `module`, so the choice is one field read. |
| Why | Fewer top-level concepts for a staff member (a seller sees one area). X's own concession: its areas are a coarse module list. Y's argument that an object list is closed under growth is met by a mandatory `area`+`sec` on every record plus a default mapping from the legacy `group`. |
| Evidence | 110 records after wiring; both X (ledger 10.1) and Y (Appendix A) placed every one without discussion. |
| Tie-breaker | **TB1 tree test**: 28 tasks (10 daily, 10 rare, 8 trace), 15 people per tree. A gap of 10 points or more in directness or success decides; below that the tree with fewer top-level rows wins (8 areas). |
| Status | **PV-2 provisional until test.** Cheapest to reverse: change which field the Menu reads. |

**D03 Bottom bar**

| | |
|---|---|
| Proposed | **X**: `Today, Find, orb, To do, Menu`. **Y**: keep the bar in phases 1-2; Search replaces Me only if the owner agrees. **Z**: `Home, Do next, orb, Search, Menu`, then adopted X's names and order. |
| Winner | **X's names and order, Z's constraints**: one-word labels (at most 8 Bangla letters), icon-only fallback instead of clipping, no sixth slot. Me moves to the top row of Menu and the Me sheet. |
| Why | Today shows jobs; **To do** shows things waiting on me. A thing is a job card on Today or a waiting item in To do, never both; the Now line on Today is only the top item of To do (fixes the duplicate Z-A found in R2). Fixed positions keep muscle memory for people who cover another shift. |
| Evidence | Label clipping: "Me" and the unsent-sales label are cut at 360 px (C-08, Z E4) [code]. |
| Tie-breaker | T14 (find form 20-3 by number) and a label-comprehension check: 10 labels read aloud, at least 90% say what each does (low-literacy group at least 80%). |
| Status | Decided |

**D04 Header, strips, bottom region, chrome budget**

| | |
|---|---|
| Proposed | **Z**: header 56 px with back/menu, one-line title, subtitle `Area > Section`, find, bell, a menu; one bottom region; chrome <= 30%. **X**: header with place chip, find, help, sync chip, avatar. **Y**: accepts Z's budget. |
| Winner | **Z.** X's place chip moves to the context strip; the sync state is the state strip ("Offline - 3 not sent - Send now"); Help sits in the header menu and as a row on Today. |
| Why | Action bar (68) plus bottom nav (74) stack to 142 px, 18% of a 780 px window, on 6 screens; a long title wraps to 5 lines (Audit D P1) [code, D]. |
| Evidence | `styles.css:412` (stacked bars). |
| Tie-breaker | Automated: chrome <= 30% on all 8 templates at 360x640 in bn, en, mix. |
| Status | Decided |

**D05 Control Center**

| | |
|---|---|
| Proposed | **X**: front page of Setup, title "Setup", "Control Center" as subtitle. **Y**: "Start" section of the Setup module, same URL. **Z**: hub template with Needs-you first. |
| Winner | **All three agree on the structure.** One change: the page title **stays "Control Center"** and the area name "Setup" is the subtitle, because a changed label counts as a rename in the inventory gate. |
| Why | Order on the page: Needs you, Setup checklist (until done), Rules by purpose (9 cards), Access, Places and go-live, Master data, Print and connections, Safety, then "All Setup screens" with the original 12 tiles and 8 extras and their `data-tile` / `data-xtile` hooks. This refines U-35: seven tabs exceed the five-tab cap, so the sections become cards on a hub. |
| Evidence | Settings are spread over 10+ screens (C-16); 27 `settings` records [code]. |
| Tie-breaker | Two owner tasks: "switch on Factory" and "find the rule about mobile number on credit sale", by browse and by search: median <= 60 s, <= 4 taps, no wrong switch. |
| Status | Decided |

**D06 Search / command palette**

| | |
|---|---|
| Proposed | **X**: Find with Do, Go, Forms, Things, Settings; old names matched. **Y**: palette (`Ctrl+K`), prefixes, number resolver, keyboard keys, scan sink. **Z**: Search as a full screen, input focused on open, browse mandatory, recents. |
| Winner | **Z's screen + X's sections + Y's number resolver.** Prefixes (`c:`, `i:`, `#`) are expert-only and hidden. Keyboard keys, desktop overlay and the scan sink go to PV-3. |
| Why | Search is hidden in the drawer and its field is not focused (C-04) [code]. Typing Bangla on a cheap keyboard is slow, so every item also has a browse path (hard rule). Resolver: 11 digits starting `01` is a mobile number; 8 to 13 digits is a barcode; `14-1-main-5` is an entry serial; ambiguous shapes show grouped candidates. |
| Evidence | C-04; `ia.js` `search()` scoring exists [code]. |
| Tie-breaker | T14 (form 20-3 by number then by name, <= 20 s each); T19 (find a screen by typing Bangla: if success is under 80%, browse stays first in the layout). |
| Status | Decided (keys: PV-3) |

**D07 Job page (form and screen as one job)**

| | |
|---|---|
| Proposed | **X**: a job card with an inline two-segment "way switch" and one status line. **Y**: a document hub with surface tabs, merged list, linked-copy chip, paper twin. **Z**: a "Way" chip and a job sheet, later a merged Job page. |
| Winner | **Z's R2 synthesis of X and Y.** Header shows `Job` plus the form-code chip (the form code is never replaced). A 44 px **Way strip** (`Quick screen / Paper-style form 04-1`) on the Job page and the first step of a new entry; after the first typed character it collapses into a subtitle chip. One status line: "Counted from: Quick screen. Paper copy: 2 owed". Merged **Records** list with a `Via` chip and a tappable "Covered by voucher 10-2 #123" chip. Rules, History and paper-twin controls live in the header menu and as end rows. |
| Why | 27 of the 42 forms have a dedicated screen (21 twin, 6 partial); 15 are form-only (from X and Audit C 2.5; each pair is [unverified] until read on screen). Neither way may be removed (BUILD-RULES 1). |
| Rules | Chip words "Counts for stock/money" and "Paper copy" appear **only** where a rule or path row says so (`path_switch` domains: payroll, stock_issue, stock_transfer, stock_count, production, expense, owner_money; rules `grn_receipt_source`, `sale_forms_link_on`). Otherwise the chip says "Two ways". Only 9 of the 27 pairs have a stored fact today [code, X]. A locked way is shown greyed with "Locked by owner on <date>", never hidden. Switching way after typing asks "Keep this as a draft and start a new one?"; no data is converted between the two stores. |
| Tie-breaker | **TB7** (PV-1) and T5b: "which way counts for stock?" at least 90% correct. |
| Status | Decided; **PV-1** for the tile tap: entry-first for people who enter data, list-first for approvers and accountants, per person per job, switchable in the job's menu ("Open on: New or Records"). |

**D08 Record pages (Object Kit, reduced)**

| | |
|---|---|
| Proposed | **Y**: 12 object types, 7 kit parts, 8 tab words, drill from every number, History and Audit tiers. **X**: none, then conceded Y3/Y4 and accepted four nouns. **Z**: template T3 with at most 5 tabs. |
| Winner | **Reduced Y**: record pages for **Customer, Item, Supplier, Employee**, plus the existing document (entry, sale, bill) page. Tabs `Overview / Activity / Money / History / More` (More lists Stock, Related, Files, Settings as rows). `History` for everyone who may see the record; `Changes` (old to new value) only for the owner and holders of a new grant `audit_view`. Drill-down ("Where this comes from") only along keys that already exist: report row to list to document to journal entry (`journal_entries(source_type, source_id)` unique) to stock-ledger row (`stock_ledger.ref_*`) (from Y; not re-checked here, [unverified]). |
| Why | No per-object page exists today; the same customer is spread over Dues, Customers, Tiers and Orders (R2 Y3). |
| Tie-breaker | **TB4**: build the drill-down only if the baseline task "from the April sales total reach the journal entry of receipt R" takes a median over 90 s or over 6 steps; after: at most 4 steps and 30 s. |
| Status | Decided (four nouns); drill-down gated. |

**D09 Grid Kit for heavy entry**

| | |
|---|---|
| Proposed | **Y**: one grid component, ten jobs, Enter/Tab flow, paste, scan, draft per cell, composer on phones. **X**: the job screen is the grid for five jobs (R2). **Z**: compact rows plus a half-height composer sheet opened from the action bar, never a second bottom bar. |
| Winner | **Y's five jobs with Z's phone form.** G1 purchase lines, G2 stock count, G3 production run, G4 attendance register, G5 price list. Each grid calls the same server function as today. **Blind count**: the grid never fetches or renders the book quantity until the count is sealed. Attendance "Fill Present for unmarked" writes an audit note and leaves a marker; no tick-all (Audit D S5). Per-job switch `ui_grid_<job>`. |
| Why | A 20-line bill is 7,000 px today; a 30-line bill costs about 9,900 px of cards [D, model]. |
| Tie-breaker | **TB3** timed 30-line entry. |
| Status | **PV-3** (default: all grid switches off until the test passes) |

**D10 Checks inbox**

| | |
|---|---|
| Proposed | **X**: one inbox, filter chips, age and amount, inline Approve/Reject, escalation hours. **Y**: adopts. **Z**: list template; inline decision only for low-risk kinds. |
| Winner | **X's inbox with Z's rule on inline decisions.** Nine places become one list (`pending`, `exceptions`, `itemreq`, `releases`, `emergency`, `changes`, `staff`, `lists`, wastage), filter chips Mine/All, Entries, Items, Unlock, Emergency, Change, Logins, Wastage, Lists, Limits. Inline Approve/Reject (reject needs a reason) only for kinds in the owner-editable list `checks_inline_kinds` (default: list options, location-setup drafts, exception acknowledgements). Money, price, period, release, emergency and payment kinds open the record and use confirm level A3/A4. **No bulk approve** for those. The old routes stay as filtered views of the same list. The decider is never the maker. |
| Evidence | C-14: approvals are spread over nine screens and four overlapping inboxes. |
| Tie-breaker | T7 (decide two requests <= 60 s, reason entered, 0 critical errors). |
| Status | Decided |

**D11 Day board**

| | |
|---|---|
| Proposed | **X**: places x key jobs matrix from `entries` timestamps, `flow_skips`, `exceptions`, with conformance flags. **Y**: adopts; points out that screen-only jobs have no done-signal and that "entered later" records have a different keying time. **Z**: draws it as one card per place, 5 places = 0.95 page. |
| Winner | **X's content, Y's corrections, Z's drawing.** One card per place with word-plus-glyph chips: Open, Drawer counted, Cash handed, Deposit, Unsent, Exceptions. A chip shows a state only where a done-signal exists; otherwise "Check by hand". It reads the original time of an "entered later" record, not the keying time [unverified: confirm the field in the entry data shape]. Time windows are **off by default**; lateness is shown only where the owner set a window. Staff see only their own on-time record. Whether staff are ranked is an owner decision (default: no ranking). |
| Evidence | Timestamps exist: `entries(created_at, submitted_at, checked_at, status, form_code, location_id)`, `flow_skips`, `exceptions` [code, X F4]. |
| Tie-breaker | One view answers "was the drawer counted in every shop by 21:30?" in <= 1.5 s. |
| Status | Decided |

**D12 Settings by purpose**

| | |
|---|---|
| Proposed | **X**: nine purpose cards, one four-position dial, three shapes, 13-step checklist. **Y**: module-tagged setting cards with nine attributes, changesets, effective-from dating. **Z**: switch list template with words beside switches, impact lines. |
| Winner | **X's structure, Z's controls, a trimmed Y card.** First view of a rule: plain sentence + control + "Changed" chip; key, value source, risk class and scope under Details. **One key belongs to exactly one card**; unmapped keys land in a visible tenth card "Other" and fail the coverage test. Changesets are used for preset application and multi-key edits (preview diff, reason, one history line, Revert as a new changeset). Effective-from dating of history-affecting rules is a separate accounting item and is **not** part of this design. |
| Evidence | The committed baseline holds 297 rules, 84 grants and 64 location settings [baseline] (X counted 283 rules, the audits 150). |
| Tie-breaker | Coverage test: every `setting:rule:<key>` and `setting:grant:<code>` of the baseline appears in exactly one purpose card's "All settings" list and in the Switchboard. |
| Status | Decided |

**D13 Confirm ladder**

| | |
|---|---|
| Proposed | **Z**: A0 just do it, A1 do plus undo, A2 deliberate tap, A3 confirm sheet with impact and reason, A4 confirm plus PIN. **C / U-37**: one confirm sheet; type-to-confirm for close month, activate agreement, restore. **Y**: add "routine posting inside limits = A2" so A3 is not a tax. |
| Winner | **Z's ladder, Y's class.** A2 covers Submit, Post bill, Collect due, Confirm sale. A3 is for void, reject, reopen approved, emergency approve, release, sensitive grants. A4 uses an "I understand" tick plus the existing PIN, **not** typed words (low-literacy users). The API still supports type-to-confirm; setting `confirm_type_words`, default off. |
| Evidence | 46 to 52 browser `confirm()` / `prompt()` calls in 27 files [grep, C and Z]. |
| Tie-breaker | T15 (void the right sale, reason entered, 0 wrong-target errors). |
| Status | Decided |

**D14 Type, touch, edges**

| | |
|---|---|
| Proposed | **Z**: body 14, floor 12, inputs 16, targets 48/44, edges 3:1, Text size S/L/X scaling type and targets together. **C**: floor 12 px and `.mini` 44 px only. **D**: keeps 12.5 px. **Y**: adopts Z's floor. |
| Winner | **Z.** Every new rule is scoped `body[data-arch]`; with the switch off the old look is unchanged. |
| Why | 216 of 254 inline font sizes are under 12 px at the 13 px root; field edges are 1.2 to 1.4:1 against a 3:1 rule that `DESIGN_SYSTEM.md` itself states [code, Z E1, E2]. |
| Cost | 14 px adds about 10 to 12% height. The step-0 harness re-measures the top 25 screens at 14 px before any "after" figure is quoted. |
| Status | Decided |

**D15 Home size** is a result of D01 and D03: staff Today about 820 px = 1.05 pages, owner about 1,050 px = 1.3 pages [model, Z]. Hard cap 1.5 pages in bn.

**D16 Desktop layer** (master-detail at 900 px and wider, 32 px dense rows with a fine pointer, keyboard keys, `Ctrl+K` palette, scan sink)

| | |
|---|---|
| Proposed | **Y**: core, about 14 days. **Z**: not first, phone-first. **X**: per-person mode, only after evidence. |
| Winner | **Evidence first.** The repository has no usage data [code]; the layout is one 640 px column at every width. A local usage log ships in step 1 so the data exists by the time the layer is decided. |
| Tie-breaker | **TB5** usage log, 2 weeks: build the layer if at least 15% of sessions of accountant, purchasing or owner logins are at width 900 px or more, or show hardware-key use, or at least 3 named people work there. |
| Status | **PV-3** |

**D17 Show everything and See as role**: Show everything is per phone (`bos_show_all`), allowed for the owner by default (`show_everything_roles`). Visible as an amber pill in the context strip ("Everything - 110 screens - Back to my view"); the Menu header repeats it. Rows the role cannot open are greyed with the reason ("needs grant `salary_view`"), reusing `settings2/noperm`. "See as role" feeds the existing `ok(c)` predicates a synthetic context, shows a banner, previews navigation only (data stays server-protected) [Y 8.1, X 2.1]. Lock versus hide: area pages show only what the person can open plus a folded line "Locked (4)"; Find and Show everything list locked rows with reason and an Ask button (existing emergency, release or change request); setting `ui_noperm_mode` keeps hide, lock and ask. Test **TB8**.

**D18 Rollout switches**: section 7.3. **D19 Preservation**: section 5. **D20 Language**: section 3.9.

**D21 Order and size**: the controls backlog (Audit A and B) outranks anything that is not on the beginner's path (Y conceded X6). Safety fixes (section 6) and the preservation gate come first. Tokens and shell come next because they are independent of the winning structure (Z). The front door follows. Productivity features (Day board, record pages, grids, desktop layer) come last and the last two are gated.

### 2.2 Tie-break protocols (defined once)

| ID | Settles | Protocol | Gate |
|---|---|---|---|
| **TB1** Tree test | PV-2, D01 vocabulary | Text-only menu trees (no visuals), both trees, 28 tasks: 10 daily jobs, 10 rare ones (digital reconcile 10-3, number-gap audit, restore drill, role x form matrix, unit conversions, deeds, parallel month, bank reconcile, period lock, item import), 8 trace tasks (all bills of one supplier for last March exported; open one customer and see dues, returns, history; who changed an item price; open the journal entry of receipt R). 15 people per tree, between subjects. Measure success, directness (no backtracking), first click, time. | Gap >= 10 points: higher wins. Below 10: the tree with fewer top-level rows (8 areas). Rare tasks: success >= 85%, folded row <= 4 taps, Find <= 3. |
| **TB2** New-hire test | D01 | For each of 5 staff roles (salesperson, storekeeper, showroom manager, factory in-charge, cash controller) 3 people who never used the app get the 10-minute script (7.8), then do the role's 5 jobs alone with the printed card. | >= 90% unaided success and total <= 10 min. With 15 people this allows at most 1 failure. Failing: fix the kit, retest. |
| **TB3** Timed entry | PV-3 grids | `purchase/new`, 30 lines from a paper bill; stock count of 80 items (blind); attendance for 40 staff x 30 days. Three builds: current, compact rows, composer sheet/grid. At least 2 people per build and role (accountant, storekeeper). Measure seconds per line, taps per line, errors per 100 lines, phone pages, blind-count leaks. | Grid must be >= 30% faster than current, errors not higher, <= 2.7 pages for 30 lines, **0 leaks**. Else that job's `ui_grid_<job>` stays off. If compact rows alone reach 30%, keep rows only. |
| **TB4** Trace | D08 drill | Current build, accountant: (a) April sales total to the journal entry of one receipt; (b) who changed this item's price and when. | Build drill/History tiers if median > 90 s or > 6 steps; after build <= 4 steps and <= 30 s. |
| **TB5** Usage log | D16 | Local counters `bos_ut`: width bucket (<600, 600-899, >= 900), pointer type, hardware-key events, per role. Two weeks. Counts only, no content. | Build the desktop layer if the threshold of D16 is met; otherwise defer and keep ~9 days. |
| **TB6** Load and cold start | Lazy loading, `today_state` RPC | Cheapest phone in use, 3G throttle. Time to first usable screen; Today open: requests and seconds. | Lazy-load modules and precache **only if** first screen > 4 s median. Add the batched RPC `today_state(p_loc)` **only if** Today > 8 requests or > 1.5 s. |
| **TB7** Tile tap | PV-1 | T5 (receive goods from a challan: time, taps) and T17 (find yesterday's record of this job: time, success) with entry-first and with list-first. | Entry-first for enter-roles if T5 median is >= 15% faster **and** T17 stays <= 20 s through the entry header; else list-first. |
| **TB8** Cover shift | D17, role-shaped Today | 4 tasks per person: a salesperson asked to do a stock count (sees locked row + Ask); a manager asked to approve; "find yesterday's rejected entry" <= 15 s; two logins on one phone. | >= 90% reach in <= 4 taps; lost rate (menu opened > 2 times) <= 10%. |
| **TB9** Way comprehension | D07 chrome | T5b: "which way counts for stock?" after a receive-goods task. | >= 90% correct and chrome <= 30%. |
| **TB10** Reading test | D20 | 10 labels in the current Bng-Eng wording and 10 in glossary-only wording, "what happens if you press it?" | >= 90% understood (low-literacy >= 80%); the wording that scores higher stays. |

Usability tasks T1 to T23 (success, time, errors, "lost" rule, SUS >= 75 and >= baseline + 10) are Z's plan, with the additions T17 to T23 of R2; the list is in Appendix C. A baseline run **R0 on today's app** happens before anything ships, so "30% faster" has a denominator. The release gate is: no P0 task worse than R0, T1 to T6 at least 30% faster than R0, and zero critical errors (wrong void, wrong grant, wrong payment). The 90% unaided-success figure of Z is the target; with 15 people it allows one failure, so a miss opens a fix list and does not by itself stop a release (X's objection to a hard 90% gate), except for the critical tasks T7 and T15.

---

## 3. Page templates, rules and tokens

Every screen declares one of **8 templates**. A screen that needs a ninth is a design bug. The wireframes are 40 characters wide, one character is about 9 px at 360 px. Money is written `Tk`. Names are neutral test names.

### 3.1 The shell (identical on every screen and every role)

```
+--------------------------------------+
| [<-] Page title (1 line)  [find][bell][:] |  header 56 px
|      Area > Section                  |  subtitle 12 px = old breadcrumb, tap = parent
+--------------------------------------+
| Main shop v  |  Today v              |  context strip 32 px (optional, scrolls away)
| Offline - 3 not sent - Send now      |  state strip 36 px (only when needed, one at a time)
|                                      |
|            ... content ...           |
|                                      |
+--------------------------------------+
| Today | Find | (ORB) | To do 3 | Menu|  bottom region 64 px: global bar
+--------------------------------------+  OR action bar OR selection bar, never two
```

| Part | Rule |
|---|---|
| Header | Back arrow on any screen reached from another (the system back gesture works too); menu icon only on Today and area pages. Title one line with ellipsis, full text in `title`; tapping it shows it in a toast. Right side: find (list, report, settings, hub), bell (route `notifications`, dot when unread), a menu (favourite star, copy link, print, **Help**, "Other ways", "Show all / Collapse all", "Reset layout"). Forms and wizards hide find and show the **save-state chip** next to the title. |
| Context strip | Place and period scope ("Main shop v, Today v"). Carries the amber **Show everything** pill when that mode is on. |
| State strip | Priority: offline, then not sent, then slow network, then "Practice: nothing is saved", then stale copy. Tap = send now. |
| Bottom region | Exactly one at a time (rule R1 in 3.5). |
| Orb | The person's main job, as a verb that starts work ("Sell", "Receive goods", "Hand cash to hub"). The only glowing element. States by shape and text, never colour alone: normal; due now (count badge); done (check badge, label "Day closed"); offline (cloud-slash badge, label "Sell - offline"). No pulsing. In landscape (height under 480 px) the orb sits inline in a 56 px bar. |
| Me | Top row of Menu (name, role, place; language, text size, theme, 2FA, log out) and the Me sheet. Not a bar slot. |

### 3.2 Chrome budget (360x640, about 600 px visible when installed)

| Template | Header | Strip | Bottom | Total | Share |
|---|---:|---:|---:|---:|---:|
| T1 Home | 56 | 0 to 36 | 64 | 120 to 156 | 20 to 26% |
| T2 List / Job page | 56 | filter 44 when active | 64 | 120 to 164 | 20 to 27% |
| T3 Detail / record | 56 | tabs 44 | 64 | 164 | 27% |
| T4 Entry form | 56 | step bar 44 | 64 | 164 | 27% |
| T5 Wizard / routine | 56 | progress 6 | 0 (global bar shown) | 120 | 20% |
| T6 Report | 56 | period/parameter 44 | 64 | 164 | 27% |
| T7 Settings | 56 | search + chips 44 | 64 | 164 | 27% |
| T8 Hub / dashboard | 56 | context 32 | 64 | 152 | 25% |

Gate: **at most 30% (180 px)**; with the state strip visible up to 192 px is accepted. Measured by the test, not by eye.

### 3.3 The eight templates

**T1 Home (Today).** Fixed block order for everyone. Content differs by role.

```
+--------------------------------------+
| [=] Main shop v               [bell] [:] |
+--------------------------------------+
| Next: Close the day (16:00)          |  Now line = first row of To do
| [ Close day                        > ] |  56 px button
| My jobs                              |
|  Count drawer   14-1        To do  > |  card 76 px: icon 32, verb <= 3 words,
|  Receive goods  04-1        Draft  > |  state WORD, small form chip
|  Hand cash to hub 10-1      Later  > |
| Done (3)                           v |  folded
| More jobs (12)                     > |  includes locked rows with Ask
| > Numbers: My sales today            |  collapsed for staff
| > Help                               |
+--------------------------------------+
| Today | Find | (Close) | To do 3 | Menu |
+--------------------------------------+
```

Owner variant adds, above My jobs: **Needs you** (inbox rows with age; inline decision only for low-risk kinds), **Day board** (T8 place cards), and the Setup checklist card until step 13 is done. Rules: a job appears once on Today (not also as shortcut tile, favourite and module tile). "All clear" is shown only when **every** count loaded; otherwise "Checking..." then "Could not check. Try again". No false zero (safety fix S-3). Without owner-set time windows the groups are `To do` and `Done` only; "Later today" appears only where a window exists.

**T2 List, and the Job page.**

```
+--------------------------------------+
| [<-] Expense                  [find] [:] |
|      Money > Expense   [10-2] [18-1]  |  form-code chips never replaced
+--------------------------------------+
| New with: [Quick screen | Voucher 10-2] |  Way strip 44 px (Job page, step 1 only)
| Counted from: Quick screen. Paper copy: 2 owed |  status line, one sentence
| (This month v) (Main v)  [Filter]    |  scope chips 36 px
|--------------------------------------|
| | Staff meals - test_person   Tk 1,500|  row 64 px: edge marker, 1-line title,
| | 2026-10-14 Wed [Via Quick][Pending] |  2 facts, Via chip, status chip with words
| | Fuel   [Covered by voucher 10-2 #123 >]|  linked-copy chip, tappable
| Show 50 more (112 left)              |
|                      [ + New expense ] |  FAB 48 px, flat
+--------------------------------------+
| global bar                           |
+--------------------------------------+
```

Plain lists are the same without the Way strip. Row: tap = open; at most 2 secondary actions visible; the rest in the row menu, destructive last with a reason. Filters open a bottom sheet with "Apply (n results)". Select mode (header menu "Select") replaces the global bar and the FAB with a selection bar `3 selected | Apply to 3 v | Preview`; bulk actions are always preview-then-apply with one audit line per record plus one batch line; never swipe-only. Saved views (`report_views`, `report_code='list:<route>'`, follows the person to a second phone) are the first applied chip. Page size 50.

**T3 Detail / record page.**

```
+--------------------------------------+
| [<-] test_customer_1                [:]|
|      Sell > Customers                 |
| [Active] [Tier 2] [Over limit]       |  chips with words
| Due Tk 3,200      Last sale 2026-10-12 |  3 to 6 key facts, 2 columns
|--------------------------------------|
| [Overview] Activity Money History More |  max 5 tabs, sticky, text badges
|  ...body...                          |
+--------------------------------------+
| [ Collect due ]          [ New sale ]  |  action bar: 1 primary + 1 secondary
+--------------------------------------+
```

History is a timeline, newest first, collapsed beyond 3, with who, when, note. Destructive verbs (void, inactivate) last in the menu, level A3. Document records add `Posted as` (journal entry) and stock-ledger rows on the Money tab and the `Via` chip of D07.

**T4 Entry form (the paper-form engine, 41 forms).**

```
+--------------------------------------+
| [<-] 14-1 Daily showroom sheet [Saved]|  save-state chip
|      Sell > Forms              [:]   |
|  Main - 2026-10-14 Wed - Draft       |  identity folds to one line on scroll
|--------------------------------------|
| (1)Open (2)Day [3]Cash (4)Stock (5)Close |  step bar 44 px: not started / partly / done / problem
|--------------------------------------|
| 1 red - 1 yellow                   v |  flags row, always rendered
| v Sales by category      11 fields   |  open group 52 px
|   Sweets Tk [      ]  Cake Tk [     ] |  two-up money pairs
| > Online and party   1 needed        |  closed group + badge in words
| v Cash count                         |
|   Tk 1000 [ - ] 2 [ + ] = 2,000      |  denomination pad
+--------------------------------------+
| Counted Tk 12,400 [Save draft] [Next ->]|  action bar: summary + secondary + primary
+--------------------------------------+
```

The identity card (date, place, weekday, status, rollout chip, "Not sent yet", revision chip) stays above step 1. The paper block ("Entered later from paper", paper serial, original time, "Printed paper no.") is one More group, **forced open** when "entered later" is on or the rollout mode is Paper. The last step's primary is Submit; earlier steps show Next; a "Review" chip in the step bar jumps to Submit. Flags box and "limits needed" notice stay **outside** the panels (S-2). Fixed tables use compact rows (56 px summary such as `Unit 1 - 3.2 C - OK`), one expanded row at a time, "Prev row / Next row", Enter moves to the next cell, a new empty row opens expanded. Denomination pad: one row per note, 52 px, `Tk 500 [ - ] 12 [ + ] = 6,000`, running total in the action bar; field ids unchanged (`cash_count.n1000` to `n1`, `cash_count.coin`).

**T5 Wizard and routine.**

```
+--------------------------------------+
| [<-] Close day                    [:] |
|  Main shop v              3 of 8 [###--] |
|--------------------------------------|
| [x] 1. Count the drawer (14-1)   Done |  whole row is the button
| [ ] 2. Release request if red open  To do |
|        needs Manager                  |
| [ ] 3. Hand the cash to the hub (10-1) To do |
| [-] 5. Bank deposit     Skipped (note)|
| [?] 6. Digital reconcile  Check by hand |  never a green tick when unknown
+--------------------------------------+
| global bar                           |
+--------------------------------------+
```

Routines (`flow.js`) keep their rule: a step is never ticked by tapping; "Skip..." needs a note of 3 or more letters and is audit-logged; both live in the row menu. Record wizards (employee, location) have Back/Next in an action bar, a draft saved on every Next, and a Review step that lists what is missing with jump buttons. Steps are free-jump; Submit does not exist before the last step in a wizard, while forms keep their own Review chip.

**T6 Report.**

```
+--------------------------------------+
| [<-] Business analysis   [Export] [:] |
| (Today) Week  Month  Year  Custom    |  period chips 44 px, sticky
| All places v    Filters (1)          |
| [!] Not enough days (needs 7): not reliable |  limit notice, never collapsed
| [Sales Tk 1.2L ] [Profit Tk 18k ]    |  2x2 stat cards 84 px, each a link
| Summary | Items | Staff              |  max 4 tabs
| table: 3 columns max; wider = rows that expand
| chart <= 160 px with "Show as table" |
+--------------------------------------+
```

Stat cards and table rows are links ("Where this comes from") only where the key exists. Provenance lines ("Verified (computed by the server)") are never collapsed. Export, print and share are within two taps. Basis chips (Management, Ledger, Cash, Stock book) sit on every profit, stock and cash report.

**T7 Settings (switch lists, purpose cards, Switchboard, matrix).**

```
+--------------------------------------+
| [<-] Setup > Rules               [:]  |
| [ Search a setting...            ]   |
| (All)(Sell)(Stock)(Money) ...  (Only changed 4) |
| v Safety switches               7    |  pinned group, always first
|  Count without expected number [ON ] |  row 60 px: plain label, 1-line effect,
|   Cash short/over hidden until sealed |  switch with the WORD beside it
|  PIN signature                 [OFF]  |
| > Sell                    12 - 1 changed |
+--------------------------------------+
| 3 changes  [Save 3 changes]          |  action bar only when something is dirty
+--------------------------------------+
```

A switch is a real switch with its state word beside it, never a button whose label is the state (an "Off" button reads as "turn off"). Switches write at once and show an Undo toast; sensitive rows (money, permission, security, `accounting_on`, `period_closed_until`) show a one-line impact sentence and need a level A3 confirm. Numbers and dates use typed controls (stepper with unit; date picker with "Entries on or before this date will be locked."). One "Save n changes" bar for all dirty numbers (D P16); no per-row Save. More than 5 sibling pages become a hub of cards, not a tab strip. The raw key and raw choice values live under Details.

**T8 Hub / dashboard** (area page, Setup front page, Day board, owner board, accounts overview).

```
+--------------------------------------+
| [=] Goods                        [bell] [:] |
| Today's routine: Receive goods [Start]|
| JOBS                                 |
|  Receive goods  04-1          Draft > |  <= 6 rows
|  Issue material 04-2                > |
| > More in Goods (5)                  |  folded, by section
| FORMS  [03-1][04-1][04-2][04-3][04-4][08-1] |  chips in paper-book order
| Locked (2)                         > |
| [ Show all ]                         |
+--------------------------------------+
| global bar                           |
+--------------------------------------+
```

Day board variant: one 148 px card per place, 3x2 state chips (word plus glyph: `v` done, `!` late or missing, `-` not yet), a "Problems only" toggle, each chip opens its source list; 5 places = about 0.95 page. Area page sections: Every day (at most 6 rows, shown), Now and then (folded), Rare or setup-like (folded, owner). A person with one area opens that area page straight from Menu (single-child levels are skipped).

**Variants that are not new templates**: Job page = T2; Area page and Setup front = T8; record page = T3; grid composer = a half-height sheet over T4; Find = a full-screen list page (T2 anatomy without bottom bar).

### 3.4 Spacing, type, touch

| Item | Value |
|---|---|
| Design size | 360 x 640; supported 320 to 640; above 640 the column stays 640 centred |
| Side gutter / content width | 16 px / 328 px at 360 |
| Grid | 12 columns, 8 px gutter. Spans: 12, 6 (160 px), 4 (104 px, icon tiles only), 3 (76 px, icon + one word) |
| Rhythm | 4 px unit; gaps from `--sp-1..7` (4, 8, 12, 16, 24, 32, 48) |
| Card padding / field gap | 12 / 12 px Standard; 8 / 8 Compact (targets stay 48) |
| Two-up fields | only `money, number, time, date, select, staff, choice (2 to 3 options), calc`; collapse to one column at Text size X or width under 340 |
| Always full width | `text, textarea, item, supplier, photo, table rows, notes` |
| Page bottom padding | height of the bottom region + 16 px + safe-area (fixes cards under the bar, C-42) |

| Role | Size / line | Weight |
|---|---|---|
| Hero number | 28 / 1.2 | 700, tabular lining digits, sans (never the thin serif below 24 px) |
| Page title | 17 / 1.4 | 700, one line |
| Section title | 15 / 1.45 | 700 |
| Body, buttons | 14 / 1.6 | 400 / 600 |
| Inputs | 16 | 400 |
| Label | 13 / 1.5 | 600, up to 2 lines, never truncated |
| Meta, chips, bar label | 12 / 1.5 (floor) | 500 |
| Money in lists | 15 / 1.3 | 600, tabular, right aligned |

Bangla: no weight 800 under 20 px; line-height at least 1.45 on any element with `overflow:hidden`; no letter-spacing. Touch: 48 px for inputs, buttons, rows, switches; 44 px floor for icon buttons and chips (hit area extended by padding); 8 px between targets; 56 px for A3/A4 buttons; `.mini` 36 px becomes 44 px. Text size (Me): Normal x1.0, Large x1.15, Extra x1.3 scales type and targets together (48, 55, 62 px). Pinch zoom stays on.

### 3.5 Sticky bars and the bottom region

| Rule | Text |
|---|---|
| R1 | One bottom region. If a screen has an action bar, the global bar is hidden (extends `hideBnav()` from `entry` and `pos` to purchase, items edit, employee wizard, partners, invoice, tiers: the 6 stacked cases). |
| R2 | Only the orb may glow. FAB and action-bar primary are flat. |
| R3 | With the soft keyboard open the action bar sits above it (`visualViewport`) and the global bar hides; the field scrolls to the upper third. |
| Action bar | 64 px: summary (2 lines, optional), one secondary text button, one primary. Primary is rightmost; check mode shows Reject (outline) and Approve. Left-hand mode (Me) mirrors the order. "Copy last entry" and "Seal count" move to the header menu (nothing removed). |
| Sheets | Primary at the bottom; Confirm/Pay/Apply is always visible (`.sheet-foot` sticky). The POS cart sheet keeps Due, Total, Back, Confirm in its foot. |
| z-index ladder | header 10, bar 12, FAB 13, scrim 40, sheet 50, toast 60, scanner 70 (today `.pos-bar` equals `.sheet-bg`, and the toast sits under the drawer). |

### 3.6 Progressive disclosure: one component, "More options"

What may go inside: optional or rare fields, notes, secondary tables. **Never inside**: required fields, fields that drive a red or yellow flag, money totals and short/over, signature and PIN boxes, blind-count boxes, the "limits needed" notice, Submit, Approve, Pay, Close.

1. A closed fold shows its content in **words**: `More options (4) - 1 required missing`, `3 of 7 filled`, `! 1 red`. Never colour alone.
2. It **auto-opens** when it holds a required empty field, a red flag, the jump or search target, or after "Show all". A remembered "closed" is ignored while any of these is true.
3. Open or closed is remembered per person, per screen, per group in `localStorage.bos_ui_state` (`staffId|screen|group` to 0 or 1, at most 300 keys, every access in try/catch, the page renders correctly with storage empty, blocked or corrupt). A second phone starts from defaults. It is a convenience, never business data.
4. Defaults come from the form designer (today's `collapsed` flag), not from the user.
5. One level only: no More inside More, no accordion inside an accordion.
6. "Show all / Collapse all" in the header menu for everyone; "Show everything" persistent per phone for the owner.
7. The first group of a step is open unless it is an "if it happened" group (B, C, D of 14-1), which stays closed with its badge.
8. "Reset layout" in Me clears the remembered state.

In the new view the items-edit group "Advance options" is called "More options" (D 5.5; "advance" also means a money advance here). The old words stay as a search keyword and in the old code path. This is the one intended label difference between the old and the new view (section 5.4).

### 3.7 Tabs, steps, accordions: one decision table

| Use | When | Must have | Never |
|---|---|---|---|
| **Tabs** (max 5, 4 at Text size L) | Peer views of one record or list, read in any order | text badge with a count when a tab has a problem; last tab remembered | tabs inside tabs; more than 5 (use a hub page); sequential data entry |
| **Steps** (step bar + Back/Next, last step = Review) | Data entry in the order things happen with a sign-off: 14-1, 14-2, 01-1, 01-2, 03-1, 02-2, employee wizard, location wizard | per-step state glyph and word (`not started / partly / done / problem`); free jumping; draft saved on every Next; Review lists what is missing with jump buttons | more than 6 steps; steps inside tabs; forced order unless the data demands it |
| **Accordion** (52 px header, remembered, badge) | Extra groups on one page | badge on every closed group; auto-open on problem | accordion in accordion; hiding Submit |
| **Segmented control** (2 to 3 options, 44 px) | A mode or filter: Business/Accounting, period, Counts/Copy, the four dial positions | | more than 3 options except the dial (4 labelled words) |
| **Sheet** | One decision or a short choice: filter, confirm, grant, location | primary at the bottom, safe choice easiest to reach | long forms |

Quick test: Is there an order in time? Steps. Is it the same thing seen differently? Tabs. Is it extra detail on this page? Accordion.

### 3.8 Jump to the missing field (build first, safety S-1)

1. Each section or fold summary shows `n/N filled` and a text badge: `! k required missing`, `k red`, `k yellow`.
2. The "missing fields" sheet lists each item as a button. Tap: close the sheet, open the step and the group that holds the field, scroll the field to one third of the screen, focus it, flash it for 1.2 s. For a field inside a table row, expand the row.
3. A red flag in the flags box gets a "Go to field" link when the flag names a field or section.
4. On Submit, a group with a required empty field or an unresolved red flag opens and **cannot be remembered closed** while the problem exists.
5. The error summary reads "2 things to fix" with one **Go to field** button per item. Typed data is kept.
6. The sheet uses ids from `missingRequired()` (spec plus data, not the DOM), so a closed tab never changes validation.

### 3.9 Language, wrapping and accessibility

| Rule | Text |
|---|---|
| English first | Builders write English labels. The `L(bn, en, mix)` triple gets its Bangla and Bng-Eng text from the translator later. Until then layouts are tested with the English string stretched to 1.6x ("pseudo-Bangla") and with the longest existing Bangla strings. |
| Budget | Every text slot is designed for 1.6x the English text, or two lines. p90 of Bangla/English length is 1.43 characters and 1.5 words over 5,328 existing triples [Z, measured]. |
| Wrap, do not cut | Labels, buttons, chips and row titles wrap to 2 lines (`overflow-wrap:anywhere`, `min-width:0`). Only the header title, the bottom-bar label (falls back to icon only) and file names are cut. |
| No clipping | Any element with `overflow:hidden` has line-height at least 1.45 and padding-block at least 2 px (fixes `.bnav button`). |
| Mix mode | `docs/LANGUAGE.md` defines Bng-Eng as Bangla with simple everyday English words. That definition stays (R2 objection to Z's glossary-only rule). The reading test TB10 decides which wording is kept. No concatenated sentences; use `{n}` templates so Bangla can reorder. |
| `lang` | `<html lang>` is set from the mode (today fixed to `bn`) [code]; English words in mixed text carry `lang="en"`. |
| Dates and money | ISO date plus day name in a date button (not the phone's `mm/dd/yyyy`); 12-hour time (existing `hour12`; setting `time_format`, owner decides); `Tk` before the number, lakh grouping `12,34,567.50`, negatives with a minus sign. Latin digits in every mode. |
| Fonts | Self-host Hind Siliguri and Anek Bangla (woff2, `font-display: swap`) and list them in the service worker; Google Fonts only today [code]. [unverified: licence for self-hosting, file sizes] |
| Accessibility | Text 4.5:1, field and control edges 3:1 (today 1.2 to 1.4:1), status by word + shape + colour, focus ring 2 px amber, `role=tablist` with roving tabindex, compact rows are `<button aria-expanded>`, toasts `role=status`, error summary `role=alert`, no gesture-only, hover-only or drag-only actions, "Simple look" switch (no blur, no 3D icons, higher edge contrast), left-hand mode. |

### 3.10 Design tokens to add (names follow the existing `--` scheme in `theme.css`)

All values apply only under `body[data-arch]` (or `html[data-tsize]`), so with the switch off the old look is unchanged. Names that already exist (`--fs-body`, `--fs-meta`, `--fs-title`, `--fs-page`, `--tap`) are redefined under that scope; the rest are new.

```css
body[data-arch] {
  --ts: 1;                                   /* text scale: 1 | 1.15 | 1.3 from html[data-tsize] */
  --fs-meta:  calc(12px * var(--ts));        /* was 11 */
  --fs-label: calc(13px * var(--ts));
  --fs-body:  calc(14px * var(--ts));        /* was 12.5 */
  --fs-input: calc(16px * var(--ts));
  --fs-title: calc(15px * var(--ts));        /* was 13.5 */
  --fs-page:  calc(17px * var(--ts));        /* was 15 */
  --fs-num-l: calc(22px * var(--ts));  --fs-num-xl: calc(28px * var(--ts));
  --lh-bn: 1.6; --lh-title: 1.45; --lh-tight: 1.35; --lh-clip-min: 1.45;
  --fw-body: 400; --fw-strong: 600; --fw-head: 700;          /* no 800 below 20 px */
  --tap: calc(48px * var(--ts));  --tap-min: 44px;  --tap-gap: 8px;  --tap-danger: 56px;
  --row-1: 56px;  --row-2: 64px;
  --hdr-h: 56px;  --strip-h: 36px;  --ctx-h: 32px;  --tabs-h: 44px;  --bar-h: 64px;  --fab-h: 48px;
  --gap-field: 12px;  --pad-card: 12px;                     /* data-density="compact": 8 / 8 */
  --edge-field: #6b6f7a;                                     /* dark: 3.05:1 on --s1 */
  --edge-ctl: color-mix(in srgb, var(--edge-field) 85%, transparent);
  --focus: 0 0 0 2px var(--s0), 0 0 0 4px var(--amber);
  --gold-ink: #8a4f00;                                       /* light theme small text */
  --st-offline: var(--warn); --st-unsent: var(--warn); --st-sent: var(--ok); --st-failed: var(--bad);
  --danger-fill: #b3202c; --danger-ink: #fff;                /* only inside A3/A4 sheets */
  --z-hdr: 10; --z-bar: 12; --z-fab: 13; --z-scrim: 40; --z-sheet: 50; --z-toast: 60; --z-scan: 70;
}
html[data-tsize="l"] { --ts: 1.15 }   html[data-tsize="x"] { --ts: 1.3 }
:root[data-theme="light"] body[data-arch] { --edge-field: #85735f }   /* 4.55:1 on white */
html[data-contrast="high"] body[data-arch] { --edge-field: #9aa0ad }
body[data-arch][data-density="compact"] { --gap-field: 8px; --pad-card: 8px; --row-1: 48px; --row-2: 56px }
```

New component classes (names only; implementation belongs to the packages): `.cbar` action bar, `.sbar` step/tab bar with state glyphs, `.more` fold with remembered state and badge, `.crow` compact row, `.fab`, `.strip`, `.way` and `.jobsheet`, `.cfm` confirm sheet (`.cfm-impact`, `.cfm-reason`, `.cfm-danger`, `.cfm-safe`), `.undo`, `.dpad`, `.sw` labelled switch, `.err-sum`, `.empty[data-kind]`, `.pill-all` (Show everything). No hard-coded colours. Contrast values were computed from token values, not from rendered pixels [unverified for blurred bars].

Dense mode (PV-3) adds only: `@media (pointer: fine) and (min-width: 900px)` with 32 px rows, font floor 13 px (body) and 12 px (meta), master-detail columns `340px 1fr`. Phones never get Dense.

---

## 4. The worst screens: before and after, with every field kept

**Units.** One phone page = 780 css px of page height (the repo's test viewport 360x780). A real window at 360x640 shows about 470 px of content after chrome, so multiply pages by about 1.65 for "screens you scroll through". "Before" is measured from a screenshot [measured] or estimated from field counts [est] (Audit D). "After" figures for rows 1 to 10 are Z's height model at 14 px body [model]; rows 11 to 24 are Audit D's model at 12.5 px, so add about 10% at 14 px [model]. No "after" figure may be quoted as fact until the step-0 harness has measured it at 14 px and at Text size X.

### 4.1 Scoreboard (24 screens)

| # | Screen | Before (pages) | After default | Max in one step or tab | After all open | Main mechanism |
|--:|---|---:|---:|---:|---:|---|
| 1 | **14-1 Daily showroom sheet** | 12.5 [measured], 21 all open [est] | **6.3** in total | 2.5 (Opening); closing sitting 3.5 | 14.2 | 5 steps, More groups, compact rows, denomination pad |
| 2 | **Switchboard** `#/switchboard` | 18 [est] (2.1 with 5 test rules) | **1.6** | 1.6 | 14.1 | search, chips, pinned Safety group, module accordions, inline switches |
| 3 | **01-2 Monthly P&L and KPI** | 9.2 [est] | **6.0** | 1.9 | 6.0 | 4 steps, compact KPI rows |
| 4 | **01-1 Weekly review note** | 8.1 [est] | **4.7** | 1.8 | 4.7 | 5 steps, one compact row per showroom |
| 5 | **14-2 Jalebi counter record** | 7.1 [est] | **4.6** | 1.4 | 4.6 | 5 steps, calc cards read-only |
| 6 | **02-2 Monthly salary sheet** | 4.9 (3 staff), 19 (30 staff) [est] | **3.5** / **7.1** | 2.2 / 3.9 | 3.5 / 7.1 | one row per person, find-person, sticky totals |
| 7 | **03-1 Transfer challan** | 5.5 [measured] | **2.8** | 1.1 | 4.3 | 4 steps, compact item rows |
| 8 | **Role x form matrix** `#/matrix` and **Form rules** `#/rules` | 6.3 [est] each | **1.3** | 1.3 | 4.7 | role chips, area accordions, three labelled toggles per row |
| 9 | **Home** `#/home` | 4.5 [measured] | **1.0 to 1.3** (+ Menu 0.6) | 1.3 | n/a | T1 Today, all other blocks move to Menu |
| 10 | **10-2 Expense voucher** | 3.7 [measured] | **1.4** | 0.9 | 2.0 | 3 steps, paper block folded |
| 11 | 02-7 Duty and backup card | 4.5 (14.8 all open) [est] | 1.8 | 1.8 | 4.2 | More groups with `3 vacant - 1 partial` badges, compact slot rows |
| 12 | 02-8 Skill checklist | 3.8 (9.7) [est] | 1.3 | 1.3 | 3.3 | sections B to G closed with `n/m done` |
| 13 | 04-3 Stock count sheet | 3.5 [measured] | 1.9 | 1.9 | not modelled | compact rows, Enter flow, blind mask kept |
| 14 | Location settings `#/locset` | 5.5 [est] | 1.2 per tab | 1.2 | 3.5 | tabs, dirty-only Save, "Save n changes" |
| 15 | Access manager `#/settings2/access` | 2.4 [measured] | 1.0 | 1.0 | not modelled | granted grants as rows, "Not granted (11)" closed |
| 16 | Customer tiers `#/tiers` | 3.0 [measured] | 0.8 per tab | 0.9 | not modelled | 3 tabs, tier row with menu |
| 17 | Partners and deed `#/partners` | 3.4 [measured] | 1.0 per tab | 1.0 | not modelled | 5 tabs, Activate stays a primary in the bar |
| 18 | Invoice template `#/invoice` | 3.2 [measured] | 1.2 per tab | 1.2 | not modelled | 3 tabs, preview in a sheet |
| 19 | Product edit `#/items/edit/<id>` | 2.6 [measured] | 1.0 | 1.0 | 1.9 | 3 More groups, one bar instead of two |
| 20 | Employee wizard `#/employees/new` | 2.1 per step 1 [measured] | 1.0 | 1.0 | 1.5 | step chips, 4 groups in step 1 |
| 21 | New purchase bill `#/purchase/new` | 2.2 (9 at 20 lines) | 1.3 (2.4 at 20 lines) | 1.3 | 2.4 | compact line rows, composer sheet |
| 22 | Assistant `#/assistant` | 5.9 [measured] | 3.0 | 3.0 | not modelled | 5 suggestion chips instead of 25 open questions |
| 23 | POS cart and pay sheet | 1.8 inside a sheet [est] | 0.8, no scroll | 0.8 | not modelled | sticky foot with Due, Total, Confirm |
| 24 | Business analysis `#/biz` | 2.4 [measured] | 1.0 per tab | 1.0 | not modelled | 5 tabs, staff table as expandable rows |

Honest notes. (a) "All open" is a stress case; the gain is from not being in it, and "Show all" still exists. (b) Salary at 30 staff stays long because 30 people are 30 rows; it gains find-person and sticky totals. (c) Audit D's own figures for 14-1 are 1.8 pages per step at 12.5 px; Z's model at 14 px is higher. (d) The field-count unit differs: Z counts a table as one id (142 ids for 14-1); the baseline counts every table column as its own field (181 field items for 14-1) [baseline]. The parity gate uses the baseline ids, so every column is guarded.

What a person sees: at 9:00 the manager opens 14-1 on step 1 (2.5 pages); at closing time steps 3 and 5 (3.5 pages), not 12.5. Steps 2 and 4 open as bars only when nothing happened that day (0.2 and 0.1 page).

### 4.2 Field maps for the paper forms (every id kept; `*` = conditional field, unchanged rule)

Table fields keep all their columns. All sections are placed (14-1: 11 of 11).

**14-1 Daily showroom sheet** (5-step bar; summary in the action bar: counted total, short/over, category match; flags row always visible; blind-count and PIN boxes exactly as today)

| Step | Sections | Groups and fields |
|---|---|---|
| Header card | head | `day_type, shift, duty_manager`, engine fields (date, place, weekday, status, rollout chip, "Not sent yet", revision); paper block (More, forced open on paper mode) |
| **1 Opening** | A | `open_time safety safety_defect* float_set open_counted open_diff* imp_cash imp_receipts imp_text*`; table `fridges[name,noise,leak,cold,seal,temp,temp_ok]`; `fridge_defect product_cond product_ok expired_shown expired_removed* expired_informed*`; keys `key_shutter key_drawer key_stock duties`; readiness `r_pack r_pest r_cobweb r_trays r_light open_all_ok` (counter 0/6) |
| **2 Day** (3 closed groups with badges) | B, C, D | B Goods receipt: table `receipts[challan_no,time,from,written,counted,short,prod_date,tag,signed]`. C Mid-day: table `clean[doer,verifier,done]`, `disp_open disp_peak sun_move t2_1* t2_2* parcel_check parcel_defect`, table `vouchers[v_no,v_head,v_amt,v_rec]`, `v_total drawer_none ho_count ho_range ho_written stock_locked`. D Pending orders: `orders_taken order_range delivered_n pending_next advance_taken board_recon board_cleared delivery_orders prior_adv_ok` |
| **3 Cash** | E (6 sub-groups) | Sales by category (open) `cat_sweet cat_cake cat_jalebi cat_doi cat_bakery cat_ice cat_drink cat_other total_entered cat_sum cat_match`; Online and party `online_sales party_cash party_invoice goods_based retail gm_text*`; Digital `d_bkash d_nagad d_card d_bank d_other d_total d_phone d_nopersonal`; Dues and adjustments `dues new_adv prior_adv disc_n disc_amt cancel_n refund refund_ref* credit_sales credit_memo*`; **Cash count pad** (open) `cash_count counted_total expected* short_over* so_reason* witness* second_count leave_float hub_deposit`; Hub handover `midday_hub midday_slip* rounding slip_no counterfoil carrier carry_time` |
| **4 Stock** (2 closed groups) | F, G | F: table `stock[kept,exp_qty,exp_amt,waste_qty,waste_reason,waste_by,ret_challan]`, `exp_apart own_use own_use_by staff_credit staff_adv_page sample sample_by`. G: table `demand[item,qty,note]` (min 5 rows), `box_bag direct_buy pr_no` |
| **5 Close** | H, I, signatures, hub | H checklist `c1`..`c16` (all required, counter 0/16, **no tick-all**), `end_temp key_to shutter_time`; I Exceptions (closed, badge) table `incidents[what,urgency,why,owner,action,solved]`, `no_incident`; `second_sig*`; hub role: `hub_ledger hub_time hub_received` (others: More (3)) |

**01-2 Monthly P&L and KPI sheet** (4 steps; head `month, scope, scope_name`)
Step 1 P&L: `sales open_stock purchases close_stock cogs gross x_staff_meal x_transport x_hospitality x_repair x_labour x_sourcing x_other expenses salary bank_charges net reinvest_pct reinvest` (calc rows read-only; Net and Gross copied to the bar). Step 2 Numbers: table `sales_by[name,amt]`, `headcount wastage discount cash_short gm_unexplained count_short payables receivables`, table `raw[name,p_start,p_end,chg]` (5 rows), `new_prod on_orders on_sales on_cpo emerg`. Step 3 KPIs: `days_text`, table `kpi[cur,prev,ly,dir]` (15 fixed rows as compact rows), `leak`. Step 4 Decide and sign: table `dec[what,who,deadline]`, `rec_sales rec_salary rec_leak*`, `prepared_by owner`, `checked_by` (checker block kept apart).

**01-1 Weekly review note** (5 steps; head `week_from, week_to`)
1 Showrooms: `other_name`, table `show[sales,cash_so,gm_gap,days_cash,days_gm,wastage,complaints,discount,orders_taken,orders_given,online,outside_ok,jal_diff,jal_oil,jal_juice]` (one compact row per showroom). 2 Factory and hub: `f_other_name`, table `fac[yield_diff,chhana_short,supplier_due,receivable,open_adv]`, `owner_liab outside_debt split_seen split split_in_decisions*`. 3 Online: `on_msgs on_orders on_sales on_ads on_cpo on_complaints rev_good rev_bad level level_cond`. 4 Decisions: `prev_total prev_done prev_open prev_reason*`, table `dec[what,who,deadline,worklist]` (min 5). 5 Sign: `present1 present2 chair`.

**14-2 Jalebi counter daily record** (5 steps; head `produced_slot prepared_slot roster measured_slot`)
1 Measures: table `meas[t_open,open,t_close,close,unit]` (3 fixed rows), `measured_by scale scale_worklist* oil_changed oil_rule* old_oil* old_oil_fate* old_oil_amt* old_oil_line*`. 2 Receipts: table `slips[slip_no,i_flour,i_sugar,i_oil,i_syrup,i_other,source]` (5 rows), `tot_flour tot_sugar tot_oil tot_syrup`. 3 Working: `jalebi_item jalebi_sales c1 c2 c3 c4 c5 c6 unsold samples c9 c10 c10_state c11 c11k c12 c12k` (read-only calc cards; `c10_state c11k c12k` also in the bar because they drive flags). 4 Decide: `unsold_show decision daytag* wasted* decider_role decided_by`, exceptions `e_noslip e_nomeasure e_same e_roster e_syrup e_diff e_days*` (ticks, no tick-all). 5 Sign: `produced_by`, `checked_by`.

**02-2 Monthly salary sheet** (4 steps; head `month, year, attendance_no`; the banner "No salary sheet without the Monthly Attendance Register" stays visible)
1 List: both notes (under info), table `pay[name,salary,work_days,absent,leave,due,overtime,other,gross,adv_ded,other_ded,net,remark]` as one row per person that expands to 13 fields; find-person field; totals `t_salary t_due t_ot t_other t_gross t_adv t_other_ded t_net` (net and gross in the bar). 2 Payment: `pay_method pay_other* pay_date ledger_date ledger_line all_signed`. 3 Receipts: table `receipts[name,net,date,method,signed]`, `t_receipts`. 4 Check: `checked approved_by approved_date`. Amounts only for roles with the salary permission (server decides, unchanged).

**03-1 Transfer challan** (4 steps; head `ttype from_loc to_loc shift vehicle driver out_time handover_point`)
1 Dispatch: `as_demand demand_sheet_no outside outside_reason* cust_order order_no* prod_dates grades`. 2 Items: table `items[item,unit,grade,prod_date,tag,demand,sent,received,diff,remark]` (min 3; compact row `I-001 - KG - sent 20 / recv 20 - diff 0`; a non-zero `diff` shows a warning glyph). 3 Receive: `count_time in_time sender_counted receiver_counted dates_ok tag_ok damage_note liability` (kept together with `diff`; the transit state stays in the header). More (4 groups closed with badges, as collapsed today): Return to factory `returns[item,qty,reason,paper_no]`; Crates and trays `crates_sent crates_back crates_due trays_sent trays_back trays_due crates_match`; Posting `in_factory_sheet factory_sheet_no in_stock_ledger both_papers`; Customer or party delivery `order_invoice_no recv_name recv_phone pay cash_amount*`.

**10-2 Expense voucher** (3 steps, or accordions when 3 sections or fewer; head `time sheet_no`)
1 Expenses: table `lines[head,to,receipt,amount]` (min 3 rows; compact row `Staff meals - paid to ... - receipt yes - Tk 120`; Enter flow adds the next row), `total` (in the bar). 2 Limit and receipts: `money_account_id* receipt_photos limit_text approved_by* no_receipt_reason* drawer_untouched`. 3 Imprest check: note as banner, `cash_morning cash_now receipts_total sum_cr* imprest_text*`. The three red or yellow imprest flags stay above the form and are counted in the bar. Paper block: More group, forced open on paper mode.

### 4.3 Settings and hub screens (every row kept)

| Screen | Where every item lives |
|---|---|
| **Switchboard** | Every rule of kind switch or choice stays in its module accordion (12 modules, badge `n on - n changed`); the per-form blind-count and PIN switches stay in their own group "Per form / place switches"; the link "Numbers and limits are in Settings" stays. A pinned **Safety switches** group at the top (owner picks; suggestion `blind_count_on pin_signature_on block_on_missing_limit entered_later_on accounting_on vat_on smart_defaults_on`). Row: plain label, one-line effect, switch with word, "Changed" chip, menu (Reset to default, History, Who may change). Key and raw choice values under Details. Choice rules open a sheet of radio rows with words. Undo toast 8 s on every switch; sensitive rows show the impact sentence and level A3. |
| **Role x form matrix** and **Form rules** | Role chips (all roles except owner); "Allow self-approve" switch directly under the role picker; every form row (about 45) keeps its three toggles with text labels (matrix: View / Enter / Approve with the same coupling, no view clears enter and approve; rules: `count_first`, `red_block`, `enabled`), grouped in 11 area accordions with `n approve` badges; `red_block` OFF carries a warning marker and the area badge counts "red not blocking"; "Copy permissions from <role>" is a sheet with a diff applied through the existing `role_form_perms` upsert; undo per toggle. |
| **Home** | Every block of today's Home moves, none is deleted: Sell / Owner-mode buttons to the orb and the Needs-you block; "Needs your decision" and "Oldest first" to To do and Needs you; "Today's sheets" to My jobs (sheet plus status chip) and Menu > Forms; quick actions, favourites and tiles to My jobs and pins on Today; Business/Accounting switch, period tabs and stat cards to Numbers (collapsed for staff, open for owner and approvers; salespeople see "My sales today"); 14 module tiles and 13 category tiles to Menu (areas, Classic); Control Center card to Menu > Setup; "All your forms" to Menu > Forms (grouped by book, code + name, count 42); "Details: problems and numbers" to Numbers > Details; Recent to the empty state of Find. |

### 4.4 The other screens (fields kept; location rule, from Audit D section 4)

| Screen | Where the fields live |
|---|---|
| 02-7 Duty and backup card | Rules notes become a one-line banner + info. Sections A to D open, E to I closed with `n vacant - n partial` badges. Each slot is a compact row `Holder - Complete/Partial (n left) - signed`; expanding shows `name, vacant, start*, skill*, part_n*, holder_sig*, appr` (approver signature stays checker-only). `extra`, `history`, `key_where`, `owner_approved`, `owner_date`, head `last_update` stay in their sections. The pair checks stay in the flags box; a row that breaks a pair shows a warning glyph. |
| 02-8 Skill checklist | Head `slot, initials, holder, place, start, end` in the header card. Section A (12 rows `na, done, date, verifier`) open; B to G (`done, date, verifier`) closed with `n/m done`. Result group `verified_n, all_done, posted*, rest_date, holder_signed` and approval `approved, approved_date` at the bottom. No tick-all; `all_done` is an explicit tick. |
| 04-3 Stock count sheet | Head `start_time, end_time, counted_by, storekeeper, kind`; `movement` Yes/No, `movement_detail*`; table `rows[item,unit,count,book,var,reason]` (min 5) as compact rows; with blind count `book` and `var` stay masked until sealed; `witness*`, PIN signature box and the Seal button stay visible and in the bar. The "storekeeper must not count" rule stays a one-line banner. |
| Location settings | Tabs A Cash and limits (14 settings), B Time and place (6), C Products and storage (6 + fridge family of 9 + day tags 7), F Purchase and count (3). Every `SETTING_DEFS` entry stays a row; the `Need data` chip stays and the tab label shows `! n need data`. Per-field Save appears only when changed; "Save n changes" runs the same per-key calls. Location picker and "Settings versions" link stay in a sticky strip. |
| Access manager | The 12 grants `view_cost, view_profit, view_reports, export_data, salary_view, view_daybook, supplier_manage, settings_invoice, location_manage, head_management, settings_approve, list_manage` stay: granted ones are rows with scope chips, not granted ones sit in a closed group "Not granted (11)" as `+ Give` buttons; sensitive grants carry a "sensitive" marker; the give sheet is unchanged. |
| Customer tiers | 7 tiers with Edit visible and Up, Down, Retire in the row menu (Retire keeps its reason); "New tier"; the five switches (pre-approved tier discount, move up automatically, refresh may also move down, loyalty points, customer gifts); five numbers (points per 100 taka, value of a point, minimum points, days around a birthday, days a gift stays valid); Preview (writes nothing); Gift rules; "This month by tier"; the disabled Retire of the default walk-in tier stays visible. |
| Partners and deed | Section select, "All deeds", Deed tab (title, effective from, to, signed paper photo, Save), Parties (role, remove, add), Clauses (`title_bn, title_en, text_bn, text_en`, order, remove, add, "Save clauses"), Profit rules (step sentence, Edit, order, Enable/Retire, add), Trial calculation, **Activate (then it cannot be edited)** as a full-width primary in the bar on the last tab, never in a menu; readiness list above it. |
| Invoice template | Name, Kind, Default branch, Default of this kind, Active; language chips with Header and Footer text; Logo (link, file, brand logo, remove); the 14 "What to show" chips; VAT line and the "VAT is off in settings" notice (stays visible); Paper (width, font scale, 4 margins in a folded group); Preview in a sheet; All templates, Test print, Save. |
| Product edit | Core: `Product name (Bangla)*`, `English name`, `Selling price*`, `Wholesale price` (when on), `Buying price` (cost permission). Groups: Classification (category, sub-category + add, unit, base unit, sell units), Stock and price rules (wholesale on, low-stock alert, minimum stock, VAT when on, product source, track stock, active), Media and codes (images max 5, barcode + scan, Bng-Eng name, details). Then conversions and `Reason (optional)`. A loss warning (cost at or above selling price) sits next to the price pair. |
| Employee wizard | Step 1 keeps `Main work place*`, names, nickname, gender, date of birth, blood group, marital status, NID (10/13/17 digits, duplicate warning), mobile, email, both addresses, emergency contact (name, relation, mobile), education, in groups Essentials, Contact and address, Emergency contact, More about the person. Steps 2 to 6 (Job, Pay and facilities, Documents and photo, Deed, Review) keep their fields; Review lists what is missing with jump buttons. |
| New purchase bill | Location, Supplier*, Supplier's bill no, Bill date; lines (Item, Qty, Unit, Unit cost, Amount, stock-effect note) as compact rows; Discount; Pay now chips (Cash, Mobile, Card, Bank, All on credit); Paid, Due; Note; Bill photo. The credit warning stays under Due; the cost-jump warning chip is a proposal with an owner threshold. |
| Assistant | All 25 suggested questions stay: 5 category chips (Today, Money, Stock, People, Setup) show 4 each plus "More questions". Per answer: table, `Open: ...`, `Export CSV`, `Print`, `Ask why` (primary visible, others in the menu), the "Verified (computed by the server)" line, "Assistant settings and usage (owner)". The verified/partial badge is never collapsed. |
| POS cart and pay | Cart lines (qty stepper, price override, remove), retail/wholesale, discount (amount or percent), total, pay modes (Cash default = total, Mobile, Card, Bank, Due), customer (mobile, name, tier chip, "Apply tier discount", gift reminder), note, Back, Confirm. When a rule makes the customer mandatory (wholesale, due, discount) that block is **not** collapsed and Confirm shows the reason. |
| Business analysis | Period select, 4 KPI cards, the "not enough days" notice, Break-even, Purchase plan (7 days), limit suggestions with their "I'll set it" buttons, ABC list, unsold items, staff-signals table (6 columns as expandable rows). The notices stay at the top of their tab. |

---

## 5. Preservation proof: nothing lost, checked by machine at every step

### 5.1 The tool that already exists

Branch `worktree-agent-af358bfac93193f23`, commit `ac004ce` ("UI no-loss safety net") holds the inventory. It is **not yet in the branch this design lives on**; merging it is step zero (W3-M).

| File | Role |
|---|---|
| `tests/ui_inventory/baseline.json` | 6,917 items, one per line, sorted, deterministic. Never edited by hand except to retire an item in a reviewed commit with a reason |
| `tools/build_ui_inventory.py`, `tools/ui_inventory_runtime.js` | Extractor. Loads `web/*.js` in the order of `index.html` in a sandbox and reads `BOS.IA`, `BOS.forms`, `BOS.SETTING_DEFS`, i18n texts, registered pages; parses seed SQL for forms, rules, grants, option lists; scans HTML in the JS for controls |
| `tools/check_ui_inventory.py` | The gate. Exit 0 = nothing lost, exit 1 = lost or renamed (list printed) |
| `tests/ui_inventory/aliases.json` | Intended renames. Types `rename`, `prefix`, `label`, `placement`. **Every entry needs a non-empty `reason`**; there is deliberately no alias that deletes |
| `tools/test_ui_inventory.py` | Self-test: proves the gate fails when a route, field, option or button label is removed |
| `.github/workflows/ui-inventory.yml` | Runs the check on every push and pull request |
| `docs/UI_NO_LOSS_RULE.md` | The rule and the process |

What the baseline holds [baseline]:

| Kind | Count | Kind | Count |
|---|---:|---|---:|
| route (`route:<route>`) | 102 | form (`form:<code>`) | 45 (42 paper + `ITEMS`, `ITEM_COST`, `POS`) |
| page (registered screens) | 91 | field (`field:<code>:<key>`, table columns as `<table>.<col>`) | 1,742 |
| group (13 categories) | 13 | option (`option:<code>:<field>:<value>`) | 662 |
| button / tab / link / action | 895 / 10 / 14 / 30 | select / select option / input / textarea | 301 / 185 / 514 / 19 |
| rpc (server calls from screens) | 405 | setting: rule / grant / location | 297 / 84 / 64 |
| text (i18n keys) / do / qa | 215 / 11 / 2 | info only: keyword / section / note / placement | 811 / 222 / 89 / 94 |

Fails: a `must` item is missing, or its label changed in any language, or a live route stopped being live or left the drawer. Notes only: `info` items and moves of group, bottom-bar or Home slot. Additions never fail. Limits: HTML built from data and options from live lists are seen only as far as the code states them (`conf: medium`); 20 "unparsed" lines are listed by `--report`. The check cannot tell whether a screen works; it tells that nothing it showed has gone. The browser tests stay for behaviour.

### 5.2 The gate for every step

| Gate | When | Commands and pass condition |
|---|---|---|
| **G0** once | Before any package starts | Merge `ac004ce`. On the untouched branch run `python3 tools/check_ui_inventory.py` (must exit 0), `python3 tools/test_ui_inventory.py`, `python3 tools/check_ui_inventory.py --report`. Save the report counts in `docs/integration/W3-M.md` as the starting numbers |
| **G1** per package, before merge | Every package of section 7 | `python3 tools/check_ui_inventory.py` exit 0; `python3 tools/test_ui_inventory.py`; `python3 tools/check_no_demo_leak.py` prints OK; `python3 tools/glossary.py` prints 0 inconsistent (after W3-D fixes the 6 known terms); `node tests/web/ia_test.js <abs tests/web>` plus nav, nav2, control, favsync, settings2; the new parity and reach tests of 5.5 |
| **G2** per package, switches OFF | Same | The old screens render byte-identical: DOM hash of 12 key screens equals the hash recorded at G0 |
| **G3** per package, switches ON | Same | Parity: the set of `data-p` paths per form, and of `data-act` / `data-k` keys per screen, with the new switches on and "Show everything" on equals the set with the switches off |
| **G4** after merge | Integrator | `python3 tools/check_ui_inventory.py --update-baseline`, commit. New items are protected from then on |
| **G5** intended rename | Never silently | One entry in `aliases.json` with a reason, listed in 5.4 and approved by the owner |

Retiring anything is outside this programme. The old files and the old code paths stay (they are the Classic view and the rollback). After two releases the owner may decide to retire a path, in a reviewed commit that edits `baseline.json` and says why.

### 5.3 How this design stays inside the gate

1. New registry fields are additive: `area`, `sec`, `module`, `old`, `jobs`. The legacy `group`, `drawer`, `status`, `mob`, `mod`, `home`, `cc`, `qa`, `kw` values are not touched, so no placement note is raised either.
2. New routes and pages are additions: `menu`, `area/<id>`, `forms`, `all`, `checks`, `help/cards`, `flow/setup`, `flow/firstday`, record routes. No existing route is renamed or removed; all dynamic patterns keep their URLs (`#/form/<code>`, `#/entry/new/<code>`, `#/entry/<id>`, `#/group/<id>`, `#/report/<key>`, `#/flow/<key>`, `#/items/edit/<id>`, `#/employee/<id>`, `#/settings2/<page>`).
3. New surfaces use **new text keys**. Existing keys keep their text. The new bar says "Today"; the old bar keeps its "Home" key for Classic.
4. Code that moves to another file gets a `prefix` alias with a reason. Code that is only wrapped in a flag stays where it is.
5. The extractor gains two info-level kinds so that the design itself is protected after approval: `area:<id>` (8) and `job:<id>` (about 65). Work: 0.5 day in W3-M. Jobs then cannot silently disappear.
6. Because the extractor is static, three run-time checks complement it (5.5).

### 5.4 The rename ledger (the only intended text changes)

| Old | New | Why | Gate |
|---|---|---|---|
| "Advance options" (items edit) | "More options" | "Advance" also means a money advance here (Audit D 5.5). `More options` already exists in `bulkitems.js` and `items2.js` | Shown only in the new view. The old string stays in the old code path, so no alias is needed. If the owner also wants the old view changed (OA-11), one `label` alias with a reason. Old words stay as search keyword |
| 13 category names | 8 area names | Area names are **new items**. The 13 names stay as `group:` items, as the Classic menu, and as a grey "was: Sales & POS" subtitle on area pages for two releases | none needed |
| Screen titles "Attendance 2", "Finance 2", "Staff" versus "Employees" | **not renamed** | Wave 3 item U-38 proposed renames; this design does not. The plain verb lives on the job card; a grey subtitle explains the screen | If the owner later decides, one alias + permanent search alias per rename |
| "Control Center" | **not renamed** | Subtitle "Setup" only | none |

No form name, form code, field, option, route, button or text key is renamed by this design; the one wording difference above exists only inside the new view.

### 5.5 Run-time checks that complement the static gate

| Test file (new, W3-M) | Assertion |
|---|---|
| `tests/web/arch_parity_test.js` | For all 41 form pages (0-1 opens `#/locset`) and the screens of section 4: the sorted `data-p` path set and the `data-act` / `data-k` set with the new switches ON and Show everything ON equals the set with them OFF. Table columns are included |
| `tests/web/arch_reach_test.js` | For 12 contexts (11 seeded roles + one grants-only accountant): every record with `ok(c)` true is on its area page, in A-Z, found by Find on its label, its `old` names and its route; `#/<route>` opens it; taps: Find <= 3, A-Z <= 3, area "Every day" row <= 3, folded row <= 4, Forms door <= 3; Today shows no job the role cannot enter |
| `tests/web/arch_off_test.js` | Master switch OFF, or `localStorage.bos_ia_arch='off'`, or storage blocked or corrupt: old Home, old bar and old drawer render; DOM hash equals G0 |
| `tests/web/arch_complete_test.js` | Fixtures `ia_routes_v0.json` (102 ids) and `labels_v0.json`: every id resolves in `BOS.ia.resolve()`; every record has `area` and `sec` (a missing `module` is filled from `group` by the default map); every old label is rendered unchanged somewhere reachable or listed in the rename ledger |
| `tests/web/settings_cover_test.js` | Every `setting:rule` (297) and `setting:grant` (84) of the baseline is in exactly one purpose card's "All settings" list and in the Switchboard A-Z; an unmapped key lands in the visible card "Other" and fails the test |
| `tests/web/arch_jobs_test.js` | Every job id points at an existing route or form; every form code appears in exactly one job; no job points at a renamed screen |

Counts a reader may meet: Y counted 879 distinct `data-act` ids in `web/*.js`; the baseline lists 895 button items (it also counts buttons with other keys). Both are guarded.

### 5.6 The old-to-new map and how to produce it

The full map is **generated, not typed**: 102 routes + 8 pending pages, 45 form codes, 1,742 fields. Typing it by hand is what let Audit C's table drop `moneyaccounts`.

```
# existing tools (after merging ac004ce)
python3 tools/check_ui_inventory.py                      # the gate
python3 tools/check_ui_inventory.py --report             # counts per category, confidence split, unparsed list

# new tool, built in W3-M (does not exist yet)
python3 tools/build_ui_map.py --baseline tests/ui_inventory/baseline.json --format md  > docs/UI_MAP.md
python3 tools/build_ui_map.py --baseline tests/ui_inventory/baseline.json --format csv > docs/UI_MAP.csv
python3 tools/build_ui_map.py --screen 14-1              # field map of one form: field id -> step, group
python3 tools/build_ui_map.py --check                    # exit 1 if any baseline route, form or field has no new home
```

`build_ui_map.py` reads the baseline for the old side and, for the new side, the registry fields (`area`, `sec`, `module`, `jobs`, `old`) through the same node runtime, and the form specs' new metadata (`steps`, `more`, `summary`) for fields. Columns of the route map: old route, old group, old drawer flag, new area > section, module, jobs, also reached via. It exits with an error when a route has no `area` or a registered page is missing. The owner signs the generated map once per release (a one-page diff, "these N items moved, these M did not").

### 5.7 Old categories to areas (13 to 8)

| Old category (`group` id) | New area | Notes |
|---|---|---|
| Dashboard (`dash`) | My day (Today) | one row: `home` |
| Items & Master Data (`item`) | Goods (price, new product, bulk) and Setup (lists, units, import, types) | `products` is a hidden alias of `items` |
| Inventory & Stock (`stock`), Purchasing & Suppliers (`purch`) | Goods | Buying is a section of Goods |
| Factory & Production (`factory`) | Make | `flow` (routines) moves to My day |
| Sales & POS (`sale`), Customers, Orders & Invoices (`cust`) | Sell | `invoice` moves to Setup > Print and paper |
| Accounting & Finance (`acc`) | Money | HR items (`employees`, `employees/new`, `deeds`) go to People |
| Approvals & Exceptions (`appr`) | Checks | six inbox routes become filtered views of one list |
| Reports & Analytics (`reports`) | Reports | `assistant` is also reached from the Help button |
| Staff, Roles & Permissions (`people`) | People and Setup > Access | `matrix` goes to Setup > Access > By form |
| Locations (`loc`), Administration & Settings (`settings`) | Setup | `partners` to Money; `owner` to My day; `parallel` and `rollout` to Setup > Places > Go live |

Records per area now (X's ledger, 102 in total): My day 3, Sell 7, Goods 11, Make 5, Money 11, People 10, Checks 11, Reports 5, Setup 35, Me 1, Help 1, hidden aliases 2. After the 8 pending screens (110): Sell 8, Money 15, Checks 12, Reports 6, Setup 36; the others unchanged.

### 5.8 The 42 paper forms (code, area, job, ways)

Form code, paper name and version stay exactly as in the `forms` table; the job name is an addition. "Twin" = a dedicated screen does the same job; "Partial" = the screen covers part of it; "Form-only" = no screen. The classification comes from Audit C 2.5 and the path domains of `phase48.sql` and must be confirmed on screen by W3-F [unverified per pair].

| Code | Area | Job (plain verb) | Ways |
|---|---|---|---|
| 14-1 | Sell | Count the drawer and close the day | Form-only (wrapped by the Close-day routine) |
| 14-2 | Sell | Fill the jalebi counter record | Form-only |
| 20-1 | Sell | Take an order | Twin (`onlineorders`, `inbox`) |
| 20-2 | Sell | Approve a discount | Twin (POS discount sheet, `discounts`) |
| 20-3 | Sell | Take a return or complaint | Twin (`salereturn`) |
| 20-4 | Sell | Make a party invoice | Twin (POS wholesale) |
| 20-5 | Sell | See a party ledger | Twin (`dues`, `customers`) |
| 20-6 | Sell | Settle online and delivery money | Partial (`onlineorders`) |
| 03-1 | Goods | Send stock to another place | Twin (`stock` Transfer; path `stock_transfer`) |
| 04-1 | Goods | Receive goods | Twin (`purchase/new`; rule `grn_receipt_source`) |
| 04-2 | Goods | Issue material | Twin (`stock` Issue; path `stock_issue`) |
| 04-3 | Goods | Count stock | Twin (`stock` Count; path `stock_count`) |
| 04-4 | Goods | Look at the store ledger | Twin (`stock` ledger) |
| 08-1 | Goods | Ask for a repair | Partial (`assets`) |
| 06-1 | Goods | Ask to buy | Form-only |
| 06-2 | Goods | Compare supplier quotes | Form-only |
| 06-3 | Goods | Order from a supplier | Form-only |
| 06-4 | Goods | Check a bill and ask for payment | Partial (`purchase`, `payables`) |
| 06-5 | Goods | See a supplier ledger | Twin (`payables`) |
| 05-1 | Make | Fill the factory daily sheet | Twin (`recipes` run; path `production`) |
| 05-2 | Make | Write a product spec | Form-only |
| 05-3 | Make | Write or read a recipe card | Twin (`recipes`, `recipebook`) |
| 05-4 | Make | Run a yield test | Form-only |
| 05-5 | Make | Decide on a new product | Form-only |
| 10-1 | Money | Hand cash to the hub | Twin (`cashmoves`) |
| 10-2 | Money | Add an expense | Twin (`quickexp`, `daybook`; path `expense`) |
| 10-3 | Money | Reconcile digital payments | Twin (`wallets`) |
| 10-4 | Money | See the cash position | Partial (`daybook`, `accounts`) |
| 10-5 | Money | Reconcile receivables and advances | Form-only |
| 18-1 | Money | Record marketing spend | Form-only |
| 01-1 | Reports | Write the weekly review | Form-only |
| 01-2 | Reports | Fill the monthly P&L and KPI | Partial (`biz`) |
| 02-1 | People | Mark attendance | Twin (`attendance`, `attend2`) |
| 02-2 | People | Run payroll | Twin (`payroll`; path `payroll`) |
| 02-3 | People | Give or recover a staff advance | Partial (`payroll`) |
| 02-4 | People | Register an employee | Twin (`deeds`, `employees`) |
| 02-5 | People | Apply for or decide leave | Twin (`leave`) |
| 02-6 | People | Clear an employee who leaves | Form-only |
| 02-7 | People | Plan duty and backup | Form-only |
| 02-8 | People | Check skills | Form-only |
| 11-1 | People | Hand over my shift | Form-only |
| 0-1 | Setup | Set a location's limits | Twin (`locset`; the form page opens it) |

Totals: 21 twin, 6 partial, 15 form-only = 42 (X). The three permission codes `ITEMS`, `ITEM_COST` and `POS` have no page; they stay in Setup > Access > By form. Each form appears on (a) its area page Forms strip, (b) Menu > Forms in paper-book order with today's status for my place (Done, Draft, To do, Paper), (c) Find by code, (d) its job card. `#/form/<code>` and `#/entry/*` are unchanged.

### 5.9 The 8 pages that exist but are not yet in the menu

Each has an integration note that says "add one `rec(...)` line to `ia.js` and one `<script>` to `index.html`". The integrator registers them in step 1 (W3-N hands over the `area`, `sec`, `module` values below); the baseline already lists them as `page:` items.

| Page | Package | Area > section | Module | Also reached via |
|---|---|---|---|---|
| `#/openparties` | W1-A | Money > Accounts and books > Opening dues | Accounts | Setup checklist step "Opening balances" |
| `#/periodlock` | W1-B | Money > Month and year > Period lock | Accounts | Setup > Rules by purpose > Books |
| `#/returnrules` | W1-C | Setup > Rules by purpose > Selling | Sales | button inside "Take a return" |
| `#/profitcheck` | W1-D | Reports > Profit and business | Reports | Money |
| `#/moneycontrols` | W1-E | Money > Accounts and books > Controls | Accounts | Setup > Rules by purpose > Cash and counting |
| `#/otherincome` | W1-F | Money > Cash today > Other income | Accounts | Find "scrap", "rent received" |
| `#/bankreceipt` | W1-F | Sell > Every day > Bank and cheque receipts | Customers | Dues action |
| `#/freshness` | W1-G | Checks > Audits > Books freshness | Controls | Money > Month and year |

### 5.10 First 30 rows of the route map (examples; the tool prints all 110)

Old side from the baseline (alphabetical order of route id); the `group`, `drawer` and `status` values do not change.

| # | Route | Old group | Old drawer | New area > section | Module | Also reached via |
|--:|---|---|:-:|---|---|---|
| 1 | `accounts` | acc | yes | Money > Accounts and books | Accounts | Find "ledger" |
| 2 | `assets` | stock | yes | Goods > Equipment | Stock | job "Ask for a repair" (08-1) |
| 3 | `assistant` | reports | yes | Help (?) > Ask; also Reports | Reports | Help button on every screen |
| 4 | `attend2` | people | yes | People > Attendance (Check in) | People | job "Check in" |
| 5 | `attendance` | people | yes | People > Attendance (Board) | People | job "Mark attendance" (02-1); Grid G4 |
| 6 | `backup` | settings | yes | Setup > Safety | Setup | checklist step 12 |
| 7 | `balancecheck` | acc | yes | Checks > Audits | Controls | Money > Month and year |
| 8 | `benefitsx` | people | yes | People > Pay > Benefits | People | tab |
| 9 | `biexport` | reports | yes | Reports > Export | Reports | Find "export" |
| 10 | `biz` | reports | yes | Reports > Profit and business | Reports | Numbers block (owner) |
| 11 | `brandpnl` | reports | yes | Reports > Profit and business > By brand | Reports | tab |
| 12 | `bulkitems` | item | yes | Goods > Items and prices > Bulk edit | Items | Grid G5 |
| 13 | `cashmoves` | acc | yes | Money > Cash today | Accounts | job "Move cash or bank money"; form 10-1 |
| 14 | `changes` | appr | yes | Checks > Inbox (filter Change) | Controls | Setup tile kept |
| 15 | `control` | settings | yes | Setup > Setup home (title stays "Control Center") | Setup | Setup area; owner Needs you |
| 16 | `costattrib` | factory | yes | Make > Costs (tab 3 of 3) | Production | Find "which showroom" |
| 17 | `costing` | factory | yes | Make > Costs (tab 1 of 3) | Production | Find "cost" |
| 18 | `costsources` | factory | yes | Make > Costs (tab 2 of 3) | Production | Find "electricity" |
| 19 | `customers` | cust | yes | Sell > Customers | Customers | record page Customer |
| 20 | `daybook` | acc | yes | Money > Cash today | Accounts | job "Look at the day book" |
| 21 | `deeds` | acc | yes | People > Employees > Deeds | People | tab |
| 22 | `delegation` | settings | yes | Setup > Access > By person | Setup | Find "delegate" |
| 23 | `discounts` | reports | yes | Reports > Sales reports | Reports | Sell (form 20-2) |
| 24 | `dues` | cust | yes | Sell > Every day | Customers | job "Collect a due" |
| 25 | `emergency` | appr | yes | Checks > Inbox (filter Emergency) | Controls | Needs you |
| 26 | `employees` | acc | yes | People > Employees | People | record page Employee |
| 27 | `employees/new` | acc | yes | People > Employees (button) | People | job "Register an employee" (02-4) |
| 28 | `eqcheck` | appr | yes | Checks > Audits | Controls | Find "re-check" |
| 29 | `exceptions` | appr | yes | Checks > Inbox | Controls | Needs you; To do |
| 30 | `finance2` | acc | yes | Money > Accounts and books > Bank, VAT, year-end | Accounts | Find "bank" (title "Finance 2" kept) |

Field examples (ids are the baseline ids and do not change; the new side is the step and group):

| Baseline id | Type | New home |
|---|---|---|
| `field:14-1:cash_count` | denoms (required) | 14-1 > step 3 Cash > Cash count pad (data-p paths `cash_count.n1000` to `n1`, `cash_count.coin` unchanged) |
| `field:14-1:fridges.cold` | tick | 14-1 > step 1 Opening > fridges table, expanded row |
| `field:14-1:c1` | tick (required) | 14-1 > step 5 Close > checklist `c1` to `c16`, counter 0/16 |
| `option:14-1:day_type:busy` | option | 14-1 > header card `day_type` |
| `ctl:entry.js:button:e_count_save` | button | stays in `entry.js`; in the bar or the Cash step, same `data-act` |
| `setting:rule:blind_count_on` | rule | Setup > Rules by purpose > "How do we protect cash and counts?"; Switchboard pinned Safety group |

---

## 6. Safety fixes that must land before any screen is folded or compacted

Folding, tabs, steps and lazy panels make three existing weaknesses worse. They are small, they edit integrator-owned files, and they are built **first** (package W3-M, integrator slot). No fold, step, tab or Today card ships before all three are merged and tested. All three are verified in the current code.

### S-1 The "missing fields" sheet lists labels but does not open the folded section

| | |
|---|---|
| Where [code] | `web/entry.js`: `missingRequired()` (line 628) returns only label strings. Three call sites show them as plain notices and nothing else: Submit (about line 679), approve (about line 703), send change (about line 880). `E.openSecs` (lines 237, 625) remembers open sections only in memory. 14-1 already has 6 collapsed sections [D]. |
| Risk | A required field sits in a closed section. The person is told "something is missing" and cannot find it. Compaction would hide far more. |
| Fix | (1) `missingRequired()` returns objects `{label, path, sec, row}` and keeps a string view for old callers. (2) The sheet shows one button per item (`data-jump=<path>`). Tap: close the sheet, open the section (add it to `E.openSecs`), expand the table row, scroll the field to one third of the screen, focus it, flash it 1.2 s. (3) On Submit, every section holding a required empty field or a red flag is forced open, and the closed summary shows a text badge `! k required missing`, `k red`. (4) A red flag in the flags box gets "Go to field" when it names a field or a section. |
| Tests | Audit D T3 (submit empty 14-1 and 10-2, click the first item: field in viewport, group open, focus set, also inside a closed group and inside a row) and T6 (red flag in a closed section: badge text present, flags box visible, Submit opens it). |
| Effort | 1.5 days, owner: integrator (edits `entry.js`). |

### S-2 The `locations.js` submit guard reads the page, not the data

| | |
|---|---|
| Where [code] | `web/locations.js` lines 323 to 328. `blockOn()` reads rule `block_on_missing_limit`. The wrapper of `H.e_submit` then searches the DOM for a `.notice.warn` that contains the "limits needed" text. If no such notice is found the submit goes through. |
| Risk | If the notice sits in a closed section, an inactive tab or a lazy panel, `find()` returns nothing and the guard **silently stops working**. A form is then submitted with a missing limit although the owner switched the block on. |
| Fix | `entry.js` exposes the computed state (`E.calc.needs`, read through `BOS.entry.needs()`); `blockOn()` and the wrapper read that value, not the DOM. The notice also stays rendered outside every panel (above the tabs), as a courtesy to the reader. `forms_stock.js:531` (wraps `BOS_PAGES.form`) is re-grepped before W3-H starts. |
| Tests | Audit D T5: rule on and a missing limit: Submit is refused with compaction on and off, also when the notice would be inside a closed group (test removes it from the DOM). |
| Effort | 0.5 day, owner: integrator (edits `entry.js`, `locations.js`). |

### S-3 "Unknown" is shown as zero or as done

| | |
|---|---|
| Where [code] | (a) `web/nav.js` `counts()` (line 186 on): the helper `q()` maps every error to `0` (`r && !r.error ? count : 0`, `() => 0`), and several RPC calls sit in `try { } catch (e) { /* phase not installed */ }`. Home shows "All clear. Nothing needs you now." (`nav.js` `all_clear`) whenever no row has a count. A failed or missing call therefore reads as "all clear". (b) `web/flow.js` `check()` returns `'unknown'` for any error and for every plain link step (comment: "a plain link: nothing can tell, so it is never ticked"); the routine screen already shows a neutral "Check manually" chip, but the new Today, To do and Day board would consume these values. |
| Risk | The most trusted sentence on the screen ("All clear") is false when a call failed, the phase SQL is not installed or the phone is offline. About a third of the jobs have no done-signal at all (sell, collect dues, bank deposit, pay supplier, reports) [Y]. |
| Fix | (1) `counts()` returns `null` for a failed item and a number only for a loaded one; the Home rows treat `null` as "not loaded". (2) "All clear" is shown only when **every** relevant count is loaded and zero. Otherwise "Checking..." and then "Could not check. Try again". A count that errors shows `?`, never `0`. (3) `flow.js` exposes `BOS.flow.state(routine)` returning `{done, todo, unknown, skipped}` and a tri-state per step; consumers must not map `unknown` to `done`. (4) Jobs without a done-signal show **no** state word (not "Done", not "unknown"); the "Done" group on Today holds only items with a positive signal. (5) Offline: last known values with an "as of" stamp. |
| Tests | New `tests/web/arch_unknown_test.js`: stub every RPC to fail: Home never shows "All clear"; a link step never shows done; with data, "All clear" appears. |
| Effort | 1.0 day (0.5 `flow.js`, 0.5 `nav.js`), owner: W3-M for `flow.js`, integrator for `nav.js`. |

### 6.1 Also required before the first fold ships (acceptance items of the packages, not separate fixes)

| Item | Where it is enforced |
|---|---|
| Blind count: a tab, step or lazy panel never reveals a masked value (`blindMask()` runs on all `[data-calc]`); the Grid never fetches the book quantity before sealing | W3-H test T10; W3-P guardrail |
| No tick-all on checklists (Audit D S5) | W3-H, W3-P |
| Remembered fold state: storage empty, corrupt or blocked still renders (try/catch, schema check) | W3-G test T4 |
| Required, red and irreversible actions are visible or carry a text badge; Submit, Approve, Activate, Pay and Close-day stay in the sticky bar, never behind a menu | W3-G, W3-H |
| `data-ctl="off"` on every new container so `BOS.ctl.enhance()` does not rewrite new markup | W3-G |
| Class names and `data-*` hooks that tests rely on are never renamed (`.rowcard .sec .actionbar data-sec data-p data-act`) | all |

Order inside W3-M: S-1 and S-2 first (they edit `entry.js` and `locations.js` before W3-H owns them), then S-3, then merge, then the other packages start. Total 3 days; the rest of W3-M (map tool, harness, fixtures) is 2.5 days and runs in parallel.

---

## 7. Build plan

### 7.1 Rules that keep parallel work safe (from `UNIFIED_BUILD_PLAN.md` 4.1, applied here)

1. A package owns its new web files, its test files, its phase-number range (only where SQL is needed) and its integration note `docs/integration/<package>.md`. Nobody else writes them.
2. A package never edits an integrator-owned file. It ships helpers with its own prefix and writes the exact hook text in its integration note.
3. **Integrator-owned**: `web/ia.js`, `web/index.html`, `web/entry.js` (except W3-H in its slot), `web/nav.js`, `web/app.js`, `web/styles.css`, `web/theme.css`, `web/sw.js`, `web/i18n.js`, `docs/IA_*.md`, `docs/BUILD-LOG.md`.
4. An existing screen file is edited by exactly one package per wave (the "Owns" column). Where two packages name the same file, the later one starts after the earlier one merged (stated in "Starts when").
5. Rules and grants are seeded by each package for its own keys only, `on conflict do nothing`. SQL goes in a new phase file, safe to paste twice. Agents never write to the live database; the owner pastes one phase at a time after review, on a test project first (CLAUDE.md).
6. Old files and old code paths are not deleted in this programme.

### 7.2 Work packages

Package ids are those of `UNIFIED_BUILD_PLAN.md` 4.5 where the work is the same package; W3-M, W3-N, W3-O, W3-P, W3-Q, W3-R are new. "New items" U-55 to U-60 are proposed numbers for the unified plan.

| Pkg | Item | Scope | New files | Existing files owned | Phase | Days | Starts when |
|---|---|---|---|---|---|---:|---|
| **W3-M** | U-55 (new) | Merge `ac004ce`; G0 baseline; `tools/build_ui_map.py` with `area:` and `job:` inventory kinds; harness and fixtures (replaces `compact_measure.js` of U-41); safety S-1, S-2, S-3; `BOS.flow.register` and `BOS.flow.state` | `tools/build_ui_map.py`, `tools/test_ui_map.py`, `tests/web/arch_measure.js`, `arch_baseline.json`, `arch_parity_test.js`, `arch_reach_test.js`, `arch_off_test.js`, `arch_complete_test.js`, `arch_unknown_test.js`, `arch_jobs_test.js`, `settings_cover_test.js`, `tests/web/fixtures/ia_routes_v0.json`, `labels_v0.json`, `docs/UI_MAP.md` (generated) | `web/flow.js`; integrator slot edits `entry.js`, `locations.js`, `nav.js` for S-1 to S-3 | none | **5.5** | day 1 |
| **W3-N** | U-56 (new) | Registry data and switches: `area`, `sec`, `module`, `old` for 102 records and the 8 pending pages; 65 jobs; 11 role kits; master switch, per-phone keys, nav view preset, Show everything, See as role; usage log (counters only) | `web/arch.js`, `web/jobs.js`, `web/kits.js`, `web/ut.js` | none (`ia.js` fields by the integrator) | **172** | **5.0** | `arch.js` first, rest after W3-M merged |
| **W3-G** | U-41 extended | Compact foundation (`B.ui.more/tabs/steps/bar/row/help/jump/find/undo`); tokens; Text size; `lang` per mode; self-hosted fonts; shell (header, strips, one bottom region, bar, FAB, selection bar, Show-everything pill); chrome diet; z-index ladder | `web/compact.js`, `web/compact.css`, `web/arch.css`, `web/shell.js`, `web/fonts/*.woff2` | none | **171** (`ui_compact`) | **12.5** | W3-M merged, `arch.js` available |
| **W3-A** | U-34 refined | Today (T1), five-slot bar, orb, To do list, start screen, `persona()` replaced by kits; Numbers; Help row | `web/home2.js`, `web/todo.js` | none (`nav.js`, `ia.js` hooks by integrator) | 173 (optional, only if TB6 fails) | **9.0** | W3-M (S-3), W3-N, W3-G shell |
| **W3-D** | U-38 refined | Menu surface, 8 area pages, Forms door, A-Z, Classic door, Find (full-screen, resolver, old names), glossary fix, generated route map | `web/areas.js`, `web/search2.js`, `docs/IA_ROUTE_MAP.md` | `tools/glossary.py` | 174 (optional `global_find`) | **10.0** | W3-N |
| **W3-F** | U-40 refined | Job page, Way strip and sheet, status line, Records tab with `Via` chip and linked-copy chip, first read of the 18 pairs that lack a stored fact | `web/jobcards.js` | `web/paths.js` | none | **8.0** | W3-N, W3-G; entry-header hook agreed with W3-H |
| **W3-E** | U-39 refined | Checks inbox (9 places in one list, old routes as filtered views), Access page with 4 lenses (person, role, form, who-has-this), approve-login sheet with role text | `web/approvals.js`, `web/access.js` | `web/delegation.js` | none | **6.5** | W3-G |
| **W3-Q** | U-59 (new) | Day board: place cards, conformance flags from timestamps, windows (off), staff own record | `web/dayboard.js` | none | 176 (optional view) | **6.0** | W3-A, W3-N |
| **W3-B** | U-35 + U-36 refined | Setup front page on `#/control`, typed controls, 9 purpose cards, dials, 3 business shapes, 13-step checklist (via `BOS.flow.register`), preview diff, undo, revert, coverage test | `web/setup.js`, `web/presets.js` | `web/rules.js`, `web/switchboard.js`, `web/settings2.js` | **170** (`apply_preset`) | **15.0** | W3-G, W3-N; U-36 after U-35 |
| **W3-C** | U-37 refined | Confirm ladder A0 to A4, error dictionary, undo toast; sweep of 27 files is the integrator's last step | `web/ui_confirm.js` | none | none | **5.5** | day 1 |
| **W3-H** | U-42 refined | Form engine: steps, More groups, compact rows, Enter flow, jump (extends S-1), save-state chip, denomination pad, 14 px, Way chip hook, per-form metadata (`steps`, `more`, `summary`, `carry`, `rare`) | none | `web/entry.js`, `web/forms*.js` | none | **10.0** | W3-M, W3-G |
| **W3-I** | U-43 (a) | Switchboard (T7 recipe), matrix, form rules, location settings, access, tiers | none | `web/switchboard.js`, `web/locations.js`, `web/customers.js` | none | **6.0** | W3-G, W3-B |
| **W3-J** | U-43 (b) | Purchase bill (+ Grid hook G1), POS cart foot, product edit, employee wizard, partners, invoice | none | `web/purchase.js`, `web/items2.js`, `web/employees.js`, `web/partners.js`, `web/invoice.js` | none | **6.4** | W3-G; POS foot after W2-C |
| **W3-K** | U-43 (c) + U-44 | Assistant, analysis; help "?", empty states, Call/Remind on dues, hold sale and repeat sale (POS hooks by integrator), receipt search on returns, PIN reset, coach "Practice" strip, role cards `#/help/cards` | `web/help.js`, `web/cards.js` | `web/assistant.js`, `web/biz.js`, `web/dues.js` | none | **13.2** | W3-G |
| **W3-O** | U-57 (new) | Record pages for Customer, Item, Supplier, Employee; History and `Changes` tiers | `web/records.js` | none | **175** (`audit_for`, grant `audit_view`) | **8.0** | W3-D, W3-N |
| **W3-P** | U-58 (new, gated) | Grid Kit and jobs G1 to G5 with guardrails; per-job switches | `web/grid.js`, `web/grid.css` | none (host hooks by the host file's owner) | none | **12.0** | W3-G, W3-H, W3-J; TB3 passes |
| **W3-R** | U-60 (new, gated) | Desktop layer: master-detail, dense rows, `Ctrl+K` palette, keys, scan sink, Simple look | `web/keys.js`, `web/desktop.css` | none | none | **9.0** | TB5 passes |
| W3-O+ | U-57 part 2 (gated) | Drill-down "Where this comes from" along existing keys | in `records.js` | none | none | **3.0** | TB4 baseline fails |
| **I-3** | integrator | `ia.js` fields, hooks in `nav.js`, `app.js`, `index.html`, `sw.js` (fonts, new files), docs amendments, test matrix run, final sweeps | none | shared files | **179** (plan) | **17.0** | continuous |
| W3-L | U-45 | Keyed i18n migration (optional, unchanged) | | all, mechanical | none | 9.0 | last |

Totals (computed): core packages **126.6 days**, integrator 17.0, so **core 143.6 days**. Gated: W3-P 12.0 + W3-R 9.0 + drill 3.0 = **24.0**. Optional W3-L 9.0 is outside both. SQL phases (proposal; the integrator confirms numbers against the repo): 170 `apply_preset` (plan), 171 `ui_compact` (plan), **172** rules for this design, 173 `today_state(p_loc)` only if TB6 fails, 174 `global_find(q, scopes)` (security invoker), **175** `audit_for(table, id)` and grant `audit_view`, 176 `day_board` view, 177 and 178 spare, 179 integrator (plan). Phases 88 to 169 are held by Waves 1 and 2.

SQL notes: 172 inserts these keys, all additive and off or blank by default: `ia_arch_v1` (switch, off), `show_everything_roles` (owner), `job_ways` (text JSON, blank = registry default), `role_kits` (text JSON, blank = seed defaults), `job_windows` (text JSON, blank = no windows), `checks_escalate_hours` (number, blank = off), `checks_inline_kinds` (text, default low-risk list), `dayboard_staff_view` (choice own | none, own), `home_totals_for_sales` (switch, off; name from U-34), `confirm_type_words` (switch, off), `time_format` (choice 12h | 24h, 12h), `ui_usage_log` (switch, off). Each package adds its own `ui_<capability>` keys the same way.

### 7.3 Switches, per-phone control and instant rollback

| Switch | Server rule (absent means) | Phone key | When off |
|---|---|---|---|
| **Master** | `ia_arch_v1` (OFF) | `localStorage.bos_ia_arch` = `on` or `off` | Current Home, 4-slot bar, 13-category drawer, current forms: byte-identical |
| Classic view | none | writes `bos_ia_arch=off` (button in the Me sheet and in Menu) | same |
| Compact (forms, screens) | `ui_compact` (OFF, U-41) | `bos_compact` | old markup |
| Capability (`today`, `areas`, `find`, `jobpage`, `checks`, `dayboard`, `setup`, `records`, `shell`) | `ui_<name>` (ON when master is on, unless the rule is false) | `bos_ui_<name>` = `off` | that capability reverts, the rest stays |
| Grid per job (`purchase_lines`, `stock_count`, `production_run`, `attendance`, `price_list`) | `ui_grid_<job>` (**OFF**) | `bos_grid_<job>` | form cards |
| Desktop layer | `ui_desktop` (**OFF**) | `bos_desktop` | one column |
| Text size | none | `bos_tsize` s, l or x (`html[data-tsize]`) | x1.0 |
| Show everything | `show_everything_roles` (owner) | `bos_show_all` = 1 | folds and menus as normal |
| Nav view | none | `bos_nav_view` = `today` / `modules` / `classic` | areas |

```
master(phone, rule) = phone == 'off' ? false : phone == 'on' ? true : rule('ia_arch_v1') == true
capability(x)       = master && rule('ui_' + x) != false && phone('bos_ui_' + x) != 'off'
grid(job)           = master && rule('ui_grid_' + job) == true && phone('bos_grid_' + job) != 'off'
```

Every storage read and write is in try/catch; blocked or corrupt storage falls back to the server rule; the rule alone is read through `B.rule` and applied after `B.reloadRules`. The new design is **off by default** (the current `ia_home_v2` is on by default; the new master starts off).

Rollback layers, fastest first: (1) this phone: Me > Classic view, or set `bos_ia_arch=off` (seconds, no deploy); (2) one capability: owner switches the rule false; (3) everyone: `ia_arch_v1` false; (4) one grid job: `ui_grid_<job>` false; (5) code: remove the new `<script>` and `<link>` lines, the old app returns (the new files are additive); (6) SQL: only additive objects, harmless to leave. No data is migrated, no route changes, no schema changes. Presets and rule changes are reverted by Undo (10 s) or by a Revert changeset, never by deleting history.

### 7.4 Dependency order and critical path

```
Step 0  W3-M  gate, baseline, safety S-1..S-3          (5.5 d)   blocks everything that folds content
Step 1  W3-N arch.js -> W3-G foundation (12.5 d)  ||  W3-C confirm (5.5 d)  ||  W3-N rest (5.0 d)
Step 2  W3-A Today  ||  W3-D Menu/Find  ||  W3-F Job page  ||  W3-B Setup  ||  W3-H Form engine  ||  W3-E Checks/Access  ||  W3-K help/assistant/biz
Step 3  W3-I settings family (after W3-B)  ||  W3-J transactions  ||  W3-Q Day board (after W3-A)  ||  W3-O records (after W3-D)
Step 4  Gate A, then Gate B; TB1, TB2, TB6, TB7 run here;  W3-P grids only if TB3 passes;  W3-R only if TB5 passes
Step 5  Gate C; I-3 final sweeps; docs amended; Classic door kept two releases
```

Critical path: W3-M (5.5) then W3-G (12.5) then W3-H (10) then W3-I (6) = **34 days** of package work plus merges; shorter parallel chains: W3-N then W3-A then W3-Q (5 + 9 + 6 = 20). With five or six builders the core takes about 8 to 10 weeks [unverified]. Release trains (each shippable behind switches): **R1 Safe and shorter** (W3-M, G, C, H, I, J, K: 59.1 days), **R2 Front door** (W3-N, A, D, F, B: 47.0 days), **R3 Productive** (W3-E, Q, O: 20.5 days), then the gated items. The controls backlog of Audits A and B (Waves 1 and 2) outranks R3 and the gated items.

### 7.5 Test plan per package

Every package: G1 to G3 of section 5.2 (inventory gate, switches-OFF hash, parity), `python3 tools/check_no_demo_leak.py`, no `docs/demo` material, neutral `test_*` fixtures only. Web tests run in the repo's Node + Playwright pattern (static server, stub for `vendor/supabase.js`, viewport 360x780 DPR 2) in **bn, en, mix and pseudo-Bangla (English stretched 1.6x)**, at Text size x1.0 and x1.3, and at 320x640. "Layout" means: no horizontal overflow, no clipped text, chrome within budget.

| Pkg | Tests specific to the package | Usability tasks |
|---|---|---|
| W3-M | `test_ui_map`: `--check` fails when a route or field has no home; `arch_unknown_test`; Audit D T3, T5, T6; harness writes `arch_baseline.json` for the 24 screens of section 4 | R0 baseline run on today's app (T1 to T16 and T17 to T23) |
| W3-N | `arch_complete_test`, `arch_jobs_test`, `arch_off_test`; kits: every seeded role's job list equals the expected list from `role_form_perms`; no job shown that the role cannot enter | none |
| W3-G | Audit D T4 (remembered state, corrupt, blocked), T7 (one fixed bottom bar, Confirm visible), T8 (overflow), T9 (keyboard); contrast test of tokens (edges 3:1 both themes); chrome budget on 8 templates; `lang` set per mode | T12 (switch to English and Large text), T16 (T2 at Extra) |
| W3-A | Today layout 1.0 to 1.3 pages in bn; "All clear" only with zero unknown; request count and time (TB6); tap table for 10 jobs vs Audit C | T1, T2, T4, T11; TB2, TB8 |
| W3-D | Find ranks label > keyword > route; finds `04-1`, "GRN", receipt number, serial, phone; opens the record; offline degrades; `glossary.py` prints 0; every record on its area page and in A-Z | T14, T19; TB1 |
| W3-F | Both ways listed; locked way greyed not hidden; default order per D07; switch after input asks to keep a draft; status line wording; chip words only with a stored fact; merged list shows both stores | T5, T5b (TB9), T17 (TB7) |
| W3-E | Inline decision only for kinds in `checks_inline_kinds`; money kinds open the record; decider is never the maker; old routes open the filtered list; four Access lenses show the same data | T7, T9 |
| W3-Q | Board answers the 21:30 question; no state without a done-signal; entered-later uses original time; staff see only own record; 5 places = about 0.95 page | owner task: "which shops did not count the drawer" |
| W3-B | `settings_cover_test` (297 rules, 84 grants); dial positions write ordinary `set_rule` values and show Custom on any difference; preview diff equals result; undo restores; preset off equals old values; checklist ticks from data or skip with note | T8, T9; two owner tasks of D05 |
| W3-C | grep: no `window.confirm` or `window.prompt` remains; A3 shows an impact sentence from real data; A4 needs the PIN; undo never offered on Submit, Approve, Reject, void, payments, close | T7, T15 |
| W3-H | Audit D T1 height budget, T2 field parity for all 41 forms, T10 blind masks stay masked, T13 both modes pass the existing suites; save-state chip states | T3, T4, T10, T13 |
| W3-I, J, K | Height budget per route; parity; one bottom bar; Confirm visible in POS sheet with 8 lines; every U-44 option present and permission-checked on the server | T6, T11 |
| W3-O | Four record pages: tabs <= 5; `Changes` visible only with `audit_view`; opened from Find, from a tapped name and from a list row | TB4 trace tasks |
| W3-P | G1 to G5 call the same server function as today; blind-count grid never fetches the book quantity before seal (network log test); paste preview lists invalid rows; attendance bulk-fill writes the audit note | T18, T22, T23 (TB3) |
| W3-R | only with `pointer:fine` and 900 px; phones unchanged; keys never run a financial action without the same confirm | usage log read-out |

### 7.6 Stage gates and exit criteria

| Gate | Who | Pass condition |
|---|---|---|
| **A** owner phone only | Owner (`bos_ia_arch=on` on one phone, rule still off) | Owner uses Today for one full day; walks the 12 "See as role" views; completes one real 14-1 on the new layout; makes one Approve from the Checks inbox; the inventory check and parity are green |
| **B** one shop, one week | One showroom, 5 daily forms (14-1, 10-1, 10-2, 04-3, 03-1) in Parallel for the new views | R0 comparison: no P0 task worse than R0; T1 to T6 at least 30% faster; 0 critical errors; Day board metrics read; TB2, TB6, TB7 results in |
| **C** everyone | `ia_arch_v1` on, each phone keeps its own off switch for the first month | TB1 decided PV-2; TB2 at least 90%; reach test green for 12 contexts; chrome within budget on 8 templates; owner signs the generated map |

**Stop and roll back if**: a role cannot reach one of its seeded form rights in 3 taps (the test fails); more than a quarter of phones switch themselves to Classic in the first week; entered-later or rejected entries rise beyond what was agreed; any person reports a job they could do yesterday and cannot find today (log it, fix the kit, do not blame the user).

Programme exit: all package tests green in both modes (switches OFF identical to today, ON parity); `check_ui_inventory.py` exit 0 with only the aliases of 5.4; `glossary.py` 0; `check_no_demo_leak.py` OK; baseline updated; `docs/IA_RULES.md`, `docs/DESIGN_SYSTEM.md` ("Sell first" becomes "primary job first"; tokens), `docs/IA_CONCEPT.md` (built versus planned), `docs/UI_NO_LOSS_RULE.md` and the `bos-organise` skill amended in the same change; one real 14-1 completed by the owner on the new layout.

### 7.7 Reconciliation with Wave 3 (U-34 to U-45)

| Item | Plan days | Status here | Days here | What changes |
|---|---:|---|---:|---|
| U-34 Home, personas, routines | 4.5 | **Refined** (W3-A) | 9.0 | Today of job cards replaces the 5 blocks; bar `Today, Find, orb, To do, Menu` (same positions as `Home, Search, orb, Do next, Menu`); kits read from `role_form_perms`; rule `ia_home_v3` becomes the capability `ui_today` under the master switch |
| U-35 Setup, typed controls | 5.0 | **Refined** (W3-B) | 8.0 | Seven tabs exceed the five-tab cap, so Setup is a hub of cards; adds 9 purpose cards, dials, coverage test |
| U-36 Presets, checklist | 7.0 | **Kept** (W3-B) | 7.0 | Checklist runs through `BOS.flow.register`; shapes use the same `apply_preset` |
| U-37 Confirm, errors, undo | 4.5 | **Refined** (W3-C) | 5.5 | Ladder A0 to A4; type-to-confirm becomes a setting, default off (tick + PIN) |
| U-38 IA regroup, search, glossary | 6.0 | **Refined** (W3-D) | 10.0 | **8 areas, not 9**; Buy merges into Goods; **no screen renamed** ("Attendance 2" and "Finance 2" stay with a subtitle); Find with resolver and old names; Forms, A-Z and Classic doors |
| U-39 Approvals inbox, Access | 6.0 | **Refined** (W3-E) | 6.5 | Inline decision only for low-risk kinds; Access has 4 lenses |
| U-40 Job cards | 5.0 | **Refined** (W3-F) | 8.0 | Becomes the Job page with Way strip, status line and merged Records list (hub); the owner-default list is the 20 pairs of Audit C, the other 7 use registry defaults |
| U-41 Compact foundation | 7.5 | **Refined** (W3-G) | 12.5 | Adds tokens, Text size, shell, fonts, one bottom region; harness and S-1 move to W3-M; `ui_compact` and `bos_compact` kept |
| U-42 Form engine | 7.5 | **Refined** (W3-H) | 10.0 | Adds Go-to-field sheet, save-state chip, denomination pad, 14 px, Way chip hook; still the only editor of `entry.js` in its slot |
| U-43 Screen compaction | 18.1 | **Refined** (W3-I, J, K) | 14.6 | Home (1.5 days) moves to W3-A; the shared test matrix (2.0) moves to I-3; the three disjoint parts keep their files |
| U-44 Ergonomics, help, missing options | 8.0 | **Kept + extended** (W3-K) | 11.0 | Adds coach "Practice" strip and role cards (3.0) |
| U-45 Keyed i18n | 9.0 | **Kept, optional** (W3-L) | 9.0 | unchanged |
| **New** U-55 gate and safety | n/a | New (W3-M) | 5.5 | S-1, S-2, S-3, map tool |
| **New** U-56 registry, jobs, kits | n/a | New (W3-N) | 5.0 | |
| **New** U-57 record pages | n/a | New (W3-O) | 8.0 + 3.0 gated | |
| **New** U-58 Grid Kit | n/a | New, gated (W3-P) | 12.0 | |
| **New** U-59 Day board | n/a | New (W3-Q) | 6.0 | |
| **New** U-60 Desktop layer | n/a | New, gated (W3-R) | 9.0 | |
| Integration I-3 | 9.0 | **Raised** | 17.0 | 6 days of new hooks, 2 days of shared test matrix |

Plan Wave 3 without the optional U-45 is 79.1 + 9 = **88.1 days**; this design's core is **143.6**. The difference of **55.5 days**: refined items **+23.0** (Today +4.5, Setup +3.0, Confirm +1.0, Find and areas +4.0, Checks and Access +0.5, Job page +3.0, foundation and tokens +5.0, form engine +2.5, help and coach +3.0, screen compaction -3.5); new packages **+24.5** (gate and safety 5.5, registry and kits 5.0, record pages 8.0, Day board 6.0); integrator **+8.0** (6.0 new hooks, 2.0 shared test matrix moved from U-43). [model, all effort numbers are estimates] The 24 gated days are in neither figure.

### 7.8 Teaching plan (easy to teach is a requirement, so it is built)

Staff learn three things: **Today, Find, Menu**. The owner learns five: shape, kit, dial, way, Show everything. The role card "My 6 jobs" (icon, verb, form chip) is generated from the registry at `#/help/cards`, so it changes when a kit changes. Because the app has no practice mode (entries cannot be hard-deleted), the first-day coach is an overlay that **never saves**: a persistent strip "Practice: nothing is saved", fields covered by dashed spotlights, examples shown as grey italic text tagged "Example", Save disabled and reading "Practice only", and a closing sheet "Nothing was saved". Test T21: at least 95% answer "no" to "was it saved?". Real first-week work happens in Parallel mode with normal approval.

| Minute | New salesperson, 10 minutes with a manager |
|---|---|
| 0 to 1 | "This app is for two things: what you do now, and finding anything." Show Today and Find. Language button |
| 1 to 3 | Tap the main job Sell, sell one item to the manager, show cancel. "You always come back with Today" |
| 3 to 5 | Collect a due; take a return |
| 5 to 7 | Take an order (20-1): the 3 fields that matter; show that "More options" exists |
| 7 to 9 | Airplane mode: sell, see "1 not sent", reconnect, see it send |
| 9 to 10 | Teach-back: the trainee does Sell, Collect a due and Find "receipt" alone. Pass = no help. Hand over the printed card |

Storekeeper (10 min): Receive goods (both ways shown once), Issue, Send, Count, the Low-stock chip. Showroom manager (15 min): Open shop routine, Count the drawer, Close day, Hand cash, why "Skip with a note" exists. Owner (45 min, day 0): shape, one location, Needs you, Day board, See as role, Show everything, Classic. Every script ends with the teach-back; an optional field in the kit records who signed the card.

---

## 8. Risks, what is given up, and the owner decisions still open

### 8.1 Risks

| ID | Risk | Likelihood / impact | Mitigation |
|---|---|---|---|
| R1 | A person has an unusual duty that is not in their kit, so Today lacks a job | Medium / medium | "More jobs", Menu, Find; kits come from permissions not titles; owner "See as role"; per-role reach test |
| R2 | The job registry becomes a second menu to maintain (about 65 hand-authored jobs) | Medium / medium | Jobs are an optional overlay; a record without a job is still on its area page, A-Z and Find; the test fails a record without `area` and `sec`, and a job that points at a missing route (`arch_jobs_test`) |
| R3 | Done-signals exist only for entry checks, exceptions, outbox, pending, closed days, lock (not for sell, collect, pay, reports) | High / medium | Jobs without a signal show no state word; "All clear" needs zero unknown (S-3); Day board shows "Check by hand" |
| R4 | Today and Day board multiply requests on a weak phone; cold start offline is empty (service worker is network-first with no precache; fonts come from Google) | High / medium | Compute done-signals only for the current routine (about 5 steps), reuse the 45 s cache, "as of" stamps; budget 8 requests and 1.5 s (TB6); batched `today_state` RPC if needed; self-hosted fonts and a precache list in W3-G; lazy loading only if first screen > 4 s |
| R5 | Two ways shown as one job confuse people about which record counts | Medium / high | Chip words only where a stored fact says so, else "Two ways"; owner lock shown greyed; no silent conversion; both ways findable; `paths` page kept as "Two-way jobs" under Advanced |
| R6 | Muscle memory of present users | High / medium | Classic door two releases; per-phone off switch; same URLs; no renames |
| R7 | A shared counter phone on one login gets "start on Sell" for the wrong person | Medium / high | Start screen is per login; shared logins defeat attribution anyway; leave it on Today if logins are shared |
| R8 | Presets overwrite rules the owner tuned | Medium / high | Preview diff, "apply only to unchanged keys" mode, 10 s undo, Revert, audit rows through `set_rule` |
| R9 | Bulk approvals hide risk | Low / high | No bulk for money, posting, price, period, release; inline decision only for the narrow default list |
| R10 | The Day board reads as surveillance | Medium / medium | Staff see only their own record; windows off by default; no ranking by default; frame as "what is missing" |
| R11 | Bangla verbs too long for cards | Medium / low | 3 words max, 2-line wrap, tested with pseudo-Bangla and the longest real strings |
| R12 | Registry drift: docs promise features not built (C-09), 8 screens unregistered, a hand-made map missed `moneyaccounts` | High / low | Generated map; `arch_complete_test`; docs amended in the same change |
| R13 | Grid mistakes at speed (pasting 300 wrong rows) | Medium / high | Preview then apply, one audit batch line, per-job switch, blind-count guard, no tick-all |
| R14 | 14 px body adds 10 to 12% height and may erase part of the gain | Medium / medium | Re-measure at 14 px in step 0; Compact density reduces gaps not targets; fold defaults from the form designer |
| R15 | Static inventory cannot see HTML built from data | Medium / medium | `conf: medium` list in `--report`; DOM parity and reach tests; browser tests stay |
| R16 | Effort is 55 days above Wave 3 and competes with Waves 1 and 2 (3 critical control holes in Audit A, 6 in Audit B) | High / high | Release trains R1 to R3 each shippable alone; gated items 24 days only on evidence; controls first (D21) |
| R17 | Optional SQL (`today_state`, `global_find`, `audit_for`, `day_board`) is late | Medium / low | Every feature degrades gracefully when the function is missing, as the repo does today |
| R18 | Usage log is seen as staff monitoring | Medium / medium | Counters only (width bucket, pointer type, key events), no content, off until the owner agrees (OA-8) |

### 8.2 What is given up, plainly

1. **The one-glance tree of all modules** as the front door. A power user gets Show everything, A-Z, the Modules view and Find instead.
2. **Dense landing pages.** Today is deliberately sparse; the dense table, master-detail and keyboard keys wait for evidence (PV-3).
3. **The same Home for every colleague.** Support and training get harder because two people see different Todays. See as role and the printed card reduce this; they do not remove it.
4. **One navigation system.** For two releases there are two (new and Classic), and a rule keeps them in step.
5. **Immediate fixing of confusing titles.** "Attendance 2", "Finance 2" and "Staff" versus "Employees" are not renamed now; the verb on the job card carries the plain meaning. A rename needs an owner decision, an alias and a permanent search alias.
6. **Some browsing discoverability.** Rare features are folded; people find them by Find, Forms, A-Z or Show all.
7. **Height.** 14 px body text and 48 px targets cost about 10% of height; the folds pay it back.
8. **Saved views and column sets for staff.** They exist as filter chips for people who use lists for hours; staff do not need to configure anything.
9. **Effective-from dating of history-affecting rules.** It is an accounting decision (Audit A-31), not an IA feature.
10. **Speed of release.** The baseline run R0, the tree test and the new-hire test add calendar time before the final gate.
11. **Y's lazy module loading and the keyboard layer** until TB5 and TB6 say they are needed.
12. **Z's hard 90% release gate**; replaced by "not worse than baseline, 30% faster on T1 to T6, zero critical errors".

### 8.3 Owner decisions still open (each is a setting or a choice; the safe default is already in place)

| ID | Question | Setting or choice | Safe default |
|---|---|---|---|
| OA-1 | Default way for each two-way job (27; Audit C proposes one for 20) | `job_ways` | Registry default; chip says "Two ways" where no rule says which counts (plan OD-13) |
| OA-2 | Do salespeople see shop totals on Today? | `home_totals_for_sales` | Off: only "My sales today" (plan OD-13) |
| OA-3 | Role start kits for the 11 roles | `role_kits` | Seed from `role_form_perms`; you edit exceptions only |
| OA-4 | Values of the three business shapes | `apply_preset` | Nothing applied until you confirm each value (plan OD-14) |
| OA-5 | Time windows for routines | `job_windows` | Blank: no lateness is ever shown |
| OA-6 | Day board: do staff see a ranking? escalation hours for old requests | `dayboard_staff_view`, `checks_escalate_hours` | Staff see only their own record; no escalation |
| OA-7 | Who may use Show everything | `show_everything_roles` | Owner only |
| OA-8 | Agree to the usage counters for TB5 | `ui_usage_log` | Off until you agree |
| OA-9 | 12-hour or 24-hour time | `time_format` | 12-hour (the code already uses it) |
| OA-10 | Ship Simple look (no blur, higher contrast) and left-hand mode in the first release | Me settings | Built, off |
| OA-11 | Also rename "Advance options" to "More options" in the old view | alias in `aliases.json` | No: the new view says "More options", the old view is untouched (recommended yes later, plan OD-18) |
| OA-12 | Tick-all on checklists | `bulk_tick_on` | Never; if ever built, off and audited (plan OD-18) |
| OA-13 | Type words to confirm the three red actions | `confirm_type_words` | Off: tick "I understand" + PIN |
| OA-14 | Which kinds may be decided inline in the Checks inbox | `checks_inline_kinds` | Low-risk list only |
| OA-15 | How long Classic stays as a door | choice | Two releases, then under Show everything |
| OA-16 | Bangla words for Cancel, Void, Reject | glossary | You choose (plan OD-18) |
| OA-17 | Rename any screen title | alias + permanent search alias | None |
| OA-18 | Bng-Eng mix wording | TB10 reading test | Keep the definition in `docs/LANGUAGE.md` |
| OA-19 | Who may hold the grant `audit_view` (Changes tab with old and new values) | grant | Owner only |
| OA-20 | Is a laptop used for long sessions by accountant, purchasing or you | answer, or TB5 | Not assumed |

### 8.4 What could not be verified [unverified]

- All "after" page counts and all effort numbers are models. No prototype was measured, no real device was used.
- Real-device behaviour of visible area, soft keyboard, sticky bars, `visualViewport`, TalkBack reading order, Bangla glyph widths at 14 px, parse time of 3 MB of scripts on cheap phones.
- Which record counts for each of the 18 two-way jobs without a stored fact; the 27/15 split comes from Audit C and X.
- Whether an "entered later" record carries an original time that the Day board can read; whether `user_favourites` accepts own-row usage counters under its row-level security; whether `journal_entries.source_id` and `stock_ledger.ref_id` use the same id string for every document type (needed for the reverse drill).
- The live rule and grant counts (the baseline says 297 and 84; the live project may differ), and the live `forms` table.
- Whether the licence of the fonts allows self-hosting as shipped; font file sizes.
- Phase numbers 172 to 178 against the repository at merge time; whether any tool sorts phase file names with a plain glob above 99.
- The tap tables of X and Audit C were derived from code paths, not timed on devices.
- Contrast values come from token values, not from rendered pixels.
- The inventory tooling lives on branch `worktree-agent-af358bfac93193f23` and was read there, not run in this worktree.

---

## Appendix A. Role start kits (derived from the seed `role_form_perms`; the owner can change any row)

Job lists are computed, not typed: `jobs_for(person) = ALL_JOBS.filter(job has a way the person may open).sort(kit order, then time window, then undone first)`. A person with two roles gets the merge of both kits, ordered by the first role. "Accountant" is not a role in the `roles` table; it is a bundle of grants (`view_daybook`, `salary_view`, form 10-3) that unlocks the Money jobs. Corrections to Audit C's examples: a salesperson cannot enter 14-1 by default; a factory in-charge cannot enter 06-1 or 11-1; the approver jobs belong to management, cash controller and owner, not to the showroom manager [code, X].

| Role (seed) | Orb (main job) | Typical cards | Areas shown |
|---|---|---|---|
| Owner | Needs you | Setup checklist until done; weekly review 01-1; month-end; Day board | all 8 |
| Management (view and approve only) | Needs you | Approvals, exceptions, weekly 01-1, monthly 01-2, month-end checks | Checks, Reports, People, Goods, Sell (read) |
| Cash controller | Hand cash to hub (10-1) | vouchers 10-2 to check; reconcile digital 10-3; cash position 10-4; receivables 10-5 | Money, Checks |
| Showroom manager | Today's routine (Open shop, then Close day by time) | Count drawer 14-1; hand cash 10-1; expense 10-2; hand over shift 11-1; receive and send stock 03-1; count stock 04-3; discount slip 20-2; leave 02-5 | Sell, Goods, People, Checks |
| Salesperson | Sell | Collect a due; take an order 20-1; take a return 20-3; jalebi counter 14-2; check in; send unsent | Sell |
| Storekeeper | Receive goods (04-1) | Issue 04-2; send 03-1; count 04-3; store ledger 04-4; wastage; low stock | Goods |
| Factory in-charge | Fill factory sheet (05-1) | Issue to production 04-2; send finished goods 03-1; yield test 05-4; recipe card 05-3; new product 05-5 | Make, Goods |
| Purchasing | Ask to buy (06-1) | Compare quotes 06-2; orders 06-3; purchase bill; pay supplier (if granted) | Goods |
| Party and wholesale coordinator | Take an order (20-1) | Discount approval 20-2; party invoice 20-4; party ledger 20-5; collect a due | Sell |
| Carrier | Delivery ledger (20-6) | Transfers to carry (03-1 view); cash to hub (10-1 view) | Sell, Goods (read) |
| HR | Mark attendance (02-1) | Leave 02-5; payroll 02-2; advances 02-3; appointment 02-4; exit 02-6; duty 02-7; skills 02-8; register employee | People |
| Grants-only accountant | Look at the day book | Month-end; reconcile digital; pay supplier; bank, VAT, year-end; other income | Money, Reports |

## Appendix B. Job record (data, optional overlay in `web/jobs.js`)

```
{ id:'receive_goods', verb:'Receive goods', icon:'box', area:'Goods',
  roles:['storekeeper','purchasing'],
  ways:[ { route:'purchase/new', kind:'screen', counts:'rule:grn_receipt_source=purchase' },
         { form:'04-1',          kind:'form',   counts:'rule:grn_receipt_source=form' } ],
  open:'new',                         // 'new' or 'list'; per person per job override
  window:null,                        // owner-set time window, blank = none
  done:{ kind:'entry', form:'04-1' }, // an existing flow.js check kind, or null (no state shown)
  old:['GRN','goods received note'] } // search words; never shown as the name
```

A form-only job has one way and no Way strip. A record with no job is still on its area page, in A-Z and in Find.

## Appendix C. Usability tasks (run with real staff on their own phones, Bangla first; one hint = assisted; three wrong screens = lost)

| # | Task | Pri | Target median | Success |
|---|---|:-:|---:|---|
| T1 | Sell 2 items for cash, one at an allowed discount | P0 | <= 45 s from Today | correct total, no help |
| T2 | Collect 500 due from a named test customer | P0 | <= 40 s | right customer, 500 collected |
| T3 | Fill step 1 (Opening) of 14-1 from a paper sheet | P0 | <= 4 min | all given values entered |
| T4 | Close the day: Close-day routine, cash step of 14-1, 10-1 step | P0 | <= 8 min | every step ticked by the system |
| T5 | Record goods received from a challan, then say which way counts for stock | P0 | <= 3 min | saved and correct answer |
| T6 | Pay a test supplier 2,000 | P0 | <= 60 s | right supplier |
| T7 | Owner decides 2 waiting requests (approve one, reject one with reason) | P0 | <= 60 s | both decided, reason entered |
| T8 | Turn blind count on for one location | P1 | <= 60 s | correct switch, impact line seen |
| T9 | Give "See cost" to one person | P1 | <= 90 s | right person, confirm read |
| T10 | Submit 10-2 with 2 required fields empty, then fix | P0 | recover <= 45 s | used Go to field |
| T11 | Make a sale with no internet, find it in Not sent, send when online | P0 | <= 2 min | sent once, no duplicate |
| T12 | Switch to English and Large text | P1 | <= 30 s | both set unaided |
| T13 | Open the factory sheet 05-1 | P1 | <= 30 s to first field | form open |
| T14 | Find form 20-3 by number, then by name | P0 | <= 20 s each | opens 20-3 |
| T15 | Void a given sale | P0 | <= 60 s | reason entered; error if the wrong sale |
| T16 | Do T2 at Extra text size | P1 | <= 60 s | no horizontal scroll |
| T17 | Find yesterday's record of this job | P1 | <= 20 s | found |
| T18 | 30-line purchase bill from paper | P1 | <= 5 min | <= 1 wrong line, <= 2.7 pages |
| T19 | Find a screen by typing Bangla, then by browsing | P1 | success >= 80% | else browse stays first |
| T20 | Icon matching: 20 icons without words, pick the job from 5 | P1 | >= 85% correct | icons under 70% are redrawn |
| T21 | After the coach: "was it saved?" | P1 | >= 95% say no | |
| T22 | Stock count of 40 items (blind) | P1 | | 0 leaks of the book quantity |
| T23 | Attendance for 40 staff | P1 | | audit note on bulk fill |

Metrics: unaided success (target 90% on P0), time on task (median and p90 at most 2x target), taps from the event log (<= Audit C: average 1.42), errors per task (<= 0.5, zero critical), lost rate (<= 10%), recovery (T10 <= 45 s), SEQ >= 5.5, SUS (Bangla) >= 75 and >= baseline + 10, label comprehension >= 90%, chrome >= 70% content window on all 8 templates, layout defects 0 (bn, en, mix at x1.0 and x1.3 on 320, 360 and 412 px wide windows), nothing lost 0.

## Appendix D. Sources

Inputs merged: `ARCH_X_JOBS_AND_ROLES.md`, `ARCH_Y_MODULES_AND_POWER.md`, `ARCH_Z_UI_UX.md`, `DEBATE_X_R2.md`, `DEBATE_Y_R2.md`, `DEBATE_Z_R2.md`, `AUDIT_C_USABILITY.md`, `AUDIT_D_COMPACT_DESIGN.md` (working papers outside the repository); in the repository `CLAUDE.md`, `docs/UNIFIED_BUILD_PLAN.md` (Wave 3, items U-34 to U-45), `docs/IA_RULES.md`, `docs/DESIGN_SYSTEM.md`, `docs/LANGUAGE.md`; on branch `worktree-agent-af358bfac93193f23` `docs/UI_NO_LOSS_RULE.md`, `tests/ui_inventory/README.md`, `tests/ui_inventory/baseline.json`, `tools/check_ui_inventory.py`. Code facts checked in this worktree: `web/entry.js` (lines 237, 625, 628, 678 to 703, 880), `web/locations.js` (lines 323 to 328), `web/flow.js` (lines 30 to 62), `web/nav.js` (lines 84 to 85, 186 to 200, 596 to 612).
