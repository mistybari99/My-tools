# DESIGN: দুই-স্টেট লেআউট (Default ↔ সব ঐচ্ছিক অংশ দৃশ্যমান) — Two-state layout

Status: design only (no code, no SQL run). Date: 21 Oct 2026. Branch: `claude/supabase-readonly-audit-xo3qkp`.
Written for the owner to read the summary and for a coding agent to build from section 13 AFTER the current fix agent has finished.
Evidence tags: **[code]** read in this tree; **[doc]** read in a doc; **[design]** a decision made here; **[unverified]** needs a phone or live data.

## বাংলা সারাংশ

- প্রধান ফিচার (যেমন করণীয়, শিফট, ঘোষণা) নিজের জায়গায় সবসময় দেখা যাবে। বন্ধ থাকলে নামের পাশে ছোট "বন্ধ" চিহ্ন থাকবে, পাতা খুললে বলবে "মালিক চালু করলে কাজ করবে"।
- শুধু ফিচারের ভেতরের সুইচ ডিফল্টে বন্ধ থাকবে। পুরো ফিচার দেখানো/লুকানো পরে মালিক ঠিক করবেন; তার জন্য একটি সহজ, ফেরানো-যায় এমন সুইচ রাখা হচ্ছে।
- Switchboard-এ দুই অবস্থা: "ডিফল্ট" আর "সব ঐচ্ছিক অংশ দৃশ্যমান"। প্রথমবার বদলানোর আগে অ্যাপ নিজেই আপনার এখনকার অবস্থার কপি (ব্যাকআপ) সার্ভারে রাখবে।
- "ডিফল্টে ফেরান" চাপলে আগে দেখাবে কী কী বদলাবে; আপনি নিশ্চিত করলে একবারে সব ফিরবে (আধা-আধা হবে না), আর "ফেরানো বাতিল" থাকবে।
- টাকা, হিসাব, হাজিরা, লয়ালটি, ওয়েবসাইট, সোশ্যাল, AI-এর সুইচ এই লেআউটে কখনো বদলায় না।
- দুইজন architect তর্ক করে এই সিদ্ধান্তে এসেছেন (পরের অংশে)। আপনাকে কোনো প্রশ্নের উত্তর দিতে হবে না; প্রতিটি সিদ্ধান্ত কারণসহ লেখা আছে।
- সবকিছু ৩৬০px ফোনে, সহজ বাংলায়; কোনো ডেমো ডেটা নেই; ছাপা ফর্মের কোড বদলায় না।

---

## 1. Problem statement

The owner's intent (paraphrased): (a) main features are visible at their proper place and only their inner settings start OFF; showing or hiding a whole main feature is a LATER owner decision, so the design must make that choice easy and reversible; (b) the Switchboard has two layout states, first a backup "Default", then "All optional parts visible", plus a way back to the saved default; (c) the sweets business is first, other businesses stay separate.

What exists now [code]:

1. `web/switchboard.js` (commit `4569cfd`) has a "Layout" card: a select (Default / All optional sections visible / Custom disabled), a button that downloads a JSON file, and a revert button. `LAYOUT_KEYS = ['todo_on','shift_on','announce_on']`.
2. `web/ia.js` lines 216, 224, 225: the screens `announce`, `todo`, `shifts` use `ok: (c) => ruleOn('...')`. While the switch is OFF (the default, `phase130/131/132.sql`) the whole screen is missing from drawer, Home and search. This contradicts intent (a). `docs/DEMAND_VERIFY.md` R8/N3/F7 marks it PARTIAL.
3. Five other-trade screens (`impexp`, `variants`, `cheques`, `schemes`, `tinting`, `web/ia.js` 190-194) show in every owner's menu with no business gating. `docs/DEMAND_VERIFY.md` N10 marks it PARTIAL.

Gaps in the existing Layout card (why it is not yet the requested feature):

| # | Gap | Effect |
|---|---|---|
| G1 | "Default" means `rules.default_value` (the code default), not the owner's own backup | If the owner had already switched Shifts ON on purpose, "Default" silently turns it OFF. That is not a backup. |
| G2 | The snapshot is only a downloaded file; nothing reads it back | "Revert to snapshot" does not use the snapshot. A lost phone loses the backup. |
| G3 | `applyLayout` loops over `set_rule` calls, one by one | A network failure in the middle leaves a mixed state (the select shows a disabled "Custom"). |
| G4 | No confirmation, no preview, no undo | One tap on a select changes business behaviour. |
| G5 | Writes the explicit default value instead of `null` | Row is stored as "set", counted by the "only changed" filter. "Back to default" is not really back. |
| G6 | Hidden screens (R8) | Turning the layout to Default hides main features, the opposite of intent (a). |
| G7 | Layout list is a hard-coded three-key array with no guard | A future key could be a money switch by mistake. |

## 2. Vocabulary (one term, one meaning)

| Term | Precise meaning | Example |
|---|---|---|
| **Main feature** | A screen registered in `web/ia.js` with a route, a group and a job. It is placed in its group for every role that has permission. Placement is never decided by a rule switch. | `todo`, `shifts`, `announce`, `pos`, `stock` |
| **Inner setting** | A `rules` row (`kind` switch or choice) that changes how a main feature behaves. Default OFF or safe. | `pay_capture_on`, `cake_flow_on`, `todo_repeat_on` |
| **Feature switch** | The rule that turns a main feature's server side on. While OFF the server refuses with an error such as `announce_off`. | `todo_on`, `shift_on`, `announce_on` |
| **Optional part** | A feature switch that is **show-only**: turning it ON only lets people use an internal screen. It must meet all of the five tests in section 6. | the three above |
| **Layout state** | A named setting of ALL optional parts: Default, All visible, or Custom. | |
| **Snapshot** | A saved copy of the optional parts' values, kept on the server, with who, when and why. | section 5.3 |
| **Hidden by owner** | The existing per-person/per-role Hide choice (`web/optviews.js`, route `optviews`). It never changes a permission. | |

