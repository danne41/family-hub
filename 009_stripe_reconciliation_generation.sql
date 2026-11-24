-- TEST ONLY. Requires stage 1 and billing migrations 004-006.
-- Not yet wired into webhook. Do not deploy separately.
BEGIN;
CREATE TABLE public.famunova_stripe_observations (
 subscription_id text PRIMARY KEY,
 generation bigint NOT NULL CHECK(generation>0)
);
ALTER TABLE public.famunova_stripe_observations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.famunova_stripe_observations FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.famunova_begin_stripe_observation(p_subscription_id text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_generation bigint;
BEGIN
 IF p_subscription_id IS NULL OR p_subscription_id !~ '^sub_[A-Za-z0-9]+$' THEN RAISE EXCEPTION 'Invalid subscription identifier'; END IF;
 INSERT INTO public.famunova_stripe_observations AS o(subscription_id,generation)
 VALUES(p_subscription_id,1)
 ON CONFLICT(subscription_id) DO UPDATE SET generation=o.generation+1
 RETURNING generation INTO v_generation;
 RETURN v_generation;
END $$;
REVOKE ALL ON FUNCTION public.famunova_begin_stripe_observation(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.famunova_begin_stripe_observation(text) TO service_role;
-- The future apply RPC must lock this row and verify generation in the SAME
-- transaction as the subscription update. Superseded requests must retry;
-- they must not acknowledge an event that has not been reconciled.
COMMIT;
