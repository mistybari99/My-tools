-- Phase 327 (bos327, package CRM-G label 127, part 5 of 5) - STATUS FOR THE SCREENS, SETTINGS OVERVIEW, GO-LIVE CHECKLIST.
-- Paste AFTER phase326. Paste-twice safe. Read only: nothing is written, nothing is posted.
--   _crmg_status()     what the signed-in person may do right now (drives which buttons the two screens draw; the server still decides every call)
--   _crmg_settings()   every setting of this package with its value, its default and the plain-English label and hint (owner, or a holder of Manage enquiries)
--   _crmg_readiness()  the go-live checklist: what must be set up before the screens are useful

do $g$ begin
  if to_regprocedure('public._crmg_task_scan(boolean)') is null then raise exception 'phase327 needs phase326 first'; end if;
end $g$;

create or replace function public._crmg_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if not public.is_active() then return jsonb_build_object('signed_in', false); end if;
  return jsonb_build_object('signed_in', true, 'uid', uid, 'lead_on', public._crmg_lead_on(), 'task_on', public._crmg_task_on(), 'reminder_on', public.rule_on('crm_task_reminder_on'),
    'is_owner', public.is_owner(),
    'can_create_lead', public.is_owner() or public.has_grant('crm_lead_all') or exists (select 1 from public.locations x where x.is_active and public._crmg_can_create(x.id)),
    'can_manage_leads', public.is_owner() or public.has_grant('crm_lead_all') or exists (select 1 from public.locations x where x.is_active and public._crmg_lead_mgr(x.id)),
    'sees_all_outlets', public.is_owner() or public.has_grant('crm_lead_all'),
    'can_assign_tasks', public.is_owner() or public.has_grant('crm_task_assign'),
    'sees_all_tasks', public.is_owner() or public.has_grant('crm_task_all'),
    'can_edit_lists', public.is_owner() or (public.rule_txt('crm_lead_list_add_mode') = 'manager' and public.has_grant('crm_lead_manage')),
    'lost_by', coalesce(public.rule_txt('crm_lead_lost_by'), 'manager'), 'reopen_mode', coalesce(public.rule_txt('crm_lead_reopen_mode'), 'reason'),
    'win_needs_quote', public.rule_on('crm_lead_win_needs_quote'), 'quote_valid_days', public.rule_num('crm_lead_quote_valid_days'),
    'stale_days', public.rule_num('crm_lead_stale_days'), 'task_default_due_hours', public.rule_num('crm_task_default_due_hours'), 'snooze_max_days', public.rule_num('crm_task_snooze_max_days'),
    'online_orders_on', public.rule_on('online_orders_on'),
    'my_outlets', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'name', coalesce(x.name_en, x.name_bn)) order by x.sort, x.id) from public.locations x where x.is_active and x.kind in ('showroom', 'hub', 'online', 'other') and public.can_loc(x.id)), '[]'::jsonb),
    'staff_here', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'staff_id', p.staff_id, 'name', p.full_name) order by p.staff_id) from public.profiles p
        where p.status = 'active' and (public.is_owner() or public.has_grant('crm_lead_manage') or public.has_grant('crm_task_assign') or public.has_grant('crm_lead_all')) ), '[]'::jsonb));
end $$;

create or replace function public._crmg_settings() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not (public.is_owner() or public.has_grant('crm_lead_manage') or public.has_grant('crm_lead_all')) then raise exception 'not allowed'; end if;
  return jsonb_build_object('rules', coalesce((select jsonb_agg(jsonb_build_object('key', r.key, 'kind', r.kind, 'value', r.value, 'default', r.default_value, 'effective', coalesce(r.value, r.default_value),
      'unit', r.unit, 'choices', r.choices, 'min', r.min_value, 'max', r.max_value, 'label', coalesce(r.label_en, r.label_bn), 'hint', coalesce(r.hint_en, r.hint_bn)) order by r.sort, r.key)
      from public.rules r where r.module = 'crm' and r.key in ('crm_lead_on', 'crm_task_on', 'crm_lead_lost_by', 'crm_lead_reopen_mode', 'crm_lead_win_needs_quote', 'crm_lead_quote_valid_days', 'crm_quote_min_lead_days',
        'crm_lead_stale_days', 'crm_lead_list_add_mode', 'crm_task_default_due_hours', 'crm_task_snooze_max_days', 'crm_order_task_days', 'crm_task_reminder_on')), '[]'::jsonb),
    'grants', coalesce((select jsonb_agg(jsonb_build_object('code', g.grant_code, 'label', coalesce(g.label_en, g.label_bn)) order by g.sort) from public.grant_defs g where g.grant_code in ('crm_lead_manage', 'crm_lead_all', 'crm_task_assign', 'crm_task_all')), '[]'::jsonb));
