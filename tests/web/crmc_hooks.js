// The exact hook text of package CRM-C for the shared web files (same text as docs/integration/CRM-C.md section 2).
// crm_segments_test.js copies web/ to a scratch folder, applies these edits and tests the screens from there, so the text is proved before the integrator uses it.
const fs = require('fs');
const path = require('path');
const IA_ANCHOR = "  rec('tiers', 'cust',";
const OK = "(c) => c.own || c.GF.crm_view === true || c.GF.crm_settings_edit === true || c.GF.customer_manage === true";
const IA_LINES = [
  `  rec('crmlists', 'cust', ['Customer lists', 'Customer lists', 'Customer lists'], { icon: 'users', ok: ${OK}, kw: ['customer list', 'segment', 'saved list', 'not seen', 'lapsed', 'birthday', 'high spender', 'by outlet', 'by tier', 'bought item', 'audience'], verbs: ['make a customer list', 'count customers'] }),`,
  `  rec('crmvalue', 'cust', ['Customer value', 'Customer value', 'Customer value'], { icon: 'users', ok: ${OK}, kw: ['rfm', 'lifetime value', 'repeat rate', 'repeat customers', 'champion', 'at risk', 'lapsed customers', 'best customers', 'customer profit', 'churn'], verbs: ['see best customers', 'see lapsed customers'] }),`,
];
const HTML_ANCHOR = '<script src="customers.js"></script>';
const HTML_ADD = '<script src="crm_segments.js"></script><script src="crm_rfm.js"></script>';
const NAV_EDITS = [
  ["'list_manage', 'rollout_manage', 'change_approve'] : [", "'list_manage', 'rollout_manage', 'change_approve', 'crm_view', 'crm_settings_edit'] : ["],
  ["'customer_manage', 'assistant_use'];", "'customer_manage', 'assistant_use', 'crm_view', 'crm_settings_edit'];"],
];
function once(text, needle, what) {
  const n = text.split(needle).length - 1;
  if (n !== 1) throw new Error('hook site for ' + what + ' found ' + n + ' times (expected 1)');
}
// copies the web folder to dst and applies the hooks; returns the folder
function apply(webDir, dst) {
  fs.rmSync(dst, { recursive: true, force: true });
  fs.cpSync(webDir, dst, { recursive: true });
  let ia = fs.readFileSync(path.join(dst, 'ia.js'), 'utf8');
  if (ia.includes("rec('crmlists'")) return dst;   // already hooked (a copy of a hooked tree)
  once(ia, IA_ANCHOR, 'ia.js');
  const at = ia.indexOf(IA_ANCHOR); const eol = ia.indexOf('\n', at);
  ia = ia.slice(0, eol + 1) + IA_LINES.join('\n') + '\n' + ia.slice(eol + 1);
  fs.writeFileSync(path.join(dst, 'ia.js'), ia);
  let html = fs.readFileSync(path.join(dst, 'index.html'), 'utf8');
  once(html, HTML_ANCHOR, 'index.html');
  html = html.replace(HTML_ANCHOR, HTML_ANCHOR + HTML_ADD);
  fs.writeFileSync(path.join(dst, 'index.html'), html);
  let nav = fs.readFileSync(path.join(dst, 'nav.js'), 'utf8');
  NAV_EDITS.forEach(([a, b], i) => { once(nav, a, 'nav.js edit ' + (i + 1)); nav = nav.replace(a, b); });
  fs.writeFileSync(path.join(dst, 'nav.js'), nav);
  return dst;
}
module.exports = { apply, IA_LINES, IA_ANCHOR, HTML_ANCHOR, HTML_ADD, NAV_EDITS };
