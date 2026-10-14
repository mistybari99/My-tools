// Step C-0: artisan recipe book page (#/recipebook): pickers show id + post (never a name), book render, cost gating, steps editor (add / move / suggestion), unassigned list with
// "add a new artisan" last option, owner register (the only place a name is shown), print/share, Bangla, no horizontal overflow at 360px.
// Run: node recipebook_test.js <abs tests/web dir>     (serves ../../web of THIS checkout and injects the script tag, since web/index.html is integrated by the lead)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2];
const C = require(SP + '/s10_common.js');
const WEB = path.join(SP, '..', '..', 'web'); const OUT = process.argv[3] || SP;
const base = C.baseData(SP), PORT = 8373;
function serve(port) {
  return http.createServer((q, r) => { const u = q.url.split('?')[0]; const f = path.join(WEB, u === '/' ? 'index.html' : u);
    fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); }
      if (u === '/' || u === '/index.html') b = Buffer.from(b.toString('utf8').replace('</body>', '<script src="recipebook.js"></script></body>'));
      const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(port);
}
const srv = serve(PORT);
const BOOK = (cost) => ({ artisan: { id: 1, code: 'artisan-1', post: 'karigor', post_other: null, work_type: 'mishti', work_other: null, location_id: 1, active: true },
  with_cost: !!cost, recipes: [{ recipe_id: 'rc1', version: 2, item_id: 'x', code: 'F-001', name_bn: 'রসগোল্লা', name_en: 'Rasgulla', yield_qty: 10, yield_unit: 'kg', approved: true, approved_at: '2026-10-10T00:00:00Z', form_ref: 'CARD-7',
    lines: [{ code: 'R-001', name_bn: 'ময়দা', name_en: 'Flour', qty: 6, unit: 'kg', waste_pct: 10 }, { code: 'R-002', name_bn: 'চিনি', name_en: 'Sugar', qty: 3, unit: 'kg', waste_pct: null }],
    steps: [{ step_no: 1, step_name: 'দুধ জ্বাল', description: 'ধীর আঁচে ২০ মিনিট', minutes: 30, people: 2, fuel: 'gas', flame_note: 'কম আঁচ', equipment: 'ডেকচি', qc_note: 'সর পড়বে না', resp_post: 'karigor' },
            { step_no: 2, step_name: 'আকার দেওয়া', description: null, minutes: null, people: null, fuel: null, resp_post: 'asst_karigor' }],
    labour: { suggested_labour_hours: 1, incomplete: true } }].map((r) => cost ? Object.assign(r, { cost: { batch_cost: 440, unit_cost: 44, complete: true } }) : r) });
