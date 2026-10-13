# Registration for Module C (customers + tiers) - to be applied by the lead

## (a) web/ia.js lines (group `cust`)
```js
  rec('customers', 'cust', ['গ্রাহক তালিকা ও স্তর', 'Customers & tiers', 'Customer list ও Tier'], { icon: 'users', ok: pos, mob: 3, kw: ['customer', 'tier', 'gold', 'elite', 'walk-in', 'regular', 'loyalty', 'points', 'gift', 'birthday', 'গ্রাহক', 'কাস্টমার', 'স্তর', 'গোল্ড', 'এলিট', 'উপহার', 'পয়েন্ট', 'জন্মদিন'] }),
  rec('tiers', 'cust', ['গ্রাহকের স্তর ও সুবিধা', 'Customer tiers & benefits', 'Customer tier ও সুবিধা'], { icon: 'settings', ok: owner, kw: ['tier', 'discount', 'gift', 'loyalty', 'points', 'auto upgrade', 'স্তর', 'ডিসকাউন্ট', 'উপহার', 'লয়্যালটি', 'পয়েন্ট'] }),
```

## (b) web/index.html (after `pos.js` / `dues.js`, anywhere after `stock2.js`; needs BOS_APP, BOS.L and B.rule)
```html
<script src="customers.js"></script>
```
Routes: `#/customers` (POS view/enter users; the server decides each action), `#/tiers` (owner only: the page shows a notice to anyone else, and every server function checks `is_owner()`). The `tiers` route is not in app.js OWNER_ONLY (not mine to edit); this is fine because the page and the server both refuse non-owners.

## (c) SQL: supabase/phase43.sql (run after phase28; idempotent)
* Grant: `customer_manage` (module master, sort 71) - change a customer's tier / credit limit / lock / active, issue gifts, adjust points. Owner always has it. Not given to any role by default.
* Switches (module `customers`, all default OFF): `tier_discount_on`, `customer_tier_auto_on`, `customer_tier_allow_downgrade`, `loyalty_points_on`, `customer_gifts_on`.
* Numbers: `points_per_100_taka` (1), `point_value_taka` (1), `redeem_min_points` (100), `gift_window_days` (7), `gift_valid_days` (30). They show in #/tiers (and #/switchboard for the switches).
* Tables (RLS, select only): `customer_tiers` (7 seeded names, discounts 0, no thresholds), `customer_tier_history` + `customer_points_ledger` + `sale_tier_use` (append-only), `gift_rules`, `customer_gifts`. `customers` gains tier_id, tier_locked, birthday, anniversary, address, customer_since, source, whatsapp (existing `note` = notes).
* Functions for the browser: customer_directory, customer_profile, customer_pos_info, customer_save, customer_set_tier, customer_points, customer_points_adjust, customer_points_redeem, gifts_due, gift_claim, gift_issue, tier_save, tier_reorder, gift_rule_save, customer_tier_refresh(p_dry default true), tier_usage_report. Internal (closed to the browser): loyalty_award, helpers, the three sales triggers.
* record_sale2 is re-created from its live definition (phase8 + phase22 bos22-late patch); only blocks marked `bos43` differ. A later phase that re-creates record_sale2 must start from THIS definition.
* web/pos.js: customer block now calls `customer_pos_info` (tier chip, perks, gift reminder, one-tap tier discount button). A database without phase43 simply shows no tier line.
