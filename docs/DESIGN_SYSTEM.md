# Islamia BOS design system (theme layer)

Files: `web/theme.css` (loaded LAST), `web/icons3d.js` (`BOS.icon`), head script in `web/index.html` (`BOS_THEME`), `nav.js` (Theme dropdown, Sell orb). Brand is fixed: ISLAMIYA MISTY GHAR, brand red + gold/amber.

## Themes
`<html data-theme="dark|light|classic">`, plus `data-skin="1"` while a Premium theme is active.
- **Premium Dark** (default for new users): graphite surfaces, soft neumorphic shadows, amber glow, brand red.
- **Premium Light**: warm white, soft shadows, orange to brand-red accent.
- **Classic**: the previous look. Every rule that restyles an old class is scoped `html[data-skin] body ...`, so Classic = no override.
- Stored in `localStorage.bos_theme` (try/catch). First run (nothing stored) follows `prefers-color-scheme`: light -> Premium Light, otherwise Premium Dark. Control: compact dropdown in the drawer footer and the Me sheet (`[data-theme-pick]`).
- Legacy variables (`--bg --card --ink --muted --hair --ruby --gold --ok ...`) are re-pointed per theme, so old screens and other agents' CSS follow automatically.

## Tokens
| Group | Tokens |
|---|---|
| Surfaces | `--s0` base, `--s1` raised, `--s1h` raised highlight, `--s2` inset, `--s3` pressed; `--raised` gradient |
| Text | `--ink`, `--ink-2`, `--muted`, `--hair` (line), `--line` |
| Accent | `--amber`, `--amber-hi`, `--amber-a`/`--amber-a2` (alpha), `--brand`, `--brand-2`, `--on-brand`, `--grad-brand` |
| Status | `--ok --warn --bad --info` and `-bg` tints |
| Radius | `--r-1..4` = 4/8/12/18, `--r-full` |
| Border | `--bw-1/2/3` = .5/1/1.5px |
| Shadow | `--sh-1/2/3` (soft/medium/deep, outer+inner), `--sh-in` (inset) |
| Glow | `--glow` (focus/primary), `--glow-s` (small) |
| Spacing | `--sp-1..7` = 4/8/12/16/24/32/48 |
| Icon | `--ic-s/m/l` = 14/18/22 |
| Type | `--fs-body` 12.5px, `--fs-meta` 11px, `--fs-title` 13.5px, `--fs-page` 15px, line-height 1.6 (Bangla safe), no letter-spacing |
| Motion | `--dur` 150ms (0 under reduced motion), `--ease` |
| Touch | `--tap` 44px, `--tap-primary` 48px |

## Rules
- Raised (`--sh-2`) = things you can press or read as a card; inset (`--sh-in`) = fields, tracks, empty tiles, off toggles; pressed = `--s2` + `--sh-in`. Deep (`--sh-3`) only for sheets, toasts, the Sell orb.
- Radius: 4 chips-in-tables, 8 small controls, 12 buttons/cards/inputs, 18 sheets/big panels. Pills only for chips, toggles, language buttons.
- Spacing only from the scale. Touch targets >= 44px (primary 48px).
- Glow only for focus, selected, primary and the Sell action. Never for decoration. One glow per screen region.
- Text contrast >= 4.5:1, UI edges >= 3:1 where they carry meaning. Do not put meaning in colour alone (chips keep their text).
- Do not hard-code colours in screens; use tokens. Do not add letter-spacing to Bangla. Keep `class` names and `data-*` hooks (tests rely on them).
- Status chips: `.chip.draft|pending|approved|rejected|locked|paper|later` (or `data-status`).
- Loading: `.skel` / `.skel.row` skeleton rows, `button.loading` or `[aria-busy=true]` spinner. Empty: `.empty` or `[data-state=empty]`.

## 3D glass icons
`BOS.icon(key, size)` returns an inline SVG string (glass body gradient + edge + sheen, accent core, accent strokes; colours from `--i3-*` variables per theme). `BOS.icon.has(key)`. Unknown key returns `''`; nav falls back to the old icon. Classic keeps the old icons.
Keys: home box bag list cart pos dues money chart pie warn alert swap unlock lock hash users user matrix sliders gear shield rules clock download upload store pin pinset doc plus edit search filter more check close info print camera barcode calendar truck factory chef book tool stamp bell star history tag link scale menu chev sell, plus aliases (route ids such as `items`, `stock`, `recipes`, action words such as `add`, `warning`, `asset`, `supplier`) and `g:<group id>` for the 13 drawer categories.
Add an icon: add `name: { g: glassShapes, c: coreShapes, l: accentStrokes, w: strokeWidth }` to `DEF` in `icons3d.js` (32x32 box, bare shapes, no fill/stroke attributes), optionally an `ALIAS`; map a screen to it with `I3` in `ia.js`.

## Add a theme
Add a `:root[data-theme="x"]` block in `theme.css` that defines the same tokens (copy the dark block), add `x` to the lists in the head script of `index.html` and the options in `themeSel()` in `nav.js`. Premium component rules are scoped by `data-skin`, so they apply to any non-classic theme.

## Sell first
Every role that can open `#/pos` gets: a large primary Sell button first on Home (`.sellbig`), Sell as the first quick action, and a raised round glowing Sell orb in the centre of the bottom bar (`#bnav .sell`, between 2 + 2 slots; `B.ia.barSlots`). Other roles keep their top job and the plain 4-slot bar.
