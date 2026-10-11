# Build commands for the app: functions only

Oct 12, 2026 · @MD ALAMIN

Twelve commands, run in order, make the app do what the design notes decided: paper and app side by side, an Add new and Other on every list, and a Control Center that edits places. This page has no colours, icons or layouts. Paste one command at a time into the AI coding tool that holds your app's code, starting with Command 0, which changes nothing.

| # | What it builds | You can check on your phone |
| --- | --- | --- |
| 0 | Standing rules saved in the repo, and a read-only audit | A report of what the app has today; nothing changes |
| 1 | Places, lists, options, the Other queue, change log, add rules | Nothing new on screen; the AI shows passing tests |
| 2 | Search, Add new and Other on every list field | Open any list, search, add a name, write an Other |
| 3 | Category, Unit and Sales column split; the old five choices migrated | New item shows Category and Unit separately; add a unit |
| 4 | Control Center shell and who may open it | The owner sees the tiles; a staff login sees none |
| 5 | Locations: edit, add a showroom, statuses, 17 setup steps | Add a test showroom; Start stays disabled until step 15 |
| 6 | Location Settings Sheet 0-1, 37 rows, versions | Fill rows, save, see Version 2 beside Version 1 |
| 7 | Form register and the Paper, Parallel, App engine | Move one part to Parallel at one place and see it on the board |
| 8 | The pattern every form follows | A test form that hides the expected figure until counted |
| 9 | Turn 2 forms: cash, bank and mobile money | Handover, expense voucher, reconciliation |
| 10 | Turn 3: Daily Showroom Sheet 14-1 and 20-2 | Mid-day events appear on the night page by themselves |
| 11 | Template for turns 4 to 7, one form at a time | The same checks on each form |

# How to use

Run one command at a time, in order, and check each on your phone with a test showroom, never with real data.

1. Take a backup with the app's Backup tile first.
2. Paste Command 0. It makes a branch, saves the rules file in the repo and writes an audit report. Nothing in the app changes.
3. Send me the audit report here. I will adjust Commands 1 to 10 to your real tables and field names before you run them.
4. Paste Command 1, check it, then Command 2, and so on. Commands 2 to 8 all depend on Command 1.
5. Every command says to follow `docs/BUILD-RULES.md`, so a new session loses nothing.
6. The AI never invents a location code, a limit, a price or a form code. When one is missing it stops and asks you.

## Command 0: save the rules and audit the app

Paste this first. It makes a branch, saves the rules every later command follows, and writes a report of what the app has today. It changes no feature, no screen and no data.

```text
TASK: Command 0. Save the standing rules, then audit this app.
Do not change any feature, screen or data. Do not deploy. Never print keys, passwords or PINs; write "present" instead.

STEP 1. Create a git branch named functions-v1 from the current main branch. Work only on it.

STEP 2. Create docs/BUILD-RULES.md with exactly the text below. Read it before every later task.

BUILD-RULES
1. Paper first. This app is the digital version of the business's paper forms. Never remove an existing form, field, option, screen or permission. You may rearrange, group or search them. Removing needs the owner's written yes.
2. Form codes are the paper's own, written as the app writes them: 0-1, 01-1, 08-1, 14-1. Never renumber, reuse or invent one. A retired form keeps its code and gets the status closed.
3. Nothing is deleted. Records, list options, locations, forms and staff are retired or closed, never deleted. A code is never given to anything else.
4. Every list has Add new and Other. There is no free-text box where a list exists. An entry stores the option's id, never its label, so renaming never breaks history.
5. Who may add is a per-list rule: open (anyone; joins the list at once), approval (a request the owner approves; until then the person writes Other), owner (only the owner adds; others write Other). Enforce it on the server or database, not only by hiding buttons.
6. Location, staff ID and time are filled by the system on every record. People never type them.
7. The change log is append-only. Every add, edit, retire, merge, approval, release and state move writes one line: who, when, what, from, to.
8. The person who asks never approves their own request. An approval outside a limit is an exception that is logged; it is never a precedent.
9. Counts are blind. The person types the counted figure first; the expected figure is shown only after the count is saved. The software never counts; it stores what people count. Short or over is always written, even when it is zero.
10. Two signatures are two different logins, each with its own PIN. One login can never sign twice on one form.
11. After approval a record is locked. A change is a request the owner approves, and it appears in the change log.
12. Offline is a state, not a failure. A record saved on the phone and not yet sent shows Not sent yet and is retried automatically. Nothing is lost.
13. Every name the owner enters is stored as name_bn and name_en. Screen text comes from a dictionary with keys and the three modes (বাংলা, Bng-Eng, English). Never hard-code a label.
14. Security: check permissions on the server or database; a hidden button must also be a refused request. Never store a PIN readable. Limit wrong PIN attempts (5 tries, then a 10 minute lock) and log failed attempts.
15. A blank number on a settings sheet blocks the form that needs it. Never invent a limit, a code, a price or a date. If a value is missing, stop and ask.
16. After every task write what changed and what you could not confirm in docs/BUILD-LOG.md, with the manual checks you ran and their results.

STEP 3. Write docs/AUDIT.md with these parts, using tables:
A. Stack: language or framework, build tool, hosting, data store or backend, how login works (staff ID and PIN: where the PIN is checked), where permissions are enforced (client only, or server or database rules), how offline works if at all.
B. Data: for each of these give the table or collection, its fields and how it is stored: staff; roles and Role-by-form permissions; items and prices (say exactly how Category and Unit are stored: one combined value such as "Sweets (KG)", or two fields); item change requests; red-control release requests; exceptions; limits per category (Location settings); form entries for 14-1; the change log; backup.
C. Locations: is there a locations list? Where are locations chosen or hard-coded (file and line)? What code does each of the seven places have today? List them exactly; do not invent any.
D. Lists: every place that uses a fixed option array, a native select or a radio set: file, field name, option values.
E. Forms: for each code below say Built (with its chips), Soon, or Absent, and where its entries are stored.
   0-1, 01-1, 01-2, 02-1 to 02-8, 03-1, 04-1 to 04-4, 05-1 to 05-5, 06-1 to 06-5, 08-1, 10-1 to 10-5, 11-1, 14-1, 14-2, 18-1, 20-1 to 20-6 (42 forms).
F. Owner tiles: list the owner tiles on Home and the screen each opens.
G. Rule check: for each of the 16 rules say Met, Partly or Not met, with the file that shows it. Look hard for any delete button or delete query, an editable change log, permissions enforced only on the client, and how PINs are stored.
H. Risks: the three riskiest things to change, and the safest order.
I. Questions for the owner: at most 10.

STEP 4. Commit only docs/ with the message "Command 0: rules and audit". Do not merge or deploy. Reply with parts H and I only.
```

Done when `docs/BUILD-RULES.md` and `docs/AUDIT.md` exist on branch `functions-v1` and `git diff main --stat` shows nothing outside `docs/`.

## Command 1: places, lists, Other queue, change log, add rules

Data and rules only, no new screens. It builds what every later command stands on.

```text
TASK: Command 1. Data foundations. Follow docs/BUILD-RULES.md and read docs/AUDIT.md first. Work on branch functions-v1. No new screens in this command.
Use the app's existing data store and naming style. Where AUDIT.md shows a table already exists for something below, extend it; do not create a second one. Make every migration safe to run twice.

1. LOCATIONS
Fields: id; code (text, unique, immutable once saved, never reused even by a closed place); name_bn; name_en; kind (showroom, factory, godown, online_office, other); model (A own, B franchise, C funded; default A); status (planned, setup, pilot, live, paused, closed; default planned); supplied_by (optional, locations); planned_opening (optional month); hub_functions (boolean); note; created_by, created_at, changed_by, changed_at.
Rules: a status moves only by a recorded decision (who, when, why); closed is final; a code is never edited or reused; a location is never deleted.
Seed these seven places with the codes the app already uses (AUDIT.md part C). If a place has no code, STOP and ask the owner; never invent one. Set status live only where the app already holds daily entries for that place; for any other place ask the owner (one place may have stopped production).
  Islamia Main (ইসলামিয়া মেইন): showroom, hub_functions true
  2nd Branch (২য় শাখা): showroom
  Misti Bari (মিষ্টি বাড়ি): showroom
  Al-Cakiz (আল-কেকিজ): showroom
  Sweet factory (মিষ্টি কারখানা): factory
  Cake factory (কেক কারখানা): factory
  Godown (গোডাউন): godown

2. LISTS AND OPTIONS
Tables:
  lists: id, key, name_bn, name_en, add_rule (open | approval | owner), allow_other (default true).
  list_options: id, list_id, code (unique in the list, immutable, never reused), name_bn, name_en, detail, sort, is_default, status (active | retired), created_by, created_at, retired_by, retired_at, retired_reason.
  other_entries: id, list_id, form_code, record_id, text, written_by, written_at, status (needs_naming | added | merged | kept), resolved_option_id, resolved_by, resolved_at.
A record stores a list value as {optionId} or as {other: "text as written"}, never as a label.
Server-side functions (each writes the change log):
  addOption(list, name_bn, name_en, by): normalise (trim, collapse spaces, ignore case and punctuation). An exact duplicate is refused. A similar name (same after removing spaces and punctuation, or edit distance 2 or less for names of 5+ letters) is returned as {similar: option} so the screen can offer Use it. At least one of name_bn, name_en is required.
  Rule open: the option is active at once. Rule approval: create a pending request that appears in the owner's Needs you list; the option is not selectable until approved; the requester can never approve it. Rule owner: only the owner role may add; everyone else gets error OWNER_ONLY, even if they call the function directly.
  editOption(option, names, detail, sort, is_default, by): the code never changes.
  retireOption(option, reason, by): hidden from new entry lists, still shown on old records, never deleted.
  reorder(list, orderedIds).
  setAddRule(list, rule, by): owner only.
  writeOther(list, form_code, record, text, by): saves the text on the record and adds a needs_naming row. It must never block saving the form.
  resolveOther(entry, action, optionId, by): action add (creates an option under the list's rule, then relinks the entry), merge (relink to an existing option), or keep (leave as written).

3. CHANGE LOG
Use the app's existing change log and keep its old rows. It is append-only at the database level: no role may update or delete a row. Columns: at, by, action, object_type, object_id, field, from, to, note.

4. PERMISSIONS
Add these keys to the existing Role-by-form mechanism: list.add:<list key> per role; list.setRule (owner); location.create (owner; the daily-accounts reconciliation role may create the code and row only after the owner's decision is recorded); location.edit (owner, head management); location.status (owner); settings.approve (owner). Owner may do everything; no other role gets a key unless the owner grants it.

5. STARTING LISTS AND ADD RULES (a proposal; the owner changes them in Command 4)
  approval: Category; Unit; Supplier; Party and wholesale customer.
  open (confirm with owner): Customer (retail, for an order); reason lists for complaint, return, repair and short-or-over.
  owner: Location kind; Payment method; Expense head (khat); Marketing head; Sales column of 14-1; Wastage class; Day-tag colours; Delivery area and charge.
Seed options only from what the app already holds (AUDIT.md part D). Do not invent options. Exception: seed Sales column with the nine columns of the 14-1 paper (Sweets, Cake, Jalebi, Doi, Bakery, Ice cream, Drinks, one unnamed slot for a new sector, Other).

6. TESTS. Write them, run them, and put the results in docs/BUILD-LOG.md:
  - a location code that exists, or ever existed, is refused; editing a code is refused; any delete is refused;
  - adding "Rasgulla" then "rasgulla " is refused as a duplicate; "Rosogolla" returns similar;
  - open list: anyone adds. Approval list: a staff add makes a pending request, the option is not selectable, the owner approves, the requester cannot approve their own;
  - owner list: a staff add is refused by the server even when the function is called directly;
  - Other: a record saves with Other text, a needs_naming row appears, and add, merge and keep each relink correctly;
  - retire: the option leaves new-entry lists and still shows on old records;
  - every test above wrote a change-log line, and an update or delete on the change log fails.
```

