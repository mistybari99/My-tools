-- Phase 480 (bos481) - X1 FOUNDATION, part 2: approval queue for agent and automation proposals, and the health view.
-- Paste after phase 480. Paste-twice safe. Nothing existing is edited.
-- Rules of the queue:
--   * A proposal names ONE target RPC from the allowlist action_targets (enabled OFF by default). Rules, grants, audit and finance posting can never be a target (trigger).
--   * Only the owner decides. The proposer never decides its own proposal. A rejection needs a reason.
--   * A decision does NOT run anything. The approver's own session calls the target RPC (under the approver's own grants), then records the result with action_proposal_mark_executed.
--     Nothing runs twice: client_id is unique, and a proposal leaves 'approved' once it is executed or failed.
--   * Expired proposals (expires_at passed) can not be approved.
-- Health: x1_health() (owner only) reads the registry, job runs, outbox, intake failures, backup and books freshness. A missing source is shown as missing or unverified, never as healthy.
-- Tags: bos481. Test data only (test_*). Tests: supabase/phase481_test.sql.

-- ---------- allowlist of proposal targets ----------
create table if not exists public.action_targets (
  rpc_name text primary key check (rpc_name ~ '^[a-z][a-z0-9_]{2,60}$'),
  label_bn text not null, label_en text not null,
  risk text not null default 'medium' check (risk in ('low', 'medium', 'high')),
  enabled boolean not null default false,
  updated_at timestamptz not null default now(), updated_by uuid
);
create or replace function public._x1_target_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if new.rpc_name ~ '(set_rule|grant|audit|journal|post|ledger|finance|account|role|user|secret|period|close|void|refund|pay|set_)' then
    raise exception 'target_not_allowed: % can never be a proposal target (rules, grants, audit and money are never proposed)', new.rpc_name;
  end if;
  return new;
end $$;
drop trigger if exists action_targets_guard on public.action_targets;
create trigger action_targets_guard before insert or update on public.action_targets for each row execute function public._x1_target_guard();