Three separate questions, three separate controls (this separation is the core of the design):

1. **Placed?** Is the main feature shown at its place? Default YES for every permitted role. Controlled later by the owner (section 5.6, and DESIGN_ROADMAP item 2).
2. **Enabled?** Is its feature switch ON? Default OFF for optional parts. Controlled by the Layout card or the row in the Switchboard.
3. **Allowed?** Does the person have permission? Decided only by the server (grants, RLS). Never touched by layout.

## 3. User stories

Format: As a role, I want X so that Y. Each has one acceptance line (tested in section 10).

**Owner**
- O1. I open Menu and see every main feature in its group, including To-do, Shifts and Announcements, even if I have not switched them on. *Test T1.*
- O2. I tap a feature that is OFF and I see a plain card "এই অংশ এখন বন্ধ" with one button "চালু করুন"; I do not see an error. *T3.*
- O3. On the Switchboard I choose "সব ঐচ্ছিক অংশ দৃশ্যমান" to look at everything at once, and I can come back with one tap. *T6, T9.*
- O4. Before anything changes, the app keeps a copy of how things were. I never have to remember to download a file. *T5.*
- O5. When I revert, I first see the list of what will change and I can cancel. After reverting I can undo it. *T10, T11.*
- O6. Later I decide to hide whole main features for a business or role; I flip one setting and can flip it back. *T14.*

**Shop manager (showroom)**
- M1. I see To-do and Shifts in my menu. If the owner has not switched them on, I see a "বন্ধ" chip and a one-line reason, not a missing menu item. *T1, T3.*
- M2. When the owner turns them on, they work for me with no new login and no reload instructions (the menu refreshes). *T8.*

**Cashier**
- C1. My menu stays short: only what my role may use. Layout never gives me a screen I am not permitted to use. *T12.*
- C2. The Sell button and Home do not move when the owner changes the layout. *T13.*

**Factory maker**
- F1. I see Announcements and To-do where they belong (People group). Nothing about recipes, production or costing changes with the layout. *T12.*

**Accountant**
- A1. Layout never changes `accounting_on`, VAT, year close, wallet split or any money or books switch. If a switch like that appears in a snapshot file I may open, the app ignores it on revert. *T7, T15.*

## 4. The debate

Participants: **Architect A** (minimal and safe), **Architect B** (configurable, progressive disclosure), **UX reviewer R** (phone, Bangla, owner and staff who are not technical). The owner is not in the room; he asked not to be asked, so the panel decides. Facts used are from sections 1-2.

### Round 1: do we need a "layout" at all?

**A:** After the R8 fix (always place the three screens, show a "off" chip) there is nothing left to hide. The Layout card then only flips three switches. Three switches already have rows in the Switchboard. I propose: fix R8, delete the Layout card, ship nothing else. Less code, no new table, no risk.

**B:** The owner asked for it by name: a backup default, an all-visible state and a revert. That is a stated requirement, not a nice-to-have. And the set will grow: every new internal screen of the sweets business (task lists, rosters, notices) will have a feature switch. One owner decision "show me everything" is worth more than N rows.

**A:** Then the set is three keys today. Building a table and RPCs for three keys is gold-plating.

**B:** The cost is not the three keys, it is the failure mode. Today the revert loops over `set_rule`, and the first network drop leaves a mixed state with a disabled "Custom" in the select (G3). With the three keys it is an annoyance; with ten keys it is a support call. An atomic server function is the smallest fix for that.

**R:** Both of you are measuring code. The owner measures confidence: "if I tap this, can I get back?" Today he cannot be sure (G1, G2). That is the product problem. I side with B on keeping the feature and with A on keeping it small.

**Decision D1:** Keep the two-state layout. Keep it small: one card, two choices, one revert. Fix R8 independently and first, because without it "Default" hides main features.

### Round 2: what is in the set? (what is an "optional part")

**B:** Make the set data-driven: any switch with `module = 'people'` or tagged show-only appears. Owners add parts by tagging.

**A:** No. The word "optional" is how a money switch gets in. `website_on` publishes to the public, `social_on` posts, `ai_on` sends text to a model, `notify_sms_on` costs money, `loyalty_points_on` changes balances. One wrong tag and "All visible" posts to Facebook. The set must be a short list in code, guarded by a test.

**B:** A hard-coded list means a coder edit for each new part.

**A:** Yes, and that is the point: an edit is reviewed; a tag is not.

**R:** Would a non-technical owner understand "optional"? He will read "সব ঐচ্ছিক অংশ দৃশ্যমান" as "everything the app can do". Then he sees Website not turned on and thinks the button failed.

**B:** Then the card must say what it covers, in one line, and list the parts. Not a vague promise.

**Decision D2:** The set is a short list in code (one constant), guarded by a test with five tests per key (section 6). The card names the parts it covers and says in plain words what it does not touch. B's data-driven tagging is rejected for now; revisit when more than 8 keys exist.

### Round 3: where do the state and the backup live?

**A:** Keep the device file (G2 says it is useless, but it is zero new infrastructure). Offer "download" and "import file" to revert.

**B:** A file on one phone is not a backup. Phones are lost; the owner uses more than one device; the fix agent and later builders cannot read it. Put it on the server, per business, with history.

