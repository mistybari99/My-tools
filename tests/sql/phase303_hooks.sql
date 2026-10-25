-- CRM-B hooks for the shared notify functions (needs phase303; paste-twice safe through the marker bosCRMB). The integrator adds these two statements to the re-patch file
-- (docs/integration/CRM-B.md section 2). The texts come from public._crmb_hook_pairs(), the one place that holds them; phase303_test.sql T9 proves them on scratch copies.
--   notify_enqueue   after its own opt-in check: refuse a do-not-contact customer and a customer whose linked duplicate said no.
--   notify_optin_set write one evidence line (crm_consent_events) for a change made the old way. Never blocks the change.
select public._crmb_patch('public.notify_enqueue(uuid,uuid,text,text,jsonb,text,text,text)'::regprocedure, public._crmb_hook_pairs('notify_enqueue'));
select public._crmb_patch('public.notify_optin_set(uuid,text,boolean,text,text)'::regprocedure, public._crmb_hook_pairs('notify_optin_set'));