Done when every test passes and the seven places exist with their real codes.

## Command 2: search, Add new and Other on every list field

One shared list control replaces every picker. Behaviour only; how it looks comes later from the design notes.

```text
TASK: Command 2. Every field that picks from a list gets search, Add new and Other. Follow docs/BUILD-RULES.md. Command 1 must be finished.

1. Build ONE shared list-field control and use it for every list field. Inputs: list key, current value ({optionId} or {other}), onChange. Find every use in docs/AUDIT.md part D (native select, radio set, fixed array) and replace each one. Where a fixed array has options that are not in the list yet, import them first as active options with the same names. Never drop an option.

2. Behaviour:
  a. Closed: show the chosen option's name (name_bn, name_en or both, by language mode), or the Other text with a small "অন্য" tag, or a placeholder.
  b. Tap opens a panel with the active options in sort order. A search box appears when there are 8 or more options; it matches name_bn, name_en and code, ignoring case and spaces.
  c. Under the scrolling list, always visible, two rows: Add new, and Other (অন্য). They stay visible whether the list has 3 options or 300.
  d. Add new follows the list's add rule for this person.
     open: a name field, pre-filled with whatever was typed in search. Save adds the option at once and selects it.
     approval: the same field, but the button says Send request. It creates the pending request for the owner's Needs you list and shows Request sent. The field stays empty until approved; meanwhile the person may use Other.
     owner: no field. Show one rule line (only the owner adds to this list) and Write as Other. For the owner, add an Open Control Center link.
     A person who may add always sees the ordinary Add field, whatever the list's rule.
  e. Duplicate guard: an exact duplicate is blocked with a message. A similar name shows "Already in the list" with a Use it button.
  f. Other: a text field. Saving stores {other: text} on this entry and shows "Kept on this entry as written. Management adds it to the list later." Other must never block saving the form.
  g. Escape closes the panel; arrow keys move through options; focus returns to the field; the field and options have accessible names.
  h. Offline: an added option, a request or an Other text is queued and shows Not sent yet, then sends by itself.

3. Dictionary keys in all three modes. English first; the Bangla is a draft for a staff member to read.
  ui.search = Search | খুঁজুন
  ui.add_new = Add new | নতুন যোগ করুন
  ui.request_new = Send request | নতুন যোগের অনুরোধ
  ui.owner_only_add = Only the owner adds to this list | নতুন যোগ শুধু মালিক
  ui.write_as_other = Write as Other | অন্য হিসেবে লিখুন
  ui.other = Other | অন্য
  ui.use_it = Use it | এটাই নিন
  ui.already_in_list = Already in the list | আগে থেকেই তালিকায় আছে
  ui.request_sent = Request sent | অনুরোধ পাঠানো হয়েছে

4. Every existing list screen (Items, Suppliers, Parties, Staff) gets a + Add button in its header that uses the same rule. Locations is done in Command 5.

5. Do NOT convert free-text fields into lists automatically. List each one in docs/BUILD-LOG.md (file, field, the distinct values now stored) so the owner can decide.

6. Manual checks on a phone, with a test list of 3 options and a test list of 300:
  Add new and Other are visible in both; search finds a Bangla and an English name; open rule adds and selects; approval rule shows Request sent and the option is not selectable; owner rule shows the rule line to a staff login but the Add field to the owner; a duplicate and a similar name behave as above; Other saves a form; Escape and arrow keys work; an add made offline sends later.
```

Done when no native select, radio set or fixed option array is left for a list field, and every check above passes.

## Command 3: split Category, Unit and Sales column

Today's New item screen mixes what an item is with how it is sold. This command separates them and moves the old five choices over without losing an item.

```text
TASK: Command 3. Split item Category into Category, Unit and Sales column. Follow docs/BUILD-RULES.md. Commands 1 and 2 must be finished. Never lose, delete or change the meaning of an item.

WHY. The New item screen has Category with five combined choices: Sweets (KG), Doi (Curd), Sweets (Piece), Cake (Pound), Cake (Piece); and Unit with KG, Piece, Pound. The Master Item Dictionary has 25 categories and 1,305 active items. The 14-1 paper has nine sales columns.

1. LISTS. Create lists category (add rule approval), unit (approval) and sales_column (owner). Add to each item: category_id and unit_id. Keep the old combined value in legacy_category and never delete it.

2. CATEGORIES. If AUDIT.md shows the 25 dictionary categories are already in the app, use them. If not, create only Sweets, Doi and Cake now, and ask the owner for the dictionary's category sheet to load the rest. Do not invent categories.

3. UNITS. Seed only KG, Piece and Pound. Dozen, Packet, Box and any other unit are added later by people through Add new.

4. SALES COLUMN MAPPING. Create category_sales_column (category_id, sales_column_id), editable later in the Control Center. Seed: Sweets to the Sweets column, Cake to Cake, Doi to Doi, and likewise for any category named like a column (Jalebi, Bakery, Ice cream, Drinks). Any category without a mapping goes to the Other column and is flagged needs mapping.

5. MIGRATION, dry run first. Write a script that, for each item, sets category_id from legacy_category and keeps the item's existing unit as unit_id:
   Sweets (KG) = Sweets + KG
   Sweets (Piece) = Sweets + Piece
   Cake (Pound) = Cake + Pound
   Cake (Piece) = Cake + Piece
   Doi (Curd) = Doi, and the unit stays whatever the item has today (ask the owner which unit is standard)
   The dry run changes nothing. It prints counts per old choice, and a list of items where the old choice and the item's own unit disagree (for example Sweets (KG) but unit Piece), and items it cannot map. STOP after the dry run and show the owner the table.
   After the owner says yes, run it once for real. Make it safe to run twice. Write one change-log line per item.

6. NEW ITEM SCREEN. Category and Unit use the shared list control from Command 2. Sales column is shown read-only, derived from the category mapping. All existing fields stay. A new item and any edit of a name or price still go through the existing Item change request path. The five old combined choices are never offered again.

7. REPORTS. Anything that grouped by the old category (including the 14-1 sales columns) now groups by sales column through the mapping. Compare the last 30 days of totals before and after; they must match. Report any difference.

8. CHECKS. Item count before equals item count after. Every active item has a category and a unit, or is on the needs decision list. No price changed. Adding a unit called Dozen through Add new creates an approval request.
```

Done when the owner has approved the dry run, the migration has run once, no item was lost, and the 30-day totals match.

## Command 4: the Control Center shell

One separate area for everything that is set, as opposed to everything that is entered. The eight tiles the app already has keep their screens; four are new.

```text
TASK: Command 4. Build the Control Center shell, the Lists & options screen and a basic Print & books screen. Follow docs/BUILD-RULES.md. Commands 1 to 3 must be finished. Do not rebuild or remove any existing owner screen.

1. ENTRY. A route /control (or the app's equivalent). Entry points: one full-width tile at the end of Home and a Menu item, shown only to the owner and head management. Each tile shows a count of what waits inside it.

2. TWELVE TILES in four groups. Existing screens open unchanged.
  Places and rollout: Locations (Command 5); Rollout board (Command 7); Location settings (the existing limits screen, extended in Command 6).
  Lists and items: Lists & options (new, below); Items & prices (existing).
  People and access: Staff & approval (existing); Role x form permissions (existing).
  Rules and system: Form rules (existing); Print & books (new, below); Settings, Change log, Backup (existing).

3. ACCESS, enforced on the server, not by hiding. A tile a role may not open is not shown and its route is refused.
  Owner: all twelve.
  Head management: Locations, Rollout board, Location settings, Lists & options, Print & books.
  Daily-accounts reconciliation staff: Locations, to create a code and a row only.
  Everyone else: nothing.
  Read each role's current permissions from the existing Role x form screen and add these as defaults; the owner can change them there.

4. NEEDS YOU on Home (owner and head management). One list that merges everything waiting for a decision, oldest first: item change requests, red-control release requests, exceptions, list add requests (Command 1), forms waiting at approve, and rollout decisions (Command 7). Item change requests, red-control releases and exceptions stay out of the Control Center; they are decisions, so they live here and under Approvals. A person never sees their own request in their approve list.

5. LISTS & OPTIONS screen (owner and head management; changing an add rule is owner only).
  The lists screen shows each list: name, add rule, number of options, number retired, number of Other entries needing a name.
  Opening a list shows its options with: edit names (both languages), detail line, reorder, default, retire (with a reason), restore (owner only). The code is read-only. Nothing is deleted.
  Needs naming: every Other entry with its form code, who wrote it and when. Three actions: Add to list (creates the option under the list's rule, then relinks the entry), Merge into an existing option (pick one; relinks), Keep as written.
  Pending add requests for approval-rule lists appear here and in Needs you, with Approve and Reject.
  Under the Category list, a Sales column mapping editor (category to sales column).
  Every action writes the change log.

6. PRINT & BOOKS (basic).
  Print notes: when a location is added, renamed or closed (Command 5), create one note per printed form that carries a location line, saying what to change at the next print. A note is cleared only when someone records the new print (date, who). Nothing is reprinted early.
  Books and serials: a register per form per location with the first and last serial of each printed book, the date issued and who holds it. Flag any break in a serial run. A serial created by the app always continues after the last paper serial.

7. CHECKS on a phone. The owner login sees twelve tiles; a head-management login sees five; a staff login sees none and cannot open /control by typing it; the counts update when an Other is written; Needs naming actions relink the original entry; a retired option disappears from the Add form but stays on old records; a print note appears and clears.
```