**A:** Server storage means a new table and SQL the owner must paste. Owner rule: new SQL is a new phase file, safe to paste twice, he pastes it himself. That is friction and risk.

**B:** True, so keep the SQL tiny: one table, two functions, owner-only, no triggers on existing tables, nothing changes until the owner presses a button (new behaviour OFF by default). Also the existing file download stays as a second copy.

**R:** A file is also confusing in Bangla ("ফাইল কোথায় গেল?"). On a phone, downloads vanish into a folder. Server copy is what I would trust.

**A (rebuttal):** Atomic revert needs a function that rewrites rules in one transaction. That function must not become a back door into money switches.

**B:** Agreed: the function ignores any key not in the layout constant (the constant lives in SQL too and a SQL test checks the two lists match). It calls the same validation as `set_rule`.

**Decision D3:** Server-side snapshot table with history, plus one atomic function. The device file stays as an extra export ("পুরো কপি ফাইল"). Phase file is only outlined here (section 7); the owner pastes it after review.

### Round 4: what does "Default" mean?

**A:** "Default" = the code default. Simple, predictable, same for everyone.

**B:** That is G1. If the owner turned Shifts ON last month because the shop uses them, tapping Default turns them OFF. He called Default "backup". A backup is the state he had.

**A:** Then two defaults will confuse people.

**R:** Call them by what they do. The card has a segmented control with two choices: "ডিফল্ট" and "সব দেখান". The word Default means "my saved default", the one the owner had before first using the card. The factory default is available only inside "আরও" as "কোম্পানির ডিফল্ট (সব বন্ধ)". Most owners never open it.

**A:** What if there is no saved default yet?

**B:** The first time the owner changes the layout, the app saves the current state automatically, before writing. So a saved default always exists once the card has been used, and it is the owner's real prior state. Before first use, "Default" = nothing to change.

**A:** Auto-save can be surprising.

**R:** It is visible: a toast "আপনার আগের অবস্থা সেভ করা হয়েছে" and a line on the card with the date. Not hidden.

**Decision D4:** "Default" = the owner's saved default snapshot (auto-created before the first change; replaceable by an explicit "এখনকার অবস্থাকে ডিফল্ট করুন" inside "আরও"). Factory default is a third, hidden-in-"আরও" action. Revert target = saved default.

### Round 5: per-user or per-business?

**B:** Per-user layouts would let a manager see all while a cashier sees default.

**A:** No. The layout flips server-side feature switches. If the cashier's screen shows a feature that the server refuses, the app breaks; if one person has "All" and another "Default", staff talk about screens that others cannot see. Also `optviews` already gives per-person Hide.

**R:** Staff memory is the hazard. A shared state for the shop is easier to teach.

**Decision D5:** Layout state is per business (rules are per business; snapshot keyed by `org_unit_id`, null while `org_scope_on` is OFF). Per-person differences come only from role/permission (server) and the existing Hide (`optviews`). Per-device conveniences (drawer footer open, location box open, "show chips") stay on the device in `localStorage` inside try/catch.

### Round 6: safety UX

**A:** Add a PIN for revert.

**R:** The Switchboard is already owner-only. A PIN on a layout change is friction without a threat. A preview list and an undo give more safety than a PIN.

**B:** Agree with R, and one more: revert must show the diff.

**A:** Then undo must be real, not a promise.

**Decision D6:** Owner-only (server-checked), confirmation sheet with the diff for every change that turns something OFF (revert and "Default"), no sheet for turning ON (reversible, low risk, still toast with "বাতিল"). Every apply writes a "before" snapshot, so "ফেরানো বাতিল" works for 24 hours (the last one is always kept). No PIN.

### Round 7: sweets first, other businesses separate

**B:** Put other-trade screens (variants, cheques, schemes, tinting, impexp) behind the same layout.

**A:** They are a different problem: they should not be in a sweets menu at all. Do not mix "optional because OFF" with "belongs to another business".

**R:** For the owner they are noise today.

**Decision D7:** Not part of this layout. The layout covers sweets-business optional parts only. Other-business screens are handled by business gating (DESIGN_ROADMAP item 2): visible only where the active business template needs them. Each business keeps its own snapshot.

### Final decision table

| # | Decision | Reason | Who gave way |
|---|---|---|---|
| D1 | Keep two-state layout, small; fix R8 first and separately | Owner asked for it; R8 makes Default hide features | A accepted keeping it; B accepted "small" |
| D2 | Set = short constant list in code + 5-test guard; no tagging | One wrong tag could post or spend money | B gave way |
| D3 | Server snapshot table + atomic function; file is only an extra export | Phone file is not a backup; loop is not atomic | A gave way, B limited SQL to 1 table + 2 functions |
| D4 | Default = owner's saved default, auto-saved before first change; factory default in "আরও" | A backup is the state he had | A gave way |
| D5 | Per business; per person only by role and Hide | Server enforces switches; one shop state is teachable | B gave way |
| D6 | Owner-only; diff sheet when turning OFF; real undo; no PIN | Preview + undo beat PIN | A gave way |
| D7 | Other-business screens are outside this layout | Different problem (belonging, not optional) | B gave way |
| D8 | "Placed", "Enabled", "Allowed" are three separate things | Fixes R8 and keeps the show/hide decision cheap later | all |
| D9 | Revert writes `null` (back to default) where the snapshot had no explicit value | Keeps "changed" markers honest (G5) | A |
| D10 | Custom state is shown as a read-only third line with a list, not a disabled select option | A disabled option looks like a bug | R |

## 5. Specified behaviour

