---
name: bos-organise
description: Use whenever you add, move, rename or hide a screen, menu entry, Home tile, bottom-bar slot, Control Center tile or search keyword in the Islamia BOS web app. Keeps navigation organised through the single registry web/ia.js.
---
1. Read docs/IA_RULES.md first (how to add a screen, groups, naming, row actions, states, i18n).
2. Register EVERY new or moved screen as one record in web/ia.js. Never hand-edit menu lists in nav.js, control.js or app.js; they read BOS.IA.
3. Never rename or remove an existing route (old URLs and favourites must keep working). Do not change colours, fonts or branding; this skill is structure only.
4. Reuse the existing permission checks (c.own, c.P, c.GF, c.locOk ...); the server stays the authority.
5. Add bn + English keywords, use glossary words, put essential actions outside the three-dot menu.
6. Run `node tests/web/ia_test.js /home/user/My-tools/tests/web` and the nav tests (nav, nav2, control, favsync, settings2); fix before finishing. Add a line to docs/BUILD-LOG.md.
