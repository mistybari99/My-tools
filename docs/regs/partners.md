# Module D - Partners (deed engine): registration for the lead

## (a) web/ia.js - add these lines (group `settings`, owner only)
```js
  rec('partners', 'settings', ['অংশীদারি ও বিনিয়োগ', 'Partners & investment', 'অংশীদারি ও Investment'], { icon: 'money', ok: (c) => c.own, kw: ['partner', 'partnership', 'investor', 'investment', 'franchise', 'royalty', 'profit share', 'profit sharing', 'deed', 'agreement', 'capital', 'loan', 'settlement', 'অংশীদার', 'বিনিয়োগ', 'ফ্র্যাঞ্চাইজ', 'রয়্যালটি', 'লাভ ভাগ', 'চুক্তি', 'পুঁজি', 'দলিল'] }),
```
(Only the owner may open it; the page itself also refuses non-owners and the server refuses every call. If the app has an OWNER_ONLY route set in web/app.js, add `partners` to it.)

## (b) web/index.html - script tag, after parallel.js (needs stock2.js loaded before it, for `B.s2`)
```html
<script src="partners.js"></script>
```

## (c) SQL / grants / rules added by supabase/phase44.sql (run after phase28; idempotent)
* Rule `partners_module_on` (switch, default ON, module `partners`, shown in #/switchboard). OFF = every partner_* function refuses with `module_off`; saved data is kept.
* No new grant_defs: everything is OWNER ONLY (`public.is_owner()` inside `_a44_guard()`); RLS select policy = owner on all 10 tables; no direct write grants; all writes go through SECURITY DEFINER functions.
* Tables: partner_parties, partner_ventures, partner_agreements, agreement_parties, partner_rules, partner_capital (append-only, void flag), partner_settlements, partner_settlement_lines, partner_settlement_payments (append-only), partner_templates (4 seeded EXAMPLE rows: franchise, investor_payback, partnership_5050, fixed_return_loan - inactive, numbers are placeholders; a deed made from one must have its numbers confirmed by the owner before it can go live).
* Browser-callable functions: partner_party_save, partner_venture_save, partner_agreement_save / _party_set / _activate / _amend / _close / _from_template, partner_rule_validate / _save, partner_rules_reorder, partner_calculate (trial, writes nothing), partner_capital_add / _void / _balances, partner_settlement_save / _approve / _void / _pay, partner_party_statement, partner_overview.
* Reads the books through the private `_p27_pl` (phase27): sales net of returns, costed COGS (gross profit only when every sold line has a cost, else NULL + warning), 11-1 expenses, 21-1 salary, location fixed cost. Module A journal balances are not read (phase40 absent); use the manual base.
* Audit: audit_<table> triggers on every table (audit_log). Immutability triggers: live deed, its rules/parties, approved settlements, capital rows, payments.
