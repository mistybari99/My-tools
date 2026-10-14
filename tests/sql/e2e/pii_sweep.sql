create or replace function tt.sweep_run2(p_who uuid, p_label text, fp text) returns void language plpgsql as $f$
declare r record; a text; res text; i int; arglist text[]; nm text; ty text; v text; okk boolean; er text; lk text;
begin
  perform set_config('request.jwt.claim.sub', p_who::text, false);
  for r in select p.oid, p.proname, p.pronargs, p.proargnames, p.proargtypes from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='public' and p.proname !~ '^_' and p.prokind='f' and has_function_privilege('authenticated', p.oid, 'execute')
              and p.proname not in ('report_fact_rebuild','backup_stock_ledger','backup_stock_balance') order by p.proname, p.oid loop
    arglist := '{}';
    for i in 1..r.pronargs loop
      nm := coalesce(r.proargnames[i], ''); ty := (select typname from pg_type where oid = r.proargtypes[i-1]);
      v := 'null';
      if ty = 'uuid' then
        v := case when nm ~ 'item' then format('%L', tt.cx('cake')) when nm ~ 'sale' then format('%L', tt.cx('sale')) when nm ~ 'order' then format('%L', tt.cx('oo')) when nm ~ '(user|emp)' then format('%L', p_who::text) when nm ~ 'p_id' then format('%L', tt.cx('oo')) else 'null' end;
      elsif ty = 'int4' then v := case when nm ~ 'loc' then '1' when nm ~ 'limit' then '50' when nm ~ 'days' then '30' else 'null' end;
      elsif ty = 'int8' then v := case when nm ~ 'limit' then '50' when nm ~ '(msg|p_id)' then '1' else 'null' end;
      elsif ty = 'date' then v := case when nm ~ 'from' then format('%L', tt.today()-10) else format('%L', tt.today()) end;
      elsif ty = 'text' then v := case when nm ~ 'mobile' then '''01811000001''' else 'null' end;
      end if;
      arglist := arglist || (v || '::' || format_type(r.proargtypes[i-1], null));
    end loop;
    a := array_to_string(arglist, ',');
    okk := false; er := null; lk := null; res := null;
    begin
      execute format('select coalesce(string_agg(to_jsonb(x)::text, '' ''), '''') from public.%I(%s) x', r.proname, a) into res;
      okk := true; lk := (regexp_match(res, '(.{0,25}(' || fp || ').{0,15})'))[1];
      raise exception 'e2e_rollback';
    exception when others then
      if sqlerrm <> 'e2e_rollback' then okk := false; er := left(sqlerrm, 80); end if;
    end;
    insert into tt.sweep values (p_label, r.proname || '(' || r.pronargs || ')', left(a,200), lk, okk, er);
  end loop;
end $f$;
grant execute on function tt.sweep_run2(uuid, text, text) to authenticated;
delete from tt.sweep;
set role authenticated;
select tt.sweep_run2('00000000-0000-0000-0000-000000000006'::uuid, 'bot', '01811000001|01711000111|Web Cust|Customer A|Dhaka 5');
select tt.sweep_run2('00000000-0000-0000-0000-000000000004'::uuid, 'seller', '01811000001|01711000111|Dhaka 5');
select tt.sweep_run2('00000000-0000-0000-0000-000000000005'::uuid, 'keeper', '01811000001|01711000111|Web Cust|Customer A|Dhaka 5');
reset role;
select who, fn, leaked from tt.sweep where leaked is not null order by 1,2;
