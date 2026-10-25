// Navigation stack: Back returns to the exact previous screen, 1 to 3 steps back, "main" = the top-level screen the deep chain started from.
// Pure Node with a fake window, location and sessionStorage (no browser). Run: node navstack_test.js <abs tests/web dir>   (exit 1 on any failure)
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const WEB = path.join(process.argv[2] || __dirname, '..', '..', 'web');
const SRC = fs.readFileSync(path.join(WEB, 'navstack.js'), 'utf8');
let fails = 0, checks = 0;
const ok = (c, m) => { checks++; if (!c) { fails++; console.log('FAIL ' + m); } };

// one fresh "tab": hash assignment fires hashchange at once, the way the browser does for a link
function tab(storage) {
  const listeners = [];
  const loc = { _h: '' };
  Object.defineProperty(loc, 'hash', {
    get() { return this._h; },
    set(v) { this._h = v; listeners.forEach((f) => f()); },   // route() would run here in the app
  });
  const win = { addEventListener: (ev, f) => { if (ev === 'hashchange') listeners.push(f); } };
  const ctx = { window: win, location: loc, sessionStorage: storage, console };
  vm.createContext(ctx);
  vm.runInContext(SRC, ctx);
  const nav = win.BOS_NAVSTACK;
  // a link to a screen: the app sets the hash, the browser fires hashchange
  const go = (k) => { loc.hash = '#/' + k; };
  return { nav, go, loc, win };
}
const mem = () => { const m = {}; return { getItem: (k) => (k in m ? m[k] : null), setItem: (k, v) => { m[k] = String(v); }, removeItem: (k) => { delete m[k]; } }; };
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// 1. entering screens builds the chain, one entry per screen, no duplicate in a row
{
  const s = mem(); const t = tab(s);
  t.go('home'); t.go('accounts'); t.go('accounts/journal'); t.go('accounts/journal'); t.go('sale');
  ok(same(t.nav.peek(), ['home', 'accounts', 'accounts/journal', 'sale']), 'chain built in entry order, refresh adds nothing: ' + JSON.stringify(t.nav.peek()));
}

// 2. Back goes to the exact previous screen, and again back
{
  const s = mem(); const t = tab(s);
  t.go('home'); t.go('accounts'); t.go('accounts/journal'); t.go('sale');
  t.nav.back();
  ok(t.loc.hash === '#/accounts/journal' && same(t.nav.peek(), ['home', 'accounts', 'accounts/journal']), 'back 1 returns to the screen the person came from (accounts/journal)');
  t.nav.back();
  ok(t.loc.hash === '#/accounts' && t.nav.depth() === 2, 'second back returns to accounts');
}

// 3. back 2 and 3 steps (optional design)
{
  const s = mem(); const t = tab(s);
  t.go('home'); t.go('a'); t.go('b'); t.go('c'); t.go('d');
  t.nav.back(2);
  ok(t.loc.hash === '#/b' && same(t.nav.peek(), ['home', 'a', 'b']), 'back 2 from d goes to b');
  t.go('x');
  t.nav.back(3);
  ok(t.loc.hash === '#/home' && t.nav.depth() === 1, 'back 3 from x (stack home,a,b,x) goes to home');
}

// 4. the browser back (hash changed by the browser, not by us) pops the same way
{
  const s = mem(); const t = tab(s);
  t.go('home'); t.go('pos'); t.go('pos/sale');
  t.go('pos');   // the browser's back button arrives as a plain hash change to the entry below the top
  ok(same(t.nav.peek(), ['home', 'pos']), 'browser back pops the top entry: ' + JSON.stringify(t.nav.peek()));
}

// 5. main = nearest top-level screen the deep chain was entered from
{
  const s = mem(); const t = tab(s);
  t.go('home'); t.go('pos'); t.go('accounts'); t.go('accounts/journal'); t.go('accounts/journal/x');
  t.nav.main();
  ok(t.loc.hash === '#/accounts' && same(t.nav.peek(), ['home', 'pos', 'accounts']), 'main from a deep chain goes to accounts, the last top-level entry');
}
{
  const s = mem(); const t = tab(s);
  t.go('home'); t.go('pos'); t.go('accounts');
  t.nav.main();
  ok(t.loc.hash === '#/pos', 'main from a top-level screen goes to the top-level screen before it');
}

// 6. no history: Back goes Home; main with nothing above goes Home
{
  const s = mem(); const t = tab(s);
  t.go('sale/x');
  t.nav.back();
  ok(t.loc.hash === '#/home', 'back with no earlier screen goes home');
}

// 7. the stack survives a reload in the same tab, and blocked storage does not break the app
{
  const s = mem(); const t = tab(s);
  t.go('home'); t.go('stock'); t.go('stock/count');
  const t2 = tab(s);   // same sessionStorage = same tab after a reload
  ok(same(t2.nav.peek(), ['home', 'stock', 'stock/count']), 'stack kept after reload');
  t2.nav.back();
  ok(t2.loc.hash === '#/stock', 'back works after reload');
}
{
  const bad = { getItem() { throw new Error('blocked'); }, setItem() { throw new Error('blocked'); } };
  let threw = false;
  try { const t = tab(bad); t.go('home'); t.go('pos'); t.nav.back(); ok(t.loc.hash === '#/home', 'blocked storage: back still works in memory'); } catch (e) { threw = true; }
  ok(!threw, 'blocked storage must not throw');
}

// 8. the stack is capped at 30 entries
{
  const s = mem(); const t = tab(s);
  for (let i = 0; i < 40; i++) t.go('p' + i);
  ok(t.nav.depth() === 30 && t.nav.peek()[29] === 'p39', 'stack is capped at 30 entries, newest kept');
}

console.log(fails ? fails + ' of ' + checks + ' checks FAILED' : 'OK navstack ' + checks + ' checks');
process.exit(fails ? 1 : 0);
