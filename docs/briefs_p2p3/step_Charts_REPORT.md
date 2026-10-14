# Step Charts report (feat/charts)

Files: web/charts.js (new, no deps, inline SVG), web/index.html (script appended at end), tests/web/charts_test.js, tests/web/charts_dark.png, charts_light.png.

## API (exact contract)
- `B.charts.TYPES`: 10 `{id,label:L(bn,en,mix),icon}` in order line, area, bar, column, stacked_bar, pie, donut, treemap, gauge, bullet. `icon` is an inline `<svg>` string (currentColor).
- `B.charts.render(host, spec)` -> `{update(spec), destroy()}`. spec: type, title, series[{name,color,points[{x,y}]}], slices[{label,value,color}], value/min/max/target/ranges[{to,color}], format, unit, height, theme auto|dark|light, mini (sparkline).
- `B.charts.compatible(spec)` -> ids (series: line, area, bar, column (+stacked_bar if >=2 series); slices: bar, column, pie, donut, treemap (no pie/donut/treemap if any negative); value: gauge, bullet).
- `B.charts.convert(spec, toType)` -> new spec; one series -> slices per point, many series -> one slice per series (summed); slices -> one series; series -> gauge uses latest value, mean as target; value <-> series/slices. Round trips are lossless (original data kept as `_shape`). render() also converts a mismatched shape itself.
- Extras: `palette(theme)`, `bdFormat`, `compactFormat`, optional spec `axisFormat`, `grouping` ('bd' default lakh grouping | 'intl' | 'none'), `compact`. Add class `bch-tile` to a host for a dark/light tile background.
- Language via B.lab (falls back to English). English strings have no Bangla.

## Tests
`node tests/web/charts_test.js` (Chromium, 360px, no server): 577 checks pass. Covers 20 type/shape combos x dark+light, NaN, overflow, pie 360deg, treemap tiling, needle and bullet geometry, update/destroy listener balance, XSS, empty/zero data, convert round trips, English-only labels, palette contrast, reduced motion, tooltips, keyboard.

## Limits
- Pie/donut fold beyond 8 slices into "Other". Treemap is single-level. stacked_bar is horizontal.
- Line/area multiple series overlay (not stacked). Hidden data table is per chart; legend toggles series (not persisted).
- Contact sheet PNGs are one tall page per theme.
