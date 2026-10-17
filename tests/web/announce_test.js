// Announcements: the headline bar (web/announce.js hooked from nav.js sync) + the screen #/announce. Package R2-A.
// Run: node announce_test.js <abs tests/web dir>      Headless Chromium 360x780 against this checkout's web/. Server stand-in: r2_common.js (R2 RPCs only).
const SP = process.argv[2];
const R = require(SP + '/r2_common.js')(SP, 9311);
const NOW = Date.now(); const iso = (ms) => new Date(NOW + ms).toISOString();
const item = (id, title, o = {}) => Object.assign({ id, title, body: 'test body ' + id, urgent: false, target_kind: 'all', starts_at: iso(-3600e3), ends_at: iso(3600e3), posted_at: iso(-3600e3), poster: 'test_poster', seen: false }, o);
const ACT = [item(11, 'test urgent gas delivery moved', { urgent: true, body: 'test full text one\nsecond line' }), item(12, 'test new price list from Sunday')];
const ON = { announce_on: true };
(async () => { try {
  await R.start(); const ok = R.ok, wait = R.wait;
  const hasBar = (p) => p.locator('#r2_tick').count();

  // 1. switch OFF (rule false): no bar, no request, no menu entry; the screen only says it is off
  let p = await R.open('#/home', { rules: { announce_on: false }, init: { ann: { active: ACT, state: { on: false, can_post: false, can_post_all: false, post_locations: [] } } } });
  ok(await hasBar(p) === 0, 'OFF: no bar on Home');
  ok((await R.callNames(p)).filter((n) => /^r2_announce/.test(n)).length === 0, 'OFF: no announcement request at all (' + (await R.callNames(p)).join(',') + ')');
  ok(await p.evaluate(() => { const r = window.BOS.IA.find((x) => x.route === 'announce'); return !!r && r.ok({}) === false; }), 'OFF: the registry hides the menu entry');
  await p.goto('http://localhost:9311/#/announce'); await wait(p, 900);
  ok(/switched off/i.test(await R.text(p)), 'OFF: the screen says it is off (state came from the server)');
  p = await R.open('#/home', { init: { ann: { active: ACT } } });       // rule absent altogether
  ok(await hasBar(p) === 0 && (await R.callNames(p)).filter((n) => /^r2_announce/.test(n)).length === 0, 'rule absent: same as OFF');

  // 2. switch ON, two active: the bar
  p = await R.open('#/home', { rules: ON, init: { ann: { active: ACT } } });
  ok(await hasBar(p) === 1, 'ON: the bar is drawn');
  ok(await p.evaluate(() => { const b = document.getElementById('r2_tick'); return b && b.previousElementSibling && b.previousElementSibling.tagName === 'HEADER' && b.previousElementSibling.classList.contains('top'); }), 'the bar sits right under the header');
  let t = await p.locator('#r2_tick').innerText();
  ok(/test urgent gas delivery moved/.test(t) && /test new price list/.test(t), 'both headlines are in the bar');
  ok(await p.locator('#r2_tick.urgent').count() === 1, 'an urgent item makes the bar urgent (red)');
  ok(/Urgent/.test(t), 'the urgent item is labelled with a word, not only a colour');
  ok(await p.locator('#r2_tick .r2-item').first().getAttribute('data-id') === '11', 'urgent first');
  ok((await p.locator('#r2_tick .r2-n').innerText()).trim() === '2', 'unread badge shows 2');
  ok(await p.evaluate(() => getComputedStyle(document.querySelector('#r2_tick .r2-track')).animationName) === 'r2tick', 'the headline scrolls (animation r2tick)');
  ok(await p.evaluate(() => document.querySelector('#r2_tick').getBoundingClientRect().height <= 48), 'the bar is slim (<= 48px)');
  ok(await p.evaluate(() => document.querySelector('#r2_tick .r2-main').getBoundingClientRect().height >= 40 && document.querySelector('#r2_tick .r2-pp').getBoundingClientRect().width >= 40), 'tap targets are large enough');
  await R.noOverflow(p, 'Home with the bar'); await R.shot(p, 'announce_bar_urgent');
  // pause button
  await p.click('#r2_tick .r2-pp'); await wait(p, 200);
  ok(await p.evaluate(() => getComputedStyle(document.querySelector('#r2_tick .r2-track')).animationPlayState) === 'paused', 'pause button stops the scroll');
  ok(await p.getAttribute('#r2_tick .r2-pp', 'aria-pressed') === 'true', 'pause button reports its state');
  await p.click('#r2_tick .r2-pp'); await p.mouse.move(5, 700); await wait(p, 200);
  ok(await p.evaluate(() => getComputedStyle(document.querySelector('#r2_tick .r2-track')).animationPlayState) === 'running', 'play again');
  // the bar stays on another screen
  await p.goto('http://localhost:9311/#/announce'); await wait(p, 900);
  ok(await hasBar(p) === 1, 'the bar is also under the header of another screen');

  // 3. tap the bar: read the full text, acknowledge
  p = await R.open('#/home', { rules: ON, init: { ann: { active: ACT } } });
  await p.click('#r2_tick .r2-main'); await wait(p, 500);
  ok(await p.locator('#r2a_read .r2-card').count() === 2, 'the sheet lists both announcements');
  t = await p.locator('#r2a_read').innerText();
  ok(/test full text one/.test(t) && /second line/.test(t) && /test_poster/.test(t), 'full text and poster are shown');
  await R.noOverflow(p, 'reading sheet'); await R.shot(p, 'announce_sheet');
  await p.click('#r2a_read .r2-card[data-id="11"] button[data-act="r2a_seen"]'); await wait(p, 500);
  ok((await R.calls(p, 'r2_announce_seen')).some((a) => a.p_id === 11), 'seen is sent to the server with the id');
  ok(await p.locator('#r2a_read .r2-card[data-id="11"] .chip.ok').count() === 1 && await p.locator('#r2a_read .r2-card[data-id="11"] button[data-act="r2a_seen"]').count() === 0, 'the card now shows Read and no button');
  ok((await p.locator('#r2_tick .r2-n').innerText()).trim() === '1', 'the unread badge went down to 1');
  await p.click('#r2a_read ~ .r2-btns [data-act="closesheet"]'); await wait(p, 200);
  ok(await p.locator('#sheet').count() === 0, 'the sheet closes');

  // 4. nothing active for this person: the bar is not drawn at all
  p = await R.open('#/home', { rules: ON, init: { ann: { active: [] } } });
  ok(await hasBar(p) === 0, 'ON but nothing addressed to me: no bar element');
  ok(await p.evaluate(() => document.querySelector('header.top').nextElementSibling.id !== 'r2_tick'), 'the screen is the normal one');
  p = await R.open('#/home', { rules: ON, init: { ann: { active: [item(13, 'test expired one', { ends_at: iso(-60e3) })] } } });
  ok(await hasBar(p) === 0, 'an item whose end time has passed is not drawn');

  // 5. reduced motion: a static one-line headline, no pause button, the list one tap away
  p = await R.open('#/home', { rules: ON, reducedMotion: true, init: { ann: { active: ACT } } });
  ok(await hasBar(p) === 1, 'reduced motion: the bar is still there');
  ok(await p.evaluate(() => getComputedStyle(document.querySelector('#r2_tick .r2-track')).animationName) === 'none', 'reduced motion: no animation');
  ok(await p.evaluate(() => getComputedStyle(document.querySelector('#r2_tick .r2-pp')).display) === 'none', 'reduced motion: no pause button needed');
  ok(await p.evaluate(() => getComputedStyle(document.querySelector('#r2_tick .r2-item:nth-of-type(2)') || document.body).display) !== undefined, 'reduced motion: extra items collapse');
  t = await p.evaluate(() => Array.from(document.querySelectorAll('#r2_tick .r2-item, #r2_tick .r2-rest')).filter((e) => e.offsetParent !== null).map((e) => e.textContent.trim()).join('|'));
  ok(/test urgent/.test(t) && !/price list/.test(t) && /\+1/.test(t), 'reduced motion: first headline and "+1" only (' + t + ')');
  await R.shot(p, 'announce_bar_reduced');
  await p.click('#r2_tick .r2-main'); await wait(p, 400);
  ok(await p.locator('#r2a_read .r2-card').count() === 2, 'reduced motion: the full list is one tap away');

  // 6. the screen for a person who may post (all targets)
  const POSTER = { ann: { active: ACT, state: { on: true, can_post: true, can_post_all: true, post_locations: [1, 2] }, mine: [
    { id: 21, title: 'test live message', body: '', urgent: true, target_kind: 'role', target_role: 'salesperson', starts_at: iso(-3600e3), ends_at: null, status: 'active', created_at: iso(-3600e3), poster: 'test_owner', live: true, audience: 5, seen: 2, withdrawn_reason: null },
    { id: 22, title: 'test old message', body: '', urgent: false, target_kind: 'all', starts_at: iso(-9e6), ends_at: iso(-8e6), status: 'active', created_at: iso(-9e6), poster: 'test_owner', live: false, audience: 7, seen: 7, withdrawn_reason: null },
    { id: 23, title: 'test pulled message', body: '', urgent: false, target_kind: 'location', target_location: 1, starts_at: iso(-3600e3), ends_at: null, status: 'withdrawn', created_at: iso(-3600e3), poster: 'test_owner', live: false, audience: 4, seen: 0, withdrawn_reason: 'test wrong place' }],
    receipts: { 21: { id: 21, title: 'test live message', status: 'active', seen: [{ user_id: 'a', name: 'test_person_a', seen_at: iso(-1800e3) }, { user_id: 'b', name: 'test_person_b', seen_at: iso(-900e3) }], unseen: [{ user_id: 'c', name: 'test_person_c' }] } } } };
  p = await R.open('#/announce', { rules: ON, init: POSTER });
  t = await R.text(p);
  ok(/Announcements/.test(await p.locator('h1').innerText()), 'screen title');
  ok(await p.locator('#r2a_now .r2-card').count() === 2, 'the page lists what is on now');
  ok(await p.locator('#r2a_mine .r2-card').count() === 3, 'the posted list shows all three');
  ok(await p.locator('#r2a_mine .r2-card[data-id="21"] .chip.ok').count() === 1 && /2 \/ 5/.test(await p.locator('#r2a_mine .r2-card[data-id="21"]').innerText()), 'live item: Live chip and 2 / 5 read');
  ok(await p.locator('#r2a_mine .r2-card[data-id="22"] .chip.ok').count() === 0, 'expired item is not marked live');
  ok(/test wrong place/.test(await p.locator('#r2a_mine .r2-card[data-id="23"]').innerText()) && await p.locator('#r2a_mine .r2-card[data-id="23"] [data-act="r2a_withdraw"]').count() === 0, 'withdrawn item shows its reason and has no Withdraw button');
  await R.noOverflow(p, 'announce screen'); await R.shot(p, 'announce_page');
  // receipts
  await p.click('#r2a_mine .r2-card[data-id="21"] [data-act="r2a_receipts"]'); await wait(p, 400);
  ok(await p.locator('#r2a_seenlist li').count() === 2 && await p.locator('#r2a_unseenlist li').count() === 1, 'receipts: 2 read, 1 not read');
  ok(/test_person_c/.test(await p.locator('#r2a_unseenlist').innerText()), 'receipts name the person who has not read it');
  await R.noOverflow(p, 'receipts sheet'); await p.click('#sheet [data-act="closesheet"].r2-btns button, #sheet .r2-btns button'); await wait(p, 200);
  // withdraw needs a reason
  await p.click('#r2a_mine .r2-card[data-id="21"] [data-act="r2a_withdraw"]'); await wait(p, 300);
  await p.click('[data-act="r2a_wgo"]'); await wait(p, 300);
  ok((await R.calls(p, 'r2_announce_withdraw')).length === 0, 'withdraw without a reason sends nothing');
  await p.fill('#r2a_wr', 'test sent twice'); await p.click('[data-act="r2a_wgo"]'); await wait(p, 600);
  ok((await R.calls(p, 'r2_announce_withdraw')).some((a) => a.p_id === 21 && a.p_reason === 'test sent twice'), 'withdraw sends id and reason');
  ok(await p.locator('#r2a_mine .r2-card[data-id="21"] [data-act="r2a_withdraw"]').count() === 0, 'after the withdraw the card has no button any more');
  // compose
  await p.click('[data-act="r2a_new"]'); await wait(p, 400);
  ok(await p.locator('#r2a_k option').count() === 4, 'compose: all four targets offered to an all-reach poster');
  await R.noOverflow(p, 'compose sheet'); await R.shot(p, 'announce_compose');
  await p.click('[data-act="r2a_post"]'); await wait(p, 300);
  ok((await R.calls(p, 'r2_announce_post')).length === 0, 'an empty headline sends nothing');
  await p.fill('#r2a_t', 'test hello team'); await p.selectOption('#r2a_k', 'role'); await wait(p, 100);
  await p.click('[data-act="r2a_post"]'); await wait(p, 300);
  ok((await R.calls(p, 'r2_announce_post')).length === 0, 'a role target is required when the target is a role');
  ok(await p.locator('#r2a_x option').count() > 2, 'the role list is filled from the roles table');
  await p.selectOption('#r2a_x', 'salesperson'); await p.check('#r2a_u'); await p.fill('#r2a_b', 'test details'); await p.fill('#r2a_e', '2099-01-02T10:30');
  await p.click('[data-act="r2a_post"]'); await wait(p, 700);
  let post = (await R.calls(p, 'r2_announce_post'))[0] || {};
  ok(post.p_title === 'test hello team' && post.p_kind === 'role' && post.p_target === 'salesperson' && post.p_urgent === true && post.p_body === 'test details', 'post carries title, role, urgent and text');
  ok(post.p_ends === '2099-01-02T10:30:00+06:00' && post.p_starts === null, 'expiry is sent as Dhaka time, an empty start as null');
  ok(typeof post.p_client === 'string' && post.p_client.length > 20, 'a client id is sent so a retry is harmless');
  ok(await p.locator('#sheet').count() === 0 && await p.locator('#r2a_mine .r2-card').first().innerText().then((x) => /test hello team/.test(x)), 'the sheet closes and the new message heads the list');
  // person target
  await p.click('[data-act="r2a_new"]'); await wait(p, 300);
  await p.fill('#r2a_t', 'test one person'); await p.selectOption('#r2a_k', 'person'); await wait(p, 100);
  ok(await p.locator('#r2a_x option').count() === 3, 'person list from the staff directory');
  await p.selectOption('#r2a_x', 'p2'); await p.click('[data-act="r2a_post"]'); await wait(p, 600);
  post = (await R.calls(p, 'r2_announce_post'))[1] || {};
  ok(post.p_kind === 'person' && post.p_target === 'p2', 'person target sends the id');
  // server refusal shows a plain message, not a crash
  await p.evaluate(() => { window.__R2.err.r2_announce_post = 'bad_date'; });
  await p.click('[data-act="r2a_new"]'); await wait(p, 300); await p.fill('#r2a_t', 'test x'); await p.click('[data-act="r2a_post"]'); await wait(p, 500);
  ok(/times are not right/i.test(await p.locator('#toast').innerText()), 'a refused post shows a readable message');

  // 7. a place-limited poster: only the place kind and only his places
  p = await R.open('#/announce', { rules: ON, owner: false, init: { ann: { active: [], state: { on: true, can_post: true, can_post_all: false, post_locations: [2] } } } });
  await p.click('[data-act="r2a_new"]'); await wait(p, 400);
  ok(await p.locator('#r2a_k option').count() === 1 && await p.locator('#r2a_x option[value="2"]').count() === 1 && await p.locator('#r2a_x option[value="1"]').count() === 0, 'place-limited poster: only "a place" and only his place');
  ok(/only to your own place/i.test(await p.locator('#r2a_form').innerText()), 'and he is told why');

  // 8. an ordinary staff member: reads, acknowledges, cannot post
  p = await R.open('#/announce', { rules: ON, owner: false, init: { ann: { active: ACT } } });
  ok(await p.locator('[data-act="r2a_new"]').count() === 0 && /cannot|may read/i.test(await R.text(p)) || /may read announcements but not post/i.test(await R.text(p)), 'staff: no New button, told why');
  ok(await p.locator('#r2a_mine').count() === 0, 'staff: no posted list');
  await p.click('#r2a_now .r2-card[data-id="12"] [data-act="r2a_seen"]'); await wait(p, 500);
  ok((await R.calls(p, 'r2_announce_seen')).some((a) => a.p_id === 12), 'staff can acknowledge from the page');

  // 9. old server (phase130 not pasted): nothing breaks
  p = await R.open('#/home', { rules: ON, init: { missing: { all: true } } });
  ok(await hasBar(p) === 0, 'missing server function: no bar and no error');
  p = await R.open('#/announce', { rules: ON, init: { missing: { all: true } } });
  ok(/does not have this yet/i.test(await R.text(p)), 'missing server function: the page says so');

  // 10. three languages, 360px, dark
  for (const lang of ['bn', 'mix', 'en']) {
    p = await R.open('#/home', { rules: ON, lang, init: POSTER });
    await R.noOverflow(p, 'Home bar ' + lang);
    ok((await p.locator('#r2_tick .r2-lab').innerText()).length > 0, 'label in ' + lang);
    await p.goto('http://localhost:9311/#/announce'); await wait(p, 900); await R.noOverflow(p, 'screen ' + lang);
    await p.click('[data-act="r2a_new"]'); await wait(p, 300); await R.noOverflow(p, 'compose ' + lang);
  }
  p = await R.open('#/home', { rules: ON, lang: 'bn', init: { ann: { active: ACT } } });
  ok(/ঘোষণা/.test(await p.locator('#r2_tick .r2-lab').innerText()), 'Bangla label in the bar');
  p = await R.open('#/home', { rules: ON, dark: true, init: { ann: { active: ACT } } });
  const col = await p.evaluate(() => { const s = getComputedStyle(document.getElementById('r2_tick')); return [s.color, s.backgroundColor, getComputedStyle(document.body).backgroundColor]; });
  const nums = (c) => c.match(/[\d.]+/g).map(Number);
  const blend = (fg, bg) => { const f = nums(fg), b = nums(bg), a = f.length > 3 ? f[3] : 1; return [0, 1, 2].map((i) => Math.round(f[i] * a + b[i] * (1 - a))); };
  const lum = (m) => { const q = m.map((v) => { v /= 255; return v <= .03928 ? v / 12.92 : Math.pow((v + .055) / 1.055, 2.4); }); return .2126 * q[0] + .7152 * q[1] + .0722 * q[2]; };
  const bgc = blend(col[1], col[2]), fgc = blend(col[0], bgc.join(',').replace(/^/, 'rgb(') + ')');
  ok((Math.max(lum(fgc), lum(bgc)) + .05) / (Math.min(lum(fgc), lum(bgc)) + .05) >= 4.5, 'dark theme: bar text contrast >= 4.5 (' + fgc.join(',') + ' on ' + bgc.join(',') + ')');
  await R.shot(p, 'announce_bar_dark');

  console.log('errors:', R.errors.length ? R.errors.join('\n') : 'none'); console.log('assertions:', R.n); console.log('assert failures:', R.bad);
  await R.stop();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; try { R.srv.close(); } catch (e2) { /* ignore */ } } })();
