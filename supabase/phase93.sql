-- ============================================================
-- Phase 93 (bos93) - STEP Tpl: selectable print / message templates per document type (and optionally per location).
--   Needs only the base schema (guard below: is_owner, is_active, audit_log, locations). Additive, paste-twice safe: one table, two functions, nothing else is touched.
--   The templates themselves live in the web app (web/tpl_*.js); the database only remembers WHICH template id the owner picked.
--   No row = no choice = today's output, unchanged (the app falls back to what it printed before).
--   A location row beats the all-locations row (location_id null) of the same document type.
--   set_doc_template is owner-only; passing a null template clears the choice (back to today's output). Every change is written to audit_log.
-- ============================================================

do $g$ begin
  if to_regprocedure('public.is_owner()') is null or to_regprocedure('public.is_active()') is null
     or to_regclass('public.audit_log') is null or to_regclass('public.locations') is null then
    raise exception 'phase93 needs the base schema (is_owner, is_active, audit_log, locations)';
  end if;
end $g$;

create table if not exists public.doc_template_choice (
  id          bigserial primary key,
  doc_type    text not null check (doc_type ~ '^[a-z][a-z0-9_]{1,40}$'),
  location_id int references public.locations(id),
  template_id text not null check (template_id ~ '^[a-z][a-z0-9_]{1,40}$'),
  set_by      uuid,
  set_at      timestamptz not null default now()
);
-- one choice per document type and place (null location = all locations)
create unique index if not exists doc_template_choice_uq on public.doc_template_choice (doc_type, coalesce(location_id, 0));

alter table public.doc_template_choice enable row level security;
drop policy if exists doc_template_choice_read on public.doc_template_choice;
create policy doc_template_choice_read on public.doc_template_choice for select to authenticated using (public.is_active());
-- nobody writes the table directly; the owner goes through set_doc_template
revoke insert, update, delete, truncate on public.doc_template_choice from public, anon, authenticated;
grant select on public.doc_template_choice to authenticated;

create or replace function public.set_doc_template(p_doc_type text, p_template_id text, p_location_id int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old text; sid text;
begin
  if not public.is_owner() then raise exception 'owner_only'; end if;
  if p_doc_type is null or p_doc_type !~ '^[a-z][a-z0-9_]{1,40}$' then raise exception 'bad_doc_type'; end if;
  if p_template_id is not null and p_template_id !~ '^[a-z][a-z0-9_]{1,40}$' then raise exception 'bad_template_id'; end if;
  if p_location_id is not null and not exists (select 1 from public.locations where id = p_location_id) then raise exception 'bad_location'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  select template_id into old from public.doc_template_choice where doc_type = p_doc_type and coalesce(location_id, 0) = coalesce(p_location_id, 0);
  if p_template_id is null then
    delete from public.doc_template_choice where doc_type = p_doc_type and coalesce(location_id, 0) = coalesce(p_location_id, 0);
  else
    insert into public.doc_template_choice (doc_type, location_id, template_id, set_by, set_at) values (p_doc_type, p_location_id, p_template_id, auth.uid(), now())
    on conflict (doc_type, (coalesce(location_id, 0))) do update set template_id = excluded.template_id, set_by = excluded.set_by, set_at = excluded.set_at;
  end if;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)   -- bos93
    values (auth.uid(), sid, case when p_template_id is null then 'doc_template_clear' else 'doc_template_set' end, 'doc_template_choice', p_doc_type || ':' || coalesce(p_location_id::text, 'all'),
            jsonb_build_object('doc_type', p_doc_type, 'location_id', p_location_id, 'old', old, 'new', p_template_id, 'src', 'phase93'));
  return jsonb_build_object('doc_type', p_doc_type, 'location_id', p_location_id, 'template_id', p_template_id, 'old', old);
end $$;
revoke all on function public.set_doc_template(text, text, int) from public, anon;
grant execute on function public.set_doc_template(text, text, int) to authenticated;

-- every saved choice (small table). The app resolves: this location first, then the all-locations row, else nothing (= today's output).
create or replace function public.get_doc_templates(p_location_id int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('doc_type', c.doc_type, 'location_id', c.location_id, 'template_id', c.template_id, 'set_at', c.set_at,
                    'effective', (c.location_id is null and not exists (select 1 from public.doc_template_choice x where x.doc_type = c.doc_type and x.location_id = p_location_id))
                                 or c.location_id = p_location_id) order by c.doc_type, c.location_id nulls first)
                   from public.doc_template_choice c), '[]'::jsonb);
end $$;
revoke all on function public.get_doc_templates(int) from public, anon;
grant execute on function public.get_doc_templates(int) to authenticated;