end $$;

create or replace function public._crmg_readiness() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare items jsonb := '[]'::jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not (public.is_owner() or public.has_grant('crm_lead_manage') or public.has_grant('crm_lead_all')) then raise exception 'not allowed'; end if;
  items := items || jsonb_build_array(
    jsonb_build_object('key', 'lead_on', 'label', 'Enquiry tracking is switched on', 'ok', public._crmg_lead_on(), 'hint', 'Switch Track party, wholesale, corporate and gift enquiries on in Settings.'),
    jsonb_build_object('key', 'task_on', 'label', 'Tasks are switched on', 'ok', public._crmg_task_on(), 'hint', 'Switch Use follow-up tasks and the My tasks list on in Settings.'),
    jsonb_build_object('key', 'manager_named', 'label', 'Someone besides the owner can manage enquiries',
      'ok', exists (select 1 from public.rule_grants g where g.grant_code = 'crm_lead_manage' and g.allowed) or exists (select 1 from public.user_grants g where g.grant_code = 'crm_lead_manage' and (g.valid_until is null or g.valid_until > now())),
      'hint', 'Give the right Manage enquiries of my outlets to a role or a person. Until then only the owner can assign, close or convert.'),
    jsonb_build_object('key', 'lists', 'label', 'The lists of lost reasons, sources and occasions are filled',
      'ok', (select count(*) from public.crm_lead_lists where kind = 'lost_reason' and active) >= 2 and (select count(*) from public.crm_lead_lists where kind = 'source' and active) >= 2 and (select count(*) from public.crm_lead_lists where kind = 'occasion' and active) >= 2,
      'hint', 'Add the reasons, sources and occasions your shop really uses. The entry Other stays.'),
    jsonb_build_object('key', 'quote_validity', 'label', 'Quote validity is decided', 'ok', public.rule_num('crm_lead_quote_valid_days') is not null,
      'hint', 'Blank means staff type the valid-until date for every quote. Set a number of days to fill it in for them.'),
    jsonb_build_object('key', 'online_orders_on', 'label', 'Online orders are switched on (needed to turn an enquiry into an order)', 'ok', public.rule_on('online_orders_on'),
      'hint', 'Without it an enquiry can still be turned into a draft party form or linked to an existing order.'),
    jsonb_build_object('key', 'channel', 'label', 'A sales channel exists for orders', 'ok', exists (select 1 from public.sales_channels where active),
      'hint', 'Orders made from an enquiry need a sales channel.'),
    jsonb_build_object('key', 'forms', 'label', 'Forms 20-1 and 20-4 are switched on', 'ok', (select count(*) from public.forms where code in ('20-1', '20-4') and enabled) = 2,
      'hint', 'Needed to make a draft customer order form or a draft party invoice from an enquiry.'),
    jsonb_build_object('key', 'reminders_off_is_fine', 'label', 'In-app reminders', 'ok', true, 'state', case when public.rule_on('crm_task_reminder_on') then 'on' else 'off' end,
      'hint', 'Off by default. Staff see their list when they open My tasks. Switch on only when the notify job calls the reminder (see the integration note).'));
  return jsonb_build_object('items', items, 'all_ok', not exists (select 1 from jsonb_array_elements(items) x where not (x->>'ok')::boolean));
end $$;

select public._crmg_lock(array['_crmg_status', '_crmg_settings', '_crmg_readiness'], array['_crmg_status', '_crmg_settings', '_crmg_readiness']);
