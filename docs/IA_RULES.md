# IA rules: how to add or move a screen

Single source of truth: `web/ia.js` (`BOS.IA`). Drawer, Home tiles/modules, bottom bar, search, breadcrumb, category page (`#/group/<id>`), Recent and the Control Center extras all read it. Never edit a menu list by hand in nav.js / control.js.

## Add a screen
1. Register the page as usual (`window.BOS_PAGES.<route> = fn`, script tag in index.html).
2. Add ONE `rec('<route>', '<group>', label, { ... })` line in `web/ia.js`:
   - `group`: exactly one of the 13 ids (dash item stock purch factory sale cust acc appr reports people loc settings). Pick by the job the screen does, not by who may see it.
   - `label`: `'t:<i18n key>'` to reuse an existing text, or `['বাংলা', 'English', 'Mix']`. Use glossary words (i18n `gl_*`, `stv_*`, docs/IA_CONCEPT.md section 6.1). One name per screen, same in drawer, title, button.
   - `kw`: Bangla AND English synonyms people would type. `verbs`: short action phrases ("pay supplier") for the Do section. `aliases`: spellings.
   - `ok: (c) => ...`: reuse only c.own, c.P(code,'view|enter|approve'), c.GF.<grant>, c.locOk(), c.canPos(), c.anyApprove(), c.ctlOk(). Do not invent permission logic; the server decides.
   - `icon`: an existing icon key (A.ICON / nav IC). `mob` 1..3 bottom-bar priority, `mod` order on Home modules, `home: {biz|acc: n}` tile slot, `cnt` attention-count key, `cc: 'places|lists|people|rules'` Control Center extra, `drawer:false` for sub pages (search/category page only), `status: 'live|soon|hidden'`, `qa: [...]` quick actions.
3. Never rename or remove a route: old URLs and favourites (`r:<route>`) must keep working. Aliases use `alias` + `status:'hidden'`.
4. Run `node tests/web/ia_test.js <abs tests/web>` plus nav, nav2, control, favsync, settings2.

## Visibility rules (owner decisions, 21 Oct 2026)
- A main feature is visible at its proper place even when its inner switch is OFF. Never gate a menu entry on a switch alone: give it `ok: (c) => c.own || <grant> || ruleOn('x_on')`-style access so the owner and the grant holder always see it, and let the screen say "Off: turn on in Settings". (announce, todo, shifts follow this rule; no other entry is hidden by a switch.)
- Screens of other trades (variants, cheques, schemes, tinting, impexp) are gated by the business template: `otherTrade()` in `web/ia.js`, backed by `B.biz.otherTrade()` / `B.biz.hasTemplate(...)` in `web/bizctx.js`. The sweets business (template `food_manufacturing`, or no template) does not see them; routes stay registered and open by link. Gate a new other-trade screen the same way; add no other-business data or details.
- The location block in the drawer has explicit move higher / lower buttons (`loc_up`, `loc_dn` in `web/nav.js`), position kept per person on the device (`bos_locpos_<id>`), and the drawer footer opens expanded by default when the person has 2 or more places.

## Row actions
Essential actions are never only in a three-dot menu. Primary button visible; at most 2 secondary visible; ⋮ holds edit details, history, print, duplicate, void, inactivate (destructive last, with reason). Same verbs, same order in row and record menus.

## States
Use `BOS.ui.state('loading'|'empty'|'error'|'offline', msg, retry)` for the block (existing classes only; error/offline add a Try again button that re-runs the route).

## i18n
Every visible string in the three modes (বাংলা / Bng-Eng / English). Brand ISLAMIYA MISTY GHAR is never translated.

## Switch
Home v2 (Now strip, quick actions, Recent, 4-slot bottom bar, Do-search) is on unless rule `ia_home_v2` is false or this phone has `localStorage.bos_ia_home_v2 = 'off'`.
