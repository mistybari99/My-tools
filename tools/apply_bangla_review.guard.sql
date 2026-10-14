  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.get_doc_templates(integer)'), ('94', 'public._intake_proof_ok94(text,text)'),
    ('95', 'public.drawer_settings(integer)'), ('96', 'public._cw_docs96()'), ('97', 'public._landed_jlines97(uuid,text)'),
    ('99', 'public._inb_pii_f99(text,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.item_categories') is null then miss := miss || ' 100'; end if;
  if to_regclass('public.setup_rec_defs81') is null then miss := miss || ' 101'; end if;
  if to_regclass('public.rules') is null or not exists (select 1 from public.rules where key = 'item_images_mode') then miss := miss || ' 102'; end if;
  if to_regclass('public.rules') is null or not exists (select 1 from public.rules where key = 'acct_manual_prod_in103') then miss := miss || ' 103'; end if;
  if miss <> '' then raise exception 'phase108 needs phases 72..103 pasted first (see docs/PASTE_ORDER.md); missing:%', miss; end if;
