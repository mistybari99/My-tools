// Proof of the web hooks of CRM-C on a scratch copy of the repo: copies tests/web and web into a temp folder, applies the hook text (crmc_hooks.js), then runs the navigation suites there
// (ia, nav, nav2, control, favsync, settings2) and the CRM-C suite. The real repo files are not touched.
// Run: node crmc_hooks_run.js <abs tests/web dir>
const fs = require('fs'), os = require('os'), path = require('path'), cp = require('child_process');
const SP = process.argv[2];
const H = require(SP + '/crmc_hooks.js');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'crmc_repo_'));
fs.cpSync(SP, path.join(tmp, 'tests', 'web'), { recursive: true });
H.apply(path.join(SP, '..', '..', 'web'), path.join(tmp, 'web'));
// some older suites serve the absolute folder /home/user/My-tools/web and read two files from there: point the copies at the scratch tree
fs.mkdirSync(path.join(tmp, 'data'), { recursive: true }); fs.mkdirSync(path.join(tmp, 'supabase'), { recursive: true });
fs.copyFileSync(path.join(SP, '..', '..', 'data', 'items_seed.csv'), path.join(tmp, 'data', 'items_seed.csv'));
fs.copyFileSync(path.join(SP, '..', '..', 'supabase', 'schema.sql'), path.join(tmp, 'supabase', 'schema.sql'));
for (const f of fs.readdirSync(path.join(tmp, 'tests', 'web'))) {
  if (!f.endsWith('.js')) continue; const fp = path.join(tmp, 'tests', 'web', f); const x = fs.readFileSync(fp, 'utf8');
  if (x.includes('/home/user/My-tools/')) fs.writeFileSync(fp, x.split('/home/user/My-tools/').join(tmp + '/'));
}
let fail = 0;
for (const t of ['ia_test', 'nav_test', 'nav2_test', 'control_test', 'favsync_test', 'settings2_test', 'crm_segments_test']) {
  const f = path.join(tmp, 'tests', 'web', t + '.js');
  const r = cp.spawnSync('node', [f, path.join(tmp, 'tests', 'web')], { encoding: 'utf8', timeout: 240000 });
  const out = (r.stdout || '') + (r.stderr || '');
  const last = out.trim().split('\n').slice(-2).join(' | ');
  const bad = r.status !== 0 || /FAIL/.test(out);
  if (bad) fail++;
  console.log((bad ? 'FAIL ' : 'PASS ') + t + ': ' + last.slice(0, 200));
}
fs.rmSync(tmp, { recursive: true, force: true });
console.log(fail ? 'crmc_hooks_run: ' + fail + ' suite(s) failed' : 'crmc_hooks_run: all suites pass with the CRM-C hooks applied');
process.exit(fail ? 1 : 0);
