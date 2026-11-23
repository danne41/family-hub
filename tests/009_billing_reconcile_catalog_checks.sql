-- Read-only catalog checks after 009 in an ISOLATED TEST DB.
DO $$
DECLARE v_rls boolean;
BEGIN
 SELECT relrowsecurity INTO v_rls FROM pg_class
 WHERE oid='public.billing_reconcile_jobs'::regclass;
 IF v_rls IS DISTINCT FROM true THEN RAISE EXCEPTION 'Reconciliation job RLS disabled'; END IF;
 IF has_table_privilege('anon','public.billing_reconcile_jobs','SELECT')
 OR has_table_privilege('authenticated','public.billing_reconcile_jobs','SELECT')
 THEN RAISE EXCEPTION 'Job table exposed to client roles'; END IF;
 IF has_function_privilege('anon','public.famunova_claim_reconcile_job(uuid)','EXECUTE')
 OR has_function_privilege('authenticated','public.famunova_claim_reconcile_job(uuid)','EXECUTE')
 OR has_function_privilege('anon','public.famunova_finish_reconcile_job(uuid,text,text)','EXECUTE')
 OR has_function_privilege('authenticated','public.famunova_finish_reconcile_job(uuid,text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'Job RPC exposed to client roles'; END IF;
 IF NOT has_function_privilege('service_role','public.famunova_claim_reconcile_job(uuid)','EXECUTE')
 OR NOT has_function_privilege('service_role','public.famunova_finish_reconcile_job(uuid,text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'Job RPC unavailable to service role'; END IF;
 IF (SELECT count(*) FROM public.billing_reconcile_jobs WHERE job_name='subscriptions')<>1
 THEN RAISE EXCEPTION 'Expected one reconciliation checkpoint'; END IF;
 RAISE NOTICE '009 catalog permissions and checkpoint checks passed';
END $$;