-- ---------- proposals ----------
create table if not exists public.action_proposals (
  id bigserial primary key,
  client_id uuid not null unique,                              -- idempotency key: the same proposal is never queued twice
  proposed_by uuid not null,
  proposer_kind text not null check (proposer_kind in ('agent', 'automation', 'owner')),
  target_rpc text not null references public.action_targets(rpc_name),
  args jsonb not null default '{}'::jsonb,
  risk text not null check (risk in ('low', 'medium', 'high')),
  reason_for text not null check (length(btrim(reason_for)) > 0),
  status text not null default 'proposed' check (status in ('proposed', 'approved', 'rejected', 'executed', 'failed', 'expired')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '3 days',
  decided_by uuid, decided_at timestamptz, decision_reason text,
  executed_at timestamptz, exec_ok boolean, exec_result jsonb,
  constraint action_proposals_reject_reason check (status <> 'rejected' or length(btrim(coalesce(decision_reason, ''))) > 0),
  constraint action_proposals_not_self check (decided_by is null or decided_by <> proposed_by)
);
create index if not exists action_proposals_open on public.action_proposals (status, id);

-- ---------- helpers ----------
create or replace function public._x1_can_propose() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_owner() or public._x1_is_bot() or public._x1_agent() is not null;
$$;

-- ---------- owner: the allowlist ----------
create or replace function public.action_target_set(p_rpc text, p_label_bn text, p_label_en text, p_risk text, p_enabled boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_rpc is null or p_risk not in ('low', 'medium', 'high') or p_enabled is null or p_label_en is null or p_label_bn is null then raise exception 'bad_input'; end if;
  insert into public.action_targets (rpc_name, label_bn, label_en, risk, enabled, updated_by) values (p_rpc, p_label_bn, p_label_en, p_risk, p_enabled, auth.uid())
    on conflict (rpc_name) do update set label_bn = excluded.label_bn, label_en = excluded.label_en, risk = excluded.risk, enabled = excluded.enabled, updated_at = now(), updated_by = auth.uid();
  return jsonb_build_object('rpc', p_rpc, 'enabled', p_enabled, 'risk', p_risk);
end $$;

-- ---------- propose (agent, automation bot or owner) ----------
create or replace function public.action_propose(p_client uuid, p_target text, p_args jsonb, p_reason text, p_expires_hours int default 72) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.action_targets; rid bigint; kind text; ex int := least(greatest(coalesce(p_expires_hours, 72), 1), 720);
begin
  if not public._x1_can_propose() then raise exception 'not allowed'; end if;
  if p_client is null or p_target is null or p_reason is null or length(btrim(p_reason)) = 0 then raise exception 'bad_input'; end if;
  if jsonb_typeof(coalesce(p_args, '{}'::jsonb)) <> 'object' then raise exception 'bad_input: args must be an object'; end if;
  select * into t from public.action_targets where rpc_name = p_target;
  if not found or not t.enabled then raise exception 'target_not_enabled'; end if;
  if exists (select 1 from public.action_proposals where client_id = p_client) then
    select id into rid from public.action_proposals where client_id = p_client;
    return jsonb_build_object('id', rid, 'duplicate', true);
  end if;
  kind := case when public.is_owner() then 'owner' when public._x1_agent() is not null then 'agent' else 'automation' end;
  insert into public.action_proposals (client_id, proposed_by, proposer_kind, target_rpc, args, risk, reason_for, expires_at)
    values (p_client, auth.uid(), kind, p_target, coalesce(p_args, '{}'::jsonb), t.risk, left(public.x1_redact(p_reason), 300), now() + make_interval(hours => ex))
    returning id into rid;
  return jsonb_build_object('id', rid, 'status', 'proposed', 'risk', t.risk, 'duplicate', false);
end $$;

-- ---------- decide (owner only, never the proposer) ----------
create or replace function public.action_decide(p_id bigint, p_decision text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr public.action_proposals; ns text;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into pr from public.action_proposals where id = p_id for update;
  if not found then raise exception 'proposal_not_found'; end if;
  if pr.proposed_by = auth.uid() then raise exception 'own_proposal_cannot_be_decided'; end if;
  if pr.status <> 'proposed' then raise exception 'not_open: status is %', pr.status; end if;
  if p_decision not in ('approve', 'reject') then raise exception 'bad_input'; end if;
  if pr.expires_at <= now() then
    update public.action_proposals set status = 'expired' where id = p_id;
    return jsonb_build_object('id', p_id, 'status', 'expired');
  end if;
  if p_decision = 'reject' and length(btrim(coalesce(p_reason, ''))) = 0 then raise exception 'reject_reason_required'; end if;
  ns := case when p_decision = 'approve' then 'approved' else 'rejected' end;
  update public.action_proposals set status = ns, decided_by = auth.uid(), decided_at = now(), decision_reason = left(public.x1_redact(p_reason), 300) where id = p_id;
  return jsonb_build_object('id', p_id, 'status', ns, 'target_rpc', pr.target_rpc, 'args', pr.args);
end $$;

-- ---------- record the result after the approver's own session ran the target (owner only) ----------
create or replace function public.action_proposal_mark_executed(p_id bigint, p_ok boolean, p_result jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ns text;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_ok is null then raise exception 'bad_input'; end if;
  ns := case when p_ok then 'executed' else 'failed' end;
  update public.action_proposals set status = ns, executed_at = now(), exec_ok = p_ok,
      exec_result = case when length(coalesce(p_result, '{}'::jsonb)::text) <= 2000 then coalesce(p_result, '{}'::jsonb) else jsonb_build_object('truncated', true) end
    where id = p_id and status = 'approved' and decided_by = auth.uid();
  if not found then raise exception 'not_approved_by_you'; end if;
  return jsonb_build_object('id', p_id, 'status', ns);
end $$;

-- ---------- list (owner sees all; a proposer sees its own) ----------
create or replace function public.action_proposals_list(p_status text default null, p_limit int default 100) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_owner() or public._x1_can_propose() then coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
    select p.id, p.proposer_kind, p.target_rpc, p.risk, p.reason_for, p.status, p.created_at, p.expires_at, p.decided_at, p.decision_reason, p.executed_at, p.exec_ok
      from public.action_proposals p where (p_status is null or p.status = p_status) and (public.is_owner() or p.proposed_by = auth.uid())
      order by p.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb) end;
$$;

-- ---------- health (owner only; a missing source is reported as missing, never as healthy) ----------
create or replace function public.x1_health() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := '{}'::jsonb; jobs jsonb; regs jsonb; bk jsonb; fr jsonb; fails int; outbox jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('code', r.code, 'kind', r.kind, 'label_en', r.label_en, 'status', r.status, 'enabled', r.enabled,
      'last_ok_at', r.last_ok_at, 'last_error_at', r.last_error_at, 'last_error', r.last_error, 'last_test_at', r.last_test_at,
      'state', case when r.status = 'disabled' or not r.enabled then 'off' when r.status = 'not_connected' then 'not_connected'
                    when r.status = 'error' then 'error' when r.last_test_at is null then 'unverified' else 'ok' end) order by r.code), '[]'::jsonb)
    into regs from public.integration_registry r;
  -- expected jobs and how long each may stay quiet before it is called stale
  with exp(job, max_hours) as (values ('notify_digest', 2), ('notify_sms', 2), ('intake_retry', 2), ('kb_rebuild', 36), ('backup', 36)),
  last_ok as (select j.job, max(j.started_at) filter (where j.ok) as ok_at, max(j.started_at) filter (where j.ok is not null) as any_at, count(*) filter (where j.ok is false) as fails_recent
    from public.job_runs j where j.started_at > now() - interval '7 days' group by j.job)
  select coalesce(jsonb_agg(jsonb_build_object('job', e.job, 'last_ok_at', l.ok_at, 'last_run_at', l.any_at,
      'state', case when l.any_at is null then 'never_run'
                    when l.ok_at is null then 'failed'
                    when l.ok_at < now() - make_interval(hours => e.max_hours) then 'stale'
                    else 'ok' end) order by e.job), '[]'::jsonb)
    into jobs from exp e left join last_ok l on l.job = e.job;
  select count(*) into fails from public.intake_failures where state in ('failed', 'dead');
  begin bk := public.backup_status(); exception when others then bk := jsonb_build_object('state', 'missing'); end;
  begin fr := public._w1g_freshness(); exception when others then fr := jsonb_build_object('state', 'missing'); end;
  select coalesce(jsonb_object_agg(s.status, s.n), '{}'::jsonb) into outbox from (select status, count(*) n from public.notify_outbox group by status) s;
  res := jsonb_build_object(
    'automation_on', public.rule_on('automation_on'),
    'paused', public._x1_pause_active(),
    'pause_until', public.rule_txt('automation_pause_until'),
    'integrations', regs,
    'jobs', jobs,
    'intake_failed_or_dead', fails,
    'outbox', outbox,
    'backup', coalesce(bk, '{}'::jsonb),
    'books', coalesce(fr, '{}'::jsonb),
    'proposals_open', (select count(*) from public.action_proposals where status = 'proposed'),
    'generated_at', now());
  return res;
end $$;

-- ---------- row level security, rights ----------
do $$ declare t text; begin
  foreach t in array array['action_targets', 'action_proposals'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop trigger if exists %I on public.%I', t || '_no_delete', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_no_delete', t);
  end loop;
end $$;
drop policy if exists x1_targets_read on public.action_targets;
create policy x1_targets_read on public.action_targets for select to authenticated using (public.is_owner());
drop policy if exists x1_proposals_read on public.action_proposals;
create policy x1_proposals_read on public.action_proposals for select to authenticated using (public.is_owner() or proposed_by = auth.uid());
drop trigger if exists x1_targets_audit on public.action_targets;
create trigger x1_targets_audit after insert or update on public.action_targets for each row execute function public.log_change('rpc_name');
drop trigger if exists x1_proposals_audit on public.action_proposals;
create trigger x1_proposals_audit after insert or update on public.action_proposals for each row execute function public.log_change('id');

do $$ declare f text; begin
  foreach f in array array['public._x1_can_propose()', 'public._x1_target_guard()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.action_target_set(text,text,text,text,boolean)', 'public.action_propose(uuid,text,jsonb,text,int)', 'public.action_decide(bigint,text,text)',
    'public.action_proposal_mark_executed(bigint,boolean,jsonb)', 'public.action_proposals_list(text,int)', 'public.x1_health()'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
