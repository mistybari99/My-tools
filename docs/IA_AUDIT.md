# IA audit (before) and proposed structure (now built in web/ia.js)

Scope: every hash route, who may open it, where it was reachable from BEFORE this change. No visual change; old URLs all still work.

## 1. Route inventory (before)
Legend: guard = app.js OWNER_ONLY (+ROUTE_GRANTS) or page-level check; reach: H=home tile, M=home "modules", D=drawer (old group), CC=Control Center tile, RH=reports hub link, U=URL/link inside another screen only.

| Route | File | Who (client check; server decides) | Reachable before |
|---|---|---|---|
| home | nav.js | all | H |
| items, products(alias) | items2.js | ITEMS view | H M D |
| items/new | items2.js | ITEMS enter | D, button in items |
| itemreq | app.js | ITEMS enter/approve | H M D |
| lists | lists.js | owner, list_manage | D M CC |
| settings2/units | settings2.js | owner | D |
| itemimport, itemtypes, assets | itemmaster.js | owner / locOk | D (assets, itemimport also M) |
| itemmap, bulkitems | bulkitems.js | owner, item_create / item_bulk / ITEMS enter | D only |
| stock, recipes | stock2.js, recipes.js | locOk | D ("stock & factory" mixed group), stock H |
| purchase, purchase/new, purchase/return, payables | purchase.js | locOk | D (one-item "Suppliers" group for payables) |
| pos, salereturn | pos.js, salereturn.js | POS view/enter | H M D |
| dues | dues.js | POS view/enter | H M D |
| invoice | invoice.js | owner | D (under Settings) |
| daybook, salary | daybook.js, salary.js | owner / view_daybook, salary_view | D, RH |
| brandpnl, discounts | reports.js | owner / POS approve | RH only |
| ledgerlinks | forms_stock.js | owner (others: only when problems exist) | RH only |
| reports, report/<key> | reports.js | all (per report grant) | H M D |
| biz | biz.js | owner / POS approve | H M D |
| exceptions, pending, numaudit | entry.js, dash.js | any approver | H M D |
| releases, emergency | entry.js, rules.js | owner | H M D |
| changes, outbox | rollout.js | owner/change_approve; all | D, home Now rows |
| staff, matrix, rules, rulehub, settings, logs, backup | app.js, rules.js | owner | D, M (some), rulehub "More" tab |
| settings2 (+11 sub pages fiscal, vat, barcode, noperm, stock, disc, units, shelf, suppliers, access, fav) | settings2.js | owner | D (hub only), subpages via hub cards |
| locations, locset, locsheet | locations.js, entry.js | owner / location_manage / head_management / settings_approve | D CC (locsheet U) |
| control | control.js | owner or any control grant | H D |
| rollout | rollout.js | owner / rollout_manage | D; Control Center tile was "Soon" although built |
| form/<code>, entry/new/<code> | entry.js + forms*.js | per form grant | D (form groups), H sheets |

## 2. Problems found
| # | Problem | Fix |
|---|---|---|
| 1 | Hand-kept lists in 6 places (nav ROUTES, tileDefs, drawMods order, Control TILES, AREA_G, search) drift apart | one registry `BOS.IA` (web/ia.js) |
| 2 | "ops" mixed stock, factory, assets, change requests, outbox; "supp" held one screen; "settings" held Locations + Rollout + Control | 13 categories |
| 3 | Control Center "Rollout board" tile shown as Soon though #/rollout is built | tile opens #/rollout |
| 4 | brandpnl, discounts, ledgerlinks only via the reports hub; bulkitems/itemmap only in drawer | each has a category home, Control Center extras, group page, search |
| 5 | Same screen under different names (itemreq "Item change request" vs tile "Item requests"; payables "Supplier payables" vs "Payables due") | one label per record |
| 6 | Mixed bn/mix/en labels in the drawer (G_ labels "Item", "Customer"...) | every label is a 3-language L() |
| 7 | Breadcrumb missing everywhere; many screens have no back arrow | `Category › Screen` line from shell(); category page `#/group/<id>` |
| 8 | Drawer search only matched the label text | keywords (Bangla + English), ranked, sections Do / Go / Settings / Items / Customers, category line under each result |
| 9 | Lock mode listed every locked route (22 rows for a cashier) | only core screens listed one by one, the rest as one summary line |
| 10 | Guard split: OWNER_ONLY set in app.js vs ctlOk()/GF in nav.js (two truths) | not changed (server is the authority); ia.js reuses nav.js predicates, route guard unchanged. Remaining: ROUTE_GRANTS lacks rollout/changes/daybook (these pages check inside) |
| 11 | Loading / empty / error states differ per screen | `BOS.ui.state(kind,msg,retry)` used on category page, search, Control Center; other screens not converted (see limits) |
| 12 | ⋮ menus | sampled all 12 files using ⋮: row menus carry secondary verbs (edit, history, void). The only one-action ⋮ is the void-return button in salereturn.js (a destructive secondary action: acceptable). No essential action found only in ⋮ on screens that were touched; none of those screens were touched |

## 3. Proposed IA (built)
Each route has exactly one primary category; "also" quick links: itemreq (also Items), discounts (also Sales).

| Category (id) | Routes |
|---|---|
| Dashboard (dash) | home |
| Items & Master Data (item) | items, items/new, lists, settings2/units, itemimport, itemmap, bulkitems, itemtypes, products(alias) |
| Inventory & Stock (stock) | stock, assets, + forms of areas stock, assets |
| Purchasing & Suppliers (purch) | purchase, purchase/new, purchase/return, payables, settings2/suppliers, forms area purchase |
| Factory & Production (factory) | recipes, forms area factory |
| Sales & POS (sale) | pos, salereturn, forms areas sales, showroom |
| Customers, Orders & Invoices (cust) | dues, invoice |
| Accounting & Finance (acc) | daybook, ledgerlinks, forms area cash |
| Approvals & Exceptions (appr) | exceptions, pending, itemreq, releases, emergency, changes, numaudit, outbox |
| Reports & Analytics (reports) | reports, report(alias), biz, brandpnl, discounts, forms area owner |
| Staff, Roles & Permissions (people) | staff, matrix, salary, forms area staff |
| Locations (loc) | locations, locset, locsheet, rollout |
| Administration & Settings (settings) | control, rulehub, rules, settings, settings2 (+9 sub pages), logs, backup |
