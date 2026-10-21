// Form names and printed codes (no browser): every printed form has a name, the codes match the baseline,
// and docs/FORM_SEQUENCE.md maps each of the 41 sorted forms once, in short-name order, to NN-1.
// Run: node form_names_test.js <abs tests/web dir>
const _P = require('./_paths');
const fs = require('fs'), path = require('path');
const { REPO_DIR, WEB_DIR } = _P;

// baseline: the 42 printed codes in supabase/schema.sql (forms seed) at this commit
const BASELINE = ['0-1', '40-1', '20-1', '19-1', '21-1', '35-1', '01-1', '15-1', '10-1', '09-1', '34-1', '39-1',
  '13-1', '18-1', '36-1', '37-1', '12-1', '26-1', '31-1', '41-1', '22-1', '28-1', '29-1', '27-1', '02-1', '38-1',
  '16-1', '03-1', '11-1', '07-1', '04-1', '30-1', '33-1', '06-1', '14-1', '17-1', '05-1', '08-1', '32-1', '24-1', '25-1', '23-1'];
const FIXED = '0-1';

let fails = 0;
const ok = (c, m) => { if (!c) { fails++; console.log('FAIL: ' + m); } else console.log('PASS: ' + m); };

// 1. seed rows (name_bn, name_en per code)
const schema = fs.readFileSync(path.join(REPO_DIR, 'supabase', 'schema.sql'), 'utf8');
const i0 = schema.indexOf('insert into public.forms (code, area, name_bn, name_mix, name_en, version, sort) values');
const seedEnd = schema.indexOf(';', i0);
const seedRows = [...schema.slice(i0, seedEnd).matchAll(/\('([^']+)','([^']+)','([^']*)','([^']*)','([^']*)','([^']*)',(\d+)\)/g)]
  .map((m) => ({ code: m[1], bn: m[3], mix: m[4], en: m[5] }));
const printed = seedRows.filter((r) => /^\d{2}-\d$|^0-\d$/.test(r.code));
const codes = printed.map((r) => r.code).sort();
ok(JSON.stringify(codes) === JSON.stringify([...BASELINE].sort()), 'printed codes equal the baseline (' + codes.length + ' forms)');
ok(codes.length === 42, 'there are 42 printed forms');

// 2. every printed form has a Bangla and an English name
const noName = printed.filter((r) => !r.bn.trim() || !r.en.trim()).map((r) => r.code);
ok(noName.length === 0, 'every printed form has a Bangla and an English name' + (noName.length ? ' (missing: ' + noName.join(' ') + ')' : ''));

// 3. every NN-N form has a form-kit title in web/forms*.js (0-1 is the settings sheet, named in the seed)
const kitSrc = fs.readdirSync(WEB_DIR).filter((f) => /^forms.*\.js$/.test(f) || f === 'formscreens.js')
  .map((f) => fs.readFileSync(path.join(WEB_DIR, f), 'utf8')).join('\n');
const kitCodes = new Set([...kitSrc.matchAll(/B\.forms\['([^']+)'\]\s*=\s*\{\s*title:/g)].map((m) => m[1]));
const noKit = codes.filter((c) => c !== FIXED && !kitCodes.has(c));
ok(noKit.length === 0, 'every NN-N form has a form-kit title' + (noKit.length ? ' (missing: ' + noKit.join(' ') + ')' : ''));

// 4. docs/FORM_SEQUENCE.md: the mapping table
const seq = fs.readFileSync(path.join(REPO_DIR, 'docs', 'FORM_SEQUENCE.md'), 'utf8');
const rows = seq.split('\n').map((l) => l.match(/^\| (\d+) \| ([^|]+?) \| ([^|]+?) \| (\d{2}-\d) \| (\d{2}-\d) \|$/))
  .filter(Boolean).map((m) => ({ no: Number(m[1]), en: m[2].trim(), bn: m[3].trim(), old: m[4], neu: m[5] }));
ok(rows.length === 41, 'mapping table has 41 sorted rows (found ' + rows.length + ')');
ok(rows.every((r, i) => r.no === i + 1), 'sort numbers run 1..41 in order');
ok(rows.every((r, i) => i === 0 || rows[i - 1].en.toLowerCase() <= r.en.toLowerCase()), 'rows are in A-Z order by English short name');
const oldSet = rows.map((r) => r.old).sort();
ok(JSON.stringify(oldSet) === JSON.stringify(BASELINE.filter((c) => c !== FIXED).sort()), 'old codes in the table are exactly the 41 printed NN-N codes, each once');
ok(rows.every((r, i) => r.neu === String(i + 1).padStart(2, '0') + '-1'), 'new codes are 40-1 .. 41-1 in row order');
ok(new Set(rows.map((r) => r.neu)).size === rows.length, 'new codes are unique');
ok(rows.every((r) => r.en && r.bn), 'every row has an English and a Bangla short name');

console.log('assert failures: ' + fails);
process.exit(fails ? 1 : 0);