### 5.1 Placement of main features (the R8 fix, prerequisite)

- `announce`, `todo`, `shifts` records use the role/permission check only (`ok`), never `ruleOn`. They appear in drawer, Home modules, search and the category page like every other screen.
- When the feature switch is OFF the record carries `off: true` (computed at draw time from `B.rule`). Drawer row and search row show the chip "বন্ধ" (word + marker, never colour alone).
- Opening the route while OFF renders the **feature-off card** (shared component `BOS.ui.state('off', ...)`, new kind), not the feature screen:
  - text: "এই অংশ এখন বন্ধ। চালু হলে এখানে কাজ করবে।"
  - owner: primary button "চালু করুন" (calls `set_rule`), secondary "Switchboard-এ দেখুন".
  - others: "মালিক চালু করলে এখানে কাজ করবে।" and a Back button.
- Routes, aliases and favourites never change (IA rule 3).

### 5.2 States

| State | Definition | Shown as |
|---|---|---|
| **Default** | Every layout key equals the saved default snapshot value | segment "ডিফল্ট" selected |
| **All visible** | Every layout key is ON | segment "সব দেখান" selected |
| **Custom** | Anything else | neither segment selected; line "কাস্টম: ২টি চালু" with the list |
| **Not started** | No snapshot yet and all keys at factory default | "ডিফল্ট" selected, line "এখনো কপি করা হয়নি" |

If saved default equals All visible (all keys already ON when first opened), the control shows "সব দেখান" selected and "ডিফল্ট" selected is impossible; both buttons still work and the first change takes the snapshot anyway.

Transitions:

| From | Action | Effect | Sheet |
|---|---|---|---|
| any | tap "সব দেখান" | take snapshot (reason `auto_before_all`) if none; turn every key ON in one function call | no sheet; toast with "বাতিল" |
| any | tap "ডিফল্ট" | restore the saved default (same as Revert) | diff sheet if anything turns OFF |
| any | tap "ডিফল্টে ফেরান" | same as above | diff sheet |
| any | tap "ফেরানো বাতিল" | restore the snapshot with reason `before_apply` (the newest one) | diff sheet |
| any | "এখনকার অবস্থাকে ডিফল্ট করুন" ("আরও") | new snapshot, reason `manual`, becomes the saved default | sheet: "আগের ডিফল্ট বদলে যাবে" |
| any | "কোম্পানির ডিফল্ট" ("আরও") | all keys to `null` | diff sheet |
| any | single switch changed in the list below | state becomes Custom automatically | none |

### 5.3 Snapshot format (v1, JSON)

```json
{
  "kind": "bos-layout-snapshot",
  "version": 1,
  "org_unit_id": null,
  "taken_at": "2026-10-21T09:30:00Z",
  "taken_by": "<user id>",
  "reason": "auto_before_all | manual | before_apply | factory",
  "keys": [
    { "key": "todo_on",     "value": null,  "default_value": false, "on": false },
    { "key": "shift_on",    "value": true,  "default_value": false, "on": true  },
    { "key": "announce_on", "value": null,  "default_value": false, "on": false }
  ]
}
```

- `value` is the stored rule value (`null` = never set, follows default). `on` is the effective value at that time (for display and for the diff).
- Only layout keys are stored. The old file `bos-layout-defaults` (all switches, `web/switchboard.js` `downloadSnapshot`) stays as "পুরো কপি ফাইল" and is never used by revert.
- Unknown keys, or keys outside the layout constant, are ignored on apply and reported as "বাদ দেওয়া হয়েছে" in the sheet.
- The server stamps `taken_at`/`taken_by`; the client never supplies them.

### 5.4 Revert rules

1. Revert touches only keys in the layout constant. It never reads the value of a money, books, attendance, loyalty, external-effect or other switch.
2. Restoring writes `value` exactly: where the snapshot has `null` it writes `null` (decision D9), where `true/false` it writes that value.
3. One transaction: all keys change or none. On error nothing changes and the card shows an error state with "আবার চেষ্টা করুন".
4. Before applying, the server stores a `before_apply` snapshot (so undo exists). Keep the newest 20 snapshots per business; the saved default and the newest `before_apply` are never pruned.
5. If a key in the snapshot no longer exists, it is skipped and listed.
6. After apply: reload rules (`B.reloadRules`), redraw drawer and Home (the three screens already exist; only their chips change), toast "ফিরে এসেছে".
7. Revert never signs anyone out, never changes language, theme, location or per-device settings.

### 5.5 Scope

| Thing | Scope | Where stored |
|---|---|---|
| Feature switches and snapshot | per business (`org_unit_id`; null while `org_scope_on` OFF) | rules + `layout_snapshots` |
| Who may change it | owner only (server) | RPC check |
| Hide of a main feature | per person / per role | existing `optviews` |
| Drawer footer open, location box open, chips on/off | per device | `localStorage` (try/catch) |
| Sweets vs other businesses | each business has its own switches and snapshot | per `org_unit_id` |

### 5.6 The later show/hide decision (how this design keeps it cheap)

New rule `ia_show_off_features` (switch, default ON, owner). ON = main features whose feature switch is OFF stay placed with the "বন্ধ" chip (this design). OFF = old behaviour (they disappear from menus). One flip, reversible, no data change, per business. Full model in `docs/DESIGN_ROADMAP.md` item 2.

## 6. What "optional part" means: the five tests and the derived list

A rule key may be in the layout constant only if ALL five are true:

| Test | Question | Check |
|---|---|---|
| E1 | `kind = 'switch'` and `default_value = false` | read `rules` |
| E2 | Turning it ON changes who can OPEN an internal screen, nothing else | no ledger, stock, payroll, price, approval, or notification effect |
| E3 | No effect outside the app | does not publish, post, send SMS or email, call AI, charge or collect money |
| E4 | No personal data of customers or staff is newly collected | no consent or PII path starts |
| E5 | Turning it OFF again loses no data | data stays, hidden by the server `*_off` guard |

Derivation [code]:

- `web/ia.js` has 13 groups. Screens gated by a rule switch: only `announce`, `todo`, `shifts` (all in group `people`). Every other record uses `ok` by role/grant/location only.
- `supabase/phase*.sql` default-OFF `_on` switches by module: impexp, dealer (3), settings (5), reports (6), pos (23), items (5), books (10), social (2), stock (2), integrations (2), customers (4), ai (2), purchase (2), assistant (2), automation (1), people (8), entries (4), crm (5), notify (1).
- Applying E1-E5 to the module `people` (8 keys): `announce_on`, `todo_on`, `shift_on` pass. `todo_repeat_on` creates tasks automatically (E2 fails). `app_punch_on`, `att_geo_check_on` change attendance (E2). `benefit_grants_on`, `pay_requests_on`, `payroll_accrual_on` touch pay (E2).
- Every other module fails E2, E3 or E4 (pos switches change orders, payments or intake; books change the ledger; social/ai/integrations leave the app; crm and customers collect or use personal data).

**Initial layout constant (final):** `todo_on`, `shift_on`, `announce_on`. This matches the existing code. The decision is deliberate: the card is small now and will grow only through a reviewed edit.

**Protected list (never in the layout, tested):** every key in modules `books`, `integrations`, `social`, `ai`, `assistant`, `crm`, `customers`, plus `accounting_on`, `payroll_accrual_on`, `app_punch_on`, `att_geo_check_on`, `loyalty_points_on`, `website_on`, `pay_gateway_on`, `notify_sms_on`, `vat_on`, `org_scope_on`.

## 7. Data model (outline only; no SQL is run from here)

No live write. The owner pastes the phase file himself after review. New file numbers: next free phase is **540** (last is 539; 500 stays unused, `docs/NUMBERING.md` section 8). Files: `supabase/phase540.sql`, `supabase/phase540_test.sql`, entries in `docs/PASTE_ORDER.md` and `tests/sql/ORDER.txt`. SQL must be safe to paste twice; new behaviour OFF.

| Object | Outline |
|---|---|
| table `layout_snapshots` | `id bigserial pk`, `org_unit_id bigint null`, `taken_at timestamptz default now()`, `taken_by uuid`, `reason text check in (auto_before_all, manual, before_apply, factory)`, `keys jsonb not null`, `is_default boolean default false`. Unique partial index: one `is_default` per `coalesce(org_unit_id,0)`. RLS on; select and write only through functions; owner only. |
| function `layout_keys()` | returns the constant list (`todo_on`, `shift_on`, `announce_on`); one place in SQL; test compares with the JS constant. |
| function `layout_state(p_org bigint default null)` | returns current values, saved default, newest undo, state label. Read-only. |
| function `layout_apply(p_target text, p_org bigint default null)` | `p_target` in `all_on`, `default`, `factory`, `undo`. Owner check; writes `before_apply` snapshot; for each layout key applies via the same validation as `set_rule` inside one transaction; ignores keys outside `layout_keys()`; returns the diff. |
| function `layout_save_default(p_org bigint default null)` | stores a `manual` snapshot and flags it default. |
| audit | every call also writes the existing audit trail used by `set_rule`. |
| rule `ia_show_off_features` | switch, default true, module `ui`, with an info entry in `web/data/info.json` (`tools/check_info_coverage.py` requires one). |
| test file | owner can; non-owner refused; second paste no error; `layout_apply` with a forged key list ignores it; money switch unchanged after any call; revert atomic when one key is missing; undo works; null restored as null. |

Open point for the coder (not for the owner): if `set_rule` already accepts a jsonb `text` kind, the snapshot could be one rule row, but history and atomicity are easier with the table. The table is the decision.

## 8. Wireframes at 360 px

Width note: 360 px at 16 px base is about 40 characters. Frames below are 38 wide. Touch targets 44 px minimum, primary 48 px (`docs/DESIGN_SYSTEM.md`).

### 8.1 Home (owner; main features all placed)

```
+--------------------------------------+
| [=]  ইসলামিয়া মিষ্টি ঘর       [মূল]  |
+--------------------------------------+
| এখন আপনার জন্য                       |
|  3 অনুমোদন · 2 বাকি · ক্যাশ মিলেছে   |
+--------------------------------------+
| [ বিক্রি ]  [ স্টক ]                  |
| [ কেক অর্ডার ]  [ খরচ ]              |
+--------------------------------------+
| সাম্প্রতিক                            |
|  > দিনের খাতা                        |
|  > করণীয় তালিকা          [বন্ধ]     |
+--------------------------------------+
| [হোম] [বিক্রি] [স্টক] [মেনু] [আমি]   |
+--------------------------------------+
```

Home does not change with layout. Optional parts appear in Recent and the Menu, never as new Home tiles by default.

### 8.2 Drawer with the location up/down box

