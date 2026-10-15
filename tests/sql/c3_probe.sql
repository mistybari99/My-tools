-- C3 differential leak probe (used by phase133_test and by hand). Needs the scaffold tests/sql/e2e/00_common.sql (tt.*), a database built through phase123 and 
-- (personas = rows 'persona_<name>' of c3.ids holding user ids of business A). The ids of the rows of business B go to c3.ids(kind, v) as '<kind>_b' before the S2 snapshot.
-- c3.probe(snap): for every exposed SECURITY DEFINER function, as the three personas, call it (inside a sub-transaction that is ALWAYS rolled back) with
--   v0       required arguments NULL, the rest default              (S1 = only A has data, S2 = B has data too: the answer must not change)
--   vP / vPX every place / business argument set to a B id / to an id that does not exist   (S2: a B id must look exactly like a missing one)
--   vI:<k>/vIX:<k> every other id argument set to the id of a B row of kind k / to a missing id (same rule)
-- Answers are reduced to 'ERR' (refused or failed), 'EMPTY' or md5:length of the text with timestamps removed. Rows go to c3.probe_out.
create schema if not exists c3;
drop table if exists c3.probe_out; create table c3.probe_out (snap text, fn text, persona text, variant text, out text);
drop table if exists c3.ids; create table c3.ids (kind text primary key, v text);
grant usage on schema c3 to authenticated, anon; grant select, insert on c3.probe_out to authenticated, anon; grant select on c3.ids to authenticated, anon;

create or replace function c3.run(p_sql text) returns text language plpgsql as $$
declare r text;
begin
  begin
    execute p_sql into r;
    raise exception using errcode = 'C3001', message = coalesce(r, 'NULL');
  exception when sqlstate 'C3001' then r := sqlerrm;
            when others then return 'ERR';
  end;
  r := regexp_replace(r, '"?[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9:.]+([+-][0-9]{2}(:?[0-9]{2})?|Z)?"?', '"TS"', 'g');
  if r in ('NULL', 'null', '[]', '{}', '0', 'false', '') then return 'EMPTY'; end if;
  return md5(r) || ':' || length(r);
end $$;

