# Module E registration notes (already applied by Module E itself)
1. web/ia.js: `rec('owner', 'settings', ['মালিকের বোর্ড', 'Owner mode board', 'Owner mode board'], { icon: 'control', ok: owner, kw: [...] })` (+ I3 key `owner: 'sliders'`).
2. web/index.html: `<script src="ownerboard.js"></script>` (after recipes.js, last in the list).
3. SQL supabase/phase45.sql: table owner_board_items (RLS own rows + owner only, no browser writes), owner_board_get(), owner_board_save(jsonb) (owner only, max 60, validated, switch-aware), rules key owner_board_on (default ON), user_favourites.sort/label/hidden + fav_order_set(jsonb) / fav_meta_set(text,text,text,boolean). No new grants.
4. Home: "Recent" block removed (drawer + Home); star buttons removed everywhere; ⋮ menu (nav.js) on tiles, drawer rows, header; Owner mode button next to Sell; header ⋮ toggle "Show the owner board as Home".