```
+--------------------------------------+
| ইসলামিয়া মিষ্টি ঘর              [X]  |
| ব্যবসা: মিষ্টি            [v]        |
| [ খুঁজুন ...                       ] |
+--------------------------------------+
| লোকেশন: মেইন শোরুম          [^]      |  <- collapsed: one line
|  (tap to open the list)              |
+--------------------------------------+
| v ড্যাশবোর্ড                          |
| v সেল ও POS                           |
| > কর্মী, রোল ও অনুমতি                 |
|     হাজিরা                           |
|     ঘোষণা ও নির্দেশ         [বন্ধ]   |
|     করণীয় তালিকা           [বন্ধ]   |
|     শিফট রোস্টার            [বন্ধ]   |
| v হিসাব ও অর্থ                        |
+--------------------------------------+
| [ভাষা] [থিম] [অনলাইন]   [লগ আউট] [^] |
+--------------------------------------+
```

Location box expanded (tap the line):

```
| লোকেশন: মেইন শোরুম          [v]      |
|  (o) সব জায়গা                       |
|  (o) মেইন শোরুম          <- chosen    |
|  (o) কারখানা                         |
```

Rules: the box is collapsed by default when the person has one choice or has chosen once; remembered per device (`bos_navloc`, try/catch). The footer chevron already exists (`bos_navfoot`). Both chevrons use `aria-expanded` and `aria-controls`. "[বন্ধ]" is a chip with a word, not colour only.

### 8.3 Switchboard two-state control

```
+--------------------------------------+
| <  সুইচবোর্ড                          |
+--------------------------------------+
| লেআউট                                |
| ঐচ্ছিক অংশ: করণীয়, শিফট, ঘোষণা       |
| টাকা, হিসাব, হাজিরা বদলায় না।        |
|                                      |
| +-----------------+----------------+ |
| |  ডিফল্ট  (o)   |  সব দেখান      | |
| +-----------------+----------------+ |
| এখন: ডিফল্ট · কপি: ২১ অক্টো ০৯:৩০    |
|                                      |
| [ ডিফল্টে ফেরান ]                    |
| [ ফেরানো বাতিল ]   (যদি থাকে)        |
|                                      |
| v আরও                                |
|   - এখনকার অবস্থাকে ডিফল্ট করুন      |
|   - কোম্পানির ডিফল্ট (সব বন্ধ)       |
|   - পুরো কপি ফাইল নামান              |
+--------------------------------------+
| [ খুঁজুন ...                       ] |
|  ... বাকি সুইচের তালিকা ...          |
```

Custom state:

```
| +-----------------+----------------+ |
| |  ডিফল্ট         |  সব দেখান      | |   (none selected)
| +-----------------+----------------+ |
| এখন: কাস্টম — চালু: শিফট রোস্টার      |
```

Segmented control = two real buttons in a `role="radiogroup"` (not a select): the select hid the state and could not carry a disabled "Custom" option cleanly (D10).

### 8.4 Revert confirmation (bottom sheet)

```
+--------------------------------------+
| ডিফল্টে ফেরান?                       |
|                                      |
| এগুলো বন্ধ হবে:                      |
|   - করণীয় তালিকা                    |
|   - শিফট রোস্টার                     |
| এগুলো যেমন আছে তেমন থাকবে:            |
|   - ঘোষণা ও নির্দেশ                  |
|                                      |
| ডেটা মুছবে না। পরে আবার চালু করা যাবে। |
|                                      |
| [ বাতিল ]          [ ফিরিয়ে দিন ]   |
+--------------------------------------+
```

Cancel is first and the default focus; the destructive-looking action is second and labelled with the verb. After confirm: toast "ফিরে এসেছে" + "ফেরানো বাতিল".

### 8.5 Feature-off card (opened from the drawer)

```
+--------------------------------------+
| <  করণীয় তালিকা                     |
+--------------------------------------+
|   (i)  এই অংশ এখন বন্ধ                |
|   চালু হলে এখানে কাজ করবে।            |
|                                      |
|   [ চালু করুন ]                      |
|   [ সুইচবোর্ডে দেখুন ]               |
+--------------------------------------+
```

(for non-owner: only the explanation and "ফিরে যান".)

## 9. Accessibility and Bangla wording

Accessibility:

- Segmented control: `role="radiogroup"` with two `role="radio"` buttons, `aria-checked`, arrow keys move, Enter/Space selects; label = the card title (`aria-labelledby`).
- Sheet: `role="dialog"` `aria-modal="true"`, focus moves to "বাতিল", focus returns to the control that opened it, Esc closes.
- Chips "বন্ধ" carry text; drawer row `aria-label` = "করণীয় তালিকা, বন্ধ".
- Status after an apply announced in a `role="status"` live region (the existing toast should be one; the coder verifies).
- Touch targets 44 px (primary 48 px); no hover-only information; text contrast 4.5:1 in all themes including glass light and dark; reduced motion respected (no animation beyond the existing sheet).
- Location and footer chevrons: `aria-expanded`, `aria-controls`, visible focus ring (`--focus`).
- Everything fits 360 px with no sideways scroll; long Bangla labels wrap (no `nowrap`), segment buttons wrap to two lines if needed.

Wording (owner word list: Save = সেভ, Date = ডেট, Approve = অ্যাপ্রুভ; common English words are written in Bangla letters in the বাংলা mode, in Latin in the Bng-Eng mode; plain, short). Add to `web/i18n.js` or `X` in `web/switchboard.js` as `L(bn, en, mix)`.

