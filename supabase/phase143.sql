-- Phase 143 (bos143) - W1-FIX re-patch: ONE call that puts every hook of phases 140 to 142 (W1-FIX) back, and a state check. Paste after phase142, paste-twice safe.
-- Earlier phase files are not edited. It changes no behaviour of its own.
--
-- WHY: phases 140 to 142 patch four old functions (void_sale, _w1e_pay_gate, employee_link_profile, employee_status_set) by exact text, like the Wave 1 hooks of
-- phase99. Pasting an OLD phase again (phase3/6 void_sale, phase94 _w1e_pay_gate, phase41 employee functions) replaces the function and the hook line is gone.
-- After such a paste run, in this order:   select public._i1_apply_hooks();   select public._w1x_apply_hooks();
-- Both are idempotent (a hook that is already inside is reported false and nothing is rewritten). Details: docs/integration/W1-FIX.md.

do $g$ begin
  if to_regprocedure('public._w1x_present140()') is null or to_regprocedure('public._w1x_present141()') is null or to_regprocedure('public._w1x_present142()') is null then
    raise exception 'phase143 needs phases 140, 141 and 142 pasted first';
  end if;
end $g$;

create or replace function public._w1x_present143() returns boolean language sql immutable as $$ select true $$;

-- the (function, marker) pairs W1-FIX expects
create or replace function public._w1x_expect() returns table (fn text, marker text) language sql immutable as $$
  values ('public.void_sale(uuid,text)'::text, 'bos140'::text),
         ('public._w1e_pay_gate(uuid,integer,jsonb,uuid,text,numeric)', 'bos141'),
         ('public.employee_link_profile(uuid,uuid)', 'bos142'),
         ('public.employee_status_set(uuid,text,date,text)', 'bos142')
$$;

create or replace function public._w1x_hooks_state() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('fn', e.fn, 'marker', e.marker,
           'present', to_regprocedure(e.fn) is not null and position(e.marker in pg_get_functiondef(to_regprocedure(e.fn))) > 0) order by e.fn, e.marker), '[]'::jsonb)
    from public._w1x_expect() e
$$;

-- one statement: if a patch site is missing the whole call stops and nothing is half patched
create or replace function public._w1x_apply_hooks() returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb; bad text;
begin
  res := public._w1x140_hooks() || public._w1x141_hooks() || public._w1x142_hooks();
  select string_agg(x ->> 'fn' || ' (' || (x ->> 'marker') || ')', ', ') into bad from jsonb_array_elements(public._w1x_hooks_state()) x where not (x ->> 'present')::boolean;
  if bad is not null then raise exception 'w1x hooks missing after patching: %', bad; end if;
  return res;
end $$;
revoke all on function public._w1x_present143(), public._w1x_expect(), public._w1x_hooks_state(), public._w1x_apply_hooks() from public, anon, authenticated;

select public._w1x_apply_hooks();