Done when all checks pass and no existing screen lost a feature.

## Command 5: Locations, edit and add a showroom

This is the part you asked for: showrooms, godowns and factories edited in one place, and more showrooms added without a developer. A new place is a new row, not a new design.

```text
TASK: Command 5. Build the Locations area of the Control Center. Follow docs/BUILD-RULES.md. Commands 1 and 4 must be finished.

1. LIST. One card per location: code, name (both languages), kind, model, status, and the setup progress for places not yet live. Search, and filter chips All, Live, Setting up, Paused, Closed. A + Add location button for roles with location.create. Order: the seven current places first in rollout order (Islamia Main, sweet factory, godown, 2nd Branch, Al-Cakiz, cake factory, Misti Bari), new places after.

2. RECORD SCREEN, one column of cards:
  Identity: code (read-only after saving), name_bn, name_en, kind and model (list controls), supplied by (optional), planned opening month, hub functions here (switch; true only on Islamia Main), note.
  Setup: the 17 steps (below) with progress.
  Rollout: the 15 software parts with their state at this place (read-only here; changed in Command 7).
  Settings sheet: a link to 0-1 for this place with its version and how many rows are filled (Command 6).
  Items and prices: the item list and price list for this place, if the app already has per-place lists; if it does not, say so in BUILD-LOG and do nothing.
  Duty slots: manager, backup, night second counter, from the Duty and Backup Card 02-7 if that form exists.
  Paper: the books and serials and the print notes for this place (Command 4).
  Every field is editable by roles with location.edit, except the code and the history. Every edit writes the change log.

3. STATUSES. planned, setup, pilot, live, paused, closed. Forward by a recorded decision, never by a timer. paused can return to live. closed is final.
  A place can be chosen in any form's location list from setup onward, because its opening count and first goods are recorded against its code before it opens. While planned it appears only here. While paused or closed it leaves the entry lists but stays in every report and in history.
  Every form's location list reads from this table, uses the list control with the owner rule, and keeps its Other option.

4. ADD A LOCATION (the form behind + Add location).
  Fields: kind, model, name_bn, name_en, code, planned opening month, supplied by (optional), decision note.
  The code: suggest the next free one; refuse one in use or ever used by a closed place (error: This code is in use or was used by a closed place. Codes are never reused.).
  Models B and C are hidden until the owner switches them on in Settings (they are not decided yet). When on, B requires the brand-registration check and the legal review recorded; C requires the first monthly P&L by location recorded.
  On Save the place becomes planned and the app does ALL of this at once:
    a. creates the 17 setup steps below, and Needs you cards for the steps that belong to the owner and head management;
    b. creates a blank Location Settings Sheet 0-1, Version 1, holding only the rows that apply to its kind, each marked needs a value (Command 6);
    c. adds a column to the Rollout board with all 15 parts at Paper (Command 7);
    d. adds the place to every location list, following the status rule in 3;
    e. writes the print notes (Command 4).

5. THE 17 SETUP STEPS. Each has an owner, a date, a done tick and a note. Steps marked * need the owner's yes.
   1* Decide: place, rent, budget, expected sales, which factory supplies it. Owner
   2 Location code and a row in the location list. Daily-accounts reconciliation staff
   3 Name the place under Other on every form's location box until the next print. Head management
   4 Item list and current price list for this place. Head management
   5* Duty slots: manager, backup, night second counter; the same person is never in two slots (form 02-7). Owner names, head management enters
   6 Skill check of the new duty holder (form 02-8). A checker from the list
   7 Hiring and registration (form 02-4). Head management
   8* Cover the one-person gap: night second count, witness, shift handover (forms 02-7, 11-1). Owner
   9 Cash boxes: drawer float and imprest kept apart; the business mobile-money number (0-1 rows 1 and 2). Head management
   10* Location Settings Sheet 0-1 at this place's own measures. Head management fills, owner approves
   11 Equipment and places: fridge thermometer, scale test weight, handover place, key duty (0-1 rows 11, 13, 30). Head management
   12 Print the paper set with serial numbers; write the first number of each book. Head management
   13 Supply map: which factory, how many trips, the handover point. Head management (optional until the supply map is confirmed)
   14 Training, one paper at a time (form 02-8). Head management
   15 Opening count the night before (forms 04-3, 04-4). Two counters
   GATE: steps 1 to 15 must be done before step 16. The button Start on the 1st is disabled until then, with a line listing the steps still open. It can only be pressed to start on the 1st of a month.
   16 Start on the 1st: first week, then one month pass or fail, then 7, 30 and 90 day reviews. Everyone at the place. On start, status becomes pilot.
   17 Weekly comparison with the other places on the same figures (form 01-1, a new column). Head management

6. PAUSE AND CLOSE. Pause hides the place from entry lists and keeps everything. Close opens a checklist that must be complete; the owner may record an exception, which is logged and is never a precedent.
   Own place (A): last stock count; remaining goods moved by challan; the place struck from the duty card (kept in history); settings sheet filed; supplier and party balances settled.
   Franchise (B): last party-ledger balance settled; deposit returned or adjusted; signboard, packaging and paper sets returned; brand use stops.
   Funded (C): last count in front of the partner; last month's P&L and commission; deposit settled; keys returned and duty slots emptied.
   On close the status is closed and the code can never be given to another place.

7. NOT NOW. Do not build franchise or funded behaviour (party invoices, commission lines) in this command. Build only the fields, the gates and the close checklist.

8. CHECKS on a phone with a test showroom: add it; try an existing code and a closed place's code (both refused); see the 17 steps and the disabled Start; tick steps 1 to 14 and see Start still disabled; tick 15 and see it enabled but only for the 1st of a month; the new place appears in a form's location list; pause it and see it leave that list but stay in a report; close it and see the checklist; a staff login cannot open any of this; every edit is in the change log.
```

Done when a test showroom can be added, set up, started, paused and closed, and nothing about the seven current places changed.

## Command 6: the Location Settings Sheet 0-1

The sheet holds every limit the forms check against: 37 rows, one sheet per place, versioned. The app's existing limits-per-category screen becomes row 22 of it.

```text
TASK: Command 6. Build the Location Settings Sheet, form 0-1. Follow docs/BUILD-RULES.md. Commands 1, 4 and 5 must be finished. Do not remove the existing Location settings screen; make it read from the sheet.

1. DATA.
  settings_sheets: id, location_id, version (1, 2, 3...), effective_date, status (draft | waiting_approval | approved | superseded), prepared_by, approved_by, approved_at, approval_photo (optional), note.
  settings_values: sheet_id, row_no, value (typed by the row's shape), source (a list: owner decision | measured on site | outside figure; add rule owner), not_needed (boolean), note.
  settings_rows (the definition list, owner can add rows): row_no, label_bn, label_en, shape, used_by (form codes), applies_to (rule below).
  Rows are seeded from the table in part 5. Row numbers are the paper's, including 7a to 7f.

2. VERSIONING. Saving a change never overwrites. It creates the next version with a new effective date; the old version stays readable. A form entry is checked against the version in force on the entry's date, so old entries keep the limits they were made under. Version 1 holds test numbers; after 30 days of real figures Version 2 replaces it.

3. BLANK BLOCKS. Provide one function getLimit(location, row_no, date) that returns the value, or BLANK. Every form that uses a row must call it and never hard-code a number. When it returns BLANK, that form cannot show its inside-limit or outside-limit tick, and shows a line saying which row is empty. A place cannot pass setup step 10 or become live while any row that applies to it is blank. A row marked not needed does not block.

4. SCREEN. One screen per place with the six sections A to F and the 37 rows, each row a typed input (money, percent, days, time, list, pair) plus its source and note. Show how many rows are filled and how many are blank. Buttons: Save draft, Send for approval. Only the owner approves; a version is approved with one action and a date, and the owner may attach a photo of the signed paper. Owner can add a row (label in both languages, shape, which forms use it, which kinds of place it applies to); it joins the sheet of every place it applies to as blank. Never create a row for keys, key stores or passwords: the sheet hangs on a wall.

5. APPLIES TO. A row not needed at a kind of place is marked not needed there. For a kind not covered (an online office), whoever creates the place ticks which rows apply.
  SH = showroom, FA = factory, SF = sweet factory, GO = godown, HUB = a place with hub_functions true.

A. Cash and limits
 1   Sales drawer: fixed float (money) | 14-1 | SH
 2   Imprest (expense box): fixed amount (money) | 10-2 | SH
 3   One-time spend limit; above it needs approval (money) | 10-2 | SH
 4   Acceptable cash difference (money) | 14-1, cash and bank ledger | SH, HUB
 5   Acceptable goods-versus-money difference (percent, or a maximum in money) | 14-1, stock ledger | SH
 6   Large single sale limit; above it a note is written (money) | 14-1 | SH
 7   Average daily sales (money, reference only) | none | SH
 7a  Days goods of an uncollected order are kept (days) | 20-1 | SH where orders are taken
 7b  Days after which an unclaimed advance goes to income (days) | 20-1 | SH where orders are taken
 7c  Deduction for late collection (no, or yes with a percent) | 20-1 | SH where orders are taken
 7d  Hub: maximum cash in the cash box; above it goes to the bank (money) | 10-4 | HUB
 7e  Hub: protected minimum cash, left out of the purchase budget (money) | 10-4 | HUB
 7f  Discount limit and refund limit; above them needs approval (two money values) | 20-2, 20-3 | SH
B. Time and place
 8   Definition of a busy day (text) | 14-1 | SH
 9   Opening and closing time (two times) | 14-1 | SH
 10  Shift split (two time ranges) | 11-1 | SH where two shifts, FA where shifts
 11  Fixed place where goods are handed over (text) | 03-1 | SH, FA
 12  Total crates, trays and pots at this place (three counts) | 03-1 | SH, FA
C. Products and storage
 13  Set temperature of each fridge, chiller or freezer unit (list of unit name and degrees C) | 14-1, 05-1 | SH, FA, GO where cold equipment
 14  Days a product is sellable, by class: sweets, cake, doi, bakery (numbers; the class list can grow) | stock ledger, 03-1 | SH, FA
 15  Day-tag colours for the seven days (seven colours) | stock ledger, 03-1, 05-2 | SH, FA
 16  Wastage classes, the reasons that may be written (list) | stock ledger, production report | SH, FA
D. Factory and jalebi
 17  Milk price per kg (money) | milk and chhana ledger | SF
 18  Expected chhana rate: kg of milk per kg of chhana (ratio) | milk and chhana ledger | SF
 19  Acceptable chhana shortfall (percent) | milk and chhana ledger | SF
 20  Acceptable production yield difference (percent) | production report | FA
 21  Daily jalebi difference limit (percent) | 14-2 | SH where a jalebi counter
E. Marketing, online, new products
 22  Monthly marketing limit by head, the khat (list of head and money) | 18-1 | HUB
 23  Online price: same as showroom, or separate with approval | 20-1 | SH where online orders go out
 24  Delivery charge by area (list of area and money) | 20-1, 20-6 | SH where online orders go out
 25  Most online orders per day: normal day and busy day (two numbers) | 20-6 | SH where online orders go out
 26  Online next-level condition: weeks of matching accounts (weeks) | 01-1 | SH where online orders go out
 27  New product review: days after launch (days) | 05-5 | FA
F. Purchase, count, scale, oil
 28  Comparison quotation mandatory above this single purchase (money) | 06-1, 06-2 | HUB
 29  Acceptable godown and store count difference (percent, or a maximum in money) | 04-3, 04-4 | FA, GO
 30  Scale check: known test item, its weight and the acceptable error | 05-1, 14-2, 04-1 | SH where a jalebi counter, FA, GO
 31  Jalebi oil change: after days, or after kg fried | 14-2 | SH where a jalebi counter

6. EXISTING LIMITS. Import the values of the current limits-per-category screen into Version 1 of each place's sheet as row 22 (marketing head limits), as a draft. Lose nothing. If a place that is not a hub place holds values, keep them, mark row 22 as applying there and list those places in docs/BUILD-LOG.md for the owner to decide. The old screen keeps working and now reads and writes row 22.

7. DICTIONARY. Row labels in both languages come from the rows above; the Bangla labels are the paper's (take them from the form 0-1 in the Build Kit file). Add keys for Save draft, Send for approval, needs a value, not needed.

8. CHECKS on a phone with a test showroom: a new place gets a blank Version 1 with only its applicable rows; a form that needs an empty row shows the blocking line; fill the row and the tick appears; save a change and see Version 2 beside Version 1, with Version 1 still readable; an entry dated before Version 2 is still checked against Version 1; a staff login cannot open or change the sheet; the owner approves one version; the existing limits screen shows the same figures as before.
```

