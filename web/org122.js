/* Islamia BOS · Organization (#/organization): the company tree (Group > legal entity > business > branches / sites / departments / cost centres / projects), owner or grant org_manage only.
   Server (supabase/phase122.sql): org_tree() -> jsonb tree, org_unit_save(p_client, p_id, p_parent, p_kind, p_code, p_name_bn, p_name_en, p_template, p_attrs, p_effective_from) -> jsonb,
   org_unit_deactivate(p_id, p_reason) -> jsonb; business templates from table business_templates (code, name, status). Nothing is deleted: a unit is deactivated with a reason.
   A template whose status is not_implemented is NEVER shown as ready. No business or brand names are written in this file: every name comes from the data. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'o' + Date.now().toString(36) + Math.random().toString(36).slice(2, 10));
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const KINDS = {
  group: L('গ্রুপ', 'Group', 'Group'), legal_entity: L('আইনি প্রতিষ্ঠান', 'Legal entity', 'Legal entity'), business: L('ব্যবসা', 'Business', 'Business'), branch: L('শাখা', 'Branch', 'Branch'),
  site: L('সাইট', 'Site', 'Site'), department: L('বিভাগ', 'Department', 'Department'), cost_centre: L('খরচ কেন্দ্র', 'Cost centre', 'Cost centre'), project: L('প্রকল্প', 'Project', 'Project'),
};
const CHILD = { group: ['legal_entity', 'business'], legal_entity: ['business', 'branch'], business: ['branch', 'site', 'department', 'cost_centre', 'project'],
  branch: ['site', 'department', 'cost_centre', 'project'], site: ['department', 'cost_centre'], department: ['cost_centre', 'project'], cost_centre: [], project: [] };
const TPL = { available: [L('পাওয়া যায়', 'Available', 'Available'), 'ok'], configured: [L('সাজানো হয়েছে', 'Configured', 'Configured'), 'ok'], needs_setup: [L('সেটআপ লাগবে', 'Needs setup', 'Setup লাগবে'), 'warn'],
  planned: [L('পরিকল্পনায়', 'Planned', 'Planned'), 'muted'], not_implemented: [L('এখনো তৈরি হয়নি', 'Not built yet', 'এখনো তৈরি হয়নি'), 'bad'] };
const X = {
  title: L('প্রতিষ্ঠানের কাঠামো', 'Organization', 'Organization কাঠামো'), add: L('যোগ করুন', 'Add', 'Add'), addRoot: L('নতুন গ্রুপ / ব্যবসা যোগ', 'Add a group or business', 'নতুন group / business যোগ'),
  rename: L('নাম বদল', 'Rename', 'Rename'), off: L('বন্ধ করুন', 'Deactivate', 'Deactivate'), inactive: L('বন্ধ', 'Inactive', 'Inactive'), kind: L('ধরন', 'Kind', 'ধরন'),
  code: L('কোড (ইংরেজি/সংখ্যা)', 'Code (letters / digits)', 'Code (English/সংখ্যা)'), nbn: L('নাম (বাংলা)', 'Name (Bangla)', 'নাম (বাংলা)'), nen: L('নাম (ইংরেজি)', 'Name (English)', 'নাম (English)'),
  tpl: L('ব্যবসার টেমপ্লেট', 'Business template', 'Business template'), none: L('কোনোটি নয়', 'None', 'কোনোটি নয়'), from: L('শুরুর তারিখ', 'Effective from', 'শুরুর তারিখ'),
  save: L('সেভ', 'Save', 'Save'), cancel: L('বাতিল', 'Cancel', 'Cancel'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'), offDone: L('বন্ধ করা হয়েছে', 'Deactivated', 'Deactivated'),
  why: L('বন্ধের কারণ', 'Reason', 'বন্ধের কারণ'), offHint: L('কিছু মুছবে না; ইউনিটটি বন্ধ হিসেবে থাকবে।', 'Nothing is deleted; the unit stays as inactive.', 'কিছু মুছবে না; unit inactive থাকবে।'),
  empty: L('এখনো কোনো প্রতিষ্ঠান যোগ করা হয়নি। প্রথমে একটি গ্রুপ বা ব্যবসা যোগ করুন।', 'No organization added yet. Start by adding a group or a business.', 'এখনো কিছু যোগ হয়নি। আগে একটি group বা business যোগ করুন।'),
  noperm: L('এই পাতা শুধু মালিক বা সংশ্লিষ্ট অনুমতিপ্রাপ্তদের জন্য।', 'This page is for the owner or people with the organization right.', 'এই page শুধু owner বা permission-ওয়ালাদের জন্য।'),
  tplNote: L('এই টেমপ্লেট এখনো তৈরি হয়নি, তাই এটি চালু নয়।', 'This template is not built yet, so it is not live.', 'এই template এখনো তৈরি হয়নি, তাই চালু নয়।'),
  child: L('ভেতরে', 'Inside', 'ভেতরে'), lic: L('ট্রেড লাইসেন্স', 'Trade licence', 'Trade licence'), pct: L('মালিকানা %', 'Owner %', 'Owner %'), fy: L('অর্থবছর শুরু', 'Fiscal start', 'Fiscal start'),
};
const T = (k) => lab(X[k]);
const D = { tree: [], flat: new Map(), tpl: [], ok: false };
const ERR = {
  not_allowed: L('অনুমতি নেই', 'Not allowed'), code_required: L('কোড লিখুন', 'Enter a code'), code_duplicate: L('এই কোড আগেই আছে', 'This code is already used'), code_exists: L('এই কোড আগেই আছে', 'This code is already used'),
  name_required: L('একটি নাম লিখুন', 'Enter a name'), bad_kind: L('ধরন ঠিক নয়', 'Kind is not valid'), bad_parent: L('উপরের ইউনিট ঠিক নয়', 'The parent unit is not valid'),
  parent_kind_mismatch: L('এই ধরন এই ইউনিটের ভেতরে হয় না', 'This kind cannot go inside that unit'), bad_template: L('টেমপ্লেট ঠিক নয়', 'Template is not valid'),
  template_not_implemented: L('এই টেমপ্লেট এখনো তৈরি হয়নি', 'This template is not built yet'), bad_date: L('তারিখ ঠিক নয়', 'Date is not valid'),
  has_active_children: L('ভেতরে চালু ইউনিট আছে; আগে সেগুলো বন্ধ করুন', 'It still has active units inside; deactivate those first'), cycle: L('নিজের ভেতরে নেওয়া যায় না', 'A unit cannot go inside itself'),
  not_found: L('ইউনিট পাওয়া যায়নি', 'Unit not found'), already_inactive: L('এটি আগেই বন্ধ', 'Already inactive'), reason_required: L('কারণ লিখুন (কমপক্ষে ৩ অক্ষর)', 'Write a reason (at least 3 characters)'),
  period_locked: L('এই মাস বন্ধ', 'This period is locked'),
};
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? lab(ERR[k]) : m || 'error'; };
const isOwner = () => !!(S.ctx && S.ctx.is_owner);
const kl = (k) => (KINDS[k] ? lab(KINDS[k]) : String(k || ''));
const uname = (u) => lab(L(u.name_bn || u.name_en || u.code || '', u.name_en || u.name_bn || u.code || '', u.name_en || u.name_bn || u.code || ''));
const tplOf = (c) => D.tpl.find((t) => t.code === c);
const tplName = (t) => (t.name_en || t.name_bn || t.name || t.code);
const tplBadge = (code) => {
  if (!code) return '';
  const t = tplOf(code), st = t && TPL[t.status];
  if (!st) return `<span class="chip muted">${esc(t ? tplName(t) : code)}</span>`;
  return `<span class="chip ${st[1]}">${esc(t.name_en || t.name_bn || t.name || code)} · ${esc(lab(st[0]))}</span>`;
};

function norm(raw) {
  let a = raw;
  if (a && !Array.isArray(a)) a = a.tree || a.units || a.roots || [a];
  const flat = new Map(), roots = [];
  const walk = (n, par) => { if (!n || typeof n !== 'object') return; const o = Object.assign({}, n, { children: [] }); if (o.parent_id === undefined && par) o.parent_id = par.id; flat.set(String(o.id), o); (n.children || []).forEach((c) => walk(c, o)); };
  (a || []).forEach((n) => walk(n, null));
  flat.forEach((o) => { const p = o.parent_id != null ? flat.get(String(o.parent_id)) : null; if (p) p.children.push(o); else roots.push(o); });
  D.flat = flat; D.tree = roots;
}
async function load() {
  const [t, p] = await Promise.all([sb.rpc('org_tree'), sb.from('business_templates').select('*')]);
  if (t.error) throw t.error;
  norm(t.data); D.tpl = p && p.data ? p.data : [];
}
function nodeHTML(n, depth) {
  const off = n.status && n.status !== 'active';
  const le = n.legal_entity ? `<div class="muted">${[n.legal_entity.trade_licence_ref ? esc(T('lic')) + ': ' + esc(n.legal_entity.trade_licence_ref) : '', n.legal_entity.owner_pct != null ? esc(T('pct')) + ': ' + esc(n.legal_entity.owner_pct) : '', n.legal_entity.fiscal_start ? esc(T('fy')) + ': ' + esc(n.legal_entity.fiscal_start) : ''].filter(Boolean).join(' · ')}</div>` : '';
  const nb = n.template_code && tplOf(n.template_code) && tplOf(n.template_code).status === 'not_implemented' ? `<div class="muted">${esc(T('tplNote'))}</div>` : '';
  const acts = off ? '' : `<div class="row" style="flex-wrap:wrap;gap:6px">${(CHILD[n.kind] || []).length ? `<button class="mini" style="min-height:40px" data-act="og_add" data-v="${esc(n.id)}">+ ${esc(T('add'))}</button>` : ''}
      <button class="mini" style="min-height:40px" data-act="og_edit" data-v="${esc(n.id)}">${esc(T('rename'))}</button><button class="mini" style="min-height:40px" data-act="og_off" data-v="${esc(n.id)}">${esc(T('off'))}</button></div>`;
  return `<div class="og-node" data-id="${esc(n.id)}" style="margin-left:${Math.min(depth, 4) * 12}px"><div class="card ${off ? 'muted' : ''}" style="word-break:break-word;overflow-wrap:anywhere">
    <div class="row" style="flex-wrap:wrap;gap:6px;align-items:center"><span class="chip">${esc(kl(n.kind))}</span><b>${esc(uname(n))}</b>${n.code ? `<span class="muted">${esc(n.code)}</span>` : ''}${off ? `<span class="chip muted">${esc(T('inactive'))}</span>` : ''}${tplBadge(n.template_code)}</div>
    ${le}${nb}${acts}</div>${n.children.map((c) => nodeHTML(c, depth + 1)).join('')}</div>`;
}
function draw() {
  const el = $('#og_body'); if (!el) return;
  const top = `<div class="row"><button class="primary full" style="min-height:40px" data-act="og_add" data-v="">+ ${esc(T('addRoot'))}</button></div>`;
  el.innerHTML = top + (D.tree.length ? D.tree.map((n) => nodeHTML(n, 0)).join('') : `<div class="card" id="og_empty"><p class="muted">${esc(T('empty'))}</p></div>`);
}
function tplOptions(sel) {
  const opts = D.tpl.map((t) => { const st = TPL[t.status]; return `<option value="${esc(t.code)}" ${t.code === sel ? 'selected' : ''} ${t.status === 'not_implemented' ? 'disabled' : ''}>${esc(tplName(t))}${st ? ' · ' + esc(lab(st[0])) : ''}</option>`; }).join('');
  return `<option value="">${esc(T('none'))}</option>${opts}`;
}
function formSheet(o) {
  const kinds = o.kinds;
  openSheet(`<h3>${esc(o.title)}</h3><div class="stack" id="og_form">
    <div><label for="og_kind">${esc(T('kind'))}</label><select id="og_kind" ${o.id ? 'disabled' : ''}>${kinds.map((k) => `<option value="${k}" ${k === o.kind ? 'selected' : ''}>${esc(kl(k))}</option>`).join('')}</select></div>
    <div><label for="og_code">${esc(T('code'))}</label><input id="og_code" autocomplete="off" maxlength="24" value="${esc(o.code || '')}"></div>
    <div><label for="og_nbn">${esc(T('nbn'))}</label><input id="og_nbn" autocomplete="off" maxlength="120" value="${esc(o.nbn || '')}"></div>
    <div><label for="og_nen">${esc(T('nen'))}</label><input id="og_nen" autocomplete="off" maxlength="120" value="${esc(o.nen || '')}"></div>
    <div id="og_tplw" ${o.kind === 'business' ? '' : 'hidden'}><label for="og_tpl">${esc(T('tpl'))}</label><select id="og_tpl">${tplOptions(o.tpl)}</select></div>
    <div><label for="og_from">${esc(T('from'))}</label><input id="og_from" type="date" value="${esc(o.from || today())}"></div>
    <div id="og_err" class="muted" role="alert"></div>
    <div class="row"><button class="full" style="min-height:40px" data-act="closesheet">${esc(T('cancel'))}</button><button class="full primary" style="min-height:40px" data-act="og_save" data-id="${esc(o.id || '')}" data-par="${esc(o.parent || '')}">${esc(T('save'))}</button></div></div>`);
  D.client = rid();
}
function showErr(m) { const e = $('#og_err'); if (e) e.textContent = m; else toast(m); }
const CODE_RE = /^[A-Za-z0-9][A-Za-z0-9_-]{1,23}$/;
Object.assign(H, {
  og_add: (a) => { const pid = a.dataset.v || ''; const par = pid ? D.flat.get(String(pid)) : null;
    const kinds = par ? CHILD[par.kind] || [] : ['group', 'legal_entity', 'business']; if (!kinds.length) return;
    formSheet({ title: par ? T('add') + ' · ' + uname(par) : T('addRoot'), kinds, kind: kinds[0], parent: pid }); },
  og_edit: (a) => { const n = D.flat.get(String(a.dataset.v)); if (!n) return;
    D.editing = n; formSheet({ title: T('rename') + ' · ' + uname(n), kinds: [n.kind], kind: n.kind, id: n.id, parent: n.parent_id == null ? '' : n.parent_id, code: n.code, nbn: n.name_bn, nen: n.name_en, tpl: n.template_code, from: n.effective_from }); },
  og_off: (a) => { const n = D.flat.get(String(a.dataset.v)); if (!n) return;
    openSheet(`<h3>${esc(T('off'))} · ${esc(uname(n))}</h3><div class="stack"><p class="muted">${esc(T('offHint'))}</p><div><label for="og_why">${esc(T('why'))}</label><input id="og_why" autocomplete="off" maxlength="200"></div>
      <div id="og_err" class="muted" role="alert"></div><div class="row"><button class="full" style="min-height:40px" data-act="closesheet">${esc(T('cancel'))}</button><button class="full primary" style="min-height:40px" data-act="og_offgo" data-id="${esc(n.id)}">${esc(T('off'))}</button></div></div>`); },
  og_offgo: async (a) => {
    const why = (($('#og_why') || {}).value || '').trim(); if (why.length < 3) return showErr(lab(ERR.reason_required));
    const r = await sb.rpc('org_unit_deactivate', { p_id: Number(a.dataset.id), p_reason: why }); if (r.error) return showErr(eText(r.error));
    closeSheet(); toast(T('offDone')); await refresh(); },
  og_save: async (a) => {
    const id = a.dataset.id ? Number(a.dataset.id) : null, kind = ($('#og_kind') || {}).value, code = (($('#og_code') || {}).value || '').trim();
    const nbn = (($('#og_nbn') || {}).value || '').trim(), nen = (($('#og_nen') || {}).value || '').trim(), from = (($('#og_from') || {}).value || '').trim(), tpl = kind === 'business' ? (($('#og_tpl') || {}).value || '') : '';
    if (!CODE_RE.test(code)) return showErr(lab(ERR.code_required));
    if (!nbn && !nen) return showErr(lab(ERR.name_required));
    if (from && !/^\d{4}-\d{2}-\d{2}$/.test(from)) return showErr(lab(ERR.bad_date));
    const t = tpl && tplOf(tpl); if (t && t.status === 'not_implemented') return showErr(lab(ERR.template_not_implemented));
    const old = id ? D.flat.get(String(id)) : null;
    const r = await sb.rpc('org_unit_save', { p_client: D.client, p_id: id, p_parent: a.dataset.par ? Number(a.dataset.par) : null, p_kind: kind, p_code: code, p_name_bn: nbn || null, p_name_en: nen || null,
      p_template: tpl || null, p_attrs: (old && old.attrs) || {}, p_effective_from: from || null });
    if (r.error) return showErr(eText(r.error));
    closeSheet(); toast(T('saved')); await refresh(); },
});
document.addEventListener('change', (e) => { if (e.target && e.target.id === 'og_kind') { const w = $('#og_tplw'); if (w) w.hidden = e.target.value !== 'business'; } });
async function refresh() { await load(); draw(); }
async function allowed() {
  if (isOwner()) return true;
  try { const r = await sb.rpc('has_grant', { p_code: 'org_manage' }); return !!(r && !r.error && r.data === true); } catch (e) { return false; }
}
async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell(T('title'), '<div id="og_body" class="stack"><p class="muted">…</p></div>', true);
  try {
    D.ok = await allowed();
    if (!D.ok) { $('#og_body').innerHTML = `<div class="card" id="og_noperm"><p class="muted">${esc(T('noperm'))}</p></div>`; return; }
    await refresh();
  } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { organization: view });
})();