function mk(o = {}) {
  const data = C.mkData(base, o); const T = data.tables;
  T.items.push({ id: 'fg1', code: 'F-001', name_bn: 'রসগোল্লা', name_en: 'Rasgulla', item_type: 'finished_good', unit: 'kg', base_unit: 'kg', tracked: true, is_active: true },
               { id: 'fg2', code: 'F-002', name_bn: 'সন্দেশ', name_en: 'Sandesh', item_type: 'finished_good', unit: 'kg', base_unit: 'kg', tracked: true, is_active: true });
  T.recipes = [{ id: 'rc1', item_id: 'fg1', version: 2, active: true, approved_at: '2026-10-10T00:00:00Z', artisan_id: 1, yield_qty: 10, used_at: null, form_ref: 'CARD-7' },
               { id: 'rc2', item_id: 'fg2', version: 1, active: true, approved_at: null, artisan_id: null, yield_qty: 5, used_at: null, form_ref: null }];
  T.recipe_steps = [{ id: 1, recipe_id: 'rc2', step_no: 1, step_name: 'boil', description: 'free', minutes: 30, people: 2, fuel: 'gas', active: true }];
  T.recipe_versions = [{ seq: 1, recipe_id: 'rc2', kind: 'created', changed_at: '2026-10-09T10:00:00Z', summary: null }];
  T.profiles = [{ id: 'u1', staff_id: 'owner1', full_name: 'Owner' }, { id: 'u2', staff_id: 'fac4', full_name: 'Fac' }];
  return data;
}
const EXTRA7 = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const T = window.__DATA.tables; const M = window.__M;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const W = M.w7 = Object.assign({ err: {}, cost: true, reg: [{ id: 1, code: 'artisan-1', name: 'TYPED-NAME-1', post: 'karigor', work_type: 'mishti', location_id: 1, active: true, recipes: 1 }, { id: 2, code: 'artisan-2', name: 'TYPED-NAME-2', post: 'other', post_other: 'ice-cream maker', work_type: 'other', work_other: 'pastry', location_id: 1, active: false, recipes: 0 }],
   list: [{ id: 1, code: 'artisan-1', post: 'karigor', work_type: 'mishti', location_id: 1, active: true }, { id: 2, code: 'artisan-2', post: 'chef', work_type: 'doi', location_id: 1, active: true }] }, window.__W7 || {});
 c.rpc = async (fn, args) => {
  if (!/^(artisan_|recipe_book|recipe_unassigned|recipe_steps_save|recipe_approve|recipe_set_artisan)/.test(fn)) return rpc(fn, args);
  M.calls.push([fn, clone(args || {})]);
  if (W.err[fn]) return { data: null, error: { message: W.err[fn], code: 'P0001' } };
  if (fn === 'artisan_list') return { data: clone(W.list), error: null };
  if (fn === 'artisan_register') return { data: clone(W.reg), error: null };
  if (fn === 'artisan_save') { W.saved = args; return { data: { id: 9, code: 'artisan-9' }, error: null }; }
  if (fn === 'artisan_set_active') return { data: null, error: null };
  if (fn === 'recipe_unassigned') return { data: T.recipes.filter((r) => !r.artisan_id).map((r) => { const i = T.items.find((x) => x.id === r.item_id); return { recipe_id: r.id, version: r.version, item_id: r.item_id, code: i.code, name_bn: i.name_bn, name_en: i.name_en }; }), error: null };
  if (fn === 'recipe_set_artisan') { const r = T.recipes.find((x) => x.id === args.p_recipe); r.artisan_id = args.p_artisan; return { data: null, error: null }; }
  if (fn === 'recipe_steps_save') return { data: { steps: args.p_steps.length }, error: null };
  if (fn === 'recipe_approve') { const r = T.recipes.find((x) => x.id === args.p_recipe); r.approved_at = '2026-10-14T00:00:00Z'; return { data: { approved: true }, error: null }; }
  if (fn === 'recipe_book') { if (W.noView) return { data: null, error: { message: 'not allowed', code: 'P0001' } }; return { data: clone(args.p_with_cost && W.cost ? W.bookCost : W.book), error: null }; }
  return { data: null, error: null }; };
 return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0, n = 0; const ok = (c, m) => { n++; if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept('test reason'));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + EXTRA7 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(mk(o))};window.__M0=${JSON.stringify(o.m || {})};window.__W7=${JSON.stringify(Object.assign({ book: BOOK(false), bookCost: BOOK(true) }, o.w || {}))};${o.owner === false ? 'window.__OWNER=false;window.__PERMS={};' : ''}try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1100); return p;
  }
  const wait = (p, t = 250) => p.waitForTimeout(t);
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => { const r = await p.evaluate(() => { const w = window.innerWidth; const out = []; document.querySelectorAll('body *').forEach((e) => { const b = e.getBoundingClientRect(); if (b.width && b.right > w + 1 && !e.closest('.sheet-bg:not(.sheet-bg *)')) out.push(e.tagName + '.' + String(e.className).slice(0, 20) + ' r=' + Math.round(b.right)); }); return { ok: document.documentElement.scrollWidth <= w + 1, sw: document.documentElement.scrollWidth, out: out.slice(0, 6) }; }); ok(r.ok, 'horizontal overflow ' + m + ' ' + JSON.stringify(r)); };

  // ---- owner: picker has id + post, never a name; book renders; no cost by default
  let p = await open({}, '#/recipebook');
  ok(await p.locator('#rb_art option').count() === 3, 'picker lists the two artisans (+ blank)');
  const optTxt = await p.locator('#rb_art').textContent();
  ok(/artisan-1/.test(optTxt) && /Artisan/.test(optTxt) && !/TYPED-NAME/.test(optTxt), 'picker shows id + post + work type, no name');
  await p.selectOption('#rb_art', '1'); await p.click('[data-act=rb_show]'); await wait(p, 400);
  let c = await calls(p, 'recipe_book'); ok(c.length === 1 && c[0].p_artisan === 1 && c[0].p_with_cost === false, 'recipe_book called without cost by default');
  const doc = await p.textContent('#rb_doc');
  ok(/F-001/.test(doc) && /Version 2/.test(doc) && /Approved 2026-10-10/.test(doc) && /CARD-7/.test(doc), 'book shows product, version, approval date, card ref');
  ok(/R-001/.test(doc) && /6 kg/.test(doc) && /10%/.test(doc) && /Data needed/.test(doc), 'ingredients with qty, unit, waste %; blank waste says Data needed');
  ok(/Step 1: /.test(doc) && /Step 2: /.test(doc) && /30 min/.test(doc) && /Gas/.test(doc), 'steps with minutes and fuel');
  ok(/Suggested labour hours: 1/.test(doc) && /only a suggestion/.test(doc) && /Incomplete/.test(doc), 'labour hours shown only as a suggestion, flagged incomplete');
  ok(!/Cost \(confidential\)|Batch cost/.test(doc), 'default view has no cost');
  ok(!/TYPED-NAME/.test(await p.textContent('body')), 'no artisan name anywhere on the book tab');
  await p.screenshot({ path: OUT + '/rb_book.png' }); await noOverflow(p, 'book');
  // cost on request (owner has the right)
  await p.check('#rb_cost'); await p.click('[data-act=rb_show]'); await wait(p, 400);
  c = await calls(p, 'recipe_book'); ok(c.length === 2 && c[1].p_with_cost === true, 'cost requested');
  ok(/Cost \(confidential\)/.test(await p.textContent('#rb_doc')) && /440/.test(await p.textContent('#rb_doc')), 'cost block shown when the server returns it');
  // share copies the text (no navigator.share in headless)
  await p.evaluate(() => { navigator.share = undefined; window.__copied = null; Object.defineProperty(navigator, 'clipboard', { value: { writeText: async (t) => { window.__copied = t; } }, configurable: true }); });
  await p.click('[data-act=rb_share]'); await wait(p, 200);
  const cp = await p.evaluate(() => window.__copied); ok(cp && /artisan-1/.test(cp) && /1\. দুধ জ্বাল/.test(cp) && !/TYPED-NAME/.test(cp), 'share text has id, steps, no name');
  await p.close();

  // ---- non-owner without cost right: no checkbox; server refusal handled
  p = await open({ owner: false, m: { grants: ['recipe_view'] } }, '#/recipebook');
  ok(await p.locator('#rb_cost').count() === 0, 'no cost checkbox without the cost right');
  ok(await p.locator('[data-act=rb_tab][data-v=reg]').count() === 0, 'no register tab without artisan_manage');
  await p.close();
  p = await open({ owner: false, m: { grants: [] }, w: { noView: true } }, '#/recipebook');
  await p.selectOption('#rb_art', '1'); await p.click('[data-act=rb_show]'); await wait(p, 400);
  ok(/Not allowed|recipe_view/.test(await p.textContent('body')) && await p.locator('#rb_doc').count() === 0, 'server refusal shows no book');
  await p.close();

  // ---- all recipes + unassigned + assign + add-new option
  p = await open({}, '#/recipebook');
  await p.click('[data-act=rb_tab][data-v=un]'); await wait(p, 200);
  ok(await p.locator('#rb_pane .card').count() === 1 && /F-002/.test(await p.textContent('#rb_pane')), 'unassigned list shows the recipe with no artisan');
  const lastOpt = await p.locator('#rb_pane select option').last().textContent(); ok(/Other: add a new artisan/.test(lastOpt), 'final dropdown option is "Other: add a new artisan"');
  await p.selectOption('#rb_pane select', '2'); await wait(p, 400);
  c = await calls(p, 'recipe_set_artisan'); ok(c.length === 1 && c[0].p_recipe === 'rc2' && c[0].p_artisan === 2, 'assigning sends recipe_set_artisan');
  ok(await p.locator('#rb_pane .card').count() === 0, 'it leaves the unassigned list');
  await p.close();
  p = await open({}, '#/recipebook'); await p.click('[data-act=rb_tab][data-v=un]'); await wait(p, 200);
  await p.selectOption('#rb_pane select', '__new'); await wait(p, 400);
  ok(await p.locator('#ra_name').count() === 1, 'owner: "add a new artisan" opens the register form'); await p.close();
  p = await open({ owner: false, m: { grants: ['recipe_manage'] } }, '#/recipebook'); await p.click('[data-act=rb_tab][data-v=un]'); await wait(p, 200);
  await p.selectOption('#rb_pane select', '__new'); await wait(p, 300);
  ok(await p.locator('#ra_name').count() === 0 && /owner adds/i.test(await p.textContent('#toast')), 'non-owner: told the owner adds a new artisan'); await p.close();

  // ---- steps editor
  p = await open({}, '#/recipebook'); await p.click('[data-act=rb_tab][data-v=all]'); await wait(p, 200);
  ok(await p.locator('#rb_pane .card').count() === 2, 'all recipes listed'); ok(await p.locator('#rb_pane .chip.warn').count() >= 1, 'unassigned/unapproved flagged');
  await p.click('#rb_pane .card:nth-child(2) [data-act=rb_open]'); await wait(p, 400);
  ok(await p.locator('.rb-stepcard').count() === 1, 'existing step loaded'); ok(/Suggested labour hours: 1/.test(await p.textContent('#rb_sug')), 'live suggestion: 30 x 2 / 60 = 1');
  await p.click('[data-act=rb_sadd]'); await wait(p, 150);
  ok(await p.locator('.rb-stepcard').count() === 2, 'Add a step adds one box');
  await p.locator('.rb-stepcard').nth(1).locator('[data-rb-f=step_name]').fill('shape');
  await p.locator('.rb-stepcard').nth(1).locator('[data-rb-f=minutes]').fill('১২'); await p.locator('.rb-stepcard').nth(1).locator('[data-rb-f=people]').fill('3'); await p.locator('.rb-stepcard').nth(1).locator('[data-rb-f=people]').dispatchEvent('change'); await wait(p, 150);
  ok(/Suggested labour hours: 1\.6/.test(await p.textContent('#rb_sug')), 'suggestion updates: (30x2 + 12x3)/60 = 1.6 (Bangla digits read)');
  await p.locator('.rb-stepcard').nth(1).locator('[data-act=rb_sup]').click(); await wait(p, 150);
  ok(await p.locator('.rb-stepcard').first().locator('[data-rb-f=step_name]').inputValue() === 'shape', 'move up swaps the order');
  await p.locator('.rb-stepcard').first().locator('[data-rb-f=fuel]').selectOption('other'); await wait(p, 150);
  ok(await p.locator('.rb-stepcard').first().locator('[data-rb-f=fuel_other]').count() === 1, 'fuel "other" shows its text box');
  await p.screenshot({ path: OUT + '/rb_steps.png' }); await noOverflow(p, 'steps editor');
  await p.click('[data-act=rb_ssave]'); await wait(p, 400);
  c = await calls(p, 'recipe_steps_save'); ok(c.length === 1 && c[0].p_steps.length === 2 && c[0].p_steps[0].step_name === 'shape' && c[0].p_steps[0].minutes === '12' && c[0].p_steps[1].step_name === 'boil', 'steps sent in the shown order, Bangla digits normalised');
  ok(typeof c[0].p_client === 'string' && c[0].p_client.length > 20, 'client id sent');
  await p.close();
  p = await open({}, '#/recipebook'); await p.click('[data-act=rb_tab][data-v=all]'); await wait(p, 200);
  await p.click('#rb_pane .card:nth-child(2) [data-act=rb_open]'); await wait(p, 300); await p.locator('[data-act=rb_sadd]').click(); await p.click('[data-act=rb_ssave]'); await wait(p, 300);
  ok(/name/i.test(await p.textContent('#toast')) && (await calls(p, 'recipe_steps_save')).length === 0, 'a step without a name is stopped in the browser');
  await p.close();
  // approved recipe: read-only steps
  p = await open({}, '#/recipebook'); await p.click('[data-act=rb_tab][data-v=all]'); await wait(p, 200);
  await p.click('#rb_pane .card:nth-child(1) [data-act=rb_open]'); await wait(p, 300);
  ok(await p.locator('[data-act=rb_ssave]').count() === 0 && await p.locator('[data-act=rb_sadd]').count() === 0 && /new version/i.test(await p.textContent('.sheet')), 'approved version: steps read-only, "make a new version"'); await p.close();
  // approval
  p = await open({ w: { err: {} } }, '#/recipebook'); await p.click('[data-act=rb_tab][data-v=all]'); await wait(p, 200);
  await p.click('#rb_pane .card:nth-child(2) [data-act=rb_open]'); await wait(p, 300); await p.click('[data-act=rb_approve]'); await wait(p, 400);
  ok((await calls(p, 'recipe_approve')).length === 1, 'approve sends recipe_approve'); await p.close();
  p = await open({ w: { err: { recipe_approve: 'self_approve_refused' } } }, '#/recipebook'); await p.click('[data-act=rb_tab][data-v=all]'); await wait(p, 200);
  await p.click('#rb_pane .card:nth-child(2) [data-act=rb_open]'); await wait(p, 300); await p.click('[data-act=rb_approve]'); await wait(p, 300);
  ok(/cannot approve/i.test(await p.textContent('#toast')), 'changer-cannot-approve is explained'); await p.close();

  // ---- register: the only place with a name
  p = await open({}, '#/recipebook'); await p.click('[data-act=rb_tab][data-v=reg]'); await wait(p, 300);
  ok(/TYPED-NAME-1/.test(await p.textContent('#rb_pane')) && /artisan-2/.test(await p.textContent('#rb_pane')), 'register shows names (owner only) and the retired artisan stays');
  await p.screenshot({ path: OUT + '/rb_register.png' }); await noOverflow(p, 'register');
  await p.click('[data-act=rb_anew]'); await wait(p, 400);
  await p.click('[data-act=rb_asave]'); await wait(p, 200); ok(/name/i.test(await p.textContent('#toast')) && (await calls(p, 'artisan_save')).length === 0, 'empty name stopped');
  await p.fill('#ra_name', 'TYPED-NAME-9'); await p.selectOption('#ra_post', 'other'); await p.fill('#ra_post_o', 'sweet maker'); await p.selectOption('#ra_work', 'doi'); await p.click('[data-act=rb_asave]'); await wait(p, 500);
  c = await calls(p, 'artisan_save'); ok(c.length === 1 && c[0].p_id === null && c[0].p_post === 'other' && c[0].p_post_other === 'sweet maker' && c[0].p_work_type === 'doi' && c[0].p_name === 'TYPED-NAME-9' && typeof c[0].p_client === 'string', 'artisan_save with the typed post, work type, client id');
  await p.click('[data-act=rb_aact][data-id="1"]'); await wait(p, 400);
  c = await calls(p, 'artisan_set_active'); ok(c.length === 1 && c[0].p_id === 1 && c[0].p_active === false && c[0].p_reason === 'test reason', 'retire sends the reason');
  await p.close();

  // ---- Bangla
  p = await open({ lang: 'bn' }, '#/recipebook');
  ok(/কারিগর/.test(await p.textContent('header.top h1')), 'Bangla title');
  await p.selectOption('#rb_art', '1'); await p.click('[data-act=rb_show]'); await wait(p, 400);
  ok(/রসগোল্লা/.test(await p.textContent('#rb_doc')) && /দুধ জ্বাল/.test(await p.textContent('#rb_doc')), 'Bangla product and step text rendered');
  const font = await p.evaluate(() => { const e = document.querySelector('#rb_doc .rb-step b'); const cs = getComputedStyle(e); const r = e.getBoundingClientRect(); return { ff: cs.fontFamily, w: Math.round(r.width), h: Math.round(r.height) }; });
  ok(font.w > 20 && font.h > 10, 'Bangla step title has a real measured box ' + JSON.stringify(font));
  await p.screenshot({ path: OUT + '/rb_bn.png' }); await noOverflow(p, 'Bangla book');
  await p.evaluate(() => { window.__printed = 0; window.print = () => { window.__printed++; }; });
  await p.click('[data-act=rb_print]'); await wait(p, 150);
  ok(await p.evaluate(() => window.__printed) === 1 && await p.locator('#rb_print').count() === 1, 'Print builds a print-only copy and calls window.print');
  await p.emulateMedia({ media: 'print' });
  const pv = await p.evaluate(() => { const d = document.querySelector('#rb_print'); const r = d.getBoundingClientRect(); return { app: getComputedStyle(document.querySelector('#app')).display, pr: getComputedStyle(d).display, h: Math.round(r.height), buttons: d.querySelectorAll('.rb-noprint').length && getComputedStyle(d.querySelector('.rb-noprint')).display }; });
  ok(pv.app === 'none' && pv.pr === 'block' && pv.h > 100 && pv.buttons === 'none', 'print view shows only the book copy, without the buttons ' + JSON.stringify(pv));
  await p.pdf({ path: OUT + '/rb_book.pdf', width: '210mm', height: '297mm' });
  ok(fs.statSync(OUT + '/rb_book.pdf').size > 3000, 'PDF of the book was produced');
  await p.close();

  await br.close();
  log('assertions:', n); log('errors:', errors.length ? errors.join(' | ') : 'none'); log('assert failures:', bad);
} catch (e) { console.log('TEST CRASH', e); } finally { srv.close(); } })();
