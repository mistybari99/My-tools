-- ============================================================
-- Phase 17 (W5a): ROLLOUT (paper / parallel / app per form x place), PAPER + APP TOGETHER (entered later + paper serial),
--                 LOCK / REVISIONS / CHANGE REQUESTS, OWNER SELF-APPROVAL SWITCH, idempotent client_id for the form offline queue.
--   Additive and safe to run twice; paste the whole file into the Supabase SQL editor.  Needs phase8..phase14.  Does NOT need phase15 / 16
--   (the rule owner_self_approve is the same key phase15 / 16 use: inserted here only when it is missing).
--   * form_rollout(form_code, location_id, mode paper | parallel | app, note, changed_by, changed_at): every existing form x place starts 'app'
--     (live forms stay in the app).  A missing row means 'app'.  RPC rollout_set / rollout_set_many: owner or the delegable grant rollout_manage; audit-logged.
--     Enforcement on the server: a BEFORE INSERT trigger on entries (like the pause trigger of phase16) refuses a NEW app entry where the mode is
--     'paper', unless it is flagged "entered later from paper" with a paper serial and the original time.  'parallel' and 'app' are allowed.
--     Switch rollout_enforce (default ON, acts only on mode 'paper' so nothing existing changes).
--   * entries: + entered_later, paper_serial, paper_at (original time), source ('app' | 'paper_entry'), rev_no, client_id, rollout_mode.
--     The paper serial is the number printed in the paper book: unique per (form, place) (index + the existing data.paper_no index of phase5, the
--     value is mirrored to data.paper_no so the gap audit sees it), the app serial (entries.serial) is software generated: the two never clash.
--     Switch entered_later_on (default ON).  number_audit_both(form, place) reports both series.
--   * save_entry gets an optional 8th argument p_meta jsonb ({client_id, entered_later, paper_serial, paper_at}); the old 7-argument calls keep working.
--     A create with a client_id that already exists returns the existing entry (idempotent re-send from the phone's offline queue).
--   * entry_change_requests + entry_revisions (append-only): after approval an entry is locked; a person who may enter the form asks for a change
--     (entry_change_request), the owner or a holder of the delegable grant change_approve decides (maker <> approver); an approval keeps the old
--     version as revision n and makes revision n+1 current.  entry_revisions_list shows the history.  reopen_entry (owner) also keeps the approved
--     version as a revision.
--   * owner_self_approve (default ON = owner exempt): decide_entry, decide_release, decide_emergency, submit_item_change / decide_item_change honour it.
--     When OFF the owner's own submission needs another approver (another owner, or a delegate: approve right on the form, release_decide,
--     emergency_decide, ITEMS approve / item_create).
-- ============================================================

-- ---------- (0) helpers (same text as phase11 / 16; here so the file stands alone) ----------
create or replace function public.no_hard_delete() returns trigger
language plpgsql set search_path = public as $$
begin raise exception 'nothing is deleted – retire instead'; end $$;

-- ---------- (1) rules and grants ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('rollout_enforce', 'entries', 'switch', 'true', null, null, null, null, 'কাগজ অবস্থায় অ্যাপে নতুন এন্ট্রি আটকানো', 'Paper অবস্থায় app-এ নতুন entry আটকানো', 'Refuse new app entries where the form is on Paper',
   'চালু থাকলে যে ফর্ম × লোকেশন ‘কাগজ’-এ আছে সেখানে সার্ভার নতুন এন্ট্রি নেবে না (কাগজ থেকে ‘পরে তোলা’ ছাড়া)। ‘পাশাপাশি’ ও ‘অ্যাপ’-এ কিছু বদলায় না', 'On থাকলে ‘Paper’ ফর্ম×লোকেশনে server নতুন entry নেবে না (কাগজ থেকে ‘পরে তোলা’ ছাড়া)', 'When on, the server refuses a new entry at a form x place set to Paper (except one entered later from paper). Parallel and App are never blocked', 90),
 ('entered_later_on', 'entries', 'switch', 'true', null, null, null, null, 'কাগজ থেকে ‘পরে তোলা’ এন্ট্রি চালু', 'কাগজ থেকে ‘পরে তোলা’ entry চালু', 'Allow "entered later from paper" entries',
   'বাইরে কাজ করা কেউ আগে কাগজে লিখে পরে অ্যাপে তুলতে পারবেন: কাগজের নম্বর ও আসল সময় লাগে; অনুমোদনে যায়', 'বাইরে কাজ করা কেউ আগে paper-এ লিখে পরে app-এ তুলতে পারবেন: paper number ও আসল সময় লাগে', 'Someone working outside fills the paper and keys it in later: needs the paper serial and the original time; goes to approval like any entry', 91),
 ('change_requests_on', 'entries', 'switch', 'true', null, null, null, null, 'অনুমোদিত এন্ট্রি বদলের অনুরোধ চালু', 'Approved entry বদলের request চালু', 'Allow change requests on approved entries',
   'বন্ধ করলে অনুমোদিত এন্ট্রি বদলের অনুরোধ নেওয়া হবে না (মালিক আগের মতো ‘আবার খুলুন’ ব্যবহার করবেন)', 'Off করলে approved entry বদলের request নেওয়া হবে না', 'When off, change requests are refused (the owner still has Reopen)', 92),
 ('entered_later_max_days', 'entries', 'number', null, 'days', null, 0, 3650, 'পরে তোলা এন্ট্রি: কাগজের আসল তারিখ সর্বোচ্চ কত দিন আগের (ফাঁকা = সীমা নেই)', 'পরে তোলা entry: paper-এর আসল date সর্বোচ্চ কত দিন আগের (ফাঁকা = Data needed)', 'Entered later: oldest allowed paper date, in days (blank = Data needed / no limit)',
   'ফাঁকা থাকলে কোনো সীমা নেই। দিলে: তার চেয়ে পুরনো কাগজ শুধু মালিক তুলতে পারবেন (লাল এক্সেপশনসহ)', 'ফাঁকা = no limit। দিলে: তার চেয়ে পুরনো paper শুধু owner তুলতে পারবেন (red exception সহ)', 'Blank = no limit. When set, older paper can be entered by the owner only (with a red exception)', 93),
 ('owner_self_approve', 'lists', 'switch', 'true', null, null, null, null, 'মালিক নিজের অনুরোধ নিজে অনুমোদন করতে পারবেন', 'Owner নিজের request নিজে approve করতে পারবেন', 'Owner may approve their own request',
   'বন্ধ করলে মালিকের অনুরোধও অন্য অনুমতিপ্রাপ্ত কেউ অনুমোদন করবেন', 'Off করলে owner-এর request অন্য কেউ approve করবেন', 'When off, the owner''s own requests need another approver', 50)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('rollout_manage', 'master', 66, 'ফর্ম × লোকেশন: কাগজ / পাশাপাশি / অ্যাপ বদলানো', 'Form × location: Paper / Parallel / App বদলানো', 'Change a form x place between Paper / Parallel / App', 'window', null),
 ('change_approve', 'master', 67, 'অনুমোদিত এন্ট্রি বদলের অনুরোধ অনুমোদন', 'Approved entry বদলের request approve', 'Approve change requests on approved entries', 'window', null),
 ('release_decide', 'master', 68, 'লাল নিয়ন্ত্রণ ছাড়ের অনুরোধ অনুমোদন', 'Red control release request approve', 'Decide red-control release requests', 'window', null)
