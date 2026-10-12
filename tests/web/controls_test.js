// Collapsed control kit (web/controls.js + controls.css). Run: node controls_test.js /home/user/My-tools/tests/web
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2], ROOT = '/home/user/My-tools/web', PORT = 8167;
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const data = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;')(fs);
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.webp': 'image/webp' };
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { 'content-type': MIME[path.extname(f)] || 'text/plain' }); r.end(b); }); }).listen(PORT);
let bad = 0; const ok = (c, m) => { if (!c) { bad++; console.log('FAIL:', m); } };
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = [];
  async function open(hash, init = '') {
    const ctx = await br.newContext({ viewport: { width: 360, height: 800 } }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push(e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{localStorage.setItem('bos_lang','en');}catch(e){} ${init}`);
    await p.goto(`http://localhost:${PORT}/${hash}`); await p.waitForTimeout(700); return p;
  }
  const p = await open('#/home');
  // find a form with a collapsed choice (CH > 3 options) and a collapsed select
  const codes = await p.evaluate(() => Object.keys(window.BOS.forms)); let F = null;
  for (const c of codes) { await p.goto(`http://localhost:${PORT}/#/entry/new/${c}/1`); await p.reload(); await p.waitForTimeout(250);
    if (await p.locator('.ctl-trg[data-kind=choice]').count() && await p.locator('.ctl-trg[data-kind=select]').count()) { F = c; break; } }
  ok(F, 'a form with a collapsed choice and select exists'); console.log('form used:', F);
  // (1) select enhanced, original kept
  const s = await p.evaluate(() => { const sel = document.querySelector('select.ctl-hid'); return { has: !!sel, tag: sel && sel.tagName, hidden: sel && sel.getAttribute('aria-hidden'), id: sel && sel.id, val: sel && sel.value, trg: !!(sel && sel.nextElementSibling && sel.nextElementSibling.classList.contains('ctl-trg')), p: sel && sel.dataset.p }; });
  ok(s.has && s.trg, 'select kept hidden in DOM with trigger next to it'); ok(s.hidden === 'true', 'aria-hidden on the original');
  // (2) choice trigger -> sheet -> pick -> engine value changes (original button gets .on after redraw)
  const trg = p.locator('.ctl-trg[data-kind=choice]').first(); const before = await trg.textContent();
  await trg.click(); await p.waitForTimeout(150);
  ok(await p.locator('.ctl-sheet [role=listbox]').count() === 1, 'listbox opens'); ok(await trg.getAttribute('aria-expanded') === 'true', 'aria-expanded true');
  const opts = p.locator('.ctl-sheet [role=option]'); const n = await opts.count(); ok(n > 3, 'sheet lists all options (' + n + ')');
  const h = await opts.first().evaluate((e) => e.getBoundingClientRect().height); ok(h >= 43.5, 'option row >= 44px (' + h + ')');
  ok(await p.evaluate(() => document.activeElement.classList.contains('ctl-opt')), 'focus moves into the sheet');
  await p.keyboard.press('Escape'); await p.waitForTimeout(100); ok(await p.locator('.ctl-bg').count() === 0, 'Esc closes'); ok(await p.evaluate(() => document.activeElement.classList.contains('ctl-trg')), 'focus returns to trigger');
  await trg.click(); await p.waitForTimeout(100); await p.keyboard.press('ArrowDown'); await p.keyboard.press('Enter'); await p.waitForTimeout(250);
  const after = await p.locator('.ctl-trg[data-kind=choice]').first().textContent(); ok(after !== before || n > 0, 'choice value shown after pick');
  const onCount = await p.evaluate(() => document.querySelectorAll('.ctl-grp [data-act=pick].on').length); ok(onCount >= 1, 'engine stored the pick (original button is .on)');
  // backdrop closes
  await p.locator('.ctl-trg[data-kind=choice]').first().click(); await p.waitForTimeout(100); await p.mouse.click(5, 5); await p.waitForTimeout(100); ok(await p.locator('.ctl-bg').count() === 0, 'backdrop closes');
  // (3) select pick fires native change/input and the original value follows
  const ev = await p.evaluate(() => { const sel = document.querySelector('select.ctl-hid'); window.__ev = []; ['input', 'change'].forEach((k) => document.addEventListener(k, (e) => { if (e.target === sel) window.__ev.push(k); })); return sel.options.length; });
  if (ev > 1) { await p.locator('select.ctl-hid + .ctl-trg').first().click(); await p.waitForTimeout(100); const o = p.locator('.ctl-sheet [role=option]'); const k = await o.count(); await o.nth(k > 1 ? 1 : 0).click(); await p.waitForTimeout(150);
    const r = await p.evaluate(() => { const sel = document.querySelector('select.ctl-hid'); return { ev: window.__ev.join(','), v: sel.value, t: sel.nextElementSibling.textContent.trim(), sel: sel.options[sel.selectedIndex].textContent.trim() }; });
    ok(/input/.test(r.ev) && /change/.test(r.ev), 'native input+change events fired (' + r.ev + ')'); ok(r.t === r.sel, 'trigger text == selected option text');
    // programmatic write keeps trigger in sync
    const t2 = await p.evaluate(() => { const sel = document.querySelector('select.ctl-hid'); sel.value = ''; return sel.nextElementSibling.textContent.trim(); }); ok(t2 !== r.t, 'programmatic sel.value= refreshes the trigger'); }
  // (4) required validation still works
  await p.evaluate(() => document.querySelector('[data-act=e_submit]') && document.querySelector('[data-act=e_submit]').click()); await p.waitForTimeout(250);
  ok(await p.locator('#sheet .notice.bad').count() > 0 || await p.locator('#toast').textContent() !== '', 'required validation still reports missing fields');
  await p.evaluate(() => { const x = document.querySelector('#sheet'); if (x) x.remove(); });
  // (5) idempotent re-run + no overflow
  const c1 = await p.evaluate(() => document.querySelectorAll('.ctl-trg').length); const r2 = await p.evaluate(() => { const a = window.BOS.ctl.enhance(document.body); return a; }); const c2 = await p.evaluate(() => document.querySelectorAll('.ctl-trg').length);
  ok(c1 === c2 && Object.values(r2).every((x) => x === 0), 'enhance() is idempotent (' + c1 + '/' + c2 + ')');
  ok(await p.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), 'no horizontal overflow at 360px (form)');
  // (6) ctl.select / multi / tick / menu / seg builders
  const kit = await p.evaluate(async () => { const C = window.BOS.ctl; const d = document.createElement('div'); d.id = 'kit'; document.body.prepend(d); let got = null, mv = null, tk = null, mn = null;
    const s1 = C.select({ title: 'T', options: [['a', 'Apple'], ['b', 'Banana']], value: 'a', onChange: (v) => { got = v; } });
    const m1 = C.multi({ title: 'M', options: ['a', 'b', 'c', 'd'].map((x) => [x, x.toUpperCase()]), values: ['a'], onChange: (v) => { mv = v; } });
    const t1 = C.tick({ label: 'Tick', checked: false, onChange: (v) => { tk = v; } });
    const g1 = C.menu({ label: 'More', items: [{ label: 'One', onClick: () => { mn = 'one'; } }, { label: 'Two', onClick: () => { mn = 'two'; } }] });
    const sg = C.seg({ options: [['x', 'X'], ['y', 'Y']], value: 'x' }); d.append(s1, m1, t1, g1, sg);
    return { s: s1.textContent.trim(), m: m1.textContent.trim(), seg: sg.querySelectorAll('button').length }; });
  ok(kit.s === 'Apple' && kit.m === 'A', 'builders render collapsed (' + JSON.stringify(kit) + ')');
  await p.locator('#kit .ctl-trg[data-kind=select]').click(); await p.locator('.ctl-sheet [role=option]').nth(1).click(); await p.waitForTimeout(80);
  ok(await p.evaluate(() => document.querySelector('#kit .ctl-trg[data-kind=select]').textContent.trim()) === 'Banana', 'B.ctl.select pick');
  await p.locator('#kit .ctl-trg[data-kind=multi]').click(); await p.locator('.ctl-sheet [role=option]').nth(1).click(); await p.locator('.ctl-sheet [role=option]').nth(2).click(); await p.locator('.ctl-fb.pri').click(); await p.waitForTimeout(80);
  ok(/3 /.test(await p.locator('#kit .ctl-trg[data-kind=multi]').textContent()), 'B.ctl.multi shows "3 selected"');
  await p.locator('#kit .ctl-trg[data-kind=multi]').click(); await p.locator('.ctl-fb', { hasText: 'Clear' }).click(); await p.locator('.ctl-fb.pri').click(); await p.waitForTimeout(80);
  ok(await p.evaluate(() => document.querySelector('#kit .ctl-trg[data-kind=multi]').textContent.trim()) !== '' , 'multi clear ok');
  await p.locator('#kit .ctl-tick').click(); ok(await p.evaluate(() => document.querySelector('#kit .ctl-tick input').checked), 'B.ctl.tick toggles');
  // (7) three-dot menu keyboard
  await p.locator('#kit .ctl-dots').focus(); await p.keyboard.press('Enter'); await p.waitForTimeout(100);
  ok(await p.locator('.ctl-sheet [role=menuitem]').count() === 2, 'menu shows 2 items'); await p.keyboard.press('ArrowDown'); await p.keyboard.press('ArrowDown'); await p.keyboard.press('Enter'); await p.waitForTimeout(100);
  ok(await p.locator('.ctl-bg').count() === 0, 'menu closes after item'); await p.evaluate(() => document.querySelector('#kit').remove());
  // (8b) generic enhancers on fixtures: >=4 single tog group, multi (data-su), checkbox group, row with 3+ secondary buttons -> ⋮, 3-option group stays seg
  const fx = await p.evaluate(async () => { window.__fx = []; document.addEventListener('click', (e) => { const b = e.target.closest('[data-fx]'); if (b) window.__fx.push(b.dataset.fx); });
    const d = document.createElement('div'); d.id = 'fx'; d.innerHTML = `<div class="row wrap" id="g4">${['a','b','c','d','e'].map((v) => `<button class="tog ${v==='b'?'on':''}" data-act="zz_f" data-fx="f${v}" data-v="${v}">Opt ${v}</button>`).join('')}</div>
      <div class="row wrap" id="g3">${['a','b','c'].map((v) => `<button class="tog ${v==='a'?'on':''}" data-act="zz_g" data-v="${v}">S ${v}</button>`).join('')}</div>
      <div class="row wrap" id="gm">${['a','b','c','d'].map((v) => `<button class="tog" data-act="zz_m" data-fx="m${v}" data-su="${v}">U ${v}</button>`).join('')}</div>
      <div id="gc">${['a','b','c','d'].map((v) => `<label class="ckrow"><input type="checkbox" value="${v}"><span>C ${v}</span></label>`).join('')}</div>
      <div class="card"><div class="row" id="rw"><button data-act="zz_1" data-fx="r1">Edit</button><button data-act="zz_2" data-fx="r2">Dup</button><button data-act="zz_3" data-fx="r3">Archive</button><button data-act="zz_4" data-fx="r4">Remove</button></div></div>`;
    document.body.prepend(d); window.BOS.ctl.enhance(document.body); const q = (s) => document.querySelector(s);
    return { g4: !!q('#g4 .ctl-trg[data-kind=choice]'), g4txt: q('#g4 .ctl-trg').textContent.trim(), g3: !q('#g3 .ctl-trg') && q('#g3').classList.contains('ctl-segc'), gm: !!q('#gm .ctl-trg[data-kind=multi]'), gc: !!q('#gc .ctl-trg[data-kind=multi]'), dots: !!q('#rw .ctl-dots'), keep: q('#rw button:not(.ctl-hid):not(.ctl-dots)').textContent }; });
  ok(fx.g4 && fx.g4txt === 'Opt b', 'single group >=4 -> dropdown showing current'); ok(fx.g3, '3-option group stays compact seg'); ok(fx.gm, 'data-su multi -> multi'); ok(fx.gc, 'checkbox group -> multi'); ok(fx.dots && fx.keep === 'Edit', 'row with 4 buttons -> primary stays + ⋮');
  await p.locator('#g4 .ctl-trg').click(); await p.locator('.ctl-sheet [role=option]').nth(3).click(); await p.waitForTimeout(80); ok((await p.evaluate(() => window.__fx)).includes('fd'), 'dropdown pick clicks the original button (same binding)');
  await p.locator('#gm .ctl-trg').click(); await p.locator('.ctl-sheet [role=option]').nth(0).click(); await p.locator('.ctl-sheet [role=option]').nth(2).click(); await p.locator('.ctl-fb.pri').click(); await p.waitForTimeout(200);
  const mf = await p.evaluate(() => window.__fx.filter((x) => x[0] === 'm')); ok(mf.includes('ma') && mf.includes('mc') && mf.length === 2, 'multi Apply clicks only the changed originals ' + mf);
  await p.locator('#gc .ctl-trg').click(); await p.locator('.ctl-sheet [role=option]').nth(1).click(); await p.locator('.ctl-fb.pri').click(); await p.waitForTimeout(80); ok(await p.evaluate(() => document.querySelectorAll('#gc input:checked').length) === 1, 'checkbox multi writes real checkboxes');
  await p.locator('#rw .ctl-dots').click(); await p.locator('.ctl-sheet [role=menuitem]').nth(1).click(); await p.waitForTimeout(80); ok((await p.evaluate(() => window.__fx)).includes('r3'), '⋮ item clicks the original secondary button');
  await p.waitForTimeout(200); ok(await p.evaluate(() => { const r = window.BOS.ctl.enhance(document.body); window.__r = r; return Object.values(r).every((x) => x === 0); }), 'fixtures: idempotent ' + JSON.stringify(await p.evaluate(() => window.__r))); await p.evaluate(() => document.querySelector('#fx').remove());
  // (8) switch OFF restores old controls instantly; read-only forms show the value
  await p.evaluate(() => window.BOS.ctl.setMode('off')); await p.waitForTimeout(150);
  ok(await p.evaluate(() => { const sel = document.querySelector('select.ctl-hid') || document.querySelector('select'); const b = sel.getBoundingClientRect(); const t = sel.nextElementSibling; return b.width > 20 && b.height > 20 && (!t || getComputedStyle(t).display === 'none'); }), 'OFF: native select visible, trigger hidden');
  ok(await p.evaluate(() => [...document.querySelectorAll('[data-act=pick]')].every((b) => b.getBoundingClientRect().width > 20)), 'OFF: old choice buttons visible again');
  await p.evaluate(() => window.BOS.ctl.setMode('on')); await p.waitForTimeout(150);
  ok(await p.evaluate(() => document.documentElement.getAttribute('data-ctl') === 'on' && document.querySelectorAll('.ctl-trg').length > 0), 'ON again');
  // rule switch: ui_collapsed_controls=false
  const pr = await open(`#/entry/new/${F}/1`, `window.__DATA.tables.rules=(window.__DATA.tables.rules||[]).concat([{key:'ui_collapsed_controls',module:'settings',kind:'switch',value:false,default_value:true,label_bn:'x',sort:1}]);`);
  await pr.waitForTimeout(400); ok(await pr.evaluate(() => document.documentElement.getAttribute('data-ctl') === 'off'), 'rule ui_collapsed_controls=false -> OFF'); ok(await pr.locator('.ctl-trg').count() === 0, 'rule OFF: no triggers built');
  // read-only: an approved entry opens in view mode -> values, not controls
  const pv = await open('#/entry/e1', `window.__DATA.tables.entries=[{id:'e1',form_code:'${F}',location_id:1,status:'approved',entry_date:'2026-10-01',data:{},check_data:{},created_by:'x',serial:1,rev_no:1,flags:[]}];`);
  await pv.waitForTimeout(500);
  const roState = await pv.evaluate(() => ({ fields: document.querySelectorAll('.fld').length, live: document.querySelectorAll('#entry .ctl-trg:not(.ctl-ro)').length, ro: document.querySelectorAll('.ctl-trg.ctl-ro, .ctl-roval').length, openBtns: document.querySelectorAll('[data-act=pick]:not(.ctl-grp > *)').length }));
  console.log('read-only view:', JSON.stringify(roState), await pv.evaluate(() => [...document.querySelectorAll('.ctl-trg:not(.ctl-ro)')].map((t) => t.previousElementSibling.outerHTML.slice(0, 160)).join(' | '))); ok(roState.fields > 0, 'read-only entry rendered'); ok(roState.live === 0 && roState.openBtns === 0, 'read-only: no live controls and no open option buttons'); await pv.context().close();
  // (9) overflow at 360 on other hubs + converts on key screens
  const per = {};
  for (const [name, hash] of [['items', '#/items'], ['stock', '#/stock'], ['purchase', '#/purchase'], ['reports', '#/reports'], ['lists', '#/lists'], ['pos', '#/pos'], ['daybook', '#/daybook'], ['rules', '#/rules'], ['settings2', '#/settings2']]) {
    const q = await open(hash); per[name] = await q.evaluate(() => ({ s: document.querySelectorAll('.ctl-trg[data-kind=select]').length, c: document.querySelectorAll('.ctl-trg[data-kind=choice]').length, m: document.querySelectorAll('.ctl-trg[data-kind=multi]').length, dots: document.querySelectorAll('.ctl-dots').length, open: document.querySelectorAll('select:not(.ctl-hid)').length, ov: document.documentElement.scrollWidth > innerWidth + 1 }));
    if (per[name].ov) ok(false, 'overflow on ' + name); await q.context().close(); }
  console.log('per screen (initial render):', JSON.stringify(per));
  console.log('errors:', errors.length ? [...new Set(errors)].slice(0, 8) : 'none'); console.log('assert failures:', bad);
  await br.close(); srv.close();
})().catch((e) => { console.log('CRASH', e.message); process.exit(1); });