Done when all 37 rows exist, a blank row blocks exactly the forms that use it, and no existing limit was lost.

## Command 7: form register and the Paper, Parallel, App engine

This is how paper and the app live together. Each of the 15 software parts has a state at each place: Paper, Parallel (one month, paper is the record) or App. The register below is the list of all 42 forms with the paper's own codes.

```text
TASK: Command 7. Build the form register, the Paper / Parallel / App state engine and the Rollout board. Follow docs/BUILD-RULES.md. Commands 1, 4, 5 and 6 must be finished.

1. REGISTER. Tables: forms_register (code primary key and immutable, bn, en, kit_version, part, turn, section, status active | closed), parts (id 1 to 15, bn, en, turn), legacy_printed (bn, en, part). Seed them from the data at the end of this command. The codes are the paper's; never renumber or invent one. Adding a form later is adding one row. When the paper changes version (for example 14-1 v2.18 to v2.19) update kit_version and keep the old version readable in history. Show the version under each form's title.

2. STATE. Table rollout_state (part_id, location_id, state paper | parallel | app, since, parallel_start_date, decided_by, decided_at). Every part at every place starts at paper. A form takes the state of its part at the place of the person using it. Parts 10 and 11 have no paper of their own. Parts 14 and 15 come with the part they report on; the owner moves them together with it.

3. TRANSITIONS.
  Only the owner moves a state. Head management can Propose, attaching the month's comparison. A proposal appears in Needs you and as a "decision waiting" marker on the Rollout board cell. Every move writes the change log with who, when and why.
  paper to parallel. The button Start Parallel is offered only when all six show done for that part at that place, each with a date and who ticked it:
    (1) stable on paper for three months and the 90-day review passed (owner ticks);
    (2) the opening count for this place was done the night before (tick, linked to form 04-3 when that exists);
    (3) the settings sheet 0-1 for this place is approved and has no blank row that this part's forms use (checked automatically with getLimit from Command 6);
    (4) the first serial of each new book at this place is recorded (Print & books, Command 4);
    (5) the master data this part stands on is in the app (items, locations, staff, limits; tick with a note);
    (6) at least one comparison pair is named for this part (see 4).
  Parallel can only start on the 1st of a month.
  parallel to app. Only after the month ends, and only with the owner's Pass. Pass requires every comparison day to be Match, or each Differ to have a recorded reason and fix. Pass sets app and closes the paper for this part at this place, with the date. Fail records the reason and the state stays parallel for another month (a new month counter).
  No automatic way back. The owner may set a part back to parallel with a reason; it is logged. (Proposal; confirm with the owner.)
  The next place for the same part should start only after the previous place passed. Show a warning if not. The owner may continue; that is logged as an exception, never a precedent.

4. PARALLEL MONTH. The paper is the record. The same entry is also keyed in the app, flagged parallel, and any report that mixes records labels parallel figures as not the record. Every day, for each named pair, a comparison row is made:
  comparison_pairs (part_id, name_bn, name_en, how_paper_is_read, how_app_is_read), editable by the owner. Do not invent pairs: create the table empty and ask the owner to name one pair per part. Example pair: the expected drawer balance written on the paper night page against the expected drawer balance the app computes.
  comparison_days (part_id, location_id, date, pair_id, paper_value, app_value, result match | differ | waiting, reason, fix, keeper_user, enterer_user).
  The keeper (who copies the paper figure) must not be the person who entered that day's app entries for that pair. Refuse it on the server.
  Month end: a Pass or Fail action for the owner, showing the days, the Differ rows and their reasons.

5. WHAT EACH STATE SHOWS for a form at the user's place.
  paper: the form is listed with the Paper chip and locked, with the line On paper at <place>. The person keeps using the paper.
  parallel: entry is open with a banner Paper is the record this month, the Parallel chip, and the day's comparison reminder.
  app: normal entry; the App chip; a Print action that reproduces the paper's layout, with the app's serial continuing after the last paper serial. Paper is output now, never a second entry.
  Chips: paper, parallel, App. Add dictionary keys in all three modes (draft Bangla: কাগজ, পাশাপাশি, অ্যাপ).

6. ROLLOUT BOARD (Control Center). Rows are the 15 parts; columns are the places that are not closed; each cell shows its chip, with a "decision waiting" marker when a decision waits. Tap a cell to open that part at that place: its papers (from the register), the six preconditions with their ticks, the comparison rows, the month-end Pass or Fail, and its history. A new place adds a column at Paper; a new part adds a row. The tile count on the Control Center is the number of decisions waiting.

7. CHECKS on a phone with a test place: every cell starts at Paper; Start Parallel is disabled with the open preconditions listed; tick them and it enables only on the 1st of a month; a form at Paper is locked, in Parallel is open with the banner, in App prints with the continued serial; the keeper cannot be the enterer; a Fail keeps Parallel; a Pass moves to App and closes the paper date; a head-management login can only Propose; every move is in the change log.

REGISTER DATA. Columns: code | bn | en | kit version | part | turn | section (T- means it comes with its part).
0-1 | লোকেশন সেটিংস শিট | Location Settings Sheet | v1.16 | P1 | T1 | Control Center
01-1 | সাপ্তাহিক রিভিউ নোট | Weekly Review Note | v1.8 | P15 | T- | Reports
01-2 | মাসিক লাভ-ক্ষতি (P&L) ও KPI শিট | Monthly P&L and KPI Sheet | v1.3 | P15 | T- | Reports
02-1 | মাসিক হাজিরা রেজিস্টার | Monthly Attendance Register | v1.8 | P13 | T6 | People
02-2 | মাসিক বেতন শিট | Monthly Salary Sheet | v1.8 | P13 | T6 | People
02-3 | স্টাফ অ্যাডভান্স রেজিস্টার | Staff Advance Register | v1.6 | P13 | T6 | People
02-4 | নিয়োগপত্র — শর্ত ও দায়িত্ব | Appointment Letter — Terms & Duties | v1.5 | P13 | T6 | People
02-5 | ছুটির আবেদন ফরম | Leave Application | v1.6 | P13 | T6 | People
02-6 | ছাড়পত্র (এক্সিট ক্লিয়ারেন্স) | Exit Clearance Form | v1.8 | P13 | T6 | People
02-7 | ডিউটি ও ব্যাকআপ কার্ড | Duty & Backup Card | v1.10 | P13 | T6 | People
02-8 | স্কিল চেকলিস্ট | Skill Checklist | v1.10 | P13 | T6 | People
03-1 | ট্রান্সফার চালান | Transfer Challan (IBT) | v2.10 | P4 | T4 | Stock & purchase
04-1 | মালামাল গ্রহণ রসিদ | Goods Received Note (GRN) | v1.11 | P3 | T4 | Stock & purchase
04-2 | মালামাল ইস্যু স্লিপ | Material Issue Slip | v1.9 | P4 | T4 | Stock & purchase
04-3 | স্টক কাউন্ট শিট | Stock Count Sheet | v1.8 | P4 | T4 | Stock & purchase
04-4 | স্টোর লেজার | Store Ledger | v1.4 | P4 | T4 | Stock & purchase
05-1 | কারখানা দৈনিক শিট | Factory Daily Sheet | v1.7 | P5 | T5 | Production
05-2 | প্রোডাক্ট স্পেক কার্ড | Product Spec Card | v2.5 | P1 | T1 | Production
05-3 | রেসিপি কার্ড | Recipe Card | v1.5 | P1 | T1 | Production
05-4 | ফলন টেস্ট শিট | Yield Test Sheet | v1.4 | P5 | T5 | Production
05-5 | নতুন প্রোডাক্ট সিদ্ধান্ত শিট | New Product Decision Sheet | v1.4 | P15 | T- | Reports
06-1 | পারচেজ রিকুইজিশন (চাহিদাপত্র) | Purchase Requisition (PR) | v1.9 | P2 | T4 | Stock & purchase
06-2 | কোটেশন তুলনা ও সাপ্লায়ার নির্বাচন | Comparative Statement (CS) | v1.4 | P2 | T4 | Stock & purchase
06-3 | পারচেজ অর্ডার | Purchase Order (PO) | v1.8 | P2 | T4 | Stock & purchase
06-4 | বিল যাচাই ও পেমেন্ট অনুরোধ | Bill Check & Payment Request | v1.8 | P3 | T4 | Stock & purchase
06-5 | সাপ্লায়ার লেজার | Supplier Ledger | v1.8 | P2 | T4 | Stock & purchase
08-1 | মেইনটেন্যান্স অনুরোধ ও রেকর্ড | Maintenance Request & Record | v1.6 | P12 | T6 | Assets & maintenance
10-1 | ক্যাশ হ্যান্ডওভার স্লিপ | Cash Handover Slip | v1.6 | P8 | T2 | Cash & accounts
10-2 | ব্যয় ভাউচার | Expense Voucher | v1.9 | P8 | T2 | Cash & accounts
10-3 | ডিজিটাল পেমেন্ট রিকনসিলিয়েশন রেজিস্টার | Digital Payment Reconciliation Register | v1.8 | P8 | T2 | Cash & accounts
10-4 | ক্যাশ পজিশন ও পারচেজ বাজেট | Cash Position & Purchase Budget | v1.9 | P8 | T2 | Cash & accounts
10-5 | প্রাপ্য ও অ্যাডভান্স রিকনসিলিয়েশন | Receivable & Advance Reconciliation | v1.10 | P9 | T6 | Cash & accounts
11-1 | শিফট হ্যান্ডওভার রেজিস্টার | Shift Handover Register | v1.5 | P13 | T6 | Showroom
14-1 | দৈনিক শোরুম শিট | Daily Showroom Sheet | v2.18 | P7 | T3 | Showroom
14-2 | জিলাপি কাউন্টার দৈনিক রেকর্ড | Jalebi Counter Daily Record | v1.6 | P6 | T5 | Showroom
18-1 | মার্কেটিং ব্যয় রেজিস্টার | Marketing Expense Register | v1.4 | P8 | T2 | Cash & accounts
20-1 | কাস্টমার অর্ডার ফরম | Customer Order Form | v3.6 | P9 | T6 | Orders & customers
20-2 | ডিসকাউন্ট অনুমোদন স্লিপ | Discount Approval Slip | v1.7 | P7 | T3 | Showroom
20-3 | রিটার্ন ও অভিযোগ রেজিস্টার | Return & Complaint Register | v1.9 | P9 | T6 | Orders & customers
20-4 | পার্টি ও পাইকারি ইনভয়েস | Party & Wholesale Invoice | v1.5 | P9 | T6 | Orders & customers
20-5 | পার্টি ও পাইকারি লেজার | Party & Wholesale Ledger | v1.6 | P9 | T6 | Orders & customers
20-6 | অনলাইন ও ডেলিভারি লেজার | Online & Delivery Ledger | v1.4 | P9 | T6 | Online & delivery
```