on conflict (grant_code) do nothing;

-- ---------- (2) rollout state ----------
create table if not exists public.form_rollout (
  form_code text not null references public.forms(code),
  location_id int not null references public.locations(id),
  mode text not null default 'app' check (mode in ('paper', 'parallel', 'app')),
  note text,
  changed_by uuid, changed_at timestamptz not null default now(),
  primary key (form_code, location_id)
);
alter table public.form_rollout enable row level security;
drop policy if exists form_rollout_read on public.form_rollout;
create policy form_rollout_read on public.form_rollout for select to authenticated using (public.is_active());
revoke all on public.form_rollout from public, anon, authenticated;
grant select on public.form_rollout to authenticated;
drop trigger if exists audit_form_rollout on public.form_rollout;
create trigger audit_form_rollout after insert or update on public.form_rollout for each row execute function public.log_change('form_code,location_id');
drop trigger if exists form_rollout_no_delete on public.form_rollout;
create trigger form_rollout_no_delete before delete on public.form_rollout for each row execute function public.no_hard_delete();

-- every existing form x place starts on the app (live forms stay live); a missing row also means app
insert into public.form_rollout (form_code, location_id, mode, note)
select f.code, l.id, 'app', 'start: live forms stay on the app'
from public.forms f cross join public.locations l
on conflict (form_code, location_id) do nothing;

create or replace function public.rollout_mode(p_form text, p_loc int) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select mode from public.form_rollout where form_code = p_form and location_id = p_loc), 'app');
$$;

create or replace function public._rollout_mgr() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and public.has_grant('rollout_manage'));
$$;

create or replace function public.rollout_set(p_form text, p_loc int, p_mode text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old text;
begin
  if not public._rollout_mgr() then raise exception 'not allowed'; end if;
  if p_mode is null or p_mode not in ('paper', 'parallel', 'app') then raise exception 'bad_mode'; end if;
  if not exists (select 1 from public.forms where code = p_form) then raise exception 'form_not_found'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'location_not_found'; end if;
  old := public.rollout_mode(p_form, p_loc);
  insert into public.form_rollout (form_code, location_id, mode, note, changed_by, changed_at)
    values (p_form, p_loc, p_mode, nullif(left(btrim(coalesce(p_note, '')), 300), ''), auth.uid(), now())
    on conflict (form_code, location_id) do update set mode = excluded.mode, note = excluded.note, changed_by = excluded.changed_by, changed_at = excluded.changed_at;
  return jsonb_build_object('form', p_form, 'location_id', p_loc, 'from', old, 'to', p_mode);
end $$;

-- bulk: null array = all forms / all places
create or replace function public.rollout_set_many(p_forms text[], p_locs int[], p_mode text, p_note text default null) returns int
language plpgsql security definer set search_path = public as $$
declare n int := 0; f text; l int;
begin
  if not public._rollout_mgr() then raise exception 'not allowed'; end if;
  if p_mode is null or p_mode not in ('paper', 'parallel', 'app') then raise exception 'bad_mode'; end if;
  for f in select code from public.forms where p_forms is null or code = any(p_forms) order by code loop
    for l in select id from public.locations where p_locs is null or id = any(p_locs) order by id loop
      perform public.rollout_set(f, l, p_mode, p_note); n := n + 1;
    end loop;
  end loop;
  return n;
end $$;

-- ---------- (3) entries: paper + app together, revision number, client id ----------
alter table public.entries add column if not exists entered_later boolean not null default false;
alter table public.entries add column if not exists paper_serial text;
alter table public.entries add column if not exists paper_at timestamptz;
alter table public.entries add column if not exists source text not null default 'app';
alter table public.entries add column if not exists rev_no int not null default 1;
alter table public.entries add column if not exists client_id uuid;
alter table public.entries add column if not exists rollout_mode text;
alter table public.entries add column if not exists reopen_snap jsonb;      -- the approved version kept at an owner reopen; becomes a revision only if the re-approved entry really differs
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'entries_source_chk') then
    alter table public.entries add constraint entries_source_chk check (source in ('app', 'paper_entry'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'entries_later_chk') then
    alter table public.entries add constraint entries_later_chk check (not entered_later or (nullif(btrim(paper_serial), '') is not null and paper_at is not null));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'entries_rollout_mode_chk') then
    alter table public.entries add constraint entries_rollout_mode_chk check (rollout_mode is null or rollout_mode in ('paper', 'parallel', 'app'));
  end if;
