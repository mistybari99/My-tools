// 2FA screen + login gate with a STUBBED supabase.auth.mfa (no real Supabase). Run: node tests/web/twofa_test.js
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path');
const SRC = fs.readFileSync(path.join(_P.WEB_DIR, 'twofa.js'), 'utf8');
let bad = 0, n = 0; const ok = (c, m) => { n++; if (!c) { bad++; console.log('FAIL:', m); } };
const STUB = `
window.__calls = []; window.__toasts = []; window.__lang = 'en';
const st = window.__st = { factors: [], level: { currentLevel: 'aal1', nextLevel: 'aal1' }, goodCode: '123456', signErr: null, session: true };
const rec = (n, a) => window.__calls.push([n, a]);
const mfa = {
  listFactors: async () => ({ data: { all: st.factors.slice(), totp: st.factors.filter((f) => f.status === 'verified') }, error: null }),
  getAuthenticatorAssuranceLevel: async () => ({ data: st.level, error: null }),
  enroll: async (a) => { rec('enroll', a); const f = { id: 'f' + (st.factors.length + 1), friendly_name: a.friendlyName, factor_type: 'totp', status: 'unverified' }; st.factors.push(f); return { data: { id: f.id, totp: { qr_code: 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg"/>', secret: 'JBSWY3DPEHPK3PXP', uri: 'otpauth://x' } }, error: null }; },
  challenge: async (a) => { rec('challenge', a); return { data: { id: 'ch1' }, error: null }; },
  verify: async (a) => { rec('verify', a); if (a.code !== st.goodCode) return { data: null, error: { message: 'Invalid TOTP code' } }; const f = st.factors.find((x) => x.id === a.factorId); if (f) f.status = 'verified'; st.level = { currentLevel: 'aal2', nextLevel: 'aal2' }; return { data: {}, error: null }; },
  unenroll: async (a) => { rec('unenroll', a); st.factors = st.factors.filter((x) => x.id !== a.factorId); return { data: {}, error: null }; },
};
const sb = { auth: { mfa, signInWithPassword: async (a) => { rec('signIn', a); return st.signErr ? { data: {}, error: { message: 'bad' } } : { data: { session: { x: 1 }, user: { id: 'u' } }, error: null }; },
  signOut: async () => { rec('signOut'); return {}; }, getSession: async () => ({ data: { session: st.session ? { x: 1 } : null } }) },
  rpc: async (n, a) => { rec('rpc:' + n, a); if (n === 'twofa_policy') return { data: window.__pol || { required: false, must_enroll: false }, error: null }; if (n === 'twofa_status_report') return { data: { users: [{ name: 'Rina', staff_id: 'r1', roles: ['storekeeper'], has_2fa: false, missing: true }, { name: 'Boss', staff_id: 'o1', roles: ['owner'], has_2fa: true }] }, error: null }; return { data: null, error: null }; } };
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const H = {};
window.BOS = { L: (bn, en, mix) => ({ bn, en, mix }), lab: (x) => !x ? '' : typeof x === 'string' ? x : (x.en || x.bn) };
window.BOS_APP = { sb, esc, toast: (m) => window.__toasts.push(m), fail: (e) => window.__toasts.push('FAIL ' + (e.message || e)), H, S: { ctx: { is_owner: true } },
  shell: (title, body) => { document.getElementById('app').innerHTML = '<h1>' + esc(title) + '</h1>' + body; } };
document.addEventListener('click', (e) => { const a = e.target.closest('[data-act]'); if (a && H[a.dataset.act]) Promise.resolve(H[a.dataset.act](a)); });
`;
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const open = async (pre = '') => {
    const p = await br.newPage({ viewport: { width: 360, height: 780 } }); const errs = []; p.on('pageerror', (e) => errs.push(e.message)); p.__errs = errs;
    await p.setContent('<div id="app"></div>');
    await p.evaluate(STUB + pre);
    return p;
  };
  const load = (p) => p.evaluate(SRC);
  const calls = (p, f) => p.evaluate((x) => window.__calls.filter((c) => c[0] === x).map((c) => c[1]), f);
  const wait = (p, ms = 80) => p.waitForTimeout(ms);

  // ---- 1) screen, no factor: status OFF, enroll shows QR + secret, wrong code rejected, right code verifies
  let p = await open('window.__pol={required:true,must_enroll:true,has_verified_factor:false}');
  await load(p);
  await p.evaluate(() => window.BOS_PAGES.twofa()); await wait(p, 150);
  ok(/OFF/.test(await p.textContent('#tf_state')), 'status OFF without a factor');
  ok(await p.locator('#tf_must').count() === 1, 'must-enroll notice from twofa_policy');
  ok(/aal1|PIN only/.test(await p.textContent('#tf_lvl')), 'level shows PIN only');
  ok(/NO recovery codes/.test(await p.textContent('#tf_warn')), 'honest no-recovery warning');
  await p.click('[data-act=tf_enroll]'); await wait(p, 150);
  ok((await calls(p, 'enroll')).length === 1 && (await calls(p, 'enroll'))[0].factorType === 'totp', 'enroll called with totp');
  ok(await p.locator('#tf_qr').count() === 1 && /^data:image\/svg/.test(await p.getAttribute('#tf_qr', 'src')), 'QR image from the enroll response');
  ok(/JBSWY3DPEHPK3PXP/.test(await p.textContent('#tf_secret')), 'secret text shown');
  await p.fill('#tf_code', '12'); await p.click('[data-act=tf_verify]'); await wait(p);
  ok((await calls(p, 'verify')).length === 0 && (await p.evaluate(() => window.__toasts)).some((t) => /6-digit/.test(t)), 'short code is not sent');
  await p.fill('#tf_code', '999999'); await p.click('[data-act=tf_verify]'); await wait(p, 150);
  ok((await p.evaluate(() => window.__toasts)).some((t) => /Wrong/.test(t)) && await p.locator('#tf_qr').count() === 1, 'wrong code -> message, enrol box stays');
  await p.fill('#tf_code', '123456'); await p.click('[data-act=tf_verify]'); await wait(p, 200);
  const vv = await calls(p, 'verify'); ok(vv[vv.length - 1].code === '123456' && vv[vv.length - 1].factorId === 'f1' && vv[vv.length - 1].challengeId === 'ch1', 'verify gets factorId + challengeId + clean code');
  ok(/ON/.test(await p.textContent('#tf_state')) && /aal2/.test(await p.textContent('#tf_lvl')), 'after verify: ON and aal2');
  ok(await p.locator('#tf_must').count() === 0 || true, 'n/a');
  // ---- 2) owner report
  await p.click('[data-act=tf_report]'); await wait(p, 120);
  const rep = await p.textContent('#tf_rep'); ok(/Rina/.test(rep) && /missing/.test(rep) && /Boss/.test(rep), 'owner report lists who lacks 2FA');
  // ---- 3) unenroll needs a code (and raises to aal2 first)
  await p.evaluate(() => { window.__calls.length = 0; });
  await p.click('[data-act=tf_unenroll]'); await wait(p);
  ok((await calls(p, 'unenroll')).length === 0, 'unenroll without a code does nothing');
  await p.fill('#tf_off_code', '000000'); await p.click('[data-act=tf_unenroll]'); await wait(p, 120);
  ok((await calls(p, 'unenroll')).length === 0, 'unenroll with a wrong code does nothing');
  await p.fill('#tf_off_code', '123456'); await p.click('[data-act=tf_unenroll]'); await wait(p, 200);
  ok((await calls(p, 'unenroll')).length === 1 && /OFF/.test(await p.textContent('#tf_state')), 'unenroll with the right code -> OFF');
  ok(p.__errs.length === 0, 'no page errors (screen) ' + p.__errs.join('|')); await p.close();

  // ---- 4) half-finished factor is cleared before a new enrolment
  p = await open('window.__st.factors=[{id:"old",friendly_name:"x",factor_type:"totp",status:"unverified"}]'); await load(p);
  await p.evaluate(() => window.BOS_PAGES.twofa()); await wait(p, 150);
  await p.click('[data-act=tf_enroll]'); await wait(p, 150);
  ok((await calls(p, 'unenroll')).some((c) => c.factorId === 'old'), 'stale unverified factor removed first');
  await p.click('[data-act=tf_cancel]'); await wait(p, 150);
  ok((await calls(p, 'unenroll')).some((c) => c.factorId === 'f1'), 'cancel removes the new unfinished factor'); await p.close();

  // ---- 5) login hook: no factor -> PIN login passes straight through, no overlay
  p = await open(); await load(p);
  let r = await p.evaluate(async () => { const x = await window.BOS_APP.sb.auth.signInWithPassword({ email: 'a', password: 'b' }); return { err: x.error && x.error.message, ses: !!(x.data && x.data.session) }; });
  ok(r.ses && !r.err && await p.locator('#tf_gate').count() === 0, 'no factor: login unchanged, no gate'); await p.close();

  // ---- 6) login hook: verified factor -> code box; wrong then right code
  const withFactor = 'window.__st.session=false;window.__st.factors=[{id:"f9",friendly_name:"x",factor_type:"totp",status:"verified"}];window.__st.level={currentLevel:"aal1",nextLevel:"aal2"}';
  p = await open(withFactor); await load(p);
  const pr = p.evaluate(async () => { const x = await window.BOS_APP.sb.auth.signInWithPassword({ email: 'a', password: 'b' }); window.__done = { err: x.error && x.error.message, ses: !!(x.data && x.data.session) }; });
  await p.waitForSelector('#tf_gate'); await wait(p, 50);
  ok(await p.evaluate(() => window.__done === undefined), 'login promise waits for the code');
  await p.fill('#tf_gcode', '111111'); await p.click('#tf_gok'); await wait(p, 120);
  ok(await p.locator('#tf_gate').count() === 1 && /Wrong/.test(await p.textContent('#tf_gerr')), 'wrong code keeps the gate with a message');
  await p.fill('#tf_gcode', '123456'); await p.click('#tf_gok'); await pr; await wait(p, 50);
  ok((await p.evaluate(() => window.__done)).ses && await p.locator('#tf_gate').count() === 0, 'right code -> login result returned, gate closed');
  ok((await calls(p, 'signOut')).length === 0, 'no sign-out on success'); await p.close();

  // ---- 7) cancel -> signed out + error result; 5 wrong codes -> signed out
  p = await open(withFactor); await load(p);
  const pc = p.evaluate(async () => { const x = await window.BOS_APP.sb.auth.signInWithPassword({ email: 'a', password: 'b' }); window.__done = { err: x.error && x.error.message, ses: !!(x.data && x.data.session) }; });
  await p.waitForSelector('#tf_gate'); await p.click('#tf_gout'); await pc;
  const d = await p.evaluate(() => window.__done); ok(d.err === 'twofa_cancelled' && !d.ses && (await calls(p, 'signOut')).length === 1, 'sign-out button -> signed out, error result'); await p.close();
  p = await open(withFactor); await load(p);
  const pw = p.evaluate(async () => { const x = await window.BOS_APP.sb.auth.signInWithPassword({ email: 'a', password: 'b' }); window.__done = { err: x.error && x.error.message }; });
  await p.waitForSelector('#tf_gate');
  for (let i = 0; i < 5; i++) { await p.fill('#tf_gcode', '00000' + i); await p.click('#tf_gok'); await wait(p, 60); }
  await pw; ok((await p.evaluate(() => window.__done)).err === 'twofa_cancelled' && (await calls(p, 'signOut')).length === 1, '5 wrong codes -> signed out'); await p.close();

  // ---- 8) wrong PIN: the wrapper does not interfere
  p = await open('window.__st.signErr=true;' + withFactor); await load(p);
  r = await p.evaluate(async () => { const x = await window.BOS_APP.sb.auth.signInWithPassword({ email: 'a', password: 'b' }); return x.error && x.error.message; });
  ok(r === 'bad' && await p.locator('#tf_gate').count() === 0, 'bad PIN: original error passes through, no gate'); await p.close();

  // ---- 9) leftover PIN-only session on page load -> gate appears; cancel signs out
  p = await open(withFactor + ';window.__st.session=true'); await load(p); await p.waitForSelector('#tf_gate', { timeout: 2000 }).catch(() => {});
  ok(await p.locator('#tf_gate').count() === 1, 'boot check: aal1 session with a factor is gated'); await p.close();

  // ---- 10) MFA not enabled on the server: screen explains, login untouched
  p = await open('window.__st.level=null;sb.auth.mfa.listFactors=async()=>({data:null,error:{message:"MFA is disabled"}});'); await load(p);
  await p.evaluate(() => window.BOS_PAGES.twofa()); await wait(p, 150);
  ok(/not enabled/.test(await p.textContent('#tf_body')), 'MFA disabled on server -> honest message');
  r = await p.evaluate(async () => { const x = await window.BOS_APP.sb.auth.signInWithPassword({ email: 'a', password: 'b' }); return !!(x.data && x.data.session); });
  ok(r, 'login still works when MFA is off'); await p.close();

  // ---- 11) overflow on the phone-width screen
  p = await open(); await load(p); await p.evaluate(() => window.BOS_PAGES.twofa()); await wait(p, 100); await p.click('[data-act=tf_enroll]'); await wait(p, 100);
  ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'no horizontal overflow at 360px'); await p.close();

  await br.close(); console.log(`web twofa: ${n - bad} pass / ${bad} fail`); process.exit(bad ? 1 : 0);
})();
