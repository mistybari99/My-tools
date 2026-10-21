// Integration helper for the web tests that prove a package's exact-text hooks on a scratch copy (crm_hooks.js, crm_loyalty_test.js, crm_profile_test.js).
// Before the integration those hooks were NOT in web/customers.js, web/pos.js ...; the tests applied them to a copy. Now the integrator has applied them for real, so a hook counts as
// "integrated" when its new text is already in the file (whole, or the part it adds when the old site is kept inside it). The old site may then be gone or changed on purpose
// (two packages hooked the same line: the integrated line carries both).
function added(find, replace) { return String(replace).split(String(find)).join('').trim(); }
function integrated(txt, find, replace) {
  const t = String(txt);
  if (t.includes(String(replace))) return true;
  const a = added(find, replace);
  return a.length > 8 && t.includes(a);
}
module.exports = { integrated, added };