end $$;
create unique index if not exists entries_client_uq on public.entries (client_id) where client_id is not null;
-- the printed number, normalised: upper case, trimmed, leading zeros of each number dropped (A-0101 = a-101 = A-101); once per form and place, apart from the app serial
create or replace function public.norm_paper_serial(p text) returns text
language sql immutable as $$ select nullif(regexp_replace(upper(btrim(coalesce(p, ''))), '(^|[^0-9])0+([0-9])', '\1\2', 'g'), '') $$;
create or replace function public.paper_serial_collisions() returns table (form_code text, location_id int, norm text, entries bigint)
language sql stable security definer set search_path = public as $$
  select e.form_code, e.location_id, public.norm_paper_serial(e.paper_serial), count(*) from public.entries e
  where public.is_owner() and public.norm_paper_serial(e.paper_serial) is not null group by 1, 2, 3 having count(*) > 1;
$$;
do $$ begin
  if exists (select 1 from public.entries where public.norm_paper_serial(paper_serial) is not null group by form_code, location_id, public.norm_paper_serial(paper_serial) having count(*) > 1) then
    raise warning 'phase17: paper serials collide after normalisation - the unique index was NOT changed; run select * from paper_serial_collisions() as the owner and fix them, then run this file again';
  else
    create unique index if not exists entries_paper_serial_nuq on public.entries (form_code, location_id, (public.norm_paper_serial(paper_serial))) where public.norm_paper_serial(paper_serial) is not null;
    drop index if exists public.entries_paper_serial_uq;
  end if;
end $$;

create or replace function public._entries_rollout_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare m text;
begin
  m := public.rollout_mode(new.form_code, new.location_id);
  new.rollout_mode := m;
  new.source := case when new.entered_later then 'paper_entry' else 'app' end;
  if m = 'paper' and public.rule_on('rollout_enforce') and not new.entered_later then raise exception 'rollout_paper:%', new.form_code; end if;
  return new;
end $$;
drop trigger if exists entries_rollout_guard on public.entries;
create trigger entries_rollout_guard before insert on public.entries for each row execute function public._entries_rollout_guard();

