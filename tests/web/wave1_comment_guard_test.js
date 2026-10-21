// Guard: a "// ..." comment added in the middle of a line must not swallow the code that follows it on that line.
// Found at the Wave 1 integration check: web/dues.js lost "D.cid = ..." (the one id per collection sheet, so a double tap could collect twice)
// and web/accounts.js lost the redraw after a manual journal, both because a "// W1-x: ..." note was inserted before the rest of the line.
// Pure Node, no browser. Run: node wave1_comment_guard_test.js <abs tests/web dir>      (exit 1 on any failure)
const fs = require('fs');
const path = require('path');
const WEB = path.join(process.argv[2] || __dirname, '..', '..', 'web');
let fails = 0, checks = 0;
const ok = (c, m) => { checks++; if (!c) { fails++; console.log('FAIL ' + m); } };

// code part of one line: everything before the first "//" that is outside a '...', "..." or `...` string on that line
function code(line) {
  let q = null;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (q) { if (c === '\\') i++; else if (c === q) q = null; continue; }
    if (c === '\'' || c === '"' || c === '`') { q = c; continue; }
    if (c === '/' && line[i + 1] === '/' && line[i - 1] !== ':') return line.slice(0, i);
  }
  return line;
}
const lines = (f) => fs.readFileSync(path.join(WEB, f), 'utf8').split('\n');
const has = (f, needle) => lines(f).some((l) => code(l).includes(needle));

// the two lines that were damaged
ok(has('dues.js', 'D.cid = crypto.randomUUID'), 'dues.js: D.cid is set in code (one id per collection sheet)');
ok(has('accounts.js', "D.tab = 'journal'") && has('accounts.js', 'D.jphoto = \'\'; D.tab'), 'accounts.js: after a saved manual journal the photo is cleared and the tab is set in code');
ok(lines('accounts.js').some((l) => /D\.jphoto = ''; D\.tab = 'journal'; D\.st = await rpc\('acct_status'\); await draw\(\);/.test(code(l))), 'accounts.js: after a saved manual journal the screen is redrawn in code');

// generic: a Wave 1 note ("// W1-A: ..." to "// W1-G: ...", "// bos88..99") must not contain statements that follow the note text on the same line
let bad = 0;
for (const f of fs.readdirSync(WEB).filter((x) => x.endsWith('.js'))) {
  lines(f).forEach((l, i) => {
    const m = l.match(/\s\/\/ (?:W1-[A-G]|bos9\d|bos8\d)[:\s].*$/);
    if (!m) return;
    const note = m[0];
    // a statement after the words of the note: "<word> D.x = ...;" or "...; await foo(...)" or a call "foo(...);"
    if (/ [A-Za-z_$][\w$.]* = [^;]{1,200};/.test(note.replace(/\/\/ one id per sheet.*$/, '')) || /;\s*(await |toast\(|draw\(|show\(|return )/.test(note)) {
      bad++; console.log('FAIL ' + f + ':' + (i + 1) + ' a note comment seems to hide code: ' + note.trim().slice(0, 120));
    }
  });
}
ok(bad === 0, 'no Wave 1 note comment hides code that follows it on the same line (' + bad + ' found)');
console.log(checks + ' checks, ' + fails + ' failed');
process.exit(fails ? 1 : 0);
