-- Leak sweep of phase 134 (used by phase134_test and by hand). Needs tests/sql/e2e/00_common.sql (tt.*), tests/sql/c3_probe.sql (c3.lit / c3.plain / c3.ids) and the c3 seed.
-- l134.scan_fn(snap): for every exposed function (the same set and argument builder as c3.probe), as every persona 'persona_*' of c3.ids, call it inside a sub-transaction that is ALWAYS
--   rolled back with  v0 (required arguments NULL)  vA (own place / business ids)  vP (ids of business B)  vPX (ids that do not exist); the OUTPUT TEXT and the ERROR TEXT are stored in
--   l134.probe. l134.scan_tables(snap): every table / view the browser may select from, read as every persona (column grants respected), the whole text is stored.
--   l134.tokens(grp, token, cs): strings that must NOT appear for a persona group ('A' = people of business A: group, legal entity, business B ...). cs = case sensitive.
-- Afterwards  select * from l134.hits  lists every function / table / persona that showed a forbidden token, and  l134.errdiff  the functions whose error text for a foreign id differs from the
-- text for a missing id (an existence oracle).
create schema if not exists l134;
drop table if exists l134.probe; create table l134.probe (snap text, kind text, fn text, persona text, variant text, ok boolean, txt text);
drop table if exists l134.tokens; create table l134.tokens (grp text, token text, cs boolean default false);
grant usage on schema l134 to authenticated, anon; grant select, insert on l134.probe to authenticated, anon; grant select on l134.tokens to authenticated, anon;

create or replace function l134.run(p_sql text, out ok boolean, out txt text) language plpgsql as $$
begin
  begin
    execute p_sql into txt;
    raise exception using errcode = 'C3001', message = coalesce(txt, 'NULL');
  exception when sqlstate 'C3001' then ok := true; txt := sqlerrm;
            when others then ok := false; txt := sqlerrm;
  end;
end $$;

create or replace function l134.scan_fn(p_snap text, p_skip text[] default '{}') returns void language plpgsql as $$
declare f record; pr record; var text; call_ text; args text; i int; nm text[]; ty oid[]; npar int; ndef int; lit text; mode_ text; who text; sep text; r record;
begin
  for f in select p.oid, p.proname, (select array_agg(x.n order by x.i) from unnest(p.proargnames, coalesce(p.proargmodes, array_fill('i'::"char", array[coalesce(array_length(p.proargnames, 1), 0)]))) with ordinality x(n, m, i) where x.m in ('i', 'b', 'v')) as proargnames,
                  p.proargtypes::oid[] as tys, p.pronargs, p.pronargdefaults, p.proretset, p.prorettype::regtype::text as rt
             from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('authenticated', p.oid, 'execute')
              and p.prorettype <> 'trigger'::regtype and (p.proargmodes is null or p.proargmodes <@ array['i', 't']::"char"[])
              and p.proname not in ('login_failed', 'login_success', 'unlock_staff', 'set_pin', 'backup_log', 'set_my_lang', 'scope_gaps133') and p.proname <> all (p_skip) order by p.proname, p.oid loop
    npar := f.pronargs; ndef := f.pronargdefaults; nm := f.proargnames; ty := f.tys;
    if npar > 0 and (nm is null or array_length(nm, 1) < npar or exists (select 1 from unnest(nm) x where x is null or x = '')) then continue; end if;
    for pr in select substr(c.kind, 9) as persona, c.v as uid from c3.ids c where c.kind like 'persona\_%' order by c.kind loop
      perform set_config('request.jwt.claim.sub', pr.uid, false);
      foreach var in array array['v0', 'vA', 'vP', 'vPX'] loop
        mode_ := case var when 'v0' then 'N' when 'vA' then 'A' else 'P' end; who := case when var = 'vP' then 'B' else 'X' end;
        args := ''; sep := '';
        for i in 1..npar loop
          lit := c3.lit(ty[i - 1]::regtype, nm[i], mode_, who, '', f.proname);
          if lit is null then lit := c3.plain(ty[i - 1]::regtype, nm[i]); end if;
          if lit is null and i <= npar - ndef then lit := 'null::' || ty[i - 1]::regtype::text; end if;
          if lit is not null then args := args || sep || quote_ident(nm[i]) || ' => ' || lit; sep := ', '; end if;
        end loop;
        if var in ('vP', 'vPX') and args !~ '=> (''?[0-9]+''?::)' then exit; end if;
        if f.proretset or f.rt = 'record' then call_ := format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb)::text from public.%I(%s) t', f.proname, args);
        else call_ := format('select to_jsonb(public.%I(%s))::text', f.proname, args); end if;
        select * into r from l134.run(call_);
        insert into l134.probe values (p_snap, 'fn', f.proname || '(' || pg_get_function_identity_arguments(f.oid) || ')', pr.persona, var, r.ok, r.txt);
      end loop;
    end loop;
  end loop;
end $$;

create or replace function l134.scan_tables(p_snap text) returns void language plpgsql as $$
declare t record; pr record; cols text; r record; ncol int;
begin
  for t in select c.oid, c.relname from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p') and has_any_column_privilege('authenticated', c.oid, 'select') order by c.relname loop
    select string_agg(quote_ident(a.attname), ', ' order by a.attnum), count(*) into cols, ncol from pg_attribute a
     where a.attrelid = t.oid and a.attnum > 0 and not a.attisdropped and has_column_privilege('authenticated', t.oid, a.attnum, 'select');
    if cols is null then continue; end if;
    for pr in select substr(c.kind, 9) as persona, c.v as uid from c3.ids c where c.kind like 'persona\_%' order by c.kind loop
      perform set_config('request.jwt.claim.sub', pr.uid, false);
      select * into r from l134.run(format('select coalesce(string_agg(to_jsonb(x)::text, '' ''), '''') from (select %s from public.%I limit 3000) x', cols, t.relname));
      insert into l134.probe values (p_snap, 'tbl', t.relname, pr.persona, 'sel', r.ok, r.txt);
    end loop;
  end loop;
end $$;
grant execute on all functions in schema l134 to authenticated, anon;

-- which persona belongs to which token group
create or replace function l134.grp_of(p_persona text) returns text language sql immutable as $$ select case when p_persona like 'a\_%' then 'A' when p_persona like 'b\_%' then 'B' end $$;
create or replace view l134.hits as
  select p.snap, p.kind, p.fn, p.persona, p.variant, t.token, left(regexp_replace(p.txt, '\s+', ' ', 'g'), 120) as txt
    from l134.probe p join l134.tokens t on t.grp = l134.grp_of(p.persona)
   where p.txt is not null and case when t.cs then position(t.token in p.txt) > 0 else position(lower(t.token) in lower(p.txt)) > 0 end;
-- error text for a foreign id vs a missing id (the same persona, same function)
create or replace view l134.errdiff as
  select b.snap, b.fn, b.persona, b.txt as foreign_txt, x.txt as missing_txt
    from l134.probe b join l134.probe x on x.snap = b.snap and x.fn = b.fn and x.persona = b.persona and x.variant = 'vPX' and x.kind = 'fn'
   where b.variant = 'vP' and b.kind = 'fn' and not b.ok and not x.ok and b.txt is distinct from x.txt;
grant select on all tables in schema l134 to authenticated, anon;
