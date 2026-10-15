# Step Glass (bos109): Liquid Glass themes

Two new themes, 'Liquid Glass Light' (bn: লিকুইড গ্লাস লাইট) and 'Liquid Glass Dark' (লিকুইড গ্লাস ডার্ক), added to the existing theme system. Premium Light / Premium Dark / Classic are unchanged.

## How it plugs in
- Mechanism reused: `bos_theme` in localStorage, `<html data-theme>` + `data-skin="1"`, `window.BOS_THEME` (inline script in index.html), theme select in nav.js. Values: `glass-light`, `glass-dark`. Because `data-skin` stays set, all Premium rules in theme.css still apply and the glass file only re-points tokens and restyles on top.
- Edits (tagged `bos109`): index.html (allowed values, theme-color meta, list, `<link theme_glass.css>` + `<script theme_glass.js>` appended after controls.css), nav.js (2 `th_*` labels via L(bn,en,mix), 2 select options).
- New: `web/theme_glass.css` (every selector scoped to `html[data-theme^="glass"]`), `web/theme_glass.js` (effects level).
- Restyled: page, cards/tiles/stats/plates/POS items (gradient glass, hue washes), primary/secondary/danger buttons (glass pill: gradient, top gloss, rim, coloured glow, soft reflection), .mini, tabs/seg/ptabs, toggles (purple), chips/badges, inputs/selects/.ctl-*, tables, header, bottom bar, drawer, sheets, toast, pos bar. Dashboard classes `bch-*` / `dx_*` handled defensively (none exist yet; Home is the dashboard). Tokens: --glass-blur, --glass-fill, --glass-rim, --glass-glow, --glass-shadow, --g-* hues, --btn-*.

## Performance / safety
- Blur only on ~8 structural layers (header, bottom bar, drawer, sheets, toast, pos bar, panel/plate), never on rows/cards; guarded by `@supports`. Page gradient is a `position:fixed` pseudo-layer. No continuous animations, no will-change.
- `html[data-fx="lite"]` (solid fills, zero backdrop-filter) is set by theme_glass.js on prefers-reduced-motion, prefers-reduced-transparency, no backdrop-filter support, deviceMemory<=2 or hardwareConcurrency<=2; CSS also has a pure-CSS `@media (prefers-reduced-transparency)` and `@supports not` fallback.
- No size changes: only colours, radii (tokens), shadows. Control heights stay within 2px of Premium Light; no overflow at 320/360/412.

## Accessibility
Computed in the test: ink / ink-2 / muted / link / status chips on panel and bar over the page stops (and bars over pure black/white), all button text on both gradient stops, plus real elements. All >= 4.5:1 (worst token pair 4.57 light, 4.74 dark); focus ring >= 3:1, 3px outline.

## Tests
`tests/web/glass_test.js` (Chromium 360px; base commit exported with `git archive` to a temp dir): selection + persistence, old themes identical to base on home/pos/form for 10 elements, overflow, errors, contrast, lite fallbacks, screenshots `tests/web/glass_{home,pos,form,dash,drawer}_{light,dark}.png`. Note: low-core machines are auto-"lite", so the test forces a capable device.
