-- TEST ONLY. Requires 011. Unknown session creation outcomes remain blocked.
BEGIN;
ALTER TABLE public.famunova_checkout_reservations ADD COLUMN stripe_session_id text UNIQUE;
CREATE FUNCTION public.famunova_bind_checkout_session(p_group uuid,p_key uuid,p_session text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF p_session IS NULL OR p_session !~ '^cs_test_[A-Za-z0-9]+$' THEN RAISE EXCEPTION 'Invalid test session'; END IF;
 PERFORM 1 FROM public.family_groups WHERE id=p_group FOR UPDATE;
 UPDATE public.famunova_checkout_reservations SET stripe_session_id=p_session
 WHERE group_id=p_group AND reservation_key=p_key AND (stripe_session_id IS NULL OR stripe_session_id=p_session);
 RETURN FOUND;
END $$;
-- Trusted server must retrieve the exact Stripe session and verify expired,
-- unpaid, no subscription, matching customer and reservation metadata.
CREATE FUNCTION public.famunova_release_expired_checkout(p_group uuid,p_key uuid,p_session text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM 1 FROM public.family_groups WHERE id=p_group FOR UPDATE;
 IF EXISTS(SELECT 1 FROM public.billing_subscriptions WHERE group_id=p_group AND status IN ('active','trialing','past_due','unpaid','incomplete','paused')) THEN RETURN false; END IF;
 DELETE FROM public.famunova_checkout_reservations WHERE group_id=p_group AND reservation_key=p_key AND stripe_session_id=p_session;
 RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.famunova_bind_checkout_session(uuid,uuid,text),public.famunova_release_expired_checkout(uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.famunova_bind_checkout_session(uuid,uuid,text),public.famunova_release_expired_checkout(uuid,uuid,text) TO service_role;
COMMIT;