-- a plausible value for an argument that is not an id (dates, limits, flags ...); null when nothing sensible is known
create or replace function c3.plain(p_type regtype, p_name text) returns text language plpgsql as $$
declare t text := p_type::text; n text := lower(coalesce(p_name, ''));
begin
  if t = 'date' then return case when n ~ 'from|start|since' then '(current_date - 30)' else 'current_date' end || '::date';
  elsif t like 'timestamp%' then return case when n ~ 'from|start|since' then '(now() - interval ''30 days'')' else 'now()' end || '::' || t;
  elsif t in ('integer', 'smallint', 'bigint') then
    if n ~ 'limit|size' then return '50::' || t; elsif n ~ 'page' then return '1::' || t; elsif n ~ 'offset' then return '0::' || t; elsif n ~ 'days|ahead|lookback' then return '30::' || t;
    elsif n ~ 'months' then return '3::' || t; elsif n ~ 'year' then return '2026::' || t; elsif n ~ 'minutes|hours' then return '10::' || t; end if;
    return null;
  elsif t = 'numeric' then return '1::numeric';
  elsif t = 'boolean' then return 'false';
  elsif t = 'jsonb' then return '''{}''::jsonb';
  end if;
  return null;
end $$;

-- literal for one argument. p_mode: N = places null, A = places of business A, P = places of B, I = ids of B rows (places of A); p_who: 'B' foreign row, 'X' missing row; p_gk = kind used for a generic id argument (p_id ...)
create or replace function c3.lit(p_type regtype, p_name text, p_mode text, p_who text, p_gk text, p_fn text default '') returns text language plpgsql as $$
declare k text; v text; t text := p_type::text; n text := lower(coalesce(p_name, ''));
begin
  if t in ('integer', 'smallint', 'bigint') and ((n ~ 'loc|place|site|showroom|org|business|biz|unit' and n !~ 'limit') or (n = 'p_id' and p_fn ~ '^location')) then
    if p_mode = 'N' then return null; end if;
    if p_mode in ('A', 'I') then
      select c.v into v from c3.ids c where c.kind = case when n ~ 'org|business|biz|unit' then 'biz_a' else 'loc_a' end;
      return coalesce(quote_literal(v), 'null') || '::' || t;
    end if;
    k := case when n ~ 'org|business|biz|unit' then 'biz' else 'loc' end;
  elsif t in ('integer', 'smallint', 'bigint') and n !~ 'limit|page|size|days|offset|months|minutes|hours|count|step|sort|year|ahead|lookback' then
    if p_mode <> 'I' then return null; end if;
    k := case when n ~ 'run' then 'payrun' when n ~ 'channel' then 'chan' else p_gk end;
  elsif t = 'uuid' then
    if p_mode <> 'I' or n ~ 'client' then return null; end if;
    k := case when n ~ 'cust' then 'cust' when n ~ 'suppl' then 'sup' when n ~ 'sale' then 'sale' when n ~ 'emp' then 'emp' when n ~ 'entry' then 'entry' when n ~ 'bill|purch' then 'pur'
              when n ~ 'user|profile' then 'user' when n ~ 'asset' then 'fa' when n ~ 'item' then null else p_gk end;
    if k is null then return null; end if;
  else return null; end if;
  if p_who = 'X' then return case when t = 'uuid' then '''00000000-0000-0000-0000-00000000dead''' else '999999' end || '::' || t; end if;
  select c.v into v from c3.ids c where c.kind = k || '_b';
  if v is null then return case when t = 'uuid' then '''00000000-0000-0000-0000-00000000dead''' else '999999' end || '::' || t; end if;
  return quote_literal(v) || '::' || t;
end $$;

create or replace function c3.probe(p_snap text) returns void language plpgsql as $$
declare f record; pr record; var text; call_ text; args text; i int; nm text[]; ty oid[]; npar int; ndef int; lit text; mode_ text; who text; gk text; res text; gks text[]; sep text; gu boolean; gb boolean; sp boolean; tn text;
begin
  for f in select p.oid, p.proname, p.proargnames, p.proargtypes::oid[] as tys, p.pronargs, p.pronargdefaults, p.proretset, p.prorettype::regtype::text as rt
             from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute')
              and p.prorettype <> 'trigger'::regtype and p.proargmodes is null
              and p.proname not in ('login_failed', 'login_success', 'unlock_staff', 'set_pin', 'backup_log', 'set_my_lang', 'scope_gaps133') order by p.proname, p.oid loop
    npar := f.pronargs; ndef := f.pronargdefaults; nm := f.proargnames; ty := f.tys;
    if npar > 0 and (nm is null or array_length(nm, 1) < npar or exists (select 1 from unnest(nm) x where x is null or x = '')) then continue; end if;
    gu := false; gb := false; sp := false;
    for i in 1..npar loop
      tn := ty[i - 1]::regtype::text;
      if tn = 'uuid' and nm[i] !~* 'client|cust|suppl|sale|emp|entry|bill|purch|user|profile|asset|item' then gu := true; end if;
      if tn in ('uuid', 'integer', 'bigint', 'smallint') and nm[i] ~* 'cust|suppl|sale|emp|entry|bill|purch|user|profile|asset|run|channel' and nm[i] !~* 'client|limit' then sp := true; end if;
      if tn in ('integer', 'bigint', 'smallint') and nm[i] !~* 'loc|place|site|showroom|org|business|biz|unit|limit|page|size|days|offset|months|minutes|hours|count|step|sort|year|ahead|lookback|run|channel' and not (nm[i] = 'p_id' and f.proname ~ '^location') then gb := true; end if;
    end loop;
    for pr in select substr(c.kind, 9) as persona, c.v as uid from c3.ids c where c.kind like 'persona\_%' order by c.kind loop
      perform set_config('request.jwt.claim.sub', pr.uid, false);
      foreach var in array array['v0', 'vA', 'vP', 'vPX', 'vI', 'vIX'] loop
        if p_snap = 'S1' and var not in ('v0', 'vA') then continue; end if;
        if var not in ('v0', 'vA') and pr.persona <> 'a_super' then continue; end if;          -- the foreign-id attacks are run by the persona that holds every right
        mode_ := case var when 'v0' then 'N' when 'vA' then 'A' when 'vP' then 'P' when 'vPX' then 'P' else 'I' end; who := case when var in ('vP', 'vI') then 'B' else 'X' end;
        gks := case when var in ('vI', 'vIX') then (case when gu then array['sale', 'pur', 'entry', 'emp', 'cust', 'sup', 'fa', 'oo'] else '{}'::text[] end || case when gb then array['payrun', 'notif', 'exc', 'inb', 'emreq'] else '{}'::text[] end || array['']) else array[''] end;
        foreach gk in array gks loop
          args := ''; sep := '';
          for i in 1..npar loop
            lit := c3.lit(ty[i - 1]::regtype, nm[i], mode_, who, gk, f.proname);
            if lit is null then lit := c3.plain(ty[i - 1]::regtype, nm[i]); end if;
            if lit is null and i <= npar - ndef then lit := 'null::' || ty[i - 1]::regtype::text; end if;
            if lit is not null then args := args || sep || quote_ident(nm[i]) || ' => ' || lit; sep := ', '; end if;
          end loop;
          if var in ('vP', 'vPX') and args !~ '=> (''?[0-9]+''?::)' then exit; end if;
          if var in ('vI', 'vIX') and (not (gu or gb or sp) or (gk = '' and (gu or gb))) then continue; end if;
          if f.proretset or f.rt = 'record' then call_ := format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb)::text from public.%I(%s) t', f.proname, args);
          else call_ := format('select to_jsonb(public.%I(%s))::text', f.proname, args); end if;
          res := c3.run(call_);
          insert into c3.probe_out values (p_snap, f.proname || '(' || pg_get_function_identity_arguments(f.oid) || ')', pr.persona, case when gk = '' then var else var || ':' || gk end, res);
        end loop;
      end loop;
    end loop;
  end loop;
end $$;
grant execute on all functions in schema c3 to authenticated, anon;
