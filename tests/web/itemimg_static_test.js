// Static checks for step Img (no browser): language rule, act prefix, script/ia order, SQL file tags. Run: node tests/web/itemimg_static_test.js
const fs = require('fs'), path = require('path');
const R = path.join(__dirname, '..', '..'), W = (f) => fs.readFileSync(path.join(R, 'web', f), 'utf8');
let bad = 0, n = 0; const ck = (c, m) => { n++; if (!c) { bad++; console.log('FAIL: ' + m); } };
const BN = /[ঀ-৿]/, js = W('itemimg.js');
let cnt = 0, three = 0;
for (const m of js.matchAll(/L\(\s*'((?:[^'\\]|\\.)*)'\s*,\s*'((?:[^'\\]|\\.)*)'\s*,\s*'((?:[^'\\]|\\.)*)'\s*\)/g)) { three++; if (BN.test(m[2])) { cnt++; console.log('  bangla in en: ' + m[2].slice(0, 60)); } }
ck(three >= 25 && cnt === 0, 'every L(bn,en,mix) has a 3rd argument and no Bangla in English (' + three + ' strings)');
const acts = [...js.matchAll(/data-act="([a-z_0-9]+)"/g)].map((m) => m[1]).filter((a) => /^img_/.test(a) || !/^(itemedit|lk_item|scan_itempick)$/.test(a));
ck(acts.length > 0 && acts.every((a) => /^img_/.test(a)), 'every data-act this file renders starts with img_: ' + [...new Set(acts)].join(','));
const hk = [...js.matchAll(/^\s{2}(img_[a-z_]+):/gm)].map((m) => m[1]); ck(hk.length === 5 && hk.every((k) => /^img_/.test(k)), 'five img_ handlers');
const ia = W('ia.js'); ck(ia.lastIndexOf("rec('itemimg'") > ia.lastIndexOf("rec('inboxpii'") && /rec\('itemimg'[^\n]*\n\];/.test(ia), 'ia.js rec itemimg is appended at the END of the registry');
const idx = W('index.html'); ck((idx.match(/itemimg\.js/g) || []).length === 1 && /<script src="optionsx\.js"><\/script><script src="itemimg\.js"><\/script>\s*<\/body>/.test(idx), 'index.html: itemimg.js once, last script');
const i2 = W('items2.js'); ck((i2.match(/bos103/g) || []).length === 1 && /'\.t\.jpg'/.test(i2), 'items2.js: exactly one bos103 line (thumbnail upload)');
for (const f of ['pos.js', 'stock2.js', 'purchase.js', 'recipes.js', 'scan.js', 'landed.js', 'salesx.js', 'forms_stock.js', 'app.js']) ck(!/bos103|itemimg/.test(W(f)), f + ' untouched');
ck(/rule\('item_images_mode'/.test(js) && /item_images_thumb_only/.test(js) && /item_images_cache_hours/.test(js), 'reads the three rules via B.rule');
const sql = fs.readFileSync(path.join(R, 'supabase', 'phase102.sql'), 'utf8'); ck(/items_first_image/.test(sql) && /security invoker/i.test(sql) && !/cost|price|stock/i.test(sql.split('create or replace function public.items_first_image')[1].split('revoke')[0]), 'sql RPC returns no cost/price/stock');
console.log('itemimg_static_test: ' + (n - bad) + ' pass / ' + bad + ' fail'); process.exit(bad ? 1 : 0);