The fifteen parts and the eight printed papers go in a second block, pasted with the one above.

```text
PARTS DATA. Columns: part | bn | en | turn.
P1 | মাস্টার ডেটা | Master data | T1
P2 | কেনা | Buying | T4
P3 | গ্রহণ ও তিন-মিল | Receiving and three-way match | T4
P4 | মজুদ (গ্রেড ও অবস্থাসহ) | Stock (grade and condition) | T4
P5 | উৎপাদন (ফলন, গ্রেড, রূপান্তর) | Production (yield, grade, conversion) | T5
P6 | জিলাপি কাউন্টার | Jalebi counter | T5
P7 | শোরুমের বিক্রি (আইটেম কোডে) | Showroom sales by item code | T3
P8 | ক্যাশ, ব্যাংক ও মোবাইল টাকার মিল | Cash, bank and mobile-money reconciliation | T2
P9 | কাস্টমার, অর্ডার, অভিযোগ | Customers, orders, complaints | T6
P10 | অবস্থা ও মেয়াদ (দিন-ট্যাগ) | Condition and expiry (day tags) | T6
P11 | খরচ-হিসাব | Costing | T7
P12 | সম্পদ ও মেইনটেন্যান্স | Assets and maintenance | T6
P13 | মানুষ ও স্কিল | People and skills | T6
P14 | গরমিল | Exceptions | with its part
P15 | রিপোর্ট ও ড্যাশবোর্ড | Reports and dashboard | with its part

PRINTED PAPERS. Columns: bn | en | part. These have no code. They stay on paper until a form exists for them.
ছাপানো ক্লোজিং রিপোর্ট | Printed closing report | P7
স্টক লেজার | Stock ledger | P4
ক্যাশ ও ব্যাংক লেজার | Cash and bank ledger | P8
ডেলিভারি ও রিটার্ন চালান | Delivery and return challan | P4
দুধ ও ছানা লেজার | Milk and chhana ledger | P5
উৎপাদন রিপোর্ট | Production report | P5
কর্মী রেজিস্ট্রেশন | Staff registration | P1
কাজের তালিকা | Work list (the list of open discrepancies) | P14
```

Done when the register holds all 42 forms, the 15 parts and the 8 printed papers, a new place shows 15 Paper cells, and a test part can be taken Paper to Parallel to App with every guard above working.

## Command 8: how every form is built

Every form from here on is built the same way, so this command builds the form engine once and proves it on a test form. Commands 9, 10 and 11 then only add data to it.

```text
TASK: Command 8. Build the shared form engine and prove it on a test form. Follow docs/BUILD-RULES.md. Commands 1, 2, 6 and 7 must be finished. Add no real form in this command.

1. A FORM IS DATA.
  form_defs: form_code (from forms_register), version, status.
  form_fields: form_code, version, key, section_letter, order_no, label_key, kind, required, list_id, limit_row, expected_of, source_form, note_on_no, evidence (none | photo | reason | either), applies_to.
  form_entries: id, client_id, form_code, version, location_id, business_date, entered_at, entered_by, status (draft | submitted | waiting_approval | approved | rejected), serial_no, entered_later, paper_serial, revision, parallel_flag.
  form_values: entry_id, field_key, value, source_entry_id.
  The order and the section letters are the paper's. Adding or moving a field is a data change, never a code change. An old entry keeps the version it was made under.

2. FIELD KINDS. Every field is exactly one of these five, plus plain inputs (text, number, money, date, time, list).
  EVENT  Filled from a record made by a quick action or by another form. The person cannot retype it; to change it they open the source record. Store source_entry_id.
  AUTO   Computed by a named function from other fields. Read-only. Store the inputs and the formula version with the result so it can be re-checked.
  COUNT  A number a person counted or read from a statement. If the field has expected_of, it is BLIND (rule 9): the server does not send the expected figure to the device until the count is saved. Hiding it on the screen is not enough. After the save, show the expected figure, then write Short or Over, even when it is zero, and ask for the reason when it is not zero.
  TICK   Yes or No. If note_on_no is set, a No needs a note. A mandatory tick blocks Submit until it is ticked.
  PIN    A signature. The person logs in with their own staff ID and PIN (rule 10). The server records who and when. One login can sign only once on one form. A slot can name a required role (for example approver) and can forbid the person who entered. Wrong PINs use the lockout in rule 14.
  A field that picks from a list uses the list control from Command 2 and stores the option id. Money inputs take Latin digits only.

3. WHAT EVERY FORM DOES.
  a. Location, staff ID and entry time come from the server. The business date is chosen by the person only where the paper allows it, and a reason is stored when it is not today.
  b. Save draft keeps the entry on the phone and on the server. Submit checks mandatory fields, mandatory ticks, evidence (a photo or a reason where the field says so) and limits (item d). Then the status becomes submitted, or waiting_approval when the form has an approval slot.
  c. Offline (rule 12). Submit with no connection stores the entry on the phone with a client_id and shows Not sent yet. It retries by itself. The server ignores a repeated client_id, so nothing is saved twice. The person sees how many entries are Not sent yet.
  d. Limits. A field with limit_row calls getLimit(location, row, business_date). BLANK blocks the inside-limit and outside-limit ticks and names the empty row. Outside the limit follows the paper: it asks for the approver slot (someone else's PIN) or starts a release request, and writes an exception that is logged and is never a precedent (rule 8).
  e. Lock (rule 11). Once approved, the server refuses every edit. Request a change creates change_requests (entry, field, old, new, reason, requested_by). Only the owner approves. Approval makes revision n+1 and revision n stays readable.
  f. Entered later. For work done on the paper backup stack during a power or internet failure, the person ticks Entered later and types the paper's serial number and the original time. Both show on every print and in the log.
  g. Serial. serial_books: form_code, location_id, book_no, first_paper_number, last_paper_number, software_first_number, next_number, status. The software's first number comes after the paper's last number. A number is never reused; a skipped number is written with its reason. Print repeats the entry's boxes in the paper's order and prints the serial. It creates no data. A second print says Copy. Every print writes a log line.
  h. Part state (Command 7). Before every action the server reads rollout_state for the form's part at the person's place. Paper: no entry; the form opens read-only, with a blank copy to print. Parallel: entry is allowed, the entry is flagged parallel, and the screen says the paper is still the record. App: normal. This is checked on the server.
  i. Permissions. Keys view, enter, approve, request_change and print per form per role, from the Role-by-form permissions, enforced on the server and scoped to the person's place (a manager reads only their own place unless the role is hub or owner).
  j. Exceptions. A tick or count that breaks a rule creates an exceptions row (form, entry, place, text, status open | closed, closed_by). Open ones feed Needs you in the Control Center.
  k. Change log lines for: create, submit, approve, lock, change request, reject, print, state change.
  l. Dictionary. Every label, hint and message is a key with bn and en.

4. TEST FORM. Create one form with the code TEST-1, visible only to the owner, holding one field of each kind, one expected_of pair, one limit_row and two PIN slots. When this command is accepted, set it to closed. Do not delete it.

5. CHECKS on a phone, using TEST-1:
  1. In the network inspector, the expected figure is absent from the response until the count is saved.
  2. Both PIN slots filled with the same login are refused.
  3. Submit with a mandatory tick missing is refused by the server as well as the screen.
  4. Airplane mode: Submit shows Not sent yet; on reconnect it is sent exactly once.
  5. After approval a direct edit is refused; a change request works and makes revision 2 while revision 1 stays readable.
  6. A blank limit row blocks the tick and names the row.
  7. Entered later stores the paper serial and shows it on the print.
  8. A part in Paper refuses entry from the server; a part in Parallel flags it.
  9. A login from another place cannot read the entry.
  10. Every step above wrote a change log line.
```

