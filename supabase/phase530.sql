-- Phase 530 (UNION-2: lock_check keeps the owner mode of the advanced line (bos113) on top of our hooks (bos87, bos89)). Paste-twice safe. Earlier phase files are not edited.
-- What: lock_check(date) gets the bos113 owner mode back. The advanced line wrote it in phase113 (rule period_lock_owner_mode = off | warn: with warn the owner may still change a closed
--   period, as before, but a yellow exception `closed_period_owner` is written, once a day per date). Our hooks (bos87 one-off exception, bos89 period integrity with the owner mode
--   owner_closed_period_mode off | log | reason) stay exactly as they are; the bos113 block runs only after our check allowed the date. Both rules default to off, so nothing changes until the owner chooses.
-- Why a separate file: phase529 had to put the phase 6 text back so that our hooks (exact text) could be applied; this file puts bos113 on top of the hooked body.
-- How it works (all UNION files 530 to 539 do the same): each function is looked at first. If it already has the merged text: nothing. If it has a KNOWN older text (the text our chain or the advanced
--   chain or the earlier live paste produced, by md5): it is replaced by the merged text and the old text is saved in public._union_fn_backup. If it has an unknown text: the patch sites of the
--   fallback are looked for; if they are not all there, ALL such functions are listed in ONE message and nothing is changed.
-- Paste AFTER phase529 and after phase 505 (end of the chain). Safe to paste twice, safe to paste again after an old phase was pasted again.

create table if not exists public._union_fn_backup (id bigserial primary key, fn text not null, saved_at timestamptz not null default now(), why text, def text not null);
alter table public._union_fn_backup enable row level security;
revoke all on public._union_fn_backup from anon, authenticated;

drop table if exists _u_plan;
create temp table _u_plan (seq serial primary key, fn text not null, kind text not null, a text not null, b text);
-- lock_check(date)
insert into _u_plan (fn, kind, a, b) values
  ('public.lock_check(date)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.lock_check(p_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v text; d date; om text;
begin
  if p_date is null then return; end if;
  if public._w1b_lock_allowed(p_date) then   -- bos89: pure date test, owner mode, override windows
    if public.is_owner() and coalesce(public.rule_txt('period_lock_owner_mode'), 'off') = 'warn' then   -- bos113: warn = the owner may still change a closed period but it is written down as a yellow exception
      v := public.rule_txt('period_closed_until');
      if v is not null and v ~ '^\d{4}-\d{2}-\d{2}$' then
        begin d := v::date; exception when others then d := null; end;
        if d is not null and p_date <= d
           and not exists (select 1 from public.exceptions x where x.flag_code = 'closed_period_owner' and x.entry_date = p_date and x.created_at > now() - interval '1 day') then
          perform public._stock_exc((select min(l.id) from public.locations l), 'closed_period_owner', 'yellow', 'মালিক বন্ধ হিসাবকালে (' || p_date::text || ') পরিবর্তন করেছেন',
            'The owner changed a closed period (date ' || p_date::text || ')', null, p_date, 'ACCOUNTS', null);
        end if;
      end if;
    end if;
    return;
  end if;
  raise exception 'period_closed';                            -- bos89: the statements below are the old body and are not reached any more
  v := public.rule_txt('period_closed_until');
  if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then return; end if;
  begin d := v::date; exception when others then return; end;      -- an impossible date (2026-02-30) locks nobody out
  if p_date > d then return; end if;
  if public.rule_ok('closed_period_edit', null, null, p_date, 'entry') then return; end if;
  if public._m_lock_exc(p_date) then return; end if;   -- bos87: an owner granted one-off exception (reason on record, shown in the Exceptions list)
  raise exception 'period_closed';
end $function$$r0_0$, null),
  ('public.lock_check(date)', 'known', '7627a1d055031d926293f90fbf2570ee', null),
  ('public.lock_check(date)', 'known', '78b7ce236462f7e613a1ee22870eb31f', null),
  ('public.lock_check(date)', 'known', 'e2722a7e428097f826c9c321ea568d44', null),
  ('public.lock_check(date)', 'old', $o0_0$AS $function$
declare v text; d date;
begin
  if p_date is null then return; end if;
  if public._w1b_lock_allowed(p_date) then return; end if;   -- bos89: pure date test, owner mode, override windows
  raise exception 'period_closed';                            -- bos89: the statements below are the old body and are not reached any more$o0_0$, $n0_0$AS $function$
declare v text; d date; om text;
begin
  if p_date is null then return; end if;
  if public._w1b_lock_allowed(p_date) then   -- bos89: pure date test, owner mode, override windows
    if public.is_owner() and coalesce(public.rule_txt('period_lock_owner_mode'), 'off') = 'warn' then   -- bos113: warn = the owner may still change a closed period but it is written down as a yellow exception
      v := public.rule_txt('period_closed_until');
      if v is not null and v ~ '^\d{4}-\d{2}-\d{2}$' then
        begin d := v::date; exception when others then d := null; end;
        if d is not null and p_date <= d
           and not exists (select 1 from public.exceptions x where x.flag_code = 'closed_period_owner' and x.entry_date = p_date and x.created_at > now() - interval '1 day') then
          perform public._stock_exc((select min(l.id) from public.locations l), 'closed_period_owner', 'yellow', 'মালিক বন্ধ হিসাবকালে (' || p_date::text || ') পরিবর্তন করেছেন',
            'The owner changed a closed period (date ' || p_date::text || ')', null, p_date, 'ACCOUNTS', null);
        end if;
      end if;
    end if;
    return;
  end if;
  raise exception 'period_closed';                            -- bos89: the statements below are the old body and are not reached any more$n0_0$);
do $u530$
declare f record; r record; cur text; body text; rbody text; miss text := ''; st text; nfix int := 0; ok boolean;
begin
  -- Every function of this file is looked at first. A function is in one of these states: DONE (already the merged text), KNOWN (a known older text of one of the two lines: it is replaced by the
  -- merged text), PATCH (not a known text, but every patch site of the fallback is found), MISSING (nothing fits). ALL missing ones are listed in ONE message and nothing is changed.
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then continue; end if;     -- the function does not exist yet: it is created below
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then continue; end if;
    ok := exists (select 1 from _u_plan where fn = f.fn and kind = 'old');
    body := cur;
    for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
      if position(r.b in body) > 0 then continue; end if;
      if position(r.a in body) = 0 then ok := false; exit; end if;
      body := overlay(body placing r.b from position(r.a in body) for length(r.a));
    end loop;
    if not ok then miss := miss || E'\n  ' || f.fn || ' (the text in this database is not one of the known texts and the patch sites are not all there; md5 ' || md5(cur) || ')'; end if;
  end loop;
  if miss <> '' then raise exception 'phase530: these functions have an unknown text, nothing was changed. Send this message to the agent:%', miss; end if;
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then
      execute rbody; nfix := nfix + 1; continue;
    end if;
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    insert into public._union_fn_backup (fn, why, def) values (f.fn, 'phase530: merged text of the two lines', cur);
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then
      execute rbody;
    else
      body := cur;
      for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
        if position(r.b in body) > 0 then continue; end if;
        body := overlay(body placing r.b from position(r.a in body) for length(r.a));
      end loop;
      execute body;
    end if;
    nfix := nfix + 1;
  end loop;
  raise notice 'phase530: % function(s) changed', nfix;
end $u530$;
drop table if exists _u_plan;
