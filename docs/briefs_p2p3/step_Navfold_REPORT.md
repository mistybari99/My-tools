# Step Navfold: collapsible drawer footer (bos101)

Files: web/nav.js (footer markup, toggle handler, one label `foot_t`, netDot also updates the slim dot), web/styles.css (end of the .dr-foot rules), tests/web/navfold_test.js, tests/web/navfold_*.png.

## যাচাই হয়েছে
- navfold_test.js (Chromium 360x740): 21 pass / 0 fail. Default collapsed; toggle has aria-expanded and a 3-language aria-label; tap target at least 40px; menu list height 373px before, 560px collapsed, 339px expanded; toggle expands and collapses; state saved in localStorage `bos_navfoot` and persists after reload (both states); language switch (bn/en) and theme select (dark/light/classic) work and the footer stays expanded after re-render; Log out works when expanded; no horizontal overflow; no page errors.
- nav2, ia, control, favsync, settings2 tests: output identical to baseline (integration code). optviews_ui: identical except the script path in a stack trace line (it fails the same way before and after).
- nav_test: identical to baseline when run with `bos_navfoot=1` pre-set in the copy. It clicks the language button in the drawer footer, which is now hidden by default (expected consequence of the collapsed default); the unmodified test would time out on that click.
- Conflict markers grep empty; node --check web/nav.js OK.

## পড়ে বোঝা
- Collapse uses grid-template-rows 0fr/1fr transition, disabled under prefers-reduced-motion; collapsed part is `inert` so it is not tabbable. .dr-body is already flex:1, so the list takes the remaining height. Slim bar shows chevron + Online dot; Online text and Log out are in the expanded part. theme.css footer background/border apply unchanged.

## যাচাই হয়নি
- Real Android Chrome device; classic/dark visual check was only by value assertion plus one light screenshot (navfold_light_after.png); RTL/very long Bangla labels; `inert` support on very old WebViews (falls back to a visually collapsed footer only).