Done when all ten checks pass, the engine reads every form from data, and TEST-1 is closed.

## Command 9: cash, bank and mobile money (rollout turn 2)

Part 8 holds five forms: 10-1 Cash Handover Slip, 10-2 Expense Voucher, 10-3 Digital Payment Reconciliation Register, 10-4 Cash Position and Purchase Budget, 18-1 Marketing Expense Register. This command adds them as data on the Command 8 engine. Every place stays on Paper for part 8 until the owner moves it, so nothing changes for staff when this is built.

```text
TASK: Command 9. Add the five forms of part 8 to the form engine. Follow docs/BUILD-RULES.md. Command 8 must be finished. Add only form data (form_defs, form_fields, serial books, permission keys, dictionary keys) and the small functions named below. Do not change another form.

Kinds: E event, A auto, C count, T tick, P pin, L list. Section letters, order and Bangla wording are the paper's: take them from the form's page in the Build Kit file (ফরম 10-1, 10-2, 10-3, 10-4, 18-1). If the paper and this text differ, the paper wins; write the difference in docs/BUILD-LOG.md.

For each form: forms_register row exists (Command 7); version shown under the title; serial book per place with first_paper_number left blank for the owner to fill (never invent it); permission keys view, enter, approve, request_change, print created for the owner only. List in docs/BUILD-LOG.md that the owner must choose which role may enter and approve each form. Do not guess role defaults.

=== 10-1 Cash Handover Slip. Two sections on one slip number, plus a counterfoil that stays in the showroom's book.
Header: date A, place A, time A, Daily Showroom Sheet number E (the 14-1 entry of that business date; typed number if 14-1 is not yet in App at this place), slip number A from the serial book, received-at place L (places with hub_functions true; default the hub).
Section A, showroom fills: note counts C for 1000, 500, 200, 100, 50, 20, 10, 5, 2, 1 and coins amount C; counted total A; change left in the drawer C; handover amount A = counted total minus change left (mandatory); amount in words A in Bangla, shown for the sender to confirm; sent with: Daily Showroom Sheet original T, expense vouchers count C, other text; sender P (the manager) and time A; carrier L (staff list, with Other for someone outside) and carrier P when staff, or a tick T "signed on the paper copy" when Other; seal or bag number text.
Section B, hub fills (a different person from the sender, enforced): counted at hub C and BLIND, so the sent amount is withheld from the hub person until the count is saved; difference A, written even when zero, with a reason when not zero; seal found intact T; Cash and Bank Ledger date and line number (typed; that ledger is a printed paper with no code); received by P and time A; return copy sent to the showroom T.
Counterfoil: slip number, date, place, handover amount, carrier, time sent, manager P. After Section B is saved, the counterfoil's "received at hub" and "matched or difference" fill themselves E/A. The showroom types nothing twice.
States: sent, then received_matched or received_difference. A difference raises an exception. The slip number and amount land on 14-1 Section E as E.

=== 10-2 Expense Voucher, spent from the expense box (imprest).
Header: date A, time A, place A, Daily Showroom Sheet number E or typed, voucher number A from the serial book.
Lines (several): expense head L; paid to or for text; receipt attached T with a photo of the receipt when Yes; amount C. Heads, in the paper's order: staff food and snacks; transport; customer hospitality; repair and utility; temporary worker wages (needs the line number in the temporary part of the monthly attendance register, typed because 02-1 is built in a later turn); goods from outside sourcing (company and goods); other (write). The list has the add rule approval.
Total A. Within the one-time spend limit T/A against row 3 of the Location Settings Sheet via getLimit; above it, an approver P who is not the person who spent. A blank row 3 blocks the tick and names the row.
T: no expense without a receipt; if not ticked, a reason text. T: nothing was taken from the sales drawer.
Imprest account: cash in the morning C, spent today A (the total), cash now C, receipts total A, cash plus receipts A, and a tick T/A that it equals the fixed amount in row 2; if not, the difference A and an exception.
Signatures: spent by P, approved by P, received at hub by P with date.
Rule: replenishing the imprest is an action that is refused unless the receipts recorded since the last replenishment cover the amount (paper: only against receipts; cash plus receipts always equals the fixed amount).
Feeds 14-1 Section C "daily expenses" as E: voucher numbers, heads, amounts, receipt ticks, total, and the tick "nothing was taken from the drawer".

=== 10-3 Digital Payment Reconciliation Register, weekly, kept at the hub.
Header: week from and to. One block per showroom place.
Per place and per channel L (bKash, Nagad, card or POS, bank; the list has the add rule approval): A shop's paper amount E (sum of that week's digital lines on 14-1 where 14-1 is in App at that place, otherwise C typed); B on the statement C; charge deducted C; C deposited in the bank C; difference A; reason or action text. The paper shows the differences; store A, B, charge and C and compute both (A minus B) and (B minus charge minus C), show both, and write the question "which pair does the paper mean?" in docs/BUILD-LOG.md. Do not choose silently.
On the statement but not on our paper: how many C, amount C, details text. On our paper but not on the statement: the same three.
T: did any money arrive on a personal number? No, or Yes with an amount C. Yes at once raises an exception and appears in Needs you for the owner and head management.
Statement collection: channels collected (the channel list, multi-tick), date, collected by L (staff). T: no statement found, so the reconciliation is held. While ticked the register cannot be signed and no figure is final. The app never lets anyone estimate.
Courier and food-app block: receivable per the Online and Delivery Ledger A (E from 20-6 when it is in App, otherwise C), on the statement B C, commission or charges kept C, received in hand or bank C, difference A, reason text.
Signatures: performed by P with date; checked by P and it must be a different person; T: added to the work list when a difference is not resolved (it creates an exception).

=== 10-4 Cash Position and Purchase Budget, daily, kept at the hub.
Date A. Prepared by P.
A, cash in hand: hub cash box C with an inside or outside tick against row 7d via getLimit (outside: management informed T and an exception); change held in the showroom drawers C; bank C; mobile account C; each with a note; total A.
B, receivable in the next 7 days: parties and credit collections; balance of orders; other. Each has amount C and date; total A.
C, payable in the next 7 days: supplier dues; salary and allowances; rent, electricity, gas; loan repayment; other. Each has amount C and date; total A.
Purchase budget A = A + B minus C minus the protected minimum cash in row 7e. If row 7e is BLANK the budget is BLANK and the line names the row. Provide getPurchaseBudget(date) that returns the latest approved figure or BLANK. A later purchase order form must not go beyond it; do not build that check here, only the function.
Shortfall expected T; if Yes: date, amount C, action text, management informed T.
If cash is short, a priority table: who first and for what (L suppliers or text), amount C, date.
Decision and approval P by someone other than the preparer, or T phone approval to be signed later; that state stays open as an exception until the signature is added. Checked by P (management).

=== 18-1 Marketing Expense Register, one page per month, kept at the hub.
Header: month A/date, brand L (Islamia Misti Ghor, Misti Bari, Al-Cakiz, Other, All; add rule approval).
Lines: serial A; date; head L from the paper's ten: online ads and boost (with VAT), content creation, printing, samples and trials, offer and discount campaigns, delivery subsidy, platform commission, festival and events, partner, other (write); product or campaign text; period and place text; source of money L; amount C; value without payment C (samples and the like); receipt or invoice number text with a photo; ledger line number text; result (messages and orders) text; approver P and the time when approval came by message.
Source of money list: expense box, bank, card, mobile, owner's personal money (it is recorded on both sides in the ledger). There is no option for the sales drawer, and the add rule for this list is owner only, so the sales drawer can never be added.
Rule: every marketing expense is entered before the work, with approval. A line cannot be saved as paid unless approved_at is earlier than the spend. A staff member who boosted with their own money and asks for a refund is refused when the line has no earlier approval. Sample goods are issued on the Material Issue Slip 04-2 (built later); keep a typed slip number field.
End of month match: register total A; marketing figure in the cash and bank ledger C; card or mobile statement and ad invoices C; T/A match, or the difference A. Inside the head limit in row 22 T/A via getLimit; outside, an approver P.
Signatures: entered by P (online duty), checked by P (the person who does the daily accounts reconciliation, not the enterer), approved by P (owner) with date.

COMPARISON PAIRS. Do not create any. In docs/BUILD-LOG.md list candidate pairs for part 8 for the owner to choose from, for example the handover amount on the paper slip against the app's, and cash plus receipts against the fixed imprest amount.

CHECKS on a phone with a test showroom and a test hub, each part 8 form first on Paper, then the test place on Parallel:
 1. 10-1: the hub person cannot see the sent amount before saving the count; a zero difference is written as 0; the same person cannot sign Section A and Section B; the counterfoil fills itself; the slip number comes from the serial book.
 2. 10-2: a line above row 3 asks for an approver who is a different person; a blank row 3 blocks the tick; cash plus receipts different from row 2 shows the difference and an exception; replenishing without receipts is refused.
 3. 10-3: Yes to the personal number appears in Needs you; no statement ticked blocks signing; checker equal to performer is refused.
 4. 10-4: row 7e blank gives a BLANK budget that names the row; filling it gives the figure; approver equal to preparer is refused; phone approval stays open until signed.
 5. 18-1: a line without earlier approval is refused; the source list has no sales drawer and the owner cannot add one; a month with a mismatch shows the difference; a spend outside the row 22 limit asks for an approver.
 6. A staff login on a place that is on Paper cannot enter any of the five; the same login on the Parallel test place can; the owner can read both.
```

Done when all five forms exist as data, all six checks pass, and BUILD-LOG lists the open questions (which pair for 10-3, role defaults, comparison pairs, first paper serial per place).

## Command 10: Daily Showroom Sheet 14-1 and Discount Approval Slip 20-2 (rollout turn 3)