-- ---------- (4) save_entry with the optional meta (client id, entered later) ----------
drop function if exists public.save_entry(uuid, text, int, date, jsonb, jsonb, text);
create or replace function public.save_entry(p_id uuid, p_form text, p_loc int, p_date date, p_data jsonb, p_flags jsonb, p_note text default null, p_meta jsonb default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text; n int; ow boolean; cid uuid; later boolean; ps text; pat timestamptz; pt text; d date := p_date; dat jsonb := coalesce(p_data, '{}'::jsonb); has_later boolean; oldd jsonb; mx numeric; fls jsonb := coalesce(p_flags, '[]'::jsonb);
begin
  if not public.can_do(p_form, 'enter') then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if not exists (select 1 from public.forms where code = p_form and enabled) then raise exception 'form is switched off'; end if;
  if p_meta is not null and jsonb_typeof(p_meta) <> 'object' then raise exception 'bad_meta'; end if;
  begin cid := nullif(p_meta->>'client_id', '')::uuid; exception when others then raise exception 'bad_client_id'; end;
  has_later := p_meta is not null and p_meta ? 'entered_later';
  select staff_id into sid from public.profiles where id = auth.uid();

  if p_id is null then
    if cid is not null then
      select * into e from public.entries where client_id = cid;
      if found then
        if e.created_by <> auth.uid() then raise exception 'client_id_in_use'; end if;
        if e.form_code <> p_form or e.location_id <> p_loc then raise exception 'client_id_mismatch'; end if;
        return jsonb_build_object('id', e.id, 'serial', e.serial, 'duplicate', true);
      end if;
    end if;
  else
    select * into e from public.entries where id = p_id for update;
    if not found then raise exception 'entry not found'; end if;
    if e.status <> 'draft' then raise exception 'entry is locked'; end if;
    if e.created_by <> auth.uid() and not public.is_owner() then raise exception 'only the maker can edit'; end if;
  end if;

  -- entered later from paper: effective values (a draft keeps its own when the meta does not mention them)
  begin later := case when has_later then coalesce((p_meta->>'entered_later')::boolean, false) else coalesce(e.entered_later, false) end;
  exception when others then raise exception 'bad_meta'; end;
  if later then
    if has_later then
      ps := nullif(btrim(coalesce(p_meta->>'paper_serial', '')), '');
      begin
        pt := nullif(btrim(coalesce(p_meta->>'paper_at', '')), '');
        if pt is null then pat := null;
        elsif pt ~ '[T ][0-9:.]+(Z|[+-][0-9]{2}(:?[0-9]{2})?)$' then pat := pt::timestamptz;      -- has an offset
        else pat := pt::timestamp at time zone 'Asia/Dhaka';                                        -- naive = Dhaka local time
        end if;
      exception when others then raise exception 'paper_time_required'; end;
    else ps := e.paper_serial; pat := e.paper_at; end if;
    if not public.rule_on('entered_later_on') and not coalesce(e.entered_later, false) then raise exception 'entered_later_off'; end if;
    if ps is null then raise exception 'paper_serial_required'; end if;
    if length(ps) > 40 then raise exception 'paper_serial_too_long'; end if;
    if pat is null then raise exception 'paper_time_required'; end if;
    if pat > now() + interval '5 minutes' then raise exception 'paper_time_future'; end if;
    d := (pat at time zone 'Asia/Dhaka')::date;                       -- the business date is the original date
    dat := jsonb_set(dat, '{paper_no}', to_jsonb(ps));                -- mirrored: the gap audit and the old unique index see it
    mx := public.rule_num('entered_later_max_days');
    if mx is not null and pat < now() - make_interval(days => mx::int) then
      if not public.is_owner() then raise exception 'entered_later_too_old'; end if;
      if not exists (select 1 from jsonb_array_elements(fls) x where x->>'code' = 'entered_later_old') then
        fls := fls || jsonb_build_array(jsonb_build_object('code', 'entered_later_old', 'level', 'red', 'src', 'system',
          'text', jsonb_build_object('bn', 'কাগজের তারিখ সীমার চেয়ে পুরনো — পরে তোলা', 'en', 'Entered later: paper date older than the limit')));
      end if;
    end if;
    if exists (select 1 from public.entries x where x.form_code = p_form and x.location_id = p_loc and (p_id is null or x.id <> p_id)
               and (public.norm_paper_serial(x.paper_serial) = public.norm_paper_serial(ps) or public.norm_paper_serial(x.data->>'paper_no') = public.norm_paper_serial(ps))) then raise exception 'paper_serial_in_use'; end if;
  else ps := null; pat := null; end if;

  if p_id is null then
    begin
      insert into public.serials (form_code, location_id, last) values (p_form, p_loc, 1)
        on conflict (form_code, location_id) do update set last = public.serials.last + 1 returning last into n;
      insert into public.entries (form_code, location_id, serial, entry_date, data, flags, created_by, created_staff, entered_later, paper_serial, paper_at, client_id)
        values (p_form, p_loc, n, d, dat, fls, auth.uid(), sid, later, ps, pat, cid) returning * into e;
    exception when unique_violation then
      -- two sends of the same client id at once: the loser (its serial bump is rolled back with this block) gets the winner's entry
      if cid is null then raise; end if;
      select * into e from public.entries where client_id = cid and created_by = auth.uid();
      if not found then raise; end if;
      if e.form_code <> p_form or e.location_id <> p_loc then raise exception 'client_id_mismatch'; end if;
      return jsonb_build_object('id', e.id, 'serial', e.serial, 'duplicate', true);
    end;
    return jsonb_build_object('id', e.id, 'serial', e.serial);
  end if;

  oldd := e.data;
  if e.entered_later and not later and not (dat ? 'paper_no') then oldd := e.data - 'paper_no'; end if;     -- switching “entered later” off drops only the mirrored serial: no note needed
  ow := public.jsonb_overwrites(oldd, dat);
  if ow and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  if ow then
    insert into public.corrections (user_id, staff_id, form_code, entry_id, note, before, after)
      values (auth.uid(), sid, e.form_code, e.id::text, btrim(p_note), e.data, dat);
  end if;
  update public.entries set data = dat, flags = fls, entry_date = d, updated_at = now(),
    entered_later = later, paper_serial = ps, paper_at = pat, source = case when later then 'paper_entry' else 'app' end where id = p_id;
  return jsonb_build_object('id', e.id, 'serial', e.serial, 'overwrote', ow);
end $$;
revoke all on function public.save_entry(uuid, text, int, date, jsonb, jsonb, text, jsonb) from public, anon;
grant execute on function public.save_entry(uuid, text, int, date, jsonb, jsonb, text, jsonb) to authenticated;

create or replace function public.submit_entry(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; f public.forms; fl jsonb; blocked text[] := '{}'; auto boolean;
begin
  select * into e from public.entries where id = p_id for update;
  if not found then raise exception 'entry not found'; end if;
  if e.status <> 'draft' then raise exception 'entry is locked'; end if;
  if e.created_by <> auth.uid() and not public.is_owner() then raise exception 'only the maker can submit'; end if;
  if not public.can_do(e.form_code, 'enter') or not public.can_loc(e.location_id) then raise exception 'not allowed'; end if;
  if public.rollout_mode(e.form_code, e.location_id) = 'paper' and public.rule_on('rollout_enforce') and not e.entered_later then
    raise exception 'rollout_paper:%', e.form_code;
  end if;
  select * into f from public.forms where code = e.form_code;
  if f.red_block then
    for fl in select * from jsonb_array_elements(e.flags) loop
      if fl->>'level' = 'red' and fl->>'code' <> 'entered_later_old' and not exists (select 1 from public.release_requests r
           where r.entry_id = e.id and r.flag_code = fl->>'code' and r.status = 'approved'
             and r.flag_amount is not distinct from nullif(fl->>'amount','')::numeric) then
        blocked := blocked || (fl->>'code');
      end if;
    end loop;
    if array_length(blocked, 1) > 0 then raise exception 'red_blocked:%', array_to_string(blocked, ','); end if;
  end if;
  update public.entries set status = 'submitted', submitted_at = now(), updated_at = now() where id = p_id;
  select coalesce((select (value #>> '{}')::boolean from public.settings where key = 'auto_exceptions'), true) into auto;
  delete from public.exceptions where entry_id = e.id and status = 'open';
  if auto then
    insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      select e.id, e.form_code, e.location_id, e.entry_date, x->>'code', x->>'level', nullif(x->>'amount','')::numeric, x->'text'
      from jsonb_array_elements(e.flags) x;
  end if;
  return jsonb_build_object('status', 'submitted');
end $$;
revoke all on function public.submit_entry(uuid) from public, anon;
grant execute on function public.submit_entry(uuid) to authenticated;

-- ---------- (5) owner self-approval switch: entries ----------
create or replace function public.decide_entry(p_id uuid, p_approve boolean, p_note text default null, p_check jsonb default null, p_flags jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text; self_ok boolean; auto boolean; newflags jsonb;
begin
  select * into e from public.entries where id = p_id for update;
  if not found or e.status <> 'submitted' then raise exception 'entry is not waiting for a decision'; end if;
  if not (public.can_do(e.form_code, 'approve') and public.can_loc(e.location_id)) then raise exception 'not allowed'; end if;
  if public.is_owner() then self_ok := public.rule_on('owner_self_approve');
  else self_ok := exists (select 1 from public.user_roles ur join public.roles r on r.code = ur.role_code where ur.user_id = auth.uid() and r.allow_self_approve);
  end if;
  if e.created_by = auth.uid() and not self_ok then raise exception 'you cannot approve your own entry'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  -- flags found while checking (receiver's count, etc.) are added to the maker's flags
  newflags := coalesce(p_flags, '[]'::jsonb);
  if p_approve and e.reopen_snap is not null then
    -- an owner reopen: the old approved version becomes a revision only when the re-approved entry really differs (no empty revisions)
    if (e.reopen_snap->'data') is distinct from e.data or (e.reopen_snap->'check_data') is distinct from coalesce(p_check, e.check_data) then
      insert into public.entry_revisions (entry_id, rev_no, data, check_data, flags, changed_by, changed_staff, approved_by, approved_staff, reason)
        values (e.id, e.rev_no, e.reopen_snap->'data', e.reopen_snap->'check_data', e.reopen_snap->'flags', (e.reopen_snap->>'by')::uuid, e.reopen_snap->>'staff', auth.uid(), sid, e.reopen_snap->>'reason');
      update public.entries set rev_no = e.rev_no + 1 where id = p_id;
    end if;
    update public.entries set reopen_snap = null where id = p_id;
  end if;
  update public.entries set status = case when p_approve then 'approved' else 'rejected' end,
    check_data = coalesce(p_check, check_data),
    flags = (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(e.flags) x where coalesce(x->>'src','') <> 'check') || newflags,
    checked_by = auth.uid(), checked_staff = sid, checked_at = now(), check_note = p_note, updated_at = now() where id = p_id;
  select coalesce((select (value #>> '{}')::boolean from public.settings where key = 'auto_exceptions'), true) into auto;
  if auto and jsonb_array_length(newflags) > 0 then
    delete from public.exceptions where entry_id = e.id and status = 'open' and flag_code in (select x->>'code' from jsonb_array_elements(newflags) x);
    insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      select e.id, e.form_code, e.location_id, e.entry_date, x->>'code', x->>'level', nullif(x->>'amount','')::numeric, x->'text'
      from jsonb_array_elements(newflags) x;
  end if;
  return jsonb_build_object('status', case when p_approve then 'approved' else 'rejected' end);
end $$;
revoke all on function public.decide_entry(uuid, boolean, text, jsonb, jsonb) from public, anon;
grant execute on function public.decide_entry(uuid, boolean, text, jsonb, jsonb) to authenticated;

-- red-control release: the owner as before, plus a delegate holding release_decide; maker <> approver (the owner exempt only while owner_self_approve is ON)
create or replace function public.decide_release(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid text; r public.release_requests;
begin
  select * into r from public.release_requests where id = p_id for update;
  if not found then raise exception 'request is not pending'; end if;
  if not (public.is_owner() or (public.is_active() and public.has_grant('release_decide', (select location_id from public.entries where id = r.entry_id)))) then raise exception 'owner only'; end if;
  if r.status <> 'pending' then raise exception 'request is not pending'; end if;
  if r.requested_by = auth.uid() and not (public.is_owner() and public.rule_on('owner_self_approve')) then raise exception 'self_approval'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.release_requests set status = case when p_approve then 'approved' else 'rejected' end,
    decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = p_note where id = p_id;
  return jsonb_build_object('status', case when p_approve then 'approved' else 'rejected' end);
end $$;
revoke all on function public.decide_release(bigint, boolean, text) from public, anon;
grant execute on function public.decide_release(bigint, boolean, text) to authenticated;
create or replace function public._release_can_see(p_entry uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('release_decide', (select location_id from public.entries where id = p_entry)));
$$;
revoke all on function public._release_can_see(uuid) from public, anon; grant execute on function public._release_can_see(uuid) to authenticated;
drop policy if exists release_read on public.release_requests;
create policy release_read on public.release_requests for select to authenticated
  using (requested_by = auth.uid() or public.is_owner() or public._release_can_see(entry_id));

-- emergency requests: someone else decides; the owner is exempt only while owner_self_approve is ON
create or replace function public.decide_emergency(p_id bigint, p_approve boolean, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.emergency_requests; sid text; mins numeric;
begin
  if not public.can_grant('emergency_decide') then raise exception 'not allowed'; end if;
  select * into r from public.emergency_requests where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if r.status <> 'pending' then raise exception 'already decided'; end if;
  if r.created_at < now() - interval '1 day' then update public.emergency_requests set status = 'expired' where id = p_id; return; end if;      -- a day-old request is stale: ask again
  if r.requested_by = auth.uid() and not (public.is_owner() and public.rule_on('owner_self_approve')) then raise exception 'own_request'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  mins := coalesce(public.rule_num('em_minutes'), 30);
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.emergency_requests set status = case when p_approve then 'approved' else 'rejected' end, decided_by = auth.uid(), decided_staff = sid, decided_at = now(),
    decision_note = left(nullif(btrim(p_note), ''), 300), valid_until = case when p_approve then now() + make_interval(mins => mins::int) end where id = p_id;
end $$;
revoke all on function public.decide_emergency(bigint, boolean, text) from public, anon;
grant execute on function public.decide_emergency(bigint, boolean, text) to authenticated;

-- item changes: the owner's own change is applied at once only while owner_self_approve is ON; otherwise it is a request for another approver
create or replace function public.submit_item_change(p_item uuid, p_patch jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid text; cid bigint;
begin
  if not public.can_do('ITEMS', 'enter') then raise exception 'not allowed'; end if;
  if p_patch ? 'cost_price' and not public.can_do('ITEM_COST', 'enter') then raise exception 'not allowed to change cost'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if public.is_owner() and public.rule_on('owner_self_approve') then
    return jsonb_build_object('status', 'applied', 'item_id', public.apply_item_patch(p_item, p_patch));
  end if;
  insert into public.item_changes (item_id, patch, note, requested_by, requested_staff)
    values (p_item, p_patch, p_note, auth.uid(), sid) returning id into cid;
  return jsonb_build_object('status', 'pending', 'id', cid);
end $$;
revoke all on function public.submit_item_change(uuid, jsonb, text) from public, anon;
grant execute on function public.submit_item_change(uuid, jsonb, text) to authenticated;

create or replace function public.decide_item_change(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.item_changes; sid text; self_ok boolean;
begin
  if not (public.is_owner() or public.can_do('ITEMS', 'approve') or (public.is_active() and public.has_grant('item_create'))) then raise exception 'not allowed'; end if;
  select * into c from public.item_changes where id = p_id for update;
  if not found or c.status <> 'pending' then raise exception 'request is not pending'; end if;
  if public.is_owner() then self_ok := public.rule_on('owner_self_approve');
  else self_ok := exists (select 1 from public.user_roles ur join public.roles r on r.code = ur.role_code where ur.user_id = auth.uid() and r.allow_self_approve);
  end if;
  if c.requested_by = auth.uid() and not self_ok then raise exception 'you cannot approve your own request'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_approve then perform set_config('bos.item_apply', '1', true); perform public.apply_item_patch(c.item_id, c.patch); perform set_config('bos.item_apply', '', true); end if;
  update public.item_changes set status = case when p_approve then 'approved' else 'rejected' end,
    decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = p_note where id = p_id;
  return jsonb_build_object('status', case when p_approve then 'approved' else 'rejected' end);
end $$;
revoke all on function public.decide_item_change(bigint, boolean, text) from public, anon;
grant execute on function public.decide_item_change(bigint, boolean, text) to authenticated;

-- ---------- (6) revisions (append-only) and change requests ----------
create table if not exists public.entry_revisions (
  entry_id uuid not null references public.entries(id),
  rev_no int not null,
  data jsonb not null, check_data jsonb not null default '{}', flags jsonb not null default '[]',
  changed_by uuid, changed_staff text,                 -- who asked for the change
  approved_by uuid, approved_staff text,               -- who decided it
  request_id bigint, reason text,
  at timestamptz not null default now(),
  primary key (entry_id, rev_no)
);
create or replace function public.entry_revisions_append_only() returns trigger
language plpgsql set search_path = public as $$
begin raise exception 'entry_revisions is append-only'; end $$;
drop trigger if exists entry_revisions_no_change on public.entry_revisions;
create trigger entry_revisions_no_change before update or delete on public.entry_revisions for each row execute function public.entry_revisions_append_only();
drop trigger if exists entry_revisions_no_truncate on public.entry_revisions;
create trigger entry_revisions_no_truncate before truncate on public.entry_revisions for each statement execute function public.entry_revisions_append_only();
alter table public.entry_revisions enable always trigger entry_revisions_no_truncate;
alter table public.entry_revisions enable row level security;
drop policy if exists entry_revisions_read on public.entry_revisions;
create policy entry_revisions_read on public.entry_revisions for select to authenticated
  using (exists (select 1 from public.entries e where e.id = entry_id));      -- exactly the entries the caller may read (entries RLS)
revoke all on public.entry_revisions from public, anon, authenticated;
grant select on public.entry_revisions to authenticated;

create table if not exists public.entry_change_requests (
  id bigserial primary key,
  entry_id uuid not null references public.entries(id),
  base_rev int not null,
  requested_by uuid not null, requested_staff text,
  reason text not null check (length(btrim(reason)) > 0),
  patch jsonb not null,                                -- {data?, check_data?, flags?}: the whole new value of each part named
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  created_at timestamptz not null default now(),
  decided_by uuid, decided_staff text, decided_at timestamptz, decision_note text, new_rev int
);
create unique index if not exists entry_change_one_pending on public.entry_change_requests (entry_id) where status = 'pending';
create index if not exists entry_change_status on public.entry_change_requests (status, created_at desc);
-- a delegate sees (and decides) requests only for entries of a place where the grant holds AND of a form he may view / approve there
create or replace function public._ecr_scope(p_entry uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or exists (select 1 from public.entries e where e.id = p_entry
    and public.has_grant('change_approve', e.location_id) and public.can_loc(e.location_id)
    and (public.can_do(e.form_code, 'approve') or public.can_do(e.form_code, 'view'))));
$$;
create or replace function public._ecr_can_see(p_requester uuid, p_entry uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (p_requester = auth.uid() or public._ecr_scope(p_entry));
$$;
alter table public.entry_change_requests enable row level security;
drop policy if exists entry_change_read on public.entry_change_requests;
create policy entry_change_read on public.entry_change_requests for select to authenticated using (public._ecr_can_see(requested_by, entry_id));
revoke all on public.entry_change_requests from public, anon, authenticated;
grant select on public.entry_change_requests to authenticated;
drop trigger if exists audit_entry_change on public.entry_change_requests;
create trigger audit_entry_change after insert or update on public.entry_change_requests for each row execute function public.log_change('id');
drop trigger if exists entry_change_no_delete on public.entry_change_requests;
create trigger entry_change_no_delete before delete on public.entry_change_requests for each row execute function public.no_hard_delete();

create or replace function public.entry_change_request(p_entry uuid, p_reason text, p_patch jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text; rid bigint;
begin
  if not public.rule_on('change_requests_on') then raise exception 'change_requests_off'; end if;
  if p_reason is null or length(btrim(p_reason)) = 0 then raise exception 'note_required'; end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' or not (p_patch ?| array['data', 'check_data', 'flags']) then raise exception 'bad_patch'; end if;
  if p_patch ? 'data' and jsonb_typeof(p_patch->'data') <> 'object' then raise exception 'bad_patch'; end if;
  if p_patch ? 'check_data' and jsonb_typeof(p_patch->'check_data') <> 'object' then raise exception 'bad_patch'; end if;
  if p_patch ? 'flags' and jsonb_typeof(p_patch->'flags') <> 'array' then raise exception 'bad_patch'; end if;
  if length(p_patch::text) > 400000 then raise exception 'bad_patch'; end if;
  select * into e from public.entries where id = p_entry;
  if not found then raise exception 'entry not found'; end if;
  if not (public.can_do(e.form_code, 'enter') and public.can_loc(e.location_id)) then raise exception 'not allowed'; end if;
  if e.status <> 'approved' then raise exception 'not_locked'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  begin
    insert into public.entry_change_requests (entry_id, base_rev, requested_by, requested_staff, reason, patch)
      values (e.id, e.rev_no, auth.uid(), sid, left(btrim(p_reason), 500), p_patch) returning id into rid;
  exception when unique_violation then raise exception 'change_pending'; end;
  return jsonb_build_object('id', rid, 'status', 'pending');
end $$;

create or replace function public.entry_change_cancel(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.entry_change_requests set status = 'cancelled', decided_by = auth.uid(), decided_at = now()
   where id = p_id and requested_by = auth.uid() and status = 'pending';
  if not found then raise exception 'request is not pending'; end if;
end $$;

create or replace function public.entry_change_decide(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.entry_change_requests; e public.entries; sid text; nd jsonb; nc jsonb; nf jsonb; auto boolean; nr int; self_ok boolean;
begin
  select * into r from public.entry_change_requests where id = p_id for update;
  if not found or r.status <> 'pending' then raise exception 'request is not pending'; end if;
  select * into e from public.entries where id = r.entry_id for update;
  if not public._ecr_scope(e.id) then raise exception 'not allowed'; end if;
  if public.is_owner() then self_ok := public.rule_on('owner_self_approve');
  else self_ok := exists (select 1 from public.user_roles ur join public.roles ro on ro.code = ur.role_code where ur.user_id = auth.uid() and ro.allow_self_approve);
  end if;
  if r.requested_by = auth.uid() and not self_ok then raise exception 'self_approval'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if not p_approve then
    update public.entry_change_requests set status = 'rejected', decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = left(btrim(p_note), 500) where id = p_id;
    return jsonb_build_object('status', 'rejected');
  end if;
  if e.status <> 'approved' or e.rev_no <> r.base_rev then raise exception 'stale_request'; end if;
  nd := coalesce(r.patch->'data', e.data); nc := coalesce(r.patch->'check_data', e.check_data); nf := coalesce(r.patch->'flags', e.flags);
  if e.entered_later then nd := jsonb_set(nd, '{paper_no}', to_jsonb(e.paper_serial)); end if;     -- the paper serial never changes through a revision
  nr := e.rev_no + 1;
  insert into public.entry_revisions (entry_id, rev_no, data, check_data, flags, changed_by, changed_staff, approved_by, approved_staff, request_id, reason)
    values (e.id, e.rev_no, e.data, e.check_data, e.flags, r.requested_by, r.requested_staff, auth.uid(), sid, r.id, r.reason);
  update public.entries set data = nd, check_data = nc, flags = nf, rev_no = nr, updated_at = now() where id = e.id;
  if r.patch ? 'flags' then
    select coalesce((select (value #>> '{}')::boolean from public.settings where key = 'auto_exceptions'), true) into auto;
    delete from public.exceptions where entry_id = e.id and status = 'open';
    if auto then
      insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        select e.id, e.form_code, e.location_id, e.entry_date, x->>'code', x->>'level', nullif(x->>'amount','')::numeric, x->'text'
        from jsonb_array_elements(nf) x;
    end if;
  end if;
  update public.entry_change_requests set status = 'approved', decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = left(btrim(p_note), 500), new_rev = nr where id = p_id;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'revision', 'entries', e.id::text, jsonb_build_object('form', e.form_code, 'serial', e.serial, 'from_rev', e.rev_no, 'to_rev', nr, 'request', r.id, 'reason', r.reason));
  return jsonb_build_object('status', 'approved', 'rev_no', nr);
end $$;

-- the history of an entry: every older version (immutable) and the current one
create or replace function public.entry_revisions_list(p_entry uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.entries;
begin
  select * into e from public.entries where id = p_entry;
  if not found then raise exception 'entry not found'; end if;
  if not (public.is_owner() or (public.can_do(e.form_code, 'view') and public.can_loc(e.location_id))) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(x order by (x->>'rev_no')::int desc) from (
      select jsonb_build_object('rev_no', v.rev_no, 'current', false, 'data', v.data, 'check_data', v.check_data, 'flags', v.flags,
             'changed_staff', v.changed_staff, 'approved_staff', v.approved_staff, 'at', v.at, 'reason', v.reason) x
      from public.entry_revisions v where v.entry_id = e.id
      union all
      select jsonb_build_object('rev_no', e.rev_no, 'current', true, 'data', e.data, 'check_data', e.check_data, 'flags', e.flags,
             'changed_staff', null, 'approved_staff', e.checked_staff, 'at', e.updated_at, 'reason', null)) q), '[]'::jsonb);
end $$;

-- how many change requests the caller may decide (for Needs-you / badge)
create or replace function public.entry_change_counts() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('pending', (select count(*) from public.entry_change_requests q where q.status = 'pending' and public._ecr_scope(q.entry_id)
    and (q.requested_by <> auth.uid() or (public.is_owner() and public.rule_on('owner_self_approve')))));
$$;

-- reopen (owner): pending change requests of the entry are cancelled; the approved version is kept and becomes a revision only if the re-approved entry differs
create or replace function public.reopen_entry(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text;
begin
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into e from public.entries where id = p_id for update;
  if not found then raise exception 'entry not found'; end if;
  if e.status = 'draft' then return jsonb_build_object('status', 'draft'); end if;
  if e.status = 'approved' and not public.is_owner() then raise exception 'only the owner can reopen an approved entry'; end if;
  if e.created_by <> auth.uid() and not public.is_owner() then raise exception 'only the maker can reopen'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.corrections (user_id, staff_id, form_code, entry_id, note, before, after)
    values (auth.uid(), sid, e.form_code, e.id::text, btrim(p_note), jsonb_build_object('status', e.status, 'data', e.data), null);
  if e.status = 'approved' then
    update public.entries set reopen_snap = jsonb_build_object('data', e.data, 'check_data', e.check_data, 'flags', e.flags, 'by', auth.uid(), 'staff', sid, 'reason', 'reopened: ' || left(btrim(p_note), 400)) where id = p_id;
  end if;
  update public.entry_change_requests set status = 'cancelled', decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = 'entry reopened by the owner'
    where entry_id = p_id and status = 'pending';
  update public.entries set status = 'draft', submitted_at = null, checked_by = null, checked_staff = null, checked_at = null, check_note = null, check_data = '{}', updated_at = now() where id = p_id;
  return jsonb_build_object('status', 'draft');
end $$;
revoke all on function public.reopen_entry(uuid, text) from public, anon;
grant execute on function public.reopen_entry(uuid, text) to authenticated;

-- ---------- (7) gap audit over both series ----------
create or replace function public.number_audit_both(p_form text, p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lo bigint; hi bigint; cnt bigint; miss_n bigint; miss bigint[]; later bigint; pa jsonb; ap jsonb;
begin
  if not (public.is_owner() or (public.can_do(p_form, 'approve') and public.can_loc(p_loc))) then raise exception 'not allowed'; end if;
  begin pa := public.number_audit(p_form, p_loc);
  exception when others then
    if sqlerrm like '%range too wide%' then pa := jsonb_build_object('range_too_wide', true); else raise; end if;
  end;
  select min(serial), max(serial), count(*) into lo, hi, cnt from public.entries where form_code = p_form and location_id = p_loc;
  select count(*) into later from public.entries where form_code = p_form and location_id = p_loc and entered_later;
  if cnt = 0 then ap := jsonb_build_object('entered', 0, 'missing_count', 0, 'missing', '[]'::jsonb);
  elsif hi - lo > 100000 then ap := jsonb_build_object('entered', cnt, 'first', lo, 'last', hi, 'range_too_wide', true);
  else
    select coalesce(array_agg(g order by g), '{}') into miss from (select g from generate_series(lo, hi) g where not exists (select 1 from public.entries e where e.form_code = p_form and e.location_id = p_loc and e.serial = g) limit 200) m;
    select count(*) into miss_n from generate_series(lo, hi) g where not exists (select 1 from public.entries e where e.form_code = p_form and e.location_id = p_loc and e.serial = g);
    ap := jsonb_build_object('entered', cnt, 'first', lo, 'last', hi, 'missing_count', miss_n, 'missing', to_jsonb(miss));
  end if;
  return jsonb_build_object('paper', pa, 'app', ap, 'entered_later', later);
end $$;

-- ---------- (7b) the owner self-approval switch may only go OFF while another person can approve ----------
create or replace function public._other_approver_exists() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p where p.status = 'active' and p.id <> auth.uid() and (
      exists (select 1 from public.user_roles ur where ur.user_id = p.id and ur.role_code = 'owner')
      or exists (select 1 from public.user_roles ur join public.role_form_perms f on f.role_code = ur.role_code join public.roles ro on ro.code = ur.role_code and ro.active
                 where ur.user_id = p.id and f.can_approve)
      or exists (select 1 from public.user_grants g where g.user_id = p.id and g.grant_code in ('change_approve', 'release_decide', 'item_create') and (g.valid_until is null or g.valid_until > now()))));
$$;
create or replace function public.owner_self_approve_set(p_on boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_on is null then raise exception 'bad_value'; end if;
  if not p_on and not public._other_approver_exists() then raise exception 'no_other_approver'; end if;
  perform public.set_rule('owner_self_approve', to_jsonb(p_on));
  return jsonb_build_object('owner_self_approve', p_on);
end $$;
create or replace function public._rules_self_approve_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- only for the API roles (set_rule through the app): a direct SQL update by the database owner is not blocked
  if current_setting('role', true) = 'authenticated' and new.key = 'owner_self_approve'
     and coalesce(new.value, new.default_value) = 'false'::jsonb and not public._other_approver_exists() then raise exception 'no_other_approver'; end if;
  return new;
end $$;
drop trigger if exists rules_self_approve_guard on public.rules;
create trigger rules_self_approve_guard before update on public.rules for each row execute function public._rules_self_approve_guard();
revoke all on function public._other_approver_exists(), public.owner_self_approve_set(boolean), public._rules_self_approve_guard(), public._ecr_scope(uuid), public.norm_paper_serial(text), public.paper_serial_collisions() from public, anon;
grant execute on function public.owner_self_approve_set(boolean), public.paper_serial_collisions(), public._ecr_scope(uuid), public.norm_paper_serial(text) to authenticated;

-- ---------- (8) privileges ----------
revoke all on function public.rollout_mode(text, int), public._rollout_mgr(), public.rollout_set(text, int, text, text), public.rollout_set_many(text[], int[], text, text),
  public._entries_rollout_guard(), public.entry_revisions_append_only(), public.entry_change_request(uuid, text, jsonb),
  public.entry_change_cancel(bigint), public.entry_change_decide(bigint, boolean, text), public.entry_revisions_list(uuid), public.entry_change_counts(),
  public.number_audit_both(text, int), public._ecr_can_see(uuid, uuid) from public, anon;
grant execute on function public.rollout_mode(text, int), public.rollout_set(text, int, text, text), public.rollout_set_many(text[], int[], text, text),
  public.entry_change_request(uuid, text, jsonb), public.entry_change_cancel(bigint), public.entry_change_decide(bigint, boolean, text),
  public.entry_revisions_list(uuid), public.entry_change_counts(), public.number_audit_both(text, int) to authenticated;
grant execute on function public._ecr_can_see(uuid, uuid) to authenticated;   -- used by the RLS policy
revoke execute on function public._rollout_mgr(), public._entries_rollout_guard(), public.entry_revisions_append_only() from authenticated;