| Key | বাংলা | Bng-Eng (mix) | English |
|---|---|---|---|
| lay_title | লেআউট | Layout | Layout |
| lay_covers | ঐচ্ছিক অংশ: করণীয়, শিফট, ঘোষণা | Optional part: To-do, Shift, Announcement | Optional parts: To-do, Shifts, Announcements |
| lay_not | টাকা, হিসাব, হাজিরা বদলায় না। | টাকা, accounts, attendance বদলায় না। | Money, books and attendance are not changed. |
| lay_default | ডিফল্ট | Default | Default |
| lay_all | সব দেখান | সব দেখান | Show all |
| lay_state_default | এখন: ডিফল্ট | এখন: Default | Now: Default |
| lay_state_custom | এখন: কাস্টম | এখন: Custom | Now: Custom |
| lay_copy_at | কপি: {date} | Copy: {date} | Copy: {date} |
| lay_copy_none | এখনো কপি করা হয়নি | এখনো copy করা হয়নি | Not copied yet |
| lay_revert | ডিফল্টে ফেরান | Default-এ ফেরান | Revert to default |
| lay_undo | ফেরানো বাতিল | Undo | Undo |
| lay_more | আরও | আরও | More |
| lay_save_default | এখনকার অবস্থাকে ডিফল্ট করুন | এখনকার state-কে Default করুন | Make the current state my default |
| lay_factory | কোম্পানির ডিফল্ট (সব বন্ধ) | Company default (সব off) | Company default (all off) |
| lay_file | পুরো কপি ফাইল নামান | পুরো copy file নামান | Download the full copy file |
| lay_sheet_title | ডিফল্টে ফেরান? | Default-এ ফেরান? | Revert to default? |
| lay_sheet_off | এগুলো বন্ধ হবে | এগুলো off হবে | These will turn off |
| lay_sheet_keep | এগুলো যেমন আছে তেমন থাকবে | এগুলো যেমন আছে থাকবে | These stay as they are |
| lay_sheet_safe | ডেটা মুছবে না। পরে আবার চালু করা যাবে। | Data মুছবে না। পরে আবার চালু করা যাবে। | No data is deleted. You can turn them on again. |
| lay_cancel / lay_confirm | বাতিল / ফিরিয়ে দিন | Cancel / ফিরিয়ে দিন | Cancel / Revert |
| lay_autosaved | আপনার আগের অবস্থা সেভ করা হয়েছে | আগের state Save করা হয়েছে | Your earlier state was saved |
| lay_done | ফিরে এসেছে | ফিরে এসেছে | Reverted |
| off_chip | বন্ধ | বন্ধ | Off |
| off_title | এই অংশ এখন বন্ধ | এই অংশ এখন বন্ধ | This part is off |
| off_body_owner | চালু হলে এখানে কাজ করবে। | চালু হলে এখানে কাজ করবে। | It will work here once it is on. |
| off_body_staff | মালিক চালু করলে এখানে কাজ করবে। | Owner চালু করলে এখানে কাজ করবে। | It will work here once the owner turns it on. |
| off_turn_on | চালু করুন | চালু করুন | Turn on |
| err_apply | কিছুই বদলায়নি। আবার চেষ্টা করুন। | কিছুই বদলায়নি। আবার try করুন। | Nothing was changed. Try again. |

"স্ন্যাপশট" is not used; the word is "কপি". Button verbs stay the same through the flow (ফেরান in the button, "ফিরে এসেছে" in the toast).

## 10. Acceptance tests (what a web test asserts)

New file `tests/web/layout_test.js` (same style as `tests/web/switchboard`/`ia_test.js`; stubbed `sb` with a fake rules table and fake RPCs). Viewport 360x740. Run through `python3 tests/web/run_all.py layout_test ia_test nav_test nav2_test navfold_test settings2_test control_test` and screenshots are not committed.

| ID | Assertion |
|---|---|
| T1 | With `todo_on`, `shift_on`, `announce_on` all OFF, `BOS.ia` drawer entries for an owner include `todo`, `shifts`, `announce`, each with `off === true`; they also appear in search results and in `#/group/people`. |
| T2 | A cashier without permission for a screen does not see it, whatever its switch value (permission still decides). |
| T3 | Opening `#/todo` while OFF renders `[data-state="off"]` with the text from `off_title`; owner sees the button `[data-act="off_turn_on"]`; a non-owner does not; neither sees an error notice. |
| T4 | Pressing "চালু করুন" calls `set_rule('todo_on', true)` once, then the route renders the real screen. |
| T5 | First tap on "সব দেখান" with no snapshot calls `layout_apply('all_on')`; the fake server now has one snapshot with `reason = auto_before_all` holding the previous values. |
| T6 | After T5 all three keys are ON and the segmented control shows "সব দেখান" checked (`aria-checked="true"`). |
| T7 | Layout code never calls `set_rule` or `layout_apply` with a key outside the constant; a forged snapshot containing `accounting_on` leaves `accounting_on` untouched and the sheet lists it as skipped. |
| T8 | After apply, drawer chips are redrawn with no page reload; `todo` loses the chip. |
| T9 | Tap "ডিফল্ট" returns all keys to the snapshot values; where snapshot value was `null` the fake rules row ends with `value === null` (D9). |
| T10 | Revert opens the sheet; it lists the keys that turn OFF and the keys that stay; "বাতিল" is focused; Esc closes and nothing was written. |
| T11 | "ফেরানো বাতিল" appears after an apply and restores the pre-apply values. |
| T12 | A role-limited user never sees a Layout card (owner only) and recipes, production, costing, stock, POS routes are unchanged between Default and All. |
| T13 | Home tiles and bottom bar slots are identical in both states. |
| T14 | Setting `ia_show_off_features = false` hides the three off screens again (old behaviour); setting it back shows the chips. |
| T15 | Network failure injected in the fake RPC: nothing changed, error state with "আবার চেষ্টা করুন", state still the same. |
| T16 | Custom: toggling one key in the list changes the control to no selection and the line shows "কাস্টম" and the list. |
| T17 | Location box: collapsed one-line by default with one choice; `aria-expanded` toggles; choice persists across reload (`bos_navloc`); with `localStorage` throwing the box still works. |
| T18 | At 360 px `document.documentElement.scrollWidth <= 360` on Home, drawer open, Switchboard, sheet open, feature-off card. |
| T19 | Three language modes render all keys of section 9 with no key name leaking (no text equal to a key id). |
| T20 | Keyboard: arrows move in the radiogroup; Tab order reaches revert and "আরও". |