Part 7 is showroom sales. 14-1 is the biggest form: one sheet a day with nine sections (A to I) and three signatures. The idea that makes it "enter once" is the quick action: a slip made in the middle of the day fills the night sheet by itself. 14-1 already appears in the live app with Entry and Approve, so this command builds beside it and removes nothing.

```text
TASK: Command 10. Add form 14-1 Daily Showroom Sheet and form 20-2 Discount Approval Slip to the form engine, with the quick actions that fill 14-1. Follow docs/BUILD-RULES.md. Commands 6, 7, 8 and 9 must be finished.

A. THE LIVE 14-1. Read docs/AUDIT.md parts B and E for how 14-1 is stored today. Do not remove, change or hide the existing 14-1 screen or its entries. Build the new 14-1 beside it under the same code, with the engine. List every field the live screen has that the paper (Build Kit, ফরম 14-1, version 2.18) does not, and every paper field the live screen lacks, in docs/BUILD-LOG.md. Existing entries stay readable and are shown as "previous layout". Nothing is migrated in this command.

B. EVENT RULE. A field marked E reads the source form's entries for that place and business date when the source form's part is Parallel or App at that place. Otherwise the field is typed on 14-1 as on the paper, and is stored with source_pending = true. When the source form is built later, the same field becomes E with no change to older entries. This is how a field is entered once and never twice.

C. QUICK ACTIONS. Table quick_actions: key, label_key, form_code, lands_on (14-1 section and field), status (built | later). A quick action opens the source form's own entry screen with the place and date filled, and saves it as that form. Create these nine; show only the built ones, the others stay as rows with status later.
  receive_goods | 03-1 | Section B | later
  spend_from_expense_box | 10-2 | Section C daily expenses | built (Command 9)
  take_an_order | 20-1 | Section D | later
  give_a_discount | 20-2 | Section E adjustments | built (this command)
  return_or_complaint | 20-3 | Section E refund | later
  credit_sale_to_a_party | 20-4 | Section E credit sales | later
  send_cash_to_hub | 10-1 | Section E and Section C | built (Command 9)
  shift_handover | 11-1 | Section C | later
  incident_or_repair | 08-1 | Section I | later

D. 14-1 FIELDS. Take every box, its order, section letter and Bangla wording from the paper. Kinds: E event, A auto, C count, T tick, P pin, L list. Use getLimit for every limit row; a BLANK row blocks that tick and names the row.
Header. Place A (Locations list). Business date and weekday A. Today's tag colour A from row 15 by weekday. Day type T: normal or busy (row 8 is the definition, shown beside it). Duty manager A from the login. Shift L (whole day, shift 1, shift 2; row 10). Sheet number A from the serial book.
Section A, opening, 12 tasks. (1) Shutter opening time A, with the row 9 time shown beside it; do not block. (2) Safety check of gas, electricity and fire T; a No needs the fault detail. (3) Opening float: fixed A from row 1, counted C, difference A. (4) Expense box: cash C plus receipts A equals the fixed amount of row 2, match T/A. (5) Fridge and chiller check: one row per cold unit from row 13, four ticks each (sound, leakage, cold, door seal) T, fault text. (6) Temperature: one reading per unit C, inside or outside the set range from row 13 A. (7) Product condition: T no fault, or the fault text. (8) Expired items on the display: T No, or Yes with removed T and management told T. (9) Key holders for shutter, drawer, store-room L (staff list). (10) Duty split for cleaning, display, order board, cash L. (11) Daily routine, five ticks T: packaging stock, pest control, cobwebs, tray rotation, lights and branding. (12) Opened by P and time A; T all mandatory boxes filled.
Section B, goods receipt, 4 rows with Add row. Challan number E from 03-1; time A; from where L (factory, godown, other branch, supplier, outside sourcing, Other); for supplier or outside sourcing goods the price and the supplier's signature are mandatory (price is never verbal): price C, T signed on the paper challan; written on the challan C; counted C; shortage or damage A; production date; tag colour A; two signatures P and P, two different logins. This count is not blind because the challan is in the receiver's hand; write this as an open question in BUILD-LOG.
Section C, mid-day, 8 rows. Cleaning for morning, noon and night: doer P and checker P, two different logins. Display arrangement, oldest in front (FIFO), at opening T and after a big sale T. Goods moved out of sun or heat: time A, reason text. Second temperature on a busy day: readings C and time A, required only when the day type is busy. Pre-parcel quality check T with defect text. Daily expenses E from 10-2: voucher numbers, heads, amounts, receipt ticks; total A; T nothing was taken from the drawer. Break and shift handover: number of handovers C; register serial from and to (E from 11-1 when built); T each is written in the register. Store-room locked T.
Section D, pending orders. Orders taken today C (E from 20-1 when built), form numbers from and to; delivered today C; left for tomorrow C; advance taken today C; T board and Customer Order Form book reconciled; T all of today's orders wiped from the board. Delivered orders: order numbers; T the advance adjustment equals the sum of those orders' advances.
Section E, sales and cash closing.
  Category sales C for sweets, cake, jalebi, doi, bakery, ice cream, drinks, others, plus one blank category the owner can name. The categories are a list with add rule approval, seeded with these. Total sales A. T/A category total equals total sales (checklist step 3). Of which online C, and party and wholesale cash C with invoice number.
  Digital C: bKash, Nagad, card, bank, one more; total digital A; T seen on the business phone or machine; T no transaction on a personal number. If the last is not ticked, raise an exception.
  Adjustments: opening float A (row 1); earlier dues collected C (E from 20-4 and 20-5 when built); new order advance (from Section D); minus advance adjusted (from Section D); discounts: count and amount E from 20-2; cancelled sales C; minus refund E from 20-3 with register number; minus credit sale today E from 20-4 with invoice number; minus cash sent to the hub in the day E from 10-1 with memo number; plus or minus rounding C.
  Goods against money: retail sales worked out from goods = the stock ledger's sales for the day times the price list, party goods excluded, typed C (the stock ledger is a printed paper); retail sales A = total sales minus party and wholesale; difference A; inside or outside T/A against row 5; outside puts a line on the work list as an exception.
  Expected drawer balance A = opening float + total sales - digital + earlier dues collected + new advance - advance adjusted - refund - credit sale today - cash sent to the hub in the day +/- rounding. It is BLIND: the server computes it and withholds it until both counts below are saved.
  Note count C for 1000, 500, 200, 100, 50, 20, 10, 5, 2, 1 and coins; counted total A. First count signed P. Second count by the witness, a different login: second total C and signature P; if the two totals differ, the sheet shows the difference and cannot be submitted until a reason is written.
  Short or Over A = counted total minus expected, written even when zero, with a reason text. Compare with row 4: beyond it raises an exception.
  Change left for tomorrow C. Deposit to the hub A = counted total minus change left. Cash Handover Slip number E from 10-1, T counterfoil is in the book, carrier, time. Received at the hub by P and time; Cash and Bank Ledger date and line number typed.
Section F, closing stock. Four product groups (sweets, cake, jalebi and doi, bakery and others): kept for tomorrow, quantity and colour C; removed because expired or near expiry, quantity and amount C; wastage, quantity C, reason L (the wastage classes of row 16, add rule approval), approver P who is not the enterer; returned to the factory with challan number E from 03-1. T expired goods kept apart. Goods issued without a sale: own use and gifts by management (product, quantity, value, received by P); staff credit (text and the Staff Advance Register page number); business gift or sample (text and approver P).
Section G, tomorrow's demand. Lines: item code L (Items and prices), product A, demand tonight C, received next morning C, difference A, remark; boxes, bags, packets C; direct purchases (drinks, water, ice cream, other) with Purchase Requisition number typed; T demand sent.
Section H, closing checklist, 16 steps, every one T and mandatory. 1 Night stock-ledger count, goods first, then cash. 2 Order board and Customer Order Form book reconciled. 3 Category total equals total sales (A, cannot be ticked while it differs). 4 Expected balance worked out (A, ticked by the engine after both counts are saved). 5 Cash counted note by note. 6 Witness's second count. 7 Short or Over and its reason written. 8 Cash Handover Slip made and its number on this sheet, counterfoil in the book. 9 Kept, removed and wastage written. 10 Expired goods kept apart. 11 Another person approved the wastage. 12 Tomorrow's demand sent. 13 Fridge and chiller on, final temperature C, all other equipment off. 14 Cleaned before closing, checked by another person (P). 15 Gas, electricity, fire: off or safe, three ticks. 16 Cash was never left alone and unprotected T; key given to L; shutter closed at time A. The sheet cannot be submitted until all 16 are ticked.
Section I, exceptions, incidents, repairs. Free lines, each: what happened, cause, who is responsible, action taken, solved T, urgent or routine T; a repair of a machine links a 08-1 number (typed until 08-1 exists). If nothing happened the person must write "none". A line becomes an exception and appears in Needs you. Where the paper has no box for a limit (row 6 large single sale), use these lines for the note.
Signatures: manager P (prepared by), second signature P (backup manager or witness, a different login), hub receiver P (at the hub, a different person again).
Print: page 1 and page 2 (closing) in the paper's order with the serial. Page 2 goes to the hub with the cash, as the paper does today.

E. 20-2 DISCOUNT APPROVAL SLIP. Used when a discount is above the set limit.
Header: place A, date A, time A, Daily Showroom Sheet number E or typed, order or memo number (optional), slip number A from the serial book.
Lines: serial A; item code L; description A; quantity C; list price A from the price list; discount C; selling price A; total A.
Reason L, one of: old customer, bulk quantity, product condition, other (text). T approved offer with the Marketing Expense Register line number (typed until 18-1 is in App at this place).
T within the set limit, no approval needed; or T above the limit, approval taken. The limit is row 7f (the discount value) via getLimit. Above the limit: the approver P is a different person from the seller, with time A. Or T phone approval, to be signed later; it stays open as an exception until the approver signs.
Signatures: seller P, approver P, shop manager P.
The selling price after the discount is what goes into the day's sales. The slip's total discount and count flow to 14-1 Section E as E; the closing note shows the total discount.
Ask in BUILD-LOG: is the row 7f limit per slip, per line, per percent, or per day? Do not choose.

F. COMPARISON PAIR. Do not create one. Write candidate pairs for part 7 in BUILD-LOG, for example the expected drawer balance on the paper against the app's.

G. CHECKS on a phone, with a test showroom on Parallel for part 7 and part 8, then once on Paper:
 1. Fill a whole day, sections A to I, signed by three different logins.
 2. An expense voucher made at 11:00 shows in Section C by itself with its total.
 3. A 20-2 slip shows in Section E discounts by itself; a 10-1 slip shows its number in Section E.
 4. The expected drawer balance is not in the network response until both counts are saved.
 5. Short or Over of zero is stored as 0, not left empty.
 6. Category total different from total sales blocks step 3 and Submit.
 7. 15 of 16 steps ticked cannot Submit, from the screen and from the server.
 8. Cleaning doer equal to checker, wastage approver equal to enterer, second count equal to first count person: each is refused.
 9. A blank row 1, 2, 4 or 5 blocks only its tick and names the row.
 10. Airplane mode: the whole sheet saves as Not sent yet and sends once on reconnect.
 11. Print page 2; print again and it says Copy.
 12. With the place on Paper, entry is refused by the server; the live previous-layout 14-1 still opens.
 13. 20-2: a discount within row 7f needs no approver; above it needs one who is not the seller; phone approval stays open.
```

