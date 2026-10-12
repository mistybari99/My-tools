-- phase30_controls.sql · additive, idempotent. One global setting: collapsed controls (dropdown / multi-select / tick / three-dot menu).
-- Absent = ON. Switch it OFF to get the old open controls back instantly (each phone can also set localStorage bos_ctl_collapsed='off').
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('ui_collapsed_controls', 'settings', 'switch', 'true', null, null, null, null,
  'বিকল্প গুটানো থাকবে (ড্রপডাউন / মাল্টি-সিলেক্ট / ⋮)', 'Option গুটানো থাকবে (dropdown / multi-select / ⋮)', 'Collapsed controls (dropdown / multi-select / ⋮)',
  'বন্ধ করলে আগের মতো সব বিকল্প খোলা দেখাবে', 'Off = the old open option buttons come back', 80)
 on conflict (key) do nothing;
