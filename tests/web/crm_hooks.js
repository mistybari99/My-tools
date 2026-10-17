// The exact hook lines for the integrator-owned screens (docs/integration/CRM-B.md section 3 copies them word for word).
// crm_consent_test.js applies them to a SCRATCH COPY of web/customers.js and web/pos.js (the real files are not touched), checks every site is found exactly once,
// checks the doc contains each new text, and runs the hooked screens.
const HOOKS = {
  'customers.js': [
    ["const r = await sb.rpc('customer_directory'); if (r.error) {",
     "const r = await (B.crmConsent ? B.crmConsent.directory() : sb.rpc('customer_directory')); if (r.error) {"],
    ["const r = await sb.rpc('customer_profile', { p_customer: id }); if (r.error) return toast(eText(r.error));",
     "const r = await (B.crmConsent ? B.crmConsent.profile(id) : sb.rpc('customer_profile', { p_customer: id })); if (r.error) return toast(eText(r.error));"],
    ['<a class="full tog" href="tel:${esc(c.mobile)}" style="text-align:center;padding:10px">${esc(T(\'menuCall\'))}</a>',
     '${B.crmConsent ? B.crmConsent.callHTML(c, T(\'menuCall\')) : `<a class="full tog" href="tel:${esc(c.mobile)}" style="text-align:center;padding:10px">${esc(T(\'menuCall\'))}</a>`}'],
    ['<a class="full tog" href="${esc(wa)}" target="_blank" rel="noopener" style="text-align:center;padding:10px">${esc(T(\'menuWa\'))}</a>',
     '${c.masked ? \'\' : `<a class="full tog" href="${esc(wa)}" target="_blank" rel="noopener" style="text-align:center;padding:10px">${esc(T(\'menuWa\'))}</a>`}'],
    ["${D.mgr ? b('cu_active', c.active ? T('menuOff') : T('menuOn')) : ''}",
     "${D.mgr ? b('cu_active', c.active ? T('menuOff') : T('menuOn')) : ''}${B.crmConsent ? B.crmConsent.menuHTML(c) : ''}${B.crmDupes ? B.crmDupes.menuHTML(c) : ''}"],
  ],
  'pos.js': [
    ['<input id="cu_name" value="${esc(c.name)}">` : \'\'}</div>`;',
     '<input id="cu_name" value="${esc(c.name)}">` : \'\'}${B.crmConsent ? B.crmConsent.posStrip(c.mobile) : \'\'}</div>`;'],
    ["if (B.invoice && B.invoice.offer) B.invoice.offer(data.id, p.p_loc);",
     "if (B.invoice && B.invoice.offer) B.invoice.offer(data.id, p.p_loc);\n    if (B.crmConsent && B.crmConsent.afterSale) B.crmConsent.afterSale(p.p_customer_mobile);"],
  ],
};
// apply to a text; throws unless every old text occurs exactly once
function apply(file, text) {
  let t = text;
  for (const [a, b] of HOOKS[file]) {
    const n = t.split(a).length - 1;
    if (n !== 1) throw new Error('hook site not found exactly once in ' + file + ' (' + n + '): ' + a.slice(0, 70));
    t = t.replace(a, () => b);
  }
  return t;
}
module.exports = { HOOKS, apply };