Done when 14-1 and 20-2 exist as data on the engine, Event fields read their sources, the live 14-1 is untouched, and the thirteen checks pass.

## Command 11: the template for the other 34 forms (turns 1, 4, 5, 6, 7)

After Command 10, 8 of the 42 forms exist: 0-1 (Command 6), 10-1 to 10-4 and 18-1 (Command 9), 14-1 and 20-2 (Command 10). The other 34 use one template: 2 master-data cards from turn 1 (05-2, 05-3), 10 forms of turn 4, 3 of turn 5, 16 of turn 6, and 3 report forms that have no turn. Paste the template once per form, changing only the form code on the first line. Never put two forms in one paste.

```text
TASK: Command 11 for form <FORM_CODE>. Replace <FORM_CODE> with one code from the register, for example 04-1. Follow docs/BUILD-RULES.md. Command 8 must be finished, and so must any form this one reads from, as listed in step 4.

1. READ THE PAPER. Open the page for this form in the Build Kit file ("ফরম <FORM_CODE>") and the rows of the Owner's Guidebook that name it. Write docs/forms/<FORM_CODE>.md with a table of every box in the paper's order: section letter, exact Bangla label, English label, kind (E event, A auto, C count, T tick, P pin, L list, plain input), mandatory (the paper's dot), list and its add rule, limit row of the Location Settings Sheet, source form, blind pair, evidence (photo, reason, none), and which kinds of place it applies to. Under the table list every rule sentence printed on the form as S1, S2 and so on, each with the server check that enforces it. Also write how many copies the paper has and who keeps which.

2. NEVER GUESS. If the kind of a box is unclear, use the safer one (a typed input or a tick) and write the question in docs/BUILD-LOG.md. Never invent a limit, a code, a price, a role, a date or a list option that the paper does not print. A list gets the paper's printed options plus Other.

3. BUILD AS DATA on the Command 8 engine: form_defs, form_fields, lists and options (each with an add rule), serial book per place with the first paper number left blank, permission keys for the owner only (the owner chooses roles later), dictionary keys with bn and en, the register row with the version shown. Write code only for a calculation the paper prints, and test each calculation with the numbers the paper's own formula gives. Every spending or counting field calls getLimit; BLANK blocks its tick.

4. SOURCES. For each E field name the source form or quick action and whether it is built. If it is not built, the field is typed with source_pending = true (Command 10, part B). Then do the reverse: find every field in the forms already built that is source_pending and whose source is THIS form, and switch it to E as a data change. Older entries keep what was typed. Write the list of switched fields in BUILD-LOG.

5. STATE. This form's part is Paper at every place. Building does not change any place's state. Only the owner moves a part, from the Rollout board.

6. DONE LINES. The form is done only when each of these is true: the register row and version exist; every list field stores an option id and has Add new and Other; every field has exactly one kind; place, staff ID and time are filled by the server; every spending field checks its limit; evidence is required where the paper says so; Submit goes draft, submitted, waiting_approval, approved, and approved is locked with Request a change; two signatures are two different logins; permissions are enforced on the server and scoped to the place; every label is a dictionary key in both languages; an offline Submit shows Not sent yet and sends once; every create, submit, approve, lock, change and print writes a change log line; the part state is respected (Paper refuses entry, Parallel flags it, App is normal); a place the form does not apply to simply does not offer it, and nothing is removed.

7. CHECKS on a phone with a test showroom and a test hub: the eight standard checks of Command 8, one check per server rule S1, S2 and so on from the table, and one check that the quick actions or forms that should fill this form do so without retyping. Write the results in docs/BUILD-LOG.md.

8. REPLY with five lines only: fields built, lists created, rules enforced, fields switched to event in other forms, and the questions left for the owner.

TURN NOTES. Use them to choose the next form. They are reminders from the register and the Guidebook, not a replacement for reading the paper.
Turn 1, still open: 05-2 Product Spec Card and 05-3 Recipe Card. They are master data. Each product on them uses the item code from Items and prices; do not create a second item list.
Turn 4, buying, receiving, stock (10 forms), suggested order: 03-1 Transfer Challan, 04-1 Goods Received Note, 04-2 Material Issue Slip, 04-3 Stock Count Sheet, 04-4 Store Ledger, 06-1 Purchase Requisition, 06-2 Comparative Statement, 06-3 Purchase Order, 06-4 Bill Check and Payment Request, 06-5 Supplier Ledger. Notes: 03-1 feeds 14-1 Sections B and F. The count in 04-3 is blind and checks the difference row 29 of the Location Settings Sheet. A comparison of quotations is mandatory above row 28. 06-3 must stay inside getPurchaseBudget (Command 9); a purchase order beyond it is refused and raises an exception. 06-4 compares the bill with the order and the goods received note, the three-way match. 04-4 and 06-5 are ledgers: build them as views over the entries of the forms that feed them, never as a second place to type.
Turn 5, production (3 forms): 05-1 Factory Daily Sheet, 05-4 Yield Test Sheet, 14-2 Jalebi Counter Daily Record. Notes: rows 17 to 21, 30 and 31 of the Location Settings Sheet (milk price, chhana rate, shortfall, yield difference, jalebi difference, scale check, oil change). The milk and chhana ledger and the production report are printed papers with no code; they stay on paper.
Turn 6, customers, orders, people, assets (16 forms): 20-1 Customer Order Form, 20-3 Return and Complaint Register, 20-4 Party and Wholesale Invoice, 20-5 Party and Wholesale Ledger, 20-6 Online and Delivery Ledger, 10-5 Receivable and Advance Reconciliation; 02-1 to 02-8 people; 08-1 Maintenance Request; 11-1 Shift Handover Register. Notes: 20-1 uses rows 7a to 7c (days kept, unclaimed advance, late deduction). Online and delivery use rows 23 to 26. 02-4 Appointment Letter and 02-6 Exit Clearance are documents more than registers: ask the owner whether each is a record with a print, then build it. When 20-1, 20-3, 20-4, 11-1 and 08-1 are built, step 4 switches the matching 14-1 fields to event.
Turn 7, costing: the Guidebook says it has no paper yet. Build nothing. Ask the owner for the paper first.
No turn: 01-1 Weekly Review Note, 01-2 Monthly P&L and KPI Sheet, 05-5 New Product Decision Sheet come with the reports. Build only when the owner names one.
```

Done for one form when its table, lists, rules, switched fields and checks are in docs/forms/ and BUILD-LOG, and the five-line reply names the questions left.

## Open questions the commands cannot answer

The commands never guess these. Each command stops and asks when it reaches one. You can answer them early by sending them back to me together with the Command 0 audit report.

| # | Question | Commands it changes |
| --- | --- | --- |
| 1 | The audit report: what stack the app uses, where the PIN is checked, whether permissions are enforced on the server, how Category and Unit are stored today, and which of the 42 forms the live app already holds. The design notes assume only 14-1 is built (with Entry and Approve) and 14-2, 08-1, 01-1, 01-2 and 0-1 show as Soon. | 1 to 10 |
| 2 | Each of the seven places: its code today and its status. Is the "sweet factory" in the Guidebook's first round the main factory at Islamia? Should the Mujgunni Sweets Factory, where production has stopped and the equipment is kept, be seeded as paused? | 1, 5, 6 |
| 3 | Which place carries the hub functions (the Guidebook points to Islamia Main). | 1, 6, 9 |
| 4 | The add rule of each list (open, approval or owner only). The starting rules in Command 1 are proposals. | 1, 2 |
| 5 | Which role may enter and which may approve each form. The commands create owner-only keys and do not guess. | 8 to 11 |
| 6 | Who proposes and who decides a move from Paper to Parallel to App. The commands assume head management proposes and the owner decides. | 7 |
| 7 | The two numbers compared each day in Parallel, for each of the 15 parts. The commands create none; they list candidates in BUILD-LOG. | 7, 9, 10 |
| 8 | What happens if a part must go back from App to Paper. The design proposes a way; the Guidebook does not say. | 7 |
| 9 | New places under Model B (franchise) or Model C (funded) are undecided. Commands 1 and 5 build Model A fully and keep B and C as placeholders. | 1, 5 |
| 10 | The 25-category dictionary file Command 3 needs, and the unit of Doi (kg, piece or pot). | 3 |
| 11 | 10-3: which pair is the "difference" on the paper, shop paper against statement, or statement less charge against bank deposit. | 9 |
| 12 | 20-2: is the limit in row 7f per slip, per line, a percent, or per day. | 10 |
| 13 | 14-1 Section B: should the goods count be blind, given the challan is in the receiver's hand. | 10 |
| 14 | Should the night page of 14-1 print from the app on the paper's layout, or should the paper book stay the only printed copy until part 7 is App at every place. | 8, 10 |
| 15 | Are the exceptions the app raises the same thing as the printed Work list (part 14), or two separate lists. | 8, 9, 10 |
| 16 | 02-4 Appointment Letter and 02-6 Exit Clearance: records with a print, or documents. | 11 |
| 17 | The first paper serial number of each book at each place, written by the person who holds the book. Never invented. | 8 to 11 |
| 18 | The new Bangla screen words (for example Planned, Setting up, Pilot, Request a new one, Needs naming) are drafts. A staff member who uses the screens should read them before they go live. | 2 to 11 |

What these commands do not contain, on purpose: colours, icons, spacing, screens' look, illustrations. They are in the separate design pack and are applied after the functions pass their checks.