Guard tests: `tools/check_info_coverage.py` (new rule has info entry), `python3 tools/check_ui_inventory.py` (nothing lost, nothing renamed silently), `python3 tools/check_no_demo_leak.py` (OK), `node tests/web/ia_test.js`.
SQL test (`phase540_test.sql`, local throwaway Postgres only): see section 7 test row.

## 11. Risks and rollback

| Risk | Likelihood | Effect | Mitigation | Rollback |
|---|---|---|---|---|
| A show-only key gets a hidden side effect later | low | All visible does more than expected | five-test guard (section 6) + protected list test | remove the key from the constant (one line) |
| Owner pastes phase 540 twice | medium | none if safe-twice | `if not exists`, `create or replace`, SQL test pastes twice | none needed |
| `layout_apply` partial write | low | mixed state | single transaction; failure test T15 | undo snapshot |
| Chips clutter the drawer | low | noise | chips only for OFF parts, 3 rows today; `ia_show_off_features` flip | set `ia_show_off_features` = false |
| Staff tap an OFF feature and think the app is broken | medium | support calls | the feature-off card explains in one sentence | none needed |
| Fix agent changes the same files | high now | merge conflict | start only after it finishes; steps touch few files, listed below | rebase |
| Bangla wording not natural | medium | confusion | wording table section 9; owner reads once (HANDOFF owner task 4) | edit i18n keys only |
| Real phone layout differs [unverified] | medium | overflow | 360 px tests + owner phone check in handoff list | CSS only |

Rollback levels: (1) `ia_show_off_features = false` restores today's menu. (2) Remove the Layout card (one `layoutHTML()` call). (3) Do not paste phase 540; the card checks that the `layout_state` RPC exists and, if it is missing, falls back to today's device-file behaviour (the old card, unchanged). No data is ever deleted by any step.

## 12. Effort estimate

| Step | Work | Size |
|---|---|---|
| S1 R8 fix and feature-off card | ia.js 3 records, nav.js chip, shared state kind, i18n | 0.5 day |
| S2 SQL phase 540 and test | 1 table, 4 functions, 1 rule, info entry | 1 day |
| S3 Layout card rebuild | radiogroup, sheet, undo, "আরও", state calc | 1 day |
| S4 Drawer location up/down | collapsible box | 0.25 day |
| S5 Tests T1-T20 | new test file | 1 day |
| S6 Docs, BUILD-LOG, checks, handoff | | 0.25 day |
| Total | | about 4 days of agent work; the owner effort is one paste and one phone check |

## 13. Implementation plan (for a coding agent, after the current fix agent finishes)

Preconditions: `git status` clean; the fix agent's commits merged; `python3 tools/check_no_demo_leak.py` OK before each commit; new SQL only in a new phase file; do not edit old phase files; never write to live Supabase; every journal entry unaffected.

| Step | What | Files it will touch |
|---|---|---|
| 1 | R8 fix: remove `ruleOn` from the `ok` of `announce`, `todo`, `shifts`; add `off` computed flag helper (`B.ia.isOff(rec)`) | `web/ia.js` |
| 2 | Chip "বন্ধ" in drawer rows, search rows, category page rows | `web/nav.js`, `web/styles.css` (or `web/controls.css`) |
| 3 | `BOS.ui.state('off', ...)` and the feature-off card for the three routes (wrap the route function; owner button calls `set_rule`) | `web/ia.js`, `web/announce.js`, `web/todo.js`, `web/shifts.js` (wrapper only), `web/i18n.js` |
| 4 | Tests for steps 1-3 (T1-T4, T14 partial) | `tests/web/layout_test.js` (new), `tests/web/ia_test.js` |
| 5 | Phase 540 SQL and test; register in the paste order | `supabase/phase540.sql`, `supabase/phase540_test.sql`, `docs/PASTE_ORDER.md`, `tests/sql/ORDER.txt`, `web/data/info.json` (info entry for `ia_show_off_features`) |
| 6 | Rebuild the Layout card: constant + guard, radiogroup, state calc, sheet, undo, "আরও", fallback when RPC missing | `web/switchboard.js`, `web/i18n.js`, `web/styles.css` |
| 7 | `ia_show_off_features` read in `ia.js` (absent = ON) | `web/ia.js` |
| 8 | Drawer location up/down (collapsible, per device) | `web/nav.js`, `web/styles.css` |
| 9 | Remaining tests T5-T20, 360 px checks | `tests/web/layout_test.js`, `tests/web/navfold_test.js` |
| 10 | Docs and checks: BUILD-LOG entry; run `check_info_coverage`, `check_ui_inventory`, `check_numbering`, `check_paste_order`, web suites; `git checkout -- tests/web/*.png` | `docs/BUILD-LOG.md`, `docs/HANDOFF.md` |

Order matters: steps 1-4 can ship alone (they fix R8 and need no SQL). Steps 5-9 add the snapshot. The first implementation step is step 1.

Not in this design (listed so nobody adds it by accident): per-person layouts, a PIN on revert, tagging switches as optional, any change to a printed form code, any other-business template, any money or books switch.
