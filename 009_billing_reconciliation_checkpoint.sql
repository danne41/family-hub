-- Famunova 009: durable reconciliation checkpoint (ISOLATED TEST DATABASE ONLY).
-- One worker lease per job. Failed batches preserve the cursor.
BEGIN;
CREATE TABLE IF NOT EXISTS public.billing_reconcile_jobs (
 job_name text PRIMARY KEY CHECK (job_name='subscriptions'),
 cursor text,
 lease_token uuid,
 lease_until timestamptz,
 last_error text,
 last_completed_at timestamptz,
 updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.billing_reconcile_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.billing_reconcile_jobs FROM PUBLIC,anon,authenticated;
INSERT INTO public.billing_reconcile_jobs(job_name) VALUES('subscriptions')
 ON CONFLICT(job_name) DO NOTHING;
CREATE OR REPLACE FUNCTION public.famunova_claim_reconcile_job(p_token uuid)
RETURNS TABLE(acquired boolean, next_cursor text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_job public.billing_reconcile_jobs%ROWTYPE;
BEGIN
 IF p_token IS NULL THEN RAISE EXCEPTION 'Missing lease token'; END IF;
 SELECT * INTO v_job FROM public.billing_reconcile_jobs
 WHERE job_name='subscriptions' FOR UPDATE;
 IF v_job.lease_until IS NOT NULL AND v_job.lease_until>now() THEN
  RETURN QUERY SELECT false,v_job.cursor; RETURN;
 END IF;
 UPDATE public.billing_reconcile_jobs SET lease_token=p_token,
 lease_until=now()+interval '3 minutes',updated_at=now()
 WHERE job_name='subscriptions';
 RETURN QUERY SELECT true,v_job.cursor;
END $$;
CREATE OR REPLACE FUNCTION public.famunova_finish_reconcile_job(
 p_token uuid,p_next_cursor text,p_error text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_job public.billing_reconcile_jobs%ROWTYPE;
BEGIN
 SELECT * INTO v_job FROM public.billing_reconcile_jobs
 WHERE job_name='subscriptions' FOR UPDATE;
 IF v_job.lease_token IS DISTINCT FROM p_token OR v_job.lease_until<=now()
 THEN RAISE EXCEPTION 'Reconciliation lease expired or mismatched'; END IF;
 IF p_next_cursor IS NOT NULL AND p_next_cursor !~ '^sub_[A-Za-z0-9]+$'
 THEN RAISE EXCEPTION 'Invalid checkpoint cursor'; END IF;
 UPDATE public.billing_reconcile_jobs SET
 cursor=CASE WHEN p_error IS NULL THEN p_next_cursor ELSE v_job.cursor END,
 last_error=left(p_error,500),last_completed_at=CASE WHEN p_error IS NULL THEN now() ELSE last_completed_at END,
 lease_token=NULL,lease_until=NULL,updated_at=now()
 WHERE job_name='subscriptions';
END $$;
REVOKE ALL ON FUNCTION public.famunova_claim_reconcile_job(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.famunova_finish_reconcile_job(uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.famunova_claim_reconcile_job(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.famunova_finish_reconcile_job(uuid,text,text) TO service_role;
COMMIT;
